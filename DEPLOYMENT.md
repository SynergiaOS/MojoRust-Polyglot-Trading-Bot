# Trading Bot Deployment Guide

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial VPS Setup](#initial-vps-setup)
3. [Install Dependencies](#install-dependencies)
4. [Configure Environment](#configure-environment)
5. [Test Deployment](#test-deployment)
6. [Production Deployment](#production-deployment)
7. [Monitoring & Maintenance](#monitoring--maintenance)
8. [Troubleshooting](#troubleshooting)
9. [Security Best Practices](#security-best-practices)

---

## Prerequisites

### 1. VPS Requirements

**Minimum Specifications:**
- **OS**: Ubuntu 22.04 LTS or newer
- **CPU**: 2+ cores (Intel i5/AMD Ryzen 5 or better)
- **RAM**: 4GB+ (8GB+ recommended)
- **Storage**: 20GB+ SSD
- **Network**: Stable internet connection with <100ms latency to Solana RPCs

**Recommended Specifications:**
- **CPU**: 4+ cores (Intel i7/AMD Ryzen 7)
- **RAM**: 8GB+
- **Storage**: 50GB+ NVMe SSD

### 2. Required Accounts & Services

**Essential Services:**
1. **Infisical Account** (Recommended)
   - Sign up at [app.infisical.com](https://app.infisical.com/)
   - Create project and get credentials
   - Store API keys securely

2. **Helius API** ($49/month Premium)
   - Required for: Token metadata, holder analysis, liquidity checks
   - Get API key at [helius.dev](https://www.helius.dev)

3. **QuickNode RPC** ($49/month Premium)
   - Required for: RPC access, transaction execution
   - Get endpoint at [quicknode.com](https://www.quicknode.com)

4. **Solana Wallet**
   - Create new wallet for trading (never use main wallet!)
   - Export private key securely

**Optional Services:**
- **DexScreener** (Free) - Market data
- **Jupiter** (Free) - DEX aggregation

---

## Initial VPS Setup

### Step 1: Connect to VPS

```bash
# Connect to your VPS
ssh root@YOUR_VPS_IP

# Update system packages
apt update && apt upgrade -y

# Install essential packages
apt install -y git curl wget build-essential software-properties-common \
    unzip htop iotop nethogs ufw

# Create trading bot user (security best practice)
adduser --disabled-password --gecos "" tradingbot
usermod -aG sudo tradingbot
```

### Step 2: Configure Firewall

```bash
# Enable firewall with minimal ports
ufw --force enable
ufw allow 22/tcp  # SSH
ufw allow 9090/tcp  # Prometheus metrics (optional)
ufw allow 3000/tcp  # Grafana dashboard (optional)

# Check firewall status
ufw status
```

### Step 3: Switch to Trading Bot User

```bash
# Switch to trading bot user
su - tradingbot

# Verify user context
whoami  # Should show "tradingbot"
pwd     # Should show "/home/tradingbot"
```

---

## Install Dependencies

### Step 1: Install Mojo

```bash
# Download and install Mojo Modular
curl -s https://get.modular.com | sh -

# Add Mojo to PATH
echo 'export PATH="$HOME/.modular/pkg/packages.modular.com_mojo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify installation
mojo --version
# Should show: Mojo 24.4+

# Test basic functionality
mojo -c "print('Mojo is working!')"
```

### Step 2: Install Rust

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add Rust to PATH
echo 'source ~/.cargo/env' >> ~/.bashrc
source ~/.bashrc

# Verify installation
rustc --version
cargo --version
```

### Step 3: Install Infisical CLI

```bash
# Install Infisical CLI
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo bash

# Update package list and install
sudo apt-get update
sudo apt-get install -y infisical

# Verify installation
infisical --version
```

---

## Configure Environment

### Option A: Using Infisical (Recommended)

#### Step 1: Login to Infisical

```bash
# Login to Infisical
infisical login

# Follow the prompts to authenticate with your browser
```

#### Step 2: Configure Project

```bash
# Set your project details
export INFISICAL_PROJECT_ID="your_project_id_here"
export INFISICAL_ENVIRONMENT="production"

# Add to .bashrc for persistence
echo 'export INFISICAL_PROJECT_ID="your_project_id_here"' >> ~/.bashrc
echo 'export INFISICAL_ENVIRONMENT="production"' >> ~/.bashrc
```

#### Step 3: Store Secrets in Infisical

Store these secrets in your Infisical project:
- `HELIUS_API_KEY`
- `QUICKNODE_PRIMARY_RPC`
- `QUICKNODE_SECONDARY_RPC`
- `WALLET_ADDRESS`
- `WALLET_PRIVATE_KEY` (encrypted)
- `INITIAL_CAPITAL`

### Option B: Using Environment Variables

#### Step 1: Create .env File

```bash
# Create environment file
nano .env
```

#### Step 2: Add Configuration

```bash
# Environment
APP_ENV=production
EXECUTION_MODE=paper  # Start with paper trading!

# API Keys
HELIUS_API_KEY=your_helius_api_key_here
QUICKNODE_PRIMARY_RPC=https://your-endpoint.solana-mainnet.quiknode.pro/your-key/
QUICKNODE_SECONDARY_RPC=https://your-backup-endpoint.solana-mainnet.quiknode.pro/your-key/

# Wallet Configuration
WALLET_ADDRESS=your_solana_wallet_address_here
WALLET_PRIVATE_KEY_PATH=~/.config/solana/id.json

# Trading Parameters
INITIAL_CAPITAL=0.1  # Start small!
MAX_POSITION_SIZE=0.1
MAX_DRAWDOWN=0.15
KELLY_FRACTION=0.5

# Filter Configuration
FILTER_MONITOR_HISTORY_SIZE=100
MIN_HEALTHY_REJECTION=85.0
MAX_HEALTHY_REJECTION=97.0
SPAM_SPIKE_MULTIPLIER=1.5
```

#### Step 3: Load Environment

```bash
# Load environment variables
source .env

# Add to .bashrc for persistence
echo 'source ~/.env' >> ~/.bashrc
```

---

## Setup Wallet Configuration

### Step 1: Create Secure Directory

```bash
# Create Solana config directory
mkdir -p ~/.config/solana
chmod 700 ~/.config/solana
```

### Step 2: Add Wallet Private Key

```bash
# Create wallet file
nano ~/.config/solana/id.json
```

**Paste your wallet private key JSON:**
```json
{
  "privateKey": [your_private_key_array],
  "publicKey": "your_public_key_here"
}
```

### Step 3: Secure Wallet File

```bash
# Set secure permissions (CRITICAL!)
chmod 600 ~/.config/solana/id.json

# Verify permissions
ls -la ~/.config/solana/id.json
# Should show: -rw-------

# Test wallet access
solana address
# Should show your wallet address
```

---

## Clone and Setup Repository

### Step 1: Clone Repository

```bash
# Clone your trading bot repository
git clone https://github.com/YOUR_USERNAME/mojo-trading-bot.git
cd mojo-trading-bot

# Or if you have the code locally, use scp/rsync to transfer it
# scp -r /path/to/local/project tradingbot@YOUR_VPS_IP:~/mojo-trading-bot
```

### Step 2: Setup Directory Structure

```bash
# Create necessary directories
mkdir -p logs
mkdir -p data/portfolio
mkdir -p data/backups
mkdir -p data/cache

# Set permissions
chmod 755 data
chmod 755 logs
```

### Step 3: Make Scripts Executable

```bash
# Make all deployment scripts executable
chmod +x scripts/*.sh

# Verify scripts
ls -la scripts/
```

---

## Test Deployment (Paper Trading)

### Step 1: Configure for Paper Trading

```bash
# Set paper trading mode
export EXECUTION_MODE=paper
export INITIAL_CAPITAL=0.1  # Small amount for testing
export APP_ENV=development

# Verify configuration
echo "Execution Mode: $EXECUTION_MODE"
echo "Initial Capital: $INITIAL_CAPITAL SOL"
echo "Environment: $APP_ENV"
```

### Step 2: Run Automated Setup

```bash
# Run the VPS setup script (if available)
./scripts/vps_setup.sh

# Or run the quick deployment script
./scripts/quick_deploy.sh
```

### Step 3: Manual Deployment

```bash
# Run the comprehensive deployment script with filters
./scripts/deploy_with_filters.sh
```

**Expected Output:**
```
🛡️ DEPLOYING TRADING BOT WITH AGGRESSIVE SPAM FILTERS...
=============================================================
📋 Deployment Configuration:
   Environment: development
   Execution Mode: paper
   Initial Capital: 0.1 SOL
   Infisical: ✅ Configured
   Wallet: YOUR_WALLET_ADDRESS

🧪 TESTING FILTER SYSTEM...
===============================
🛡️ RUNNING COMPREHENSIVE FILTER VERIFICATION
==================================================
🧪 TESTING FILTER AGGRESSIVENESS...
   Generating 1000 test signals (90% spam)
🎯 FILTER TEST RESULTS:
   Input signals: 1000 (simulated)
   Output signals: 47
   Rejection rate: 95.3%
✅ FILTERS PASS: 90%+ spam rejection achieved!
📋 TEST SUMMARY
==============================
   Aggressiveness        ✅ PASS
   Cooldown              ✅ PASS
   Signal Limit          ✅ PASS
   Volume Quality        ✅ PASS
==============================
🎉 ALL TESTS PASSED (4/4)
✅ SYSTEM READY FOR DEPLOYMENT

🚀 FILTER VERIFICATION COMPLETE - READY FOR DEPLOYMENT
✅ Filters verified - 90%+ spam rejection achieved

📦 Building trading bot...
✅ Trading bot built successfully
🚀 Starting Trading Bot with aggressive filtering...
EXECUTING: ./trading-bot --aggressive-filtering
📝 LOG FILE: logs/trading-bot-20241006-143022.log

🛡️  FILTERING: Aggressive mode enabled (90%+ spam rejection)
📊 MONITORING: Check filter performance with: grep 'Filter Performance' logs/trading-bot-*.log

🎮 Starting trading bot in foreground (Ctrl+C to stop)...
```

### Step 4: Monitor Paper Trading

```bash
# Monitor logs in real-time (in new terminal)
tail -f logs/trading-bot-*.log

# Check filter performance
grep "Filter Performance" logs/trading-bot-*.log | tail -20

# Check for trading activity
grep "EXECUTED\|PROFIT\|LOSS" logs/trading-bot-*.log

# Check for errors
grep "ERROR\|CRITICAL" logs/trading-bot-*.log
```

**Run paper trading for 24-48 hours** before switching to live trading!

---

## Production Deployment

### Step 1: Prepare for Live Trading

⚠️ **CRITICAL WARNING**: Only switch to live trading after:
- Paper trading has run successfully for 24-48 hours
- Filter performance is stable (85-97% rejection rate)
- No critical errors in logs
- You understand the risks

```bash
# Stop paper trading bot
pkill -f trading-bot

# Update to live mode with small capital
export EXECUTION_MODE=live
export INITIAL_CAPITAL=1.0  # Start with 1 SOL max
export APP_ENV=production

# Verify configuration
echo "⚠️  LIVE TRADING MODE ENABLED"
echo "Execution Mode: $EXECUTION_MODE"
echo "Initial Capital: $INITIAL_CAPITAL SOL"
echo "Environment: $APP_ENV"
```

### Step 2: Deploy Live Trading

```bash
# Deploy with live trading
./scripts/deploy_with_filters.sh --background

# Monitor deployment
ps aux | grep trading-bot
tail -f logs/trading-bot-*.log
```

### Step 3: Setup as System Service (Optional but Recommended)

```bash
# Create systemd service file
sudo nano /etc/systemd/system/trading-bot.service
```

**Service Configuration:**
```ini
[Unit]
Description=Solana Trading Bot with Aggressive Filters
After=network.target

[Service]
Type=simple
User=tradingbot
Group=tradingbot
WorkingDirectory=/home/tradingbot/mojo-trading-bot
Environment="APP_ENV=production"
Environment="EXECUTION_MODE=live"
Environment="INFISICAL_PROJECT_ID=your_project_id"
Environment="INFISICAL_ENVIRONMENT=production"
ExecStart=/home/tradingbot/mojo-trading-bot/trading-bot --aggressive-filtering
Restart=always
RestartSec=10
StandardOutput=append:/home/tradingbot/mojo-trading-bot/logs/trading-bot-service.log
StandardError=append:/home/tradingbot/mojo-trading-bot/logs/trading-bot-service-error.log

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable trading-bot
sudo systemctl start trading-bot
sudo systemctl status trading-bot

# Check logs
sudo journalctl -u trading-bot -f
```

---

## Monitoring & Maintenance

### Real-time Monitoring

#### Filter Performance Monitoring

```bash
# Current filter performance
grep "Filter Performance" logs/trading-bot-*.log | tail -10

# Filter statistics summary
grep "FILTER PERFORMANCE SUMMARY" logs/trading-bot-*.log | tail -5

# Spam spike alerts
grep "SPAM SPIKE" logs/trading-bot-*.log

# Filter health warnings
grep "WARNING.*Filter" logs/trading-bot-*.log
```

#### Trading Performance Monitoring

```bash
# Executed trades
grep "EXECUTED" logs/trading-bot-*.log | tail -20

# Profit/Loss tracking
grep -E "(PROFIT|LOSS|P&L)" logs/trading-bot-*.log | tail -20

# Portfolio value
grep "Portfolio value" logs/trading-bot-*.log | tail -10

# Drawdown monitoring
grep "drawdown" logs/trading-bot-*.log | tail -10
```

#### System Health Monitoring

```bash
# System resource usage
htop

# Disk usage
df -h

# Memory usage
free -h

# Network connectivity
ping -c 3 google.com

# Solana RPC connectivity
curl -X POST $QUICKNODE_PRIMARY_RPC \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}'
```

### Log Management

#### Setup Log Rotation

```bash
# Configure log rotation (as root)
sudo nano /etc/logrotate.d/trading-bot
```

**Log Rotation Configuration:**
```
/home/tradingbot/mojo-trading-bot/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 tradingbot tradingbot
    postrotate
        systemctl reload trading-bot || true
    endscript
}
```

```bash
# Test log rotation
sudo logrotate -d /etc/logrotate.d/trading-bot
```

### Backup Strategy

#### Automated Backups

```bash
# Create backup script
nano backup-trading-bot.sh
```

**Backup Script:**
```bash
#!/bin/bash
BACKUP_DIR="/home/tradingbot/backups"
DATE=$(date +%Y%m%d-%H%M%S)
PROJECT_DIR="/home/tradingbot/mojo-trading-bot"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration and data
tar -czf "$BACKUP_DIR/trading-bot-backup-$DATE.tar.gz" \
    -C "$PROJECT_DIR" \
    .env data/ logs/ \
    --exclude="logs/*.log"  # Exclude large log files

# Keep only last 7 days of backups
find "$BACKUP_DIR" -name "trading-bot-backup-*.tar.gz" -mtime +7 -delete

echo "Backup completed: $BACKUP_DIR/trading-bot-backup-$DATE.tar.gz"
```

```bash
# Make executable and schedule
chmod +x backup-trading-bot.sh

# Add to crontab for daily backups
crontab -e
# Add line: 0 2 * * * /home/tradingbot/backup-trading-bot.sh
```

---

## Troubleshooting

### Filter Issues

#### Rejection Rate Too Low (<85%)

**Symptoms:**
- Filter performance shows <85% rejection
- Spam spike alerts
- Filter health warnings

**Solutions:**
```bash
# Check current filter performance
grep "Filter Performance" logs/*.log | tail -20

# Review rejection reasons
grep "Filtered spam" logs/*.log | tail -20

# Check if spam is getting through
grep "EXECUTED" logs/*.log | tail -20

# Tighten filter parameters if needed
# Edit src/engine/spam_filter.mojo or src/engine/instant_spam_detector.mojo
# Rebuild and redeploy
```

#### Rejection Rate Too High (>97%)

**Symptoms:**
- Filter performance shows >97% rejection
- Few or no trades executed
- Filter health warnings about being too aggressive

**Solutions:**
```bash
# Check what's being rejected
grep "rejected" logs/*.log | tail -20

# Review approved signals
grep "approved" logs/*.log | tail -10

# Loosen filter parameters slightly
# Edit configuration files and redeploy
```

### Build Issues

#### Mojo Build Fails

```bash
# Check Mojo installation
mojo --version

# Clean build
rm -rf target/
mojo build src/main.mojo -o trading-bot

# Check syntax errors
mojo build src/main.mojo --verbose
```

#### Rust Module Build Fails

```bash
# Check Rust installation
rustc --version
cargo --version

# Clean Rust build
cd rust-modules
cargo clean
cargo build --release
cd ..

# Check for missing dependencies
cargo check
```

### Connection Issues

#### API Connection Problems

```bash
# Test Helius API
curl -H "Authorization: Bearer $HELIUS_API_KEY" \
  https://api.helius.xyz/v0/health

# Test QuickNode RPC
curl -X POST $QUICKNODE_PRIMARY_RPC \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'

# Check network connectivity
ping -c 3 api.helius.xyz
ping -c 3 solana-mainnet.rpc.extrnode.com
```

#### Infisical Connection Issues

```bash
# Check Infisical login
infisical whoami

# Test secret access
infisical secrets

# Verify environment variables
env | grep INFISICAL
```

### Performance Issues

#### High Memory Usage

```bash
# Check memory usage
free -h
ps aux --sort=-%mem | head -10

# Monitor memory trends
watch -n 5 'free -h'
```

#### High CPU Usage

```bash
# Check CPU usage
top -p $(pgrep trading-bot)

# Monitor CPU trends
htop
```

### Service Issues

#### Systemd Service Failures

```bash
# Check service status
sudo systemctl status trading-bot

# View service logs
sudo journalctl -u trading-bot -n 50

# Restart service
sudo systemctl restart trading-bot

# Check service configuration
sudo systemctl cat trading-bot
```

---

## Security Best Practices

### 1. Environment Security

```bash
# Secure environment files
chmod 600 .env
chmod 700 ~/.config/solana/

# Never commit secrets to git
echo ".env" >> .gitignore
echo "*.key" >> .gitignore
echo "id.json" >> .gitignore

# Use Infisical for secret management when possible
# Rotate API keys regularly
```

### 2. System Security

```bash
# Keep system updated
sudo apt update && sudo apt upgrade -y

# Use strong passwords
passwd  # Change default password

# Disable root SSH access
sudo nano /etc/ssh/sshd_config
# Set: PermitRootLogin no
sudo systemctl restart ssh

# Use SSH key authentication
# On local machine: ssh-copy-id tradingbot@YOUR_VPS_IP
```

### 3. Trading Security

```bash
# Start with paper trading always
# Use small initial capital (<1 SOL)
# Set conservative risk parameters
# Monitor for unusual activity
# Have emergency stop procedures
```

### 4. Backup Security

```bash
# Encrypt sensitive backups
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Store backups securely (offsite if possible)
# Test backup restoration regularly
# Document recovery procedures
```

### 5. Monitoring Security

```bash
# Set up alerting for critical events
# Monitor for failed login attempts
# Watch for unusual trading patterns
# Implement rate limiting on APIs
```

---

## Emergency Procedures

### 1. Emergency Stop

```bash
# Stop trading bot immediately
sudo systemctl stop trading-bot
# OR
pkill -f trading-bot

# Verify stopped
ps aux | grep trading-bot
```

### 2. Emergency Wallet Actions

```bash
# Move funds to cold storage if needed
# Revoke API access
# Change wallet private keys
# Contact exchanges if necessary
```

### 3. Emergency Recovery

```bash
# Restore from backup
tar -xzf trading-bot-backup-YYYYMMDD-HHMMSS.tar.gz

# Restart with safe parameters
export EXECUTION_MODE=paper
export INITIAL_CAPITAL=0.01
./scripts/deploy_with_filters.sh
```

---

## Support & Resources

### Documentation

- **Project README**: `README.md`
- **Implementation Guide**: `IMPLEMENTATION_GUIDE.md`
- **Architecture Guide**: `docs/ARCHITECTURE.md`
- **API Reference**: `docs/API.md`

### Community Support

- **GitHub Issues**: [Report bugs](https://github.com/YOUR_USERNAME/mojo-trading-bot/issues)
- **Discord**: [Join community](https://discord.gg/your-server)
- **Documentation**: [Project Wiki](https://github.com/YOUR_USERNAME/mojo-trading-bot/wiki)

### Contact

For critical issues or security concerns:
- Check logs first: `logs/trading-bot-*.log`
- Review filter statistics
- Include log excerpts in support requests
- Provide system information and configuration

---

**⚠️ IMPORTANT DISCLAIMER**: Trading cryptocurrencies involves substantial risk of loss. Always start with paper trading, use small amounts, and never risk more than you can afford to lose. This software is provided "as is" without warranty of any kind.

---

*Last updated: October 2024*