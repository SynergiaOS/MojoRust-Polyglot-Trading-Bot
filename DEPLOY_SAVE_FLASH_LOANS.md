# 🚀 Save Flash Loans Deployment Guide

## 📋 Overview

This guide provides step-by-step instructions for deploying Save Flash Loans integration in your MojoRust sniper bot. The deployment includes comprehensive testing, monitoring, and production setup.

## 🔧 Prerequisites

### System Requirements
- **RAM**: 8GB+ minimum, 16GB+ recommended
- **Storage**: 20GB+ available disk space
- **Network**: Stable internet connection for Solana RPC
- **OS**: Ubuntu 20.04+ or macOS 12+

### Software Requirements
```bash
# Rust 1.70+
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Python 3.9+
sudo apt update
sudo apt install python3 python3-pip python3-venv

# Docker & Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Additional dependencies
sudo apt install build-essential pkg-config libssl-dev
```

### API Keys Required
```bash
# Solana RPC
export QUICKNODE_RPC_URL="https://xxx.solana-mainnet.quiknode.pro/xxx"
export HELIUS_API_KEY="your_helius_api_key"

# Jupiter & Jito
export JUPITER_API_KEY="your_jupiter_api_key"
export JITO_AUTH_KEY="your_jito_auth_key"

# Telegram (optional)
export TELEGRAM_BOT_TOKEN="your_telegram_bot_token"
export TELEGRAM_CHAT_ID="your_chat_id"
```

## 🚀 Deployment Steps

### Step 1: Environment Setup

```bash
# Clone the repository
git clone https://github.com/SynergiaOS/MojoRust.git
cd MojoRust

# Set up Python virtual environment
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Copy environment template
cp .env.example .env
# Edit .env with your API keys and configuration
```

### Step 2: Build Components

```bash
# Build Rust modules
cd rust-modules
cargo build --release

# Build Docker images
cd ..
docker-compose build
```

### Step 3: Configuration

#### Trading Configuration (`config/trading.toml`)
```toml
[sniper]
flash_loan_protocol = "save"
max_loan_amount = 5000000000  # 5 SOL
min_volume = 5000
min_lp_burn = 90.0
min_social_mentions = 10
fee_bps = 3  # 0.03%

[save]
program_id = "SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV"
max_latency_ms = 20
max_loan_amount_sol = 5.0
enabled = true

[monitoring]
metrics_enabled = true
alerting_enabled = true
health_check_interval = 30
```

#### Environment Variables (`.env`)
```bash
# Core configuration
TRADING_ENV=production
EXECUTION_MODE=live
INITIAL_CAPITAL=1.0

# API Keys
QUICKNODE_RPC_URL=your_quicknode_url
HELIUS_API_KEY=your_helius_key
JUPITER_API_KEY=your_jupiter_key
JITO_AUTH_KEY=your_jito_key

# Save Flash Loan Configuration
SAVE_PROGRAM_ID=SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV
FLASH_LOAN_SAVE_ENABLED=true
FLASH_LOAN_MAX_AMOUNT_LAMPORTS=5000000000

# Monitoring
PROMETHEUS_URL=http://localhost:9090
GRAFANA_URL=http://localhost:3001
REDIS_URL=redis://localhost:6379

# Wallet (NEVER commit real keys!)
WALLET_PRIVATE_KEY_PATH=/app/secrets/wallet.keypair
```

### Step 4: Security Setup

```bash
# Generate secure wallet keypair
solana-keygen new --no-bip39-passphrase --outfile /path/to/secure/wallet.keypair

# Set secure permissions
chmod 600 /path/to/secure/wallet.keypair

# Create secrets directory
mkdir -p secrets
cp /path/to/secure/wallet.keypair secrets/wallet.keypair
chmod 600 secrets/wallet.keypair
```

### Step 5: Run Tests

```bash
# Run comprehensive test suite
./scripts/run_all_tests.sh

# Individual test categories if needed
cd rust-modules && cargo test --release save_flash_loan
pytest tests/test_save_integration.py -v
cargo bench --release save_flash_loan_benchmark
```

### Step 6: Deploy Services

```bash
# Start all services
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f trading-bot
```

### Step 7: Verify Deployment

```bash
# Health check
curl http://localhost:8080/health

# Save provider status
curl http://localhost:8080/api/providers/save/status

# Flash loan configuration
curl http://localhost:8080/api/flash-loan/config

# Metrics endpoint
curl http://localhost:8080/metrics
```

## 📊 Monitoring Setup

### Grafana Dashboard

Access Grafana at `http://localhost:3001` (admin/trading_admin)

**Key Dashboards:**
1. **Save Flash Loan Metrics**
   - Execution success rate
   - Average latency
   - Profit per trade
   - Error rates

2. **System Health**
   - CPU/Memory usage
   - Network latency
   - Redis performance

3. **Trading Performance**
   - Win rate
   - ROI
   - Risk metrics

### Prometheus Metrics

Access Prometheus at `http://localhost:9090`

**Key Metrics:**
- `save_flash_loan_duration_seconds`
- `save_flash_loan_success_total`
- `save_flash_loan_profit_sol`
- `save_flash_loan_errors_total`

### AlertManager

Configure alerts in `config/alertmanager.yml`:

```yaml
route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    telegram_configs:
      - bot_token: 'your_telegram_bot_token'
        chat_id: 'your_chat_id'
        parse_mode: 'Markdown'

inhibit_rules:
  - source_match:
      alertname: 'Watchdog'
    target_match:
      alertname: 'Watchdog'
    equal: ['alertname', 'alertname']
```

