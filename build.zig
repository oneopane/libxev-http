const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // libxev dependency
    const libxev_dep = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    // Library module
    const lib = b.addStaticLibrary(.{
        .name = "libxev-http",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("xev", libxev_dep.module("xev"));
    b.installArtifact(lib);

    // Examples
    const basic_example = b.addExecutable(.{
        .name = "basic-server",
        .root_source_file = b.path("examples/basic_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    basic_example.root_module.addImport("xev", libxev_dep.module("xev"));
    basic_example.root_module.addImport("libxev-http", lib.root_module);
    b.installArtifact(basic_example);

    // Run steps for examples
    const run_basic = b.addRunArtifact(basic_example);
    run_basic.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_basic.addArgs(args);
    }
    const run_basic_step = b.step("run-basic", "Run the basic HTTP server example");
    run_basic_step.dependOn(&run_basic.step);

    // Main library tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
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
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Individual module tests
    const request_tests = b.addTest(.{
        .root_source_file = b.path("src/request.zig"),
        .target = target,
        .optimize = optimize,
    });
    request_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const response_tests = b.addTest(.{
        .root_source_file = b.path("src/response.zig"),
        .target = target,
        .optimize = optimize,
    });
    response_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const context_tests = b.addTest(.{
        .root_source_file = b.path("src/context.zig"),
        .target = target,
        .optimize = optimize,
    });
    context_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const router_tests = b.addTest(.{
        .root_source_file = b.path("src/router.zig"),
        .target = target,
        .optimize = optimize,
    });
    router_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const buffer_tests = b.addTest(.{
        .root_source_file = b.path("src/buffer.zig"),
        .target = target,
        .optimize = optimize,
    });
    buffer_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    const config_tests = b.addTest(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config_tests.root_module.addImport("xev", libxev_dep.module("xev"));

    // Run individual module tests
    const run_request_tests = b.addRunArtifact(request_tests);
    const run_response_tests = b.addRunArtifact(response_tests);
    const run_context_tests = b.addRunArtifact(context_tests);
    const run_router_tests = b.addRunArtifact(router_tests);
    const run_buffer_tests = b.addRunArtifact(buffer_tests);
    const run_config_tests = b.addRunArtifact(config_tests);

    // Individual test steps
    const request_test_step = b.step("test-request", "Run request module tests");
    request_test_step.dependOn(&run_request_tests.step);

    const response_test_step = b.step("test-response", "Run response module tests");
    response_test_step.dependOn(&run_response_tests.step);

    const context_test_step = b.step("test-context", "Run context module tests");
    context_test_step.dependOn(&run_context_tests.step);

    const router_test_step = b.step("test-router", "Run router module tests");
    router_test_step.dependOn(&run_router_tests.step);

    const buffer_test_step = b.step("test-buffer", "Run buffer module tests");
    buffer_test_step.dependOn(&run_buffer_tests.step);

    const config_test_step = b.step("test-config", "Run config module tests");
    config_test_step.dependOn(&run_config_tests.step);

    // Comprehensive test suite - runs ALL tests
    const test_all_step = b.step("test-all", "🧪 Run ALL tests (unit + integration + modules)");
    test_all_step.dependOn(&run_lib_unit_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);
    test_all_step.dependOn(&run_request_tests.step);
    test_all_step.dependOn(&run_response_tests.step);
    test_all_step.dependOn(&run_context_tests.step);
    test_all_step.dependOn(&run_router_tests.step);
    test_all_step.dependOn(&run_buffer_tests.step);
    test_all_step.dependOn(&run_config_tests.step);

    // Coverage test step (verbose output)
    const test_coverage_step = b.step("test-coverage", "📊 Run all tests with coverage analysis");
    test_coverage_step.dependOn(test_all_step);

    // Quick test step (only core functionality)
    const test_quick_step = b.step("test-quick", "⚡ Run quick tests (lib + integration only)");
    test_quick_step.dependOn(&run_lib_unit_tests.step);
    test_quick_step.dependOn(&run_integration_tests.step);
}
