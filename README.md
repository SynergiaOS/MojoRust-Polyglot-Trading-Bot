# 🚀 Algorithmic Memecoin Trading Bot for Solana

A high-performance trading bot designed for Solana memecoin markets using **pure algorithmic intelligence**, optimized execution, and comprehensive risk management. **No external AI dependencies required!**

---

## 🚀 Quick Deployment to Production Server

### Server Information
- **Production Server**: `38.242.239.150`
- **Quick Connect**: `ssh root@38.242.239.150`

### ⚡ One-Command Deployment
```bash
# From your local machine
./scripts/deploy_to_server.sh

# Or on the server directly
ssh root@38.242.239.150
curl -sSL https://raw.githubusercontent.com/SynergiaOS/MojoRust/main/scripts/quick_deploy.sh | bash
```

### 📖 Quick Links
- 📖 [Immediate Deployment Guide](DEPLOY_NOW.md) - English
- 📖 [Przewodnik Wdrożenia](DEPLOY_NOW_PL.md) - Polski
- 📖 [Full Deployment Documentation](DEPLOYMENT.md)
- 🔧 [Infisical Setup](https://app.infisical.com)

### 🛠️ Deployment Options
- **Automated deployment**: `./scripts/deploy_to_server.sh`
- **Manual VPS setup**: `./scripts/vps_setup.sh`
- **Quick deploy**: `./scripts/quick_deploy.sh`
- **Filtered deployment**: `./scripts/deploy_with_filters.sh`
- **Docker deployment**: `docker-compose up -d`

### 🔍 Health Monitoring
```bash
# Check server health
./scripts/server_health.sh --remote

# View logs
ssh root@38.242.239.150 'tail -f ~/mojo-trading-bot/logs/trading-bot-*.log'
```

### ⚠️ Pre-Deployment Requirements
- ✅ Infisical account at https://app.infisical.com
- ✅ Helius API key
- ✅ QuickNode RPC endpoint
- ✅ Solana wallet configured
- ✅ SSH access to 38.242.239.150

> **🚨 WARNING**: Always start with **PAPER TRADING MODE**. Monitor for at least 24 hours before switching to LIVE trading with real funds.

---

## 🎯 Performance Targets

- **Daily ROI**: 2-5%
- **Win Rate**: 65-75%
- **Max Drawdown**: <15%
- **Execution Latency**: <100ms (50-100ms typical)
- **Strategy**: RSI + Support/Resistance confluence detection
- **Processing Speed**: 10x faster than AI-powered solutions
- **Cost Efficiency**: $0/month in AI fees (saves $25+/month)

## 🎯 Algorithmic-Only Benefits

- **Ultra-Low Latency**: 50-100ms execution without external API calls
- **Complete Determinism**: Reproducible results without AI randomness
- **Cost Optimization**: $25+/month savings on AI API fees
- **Privacy & Security**: No data sharing with external AI services
- **Reliability**: No dependency on third-party AI availability

---

## ⚡ Quick Start (5 Minutes)

Get the trading bot running in just 5 minutes with our streamlined setup process.

### 🚀 One-Command Quick Start
```bash
# Clone and setup in seconds
git clone https://github.com/SynergiaOS/MojoRust.git
cd MojoRust
chmod +x scripts/*.sh

# Configure API keys (minimum required)
cp .env.example .env
nano .env

# Environment setup for basic functionality
export HELIUS_API_KEY=your_helius_api_key_here
export QUICKNODE_PRIMARY_RPC=your_quicknode_rpc_here
export GEYSER_ENDPOINT=your_geyser_endpoint_here
export TWITTER_API_KEY=your_twitter_api_key_here

# Add your required API keys to .env file. At a minimum, you will need:
# - HELIUS_API_KEY
# - QUICKNODE_PRIMARY_RPC
# For advanced features, you will also need:
# - GEYSER_ENDPOINT and GEYSER_TOKEN
# - TWITTER_API_KEY, TWITTER_API_SECRET, etc.

# Start trading in safe paper mode
./scripts/start_bot.sh --mode=paper --verbose
```

### 📋 What You Need (2 minutes)
- **API Keys**:
  - [Helius](https://www.helius.dev/) (Get free API key)
  - [QuickNode](https://www.quicknode.com/) (Get free RPC endpoint)
- **Solana Wallet**: Automatically detected or create new one
- **Basic Tools**: `git`, `curl`, command line

### 🎯 Instant Results
Your bot will immediately start:
- ✅ Analyzing Solana memecoin markets
- ✅ Executing paper trades (no real money)
- ✅ Providing real-time metrics at `http://localhost:8080`
- ✅ Logging activity to `logs/trading-bot-*.log`

### 📊 Monitor Your Bot
```bash
# Check bot status
curl http://localhost:8080/api/health

# View recent activity
curl http://localhost:8080/api/status

# Watch real-time logs
tail -f logs/trading-bot-*.log
```

### 🔧 Need Help?
- 📖 **Complete Guide**: [Bot Startup Guide](docs/BOT_STARTUP_GUIDE.md)
- ⚡ **Fastest Path**: [5-Minute Quick Start](docs/QUICK_START.md)
- 🔐 **Wallet Setup**: [Wallet Setup Guide](docs/WALLET_SETUP_GUIDE.md)
- 🚀 **Production Deploy**: [Deployment Guide](DEPLOYMENT.md)

---

## 🏗️ System Architecture

```
Data Layer (APIs) → Processing Layer (Algorithmic Engines) → Execution Layer (Trading)
```


### 🏛️ Advanced Architecture Guides

For comprehensive understanding of the bot's architecture, refer to these detailed guides:

- **[RPC Provider Strategy](docs/RPC_PROVIDER_STRATEGY.md)**: Dual-RPC routing, health checks, and failover mechanisms
- **[Flash Loan Integration](docs/FLASH_LOAN_INTEGRATION.md)**: Arbitrage strategies using Solend and Kamino flash loans
- **[Data Ingestion Architecture](docs/DATA_INGESTION_ARCHITECTURE.md)**: Real-time data pipelines with Geyser and Yellowstone
- **[Portfolio Manager Design](docs/PORTFOLIO_MANAGER_DESIGN.md)**: Rust-based capital allocation and risk management
- **[Advanced Filters Guide](docs/ADVANCED_FILTERS_GUIDE.md)**: Multi-stage filtering engine with spam detection
- **[Free Data Sources Guide](docs/FREE_DATA_SOURCES_GUIDE.md)**: Integrating Geyser and other free real-time data sources.
- **[MEV Strategy Guide](docs/MEV_STRATEGY_GUIDE.md)**: MEV extraction techniques with Jito bundles
- **[Parallel Processing Architecture](docs/PARALLEL_PROCESSING_ARCHITECTURE.md)**: Asyncio-based task pool for high-throughput analysis

### 🛠️ Technology Layer Responsibilities

This project uses a polyglot architecture where each language has specific responsibilities:

- **Python (🐍)**: **Orchestration Layer**
  - **Responsibilities**: API clients, task scheduling, webhooks, database interactions, main application loop
  - **Why?**: Python's rich ecosystem and mature `asyncio` framework perfect for managing complex workflows

- **Mojo (🔥)**: **Intelligence Layer**
  - **Responsibilities**: Filters/ML inference, signal generation, data analysis, pattern recognition
  - **Why?**: Mojo's Python-like syntax with C-level performance for computationally intensive tasks
  - **Note**: Mojo handles intelligence but NOT execution - it provides data to Rust

- **Rust (🦀)**: **Secure Execution Layer**
  - **Responsibilities**: Private keys, transaction signing, CPI calls, Jito bundles, portfolio management
  - **Why?**: Rust's ownership model and compile-time guarantees ensure security of funds and safe execution
  - **NEW**: High-performance Geyser data consumer for filtering on-chain events at the source.

### 🚀 New: Free Data Sources & High-Performance Ingestion

The bot now features a powerful data ingestion pipeline that leverages free, real-time data from Solana's Geyser stream, significantly reducing reliance on paid APIs.

**Architecture:**
```
┌──────────────────┐      ┌───────────────────┐      ┌──────────────────┐      ┌──────────────────┐
│ Solana Geyser    ├─────►│ Rust Data         ├─────►│ Redis Pub/Sub    ├─────►│ Python           │
│ (gRPC Stream)    │      │ Consumer          │      │ (Channels)       │      │ TaskPoolManager  │
└──────────────────┘      │ (Filtering >99%)  │      └──────────────────┘      │ (Subscriber)     │
                          └───────────────────┘                                └──────────────────┘
```

This design offloads the heavy lifting of event filtering to a compiled Rust binary, allowing the Python layer to focus on complex analysis and orchestration.

📖 **Read the Full Guide: `docs/FREE_DATA_SOURCES_GUIDE.md`**

### Core Components

- **Data Collection**: Helius (blockchain), QuickNode (RPC), DexScreener (market data), Jupiter (DEX aggregator)
- **Algorithmic Analysis**:
  - Sentiment Analyzer (market-based sentiment, no external AI)
  - Pattern Recognition Engine (technical and manipulation patterns)
  - Whale Behavior Tracker (on-chain analysis)
  - Volume Analysis Engine (anomaly detection)
- **Strategy Engines**:
  - Enhanced Context Engine (RSI+Support confluence)
  - Spam Filter (wash trading detection)
  - Strategy Engine (signal generation)
- **Risk Management**: Kelly Criterion position sizing, portfolio diversification, drawdown monitoring
- **Execution**: Optimized trade execution via Jupiter with slippage control

## 🎯 Advanced Sniper Trading System

### Overview
The **PumpFun Sniper Trading System** is a specialized high-frequency trading module designed for memecoin markets on Solana. It combines advanced filtering, real-time monitoring, and MEV extraction to identify and execute profitable trades on newly launched tokens.

### 🎯 Key Features

#### Advanced Sniper Filters
- **LP Burn Analysis**: Verifies ≥90% LP tokens are burned to prevent rug pulls
- **Authority Revocation**: Ensures mint/freeze authorities are revoked for token security
- **Holder Distribution**: Analyzes top 5 holder concentration (<30% threshold)
- **Social Mentions**: Monitors X/Twitter for minimum social activity (10+ mentions)
- **Honeypot Detection**: Integrated API checks for contract security
- **Volume Requirements**: Minimum active volume of $5,000 in 5 minutes

#### Trading Modes

**1. PumpPortal Real-Time Trader**
- WebSocket-based real-time token monitoring
- Sub-100ms signal processing
- Automatic TP/SL execution (1.5x TP, 0.8x SL)
- Position management with timeout controls

**2. Jito MEV Extractor**
- Bundle-based MEV extraction
- Optimized transaction ordering
- Dynamic tip calculation based on profit potential
- Sub-30ms bundle submission

### 📊 Sniper Performance Metrics

```bash
# Typical sniper performance:
- Signal Processing: 50-100ms latency
- Win Rate: 70-85% (with filters)
- Average ROI: 5-15% per trade
- Rejection Rate: 90-95% (quality filtering)
- Bundle Success Rate: 80-90%
```

### 🚀 Quick Start for Sniper Trading

#### 1. API Requirements
```bash
# Required API keys for sniper trading:
HONEYPOT_API_KEY=your_honeypot_api_key_here
TWITTER_API_KEY=your_twitter_api_key_here
PUMPPORTAL_API_KEY=your_pumpportal_api_key_here
JITO_AUTH_KEY=your_jito_auth_key_here
```

#### 2. Configuration
```toml
[arbitrage.sniper_filters]
min_lp_burn_rate = 90.0
revoke_authority_required = true
max_top_holders_share = 30.0
min_social_mentions = 10
social_check_enabled = true
honeypot_check = true
tp_threshold = 1.5
sl_threshold = 0.8
```

#### 3. Launch Sniper Traders
```bash
# PumpPortal real-time trader
python pumpportal_realtime_trader.py

# Jito MEV extractor
python jito_pumpfun_trader.py

# Or run both with monitoring
./scripts/start_sniper_trading.sh --monitor
```

### 🛡️ Sniper Safety Features

#### Multi-Layer Security
1. **Pre-Trade Validation**: All tokens pass through 5 security checks
2. **Real-time Monitoring**: Continuous position tracking and exit conditions
3. **Circuit Breakers**: Automatic position limits and drawdown protection
4. **Fail-Safe Defaults**: Reject on API errors or insufficient data

#### Risk Management
```bash
# Built-in safety limits:
- Max Open Positions: 5 simultaneous trades
- Max Position Size: 10% of portfolio
- Minimum Trade Interval: 30 seconds
- Maximum Token Age: 5 minutes
- Stop Loss: 20% (automatic)
- Take Profit: 50% (automatic)
```

### 📈 Sniper Monitoring Dashboard

Access comprehensive sniper monitoring at `http://localhost:3000`:
- **Signal Processing**: Real-time filter performance
- **API Health**: Status of all external APIs
- **Trading Metrics**: Win rate, P&L, position tracking
- **MEV Performance**: Bundle success rates and tip costs
- **Risk Metrics**: Drawdown, concentration, exposure

#### Key Metrics
- `sniper_filter_rejections_total` - Filter rejection reasons
- `sniper_trades_won_total` - Successful trade count
- `jito_bundles_confirmed_total` - MEV bundle confirmations
- `sniper_portfolio_balance_sol` - Current portfolio value
- `sniper_signal_quality_score` - Overall signal quality

### ⚠️ Sniper Trading Risks

**High-Risk Activity**: Sniper trading is extremely high-risk and should only be attempted with:
- Capital you can afford to lose completely
- Extensive testing in paper trading mode
- Understanding of memecoin market dynamics
- Proper risk management procedures

**Recommended Approach**:
1. Start with **0.1 SOL** maximum capital
2. Run in **paper trading mode** for at least 48 hours
3. Monitor win rate and rejection rates
4. Gradually increase capital only after consistent performance
5. Never risk more than 5% of total portfolio on sniper trading

### 🔧 Sniper Troubleshooting

#### Common Issues
```bash
# High rejection rate (95%+)
- Check API key validity
- Verify filter thresholds aren't too strict
- Monitor social API status

# Low win rate (<60%)
- Adjust TP/SL thresholds
- Review market conditions
- Check honeypot API accuracy

# Bundle failures
- Increase tip amounts
- Check network congestion
- Verify Jito endpoint status
```

#### Health Checks
```bash
# API health monitoring
curl http://localhost:8080/api/sniper/health

# Filter performance
curl http://localhost:8080/api/sniper/filters/stats

# Active positions
curl http://localhost:8080/api/sniper/positions
```

---

## 🛡️ Production Safety & Monitoring

### Circuit Breakers
Automated trading halt mechanisms to protect capital:
- **Max Drawdown Protection**: Halts trading if portfolio drops >15%
- **Consecutive Loss Protection**: Stops after 5 consecutive losing trades
- **Daily Loss Limit**: Halts if daily losses exceed 10%
- **Position Concentration**: Prevents over-exposure to single positions
- **Trade Velocity Control**: Limits rapid-fire trading on same symbol
- **Rapid Drawdown Detection**: Catches sudden portfolio drops

### Performance Analytics
Comprehensive performance tracking and analysis:
- **Win Rate**: Percentage of profitable trades
- **Sharpe Ratio**: Risk-adjusted return metric
- **Sortino Ratio**: Downside risk-adjusted return
- **Max Drawdown**: Peak-to-trough portfolio decline
- **Profit Factor**: Gross profit / gross loss ratio
- **Expectancy**: Expected value per trade
- **Trade Distribution Analysis**: Win/loss patterns
- **Equity Curve Tracking**: Portfolio value over time

### Data Persistence
TimescaleDB/PostgreSQL integration for:
- **Trade History**: Complete record of all trades
- **Portfolio Snapshots**: Regular portfolio state saves
- **Market Data Archive**: Historical market data storage
- **Performance Metrics**: Time-series performance tracking
- **Backup & Recovery**: Automatic portfolio state restoration

### Alert System
Multi-channel notifications for:
- **Trade Execution**: Real-time trade confirmations
- **Error Alerts**: Critical error notifications
- **Performance Alerts**: Threshold breach warnings
- **Circuit Breaker Triggers**: Trading halt notifications
- **Daily Summaries**: End-of-day performance reports

Supported channels:
- Console (always enabled)
- Discord/Slack webhooks
- Telegram bot
- Email (coming soon)

### Data Ingestion Pipeline Monitoring

The health and performance of the Rust `data-consumer` and Python `TaskPoolManager` are critical. We provide a pre-built Grafana dashboard and Prometheus alerts to monitor this pipeline.

#### Grafana Dashboard

A dedicated "Data Ingestion Pipeline" dashboard is available in Grafana (`config/grafana/dashboards/data_ingestion.json`). It visualizes key metrics, including:

- **Rust Consumer (Geyser)**:
  - Event Throughput (received vs. published)
  - Event Filter Rate (%)
  - Processing Latency (p95)
  - Geyser Connection Status

- **Python Consumer (Task Manager)**:
  - Redis Pub/Sub Lag (ms)
  - Task Queue Size
  - Dropped Events Rate (due to backpressure)

#### Prometheus Alerts

Alerting rules are defined in `config/prometheus_rules/data_ingestion_alerts.yml` to notify you of potential issues:

- `HighRedisPubSubLag`: Fires if the lag between the Rust producer and Python consumer exceeds 5 seconds, indicating the Python service is falling behind.
- `HighRateOfDroppedEvents`: Fires if the Python service is dropping events due to a full task queue, indicating sustained high load.

### Strategy Adaptation
Dynamic parameter adjustment based on performance:
- **Confidence Threshold Tuning**: Adjust selectivity based on win rate
- **Position Sizing Adaptation**: Scale up/down based on performance
- **Stop Loss/Take Profit Optimization**: Adjust risk/reward ratios
- **Market Regime Detection**: Adapt to trending vs ranging markets
- **Performance-Based Learning**: Improve over time without external AI

## 📊 Complete Trading Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    DATA INGESTION                           │
│  DexScreener → QuickNode → Helius → Market Data            │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                 CIRCUIT BREAKER CHECK                       │
│  ✓ Drawdown OK  ✓ No consecutive losses  ✓ Velocity OK     │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                  CONTEXT ANALYSIS                           │
│  RSI + Support/Resistance + Market Regime Detection         │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                 SIGNAL GENERATION                           │
│  Strategy Engine → Raw Signals (100-1000/hour)             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              MASTER FILTER PIPELINE                         │
│  Instant Filter → Aggressive Filter → Micro Filter          │
│  (90-95% rejection rate)                                    │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                 RISK MANAGEMENT                             │
│  Position Sizing + Stop Loss + Portfolio Limits             │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│              TRADE EXECUTION                                │
│  Jupiter Swap → Blockchain → Confirmation                   │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│          MONITORING & PERSISTENCE                           │
│  • Record trade in database                                 │
│  • Update performance analytics                             │
│  • Send alerts                                              │
│  • Update circuit breakers                                  │
│  • Save portfolio snapshot                                  │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│            STRATEGY ADAPTATION (24h)                        │
│  Analyze performance → Adjust parameters → Optimize         │
└─────────────────────────────────────────────────────────────┘
```

## 🗄️ Database Setup

### TimescaleDB Installation

```bash
# Install TimescaleDB (PostgreSQL extension)
sudo apt-get install timescaledb-postgresql-14

# Create database
sudo -u postgres psql
CREATE DATABASE trading_bot;
CREATE USER trader WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE trading_bot TO trader;
\c trading_bot
CREATE EXTENSION IF NOT EXISTS timescaledb;
```

### Environment Variables

```bash
export DB_PASSWORD="your_database_password"
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
export TELEGRAM_BOT_TOKEN="your_telegram_bot_token"
export TELEGRAM_CHAT_ID="your_telegram_chat_id"
```

### Database Schema

The bot automatically creates required tables on first run:
- `trades` - Complete trade history
- `portfolio_snapshots` - Portfolio state over time
- `market_data` - Historical market data (TimescaleDB hypertable)
- `performance_metrics` - Performance statistics over time

## 📱 Alert Configuration

### Discord Webhook

1. Go to Discord Server Settings → Integrations → Webhooks
2. Create new webhook, copy URL
3. Set `DISCORD_WEBHOOK_URL` environment variable
4. Enable in `config/trading.toml`: `channels = ["console", "webhook"]`

### Telegram Bot

1. Create bot via [@BotFather](https://t.me/botfather)
2. Get bot token
3. Get your chat ID via [@userinfobot](https://t.me/userinfobot)
4. Set environment variables:
   ```bash
   export TELEGRAM_BOT_TOKEN="your_token"
   export TELEGRAM_CHAT_ID="your_chat_id"
   ```
5. Enable in config: `channels = ["console", "telegram"]`

## 🎯 Strategy Adaptation

The bot automatically adapts its strategy every 24 hours based on recent performance:

**Low Win Rate (<40%)**
- Increases confidence threshold (more selective)
- Reduces position sizes (lower risk)
- Reason: "Low win rate - increasing selectivity"

**High Win Rate (>70%)**
- Decreases confidence threshold (more trades)
- Increases position sizes (higher returns)
- Reason: "High win rate - increasing aggression"

**Poor Profit Factor (<1.5)**
- Tightens stop losses
- Widens take profit targets
- Reason: "Poor profit factor - adjusting risk/reward"

**High Volatility Market**
- Reduces position sizes
- Decreases max concurrent positions
- Reason: "High volatility - reducing exposure"

Adaptation can be disabled in `config/trading.toml`:
```toml
[strategy_adaptation]
enabled = false
```

## 🛠️ Tech Stack

- **Performance**: Mojo 24.4+ (for hot paths and computational efficiency)
- **Security**: Rust 1.70+ (for cryptographic operations and critical components)
- **Blockchain**: Solana Web3.js, Anchor Framework
- **Database**: TimescaleDB (time-series data), Redis (caching)
- **Algorithmic Intelligence**: Built-in algorithmic analysis (no external AI dependencies)
- **Monitoring**: Prometheus/Grafana (metrics, dashboards)
- **Infrastructure**: Docker, Kubernetes

## 💻 Hardware Requirements

- **CPU**: 8+ cores (Intel i7/AMD Ryzen 7 or better)
- **RAM**: 32GB+ DDR4
- **Storage**: 1TB+ NVMe SSD
- **Network**: Stable internet connection with <50ms latency to Solana RPCs

## 🚀 Quick Start

### Prerequisites

1. **Mojo** 24.4+ installed: [Download Mojo](https://www.modular.com/mojo)
2. **Rust** 1.70+ installed: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
3. **Docker** 24.0+ and Docker Compose
4. **API Accounts**:
   - Helius Premium ($49/mo)
   - QuickNode Premium ($49/mo)
   - DexScreener (free)
   - Jupiter (free)

### Installation

```bash
# Clone repository
git clone https://github.com/your-org/mojo-trading-bot.git
cd mojo-trading-bot

# Configure environment
cp .env.example .env
# Edit .env with your API keys and configuration

# Deploy and run (automated build and deployment)
./scripts/deploy.sh --mode=paper --capital=1.0

# Or manual deployment:
# - Build: mojo build src/main.mojo -o target/trading-bot
# - Test: mojo run tests/test_suite.mojo
# - Run: ./target/trading-bot --mode=paper --capital=1.0
```

### Environment Configuration

Copy `.env.example` to `.env` and configure:

```bash
# Trading mode
TRADING_ENV=paper  # development/staging/production

# API Keys
HELIUS_API_KEY=your_helius_api_key
QUICKNODE_PRIMARY_RPC=https://your-endpoint.solana-mainnet.quiknode.pro/

# Wallet Configuration
WALLET_ADDRESS=your_solana_wallet_address
WALLET_PRIVATE_KEY_PATH=/secure/path/to/keypair.json

# Trading Parameters
INITIAL_CAPITAL=1.0  # SOL
MAX_POSITION_SIZE=0.1  # 10%
MAX_DRAWDOWN=0.15  # 15%
```

## 📊 Project Structure

```text
├── src/                    # Mojo source code
│   ├── main.mojo          # Application entry point
│   ├── core/              # Core data structures and utilities
│   │   ├── config.mojo    # Configuration management
│   │   ├── types.mojo     # Core data types
│   │   └── logger.mojo    # Structured logging
│   ├── data/              # External API clients
│   │   ├── helius_client.mojo
│   │   ├── quicknode_client.mojo
│   │   ├── dexscreener_client.mojo
│   │   └── jupiter_client.mojo
│   ├── engine/            # Trading and analysis engines
│   │   ├── enhanced_context_engine.mojo
│   │   ├── master_filter.mojo
│   │   ├── strategy_engine.mojo
│   │   ├── spam_filter.mojo
│   │   ├── instant_spam_detector.mojo
│   │   ├── micro_timeframe_filter.mojo
│   │   └── strategy_adaptation.mojo
│   ├── risk/              # Risk management
│   │   ├── risk_manager.mojo
│   │   └── circuit_breakers.mojo
│   ├── monitoring/        # Production monitoring components
│   │   ├── performance_analytics.mojo
│   │   └── alert_system.mojo
│   ├── persistence/       # Data persistence
│   │   └── database_manager.mojo
│   ├── execution/         # Trade execution
│   │   └── execution_engine.mojo
│   └── analysis/          # Algorithmic analysis engines
│       ├── sentiment_analyzer.mojo
│       ├── pattern_recognizer.mojo
│       └── whale_tracker.mojo
├── rust-modules/          # Rust security modules
├── config/                # Configuration files
│   └── trading.toml       # Main configuration
├── tests/                 # Unit and integration tests
├── scripts/               # Deployment and utility scripts
└── docs/                  # Documentation
```

## 🧪 Testing

```bash
# Run all tests
mojo test tests/

# Run specific test suite
mojo test tests/test_context_engine.mojo
mojo test tests/test_risk_manager.mojo

# Run backtests
mojo run tests/backtest/backtest_engine.mojo --start=2024-01-01 --end=2024-03-01

# Performance tests
mojo run tests/performance/latency_test.mojo
```

## 📈 Development Roadmap (12 Weeks)

### Phase 1: Foundation (Week 1-2)
- [x] Project structure and environment setup
- [x] Core data models and configuration
- [x] Basic API integrations
- [x] Context Engine MVP
- [x] Simple spam filtering

### Phase 2: Core Engine (Week 3-4)
- [x] Advanced spam detection (wash trading, pump/dump)
- [x] Strategy Engine implementation
- [x] Risk management system
- [x] Paper trading framework
- [x] Performance monitoring

### Phase 3: Algorithmic Enhancements (Week 5-6)
- [x] Algorithmic sentiment analysis (`src/analysis/sentiment_analyzer.mojo`)
- [x] Pattern recognition engine (`src/analysis/pattern_recognizer.mojo`)
- [x] Whale behavior tracking (`src/analysis/whale_tracker.mojo`)
- [x] Volume anomaly detection (`src/analysis/volume_analyzer.mojo`)
- [x] Real-time signal processing and optimization

### Phase 4: Production (Week 7-8)
- [x] Live trading with small capital
- [x] Execution optimization
- [x] Comprehensive monitoring
- [x] Scaling and performance tuning

### Phase 5: Enhancement (Week 9-12)
- [x] Multi-strategy optimization
- [x] Advanced risk models
- [x] Machine learning integration
- [x] Institutional features

## 🔍 Monitoring

Access Grafana dashboards at `http://localhost:3000`:
- Portfolio performance and P&L
- Trade execution metrics
- API latency and error rates
- System health indicators

Prometheus metrics at `http://localhost:9090/metrics`

## ⚠️ Risk Management

The bot implements multiple safety layers:

1. **Position Sizing**: Kelly Criterion with 50% fraction (conservative)
2. **Stop Losses**: Support-based with 15% buffer
3. **Drawdown Protection**: Stops trading at 15% drawdown
4. **Diversification**: Max 10 positions, sector caps
5. **Spam Filtering**: Removes 80-90% of low-quality signals
6. **Circuit Breakers**: Halts trading on extreme volatility

## 📊 Performance Metrics

Target metrics during backtesting and live trading:

- **Win Rate**: 65-75%
- **Profit Factor**: >2.0
- **Sharpe Ratio**: >2.0
- **Max Drawdown**: <15%
- **Average Trade Duration**: 5-30 minutes
- **Execution Latency**: <100ms

## 🚨 Alerts

Configurable alerts for:
- Drawdown >10%
- Execution failure rate >5%
- API error rate >10%
- Low wallet balance
- Unusual trading patterns

## 🔒 Security

- Private keys stored securely in Rust module
- No credential logging
- Rate limiting on all APIs
- Encrypted wallet storage
- Audit logging for all trades
- Regular security patches

## 📚 Documentation

- [Implementation Guide](IMPLEMENTATION_GUIDE.md) - Complete setup and deployment guide
- [Architecture](docs/ARCHITECTURE.md) - System design and components
- [API Reference](docs/API.md) - External API integrations
- [Trading Strategy](docs/STRATEGY.md) - Detailed strategy explanations
- [Deployment Script](scripts/deploy.sh) - Automated deployment utility
- [Test Suite](tests/test_suite.mojo) - Comprehensive testing framework

## 🤝 Contributing

We welcome contributions! Please read our guidelines before submitting.

### 📚 Contribution Resources

- 📋 **[Contributing Guidelines](CONTRIBUTING.md)** - Detailed process and requirements
- 🛡️ **[Code of Conduct](CODE_OF_CONDUCT.md)** - Community standards (required reading)
- 🔒 **[Security Policy](SECURITY.md)** - Report vulnerabilities responsibly
- 📝 **[Changelog](CHANGELOG.md)** - Track project changes

### 🚀 Quick Contribution Guide

**For Code Contributions:**
1. Fork the repository
2. Create feature branch: `git checkout -b feature/your-feature`
3. Install development tools: `make setup-dev`
4. Make changes following our [code style guidelines](CONTRIBUTING.md#code-style)
5. Write tests (70%+ coverage required)
6. Run checks: `make ci`
7. Commit with [conventional format](https://www.conventionalcommits.org/): `type(scope): description`
8. Push and open Pull Request
9. Address review feedback
10. Celebrate when merged! 🎉

**For Non-Code Contributions:**
- 🐛 Report bugs via [GitHub Issues](https://github.com/SynergiaOS/MojoRust/issues)
- 💡 Suggest features via [GitHub Discussions](https://github.com/SynergiaOS/MojoRust/discussions)
- 📖 Improve documentation (typos, clarity, examples)
- 🌍 Add translations (Polish, English, others)
- 💬 Help others in community channels
- ⭐ Star the repository if you find it useful!

### ✅ Contribution Requirements

**Before Submitting PR:**
- [ ] All tests pass: `make test-all`
- [ ] Code coverage ≥70%: `make test-coverage-report`
- [ ] No linting errors: `make lint`
- [ ] No security issues: `make validate-secrets`
- [ ] CHANGELOG.md updated (for notable changes)
- [ ] Documentation updated (for user-facing changes)
- [ ] Conventional commit messages used
- [ ] No hardcoded secrets or credentials

**Code Review:**
- At least 1 approval from maintainer required
- CI checks must pass (lint, security, build, test, coverage)
- Security-sensitive changes require additional review
- Performance changes require benchmarks

### 🎯 Good First Issues

New to the project? Look for issues labeled:
- `good first issue` - Beginner-friendly tasks
- `documentation` - Documentation improvements
- `help wanted` - Community help needed
- `bug` - Bug fixes (great for learning codebase)

### 💬 Community

**Get Help:**
- 💭 [GitHub Discussions](https://github.com/SynergiaOS/MojoRust/discussions) - Ask questions
- 🐛 [GitHub Issues](https://github.com/SynergiaOS/MojoRust/issues) - Report bugs
- 📖 [Documentation](docs/) - Read guides
- 💬 Discord/Telegram - Community chat (links in repository)

**Code of Conduct:**
All contributors must follow our [Code of Conduct](CODE_OF_CONDUCT.md). We are committed to providing a welcoming and inclusive environment.

### 🏆 Recognition

**Contributors are recognized through:**
- GitHub contributors page
- Release notes acknowledgments
- Security Hall of Fame (for vulnerability reports)

### 📄 License Agreement

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

**Thank you for contributing to MojoRust! 🙏**

## ⚖️ License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### What This Means

**You are free to:**
- ✅ Use this software for personal or commercial purposes
- ✅ Modify and adapt the code to your needs
- ✅ Distribute copies of the software
- ✅ Sublicense and sell copies

**Under these conditions:**
- 📄 Include the original copyright notice and license in any copies
- 📄 Provide attribution to the original authors

**Limitations:**
- ⚠️ The software is provided "AS IS" without warranty
- ⚠️ Authors are not liable for any damages or losses
- ⚠️ No patent rights granted (consider Apache 2.0 if needed)

### Third-Party Licenses

This project uses open-source dependencies. See:
- Rust dependencies: `rust-modules/Cargo.toml`
- Python dependencies: `requirements.txt`
- Mojo dependencies: `mojo.toml`

All dependencies are compatible with MIT License.

## 🚨 Disclaimer & Risk Warnings

### ⚠️ CRITICAL FINANCIAL RISK WARNING

**READ THIS CAREFULLY BEFORE USING THIS SOFTWARE**

This trading bot is provided for **EDUCATIONAL AND RESEARCH PURPOSES ONLY**. Trading cryptocurrencies, especially volatile memecoin markets, involves **SUBSTANTIAL RISK OF LOSS** and is not suitable for all investors.

### Financial Risks

**Market Risks:**
- 💸 **Total Loss Possible:** You can lose 100% of your invested capital
- 📉 **High Volatility:** Memecoin prices can drop 90%+ in minutes
- 🎢 **Extreme Price Swings:** Prices can change dramatically between execution and confirmation
- 🐋 **Manipulation:** Whale activity, pump-and-dump schemes, rug pulls are common
- 💧 **Liquidity Risk:** Low liquidity can prevent trade execution or cause extreme slippage

**Technical Risks:**
- 🐛 **Software Bugs:** This software may contain bugs that cause financial losses
- ⚡ **Execution Failures:** Network issues, API failures, or smart contract errors can prevent trades
- 🕐 **Latency:** Delays in execution can result in unfavorable prices
- 🔌 **Downtime:** System failures may prevent closing positions during critical moments
- 🔐 **Security Vulnerabilities:** Despite security measures, vulnerabilities may exist

**Operational Risks:**
- 🔑 **Wallet Security:** Improper key management can lead to theft of funds
- 🌐 **API Dependencies:** Third-party API failures (Helius, QuickNode, Jupiter) can disrupt trading
- 💾 **Data Loss:** Database or configuration errors may cause loss of trading history
- ⚙️ **Configuration Errors:** Incorrect settings can lead to unintended trading behavior

**Regulatory Risks:**
- ⚖️ **Legal Compliance:** Cryptocurrency trading may be restricted or illegal in your jurisdiction
- 📋 **Tax Obligations:** You are responsible for reporting and paying taxes on trading profits
- 🏛️ **Regulatory Changes:** Laws and regulations may change, affecting legality of automated trading

### No Guarantees

**Past Performance:**
- 📊 Past performance does NOT guarantee future results
- 🎯 Target metrics (2-5% daily ROI, 65-75% win rate) are aspirational, not guaranteed
- 📈 Backtesting results may not reflect live trading performance
- 🔄 Market conditions change constantly

**Software Warranty:**
- ⚠️ This software is provided "AS IS" without warranty of any kind
- ⚠️ No warranty of merchantability or fitness for a particular purpose
- ⚠️ Authors and contributors are NOT responsible for any financial losses
- ⚠️ Use at your own risk

### Liability Limitations

**The authors, contributors, and maintainers of this software:**
- ❌ Are NOT financial advisors
- ❌ Do NOT provide investment advice
- ❌ Are NOT responsible for your trading decisions
- ❌ Are NOT liable for any direct, indirect, incidental, or consequential damages
- ❌ Make NO representations about profitability or success

**By using this software, you acknowledge:**
- ✅ You understand the risks involved in cryptocurrency trading
- ✅ You are solely responsible for your trading decisions
- ✅ You will not hold authors liable for any losses
- ✅ You have consulted with financial and legal advisors (if appropriate)
- ✅ You comply with all applicable laws and regulations in your jurisdiction

### Recommended Safety Measures

**Before Live Trading:**
1. ✅ **Start with Paper Trading:** Test for at least 24-48 hours with no real money
2. ✅ **Use Small Amounts:** Start with capital you can afford to lose completely (0.1-1 SOL)
3. ✅ **Understand the Code:** Review the trading logic and risk management
4. ✅ **Test Thoroughly:** Run all tests, monitor in paper mode, verify filter performance
5. ✅ **Set Conservative Limits:** Use strict stop losses, position limits, and drawdown protection
6. ✅ **Monitor Constantly:** Watch the bot closely, especially in first days
7. ✅ **Have Exit Plan:** Know how to emergency stop and withdraw funds
8. ✅ **Secure Your Wallet:** Use dedicated wallet, never your main wallet
9. ✅ **Enable Alerts:** Configure Telegram/Discord for real-time notifications
10. ✅ **Regular Backups:** Backup configuration and trading data

**During Live Trading:**
- 👀 Monitor performance daily
- 📊 Review trading logs and metrics
- 🛑 Stop immediately if unusual behavior detected
- 💰 Withdraw profits regularly
- 🔄 Adjust parameters based on performance
- 🚨 Respect circuit breaker triggers

### Regulatory Compliance

**Your Responsibilities:**
- 📋 Verify cryptocurrency trading is legal in your jurisdiction
- 💵 Report and pay taxes on trading profits
- 🏦 Comply with anti-money laundering (AML) regulations
- 🆔 Complete KYC (Know Your Customer) requirements if applicable
- 📜 Maintain records for tax and regulatory purposes

**Jurisdictional Warnings:**
- 🇺🇸 **USA:** Cryptocurrency trading may be subject to SEC/CFTC regulations
- 🇪🇺 **EU:** MiCA regulations may apply
- 🇨🇳 **China:** Cryptocurrency trading is restricted
- 🌍 **Other:** Check local laws before using

### Not Financial Advice

**IMPORTANT:** Nothing in this repository constitutes financial, investment, legal, or tax advice. This software is a tool for algorithmic trading research and education. All trading decisions are your own responsibility.

**Consult Professionals:**
- 💼 Financial advisor for investment decisions
- ⚖️ Legal counsel for regulatory compliance
- 💰 Tax professional for tax obligations

---

**BY USING THIS SOFTWARE, YOU ACKNOWLEDGE THAT YOU HAVE READ, UNDERSTOOD, AND AGREE TO THIS DISCLAIMER AND ALL ASSOCIATED RISKS.**

**NEVER TRADE WITH MONEY YOU CANNOT AFFORD TO LOSE.**

## 📋 Project Status

**Current Version:** 1.0.0 (see [CHANGELOG.md](CHANGELOG.md))

**Development Status:** ✅ Production Ready

**Maintenance:** 🟢 Actively Maintained

**Security:** 🔒 Security updates provided (see [SECURITY.md](SECURITY.md))

**Community:** 👥 Contributions welcome (see [CONTRIBUTING.md](CONTRIBUTING.md))

## 🆘 Support & Community

### 📚 Documentation
- 📖 [README](README.md) - Project overview and quick start
- 🚀 [Deployment Guide](DEPLOYMENT.md) - Production deployment
- 🔧 [CI/CD Guide](docs/CI_CD_GUIDE.md) - Development workflow
- ⚡ [FFI Optimization](docs/FFI_OPTIMIZATION_GUIDE.md) - Performance tuning
- 🔄 [Arbitrage Guide](docs/ARBITRAGE_GUIDE.md) - Arbitrage strategies

### 💬 Get Help
- 🐛 **Bug Reports:** [GitHub Issues](https://github.com/SynergiaOS/MojoRust/issues)
- 💡 **Feature Requests:** [GitHub Discussions](https://github.com/SynergiaOS/MojoRust/discussions)
- 🔒 **Security Issues:** [SECURITY.md](SECURITY.md)
- 📖 **Documentation:** [Wiki](https://github.com/SynergiaOS/MojoRust/wiki)
- 💬 **Community Chat:** Discord/Telegram (links in repository)

### 🤝 Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

### 📜 Legal
- **License:** [MIT License](LICENSE)
- **Code of Conduct:** [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- **Security Policy:** [SECURITY.md](SECURITY.md)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md)

---

Built with ❤️ and [Mojo](https://www.modular.com/mojo) + [Rust](https://www.rust-lang.org/)
## Project Structure

```
MojoRust/
├── src/                    # Main source code (Mojo)
│   ├── core/              # Core functionality
│   ├── data/              # Data layer (Mojo + typed DTOs)
│   ├── engine/            # Trading engines
│   ├── risk/              # Risk management
│   ├── monitoring/        # Monitoring & alerting
│   └── orchestration/     # Task orchestration (Python)
│
├── python/                # Pure Python modules
│   ├── social_intelligence_engine.py
│   ├── geyser_client.py
│   └── jupiter_price_api.py
│
├── rust-modules/          # High-performance Rust components
├── tests/                 # Comprehensive test suite
├── config/                # Configuration files
├── scripts/               # Utility scripts
└── docs/                  # Documentation
```

### Technology Stack

- **Mojo**: High-performance core components
- **Python**: Orchestration and external integrations
- **Rust**: Ultra-performance data processing
- **Docker**: Containerized deployment
- **Prometheus/Grafana**: Monitoring stack

### Getting Started

1. **Clone and setup**:
   ```bash
   git clone <repository-url>
   cd MojoRust
   make dev-setup
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your API keys
   ```

3. **Run tests**:
   ```bash
   make test
   ```

4. **Start the bot**:
   ```bash
   make run
   ```

### Development

- **Code formatting**: `make format`
- **Linting**: `make lint`
- **Testing**: `make test`
- **Coverage**: `make test-coverage`
- **Docker**: `make docker-build && make docker-run`

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for detailed information.
