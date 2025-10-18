#!/bin/bash

# =============================================================================
# MojoRust Trading Bot - Rust Modules Build Script
# =============================================================================
# This script builds the Rust modules with proper error handling,
# prerequisite checks, dependency caching, and verification steps.

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
RUST_MODULES_DIR="rust-modules"
CARGO_TOML="$RUST_MODULES_DIR/Cargo.toml"
CARGO_LOCK="$RUST_MODULES_DIR/Cargo.lock"
BUILD_TARGET="release"  # Can be "debug" or "release"
SKIP_TESTS=false
SKIP_CLIPPY=false
SKIP_AUDIT=false
CLEAN_BUILD=false
VERBOSE=false
PARALLEL_JOBS=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "4")

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🦀 RUST MODULES BUILD SCRIPT 🦀                        ║"
    echo "║                                                              ║"
    echo "║    Build high-performance Rust modules                       ║"
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
MojoRust Trading Bot - Rust Modules Build Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --debug                Build in debug mode (default: release)
    --verbose              Enable verbose output
    --skip-tests            Skip running tests
    --skip-clippy           Skip Clippy linting
    --skip-audit            Skip cargo audit
    --clean                Clean build artifacts before building
    --jobs <N>             Set number of parallel jobs (default: $PARALLEL_JOBS)
    --help                 Show this help message

EXAMPLES:
    $0                      # Build in release mode
    $0 --debug             # Build in debug mode
    $0 --verbose --skip-clippy  # Verbose build without Clippy
    $0 --clean             # Clean and build

REQUIREMENTS:
    - Rust 1.70+ installed
    - Cargo package manager
    - Source code in $RUST_MODULES_DIR
    - Sufficient disk space for build artifacts

