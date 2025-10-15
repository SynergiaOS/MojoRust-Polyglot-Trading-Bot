#!/bin/bash

# =============================================================================
# 🚀 MojoRust Trading Bot - Automated Deployment Script
# Server: 38.242.239.150
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_SERVER_IP="38.242.239.150"
DEFAULT_SSH_USER="root"
DEFAULT_MODE="paper"
DEFAULT_REPO="https://github.com/SynergiaOS/MojoRust.git"

# Detect docker compose binary (local CLI). Prefer 'docker compose' (v2) when available.
if docker compose version >/dev/null 2>&1; then
    COMPOSE_LOCAL='docker compose'
else
    COMPOSE_LOCAL='docker-compose'
fi

# Configuration variables
SERVER_IP="${SERVER_IP:-$DEFAULT_SERVER_IP}"
SSH_USER="${SSH_USER:-$DEFAULT_SSH_USER}"
DEPLOY_MODE="${DEPLOY_MODE:-$DEFAULT_MODE}"
REPO_URL="${REPO_URL:-$DEFAULT_REPO}"
DEPLOYMENT_DIR="~/mojo-trading-bot"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="mojorust-deploy-${TIMESTAMP}.tar.gz"

# Parse command line arguments
DRY_RUN=false
SKIP_SETUP=false
CONFIG_ONLY=false
RESTART_MODE=false
USE_DOCKER_COMPOSE=false

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
        "PROGRESS")
            echo -e "${PURPLE}🔄 $message${NC}"
            ;;
        "STEP")
            echo -e "${CYAN}📋 $message${NC}"
            ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
🚀 MojoRust Trading Bot - Automated Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --server-ip <IP>       Server IP address (default: $DEFAULT_SERVER_IP)
    --ssh-user <USER>      SSH user (default: $DEFAULT_SSH_USER)
    --mode <MODE>          Deployment mode: paper|live (default: $DEFAULT_MODE)
    --repo <URL>           Repository URL (default: $DEFAULT_REPO)
    --dry-run              Show what would be done without executing
    --skip-setup           Skip VPS setup if already configured
    --config-only          Only update configuration files
    --restart              Restart existing deployment
    --docker-compose       Deploy using Docker Compose (recommended for production)
    --help                 Show this help message

EXAMPLES:
    $0                                    # Deploy to production in paper mode
    $0 --mode live                         # Deploy in live trading mode
    $0 --dry-run                          # Preview deployment steps
    $0 --skip-setup --restart             # Restart existing deployment
    $0 --server-ip 192.168.1.100          # Deploy to different server
    $0 --docker-compose                   # Deploy with Docker Compose
    $0 --docker-compose --mode live       # Deploy with Docker Compose in live mode

ENVIRONMENT VARIABLES:
    SERVER_IP       - Override server IP
    SSH_USER        - Override SSH user
    DEPLOY_MODE     - Override deployment mode
    REPO_URL        - Override repository URL

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --mode)
            DEPLOY_MODE="$2"
            shift 2
            ;;
        --repo)
            REPO_URL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --restart)
            RESTART_MODE=true
            shift
            ;;
        --docker-compose)
            USE_DOCKER_COMPOSE=true
            shift
            ;;
        --help)
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

# Function to execute command locally or via SSH
execute() {
    local cmd="$1"
    local use_ssh="${2:-true}"

    if [ "$DRY_RUN" = true ]; then
        if [ "$use_ssh" = true ]; then
            print_status "INFO" "SSH Command: $SSH_USER@$SERVER_IP: $cmd"
        else
            print_status "INFO" "Local Command: $cmd"
        fi
        return 0
    fi

    if [ "$use_ssh" = true ]; then
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "$cmd"
    else
        eval "$cmd"
    fi
}

