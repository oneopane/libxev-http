//! HTTP response building and management
//!
//! This module provides comprehensive HTTP response building with:
//! - Status code management
//! - Header manipulation with memory safety
//! - Cookie support with security attributes
//! - Content type helpers (JSON, HTML, text)
//! - Complete response serialization

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;
const utils = @import("utils.zig");

/// HTTP status codes
pub const StatusCode = enum(u16) {
    // 1xx Informational
    continue_status = 100,
    switching_protocols = 101,

    // 2xx Success
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,

    // 3xx Redirection
    moved_permanently = 301,
    found = 302,
    not_modified = 304,

    // 4xx Client Error
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    conflict = 409,
    payload_too_large = 413,

    // 5xx Server Error
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,

    /// Get status code phrase
    pub fn toString(self: StatusCode) []const u8 {
        return switch (self) {
            .continue_status => "Continue",
            .ok => "OK",
            inline else => |tag| comptime utils.snakeCaseToTitleCase(@tagName(tag)),
        };
    }
};

/// HTTP response builder
/// Handles building complete HTTP responses including status line, headers, cookies and body
pub const HttpResponse = struct {
    allocator: Allocator,
    status: StatusCode,
    headers: StringHashMap([]const u8),
    body: ?[]const u8,
    cookies: ArrayList(Cookie),

    const Self = @This();

    /// HTTP Cookie representation
    /// Contains all cookie attributes and security options
    pub const Cookie = struct {
        name: []const u8,
        value: []const u8,
        path: ?[]const u8 = null,
        domain: ?[]const u8 = null,
        expires: ?[]const u8 = null,
        max_age: ?i64 = null,
        secure: bool = false,
        http_only: bool = false,
        same_site: ?SameSite = null,

        /// Cookie SameSite attribute
        /// Controls cookie behavior in cross-site requests
        pub const SameSite = enum {
            Strict,
            Lax,
            None,

            pub fn toString(self: SameSite) []const u8 {
                return switch (self) {
                    .Strict => "Strict",
                    .Lax => "Lax",
                    .None => "None",
                };
            }
        };

        /// Cookie options structure
        pub const Options = struct {
            path: ?[]const u8 = null,
            domain: ?[]const u8 = null,
            expires: ?[]const u8 = null,
            max_age: ?i64 = null,
            secure: bool = false,
            http_only: bool = false,
            same_site: ?SameSite = null,
        };
    };

    /// Initialize HTTP response
    pub fn init(allocator: Allocator) HttpResponse {
        return HttpResponse{
            .allocator = allocator,
            .status = .ok,
            .headers = StringHashMap([]const u8).init(allocator),
            .body = null,
            .cookies = ArrayList(Cookie).init(allocator),
        };
    }

    /// Set status code
    pub fn setStatus(self: *Self, status: StatusCode) void {
        self.status = status;
    }

    /// Set response header
    pub fn setHeader(self: *Self, name: []const u8, value: []const u8) !void {
        // If header already exists, free old value
        if (self.headers.fetchRemove(name)) |old_entry| {
            self.allocator.free(old_entry.key);
            self.allocator.free(old_entry.value);
        }

        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);

        const value_dup = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_dup);

        try self.headers.put(name_dup, value_dup);
    }

    /// Set response body
    pub fn setBody(self: *Self, body: []const u8) !void {
        if (self.body) |old_body| {
            self.allocator.free(old_body);
        }

        self.body = try self.allocator.dupe(u8, body);
    }

    /// Set JSON response body
    pub fn setJsonBody(self: *Self, json: []const u8) !void {
        try self.setHeader("Content-Type", "application/json; charset=utf-8");
        try self.setBody(json);
    }

    /// Set HTML response body
    pub fn setHtmlBody(self: *Self, html: []const u8) !void {
        try self.setHeader("Content-Type", "text/html; charset=utf-8");
        try self.setBody(html);
    }

    /// Set text response body
    pub fn setTextBody(self: *Self, text: []const u8) !void {
        try self.setHeader("Content-Type", "text/plain; charset=utf-8");
        try self.setBody(text);
    }

    /// Set cookie
    pub fn setCookie(self: *Self, cookie: Cookie) !void {
        try self.cookies.append(cookie);
    }

    /// Build complete HTTP response
    pub fn build(self: *Self) ![]u8 {
        var response = ArrayList(u8).init(self.allocator);
        errdefer response.deinit();

        // Status line
        try response.writer().print("HTTP/1.1 {d} {s}\r\n", .{ @intFromEnum(self.status), self.status.toString() });

        // Default headers
        if (!self.headers.contains("Server")) {
            try response.writer().print("Server: libxev-http/1.0\r\n", .{});
        }

        if (!self.headers.contains("Date")) {
            const timestamp = std.time.timestamp();
            try response.writer().print("Date: {d}\r\n", .{timestamp});
        }

        if (!self.headers.contains("Connection")) {
            try response.writer().print("Connection: close\r\n", .{});
        }

        // Custom headers
        var iterator = self.headers.iterator();
        while (iterator.next()) |entry| {
            try response.writer().print("{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
        }

        // Cookie headers
        for (self.cookies.items) |cookie| {
            var cookie_str = ArrayList(u8).init(self.allocator);
            defer cookie_str.deinit();

            try cookie_str.writer().print("{s}={s}", .{ cookie.name, cookie.value });

            if (cookie.path) |path| {
                try cookie_str.writer().print("; Path={s}", .{path});
            }

            if (cookie.domain) |domain| {
                try cookie_str.writer().print("; Domain={s}", .{domain});
            }

            if (cookie.expires) |expires| {
                try cookie_str.writer().print("; Expires={s}", .{expires});
            }

            if (cookie.max_age) |max_age| {
                try cookie_str.writer().print("; Max-Age={d}", .{max_age});
            }

            if (cookie.secure) {
                try cookie_str.writer().print("; Secure", .{});
            }

            if (cookie.http_only) {
                try cookie_str.writer().print("; HttpOnly", .{});
            }

            if (cookie.same_site) |same_site| {
                try cookie_str.writer().print("; SameSite={s}", .{same_site.toString()});
            }

            try response.writer().print("Set-Cookie: {s}\r\n", .{cookie_str.items});
        }

        // Response body
        if (self.body) |body| {
            if (!self.headers.contains("Content-Length")) {
                try response.writer().print("Content-Length: {d}\r\n", .{body.len});
            }

            try response.writer().print("\r\n", .{});
            try response.writer().print("{s}", .{body});
        } else {
            try response.writer().print("Content-Length: 0\r\n\r\n", .{});
        }

        return response.toOwnedSlice();
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();

        if (self.body) |body| {
            self.allocator.free(body);
        }

        self.cookies.deinit();
    }
};

