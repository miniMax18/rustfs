#!/bin/bash

# RustFS Performance Optimization Validation Script
# This script validates that all optimizations are working correctly

set -e

echo "🔍 RustFS Performance Optimization Validation"
echo "============================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VALIDATION_PASSED=0
VALIDATION_FAILED=0

# Function to log validation steps
log_validation() {
    local status=$1
    local message=$2

    if [ "$status" = "PASS" ]; then
        echo -e "  ✅ ${GREEN}PASS${NC}: $message"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    elif [ "$status" = "FAIL" ]; then
        echo -e "  ❌ ${RED}FAIL${NC}: $message"
        VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
    elif [ "$status" = "INFO" ]; then
        echo -e "  ℹ️  ${BLUE}INFO${NC}: $message"
    else
        echo -e "  ⚠️  ${YELLOW}WARN${NC}: $message"
    fi
}

# Function to validate buffer size optimizations
validate_buffer_optimizations() {
    echo -e "${BLUE}1. Validating Buffer Size Optimizations...${NC}"

    # Check if DEFAULT_READ_BUFFER_SIZE is 8MB
    if grep -q "DEFAULT_READ_BUFFER_SIZE: usize = 8 \* 1024 \* 1024" crates/ecstore/src/set_disk.rs; then
        log_validation "PASS" "DEFAULT_READ_BUFFER_SIZE increased to 8MB"
    else
        log_validation "FAIL" "DEFAULT_READ_BUFFER_SIZE not set to 8MB"
    fi

    # Check if DEFAULT_WRITE_BUFFER_SIZE is added
    if grep -q "DEFAULT_WRITE_BUFFER_SIZE: usize = 8 \* 1024 \* 1024" crates/ecstore/src/set_disk.rs; then
        log_validation "PASS" "DEFAULT_WRITE_BUFFER_SIZE added with 8MB"
    else
        log_validation "FAIL" "DEFAULT_WRITE_BUFFER_SIZE not found"
    fi

    # Check for optimized buffer allocation in decode.rs
    if grep -q "shard_size\.max(64 \* 1024)" crates/ecstore/src/erasure_coding/decode.rs; then
        log_validation "PASS" "Optimized buffer allocation in parallel reader"
    else
        log_validation "FAIL" "Buffer allocation optimization not found in decode.rs"
    fi

    echo
}

# Function to validate async I/O improvements
validate_async_io_improvements() {
    echo -e "${BLUE}2. Validating Async I/O Improvements...${NC}"

    # Check that spawn_blocking is removed from write_all_internal
    if ! grep -q "spawn_blocking" crates/ecstore/src/disk/local.rs; then
        log_validation "PASS" "spawn_blocking removed from local.rs"
    else
        log_validation "FAIL" "spawn_blocking still present in local.rs"
    fi

    # Check that block_in_place is removed from fs.rs
    if ! grep -q "block_in_place" crates/ecstore/src/disk/fs.rs; then
        log_validation "PASS" "block_in_place removed from fs.rs"
    else
        log_validation "FAIL" "block_in_place still present in fs.rs"
    fi

    # Check for async sync operation
    if grep -q "f\.sync_all()\.await" crates/ecstore/src/disk/local.rs; then
        log_validation "PASS" "Async sync operation added"
    else
        log_validation "WARN" "Async sync operation not found (optional)"
    fi

    echo
}

# Function to validate erasure coding optimizations
validate_erasure_coding_optimizations() {
    echo -e "${BLUE}3. Validating Erasure Coding Optimizations...${NC}"

    # Check for Arc-based shared caching
    if grep -q "std::sync::Arc<std::sync::RwLock" crates/ecstore/src/erasure_coding/erasure.rs; then
        log_validation "PASS" "Arc-based shared caching implemented"
    else
        log_validation "FAIL" "Arc-based shared caching not found"
    fi

    # Check for Arc import
    if grep -q "use std::sync::Arc;" crates/ecstore/src/erasure_coding/erasure.rs; then
        log_validation "PASS" "Arc import added"
    else
        log_validation "FAIL" "Arc import not found"
    fi

    # Check for shared cache in clone implementation
    if grep -q "Arc::clone" crates/ecstore/src/erasure_coding/erasure.rs; then
        log_validation "PASS" "Shared cache in clone implementation"
    else
        log_validation "FAIL" "Shared cache not used in clone implementation"
    fi

    echo
}