# Function to check SSH connection
check_ssh_connection() {
    print_status "STEP" "Checking SSH connection to $SSH_USER@$SERVER_IP"

    if ! execute "echo 'SSH connection successful'" true; then
        print_status "ERROR" "Cannot connect to server $SSH_USER@$SERVER_IP"
        print_status "INFO" "Please check:"
        print_status "INFO" "  - Server IP address is correct"
        print_status "INFO" "  - SSH service is running on server"
        print_status "INFO" "  - Your SSH key is properly configured"
        print_status "INFO" "  - Firewall allows SSH connection"
        exit 1
    fi

    print_status "SUCCESS" "SSH connection established"
}

# Function to check local prerequisites
check_local_prerequisites() {
    print_status "STEP" "Checking local prerequisites"

    local missing_tools=()

    if ! command -v git >/dev/null 2>&1; then
        missing_tools+=("git")
    fi

    if ! command -v tar >/dev/null 2>&1; then
        missing_tools+=("tar")
    fi

    if ! command -v scp >/dev/null 2>&1; then
        missing_tools+=("scp")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_status "ERROR" "Missing required tools: ${missing_tools[*]}"
        print_status "INFO" "Please install missing tools and try again"
        exit 1
    fi

    print_status "SUCCESS" "Local prerequisites check passed"
}

# Function to create deployment package
create_deployment_package() {
    print_status "STEP" "Creating deployment package"

    if [ "$RESTART_MODE" = false ] && [ "$CONFIG_ONLY" = false ]; then
        # Create temporary directory for packaging
        local temp_dir=$(mktemp -d)
        local package_dir="$temp_dir/mojorust"

        # Copy necessary files
        mkdir -p "$package_dir"

        # Copy core files
        cp -r src/ "$package_dir/"
        cp -r scripts/ "$package_dir/"
        cp -r config/ "$package_dir/"
        cp -r rust-modules/ "$package_dir/"
        cp -r tests/ "$package_dir/"

        # Copy configuration files
        cp *.toml "$package_dir/" 2>/dev/null || true
        cp *.md "$package_dir/" 2>/dev/null || true
        cp .env.example "$package_dir/" 2>/dev/null || true
        cp .env.production.example "$package_dir/" 2>/dev/null || true

        # Copy Docker files if they exist
        cp Dockerfile* "$package_dir/" 2>/dev/null || true
        cp docker-compose*.yml "$package_dir/" 2>/dev/null || true

        # Include pre-built trading-bot binary if present locally
        if [ -f trading-bot ]; then
            cp trading-bot "$package_dir/" || true
        fi

        # Create deployment info
        cat > "$package_dir/DEPLOYMENT_INFO.txt" << EOF
Deployment Information
====================
Server: $SERVER_IP
User: $SSH_USER
Mode: $DEPLOY_MODE
Timestamp: $TIMESTAMP
Repository: $REPO_URL

Deployment Commands:
- Start: cd ~/mojo-trading-bot && ./scripts/deploy_with_filters.sh
- Stop: pkill -f mojo
- Restart: ./scripts/restart_bot.sh
- Status: ./scripts/server_health.sh
- Logs: tail -f logs/trading-bot-*.log

API Endpoints:
- Health: http://$SERVER_IP:8080/api/health
- Status: http://$SERVER_IP:8080/api/status
- Metrics: http://$SERVER_IP:8080/api/metrics
EOF

        # Create package
        tar -czf "$PACKAGE_NAME" -C "$temp_dir" mojorust

        # Cleanup
        rm -rf "$temp_dir"

        print_status "SUCCESS" "Deployment package created: $PACKAGE_NAME"
    else
        print_status "INFO" "Skipping package creation (restart/config-only mode)"
    fi
}

# Function to upload package to server
upload_package() {
    if [ "$RESTART_MODE" = false ] && [ "$CONFIG_ONLY" = false ]; then
        print_status "STEP" "Uploading deployment package to server"

        # Create deployment directory on server
        execute "mkdir -p $DEPLOYMENT_DIR" true

        # Upload package
        if ! scp -o StrictHostKeyChecking=no "$PACKAGE_NAME" "$SSH_USER@$SERVER_IP:$DEPLOYMENT_DIR/"; then
            print_status "ERROR" "Failed to upload package to server"
            exit 1
        fi

        print_status "SUCCESS" "Package uploaded successfully"
    else
        print_status "INFO" "Skipping package upload (restart/config-only mode)"
    fi
}

