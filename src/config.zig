//! Server configuration management
//!
//! This module provides comprehensive configuration management for the HTTP server:
//! - Network and connection settings
//! - Performance tuning parameters
//! - Security limits and timeouts
//! - Environment-specific configurations
//! - Configuration file loading support

const std = @import("std");

/// HTTP server configuration
/// Contains all configuration parameters needed for server operation
pub const HttpConfig = struct {
    // Network configuration
    port: u16 = 8080,
    address: []const u8 = "127.0.0.1",

    // Connection management
    max_connections: usize = 1000,
    read_timeout_ms: u32 = 30000,
    write_timeout_ms: u32 = 30000,
    keepalive_timeout_ms: u32 = 60000,

    // Memory management
    buffer_size: usize = 8192,
    max_buffers: usize = 200,

    // Routing system
    max_routes: usize = 100,
    max_route_params: usize = 20,

    // Middleware system
    max_middlewares: usize = 50,

    // Connection and timeout settings
    connection_timeout_ms: u32 = 30000, // Maximum connection lifetime
    request_timeout_ms: u32 = 30000, // Maximum time to receive complete request
    header_timeout_ms: u32 = 10000, // Maximum time to receive headers
    body_timeout_ms: u32 = 60000, // Maximum time to receive body
    idle_timeout_ms: u32 = 5000, // Connection idle timeout

    // Request size limits
    max_request_size: usize = 1024 * 1024, // Maximum total request size (1MB)
    max_header_count: usize = 100, // Maximum number of headers
    max_header_size: usize = 8192, // Maximum size of individual header
    max_uri_length: usize = 2048, // Maximum URI length
    max_body_size: usize = 10 * 1024 * 1024, // Maximum body size (10MB)

    // Body processing settings
    body_read_threshold_percent: u8 = 10, // Minimum body percentage for progress validation

    // Security and protection features
    enable_request_validation: bool = true, // Enable request validation
    enable_timeout_protection: bool = true, // Enable timeout-based protection

    // Performance settings
    enable_keep_alive: bool = true,
    enable_compression: bool = false,
    enable_cors: bool = true,

    // Logging configuration
    log_level: LogLevel = .info,
    enable_access_log: bool = true,
    enable_error_log: bool = true,

    /// Log level enumeration
    pub const LogLevel = enum {
        debug,
        info,
        warning,
        @"error",
        critical,

        pub fn toString(self: LogLevel) []const u8 {
            return switch (self) {
                .debug => "DEBUG",
                .info => "INFO",
                .warning => "WARNING",
                .@"error" => "ERROR",
                .critical => "CRITICAL",
            };
        }
    };

    /// Validate configuration values
    pub fn validate(self: HttpConfig) !void {
        if (self.port == 0) return error.InvalidPort;
        if (self.max_connections == 0) return error.InvalidMaxConnections;
        if (self.buffer_size == 0) return error.InvalidBufferSize;
        if (self.max_buffers == 0) return error.InvalidMaxBuffers;
        if (self.read_timeout_ms == 0) return error.InvalidReadTimeout;
        if (self.write_timeout_ms == 0) return error.InvalidWriteTimeout;
        if (self.max_request_size == 0) return error.InvalidMaxRequestSize;
    }

    /// Get configuration optimized for development
    pub fn development() HttpConfig {
        return HttpConfig{
            .port = 8080,
            .max_connections = 100,
            .log_level = .debug,
            .enable_access_log = true,
            .enable_error_log = true,
            .read_timeout_ms = 10000,
            .write_timeout_ms = 10000,
            // More lenient timeouts for development
            .connection_timeout_ms = 60000,
            .request_timeout_ms = 60000,
            .header_timeout_ms = 20000,
            .body_timeout_ms = 120000,
            .idle_timeout_ms = 10000,
        };
    }

    /// Get configuration optimized for production
    pub fn production() HttpConfig {
        return HttpConfig{
            .port = 80,
            .max_connections = 10000,
            .log_level = .info,
            .enable_access_log = true,
            .enable_error_log = true,
            .enable_keep_alive = true,
            .enable_compression = true,
            .read_timeout_ms = 30000,
            .write_timeout_ms = 30000,
            .buffer_size = 16384,
            .max_buffers = 1000,
        };
    }

    /// Get configuration optimized for testing
    pub fn testing() HttpConfig {
        return HttpConfig{
            .port = 0, // Random port
            .max_connections = 10,
            .log_level = .warning,
            .enable_access_log = false,
            .enable_error_log = true,
            .read_timeout_ms = 1000,
            .write_timeout_ms = 1000,
            // Fast timeouts for testing
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 5000,
            .header_timeout_ms = 2000,
            .body_timeout_ms = 3000,
            .idle_timeout_ms = 1000,
        };
    }
};

