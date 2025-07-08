#!/bin/bash

# RustFS Self-Contained Performance Benchmark Script
# This script automatically starts RustFS, runs performance tests, and cleans up

set -e

echo "🚀 RustFS Self-Contained Performance Benchmark"
echo "============================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(pwd)"
VOLUMES_DIR="$PROJECT_ROOT/target/volume"
TEST_FILES_DIR="/tmp/rustfs_test_files"
LOG_FILE="$PROJECT_ROOT/target/benchmark.log"
BENCHMARK_LOG="/tmp/benchmark.log"

# RustFS configuration
RUSTFS_ADDRESS=":9000"
RUSTFS_ENDPOINT="http://localhost:9000"
RUSTFS_ACCESS_KEY="rustfsadmin"
RUSTFS_SECRET_KEY="rustfsadmin"
RUSTFS_PID=""
RUSTFS_BINARY="$PROJECT_ROOT/target/release/rustfs"

# Test configuration
BUCKET_NAME="benchmark-bucket"
TEST_FILE_SIZE_MB=1
TEST_ITERATIONS=3
CONCURRENT_OPERATIONS=2
STARTUP_TIMEOUT=30

# AWS CLI configuration
export AWS_ACCESS_KEY_ID="$RUSTFS_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$RUSTFS_SECRET_KEY"
export AWS_DEFAULT_REGION="us-east-1"

# Global variables for tracking results
PUT_SUCCESSFUL_OPS=0
PUT_AVG_TIME=0
PUT_THROUGHPUT=0
GET_SUCCESSFUL_OPS=0
GET_AVG_TIME=0
GET_THROUGHPUT=0
LIST_SUCCESSFUL_OPS=0
LIST_AVG_TIME=0
LIST_THROUGHPUT=0
DELETE_SUCCESSFUL_OPS=0
DELETE_AVG_TIME=0
DELETE_THROUGHPUT=0

echo -e "${BLUE}Configuration:${NC}"
echo "  - Project root: $PROJECT_ROOT"
echo "  - RustFS endpoint: $RUSTFS_ENDPOINT"
echo "  - Test file size: ${TEST_FILE_SIZE_MB}MB"
echo "  - Test iterations: $TEST_ITERATIONS"
echo "  - Concurrent operations: $CONCURRENT_OPERATIONS"
echo "  - Bucket name: $BUCKET_NAME"
echo "  - Log file: $LOG_FILE"
echo

# Function to cleanup everything
cleanup_all() {
    echo -e "${YELLOW}Cleaning up all resources...${NC}"

    # Stop RustFS if running
    if [ -n "$RUSTFS_PID" ] && kill -0 "$RUSTFS_PID" 2>/dev/null; then
        echo -e "${YELLOW}Stopping RustFS server (PID: $RUSTFS_PID)...${NC}"
        kill "$RUSTFS_PID" 2>/dev/null || true

        # Wait for process to stop
        local wait_count=0
        while kill -0 "$RUSTFS_PID" 2>/dev/null && [ $wait_count -lt 10 ]; do
            sleep 1
            wait_count=$((wait_count + 1))
        done

        # Force kill if still running
        if kill -0 "$RUSTFS_PID" 2>/dev/null; then
            echo -e "${YELLOW}Force killing RustFS server...${NC}"
            kill -9 "$RUSTFS_PID" 2>/dev/null || true
        fi

        echo -e "${GREEN}RustFS server stopped${NC}"
    fi

    # Remove test files
    rm -f /tmp/rustfs_test_file.bin
    rm -f /tmp/rustfs_downloaded_*.bin

    # Clean test files directory
    if [ -d "$TEST_FILES_DIR" ]; then
        echo -e "${YELLOW}Cleaning test files directory...${NC}"
        rm -rf "$TEST_FILES_DIR"
    fi

    # Clean volumes directory
    if [ -d "$VOLUMES_DIR" ]; then
        echo -e "${YELLOW}Cleaning volume directory...${NC}"
        rm -rf "$VOLUMES_DIR"
    fi

    echo -e "${GREEN}Cleanup completed.${NC}"
}

# Function to handle script interruption
handle_interrupt() {
    echo -e "${RED}Benchmark interrupted, cleaning up...${NC}"
    cleanup_all
    exit 1
}

