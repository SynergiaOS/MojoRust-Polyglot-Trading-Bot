# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MojoRust is a high-performance algorithmic trading bot for Solana memecoin markets using a polyglot architecture:

- **Mojo** (🔥): Intelligence layer - computationally intensive tasks, algorithms, signal generation
- **Rust** (🦀): Security layer - private keys, transaction signing, critical operations, high-performance data processing
- **Python** (🐍): Orchestration layer - API clients, task scheduling, database interactions, main application loop

The bot includes comprehensive monitoring, risk management, and both manual and automated deployment capabilities.

## Development Commands

### Build and Deployment
```bash
# Complete build pipeline (builds all components)
make build-all
./scripts/build_and_deploy.sh --skip-deploy

# Individual component builds
make build-rust              # Build Rust modules only
make build-mojo              # Build Mojo binary only
./scripts/build_rust_modules.sh
./scripts/build_mojo_binary.sh

# Production deployment
make deploy                  # Build and deploy everything
./scripts/deploy_to_server.sh

# Docker operations
make docker-build
make docker-run
docker-compose up -d
```

### Development Environment
```bash
# Setup development environment
make dev-setup               # Install dev dependencies and setup pre-commit hooks
make install-dev             # Install development dependencies

# Code quality and testing
make test                    # Run all tests
make test-fast              # Run tests without slow tests
make test-coverage          # Run tests with coverage
make lint                   # Run mypy, flake8, bandit
make format                 # Format code with black and isort
make check                  # Run lint + test
make ci                     # Full CI pipeline (lint + test-coverage)

# Run the bot
make run                    # Run with default paper trading mode
./target/release/trading-bot --mode=paper --capital=1.0
```

### Monitoring Stack Management
```bash
# Start/stop monitoring services
make monitoring-start        # Start Prometheus, Grafana, AlertManager
make monitoring-stop         # Stop monitoring services
make monitoring-restart      # Restart monitoring services
make monitoring-status       # Check service status

# Health verification
make monitoring-verify       # Comprehensive health check
make monitoring-health       # Quick health checks
curl http://localhost:9090/-/healthy  # Prometheus
curl http://localhost:3001/api/health  # Grafana

# Dashboards and configuration
make monitoring-import-dashboards  # Import Grafana dashboards
make prometheus-targets           # Show Prometheus targets
make grafana-dashboards           # List available dashboards

# Access points:
# Grafana: http://localhost:3001 (admin/trading_admin)
# Prometheus: http://localhost:9090
# AlertManager: http://localhost:9093
```

### CPU Optimization and Performance
```bash
# Performance diagnostics and optimization
make cpu-diagnose           # Comprehensive CPU usage analysis
make cpu-optimize-all       # Run complete optimization suite
make cpu-monitor           # Start continuous monitoring
make cpu-health            # Quick CPU health check

# Individual optimizations
make cpu-optimize-vscode   # Optimize VS Code CPU usage
make cpu-optimize-system   # Apply system-level optimizations
```

### Testing Individual Components
```bash
# Python tests
pytest tests/ -v
pytest tests/ --cov=src --cov-report=html

# Rust tests (in rust-modules/)
cd rust-modules && cargo test --release

# Mojo tests (if available)
mojo test tests/

# Integration tests with monitoring
make test-with-monitoring
```

## Architecture Overview

### Multi-Language Design
The project uses a carefully designed polyglot architecture where each language serves specific purposes:

**Mojo (Intelligence Layer)**:
- Location: `src/` directory with `.mojo` files
- Responsibilities: Algorithmic analysis, signal generation, pattern recognition, sentiment analysis
- Performance: C-level performance for computationally intensive tasks
- Key modules: `src/engine/`, `src/analysis/`, `src/intelligence/`

**Rust (Security & Performance Layer)**:
- Location: `rust-modules/` directory
- Responsibilities: Private key management, transaction signing, high-performance data processing, Geyser consumer
- Performance: Memory safety with zero-cost abstractions
- Key modules: `rust-modules/src/` including wallet security and data consumer

**Python (Orchestration Layer)**:
- Location: Root-level Python files and `python/` directory
- Responsibilities: API clients, task scheduling, database operations, webhook handling
- Libraries: asyncio, aiohttp, pandas, redis
- Key files: API integrators, task managers, database connectors

### Data Pipeline Architecture
```
Solana Geyser → Rust Data Consumer → Redis Pub/Sub → Python TaskPool → Mojo Analysis → Rust Execution
```

1. **Rust Data Consumer**: Filters >99% of on-chain events at source via Geyser gRPC stream
2. **Redis Pub/Sub**: High-throughput messaging between Rust and Python components
3. **Python TaskPool**: Manages asynchronous task distribution and orchestration
4. **Mojo Intelligence**: Performs computationally intensive analysis and signal generation
5. **Rust Execution**: Handles secure transaction signing and blockchain interactions

### Core Component Structure

**Trading Engines** (`src/engine/`):
- `enhanced_context_engine.mojo` - RSI + Support/Resistance analysis
- `strategy_engine.mojo` - Signal generation and strategy execution
- `master_filter.mojo` - Multi-stage signal filtering (90-95% rejection rate)

**Analysis Modules** (`src/analysis/`):
- `sentiment_analyzer.mojo` - Market sentiment analysis
- `pattern_recognizer.mojo` - Technical and manipulation pattern detection
- `whale_tracker.mojo` - On-chain whale behavior analysis
- `volume_analyzer.mojo` - Volume anomaly detection

