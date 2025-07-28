//! HTTP request parsing and handling
//!
//! This module provides comprehensive HTTP request parsing with:
//! - Robust request line parsing (method, path, version)
//! - Header parsing with security validation
//! - Query parameter extraction
//! - Request body handling with size limits
//! - Memory-safe string handling

const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const HttpConfig = @import("config.zig").HttpConfig;

/// HTTP method enumeration
/// Defines all standard HTTP methods
pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
    TRACE,
    CONNECT,

    /// Convert string to HTTP method enum
    pub fn fromString(method_str: []const u8) ?HttpMethod {
        return std.meta.stringToEnum(HttpMethod, method_str);
    }

    /// Convert HTTP method enum to string
    pub fn toString(self: HttpMethod) []const u8 {
        return @tagName(self);
    }
};

/// Security limits for request parsing
const SecurityLimits = struct {
    const MAX_REQUEST_SIZE: usize = 1024 * 1024; // 1MB
    const MAX_METHOD_LENGTH: usize = 16;
    const MAX_URI_LENGTH: usize = 2048;
    const MAX_VERSION_LENGTH: usize = 16;
    const MAX_HEADER_NAME_SIZE: usize = 256;
    const MAX_HEADER_VALUE_SIZE: usize = 4096;
    const MAX_HEADER_COUNT: usize = 100;
};

/// Complete HTTP request representation
/// Contains request line, headers, body and provides structured access
pub const HttpRequest = struct {
    allocator: Allocator,
    method: []const u8,
    path: []const u8,
    query: ?[]const u8,
    version: []const u8,
    headers: StringHashMap([]const u8),
    body: ?[]const u8,
    raw_data: []const u8,

    const Self = @This();

    /// Parse raw HTTP request data
    /// Converts byte stream to structured request object
    pub fn parseFromBuffer(allocator: Allocator, buffer: []const u8, config: HttpConfig) !Self {
        // Basic request size validation - use a reasonable upper bound
        // We'll validate headers and body separately according to their specific limits
        const max_reasonable_request = config.max_body_size + 64 * 1024; // body + 64KB for headers
        if (buffer.len > max_reasonable_request) {
            return error.RequestTooLarge;
        }

        var request = Self{
            .allocator = allocator,
            .method = "",
            .path = "",
            .query = null,
            .version = "",
            .headers = StringHashMap([]const u8).init(allocator),
            .body = null,
            .raw_data = buffer,
        };

        // Find headers and body separator
        const header_end = std.mem.indexOf(u8, buffer, "\r\n\r\n") orelse {
            return error.InvalidRequest;
        };

        // Validate header section size
        if (header_end > config.max_header_size) {
            return error.HeadersTooLarge;
        }

        const headers_part = buffer[0..header_end];

        // Parse request line and headers
        var lines = std.mem.splitSequence(u8, headers_part, "\r\n");

        // Parse request line
        const request_line = lines.next() orelse {
            return error.InvalidRequest;
        };

        try request.parseRequestLine(request_line);
        errdefer request.deinit();

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) break;
            try request.parseHeaderLine(line);
        }

        // Parse body
        if (header_end + 4 < buffer.len) {
            const body_start = header_end + 4;
            const content_length = request.getContentLength();

            if (content_length != null and content_length.? > 0) {
                // Validate body size against configuration
                if (content_length.? > config.max_body_size) {
                    return error.BodyTooLarge;
                }

                // Enhanced boundary checking
                if (body_start >= buffer.len) {
                    return error.InvalidRequestFormat;
                }

                const available_body_size = buffer.len - body_start;
                const actual_body_size = @min(content_length.?, available_body_size);

                if (actual_body_size > 0) {
                    const body_end = body_start + actual_body_size;
                    request.body = buffer[body_start..body_end];
                }
            }
        }

        return request;
    }

    /// Parse request line (method, path, version)
    fn parseRequestLine(self: *Self, line: []const u8) !void {
        var parts = std.mem.splitSequence(u8, line, " ");

        // Validate all parts exist and are valid
        const method = parts.next() orelse {
            return error.InvalidRequestLine;
        };
        if (method.len == 0 or method.len > SecurityLimits.MAX_METHOD_LENGTH) {
            return error.InvalidRequestLine;
        }

        const url = parts.next() orelse {
            return error.InvalidRequestLine;
        };
        if (url.len == 0 or url.len > SecurityLimits.MAX_URI_LENGTH) {
            return error.InvalidRequestLine;
        }

        const version = parts.next() orelse {
            return error.InvalidRequestLine;
        };
        if (version.len == 0 or version.len > SecurityLimits.MAX_VERSION_LENGTH) {
            return error.InvalidRequestLine;
        }

        // Validate HTTP method
        const valid_methods = [_][]const u8{ "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH", "TRACE" };
        var method_valid = false;
        for (valid_methods) |valid_method| {
            if (std.mem.eql(u8, method, valid_method)) {
                method_valid = true;
                break;
            }
        }
        if (!method_valid) {
            return error.InvalidRequestLine;
        }

        // Validate HTTP version format
        if (!std.mem.startsWith(u8, version, "HTTP/")) {
            return error.InvalidRequestLine;
        }

        // Check for dangerous characters in URL
        for (url) |char| {
            if (char == 0) { // Null byte injection detection
                return error.InvalidRequestLine;
            }
        }

        // All validation passed, allocate memory
        self.method = try self.allocator.dupe(u8, method);
        errdefer {
            self.allocator.free(self.method);
            self.method = "";
        }

        // Check for query parameters
        if (std.mem.indexOf(u8, url, "?")) |query_start| {
            self.path = try self.allocator.dupe(u8, url[0..query_start]);
            errdefer {
                self.allocator.free(self.path);
                self.path = "";
            }
            self.query = try self.allocator.dupe(u8, url[query_start + 1 ..]);
            errdefer {
                if (self.query) |q| {
                    self.allocator.free(q);
                    self.query = null;
                }
            }
        } else {
            self.path = try self.allocator.dupe(u8, url);
            errdefer {
                self.allocator.free(self.path);
                self.path = "";
            }
        }

        self.version = try self.allocator.dupe(u8, version);
        errdefer {
            self.allocator.free(self.version);
            self.version = "";
        }
    }

    /// Parse header line
    fn parseHeaderLine(self: *Self, line: []const u8) !void {
        const colon_pos = std.mem.indexOf(u8, line, ":") orelse {
            return error.InvalidHeaderLine;
        };

        const name = std.mem.trim(u8, line[0..colon_pos], " ");
        const value = std.mem.trim(u8, line[colon_pos + 1 ..], " ");

        // Validate header name and value length
        if (name.len == 0 or name.len > SecurityLimits.MAX_HEADER_NAME_SIZE) {
            return error.InvalidHeaderLine;
        }
        if (value.len > SecurityLimits.MAX_HEADER_VALUE_SIZE) {
            return error.InvalidHeaderLine;
        }

        // Check for CRLF injection attacks
        for (value) |char| {
            if (char == '\r' or char == '\n' or char == 0) {
                return error.InvalidHeaderLine;
            }
        }

        // Check header count limit
        if (self.headers.count() >= SecurityLimits.MAX_HEADER_COUNT) {
            return error.TooManyHeaders;
        }

        const name_dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_dup);

        const value_dup = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_dup);

        try self.headers.put(name_dup, value_dup);
    }

    /// Get content length from headers
    fn getContentLength(self: *Self) ?usize {
        const content_length = self.headers.get("Content-Length") orelse {
            return null;
        };

        return std.fmt.parseInt(usize, content_length, 10) catch null;
    }

    /// Get request header by name
    pub fn getHeader(self: *const Self, name: []const u8) ?[]const u8 {
        return self.headers.get(name);
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Free string memory (only if not empty)
        if (self.method.len > 0) {
            self.allocator.free(self.method);
            self.method = "";
        }
        if (self.path.len > 0) {
            self.allocator.free(self.path);
            self.path = "";
        }
        if (self.query) |query| {
            self.allocator.free(query);
            self.query = null;
        }
        if (self.version.len > 0) {
            self.allocator.free(self.version);
            self.version = "";
        }

        // Free header memory
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }

        self.headers.deinit();
    }
};