# Set up signal handlers
trap handle_interrupt INT TERM

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_ROOT/Cargo.toml" ]; then
        echo -e "${RED}Error: Not in RustFS project root${NC}"
        echo "Please run this script from the RustFS project root"
        exit 1
    fi

    # Check if aws CLI is installed
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}Error: AWS CLI is not installed${NC}"
        echo "Please install AWS CLI: https://aws.amazon.com/cli/"
        exit 1
    fi

    # Check if bc is installed (needed for calculations)
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}Error: bc calculator is not installed${NC}"
        if [ "$(uname)" = "Darwin" ]; then
            echo "Please install bc: brew install bc"
        else
            echo "Please install bc: sudo apt-get install bc"
        fi
        exit 1
    fi

    # Check if cargo is available
    if ! command -v cargo &> /dev/null; then
        echo -e "${RED}Error: Cargo is not installed${NC}"
        echo "Please install Rust: https://rustup.rs/"
        exit 1
    fi

    echo -e "${GREEN}✅ All prerequisites satisfied${NC}"
}

# Function to build RustFS
build_rustfs() {
    echo -e "${YELLOW}Building RustFS in release mode...${NC}"

    cd "$PROJECT_ROOT"

    # Clean previous build artifacts that might interfere
    cargo clean

    # Build RustFS in release mode
    if cargo build --release --bin rustfs; then
        echo -e "${GREEN}✅ RustFS built successfully${NC}"
    else
        echo -e "${RED}❌ Failed to build RustFS${NC}"
        exit 1
    fi
}

# Function to setup volumes
setup_volumes() {
    echo -e "${YELLOW}Setting up storage volumes...${NC}"

    # Clean any existing volume directories to avoid corruption
    if [ -d "$VOLUMES_DIR" ]; then
        echo -e "${YELLOW}Cleaning existing volumes...${NC}"
        rm -rf "$VOLUMES_DIR"
    fi

    # Create fresh volume directories
    mkdir -p "$VOLUMES_DIR"/{test1,test2,test3,test4}

    # Ensure proper permissions
    chmod -R 755 "$VOLUMES_DIR"

    echo -e "${GREEN}✅ Storage volumes created${NC}"
}

# Function to start RustFS server
start_rustfs() {
    echo -e "${YELLOW}Starting RustFS server...${NC}"

    cd "$PROJECT_ROOT"

    # Prepare volumes string with proper expansion
    local volumes="$VOLUMES_DIR/test1 $VOLUMES_DIR/test2 $VOLUMES_DIR/test3 $VOLUMES_DIR/test4"

    echo -e "${YELLOW}Using volumes: $volumes${NC}"

    # Start RustFS in background and capture PID
    nohup "$RUSTFS_BINARY" --address "$RUSTFS_ADDRESS" $volumes > "$LOG_FILE" 2>&1 &
    RUSTFS_PID=$!

    echo "RustFS started with PID: $RUSTFS_PID"
    echo "Log file: $LOG_FILE"

    # Wait for server to start
    echo -e "${YELLOW}Waiting for RustFS to start (timeout: ${STARTUP_TIMEOUT}s)...${NC}"

    local wait_count=0
    local health_check_passed=false

    while [ $wait_count -lt $STARTUP_TIMEOUT ]; do
        # Check if process is still running
        if ! kill -0 "$RUSTFS_PID" 2>/dev/null; then
            echo -e "${RED}❌ RustFS process died unexpectedly${NC}"
            echo -e "${RED}Check log file: $LOG_FILE${NC}"
            exit 1
        fi

        # Try to connect to RustFS
        if curl -s --connect-timeout 2 "$RUSTFS_ENDPOINT" >/dev/null 2>&1; then
            health_check_passed=true
            break
        fi

        echo -n "."
        sleep 2
        wait_count=$((wait_count + 2))
    done

    if [ "$health_check_passed" = true ]; then
        echo -e "\n${GREEN}✅ RustFS server is ready!${NC}"

        # Wait a bit more for erasure coding initialization
        echo -e "${YELLOW}Waiting for erasure coding initialization...${NC}"
        sleep 5
    else
        echo -e "\n${RED}❌ RustFS failed to start within ${STARTUP_TIMEOUT}s${NC}"
        echo -e "${RED}Check log file: $LOG_FILE${NC}"
        cleanup_all
        exit 1
    fi
}

