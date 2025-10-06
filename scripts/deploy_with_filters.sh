#!/bin/bash

# =============================================================================
# MojoRust Trading Bot Deployment Script with Aggressive Filters
# =============================================================================
# This script verifies filter performance, builds the application, and deploys
# with comprehensive spam filtering enabled

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Script configuration
SKIP_VERIFICATION=false
DRY_RUN=false
BACKGROUND=false
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER_TEST_BIN="$PROJECT_ROOT/filter-test"
TRADING_BOT_BIN="$PROJECT_ROOT/trading-bot"

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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_banner() {
    echo -e "${PURPLE}"
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║                                                                   ║"
    echo "║    🛡️ DEPLOYING TRADING BOT WITH AGGRESSIVE SPAM FILTERS 🛡️      ║"
    echo "║                                                                   ║"
    echo "║    Algorithmic Memecoin Trading for Solana                        ║"
    echo "║    90%+ Spam Rejection Rate Guaranteed                            ║"
    echo "║                                                                   ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

cleanup() {
    log_warning "⚠️  Shutting down gracefully..."
    # Kill trading bot process if running
    pkill -f trading-bot || true
    pkill -f filter-test || true
}

# Helper functions for numeric validation
has_bc() {
    command -v bc >/dev/null 2>&1;
}

is_positive_number() {
    if has_bc; then
        echo "$1 > 0" | bc -l >/dev/null 2>&1 && [ "$(echo "$1 > 0" | bc -l)" = "1" ]
    else
        awk -v v="$1" 'BEGIN{exit !(v+0>0)}'
    fi
}

validate_environment_for_verification() {
    log_step "Validating environment for filter verification..."

    # Minimal validation needed for filter verification
    local required_vars=(
        "APP_ENV"
        "INITIAL_CAPITAL"
    )

    # Check for Infisical token
    if [[ -n "$INFISICAL_TOKEN" ]]; then
        log_success "✅ Infisical token found"
        INFISICAL_CONFIGURED=true
    else
        log_warning "⚠️  No Infisical token - checking environment variables"
        INFISICAL_CONFIGURED=false

        # Need API keys for verification if not using Infisical
        required_vars+=(
            "HELIUS_API_KEY"
            "QUICKNODE_PRIMARY_RPC"
        )
    fi

    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "❌ Missing required environment variables for filter verification:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo
        echo "Please set these variables in your environment or .env file:"
        if [[ "$INFISICAL_CONFIGURED" == false ]]; then
            echo "   export HELIUS_API_KEY=your_helius_api_key"
            echo "   export QUICKNODE_PRIMARY_RPC=your_quicknode_rpc_url"
        fi
        echo "   export APP_ENV=production"
        echo "   export INITIAL_CAPITAL=0.1"
        echo
        exit 1
    fi

    # Validate values
    if [[ ! "$APP_ENV" =~ ^(development|staging|production)$ ]]; then
        log_error "❌ Invalid APP_ENV: $APP_ENV. Must be: development, staging, or production"
        exit 1
    fi

    if [[ ! "$INITIAL_CAPITAL" =~ ^[0-9]+\.?[0-9]*$ ]] || ! is_positive_number "$INITIAL_CAPITAL"; then
        log_error "❌ Invalid INITIAL_CAPITAL: $INITIAL_CAPITAL. Must be a positive number"
        exit 1
    fi

    log_success "✅ Environment validation for filter verification passed"
}

validate_environment_for_bot() {
    log_step "Validating environment for trading bot startup..."

    # Full validation needed for bot startup - includes wallet configuration
    local required_vars=(
        "WALLET_ADDRESS"
        "APP_ENV"
        "INITIAL_CAPITAL"
        "EXECUTION_MODE"
    )

    # Fallback variables if not using Infisical
    if [[ "$INFISICAL_CONFIGURED" == false ]]; then
        required_vars+=(
            "HELIUS_API_KEY"
            "QUICKNODE_PRIMARY_RPC"
        )
    fi

    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "❌ Missing required environment variables for trading bot:"
        for var in "${missing_vars[@]}"; do
            echo "   - $var"
        done
        echo
        echo "Please set these variables in your environment or .env file:"
        if [[ "$INFISICAL_CONFIGURED" == false ]]; then
            echo "   export HELIUS_API_KEY=your_helius_api_key"
            echo "   export QUICKNODE_PRIMARY_RPC=your_quicknode_rpc_url"
        fi
        echo "   export WALLET_ADDRESS=your_solana_wallet_address"
        echo "   export APP_ENV=production"
        echo "   export INITIAL_CAPITAL=0.1"
        echo "   export EXECUTION_MODE=paper"
        echo
        exit 1
    fi

    # Validate values
    if [[ ! "$EXECUTION_MODE" =~ ^(paper|live|test)$ ]]; then
        log_error "❌ Invalid EXECUTION_MODE: $EXECUTION_MODE. Must be: paper, live, or test"
        exit 1
    fi

    log_success "✅ Environment validation for trading bot passed"
    print_deployment_config
}

validate_environment() {
    # Legacy function - calls both validations
    validate_environment_for_verification
    validate_environment_for_bot
}

print_deployment_config() {
    echo ""
    log_info "📋 Deployment Configuration:"
    echo "   Environment: $APP_ENV"
    echo "   Execution Mode: ${EXECUTION_MODE:-paper}"
    echo "   Initial Capital: $INITIAL_CAPITAL SOL"
    echo "   Infisical: $([ -n "$INFISICAL_TOKEN" ] && echo "✅ Configured" || echo "❌ Not configured")"
    echo "   Wallet: $WALLET_ADDRESS"
    echo ""
}

build_filter_verification_tool() {
    if [[ "$SKIP_VERIFICATION" == true ]]; then
        log_warning "⚠️  Skipping filter verification tool build"
        return 0
    fi

    log_step "Building filter verification tool..."

    cd "$PROJECT_ROOT"

    # Build the filter verification tool
    mojo build src/engine/filter_verification.mojo -o "$FILTER_TEST_BIN"

    if [[ ! -f "$FILTER_TEST_BIN" ]]; then
        log_error "❌ Filter verification tool build failed - binary not found at $FILTER_TEST_BIN"
        exit 1
    fi

    # Make executable
    chmod +x "$FILTER_TEST_BIN"

    log_success "✅ Filter verification tool built successfully"
}

run_filter_tests() {
    if [[ "$SKIP_VERIFICATION" == true ]]; then
        log_warning "⚠️  Skipping filter verification tests"
        return 0
    fi

    log_step "Running filter verification tests..."

    cd "$PROJECT_ROOT"

    echo "🧪 TESTING FILTER SYSTEM..."
    echo "==============================="

    # Run the filter verification tool
    if "$FILTER_TEST_BIN"; then
        log_success "✅ Filters verified - 90%+ spam rejection achieved!"
        echo ""
    else
        log_error "❌ Filter verification failed - check filter parameters"
        echo ""
        echo "❌ DEPLOYMENT ABORTED - Fix filter issues before deploying"
        exit 1
    fi
}

build_main_application() {
    log_step "Building trading bot application..."

    cd "$PROJECT_ROOT"

    # Build Rust modules first
    if [[ -d "rust-modules" ]]; then
        log_info "📦 Building Rust security modules..."
        cd rust-modules
        cargo build --release
        cd ..
    fi

    # Build the main Mojo application
    log_info "📦 Building Mojo trading bot..."
    mojo build src/main.mojo -o "$TRADING_BOT_BIN"

    if [[ ! -f "$TRADING_BOT_BIN" ]]; then
        log_error "❌ Trading bot build failed - binary not found at $TRADING_BOT_BIN"
        exit 1
    fi

    # Make executable
    chmod +x "$TRADING_BOT_BIN"

    log_success "✅ Trading bot built successfully"
}

create_directories() {
    log_step "Creating necessary directories..."

    # Create log directory
    mkdir -p "$PROJECT_ROOT/logs"

    # Create data directories
    mkdir -p "$PROJECT_ROOT/data/portfolio"
    mkdir -p "$PROJECT_ROOT/data/backups"
    mkdir -p "$PROJECT_ROOT/data/cache"

    log_success "✅ Directories created"
}

start_trading_bot() {
    if [[ "$DRY_RUN" == true ]]; then
        log_info "🔍 DRY RUN MODE - Would start trading bot with these settings:"
        echo "   Binary: $TRADING_BOT_BIN"
        echo "   Command: $TRADING_BOT_BIN --aggressive-filtering"
        echo "   Environment: $APP_ENV"
        echo "   Execution Mode: ${EXECUTION_MODE:-paper}"
        return 0
    fi

    log_step "Starting Trading Bot with aggressive filtering..."
    echo ""

    # Prepare log file with timestamp
    LOG_FILE="$PROJECT_ROOT/logs/trading-bot-$(date +%Y%m%d-%H%M%S).log"

    # Prepare the command
    local cmd="$TRADING_BOT_BIN --aggressive-filtering"

    echo "🚀 EXECUTING: $cmd"
    echo "📝 LOG FILE: $LOG_FILE"
    echo ""
    echo "🛡️  FILTERING: Aggressive mode enabled (90%+ spam rejection)"
    echo "📊 MONITORING: Check filter performance with: grep 'Filter Performance' $LOG_FILE"
    echo ""

    if [[ "$BACKGROUND" == true ]]; then
        # Start in background
        nohup $cmd > "$LOG_FILE" 2>&1 &
        local bot_pid=$!

        log_success "✅ Trading bot started in background (PID: $bot_pid)"
        echo ""
        echo "Monitor with: tail -f $LOG_FILE"
        echo "Stop with: kill $bot_pid"
        echo "Check status: ps aux | grep trading-bot"
    else
        # Start in foreground
        log_info "🎮 Starting trading bot in foreground (Ctrl+C to stop)..."
        echo ""

        # Set up error handling
        trap cleanup EXIT

        # Start the bot and log output
        $cmd 2>&1 | tee "$LOG_FILE"
    fi
}

print_deployment_summary() {
    echo ""
    log_success "🎉 DEPLOYMENT COMPLETE!"
    echo "============================"
    echo ""
    echo "📋 Deployment Summary:"
    echo "   • Environment: $APP_ENV"
    echo "   • Execution Mode: ${EXECUTION_MODE:-paper}"
    echo "   • Initial Capital: $INITIAL_CAPITAL SOL"
    echo "   • Aggressive Filters: ✅ ENABLED (90%+ spam rejection)"
    echo "   • Infisical: $([ -n "$INFISICAL_TOKEN" ] && echo "✅ Configured" || echo "❌ Using env vars")"
    echo ""
    echo "🔍 Monitoring Commands:"
    echo "   • View logs: tail -f logs/trading-bot-*.log"
    echo "   • Filter performance: grep 'Filter Performance' logs/*.log"
    echo "   • Trading activity: grep 'EXECUTED\|PROFIT\|LOSS' logs/*.log"
    echo "   • Errors: grep 'ERROR\|CRITICAL' logs/*.log"
    echo ""
    if [[ "${EXECUTION_MODE:-paper}" == "paper" ]]; then
        echo "⚠️  RUNNING IN PAPER TRADING MODE"
        echo "   Monitor for 24-48 hours before switching to live trading"
        echo ""
    fi
    echo "📚 For detailed monitoring and troubleshooting, see DEPLOYMENT.md"
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    print_banner

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-verification)
                SKIP_VERIFICATION=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --background)
                BACKGROUND=true
                shift
                ;;
            --mock-apis)
                export MOCK_APIS=true
                log_info "🔧 Mock APIs mode enabled - no network calls"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-verification    Skip filter verification tests (not recommended)"
                echo "  --dry-run              Show what would be done without executing"
                echo "  --background           Start trading bot in background"
                echo "  --mock-apis            Use mock APIs for offline testing (no network calls)"
                echo "  --help, -h             Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Set default values
    export EXECUTION_MODE=${EXECUTION_MODE:-paper}
    export APP_ENV=${APP_ENV:-production}

    # Validate environment for filter verification
    validate_environment_for_verification

    # Build and test filters
    build_filter_verification_tool
    run_filter_tests

    # Validate environment for trading bot startup
    validate_environment_for_bot

    # Build main application
    build_main_application

    # Prepare deployment
    create_directories

    # Start the application
    start_trading_bot

    # Print summary
    print_deployment_summary
}

# Set up error handling
trap cleanup EXIT

# Run main function
main "$@"