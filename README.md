# libxev-http

A high-performance async HTTP framework for Zig built on top of [libxev](https://github.com/mitchellh/libxev).

## ✨ Features

- **⚡ Async Event-Driven**: Built on libxev for maximum performance and scalability
- **🛣️ Advanced Routing**: Parameter extraction, wildcards, and middleware support
- **🔒 Memory Safe**: Comprehensive resource management and security validation
- **🌍 Cross-Platform**: Supports Linux (io_uring/epoll), macOS (kqueue), and Windows (IOCP)
- **📦 Production Ready**: Battle-tested HTTP parsing and response building

## 🚀 Quick Start

### Installation

Add libxev-http to your project using git submodules:

```bash
git submodule add https://github.com/mitchellh/libxev.git libxev
```

### Basic Usage

```zig
const std = @import("std");
const libxev_http = @import("libxev-http");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
    try ctx.html("<h1>Hello, libxev-http!</h1>");
}

fn statusHandler(ctx: *libxev_http.Context) !void {
    try ctx.json("{\"status\":\"ok\",\"server\":\"libxev-http\"}");
}

fn echoHandler(ctx: *libxev_http.Context) !void {
    const body = ctx.getBody() orelse "No body";
    try ctx.text(body);
}

fn userHandler(ctx: *libxev_http.Context) !void {
    const user_id = ctx.getParam("id") orelse "unknown";
    const response = try std.fmt.allocPrint(ctx.allocator,
        "{{\"user_id\":\"{s}\"}}", .{user_id});
    defer ctx.allocator.free(response);
    try ctx.json(response);
}
```

## 📚 API Reference

### Server

```zig
// Create server
var server = try libxev_http.createServer(allocator, "127.0.0.1", 8080);

// Add routes
_ = try server.get("/path", handler);
_ = try server.post("/path", handler);
_ = try server.put("/path", handler);
_ = try server.delete("/path", handler);

// Start server
try server.listen();
```

### Context

```zig
fn handler(ctx: *libxev_http.Context) !void {
    // Request information
    const method = ctx.getMethod();
    const path = ctx.getPath();
    const body = ctx.getBody();
    const header = ctx.getHeader("Content-Type");

    // Route parameters
    const id = ctx.getParam("id");

    // Response helpers
    ctx.status(.ok);
    try ctx.json("{\"message\":\"success\"}");
    try ctx.html("<h1>Hello</h1>");
    try ctx.text("Plain text");

    // Headers
    try ctx.setHeader("X-Custom", "value");

    // Redirect
    try ctx.redirect("/new-path", .moved_permanently);
}
```

### Routing

```zig
// Exact routes
_ = try server.get("/users", listUsers);

// Parameter routes
_ = try server.get("/users/:id", getUser);
_ = try server.get("/users/:id/posts/:post_id", getUserPost);

// Wildcard routes
_ = try server.get("/static/*", serveStatic);
```

## 🏗️ Architecture

The framework is built with a modular architecture:

- **`request.zig`**: HTTP request parsing with security validation
- **`response.zig`**: HTTP response building with headers and cookies
- **`router.zig`**: High-performance routing with parameter extraction
- **`context.zig`**: Request context management and response helpers
- **`lib.zig`**: Main server implementation and public API

## 🧪 Testing

```bash
# Run all tests
zig build test

# Run integration tests
zig build test-integration

# Run example server
zig build run-basic
```

## 📖 Examples

See the `examples/` directory for complete examples:

- **`basic_server.zig`**: Simple HTTP server with multiple routes
- More examples coming soon!

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built on top of [libxev](https://github.com/mitchellh/libxev) by Mitchell Hashimoto
- Inspired by modern HTTP frameworks across different languages
- Extracted and refined from the original Zig-HTTP project

---

**libxev-http** - High-performance async HTTP framework for Zig 🚀
