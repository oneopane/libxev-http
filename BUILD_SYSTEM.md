# libxev-http Build System

## Overview

libxev-http provides a comprehensive build system that supports library building, example execution, test running, and various other functions. The build system uses Zig's native build tools and provides rich commands and options.

## 🚀 Quick Start

### View All Available Commands
```bash
zig build help
```

### Build Library
```bash
zig build install
```

### Run Example Server
```bash
# Basic mode
zig build run-basic

# Secure mode
zig build run-basic -- --mode=secure

# Development mode
zig build run-basic -- --mode=dev
```

### Run Tests
```bash
# Quick tests
zig build test-quick

# Complete tests
zig build test-all
```

## 📦 Library Building

### Basic Build
```bash
zig build install
```
Builds and installs the libxev-http static library to `zig-out/lib/`.

### Release Build
```bash
zig build install --release=fast
```
Builds an optimized version of the library.

## 🎯 Examples and Tools

### Multi-Mode Example Server
```bash
# Basic mode (default configuration, port 8080)
zig build run-basic
zig build run-basic-mode

# Secure mode (strict configuration, port 8082)
zig build run-basic -- --mode=secure
zig build run-secure-mode

# Development mode (relaxed configuration, suitable for debugging)
zig build run-basic -- --mode=dev
zig build run-dev-mode
```



## 🧪 Testing System

### Core Tests
```bash
# Core library unit tests
zig build test

# Integration tests
zig build test-integration

# Quick tests (core + integration)
zig build test-quick
```

### Module Tests
```bash
# HTTP request module
zig build test-request

# HTTP response module
zig build test-response

# Context module
zig build test-context

# Router module
zig build test-router

# Buffer module
zig build test-buffer

# Configuration module
zig build test-config

# Security and timeout protection module
zig build test-security
```

### Comprehensive Tests
```bash
# Run all tests
zig build test-all

# Tests with coverage analysis
zig build test-coverage
```

## 🔧 Build Options

### Target Platform
```bash
# Cross-compile to Linux
zig build -Dtarget=x86_64-linux

# Cross-compile to Windows
zig build -Dtarget=x86_64-windows
```

### Optimization Level
```bash
# Debug build (default)
zig build -Doptimize=Debug

# Safe release build
zig build -Doptimize=ReleaseSafe

# Fast release build
zig build -Doptimize=ReleaseFast

# Small release build
zig build -Doptimize=ReleaseSmall
```

## 📊 Build Output

### Directory Structure
```
zig-out/
├── lib/
│   └── libxev-http.a          # Static library
├── bin/
│   └── example-server         # Example server
└── include/                   # Header files (if any)
```

### Build Artifacts
- **libxev-http.a**: Static library file
- **example-server**: Multi-mode example server executable

## 🛠️ Development Workflow

### Daily Development
```bash
# 1. Quick test after code changes
zig build test-quick

# 2. Run example to verify functionality
zig build run-basic -- --mode=dev

# 3. Test specific modules
zig build test-security

# 4. Complete testing
zig build test-all
```

### Release Preparation
```bash
# 1. Complete testing
zig build test-all

# 2. Release build
zig build install --release=fast

# 3. Verify examples
zig build run-basic -- --mode=secure
```

## 🔍 Troubleshooting

### Common Issues

**Build Failures**:
```bash
# Clean cache and rebuild
rm -rf zig-cache zig-out
zig build install
```

**Test Failures**:
```bash
# Run verbose tests
zig build test --verbose

# Run specific module tests
zig build test-security --verbose
```

**Example Server Won't Start**:
```bash
# Check port usage
lsof -i :8080
lsof -i :8082

# Use different mode
zig build run-basic -- --mode=dev
```

### Debug Options
```bash
# Enable verbose output
zig build --verbose

# Show compilation commands
zig build --verbose-cc

# Debug build script
zig build --debug-log
```

## 📚 Build Script Structure

### Main Components
1. **Dependency Management**: libxev dependency configuration
2. **Library Building**: Static library compilation configuration
3. **Example Building**: Example program compilation configuration
4. **Test Configuration**: Various test configurations
5. **Convenience Steps**: Shortcuts and help commands

### Custom Builds
If you need custom build options, you can modify the `build.zig` file:

```zig
// Add custom compilation options
const custom_option = b.option(bool, "custom", "Enable custom feature") orelse false;

// Use in library configuration
if (custom_option) {
    lib.root_module.addCMacro("CUSTOM_FEATURE", "1");
}
```

## 🎯 Best Practices

### During Development
- Use `zig build test-quick` for quick verification
- Use `zig build run-basic -- --mode=dev` for functionality testing
- Regularly run `zig build test-all` to ensure completeness

### Before Deployment
- Run `zig build test-all` to ensure all tests pass
- Use `--release=fast` to build optimized versions
- Verify different modes of example server work properly

### CI/CD
```bash
# Complete CI process
zig build test-all
zig build install --release=fast
```

This build system provides complete support for libxev-http development, testing, and deployment.
