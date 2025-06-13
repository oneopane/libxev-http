# Middleware System

libxev-http provides a powerful and flexible middleware system that allows you to process HTTP requests and responses in a pipeline fashion. This document explains how to use and create middleware.

## Overview

The middleware system in libxev-http supports:

- **Global middleware**: Applied to all routes
- **Route-specific middleware**: Applied only to specific routes
- **Built-in middleware**: Common functionality like logging, CORS, authentication, etc.
- **Custom middleware**: Create your own middleware functions
- **Middleware chaining**: Multiple middleware can be chained together

## Core Concepts

### Middleware Function Type

```zig
pub const MiddlewareFn = *const fn (*Context, NextFn) anyerror!void;
pub const NextFn = *const fn (*Context) anyerror!void;
```

A middleware function receives:
- `ctx`: The HTTP context containing request and response data
- `next`: A function to call the next middleware in the chain

### Execution Order

1. Global middleware (in registration order)
2. Route-specific middleware (in registration order)
3. Route handler

## Basic Usage

### Adding Global Middleware

Global middleware applies to all routes:

```zig
var server = try libxev_http.createServer(allocator, "127.0.0.1", 8080);

// Add global middleware
try server.use("logging", libxev_http.loggingMiddleware);
try server.use("request-id", libxev_http.requestIdMiddleware);
try server.use("cors", libxev_http.corsMiddleware);
```

### Adding Route-Specific Middleware

Route-specific middleware applies only to that route:

```zig
// Create a route
const protected_route = try server.get("/api/protected", protectedHandler);

// Add middleware to this specific route
try protected_route.use("auth", libxev_http.basicAuthMiddleware);
try protected_route.use("rate-limit", libxev_http.rateLimitMiddleware);
```

## Built-in Middleware

libxev-http provides several built-in middleware functions:

### Logging Middleware
Logs request details and timing:
```zig
try server.use("logging", libxev_http.loggingMiddleware);
```

### Request ID Middleware
Generates unique request IDs:
```zig
try server.use("request-id", libxev_http.requestIdMiddleware);
```

### CORS Middleware
Adds CORS headers:
```zig
try server.use("cors", libxev_http.corsMiddleware);
```

### Security Headers Middleware
Adds security-related headers:
```zig
try server.use("security", libxev_http.securityHeadersMiddleware);
```

### Basic Authentication Middleware
Provides basic HTTP authentication:
```zig
try route.use("auth", libxev_http.basicAuthMiddleware);
```

### JSON Body Parser Middleware
Validates JSON request bodies:
```zig
try server.use("json-parser", libxev_http.jsonBodyParserMiddleware);
```

### Rate Limiting Middleware
Adds rate limiting headers:
```zig
try route.use("rate-limit", libxev_http.rateLimitMiddleware);
```

### Error Handler Middleware
Handles errors gracefully:
```zig
try server.use("error-handler", libxev_http.errorHandlerMiddleware);
```

### Compression Middleware
Adds compression support:
```zig
try server.use("compression", libxev_http.compressionMiddleware);
```

## Creating Custom Middleware

### Basic Custom Middleware

```zig
fn customMiddleware(ctx: *libxev_http.Context, next: libxev_http.NextFn) !void {
    // Pre-processing: runs before the handler
    std.log.info("Custom middleware executing", .{});

    // Set some state
    try ctx.setState("custom_processed", "true");

    // Add a custom header
    try ctx.setHeader("X-Custom-Middleware", "executed");

    // Call the next middleware/handler
    try next(ctx);

    // Post-processing: runs after the handler (if needed)
    std.log.info("Custom middleware completed", .{});
}
```

### Middleware with Conditional Logic

```zig
fn validationMiddleware(ctx: *libxev_http.Context, next: libxev_http.NextFn) !void {
    const content_type = ctx.getHeader("Content-Type");

    if (content_type == null) {
        ctx.status(.bad_request);
        try ctx.json("{\"error\":\"Content-Type header required\"}");
        return; // Don't call next() to stop the chain
    }

    // Validation passed, continue
    return next(ctx);
}
```

### Middleware with Error Handling

```zig
fn errorHandlingMiddleware(ctx: *libxev_http.Context, next: libxev_http.NextFn) !void {
    next(ctx) catch |err| {
        std.log.err("Middleware error: {}", .{err});

        // Set error response
        ctx.status(.internal_server_error);
        try ctx.json("{\"error\":\"Internal server error\"}");

        return err;
    };
}
```

## Complete Example

```zig
const std = @import("std");
const libxev_http = @import("libxev-http");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try libxev_http.createServer(allocator, "127.0.0.1", 8080);
    defer server.deinit();

    // Global middleware
    try server.use("logging", libxev_http.loggingMiddleware);
    try server.use("request-id", libxev_http.requestIdMiddleware);
    try server.use("cors", libxev_http.corsMiddleware);

    // Basic route
    _ = try server.get("/", indexHandler);

    // Protected route with custom middleware
    const protected_route = try server.get("/api/protected", protectedHandler);
    try protected_route.use("auth", libxev_http.basicAuthMiddleware);
    try protected_route.use("custom", customMiddleware);

    try server.listen();
}

fn indexHandler(ctx: *libxev_http.Context) !void {
    try ctx.json("{\"message\":\"Hello World!\"}");
}

fn protectedHandler(ctx: *libxev_http.Context) !void {
    const request_id = ctx.getState("request_id") orelse "unknown";
    const response = try std.fmt.allocPrint(ctx.allocator,
        "{{\"message\":\"Protected resource\",\"request_id\":\"{s}\"}}",
        .{request_id});
    defer ctx.allocator.free(response);
    try ctx.json(response);
}

fn customMiddleware(ctx: *libxev_http.Context, next: libxev_http.NextFn) !void {
    try ctx.setHeader("X-Custom", "middleware-executed");
    return next(ctx);
}
```

## Best Practices

1. **Order matters**: Register middleware in the order you want them to execute
2. **Always call next()**: Unless you want to stop the chain (e.g., for authentication failures)
3. **Handle errors gracefully**: Use error handling middleware to catch and respond to errors
4. **Use state for data sharing**: Use `ctx.setState()` and `ctx.getState()` to share data between middleware
5. **Keep middleware focused**: Each middleware should have a single responsibility
6. **Test middleware independently**: Write unit tests for your custom middleware

## Testing

You can test the middleware system using the provided examples:

```bash
# Run the simple middleware test
zig build run-simple-middleware

# Run the comprehensive middleware example
zig build run-middleware

# Run middleware tests
zig build test-middleware
```

## Advanced Topics

### Middleware State Management

Middleware can store and retrieve state using the context:

```zig
// Set state in middleware
try ctx.setState("user_id", "12345");

// Get state in handler or other middleware
const user_id = ctx.getState("user_id");
```

### Conditional Middleware

You can create middleware that only runs under certain conditions:

```zig
fn conditionalMiddleware(ctx: *libxev_http.Context, next: libxev_http.NextFn) !void {
    if (std.mem.eql(u8, ctx.getMethod(), "POST")) {
        // Only run for POST requests
        try ctx.setHeader("X-POST-Request", "true");
    }
    return next(ctx);
}
```

### Middleware Composition

You can compose multiple middleware functions:

```zig
fn composedMiddleware(ctx: *libxev_http.Context, next: libxev_http.NextFn) !void {
    // Run multiple middleware in sequence
    try authMiddleware(ctx, struct {
        fn call(context: *libxev_http.Context) !void {
            return validationMiddleware(context, next);
        }
    }.call);
}
```
