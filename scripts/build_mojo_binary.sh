#!/bin/bash

# =============================================================================
# MojoRust Trading Bot - Mojo Binary Build Script
# =============================================================================
# This script builds the Mojo trading bot binary with proper error handling,
# prerequisite checks, and verification steps.

set -euo pipefail

# =============================================================================
# Colors for output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration Variables
# =============================================================================
MOJO_SOURCE_DIR="src"
MOJO_OUTPUT_DIR="target"
MOJO_BINARY_NAME="trading-bot"
MOJO_MAIN_FILE="main.mojo"
BUILD_TARGET="release"  # Can be "debug" or "release"
VERBOSE=false
SKIP_TESTS=false
SKIP_FORMAT_CHECK=false

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🔥 MOJO BINARY BUILD SCRIPT 🔥                           ║"
    echo "║                                                              ║"
    echo "║    Build the Mojo trading bot binary                         ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    cat << EOF
MojoRust Trading Bot - Mojo Binary Build Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --debug                Build in debug mode (default: release)
    --verbose              Enable verbose output
    --skip-tests            Skip running tests
    --skip-format-check    Skip code formatting check
    --clean                Clean build artifacts before building
    --help                 Show this help message

EXAMPLES:
    $0                      # Build in release mode
    $0 --debug             # Build in debug mode
    $0 --verbose --skip-tests  # Verbose build without tests
    $0 --clean             # Clean and build

REQUIREMENTS:
    - Mojo 24.4+ installed
    - Source code in $MOJO_SOURCE_DIR
    - Sufficient disk space for build artifacts

