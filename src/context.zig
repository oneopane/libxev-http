//! HTTP request context management
//!
//! This module provides the Context structure that encapsulates:
//! - HTTP request and response objects
//! - Route parameter extraction and storage
//! - Request state management
//! - Convenient response helpers (JSON, HTML, text)
//! - Status code management

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const HttpRequest = @import("request.zig").HttpRequest;
const HttpResponse = @import("response.zig").HttpResponse;
const StatusCode = @import("response.zig").StatusCode;
const HttpConfig = @import("config.zig").HttpConfig;

/// HTTP request processing context
/// Encapsulates request and response objects, provides convenient operation methods
/// Manages path parameters, state data and response building
pub const Context = struct {
    request: *HttpRequest,
    response: *HttpResponse,
    allocator: Allocator,
    params: StringHashMap([]const u8),
    state: StringHashMap([]const u8),

    const Self = @This();

    /// Initialize context
    pub fn init(allocator: Allocator, request: *HttpRequest, response: *HttpResponse) Self {
        return Self{
            .request = request,
            .response = response,
            .allocator = allocator,
            .params = StringHashMap([]const u8).init(allocator),
            .state = StringHashMap([]const u8).init(allocator),
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        var it = self.params.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.params.deinit();

        var state_it = self.state.iterator();
        while (state_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.state.deinit();
    }

    /// Set path parameter
    pub fn setParam(self: *Self, key: []const u8, value: []const u8) !void {
        // Check if key already exists, free old memory if so
        if (self.params.fetchRemove(key)) |old_entry| {
            self.allocator.free(old_entry.key);
            self.allocator.free(old_entry.value);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.params.put(owned_key, owned_value);
    }

    /// Get path parameter
    pub fn getParam(self: *Self, key: []const u8) ?[]const u8 {
        return self.params.get(key);
    }

    /// Set state
    pub fn setState(self: *Self, key: []const u8, value: []const u8) !void {
        // Check if key already exists, free old memory if so
        if (self.state.fetchRemove(key)) |old_entry| {
            self.allocator.free(old_entry.key);
            self.allocator.free(old_entry.value);
        }

        const owned_key = try self.allocator.dupe(u8, key);
        const owned_value = try self.allocator.dupe(u8, value);
        try self.state.put(owned_key, owned_value);
    }

    /// Get state
    pub fn getState(self: *Self, key: []const u8) ?[]const u8 {
        return self.state.get(key);
    }

    /// Set response status code
    pub fn status(self: *Self, code: StatusCode) void {
        self.response.status = code;
    }

    /// Send JSON response
    pub fn json(self: *Self, data: []const u8) !void {
        try self.response.setHeader("Content-Type", "application/json");
        try self.response.setBody(data);
    }

    /// Send text response
    pub fn text(self: *Self, content: []const u8) !void {
        try self.response.setHeader("Content-Type", "text/plain");
        try self.response.setBody(content);
    }

    /// Send HTML response
    pub fn html(self: *Self, content: []const u8) !void {
        try self.response.setHeader("Content-Type", "text/html");
        try self.response.setBody(content);
    }

    /// Redirect
    pub fn redirect(self: *Self, url: []const u8, status_code: StatusCode) !void {
        self.response.status = status_code;
        try self.response.setHeader("Location", url);
    }

    /// Get request header
    pub fn getHeader(self: *Self, name: []const u8) ?[]const u8 {
        return self.request.getHeader(name);
    }

    /// Set response header
    pub fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
        try self.response.setHeader(name, value);
    }

    /// Get request body
    pub fn getBody(self: *Self) ?[]const u8 {
        return self.request.body;
    }

    /// Get request method
    pub fn getMethod(self: *Self) []const u8 {
        return self.request.method;
    }

    /// Get request path
    pub fn getPath(self: *Self) []const u8 {
        return self.request.path;
    }

    /// Get query string
    pub fn getQuery(self: *Self) ?[]const u8 {
        return self.request.query;
    }
};

// Tests
test "Context initialization and cleanup" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create mock request and response
    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    // Test initial state
    try testing.expect(ctx.params.count() == 0);
    try testing.expect(ctx.state.count() == 0);
}

test "Context parameter operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    // Set parameters
    try ctx.setParam("id", "123");
    try ctx.setParam("name", "test");

    // Get parameters
    const id = ctx.getParam("id");
    try testing.expect(id != null);
    try testing.expectEqualStrings("123", id.?);

    const name = ctx.getParam("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("test", name.?);

    // Get non-existent parameter
    const nonexistent = ctx.getParam("nonexistent");
    try testing.expect(nonexistent == null);

    // Override parameter
    try ctx.setParam("id", "456");
    const updated_id = ctx.getParam("id");
    try testing.expectEqualStrings("456", updated_id.?);
}

test "Context state operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    // Set state
    try ctx.setState("user_id", "user123");
    try ctx.setState("session", "session456");

    // Get state
    const user_id = ctx.getState("user_id");
    try testing.expect(user_id != null);
    try testing.expectEqualStrings("user123", user_id.?);

    const session = ctx.getState("session");
    try testing.expect(session != null);
    try testing.expectEqualStrings("session456", session.?);

    // Get non-existent state
    const nonexistent = ctx.getState("nonexistent");
    try testing.expect(nonexistent == null);
}

test "Context response status code setting" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    // Test status code setting
    ctx.status(.not_found);
    try testing.expect(ctx.response.status == .not_found);

    ctx.status(.internal_server_error);
    try testing.expect(ctx.response.status == .internal_server_error);
}

test "Context JSON response" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    // Test JSON response
    try ctx.json("{\"message\":\"success\"}");

    // Verify response headers and body
    const content_type = ctx.response.headers.get("Content-Type");
    try testing.expect(content_type != null);
    try testing.expectEqualStrings("application/json", content_type.?);

    try testing.expect(ctx.response.body != null);
    try testing.expectEqualStrings("{\"message\":\"success\"}", ctx.response.body.?);
}

test "Context text response" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost\r\n\r\n";
    const config = HttpConfig{};
    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    var ctx = Context.init(allocator, &request, &response);
    defer ctx.deinit();

    // Test text response
    try ctx.text("Hello, World!");

    // Verify response headers and body
    const content_type = ctx.response.headers.get("Content-Type");
    try testing.expect(content_type != null);
    try testing.expectEqualStrings("text/plain", content_type.?);

    try testing.expect(ctx.response.body != null);
    try testing.expectEqualStrings("Hello, World!", ctx.response.body.?);
}