## 🔥 Production Deployment

### IP Address Configuration

For production deployment on IP `38.242.239.150`:

```bash
# Update firewall rules
sudo ufw allow 8080/tcp  # Trading bot API
sudo ufw allow 9090/tcp  # Prometheus
sudo ufw allow 3001/tcp  # Grafana
sudo ufw allow 6379/tcp  # Redis

# Update docker-compose.yml for external access
# Modify port bindings to expose to external IP
```

### Production Configuration

```toml
[production]
enable_paper_trading = false
enable_real_trading = true
max_concurrent_flash_loans = 3
risk_management_enabled = true

[security]
enable_rate_limiting = true
max_requests_per_minute = 100
enable_circuit_breaker = true
circuit_breaker_threshold = 5
```

### SSL/TLS Setup

```bash
# Generate SSL certificates
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com

# Update nginx configuration for HTTPS
sudo nano /etc/nginx/sites-available/default
```

## 🧪 Testing in Production

### Paper Trading Mode

```bash
# Start with paper trading first
export EXECUTION_MODE=paper
docker-compose up -d

# Monitor for 24-48 hours
curl http://localhost:8080/api/trading/metrics

# Review results before switching to live
```

### Live Trading (Small Scale)

```bash
# Start with minimal capital
export INITIAL_CAPITAL=0.1
export MAX_CONCURRENT_FLASH_LOANS=1

# Monitor closely
docker-compose logs -f trading-bot | grep "flash_loan"

# Check results every hour
curl http://localhost:8080/api/flash-loan/stats
```

### Full Production

```bash
# Full configuration
export INITIAL_CAPITAL=1.0
export MAX_CONCURRENT_FLASH_LOANS=3
export EXECUTION_MODE=live

# Deploy with monitoring
./scripts/deploy_chainguard.sh --mode=production

# Set up monitoring alerts
# Verify all systems operational
```

## 📈 Performance Optimization

### System Optimization

```bash
# Run system optimizations
./scripts/apply_system_optimizations.sh

# CPU governor for high performance
echo 'performance' | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Network optimization
echo 'net.core.rmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Rust Optimization (PGO)

```bash
# Profile-guided optimization
cd rust-modules
cargo pgo build --release

# Run with profiling (48 hours recommended)
RUSTFLAGS="-Cprofile-generate=/tmp/pgo-data" ./target/release/trading-bot --mode=paper

# Optimize with collected profile
llvm-profdata merge -output=/tmp/merged.profdata /tmp/pgo-data/*.profraw
RUSTFLAGS="-Cprofile-use=/tmp/merged.profdata" cargo pgo optimize --release
```

### Memory Optimization

```bash
# Monitor memory usage
docker stats trading-bot-app

# Adjust memory limits if needed
# Update docker-compose.yml
services:
  trading-bot:
    mem_limit: 4g
    memswap_limit: 6g
```

## 🚨 Troubleshooting

### Common Issues

#### Flash Loan Failures
```bash
# Check Save provider status
curl http://localhost:8080/api/providers/save/status

# Check Jupiter API
curl -H "Authorization: Bearer $JUPITER_API_KEY" https://quote-api.jup.ag/v6/quote

# Check Jito status
curl https://mainnet.block-engine.jito.wtf/api/v1/bundles
```

#### High Latency
```bash
# Check network latency
ping -c 5 api.mainnet-beta.solana.com

# Check system resources
top -p $(pgrep trading-bot)

# Optimize if needed
./scripts/apply_system_optimizations.sh
```

#### Low Success Rate
```bash
# Check logs for error patterns
docker-compose logs trading-bot | grep ERROR

# Adjust slippage settings
# Update config/trading.toml
[flash_loan]
slippage_bps = 100  # Increase if needed

# Check wallet balance
solana balance $(solana address)
```

### Recovery Procedures

#### Emergency Stop
```bash
# Stop all trading
curl -X POST http://localhost:8080/api/emergency/stop

# Verify stopped
curl http://localhost:8080/api/status
```

#### Restart Services
```bash
# Graceful restart
docker-compose restart trading-bot

# Full restart
docker-compose down
docker-compose up -d
```

#### Rollback
```bash
# Rollback to previous version
git checkout <previous_commit_tag>
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## 📚 Maintenance

### Daily Tasks
- Review trading metrics
- Check system health
- Monitor error rates
- Verify alert systems

### Weekly Tasks
- Update security patches
- Rotate API keys
- Backup configuration
- Review performance metrics

### Monthly Tasks
- Update dependencies
- Full system audit
- Performance optimization review
- Capacity planning

## 🎯 Success Metrics

### Performance Targets
- **Flash Loan Latency**: <30ms average
- **Success Rate**: ≥85%
- **ROI**: 2-5% after fees
- **Uptime**: ≥99%

### Monitoring Alerts
- Flash loan success rate <80%
- Average latency >50ms
- Error rate >5%
- System resource usage >80%

### Scaling Indicators
- Memory usage >4GB
- CPU usage >80%
- Network latency >100ms
- Queue depth >100

---

## 📞 Support

For deployment issues:
1. Check this documentation first
2. Review logs in `logs/` directory
3. Run `./scripts/run_all_tests.sh` for diagnostics
4. Check GitHub issues for known problems

### Emergency Contacts
- **System Admin**: For infrastructure issues
- **Development Team**: For application bugs
- **Security Team**: For security concerns

---

**🚀 Ready to deploy Save Flash Loans in production!** 🎉