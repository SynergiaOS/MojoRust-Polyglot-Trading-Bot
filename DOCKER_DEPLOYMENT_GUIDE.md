# Docker Compose Deployment Guide
## MojoRust Trading Bot - Production Deployment to 38.242.239.150

---

## Prerequisites

**Completed Steps:**
- ✅ Phase 1: Pre-deployment environment setup (Infisical, API keys, wallet, .env configuration)
- ✅ Phase 2: VPS infrastructure setup (Mojo, Rust, Docker, firewall, user accounts)
- ✅ Server: 38.242.239.150 is accessible via SSH

**Required Files:**
- `.env` - Application configuration (API keys, trading parameters)
- `.env.docker` - Docker infrastructure configuration (database passwords)
- `docker-compose.yml` - Service orchestration (fixed port conflicts)
- `secrets/keypair.json` - Solana wallet keypair

---

## Step 1: Transfer Deployment Package

**Option A: Using deploy_to_server.sh (Automated)**

```bash
# From local machine in project root
./scripts/deploy_to_server.sh --docker-compose --mode paper

# This will:
# - Create deployment package
# - Upload to server via SCP
# - Extract files
# - Configure environment
# - Run docker-compose up -d
# - Verify deployment
```

**Option B: Manual Transfer (Step-by-Step)**

```bash
# 1. Create deployment package locally
tar -czf mojorust-deploy.tar.gz \
    docker-compose.yml \
    Dockerfile \
    rust-modules/ \
    config/ \
    scripts/ \
    .env.production.example \
    .env.docker.example

# 2. Transfer to server
scp mojorust-deploy.tar.gz root@38.242.239.150:~/mojo-trading-bot/

# 3. Transfer environment files (separately for security)
scp .env root@38.242.239.150:~/mojo-trading-bot/
scp .env.docker root@38.242.239.150:~/mojo-trading-bot/

# 4. Transfer wallet (encrypted transfer recommended)
scp secrets/keypair.json root@38.242.239.150:~/mojo-trading-bot/secrets/

# 5. SSH to server
ssh root@38.242.239.150

# 6. Extract package
cd ~/mojo-trading-bot
tar -xzf mojorust-deploy.tar.gz
```

---

## Step 2: Configure Environment Variables

**On Server (38.242.239.150):**

```bash
cd ~/mojo-trading-bot

# 1. Verify .env file exists and has correct values
cat .env | grep -E "EXECUTION_MODE|HELIUS_API_KEY|WALLET_ADDRESS"

# Expected output:
# EXECUTION_MODE=paper
# HELIUS_API_KEY=your_actual_key
# WALLET_ADDRESS=your_actual_address

# 2. Create .env.docker if not exists
if [ ! -f .env.docker ]; then
    cp .env.docker.example .env.docker
    nano .env.docker  # Edit passwords
fi

# 3. Set secure passwords in .env.docker
# CRITICAL: Change these from defaults!
sed -i 's/change_this_secure_password_in_production/YOUR_SECURE_TIMESCALE_PASSWORD/' .env.docker
sed -i 's/change_this_dragonflydb_password_in_production/YOUR_SECURE_DRAGONFLYDB_PASSWORD/' .env.docker
sed -i 's/change_this_grafana_password/YOUR_SECURE_GRAFANA_PASSWORD/' .env.docker

# 4. Set file permissions
chmod 600 .env .env.docker
chmod 600 secrets/keypair.json

# 5. Verify configuration
./scripts/validate_config.sh
```

**Key Variables for docker-compose.yml:**

From `.env`:
- `TRADING_ENV=production`
- `EXECUTION_MODE=paper` (start with paper!)
- `HELIUS_API_KEY`, `QUICKNODE_PRIMARY_RPC`
- `WALLET_ADDRESS`, `INITIAL_CAPITAL`
- `GEYSER_ENDPOINT` (for data-consumer)
- `REDIS_URL` (DragonflyDB Cloud URL)

From `.env.docker`:
- `BUILD_TARGET=runtime`
- `TIMESCALEDB_PASSWORD`, `REDIS_PASSWORD`
- `GRAFANA_ADMIN_PASSWORD`, `PGADMIN_PASSWORD`

---

## Step 3: Build Docker Images

**Pre-Build: Compile Mojo Binary Locally**

Since Mojo requires Modular authentication, build locally first:

```bash
# On local machine (with Mojo installed)
mojo build src/main.mojo -o trading-bot

# Transfer binary to server
scp trading-bot root@38.242.239.150:~/mojo-trading-bot/
```

