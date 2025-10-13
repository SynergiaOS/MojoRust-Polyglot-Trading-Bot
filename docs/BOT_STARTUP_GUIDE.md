# 🚀 MojoRust Trading Bot - Startup Guide

## Overview

This guide covers the complete startup process for the MojoRust Trading Bot, including environment configuration, wallet verification, and various startup methods. The bot supports multiple execution modes (paper, live, test) and can be run using different methods (direct Mojo execution, compiled binary, or deployment script).

## Prerequisites

### System Requirements
- **Operating System**: Linux (Ubuntu 20.04+, CentOS 8+), macOS 10.15+, or Windows 10+ with WSL2
- **Memory**: Minimum 4GB RAM, 8GB+ recommended
- **Storage**: 10GB+ free disk space
- **Network**: Stable internet connection with access to Solana RPC endpoints

### Required Software
- **Mojo 24.4+**: https://www.modular.com/mojo
- **Rust 1.70+**: https://rustup.rs/
- **Solana CLI 1.16+**: https://docs.solana.com/cli/install-solana-cli-tools
- **Git**: For cloning the repository
- **Curl**: For network operations and API calls

### Environment Setup
```bash
# Verify Mojo installation
mojo --version

# Verify Rust installation
rustc --version
cargo --version

# Verify Solana CLI
solana --version

# Clone repository (if not already done)
git clone https://github.com/SynergiaOS/MojoRust.git
cd MojoRust
```

## Quick Start (5 Minutes)

For the fastest startup path, see the [Quick Start Guide](QUICK_START.md).

## Environment Configuration

### 1. Environment File Setup
The bot uses a `.env` file for configuration. Copy the appropriate template:

```bash
# For development/testing
cp .env.example .env

# For production deployment
cp .env.production.example .env
```

### 2. Required Configuration
Edit `.env` with your specific configuration:

```bash
# Server Configuration
SERVER_HOST=localhost          # Server bind address
SERVER_PORT=8080              # Server port

# Trading Configuration
EXECUTION_MODE=paper          # paper, live, or test
INITIAL_CAPITAL=1.0          # Initial capital in SOL
MAX_POSITION_SIZE=0.10        # Maximum position size as percentage
MAX_DRAWDOWN=0.15           # Maximum allowed drawdown

# API Configuration (required for live/paper modes)
HELIUS_API_KEY=your_helius_api_key
QUICKNODE_RPC_URL=your_quicknode_rpc_url
WALLET_ADDRESS=your_solana_wallet_address

# Optional Configuration
AGGRESSIVE_FILTERING=false   # Enable aggressive trade filtering
ENABLE_ALERTS=false         # Enable trading alerts
ALERT_EMAIL=your@email.com  # Email for alerts (if enabled)
```

### 3. Wallet Configuration
See the [Wallet Setup Guide](WALLET_SETUP_GUIDE.md) for detailed wallet setup instructions.

### 4. API Key Setup

#### Helius API Key
1. Sign up at https://www.helius.dev/
2. Create a new project
3. Copy your API key to `HELIUS_API_KEY`

#### QuickNode RPC Endpoint
1. Sign up at https://www.quicknode.com/
2. Create a new Solana endpoint
3. Copy your RPC URL to `QUICKNODE_RPC_URL`

## Startup Methods

### Method 1: Direct Mojo Execution (Recommended for Development)

Start the bot directly using Mojo:

```bash
# Basic startup (paper mode)
./scripts/start_bot.sh

# Live trading with confirmation
./scripts/start_bot.sh --mode=live

# Custom capital amount
./scripts/start_bot.sh --capital=10.0

# Daemon mode (background)
./scripts/start_bot.sh --daemon

# Verbose output
./scripts/start_bot.sh --verbose

# Aggressive filtering
./scripts/start_bot.sh --aggressive-filtering
```

### Method 2: Compiled Binary (Recommended for Production)

Build and run as a binary:

```bash
# Build and run
./scripts/start_bot.sh --method=build

# Build and run as daemon
./scripts/start_bot.sh --method=build --daemon

# Live mode with custom settings
./scripts/start_bot.sh --method=build --mode=live --capital=5.0 --daemon
```

### Method 3: Deployment Script (Full Infrastructure)

Use the comprehensive deployment script:

```bash
# Full deployment with infrastructure
./scripts/start_bot.sh --method=deploy

# Deploy with custom configuration
./scripts/start_bot.sh --method=deploy --mode=live --aggressive-filtering
```

## Trading Modes

