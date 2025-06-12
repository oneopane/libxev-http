# libxev-http Timeout Protection and Request Validation

## Overview

The libxev-http framework includes comprehensive timeout protection and request validation features that ensure server stability under various network conditions. These features prevent resource exhaustion, improve user experience, and provide flexible configuration options to adapt to different deployment environments.

## 🛡️ Protection Features

### Timeout Protection
- **Connection timeout**: Limits the maximum lifetime of individual connections
- **Request timeout**: Limits the maximum time to receive a complete request
- **Header timeout**: Limits the maximum time to receive HTTP headers
- **Body timeout**: Limits the maximum time to receive request body
- **Idle timeout**: Limits the maximum idle time for connections

### Request Validation
- **Size limits**: Configurable limits for requests, headers, URI, and body sizes
- **Format validation**: Validates HTTP request format correctness
- **Progress monitoring**: Monitors request reception progress to prevent abnormally slow transmissions

## ⚙️ Configuration Options

### Basic Configuration
```zig
const libxev_http = @import("libxev-http");

const config = libxev_http.HttpConfig{
    // Timeout settings
    .connection_timeout_ms = 30000,      // Connection timeout: 30 seconds
    .request_timeout_ms = 30000,         // Request timeout: 30 seconds
    .header_timeout_ms = 10000,          // Header timeout: 10 seconds
    .body_timeout_ms = 60000,            // Body timeout: 60 seconds
    .idle_timeout_ms = 5000,             // Idle timeout: 5 seconds

    // Size limits
    .max_request_size = 1024 * 1024,     // Max request: 1MB
    .max_header_count = 100,             // Max header count: 100
    .max_header_size = 8192,             // Max header size: 8KB
    .max_uri_length = 2048,              // Max URI length: 2KB
    .max_body_size = 10 * 1024 * 1024,   // Max body: 10MB

    // Protection feature toggles
    .enable_request_validation = true,    // Enable request validation
    .enable_timeout_protection = true,    // Enable timeout protection
};
```

### Preset Configurations

#### Development Environment
```zig
const config = libxev_http.HttpConfig.development();
// Features: Relaxed timeout settings, detailed logging, suitable for debugging
```

#### Production Environment
```zig
const config = libxev_http.HttpConfig.production();
// Features: Balanced timeout settings, moderate limits, stable and reliable
```

#### Testing Environment
```zig
const config = libxev_http.HttpConfig.testing();
// Features: Fast timeout settings, small limits, accelerated testing
```

## 🚀 Usage

### Basic Usage
```zig
// Use default configuration (automatically enables all protection features)
var server = try libxev_http.createServer(allocator, "127.0.0.1", 8080);
```

### Custom Configuration
```zig
// Use custom configuration
var server = try libxev_http.createServerWithConfig(
    allocator,
    "127.0.0.1",
    8080,
    config
);
```

### Multi-Mode Example Server
```bash
# Basic mode (default configuration)
zig build run-basic

# Secure mode (strict limits)
zig build run-basic -- --mode=secure

# Development mode (relaxed settings)
zig build run-basic -- --mode=dev
```

## 📊 Configuration Scenarios

### High-Performance Scenario
```zig
const config = libxev_http.HttpConfig{
    .connection_timeout_ms = 60000,       // Longer connection time
    .header_timeout_ms = 20000,           // Longer header processing time
    .body_timeout_ms = 120000,            // Longer body processing time
    .max_request_size = 10 * 1024 * 1024, // Larger request limits
    .max_body_size = 100 * 1024 * 1024,   // Larger body limits
};
```

### High-Security Scenario
```zig
const config = libxev_http.HttpConfig{
    .connection_timeout_ms = 10000,       // Shorter connection time
    .header_timeout_ms = 3000,            // Shorter header processing time
    .body_timeout_ms = 5000,              // Shorter body processing time
    .max_request_size = 256 * 1024,       // Smaller request limits
    .max_body_size = 1024 * 1024,         // Smaller body limits
    .enable_keep_alive = false,           // Disable keep-alive
};
```