**On Server: Build Docker Images**

```bash
cd ~/mojo-trading-bot

# 1. Build Rust data consumer
docker-compose build data-consumer

# Expected output:
# Building data-consumer
# Step 1/10 : FROM rust:1.70 as builder
# ...
# Successfully built [image_id]
# Successfully tagged trading-bot-data-consumer:latest

# 2. Build trading bot (uses pre-built Mojo binary)
docker-compose build trading-bot

# Expected output:
# Building trading-bot
# Step 1/15 : FROM rust:1.75-slim as rust-builder
# ...
# Successfully built [image_id]
# Successfully tagged trading-bot-app:latest

# 3. Verify images
docker images | grep trading-bot

# Expected output:
# trading-bot-app              latest    [id]    [size]
# trading-bot-data-consumer    latest    [id]    [size]
```

**Troubleshooting Build Issues:**

```bash
# If Rust build fails (Solana SDK issue)
# Edit rust-modules/Dockerfile.data-consumer
# Apply fix from implementation plan (remove Solana SDK dependency)

# If trading-bot build fails (missing Mojo binary)
# Ensure trading-bot binary is in project root
ls -la trading-bot

# Rebuild with verbose output
docker-compose build --no-cache --progress=plain data-consumer
```

---

## Pre-Deployment Port Verification

**Before starting services, always verify port availability:**

```bash
cd ~/mojo-trading-bot

# Run comprehensive port verification
./scripts/verify_port_availability.sh --pre-deploy

# Expected output if all ports available:
# ✅ Pre-deployment validation PASSED
# System is ready for Docker Compose deployment
# Command: docker-compose up -d
```

**If port conflicts are detected:**

```bash
# Diagnose the specific conflict
./scripts/diagnose_port_conflict.sh

# Resolve conflicts interactively
./scripts/resolve_port_conflict.sh

# Re-verify after resolution
./scripts/verify_port_availability.sh --pre-deploy
```

**Port Verification Checklist:**
- ✅ Docker is running and accessible
- ✅ Docker Compose is installed and functional
- ✅ docker-compose.yml syntax is valid
- ✅ All required ports are available (5432, 9090, 3001, 8082, 9093, 8081, 9191, 9100, 8083)
- ✅ No conflicts with system services
- ✅ No conflicts with other Docker containers

**Alternative Quick Check:**
```bash
# Quick availability check (non-comprehensive)
./scripts/verify_port_availability.sh

# Check specific port (e.g., TimescaleDB)
./scripts/verify_port_availability.sh --port 5432
```

---

## Step 4: Start Services

**Start All Services:**

```bash
cd ~/mojo-trading-bot

# 1. Pre-deployment port verification (REQUIRED)
./scripts/verify_port_availability.sh --pre-deploy

# 2. If ports are available, start services
if [ $? -eq 0 ]; then
    echo "✅ All ports verified, starting services..."
    docker-compose up -d
else
    echo "❌ Port conflicts detected, resolve before starting services"
    echo "Run: ./scripts/resolve_port_conflict.sh"
    exit 1
fi

# Alternative: Start services in detached mode
docker-compose up -d

# Expected output:
# Creating network "trading-network" with driver "bridge"
# Creating volume "timescaledb_data" with local driver
# Creating volume "prometheus_data" with local driver
# Creating volume "grafana_data" with local driver
# Creating trading-bot-timescaledb ... done
# DragonflyDB Cloud connection - no local Redis service needed
# Creating trading-bot-prometheus  ... done
# Creating trading-bot-grafana     ... done
# Creating trading-bot-alertmanager ... done
# Creating trading-bot-data-consumer ... done
# Creating trading-bot-app         ... done
# Creating trading-bot-node-exporter ... done
# Creating trading-bot-cadvisor    ... done
# Creating trading-bot-pgadmin     ... done

# 2. Wait for services to initialize (30-60 seconds)
sleep 30

# 3. Check service status
docker-compose ps

# Expected output (all should show "Up"):
# NAME                        STATUS              PORTS
# trading-bot-timescaledb     Up (healthy)        0.0.0.0:5432->5432/tcp
# DragonflyDB Cloud          Connected (via REDIS_URL)
# trading-bot-prometheus      Up (healthy)        0.0.0.0:9090->9090/tcp
# trading-bot-grafana         Up (healthy)        0.0.0.0:3000->3000/tcp
# trading-bot-alertmanager    Up                  0.0.0.0:9093->9093/tcp
# trading-bot-data-consumer   Up                  0.0.0.0:9191->9191/tcp
# trading-bot-app             Up (healthy)        0.0.0.0:8082->8082/tcp, 0.0.0.0:9091->9090/tcp
# trading-bot-pgadmin         Up                  0.0.0.0:8081->80/tcp
# trading-bot-node-exporter   Up                  0.0.0.0:9100->9100/tcp
# trading-bot-cadvisor        Up                  0.0.0.0:8083->8080/tcp
```