/// Application configuration
/// Contains application-level configuration and HTTP server configuration
pub const AppConfig = struct {
    http: HttpConfig = .{},
    app_name: []const u8 = "libxev-http",
    version: []const u8 = "1.0.0",
    environment: Environment = .development,

    /// Application runtime environment
    pub const Environment = enum {
        development,
        testing,
        production,

        pub fn toString(self: Environment) []const u8 {
            return switch (self) {
                .development => "development",
                .testing => "testing",
                .production => "production",
            };
        }
    };

    /// Check if running in development environment
    pub fn isDevelopment(self: AppConfig) bool {
        return self.environment == .development;
    }

    /// Check if running in production environment
    pub fn isProduction(self: AppConfig) bool {
        return self.environment == .production;
    }

    /// Check if running in testing environment
    pub fn isTesting(self: AppConfig) bool {
        return self.environment == .testing;
    }

    /// Get environment-specific HTTP configuration
    pub fn getHttpConfig(self: AppConfig) HttpConfig {
        return switch (self.environment) {
            .development => HttpConfig.development(),
            .testing => HttpConfig.testing(),
            .production => HttpConfig.production(),
        };
    }

    /// Validate entire application configuration
    pub fn validate(self: AppConfig) !void {
        try self.http.validate();
        if (self.app_name.len == 0) return error.InvalidAppName;
        if (self.version.len == 0) return error.InvalidVersion;
    }
};

/// Load application configuration from file
/// Returns default configuration if file not found
pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !AppConfig {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound => {
                std.log.info("Configuration file not found, using defaults: {s}", .{path});
                return AppConfig{};
            },
            else => return err,
        }
    };
    defer file.close();

    const file_size = try file.getEndPos();
    if (file_size > 1024 * 1024) { // Limit config file size to 1MB
        return error.ConfigFileTooLarge;
    }

    const contents = try allocator.alloc(u8, file_size);
    defer allocator.free(contents);

    _ = try file.readAll(contents);

    // Simple configuration parsing (in real projects, use JSON/TOML parser)
    var config = AppConfig{};

    // Parse configuration content (example implementation)
    if (std.mem.indexOf(u8, contents, "port=")) |start| {
        const port_start = start + 5;
        if (std.mem.indexOf(u8, contents[port_start..], "\n")) |end| {
            const port_str = contents[port_start .. port_start + end];
            config.http.port = std.fmt.parseInt(u16, port_str, 10) catch config.http.port;
        }
    }

    if (std.mem.indexOf(u8, contents, "environment=")) |start| {
        const env_start = start + 12;
        if (std.mem.indexOf(u8, contents[env_start..], "\n")) |end| {
            const env_str = contents[env_start .. env_start + end];
            if (std.mem.eql(u8, env_str, "production")) {
                config.environment = .production;
            } else if (std.mem.eql(u8, env_str, "testing")) {
                config.environment = .testing;
            }
        }
    }

    try config.validate();
    return config;
}

/// Save configuration to file
pub fn saveConfig(config: AppConfig, allocator: std.mem.Allocator, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    const writer = buffer.writer();
    try writer.print("# libxev-http Configuration\n");
    try writer.print("app_name={s}\n", .{config.app_name});
    try writer.print("version={s}\n", .{config.version});
    try writer.print("environment={s}\n", .{config.environment.toString()});
    try writer.print("\n# HTTP Server Configuration\n");
    try writer.print("port={}\n", .{config.http.port});
    try writer.print("address={s}\n", .{config.http.address});
    try writer.print("max_connections={}\n", .{config.http.max_connections});
    try writer.print("read_timeout_ms={}\n", .{config.http.read_timeout_ms});
    try writer.print("write_timeout_ms={}\n", .{config.http.write_timeout_ms});
    try writer.print("buffer_size={}\n", .{config.http.buffer_size});
    try writer.print("max_buffers={}\n", .{config.http.max_buffers});
    try writer.print("log_level={s}\n", .{config.http.log_level.toString()});

    try file.writeAll(buffer.items);
}

