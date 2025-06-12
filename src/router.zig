//! High-performance HTTP router with parameter extraction and middleware support

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

// Import Context from context.zig
const Context = @import("context.zig").Context;
const HttpMethod = @import("request.zig").HttpMethod;
const url = @import("url.zig");

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

/// Parameter and wildcard route matching with URL decoding support
/// This function uses a temporary allocator for URL decoding during matching
pub fn matchRouteWithParams(allocator: Allocator, pattern: []const u8, path: []const u8) !bool {
    // Split and decode path components
    var path_components = url.splitAndDecodePath(allocator, path) catch {
        // If URL decoding fails, fall back to raw matching for safety
        return matchRouteWithParamsRaw(pattern, path);
    };
    defer url.freePathComponents(allocator, &path_components);

    // Split pattern components (patterns are not URL encoded)
    var pattern_parts = std.mem.splitScalar(u8, pattern, '/');
    var pattern_components = std.ArrayList([]const u8).init(allocator);
    defer pattern_components.deinit();

    while (pattern_parts.next()) |part| {
        if (part.len == 0) continue; // Skip empty parts
        try pattern_components.append(part);
    }

    // Compare components
    if (pattern_components.items.len != path_components.items.len) {
        // Check for wildcard at the end
        if (pattern_components.items.len > 0) {
            const last_pattern = pattern_components.items[pattern_components.items.len - 1];
            if (std.mem.eql(u8, last_pattern, "*")) {
                return pattern_components.items.len <= path_components.items.len + 1;
            }
        }
        return false;
    }

    for (pattern_components.items, 0..) |pattern_part, i| {
        const path_part = path_components.items[i];

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

        // Exact matching (case-sensitive)
        if (!std.mem.eql(u8, pattern_part, path_part)) {
            return false;
        }
    }

    return true;
}

/// Fallback raw matching without URL decoding (for compatibility)
fn matchRouteWithParamsRaw(pattern: []const u8, path: []const u8) bool {
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

    /// Route matching algorithm with URL decoding support
    fn matchRoute(self: *Router, pattern: []const u8, path: []const u8) bool {
        // Fast path for exact matches
        if (std.mem.eql(u8, pattern, path)) {
            return true;
        }

        // Skip parameter matching if no special characters
        if (std.mem.indexOf(u8, pattern, ":") == null and std.mem.indexOf(u8, pattern, "*") == null) {
            return false;
        }

        return matchRouteWithParams(self.allocator, pattern, path) catch false;
    }

    /// Extract parameters from URL path with proper URL decoding
    pub fn extractParams(self: *Router, pattern: []const u8, path: []const u8, ctx: *Context) !void {
        // Split and decode path components
        var path_components = url.splitAndDecodePath(self.allocator, path) catch {
            // If URL decoding fails, fall back to raw extraction
            return self.extractParamsRaw(pattern, path, ctx);
        };
        defer url.freePathComponents(self.allocator, &path_components);

        // Split pattern components (patterns are not URL encoded)
        var pattern_parts = std.mem.splitScalar(u8, pattern, '/');
        var pattern_components = std.ArrayList([]const u8).init(self.allocator);
        defer pattern_components.deinit();

        while (pattern_parts.next()) |part| {
            if (part.len == 0) continue; // Skip empty parts
            try pattern_components.append(part);
        }

        // Extract parameters from matching components
        const min_len = @min(pattern_components.items.len, path_components.items.len);
        for (pattern_components.items[0..min_len], 0..) |pattern_part, i| {
            // Extract parameter
            if (pattern_part.len > 0 and pattern_part[0] == ':') {
                const param_name = pattern_part[1..];
                const decoded_value = path_components.items[i];
                try ctx.setParam(param_name, decoded_value);
            }
        }
    }

    /// Fallback parameter extraction without URL decoding
    fn extractParamsRaw(self: *Router, pattern: []const u8, path: []const u8, ctx: *Context) !void {
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test exact match
    try testing.expect(try matchRouteWithParams(allocator, "/users", "/users"));

    // Test parameter match
    try testing.expect(try matchRouteWithParams(allocator, "/users/:id", "/users/123"));

    // Test wildcard match
    try testing.expect(try matchRouteWithParams(allocator, "/static/*", "/static/css/style.css"));

    // Test no match
    try testing.expect(!try matchRouteWithParams(allocator, "/users", "/posts"));
}

test "route matching with URL encoding" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test URL-encoded slash in path component
    try testing.expect(try matchRouteWithParams(allocator, "/files/:filename", "/files/foo%2Fbar.txt"));

    // Test URL-encoded space in path component
    try testing.expect(try matchRouteWithParams(allocator, "/files/:filename", "/files/my%20file.txt"));

    // Test multiple encoded components
    try testing.expect(try matchRouteWithParams(allocator, "/users/:id/files/:filename", "/users/user%20123/files/doc%2Epdf"));

    // Test that encoded slash doesn't break path structure
    try testing.expect(!try matchRouteWithParams(allocator, "/files/:filename/download", "/files/foo%2Fbar.txt"));
}

test "parameter extraction with URL encoding" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a mock request and response for context
    const HttpRequest = @import("request.zig").HttpRequest;
    const HttpResponse = @import("response.zig").HttpResponse;
    const HttpConfig = @import("config.zig").HttpConfig;

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    const router = try Router.init(allocator);
    defer {
        router.deinit();
        allocator.destroy(router);
    }

    // Test parameter extraction with URL-encoded slash
    try router.extractParams("/files/:filename", "/files/foo%2Fbar.txt", &ctx);
    const filename = ctx.getParam("filename");
    try testing.expect(filename != null);
    try testing.expectEqualStrings("foo/bar.txt", filename.?);

    // Clear params for next test (properly free memory)
    {
        var it = ctx.params.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        ctx.params.clearAndFree();
    }

    // Test parameter extraction with URL-encoded space
    try router.extractParams("/users/:name", "/users/John%20Doe", &ctx);
    const name = ctx.getParam("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("John Doe", name.?);
}
