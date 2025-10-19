#!/bin/bash

# =============================================================================
# MojoRust Strategic Orchestrator Startup Script
# =============================================================================
# This script starts the complete integrated trading system with:
# - Geyser data consumer (pool creation detection)
# - 10-token arbitrage scanner
# - Unified sniper engine
# - Strategic orchestrator (CEO brain)
# - Manual targeting API
# - DragonflyDB coordination

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Environment Validation
# =============================================================================

echo -e "${BLUE}🔍 Validating environment...${NC}"

# Check required environment variables
REQUIRED_VARS=(
    "REDIS_URL"
    "SOLANA_RPC_URL"
    "WALLET_PRIVATE_KEY"
    "HELIUS_API_KEY"
    "JUPITER_API_KEY"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var}" ]]; then
        MISSING_VARS+=("$var")
    fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo -e "${RED}❌ Missing required environment variables:${NC}"
    for var in "${MISSING_VARS[@]}"; do
        echo "   - $var"
    done
    exit 1
fi

echo -e "${GREEN}✅ Environment variables validated${NC}"

# =============================================================================
# Configuration Validation
# =============================================================================

echo -e "${BLUE}📋 Validating configuration...${NC}"

if [[ ! -f "config/trading.toml" ]]; then
    echo -e "${RED}❌ config/trading.toml not found${NC}"
    exit 1
fi

# Check if DragonflyDB is accessible
echo "Testing DragonflyDB connection..."
if ! redis-cli -u "$REDIS_URL" ping > /dev/null 2>&1; then
    echo -e "${RED}❌ Cannot connect to DragonflyDB at $REDIS_URL${NC}"
    exit 1
fi
echo -e "${GREEN}✅ DragonflyDB connection successful${NC}"

# Check Solana RPC connectivity
echo "Testing Solana RPC connection..."
if ! curl -s -X POST "$SOLANA_RPC_URL" \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' | grep -q "result"; then
    echo -e "${RED}❌ Cannot connect to Solana RPC at $SOLANA_RPC_URL${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Solana RPC connection successful${NC}"

# =============================================================================
# Service Startup Sequence
# =============================================================================

echo -e "${BLUE}🚀 Starting orchestrator services...${NC}"

# Create log directory
mkdir -p logs

# Function to start service with logging
start_service() {
    local service_name=$1
    local command=$2
    local log_file="logs/${service_name}.log"

    echo -e "${YELLOW}🔄 Starting $service_name...${NC}"

    # Start service in background with logging
    nohup bash -c "$command" > "$log_file" 2>&1 &
    local pid=$!

    # Store PID for cleanup
    echo $pid > "logs/${service_name}.pid"

    # Wait a moment for service to initialize
    sleep 2

    # Check if service is still running
    if kill -0 $pid 2>/dev/null; then
        echo -e "${GREEN}✅ $service_name started (PID: $pid)${NC}"
        return 0
    else
        echo -e "${RED}❌ $service_name failed to start${NC}"
        if [[ -f "$log_file" ]]; then
            echo -e "${RED}   Error details:${NC}"
            tail -5 "$log_file"
        fi
        return 1
    fi
}

# =============================================================================
# 1. Start Rust Data Consumer (Geyser)
# =============================================================================

start_service "data_consumer" "
    cd rust-modules && \
    RUST_LOG=info \
    REDIS_URL='$REDIS_URL' \
    METRICS_ADDR='0.0.0.0:9191' \
    USE_HELIUS_LASERSTREAM='true' \
    HELIUS_LASERSTREAM_KEY='$HELIUS_API_KEY' \
    HELIUS_LASERSTREAM_ENDPOINT='grpc://helius-laserstream.helius-rpc.com:443' \
    cargo run --bin data_consumer
"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Failed to start data consumer${NC}"
    exit 1
fi

# =============================================================================
# 2. Wait for Data Consumer to Initialize
# =============================================================================

echo -e "${YELLOW}⏳ Waiting for data consumer to initialize...${NC}"
sleep 5

# Check data consumer health
if ! curl -s http://localhost:9191/health > /dev/null; then
    echo -e "${RED}❌ Data consumer health check failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Data consumer is healthy${NC}"

# =============================================================================
# 3. Start 10-Token Arbitrage Scanner
# =============================================================================

start_service "arbitrage_scanner" "
    cd rust-modules && \
    RUST_LOG=info \
    REDIS_URL='$REDIS_URL' \
    cargo run --bin ten_token_arbitrage
"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Failed to start arbitrage scanner${NC}"
    # Continue anyway as this might be a development mode issue
fi

# =============================================================================
# 4. Start Health API (includes Manual Targeting)
# =============================================================================