**Start Specific Services:**

```bash
# Start only core services (database, cache, bot)
docker-compose up -d timescaledb trading-bot

# Start monitoring services
docker-compose up -d prometheus grafana

# Start data consumer
docker-compose up -d data-consumer
```

---

## Step 5: Verify Rust Data Consumer Build

**Check Data Consumer Status:**

```bash
# 1. Check container is running
docker-compose ps data-consumer

# Expected: Up status

# 2. Check logs
docker-compose logs data-consumer

# Expected output:
# data-consumer_1  | Starting Data Consumer service...
# data-consumer_1  | Metrics and health server listening on 0.0.0.0:9191
# data-consumer_1  | Connecting to Geyser endpoint: [endpoint]
# data-consumer_1  | Connected to DragonflyDB: [redis_url]

# 3. Test health endpoint
curl http://localhost:9191/health

# Expected: OK

# 4. Test metrics endpoint
curl http://localhost:9191/metrics

# Expected: Prometheus metrics output
# # HELP geyser_events_received Total events received from Geyser
# # TYPE geyser_events_received counter
# geyser_events_received 0
# ...

# 5. Check for errors
docker-compose logs data-consumer | grep -i error

# Expected: No errors (or only connection retries if Geyser not configured)
```

**Troubleshooting Data Consumer:**

```bash
# If container exits immediately
docker-compose logs data-consumer --tail=50

# Common issues:
# - Missing GEYSER_ENDPOINT: Set in .env
# - Missing REDIS_URL: Check .env (should be DragonflyDB Cloud)
# - Solana SDK error: Apply Dockerfile.data-consumer fix

# Rebuild if needed
docker-compose build --no-cache data-consumer
docker-compose up -d data-consumer
```

---

## Step 6: Verify Trading Bot in Paper Mode

**Check Trading Bot Status:**

```bash
# 1. Verify EXECUTION_MODE is paper
docker-compose exec trading-bot env | grep EXECUTION_MODE

# Expected: EXECUTION_MODE=paper

# 2. Check container logs
docker-compose logs trading-bot --tail=100

# Expected output:
# trading-bot_1  | Starting trading bot in paper mode...
# trading-bot_1  | Environment: production
# trading-bot_1  | Execution Mode: paper
# trading-bot_1  | Initial Capital: 1.0 SOL
# trading-bot_1  | Wallet: [your_wallet_address]
# trading-bot_1  | Aggressive filtering: ENABLED
# trading-bot_1  | Filter performance: 95.3% rejection rate
# trading-bot_1  | Trading bot started successfully

# 3. Test health endpoint
curl http://localhost:8082/health

# Expected: {"status":"healthy","mode":"paper"}

# 4. Test metrics endpoint
curl http://localhost:9091/metrics

# Expected: Prometheus metrics
# trading_bot_trades_total{mode="paper"} 0
# trading_bot_portfolio_value_sol 1.0
# ...

# 5. Check filter performance
docker-compose logs trading-bot | grep "Filter Performance"

# Expected:
# Filter Performance: 95.3% rejection rate
# Spam spike detection: ACTIVE
# Volume quality filter: ENABLED

# 6. Monitor real-time logs
docker-compose logs -f trading-bot

# Press Ctrl+C to stop following
```

**Verify Aggressive Spam Filters:**

```bash
# Check filter statistics
docker-compose logs trading-bot | grep -E "(Filter|Spam|Rejection)"

# Expected:
# ✅ Filters verified - 90%+ spam rejection achieved
# Filter Performance: 95.3% rejection rate
# Spam spike detection: ACTIVE
# Volume quality filter: ENABLED

# Verify no spam trades executed
docker-compose logs trading-bot | grep "EXECUTED" | head -10

# Should show only high-quality trades (if any)
```

---

## Step 7: Check All Containers Running

**Comprehensive Status Check:**

