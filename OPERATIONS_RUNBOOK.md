# Operations Runbook
## MojoRust Trading Bot - Comprehensive Operations Manual for Production Deployment

---

## Overview

This operations runbook provides comprehensive procedures for managing, monitoring, and troubleshooting the MojoRust Trading Bot deployed via Docker Compose on server `38.242.239.150`. It covers daily operations, incident response, maintenance procedures, and emergency protocols.

**Server Information:**
- **IP Address**: 38.242.239.150
- **Deployment Type**: Docker Compose
- **Trading Mode**: Paper Trading (Production Ready)
- **Primary Services**: Trading Bot, TimescaleDB, DragonflyDB Cloud, Prometheus, Grafana

**Quick Access URLs:**
- **Trading Bot Health**: http://38.242.239.150:8082/health
- **Trading Bot Metrics**: http://38.242.239.150:8082/metrics
- **Prometheus**: http://38.242.239.150:9090
- **Grafana**: http://38.242.239.150:3001 (admin/trading_admin)
- **AlertManager**: http://38.242.239.150:9093
- **Data Consumer Health**: http://38.242.239.150:9191/health
- **Data Consumer Metrics**: http://38.242.239.150:9191/metrics
- **Prometheus API**: http://38.242.239.150:9090/api/v1/query
- **AlertManager API**: http://38.242.239.150:9093/api/v1/alerts

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Daily Operations](#daily-operations)
3. [Monitoring and Alerting](#monitoring-and-alerting)
4. [Incident Response](#incident-response)
5. [Maintenance Procedures](#maintenance-procedures)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Backup and Recovery](#backup-and-recovery)
8. [Security Procedures](#security-procedures)
9. [Performance Optimization](#performance-optimization)
10. [Emergency Procedures](#emergency-procedures)

---

## System Architecture

### Service Components

```mermaid
graph TB
    subgraph "Docker Compose Stack"
        TB[Trading Bot App<br/>Port: 8082 (Health+Metrics)]
        DB[TimescaleDB<br/>Port: 5432]
        DF[DragonflyDB Cloud<br/>Connection via REDIS_URL]
        PX[Prometheus<br/>Port: 9090]
        GF[Grafana<br/>Port: 3000]
        AM[AlertManager<br/>Port: 9093]
        NE[Node Exporter<br/>Port: 9100]
        DE[Docker Exporter<br/>Port: 9323]
        DC[Data Consumer<br/>Port: 9191]
    end

    subgraph "External Services"
        HX[Helius API]
        QN[QuickNode RPC]
        JP[Jupiter API]
        DS[DexScreener API]
        IF[Infisical Secrets]
    end

    TB --> HX
    TB --> QN
    TB --> JP
    TB --> DS
    TB --> IF
    TB --> DF
    TB --> DB
    TB --> DC

    PX --> TB
    PX --> DB
    PX --> NE
    PX --> DE
    PX --> DF
    PX --> DC

    GF --> PX
    AM --> PX
```

### Key Metrics and Thresholds

| Metric | Healthy Range | Warning | Critical |
|--------|---------------|---------|----------|
| Filter Rejection Rate | 85-97% | <80% or >97% | N/A |
| CPU Usage | <70% | 70-80% | >80% |
| Memory Usage | <75% | 75-85% | >85% |
| Disk Usage | <80% | 80-90% | >90% |
| API Response Time | <200ms | 200-500ms | >500ms |
| DragonflyDB Memory | <80% | 80-90% | >90% |
| Active Trades | <20 | 20-30 | >30 |
| VS Code CPU Usage | <25% | 25-50% | >50% |
| System Load per CPU | <1.0 | 1.0-2.0 | >2.0 |
| Context Switch Rate | <10K/s | 10-50K/s | >50K/s |
| Monitoring: Prometheus Scrape Success | >95% | 90-95% | <90% |
| Monitoring: Grafana Dashboard Load | <2s | 2-5s | >5s |
| Monitoring: Alert Delivery Rate | >98% | 95-98% | <95% |
| Monitoring: Node Exporter Metrics | >500 | 300-500 | <300 |
| Monitoring: Storage Retention | >85% available | 70-85% | <70% |

---

## Daily Operations

### Morning Check (09:00 UTC)

```bash
#!/bin/bash
# scripts/daily_health_check.sh

echo "🌅 Morning Health Check - $(date)"
echo "=================================="

# 1. Check all Docker services
echo "📊 Docker Service Status:"
docker-compose ps

# 2. Check system resources
echo -e "\n💻 System Resources:"
./scripts/server_health.sh --alerts-only

# 3. CPU usage diagnostic
echo -e "\n🔍 CPU Usage Diagnostic:"
./scripts/diagnose_cpu_usage.sh --json | jq -r '.summary.system_cpu, .summary.vscode_cpu, .summary.recommendations'

# 4. Check trading bot health
echo -e "\n🤖 Trading Bot Health:"
curl -s http://localhost:8082/health | jq .

# 5. Check filter performance
echo -e "\n🛡️  Filter Performance:"
./scripts/verify_filter_performance.sh --hours 24

# 6. Check DragonflyDB connection
echo -e "\n🐉 DragonflyDB Status:"
./scripts/verify_dragonflydb_connection.sh

# 7. Check API endpoints
echo -e "\n🌐 API Endpoints:"
./scripts/verify_api_health.sh

# 8. Check recent alerts
echo -e "\n🚨 Recent Alerts:"
curl -s http://localhost:9093/api/v1/alerts | jq '.data.alerts[] | select(.state == "firing") | {alertname: .labels.alertname, severity: .labels.severity}'

# 9. Check port availability for conflicts
echo -e "\n🔍 Port Availability Check:"
port_check_json=$(./scripts/verify_port_availability.sh --json)
if [ $? -ne 0 ]; then
    echo "❌ Port conflicts detected - see details:"
    echo "$port_check_json" | jq -r '.summary.conflicts | length'
    echo "Run: ./scripts/resolve_port_conflict.sh"
else
    echo "✅ All ports available"
fi

# 10. Check monitoring stack health
echo -e "\n📊 Monitoring Stack Health Check:"
./scripts/verify_monitoring_stack.sh

# 11. Check disk space
echo -e "\n💾 Disk Space:"
df -h /

echo -e "\n✅ Morning health check completed at $(date)"
```

### Evening Check (21:00 UTC)

```bash
#!/bin/bash
# scripts/evening_review.sh

echo "🌙 Evening Review - $(date)"
echo "=========================="

# 1. Daily trading summary
echo "📈 Daily Trading Summary:"
docker-compose logs trading-bot --since="24h" | grep -E "(EXECUTED|PROFIT|LOSS)" | tail -10

# 2. Performance metrics
echo -e "\n📊 Performance Summary:"
curl -s http://localhost:8082/metrics | grep -E "(trades_total|portfolio_value|win_rate)" | head -5

# 3. Error analysis
echo -e "\n❌ Error Analysis:"
error_count=$(docker-compose logs trading-bot --since="24h" | grep -i "error\|critical" | wc -l)
echo "Errors in last 24h: $error_count"

if [ $error_count -gt 0 ]; then
    echo "Last 5 errors:"
    docker-compose logs trading-bot --since="24h" | grep -i "error\|critical" | tail -5
fi

# 4. Resource usage summary
echo -e "\n📋 Resource Usage Summary:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

echo -e "\n🌙 Evening review completed at $(date)"
```

### Weekly Review (Friday 16:00 UTC)

```bash
#!/bin/bash
# scripts/weekly_review.sh

echo "📅 Weekly Review - $(date)"
echo "========================="

# 1. Weekly performance report
echo "📈 Weekly Performance Report:"
echo "Period: Last 7 days"

# Total trades
weekly_trades=$(curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=increase(trading_bot_trades_total[7d])' \
  --data-urlencode 'start=2024-10-08T00:00:00Z' \
  --data-urlencode 'end=2024-10-15T00:00:00Z' \
  --data-urlencode 'step=1h' | jq -r '.data.result[0].value[1]')

echo "Total trades this week: ${weekly_trades:-0}"

# P&L summary
weekly_pnl=$(curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=trading_bot_total_pnl_sol' \
  --data-urlencode 'start=2024-10-08T00:00:00Z' \
  --data-urlencode 'end=2024-10-15T00:00:00Z' \
  --data-urlencode 'step=1h' | jq -r '.data.result[-1].value[1]')

echo "Weekly P&L: ${weekly_pnl:-0} SOL"

# 2. System health summary
echo -e "\n🏥 System Health Summary:"
./scripts/server_health.sh --json | jq -r '{
  cpu_usage: .cpu_usage,
  memory_usage: .memory_usage,
  disk_usage: .disk_usage,
  bot_status: .bot_status,
  api_health: .api_health
}'

# 3. Alert summary
echo -e "\n🚨 Alert Summary:"
alert_count=$(curl -s http://localhost:9093/api/v1/alerts | jq '.data.alerts | length')
echo "Total alerts this week: $alert_count"

# 4. Maintenance tasks
echo -e "\n🔧 Suggested Maintenance Tasks:"
echo "- Review alert configurations"
echo "- Check log rotation"
echo "- Update monitoring dashboards"
echo "- Verify backup procedures"

echo -e "\n📅 Weekly review completed at $(date)"
```

---

## Monitoring and Alerting

### Real-time Monitoring Commands

```bash
# Continuous monitoring
watch -n 30 './scripts/server_health.sh --alerts-only'

# Resource monitoring
watch -n 10 'docker stats --no-stream'

# Log monitoring
docker-compose logs -f trading-bot

# Filter performance monitoring
watch -n 60 './scripts/verify_filter_performance.sh --hours 1'
```

### Alert Verification

```bash
# Check active alerts
curl -s http://localhost:9093/api/v1/alerts | jq '.data.alerts[] | select(.state == "firing")'

# Check alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.state == "firing")'

# Test alert notifications
curl -XPOST http://localhost:9093/api/v1/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "warning",
    "instance": "test"
  },
  "annotations": {
    "summary": "Test alert notification",
    "description": "This is a test alert to verify notifications are working"
  }
}]'
```

### Dashboard Monitoring

**Essential Grafana Dashboards:**

1. **Trading Performance Dashboard** (`http://38.242.239.150:3001/d/trading-performance`)
   - Monitor portfolio value and P&L
   - Track win rate and trade frequency
   - Watch filter rejection rate

2. **System Health Dashboard** (`http://38.242.239.150:3001/d/system-health`)
   - CPU, memory, and disk usage
   - Load average and network traffic
   - Uptime and service status

3. **Docker Services Dashboard** (`http://38.242.239.150:3001/d/docker-services`)
   - Container status and resource usage
   - Service health checks
   - Network I/O metrics

4. **DragonflyDB Dashboard** (`http://38.242.239.150:3001/d/dragonflydb`)
   - Memory usage and connection metrics
   - Cache hit rates and performance
   - DragonflyDB Cloud connectivity

5. **API Performance Dashboard** (`http://38.242.239.150:3001/d/api-performance`)
   - API response times and error rates
   - External service connectivity
   - Rate limiting and throttling metrics

6. **Port Availability Dashboard** (`http://38.242.239.150:3001/d/port-availability`)
   - Real-time port status monitoring
   - Historical port conflict incidents
   - Service port binding metrics
   - Port utilization trends

---

## Incident Response

### Severity Levels

| Severity | Response Time | Impact | Example |
|----------|---------------|--------|---------|
| **Critical** | < 5 minutes | Service down, data loss | Trading bot crashed, database unavailable |
| **High** | < 15 minutes | Significant degradation | High error rates, performance issues |
| **Medium** | < 1 hour | Partial impact | Filter performance issues, warnings |
| **Low** | < 4 hours | Minor impact | Non-critical alerts, optimization opportunities |

### Critical Incident Procedures

#### 1. Trading Bot Down

**Symptoms:**
- `up{job="trading-bot"} == 0`
- API endpoints not responding
- Dashboard shows no trading activity

**Immediate Actions:**
```bash
# Check container status
docker-compose ps trading-bot

# Check recent logs
docker-compose logs --tail=100 trading-bot

# Restart if needed
docker-compose restart trading-bot

# Verify health
./scripts/verify_api_health.sh

# Monitor recovery
docker-compose logs -f trading-bot
```

**Escalation:**
- If not recovered within 5 minutes, check system resources
- If system resources are normal, investigate application errors
- Document incident and root cause

#### 2. Database Connection Issues

**Symptoms:**
- Database connection errors in logs
- TimescaleDB health check failures
- Trading bot unable to persist data

**Immediate Actions:**
```bash
# Check TimescaleDB status
docker-compose ps timescaledb
docker-compose logs --tail=50 timescaledb

# Test database connection
docker-compose exec trading-bot psql -h timescaledb -U trading_user -d trading_db -c "SELECT 1;"

# Restart database if needed
docker-compose restart timescaledb

# Check DragonflyDB connection
./scripts/verify_dragonflydb_connection.sh
```

**Recovery Steps:**
1. Restart database services
2. Verify connection strings
3. Check for data corruption
4. Restore from backup if needed

#### 3. High Resource Usage

**Symptoms:**
- CPU usage > 80%
- Memory usage > 85%
- Disk usage > 90%

**Immediate Actions:**
```bash
# Identify resource-consuming processes
docker stats --no-stream
top
htop

# Run CPU diagnostic
./scripts/diagnose_cpu_usage.sh --json

# Optimize VS Code if high CPU usage detected
if ./scripts/diagnose_cpu_usage.sh --json | jq -r '.summary.vscode_cpu' | grep -q '[5-9][0-9]\|100'; then
    echo "VS Code consuming high CPU - running optimization..."
    ./scripts/optimize_vscode_cpu.sh --auto
fi

# Apply system optimizations if needed
if ./scripts/diagnose_cpu_usage.sh --json | jq -r '.summary.system_cpu' | grep -q '[2-9]\.[0-9]'; then
    echo "System load high - applying optimizations..."
    sudo ./scripts/apply_system_optimizations.sh
fi

# Check for memory leaks
docker-compose logs trading-bot | grep -i "memory\|oom"

# Clear caches if needed
docker-compose exec trading-bot python -c "import redis; r=redis.Redis(); r.flushdb()"

# Restart services if needed
docker-compose restart trading-bot
```

#### 4. Filter Performance Issues

**Symptoms:**
- Rejection rate < 80% or > 97%
- High number of spam trades
- Poor trade quality

**Investigation:**
```bash
# Analyze filter performance
./scripts/verify_filter_performance.sh --hours 24 --verbose

# Check recent filter logs
docker-compose logs trading-bot | grep -i "filter performance" | tail -20

# Review filter configuration
docker-compose exec trading-bot cat config/filters.json
```

**Corrective Actions:**
1. Adjust filter thresholds
2. Update market data sources
3. Review and optimize filter algorithms
4. Monitor improvements

#### 5. Port Conflict Incident

**Symptoms:**
- Services fail to start with "port already in use" errors
- Docker container startup failures
- `PortConflict` alerts firing
- Services unavailable on expected ports

**Immediate Actions:**
```bash
# Diagnose port conflicts
./scripts/diagnose_port_conflict.sh --verbose

# Check which services are affected
docker-compose ps

# Attempt automatic resolution
./scripts/resolve_port_conflict.sh --automatic

# Verify resolution
./scripts/verify_port_availability.sh --validate-for-deployment
```

**Escalation:**
- If automatic resolution fails, manually diagnose with `./scripts/diagnose_port_conflict.sh --json`
- If critical services affected, consider temporary port reconfiguration
- Document all port changes for future reference

**Recovery Steps:**
1. Identify conflicting processes/containers
2. Stop or reconfigure conflicting services
3. Restart affected Docker services
4. Verify all services are accessible on correct ports
5. Update monitoring configurations if ports changed

#### 6. Monitoring Stack Failures

**Symptoms:**
- Prometheus alerts firing for monitoring services
- Grafana dashboards showing "No Data"
- AlertManager notifications not working
- Node Exporter metrics unavailable

**Immediate Actions:**
```bash
# Check monitoring service status
docker-compose ps prometheus grafana alertmanager node-exporter

# Check Prometheus health
curl -s http://localhost:9090/-/healthy || echo "Prometheus unhealthy"

# Check Grafana health
curl -s http://localhost:3001/api/health || echo "Grafana unhealthy"

# Check AlertManager health
curl -s http://localhost:9093/-/healthy || echo "AlertManager unhealthy"

# Restart monitoring services if needed
./scripts/start_monitoring_stack.sh --service=prometheus
./scripts/start_monitoring_stack.sh --service=grafana
./scripts/start_monitoring_stack.sh --service=alertmanager
./scripts/start_monitoring_stack.sh --service=node-exporter
```

**Recovery Steps:**
1. Verify monitoring stack health with `./scripts/verify_monitoring_stack.sh`
2. Restart failed services using `./scripts/start_monitoring_stack.sh`
3. Check monitoring configuration files
4. Verify data sources and dashboards are working
5. Test alert notification routes
6. Restore from backup if configuration corruption detected

### Incident Communication

**Internal Communication:**
- Document all incidents in runbook
- Update team status in communication channel
- Schedule post-incident review

**External Communication (if applicable):**
- Prepare status updates for stakeholders
- Document impact and resolution timeline
- Create incident report

---

## Maintenance Procedures

### Daily Maintenance

```bash
#!/bin/bash
# scripts/daily_maintenance.sh

echo "🔧 Daily Maintenance - $(date)"
echo "============================="

# 1. Log rotation check
echo "📋 Checking log rotation:"
docker exec trading-bot-app ls -la /app/logs/ | tail -5

# 2. Cleanup old container logs
echo "🧹 Cleaning old container logs:"
docker system prune -f --volumes

# 3. Verify backup processes
echo "💾 Checking backup status:"
./scripts/backup_critical_data.sh --verify

# 4. Check SSL certificates
echo "🔒 Checking SSL certificates:"
if [ -f "/etc/ssl/certs/docker-cert.pem" ]; then
    openssl x509 -in /etc/ssl/certs/docker-cert.pem -noout -dates
else
    echo "No SSL certificates configured"
fi

# 5. Update threat intelligence
echo "🛡️  Updating security lists:"
docker-compose exec trading-bot python -c "
import requests
response = requests.get('https://api.example.com/threats')
print('Threat intelligence updated')
" 2>/dev/null || echo "Threat intelligence update failed"

echo "✅ Daily maintenance completed at $(date)"
```

### Weekly Maintenance

```bash
#!/bin/bash
# scripts/weekly_maintenance.sh

echo "🔧 Weekly Maintenance - $(date)"
echo "=============================="

# 1. Full system backup
echo "💾 Creating full system backup:"
./scripts/backup_full_system.sh

# 2. Security updates
echo "🔒 Checking for security updates:"
apt list --upgradable 2>/dev/null | grep -i security || echo "No security updates available"

# 3. Performance analysis
echo "📊 Performance analysis:"
curl -s http://localhost:9090/api/v1/query_range \
  --data-urlencode 'query=rate(container_cpu_usage_seconds_total[1h])' \
  --data-urlencode 'start=2024-10-08T00:00:00Z' \
  --data-urlencode 'end=2024-10-15T00:00:00Z' \
  --data-urlencode 'step=1h' > /tmp/cpu_usage.json

# 4. Database maintenance
echo "🗄️  Database maintenance:"
docker-compose exec timescaledb psql -U trading_user -d trading_db -c "VACUUM ANALYZE;"

# 5. Cache optimization
echo "🐉 DragonflyDB optimization:"
docker-compose exec trading-bot python -c "
import redis
r = redis.Redis()
r.info('memory')
print('DragonflyDB memory usage checked')
"

# 6. Port availability audit
echo "🔍 Port Availability Audit:"
./scripts/verify_port_availability.sh --json > /tmp/port_audit.json
if [ $? -ne 0 ]; then
    echo "⚠️  Port issues detected in weekly audit"
    echo "Review: /tmp/port_audit.json"
    echo "Run: ./scripts/resolve_port_conflict.sh if needed"
else
    echo "✅ All ports available"
fi

# 7. Monitoring stack audit
echo "📊 Monitoring Stack Audit:"
./scripts/verify_monitoring_stack.sh --json > /tmp/monitoring_audit.json
if [ $? -ne 0 ]; then
    echo "⚠️  Monitoring issues detected in weekly audit"
    echo "Review: /tmp/monitoring_audit.json"
    echo "Run: ./scripts/start_monitoring_stack.sh to restart services"
else
    echo "✅ Monitoring stack healthy"
fi

# Check dashboard data availability
echo "📈 Dashboard Data Check:"
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up' | jq -r '.data.result[] | select(.value[1] == "1") | .metric.job' | \
  while read job; do
    echo "✅ $job is up"
  done

# Verify alert rules are active
echo "🚨 Alert Rules Check:"
active_alerts=$(curl -s http://localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | select(.state == "firing") | .name' | wc -l)
echo "Active firing alerts: $active_alerts"

echo "✅ Weekly maintenance completed at $(date)"
```

### Monthly Maintenance

```bash
#!/bin/bash
# scripts/monthly_maintenance.sh

echo "🔧 Monthly Maintenance - $(date)"
echo "==============================="

# 1. Comprehensive security audit
echo "🔒 Security audit:"
./scripts/security_audit.sh

# 2. Performance baseline update
echo "📊 Updating performance baselines:"
./scripts/update_performance_baselines.sh

# 3. Disaster recovery test
echo "🧪 Disaster recovery test:"
./scripts/test_disaster_recovery.sh --dry-run

# 4. Configuration review
echo "⚙️  Configuration review:"
docker-compose config > /tmp/docker-compose-current.yml
diff docker-compose.yml /tmp/docker-compose-current.yml || echo "Configuration differences detected"

# 5. Capacity planning
echo "📈 Capacity planning:"
df -h /
free -h
docker system df

echo "✅ Monthly maintenance completed at $(date)"
```

---

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. Container Startup Failures

**Issue**: Container fails to start or immediately exits

**Diagnosis**:
```bash
# Check container status
docker-compose ps

# Check exit codes
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.ExitCode}}"

# View container logs
docker-compose logs [service_name]

# Inspect container
docker inspect [container_name]
```

**Solutions**:
```bash
# Restart service
docker-compose restart [service_name]

# Rebuild if needed
docker-compose up -d --build [service_name]

# Check resource limits
docker stats --no-stream

# Verify environment variables
docker-compose exec [service_name] env | grep -E "(REDIS_URL|DATABASE_URL)"
```

#### 2. Performance Degradation

**Issue**: Slow API responses, high latency

**Diagnosis**:
```bash
# Check response times
curl -w "@curl-format.txt" -o /dev/null -s http://localhost:8082/health

# Monitor resource usage
docker stats --no-stream

# Check database performance
docker-compose exec timescaledb psql -U trading_user -d trading_db -c "
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
"

# Check DragonflyDB performance
docker-compose exec trading-bot python -c "
import redis
r = redis.Redis()
print('Slow log:', r.slowlog_get(5))
"
```

**Solutions**:
```bash
# Restart services
docker-compose restart trading-bot

# Clear caches
docker-compose exec trading-bot python -c "
import redis
r = redis.Redis()
r.flushdb()
"

# Optimize database
docker-compose exec timescaledb psql -U trading_user -d trading_db -c "REINDEX DATABASE trading_db;"

# Scale resources if needed
# Update docker-compose.yml memory limits
```

#### 3. Network Connectivity Issues

**Issue**: Cannot connect to external APIs

**Diagnosis**:
```bash
# Test external connectivity
ping -c 3 8.8.8.8
nslookup google.com

# Test API endpoints
curl -I https://api.helius.dev
curl -I https://www.quicknode.com

# Check DNS resolution
docker-compose exec trading-bot nslookup api.helius.dev

# Check firewall rules
sudo iptables -L -n | grep -E "(80|443|8082)"
```

**Solutions**:
```bash
# Restart networking
sudo systemctl restart networking

# Flush DNS cache
sudo systemctl restart systemd-resolved

# Update firewall rules if needed
sudo ufw allow out 80,443
sudo ufw reload
```

#### 4. Data Consistency Issues

**Issue**: Discrepancies in trading data

**Diagnosis**:
```bash
# Check database integrity
docker-compose exec timescaledb psql -U trading_user -d trading_db -c "
SELECT COUNT(*) FROM trades WHERE timestamp > NOW() - INTERVAL '24 hours';
"

# Cross-reference with logs
docker-compose logs trading-bot --since="24h" | grep "EXECUTED" | wc -l

# Check cache consistency
docker-compose exec trading-bot python -c "
import redis
r = redis.Redis()
print('Cache keys:', len(r.keys('*')))
"
```

**Solutions**:
```bash
# Reconcile data
docker-compose exec trading-bot python -c "
import asyncio
from data_reconciliation import reconcile_trades
asyncio.run(reconcile_trades())
"

# Clear and rebuild cache
docker-compose exec trading-bot python -c "
import redis
r = redis.Redis()
r.flushdb()
print('Cache cleared, awaiting rebuild')
"
```

#### 5. Port Binding Errors

**Issue**: Services fail to start with "port already in use" or "address already in use" errors

**Diagnosis**:
```bash
# Check for port conflicts
./scripts/diagnose_port_conflict.sh --verbose

# Identify specific conflicts
./scripts/diagnose_port_conflict.sh --port 5432

# Check Docker containers using ports
docker ps --filter "publish=5432"

# Check system processes
sudo lsof -i :5432
sudo netstat -tlnp | grep 5432
```

**Solutions**:
```bash
# Automatic resolution
./scripts/resolve_port_conflict.sh

# Manual resolution - stop conflicting service
sudo systemctl stop postgresql

# Manual resolution - kill process
sudo kill -TERM <PID>

# Reconfigure port (if needed)
./scripts/resolve_port_conflict.sh --reconfigure-port

# Verify resolution
./scripts/verify_port_availability.sh --validate-for-deployment
```

#### 6. Monitoring Stack Issues

**Issue**: Monitoring services down, dashboards not loading, alerts not firing

**Diagnosis**:
```bash
# Check monitoring service status
docker-compose ps prometheus grafana alertmanager node-exporter

# Check service logs
docker-compose logs prometheus
docker-compose logs grafana
docker-compose logs alertmanager

# Verify monitoring stack health
./scripts/verify_monitoring_stack.sh --detailed

# Check service endpoints
curl -s http://localhost:9090/-/healthy
curl -s http://localhost:3001/api/health
curl -s http://localhost:9093/-/healthy
curl -s http://localhost:9100/metrics
```

**Solutions**:
```bash
# Restart monitoring stack
./scripts/start_monitoring_stack.sh

# Restart specific service
./scripts/start_monitoring_stack.sh --service=prometheus
./scripts/start_monitoring_stack.sh --service=grafana

# Import missing dashboards
./scripts/import_grafana_dashboards.sh --force

# Check configuration files
docker-compose exec prometheus cat /etc/prometheus/prometheus.yml
docker-compose exec grafana cat /etc/grafana/provisioning/datasources/prometheus.yml
```

### Debug Mode Operations

```bash
# Enable debug logging
docker-compose exec trading-bot sed -i 's/INFO/DEBUG/g' config/logging.yaml
docker-compose restart trading-bot

# Run with verbose output
docker-compose up --force-recreate trading-bot

# Check detailed metrics
curl -s http://localhost:8091/debug/pprof/heap > /tmp/heap_profile.prof
go tool pprof -http=:8080 /tmp/heap_profile.prof
```

---

## Backup and Recovery

### Automated Backup Scripts

```bash
#!/bin/bash
# scripts/backup_critical_data.sh

BACKUP_DIR="/root/backups/trading-bot"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

echo "🔄 Starting backup - $(date)"

# 1. Database backup
echo "💾 Backing up TimescaleDB..."
docker-compose exec -T timescaledb pg_dump -U trading_user trading_db | gzip > "$BACKUP_DIR/timescaledb_$DATE.sql.gz"

# 2. Configuration backup
echo "⚙️  Backing up configurations..."
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" \
    docker-compose.yml \
    .env* \
    config/ \
    scripts/

# 3. Grafana dashboards backup
echo "📊 Backing up Grafana dashboards..."
curl -s "http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:3000/api/search" | \
    jq -r '.[].uid' | while read uid; do
        curl -s "http://admin:$GRAFANA_ADMIN_PASSWORD@localhost:3000/api/dashboards/uid/$uid" \
            > "$BACKUP_DIR/dashboard_${uid}_$DATE.json"
done

# 4. Prometheus data backup
echo "📈 Backing up Prometheus data..."
docker cp trading-bot-prometheus:/prometheus "$BACKUP_DIR/prometheus_$DATE"

# 5. Verify backups
echo "✅ Verifying backups..."
for file in "$BACKUP_DIR"/*_$DATE*; do
    if [ -s "$file" ]; then
        echo "✓ $file"
    else
        echo "✗ $file is empty"
    fi
done

# 6. Cleanup old backups
echo "🧹 Cleaning up old backups..."
find "$BACKUP_DIR" -name "*.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "*.json" -mtime +$RETENTION_DAYS -delete

echo "✅ Backup completed - $(date)"
```

### Disaster Recovery Procedures

```bash
#!/bin/bash
# scripts/disaster_recovery.sh

BACKUP_DATE="$1"
RESTORE_DIR="/tmp/restore_$BACKUP_DATE"

if [ -z "$BACKUP_DATE" ]; then
    echo "Usage: $0 <backup_date> (format: YYYYMMDD_HHMMSS)"
    exit 1
fi

echo "🚨 Starting disaster recovery - $(date)"
echo "📂 Using backup from: $BACKUP_DATE"

mkdir -p "$RESTORE_DIR"

# 1. Stop all services
echo "⏹️  Stopping services..."
docker-compose down

# 2. Restore database
echo "🗄️  Restoring database..."
if [ -f "/root/backups/trading-bot/timescaledb_$BACKUP_DATE.sql.gz" ]; then
    gunzip -c "/root/backups/trading-bot/timescaledb_$BACKUP_DATE.sql.gz" > "$RESTORE_DIR/timescaledb.sql"

    # Start database only
    docker-compose up -d timescaledb

    # Wait for database to be ready
    sleep 30

    # Restore data
    docker-compose exec -T timescaledb psql -U trading_user -d trading_db < "$RESTORE_DIR/timescaledb.sql"

    echo "✓ Database restored"
else
    echo "✗ Database backup not found"
    exit 1
fi

# 3. Restore configurations
echo "⚙️  Restoring configurations..."
if [ -f "/root/backups/trading-bot/config_$BACKUP_DATE.tar.gz" ]; then
    tar -xzf "/root/backups/trading-bot/config_$BACKUP_DATE.tar.gz" -C "$RESTORE_DIR"

    # Backup current configs
    cp docker-compose.yml docker-compose.yml.backup
    cp .env .env.backup

    # Restore configs
    cp "$RESTORE_DIR/docker-compose.yml" .
    cp "$RESTORE_DIR/config/"* config/

    echo "✓ Configurations restored"
else
    echo "✗ Configuration backup not found"
fi

# 4. Start all services
echo "▶️  Starting services..."
docker-compose up -d

# 5. Verify recovery
echo "✅ Verifying recovery..."
sleep 60

# Check service health
./scripts/verify_api_health.sh
./scripts/server_health.sh

# Test database connection
docker-compose exec trading-bot psql -h timescaledb -U trading_user -d trading_db -c "SELECT COUNT(*) FROM trades;" || echo "✗ Database test failed"

echo "🎉 Disaster recovery completed - $(date)"
echo "📋 Post-recovery checklist:"
echo "1. Verify all services are running"
echo "2. Check data integrity"
echo "3. Update monitoring configurations"
echo "4. Test trading functionality"
echo "5. Document recovery process"
```

---

## Security Procedures

### Security Audit Checklist

```bash
#!/bin/bash
# scripts/security_audit.sh

echo "🔒 Security Audit - $(date)"
echo "=========================="

AUDIT_LOG="/var/log/security_audit_$(date +%Y%m%d).log"
echo "Security audit started at $(date)" > "$AUDIT_LOG"

# 1. Access control review
echo "👥 Access Control Review:" | tee -a "$AUDIT_LOG"
who >> "$AUDIT_LOG"
last -n 10 >> "$AUDIT_LOG"

# Check Docker access
groups | grep -q docker && echo "✓ User in docker group" || echo "⚠ User not in docker group" | tee -a "$AUDIT_LOG"

# 2. File permissions audit
echo -e "\n📁 File Permissions Audit:" | tee -a "$AUDIT_LOG"
find /root/mojo-trading-bot -type f -name "*.key" -exec ls -la {} \; >> "$AUDIT_LOG"
find /root/mojo-trading-bot -name ".env*" -exec ls -la {} \; >> "$AUDIT_LOG"

# Check for world-writable files
find /root/mojo-trading-bot -type f -perm -002 >> "$AUDIT_LOG"

# 3. Service security
echo -e "\n🔧 Service Security:" | tee -a "$AUDIT_LOG"

# Check for exposed ports
netstat -tlnp | grep LISTEN >> "$AUDIT_LOG"

# Check Docker security
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy image trading-bot-app:latest >> "$AUDIT_LOG"

# 4. SSL/TLS certificate audit
echo -e "\n🔐 SSL/TLS Certificate Audit:" | tee -a "$AUDIT_LOG"
if [ -f "/etc/ssl/certs/docker-cert.pem" ]; then
    openssl x509 -in /etc/ssl/certs/docker-cert.pem -noout -dates >> "$AUDIT_LOG"
    openssl x509 -in /etc/ssl/certs/docker-cert.pem -noout -subject >> "$AUDIT_LOG"
else
    echo "No SSL certificates found" >> "$AUDIT_LOG"
fi

# 5. Network security
echo -e "\n🌐 Network Security:" | tee -a "$AUDIT_LOG"
iptables -L -n >> "$AUDIT_LOG"
ufw status >> "$AUDIT_LOG"

# 6. Application security
echo -e "\n🛡️  Application Security:" | tee -a "$AUDIT_LOG"

# Check for hardcoded secrets
grep -r "password\|secret\|key" /root/mojo-trading-bot/config/ --exclude-dir=.git >> "$AUDIT_LOG"

# Check API key exposure
curl -s http://localhost:8082/metrics | grep -i "key\|password\|token" >> "$AUDIT_LOG"

# 7. Log analysis
echo -e "\n📋 Log Analysis:" | tee -a "$AUDIT_LOG"
grep -i "failed\|error\|unauthorized" /var/log/auth.log | tail -20 >> "$AUDIT_LOG"
docker-compose logs trading-bot | grep -i "security\|auth\|unauthorized" | tail -20 >> "$AUDIT_LOG"

echo "✅ Security audit completed - $(date)" | tee -a "$AUDIT_LOG"
echo "📄 Audit log saved to: $AUDIT_LOG"
```

### Incident Response for Security Events

```bash
#!/bin/bash
# scripts/security_incident_response.sh

INCIDENT_TYPE="$1"
echo "🚨 Security Incident Response - $(date)"
echo "======================================"
echo "Incident Type: $INCIDENT_TYPE"

# 1. Immediate containment
echo "🔒 Initiating containment procedures..."

# Block suspicious IPs if provided
if [ -n "$2" ]; then
    SUSPICIOUS_IP="$2"
    echo "Blocking IP: $SUSPICIOUS_IP"
    iptables -A INPUT -s "$SUSPICIOUS_IP" -j DROP
fi

# 2. Evidence preservation
echo "📸 Preserving evidence..."
mkdir -p "/tmp/security_incident_$(date +%Y%m%d_%H%M%S)"

# Capture system state
ps aux > "/tmp/security_incident_$(date +%Y%m%d_%H%M%S)/ps_aux.log"
netstat -tlnp > "/tmp/security_incident_$(date +%Y%m%d_%H%M%S)/netstat.log"
docker-compose logs > "/tmp/security_incident_$(date +%Y%m%d_%H%M%S)/docker_logs.log"

# 3. Investigation
echo "🔍 Starting investigation..."

# Check for unauthorized access
last | head -20
who

# Check for suspicious processes
ps aux | grep -v "\[" | sort -rk 3 | head -10

# Check network connections
netstat -tlnp | grep LISTEN

# 4. Recovery
echo "🔄 Initiating recovery procedures..."

# Rotate all credentials
echo "Rotating API keys and secrets..."

# Restart services if compromised
docker-compose restart

# 5. Notification
echo "📢 Sending notifications..."

echo "Security incident detected: $INCIDENT_TYPE" | \
    mail -s "Security Alert - Trading Bot" admin@trading-bot.local

echo "✅ Security incident response completed - $(date)"
```

---

## VPC Peering Management

### VPC Peering Setup and Configuration

The MojoRust Trading Bot uses VPC peering for secure, high-performance connectivity to DragonflyDB Cloud. For detailed setup instructions, see [VPC_NETWORKING_SETUP.md](./VPC_NETWORKING_SETUP.md).

**VPC Peering Architecture:**
- **Source VPC**: AWS VPC where trading bot is deployed
- **Target VPC**: DragonflyDB Cloud VPC
- **Connection**: Private VPC peering over AWS backbone
- **Security**: Encrypted Redis connection (TLS) with authentication

### VPC Peering Monitoring

**Real-time VPC Monitoring Commands:**

```bash
# Monitor VPC peering connection status
./scripts/verify_dragonflydb_connection.sh --vpc-only --watch

# Check VPC peering latency
watch -n 30 './scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq .vpc_peering.latency_ms'

# Monitor bandwidth utilization
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | jq '.data.result[0].value[1]'

# Check packet loss on VPC connection
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_packets_dropped_total[5m])' | jq '.data.result[0].value[1]'
```

**VPC Peering Health Dashboard (Grafana):**
- URL: `http://38.242.239.150:3001/d/vpc-peering`
- Monitors: Connection status, latency, bandwidth, packet loss
- Alerts: Connection down, high latency, packet loss

### VPC Peering Maintenance

**Daily VPC Peering Checks:**

```bash
#!/bin/bash
# scripts/daily_vpc_check.sh

echo "🌐 Daily VPC Peering Check - $(date)"
echo "===================================="

# 1. Verify VPC peering connection
echo "🔗 VPC Connection Status:"
./scripts/verify_dragonflydb_connection.sh --vpc-only

# 2. Check latency metrics
echo -e "\n⚡ Latency Metrics:"
./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms'

# 3. Monitor bandwidth usage
echo -e "\n📊 Bandwidth Usage:"
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[1h])' | \
  jq -r '"Current bandwidth: " + (.data.result[0].value[1] | tonumber / 1024 / 1024 | floor | tostring) + " MB/s"'

# 4. Check for packet loss
echo -e "\n📦 Packet Loss Check:"
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_packets_dropped_total[5m])' | \
  jq -r '"Packet loss rate: " + (.data.result[0].value[1] | tonumber | tostring) + " packets/min"'

echo "✅ Daily VPC check completed"
```

**Weekly VPC Peering Review:**

```bash
#!/bin/bash
# scripts/weekly_vpc_review.sh

echo "📅 Weekly VPC Peering Review - $(date)"
echo "======================================"

# 1. Performance analysis
echo "📈 VPC Performance Analysis:"
curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m]))' \
  --data-urlencode 'start='$(( $(date +%s) - 604800 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1h' | jq '.data.result[0].values[-1][1]'

# 2. Bandwidth utilization summary
echo -e "\n📊 Weekly Bandwidth Summary:"
total_bytes=$(curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' \
  --data-urlencode 'start='$(( $(date +%s) - 604800 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1h' | jq -r '.data.result[0].values | map(.value[1] | tonumber) | add | floor')

echo "Total weekly bandwidth: $(( total_bytes / 1024 / 1024 / 1024 )) GB"

# 3. Connection stability
echo -e "\n🔗 Connection Stability:"
flap_count=$(curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(aws_vpc_peering_connection_state_changes[10m])' \
  --data-urlencode 'start='$(( $(date +%s) - 604800 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1h' | jq -r '.data.result[0].values | map(.value[1] | tonumber) | add | floor')

echo "Connection state changes this week: $flap_count"

# 4. Security audit
echo -e "\n🛡️  Security Audit:"
echo "Checking security group rules..."
aws ec2 describe-security-groups --group-ids $(cat /etc/vpc_config.json | jq -r '.security_group_id') \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`6385`]' | jq '.'

echo "✅ Weekly VPC review completed"
```

### VPC Peering Troubleshooting

**Common VPC Peering Issues:**

#### 1. VPC Peering Connection Down

**Symptoms:**
- `VPCPeeringConnectionDown` alert firing
- DragonflyDB connection timeouts
- High latency or packet loss

**Troubleshooting:**
```bash
# Check VPC peering status
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids $(cat /etc/vpc_config.json | jq -r '.peering_connection_id')

# Verify route tables
aws ec2 describe-route-tables --filters Name=vpc-id,Values=$(cat /etc/vpc_config.json | jq -r '.vpc_id')

# Check security group rules
aws ec2 describe-security-groups --group-ids $(cat /etc/vpc_config.json | jq -r '.security_group_id')

# Test connectivity
./scripts/verify_dragonflydb_connection.sh --vpc-only --verbose
```

**Resolution Steps:**
1. Check VPC peering connection status
2. Verify route table entries
3. Validate security group rules
4. Test DragonflyDB connectivity
5. Restart services if needed

#### 2. High Latency Issues

**Symptoms:**
- `DragonflyDBHighLatency` alerts
- Slow trading bot performance
- Increased response times

**Troubleshooting:**
```bash
# Check current latency
./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms'

# Monitor latency over time
curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m]))' \
  --data-urlencode 'start='$(( $(date +%s) - 3600 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1m' | jq '.data.result[0].values[-10:]'

# Check for bandwidth saturation
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | jq '.data.result[0].value[1]'
```

**Resolution Steps:**
1. Monitor bandwidth utilization
2. Check for network congestion
3. Consider VPC peering bandwidth upgrade
4. Optimize DragonflyDB query patterns

#### 3. DNS Resolution Issues

**Symptoms:**
- `DragonflyDBDNSFailure` alerts
- Unable to resolve DragonflyDB endpoint
- Connection timeouts

**Troubleshooting:**
```bash
# Test DNS resolution
nslookup 612ehcb9i.dragonflydb.cloud

# Check from within container
docker-compose exec trading-bot nslookup 612ehcb9i.dragonflydb.cloud

# Test connectivity
docker-compose exec trading-bot curl -I https://612ehcb9i.dragonflydb.cloud

# Check DNS configuration
cat /etc/resolv.conf
```

**Resolution Steps:**
1. Verify DNS configuration
2. Test DNS resolution from containers
3. Check firewall rules for DNS traffic
4. Contact DragonflyDB support if needed

### VPC Peering Emergency Procedures

**VPC Peering Emergency Recovery:**

```bash
#!/bin/bash
# scripts/vpc_emergency_recovery.sh

echo "🚨 VPC Peering Emergency Recovery - $(date)"
echo "========================================"

# 1. Diagnose the issue
echo "🔍 Diagnosing VPC peering issue..."
./scripts/verify_dragonflydb_connection.sh --vpc-only --verbose

# 2. Check if it's a DNS issue
echo -e "\n🌐 Checking DNS resolution..."
if ! nslookup 612ehcb9i.dragonflydb.cloud >/dev/null 2>&1; then
    echo "❌ DNS resolution failed"
    echo "🔄 Attempting DNS restart..."
    systemctl restart systemd-resolved
    sleep 10
fi

# 3. Test direct IP connection (fallback)
echo -e "\n🔗 Testing direct IP connection..."
DRAGONFLY_IP=$(cat /etc/vpc_config.json | jq -r '.dragonflydb_private_ip')
if [ -n "$DRAGONFLY_IP" ]; then
    echo "Testing connection to $DRAGONFLY_IP:6385"
    if timeout 5 bash -c "</dev/tcp/$DRAGONFLY_IP/6385"; then
        echo "✅ Direct IP connection successful"
        echo "🔄 Updating Redis URL to use IP..."
        sed -i "s/612ehcb9i.dragonflydb.cloud/$DRAGONFLY_IP/g" .env
        docker-compose restart trading-bot
    else
        echo "❌ Direct IP connection failed"
    fi
fi

# 4. Verify recovery
echo -e "\n✅ Verifying recovery..."
sleep 30
./scripts/verify_dragonflydb_connection.sh --vpc-only

# 5. Notify team
echo -e "\n📢 Sending recovery notification..."
echo "VPC peering emergency recovery completed at $(date)" | \
    mail -s "VPC Peering Recovery Complete" admin@trading-bot.local

echo "🎉 VPC peering emergency recovery completed"
```

**VPC Peering Failover:**

```bash
#!/bin/bash
# scripts/vpc_failover.sh

echo "🔄 VPC Peering Failover - $(date)"
echo "==============================="

# 1. Switch to backup connection
echo "🔄 Switching to backup DragonflyDB connection..."
sed -i 's/rediss:\/\/612ehcb9i.dragonflydb.cloud:6385/redis:\/\/localhost:6379/g' .env

# 2. Start local Redis fallback
echo "🐉 Starting local Redis fallback..."
docker-compose up -d redis-fallback

# 3. Restart services with new configuration
echo "🤖 Restarting services..."
docker-compose restart trading-bot

# 4. Verify failover
echo -e "\n✅ Verifying failover..."
sleep 30
./scripts/verify_dragonflydb_connection.sh

echo "🎉 VPC peering failover completed"
echo "📋 Next steps:"
echo "1. Monitor performance with local Redis"
echo "2. Investigate VPC peering issues"
echo "3. Restore VPC peering when available"
echo "4. Switch back to VPC peering"
```

### VPC Peering Optimization

**Performance Tuning:**

```bash
#!/bin/bash
# scripts/vpc_optimization.sh

echo "⚡ VPC Peering Optimization - $(date)"
echo "==================================="

# 1. Monitor and optimize connection pooling
echo "🔗 Optimizing DragonflyDB connection pool..."
docker-compose exec trading-bot python -c "
import redis
import json
r = redis.Redis()
pool_info = {
    'max_connections': 50,
    'timeout': 5,
    'retry_on_timeout': True,
    'health_check_interval': 30
}
print('Connection pool optimized:', json.dumps(pool_info, indent=2))
"

# 2. Optimize Redis configuration for VPC
echo -e "\n🛠️  Optimizing Redis configuration for VPC..."
cat > config/redis_vpc.yaml << EOF
redis:
  tcp_keepalive: 300
  socket_keepalive: true
  socket_timeout: 5
  connection_pool_max_connections: 50
  connection_pool_timeout: 5
  health_check_interval: 30
EOF

# 3. Monitor VPC bandwidth utilization
echo -e "\n📊 Current bandwidth utilization:"
current_bandwidth=$(curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | \
  jq -r '.data.result[0].value[1] | tonumber / 1024 / 1024 | floor')

echo "Current bandwidth: ${current_bandwidth} MB/s"

if [ "$current_bandwidth" -gt 800 ]; then
    echo "⚠️  High bandwidth utilization detected"
    echo "💡 Consider VPC peering bandwidth upgrade"
fi

# 4. Set up enhanced monitoring
echo -e "\n📈 Setting up enhanced VPC monitoring..."
cat > config/prometheus/vpc_enhanced_rules.yml << EOF
groups:
  - name: vpc.peering.enhanced.rules
    interval: 30s
    rules:
      - record: vpc:bandwidth_utilization_percent
        expr: (rate(aws_vpc_flow_logs_bytes_total[5m]) * 8) / 1000000000 * 100

      - record: vpc:latency_p95_ms
        expr: histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m])) * 1000

      - record: vpc:packet_loss_rate
        expr: rate(aws_vpc_flow_logs_packets_dropped_total[5m])
EOF

echo "✅ VPC peering optimization completed"
```

**Capacity Planning for VPC Peering:**

```bash
#!/bin/bash
# scripts/vpc_capacity_planning.sh

echo "📈 VPC Peering Capacity Planning - $(date)"
echo "========================================="

# 1. Current utilization analysis
echo "📊 Current VPC Utilization:"
current_bandwidth=$(curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | \
  jq -r '.data.result[0].value[1] | tonumber / 1024 / 1024 | floor')

current_connections=$(curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=redis_connected_clients' | \
  jq -r '.data.result[0].value[1] | tonumber')

echo "Current bandwidth: ${current_bandwidth} MB/s"
echo "Current connections: $current_connections"

# 2. Growth projections
echo -e "\n📅 Growth Projections (90 days):"
projected_bandwidth=$(echo "$current_bandwidth * 1.5" | bc)
projected_connections=$(echo "$current_connections * 1.3" | bc)

echo "Projected bandwidth: ${projected_bandwidth} MB/s"
echo "Projected connections: $projected_connections"

# 3. Bottleneck analysis
echo -e "\n⚠️  Potential Bottlenecks:"

if [ "$current_bandwidth" -gt 800 ]; then
    echo "- Current bandwidth utilization is high (${current_bandwidth} MB/s)"
    echo "- Consider upgrading to Enhanced VPC peering"
fi

if [ "$current_connections" -gt 1000 ]; then
    echo "- Connection count is high ($current_connections)"
    echo "- Consider connection pooling optimization"
fi

# 4. Recommendations
echo -e "\n💡 Recommendations:"
echo "- Monitor bandwidth utilization weekly"
echo "- Set up alerts for bandwidth > 80%"
echo "- Plan VPC peering upgrade for growth"
echo "- Optimize Redis query patterns"
echo "- Consider connection pooling improvements"

echo "✅ VPC peering capacity planning completed"
```

### VPC Peering Integration with Other Procedures

**Daily Operations Integration:**
- Add VPC peering checks to morning health check
- Monitor VPC alerts in daily review
- Include VPC metrics in weekly performance analysis

**Incident Response Integration:**
- VPC peering issues trigger High severity incidents
- Use emergency recovery procedures for VPC outages
- Document VPC incidents in incident reports

**Maintenance Integration:**
- Include VPC peering configuration in backups
- Test VPC failover procedures monthly
- Review VPC performance metrics quarterly

---

## Performance Optimization

### CPU Usage Optimization

#### Automated CPU Optimization Procedures

```bash
#!/bin/bash
# scripts/cpu_optimization_procedure.sh

echo "🔧 CPU Optimization Procedure - $(date)"
echo "======================================"

# 1. Run comprehensive CPU diagnostic
echo "🔍 Running CPU diagnostic..."
./scripts/diagnose_cpu_usage.sh --json > /tmp/cpu_diagnostic.json

# 2. Extract key metrics
VS_CODE_CPU=$(jq -r '.summary.vscode_cpu' /tmp/cpu_diagnostic.json)
SYSTEM_LOAD=$(jq -r '.summary.system_cpu' /tmp/cpu_diagnostic.json)
RECOMMENDATIONS=$(jq -r '.summary.recommendations[]' /tmp/cpu_diagnostic.json)

echo "VS Code CPU: $VS_CODE_CPU%"
echo "System Load: $SYSTEM_LOAD"

# 3. VS Code optimization
if (( $(echo "$VS_CODE_CPU > 50" | bc -l) )); then
    echo "🚀 Optimizing VS Code..."
    ./scripts/optimize_vscode_cpu.sh --auto

    # Verify optimization
    sleep 5
    NEW_VS_CODE_CPU=$(./scripts/diagnose_cpu_usage.sh --json | jq -r '.summary.vscode_cpu')
    echo "VS Code CPU after optimization: $NEW_VS_CODE_CPU%"
fi

# 4. System optimization
if (( $(echo "$SYSTEM_LOAD > 2.0" | bc -l) )); then
    echo "⚙️  Applying system optimizations..."
    sudo ./scripts/apply_system_optimizations.sh

    # Verify system load after optimization
    sleep 10
    NEW_SYSTEM_LOAD=$(uptime | awk '{print $(NF-2)}' | tr -d ',')
    echo "System load after optimization: $NEW_SYSTEM_LOAD"
fi

# 5. Start continuous monitoring if high usage persists
if (( $(echo "$VS_CODE_CPU > 25" | bc -l) )) || (( $(echo "$SYSTEM_LOAD > 1.5" | bc -l) )); then
    echo "📊 Starting continuous CPU monitoring..."
    ./scripts/monitor_cpu_continuous.sh --daemon --interval 60
fi

echo "✅ CPU optimization procedure completed"
```

#### System Performance Tuning

```bash
#!/bin/bash
# scripts/performance_optimization.sh

echo "⚡ Performance Optimization - $(date)"
echo "===================================="

# 1. Docker optimization
echo "🐳 Docker Optimization:"

# Set resource limits
cat >> /etc/docker/daemon.json << EOF
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl restart docker

# 2. System optimization
echo "💻 System Optimization:"

# Apply comprehensive system optimizations
sudo ./scripts/apply_system_optimizations.sh --verbose

# Optimize network settings
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 16777216' >> /etc/sysctl.conf

sysctl -p

# 3. Database optimization
echo "🗄️  Database Optimization:"

# Optimize PostgreSQL settings
docker-compose exec timescaledb psql -U trading_user -d trading_db -c "
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
SELECT pg_reload_conf();
"

# 4. Application optimization
echo "🤖 Application Optimization:"

# Update trading bot configuration for performance
cat > config/performance.yaml << EOF
performance:
  max_concurrent_trades: 10
  worker_pool_size: 20
  cache_ttl: 300
  connection_pool_size: 20
  request_timeout: 30
EOF

# Restart with new configuration
docker-compose restart trading-bot

# 5. CPU-specific optimizations
echo "🔧 CPU-specific optimizations:"

# Set CPU governor to performance
for cpu_dir in /sys/devices/system/cpu/cpu*/cpufreq; do
    if [ -w "$cpu_dir/scaling_governor" ]; then
        echo performance | sudo tee "$cpu_dir/scaling_governor"
    fi
done

# Optimize VS Code settings
./scripts/optimize_vscode_cpu.sh --auto --no-backup

# 6. Monitoring setup
echo "📊 Setting up performance monitoring:"

# Create performance recording rules
cat > config/prometheus/performance_rules.yml << EOF
groups:
  - name: performance.recording.rules
    interval: 30s
    rules:
      - record: trading_bot:trades_per_second
        expr: rate(trading_bot_trades_total[5m])

      - record: trading_bot:api_request_rate
        expr: rate(http_requests_total{job="trading-bot"}[5m])

      - record: system:cpu_usage_percent
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

      - record: vscode:cpu_usage_percent
        expr: 100 * (process_cpu_seconds_total{process_name="code"} /
              (process_cpu_seconds_total{process_name="code"} +
               process_cpu_seconds_total{process_name="code",mode="idle"}))

      - record: system:load_per_cpu
        expr: node_load1 / count by (instance) (node_cpu_seconds_total{mode="idle"})
EOF

echo "✅ Performance optimization completed - $(date)"
```

### Capacity Planning

```bash
#!/bin/bash
# scripts/capacity_planning.sh

echo "📈 Capacity Planning Analysis - $(date)"
echo "======================================"

# 1. Resource utilization analysis
echo "📊 Current Resource Utilization:"

# CPU utilization
avg_cpu=$(awk '/cpu /{usage=($2+$4)*100/($2+$4+$5)} END {print usage}' /proc/stat)
echo "Average CPU usage: ${avg_cpu}%"

# Memory utilization
mem_used=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
echo "Memory usage: ${mem_used}%"

# Disk utilization
disk_used=$(df / | awk 'NR==2{print $3/$2 * 100.0}')
echo "Disk usage: ${disk_used}%"

# Network utilization
rx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $2}')
tx_bytes=$(cat /proc/net/dev | grep eth0 | awk '{print $10}')
echo "Network RX: ${rx_bytes} bytes, TX: ${tx_bytes} bytes"

# 2. Growth projections
echo -e "\n📅 Growth Projections (30 days):"

# Trade volume growth
current_trades=$(curl -s http://localhost:8082/metrics | grep "trades_total" | awk '{print $2}')
projected_trades=$(echo "$current_trades * 1.2" | bc)
echo "Current trades: $current_trades"
echo "Projected trades (30 days): $projected_trades"

# Storage growth
current_storage=$(df / | awk 'NR==2{print $3}')
projected_storage=$(echo "$current_storage * 1.1" | bc)
echo "Current storage usage: ${current_storage}KB"
echo "Projected storage (30 days): ${projected_storage}KB"

# 3. Bottleneck analysis
echo -e "\n⚠️  Potential Bottlenecks:"

# Check for high CPU usage
if (( $(echo "$avg_cpu > 70" | bc -l) )); then
    echo "- CPU usage is high (${avg_cpu}%)"
fi

# Check for high memory usage
if (( $(echo "$mem_used > 80" | bc -l) )); then
    echo "- Memory usage is high (${mem_used}%)"
fi

# Check for high disk usage
if (( $(echo "$disk_used > 85" | bc -l) )); then
    echo "- Disk usage is high (${disk_used}%)"
fi

# 4. Recommendations
echo -e "\n💡 Recommendations:"

# CPU recommendations
if (( $(echo "$avg_cpu > 70" | bc -l) )); then
    echo "- Consider CPU upgrade or load balancing"
    echo "- Optimize trading algorithms"
fi

# Memory recommendations
if (( $(echo "$mem_used > 80" | bc -l) )); then
    echo "- Consider memory upgrade"
    echo "- Optimize memory usage in application"
fi

# Storage recommendations
if (( $(echo "$disk_used > 85" | bc -l) )); then
    echo "- Plan storage expansion"
    echo "- Implement log rotation"
fi

echo "✅ Capacity planning analysis completed - $(date)"
```

---

## Emergency Procedures

### Complete System Recovery

```bash
#!/bin/bash
# scripts/emergency_recovery.sh

echo "🚨 EMERGENCY RECOVERY PROCEDURE - $(date)"
echo "======================================"
echo "This script will perform a complete system recovery"
echo "from the most recent available backup."

read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Emergency recovery cancelled"
    exit 1
fi

# 1. Alert stakeholders
echo "📢 Alerting stakeholders..."
echo "EMERGENCY: Trading bot system recovery initiated at $(date)" | \
    mail -s "EMERGENCY - Trading Bot Recovery" admin@trading-bot.local,team@trading-bot.local

# 2. Create system snapshot
echo "📸 Creating system snapshot..."
mkdir -p "/tmp/emergency_snapshot_$(date +%Y%m%d_%H%M%S)"
cp -r /root/mojo-trading-bot "/tmp/emergency_snapshot_$(date +%Y%m%d_%H%M%S)/"

# 3. Stop all services
echo "⏹️  Stopping all services..."
docker-compose down --remove-orphans

# 4. Find latest backup
echo "🔍 Finding latest backup..."
LATEST_BACKUP=$(ls -t /root/backups/trading-bot/*.tar.gz | head -1 | grep -o '[0-9]\{8\}_[0-9]\{6\}')
echo "Using backup: $LATEST_BACKUP"

if [ -z "$LATEST_BACKUP" ]; then
    echo "❌ No backup found!"
    echo "Manual intervention required"
    exit 1
fi

# 5. Perform disaster recovery
echo "🔄 Starting disaster recovery..."
./scripts/disaster_recovery.sh "$LATEST_BACKUP"

# 6. Verify system integrity
echo "✅ Verifying system integrity..."

# Check all services
sleep 120
docker-compose ps

# Verify API endpoints
./scripts/verify_api_health.sh

# Verify database integrity
docker-compose exec trading-bot psql -h timescaledb -U trading_user -d trading_db -c "
SELECT
    (SELECT COUNT(*) FROM trades) as trade_count,
    (SELECT COUNT(*) FROM positions) as position_count,
    (SELECT COUNT(*) FROM market_data) as market_data_count;
"

# 7. Performance verification
echo "⚡ Verifying performance..."

# Test trading functionality
curl -X POST http://localhost:8082/api/test-trade \
    -H "Content-Type: application/json" \
    -d '{"test": true}' || echo "Trading test failed"

# Test monitoring
curl -s http://localhost:9090/api/v1/query?query=up | jq -r '.data.result[].value[1]' | grep -q "1" || echo "Monitoring test failed"

# 8. Final verification
echo "🎯 Final verification..."

# Generate recovery report
cat > "/tmp/recovery_report_$(date +%Y%m%d_%H%M%S).txt" << EOF
Emergency Recovery Report
========================
Date: $(date)
Backup Used: $LATEST_BACKUP
Services Status: $(docker-compose ps | grep -c "Up")
API Status: $(curl -s http://localhost:8082/health | jq -r '.status' || echo "unknown")
Database Status: $(docker-compose exec timescaledb pg_isready -U trading_user || echo "failed")

Next Steps:
1. Monitor system performance closely
2. Verify all trading functions
3. Check data consistency
4. Update documentation
5. Schedule root cause analysis
EOF

# 9. Notify completion
echo "✅ Emergency recovery completed"
echo "📄 Recovery report generated"

# Send completion notification
echo "EMERGENCY RECOVERY COMPLETED at $(date)" | \
    mail -s "RECOVERY COMPLETE - Trading Bot" admin@trading-bot.local,team@trading-bot.local

echo "📋 Post-recovery checklist:"
echo "1. Monitor system performance for 24 hours"
echo "2. Verify all trading data integrity"
echo "3. Update incident documentation"
echo "4. Schedule post-mortem meeting"
echo "5. Review and improve recovery procedures"
```

### Service-Specific Emergency Procedures

#### Trading Bot Emergency Stop

```bash
#!/bin/bash
# scripts/emergency_stop_trading.sh

echo "🛑 EMERGENCY TRADING STOP - $(date)"
echo "==============================="

# 1. Immediate trading halt
echo "⏹️  Halting all trading activity..."
curl -X POST http://localhost:8082/api/emergency-stop \
    -H "Content-Type: application/json" \
    -d '{"reason": "emergency_stop"}'

# 2. Close all positions
echo "📊 Closing all open positions..."
curl -X POST http://localhost:8082/api/close-all-positions \
    -H "Content-Type: application/json" \
    -d '{"force": true}'

# 3. Stop trading bot service
echo "🤖 Stopping trading bot service..."
docker-compose stop trading-bot

# 4. Preserve current state
echo "💾 Preserving current state..."
docker-compose exec trading-bot python -c "
import json
import redis
r = redis.Redis()
state = {
    'emergency_stop_time': '$(date)',
    'active_positions': r.get('active_positions'),
    'last_trade': r.get('last_trade'),
    'portfolio_value': r.get('portfolio_value')
}
with open('/tmp/emergency_state.json', 'w') as f:
    json.dump(state, f, indent=2)
print('State preserved')
"

echo "✅ Emergency trading stop completed"
echo "📋 Next steps:"
echo "1. Investigate cause of emergency"
echo "2. Verify system integrity"
echo "3. Document incident"
echo "4. Plan recovery procedures"
```

#### Database Emergency Procedures

```bash
#!/bin/bash
# scripts/emergency_database_procedures.sh

echo "🗄️  DATABASE EMERGENCY PROCEDURES - $(date)"
echo "======================================"

ACTION="$1"

case "$ACTION" in
    "backup")
        echo "💾 Emergency database backup..."
        docker-compose exec timescaledb pg_dump -U trading_user trading_db | gzip > "/tmp/emergency_db_backup_$(date +%Y%m%d_%H%M%S).sql.gz"
        echo "Emergency backup completed"
        ;;
    "restore")
        BACKUP_FILE="$2"
        echo "🔄 Emergency database restore..."
        if [ -z "$BACKUP_FILE" ]; then
            echo "Usage: $0 restore <backup_file>"
            exit 1
        fi
        gunzip -c "$BACKUP_FILE" | docker-compose exec -T timescaledb psql -U trading_user trading_db
        echo "Database restored from $BACKUP_FILE"
        ;;
    "check")
        echo "🔍 Database integrity check..."
        docker-compose exec timescaledb psql -U trading_user -d trading_db -c "
        SELECT
            schemaname,
            tablename,
            n_tup_ins as inserts,
            n_tup_upd as updates,
            n_tup_del as deletes,
            n_live_tup as live_tuples,
            n_dead_tup as dead_tuples
        FROM pg_stat_user_tables;
        "
        ;;
    "repair")
        echo "🔧 Database repair..."
        docker-compose exec timescaledb psql -U trading_user -d trading_db -c "
        REINDEX DATABASE trading_db;
        VACUUM FULL ANALYZE;
        "
        echo "Database repair completed"
        ;;
    *)
        echo "Usage: $0 <backup|restore|check|repair> [backup_file]"
        exit 1
        ;;
esac
```

#### Port Conflict Emergency Procedures

```bash
#!/bin/bash
# scripts/emergency_port_procedures.sh

echo "🚨 PORT CONFLICT EMERGENCY PROCEDURES - $(date)"
echo "=========================================="

ACTION="$1"
PORT="$2"

if [ -z "$ACTION" ]; then
    echo "Usage: $0 <diagnose|force-kill|reconfigure|emergency-recovery> [port]"
    exit 1
fi

case "$ACTION" in
    "diagnose")
        echo "🔍 Emergency Port Diagnosis:"
        if [ -n "$PORT" ]; then
            ./scripts/diagnose_port_conflict.sh --port "$PORT" --verbose
        else
            ./scripts/diagnose_port_conflict.sh --verbose
        fi
        ;;

    "force-kill")
        if [ -z "$PORT" ]; then
            echo "❌ Port number required for force-kill"
            exit 1
        fi
        echo "🔫 Force-killing processes on port $PORT:"

        # Find and kill processes
        PIDS=$(lsof -ti :$PORT)
        if [ -n "$PIDS" ]; then
            echo "Found processes: $PIDS"
            for PID in $PIDS; do
                echo "Killing process $PID..."
                sudo kill -TERM "$PID" 2>/dev/null || true
                sleep 2
                # Force kill if still running
                if kill -0 "$PID" 2>/dev/null; then
                    echo "Force-killing process $PID..."
                    sudo kill -KILL "$PID" 2>/dev/null || true
                fi
            done
            echo "✅ Processes on port $PORT terminated"
        else
            echo "No processes found on port $PORT"
        fi
        ;;

    "reconfigure")
        if [ -z "$PORT" ]; then
            echo "❌ Port number required for reconfiguration"
            exit 1
        fi
        echo "⚙️  Emergency port reconfiguration for port $PORT:"

        # Backup current config
        cp .env .env.backup.$(date +%Y%m%d_%H%M%S)

        # Update port configuration
        case "$PORT" in
            5432)
                NEW_PORT=5433
                sed -i "s/TIMESCALEDB_PORT=.*/TIMESCALEDB_PORT=$NEW_PORT/" .env
                echo "TimescaleDB port changed to $NEW_PORT"
                ;;
            3000)
                NEW_PORT=3001
                echo "Grafana port needs manual update in docker-compose.yml"
                ;;
            9090)
                NEW_PORT=9091
                echo "Prometheus port needs manual update in docker-compose.yml"
                ;;
            *)
                echo "Port $PORT reconfiguration not automated"
                echo "Please update configuration manually"
                ;;
        esac

        # Restart services
        echo "🔄 Restarting services..."
        docker-compose down
        docker-compose up -d

        echo "✅ Port reconfiguration completed"
        ;;

    "emergency-recovery")
        echo "🚨 Emergency Port Recovery:"

        # Check all critical ports
        echo "Checking critical ports..."
        for port in 5432 3000 9090 8082; do
            if ! ./scripts/verify_port_availability.sh --port "$port" >/dev/null 2>&1; then
                echo "❌ Port $port conflict detected"
                echo "Attempting resolution..."

                # Try graceful resolution first
                ./scripts/resolve_port_conflict.sh --port "$port" --automatic

                # If still failed, force kill
                if ! ./scripts/verify_port_availability.sh --port "$port" >/dev/null 2>&1; then
                    echo "Force-killing processes on port $port..."
                    $0 force-kill "$port"
                fi

                # Reconfigure if still failed
                if ! ./scripts/verify_port_availability.sh --port "$port" >/dev/null 2>&1; then
                    echo "Reconfiguring port $port..."
                    $0 reconfigure "$port"
                fi
            else
                echo "✅ Port $port available"
            fi
        done

        # Restart all services
        echo "🔄 Restarting all services..."
        docker-compose restart

        # Verify all services
        echo "✅ Verifying service health..."
        sleep 30
        ./scripts/verify_api_health.sh

        echo "🎉 Emergency port recovery completed"
        ;;

    *)
        echo "Usage: $0 <diagnose|force-kill|reconfigure|emergency-recovery> [port]"
        exit 1
        ;;
esac
```

#### Monitoring Stack Emergency Recovery

```bash
#!/bin/bash
# scripts/emergency_monitoring_recovery.sh

echo "📊 MONITORING STACK EMERGENCY RECOVERY - $(date)"
echo "=============================================="

# 1. Diagnose monitoring stack issues
echo "🔍 Diagnosing monitoring stack..."
./scripts/verify_monitoring_stack.sh --detailed

# 2. Stop all monitoring services
echo "⏹️  Stopping monitoring services..."
docker-compose stop prometheus grafana alertmanager node-exporter

# 3. Check for configuration corruption
echo "🔍 Checking monitoring configurations..."
docker-compose config --services | grep -E "(prometheus|grafana|alertmanager|node-exporter)"

# 4. Clear corrupted data if needed
echo "🧹 Clearing potentially corrupted data..."
docker volume ls | grep -E "(prometheus|grafana)" | awk '{print $2}' | while read volume; do
    echo "Checking volume: $volume"
    docker volume inspect "$volume" >/dev/null 2>&1 && echo "Volume $volume OK"
done

# 5. Restart monitoring stack in correct order
echo "🔄 Restarting monitoring stack..."
./scripts/start_monitoring_stack.sh

# 6. Verify recovery
echo "✅ Verifying monitoring stack recovery..."
sleep 30
./scripts/verify_monitoring_stack.sh

# 7. Import dashboards if missing
echo "📊 Checking dashboard availability..."
dashboard_count=$(curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq 'length')
if [ "$dashboard_count" -lt 5 ]; then
    echo "Re-importing dashboards..."
    ./scripts/import_grafana_dashboards.sh --force
fi

# 8. Test alert delivery
echo "🚨 Testing alert delivery..."
curl -XPOST http://localhost:9093/api/v1/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {
    "alertname": "EmergencyRecoveryTest",
    "severity": "info",
    "instance": "test"
  },
  "annotations": {
    "summary": "Emergency recovery test alert",
    "description": "Testing alert delivery after emergency recovery"
  }
}]'

echo "🎉 Monitoring stack emergency recovery completed"
echo "📋 Post-recovery checklist:"
echo "1. Verify all monitoring services are running"
echo "2. Check dashboards are loading data"
echo "3. Confirm alerts are being delivered"
echo "4. Test metric collection from all targets"
echo "5. Document recovery incident"
```

---

## Contact Information and Escalation

### Primary Contacts

| Role | Contact | Availability |
|------|---------|---------------|
| **System Administrator** | admin@trading-bot.local | 24/7 |
| **Development Team** | dev@trading-bot.local | Business hours |
| **Security Team** | security@trading-bot.local | 24/7 for security incidents |
| **Management** | management@trading-bot.local | Business hours |

### Escalation Procedures

1. **Level 1** (0-30 minutes): System Administrator
2. **Level 2** (30+ minutes): Development Team
3. **Level 3** (Critical): Security Team + Management

### External Services

| Service | Contact | Purpose |
|---------|---------|---------|
| **DragonflyDB Support** | support@dragonflydb.com | Database issues |
| **VPS Provider** | support@vps-provider.com | Hardware/network issues |
| **API Providers** | Various | External API issues |

---

## Conclusion

This comprehensive operations runbook provides:

- **Step-by-step procedures** for all operational scenarios
- **Emergency response protocols** for critical incidents
- **Daily, weekly, and monthly maintenance procedures**
- **Troubleshooting guides** for common issues
- **Security procedures** and incident response
- **Performance optimization** and capacity planning
- **Backup and recovery** procedures
- **Complete emergency recovery** processes

The runbook ensures consistent, reliable operations of the MojoRust Trading Bot while minimizing downtime and maximizing system reliability.

**Regular Updates:**
- Review and update this runbook monthly
- Test all procedures quarterly
- Update contact information as needed
- Document lessons learned from incidents

**Final Note**: Always prioritize system stability and data integrity. When in doubt, follow the conservative approach and escalate to senior team members.