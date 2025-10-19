# 🚀 MojoRust Automated Trading System - Setup Guide

## Overview

The MojoRust Automated Trading System is a fully automated algorithmic trading bot for Solana memecoin markets. It discovers new tokens, analyzes opportunities, executes trades, and manages risk without requiring manual intervention.

## 🎯 System Features

### 🤖 **Full Automation**
- **Automatic Token Discovery**: Scans multiple sources for new tokens
- **Intelligent Analysis**: Evaluates tokens using multiple criteria
- **Strategy Execution**: Executes trades based on configured strategies
- **Risk Management**: Monitors and manages trading risks automatically

### 📊 **Multi-Strategy Support**
- **Enhanced RSI**: RSI-based trading with support/resistance
- **Momentum Trading**: Follows market momentum and volume trends
- **Arbitrage**: Exploits price differences across exchanges
- **Flash Loans**: Uses flash loans for arbitrage opportunities

### 🛡️ **Risk Management**
- **Position Sizing**: Automatic position size calculation
- **Stop Loss/Take Profit**: Automatic profit/loss management
- **Drawdown Protection**: Protects against significant losses
- **Emergency Stop**: Immediate trading halt if needed

## 📋 Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ recommended)
- **Python**: 3.9+
- **Redis**: 6.0+
- **RAM**: 2GB minimum, 4GB recommended
- **Storage**: 10GB free space

### Required APIs
- **Helius API**: Solana data and streaming
- **QuickNode RPC**: Solana blockchain access
- **Jupiter API**: DEX routing and prices
- **Optional**: Twitter API, Telegram Bot API

## 🛠️ Installation

### 1. **Clone the Repository**
```bash
git clone <repository-url>
cd MojoRust
```

### 2. **Install System Dependencies**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y python3.9 python3.9-venv python3.9-dev redis-server

# Start Redis
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

### 3. **Set Up Python Environment**
```bash
# Create virtual environment
python3.9 -m venv venv
source venv/bin/activate

# Install Python dependencies
pip install -r requirements.txt
```

### 4. **Configure Environment Variables**
```bash
# Copy environment template
cp .env.example .env

# Edit the configuration
nano .env
```

### 5. **Configure API Keys**
Edit `.env` file with your API keys:
```bash
# Solana APIs
HELIUS_API_KEY=your_helius_api_key
QUICKNODE_PRIMARY_RPC=your_quicknode_rpc
QUICKNODE_API_KEY=your_quicknode_api_key

# Optional APIs
TWITTER_API_KEY=your_twitter_api_key
TWITTER_API_SECRET=your_twitter_api_secret
TELEGRAM_BOT_TOKEN=your_telegram_bot_token

# System Configuration
REDIS_URL=redis://localhost:6379
LOG_LEVEL=INFO
```

## ⚙️ Configuration

### 1. **Create Configuration File**
```bash
# Create sample configuration
python run_automated_trading.py --create-config

# Edit the configuration
nano automated_trading_config.json
```

### 2. **Configuration Options**
```json
{
  "redis_url": "redis://localhost:6379",
  "automation_mode": "fully_automatic",
  "trading_enabled": true,
  "discovery_enabled": true,
  "risk_management_enabled": true,
  "auto_recovery": true,
  "emergency_stop_enabled": true,
  "max_daily_trades": 100,
  "daily_loss_limit": 0.1,
  "initial_capital": 1.0,
  "execution_mode": "paper",
  "default_strategy": "enhanced_rsi",
  "log_level": "INFO",
  "monitoring_enabled": true,
  "maintenance_windows": [
    {
      "start_hour": 2,
      "end_hour": 3,
      "description": "Daily maintenance window"
    }
  ]
}
```

### 3. **Automation Modes**
- **fully_automatic**: Complete automation without manual intervention
- **semi_automatic**: Automation with manual oversight capability
- **monitoring_only**: Monitor opportunities without trading

## 🚀 Starting the System

### 1. **Start in Paper Trading Mode (Recommended)**
```bash
# Start with paper trading
python run_automated_trading.py --mode fully_automatic --paper

# Or with configuration file
python run_automated_trading.py --config automated_trading_config.json --paper
```

### 2. **Start in Live Trading Mode**
```bash
# ⚠️ WARNING: Only after thorough paper trading testing
python run_automated_trading.py --mode fully_automatic
```

### 3. **Dry Run Mode (No Trades)**
```bash
# Test system without executing trades
python run_automated_trading.py --dry-run
```

## 📊 Monitoring

### 1. **System Status**
The system logs status updates every 5 minutes:
```
System running - Uptime: 3600s, Trades: 15, PnL: 0.0234 SOL
```

### 2. **Real-time Monitoring**
```bash
# Check Redis for system status
redis-cli GET orchestrator_health

# Check system metrics
redis-cli GET auto_executor_metrics

# Check discovery statistics
redis-cli GET discovery_statistics
```

### 3. **Log Files**
```bash
# View main log
tail -f logs/automated_trading.log

# View error logs
tail -f logs/errors.log
```

## 🎛️ Advanced Configuration

### 1. **Strategy Parameters**
Edit strategy parameters in `config/trading.toml`:
```toml
[strategy]
rsi_period = 14
oversold_threshold = 25.0
overbought_threshold = 75.0
min_confluence_strength = 0.7

[strategy.flash_loan_ensemble]
enabled = true
min_confidence_threshold = 0.7
```

### 2. **Risk Management**
```toml
[trading]
initial_capital = 1.0
max_position_size = 0.1
max_drawdown = 0.15
daily_trade_limit = 50
kelly_fraction = 0.5
```