OUTPUT:
    Binary will be created at: $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                BUILD_TARGET="debug"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-format-check)
                SKIP_FORMAT_CHECK=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Mojo is installed
    if ! command -v mojo &> /dev/null; then
        log_error "Mojo is not installed or not in PATH"
        echo "Please install Mojo 24.4+ from https://www.modular.com/mojo"
        exit 1
    fi

    # Check Mojo version
    local mojo_version
    mojo_version=$(mojo --version 2>/dev/null | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    if [[ -z "$mojo_version" ]]; then
        log_warning "Could not determine Mojo version"
    else
        local major_version=$(echo "$mojo_version" | cut -d. -f1)
        local minor_version=$(echo "$mojo_version" | cut -d. -f2)

        if [[ $major_version -lt 24 ]] || [[ $major_version -eq 24 && $minor_version -lt 4 ]]; then
            log_error "Mojo version $mojo_version is too old. Required: 24.4+"
            exit 1
        fi

        log_success "Mojo version $mojo_version detected"
    fi

    # Check source directory
    if [[ ! -d "$MOJO_SOURCE_DIR" ]]; then
        log_error "Source directory '$MOJO_SOURCE_DIR' not found"
        exit 1
    fi

    # Check main Mojo file
    if [[ ! -f "$MOJO_SOURCE_DIR/$MOJO_MAIN_FILE" ]]; then
        log_error "Main Mojo file '$MOJO_SOURCE_DIR/$MOJO_MAIN_FILE' not found"
        exit 1
    fi

    # Check available disk space
    local available_space
    available_space=$(df . | awk 'NR==2{print $4}')
    local required_space=1048576  # 1GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 1GB, Available: $((available_space/1024/1024))GB"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Clean build artifacts
clean_build() {
    if [[ "${CLEAN_BUILD:-false}" == true ]]; then
        log_info "Cleaning build artifacts..."

        # Remove Mojo build cache
        if [[ -d ".mojo_cache" ]]; then
            rm -rf .mojo_cache
            log_success "Removed .mojo_cache"
        fi

        # Remove target directory
        if [[ -d "$MOJO_OUTPUT_DIR" ]]; then
            rm -rf "$MOJO_OUTPUT_DIR"
            log_success "Removed $MOJO_OUTPUT_DIR directory"
        fi

        # Clean Mojo temp files
        find . -name "*.mojo.tmp" -delete 2>/dev/null || true

        log_success "Build artifacts cleaned"
    fi
}

# Run format check
run_format_check() {
    if [[ "$SKIP_FORMAT_CHECK" == true ]]; then
        log_warning "Skipping format check"
        return 0
    fi

    log_info "Running code format check..."

    # Check if mojo format is available
    if mojo format --help &> /dev/null; then
        # Check formatting without modifying files
        local format_issues
        format_issues=$(find "$MOJO_SOURCE_DIR" -name "*.mojo" -exec mojo format --check {} \; 2>&1 || true)

        if [[ -n "$format_issues" ]]; then
            log_error "Code formatting issues found:"
            echo "$format_issues"
            echo ""
            log_info "Run 'mojo format src/**/*.mojo' to fix formatting issues"
            exit 1
        fi

        log_success "Code formatting check passed"
    else
        log_warning "Mojo format command not available, skipping format check"
    fi
}

# Build the Mojo binary
build_mojo_binary() {
    log_info "Building Mojo binary in $BUILD_TARGET mode..."

    # Create output directory
    mkdir -p "$MOJO_OUTPUT_DIR/$BUILD_TARGET"

    # Set build flags based on target
    local build_flags=""
    if [[ "$BUILD_TARGET" == "release" ]]; then
        build_flags="-O"
    else
        build_flags="-g"
    fi

    # Build command
    local build_cmd="mojo build $build_flags -o $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME $MOJO_SOURCE_DIR/$MOJO_MAIN_FILE"

    if [[ "$VERBOSE" == true ]]; then
        log_info "Running build command: $build_cmd"
        eval "$build_cmd"
    else
        eval "$build_cmd" > /dev/null 2>&1
    fi

    # Check if build was successful
    if [[ ! -f "$MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME" ]]; then
        log_error "Build failed - binary not found at expected location"
        exit 1
    fi

    # Make binary executable
    chmod +x "$MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME"

    log_success "Mojo binary built successfully"
    log_info "Binary location: $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME"
}

# Run tests
run_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        log_warning "Skipping tests"
        return 0
    fi

    log_info "Running Mojo tests..."

    # Find test files
    local test_files
    test_files=$(find . -name "*test*.mojo" -o -name "test_*.mojo" 2>/dev/null || true)

    if [[ -z "$test_files" ]]; then
        log_warning "No test files found, skipping tests"
        return 0
    fi

    # Run tests
    local failed_tests=0
    while IFS= read -r test_file; do
        if [[ -f "$test_file" ]]; then
            log_info "Running test: $test_file"
            if ! mojo run "$test_file" 2>/dev/null; then
                log_error "Test failed: $test_file"
                ((failed_tests++))
            fi
        fi
    done <<< "$test_files"

    if [[ $failed_tests -gt 0 ]]; then
        log_error "$failed_tests test(s) failed"
        exit 1
    fi

    log_success "All tests passed"
}