# Function to setup server environment
setup_server_environment() {
    if [ "$SKIP_SETUP" = false ] && [ "$RESTART_MODE" = false ]; then
        print_status "STEP" "Setting up server environment"

        # Download and execute VPS setup script
        execute "cd $DEPLOYMENT_DIR && curl -fsSL https://raw.githubusercontent.com/SynergiaOS/MojoRust/main/scripts/vps_setup.sh | bash" true

        print_status "SUCCESS" "Server environment setup completed"
    else
        print_status "INFO" "Skipping server setup (skip-setup/restart mode)"
    fi
}

# Function to extract and configure deployment
extract_and_configure() {
    if [ "$RESTART_MODE" = false ] && [ "$CONFIG_ONLY" = false ]; then
        print_status "STEP" "Extracting deployment package"

        # Extract package
        execute "cd $DEPLOYMENT_DIR && tar -xzf $PACKAGE_NAME --strip-components=1" true

        # Make scripts executable
        execute "cd $DEPLOYMENT_DIR && chmod +x scripts/*.sh" true

        # Create necessary directories
        execute "cd $DEPLOYMENT_DIR && mkdir -p logs data secrets" true

        print_status "SUCCESS" "Deployment package extracted"
    fi
}

# Function to configure environment
configure_environment() {
    print_status "STEP" "Configuring environment"

    # Copy environment template if .env doesn't exist
    execute "cd $DEPLOYMENT_DIR && [ ! -f .env ] && cp .env.production.example .env || true" true

    # Copy docker env template if .env.docker doesn't exist
    execute "cd $DEPLOYMENT_DIR && [ ! -f .env.docker ] && [ -f .env.docker.example ] && cp .env.docker.example .env.docker || true" true

    # Set deployment mode in .env
    execute "cd $DEPLOYMENT_DIR && sed -i 's/EXECUTION_MODE=.*/EXECUTION_MODE=$DEPLOY_MODE/' .env" true

    # Set server host
    execute "cd $DEPLOYMENT_DIR && sed -i 's/SERVER_HOST=.*/SERVER_HOST=$SERVER_IP/' .env" true

    if [ "$CONFIG_ONLY" = false ]; then
        print_status "SUCCESS" "Environment configured for $DEPLOY_MODE mode"
    else
        print_status "SUCCESS" "Environment configuration updated"
    fi
}

# Function to deploy bot
deploy_bot() {
    if [ "$CONFIG_ONLY" = false ]; then
        print_status "STEP" "Deploying trading bot"

        if [ "$USE_DOCKER_COMPOSE" = true ]; then
            # Docker Compose deployment
            print_status "INFO" "Using Docker Compose for deployment"

            # Transfer docker-compose files if not already done
            execute "cd $DEPLOYMENT_DIR && [ -f docker-compose.yml ] || echo 'docker-compose.yml missing'" true

            # Pull/build images
            # Use remote detection to pick docker compose variant (docker compose vs docker-compose)
            execute "cd $DEPLOYMENT_DIR && if docker compose version >/dev/null 2>&1; then COMPOSE='docker compose'; else COMPOSE='docker-compose'; fi; \n$COMPOSE pull || true; \nif [ -f ./trading-bot ]; then echo 'trading-bot binary present'; else echo 'ERROR: trading-bot binary missing in deployment directory' && exit 2; fi; \n$COMPOSE build; \n$COMPOSE up -d" true

            # Wait for services to be healthy
            print_status "INFO" "Waiting for services to start..."
            sleep 10

            # Check service status
            execute "cd $DEPLOYMENT_DIR && if docker compose version >/dev/null 2>&1; then docker compose ps; else docker-compose ps; fi" true

        elif [ "$RESTART_MODE" = true ]; then
            # Restart existing deployment
            execute "cd $DEPLOYMENT_DIR && ./scripts/restart_bot.sh" true
        else
            # Fresh deployment with filters
            execute "cd $DEPLOYMENT_DIR && ./scripts/deploy_with_filters.sh" true
        fi

        print_status "SUCCESS" "Trading bot deployed successfully"
    else
        print_status "INFO" "Skipping bot deployment (config-only mode)"
    fi
}

