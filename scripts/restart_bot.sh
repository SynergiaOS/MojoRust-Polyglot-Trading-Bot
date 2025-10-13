#!/bin/bash

# =============================================================================
# 🔄 MojoRust Trading Bot - Restart Script
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2

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
    esac
}

# Function to stop existing trading bot processes
stop_bot() {
    print_status "INFO" "Stopping existing trading bot processes..."

    local stopped=false

    # Try to find and stop processes by multiple patterns
    local bot_pids=$(pgrep -f 'trading-bot|mojo run|main.mojo' 2>/dev/null || true)

    if [ -n "$bot_pids" ]; then
        print_status "INFO" "Found running processes: $bot_pids"

        for pid in $bot_pids; do
            if [ -n "$pid" ]; then
                print_status "INFO" "Stopping process $pid..."
                kill -TERM "$pid" 2>/dev/null || true

                # Wait a bit for graceful shutdown
                sleep 3

                # Check if still running and force kill if needed
                if kill -0 "$pid" 2>/dev/null; then
                    print_status "WARNING" "Process $pid still running, forcing termination..."
                    kill -KILL "$pid" 2>/dev/null || true
                fi

                stopped=true
            fi
        done

        if [ "$stopped" = true ]; then
            print_status "SUCCESS" "Trading bot processes stopped"
        else
            print_status "WARNING" "No running processes found to stop"
        fi
    else
        print_status "INFO" "No running trading bot processes found"
    fi

    # Also try to stop systemd service if it exists
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet trading-bot 2>/dev/null; then
            print_status "INFO" "Stopping systemd service trading-bot..."
            systemctl stop trading-bot 2>/dev/null || true
            print_status "SUCCESS" "Systemd service stopped"
        fi
    fi

    # Additional cleanup
    sleep 2

    # Verify no processes are still running
    local remaining_pids=$(pgrep -f 'trading-bot|mojo run|main.mojo' 2>/dev/null || true)
    if [ -n "$remaining_pids" ]; then
        print_status "WARNING" "Some processes still running: $remaining_pids"
        print_status "INFO" "Force killing remaining processes..."
        echo "$remaining_pids" | xargs kill -KILL 2>/dev/null || true
        sleep 1
    fi
}

# Function to start the bot
start_bot() {
    print_status "INFO" "Starting trading bot..."

    # Check if we're in the right directory
    if [ ! -f "./scripts/deploy_with_filters.sh" ]; then
        print_status "ERROR" "deploy_with_filters.sh not found. Are you in the project root?"
        exit 1
    fi

    # Check if required files exist
    if [ ! -f "src/main.mojo" ]; then
        print_status "ERROR" "src/main.mojo not found"
        exit 1
    fi

    # Check if configuration exists
    if [ ! -f ".env" ]; then
        print_status "WARNING" ".env file not found, using .env.example"
        if [ -f ".env.example" ]; then
            cp .env.example .env
            print_status "INFO" "Copied .env.example to .env"
        else
            print_status "ERROR" "No configuration file found"
            exit 1
        fi
    fi

    # Start the bot using the deployment script
    print_status "INFO" "Starting bot with deploy_with_filters.sh..."

    # Check if running in background is requested
    if [ "$1" = "--background" ] || [ "$1" = "-b" ]; then
        print_status "INFO" "Starting bot in background mode..."
        nohup ./scripts/deploy_with_filters.sh > logs/restart_$(date +%Y%m%d_%H%M%S).log 2>&1 &
        local bg_pid=$!
        print_status "SUCCESS" "Bot started in background with PID: $bg_pid"
        print_status "INFO" "You can check logs with: tail -f logs/restart_$(date +%Y%m%d_%H%M%S).log"

        # Wait a moment to check if it started successfully
        sleep 5
        if kill -0 $bg_pid 2>/dev/null; then
            print_status "SUCCESS" "Background process is running"
        else
            print_status "ERROR" "Background process failed to start"
            exit 1
        fi
    else
        # Start in foreground
        print_status "INFO" "Starting bot in foreground mode..."
        print_status "INFO" "Press Ctrl+C to stop the bot"
        echo ""

        # Execute the deployment script
        if ! ./scripts/deploy_with_filters.sh; then
            print_status "ERROR" "Failed to start trading bot"
            exit 1
        fi
    fi
}

# Function to show help
show_help() {
    cat << EOF
🔄 MojoRust Trading Bot - Restart Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --background, -b     Start bot in background mode
    --help, -h          Show this help message

EXAMPLES:
    $0                  # Restart bot in foreground
    $0 --background     # Restart bot in background

DESCRIPTION:
    This script safely stops any existing trading bot processes and starts
    a fresh instance. It handles both foreground and background modes.

    In background mode, logs are saved to logs/restart_*.log files.

EXIT CODES:
    0   Success
    1   Error (bot failed to start, missing files, etc.)

EOF
}

# Main execution
main() {
    print_status "INFO" "🔄 MojoRust Trading Bot - Restart Script"
    echo ""

    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --background|-b)
            BACKGROUND_MODE=true
            ;;
        "")
            BACKGROUND_MODE=false
            ;;
        *)
            print_status "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    # Create logs directory if it doesn't exist
    mkdir -p logs

    # Stop existing processes
    stop_bot

    # Wait a moment for cleanup
    sleep 2

    # Start the bot
    if [ "$BACKGROUND_MODE" = true ]; then
        start_bot --background
    else
        start_bot
    fi

    print_status "SUCCESS" "✅ Trading bot restart completed!"
}

# Handle script interruption gracefully
trap 'print_status "INFO"; print_status "WARNING"; print_status "WARNING" "Restart interrupted by user"; exit 130' INT TERM

# Run main function
main "$@"