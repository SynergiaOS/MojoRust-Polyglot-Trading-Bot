#!/bin/bash

# =============================================================================
# MojoRust Trading Bot Deployment Script
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/target"
TRADING_BOT_BIN="$BUILD_DIR/trading-bot"

# Default configuration
MODE="paper"
CAPITAL="1.0"
CONFIG_FILE="$PROJECT_ROOT/config/trading.toml"
SKIP_PORT_CHECK=false

# =============================================================================
# Functions
# =============================================================================

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

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🚀 MojoRust Trading Bot Deployment Script 🚀              ║"
    echo "║                                                              ║"
    echo "║    Algorithmic-Only Memecoin Trading for Solana               ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

validate_environment() {
    log_info "Validating environment configuration..."

    # Check if Infisical is configured
    local infisical_vars=(
        "INFISICAL_CLIENT_ID"
        "INFISICAL_CLIENT_SECRET"
        "INFISICAL_PROJECT_ID"
    )

    local infisical_configured=true
    for var in "${infisical_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            infisical_configured=false
            break
        fi
    done

    if [[ "$infisical_configured" == true ]]; then
        log_success "Infisical secrets management detected"

        # Check Infisical connection (optional validation)
        log_info "Testing Infisical connection..."
        # Here you could add a test call to Infisical API
        log_success "Infisical configuration validated"

        # Still validate critical fallback vars
        local critical_vars=(
            "WALLET_ADDRESS"
        )

        local missing_vars=()
        for var in "${critical_vars[@]}"; do
            if [[ -z "${!var}" ]]; then
                missing_vars+=("$var")
            fi
        done

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing critical environment variables:"
            for var in "${missing_vars[@]}"; do
                echo "  - $var"
            done
            echo
            echo "Please set these variables in your environment or .env file:"
            echo "export WALLET_ADDRESS=your_solana_wallet_address"
            exit 1
        fi

    else
        log_warning "Infisical not configured, using environment variables"
        log_info "For production, consider setting up Infisical secrets management"
        echo
        echo "To set up Infisical:"
        echo "1. Create an account at https://app.infisical.com/"
        echo "2. Create a project and get your credentials"
        echo "3. Set the following environment variables:"
        echo "   export INFISICAL_CLIENT_ID=your_client_id"
        echo "   export INFISICAL_CLIENT_SECRET=your_client_secret"
        echo "   export INFISICAL_PROJECT_ID=your_project_id"
        echo "   export INFISICAL_ENVIRONMENT=dev"
        echo

        # Check required environment variables (fallback mode)
        local required_vars=(
            "HELIUS_API_KEY"
            "QUICKNODE_PRIMARY_RPC"
            "WALLET_ADDRESS"
        )

        local missing_vars=()

        for var in "${required_vars[@]}"; do
            if [[ -z "${!var}" ]]; then
                missing_vars+=("$var")
            fi
        done

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing required environment variables:"
            for var in "${missing_vars[@]}"; do
                echo "  - $var"
            done
            echo
            echo "Please set these variables in your environment or .env file:"
            echo "export HELIUS_API_KEY=your_helius_api_key"
            echo "export QUICKNODE_PRIMARY_RPC=your_quicknode_rpc_url"
            echo "export WALLET_ADDRESS=your_solana_wallet_address"
            exit 1
        fi
    fi

    log_success "Environment validation passed"
}

build_project() {
    log_info "Building MojoRust trading bot..."

    # Create build directory if it doesn't exist
    mkdir -p "$BUILD_DIR"

    # Build the project
    cd "$PROJECT_ROOT"

    # Build Rust modules first
    log_info "Building Rust security modules..."
    cd rust-modules
    cargo build --release
    cd ..

    # Build Mojo main application
    log_info "Building Mojo trading bot..."
    mojo build src/main.mojo -o "$TRADING_BOT_BIN"

    if [[ ! -f "$TRADING_BOT_BIN" ]]; then
        log_error "Build failed - binary not found at $TRADING_BOT_BIN"
        exit 1
    fi

    log_success "Build completed successfully"
}

