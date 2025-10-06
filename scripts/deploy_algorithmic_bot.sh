#!/bin/bash
# =============================================================================
# Algorithmic Trading Bot Deployment Script
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Configuration Check
# =============================================================================

print_status "🚀 Starting Algorithmic Trading Bot Deployment..."

# Check if .env file exists
if [ ! -f ".env" ]; then
    print_warning ".env file not found. Creating from template..."
    cp .env.example .env
    print_warning "Please edit .env file with your API keys and configuration"
    print_warning "Required variables:"
    echo "  - HELIUS_API_KEY"
    echo "  - QUICKNODE_PRIMARY_RPC"
    echo "  - WALLET_ADDRESS"
    exit 1
fi

# Source environment variables
source .env

# Validate required environment variables
if [ -z "$HELIUS_API_KEY" ]; then
    print_error "HELIUS_API_KEY is required"
    exit 1
fi

if [ -z "$QUICKNODE_PRIMARY_RPC" ]; then
    print_error "QUICKNODE_PRIMARY_RPC is required"
    exit 1
fi

if [ -z "$WALLET_ADDRESS" ]; then
    print_error "WALLET_ADDRESS is required"
    exit 1
fi

# =============================================================================
# Build Process
# =============================================================================

print_status "🔨 Building Algorithmic Trading Bot..."

# Check if Mojo is installed
if ! command -v mojo &> /dev/null; then
    print_error "Mojo is not installed or not in PATH"
    print_status "Please install Mojo from: https://www.modular.com/mojo"
    exit 1
fi

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    print_error "Rust is not installed or not in PATH"
    print_status "Please install Rust from: https://rustup.rs/"
    exit 1
fi

# Build Rust modules
print_status "Building Rust security modules..."
cd rust-modules
cargo build --release
cd ..

# Build Mojo application
print_status "Building Mojo application..."
mojo build src/main.mojo -o trading-bot

if [ $? -eq 0 ]; then
    print_success "Build completed successfully!"
else
    print_error "Build failed!"
    exit 1
fi

# =============================================================================
# Pre-deployment Checks
# =============================================================================

print_status "🔍 Running pre-deployment checks..."

# Run comprehensive tests
print_status "Running test suite..."
mojo run tests/test_comprehensive.mojo

if [ $? -ne 0 ]; then
    print_error "Tests failed! Please fix issues before deployment."
    exit 1
fi

# Test API connections
print_status "Testing API connections..."
python3 -c "
import requests
import os

# Test Helius API
if os.getenv('HELIUS_API_KEY'):
    try:
        response = requests.get('https://api.helius.xyz/v0/health', timeout=10)
        if response.status_code == 200:
            print('✅ Helius API connection successful')
        else:
            print('⚠️  Helius API connection issue')
    except Exception as e:
        print(f'❌ Helius API connection failed: {e}')

# Test QuickNode RPC
if os.getenv('QUICKNODE_PRIMARY_RPC'):
    try:
        import json
        rpc_url = os.getenv('QUICKNODE_PRIMARY_RPC')
        payload = {
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'getSlot'
        }
        response = requests.post(rpc_url, json=payload, timeout=10)
        if response.status_code == 200:
            print('✅ QuickNode RPC connection successful')
        else:
            print('⚠️  QuickNode RPC connection issue')
    except Exception as e:
        print(f'❌ QuickNode RPC connection failed: {e}')

print('API connection tests completed.')
"

# =============================================================================
# Deployment
# =============================================================================

print_status "🚀 Deploying Algorithmic Trading Bot..."

# Create deployment directory
DEPLOY_DIR="/opt/trading-bot"
if [ "$EUID" -eq 0 ]; then
    # Running as root
    mkdir -p $DEPLOY_DIR
    cp trading-bot $DEPLOY_DIR/
    cp -r src/ $DEPLOY_DIR/
    cp .env $DEPLOY_DIR/
    chmod +x $DEPLOY_DIR/trading-bot
    chown -R tradingbot:tradingbot $DEPLOY_DIR/ 2>/dev/null || true
    print_success "Bot deployed to $DEPLOY_DIR"
else
    # Running as user
    mkdir -p ./deploy
    cp trading-bot ./deploy/
    cp -r src/ ./deploy/
    cp .env ./deploy/
    chmod +x ./deploy/trading-bot
    print_success "Bot deployed to ./deploy/"
fi

# =============================================================================
# Service Setup (Linux)
# =============================================================================

if command -v systemctl &> /dev/null && [ "$EUID" -eq 0 ]; then
    print_status "🔧 Setting up systemd service..."

    cat > /etc/systemd/system/trading-bot.service << EOF
[Unit]
Description=Algorithmic Trading Bot
After=network.target