# Function to verify Docker Compose deployment
verify_docker_compose_deployment() {
    if [ "$USE_DOCKER_COMPOSE" = true ]; then
        print_status "STEP" "Verifying Docker Compose deployment"

        # Check if all services are running (detect compose v2 vs v1 on remote)
        execute "cd $DEPLOYMENT_DIR && if docker compose version >/dev/null 2>&1; then \n  COMPOSE='docker compose'; \nelse \n  COMPOSE='docker-compose'; \nfi; \nTOTAL=$($COMPOSE ps --services | wc -l); \nRUNNING=$($COMPOSE ps --services | xargs -r $COMPOSE ps --format '{{.Name}} {{.Status}}' | grep -c ' Up' || true); \necho \"$RUNNING $TOTAL\"" true

        # Check critical services status individually using portable command
        local critical_services=("timescaledb" "prometheus" "trading-bot")
        for service in "${critical_services[@]}"; do
            execute "cd $DEPLOYMENT_DIR && if docker compose version >/dev/null 2>&1; then \n  COMPOSE='docker compose'; \nelse \n  COMPOSE='docker-compose'; \nfi; \nSTATUS=$($COMPOSE ps $service --format '{{.Status}}' 2>/dev/null || $COMPOSE ps | grep -E '^ *$service' | awk '{print $4" "$5" "$6" "$7" "$8}'); \necho \"$STATUS\"" true
        done

        # Check logs for errors (fallback to simple grep)
        print_status "INFO" "Checking logs for errors..."
        execute "cd $DEPLOYMENT_DIR && if docker compose version >/dev/null 2>&1; then COMPOSE='docker compose'; else COMPOSE='docker-compose'; fi; $COMPOSE logs --tail=50 | grep -i error || echo 'No errors found'" true

        return
    fi
}

# Function to verify deployment
verify_deployment() {
    print_status "STEP" "Verifying deployment"

    if [ "$USE_DOCKER_COMPOSE" = true ]; then
        verify_docker_compose_deployment
        return
    fi

    # Check if bot process is running
    local bot_running=$(execute "pgrep -f 'mojo run' | wc -l" true)

    if [ "$bot_running" -gt 0 ]; then
        print_status "SUCCESS" "Trading bot is running ($bot_running processes)"
    else
        print_status "WARNING" "Trading bot process not detected - may still be starting"
    fi

    # Check API health
    print_status "INFO" "Checking API health..."
    local api_health=$(execute "curl -s http://localhost:8080/api/health || echo 'API not responding'" true)

    if [[ "$api_health" == *"healthy"* ]] || [[ "$api_health" == *"ok"* ]]; then
        print_status "SUCCESS" "API is responding"
    else
        print_status "WARNING" "API not yet responding - may still be starting"
    fi

    # Show log location
    print_status "INFO" "Log files location: $DEPLOYMENT_DIR/logs/"
}

