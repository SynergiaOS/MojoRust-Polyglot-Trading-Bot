# 🚀 DEPLOY NOW - Immediate Deployment Guide
## Production Server: 38.242.239.150

### ⚡ Quick Start (Copy-Paste Commands)

#### Pre-Deployment Checklist
- ✅ Infisical account: https://app.infisical.com
- ✅ Helius API key
- ✅ QuickNode RPC endpoint
- ✅ Solana wallet ready
- ✅ SSH access to 38.242.239.150

---

## Step 1: Connect to Production Server

```bash
# Connect to your VPS
ssh root@38.242.239.150

# Once connected, update system
apt update && apt upgrade -y
```

---

## Step 2: Run Automated VPS Setup

```bash
# Create project directory
mkdir -p ~/mojo-trading-bot
cd ~/mojo-trading-bot

# Download and run VPS setup script
curl -fsSL https://raw.githubusercontent.com/SynergiaOS/MojoRust/main/scripts/vps_setup.sh | bash

# Source environment variables
source ~/.bashrc
```

**The VPS setup script will install:**
- ✅ Mojo 24.4+
- ✅ Rust 1.70+
- ✅ Infisical CLI
- ✅ Docker & Docker Compose
- ✅ Firewall configuration
- ✅ Trading user account

---

## Step 3: Clone Repository

```bash
# Clone the project
git clone https://github.com/SynergiaOS/MojoRust.git .

# Make all scripts executable
chmod +x scripts/*.sh

# Create necessary directories
mkdir -p logs data secrets
```

---

## Step 4: Configure Infisical

```bash
# Login to Infisical
infisical login

# Initialize Infisical project (creates .infisical.json)
infisical init
# Set workspaceId and defaultEnvironment when prompted
# Or list secrets explicitly:
infisical secrets list --projectId <PROJECT_ID> --env production

# Test connection
infisical secrets list --projectId <PROJECT_ID> --env production
```

---

## Step 5: Configure Environment

```bash
# Copy production environment template
cp .env.production.example .env

# Edit configuration (IMPORTANT - start with PAPER TRADING!)
nano .env
```

**Critical Settings in .env:**
```bash
# Start with PAPER trading mode
EXECUTION_MODE=paper

# Server configuration
SERVER_HOST=38.242.239.150
SERVER_PORT=8080

# Trading parameters (conservative start)
INITIAL_CAPITAL=1.0
MAX_POSITION_SIZE=0.10
MAX_DRAWDOWN=0.15

# API keys (get from Infisical or set manually)
HELIUS_API_KEY=your_helius_key
QUICKNODE_RPC_URL=your_quicknode_url
```

---

## Step 6: Deploy Trading Bot

```bash
# Run deployment script
./scripts/deploy_with_filters.sh

# Or run directly with Mojo
mojo run src/main.mojo --mode=paper

# Or run with Infisical secrets (recommended)
infisical run --projectId <PROJECT_ID> --env production -- ./scripts/deploy_with_filters.sh
```

**The deployment script will:**
- ✅ Build Rust FFI modules
- ✅ Compile Mojo code
- ✅ Initialize database
- ✅ Start monitoring services
- ✅ Configure health checks

---

## Step 7: Verify Deployment

```bash
# Check if bot is running
ps aux | grep mojo

# View real-time logs
tail -f logs/trading-bot-$(date +%Y%m%d).log

# Check API status
curl http://localhost:8080/api/health

# View performance metrics
curl http://localhost:8080/api/metrics
```

---

## Step 8: Monitor and Manage

```bash
# Bot status dashboard
curl http://localhost:8080/api/status

# Recent trades
curl http://localhost:8080/api/trades/recent

# Performance summary
curl http://localhost:8080/api/performance/summary

# Stop the bot (gracefully)
curl -X POST http://localhost:8080/api/stop

# Emergency stop
pkill -f "mojo run"
```

---

## 🚨 Emergency Procedures

### Emergency Stop
```bash
# Immediate stop
pkill -9 mojo

# Stop all services
docker-compose down

# Disable trading (keep monitoring)
curl -X POST http://localhost:8080/api/disable-trading
```

### Restart Services
```bash
# Restart bot
./scripts/restart_bot.sh

# Restart monitoring
docker-compose restart monitoring

# Full restart
./scripts/deploy_with_filters.sh --restart
```

---

## 🔧 Maintenance Commands

### Daily Health Check
```bash
# System health
./scripts/server_health.sh

# Check logs for errors
grep -i error logs/trading-bot-*.log | tail -20

# Check resource usage
htop

# Disk space
df -h
```

### Updates
```bash
# Update code
git pull origin main

# Redeploy
./scripts/deploy_with_filters.sh

# Update dependencies
./scripts/update_dependencies.sh
```

---

## 📊 Monitoring URLs

Access these URLs in your browser:
- **Bot Dashboard**: http://38.242.239.150:8080
- **Metrics**: http://38.242.239.150:9090 (Prometheus)
- **Grafana**: http://38.242.239.150:3000 (admin/admin)
- **Health Check**: http://38.242.239.150:8080/api/health

---

## 🆘 Troubleshooting

### Bot Won't Start
```bash
# Check logs
tail -f logs/trading-bot-*.log

# Check configuration
./scripts/validate_config.sh

# Check dependencies
which mojo && which rustc && which infisical
```

### API Connection Issues
```bash
# Test Infisical (with project ID if set)
infisical secrets list --projectId <PROJECT_ID> --env production

# Test Helius API
curl -H "Authorization: Bearer $HELIUS_API_KEY" \
     https://api.helius.xyz/v0/tokens/addresses

# Test QuickNode
curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
     $QUICKNODE_RPC_URL
```

### Performance Issues
```bash
# Check system resources
free -h
df -h
iostat 1 5

# Check bot processes
ps aux | grep -E "(mojo|rust)"

# Profile performance
./scripts/profile_bot.sh
```

---

## 🎯 Next Steps

### When Paper Trading is Stable:
1. **Switch to Live Trading** (edit `.env`):
   ```bash
   EXECUTION_MODE=live
   INITIAL_CAPITAL=10.0  # Increase gradually
   ```

2. **Enable Alerts**:
   ```bash
   ENABLE_ALERTS=true
   ALERT_EMAIL=your@email.com
   ```

3. **Scale Up**:
   - Add more strategies
   - Increase position sizes
   - Add more pairs

---

## 📞 Support

- **Documentation**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Infisical**: https://app.infisical.com
- **Repository**: https://github.com/SynergiaOS/MojoRust
- **Issues**: https://github.com/SynergiaOS/MojoRust/issues

---

**⚠️ IMPORTANT**: Always start with PAPER trading mode. Monitor for at least 24 hours before switching to LIVE trading with real funds.

**🔒 SECURITY**: Never share your `.env` file or API keys. Use Infisical for secure secrets management.