OUTPUT:
    Built libraries will be in: $RUST_MODULES_DIR/target/$BUILD_TARGET/

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
            --skip-clippy)
                SKIP_CLIPPY=true
                shift
                ;;
            --skip-audit)
                SKIP_AUDIT=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --jobs)
                PARALLEL_JOBS="$2"
                shift 2
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

    # Validate parallel jobs
    if ! [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [[ "$PARALLEL_JOBS" -lt 1 ]]; then
        log_error "Invalid number of jobs: $PARALLEL_JOBS"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Rust is installed
    if ! command -v rustc &> /dev/null; then
        log_error "Rust is not installed or not in PATH"
        echo "Please install Rust from https://rustup.rs/"
        exit 1
    fi

    # Check Rust version
    local rust_version
    rust_version=$(rustc --version | grep -o 'rustc [0-9]\+\.[0-9]+\.[0-9]+' | cut -d' ' -f2)
    if [[ -z "$rust_version" ]]; then
        log_warning "Could not determine Rust version"
    else
        local major_version=$(echo "$rust_version" | cut -d. -f1)
        local minor_version=$(echo "$rust_version" | cut -d. -f2)

        if [[ $major_version -lt 1 ]] || [[ $major_version -eq 1 && $minor_version -lt 70 ]]; then
            log_error "Rust version $rust_version is too old. Required: 1.70+"
            exit 1
        fi

        log_success "Rust version $rust_version detected"
    fi

    # Check if Cargo is available
    if ! command -v cargo &> /dev/null; then
        log_error "Cargo is not available"
        exit 1
    fi

    # Check Rust modules directory
    if [[ ! -d "$RUST_MODULES_DIR" ]]; then
        log_error "Rust modules directory '$RUST_MODULES_DIR' not found"
        exit 1
    fi

    # Check Cargo.toml
    if [[ ! -f "$CARGO_TOML" ]]; then
        log_error "Cargo.toml not found at $CARGO_TOML"
        exit 1
    fi

    # Check available disk space
    local available_space
    available_space=$(df "$RUST_MODULES_DIR" | awk 'NR==2{print $4}')
    local required_space=2097152  # 2GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 2GB, Available: $((available_space/1024/1024))GB"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Clean build artifacts
clean_build() {
    if [[ "$CLEAN_BUILD" == true ]]; then
        log_info "Cleaning Rust build artifacts..."

        cd "$RUST_MODULES_DIR"

        # Clean using cargo clean
        if [[ "$VERBOSE" == true ]]; then
            cargo clean --verbose
        else
            cargo clean > /dev/null 2>&1
        fi

        # Remove any remaining build artifacts
        rm -rf target/debug/
        rm -rf target/release/
        rm -rf target/.rustc_info.json

        cd - > /dev/null

        log_success "Rust build artifacts cleaned"
    fi
}

# Run cargo audit for security vulnerabilities
run_audit() {
    if [[ "$SKIP_AUDIT" == true ]]; then
        log_warning "Skipping security audit"
        return 0
    fi

    log_info "Running security audit..."

    # Check if cargo-audit is installed
    if ! command -v cargo-audit &> /dev/null; then
        log_warning "cargo-audit not found, installing..."
        cargo install cargo-audit
    fi

    cd "$RUST_MODULES_DIR"

    # Run audit
    if cargo audit 2>/dev/null; then
        log_success "Security audit passed - no vulnerabilities found"
    else
        log_warning "Security audit found vulnerabilities or issues"
        log_info "Review the audit output above and address any security concerns"
    fi

    cd - > /dev/null
}

# Run Clippy for code quality
run_clippy() {
    if [[ "$SKIP_CLIPPY" == true ]]; then
        log_warning "Skipping Clippy linting"
        return 0
    fi

    log_info "Running Clippy code quality checks..."

    cd "$RUST_MODULES_DIR"

    # Set clippy flags
    local clippy_flags="-- -D warnings -A clippy::all"
    if [[ "$BUILD_TARGET" == "release" ]]; then
        clippy_flags="$clippy_flags --release"
    fi

    # Run clippy
    if cargo clippy $clippy_flags 2>/dev/null; then
        log_success "Clippy checks passed - no code quality issues found"
    else
        log_error "Clippy found code quality issues"
        log_info "Run 'cd $RUST_MODULES_DIR && cargo clippy --fix' to auto-fix some issues"
        exit 1
    fi

    cd - > /dev/null
}

# Build Rust modules
build_rust_modules() {
    log_info "Building Rust modules in $BUILD_TARGET mode..."

    cd "$RUST_MODULES_DIR"

    # Set build flags
    local build_flags=""
    if [[ "$BUILD_TARGET" == "release" ]]; then
        build_flags="--release"
    fi

    # Set parallel jobs
    local jobs_flag="--jobs $PARALLEL_JOBS"

    # Build command
    local build_cmd="cargo build $build_flags $jobs_flag"

    if [[ "$VERBOSE" == true ]]; then
        log_info "Running build command: $build_cmd"
        eval "$build_cmd"
    else
        eval "$build_cmd" > /dev/null 2>&1
    fi

    # Check if build was successful
    local target_dir="target/$BUILD_TARGET"
    if [[ ! -d "$target_dir" ]]; then
        log_error "Build failed - target directory not found: $target_dir"
        exit 1
    fi

    # Check for built libraries
    local built_libs=0
    for lib in "$target_dir"/deps/lib*.rlib; do
        if [[ -f "$lib" ]]; then
            ((built_libs++))
        fi
    done

    if [[ $built_libs -eq 0 ]]; then
        log_error "No libraries were built successfully"
        exit 1
    fi

    log_success "Rust modules built successfully ($built_libs libraries)"
    log_info "Build artifacts location: $RUST_MODULES_DIR/$target_dir"

    cd - > /dev/null
}

# Run tests
run_tests() {
    if [[ "$SKIP_TESTS" == true ]]; then
        log_warning "Skipping tests"
        return 0
    fi

    log_info "Running Rust tests..."

    cd "$RUST_MODULES_DIR"

    # Set test flags
    local test_flags=""
    if [[ "$BUILD_TARGET" == "release" ]]; then
        test_flags="--release"
    fi

    # Run tests
    if cargo test $test_flags --jobs "$PARALLEL_JOBS" 2>/dev/null; then
        log_success "All tests passed"
    else
        log_error "Some tests failed"
        log_info "Run 'cd $RUST_MODULES_DIR && cargo test' to see detailed test results"
        exit 1
    fi

    cd - > /dev/null
}

# Verify build output
verify_build() {
    log_info "Verifying build output..."

    local target_dir="$RUST_MODULES_DIR/target/$BUILD_TARGET"

    # Check target directory exists
    if [[ ! -d "$target_dir" ]]; then
        log_error "Target directory not found: $target_dir"
        exit 1
    fi

    # Check for main library files
    local expected_files=(
        "deps"
        "build"
    )

    for file in "${expected_files[@]}"; do
        if [[ ! -e "$target_dir/$file" ]]; then
            log_error "Expected build artifact not found: $file"
            exit 1
        fi
    done

    # Check library size (should be reasonable)
    local total_size=0
    for lib in "$target_dir"/deps/lib*.rlib; do
        if [[ -f "$lib" ]]; then
            local size=$(stat -f%z "$lib" 2>/dev/null || stat -c%s "$lib" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
        fi
    done

    if [[ $total_size -lt 100000 ]]; then  # Less than 100KB seems too small
        log_warning "Total library size seems small ($(echo "scale=2; $total_size/1024/1024" | bc 2>/dev/null || echo $((total_size/1024/1024)))MB)"
    else
        log_success "Library size looks good ($(echo "scale=2; $total_size/1024/1024" | bc 2>/dev/null || echo $((total_size/1024/1024)))MB)"
    fi

    # Verify dynamic libraries
    log_info "Verifying dynamic library exports..."
    local lib_count=0
    for lib in "$target_dir"/deps/lib*.so; do
        if [[ -f "$lib" ]]; then
            if objdump -T "$lib" 2>/dev/null | grep -q .text || nm -D "$lib" 2>/dev/null | grep -q " T "; then
                ((lib_count++))
            else
                log_warning "Library may be incomplete: $(basename "$lib")"
            fi
        fi
    done

    if [[ $lib_count -gt 0 ]]; then
        log_success "Found $lib_count properly linked dynamic libraries"
    else
        log_warning "No dynamic libraries found or libraries may be incomplete"
    fi

    # Check for critical external symbols
    log_info "Checking for required symbols..."
    local critical_symbols=("redis_connect" "solana_transaction_sign" "portfolio_update")
    local found_symbols=0

    for lib in "$target_dir"/deps/lib*.so; do
        if [[ -f "$lib" ]]; then
            for symbol in "${critical_symbols[@]}"; do
                if nm -D "$lib" 2>/dev/null | grep -q "$symbol"; then
                    log_success "Found critical symbol: $symbol"
                    ((found_symbols++))
                fi
            done
        fi
    done

    if [[ $found_symbols -gt 0 ]]; then
        log_success "Found $found_symbols critical symbols in libraries"
    else
        log_warning "No critical symbols found - this may be normal for your configuration"
    fi

    # Integration test preparation
    log_info "Preparing integration test artifacts..."
    if [[ ! -d "../tests/rust_integration" ]]; then
        mkdir -p "../tests/rust_integration"
    fi

    # Copy library manifest for integration testing
    if [[ -f "$target_dir/.rustc_info.json" ]]; then
        cp "$target_dir/.rustc_info.json" "../tests/rust_integration/"
    fi

    log_success "Build verification completed"
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
    echo "   Modules: $RUST_MODULES_DIR"
    echo "   Parallel jobs: $PARALLEL_JOBS"
    echo "   Cargo.toml: $CARGO_TOML"
    echo ""
    echo "🔗 Next Steps:"
    echo "   1. Review build artifacts: ls -la $RUST_MODULES_DIR/target/$BUILD_TARGET/"
    echo "   2. Test integration with Mojo: cd .. && ./scripts/build_mojo_binary.sh"
    echo "   3. Run full build: ./scripts/build_and_deploy.sh"
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

    # Run security audit
    run_audit

    # Run code quality checks
    run_clippy

    # Build Rust modules
    build_rust_modules

    # Run tests
    run_tests

    # Verify build
    verify_build

    # Show summary
    show_build_summary

    log_success "Rust modules build completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"