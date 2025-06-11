//! Integration tests for libxev-http

const std = @import("std");
const testing = std.testing;
const libxev_http = @import("libxev-http");

test "library version information" {
    try testing.expectEqualStrings("1.0.0", libxev_http.version);
    try testing.expect(libxev_http.version_major == 1);
    try testing.expect(libxev_http.version_minor == 0);
    try testing.expect(libxev_http.version_patch == 0);
}

test "basic types are available" {
    // Test that basic types can be referenced
    const allocator_type = libxev_http.Allocator;
    const arraylist_type = libxev_http.ArrayList;
    const hashmap_type = libxev_http.StringHashMap;

    // These should compile without error
    _ = allocator_type;
    _ = arraylist_type;
    _ = hashmap_type;
}
