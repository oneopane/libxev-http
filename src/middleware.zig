//! Middleware system for libxev-http
//!
//! This module provides a flexible middleware system that allows:
//! - Request/response processing pipeline
//! - Global and route-specific middleware
//! - Built-in common middleware (logging, CORS, auth, etc.)
//! - Custom middleware development

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Context = @import("context.zig").Context;

/// Next function type - calls the next middleware in the chain
pub const NextFn = *const fn (*Context) anyerror!void;

/// Middleware function type
/// Takes context and next function, can choose to call next or not
pub const MiddlewareFn = *const fn (*Context, NextFn) anyerror!void;

/// Middleware wrapper structure
pub const Middleware = struct {
    name: []const u8,
    handler: MiddlewareFn,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, handler: MiddlewareFn) !*Middleware {
        const middleware = try allocator.create(Middleware);
        middleware.* = Middleware{
            .name = try allocator.dupe(u8, name),
            .handler = handler,
            .allocator = allocator,
        };
        return middleware;
    }

    pub fn deinit(self: *Middleware) void {
        self.allocator.free(self.name);
    }
};

/// Middleware chain executor
pub const MiddlewareChain = struct {
    middlewares: ArrayList(*Middleware),
    allocator: Allocator,

    pub fn init(allocator: Allocator) MiddlewareChain {
        return MiddlewareChain{
            .middlewares = ArrayList(*Middleware).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MiddlewareChain) void {
        for (self.middlewares.items) |middleware| {
            middleware.deinit();
            self.allocator.destroy(middleware);
        }
        self.middlewares.deinit();
    }

    /// Add middleware to the chain
    pub fn use(self: *MiddlewareChain, name: []const u8, handler: MiddlewareFn) !void {
        const middleware = try Middleware.init(self.allocator, name, handler);
        try self.middlewares.append(middleware);
    }

    /// Execute middleware chain
    pub fn execute(self: *MiddlewareChain, ctx: *Context, final_handler: NextFn) !void {
        return self.executeFromIndex(ctx, final_handler, 0);
    }

    /// Execute middleware chain starting from a specific index
    fn executeFromIndex(self: *MiddlewareChain, ctx: *Context, final_handler: NextFn, start_index: usize) !void {
        if (start_index >= self.middlewares.items.len) {
            return final_handler(ctx);
        }

        const middleware = self.middlewares.items[start_index];

        // Create next function that continues the chain
        const NextHandler = struct {
            chain: *MiddlewareChain,
            final_handler: NextFn,
            next_index: usize,

            fn call(self_handler: @This(), context: *Context) anyerror!void {
                return self_handler.chain.executeFromIndex(context, self_handler.final_handler, self_handler.next_index);
            }
        };

        const next_handler = NextHandler{
            .chain = self,
            .final_handler = final_handler,
            .next_index = start_index + 1,
        };

        const next_fn = struct {
            fn call(context: *Context) anyerror!void {
                // Get handler from context state
                const handler_ptr = context.getState("__next_handler") orelse return error.MiddlewareError;
                const handler = @as(*NextHandler, @ptrFromInt(std.fmt.parseInt(usize, handler_ptr, 10) catch return error.MiddlewareError));
                return handler.call(context);
            }
        }.call;

        // Store handler pointer in context
        const handler_addr = @intFromPtr(&next_handler);
        const addr_str = try std.fmt.allocPrint(ctx.allocator, "{}", .{handler_addr});
        defer ctx.allocator.free(addr_str);
        try ctx.setState("__next_handler", addr_str);

        return middleware.handler(ctx, next_fn);
    }
};

// Built-in middleware implementations

/// Logging middleware - logs request details
pub fn loggingMiddleware(ctx: *Context, next: NextFn) !void {
    const start_time = std.time.milliTimestamp();

    std.log.info("🌐 {s} {s} - Started", .{ ctx.getMethod(), ctx.getPath() });

    // Call next middleware/handler
    next(ctx) catch |err| {
        const duration = std.time.milliTimestamp() - start_time;
        std.log.err("❌ {s} {s} - Error: {} ({}ms)", .{ ctx.getMethod(), ctx.getPath(), err, duration });
        return err;
    };

    const duration = std.time.milliTimestamp() - start_time;
    std.log.info("✅ {s} {s} - Completed ({}ms)", .{ ctx.getMethod(), ctx.getPath(), duration });
}

/// CORS middleware - adds CORS headers
pub fn corsMiddleware(ctx: *Context, next: NextFn) !void {
    // Add CORS headers
    try ctx.setHeader("Access-Control-Allow-Origin", "*");
    try ctx.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    try ctx.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    try ctx.setHeader("Access-Control-Max-Age", "86400");

    // Handle preflight requests
    if (std.mem.eql(u8, ctx.getMethod(), "OPTIONS")) {
        ctx.status(.no_content);
        return;
    }

    return next(ctx);
}

/// Security headers middleware
pub fn securityHeadersMiddleware(ctx: *Context, next: NextFn) !void {
    try ctx.setHeader("X-Content-Type-Options", "nosniff");
    try ctx.setHeader("X-Frame-Options", "DENY");
    try ctx.setHeader("X-XSS-Protection", "1; mode=block");
    try ctx.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains");

    return next(ctx);
}

/// Request ID middleware - adds unique request ID
pub fn requestIdMiddleware(ctx: *Context, next: NextFn) !void {
    // Generate simple request ID (timestamp + random)
    const timestamp = std.time.timestamp();
    var prng = std.Random.DefaultPrng.init(@as(u64, @intCast(timestamp)));
    const random = prng.random().int(u32);

    const request_id = try std.fmt.allocPrint(ctx.allocator, "{}-{}", .{ timestamp, random });
    defer ctx.allocator.free(request_id);

    try ctx.setState("request_id", request_id);
    try ctx.setHeader("X-Request-ID", request_id);

    return next(ctx);
}

/// Rate limiting middleware
pub fn rateLimitMiddleware(ctx: *Context, next: NextFn) !void {
    // Simple rate limiting based on IP (in production, use Redis or similar)
    // For demo purposes, we'll just add headers
    try ctx.setHeader("X-RateLimit-Limit", "100");
    try ctx.setHeader("X-RateLimit-Remaining", "99");
    try ctx.setHeader("X-RateLimit-Reset", "3600");

    return next(ctx);
}

/// Basic authentication middleware
pub fn basicAuthMiddleware(ctx: *Context, next: NextFn) !void {
    const auth_header = ctx.getHeader("Authorization");

    if (auth_header == null) {
        ctx.status(.unauthorized);
        try ctx.setHeader("WWW-Authenticate", "Basic realm=\"Protected Area\"");
        try ctx.json("{\"error\":\"Authentication required\"}");
        return;
    }

    // In production, validate the credentials properly
    if (!std.mem.startsWith(u8, auth_header.?, "Basic ")) {
        ctx.status(.unauthorized);
        try ctx.json("{\"error\":\"Invalid authentication method\"}");
        return;
    }

    return next(ctx);
}

/// JSON body parser middleware
pub fn jsonBodyParserMiddleware(ctx: *Context, next: NextFn) !void {
    const content_type = ctx.getHeader("Content-Type");

    if (content_type != null and std.mem.indexOf(u8, content_type.?, "application/json") != null) {
        const body = ctx.getBody();
        if (body != null) {
            // Validate JSON format
            const parsed = std.json.parseFromSlice(std.json.Value, ctx.allocator, body.?, .{}) catch {
                ctx.status(.bad_request);
                try ctx.json("{\"error\":\"Invalid JSON format\"}");
                return;
            };
            defer parsed.deinit();

            // Store parsed indicator
            try ctx.setState("json_parsed", "true");
        }
    }

    return next(ctx);
}

/// Error handling middleware
pub fn errorHandlerMiddleware(ctx: *Context, next: NextFn) !void {
    next(ctx) catch |err| {
        std.log.err("Middleware error: {}", .{err});

        // Don't override if response already started
        if (ctx.response.status == .ok) {
            ctx.status(.internal_server_error);
            ctx.json("{\"error\":\"Internal server error\"}") catch {};
        }

        return err;
    };
}

/// Compression middleware (placeholder)
pub fn compressionMiddleware(ctx: *Context, next: NextFn) !void {
    const accept_encoding = ctx.getHeader("Accept-Encoding");

    if (accept_encoding != null and std.mem.indexOf(u8, accept_encoding.?, "gzip") != null) {
        try ctx.setHeader("Content-Encoding", "gzip");
        // In production, implement actual compression
    }

    return next(ctx);
}

// Tests
const testing = std.testing;

test "MiddlewareChain basic functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var chain = MiddlewareChain.init(allocator);
    defer chain.deinit();

    // Test adding middleware
    try chain.use("test", loggingMiddleware);
    try testing.expect(chain.middlewares.items.len == 1);
    try testing.expectEqualStrings("test", chain.middlewares.items[0].name);
}

test "Built-in middleware compilation" {
    // Just test that all middleware functions compile correctly
    const middlewares = [_]MiddlewareFn{
        loggingMiddleware,
        corsMiddleware,
        securityHeadersMiddleware,
        requestIdMiddleware,
        rateLimitMiddleware,
        basicAuthMiddleware,
        jsonBodyParserMiddleware,
        errorHandlerMiddleware,
        compressionMiddleware,
    };

    try testing.expect(middlewares.len == 9);
}
