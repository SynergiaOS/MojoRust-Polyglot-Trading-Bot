#!/bin/bash
# =============================================================================
# Docker Entrypoint Script for MojoRust Trading Bot
# =============================================================================
# This script handles container initialization, environment validation, and graceful startup

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
APP_PID=""
HEALTH_SERVER_PID=""

# Logging functions
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

# Trap signals for graceful shutdown
cleanup() {
    log_info "Shutting down gracefully..."

    # Kill health server if running
    if [ -n "$HEALTH_SERVER_PID" ]; then
        kill -TERM $HEALTH_SERVER_PID 2>/dev/null || true
        wait $HEALTH_SERVER_PID 2>/dev/null || true
    fi

    # Kill main application
    if [ -n "$APP_PID" ]; then
        kill -TERM $APP_PID 2>/dev/null || true
        # Wait up to 30 seconds for graceful shutdown
        timeout 30s bash -c "wait $APP_PID" || {
            log_warning "App did not shut down gracefully within 30s, forcing kill"
            kill -KILL $APP_PID 2>/dev/null || true
        }
    fi

    log_success "Shutdown complete"
    exit 0
}

# Set up signal traps
trap cleanup SIGTERM SIGINT

# Validate environment variables
validate_environment() {
    log_info "Validating environment configuration..."

    # Check required environment variables
    local required_vars=("TRADING_ENV")
    local missing_vars=()

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi

    # Check wallet configuration
    if [ -z "$WALLET_ADDRESS" ]; then
        log_warning "WALLET_ADDRESS not set, trading functionality will be limited"
    fi

    # Check for wallet keypair file
    local wallet_paths=(
        "$WALLET_PRIVATE_KEY_PATH"
        "/app/secrets/wallet.keypair"
        "/app/wallet.keypair"
        "$HOME/.config/solana/id.json"
    )

    local wallet_found=false
    for path in "${wallet_paths[@]}"; do
        if [ -f "$path" ]; then
            log_success "Wallet keypair found: $path"
            wallet_found=true
            break
        fi
    done

    if [ "$wallet_found" = false ]; then
        log_warning "No wallet keypair file found, trading functionality will be limited"
    fi

    # Validate Infisical configuration if enabled
    if [ -n "$INFISICAL_CLIENT_ID" ]; then
        log_info "Infisical configuration detected, testing connectivity..."
        if command -v infisical >/dev/null 2>&1; then
            if infisical secrets list --projectId "$INFISICAL_PROJECT_ID" --env "$INFISICAL_ENVIRONMENT" >/dev/null 2>&1; then
                log_success "Infisical connectivity verified"
            else
                log_warning "Infisical connectivity failed, falling back to environment variables"
            fi
        else
            log_warning "Infisical CLI not found, falling back to environment variables"
        fi
    fi

    log_success "Environment validation completed"
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."

    # Create required directories
    local dirs=(
        "/app/logs"
        "/app/data"
        "/app/cache"
        "/app/data/portfolio"
        "/app/data/backups"
        "/app/data/cache"
    )

    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done

    # Set permissions for non-root user if running as non-root
    if [ "$(id -u)" != "0" ]; then
        # Ensure we own our directories
        chown -R $(id -u):$(id -g) /app/logs /app/data /app/cache 2>/dev/null || true
    fi

    log_success "Directory setup completed"
}

# Start health check endpoint
start_health_server() {
    log_info "Starting health check server on port 8082..."
    # Simple health server using Python if available, otherwise netcat
    if command -v python3 >/dev/null 2>&1; then
        # Python health server
        python3 -c "
import http.server
import socketserver
import json
import os
from datetime import datetime

class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()

            # Get execution mode
            exec_mode = os.environ.get('EXECUTION_MODE', 'unknown')

            health_data = {
                'status': 'healthy',
                'mode': exec_mode,
                'timestamp': datetime.utcnow().isoformat() + 'Z',
                'version': '1.0.0'
            }

            self.wfile.write(json.dumps(health_data).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress access logs
        pass

with socketserver.TCPServer(('', 8082), HealthHandler) as httpd:
    httpd.serve_forever()
" &
        HEALTH_SERVER_PID=$!
    else
        # Fallback: Use netcat for simple health check if available
        if command -v nc >/dev/null 2>&1 || command -v netcat >/dev/null 2>&1; then
            NC_CMD=$(command -v nc || command -v netcat)
            while true; do
                echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"healthy\",\"mode\":\"$(echo $EXECUTION_MODE)\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" | $NC_CMD -l -p 8082
                sleep 1
            done &
            HEALTH_SERVER_PID=$!
        else
            log_warning "Neither python3 nor netcat found; skipping health server startup"
            HEALTH_SERVER_PID=""
        fi
    fi

    log_success "Health server started (PID: $HEALTH_SERVER_PID)"
}

# Load Infisical secrets if configured
load_infisical_secrets() {
    if [ -n "$INFISICAL_CLIENT_ID" ] && command -v infisical >/dev/null 2>&1; then
        log_info "Loading secrets from Infisical..."

        # Export Infisical secrets to environment
        if infisical secrets list --projectId "$INFISICAL_PROJECT_ID" --env "$INFISICAL_ENVIRONMENT" >/dev/null 2>&1; then
            # Use Infisical's export functionality
            eval $(infisical secrets export --projectId "$INFISICAL_PROJECT_ID" --env "$INFISICAL_ENVIRONMENT" --format env)
            log_success "Infisical secrets loaded successfully"
        else
            log_warning "Failed to load Infisical secrets, using environment variables"
        fi
    fi
}

# Start the trading bot application
start_application() {
    log_info "Starting trading bot application..."

    # Log startup configuration
    log_info "Configuration Summary:"
    log_info "  Environment: $TRADING_ENV"
    log_info "  Execution Mode: ${EXECUTION_MODE:-unknown}"
    log_info "  Wallet Address: ${WALLET_ADDRESS:-not_set}"
    log_info "  Initial Capital: ${INITIAL_CAPITAL:-1.0} SOL"
    log_info "  Log Level: ${LOG_LEVEL:-INFO}"
    log_info "  Prometheus Port: ${PROMETHEUS_PORT:-9091}"

    # Execute the application (CMD passed from Dockerfile)
    # Using exec to replace shell process for proper signal handling
    exec "$@" &
    APP_PID=$!

    log_success "Trading bot started (PID: $APP_PID)"

    # Wait for the application to finish
    wait $APP_PID
}

# Main execution flow
main() {
    log_info "Initializing MojoRust Trading Bot container..."

    # Run setup steps
    validate_environment
    setup_directories
    start_health_server
    load_infisical_secrets

    # Start the application
    start_application "$@"

    # If we reach here, the application has exited
    log_info "Trading bot application exited"
}

# Run main function with all arguments
main "$@"