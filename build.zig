const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================================
    // Dependencies
    // ============================================================================

    const libxev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    // ============================================================================
    // Library
    // ============================================================================

    const lib = b.addStaticLibrary(.{
        .name = "libxev-http",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("xev", libxev_dep.module("xev"));
    b.installArtifact(lib);

    // ============================================================================
    // Examples and Tools
    // ============================================================================

    // Multi-mode example server (supports basic, secure, and dev modes)
    const example_server = b.addExecutable(.{
        .name = "example-server",
        .root_source_file = b.path("examples/basic_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_server.root_module.addImport("xev", libxev_dep.module("xev"));
    example_server.root_module.addImport("libxev-http", lib.root_module);
    b.installArtifact(example_server);

    const run_example = b.addRunArtifact(example_server);
    run_example.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_example.addArgs(args);
    }
    const run_example_step = b.step("run-basic", "🚀 Run the multi-mode example server (use --mode=basic|secure|dev)");
    run_example_step.dependOn(&run_example.step);

    // ============================================================================
    // Tests
    // ============================================================================

    // Main library tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "🧪 Run core library unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("xev", libxev_dep.module("xev"));
    integration_tests.root_module.addImport("libxev-http", lib.root_module);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "🔗 Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // ============================================================================
    // Module-specific Tests
    // ============================================================================

    // HTTP Request module tests
    const request_tests = b.addTest(.{
        .root_source_file = b.path("src/request.zig"),
        .target = target,
        .optimize = optimize,
    });
    request_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // HTTP Response module tests
    const response_tests = b.addTest(.{
        .root_source_file = b.path("src/response.zig"),
        .target = target,
        .optimize = optimize,
    });
    response_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // Context module tests
    const context_tests = b.addTest(.{
        .root_source_file = b.path("src/context.zig"),
        .target = target,
        .optimize = optimize,
    });
    context_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // Router module tests
    const router_tests = b.addTest(.{
        .root_source_file = b.path("src/router.zig"),
        .target = target,
        .optimize = optimize,
    });
    router_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // Buffer module tests
    const buffer_tests = b.addTest(.{
        .root_source_file = b.path("src/buffer.zig"),
        .target = target,
        .optimize = optimize,
    });
    buffer_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // Configuration module tests
    const config_tests = b.addTest(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // Security and timeout protection module tests
    const security_tests = b.addTest(.{
        .root_source_file = b.path("src/security.zig"),
        .target = target,
        .optimize = optimize,
    });
    security_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // URL encoding/decoding module tests
    const url_tests = b.addTest(.{
        .root_source_file = b.path("src/url.zig"),
        .target = target,
        .optimize = optimize,
    });
    url_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // ============================================================================
    // Test Execution Steps
    // ============================================================================

    // Module test runners
    const run_request_tests = b.addRunArtifact(request_tests);
    const run_response_tests = b.addRunArtifact(response_tests);
    const run_context_tests = b.addRunArtifact(context_tests);
    const run_router_tests = b.addRunArtifact(router_tests);
    const run_buffer_tests = b.addRunArtifact(buffer_tests);
    const run_config_tests = b.addRunArtifact(config_tests);
    const run_security_tests = b.addRunArtifact(security_tests);
    const run_url_tests = b.addRunArtifact(url_tests);

    // Individual module test steps
    const request_test_step = b.step("test-request", "📨 Run HTTP request module tests");
    request_test_step.dependOn(&run_request_tests.step);

    const response_test_step = b.step("test-response", "📤 Run HTTP response module tests");
    response_test_step.dependOn(&run_response_tests.step);

    const context_test_step = b.step("test-context", "🔄 Run context module tests");
    context_test_step.dependOn(&run_context_tests.step);

    const router_test_step = b.step("test-router", "🛣️ Run router module tests");
    router_test_step.dependOn(&run_router_tests.step);

    const buffer_test_step = b.step("test-buffer", "📦 Run buffer module tests");
    buffer_test_step.dependOn(&run_buffer_tests.step);

    const config_test_step = b.step("test-config", "⚙️ Run configuration module tests");
    config_test_step.dependOn(&run_config_tests.step);

    const security_test_step = b.step("test-security", "🛡️ Run security and timeout protection tests");
    security_test_step.dependOn(&run_security_tests.step);

    const url_test_step = b.step("test-url", "🔗 Run URL encoding/decoding module tests");
    url_test_step.dependOn(&run_url_tests.step);

    // ============================================================================
    // Comprehensive Test Suites
    // ============================================================================

    // Complete test suite - runs ALL tests
    const test_all_step = b.step("test-all", "🧪 Run ALL tests (unit + integration + modules)");
    test_all_step.dependOn(&run_lib_unit_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);
    test_all_step.dependOn(&run_request_tests.step);
    test_all_step.dependOn(&run_response_tests.step);
    test_all_step.dependOn(&run_context_tests.step);
    test_all_step.dependOn(&run_router_tests.step);
    test_all_step.dependOn(&run_buffer_tests.step);
    test_all_step.dependOn(&run_config_tests.step);
    test_all_step.dependOn(&run_security_tests.step);
    test_all_step.dependOn(&run_url_tests.step);

    // Coverage analysis (runs all tests with detailed output)
    const test_coverage_step = b.step("test-coverage", "📊 Run all tests with coverage analysis");
    test_coverage_step.dependOn(test_all_step);

    // Quick test suite (core functionality only)
    const test_quick_step = b.step("test-quick", "⚡ Run quick tests (core library + integration)");
    test_quick_step.dependOn(&run_lib_unit_tests.step);
    test_quick_step.dependOn(&run_integration_tests.step);

    // ============================================================================
    // Convenience Steps
    // ============================================================================

    // Example server shortcuts
    const run_basic_mode = b.step("run-basic-mode", "🚀 Run example server in basic mode");
    run_basic_mode.dependOn(&run_example.step);

    const run_secure_mode_step = b.addSystemCommand(&.{ "zig", "build", "run-basic", "--", "--mode=secure" });
    const run_secure_mode = b.step("run-secure-mode", "🔒 Run example server in secure mode");
    run_secure_mode.dependOn(&run_secure_mode_step.step);

    const run_dev_mode_step = b.addSystemCommand(&.{ "zig", "build", "run-basic", "--", "--mode=dev" });
    const run_dev_mode = b.step("run-dev-mode", "🛠️ Run example server in development mode");
    run_dev_mode.dependOn(&run_dev_mode_step.step);

    // Help step
    const help_step = b.step("help", "📖 Show available build commands");
    help_step.dependOn(&b.addSystemCommand(&.{
        "echo",
        \\
        \\🚀 libxev-http Build Commands:
        \\
        \\📦 Library:
        \\  install                    Build and install the library
        \\
        \\🎯 Examples:
        \\  run-basic                  Run multi-mode example server
        \\  run-basic-mode             Run example server in basic mode
        \\  run-secure-mode            Run example server in secure mode
        \\  run-dev-mode               Run example server in development mode
        \\
        \\🧪 Testing:
        \\  test                       Run core library unit tests
        \\  test-integration           Run integration tests
        \\  test-quick                 Run quick tests (core + integration)
        \\  test-all                   Run ALL tests (comprehensive)
        \\  test-coverage              Run tests with coverage analysis
        \\
        \\🔧 Module Tests:
        \\  test-request               Test HTTP request module
        \\  test-response              Test HTTP response module
        \\  test-context               Test context module
        \\  test-router                Test router module
        \\  test-buffer                Test buffer module
        \\  test-config                Test configuration module
        \\  test-security              Test security and timeout protection
        \\  test-url                   Test URL encoding/decoding module
        \\
        \\💡 Usage Examples:
        \\  zig build run-basic -- --mode=secure
        \\  zig build test-all
        \\  zig build help
        \\
    }).step);
}
