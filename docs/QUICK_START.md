# ⚡ MojoRust Trading Bot - 5 Minute Quick Start

## 🚀 Get Trading in Under 5 Minutes

This guide gets you from zero to running trading bot in just 5 minutes. Perfect for testing and development.

### Prerequisites (2 minutes)
- **Git installed**: `git --version`
- **Basic command line knowledge**
- **Linux/macOS/Windows with WSL2**

---

## Step 1: Clone and Setup (1 minute)

```bash
# Clone the repository
git clone https://github.com/SynergiaOS/MojoRust.git
cd MojoRust

# Make scripts executable
chmod +x scripts/*.sh
```

---

## Step 2: Quick Configuration (1 minute)

```bash
# Copy quick-start template
cp .env.example .env

# Edit configuration (minimum required)
nano .env
```

**Essential settings only:**
```bash
# Required: Get from https://www.helius.dev/
HELIUS_API_KEY=your_helius_key_here

# Required: Get from https://www.quicknode.com/
QUICKNODE_RPC_URL=your_quicknode_url_here

# Optional: Your wallet address (will be auto-detected if not set)
WALLET_ADDRESS=your_solana_address_here
```

**API Key Setup:**
1. **Helius**: Sign up at https://www.helius.dev/ → Create project → Copy API key
2. **QuickNode**: Sign up at https://www.quicknode.com/ → Create Solana endpoint → Copy URL

---

## Step 3: Wallet Setup (1 minute)

**Option A: Use existing wallet**
```bash
# If you already have Solana wallet at ~/.config/solana/id.json
./scripts/check_wallet.sh --fix
```

**Option B: Generate new test wallet**
```bash
# Create test wallet (safe for testing)
mkdir -p ~/.config/solana
solana-keygen new --no-bip39-passphrase --silent > ~/.config/solana/id.json
chmod 600 ~/.config/solana/id.json
./scripts/check_wallet.sh --fix
```

---

## Step 4: Start Bot (30 seconds)

```bash
# Start in safe paper trading mode
./scripts/start_bot.sh --mode=paper --verbose

# OR run in background (daemon mode)
./scripts/start_bot.sh --mode=paper --daemon --verbose
```

**That's it! Your bot is now running! 🎉**

---

## ✅ Verification (30 seconds)

Check if everything is working:

```bash
# Check bot status
curl http://localhost:8080/api/health

# View recent activity
curl http://localhost:8080/api/status

# View logs (if running as daemon)
tail -f logs/trading-bot-$(date +%Y%m%d).log
```

Expected response: `{"status": "healthy", "mode": "paper"}`

---

## 🎯 Next Steps

### Monitor Your Bot
```bash
# Real-time monitoring
tail -f logs/trading-bot-*.log

# Performance metrics
curl http://localhost:8080/api/metrics

# Recent trades
curl http://localhost:8080/api/trades/recent
```

### Stop the Bot
```bash
# If running in foreground: Press Ctrl+C
# If running as daemon:
kill $(cat logs/trading-bot.pid)
```

### Go Live (When Ready)
```bash
# Switch to live trading (real money!)
./scripts/start_bot.sh --mode=live
# Type 'LIVE' to confirm
```

---

## 🔧 Common Quick Fixes

### API Key Issues
```bash
# Test your Helius key
curl -H "Authorization: Bearer YOUR_HELIUS_KEY" https://api.helius.xyz/v0/tokens/addresses

# Test your QuickNode URL
curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
     YOUR_QUICKNODE_URL
```

### Wallet Issues
```bash
# Check and fix wallet
./scripts/check_wallet.sh --verbose --fix

# Create new wallet if needed
rm ~/.config/solana/id.json
solana-keygen new --no-bip39-passphrase --silent > ~/.config/solana/id.json
chmod 600 ~/.config/solana/id.json
```

### Port Issues
```bash
# Check if port 8080 is available
lsof -i :8080

# Kill any process using port 8080
sudo lsof -ti:8080 | xargs kill -9
```

---

## 📊 Quick Monitoring Commands

```bash
# System health
./scripts/server_health.sh

# Bot processes
ps aux | grep trading-bot

# Log errors
grep -i error logs/trading-bot-*.log | tail -10

# Trading activity
grep -i "trade\|position" logs/trading-bot-*.log | tail -20
```

---

## 🎉 Success Indicators

You know it's working when you see:

✅ **Startup output**: "✅ Bot startup completed"
✅ **Health check**: `{"status": "healthy"}`
✅ **Log entries**: Trading activity and price updates
✅ **API response**: Status and metrics endpoints working
✅ **No errors**: Clean startup without critical errors

---

## ⚠️ Important Reminders

- **Paper Mode**: No real money at risk - safe for testing
- **API Keys**: Never share or commit to version control
- **Live Trading**: Only switch to live after thorough testing
- **Monitoring**: Keep an eye on logs and performance metrics

---

## 🆘 Need Help?

**Quick solutions:**
- **API key issues**: Re-check keys from Helius/QuickNode
- **Wallet problems**: Run `./scripts/check_wallet.sh --fix`
- **Port conflicts**: Kill processes on port 8080
- **Permission errors**: Run `chmod +x scripts/*.sh`

**Full documentation:**
- [Complete Startup Guide](BOT_STARTUP_GUIDE.md)
- [Wallet Setup Guide](WALLET_SETUP_GUIDE.md)
- [Main Documentation](../README.md)
- [GitHub Issues](https://github.com/SynergiaOS/MojoRust/issues)

**Community:**
- Discord: [Join our community]
- GitHub: [Report issues]

---

## 🎯 You're Done!

**🚀 Your MojoRust Trading Bot is running!**

**What's happening:**
- Bot is analyzing Solana markets in real-time
- Paper trades are being executed (no real money)
- Performance metrics are being tracked
- Logs are recording all activity

**Monitor at:** http://localhost:8080

**Ready for more?** See the [Bot Startup Guide](BOT_STARTUP_GUIDE.md) for advanced configuration and live trading setup.

---

**⏱️ Total time: ~5 minutes**
**🎯 Status: Trading bot operational!**
**🔒 Safety: Paper trading mode (no risk)**