// Tests
test "HttpRequest basic GET parsing" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /hello HTTP/1.1\r\nHost: localhost\r\nUser-Agent: test\r\n\r\n";
    const config = HttpConfig{};

    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    try testing.expectEqualStrings("GET", request.method);
    try testing.expectEqualStrings("/hello", request.path);
    try testing.expectEqualStrings("HTTP/1.1", request.version);
    try testing.expect(request.query == null);
    try testing.expect(request.body == null);

    // Test headers
    const host = request.getHeader("Host");
    try testing.expect(host != null);
    try testing.expectEqualStrings("localhost", host.?);

    const user_agent = request.getHeader("User-Agent");
    try testing.expect(user_agent != null);
    try testing.expectEqualStrings("test", user_agent.?);
}

test "HttpRequest with query parameters" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "GET /search?q=zig&limit=10 HTTP/1.1\r\nHost: example.com\r\n\r\n";
    const config = HttpConfig{};

    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    try testing.expectEqualStrings("GET", request.method);
    try testing.expectEqualStrings("/search", request.path);
    try testing.expect(request.query != null);
    try testing.expectEqualStrings("q=zig&limit=10", request.query.?);
}

test "HttpRequest POST with body" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const raw_request = "POST /api/users HTTP/1.1\r\nHost: api.example.com\r\nContent-Type: application/json\r\nContent-Length: 25\r\n\r\n{\"name\":\"John\",\"age\":30}";
    const config = HttpConfig{};

    var request = try HttpRequest.parseFromBuffer(allocator, raw_request, config);
    defer request.deinit();

    try testing.expectEqualStrings("POST", request.method);
    try testing.expectEqualStrings("/api/users", request.path);
    try testing.expect(request.body != null);
    try testing.expectEqualStrings("{\"name\":\"John\",\"age\":30}", request.body.?);
}

test "HttpMethod enum" {
    const testing = std.testing;

    try testing.expect(HttpMethod.fromString("GET") == .GET);
    try testing.expect(HttpMethod.fromString("POST") == .POST);
    try testing.expect(HttpMethod.fromString("INVALID") == null);

    try testing.expectEqualStrings("GET", HttpMethod.GET.toString());
    try testing.expectEqualStrings("POST", HttpMethod.POST.toString());
}

test "HttpRequest body size validation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with small body size limit
    var config = HttpConfig{};
    config.max_body_size = 10; // Very small limit for testing

    const raw_request = "POST /api/test HTTP/1.1\r\nContent-Length: 20\r\n\r\nThis is a long body content";

    const result = HttpRequest.parseFromBuffer(allocator, raw_request, config);
    try testing.expectError(error.BodyTooLarge, result);
}

test "HttpRequest header size validation" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test with small header size limit
    var config = HttpConfig{};
    config.max_header_size = 50; // Very small limit for testing

    const raw_request = "GET /test HTTP/1.1\r\nVery-Long-Header-Name-That-Exceeds-Limit: value\r\nAnother-Header: value\r\n\r\n";

    const result = HttpRequest.parseFromBuffer(allocator, raw_request, config);
    try testing.expectError(error.HeadersTooLarge, result);
}
