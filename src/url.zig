//! URL encoding and decoding utilities
//!
//! This module provides safe URL encoding/decoding functions to handle
//! percent-encoded characters in URLs properly.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// URL decode a string, handling percent-encoded characters
/// Returns a newly allocated string that must be freed by the caller
pub fn urlDecode(allocator: Allocator, encoded: []const u8) ![]u8 {
    var decoded = std.ArrayList(u8).init(allocator);
    defer decoded.deinit();

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            // Try to decode the percent-encoded character
            const hex_chars = encoded[i + 1 .. i + 3];
            if (isValidHex(hex_chars)) {
                const decoded_byte = std.fmt.parseInt(u8, hex_chars, 16) catch {
                    // Invalid hex, treat as literal %
                    try decoded.append('%');
                    i += 1;
                    continue;
                };
                try decoded.append(decoded_byte);
                i += 3;
            } else {
                // Invalid hex sequence, treat as literal %
                try decoded.append('%');
                i += 1;
            }
        } else if (encoded[i] == '+') {
            // Convert + to space (common in query parameters)
            try decoded.append(' ');
            i += 1;
        } else {
            try decoded.append(encoded[i]);
            i += 1;
        }
    }

    return decoded.toOwnedSlice();
}

/// URL encode a string, percent-encoding special characters
/// Returns a newly allocated string that must be freed by the caller
pub fn urlEncode(allocator: Allocator, input: []const u8) ![]u8 {
    var encoded = std.ArrayList(u8).init(allocator);
    defer encoded.deinit();

    for (input) |byte| {
        if (shouldEncode(byte)) {
            try encoded.writer().print("%{X:0>2}", .{byte});
        } else {
            try encoded.append(byte);
        }
    }

    return encoded.toOwnedSlice();
}

/// Check if a character should be percent-encoded
fn shouldEncode(byte: u8) bool {
    return switch (byte) {
        // Unreserved characters (RFC 3986)
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => false,
        // Everything else should be encoded
        else => true,
    };
}

/// Check if a two-character string is valid hexadecimal
fn isValidHex(hex: []const u8) bool {
    if (hex.len != 2) return false;
    for (hex) |char| {
        switch (char) {
            '0'...'9', 'A'...'F', 'a'...'f' => {},
            else => return false,
        }
    }
    return true;
}

/// Decode URL path components safely, handling percent-encoding
/// This function specifically handles path segments and preserves path structure
pub fn decodePathComponent(allocator: Allocator, component: []const u8) ![]u8 {
    // For path components, we don't convert + to space
    var decoded = std.ArrayList(u8).init(allocator);
    defer decoded.deinit();

    var i: usize = 0;
    while (i < component.len) {
        if (component[i] == '%' and i + 2 < component.len) {
            // Try to decode the percent-encoded character
            const hex_chars = component[i + 1 .. i + 3];
            if (isValidHex(hex_chars)) {
                const decoded_byte = std.fmt.parseInt(u8, hex_chars, 16) catch {
                    // Invalid hex, treat as literal %
                    try decoded.append('%');
                    i += 1;
                    continue;
                };
                try decoded.append(decoded_byte);
                i += 3;
            } else {
                // Invalid hex sequence, treat as literal %
                try decoded.append('%');
                i += 1;
            }
        } else {
            try decoded.append(component[i]);
            i += 1;
        }
    }

    return decoded.toOwnedSlice();
}

/// Split URL path into components and decode each component
/// Returns an ArrayList of decoded path components
pub fn splitAndDecodePath(allocator: Allocator, path: []const u8) !std.ArrayList([]u8) {
    var components = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (components.items) |component| {
            allocator.free(component);
        }
        components.deinit();
    }

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue; // Skip empty parts (leading/trailing slashes)

        const decoded_part = try decodePathComponent(allocator, part);
        try components.append(decoded_part);
    }

    return components;
}

/// Free path components allocated by splitAndDecodePath
pub fn freePathComponents(allocator: Allocator, components: *std.ArrayList([]u8)) void {
    for (components.items) |component| {
        allocator.free(component);
    }
    components.deinit();
}

// Tests
test "URL decoding basic cases" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic percent encoding
    {
        const decoded = try urlDecode(allocator, "hello%20world");
        defer allocator.free(decoded);
        try testing.expectEqualStrings("hello world", decoded);
    }

    // Test forward slash encoding
    {
        const decoded = try urlDecode(allocator, "foo%2Fbar");
        defer allocator.free(decoded);
        try testing.expectEqualStrings("foo/bar", decoded);
    }

    // Test plus to space conversion
    {
        const decoded = try urlDecode(allocator, "hello+world");
        defer allocator.free(decoded);
        try testing.expectEqualStrings("hello world", decoded);
    }

    // Test no encoding needed
    {
        const decoded = try urlDecode(allocator, "hello");
        defer allocator.free(decoded);
        try testing.expectEqualStrings("hello", decoded);
    }
}

test "URL path component decoding" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test path component with encoded slash
    {
        const decoded = try decodePathComponent(allocator, "foo%2Fbar.txt");
        defer allocator.free(decoded);
        try testing.expectEqualStrings("foo/bar.txt", decoded);
    }

    // Test path component with encoded space
    {
        const decoded = try decodePathComponent(allocator, "my%20file.txt");
        defer allocator.free(decoded);
        try testing.expectEqualStrings("my file.txt", decoded);
    }
}

test "Split and decode path" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test path with encoded components
    {
        var components = try splitAndDecodePath(allocator, "/files/foo%2Fbar.txt/download");
        defer freePathComponents(allocator, &components);

        try testing.expect(components.items.len == 3);
        try testing.expectEqualStrings("files", components.items[0]);
        try testing.expectEqualStrings("foo/bar.txt", components.items[1]);
        try testing.expectEqualStrings("download", components.items[2]);
    }
}