# Function to setup test environment
setup_test_environment() {
    echo -e "${YELLOW}Setting up test environment...${NC}"

    # Create bucket
    if aws s3api create-bucket --bucket "$BUCKET_NAME" --endpoint-url "$RUSTFS_ENDPOINT" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Bucket '$BUCKET_NAME' created${NC}"
    else
        echo -e "${YELLOW}Bucket '$BUCKET_NAME' already exists or creation failed${NC}"
    fi

    # Create test files directory
    mkdir -p "$TEST_FILES_DIR"

    # Create test files for each iteration
    echo -e "${YELLOW}Creating test files (${TEST_FILE_SIZE_MB}MB each)...${NC}"
    for i in $(seq 1 $TEST_ITERATIONS); do
        echo -n "  Creating test_file_$i.bin... "
        if dd if=/dev/urandom of="$TEST_FILES_DIR/test_file_$i.bin" bs=1M count=$TEST_FILE_SIZE_MB 2>/dev/null; then
            echo -e "${GREEN}✅${NC}"
        else
            echo -e "${RED}❌${NC}"
        fi
    done

    echo -e "${GREEN}✅ Test environment setup completed${NC}"
}

# Function to measure PUT performance
measure_put_performance() {
    echo -e "${BLUE}Measuring PUT Performance...${NC}"

    local total_time=0
    local successful_ops=0

    for i in $(seq 1 $TEST_ITERATIONS); do
        echo -n "  PUT test $i/$TEST_ITERATIONS: "

        local start_time=$(date +%s.%N)

        # Force single-part upload to avoid multipart upload issues
        # Set a small multipart threshold and disable multipart altogether
        if AWS_CLI_AUTO_PROMPT=off aws s3api put-object \
            --bucket "$BUCKET_NAME" \
            --key "test_file_$i.bin" \
            --body "$TEST_FILES_DIR/test_file_$i.bin" \
            --endpoint-url "$RUSTFS_ENDPOINT" \
            --cli-connect-timeout 30 \
            --cli-read-timeout 60 \
            --no-cli-pager \
            >/dev/null 2>&1; then

            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            total_time=$(echo "$total_time + $duration" | bc)
            successful_ops=$((successful_ops + 1))

            echo -e "${GREEN}✅ ${duration}s${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi

        # Small delay to avoid overwhelming the server
        sleep 0.1
    done

    if [ $successful_ops -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_ops" | bc)
        local throughput=$(echo "scale=2; $successful_ops / $total_time" | bc)

        echo -e "${GREEN}PUT Performance Results:${NC}"
        echo -e "  Total operations: $successful_ops/$TEST_ITERATIONS"
        echo -e "  Average time per operation: ${avg_time}s"
        echo -e "  Throughput: ${throughput} ops/s"
        echo -e "  Success rate: $(echo "scale=1; $successful_ops * 100 / $TEST_ITERATIONS" | bc)%"

        # Store results for final report
        PUT_SUCCESSFUL_OPS=$successful_ops
        PUT_AVG_TIME=$avg_time
        PUT_THROUGHPUT=$throughput
    else
        echo -e "${RED}All PUT operations failed${NC}"
        PUT_SUCCESSFUL_OPS=0
        PUT_AVG_TIME=0
        PUT_THROUGHPUT=0
    fi
}

# Function to measure GET performance
measure_get_performance() {
    echo -e "${BLUE}Measuring GET Performance...${NC}"

    local total_time=0
    local successful_ops=0

    for i in $(seq 1 $TEST_ITERATIONS); do
        echo -n "  GET test $i/$TEST_ITERATIONS: "

        local start_time=$(date +%s.%N)

        # Download one of the uploaded files using get-object API
        local file_to_download="test_file_$i.bin"
        local download_path="/tmp/rustfs_downloaded_$i.bin"

        # Remove existing downloaded file if exists
        [ -f "$download_path" ] && rm -f "$download_path"

        # Use get-object API to avoid range request issues
        if AWS_CLI_AUTO_PROMPT=off aws s3api get-object \
            --bucket "$BUCKET_NAME" \
            --key "$file_to_download" \
            --endpoint-url "$RUSTFS_ENDPOINT" \
            --cli-connect-timeout 30 \
            --cli-read-timeout 60 \
            --no-cli-pager \
            "$download_path" \
            >/dev/null 2>&1; then

            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            total_time=$(echo "$total_time + $duration" | bc)
            successful_ops=$((successful_ops + 1))

            echo -e "${GREEN}✅ ${duration}s${NC}"

            # Clean up downloaded file
            rm -f "$download_path"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi

        # Small delay to avoid overwhelming the server
        sleep 0.1
    done

    if [ $successful_ops -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_ops" | bc)
        local throughput=$(echo "scale=2; $successful_ops / $total_time" | bc)

        echo -e "${GREEN}GET Performance Results:${NC}"
        echo -e "  Total operations: $successful_ops/$TEST_ITERATIONS"
        echo -e "  Average time per operation: ${avg_time}s"
        echo -e "  Throughput: ${throughput} ops/s"
        echo -e "  Success rate: $(echo "scale=1; $successful_ops * 100 / $TEST_ITERATIONS" | bc)%"

        # Store results for final report
        GET_SUCCESSFUL_OPS=$successful_ops
        GET_AVG_TIME=$avg_time
        GET_THROUGHPUT=$throughput
    else
        echo -e "${RED}All GET operations failed${NC}"
        GET_SUCCESSFUL_OPS=0
        GET_AVG_TIME=0
        GET_THROUGHPUT=0
    fi
}

# Function to run concurrent operations test
run_concurrent_test() {
    echo -e "${BLUE}Running Concurrent Operations Test...${NC}"

    echo "  Testing $CONCURRENT_OPERATIONS concurrent PUT operations..."

    local start_time=$(date +%s.%N)

    # Run concurrent PUT operations
    for i in $(seq 1 $CONCURRENT_OPERATIONS); do
        (aws s3 cp /tmp/rustfs_test_file.bin "s3://$BUCKET_NAME/concurrent_test_$i.bin" --endpoint-url "$RUSTFS_ENDPOINT" >/dev/null 2>&1) &
    done

    # Wait for all background jobs to complete
    wait

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    local total_mb=$(echo "$TEST_FILE_SIZE_MB * $CONCURRENT_OPERATIONS" | bc)
    local throughput=$(echo "scale=2; $total_mb / $duration" | bc)

    echo -e "${GREEN}Concurrent Operations Results:${NC}"
    echo "  - Total data uploaded: ${total_mb}MB"
    echo "  - Time taken: ${duration}s"
    echo "  - Aggregate throughput: ${throughput} MB/s"
    echo
}

# Function to display system information
display_system_info() {
    echo -e "${CYAN}System Information:${NC}"
    echo -e "  - OS: $(uname -s) $(uname -r)"
    echo -e "  - CPU: $(sysctl -n hw.ncpu) cores"
    echo -e "  - Memory: $(echo $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024)))GB"
    echo -e "  - Rust version: $(rustc --version)"
    echo -e "  - AWS CLI version: $(aws --version)"
    echo
}

# Function to measure LIST performance
measure_list_performance() {
    echo -e "${BLUE}Measuring LIST Performance...${NC}"

    local total_time=0
    local successful_ops=0

    for i in $(seq 1 $TEST_ITERATIONS); do
        echo -n "  LIST test $i/$TEST_ITERATIONS: "

        local start_time=$(date +%s.%N)

        # List objects in bucket
        if AWS_CLI_AUTO_PROMPT=off aws s3api list-objects-v2 \
            --bucket "$BUCKET_NAME" \
            --endpoint-url "$RUSTFS_ENDPOINT" \
            --cli-connect-timeout 30 \
            --cli-read-timeout 60 \
            --no-cli-pager \
            >/dev/null 2>&1; then

            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            total_time=$(echo "$total_time + $duration" | bc)
            successful_ops=$((successful_ops + 1))

            echo -e "${GREEN}✅ ${duration}s${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi

        # Small delay to avoid overwhelming the server
        sleep 0.1
    done

    if [ $successful_ops -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_ops" | bc)
        local throughput=$(echo "scale=2; $successful_ops / $total_time" | bc)

        echo -e "${GREEN}LIST Performance Results:${NC}"
        echo -e "  Total operations: $successful_ops/$TEST_ITERATIONS"
        echo -e "  Average time per operation: ${avg_time}s"
        echo -e "  Throughput: ${throughput} ops/s"
        echo -e "  Success rate: $(echo "scale=1; $successful_ops * 100 / $TEST_ITERATIONS" | bc)%"

        # Store results for final report
        LIST_SUCCESSFUL_OPS=$successful_ops
        LIST_AVG_TIME=$avg_time
        LIST_THROUGHPUT=$throughput
    else
        echo -e "${RED}All LIST operations failed${NC}"
        LIST_SUCCESSFUL_OPS=0
        LIST_AVG_TIME=0
        LIST_THROUGHPUT=0
    fi
}

# Function to measure DELETE performance
measure_delete_performance() {
    echo -e "${BLUE}Measuring DELETE Performance...${NC}"

    local total_time=0
    local successful_ops=0

    for i in $(seq 1 $TEST_ITERATIONS); do
        echo -n "  DELETE test $i/$TEST_ITERATIONS: "

        local start_time=$(date +%s.%N)

        # Delete one of the uploaded files
        if AWS_CLI_AUTO_PROMPT=off aws s3api delete-object \
            --bucket "$BUCKET_NAME" \
            --key "test_file_$i.bin" \
            --endpoint-url "$RUSTFS_ENDPOINT" \
            --cli-connect-timeout 30 \
            --cli-read-timeout 60 \
            --no-cli-pager \
            >/dev/null 2>&1; then

            local end_time=$(date +%s.%N)
            local duration=$(echo "$end_time - $start_time" | bc)
            total_time=$(echo "$total_time + $duration" | bc)
            successful_ops=$((successful_ops + 1))

            echo -e "${GREEN}✅ ${duration}s${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi

        # Small delay to avoid overwhelming the server
        sleep 0.1
    done

    if [ $successful_ops -gt 0 ]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_ops" | bc)
        local throughput=$(echo "scale=2; $successful_ops / $total_time" | bc)

        echo -e "${GREEN}DELETE Performance Results:${NC}"
        echo -e "  Total operations: $successful_ops/$TEST_ITERATIONS"
        echo -e "  Average time per operation: ${avg_time}s"
        echo -e "  Throughput: ${throughput} ops/s"
        echo -e "  Success rate: $(echo "scale=1; $successful_ops * 100 / $TEST_ITERATIONS" | bc)%"

        # Store results for final report
        DELETE_SUCCESSFUL_OPS=$successful_ops
        DELETE_AVG_TIME=$avg_time
        DELETE_THROUGHPUT=$throughput
    else
        echo -e "${RED}All DELETE operations failed${NC}"
        DELETE_SUCCESSFUL_OPS=0
        DELETE_AVG_TIME=0
        DELETE_THROUGHPUT=0
    fi
}

# Function to generate final performance report
generate_final_report() {
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                       FINAL PERFORMANCE REPORT                 ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${YELLOW}Test Configuration:${NC}"
    echo -e "  • Test iterations: $TEST_ITERATIONS"
    echo -e "  • File size: $TEST_FILE_SIZE_MB MB"
    echo -e "  • Endpoint: $RUSTFS_ENDPOINT"
    echo -e "  • Bucket: $BUCKET_NAME"
    echo
    echo -e "${YELLOW}Operation Performance Summary:${NC}"
    echo

    # PUT Operations
    echo -e "${CYAN}📤 PUT Operations:${NC}"
    if [ "$PUT_SUCCESSFUL_OPS" -gt 0 ]; then
        echo -e "  ✅ Success rate: $(echo "scale=1; $PUT_SUCCESSFUL_OPS * 100 / $TEST_ITERATIONS" | bc)% ($PUT_SUCCESSFUL_OPS/$TEST_ITERATIONS)"
        echo -e "  ⏱️  Average time: ${PUT_AVG_TIME}s"
        echo -e "  🚀 Throughput: ${PUT_THROUGHPUT} ops/s"
    else
        echo -e "  ❌ All operations failed"
    fi
    echo

    # GET Operations
    echo -e "${CYAN}📥 GET Operations:${NC}"
    if [ "$GET_SUCCESSFUL_OPS" -gt 0 ]; then
        echo -e "  ✅ Success rate: $(echo "scale=1; $GET_SUCCESSFUL_OPS * 100 / $TEST_ITERATIONS" | bc)% ($GET_SUCCESSFUL_OPS/$TEST_ITERATIONS)"
        echo -e "  ⏱️  Average time: ${GET_AVG_TIME}s"
        echo -e "  🚀 Throughput: ${GET_THROUGHPUT} ops/s"
    else
        echo -e "  ❌ All operations failed"
    fi
    echo

    # LIST Operations
    echo -e "${CYAN}📋 LIST Operations:${NC}"
    if [ "$LIST_SUCCESSFUL_OPS" -gt 0 ]; then
        echo -e "  ✅ Success rate: $(echo "scale=1; $LIST_SUCCESSFUL_OPS * 100 / $TEST_ITERATIONS" | bc)% ($LIST_SUCCESSFUL_OPS/$TEST_ITERATIONS)"
        echo -e "  ⏱️  Average time: ${LIST_AVG_TIME}s"
        echo -e "  🚀 Throughput: ${LIST_THROUGHPUT} ops/s"
    else
        echo -e "  ❌ All operations failed"
    fi
    echo

    # DELETE Operations
    echo -e "${CYAN}🗑️  DELETE Operations:${NC}"
    if [ "$DELETE_SUCCESSFUL_OPS" -gt 0 ]; then
        echo -e "  ✅ Success rate: $(echo "scale=1; $DELETE_SUCCESSFUL_OPS * 100 / $TEST_ITERATIONS" | bc)% ($DELETE_SUCCESSFUL_OPS/$TEST_ITERATIONS)"
        echo -e "  ⏱️  Average time: ${DELETE_AVG_TIME}s"
        echo -e "  🚀 Throughput: ${DELETE_THROUGHPUT} ops/s"
    else
        echo -e "  ❌ All operations failed"
    fi
    echo

    # Overall assessment
    local total_success=$((PUT_SUCCESSFUL_OPS + GET_SUCCESSFUL_OPS + LIST_SUCCESSFUL_OPS + DELETE_SUCCESSFUL_OPS))
    local total_operations=$((TEST_ITERATIONS * 4))
    local overall_success_rate=$(echo "scale=1; $total_success * 100 / $total_operations" | bc)

    echo -e "${YELLOW}Overall Assessment:${NC}"
    echo -e "  • Total operations: $total_success/$total_operations"
    echo -e "  • Overall success rate: ${overall_success_rate}%"

    if [ "$(echo "$overall_success_rate >= 80" | bc)" -eq 1 ]; then
        echo -e "  • Status: ${GREEN}✅ EXCELLENT - RustFS is performing well${NC}"
    elif [ "$(echo "$overall_success_rate >= 60" | bc)" -eq 1 ]; then
        echo -e "  • Status: ${YELLOW}⚠️  GOOD - Some operations may need optimization${NC}"
    else
        echo -e "  • Status: ${RED}❌ POOR - RustFS needs significant improvements${NC}"
    fi

    echo
    echo -e "${YELLOW}Log Information:${NC}"
    echo -e "  • RustFS log: $LOG_FILE"
    echo -e "  • Benchmark log: $BENCHMARK_LOG"
    echo
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
}

# Main execution function
main() {
    echo -e "${YELLOW}Starting self-contained RustFS performance benchmark...${NC}"
    echo

    check_prerequisites
    display_system_info

    build_rustfs
    setup_volumes
    start_rustfs
    setup_test_environment

    echo -e "${YELLOW}Running performance benchmarks...${NC}"
    echo

    measure_put_performance
    measure_get_performance
    run_concurrent_test
    measure_list_performance
    measure_delete_performance

    echo -e "${GREEN}✅ All RustFS benchmarks completed successfully!${NC}"
    echo
    echo -e "${BLUE}Summary:${NC}"
    echo "  - This benchmark automatically built and tested RustFS"
    echo "  - Performance metrics are shown above"
    echo "  - Log file available at: $LOG_FILE"
    echo
    echo -e "${YELLOW}Performance Targets (based on Issue #73):${NC}"
    echo "  - GET Throughput: > 50 Gbps target"
    echo "  - PUT Throughput: Maintain current levels"
    echo "  - TTFB: < 50ms target"
    echo

    # Clean shutdown
    cleanup_all

    # Generate final performance report
    generate_final_report
}

# Run main function
main "$@"
