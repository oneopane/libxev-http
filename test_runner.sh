#!/bin/bash

# libxev-http Test Runner
# Comprehensive test suite for the libxev-http framework

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to run a test and track results
run_test() {
    local test_name=$1
    local test_command=$2
    
    print_status $BLUE "🧪 Running $test_name..."
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if eval $test_command > /dev/null 2>&1; then
        print_status $GREEN "✅ $test_name PASSED"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_status $RED "❌ $test_name FAILED"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        
        # Show error details
        print_status $YELLOW "Error details:"
        eval $test_command
    fi
    echo
}

# Function to print test summary
print_summary() {
    echo
    print_status $CYAN "📊 TEST SUMMARY"
    print_status $CYAN "==============="
    echo "Total Tests: $TOTAL_TESTS"
    print_status $GREEN "Passed: $PASSED_TESTS"
    print_status $RED "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_status $GREEN "🎉 ALL TESTS PASSED!"
        exit 0
    else
        print_status $RED "💥 SOME TESTS FAILED!"
        exit 1
    fi
}

# Main test execution
main() {
    print_status $PURPLE "🚀 libxev-http Test Suite"
    print_status $PURPLE "=========================="
    echo
    
    # Check if zig is available
    if ! command -v zig &> /dev/null; then
        print_status $RED "❌ Zig compiler not found!"
        exit 1
    fi
    
    print_status $CYAN "Zig version: $(zig version)"
    echo
    
    # Run individual module tests
    run_test "Request Module Tests" "zig build test-request"
    run_test "Response Module Tests" "zig build test-response"
    run_test "Context Module Tests" "zig build test-context"
    run_test "Router Module Tests" "zig build test-router"
    run_test "Buffer Module Tests" "zig build test-buffer"
    run_test "Config Module Tests" "zig build test-config"
    
    # Run integration tests
    run_test "Integration Tests" "zig build test-integration"
    
    # Run main library tests
    run_test "Library Unit Tests" "zig build test"
    
    # Print final summary
    print_summary
}

# Handle command line arguments
case "${1:-all}" in
    "all")
        main
        ;;
    "quick")
        print_status $PURPLE "⚡ Quick Test Mode"
        print_status $PURPLE "=================="
        echo
        run_test "Library Unit Tests" "zig build test"
        run_test "Integration Tests" "zig build test-integration"
        print_summary
        ;;
    "module")
        if [ -z "$2" ]; then
            print_status $RED "❌ Please specify module name (request, response, context, router, buffer, config)"
            exit 1
        fi
        print_status $PURPLE "🔍 Testing $2 Module"
        print_status $PURPLE "===================="
        echo
        run_test "$2 Module Tests" "zig build test-$2"
        print_summary
        ;;
    "help")
        echo "libxev-http Test Runner"
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  all     - Run all tests (default)"
        echo "  quick   - Run only core tests (lib + integration)"
        echo "  module <name> - Run specific module tests"
        echo "  help    - Show this help message"
        echo
        echo "Available modules: request, response, context, router, buffer, config"
        ;;
    *)
        print_status $RED "❌ Unknown command: $1"
        print_status $YELLOW "Use '$0 help' for usage information"
        exit 1
        ;;
esac