### Paper Trading Mode (Default)
- **Risk**: No real money at risk
- **Purpose**: Testing strategies with simulated trades
- **Configuration**: `EXECUTION_MODE=paper`
- **Usage**: Ideal for initial testing and strategy development

```bash
./scripts/start_bot.sh --mode=paper
```

### Live Trading Mode
- **Risk**: Real money at risk
- **Purpose**: Actual trading with real funds
- **Configuration**: `EXECUTION_MODE=live`
- **Requirements**:
  - Verified wallet with sufficient SOL balance
  - Valid API keys
  - Manual confirmation required

```bash
./scripts/start_bot.sh --mode=live
# Type 'LIVE' when prompted to confirm
```

### Test Mode
- **Risk**: No real money at risk
- **Purpose**: Development and integration testing
- **Configuration**: `EXECUTION_MODE=test`
- **Usage**: For development and debugging

```bash
./scripts/start_bot.sh --mode=test
```

## Command Line Options

### Basic Options
- `--mode=<paper|live|test>`: Set trading mode
- `--method=<direct|build|deploy>`: Set startup method
- `--daemon`: Run as background process
- `--verbose`: Enable verbose output
- `--help`: Show help message

### Advanced Options
- `--capital=<amount>`: Override initial capital amount
- `--aggressive-filtering`: Enable aggressive trade filtering

### Examples
```bash
# Start in paper mode with direct execution
./scripts/start_bot.sh

# Start in live mode as daemon with 10 SOL capital
./scripts/start_bot.sh --mode=live --daemon --capital=10.0

# Build and run with aggressive filtering
./scripts/start_bot.sh --method=build --aggressive-filtering

# Full deployment in test mode
./scripts/start_bot.sh --method=deploy --mode=test
```

## Wallet Verification

The bot automatically runs wallet verification before startup:

### Automatic Verification
```bash
# The startup script automatically calls:
./scripts/check_wallet.sh --verbose
```

### Manual Wallet Check
```bash
# Run wallet verification manually
./scripts/check_wallet.sh --verbose

# Fix wallet permissions automatically
./scripts/check_wallet.sh --fix --verbose

# Check custom wallet path
./scripts/check_wallet.sh --wallet-path /path/to/wallet.json
```

### Verification Checklist
- ✅ Wallet file exists and is readable
- ✅ File permissions are secure (600)
- ✅ JSON format is valid (64-element array)
- ✅ Public key extraction works
- ✅ Network connectivity to Solana RPC
- ✅ Environment variables match wallet

## Daemon Mode

Running the bot as a daemon (background process):

### Starting as Daemon
```bash
./scripts/start_bot.sh --daemon
```

### Daemon Management
```bash
# Check if bot is running
ps aux | grep trading-bot

# View real-time logs
tail -f logs/trading-bot-$(date +%Y%m%d).log

# Stop the bot gracefully
kill $(cat logs/trading-bot.pid)

# Restart the bot
./scripts/start_bot.sh --daemon --mode=paper
```

### Log Files
- **Location**: `logs/trading-bot-YYYYMMDD.log`
- **Rotation**: New log file created each day
- **Content**: Trading activity, errors, performance metrics
- **PID File**: `logs/trading-bot.pid`

## Monitoring and Management

### Health Checks
```bash
# API health check
curl http://localhost:8080/api/health

# Bot status
curl http://localhost:8080/api/status

# Recent trades
curl http://localhost:8080/api/trades/recent

# Performance metrics
curl http://localhost:8080/api/metrics
```

### System Monitoring
```bash
# Check system resources
./scripts/server_health.sh

# Profile bot performance
./scripts/profile_bot.sh --duration=300

# Memory usage check
./scripts/profile_bot.sh memory-check
```

### Log Analysis
```bash
# View recent errors
grep -i error logs/trading-bot-*.log | tail -20

# Monitor trading activity
grep -i "trade\|position" logs/trading-bot-*.log | tail -50

# Performance analysis
./scripts/profile_bot.sh --analyze-only --output logs/profile-20231201_120000.log
```

## Troubleshooting

### Common Startup Issues

#### Environment Configuration Errors
```bash
# Validate configuration
./scripts/validate_config.sh

# Check .env file permissions
ls -la .env

# Test environment loading
source .env && env | grep -E "(EXECUTION_MODE|SERVER_|WALLET_)"
```

#### Wallet Verification Failures
```bash
# Run detailed wallet check
./scripts/check_wallet.sh --verbose

# Fix common wallet issues
./scripts/check_wallet.sh --fix

# Check wallet file
ls -la ~/.config/solana/id.json
stat -c "%a" ~/.config/solana/id.json
```

