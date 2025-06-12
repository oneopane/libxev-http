//! Security utilities for HTTP server
//!
//! This module provides security-related functionality including:
//! - Slow attack detection and prevention
//! - Request size validation
//! - Connection timeout management
//! - Security headers management

const std = @import("std");
const HttpConfig = @import("config.zig").HttpConfig;

/// Security limits and validation
pub const SecurityLimits = struct {
    /// Maximum allowed request size (1MB default)
    pub const DEFAULT_MAX_REQUEST_SIZE: usize = 1024 * 1024;

    /// Maximum allowed header count
    pub const DEFAULT_MAX_HEADER_COUNT: usize = 100;

    /// Maximum allowed header size
    pub const DEFAULT_MAX_HEADER_SIZE: usize = 8192;

    /// Maximum allowed URI length
    pub const DEFAULT_MAX_URI_LENGTH: usize = 2048;

    /// Maximum allowed body size (10MB default)
    pub const DEFAULT_MAX_BODY_SIZE: usize = 10 * 1024 * 1024;
};

/// Request validation and processing result
pub const SecurityResult = enum {
    allowed,
    request_too_large,
    headers_too_many,
    header_too_large,
    uri_too_long,
    body_too_large,
    processing_timeout,
    connection_timeout,
    idle_timeout,
};

/// Validate request size against security limits
pub fn validateRequestSize(size: usize, config: HttpConfig) SecurityResult {
    if (size > config.max_request_size) {
        return .request_too_large;
    }
    return .allowed;
}

/// Validate header count against security limits
pub fn validateHeaderCount(count: usize, config: HttpConfig) SecurityResult {
    if (count > config.max_header_count) {
        return .headers_too_many;
    }
    return .allowed;
}

/// Validate individual header size
pub fn validateHeaderSize(size: usize, config: HttpConfig) SecurityResult {
    if (size > config.max_header_size) {
        return .header_too_large;
    }
    return .allowed;
}

/// Validate URI length
pub fn validateUriLength(length: usize, config: HttpConfig) SecurityResult {
    if (length > config.max_uri_length) {
        return .uri_too_long;
    }
    return .allowed;
}

/// Validate body size
pub fn validateBodySize(size: usize, config: HttpConfig) SecurityResult {
    if (size > config.max_body_size) {
        return .body_too_large;
    }
    return .allowed;
}

/// Connection timing information for attack detection
pub const ConnectionTiming = struct {
    start_time: i64,
    last_read_time: i64,
    headers_complete: bool,
    expected_body_length: ?usize,
    received_body_length: usize,

    pub fn init() ConnectionTiming {
        const now = std.time.milliTimestamp();
        return ConnectionTiming{
            .start_time = now,
            .last_read_time = now,
            .headers_complete = false,
            .expected_body_length = null,
            .received_body_length = 0,
        };
    }

    pub fn updateReadTime(self: *ConnectionTiming) void {
        self.last_read_time = std.time.milliTimestamp();
    }

    pub fn setHeadersComplete(self: *ConnectionTiming, body_length: ?usize) void {
        self.headers_complete = true;
        self.expected_body_length = body_length;
    }

    pub fn updateBodyLength(self: *ConnectionTiming, length: usize) void {
        self.received_body_length = length;
    }
};

/// Check for timeout and request processing issues
pub fn checkRequestTimeouts(timing: *const ConnectionTiming, config: HttpConfig) SecurityResult {
    if (!config.enable_timeout_protection) {
        return .allowed;
    }

    const now = std.time.milliTimestamp();
    const connection_duration = now - timing.start_time;
    const idle_duration = now - timing.last_read_time;

    // Check connection timeout
    if (connection_duration > config.connection_timeout_ms) {
        return .connection_timeout;
    }

    // Check idle timeout
    if (idle_duration > config.idle_timeout_ms) {
        return .idle_timeout;
    }

    // Check header processing timeout
    if (connection_duration > config.header_timeout_ms and !timing.headers_complete) {
        return .processing_timeout;
    }

    // Check body processing timeout and progress
    if (timing.headers_complete and timing.expected_body_length != null) {
        const expected = timing.expected_body_length.?;
        const threshold_percent = config.body_read_threshold_percent;
        const required_bytes = (expected * threshold_percent) / 100;

        if (connection_duration > config.body_timeout_ms and timing.received_body_length < required_bytes) {
            return .processing_timeout;
        }
    }

    return .allowed;
}

/// Security headers that should be added to responses
pub const SecurityHeaders = struct {
    /// Add security headers to response
    pub fn addSecurityHeaders(headers: *std.StringHashMap([]const u8), allocator: std.mem.Allocator) !void {
        // X-Content-Type-Options
        try headers.put(try allocator.dupe(u8, "X-Content-Type-Options"), try allocator.dupe(u8, "nosniff"));

        // X-Frame-Options
        try headers.put(try allocator.dupe(u8, "X-Frame-Options"), try allocator.dupe(u8, "DENY"));

        // X-XSS-Protection
        try headers.put(try allocator.dupe(u8, "X-XSS-Protection"), try allocator.dupe(u8, "1; mode=block"));

        // Referrer-Policy
        try headers.put(try allocator.dupe(u8, "Referrer-Policy"), try allocator.dupe(u8, "strict-origin-when-cross-origin"));
    }
};

/// Parse Content-Length header safely
pub fn parseContentLength(request_data: []const u8) ?usize {
    // Find the end of headers
    const header_end = std.mem.indexOf(u8, request_data, "\r\n\r\n") orelse return null;
    const headers_section = request_data[0..header_end];

    // Look for Content-Length header (case insensitive)
    var lines = std.mem.splitSequence(u8, headers_section, "\r\n");
    while (lines.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
            const value_start = std.mem.indexOf(u8, line, ":") orelse continue;
            const value = std.mem.trim(u8, line[value_start + 1 ..], " \t");
            return std.fmt.parseInt(usize, value, 10) catch null;
        }
    }

    return null;
}

/// Get result description for logging
pub fn getSecurityResultDescription(result: SecurityResult) []const u8 {
    return switch (result) {
        .allowed => "Request allowed",
        .request_too_large => "Request size exceeds limit",
        .headers_too_many => "Too many headers",
        .header_too_large => "Header size exceeds limit",
        .uri_too_long => "URI length exceeds limit",
        .body_too_large => "Body size exceeds limit",
        .processing_timeout => "Request processing timeout",
        .connection_timeout => "Connection timeout exceeded",
        .idle_timeout => "Idle timeout exceeded",
    };
}

// Tests
test "security validation functions" {
    const testing = std.testing;
    const config = HttpConfig{};

    // Test request size validation
    try testing.expect(validateRequestSize(1000, config) == .allowed);
    try testing.expect(validateRequestSize(2 * 1024 * 1024, config) == .request_too_large);

    // Test header count validation
    try testing.expect(validateHeaderCount(50, config) == .allowed);
    try testing.expect(validateHeaderCount(200, config) == .headers_too_many);
}

test "connection timing" {
    const testing = std.testing;

    var timing = ConnectionTiming.init();
    try testing.expect(!timing.headers_complete);
    try testing.expect(timing.expected_body_length == null);

    timing.setHeadersComplete(1000);
    try testing.expect(timing.headers_complete);
    try testing.expect(timing.expected_body_length.? == 1000);
}

test "content length parsing" {
    const testing = std.testing;

    const request1 = "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 123\r\n\r\n";
    try testing.expect(parseContentLength(request1).? == 123);

    const request2 = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    try testing.expect(parseContentLength(request2) == null);
}