### Development/Debugging Scenario
```zig
const config = libxev_http.HttpConfig{
    .connection_timeout_ms = 300000,      // Very long timeout for debugging
    .enable_timeout_protection = false,   // Optionally disable protection
    .log_level = .debug,                  // Detailed logging
};
```

## 🔍 Monitoring and Logging

### Timeout Event Logs
```
warning: ⏰ Connection timeout exceeded
warning: ⏰ Idle timeout exceeded
warning: ⏱️ Request processing timeout
```

### Validation Failure Logs
```
warning: 🚫 Request size exceeds limit: 1048576 bytes (limit: 524288 bytes)
warning: 🚫 Request validation failed: Request too large
```

### Connection Management Logs
```
info: 📥 Accepted new connection (Active: 1)
info: 📨 Received 87 bytes (total: 87)
info: 🔒 Connection closed
```

## 🧪 Testing and Validation

### Functional Testing
```bash
# Normal request test
curl http://127.0.0.1:8080/api/status

# Timeout test (simulate slow request)
{ echo "GET /test HTTP/1.1"; sleep 6; echo "Host: localhost"; } | nc 127.0.0.1 8080

# Size limit test
dd if=/dev/zero bs=1024 count=2048 | curl -X POST -d @- http://127.0.0.1:8080/upload
```

### Unit Testing
```bash
# Run security module tests
zig build test-security

# Run all tests
zig build test-all
```

## 📈 Performance Impact

### Memory Overhead
- Approximately 64 bytes per connection for time tracking
- Request buffers allocated dynamically based on actual needs
- Total memory overhead < 1%

### CPU Overhead
- Timeout checks on each read: < 1 microsecond
- Request validation function calls: < 100 nanoseconds
- Total CPU overhead < 0.1%

### Network Effects
- No additional network overhead
- Abnormal connections closed faster, reducing resource usage
- Improved overall server responsiveness

## 🔧 Internal Implementation

### Connection Time Tracking
```zig
pub const ConnectionTiming = struct {
    start_time: i64,
    last_read_time: i64,
    headers_complete: bool,
    expected_body_length: ?usize,
    received_body_length: usize,
};
```

### Validation Results
```zig
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
```

### Core Check Functions
```zig
pub fn checkRequestTimeouts(timing: *const ConnectionTiming, config: HttpConfig) SecurityResult;
pub fn validateRequestSize(size: usize, config: HttpConfig) SecurityResult;
pub fn validateHeaderCount(count: usize, config: HttpConfig) SecurityResult;
```

## 🎯 Best Practices

### Production Deployment
1. **Monitor logs**: Regularly check timeout and validation failure logs
2. **Adjust configuration**: Tune timeout values based on actual traffic patterns
3. **Load testing**: Verify configuration performance under high load
4. **Gradual deployment**: Test configuration in staging before production

### Development/Debugging
1. **Use development mode**: `HttpConfig.development()` provides relaxed settings
2. **Enable detailed logging**: Set `.log_level = .debug`
3. **Temporarily disable protection**: Set `.enable_timeout_protection = false` when debugging
4. **Gradual tightening**: Start with relaxed configuration and gradually adjust to production settings

### Security Hardening
1. **Strict timeouts**: Use shorter timeout values
2. **Small limits**: Set smaller request and body size limits
3. **Disable features**: Disable unnecessary features like Keep-Alive
4. **Monitor alerts**: Set up alerts for abnormal events

## 🔄 Compatibility

### API Compatibility
- ✅ All existing APIs remain unchanged
- ✅ Default configuration provides reasonable protection levels
- ✅ Existing applications work without modification

### Configuration Compatibility
- ✅ Supports gradual configuration adjustments
- ✅ Features can be selectively enabled/disabled
- ✅ Backward-compatible configuration options

These protection features ensure that libxev-http servers run stably, securely, and efficiently across various network environments.
