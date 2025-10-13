#!/bin/bash

# =============================================================================
# 🚀 MojoRust Trading Bot - Startup Script
# =============================================================================

set -e

# POSIX shell compatibility
if [ -z "$BASH_VERSION" ] && [ -z "$ZSH_VERSION" ]; then
    POSIX_MODE=1
else
    POSIX_MODE=0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
MODE="paper"
METHOD="direct"
DAEMON=false
CAPITAL=""
AGGRESSIVE_FILTERING=false
LOG_FILE=""
PID_FILE=""
VERBOSE=false

# Environment file location
ENV_FILE=".env"

# Functions for colored output
print_status() {
    local status=$1
    local message=$2

    if [ "$POSIX_MODE" = 1 ]; then
        case $status in
            "SUCCESS") echo "✅ $message" ;;
            "ERROR") echo "❌ $message" ;;
            "WARNING") echo "⚠️  $message" ;;
            "INFO") echo "ℹ️  $message" ;;
        esac
    else
        case $status in
            "SUCCESS")
                echo -e "${GREEN}✅ $message${NC}"
                ;;
            "ERROR")
                echo -e "${RED}❌ $message${NC}"
                ;;
            "WARNING")
                echo -e "${YELLOW}⚠️  $message${NC}"
                ;;
            "INFO")
                echo -e "${BLUE}ℹ️  $message${NC}"
                ;;
            "PROGRESS")
                echo -e "${PURPLE}🔄 $message${NC}"
                ;;
        esac
    fi
}

# Function to show help
show_help() {
    cat << 'EOF'
🚀 MojoRust Trading Bot - Startup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --mode MODE         Trading mode: paper, live, test (default: paper)
    --method METHOD     Startup method: direct, build, deploy (default: direct)
    --daemon            Run as daemon process
    --capital AMOUNT    Initial capital amount (overrides .env)
    --aggressive-filtering Enable aggressive filtering mode
    --verbose, -v       Enable verbose output
    --help, -h          Show this help message

STARTUP METHODS:
    direct              Run directly with Mojo (mojo run src/main.mojo)
    build               Build binary and execute
    deploy              Use deployment script (./scripts/deploy_with_filters.sh)

EXAMPLES:
    $0                                  # Start in paper mode, direct execution
    $0 --mode=live --daemon             # Start in live mode as daemon
    $0 --method=deploy --capital=10.0   # Deploy with custom capital
    $0 --aggressive-filtering --verbose # Enable verbose aggressive filtering

DESCRIPTION:
    This script starts the MojoRust Trading Bot with comprehensive validation:
    - Sources .env file for configuration
    - Validates wallet via check_wallet.sh (fail fast on errors)
    - Validates required environment variables
    - Confirms live mode with typed 'LIVE' confirmation
    - Manages logs and PID files for daemon mode
    - Provides monitoring tips and guidance

EXIT CODES:
    0   Success (bot started)
    1   Error (configuration, validation, or startup failed)
    2   User cancelled (live mode confirmation)
    3   Wallet verification failed

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --method)
            METHOD="$2"
            shift 2
            ;;
        --daemon)
            DAEMON=true
            shift
            ;;
        --capital)
            CAPITAL="$2"
            shift 2
            ;;
        --aggressive-filtering)
            AGGRESSIVE_FILTERING=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            print_status "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate mode
if [[ ! "$MODE" =~ ^(paper|live|test)$ ]]; then
    print_status "ERROR" "Invalid mode: $MODE (must be paper, live, or test)"
    exit 1
fi

# Validate method
if [[ ! "$METHOD" =~ ^(direct|build|deploy)$ ]]; then
    print_status "ERROR" "Invalid method: $METHOD (must be direct, build, or deploy)"
    exit 1
fi