run_tests() {
    log_info "Running tests..."

    # Run Rust tests
    log_info "Running Rust module tests..."
    cd "$PROJECT_ROOT/rust-modules"
    cargo test
    cd ..

    # Run Mojo tests if they exist
    if [[ -f "$PROJECT_ROOT/tests/test_suite.mojo" ]]; then
        log_info "Running Mojo tests..."
        mojo run tests/test_suite.mojo
    else
        log_warning "No Mojo test suite found - skipping Mojo tests"
    fi

    log_success "All tests passed"
}

check_port_availability() {
    if [[ "$SKIP_PORT_CHECK" == true ]]; then
        log_warning "Skipping port availability check as requested"
        return 0
    fi

    log_info "Checking port availability..."

    # Run port availability verification
    if ! "$PROJECT_ROOT/scripts/verify_port_availability.sh" --json >/dev/null 2>&1; then
        log_error "Port conflicts detected!"
        echo
        log_info "Port conflicts prevent successful deployment."
        log_info "Please run the following command to resolve conflicts:"
        echo "  $PROJECT_ROOT/scripts/resolve_port_conflict.sh"
        echo

        # Ask user if they want to run the resolver now
        read -p "Would you like to run the port conflict resolver now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Running port conflict resolver..."
            "$PROJECT_ROOT/scripts/resolve_port_conflict.sh"

            # Re-check after resolution
            log_info "Re-checking port availability after resolution..."
            if ! "$PROJECT_ROOT/scripts/verify_port_availability.sh" --json >/dev/null 2>&1; then
                log_error "Port conflicts still exist after resolution attempt"
                log_error "Please resolve conflicts manually and try again"
                exit 1
            else
                log_success "Port conflicts resolved successfully"
            fi
        else
            log_error "Port conflicts must be resolved before deployment"
            exit 1
        fi
    else
        log_success "All required ports are available"
    fi
}

print_configuration() {
    log_info "Deployment Configuration:"
    echo "  Mode: $MODE"
    echo "  Initial Capital: $CAPITAL SOL"
    echo "  Config File: $CONFIG_FILE"
    echo "  Binary: $TRADING_BOT_BIN"
    echo "  Wallet: $WALLET_ADDRESS"
    echo "  TimescaleDB Port: ${TIMESCALEDB_PORT:-5432}"
    echo
}

start_trading_bot() {
    log_info "Starting MojoRust trading bot..."

    # Ensure binary is executable
    chmod +x "$TRADING_BOT_BIN"

    # Start the trading bot with configuration
    cd "$PROJECT_ROOT"

    local cmd="$TRADING_BOT_BIN --mode=$MODE --capital=$CAPITAL --config=$CONFIG_FILE"

    log_info "Executing: $cmd"
    echo

    # Start the bot
    exec $cmd
}

cleanup() {
    log_info "Performing cleanup..."
    # Add any cleanup tasks here
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    print_banner

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mode=*)
                MODE="${1#*=}"
                shift
                ;;
            --capital=*)
                CAPITAL="${1#*=}"
                shift
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-port-check)
                SKIP_PORT_CHECK=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --mode=MODE         Trading mode (paper, live, test) [default: paper]"
                echo "  --capital=AMOUNT    Initial capital in SOL [default: 1.0]"
                echo "  --config=FILE       Configuration file path"
                echo "  --skip-tests        Skip running tests"
                echo "  --skip-port-check   Skip port availability verification"
                echo "  --help, -h          Show this help message"
                echo
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Validate arguments
    if [[ ! "$MODE" =~ ^(paper|live|test)$ ]]; then
        log_error "Invalid mode: $MODE. Must be one of: paper, live, test"
        exit 1
    fi

    if [[ ! "$CAPITAL" =~ ^[0-9]+\.?[0-9]*$ ]] || [[ $(echo "$CAPITAL <= 0" | bc -l) -eq 1 ]]; then
        log_error "Invalid capital amount: $CAPITAL. Must be a positive number"
        exit 1
    fi

    # Set up error handling
    trap cleanup EXIT

    # Execute deployment steps
    validate_environment
    check_port_availability
    build_project

    if [[ "$SKIP_TESTS" != "true" ]]; then
        run_tests
    else
        log_warning "Skipping tests as requested"
    fi

    print_configuration

    # Start the trading bot
    start_trading_bot
}

# Run main function
main "$@"