```bash
# 1. List all containers
docker-compose ps

# 2. Check health status
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# 3. Verify critical services are healthy
for service in timescaledb prometheus trading-bot; do
    status=$(docker-compose ps $service --format '{{.Status}}')
    echo "$service: $status"
done

# Expected:
# timescaledb: Up (healthy)
# prometheus: Up (healthy)
# trading-bot: Up (healthy)

# 4. Check resource usage
docker stats --no-stream

# Shows CPU, memory, network usage for each container

# 5. Check networks
docker network ls | grep trading

# Expected: trading-network

# 6. Check volumes
docker volume ls | grep trading

# Expected:
# timescaledb_data
# prometheus_data
# grafana_data
```

**Service-by-Service Verification:**

```bash
# TimescaleDB
docker-compose exec timescaledb pg_isready -U trading_user
# Expected: accepting connections

# DragonflyDB (via Redis CLI)
docker-compose exec trading-bot curl -s ${REDIS_URL%/}/ping || echo "DragonflyDB connection test"
# Expected: PONG

# Prometheus
curl http://localhost:9090/-/healthy
# Expected: Prometheus is Healthy.

# Grafana
curl http://localhost:3000/api/health
# Expected: {"database":"ok"}

# AlertManager
curl http://localhost:9093/-/healthy
# Expected: OK
```

---

## Step 8: Access Monitoring Dashboards

**URLs (from local browser):**

- **Prometheus**: http://38.242.239.150:9090
  - Query metrics: `trading_bot_trades_total`
  - Check targets: Status > Targets

- **Grafana**: http://38.242.239.150:3000
  - Login: admin / [GRAFANA_ADMIN_PASSWORD from .env.docker]
  - Dashboards: Home > Dashboards
  - Import dashboards from `config/grafana/dashboards/`

- **Trading Bot Health**: http://38.242.239.150:8082/health
  - JSON response with bot status

- **Trading Bot Metrics**: http://38.242.239.150:9091/metrics
  - Prometheus format metrics

- **Data Consumer Metrics**: http://38.242.239.150:9191/metrics
  - Geyser streaming metrics

- **pgAdmin**: http://38.242.239.150:8081
  - Login: [PGADMIN_EMAIL] / [PGADMIN_PASSWORD]
  - Connect to TimescaleDB

**Import Grafana Dashboards:**

```bash
# On server, copy dashboards to Grafana
docker cp config/grafana/dashboards/trading_performance.json trading-bot-grafana:/var/lib/grafana/dashboards/
docker cp config/grafana/dashboards/system_health.json trading-bot-grafana:/var/lib/grafana/dashboards/
docker cp config/grafana/dashboards/data_ingestion.json trading-bot-grafana:/var/lib/grafana/dashboards/

# Or import via UI:
# Grafana > Dashboards > Import > Upload JSON file
```

---

## Management Commands

**View Logs:**

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f trading-bot

# Last 100 lines
docker-compose logs --tail=100 trading-bot

# Since timestamp
docker-compose logs --since 2024-10-15T10:00:00 trading-bot

# Filter for errors
docker-compose logs trading-bot | grep -i error
```

**Restart Services:**

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart trading-bot

# Restart with rebuild
docker-compose up -d --build trading-bot
```

**Stop Services:**

```bash
# Stop all (keeps data)
docker-compose stop

# Stop specific service
docker-compose stop trading-bot

# Stop and remove containers (keeps volumes)
docker-compose down

# Stop and remove everything including volumes (DESTRUCTIVE!)
docker-compose down -v
```

**Update Deployment:**

```bash
# Pull latest code
git pull origin main

# Rebuild images
docker-compose build

# Restart with new images
docker-compose up -d

# Or in one command
docker-compose up -d --build
```

---

## Troubleshooting

**Port Conflicts:**

The MojoRust Trading Bot uses automated port conflict resolution tools. For comprehensive port conflict management, see [Port Conflict Resolution Guide](./docs/port_conflict_resolution_guide.md).

**Quick Port Conflict Resolution:**

```bash
# 1. Diagnose port conflicts (automated)
./scripts/diagnose_port_conflict.sh

# 2. Verify all required ports before deployment
./scripts/verify_port_availability.sh --pre-deploy

# 3. If conflicts detected, use interactive resolution
./scripts/resolve_port_conflict.sh

# 4. Alternative: Manual port check
sudo netstat -tulpn | grep -E "(9090|8080|8082|3000|5432|6379)"

# 5. Alternative: Change TimescaleDB port in .env
echo "TIMESCALEDB_PORT=5433" >> .env
```

