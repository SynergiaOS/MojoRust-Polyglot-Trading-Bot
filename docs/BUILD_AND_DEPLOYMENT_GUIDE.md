# 🚀 MojoRust Trading Bot - Build and Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Environment Configuration](#environment-configuration)
4. [Building the Application](#building-the-application)
5. [Docker Deployment](#docker-deployment)
6. [Manual Deployment](#manual-deployment)
7. [Monitoring Setup](#monitoring-setup)
8. [Verification and Testing](#verification-and-testing)
9. [Troubleshooting](#troubleshooting)
10. [Security Considerations](#security-considerations)

## Overview

This guide covers the complete build and deployment process for the MojoRust Trading Bot, including:

- **Mojo components**: High-performance trading logic
- **Rust modules**: Secure execution environment
- **Docker containerization**: Multi-stage builds
- **Monitoring stack**: Prometheus, Grafana, AlertManager
- **Database integration**: TimescaleDB, DragonflyDB Cloud

## Prerequisites

### System Requirements

- **OS**: Linux (Ubuntu 20.04+), macOS (12+), or Windows 10+ with WSL2
- **RAM**: Minimum 4GB, Recommended 8GB+
- **Storage**: Minimum 20GB free space
- **Network**: Stable internet connection for API access

### Required Tools

#### Core Development Tools
```bash
# Install Rust 1.70+
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env

# Install Mojo 24.4+
# Follow instructions at https://docs.modular.com/mojo/get-started

# Install Docker & Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
# Install Docker Compose following official docs
```

#### Additional Dependencies
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y build-essential pkg-config libssl-dev

# macOS
xcode-select --install
brew install openssl

# Verify installations
rustc --version
cargo --version
mojo --version
docker --version
docker-compose --version
```

### API Keys and Services

You'll need accounts and API keys from:

1. **Helius** (Solana data): https://helius.dev
2. **QuickNode** (Solana RPC): https://www.quicknode.com
3. **DragonflyDB Cloud** (Redis cache): https://dragonflydb.cloud
4. **Infisical** (Secrets management): https://infisical.com

## Environment Configuration

### 1. Environment Files Setup

Copy the example environment files:

```bash
# Production environment
cp .env.production.example .env

# Docker-specific configuration
cp .env.docker.example .env.docker

# Set secure permissions
chmod 600 .env .env.docker
```

### 2. Configure Main Environment (.env)

Edit `.env` with your actual values:

```bash
nano .env
```

**Critical Configuration:**
```bash
# Environment
TRADING_ENV=production
EXECUTION_MODE=paper  # Start with paper trading!

# API Keys (replace with real values)
HELIUS_API_KEY=your_actual_helius_api_key
QUICKNODE_RPC_URL=https://your-quicknode-endpoint.solana-mainnet.quiknode.pro

# DragonflyDB Cloud
REDIS_URL=rediss://default:gv7g6u9svsf1@612ehcb9i.dragonflydb.cloud:6385

# Wallet (replace with your actual wallet)
WALLET_ADDRESS=5KQpwrWb2HsLzYwJeG3vh8Bxn1wkNJg3yBKjvLF3uqUu
SOLANA_KEYPAIR_FILE=secrets/keypair.json

# Trading Parameters (conservative defaults)
INITIAL_CAPITAL=1.0
MAX_POSITION_SIZE=0.10
EXECUTION_MODE=paper
```

### 3. Configure Docker Environment (.env.docker)

Edit `.env.docker` with Docker-specific settings:

```bash
nano .env.docker
```

**Database Configuration:**
```bash
# TimescaleDB
TIMESCALEDB_PASSWORD=your_secure_password_32_chars_min

# Grafana
GRAFANA_ADMIN_PASSWORD=your_grafana_password_32_chars_min

# Build Target
BUILD_TARGET=runtime  # development, runtime, test
```

### 4. Create Secrets Directory

```bash
mkdir -p secrets
chmod 700 secrets

# Place your Solana keypair here
cp /path/to/your/keypair.json secrets/keypair.json
chmod 600 secrets/keypair.json
```

## Building the Application

### Option 1: Automated Build Script

Use the comprehensive build script for automated building:

```bash
# Full production build and deploy
./scripts/build_and_deploy.sh

# Build only (no deployment)
./scripts/build_and_deploy.sh --skip-deploy

# Debug build
./scripts/build_and_deploy.sh --debug

# Clean build
./scripts/build_and_deploy.sh --clean
```

### Option 2: Manual Step-by-Step Build

#### Step 1: Build Rust Modules

```bash
./scripts/build_rust_modules.sh

# Options
./scripts/build_rust_modules.sh --help
./scripts/build_rust_modules.sh --debug    # Debug build
./scripts/build_rust_modules.sh --clean    # Clean artifacts
./scripts/build_rust_modules.sh --verbose  # Verbose output
```

#### Step 2: Build Mojo Binary

```bash
./scripts/build_mojo_binary.sh

# Options
./scripts/build_mojo_binary.sh --help
./scripts/build_mojo_binary.sh --debug    # Debug build
./scripts/build_mojo_binary.sh --clean    # Clean artifacts
```

#### Step 3: Verify Build Output

```bash
# Check Rust modules
ls -la rust-modules/target/release/deps/*.so

# Check Mojo binary
ls -la target/release/trading-bot
file target/release/trading-bot
```

## Docker Deployment

### Option 1: Docker Compose (Recommended)

#### Prerequisites Setup

```bash
# Verify configuration
docker-compose config

# Check port availability
./scripts/verify_port_availability.sh --port 8082 --port 9090 --port 3001
```

#### Deploy Services

```bash
# Deploy all services
docker-compose up -d

# Deploy specific services
docker-compose up -d timescaledb prometheus grafana trading-bot

# Check deployment status
docker-compose ps
```

#### Health Verification

```bash
# Wait for services to start (30-60 seconds)
sleep 60

# Check service health
docker-compose ps

# Test individual services
curl http://localhost:8082/health  # Trading bot
curl http://localhost:9090/-/healthy  # Prometheus
curl http://localhost:3001/api/health  # Grafana
```

### Option 2: Manual Docker Build

#### Build Docker Image

```bash
# Production image
docker build --target runtime -t mojorust/trading-bot:latest .

# Development image
docker build --target development -t mojorust/trading-bot:dev .

# Test image
docker build --target test -t mojorust/trading-bot:test .
```

#### Run Container

```bash
# Create Docker network
docker network create trading-network

# Run with environment file
docker run -d \
  --name trading-bot \
  --network trading-network \
  --env-file .env \
  --env-file .env.docker \
  -p 8082:8082 \
  -p 9091:9091 \
  -v $(pwd)/secrets:/app/secrets:ro \
  -v $(pwd)/logs:/app/logs \
  mojorust/trading-bot:latest
```

## Manual Deployment

### Prerequisites

- Linux server with Docker and Docker Compose installed
- Proper firewall configuration
- SSL certificates for production (recommended)

### Deployment Steps

#### 1. Server Setup

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Create application directory
sudo mkdir -p /opt/mojorust
sudo chown $USER:$USER /opt/mojorust
cd /opt/mojorust
```

#### 2. Clone and Configure

```bash
# Clone repository
git clone <your-repo-url> .
cd mojorust

# Configure environment
cp .env.production.example .env
cp .env.docker.example .env.docker
chmod 600 .env .env.docker

# Edit configuration files
nano .env
nano .env.docker

# Create secrets directory
mkdir -p secrets
chmod 700 secrets
```

#### 3. Deploy Services

```bash
# Build and deploy
./scripts/build_and_deploy.sh

# Or manually
docker-compose up -d

# Enable auto-start
sudo systemctl enable docker
```

## Monitoring Setup

### Start Monitoring Stack

```bash
# Using Makefile (recommended)
make monitoring-start

# Or manually
docker-compose up -d prometheus grafana alertmanager node-exporter
```

### Access Dashboards

- **Grafana**: http://localhost:3001 (admin/trading_admin)
- **Prometheus**: http://localhost:9090
- **AlertManager**: http://localhost:9093

### Import Dashboards

```bash
# Import pre-configured dashboards
./scripts/import_grafana_dashboards.sh --force

# Or manually via Grafana UI
# Navigate to Dashboards → Import → Upload JSON file
```

### Configure Alerts

```bash
# Test alert delivery
make monitoring-test-alerts

# Or manually
curl -XPOST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{"labels":{"alertname":"TestAlert","severity":"warning"}}]'
```

## Verification and Testing

### Health Checks

```bash
# Comprehensive health check
make monitoring-full-check

# Individual service checks
curl http://localhost:8082/health  # Trading bot API
curl http://localhost:8082/metrics  # Metrics endpoint
docker-compose ps                  # Service status
```

### Log Monitoring

```bash
# View logs for all services
docker-compose logs -f

# View specific service logs
docker-compose logs -f trading-bot
docker-compose logs -f prometheus
docker-compose logs -f grafana

# View application logs
tail -f logs/trading-bot.log
```

### Performance Verification

```bash
# Check resource usage
docker stats

# Check system metrics
curl http://localhost:9100/metrics  # Node exporter

# Check application metrics
curl http://localhost:9091/metrics  # Trading bot metrics
```

### Integration Testing

```bash
# Test API endpoints
curl http://localhost:8082/api/status
curl http://localhost:8082/api/positions
curl http://localhost:8082/api/performance

# Test database connectivity
docker-compose exec trading-bot python -c "
import psycopg2
import redis
print('Database connections successful')
"
```

## Troubleshooting

### Common Issues

#### Build Failures

```bash
# Rust build issues
cd rust-modules
cargo clean
cargo build --release

# Mojo build issues
cd src
mojo build main.mojo -o ../target/release/trading-bot

# Docker build issues
docker system prune -f
docker build --no-cache --target runtime -t mojorust/trading-bot .
```

#### Runtime Issues

```bash
# Check container status
docker-compose ps
docker-compose logs trading-bot

# Restart services
docker-compose restart trading-bot

# Check resource limits
docker stats
```

#### Database Issues

```bash
# Check TimescaleDB
docker-compose exec timescaledb psql -U trading_user -d trading_db -c "SELECT version();"

# Check DragonflyDB connection
docker-compose exec trading-bot python -c "
import redis
r = redis.from_url(os.environ['REDIS_URL'])
print(r.ping())
"
```

#### Monitoring Issues

```bash
# Check Prometheus configuration
docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Reload Prometheus configuration
curl -X POST http://localhost:9090/-/reload

# Check Grafana health
curl http://localhost:3001/api/health
```

### Debug Mode

Enable debug logging for troubleshooting:

```bash
# Set debug mode in .env
LOG_LEVEL=DEBUG
VERBOSE_LOGGING=true

# Or override with Docker
docker-compose up -d -e LOG_LEVEL=DEBUG trading-bot
```

### Reset Environment

```bash
# Stop all services
docker-compose down

# Remove volumes (WARNING: This deletes all data)
docker-compose down -v

# Clean build artifacts
./scripts/build_and_deploy.sh --clean

# Rebuild and deploy
./scripts/build_and_deploy.sh
```

## Security Considerations

### Environment Security

```bash
# Secure environment files
chmod 600 .env .env.docker
chown $USER:$USER .env .env.docker

# Secure secrets directory
chmod 700 secrets
chown $USER:$USER secrets

# Add to .gitignore
echo "secrets/" >> .gitignore
echo ".env" >> .gitignore
echo ".env.docker" >> .gitignore
```

### Network Security

```bash
# Firewall configuration
sudo ufw allow 22/tcp      # SSH
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw allow 8082/tcp    # Trading bot API (restrict to trusted IPs)
sudo ufw enable
```

### Docker Security

```bash
# Use non-root containers
docker-compose exec trading-bot whoami

# Scan images for vulnerabilities
docker scan mojorust/trading-bot:latest

# Regular updates
docker-compose pull
docker-compose up -d
```

### API Security

- **Rate Limiting**: Configure appropriate rate limits
- **Authentication**: Use JWT tokens for API access
- **HTTPS**: Enable SSL/TLS in production
- **Network Policies**: Restrict access to sensitive ports

### Backup and Recovery

```bash
# Automated backups
./scripts/backup.sh

# Manual backup
docker-compose exec timescaledb pg_dump -U trading_user trading_db > backup.sql

# Restore backup
docker-compose exec -T timescaledb psql -U trading_user trading_db < backup.sql
```

## Production Deployment Checklist

### Pre-Deployment

- [ ] Environment files configured with production values
- [ ] API keys and secrets secured and not in version control
- [ ] DragonflyDB Cloud connection tested
- [ ] SSL certificates installed
- [ ] Firewall rules configured
- [ ] Monitoring stack deployed and tested
- [ ] Backup strategy implemented

### Post-Deployment

- [ ] All services running and healthy
- [ ] Monitoring dashboards accessible
- [ ] Alert notifications configured
- [ ] Log aggregation working
- [ ] Performance benchmarks met
- [ ] Security scan passed
- [ ] Documentation updated

### Ongoing Maintenance

- [ ] Regular security updates
- [ ] Log monitoring and review
- [ ] Performance optimization
- [ ] Backup verification
- [ ] Credential rotation
- [ ] Documentation maintenance

## Support and Resources

- **Documentation**: [docs/](../docs/)
- **Scripts**: [scripts/](../scripts/)
- **Configuration**: [config/](../config/)
- **Issues**: [GitHub Issues](https://github.com/your-repo/issues)
- **Community**: [Discord/Slack Channel]

## Version Information

- **Guide Version**: 1.0.0
- **Last Updated**: 2024-01-XX
- **Compatible Versions**: Mojo 24.4+, Rust 1.70+, Docker 20.10+

---

**⚠️ Important**: Always start with paper trading mode and thorough testing before deploying with real funds. Monitor the system closely during the first 24-48 hours of deployment.