### 3. **Token Discovery**
```python
# Discovery thresholds
'min_liquidity_threshold': 5000,     # 5000 SOL minimum
'min_volume_threshold': 10000,       # 10000 SOL minimum 24h volume
'quality_threshold': 0.6,           # Minimum quality score
'token_age_limit_hours': 24,         # Maximum age for new tokens
```

## 🔧 Customization

### 1. **Adding Custom Strategies**
```python
# Create new strategy in src/strategies/
class CustomStrategy:
    def __init__(self, parameters):
        self.parameters = parameters

    async def generate_signals(self, market_data):
        # Your custom logic here
        pass

# Register in StrategyManager
strategy_manager.load_strategy("custom_strategy", CustomStrategy)
```

### 2. **Custom Token Sources**
```python
# Add new discovery source
async def scan_custom_source(self):
    # Your custom scanning logic
    tokens = []
    # ... discover tokens
    return tokens

# Register in AutoTokenDiscovery
self.data_sources[DiscoverySource.CUSTOM] = self.scan_custom_source
```

### 3. **Custom Risk Rules**
```python
# Add custom risk checks
async def custom_risk_check(self, trade_request):
    # Your custom risk logic
    return allowed, reason, risk_info

# Integrate with RiskController
risk_controller.add_custom_check(custom_risk_check)
```

## 🔍 Testing

### 1. **Unit Tests**
```bash
# Run all tests
python -m pytest tests/ -v

# Run specific test category
python -m pytest tests/test_discovery.py -v
```

### 2. **Integration Tests**
```bash
# Test full system integration
python -m pytest tests/integration/ -v
```

### 3. **Paper Trading Testing**
1. Run system in paper mode for at least 24 hours
2. Monitor performance metrics
3. Check risk management effectiveness
4. Verify strategy performance

## 📈 Performance Optimization

### 1. **System Resources**
```bash
# Monitor CPU usage
htop

# Monitor memory usage
free -h

# Monitor Redis
redis-cli INFO memory
```

### 2. **Database Optimization**
```bash
# Redis optimization
redis-cli CONFIG SET maxmemory 1gb
redis-cli CONFIG SET maxmemory-policy allkeys-lru
```

### 3. **Logging Optimization**
```python
# Reduce log verbosity in production
"log_level": "WARNING"

# Rotate logs
import logging
from logging.handlers import RotatingFileHandler

handler = RotatingFileHandler('trading.log', maxBytes=100MB, backupCount=5)
```

## 🔒 Security

### 1. **API Key Security**
- Never commit API keys to version control
- Use environment variables for sensitive data
- Rotate API keys regularly
- Use read-only keys where possible

### 2. **Network Security**
```bash
# Firewall configuration
sudo ufw allow 22/tcp  # SSH
sudo ufw allow 6379/tcp  # Redis (internal only)
sudo ufw enable
```

### 3. **Trading Security**
- Always start with paper trading
- Set conservative risk limits
- Monitor for unusual activity
- Keep emergency stop accessible

## 🚨 Troubleshooting

### 1. **Common Issues**

#### **System Won't Start**
```bash
# Check Redis connection
redis-cli ping

# Check Python dependencies
pip list

# Check log files
tail logs/automated_trading.log
```

#### **No Trading Activity**
```bash
# Check API keys
grep -r API_KEY .env

# Check system status
redis-cli GET orchestrator_health

# Check discovery stats
redis-cli GET discovery_statistics
```

#### **High Memory Usage**
```bash
# Check Redis memory usage
redis-cli INFO memory

# Clear expired keys
redis-cli --scan --pattern "*expired*" | xargs redis-cli del
```

### 2. **Error Recovery**
```bash
# Emergency stop
redis-cli PUBLISH risk_notifications '{"type": "emergency_stop", "reason": "manual"}'

# Restart components
python run_automated_trading.py --dry-run

# Reset system state
redis-cli FLUSHDB
```

### 3. **Performance Issues**
```bash
# Monitor system performance
top -p $(pgrep -f run_automated_trading)

# Check database performance
redis-cli --latency-history -i 1

# Profile Python code
python -m cProfile -o profile.stats run_automated_trading.py --dry-run
```

## 📚 Documentation

### 1. **API Documentation**
- **Trading API**: http://localhost:8083/docs
- **WebSocket**: ws://localhost:8083/ws/trading
- **Health Check**: http://localhost:8084/health

### 2. **System Architecture**
```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│ Token Discovery  │───▶│ Strategy Executor │───▶│ Risk Controller  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Data Sources   │    │ Trading Controller│    │ Trading API     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### 3. **Data Flow**
```
Token Discovery → Analysis → Opportunity Queue → Risk Check → Execution → Monitoring
```

## 🆘 Support

### 1. **Getting Help**
- Check log files for error messages
- Review configuration settings
- Test with paper trading first
- Join community channels for support

### 2. **Bug Reports**
- Include system logs
- Provide configuration details
- Describe expected vs actual behavior
- Include steps to reproduce

### 3. **Feature Requests**
- Describe the use case
- Explain expected benefits
- Provide implementation suggestions
- Consider contribution guidelines

---

## 🎉 Next Steps

1. **Install the system** following the setup guide
2. **Configure with paper trading** mode
3. **Monitor for 24-48 hours** to ensure stability
4. **Analyze performance metrics** and adjust parameters
5. **Consider live trading** only after thorough testing

Happy trading! 🚀

---

*Disclaimer: Automated trading involves significant risk. Start with paper trading and never invest more than you can afford to lose.*