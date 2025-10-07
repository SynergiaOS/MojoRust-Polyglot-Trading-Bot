# 📖 Ultimate Trading Bot - User Guide

## 🎯 Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [System Overview](#system-overview)
4. [Configuration](#configuration)
5. [Trading Strategies](#trading-strategies)
6. [Risk Management](#risk-management)
7. [Monitoring](#monitoring)
8. [API Usage](#api-usage)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)

---

## 🚀 Introduction

### What is Ultimate Trading Bot?

The Ultimate Trading Bot is a state-of-the-art automated cryptocurrency trading system designed for the Solana blockchain. It incorporates 8 advanced trading strategies, real-time multi-source data collection, comprehensive market analysis, intelligent risk management, and ultra-low latency execution.

### Key Features
- **8 Advanced Trading Strategies** with ensemble consensus
- **Real-time Data Collection** from 4 major sources
- **Comprehensive Market Analysis** with 7 analysis types
- **Intelligent Risk Management** with dynamic position sizing
- **Ultra-Low Latency Execution** (< 100ms)
- **Real-time Monitoring** with Telegram alerts
- **Production-Ready Deployment** with health checks

### Who Should Use This Bot?

This trading bot is designed for:
- **Experienced Traders** who want automated trading
- **Quantitative Analysts** who need advanced strategies
- **Investment Firms** requiring reliable execution
- **Developers** building on Solana ecosystem
- **Institutions** needing robust risk management

---

## 🎯 Getting Started

### Prerequisites

#### System Requirements
- **Operating System:** Ubuntu 20.04+ or macOS 10.15+
- **Python:** 3.8+ (3.12+ recommended)
- **Memory:** 4GB+ RAM
- **Storage:** 10GB+ available space
- **Network:** Stable internet connection

#### Required Accounts
1. **Solana Wallet** (for trading)
2. **Exchange Accounts** (for API access)
3. **Telegram Account** (for notifications)
4. **API Keys** from supported exchanges

### Quick Start

#### 1. Installation
```bash
# Clone repository
git clone https://github.com/SynergiaOS/MojoRust.git
cd MojoRust

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

#### 2. Configuration
```bash
# Copy configuration template
cp config/trading_template.toml config/trading.toml
cp .env.example .env

# Edit configuration files
nano config/trading.toml
nano .env
```

#### 3. API Setup
```bash
# Add your API keys to .env file
echo "TELEGRAM_TOKEN=your_telegram_token" >> .env
echo "CHAT_ID=your_chat_id" >> .env
echo "HELIUS_API_KEY=your_helius_key" >> .env
```

#### 4. Start Trading Bot
```bash
# Start the system
python src/main_ultimate.mojo

# Or start in background
nohup python src/main_ultimate.mojo > trading.log 2>&1 &
```

#### 5. Verify Operation
```bash
# Check if bot is running
curl http://localhost:8080/health

# Check Telegram for welcome message
```

---

## 🖥️ System Overview

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    ULTIMATE TRADING BOT                      │
├─────────────────────────────────────────────────────────────┤
│  📊 Data Collection Layer                                   │
│  ├── DexScreener (Price & Volume)                          │
│  ├── Birdeye (Market Analytics)                            │
│  ├── Jupiter (DEX Aggregation)                             │
│  └── Helius (On-Chain Data)                               │
├─────────────────────────────────────────────────────────────┤
│  🧠 Analysis Layer                                         │
│  ├── Technical Analysis                                    │
│  ├── Predictive Analytics                                  │
│  ├── Pattern Recognition                                   │
│  ├── Sentiment Analysis                                    │
│  └── Multi-timeframe Analysis                              │
├─────────────────────────────────────────────────────────────┤
│  🎯 Strategy Layer                                         │
│  ├── Momentum Breakthrough                                 │
│  ├── Mean Reversion                                       │
│  ├── Trend Following                                      │
│  ├── Whale Tracking                                       │
│  └── 4 More Advanced Strategies                           │
├─────────────────────────────────────────────────────────────┤
│  🛡️ Risk Management Layer                                  │
│  ├── Position Sizing                                      │
│  ├── Portfolio Heat Management                            │
│  ├── Stop Loss & Take Profit                              │
│  └── Emergency Stops                                       │
├─────────────────────────────────────────────────────────────┤
│  ⚡ Execution Layer                                         │
│  ├── Smart Order Routing                                   │
│  ├── Multi-RPC Load Balancing                            │
│  ├── Slippage Protection                                  │
│  └── Gas Optimization                                      │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

#### 1. Data Pipeline
- **Multi-source collection** from 4 major APIs
- **Real-time processing** with < 1 second latency
- **Data validation** and quality checks
- **Intelligent caching** for performance

#### 2. Analysis Engine
- **Technical indicators:** RSI, MACD, Bollinger Bands, ADX
- **Predictive models:** Machine learning-based forecasts
- **Pattern detection:** Advanced chart patterns
- **Sentiment analysis:** Social media monitoring

#### 3. Strategy System
- **8 advanced strategies** with proven track records
- **Ensemble consensus** with weighted voting
- **Adaptive learning** from market conditions
- **Dynamic strategy selection** based on performance

#### 4. Risk Management
- **Dynamic position sizing** based on volatility
- **Portfolio heat management** with correlation analysis
- **Real-time risk monitoring** with automatic adjustments
- **Emergency stop conditions** for extreme market events

---

## ⚙️ Configuration

### Main Configuration File

Edit `config/trading.toml` to customize your trading bot:

#### Basic Settings
```toml
[environment]
trading_env = "paper"        # paper, live
execution_mode = "simulation" # simulation, live
debug_mode = true
log_level = "INFO"

[trading]
max_position_size = 0.95     # 95% of portfolio max
risk_per_trade = 0.02        # 2% risk per trade
max_drawdown = 0.15          # 15% max drawdown
min_confidence = 0.6         # 60% minimum confidence
slippage_tolerance = 0.005   # 0.5% max slippage
```

#### Strategy Configuration
```toml
[strategies]
# Strategy weights (must sum to 1.0)
momentum_breakthrough = 0.15
mean_reversion = 0.12
trend_following = 0.14
volatility_breakout = 0.13
whale_tracking = 0.16
sentiment_momentum = 0.11
pattern_recognition = 0.10
statistical_arbitrage = 0.09

# Strategy thresholds
[strategies.thresholds]
min_momentum_strength = 0.7
min_mean_reversion_deviation = 0.03
trend_confirmation_periods = 3
volatility_breakout_multiplier = 2.0
whale_min_transaction_size = 100000
sentiment_threshold = 0.7
```

#### Risk Management
```toml
[risk]
portfolio_heat_limit = 0.8   # 80% max exposure
correlation_limit = 0.7       # 70% max correlation
volatility_threshold = 0.05   # 5% volatility threshold
max_concurrent_positions = 5   # Max 5 positions
emergency_stop_enabled = true

# Risk adjustments
[risk.adjustments]
high_volatility_factor = 0.7    # Reduce position size in high vol
low_volatility_factor = 1.2     # Increase position size in low vol
trend_factor = 1.1              # Increase in strong trends
```

#### API Configuration
```toml
[api]
timeout_seconds = 10.0
rate_limit_per_minute = 300
retry_attempts = 3
retry_delay_seconds = 1.0

# Individual API settings
[api.dexscreener]
base_url = "https://api.dexscreener.com/latest/dex"
rate_limit = 300
timeout = 10

[api.helius]
base_url = "https://api.helius.xyz"
rate_limit = 100000
timeout = 15

[api.jupiter]
base_url = "https://quote-api.jup.ag"
rate_limit = 100
timeout = 5
```

### Environment Variables

Create `.env` file for sensitive data:

```bash
# Trading Configuration
TRADING_ENV=paper
WALLET_ADDRESS=your_solana_wallet_address
WALLET_PRIVATE_KEY_PATH=/path/to/your/private_key.json

# API Keys
HELIUS_API_KEY=your_helius_api_key_here
QUICKNODE_RPC_URL=https://your-quicknode-url.solana-mainnet.quiknode.pro/your-key/
DEXSCREENER_API_KEY=your_dexscreener_key_here
BIRDEYE_API_KEY=your_birdeye_key_here

# Telegram Configuration
TELEGRAM_TOKEN=8499251370:AAEtMGNmMF3XwuwZgypA8O42-fjkaNWGocA
CHAT_ID=6201158809

# Database Configuration
DATABASE_URL=postgresql://username:password@localhost:5432/mojorust_db
REDIS_URL=redis://localhost:6379

# Security
INFISICAL_CLIENT_ID=your_infisical_client_id
INFISICAL_CLIENT_SECRET=your_infisical_client_secret
```

### Configuration Validation

```bash
# Validate configuration
python -c "
import toml
config = toml.load('config/trading.toml')
print('Configuration is valid!')
print(f'Environment: {config[\"environment\"][\"trading_env\"]}')
print(f'Max position size: {config[\"trading\"][\"max_position_size\"]}')
"

# Test environment variables
python -c "
import os
from dotenv import load_dotenv
load_dotenv()
print('Environment variables loaded!')
print(f'Trading env: {os.getenv(\"TRADING_ENV\")}')
print(f'Telegram token set: {bool(os.getenv(\"TELEGRAM_TOKEN\"))}')
"
```

---

## 📈 Trading Strategies

### Strategy Overview

The Ultimate Trading Bot uses 8 advanced strategies that work together in an ensemble system:

#### 1. Momentum Breakthrough Strategy
**Purpose:** Capture strong momentum movements with volume confirmation

**Indicators Used:**
- RSI (5m, 15m, 1h)
- Price momentum
- Volume analysis
- Moving averages

**Entry Conditions:**
- RSI momentum > 0.7
- Volume > 1.5x average
- Price breakout confirmation

**Exit Conditions:**
- Take profit: 2.5x ATR
- Stop loss: 1.2x ATR
- Momentum reversal signals

#### 2. Mean Reversion Strategy
**Purpose:** Profit from price corrections to the mean

**Indicators Used:**
- Bollinger Bands
- RSI (oversold/overbought)
- Price deviation from mean
- Support/resistance levels

**Entry Conditions:**
- Price < lower Bollinger Band OR RSI < 25
- Price deviation > 3% from mean
- Volume confirmation

**Exit Conditions:**
- Take profit: Mean price
- Stop loss: 3% below entry
- Reversion completed

#### 3. Trend Following Strategy
**Purpose:** Follow established trends with confirmation

**Indicators Used:**
- Moving averages (20, 50, 200)
- ADX (trend strength)
- MACD
- Price position relative to MAs

**Entry Conditions:**
- SMA 20 > SMA 50 > SMA 200
- ADX > 25
- MACD bullish crossover
- Price above key MAs

**Exit Conditions:**
- Take profit: 3x ATR
- Stop loss: SMA 50 - 0.5x ATR
- Trend reversal signals

#### 4. Volatility Breakout Strategy
**Purpose:** Capture price movements during high volatility

**Indicators Used:**
- Current volatility vs average
- Bollinger Band width
- Volume surge detection
- Price breakouts

**Entry Conditions:**
- Volatility ratio > 1.8
- Volume > 2x average
- Price breaks Bollinger Bands

**Exit Conditions:**
- Take profit: 2x ATR
- Stop loss: 1x ATR
- Volatility normalization

#### 5. Whale Tracking Strategy
**Purpose:** Follow large wallet movements and accumulation

**Indicators Used:**
- Large transaction analysis
- Whale wallet activity
- Exchange flow data
- Accumulation patterns

**Entry Conditions:**
- Large buys > sells by 1.5x
- Whale accumulation score > 0.7
- Exchange outflow detected

**Exit Conditions:**
- Take profit: 2.5x ATR
- Stop loss: 1.5x ATR
- Whale distribution detected

#### 6. Sentiment Momentum Strategy
**Purpose:** Combine social sentiment with price momentum

**Indicators Used:**
- Social sentiment score
- Sentiment momentum
- News sentiment
- Fear & Greed Index

**Entry Conditions:**
- Overall sentiment > 0.7
- Sentiment momentum > 0.3
- Social volume > 0.6
- Breaking news confirmation

**Exit Conditions:**
- Take profit: 2x ATR
- Stop loss: 1.3x ATR
- Sentiment shift detected

#### 7. Pattern Recognition Strategy
**Purpose:** Identify and trade chart patterns

**Indicators Used:**
- Bullish/bearish patterns
- Support/resistance levels
- Candlestick patterns
- Pattern strength

**Entry Conditions:**
- Bullish patterns > 0 with strength > 0.6
- Price near support
- Pattern confirmation

**Exit Conditions:**
- Take profit: Next resistance level
- Stop loss: Below support + 2%
- Pattern completion

#### 8. Statistical Arbitrage Strategy
**Purpose:** Exploit statistical mispricings and correlations

**Indicators Used:**
- Price z-scores
- Mean reversion probability
- Cross-exchange price differences
- Correlation analysis

**Entry Conditions:**
- Z-score > 2.0 or < -2.0
- Mean reversion probability > 0.7
- Price difference > 0.5%

**Exit Conditions:**
- Take profit: Statistical mean
- Stop loss: 0.8x ATR
- Reversion completed

### Ensemble Decision Making

The bot combines all 8 strategies using a weighted consensus system:

#### Signal Generation Process
1. **Individual Strategy Analysis:** Each strategy generates its own signal
2. **Weight Application:** Strategy weights applied based on recent performance
3. **Consensus Calculation:** Combined signal strength calculated
4. **Confidence Threshold:** Minimum 65% consensus required for action
5. **Final Decision:** Buy/Sell/Hold based on consensus and confidence

#### Adaptive Weighting
Strategy weights are automatically adjusted based on:
- Recent performance (last 20 trades)
- Market conditions (volatility, trend)
- Strategy correlation (avoid overexposure)
- Success rate vs. risk ratio

### Strategy Performance Monitoring

```bash
# Check strategy performance
curl http://localhost:8080/api/strategies/performance

# Individual strategy analysis
curl http://localhost:8080/api/strategies/momentum_breakthrough
curl http://localhost:8080/api/strategies/mean_reversion
```

---

## 🛡️ Risk Management

### Risk Management Overview

The Ultimate Trading Bot implements multiple layers of risk protection:

#### 1. Position Sizing

**Dynamic Position Sizing**
- Base position size determined by strategy confidence
- Adjusted for market volatility
- Reduced during high-risk conditions
- Increased during low-risk opportunities

**Position Size Formula:**
```
Position Size = Base Size × Volatility Factor × Trend Factor ×
               Confidence Factor × Risk Budget Factor ×
               Portfolio Heat Factor
```

**Risk Limits:**
- Maximum position size: 95% of portfolio
- Risk per trade: 2% of portfolio
- Maximum concurrent positions: 5

#### 2. Portfolio Heat Management

**Portfolio Heat Calculation:**
```
Portfolio Heat = (Total Risk Amount) / (Portfolio Value)
```

**Heat Management Rules:**
- Heat < 50%: Normal position sizing
- Heat 50-70%: Reduce positions by 20%
- Heat 70-80%: Reduce positions by 50%
- Heat > 80%: Stop all new positions

#### 3. Stop Loss & Take Profit

**Dynamic Stop Loss:**
- Based on Average True Range (ATR)
- Adjusted for market volatility
- Tightened during high volatility
- Loosened during low volatility

**Take Profit Targets:**
- Strategy-specific targets
- Adjusted for market conditions
- Partial profit taking at key levels
- Trailing stop for trend following

#### 4. Emergency Conditions

**Automatic Stop Conditions:**
- Portfolio drawdown > 15%
- Extreme market volatility (> 5% daily)
- Whale manipulation detected
- Flash crash conditions
- System health issues

**Manual Override:**
- Emergency stop via Telegram
- Pause trading temporarily
- Close all positions
- Switch to safe mode

### Risk Monitoring

#### Real-time Risk Metrics
```bash
# Check current risk level
curl http://localhost:8080/api/risk/current

# Risk assessment details
curl http://localhost:8080/api/risk/assessment

# Portfolio heat status
curl http://localhost:8080/api/risk/portfolio_heat
```

#### Risk Alerts
The bot sends Telegram alerts for:
- High risk level detected
- Emergency stop conditions
- Portfolio heat warnings
- Strategy performance degradation
- System health issues

### Risk Configuration

#### Risk Settings in `trading.toml`
```toml
[risk]
# Basic risk limits
max_position_size = 0.95
risk_per_trade = 0.02
max_drawdown = 0.15
portfolio_heat_limit = 0.8
correlation_limit = 0.7

# Stop loss settings
stop_loss_atr_multiplier = 1.5
take_profit_atr_multiplier = 2.5
trailing_stop_enabled = true
trailing_stop_atr_multiplier = 2.0

# Emergency conditions
emergency_stop_enabled = true
max_volatility_threshold = 0.05
max_drawdown_threshold = 0.15
min_confidence_threshold = 0.6
```

#### Risk Adjustment Factors
```toml
[risk.adjustments]
# Volatility adjustments
high_volatility_factor = 0.7    # Reduce positions 30%
low_volatility_factor = 1.2     # Increase positions 20%

# Trend adjustments
strong_trend_factor = 1.1       # Increase in strong trends
weak_trend_factor = 0.9         # Reduce in weak trends

# Market condition adjustments
bull_market_factor = 1.1        # Increase in bull markets
bear_market_factor = 0.9        # Decrease in bear markets
sideways_factor = 1.0           # Normal in sideways markets
```

### Risk Best Practices

#### 1. Start Conservative
- Use paper trading mode initially
- Start with small position sizes
- Monitor performance before scaling up
- Keep tight stop losses initially

#### 2. Monitor Regularly
- Check risk metrics daily
- Review strategy performance weekly
- Adjust risk parameters as needed
- Stay informed about market conditions

#### 3. Diversification
- Don't rely on single strategy
- Monitor strategy correlation
- Maintain balanced portfolio
- Avoid overconcentration

#### 4. Emergency Preparedness
- Have emergency stop procedures
- Monitor system health continuously
- Keep backup communication channels
- Test emergency scenarios

---

## 📊 Monitoring

### Monitoring Overview

The Ultimate Trading Bot provides comprehensive monitoring capabilities:

#### 1. Real-time Dashboard
- Live trading status
- Current positions
- Performance metrics
- System health indicators

#### 2. Performance Analytics
- Trade history and analysis
- Strategy performance comparison
- Risk metrics tracking
- Profit and loss reporting

#### 3. System Monitoring
- CPU and memory usage
- Network latency
- API response times
- Error rates

#### 4. Alert System
- Telegram notifications
- Email alerts (optional)
- Slack integration (optional)
- Custom webhook support

### Real-time Monitoring

#### Web Dashboard
Access the dashboard at `http://localhost:8080/dashboard`

**Dashboard Features:**
- Live price charts
- Current positions
- Recent trades
- Performance metrics
- System status

#### API Endpoints
```bash
# Overall status
curl http://localhost:8080/api/status

# Performance metrics
curl http://localhost:8080/api/performance

# Current positions
curl http://localhost:8080/api/positions

# Recent trades
curl http://localhost:8080/api/trades/recent

# System health
curl http://localhost:8080/api/health
```

### Performance Analytics

#### Key Performance Metrics
- **Win Rate:** Percentage of profitable trades
- **Profit Factor:** Total profit / Total loss
- **Sharpe Ratio:** Risk-adjusted returns
- **Maximum Drawdown:** Largest peak-to-trough decline
- **Average Execution Time:** Trade execution speed
- **Average Slippage:** Price execution variance

#### Performance Reports
```bash
# Daily performance report
curl http://localhost:8080/api/reports/daily

# Weekly performance report
curl http://localhost:8080/api/reports/weekly

# Monthly performance report
curl http://localhost:8080/api/reports/monthly

# Strategy performance breakdown
curl http://localhost:8080/api/reports/strategies
```

### Telegram Notifications

#### Alert Types
1. **Trade Execution:** Buy/Sell confirmations
2. **Performance Alerts:** Milestones and warnings
3. **Risk Alerts:** High risk conditions
4. **System Alerts:** Health and status updates
5. **Market Alerts:** Extreme market conditions

#### Custom Alert Configuration
```toml
[telegram]
token = "YOUR_TELEGRAM_TOKEN"
chat_id = "YOUR_CHAT_ID"

[telegram.alerts]
trade_alerts = true
performance_alerts = true
risk_alerts = true
system_alerts = true
market_alerts = true

[telegram.thresholds]
profit_milestone = 100      # Alert every $100 profit
loss_warning = 50          # Alert at $50 loss
risk_level_warning = 70    # Alert at 70% risk level
system_cpu_warning = 80    # Alert at 80% CPU usage
```

### System Health Monitoring

#### Health Check Endpoints
```bash
# Basic health check
curl http://localhost:8080/health

# Detailed health check
curl http://localhost:8080/health/detailed

# Component status
curl http://localhost:8080/health/components
```

#### Monitoring Metrics
- **CPU Usage:** Current CPU utilization
- **Memory Usage:** RAM consumption
- **Disk Usage:** Storage utilization
- **Network Latency:** API response times
- **Error Rate:** System error frequency
- **Uptime:** System running time

### Custom Monitoring

#### Custom Metrics
```python
# Add custom monitoring
from monitoring.ultimate_monitor import UltimateMonitor

monitor = UltimateMonitor(config, notifier)

# Custom alert
monitor.create_alert(
    severity="WARNING",
    category="CUSTOM",
    title="Custom Alert",
    message="Your custom message",
    data={"custom_field": "value"}
)
```

#### External Monitoring Integration
```bash
# Prometheus metrics (if enabled)
curl http://localhost:8080/metrics

# Grafana dashboard integration
# Configure Grafana to query Prometheus endpoint
```

---

## 🔌 API Usage

### REST API Reference

#### Base URL
```
http://localhost:8080/api/v1
```

#### Authentication
```bash
# Add API key to headers
curl -H "X-API-Key: your_api_key" http://localhost:8080/api/v1/status
```

### Core Endpoints

#### 1. System Status
```bash
# Get system status
GET /api/v1/status

Response:
{
    "status": "RUNNING",
    "version": "ULTIMATE-1.0.0",
    "uptime": 86400,
    "active_strategies": 8,
    "current_positions": 3
}
```

#### 2. Trading Operations
```bash
# Get current positions
GET /api/v1/positions

Response:
{
    "positions": [
        {
            "symbol": "SOL-USDC",
            "side": "LONG",
            "size": 100.0,
            "entry_price": 150.25,
            "current_price": 152.50,
            "pnl": 2.25,
            "strategy": "momentum_breakthrough"
        }
    ]
}

# Place manual trade
POST /api/v1/trade
{
    "symbol": "SOL-USDC",
    "side": "BUY",
    "size": 50.0,
    "order_type": "MARKET",
    "strategy": "manual"
}

# Close position
POST /api/v1/positions/{position_id}/close
```

#### 3. Performance Data
```bash
# Get performance metrics
GET /api/v1/performance

Response:
{
    "total_trades": 150,
    "win_rate": 0.65,
    "total_pnl": 1250.50,
    "sharpe_ratio": 1.85,
    "max_drawdown": 0.08,
    "avg_execution_time": 85.2
}

# Get trade history
GET /api/v1/trades?limit=50&offset=0

Response:
{
    "trades": [
        {
            "id": "trade_123",
            "symbol": "SOL-USDC",
            "side": "BUY",
            "size": 50.0,
            "price": 150.25,
            "fees": 0.75,
            "timestamp": "2025-10-07T10:30:00Z",
            "strategy": "momentum_breakthrough",
            "pnl": 25.50
        }
    ]
}
```

#### 4. Configuration
```bash
# Get current configuration
GET /api/v1/config

# Update configuration
PUT /api/v1/config
{
    "trading.max_position_size": 0.9,
    "risk.risk_per_trade": 0.025,
    "strategies.momentum_breakthrough": 0.16
}

# Reset configuration to defaults
POST /api/v1/config/reset
```

#### 5. Risk Management
```bash
# Get current risk metrics
GET /api/v1/risk

Response:
{
    "overall_risk_level": "MEDIUM",
    "risk_score": 45.2,
    "portfolio_heat": 0.65,
    "max_drawdown": 0.08,
    "risk_factors": ["moderate_volatility", "high_correlation"],
    "position_adjustment": 0.85
}

# Get risk limits
GET /api/v1/risk/limits

# Update risk limits
PUT /api/v1/risk/limits
{
    "max_position_size": 0.9,
    "risk_per_trade": 0.025,
    "portfolio_heat_limit": 0.85
}
```

### WebSocket API

#### Real-time Data
```javascript
// Connect to WebSocket
const ws = new WebSocket('ws://localhost:8080/ws');

// Subscribe to real-time updates
ws.send(JSON.stringify({
    "action": "subscribe",
    "channels": ["trades", "positions", "performance", "alerts"]
}));

// Handle real-time messages
ws.onmessage = function(event) {
    const data = JSON.parse(event.data);
    console.log('Received:', data);
};
```

#### WebSocket Channels
- `trades`: Real-time trade executions
- `positions`: Position updates
- `performance`: Performance metrics
- `alerts`: System alerts
- `market`: Market data updates

### Error Handling

#### Error Response Format
```json
{
    "error": {
        "code": "INVALID_PARAMETER",
        "message": "Invalid position size",
        "details": {
            "field": "size",
            "value": "invalid",
            "expected": "number > 0"
        }
    }
}
```

#### Common Error Codes
- `INVALID_PARAMETER`: Invalid request parameter
- `INSUFFICIENT_BALANCE`: Not enough balance for trade
- `RISK_LIMIT_EXCEEDED`: Risk limits exceeded
- `MARKET_CLOSED`: Market is closed for trading
- `API_RATE_LIMIT`: Too many API requests
- `SYSTEM_ERROR`: Internal system error

### Python SDK Example

```python
import requests
import json

class UltimateTradingBotClient:
    def __init__(self, base_url="http://localhost:8080/api/v1", api_key=None):
        self.base_url = base_url
        self.headers = {"X-API-Key": api_key} if api_key else {}

    def get_status(self):
        response = requests.get(f"{self.base_url}/status", headers=self.headers)
        return response.json()

    def get_positions(self):
        response = requests.get(f"{self.base_url}/positions", headers=self.headers)
        return response.json()

    def place_trade(self, symbol, side, size, order_type="MARKET"):
        data = {
            "symbol": symbol,
            "side": side,
            "size": size,
            "order_type": order_type,
            "strategy": "manual"
        }
        response = requests.post(f"{self.base_url}/trade", json=data, headers=self.headers)
        return response.json()

    def get_performance(self):
        response = requests.get(f"{self.base_url}/performance", headers=self.headers)
        return response.json()

# Usage example
client = UltimateTradingBotClient(api_key="your_api_key")

# Get system status
status = client.get_status()
print(f"System status: {status['status']}")

# Get current positions
positions = client.get_positions()
print(f"Current positions: {len(positions['positions'])}")

# Place a trade
trade_result = client.place_trade("SOL-USDC", "BUY", 50.0)
print(f"Trade result: {trade_result}")
```

---

## 🔧 Troubleshooting

### Common Issues

#### 1. Bot Won't Start
**Symptoms:**
- Service fails to start
- Error messages on startup
- Port already in use

**Solutions:**
```bash
# Check if port is in use
netstat -tuln | grep 8080

# Kill existing process
sudo kill -9 <PID>

# Check configuration
python -c "import toml; print('Config OK') if toml.load('config/trading.toml') else print('Config Error')"

# Check Python environment
python --version
pip list | grep fastapi
```

#### 2. API Connection Issues
**Symptoms:**
- API calls failing
- Timeout errors
- Authentication failures

**Solutions:**
```bash
# Test network connectivity
curl -I https://api.dexscreener.com

# Check API keys
echo $TELEGRAM_TOKEN
echo $HELIUS_API_KEY

# Test API manually
curl "https://api.telegram.org/bot$TELEGRAM_TOKEN/getMe"

# Check rate limits
curl -H "X-Rate-Limit-Remaining: 1" https://api.dexscreener.com/latest/dex
```

#### 3. Trading Issues
**Symptoms:**
- Trades not executing
- Slippage too high
- Position sizing errors

**Solutions:**
```bash
# Check trading configuration
curl http://localhost:8080/api/config

# Check risk limits
curl http://localhost:8080/api/risk/limits

# Check current positions
curl http://localhost:8080/api/positions

# Review recent trades
curl http://localhost:8080/api/trades/recent
```

#### 4. Performance Issues
**Symptoms:**
- Slow response times
- High CPU usage
- Memory leaks

**Solutions:**
```bash
# Check system resources
top
htop
free -h

# Check application logs
tail -f /var/log/mojorust.log

# Monitor API response times
curl -w "@curl-format.txt" http://localhost:8080/health

# Restart service
sudo systemctl restart mojorust
```

### Debug Mode

#### Enable Debug Logging
```bash
# Set debug mode in configuration
sed -i 's/debug_mode = false/debug_mode = true/' config/trading.toml
sed -i 's/log_level = "INFO"/log_level = "DEBUG"/' config/trading.toml

# Restart service
sudo systemctl restart mojorust

# Monitor debug logs
tail -f /var/log/mojorust.log | grep DEBUG
```

#### Debug Tools
```bash
# Check Python processes
ps aux | grep python

# Monitor network connections
netstat -an | grep 8080

# Check system performance
iostat -x 1
mpstat 1

# Test API endpoints
curl -v http://localhost:8080/health
```

### Log Analysis

#### Log Locations
```bash
# Application logs
/var/log/mojorust.log

# System logs
sudo journalctl -u mojorust -f

# Error logs
grep "ERROR" /var/log/mojorust.log

# Trading logs
grep "TRADE" /var/log/mojorust.log
```

#### Log Analysis Commands
```bash
# Recent errors
tail -100 /var/log/mojorust.log | grep ERROR

# Trade execution analysis
grep "EXECUTED" /var/log/mojorust.log | tail -20

# Performance analysis
grep "PERFORMANCE" /var/log/mojorust.log | tail -10

# API errors
grep "API_ERROR" /var/log/mojorust.log | tail -10
```

### Recovery Procedures

#### Service Recovery
```bash
# Check service status
sudo systemctl status mojorust

# Restart service
sudo systemctl restart mojorust

# Force restart
sudo systemctl stop mojorust
sudo systemctl start mojorust

# Check logs after restart
sudo journalctl -u mojorust --since "1 minute ago"
```

#### Data Recovery
```bash
# Backup current data
cp -r /root/mojorust/data /root/mojorust/data_backup

# Restore from backup
cp -r /root/mojorust/backup/data /root/mojorust/data

# Database recovery
psql mojorust_db < backup.sql

# Configuration recovery
cp config/trading.toml.backup config/trading.toml
```

#### Emergency Procedures
```bash
# Emergency stop all trading
curl -X POST http://localhost:8080/api/emergency_stop

# Close all positions
curl -X POST http://localhost:8080/api/positions/close_all

# Switch to safe mode
curl -X POST http://localhost:8080/api/safe_mode

# System reboot (last resort)
sudo reboot
```

### Getting Help

#### Support Channels
1. **Telegram Bot:** @RustMojoBot for alerts
2. **Documentation:** Check this guide and technical docs
3. **Logs:** Review application and system logs
4. **Community:** GitHub issues and discussions

#### Information to Provide
When requesting help, provide:
- Error messages
- Configuration details
- Log outputs
- System specifications
- Steps to reproduce the issue

---

## 📋 Best Practices

### Trading Best Practices

#### 1. Start Conservative
- **Paper Trading First:** Test strategies without real money
- **Small Position Sizes:** Start with 1-2% of portfolio
- **Monitor Closely:** Watch performance in real-time
- **Gradual Scaling:** Increase position sizes slowly

#### 2. Risk Management
- **Diversify Strategies:** Don't rely on single strategy
- **Set Stop Losses:** Always use stop-loss orders
- **Monitor Portfolio Heat:** Keep total exposure under control
- **Regular Reviews:** Weekly performance and risk assessment

#### 3. Market Awareness
- **Stay Informed:** Follow cryptocurrency news
- **Market Conditions:** Adjust strategies for different market states
- **Volatility Awareness:** Be extra careful during high volatility
- **Liquidity Checks:** Ensure sufficient liquidity for trades

#### 4. Technical Setup
- **Reliable Internet:** Stable connection required
- **Backup Systems:** Have backup internet and power
- **Regular Backups:** Backup configuration and data
- **Security Updates:** Keep system updated

### Configuration Best Practices

#### 1. Environment Management
```bash
# Use different environments
# Development: Test new features
# Staging: Pre-production testing
# Production: Live trading
```

#### 2. API Key Security
```bash
# Use environment variables for sensitive data
# Never hardcode API keys
# Rotate API keys regularly
# Use read-only keys where possible
```

#### 3. Configuration Validation
```bash
# Test configuration before deployment
python -c "
import toml
try:
    config = toml.load('config/trading.toml')
    print('Configuration is valid')
except Exception as e:
    print(f'Configuration error: {e}')
"
```

### Monitoring Best Practices

#### 1. Regular Health Checks
```bash
# Daily health check script
#!/bin/bash
response=$(curl -s http://localhost:8080/health)
if [[ $response == *"HEALTHY"* ]]; then
    echo "✅ System is healthy"
else
    echo "❌ System health check failed"
    # Send alert
fi
```

#### 2. Performance Monitoring
- **Key Metrics:** Win rate, profit factor, drawdown
- **Alert Thresholds:** Set reasonable alert levels
- **Regular Reviews:** Weekly and monthly performance analysis
- **Strategy Rotation:** Adjust strategy weights based on performance

#### 3. Log Management
```bash
# Log rotation setup
sudo nano /etc/logrotate.d/mojorust

# Content:
/var/log/mojorust.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        systemctl reload mojorust
    endscript
}
```

### Security Best Practices

#### 1. System Security
```bash
# Firewall configuration
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 8080
sudo ufw deny all other ports

# User permissions
sudo adduser mojorust
sudo chown -R mojorust:mojorust /root/mojorust
```

#### 2. API Security
```bash
# Use HTTPS in production
# Implement rate limiting
# Validate all inputs
# Use secure API keys
```

#### 3. Trading Security
```bash
# Use hardware wallets for large amounts
# Implement withdrawal limits
# Regular security audits
# Keep software updated
```

### Performance Optimization

#### 1. System Optimization
```bash
# Optimize system parameters
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'net.core.somaxconn=65535' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

#### 2. Application Optimization
```python
# Use efficient data structures
# Implement caching
# Optimize database queries
# Use connection pooling
```

#### 3. Network Optimization
```bash
# Use CDN for static assets
# Implement compression
# Optimize API response times
# Use efficient serialization
```

### Maintenance Schedule

#### Daily Tasks
- [ ] Check system health
- [ ] Review trading performance
- [ ] Monitor risk metrics
- [ ] Check for alerts

#### Weekly Tasks
- [ ] Performance analysis
- [ ] Strategy review
- [ ] Configuration backup
- [ ] Security checks

#### Monthly Tasks
- [ ] Deep performance analysis
- [ ] Strategy optimization
- [ ] System maintenance
- [ ] Documentation updates

#### Quarterly Tasks
- [ ] Strategy backtesting
- [ ] Risk assessment
- [ ] System audit
- [ ] Planning for improvements

---

## 📞 Support

### Contact Information

- **Development Team:** Available through GitHub issues
- **Emergency Support:** Telegram bot alerts
- **Documentation:** This guide and technical documentation
- **Community:** GitHub discussions

### Resources

- **GitHub Repository:** https://github.com/SynergiaOS/MojoRust
- **Technical Documentation:** `TECHNICAL_DOCUMENTATION.md`
- **API Documentation:** `API_DOCUMENTATION.md`
- **Configuration Guide:** This guide

### Contributing

We welcome contributions! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

### License

This project is licensed under the MIT License - see the LICENSE file for details.

---

*This user guide provides comprehensive information for using the Ultimate Trading Bot. For technical implementation details, please refer to the technical documentation.*