# Function to source environment file
source_environment() {
    print_status "PROGRESS" "Loading environment configuration..."

    if [ ! -f "$ENV_FILE" ]; then
        print_status "WARNING" "Environment file not found: $ENV_FILE"
        print_status "INFO" "Using default configuration"
        return 0
    fi

    if [ "$VERBOSE" = true ]; then
        print_status "INFO" "Sourcing environment from: $ENV_FILE"
    fi

    # Source the environment file safely
    set -a
    # shellcheck source=.env
    source "$ENV_FILE"
    set +a

    if [ "$VERBOSE" = true ]; then
        print_status "SUCCESS" "Environment loaded successfully"
    fi
}

# Function to validate required environment variables
validate_environment() {
    print_status "PROGRESS" "Validating environment variables..."

    local required_vars=(
        "SERVER_HOST"
        "SERVER_PORT"
    )

    local mode_specific_vars=()

    # Add mode-specific requirements
    case $MODE in
        "live"|"paper")
            mode_specific_vars+=(
                "HELIUS_API_KEY"
                "QUICKNODE_RPC_URL"
                "WALLET_ADDRESS"
            )
            ;;
    esac

    # Check required variables
    local missing_vars=()

    for var in "${required_vars[@]}" "${mode_specific_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_status "ERROR" "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  • $var"
        done
        print_status "INFO" "Check your .env file or set these variables"
        return 1
    fi

    # Override capital if specified
    if [ -n "$CAPITAL" ]; then
        export INITIAL_CAPITAL="$CAPITAL"
        if [ "$VERBOSE" = true ]; then
            print_status "INFO" "Capital override: $CAPITAL"
        fi
    fi

    # Set mode
    export EXECUTION_MODE="$MODE"

    # Set aggressive filtering
    if [ "$AGGRESSIVE_FILTERING" = true ]; then
        export AGGRESSIVE_FILTERING="true"
        if [ "$VERBOSE" = true ]; then
            print_status "INFO" "Aggressive filtering enabled"
        fi
    fi

    print_status "SUCCESS" "Environment validation passed"
    return 0
}

# Function to run wallet verification
verify_wallet() {
    print_status "PROGRESS" "Running wallet verification..."

    local wallet_script="scripts/check_wallet.sh"

    if [ ! -f "$wallet_script" ]; then
        print_status "ERROR" "Wallet verification script not found: $wallet_script"
        return 1
    fi

    if [ ! -x "$wallet_script" ]; then
        print_status "INFO" "Making wallet script executable..."
        chmod +x "$wallet_script"
    fi

    # Run wallet verification
    if [ "$VERBOSE" = true ]; then
        print_status "INFO" "Running: $wallet_script --verbose"
    fi

    if ! bash "$wallet_script" --verbose; then
        local exit_code=$?
        print_status "ERROR" "Wallet verification failed (exit code: $exit_code)"
        print_status "INFO" "Fix wallet issues before starting bot"
        return $exit_code
    fi

    print_status "SUCCESS" "Wallet verification passed"
    return 0
}

# Function to confirm live mode
confirm_live_mode() {
    if [ "$MODE" != "live" ]; then
        return 0
    fi

    print_status "WARNING" "🚨 LIVE TRADING MODE CONFIRMATION"
    echo ""
    print_status "WARNING" "You are about to start the bot in LIVE trading mode."
    print_status "WARNING" "This will use REAL MONEY for trading operations."
    echo ""
    print_status "INFO" "Type 'LIVE' to confirm and continue:"
    echo -n "> "

    read -r confirmation

    if [ "$confirmation" != "LIVE" ]; then
        print_status "ERROR" "Live mode confirmation cancelled"
        print_status "INFO" "Bot not started. Type 'LIVE' exactly to confirm."
        exit 2
    fi

    print_status "SUCCESS" "Live mode confirmed - proceeding with startup"
    echo ""
}

# Function to setup logging
setup_logging() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="logs/trading-bot-${timestamp}.log"
    PID_FILE="logs/trading-bot.pid"

    # Create logs directory
    mkdir -p logs

    if [ "$DAEMON" = true ]; then
        print_status "INFO" "Daemon mode enabled"
        print_status "INFO" "Log file: $LOG_FILE"
        print_status "INFO" "PID file: $PID_FILE"
    fi
}