# Verify binary functionality
verify_binary() {
    log_info "Verifying binary functionality..."

    local binary_path="$MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME"

    # Check if binary is executable
    if [[ ! -x "$binary_path" ]]; then
        log_error "Binary is not executable"
        exit 1
    fi

    # Test binary with --help flag
    if "$binary_path" --help &> /dev/null; then
        log_success "Binary responds to --help flag"
    else
        log_warning "Binary does not respond to --help flag (this may be normal)"
    fi

    # Check binary size
    local binary_size
    binary_size=$(stat -f%z "$binary_path" 2>/dev/null || stat -c%s "$binary_path" 2>/dev/null || echo "0")

    if [[ $binary_size -lt 1000 ]]; then
        log_warning "Binary size seems small ($binary_size bytes), build may have failed"
    else
        log_success "Binary size looks good ($(echo "scale=2; $binary_size/1024/1024" | bc 2>/dev/null || echo $((binary_size/1024/1024)))MB)"
    fi

    # Verify binary dependencies and symbols
    log_info "Checking binary dependencies..."
    if command -v ldd &> /dev/null; then
        if ldd "$binary_path" &> /dev/null; then
            log_success "Binary dependencies are properly linked"
            # Check for critical dependencies
            local critical_deps=("libssl" "libcrypto" "libc")
            for dep in "${critical_deps[@]}"; do
                if ldd "$binary_path" | grep -q "$dep"; then
                    log_success "Found critical dependency: $dep"
                fi
            done
        else
            log_warning "Binary has missing dependencies or is statically linked"
        fi
    fi

    # Test binary execution with different arguments
    log_info "Testing binary execution..."

    # Test version/help flag
    if "$binary_path" --version &> /dev/null; then
        local version_output=$("$binary_path" --version 2>&1)
        log_success "Binary version command works: $version_output"
    elif "$binary_path" --help &> /dev/null; then
        log_success "Binary help command works"
    else
        log_warning "Binary doesn't respond to --version or --help flags"
    fi

    # Test binary in different modes
    log_info "Testing binary execution modes..."

    # Test paper trading mode (dry run)
    if timeout 5 "$binary_path" --mode=paper --dry-run --capital=0.1 &> /dev/null; then
        log_success "Binary executes successfully in paper trading mode"
    else
        log_warning "Binary may have issues in paper trading mode (this could be normal)"
    fi

    # Test configuration loading
    log_info "Testing configuration loading..."
    if timeout 3 "$binary_path" --config=../.env.example --dry-run &> /dev/null; then
        log_success "Binary loads configuration successfully"
    else
        log_warning "Binary may have configuration loading issues"
    fi

    # Verify binary architecture
    log_info "Checking binary architecture..."
    if command -v file &> /dev/null; then
        local arch_info=$(file "$binary_path")
        log_success "Binary architecture: $arch_info"

        if echo "$arch_info" | grep -q "x86-64"; then
            log_success "Binary is built for correct architecture (x86-64)"
        elif echo "$arch_info" | grep -q "ARM"; then
            log_success "Binary is built for ARM architecture"
        else
            log_warning "Binary architecture may be unusual: $arch_info"
        fi
    fi

    # Check for security features
    log_info "Checking binary security features..."
    if command -v checksec &> /dev/null; then
        checksec --file="$binary_path" 2>/dev/null || log_warning "Security check failed or checksec not available"
    fi

    # Create integration test package
    log_info "Creating integration test package..."
    if [[ ! -d "../tests/mojo_integration" ]]; then
        mkdir -p "../tests/mojo_integration"
    fi

    # Copy binary for integration testing
    cp "$binary_path" "../tests/mojo_integration/"
    log_success "Binary copied to integration test directory"

    log_success "Binary verification completed"
}

# Show build summary
show_build_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    BUILD SUMMARY                           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "📦 Build Configuration:"
    echo "   Target: $BUILD_TARGET"
    echo "   Binary: $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME"
    echo "   Source: $MOJO_SOURCE_DIR/$MOJO_MAIN_FILE"
    echo ""
    echo "🔗 Next Steps:"
    echo "   1. Run the binary: $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME"
    echo "   2. Test with: $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME --help"
    echo "   3. Configure environment: cp .env.example .env"
    echo "   4. Start trading: $MOJO_OUTPUT_DIR/$BUILD_TARGET/$MOJO_BINARY_NAME --mode=paper"
    echo ""
    echo "📊 Build completed at: $(date)"
    echo ""
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Print banner
    print_banner

    # Check prerequisites
    check_prerequisites

    # Clean build if requested
    clean_build

    # Run format check
    run_format_check

    # Build the binary
    build_mojo_binary

    # Run tests
    run_tests

    # Verify binary
    verify_binary

    # Show summary
    show_build_summary

    log_success "Mojo binary build completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"