// Tests
test "HttpResponse initialization and basic operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    // Test initial state
    try testing.expect(response.status == StatusCode.ok);
    try testing.expect(response.body == null);
    try testing.expect(response.headers.count() == 0);
    try testing.expect(response.cookies.items.len == 0);
}

test "HttpResponse set headers" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    // Set headers
    try response.setHeader("Content-Type", "application/json");
    try response.setHeader("X-Custom", "test-value");

    // Verify headers
    try testing.expect(response.headers.count() == 2);
    try testing.expectEqualStrings("application/json", response.headers.get("Content-Type").?);
    try testing.expectEqualStrings("test-value", response.headers.get("X-Custom").?);
}

test "HttpResponse set body" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    // Set body
    try response.setBody("Hello, World!");
    try testing.expect(response.body != null);
    try testing.expectEqualStrings("Hello, World!", response.body.?);

    // Override body
    try response.setBody("New content");
    try testing.expectEqualStrings("New content", response.body.?);
}

test "HttpResponse JSON response" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    // Set JSON response
    try response.setJsonBody("{\"message\":\"success\"}");

    // Verify content type and body
    try testing.expectEqualStrings("application/json; charset=utf-8", response.headers.get("Content-Type").?);
    try testing.expectEqualStrings("{\"message\":\"success\"}", response.body.?);
}

test "HttpResponse HTML response" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    // Set HTML response
    try response.setHtmlBody("<html><body>Hello</body></html>");

    // Verify content type and body
    try testing.expectEqualStrings("text/html; charset=utf-8", response.headers.get("Content-Type").?);
    try testing.expectEqualStrings("<html><body>Hello</body></html>", response.body.?);
}

test "HttpResponse text response" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var response = HttpResponse.init(allocator);
    defer response.deinit();

    // Set text response
    try response.setTextBody("Plain text content");

    // Verify content type and body
    try testing.expectEqualStrings("text/plain; charset=utf-8", response.headers.get("Content-Type").?);
    try testing.expectEqualStrings("Plain text content", response.body.?);
}

test "StatusCode enum" {
    const testing = std.testing;

    try testing.expect(@intFromEnum(StatusCode.ok) == 200);
    try testing.expect(@intFromEnum(StatusCode.not_found) == 404);
    try testing.expect(@intFromEnum(StatusCode.internal_server_error) == 500);

    try testing.expectEqualStrings("OK", StatusCode.ok.toString());
    try testing.expectEqualStrings("Not Found", StatusCode.not_found.toString());
    try testing.expectEqualStrings("Internal Server Error", StatusCode.internal_server_error.toString());
}