#### API Connection Issues
```bash
# Test Helius API
curl -H "Authorization: Bearer $HELIUS_API_KEY" \
     https://api.helius.xyz/v0/tokens/addresses

# Test QuickNode RPC
curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
     $QUICKNODE_RPC_URL

# Test network connectivity
ping api.mainnet-beta.solana.com
```

#### Dependency Issues
```bash
# Check required tools
which mojo rustc solana git curl

# Update dependencies
./scripts/update_dependencies.sh

# Rebuild if necessary
rm -rf target/
cargo build --release
```

### Performance Issues

#### High Memory Usage
```bash
# Check memory usage
free -h
ps aux | grep trading-bot

# Profile memory usage
./scripts/profile_bot.sh --memory-profiling

# Restart if needed
./scripts/restart_bot.sh
```

#### Slow Response Times
```bash
# Check system load
uptime
htop

# Profile performance
./scripts/profile_bot.sh --cpu-profiling

# Check network latency
ping -c 10 api.mainnet-beta.solana.com
```

## Security Best Practices

### Environment Security
- **Never commit `.env` files** to version control
- **Use strong API keys** and rotate them regularly
- **Limit API access** to specific IP addresses when possible
- **Monitor API usage** for unusual activity

### Wallet Security
- **Use hardware wallets** for production environments
- **Keep wallet backups** in encrypted, offline storage
- **Monitor wallet activity** regularly
- **Use multi-signature wallets** for large amounts

### System Security
- **Run as non-root user** whenever possible
- **Use firewall rules** to restrict access
- **Enable log monitoring** for security events
- **Regular system updates** and security patches

## Advanced Configuration

### Custom Environment Variables
```bash
# Add custom configuration to .env
CUSTOM_STRATEGY_ENABLED=true
CUSTOM_RISK_THRESHOLD=0.05
CUSTOM_TIMEFRAME=1m
```

### Multiple Bot Instances
```bash
# Run multiple instances with different configurations
cp .env .env.bot1
cp .env .env.bot2

# Start with custom environment
ENV_FILE=.env.bot1 ./scripts/start_bot.sh --daemon --port=8080
ENV_FILE=.env.bot2 ./scripts/start_bot.sh --daemon --port=8081
```

### Integration with External Systems
```bash
# Webhook configuration
WEBHOOK_URL=https://your-webhook-endpoint.com/trades
WEBHOOK_ENABLED=true

# Database integration
DATABASE_URL=postgresql://user:pass@localhost/trading_bot
DATABASE_ENABLED=true
```

## Migration and Upgrades

### Upgrading Bot Version
```bash
# Backup current configuration
cp .env .env.backup
cp -r logs/ logs.backup/

# Update code
git pull origin main

# Update dependencies
./scripts/update_dependencies.sh

# Restart with same configuration
./scripts/start_bot.sh --daemon
```

### Migrating to New Server
```bash
# Export configuration
tar -czf bot-backup.tar.gz .env logs/ data/

# Import on new server
tar -xzf bot-backup.tar.gz

# Verify and start
./scripts/validate_config.sh
./scripts/start_bot.sh --daemon
```

## Support and Resources

### Documentation
- **Main Documentation**: [README.md](../README.md)
- **Deployment Guide**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Wallet Setup**: [WALLET_SETUP_GUIDE.md](WALLET_SETUP_GUIDE.md)
- **API Documentation**: [API_REFERENCE.md](API_REFERENCE.md)

### Community and Support
- **GitHub Repository**: https://github.com/SynergiaOS/MojoRust
- **Issues and Bug Reports**: https://github.com/SynergiaOS/MojoRust/issues
- **Discord Community**: [Invite Link]
- **Documentation Wiki**: https://github.com/SynergiaOS/MojoRust/wiki

### Quick Reference Commands
```bash
# Start bot (paper mode)
./scripts/start_bot.sh

# Start bot (live mode)
./scripts/start_bot.sh --mode=live

# Check bot status
curl http://localhost:8080/api/status

# View logs
tail -f logs/trading-bot-$(date +%Y%m%d).log

# Stop bot
kill $(cat logs/trading-bot.pid)

# Restart bot
./scripts/restart_bot.sh

# Health check
./scripts/server_health.sh
```

---

**⚠️ IMPORTANT**: Always start with paper trading mode to validate your configuration and strategy performance before switching to live trading with real funds.

**🔒 SECURITY**: Never share your private keys, API keys, or `.env` files. Use secure channels for all sensitive information and consider using hardware wallets for production environments.