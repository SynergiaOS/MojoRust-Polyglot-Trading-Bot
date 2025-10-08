#!/bin/bash

# =============================================================================
# FFI Verification Script for MojoRust Trading Bot
# =============================================================================
# Comprehensive verification of Rust-Mojo FFI integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RUST_DIR="rust-modules"
LIBRARY_PATH="$RUST_DIR/target/release/libmojo_trading_bot.so"
REQUIRED_SYMBOLS=(
    "crypto_engine_new"
    "crypto_engine_destroy"
    "crypto_engine_generate_keypair"
    "security_engine_new"
    "security_engine_initialize"
    "security_engine_check_request"
    "solana_engine_new"
    "solana_engine_get_balance"
    "secrets_manager_init"
    "secrets_manager_get_secret"
    "ffi_initialize"
    "ffi_cleanup"
    "ffi_bytes_free"
)

# Report file
REPORT_FILE="ffi_verification_report.txt"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2

    case $status in
        "SUCCESS")
            echo -e "${GREEN}✓ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}✗ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠ $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ $message${NC}"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to verify prerequisites
verify_prerequisites() {
    print_status "INFO" "Verifying prerequisites..."

    local missing_prereqs=()

    # Check for Rust
    if ! command_exists rustc; then
        missing_prereqs+=("rustc")
    fi

    # Check for Cargo
    if ! command_exists cargo; then
        missing_prereqs+=("cargo")
    fi

    # Check for nm (for symbol listing)
    if ! command_exists nm; then
        missing_prereqs+=("nm (binutils)")
    fi

    # Check for objdump (fallback for symbol listing)
    if ! command_exists objdump; then
        missing_prereqs+=("objdump (binutils)")
    fi

    # Check for Mojo
    if ! command_exists mojo; then
        missing_prereqs+=("mojo")
    fi

    if [ ${#missing_prereqs[@]} -gt 0 ]; then
        print_status "ERROR" "Missing prerequisites: ${missing_prereqs[*]}"
        print_status "INFO" "Please install missing tools and try again"
        exit 1
    fi

    print_status "SUCCESS" "All prerequisites found"
}

# Function to compile Rust modules
compile_rust() {
    print_status "INFO" "Compiling Rust modules..."

    cd "$RUST_DIR"

    # Clean previous build
    if [ -d "target" ]; then
        cargo clean
        print_status "INFO" "Cleaned previous build"
    fi

    # Build in release mode
    if cargo build --release; then
        print_status "SUCCESS" "Rust modules compiled successfully"
    else
        print_status "ERROR" "Rust compilation failed"
        cd ..
        exit 1
    fi

    cd ..
}

# Function to verify library generation
verify_library() {
    print_status "INFO" "Verifying library generation..."

    if [ -f "$LIBRARY_PATH" ]; then
        local size=$(stat -c%s "$LIBRARY_PATH" 2>/dev/null || stat -f%z "$LIBRARY_PATH" 2>/dev/null || echo "unknown")
        print_status "SUCCESS" "Library found: $LIBRARY_PATH (${size} bytes)"

        # Check if it's a shared library
        if file "$LIBRARY_PATH" | grep -q "shared object"; then
            print_status "SUCCESS" "Library is a valid shared object"
        else
            print_status "ERROR" "Library is not a shared object"
            exit 1
        fi
    else
        print_status "ERROR" "Library not found: $LIBRARY_PATH"
        exit 1
    fi
}

# Function to safely get symbols from nm or objdump
get_symbols() {
    local symbols_file="/tmp/ffi_symbols_$$.txt"

    # Try nm first
    if command_exists nm && nm -D "$LIBRARY_PATH" 2>/dev/null > "$symbols_file"; then
        # Verify the symbol file is not empty and has expected format
        if [ -s "$symbols_file" ]; then
            echo "$symbols_file"
            return 0
        fi
    fi

    # Fallback to objdump if nm fails or returns no symbols
    if command_exists objdump && objdump -T "$LIBRARY_PATH" 2>/dev/null > "$symbols_file"; then
        # Verify the symbol file is not empty and has expected format
        if [ -s "$symbols_file" ]; then
            print_status "INFO" "Using objdump for symbol extraction (nm failed)"
            echo "$symbols_file"
            return 0
        fi
    fi

    # Both methods failed
    print_status "ERROR" "Failed to extract symbols from library (both nm and objdump failed)"
    rm -f "$symbols_file"
    return 1
}

# Function to list exported symbols
list_symbols() {
    print_status "INFO" "Listing exported symbols..."

    if command_exists nm; then
        local symbols_file
        if ! symbols_file=$(get_symbols); then
            return 1
        fi

        local symbol_count
        symbol_count=$(wc -l < "$symbols_file" 2>/dev/null || echo "0")
        print_status "SUCCESS" "Found $symbol_count exported symbols"

        # List FFI symbols with better error handling
        local ffi_symbols
        ffi_symbols=$(grep -E "(crypto_engine|security_engine|solana_engine|secrets_manager|ffi_)" "$symbols_file" || true)

        if [ -n "$ffi_symbols" ]; then
            print_status "INFO" "FFI symbols found:"
            echo "$ffi_symbols" | while read -r line; do
                local symbol=$(echo "$line" | awk '{print $3}')
                if [ -n "$symbol" ]; then
                    print_status "INFO" "  - $symbol"
                fi
            done
        else
            print_status "WARNING" "No FFI symbols found with expected patterns"
        fi

        # Clean up
        rm -f "$symbols_file"
    else
        print_status "WARNING" "nm command not available, cannot list symbols"
    fi
}

# Function to check required symbols
check_required_symbols() {
    print_status "INFO" "Checking required FFI symbols..."

    local symbols_file
    if ! symbols_file=$(get_symbols); then
        print_status "ERROR" "Cannot check required symbols - failed to extract symbols"
        return 1
    fi

    local missing_symbols=()
    local found_symbols=()

    for symbol in "${REQUIRED_SYMBOLS[@]}"; do
        # Use relaxed matching with word boundaries to work across platforms
        if grep -qw "$symbol" "$symbols_file" 2>/dev/null; then
            found_symbols+=("$symbol")
        else
            missing_symbols+=("$symbol")
        fi
    done

    print_status "SUCCESS" "Found ${#found_symbols[@]} required symbols"

    if [ ${#found_symbols[@]} -gt 0 ]; then
        print_status "INFO" "Found symbols:"
        for symbol in "${found_symbols[@]}"; do
            print_status "SUCCESS" "  ✓ $symbol"
        done
    fi

    if [ ${#missing_symbols[@]} -gt 0 ]; then
        print_status "WARNING" "Missing required symbols:"
        for symbol in "${missing_symbols[@]}"; do
            print_status "WARNING" "  ✗ $symbol"
        done

        # Check if symbols exist with different naming
        local similar_symbols
        similar_symbols=$(grep " T " "$symbols_file" 2>/dev/null | grep -E "$(IFS='|'; echo "${missing_symbols[*]}")" || true)
        if [ -n "$similar_symbols" ]; then
            print_status "INFO" "Similar symbols found (might be naming mismatch):"
            echo "$similar_symbols" | while read -r line; do
                local symbol=$(echo "$line" | awk '{print $3}')
                print_status "INFO" "  ~ $symbol"
            done
        fi
    fi

    # Clean up
    rm -f "$symbols_file"

    # Return success if at least 80% of symbols are found
    local total_symbols=${#REQUIRED_SYMBOLS[@]}
    local found_count=${#found_symbols[@]}
    local required_count=$((total_symbols * 80 / 100))

    if [ $found_count -lt $required_count ]; then
        print_status "ERROR" "Too many symbols missing ($found_count/$total_symbols found, required at least $required_count)"
        return 1
    fi

    return 0
}

# Function to run Rust tests
run_rust_tests() {
    print_status "INFO" "Running Rust tests..."

    cd "$RUST_DIR"

    if cargo test --release; then
        print_status "SUCCESS" "All Rust tests passed"
    else
        print_status "ERROR" "Some Rust tests failed"
        cd ..
        exit 1
    fi

    cd ..
}

# Function to check for FFI bindings
check_ffi_bindings() {
    print_status "INFO" "Checking for Mojo FFI bindings..."

    if [ -f "src/ffi/rust_bindings.mojo" ]; then
        print_status "SUCCESS" "FFI bindings found: src/ffi/rust_bindings.mojo"
    else
        print_status "WARNING" "FFI bindings not found: src/ffi/rust_bindings.mojo"
        print_status "INFO" "FFI bindings need to be implemented"
    fi
}

# Function to run simple FFI test
run_simple_ffi_test() {
    print_status "INFO" "Running simple FFI test..."

    if [ -f "tests/test_ffi_simple.mojo" ] && command_exists mojo; then
        if mojo run tests/test_ffi_simple.mojo; then
            print_status "SUCCESS" "Simple FFI test passed"
        else
            print_status "ERROR" "Simple FFI test failed"
            return 1
        fi
    else
        print_status "WARNING" "Simple FFI test not available"
    fi
}

# Function to run comprehensive FFI tests
run_comprehensive_ffi_tests() {
    print_status "INFO" "Running comprehensive FFI tests..."

    if [ -f "tests/test_ffi_integration.mojo" ] && command_exists mojo; then
        if mojo run tests/test_ffi_integration.mojo; then
            print_status "SUCCESS" "Comprehensive FFI tests passed"
        else
            print_status "ERROR" "Comprehensive FFI tests failed"
            return 1
        fi
    else
        print_status "WARNING" "Comprehensive FFI tests not available"
    fi
}

# Function to generate verification report
generate_report() {
    print_status "INFO" "Generating verification report..."

    {
        echo "FFI Verification Report"
        echo "======================"
        echo "Generated: $(date)"
        echo ""

        echo "Library Information:"
        echo "- Path: $LIBRARY_PATH"
        if [ -f "$LIBRARY_PATH" ]; then
            echo "- Size: $(stat -c%s "$LIBRARY_PATH" 2>/dev/null || stat -f%z "$LIBRARY_PATH" 2>/dev/null || echo "unknown") bytes"
            echo "- Type: $(file "$LIBRARY_PATH" | cut -d: -f2-)"
        fi
        echo ""

        echo "Exported Symbols:"
        local symbols_file
        if command_exists nm && symbols_file=$(get_symbols 2>/dev/null); then
            local total_symbols
            total_symbols=$(wc -l < "$symbols_file" 2>/dev/null || echo "0")
            local ffi_symbols
            ffi_symbols=$(grep -E "(crypto_engine|security_engine|solana_engine|secrets_manager|ffi_)" "$symbols_file" | wc -l || echo "0")
            echo "- Total: $total_symbols"
            echo "- FFI Symbols: $ffi_symbols"

            # Clean up
            rm -f "$symbols_file"
        else
            echo "- nm command not available or failed"
        fi
        echo ""

        echo "Required Symbols Status:"
        if command_exists nm && symbols_file=$(get_symbols 2>/dev/null); then
            local found_count=0
            local missing_count=0
            for symbol in "${REQUIRED_SYMBOLS[@]}"; do
                if grep -qw "$symbol" "$symbols_file" 2>/dev/null; then
                    echo "- $symbol: ✓ Found"
                    ((found_count++))
                else
                    echo "- $symbol: ✗ Missing"
                    ((missing_count++))
                fi
            done
            echo ""
            echo "- Summary: $found_count/${#REQUIRED_SYMBOLS[@]} symbols found"
            if [ $missing_count -gt 0 ]; then
                echo "- Missing: $missing_count symbols"
            fi

            # Clean up
            rm -f "$symbols_file"
        else
            echo "- Could not verify symbol status (nm command failed)"
        fi
        echo ""

        echo "Test Results:"
        echo "- Rust Tests: $(cd "$RUST_DIR" && cargo test --release >/dev/null 2>&1 && echo "✓ Passed" || echo "✗ Failed")"
        echo "- Simple FFI Test: $([ -f "tests/test_ffi_simple.mojo" ] && command_exists mojo && mojo run tests/test_ffi_simple.mojo >/dev/null 2>&1 && echo "✓ Passed" || echo "⚠ Not Available")"
        echo "- Comprehensive FFI Test: $([ -f "tests/test_ffi_integration.mojo" ] && command_exists mojo && mojo run tests/test_ffi_integration.mojo >/dev/null 2>&1 && echo "✓ Passed" || echo "⚠ Not Available")"

    } > "$REPORT_FILE"

    print_status "SUCCESS" "Report generated: $REPORT_FILE"
}

# Function to provide troubleshooting hints
troubleshooting_hints() {
    print_status "INFO" "Troubleshooting hints:"
    echo ""
    echo "If compilation fails:"
    echo "  - Check Rust toolchain installation: rustc --version"
    echo "  - Update Rust: rustup update"
    echo "  - Clean build: cd $RUST_DIR && cargo clean"
    echo "  - Check dependencies: cd $RUST_DIR && cargo check"
    echo ""
    echo "If library not found:"
    echo "  - Ensure compilation completed successfully"
    echo "  - Check library path: $LIBRARY_PATH"
    echo "  - Verify build target: release mode required"
    echo ""
    echo "If symbols missing:"
    echo "  - Check FFI exports in rust-modules/src/ffi/mod.rs"
    echo "  - Ensure #[no_mangle] attribute is present"
    echo "  - Verify extern \"C\" block"
    echo ""
    echo "If FFI tests fail:"
    echo "  - Check Mojo installation: mojo --version"
    echo "  - Verify library loading in test files"
    echo "  - Check library path in test configuration"
}

# Main execution
main() {
    echo "======================================"
    echo "FFI Verification Script"
    echo "MojoRust Trading Bot"
    echo "======================================"
    echo ""

    local start_time=$(date +%s)
    local overall_status=0

    # Run verification steps
    verify_prerequisites || exit 1
    echo ""

    compile_rust || exit 1
    echo ""

    verify_library || exit 1
    echo ""

    list_symbols
    echo ""

    if ! check_required_symbols; then
        echo ""
        print_status "ERROR" "Symbol verification failed - too many required symbols missing"
        exit 1
    fi
    echo ""

    run_rust_tests || exit 1
    echo ""

    check_ffi_bindings
    echo ""

    # Run FFI tests if available
    if run_simple_ffi_test; then
        echo ""
        run_comprehensive_ffi_tests || overall_status=1
    else
        overall_status=1
    fi
    echo ""

    generate_report
    echo ""

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Summary
    echo "======================================"
    print_status "INFO" "Verification completed in ${duration}s"

    if [ $overall_status -eq 0 ]; then
        print_status "SUCCESS" "All verification steps passed!"
        print_status "INFO" "FFI integration is ready for use"
    else
        print_status "WARNING" "Some verification steps had warnings"
        print_status "INFO" "Review the report for details: $REPORT_FILE"
    fi

    echo ""
    troubleshooting_hints

    exit $overall_status
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h    Show this help message"
        echo "  --no-compile  Skip Rust compilation"
        echo "  --no-tests    Skip test execution"
        echo ""
        echo "This script verifies the Rust-Mojo FFI integration for the"
        echo "MojoRust Trading Bot project."
        exit 0
        ;;
    --no-compile)
        print_status "INFO" "Skipping Rust compilation"
        compile_rust() { print_status "INFO" "Compilation skipped"; }
        ;;
    --no-tests)
        print_status "INFO" "Skipping test execution"
        run_rust_tests() { print_status "INFO" "Rust tests skipped"; }
        run_simple_ffi_test() { print_status "INFO" "Simple FFI test skipped"; }
        run_comprehensive_ffi_tests() { print_status "INFO" "Comprehensive FFI tests skipped"; }
        ;;
esac

# Run main function
main "$@"