# Function to start bot directly with Mojo
start_direct() {
    print_status "PROGRESS" "Starting bot with direct Mojo execution..."

    if ! command -v mojo >/dev/null 2>&1; then
        print_status "ERROR" "Mojo CLI not found"
        print_status "INFO" "Install Mojo: https://www.modular.com/mojo"
        return 1
    fi

    if [ ! -f "src/main.mojo" ]; then
        print_status "ERROR" "Main Mojo file not found: src/main.mojo"
        return 1
    fi

    local mojo_cmd="mojo run src/main.mojo"

    if [ "$VERBOSE" = true ]; then
        print_status "INFO" "Running: $mojo_cmd"
    fi

    if [ "$DAEMON" = true ]; then
        print_status "INFO" "Starting bot in daemon mode..."
        nohup $mojo_cmd > "$LOG_FILE" 2>&1 &
        local bot_pid=$!
        echo "$bot_pid" > "$PID_FILE"
        print_status "SUCCESS" "Bot started in daemon mode (PID: $bot_pid)"
    else
        print_status "INFO" "Starting bot in foreground mode..."
        print_status "INFO" "Press Ctrl+C to stop the bot"
        echo ""
        $mojo_cmd
    fi
}

# Function to build and run binary
start_build() {
    print_status "PROGRESS" "Building and running bot binary..."

    if ! command -v mojo >/dev/null 2>&1; then
        print_status "ERROR" "Mojo CLI not found for building"
        return 1
    fi

    # Build the binary
    local build_cmd="mojo build src/main.mojo -o trading-bot"

    if [ "$VERBOSE" = true ]; then
        print_status "INFO" "Building: $build_cmd"
    fi

    if ! $build_cmd; then
        print_status "ERROR" "Build failed"
        return 1
    fi

    if [ ! -f "trading-bot" ]; then
        print_status "ERROR" "Built binary not found: trading-bot"
        return 1
    fi

    # Make binary executable
    chmod +x trading-bot

    local run_cmd="./trading-bot"

    if [ "$DAEMON" = true ]; then
        print_status "INFO" "Starting binary in daemon mode..."
        nohup $run_cmd > "$LOG_FILE" 2>&1 &
        local bot_pid=$!
        echo "$bot_pid" > "$PID_FILE"
        print_status "SUCCESS" "Bot started in daemon mode (PID: $bot_pid)"
    else
        print_status "INFO" "Starting binary in foreground mode..."
        print_status "INFO" "Press Ctrl+C to stop the bot"
        echo ""
        $run_cmd
    fi
}

# Function to start via deployment script
start_deploy() {
    print_status "PROGRESS" "Starting bot via deployment script..."

    local deploy_script="scripts/deploy_with_filters.sh"

    if [ ! -f "$deploy_script" ]; then
        print_status "ERROR" "Deployment script not found: $deploy_script"
        return 1
    fi

    if [ ! -x "$deploy_script" ]; then
        print_status "INFO" "Making deployment script executable..."
        chmod +x "$deploy_script"
    fi

    local deploy_cmd="$deploy_script"

    # Add mode flag if not paper
    if [ "$MODE" != "paper" ]; then
        deploy_cmd="$deploy_cmd --mode=$MODE"
    fi

    # Add capital flag if specified
    if [ -n "$CAPITAL" ]; then
        deploy_cmd="$deploy_cmd --capital=$CAPITAL"
    fi

    # Add aggressive filtering flag
    if [ "$AGGRESSIVE_FILTERING" = true ]; then
        deploy_cmd="$deploy_cmd --aggressive-filtering"
    fi

    if [ "$VERBOSE" = true ]; then
        print_status "INFO" "Running: $deploy_cmd"
    fi

    if [ "$DAEMON" = true ]; then
        print_status "INFO" "Starting deployment in daemon mode..."
        nohup $deploy_cmd > "$LOG_FILE" 2>&1 &
        local bot_pid=$!
        echo "$bot_pid" > "$PID_FILE"
        print_status "SUCCESS" "Bot deployed in daemon mode (PID: $bot_pid)"
    else
        print_status "INFO" "Starting deployment in foreground mode..."
        print_status "INFO" "Press Ctrl+C to stop the bot"
        echo ""
        $deploy_cmd
    fi
}