# Function to show deployment summary
show_deployment_summary() {
    print_status "SUCCESS" "🎉 Deployment completed successfully!"

    echo ""
    print_status "INFO" "📊 Deployment Summary:"
    echo "  Server: $SSH_USER@$SERVER_IP"
    echo "  Mode: $DEPLOY_MODE"
    echo "  Directory: $DEPLOYMENT_DIR"
    echo "  Timestamp: $TIMESTAMP"
    if [ "$USE_DOCKER_COMPOSE" = true ]; then
        echo "  Deployment Type: Docker Compose"
    else
        echo "  Deployment Type: Direct Binary"
    fi

    echo ""
    print_status "INFO" "🔗 Useful URLs:"
    if [ "$USE_DOCKER_COMPOSE" = true ]; then
        echo "  Prometheus: http://$SERVER_IP:9090"
        echo "  Grafana: http://$SERVER_IP:3000 (admin/admin)"
        echo "  Trading Bot Metrics: http://$SERVER_IP:9091/metrics"
        echo "  Trading Bot Health: http://$SERVER_IP:8082/health"
        echo "  Data Consumer Metrics: http://$SERVER_IP:9191/metrics"
        echo "  pgAdmin: http://$SERVER_IP:8081"
    else
        echo "  Bot Dashboard: http://$SERVER_IP:8080"
        echo "  API Health: http://$SERVER_IP:8080/api/health"
        echo "  API Status: http://$SERVER_IP:8080/api/status"
        echo "  Grafana: http://$SERVER_IP:3000 (admin/admin)"
    fi

    echo ""
    print_status "INFO" "📋 Management Commands:"
    echo "  SSH: ssh $SSH_USER@$SERVER_IP"
    if [ "$USE_DOCKER_COMPOSE" = true ]; then
        echo "  Status: ssh $SSH_USER@$SERVER_IP 'cd $DEPLOYMENT_DIR && docker-compose ps'"
        echo "  Logs: ssh $SSH_USER@$SERVER_IP 'cd $DEPLOYMENT_DIR && docker-compose logs -f'"
        echo "  Stop: ssh $SSH_USER@$SERVER_IP 'cd $DEPLOYMENT_DIR && docker-compose down'"
        echo "  Restart: ssh $SSH_USER@$SERVER_IP 'cd $DEPLOYMENT_DIR && docker-compose restart'"
    else
        echo "  Status: ssh $SSH_USER@$SERVER_IP 'cd $DEPLOYMENT_DIR && ./scripts/server_health.sh'"
        echo "  Logs: ssh $SSH_USER@$SERVER_IP 'tail -f $DEPLOYMENT_DIR/logs/trading-bot-*.log'"
        echo "  Stop: ssh $SSH_USER@$SERVER_IP 'pkill -f mojo'"
        echo "  Restart: ssh $SSH_USER@$SERVER_IP 'cd $DEPLOYMENT_DIR && ./scripts/restart_bot.sh'"
    fi

    echo ""
    if [ "$DEPLOY_MODE" = "paper" ]; then
        print_status "WARNING" "⚠️  Bot is running in PAPER trading mode"
        print_status "INFO" "💡 Monitor performance for 24h before switching to LIVE mode"
    else
        print_status "WARNING" "🚨 Bot is running in LIVE trading mode with REAL money"
        print_status "INFO" "💡 Monitor closely and set appropriate risk limits"
    fi

    echo ""
    print_status "INFO" "📞 Support & Documentation:"
    echo "  Deployment Guide: DEPLOY_NOW.md"
    echo "  Polish Guide: DEPLOY_NOW_PL.md"
    echo "  Full Documentation: DEPLOYMENT.md"
    echo "  Issues: https://github.com/SynergiaOS/MojoRust/issues"
}

# Function to cleanup
cleanup() {
    if [ -f "$PACKAGE_NAME" ]; then
        rm -f "$PACKAGE_NAME"
        print_status "INFO" "Cleaned up local package file"
    fi
}

# Main deployment flow
main() {
    print_status "INFO" "🚀 Starting MojoRust Trading Bot Deployment"
    print_status "INFO" "Target Server: $SSH_USER@$SERVER_IP"
    print_status "INFO" "Deployment Mode: $DEPLOY_MODE"
    echo ""

    # Pre-deployment checks
    check_local_prerequisites
    check_ssh_connection

    # Create and upload package
    create_deployment_package
    upload_package

    # Server setup and configuration
    setup_server_environment
    extract_and_configure
    configure_environment

    # Deploy and verify
    deploy_bot
    verify_deployment

    # Show summary
    show_deployment_summary

    # Cleanup
    cleanup

    print_status "SUCCESS" "✅ Deployment process completed!"
}

# Handle cleanup on script exit
trap cleanup EXIT

# Start deployment
main "$@"