//! Basic HTTP Server Example
//!
//! This example demonstrates how to create a simple HTTP server using libxev-http.

const std = @import("std");
const libxev_http = @import("libxev-http");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.log.info("🚀 Starting libxev-http basic server example...", .{});
    std.log.info("Library version: {s}", .{libxev_http.version});

    // Create HTTP server
    var server = try libxev_http.createServer(allocator, "127.0.0.1", 8080);
    defer server.deinit();

    // Set up routes
    _ = try server.get("/", indexHandler);
    _ = try server.get("/api/status", statusHandler);
    _ = try server.post("/api/echo", echoHandler);
    _ = try server.get("/users/:id", userHandler);

    // Start listening
    try server.listen();
}

fn indexHandler(ctx: *libxev_http.Context) !void {
    try ctx.html(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\    <title>libxev-http Basic Server</title>
        \\    <style>
        \\        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        \\        .header { text-align: center; color: #333; }
        \\        .feature { background: #f5f5f5; padding: 15px; margin: 10px 0; border-radius: 5px; }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="header">
        \\        <h1>🚀 libxev-http Basic Server</h1>
        \\        <p>High-performance async HTTP framework for Zig</p>
        \\    </div>
        \\    
        \\    <div class="feature">
        \\        <h3>⚡ Async Event-Driven</h3>
        \\        <p>Built on libxev for maximum performance and scalability</p>
        \\    </div>
        \\    
        \\    <div class="feature">
        \\        <h3>🛣️ Advanced Routing</h3>
        \\        <p>Parameter extraction, wildcards, and middleware support</p>
        \\    </div>
        \\    
        \\    <div class="feature">
        \\        <h3>🔒 Production Ready</h3>
        \\        <p>Memory safe, cross-platform, and battle-tested</p>
        \\    </div>
        \\    
        \\    <div class="feature">
        \\        <h3>📚 API Endpoints</h3>
        \\        <ul>
        \\            <li><a href="/api/status">GET /api/status</a> - Server status</li>
        \\            <li>POST /api/echo - Echo request body</li>
        \\            <li>GET /users/:id - User profile (try /users/123)</li>
        \\        </ul>
        \\    </div>
        \\</body>
        \\</html>
    );
}

fn statusHandler(ctx: *libxev_http.Context) !void {
    const timestamp = std.time.timestamp();
    const status_json = try std.fmt.allocPrint(ctx.allocator,
        \\{{"status":"ok","server":"libxev-http","version":"{s}","timestamp":{d}}}
    , .{ libxev_http.version, timestamp });
    defer ctx.allocator.free(status_json);

    try ctx.json(status_json);
}

fn echoHandler(ctx: *libxev_http.Context) !void {
    const body = ctx.getBody() orelse "No body received";

    const echo_json = try std.fmt.allocPrint(ctx.allocator,
        \\{{"echo":"{s}","length":{d},"method":"{s}"}}
    , .{ body, body.len, ctx.getMethod() });
    defer ctx.allocator.free(echo_json);

    try ctx.json(echo_json);
}

fn userHandler(ctx: *libxev_http.Context) !void {
    const user_id = ctx.getParam("id") orelse "unknown";

    const user_json = try std.fmt.allocPrint(ctx.allocator,
        \\{{"user_id":"{s}","name":"User {s}","email":"user{s}@example.com"}}
    , .{ user_id, user_id, user_id });
    defer ctx.allocator.free(user_json);

    try ctx.json(user_json);
}