# Function to show monitoring tips
show_monitoring_tips() {
    echo ""
    print_status "INFO" "📊 Monitoring Tips:"
    echo ""

    if [ "$DAEMON" = true ]; then
        echo "  • View logs:      tail -f $LOG_FILE"
        echo "  • Check status:   ps aux | grep trading-bot"
        echo "  • Stop bot:       kill \$(cat $PID_FILE)"
        echo "  • Restart:        $0 --daemon --mode=$MODE --method=$METHOD"
    else
        echo "  • Bot is running in foreground mode"
        echo "  • Press Ctrl+C to stop the bot"
    fi

    echo ""
    echo "  • Health check:   curl http://${SERVER_HOST:-localhost}:${SERVER_PORT:-8080}/api/health"
    echo "  • Bot status:     curl http://${SERVER_HOST:-localhost}:${SERVER_PORT:-8080}/api/status"
    echo "  • Recent trades:  curl http://${SERVER_HOST:-localhost}:${SERVER_PORT:-8080}/api/trades/recent"
    echo ""

    if [ "$MODE" = "paper" ]; then
        print_status "INFO" "📝 Paper Trading Mode - No real money at risk"
    elif [ "$MODE" = "live" ]; then
        print_status "WARNING" "💰 Live Trading Mode - Real money in use"
    else
        print_status "INFO" "🧪 Test Mode - Simulation environment"
    fi

    echo ""
}

# Function to show startup summary
show_startup_summary() {
    echo ""
    print_status "INFO" "🚀 MojoRust Trading Bot Startup Summary"
    echo ""
    echo "Configuration:"
    echo "  Mode:               $MODE"
    echo "  Method:             $METHOD"
    echo "  Daemon:             $DAEMON"
    echo "  Aggressive Filtering: $AGGRESSIVE_FILTERING"

    if [ -n "$CAPITAL" ]; then
        echo "  Initial Capital:    $CAPITAL"
    fi

    echo "  Server Host:        ${SERVER_HOST:-localhost}"
    echo "  Server Port:        ${SERVER_PORT:-8080}"

    if [ "$DAEMON" = true ]; then
        echo "  Log File:           $LOG_FILE"
        echo "  PID File:           $PID_FILE"
    fi

    echo ""
}

# Main startup function
main() {
    print_status "INFO" "🚀 MojoRust Trading Bot - Startup Script"
    print_status "INFO" "Starting comprehensive bot initialization..."
    echo ""

    # Show startup summary
    show_startup_summary

    # Source environment
    source_environment || exit 1

    # Validate environment
    validate_environment || exit 1

    # Verify wallet (fail fast)
    verify_wallet || exit 3

    # Confirm live mode
    confirm_live_mode || exit 2

    # Setup logging
    setup_logging

    # Start bot based on method
    case $METHOD in
        "direct")
            start_direct || exit 1
            ;;
        "build")
            start_build || exit 1
            ;;
        "deploy")
            start_deploy || exit 1
            ;;
    esac

    # Show monitoring tips
    show_monitoring_tips

    if [ "$DAEMON" = false ]; then
        print_status "SUCCESS" "✅ Bot startup completed - Running in foreground"
    else
        print_status "SUCCESS" "✅ Bot startup completed - Running in daemon mode"
    fi
}

# Handle script interruption gracefully
trap 'print_status "WARNING"; print_status "WARNING" "Bot startup interrupted by user"; exit 130' INT TERM

# Run main function
main