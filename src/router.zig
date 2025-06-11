//! High-performance HTTP router with parameter extraction and middleware support

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

// Import Context from context.zig
const Context = @import("context.zig").Context;
const HttpMethod = @import("request.zig").HttpMethod;

/// Route handler function type
pub const HandlerFn = *const fn (*Context) anyerror!void;

/// Individual route definition
pub const Route = struct {
    method: HttpMethod,
    pattern: []const u8,
    handler: HandlerFn,
    allocator: Allocator,

    pub fn init(allocator: Allocator, method: HttpMethod, pattern: []const u8, handler: HandlerFn) !*Route {
        const route = try allocator.create(Route);
        route.* = Route{
            .method = method,
            .pattern = try allocator.dupe(u8, pattern),
            .handler = handler,
            .allocator = allocator,
        };
        return route;
    }

    pub fn deinit(self: *Route) void {
        self.allocator.free(self.pattern);
    }
};

/// Parameter and wildcard route matching
pub fn matchRouteWithParams(pattern: []const u8, path: []const u8) bool {
    var pattern_parts = std.mem.splitScalar(u8, pattern, '/');
    var path_parts = std.mem.splitScalar(u8, path, '/');

    while (true) {
        const pattern_part = pattern_parts.next() orelse {
            return path_parts.next() == null;
        };

        const path_part = path_parts.next() orelse {
            return false;
        };

        // Parameter matching (:param)
        if (pattern_part.len > 0 and pattern_part[0] == ':') {
            if (path_part.len == 0) {
                return false;
            }
            continue;
        }

        // Wildcard matching (*)
        if (std.mem.eql(u8, pattern_part, "*")) {
            return true;
        }

        // Exact matching
        if (!std.mem.eql(u8, pattern_part, path_part)) {
            return false;
        }
    }
}

/// High-performance HTTP router
pub const Router = struct {
    routes: ArrayList(*Route),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*Router {
        const router = try allocator.create(Router);
        router.* = Router{
            .routes = ArrayList(*Route).init(allocator),
            .allocator = allocator,
        };
        return router;
    }

    pub fn deinit(self: *Router) void {
        for (self.routes.items) |route| {
            route.deinit();
            self.allocator.destroy(route);
        }
        self.routes.deinit();
    }

    /// HTTP method shortcuts
    pub fn get(self: *Router, path: []const u8, handler: HandlerFn) !*Route {
        return try self.addRoute(.GET, path, handler);
    }

    pub fn post(self: *Router, path: []const u8, handler: HandlerFn) !*Route {
        return try self.addRoute(.POST, path, handler);
    }

    pub fn put(self: *Router, path: []const u8, handler: HandlerFn) !*Route {
        return try self.addRoute(.PUT, path, handler);
    }

    pub fn delete(self: *Router, path: []const u8, handler: HandlerFn) !*Route {
        return try self.addRoute(.DELETE, path, handler);
    }

    /// Add a new route
    pub fn addRoute(self: *Router, method: HttpMethod, path: []const u8, handler: HandlerFn) !*Route {
        const route = try Route.init(self.allocator, method, path, handler);
        try self.routes.append(route);
        return route;
    }

    /// Handle incoming HTTP request
    pub fn handleRequest(self: *Router, ctx: *Context) !void {
        const method_enum = HttpMethod.fromString(ctx.request.method) orelse {
            return error.InvalidMethod;
        };
        const route = self.findRoute(method_enum, ctx.request.path) orelse {
            return error.NotFound;
        };

        // Extract route parameters
        try self.extractParams(route.pattern, ctx.request.path, ctx);

        try route.handler(ctx);
    }

    /// Find matching route
    pub fn findRoute(self: *Router, method: HttpMethod, path: []const u8) ?*Route {
        for (self.routes.items) |route| {
            if (route.method == method and self.matchRoute(route.pattern, path)) {
                return route;
            }
        }
        return null;
    }

    /// Route matching algorithm
    fn matchRoute(_: *Router, pattern: []const u8, path: []const u8) bool {
        // Fast path for exact matches
        if (std.mem.eql(u8, pattern, path)) {
            return true;
        }

        // Skip parameter matching if no special characters
        if (std.mem.indexOf(u8, pattern, ":") == null and std.mem.indexOf(u8, pattern, "*") == null) {
            return false;
        }

        return matchRouteWithParams(pattern, path);
    }

    /// Extract parameters from URL path
    pub fn extractParams(self: *Router, pattern: []const u8, path: []const u8, ctx: *Context) !void {
        _ = self;

        var pattern_parts = std.mem.splitScalar(u8, pattern, '/');
        var path_parts = std.mem.splitScalar(u8, path, '/');

        while (true) {
            const pattern_part = pattern_parts.next() orelse break;
            const path_part = path_parts.next() orelse break;

            // Extract parameter
            if (pattern_part.len > 0 and pattern_part[0] == ':') {
                const param_name = pattern_part[1..];
                try ctx.setParam(param_name, path_part);
            }
        }
    }
};

// Tests
test "router creation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const router = try Router.init(allocator);
    defer {
        router.deinit();
        allocator.destroy(router);
    }

    try testing.expect(router.routes.items.len == 0);
}

test "route matching" {
    const testing = std.testing;

    // Test exact match
    try testing.expect(matchRouteWithParams("/users", "/users"));

    // Test parameter match
    try testing.expect(matchRouteWithParams("/users/:id", "/users/123"));

    // Test wildcard match
    try testing.expect(matchRouteWithParams("/static/*", "/static/css/style.css"));

    // Test no match
    try testing.expect(!matchRouteWithParams("/users", "/posts"));
}