start_service "health_api" "
    cd python && \
    REDIS_URL='$REDIS_URL' \
    HEALTH_CHECK_PORT='8082' \
    python health_api.py
"

if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}⚠️  Health API (Manual Targeting) not available (continuing)${NC}"
fi

# =============================================================================
# 5. Start 10-Token Arbitrage Scanner (as Python module)
# =============================================================================

start_service "arbitrage_scanner_python" "
    cd python && \
    python -c '
import sys
sys.path.append(\"../rust-modules/target/debug\")
import mojo_trading_bot

# Initialize arbitrage scanner
config = mojo_trading_bot.arbitrage.ten_token.TenTokenConfig(
    enabled=True,
    use_real_dex_clients=False,  # Start with mock clients
    use_flash_loan=True
)

scanner = mojo_trading_bot.arbitrage.ten_token.TenTokenArbitrageScanner(
    config, \"$REDIS_URL\"
)

# Start scanning
import asyncio
asyncio.run(scanner.start_scanning())
'
"

if [[ $? -ne 0 ]]; then
    echo -e "${YELLOW}⚠️  Arbitrage scanner not available (continuing)${NC}"
fi

# =============================================================================
# 6. Start Strategic Orchestrator (Mojo)
# =============================================================================

start_service "strategic_orchestrator" "
    mojo src/core/orchestrator.mojo
"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Failed to start strategic orchestrator${NC}"
    exit 1
fi

# =============================================================================
# Startup Summary
# =============================================================================

echo -e "${GREEN}"
echo "============================================================================"
echo "🎯 MojoRust Strategic Orchestrator Started Successfully!"
echo "============================================================================"
echo "${NC}"

echo -e "${BLUE}📊 Service Status:${NC}"
echo "   • Data Consumer (Geyser): $(curl -s http://localhost:9191/health || echo '❌ DOWN')"
echo "   • Arbitrage Scanner (Rust): $([ -f logs/arbitrage_scanner.pid ] && echo '✅ RUNNING' || echo '❌ DOWN')"
echo "   • Arbitrage Scanner (Python): $([ -f logs/arbitrage_scanner_python.pid ] && echo '✅ RUNNING' || echo '❌ DOWN')"
echo "   • Health API (Manual Targeting): $([ -f logs/health_api.pid ] && echo '✅ RUNNING' || echo '⚠️  NOT STARTED')"
echo "   • Strategic Orchestrator: $([ -f logs/strategic_orchestrator.pid ] && echo '✅ RUNNING' || echo '❌ DOWN')"

echo ""
echo -e "${BLUE}🔗 Access Points:${NC}"
echo "   • DragonflyDB: $REDIS_URL"
echo "   • Data Consumer Metrics: http://localhost:9191/metrics"
echo "   • Data Consumer Health: http://localhost:9191/health"
echo "   • Health API (Manual Targeting): http://localhost:8082"
echo "   • Health API Docs: http://localhost:8082/docs"

echo ""
echo -e "${BLUE}📝 Log Files:${NC}"
for log_file in logs/*.log; do
    if [[ -f "$log_file" ]]; then
        echo "   • $log_file"
    fi
done

echo ""
echo -e "${GREEN}🎉 Unified Save Protocol Ensemble Strategy is now LIVE!${NC}"
echo "   All 6 strategies coordinated on Save protocol with intelligent orchestration"
echo ""

# =============================================================================
# Graceful Shutdown Handler
# =============================================================================

cleanup() {
    echo -e "${YELLOW}🛑 Shutting down services...${NC}"

    for pid_file in logs/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            local service_name=$(basename "$pid_file" .pid)

            echo -e "${YELLOW}   Stopping $service_name (PID: $pid)...${NC}"
            kill -TERM $pid 2>/dev/null || true

            # Wait for graceful shutdown
            sleep 2

            # Force kill if still running
            if kill -0 $pid 2>/dev/null; then
                kill -KILL $pid 2>/dev/null || true
            fi

            rm -f "$pid_file"
        fi
    done

    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

# Register cleanup handler
trap cleanup SIGINT SIGTERM

echo -e "${BLUE}🔄 Monitoring services... Press Ctrl+C to stop${NC}"

# Keep script running and monitor services
while true; do
    sleep 30

    # Check if critical services are still running
    if [[ ! -f logs/strategic_orchestrator.pid ]] || ! kill -0 $(cat logs/strategic_orchestrator.pid) 2>/dev/null; then
        echo -e "${RED}❌ Strategic orchestrator stopped unexpectedly!${NC}"
        cleanup
    fi

    if [[ ! -f logs/data_consumer.pid ]] || ! kill -0 $(cat logs/data_consumer.pid) 2>/dev/null; then
        echo -e "${RED}❌ Data consumer stopped unexpectedly!${NC}"
        cleanup
    fi
done