**Common Port Conflicts and Solutions:**

- **Port 5432 (TimescaleDB)**: Conflict with system PostgreSQL
  - Solution: Use `./scripts/resolve_port_conflict.sh` to reconfigure to port 5433
  - Or stop system PostgreSQL: `sudo systemctl stop postgresql`

- **Port 3000 (Grafana)**: Conflict with other web applications
  - Solution: Already configured to use port 3001 in docker-compose.yml

- **Port 9090 (Prometheus)**: Conflict with monitoring tools
  - Solution: Change port in docker-compose.yml if needed

**Pre-Deployment Port Check (Recommended):**

```bash
# Always verify ports before deployment
if ./scripts/verify_port_availability.sh --pre-deploy; then
    echo "✅ All ports available, proceeding with deployment"
    docker-compose up -d
else
    echo "❌ Port conflicts detected, resolve first"
    ./scripts/resolve_port_conflict.sh
fi
```

**Container Won't Start:**

```bash
# Check logs
docker-compose logs [service_name]

# Check container exit code
docker-compose ps [service_name]

# Inspect container
docker inspect trading-bot-[service_name]

# Try starting in foreground
docker-compose up [service_name]
```

**Health Check Failures:**

```bash
# Check health status
docker-compose ps

# Inspect health check
docker inspect trading-bot-app | grep -A 10 Health

# Test health endpoint manually
docker-compose exec trading-bot curl http://localhost:8082/health
```

**Database Connection Issues:**

```bash
# Test TimescaleDB connection
docker-compose exec trading-bot psql -h timescaledb -U trading_user -d trading_db

# Test DragonflyDB connection
docker-compose exec trading-bot curl -s ${REDIS_URL%/}/ping || echo "DragonflyDB connection test"
```

**DragonflyDB Connection Issues:**

```bash
# Check REDIS_URL is set correctly
docker-compose exec trading-bot env | grep REDIS_URL

# Test DragonflyDB connection from server
curl -I ${REDIS_URL}

# If DragonflyDB is not accessible:
# 1. Check firewall allows outbound connections to DragonflyDB Cloud
# 2. Verify REDIS_URL format: rediss://user:password@host:port
# 3. Check DragonflyDB Cloud service status
```

---

## Performance Optimization

**DragonflyDB Performance:**

```bash
# Check DragonflyDB connection metrics
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} info stats

# Monitor memory usage
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} info memory

# Check key distribution
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} info keyspace
```

**Container Resource Limits:**

```bash
# Monitor resource usage
docker stats

# Set memory limits in docker-compose.yml:
# deploy:
#   resources:
#     limits:
#       memory: 2G
#     reservations:
#       memory: 1G
```

---

## Security Considerations

**DragonflyDB Security:**

```bash
# Verify DragonflyDB connection uses TLS (rediss://)
echo $REDIS_URL | grep rediss://

# Check DragonflyDB authentication
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} auth
```

**Container Security:**

```bash
# Check containers are running as non-root users
docker-compose exec trading-bot whoami

# Verify no sensitive data in logs
docker-compose logs trading-bot | grep -i -E "(password|key|secret)" | head -5
```

---

## Next Steps

After successful deployment:

1. **Monitor for 24-48 hours** in paper trading mode
2. **Check filter performance** regularly: `docker-compose logs trading-bot | grep "Filter Performance"`
3. **Review trades**: Ensure only high-quality signals are executed
4. **Monitor resources**: `docker stats`
5. **Set up alerts**: Configure AlertManager webhooks
6. **Backup data**: `docker-compose exec timescaledb pg_dump ...`
7. **Switch to live trading**: Only after paper trading is stable (see Phase 4 documentation)

---

**⚠️ IMPORTANT**: Always start with paper trading mode. Never switch to live trading without 24+ hours of successful paper trading and thorough verification of filter performance.

## DragonflyDB vs Redis Note

This deployment uses DragonflyDB Cloud instead of local Redis for better performance and scalability:

- **DragonflyDB Cloud**: Ultra-performance, Redis-compatible database
- **Connection**: Via `REDIS_URL` environment variable (TLS encrypted)
- **Benefits**: Higher throughput, lower latency, automatic scaling
- **Configuration**: No local Redis service needed in docker-compose.yml

If you need to switch back to local Redis for development:
1. Uncomment Redis service in docker-compose.yml
2. Set `REDIS_URL=redis://:${REDIS_PASSWORD:-trading_password}@redis:6379` in .env
3. Restart services: `docker-compose up -d`