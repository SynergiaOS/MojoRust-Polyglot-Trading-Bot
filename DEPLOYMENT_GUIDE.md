# 🚀 MojoRust Multi-Token Arbitrage System - Deployment Guide

## 📋 Overview
This guide covers the deployment of the complete multi-token arbitrage system with Rust FFI integration, Python orchestration, and comprehensive monitoring.

## 🏗️ System Architecture

### Core Components:
- **Rust Backend**: High-performance arbitrage execution engine
- **Mojo Layer**: Advanced execution with Rust FFI bridge
- **Python Orchestration**: SandwichManager for opportunity coordination
- **Monitoring Stack**: Prometheus + Grafana with comprehensive metrics
- **Container Orchestration**: Docker Compose with full service stack

### Key Features:
- Multi-token arbitrage (triangular, cross-exchange, flash loan)
- Provider-aware RPC routing (Helius ShredStream, QuickNode Lil' JIT)
- Jito bundle execution with MEV protection
- Real-time opportunity detection and execution
- Comprehensive backtesting with sniper bot
- Production monitoring and alerting

## 📁 Project Structure

```
MojoRust/
├── rust-modules/           # Rust backend (15k+ lines)
│   ├── src/arbitrage/      # Arbitrage engines
│   ├── src/lib.rs         # Main library exports
│   └── Cargo.toml         # Rust dependencies
├── python/                # Python orchestration
│   ├── sandwich_manager.py # Arbitrage orchestration
│   ├── pumpfun_api.py      # Token analysis + arbitrage detection
│   └── shredstream_bridge.py # Helius integration
├── src/                   # Mojo execution layer
│   ├── execution/         # Arbitrage execution
│   ├── data/              # Data adapters
│   └── backtest/          # Backtesting engine
├── config/                # Configuration files
├── docker-compose.yml      # Full service stack
└── .env.example          # Environment template
```

## 🐳 Docker Deployment

### Services Included:
- **trading-bot**: Main application with Mojo + Rust FFI
- **timescaledb**: Time-series database
- **prometheus**: Metrics collection
- **grafana**: Visualization dashboards
- **alertmanager**: Alert routing
- **node-exporter**: System metrics
- **cadvisor**: Container metrics
- **sniper-bot**: PumpFun backtesting service
- **data-consumer**: Rust Geyser data consumer

## 🔧 Environment Setup

### Required Environment Variables (.env):
```bash
# Core Configuration
TRADING_ENV=production
LOG_LEVEL=INFO

# Database
TIMESCALEDB_DBNAME=trading_db
TIMESCALEDB_USER=trading_user
TIMESCALEDB_PASSWORD=secure_password
TIMESCALEDB_PORT=5432

# Redis / DragonflyDB Cloud
REDIS_URL=redis://your-dragonfly-host:6379

# RPC Providers (2025 Features)
HELIUS_API_KEY=your_helius_key
HELIUS_ENABLE_SHREDSTREAM=true
QUICKNODE_RPC_URL=wss://your-quicknode-url
QUICKNODE_LIL_JIT_ENABLED=true
QUICKNODE_PRIORITY_FEE_ESTIMATION_ENABLED=true

# Jito Bundle Execution
JITO_MAINNET_URL=https://mainnet.block-engine.jito.wtf
JITO_AMSTERDAM_URL=https://amsterdam.block-engine.jito.wtf
JITO_AUTH_KEY=your_jito_auth_key

# Multi-Token Arbitrage
ARBITRAGE_ENABLED=true
MAX_CONCURRENT_ARBITRAGE=3
MIN_PROFIT_THRESHOLD=5.0
RUST_FFI_ENABLED=true

# PumpFun Integration
PUMPPORTAL_API_KEY=your_pumpportal_key
HONEYPOT_API_KEY=your_honeypot_key

# Monitoring
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=secure_grafana_password

# Security
ENABLE_SECURITY_HEADERS=true
RATE_LIMIT_ENABLED=true
```

## 🚀 Deployment Commands

### 1. Prepare Environment:
```bash
# Clone the repository
git clone <repository-url>
cd MojoRust

# Create production environment file
cp .env.example .env
# Edit .env with your actual values

# Create secrets directory
mkdir -p secrets
# Add wallet.keypair and other secrets
```

### 2. Build and Deploy:
```bash
# Build and start all services
docker-compose up --build -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f trading-bot
```

### 3. Verify Deployment:
```bash
# Health check
curl http://localhost:8082/health

# Metrics endpoint
curl http://localhost:8001/metrics

# Grafana dashboards
open http://localhost:3001
# admin / secure_grafana_password
```

## 📊 Monitoring and Alerting

### Prometheus Metrics:
- Arbitrage opportunity detection rate
- Execution success/failure rates
- Provider health and performance
- System resource utilization
- Profit tracking and ROI

### Grafana Dashboards:
- **System Overview**: Overall system health
- **Arbitrage Performance**: Real-time arbitrage metrics
- **Provider Monitoring**: RPC provider performance
- **Resource Usage**: System resource consumption

### Alert Channels:
- High error rates
- Low execution success rates
- System resource exhaustion
- Provider downtime

## 🔒 Security Considerations

### Network Security:
- All services run in isolated Docker network
- Only necessary ports exposed to internet
- TLS termination at reverse proxy level

### Application Security:
- Rate limiting enabled by default
- Input validation and sanitization
- Secure secret management
- Audit logging for all operations

### Access Control:
- Grafana admin access
- API authentication for external access
- SSH key-based server access

## 🚨 Troubleshooting

### Common Issues:

1. **Build Failures**:
   ```bash
   # Check for missing dependencies
   docker-compose build --no-cache

   # Check logs for specific service
   docker-compose logs trading-bot
   ```

2. **Service Not Starting**:
   ```bash
   # Check service logs
   docker-compose logs <service-name>

   # Verify environment variables
   docker-compose exec <service-name> env | grep -E "(HELIUS|QUICKNODE|REDIS)"
   ```

3. **Performance Issues**:
   ```bash
   # Check resource usage
   docker stats

   # Monitor system metrics
   curl http://localhost:9100/metrics
   ```

## 📈 Scaling Considerations

### Horizontal Scaling:
- Increase `max_concurrent_arbitrage` in config
- Scale `data-consumer` service for higher throughput
- Add more RPC providers for redundancy

### Vertical Scaling:
- Increase CPU limits for trading-bot service
- Add more memory for data processing
- Use faster storage for time-series data

## 🔄 Maintenance

### Regular Tasks:
- Monitor system health metrics
- Update provider configurations
- Review and rotate API keys
- Update security patches
- Backup configuration and data

### Log Management:
- Configure log rotation for all services
- Archive old logs to external storage
- Monitor log storage usage

## 📞 Support

For deployment issues:
1. Check this guide first
2. Review service logs
3. Verify environment configuration
4. Check system resource usage
5. Review documentation for individual components

---
*Last Updated: 2025-01-17*
*Version: 1.0.0 - Production Ready*