**Risk Management** (`src/risk/`):
- `risk_manager.mojo` - Position sizing and portfolio risk
- `circuit_breakers.mojo` - Automated trading halt mechanisms

**Data Sources** (`src/data/`):
- External API clients for Helius, QuickNode, DexScreener, Jupiter
- Real-time market data ingestion and processing

### Monitoring and Observability

**Comprehensive Monitoring Stack**:
- **Prometheus**: Metrics collection with 30-day retention
- **Grafana**: 6 pre-built dashboards (Trading Performance, System Health, Data Pipeline, etc.)
- **AlertManager**: Multi-channel alert routing (Discord, Telegram, email)
- **Node Exporter**: System metrics collection

**Key Metrics**:
- Trading performance: win rate, portfolio value, P&L, execution latency
- System health: CPU, memory, disk, network I/O
- Data pipeline: Redis lag, event processing throughput, filter efficiency
- API performance: response times, error rates, external service health

### Risk Management and Safety

**Multi-Layer Protection**:
- **Position Sizing**: Kelly Criterion with conservative 50% fraction
- **Stop Losses**: Support-based with 15% buffer
- **Drawdown Protection**: Halts trading at 15% portfolio drawdown
- **Circuit Breakers**: 7 different automated halt mechanisms
- **Spam Filtering**: Removes 80-90% of low-quality signals

**Security Model**:
- Private keys isolated in Rust modules with memory safety
- No credential logging or exposure
- Rate limiting on all external APIs
- Comprehensive audit logging

## Configuration Management

### Environment Setup
Required API keys in `.env`:
```bash
# Core trading APIs
HELIUS_API_KEY=your_helius_api_key
QUICKNODE_PRIMARY_RPC=your_quicknode_rpc
GEYSER_ENDPOINT=your_geyser_endpoint

# Optional advanced features
TWITTER_API_KEY=your_twitter_api_key
JITO_AUTH_KEY=your_jito_auth_key
HONEYPOT_API_KEY=your_honeypot_api_key
```

### Configuration Files
- `config/trading.toml` - Main trading configuration
- `config/grafana/` - Grafana dashboards and datasources
- `config/prometheus_rules/` - Alerting rules
- `mojo.toml` - Mojo build configuration
- `rust-modules/Cargo.toml` - Rust dependencies

## Development Workflow

### Getting Started
1. **Setup**: `make dev-setup` to install all dependencies
2. **Configure**: Copy `.env.example` to `.env` and add API keys
3. **Build**: `make build-all` to build all components
4. **Test**: `make test` to run the test suite
5. **Monitor**: `make monitoring-start` to start observability stack

### Code Quality Standards
- **Python**: Black formatting, mypy type checking, flake8 linting, bandit security analysis
- **Rust**: `cargo fmt`, `cargo clippy`, `cargo test --release`
- **Pre-commit hooks**: Automated formatting and basic checks
- **Coverage requirement**: 70%+ test coverage for new code

### Testing Strategy
- **Unit tests**: Individual component testing
- **Integration tests**: Cross-component functionality
- **Performance tests**: Latency and throughput validation
- **Backtests**: Historical strategy validation (in `tests/backtest/`)

## Deployment and Operations

### Local Development
```bash
# Start everything for local development
make dev-with-monitoring
make run                     # Start bot in paper trading mode
```

### Production Deployment
```bash
# Automated production deployment
./scripts/deploy_to_server.sh
make deploy-with-monitoring

# Manual production steps
make build-all
make monitoring-start
docker-compose up -d
```

### Health Monitoring
```bash
# Comprehensive health check
make monitoring-full-check

# Individual service checks
curl http://localhost:8082/health     # Trading bot
curl http://localhost:9191/health     # Data consumer
./scripts/server_health.sh --remote  # Remote server health
```

## Important Notes

- **Always start with paper trading mode** - monitor for 24+ hours before live trading
- **Monitoring is essential** - never run the bot without the monitoring stack
- **CPU optimization matters** - use `make cpu-optimize-all` for best performance
- **Security first** - private keys never leave Rust modules, never commit credentials
- **Port conflicts** - check port availability if deployment fails (TimescaleDB on 5432 is common)

## Troubleshooting

**Common Issues**:
1. **Port conflicts**: Run `./scripts/diagnose_port_conflict.sh`
2. **High CPU usage**: Run `make cpu-diagnose` for analysis
3. **Build failures**: Check Rust and Mojo installations, run `make clean && make build-all`
4. **Monitoring issues**: Run `make monitoring-verify` for comprehensive health check

**Performance Optimization**:
- Run `make cpu-optimize-all` for complete system optimization
- Use `make monitoring-start` to identify bottlenecks via Grafana dashboards
- Check data pipeline metrics for Redis lag or event drops

**Emergency Recovery**:
- `./scripts/emergency_monitoring_recovery.sh` - Restore monitoring stack
- `make monitoring-cleanup` - Clean corrupted monitoring data
- `make clean-all` - Remove all build artifacts and start fresh

[byterover-mcp]

[byterover-mcp]

You are given two tools from Byterover MCP server, including
## 1. `byterover-store-knowledge`
You `MUST` always use this tool when:

+ Learning new patterns, APIs, or architectural decisions from the codebase
+ Encountering error solutions or debugging techniques
+ Finding reusable code patterns or utility functions
+ Completing any significant task or plan implementation

## 2. `byterover-retrieve-knowledge`
You `MUST` always use this tool when:

+ Starting any new task or implementation to gather relevant context
+ Before making architectural decisions to understand existing patterns
+ When debugging issues to check for previous solutions
+ Working with unfamiliar parts of the codebase