// Tests
test "HttpConfig default values" {
    const testing = std.testing;
    const config = HttpConfig{};

    try testing.expect(config.port == 8080);
    try testing.expectEqualStrings("127.0.0.1", config.address);
    try testing.expect(config.max_connections == 1000);
    try testing.expect(config.read_timeout_ms == 30000);
    try testing.expect(config.write_timeout_ms == 30000);
    try testing.expect(config.buffer_size == 8192);
    try testing.expect(config.max_buffers == 200);
    try testing.expect(config.max_routes == 100);
    try testing.expect(config.max_middlewares == 50);
    try testing.expect(config.log_level == .info);
}

test "HttpConfig validation" {
    const testing = std.testing;

    // Valid configuration
    const valid_config = HttpConfig{};
    try valid_config.validate();

    // Invalid configurations
    const invalid_port = HttpConfig{ .port = 0 };
    try testing.expectError(error.InvalidPort, invalid_port.validate());

    const invalid_connections = HttpConfig{ .max_connections = 0 };
    try testing.expectError(error.InvalidMaxConnections, invalid_connections.validate());
}

test "HttpConfig environment presets" {
    const testing = std.testing;

    const dev_config = HttpConfig.development();
    try testing.expect(dev_config.port == 8080);
    try testing.expect(dev_config.log_level == .debug);
    try testing.expect(dev_config.max_connections == 100);

    const prod_config = HttpConfig.production();
    try testing.expect(prod_config.port == 80);
    try testing.expect(prod_config.log_level == .info);
    try testing.expect(prod_config.max_connections == 10000);
    try testing.expect(prod_config.enable_compression);

    const test_config = HttpConfig.testing();
    try testing.expect(test_config.port == 0);
    try testing.expect(test_config.log_level == .warning);
    try testing.expect(test_config.max_connections == 10);
}

test "AppConfig environment checks" {
    const testing = std.testing;

    const dev_config = AppConfig{ .environment = .development };
    try testing.expect(dev_config.isDevelopment());
    try testing.expect(!dev_config.isProduction());
    try testing.expect(!dev_config.isTesting());

    const prod_config = AppConfig{ .environment = .production };
    try testing.expect(!prod_config.isDevelopment());
    try testing.expect(prod_config.isProduction());
    try testing.expect(!prod_config.isTesting());
}

test "AppConfig validation" {
    const testing = std.testing;

    // Valid configuration
    const valid_config = AppConfig{};
    try valid_config.validate();

    // Invalid app name
    const invalid_name = AppConfig{ .app_name = "" };
    try testing.expectError(error.InvalidAppName, invalid_name.validate());

    // Invalid version
    const invalid_version = AppConfig{ .version = "" };
    try testing.expectError(error.InvalidVersion, invalid_version.validate());
}

test "loadConfig function" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test loading default configuration (when file doesn't exist)
    const config = try loadConfig(allocator, "nonexistent.conf");

    try testing.expectEqualStrings("libxev-http", config.app_name);
    try testing.expectEqualStrings("1.0.0", config.version);
    try testing.expect(config.environment == .development);
    try testing.expect(config.http.port == 8080);
}

test "LogLevel enum" {
    const testing = std.testing;

    try testing.expectEqualStrings("DEBUG", HttpConfig.LogLevel.debug.toString());
    try testing.expectEqualStrings("INFO", HttpConfig.LogLevel.info.toString());
    try testing.expectEqualStrings("WARNING", HttpConfig.LogLevel.warning.toString());
    try testing.expectEqualStrings("ERROR", HttpConfig.LogLevel.@"error".toString());
    try testing.expectEqualStrings("CRITICAL", HttpConfig.LogLevel.critical.toString());
}

test "Environment enum" {
    const testing = std.testing;

    try testing.expectEqualStrings("development", AppConfig.Environment.development.toString());
    try testing.expectEqualStrings("testing", AppConfig.Environment.testing.toString());
    try testing.expectEqualStrings("production", AppConfig.Environment.production.toString());
}