# Function to validate connection pool configuration
validate_connection_pool_config() {
    echo -e "${BLUE}4. Validating Connection Pool Configuration...${NC}"

    # Check for MAX_CONCURRENT_READS
    if grep -q "MAX_CONCURRENT_READS: usize = 64" crates/ecstore/src/set_disk.rs; then
        log_validation "PASS" "MAX_CONCURRENT_READS configured"
    else
        log_validation "FAIL" "MAX_CONCURRENT_READS not found"
    fi

    # Check for MAX_CONCURRENT_WRITES
    if grep -q "MAX_CONCURRENT_WRITES: usize = 32" crates/ecstore/src/set_disk.rs; then
        log_validation "PASS" "MAX_CONCURRENT_WRITES configured"
    else
        log_validation "FAIL" "MAX_CONCURRENT_WRITES not found"
    fi

    # Check for IO_TIMEOUT_SECONDS
    if grep -q "IO_TIMEOUT_SECONDS: u64 = 30" crates/ecstore/src/set_disk.rs; then
        log_validation "PASS" "IO_TIMEOUT_SECONDS configured"
    else
        log_validation "FAIL" "IO_TIMEOUT_SECONDS not found"
    fi

    echo
}

# Function to validate benchmark scripts
validate_benchmark_scripts() {
    echo -e "${BLUE}5. Validating Benchmark Scripts...${NC}"

    # Check if benchmark.sh exists and is executable
    if [ -x "scripts/benchmark.sh" ]; then
        log_validation "PASS" "General benchmark script exists and is executable"
    else
        log_validation "FAIL" "General benchmark script missing or not executable"
    fi

    # Check if rustfs_benchmark.sh exists and is executable
    if [ -x "scripts/rustfs_benchmark.sh" ]; then
        log_validation "PASS" "RustFS-specific benchmark script exists and is executable"
    else
        log_validation "FAIL" "RustFS-specific benchmark script missing or not executable"
    fi

    # Check if PERFORMANCE_OPTIMIZATIONS.md exists
    if [ -f "PERFORMANCE_OPTIMIZATIONS.md" ]; then
        log_validation "PASS" "Performance optimization documentation exists"
    else
        log_validation "FAIL" "Performance optimization documentation missing"
    fi

    echo
}

# Function to validate code compilation
validate_compilation() {
    echo -e "${BLUE}6. Validating Code Compilation...${NC}"

    echo "  Running cargo check..."
    if cargo check --all-targets >/dev/null 2>&1; then
        log_validation "PASS" "Code compiles successfully"
    else
        log_validation "FAIL" "Compilation errors found"
        return
    fi

    echo "  Running cargo clippy..."
    if cargo clippy --all-targets --all-features -- -D warnings >/dev/null 2>&1; then
        log_validation "PASS" "Clippy checks pass"
    else
        log_validation "FAIL" "Clippy warnings or errors found"
    fi

    echo
}

# Function to validate performance expectations
validate_performance_expectations() {
    echo -e "${BLUE}7. Validating Performance Expectations...${NC}"

    log_validation "INFO" "Target: >50 Gbps GET throughput (vs current 23 Gbps)"
    log_validation "INFO" "Target: <50ms TTFB (vs current 260ms)"
    log_validation "INFO" "Expected improvement: 2-2.5x throughput, 2.5-5x TTFB"

    echo "  To measure actual improvements:"
    echo "    1. Build release version: cargo build --release"
    echo "    2. Start RustFS server: cargo run --release --bin rustfs -- --address 0.0.0.0:9000"
    echo "    3. Run benchmark: ./scripts/rustfs_benchmark.sh"

    echo
}

# Function to display validation summary
display_summary() {
    echo -e "${BLUE}Validation Summary${NC}"
    echo "================="

    local total_checks=$((VALIDATION_PASSED + VALIDATION_FAILED))

    if [ $VALIDATION_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ All validations passed! ($VALIDATION_PASSED/$total_checks)${NC}"
        echo -e "${GREEN}🚀 Performance optimizations are ready for testing!${NC}"
        return 0
    else
        echo -e "${RED}❌ Some validations failed: $VALIDATION_FAILED/$total_checks${NC}"
        echo -e "${YELLOW}⚠️  Please fix the failed validations before proceeding.${NC}"
        return 1
    fi
}

# Function to show next steps
show_next_steps() {
    echo
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Build the optimized version: cargo build --release"
    echo "2. Start RustFS server: cargo run --release --bin rustfs -- --address 0.0.0.0:9000"
    echo "3. In another terminal, run: ./scripts/rustfs_benchmark.sh"
    echo "4. Compare results with baseline performance from Issue #73"
    echo "5. Fine-tune parameters based on measured results"
    echo
    echo -e "${BLUE}Performance Monitoring:${NC}"
    echo "- Monitor CPU usage during tests"
    echo "- Check memory consumption (expect increase due to larger buffers)"
    echo "- Verify no increase in error rates"
    echo "- Test with various file sizes (1MB, 100MB, 1GB)"
    echo
}

# Main execution
main() {
    echo -e "${YELLOW}Validating all performance optimizations...${NC}"
    echo

    validate_buffer_optimizations
    validate_async_io_improvements
    validate_erasure_coding_optimizations
    validate_connection_pool_config
    validate_benchmark_scripts
    validate_compilation
    validate_performance_expectations

    echo
    display_summary

    if [ $? -eq 0 ]; then
        show_next_steps
        echo -e "${GREEN}🎉 RustFS performance optimizations validation completed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Validation failed. Please address the issues above.${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
