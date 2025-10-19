#!/bin/bash

# =============================================================================
# Save Flash Loan Tests - Complete Test Suite Runner
# Comprehensive test execution for Save Flash Loans integration
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Timestamp
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

# Directories
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUST_MODULES="$PROJECT_ROOT/rust-modules"
TESTS_DIR="$PROJECT_ROOT/tests"
LOGS_DIR="$PROJECT_ROOT/logs"

# Create logs directory
mkdir -p "$LOGS_DIR"

# Log file
LOG_FILE="$LOGS_DIR/save_flash_loan_tests_$(date +%Y%m%d_%H%M%S).log"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to log with timestamp
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to print header
print_header() {
    local title="$1"
    local width=60
    local padding=$(( (width - ${#title}) / 2 ))
    local line=$(printf '=%.0s' $(seq 1 $width))

    log "${BLUE}$line${NC}"
    log "${BLUE}$(printf '%*s' $((padding + ${#title})) "$title")${NC}"
    log "${BLUE}$line${NC}"
}

# Function to run test and update counters
run_test() {
    local test_name="$1"
    local test_command="$2"
    local description="$3"

    log "\n${CYAN}🧪 Running: $test_name${NC}"
    log "${YELLOW}Description: $description${NC}"
    log "${PURPLE}Command: $test_command${NC}"

    echo "" | tee -a "$LOG_FILE"

    if eval "$test_command" 2>&1 | tee -a "$LOG_FILE"; then
        log "${GREEN}✅ PASSED: $test_name${NC}"
        ((PASSED_TESTS++))
        return 0
    else
        log "${RED}❌ FAILED: $test_name${NC}"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_header "CHECKING PREREQUISITES"

    local all_good=true

    # Check Rust
    if command -v cargo &> /dev/null; then
        log "${GREEN}✅ Cargo found${NC}"
        rust_version=$(cargo --version)
        log "   Version: $rust_version"
    else
        log "${RED}❌ Cargo not found${NC}"
        all_good=false
    fi

    # Check Python
    if command -v python3 &> /dev/null; then
        log "${GREEN}✅ Python3 found${NC}"
        python_version=$(python3 --version)
        log "   Version: $python_version"
    else
        log "${RED}❌ Python3 not found${NC}"
        all_good=false
    fi

    # Check pytest
    if python3 -c "import pytest" &> /dev/null; then
        log "${GREEN}✅ pytest found${NC}"
    else
        log "${RED}❌ pytest not found${NC}"
        log "${YELLOW}Installing pytest...${NC}"
        pip3 install pytest pytest-asyncio &>> "$LOG_FILE"
    fi

    # Check Redis
    if command -v redis-cli &> /dev/null; then
        if redis-cli ping &> /dev/null; then
            log "${GREEN}✅ Redis is running${NC}"
        else
            log "${YELLOW}⚠️ Redis not running - some tests may fail${NC}"
        fi
    else
        log "${YELLOW}⚠️ Redis not found - some tests may fail${NC}"
    fi

    # Check Docker
    if command -v docker &> /dev/null; then
        log "${GREEN}✅ Docker found${NC}"
        if docker ps &> /dev/null; then
            log "${GREEN}✅ Docker daemon running${NC}"
        else
            log "${YELLOW}⚠️ Docker daemon not running${NC}"
        fi
    else
        log "${YELLOW}⚠️ Docker not found${NC}"
    fi

    if ! $all_good; then
        log "${RED}❌ Some prerequisites missing. Please install missing dependencies.${NC}"
        exit 1
    fi

    log "${GREEN}✅ All prerequisites satisfied${NC}"
}

# Function to setup test environment
setup_test_environment() {
    print_header "SETTING UP TEST ENVIRONMENT"

    # Set environment variables for testing
    export SAVE_PROGRAM_ID="SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV"
    export JUPITER_API_URL="https://quote-api.jup.ag/v6"
    export JITO_API_URL="https://mainnet.block-engine.jito.wtf"
    export REDIS_URL="redis://localhost:6379"
    export SOLANA_RPC_URL="https://api.mainnet-beta.solana.com"
    export RUST_LOG="debug"
    export PYTHONPATH="$PROJECT_ROOT:$PYTHONPATH"

    log "${GREEN}✅ Environment variables set${NC}"

    # Build Rust modules
    log "${BLUE}Building Rust modules...${NC}"
    cd "$RUST_MODULES"
    if cargo build --release &>> "$LOG_FILE"; then
        log "${GREEN}✅ Rust modules built successfully${NC}"
    else
        log "${RED}❌ Failed to build Rust modules${NC}"
        return 1
    fi

    cd "$PROJECT_ROOT"

    # Start required services if not running
    log "${BLUE}Checking required services...${NC}"

    # Start Redis if not running
    if ! pgrep -x redis-server > /dev/null; then
        log "${YELLOW}Starting Redis...${NC}"
        if command -v docker &> /dev/null; then
            docker run -d --name redis-test -p 6379:6379 redis:7-alpine &>> "$LOG_FILE"
            sleep 2
        else
            log "${YELLOW}Please start Redis manually: redis-server${NC}"
        fi
    fi

    log "${GREEN}✅ Test environment setup complete${NC}"
}

# Function to run Rust unit tests
run_rust_unit_tests() {
    print_header "RUST UNIT TESTS"

    local test_command="cargo test --release save_flash_loan --lib -- --nocapture"
    local description="Save Flash Loan unit tests with comprehensive mocking"

    cd "$RUST_MODULES"
    if run_test "Rust Unit Tests" "$test_command" "$description"; then
        log "${GREEN}✅ All Rust unit tests passed${NC}"
    else
        log "${RED}❌ Some Rust unit tests failed${NC}"
    fi
    cd "$PROJECT_ROOT"

    ((TOTAL_TESTS++))
}

# Function to run Rust benchmarks
run_rust_benchmarks() {
    print_header "RUST PERFORMANCE BENCHMARKS"

    local test_command="cargo bench --release save_flash_loan_benchmark"
    local description="Save Flash Loan performance benchmarks with Criterion"

    cd "$RUST_MODULES"
    if run_test "Rust Benchmarks" "$test_command" "$description"; then
        log "${GREEN}✅ Performance benchmarks completed${NC}"

        # Extract key metrics from benchmark output
        log "${BLUE}📊 Key Performance Metrics:${NC}"
        if grep -q "save_flash_loan_snipe" "$LOG_FILE"; then
            local avg_time=$(grep "save_flash_loan_snipe" "$LOG_FILE" | tail -1 | grep -o '[0-9.]* ns/iter' | head -1)
            log "   Average execution time: $avg_time"
        fi
    else
        log "${RED}❌ Performance benchmarks failed${NC}"
    fi
    cd "$PROJECT_ROOT"

    ((TOTAL_TESTS++))
}

# Function to run Python tests
run_python_tests() {
    local test_file="$1"
    local test_name="$2"
    local description="$3"

    local test_command="python3 -m pytest $test_file -v --tb=short --asyncio-mode=auto"

    if run_test "$test_name" "$test_command" "$description"; then
        log "${GREEN}✅ $test_name completed${NC}"
    else
        log "${RED}❌ $test_name failed${NC}"
    fi

    ((TOTAL_TESTS++))
}

# Function to run integration tests
run_integration_tests() {
    print_header "INTEGRATION TESTS"
    run_python_tests "$TESTS_DIR/test_save_integration.py" "Integration Tests" "End-to-end pipeline testing with Redis, Telegram, and Jito"
}

# Function to run profitability tests
run_profitability_tests() {
    print_header "PROFITABILITY TESTS"
    run_python_tests "$TESTS_DIR/test_save_profitability.py" "Profitability Tests" "ROI calculation and fee analysis testing"
}

# Function to run stability tests
run_stability_tests() {
    print_header "STABILITY TESTS"
    run_python_tests "$TESTS_DIR/test_save_stability.py" "Stability Tests" "Error handling and failure scenario testing"
}

# Function to run production tests
run_production_tests() {
    print_header "PRODUCTION DEPLOYMENT TESTS"

    # Check if services are running
    log "${BLUE}Checking if services are running for production tests...${NC}"

    local services_running=true
    if ! curl -s "http://localhost:8080/health" &> /dev/null; then
        log "${YELLOW}⚠️ Trading bot not running - skipping some production tests${NC}"
        services_running=false
    fi

    if ! curl -s "http://localhost:9090/-/healthy" &> /dev/null; then
        log "${YELLOW}⚠️ Prometheus not running - skipping monitoring tests${NC}"
        services_running=false
    fi

    if $services_running; then
        run_python_tests "$TESTS_DIR/test_production_deployment.py" "Production Tests" "Live environment testing with monitoring"
    else
        log "${YELLOW}⚠️ Skipping production tests - services not available${NC}"
        ((TOTAL_TESTS++))
    fi
}

# Function to cleanup test environment
cleanup_test_environment() {
    print_header "CLEANUP"

    # Stop test Redis container if it was started
    if docker ps -q --filter "name=redis-test" | grep -q .; then
        log "${BLUE}Stopping test Redis container...${NC}"
        docker stop redis-test &>> "$LOG_FILE"
        docker rm redis-test &>> "$LOG_FILE"
    fi

    log "${GREEN}✅ Cleanup completed${NC}"
}

# Function to generate final report
generate_final_report() {
    print_header "FINAL TEST REPORT"

    local success_rate=0
    if [ "$TOTAL_TESTS" -gt 0 ]; then
        success_rate=$(( PASSED_TESTS * 100 / TOTAL_TESTS ))
    fi

    log "${BLUE}📊 Test Summary:${NC}"
    log "   Total Tests: $TOTAL_TESTS"
    log "   Passed: ${GREEN}$PASSED_TESTS${NC}"
    log "   Failed: ${RED}$FAILED_TESTS${NC}"
    log "   Success Rate: $success_rate%"

    log ""
    log "${BLUE}📝 Log File:${NC}"
    log "   $LOG_FILE"

    log ""
    log "${BLUE}📊 Test Results by Category:${NC}"

    # Parse results from log file
    grep "✅ PASSED\|❌ FAILED" "$LOG_FILE" | while read -r line; do
        if echo "$line" | grep -q "✅ PASSED"; then
            log "   ${GREEN}$line${NC}"
        else
            log "   ${RED}$line${NC}"
        fi
    done

    log ""
    log "${BLUE}🎯 Recommendations:${NC}"

    if [ "$success_rate" -eq 100 ]; then
        log "   ${GREEN}✅ All tests passed! Ready for production deployment.${NC}"
    elif [ "$success_rate" -ge 90 ]; then
        log "   ${YELLOW}⚠️ Most tests passed. Review failed tests before production.${NC}"
    elif [ "$success_rate" -ge 75 ]; then
        log "   ${RED}❌ Significant test failures. Fix issues before deployment.${NC}"
    else
        log "   ${RED}❌ Critical test failures. Deployment not recommended.${NC}"
    fi

    log ""
    log "${BLUE}📈 Next Steps:${NC}"
    log "   1. Review test results in log file"
    log "   2. Fix any failed tests"
    log "   3. Re-run tests to verify fixes"
    log "   4. Deploy to production if all tests pass"

    log ""
    log "${BLUE}🚀 Save Flash Loan Tests Completed!${NC}"
}

# Function to handle interruption
handle_interrupt() {
    log ""
    log "${YELLOW}⚠️ Test execution interrupted${NC}"
    cleanup_test_environment
    generate_final_report
    exit 1
}

# Main execution
main() {
    log "${BLUE}🚀 Save Flash Loan Tests - Complete Test Suite${NC}"
    log "${BLUE}Started at: $TIMESTAMP${NC}"
    log "${BLUE}Log file: $LOG_FILE${NC}"

    # Set up interrupt handler
    trap handle_interrupt INT TERM

    # Run test phases
    check_prerequisites
    setup_test_environment

    run_rust_unit_tests
    run_rust_benchmarks
    run_integration_tests
    run_profitability_tests
    run_stability_tests
    run_production_tests

    # Cleanup and generate report
    cleanup_test_environment
    generate_final_report

    # Exit with appropriate code
    if [ "$FAILED_TESTS" -eq 0 ]; then
        log "${GREEN}🎉 All tests passed successfully!${NC}"
        exit 0
    else
        log "${RED}💥 Some tests failed. Check the log file for details.${NC}"
        exit 1
    fi
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log "${RED}❌ Please do not run this script as root${NC}"
    exit 1
fi

# Run main function
main "$@"