# libxev-http Multi-Mode Example Server

## Overview

libxev-http provides a multi-mode example server that supports different configuration scenarios. Through simple command-line arguments, you can experience basic mode, secure mode, and development mode to understand how different configurations affect server behavior.

## 🚀 Usage

### Basic Usage

```bash
# Default mode (basic mode)
zig build run-basic

# Explicitly specify basic mode
zig build run-basic -- --mode=basic

# Secure mode (strict limits and timeouts)
zig build run-basic -- --mode=secure

# Development mode (relaxed settings)
zig build run-basic -- --mode=dev
```

## 📋 Server Modes

### 1. Basic Mode
- **Port**: 8080
- **Configuration**: Default configuration
- **Max Connections**: 1000
- **Use Case**: General purpose, balanced performance and security

```bash
zig build run-basic -- --mode=basic
```

**Features**:
- Standard timeout settings
- Default size limits
- Basic routing functionality

### 2. Secure Mode
- **Port**: 8082
- **Configuration**: Strict security configuration
- **Max Connections**: 500
- **Use Case**: High-security environments

```bash
zig build run-basic -- --mode=secure
```

**Features**:
- Strict timeout settings (connection: 20s, headers: 5s, body: 10s, idle: 3s)
- Strict size limits (request: 512KB, body: 5MB)
- Enhanced routing functionality
- Keep-Alive and compression disabled

### 3. Development Mode
- **Port**: 8080 (development configuration)
- **Configuration**: Relaxed development configuration
- **Max Connections**: 100
- **Use Case**: Development and debugging

```bash
zig build run-basic -- --mode=dev
```

**Features**:
- Relaxed timeout settings
- Detailed debug logging
- Suitable for development and debugging

## 🛣️ Route Comparison

### Basic Mode and Development Mode Routes

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | Homepage showing server info and mode description |
| GET | `/api/status` | Server status |
| POST | `/api/echo` | Echo request content |
| GET | `/users/:id` | User information (parameter example) |

### Additional Routes in Secure Mode

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check (secure mode only) |
| GET | `/config` | Configuration details (secure mode only) |
| POST | `/upload` | File upload test (size limited) |
| GET | `/stress-test` | Stress test (timeout test) |

## 🎯 Homepage Content

### Basic Mode Homepage
- Shows server mode information
- Introduces features of different modes
- Basic API endpoint list

### Secure Mode Homepage
- Shows detailed security configuration
- Timeout setting descriptions
- Complete endpoint list
- Security feature descriptions

## 🧪 Testing Examples

### Basic Functionality Testing

```bash
# Start basic mode
zig build run-basic

# Test status endpoint
curl http://127.0.0.1:8080/api/status

# Test user endpoint
curl http://127.0.0.1:8080/users/123

# Test echo endpoint
curl -X POST -d "Hello World" http://127.0.0.1:8080/api/echo
```

### Secure Mode Testing

```bash
# Start secure mode
zig build run-basic -- --mode=secure

# Test health check
curl http://127.0.0.1:8082/health

# Test configuration info
curl http://127.0.0.1:8082/config

# Test file upload
curl -X POST -d "test data" http://127.0.0.1:8082/upload

# Test timeout handling
curl http://127.0.0.1:8082/stress-test
```

### Timeout Protection Testing

```bash
# Test slow header attack protection (should timeout after 5 seconds)
{ echo "GET /test HTTP/1.1"; sleep 2; echo "Host: localhost"; sleep 4; echo ""; echo ""; } | nc 127.0.0.1 8082
```

## 📊 Configuration Comparison

| Configuration Item | Basic Mode | Secure Mode | Development Mode |
|-------------------|------------|-------------|------------------|
| Port | 8080 | 8082 | 8080 |
| Max Connections | 1000 | 500 | 100 |
| Connection Timeout | 30s | 20s | 60s |
| Header Timeout | 10s | 5s | 20s |
| Body Timeout | 60s | 10s | 120s |
| Idle Timeout | 5s | 3s | 10s |
| Max Request Size | 1MB | 512KB | 1MB |
| Max Body Size | 10MB | 5MB | 10MB |
| Keep-Alive | Enabled | Disabled | Enabled |

## 🔧 Code Structure

### Mode Detection
```zig
const ServerMode = enum {
    basic,
    secure,
    dev,

    fn fromString(str: []const u8) ?ServerMode {
        // Parse command line arguments
    }
};
```

### Configuration Generation
```zig
const config = switch (mode) {
    .basic => libxev_http.HttpConfig{ /* basic config */ },
    .secure => libxev_http.HttpConfig{ /* secure config */ },
    .dev => libxev_http.HttpConfig.development(),
};
```

### Dynamic Routing
```zig
// Common routes
_ = try server.get("/", indexHandler);
_ = try server.get("/api/status", statusHandler);

// Secure mode specific routes
if (mode == .secure) {
    _ = try server.get("/health", healthHandler);
    _ = try server.get("/config", configHandler);
}
```

### Smart Homepage
```zig
fn indexHandler(ctx: *libxev_http.Context) !void {
    // Detect mode based on Host header
    const is_secure_mode = std.mem.indexOf(u8, host_header, ":8082") != null;

    if (is_secure_mode) {
        // Show secure mode page
    } else {
        // Show basic mode page
    }
}
```

## 🎉 Features

### 1. Multi-Mode Support
- Single example file supports multiple configurations
- Easy mode switching via command-line arguments
- Unified build and test process

### 2. Smart Adaptation
- Routes automatically adjust based on mode
- Dynamic page content generation
- Intelligent feature demonstration

### 3. Learning Friendly
- Clear mode comparisons
- Complete configuration examples
- Actual functionality demonstrations

### 4. Practical Value
- Demonstrates best practices
- Provides configuration templates
- Convenient for rapid prototyping

This multi-mode example server provides users with a complete libxev-http functionality experience and learning resource.