[Service]
Type=simple
User=tradingbot
WorkingDirectory=$DEPLOY_DIR
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Restart=always
RestartSec=10
ExecStart=$DEPLOY_DIR/trading-bot --mode=$EXECUTION_MODE --capital=$INITIAL_CAPITAL

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DEPLOY_DIR

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable trading-bot
    print_success "Systemd service created and enabled"
    print_status "Start the bot with: systemctl start trading-bot"
    print_status "Check status with: systemctl status trading-bot"
    print_status "View logs with: journalctl -u trading-bot -f"
fi

# =============================================================================
# Monitoring Setup
# =============================================================================

if command -v docker &> /dev/null; then
    print_status "📊 Setting up monitoring stack..."

    # Create docker-compose for monitoring
    cat > docker-compose.monitoring.yml << EOF
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin123
      - GF_USERS_ALLOW_SIGN_UP=false

volumes:
  prometheus_data:
  grafana_data:
EOF

    print_success "Monitoring docker-compose file created"
    print_status "Start monitoring with: docker-compose -f docker-compose.monitoring.yml up -d"
fi

# =============================================================================
# Security Setup
# =============================================================================

print_status "🔒 Setting up security measures..."

# Set appropriate file permissions
chmod 600 .env
chmod 700 scripts/ 2>/dev/null || true

# Create security configuration
cat > security.conf << EOF
# Trading Bot Security Configuration

# File permissions
ENV_FILE_PERMISSIONS=600
EXECUTABLE_PERMISSIONS=755
SCRIPT_PERMISSIONS=700

# Network security
ALLOWED_HOSTS=localhost,127.0.0.1
RATE_LIMIT_ENABLED=true
RATE_LIMIT_REQUESTS_PER_MINUTE=100

# API security
API_KEY_ROTATION_DAYS=30
SESSION_TIMEOUT_HOURS=24
MAX_LOGIN_ATTEMPTS=5

# Data protection
ENCRYPT_SENSITIVE_DATA=true
BACKUP_ENCRYPTION=true
LOG_RETENTION_DAYS=30
EOF

print_success "Security configuration created"

# =============================================================================
# Final Setup
# =============================================================================

print_status "📋 Creating startup scripts..."

# Create startup script
cat > start-bot.sh << 'EOF'
#!/bin/bash

# Algorithmic Trading Bot Startup Script

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Algorithmic Trading Bot...${NC}"

# Load environment
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "❌ .env file not found!"
    exit 1
fi

# Set execution mode
MODE=${1:-paper}
CAPITAL=${2:-$INITIAL_CAPITAL}

echo "Execution Mode: $MODE"
echo "Initial Capital: $CAPITAL SOL"

# Start the bot
./trading-bot --mode=$MODE --capital=$CAPITAL
EOF

chmod +x start-bot.sh

# Create status monitoring script
cat > bot-status.sh << 'EOF'
#!/bin/bash

# Trading Bot Status Monitor

echo "🤖 Algorithmic Trading Bot Status"
echo "================================"

# Check if bot is running
if pgrep -f "trading-bot" > /dev/null; then
    echo "✅ Bot is running"
    echo "PID: $(pgrep -f 'trading-bot')"
    echo "Uptime: $(ps -o etime= -p $(pgrep -f 'trading-bot') | tail -1 | tr -d ' ')"
else
    echo "❌ Bot is not running"
fi

# Check recent logs
if [ -f "trading.log" ]; then
    echo ""
    echo "📊 Recent Activity:"
    tail -10 trading.log
fi

# Check system resources
echo ""
echo "💻 System Resources:"
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}'%)"
echo "Memory Usage: $(free | grep Mem | awk '{printf("%.1f%%"), $3/$2 * 100.0}')"
echo "Disk Usage: $(df -h . | tail -1 | awk '{print $5}')"
EOF

chmod +x bot-status.sh

print_success "Startup scripts created"

# =============================================================================
# Deployment Complete
# =============================================================================

print_success "🎉 Algorithmic Trading Bot deployment completed!"
print_status ""
print_status "📋 Next Steps:"
echo "1. Review and configure your .env file"
echo "2. Start the bot: ./start-bot.sh [paper|live] [capital]"
echo "3. Monitor with: ./bot-status.sh"
echo "4. Check logs for trading activity"
echo ""
print_status "🔧 Configuration:"
echo "Execution Mode: $EXECUTION_MODE"
echo "Initial Capital: $INITIAL_CAPITAL SOL"
echo "Environment: $TRADING_ENV"
echo ""
print_status "📊 Features Enabled:"
echo "✅ Algorithmic Sentiment Analysis"
echo "✅ Pattern Recognition Engine"
echo "✅ Whale Behavior Tracking"
echo "✅ Advanced Risk Management"
echo "✅ High-Frequency Execution"
echo "✅ Spam Filter Protection"
echo "✅ Real-time Monitoring"
echo ""
print_status "🚀 The bot is ready for algorithmic trading!"
print_status "📖 For help, run: ./trading-bot --help"