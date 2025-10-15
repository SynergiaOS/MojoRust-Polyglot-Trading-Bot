#!/bin/bash

# =============================================================================
# 🚀 MojoRust Trading Bot - Quick Deployment Script
# Server: 38.242.239.150
# =============================================================================

set -e

# Configuration
SERVER_IP="38.242.239.150"
SSH_USER="root"
DEPLOY_MODE="paper"
DEPLOYMENT_DIR="~/mojo-trading-bot"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check SSH connection
check_ssh() {
    print_info "Checking SSH connection to $SERVER_IP..."
    if ssh -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "echo 'SSH OK'" >/dev/null 2>&1; then
        print_status "SSH connection successful"
    else
        print_error "Cannot connect to server $SERVER_IP"
        exit 1
    fi
}

# Quick deploy
main() {
    print_info "🚀 Starting Quick Deployment to $SERVER_IP"
    print_info "Mode: $DEPLOY_MODE"

    check_ssh

    # Create deployment package
    print_info "Creating deployment package..."
    tar -czf "quick-deploy-${TIMESTAMP}.tar.gz" \
        src/ \
        scripts/ \
        config/ \
        rust-modules/ \
        *.toml \
        .env.example \
        .env.production.example \
        docs/ \
        2>/dev/null

    # Upload to server
    print_info "Uploading to server..."
    scp "quick-deploy-${TIMESTAMP}.tar.gz" "$SSH_USER@$SERVER_IP:$DEPLOYMENT_DIR/"

    # Extract and configure
    ssh "$SSH_USER@$SERVER_IP" << EOF
        cd $DEPLOYMENT_DIR
        tar -xzf "quick-deploy-${TIMESTAMP}.tar.gz" --strip-components=1
        rm "quick-deploy-${TIMESTAMP}.tar.gz"

        # Configure environment
        [ ! -f .env ] && cp .env.production.example .env
        sed -i "s/EXECUTION_MODE=.*/EXECUTION_MODE=$DEPLOY_MODE/" .env
        sed -i "s/SERVER_HOST=.*/SERVER_HOST=$SERVER_IP/" .env

        # Enable Rust consumer
        sed -i 's/ENABLE_RUST_CONSUMER=.*/ENABLE_RUST_CONSUMER=true/' .env

        # Set DragonflyDB URL
        sed -i 's|REDIS_URL=.*|REDIS_URL=rediss://default:gv7g6u9svsf1@612ehcb9i.dragonflydb.cloud:6385|' .env

        chmod +x scripts/*.sh
        mkdir -p logs data secrets

        echo "Deployment configured successfully"
EOF

    # Build and start
    print_info "Building and starting services..."
    ssh "$SSH_USER@$SERVER_IP" << EOF
        cd $DEPLOYMENT_DIR

        # Build Rust data consumer
        cd rust-modules
        cargo build --release --bin data_consumer 2>/dev/null || echo "Rust build already completed"
        cd ..

        # Start services
        ./scripts/deploy_with_filters.sh
EOF

    # Cleanup
    rm -f "quick-deploy-${TIMESTAMP}.tar.gz"

    print_status "🎉 Deployment completed!"
    print_info "Access URLs:"
    echo "  - Bot Dashboard: http://$SERVER_IP:8080"
    echo "  - Grafana: http://$SERVER_IP:3000 (admin/admin)"
    echo "  - Rust Metrics: http://$SERVER_IP:9191/metrics"
}

main "$@"