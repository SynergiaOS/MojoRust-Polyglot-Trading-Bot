# Monitoring Stack Deployment Guide

## Overview

The MojoRust Trading Bot includes a comprehensive monitoring infrastructure with Prometheus for metrics collection, Grafana for visualization, Node Exporter for system metrics, and AlertManager for alert routing. This guide covers deployment, configuration, verification, and management of the monitoring stack.

### Architecture Components

- **Prometheus** (port 9090): Metrics collection and storage with 30-day retention
- **Grafana** (port 3001): Visualization dashboards with auto-provisioning
- **Node Exporter** (port 9100): System metrics collection from the host
- **AlertManager** (port 9093): Alert routing and notification management
- **cAdvisor** (port 8080): Container metrics collection
- **Trading Bot Metrics** (port 8082): Application metrics from the trading bot

## Prerequisites

### System Requirements

- Docker 24.0+ and Docker Compose installed
- Ports 9090, 3001, 9100, 9093, 8083 available
- Minimum 2GB RAM for monitoring stack
- 10GB+ disk space for Prometheus data (30-day retention)
- Network connectivity between containers

### Configuration Files Required

- `docker-compose.yml`: Service definitions and networking
- `config/prometheus.yml`: Prometheus scrape configurations
- `config/grafana/provisioning/datasources/datasources.yml`: Grafana datasources
- `config/grafana/provisioning/dashboards/dashboards.yml`: Dashboard auto-provisioning
- `config/grafana/dashboards/*.json`: Dashboard definitions

## Quick Start

### Automated Deployment

```bash
# Start the complete monitoring stack
./scripts/start_monitoring_stack.sh

# Verify all services are operational
./scripts/verify_monitoring_stack.sh

# Access dashboards
# Grafana: http://localhost:3001 (admin/trading_admin)
# Prometheus: http://localhost:9090
```

### Manual Deployment

#### Step 1: Verify Configuration

Check that all configuration files exist and are valid:

```bash
# Verify docker-compose.yml
docker-compose config >/dev/null && echo "✅ docker-compose.yml is valid"

# Verify Prometheus configuration
docker run --rm -v $(pwd)/config/prometheus.yml:/etc/prometheus/prometheus.yml prom/prometheus:latest promtool check config /etc/prometheus/prometheus.yml

# Verify Grafana provisioning files
jq . config/grafana/provisioning/datasources/datasources.yml >/dev/null && echo "✅ Datasources config is valid"
jq . config/grafana/provisioning/dashboards/dashboards.yml >/dev/null && echo "✅ Dashboards config is valid"
```

#### Step 2: Start Prometheus

```bash
# Start Prometheus service
docker-compose up -d prometheus

# Wait for health check
sleep 10

# Verify Prometheus is running
docker-compose ps prometheus

# Check Prometheus is accessible
curl -f http://localhost:9090/-/healthy && echo "✅ Prometheus is healthy"

# Verify configuration is loaded
curl -s http://localhost:9090/api/v1/status/config | jq -r '.status' | grep -q "success" && echo "✅ Configuration loaded successfully"
```

#### Step 3: Start Grafana

```bash
# Start Grafana (depends on Prometheus)
docker-compose up -d grafana

# Wait for Grafana to be ready
sleep 15

# Verify Grafana is running
docker-compose ps grafana

# Check Grafana health
curl -f http://localhost:3001/api/health && echo "✅ Grafana is healthy"

# Test authentication
curl -f -u admin:trading_admin http://localhost:3001/api/org && echo "✅ Authentication successful"

# Verify datasources are provisioned
datasource_count=$(curl -s -u admin:trading_admin http://localhost:3001/api/datasources | jq 'length')
echo "✅ $datasource_count datasources provisioned"

# Verify dashboards are loaded
dashboard_count=$(curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq 'length')
echo "✅ $dashboard_count dashboards loaded"
```

#### Step 4: Start Node Exporter

```bash
# Start Node Exporter
docker-compose up -d node-exporter

# Verify Node Exporter is running
docker-compose ps node-exporter

# Check metrics endpoint
curl -f http://localhost:9100/metrics >/dev/null && echo "✅ Node Exporter is accessible"

# Verify metrics collection
metrics_count=$(curl -s http://localhost:9100/metrics | grep -c "^node_")
echo "✅ Node Exporter collecting $metrics_count system metrics"
```

#### Step 5: Start AlertManager

```bash
# Start AlertManager
docker-compose up -d alertmanager

# Verify AlertManager is running
docker-compose ps alertmanager

# Check AlertManager health
curl -f http://localhost:9093/-/healthy && echo "✅ AlertManager is healthy"

# Verify AlertManager configuration
curl -s http://localhost:9093/api/v1/status | jq -r '.data.cluster.status' | grep -q "ready" && echo "✅ AlertManager is ready"
```

## Verification

### Automated Verification

Run the comprehensive verification script:

```bash
# Full verification
./scripts/verify_monitoring_stack.sh

# Detailed output
./scripts/verify_monitoring_stack.sh --detailed

# JSON output for automation
./scripts/verify_monitoring_stack.sh --json

# Check specific service
./scripts/verify_monitoring_stack.sh --check=prometheus
./scripts/verify_monitoring_stack.sh --check=grafana
```

### Manual Verification

#### Prometheus Verification

1. **Check Prometheus UI**: Navigate to http://localhost:9090
   - Status should show "Ready" and "Healthy"
   - Click "Status" → "Targets" to verify all targets are "UP"

2. **Verify Targets**:
   ```bash
   # List all targets
   curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

   # Check specific targets
   curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health=="up") | .labels.job'
   ```

3. **Verify Metrics Collection**:
   ```bash
   # Check trading bot metrics
   curl -s "http://localhost:9090/api/v1/query?query=trading_bot_cpu_usage" | jq '.data.result | length'

   # Check system metrics
   curl -s "http://localhost:9090/api/v1/query?query=node_cpu_seconds_total" | jq '.data.result | length'

   # List all metric names
   curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data | length'
   ```

#### Grafana Verification

1. **Access Grafana**: Navigate to http://localhost:3001
   - Login with credentials: admin/trading_admin
   - Should see "Trading Bot" folder in dashboards

2. **Check Data Sources**:
   ```bash
   # List datasources
   curl -s -u admin:trading_admin http://localhost:3001/api/datasources | jq -r '.[] | "\(.name): \(.type)"'

   # Test Prometheus datasource
   curl -s -u admin:trading_admin http://localhost:3001/api/datasources/proxy/1/api/v1/query?query=up | jq '.data.result | length'
   ```

3. **Verify Dashboards**:
   ```bash
   # List all dashboards
   curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq -r '.[] | "\(.title) - \(.uid)"'

   # Expected dashboards:
   # - System Health
   # - Trading Performance
   # - API Metrics
   # - Data Ingestion
   # - Arbitrage Dashboard
   # - Sniper Dashboard
   # - Reliability Metrics
   ```

4. **Test Dashboard Functionality**:
   - Open "System Health Dashboard"
   - Verify panels show data (not "No Data")
   - Check time range selector works
   - Verify refresh functionality

#### Node Exporter Verification

```bash
# Check Node Exporter metrics
curl -s http://localhost:9100/metrics | head -20

# Verify key metrics
curl -s http://localhost:9100/metrics | grep -E "node_cpu_seconds_total|node_memory_MemTotal_bytes|node_filesystem_avail_bytes"

# Check Prometheus is scraping Node Exporter
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="node-exporter") | .health'
```

## Dashboard Access

### Available Dashboards

The monitoring stack includes 7 pre-built dashboards:

#### System Health Dashboard
- **URL**: http://localhost:3001/d/system-health
- **Purpose**: Real-time system monitoring
- **Panels**: CPU usage, memory usage, error rate, network latency
- **Refresh**: 30 seconds
- **Use Case**: Monitor system resources and identify bottlenecks

#### Trading Performance Dashboard
- **URL**: http://localhost:3001/d/trading-performance
- **Purpose**: Trading strategy performance analysis
- **Panels**: Total P&L, win rate, total trades, current drawdown
- **Refresh**: 10 seconds
- **Use Case**: Track trading performance and profitability

#### API Metrics Dashboard
- **URL**: http://localhost:3001/d/api-metrics
- **Purpose**: API performance monitoring
- **Panels**: API call rates, latencies, error rates by endpoint
- **Refresh**: 15 seconds
- **Use Case**: Monitor API performance and troubleshoot issues

#### Data Ingestion Dashboard
- **URL**: http://localhost:3001/d/data-ingestion
- **Purpose**: Data pipeline monitoring
- **Panels**: Data pipeline throughput, latency, errors
- **Refresh**: 5 seconds
- **Use Case**: Monitor Geyser data consumer and Rust data pipeline

#### Arbitrage Dashboard
- **URL**: http://localhost:3001/d/arbitrage-dashboard
- **Purpose**: Arbitrage strategy monitoring
- **Panels**: Arbitrage opportunities, execution success rate, profit
- **Refresh**: 10 seconds
- **Use Case**: Track arbitrage strategy performance

#### Sniper Dashboard
- **URL**: http://localhost:3001/d/sniper-dashboard
- **Purpose**: Sniper strategy monitoring
- **Panels**: Sniper triggers, execution speed, success rate
- **Refresh**: 5 seconds
- **Use Case**: Monitor high-frequency trading strategies

#### Reliability Metrics Dashboard
- **URL**: http://localhost:3001/d/reliability-metrics
- **Purpose**: System reliability monitoring
- **Panels**: Uptime, error rates, circuit breaker status
- **Refresh**: 30 seconds
- **Use Case**: Monitor system reliability and SLA compliance

### Accessing Dashboards

1. **Navigate to Grafana**: http://localhost:3001
2. **Login**: Use credentials admin/trading_admin
3. **Browse Dashboards**:
   - Click "Dashboards" in the left sidebar
   - Select "Trading Bot" folder
   - Click on desired dashboard

### Dashboard Management

#### Manual Import (if auto-provisioning fails)

```bash
# Import all dashboards
./scripts/import_grafana_dashboards.sh

# Import specific dashboard
./scripts/import_grafana_dashboards.sh --dashboard=config/grafana/dashboards/system_health.json

# Force overwrite existing dashboards
./scripts/import_grafana_dashboards.sh --force

# Use custom folder name
./scripts/import_grafana_dashboards.sh --folder="My Dashboards"
```

#### Export Dashboards

```bash
# Export specific dashboard
curl -s -u admin:trading_admin http://localhost:3001/api/dashboards/uid/system-health | jq .dashboard > system-health-backup.json

# Export all dashboards
for uid in $(curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq -r '.[].uid'); do
    curl -s -u admin:trading_admin http://localhost:3001/api/dashboards/uid/$uid | jq .dashboard > "backup-dashboard-$uid.json"
done
```

## Metrics Collection

### Trading Bot Metrics

The trading bot exposes metrics at port 8082/metrics:

#### Performance Metrics
- `trading_bot_cpu_usage`: CPU usage percentage
- `trading_bot_memory_usage`: Memory usage percentage
- `trading_bot_error_rate`: Error rate percentage
- `trading_bot_network_latency_ms`: Network latency in milliseconds

#### Trading Metrics
- `trading_bot_total_pnl`: Total profit and loss in SOL
- `trading_bot_win_rate`: Win rate percentage
- `trading_bot_total_trades`: Total number of trades
- `trading_bot_current_drawdown`: Current drawdown percentage
- `trading_bot_active_positions`: Number of active positions

#### Strategy Metrics
- `trading_bot_signals_total`: Total trading signals generated
- `trading_bot_filters_passed`: Number of filters passed
- `trading_bot_filters_rejected`: Number of filters rejected

### System Metrics (Node Exporter)

#### CPU Metrics
- `node_cpu_seconds_total`: Total CPU time by mode
- `node_load1`: 1-minute load average
- `node_load5`: 5-minute load average
- `node_load15`: 15-minute load average

#### Memory Metrics
- `node_memory_MemTotal_bytes`: Total memory in bytes
- `node_memory_MemAvailable_bytes`: Available memory in bytes
- `node_memory_MemUsed_bytes`: Used memory in bytes
- `node_memory_SwapTotal_bytes`: Total swap in bytes

#### Disk Metrics
- `node_filesystem_size_bytes`: Filesystem size in bytes
- `node_filesystem_avail_bytes`: Available disk space in bytes
- `node_filesystem_used_bytes`: Used disk space in bytes
- `node_disk_io_time_seconds_total`: Disk I/O time

#### Network Metrics
- `node_network_receive_bytes_total`: Total bytes received
- `node_network_transmit_bytes_total`: Total bytes transmitted
- `node_network_receive_errs_total`: Total receive errors
- `node_network_transmit_errs_total`: Total transmit errors

### Container Metrics (cAdvisor)

#### Resource Usage
- `container_cpu_usage_seconds_total`: Container CPU usage
- `container_memory_usage_bytes`: Container memory usage
- `container_memory_max_usage_bytes`: Maximum memory usage
- `container_fs_usage_bytes`: Container filesystem usage

#### Network I/O
- `container_network_receive_bytes_total`: Network bytes received
- `container_network_transmit_bytes_total`: Network bytes transmitted
- `container_network_receive_packets_total`: Network packets received
- `container_network_transmit_packets_total`: Network packets transmitted

## Configuration

### Prometheus Configuration

The Prometheus configuration is in `config/prometheus.yml`:

#### Scrape Configurations

```yaml
# Global settings
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Scrape configurations
scrape_configs:
  # Trading bot metrics
  - job_name: 'trading-bot'
    static_configs:
      - targets: ['trading-bot:8082']
    scrape_interval: 10s
    metrics_path: '/metrics'

  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Node Exporter
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # Grafana
  - job_name: 'grafana'
    static_configs:
      - targets: ['grafana:3000']

  # Data Consumer
  - job_name: 'data-consumer'
    static_configs:
      - targets: ['data-consumer:9191']

  # cAdvisor
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
```

#### Adding New Targets

1. Edit `config/prometheus.yml`
2. Add new scrape job configuration
3. Restart Prometheus: `docker-compose restart prometheus`
4. Verify new target in Prometheus UI

#### Recording Rules

Create recording rules in `config/prometheus_rules/`:

```yaml
# config/prometheus_rules/trading_bot.yml
groups:
  - name: trading_bot_recording_rules
    interval: 15s
    rules:
      - record: trading_bot:cpu_usage_rate
        expr: rate(trading_bot_cpu_usage[5m])

      - record: trading_bot:error_rate_5m
        expr: increase(trading_bot_error_total[5m])
```

### Grafana Configuration

#### Datasources

Datasources are auto-provisioned from `config/grafana/provisioning/datasources/datasources.yml`:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true

  - name: TimescaleDB
    type: postgres
    url: postgresql://trading_user:trading_password@timescaledb:5432/trading_db
    database: trading_db
    user: trading_user
    password: trading_password
    sslmode: disable

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    editable: true

  - name: AlertManager
    type: alertmanager
    access: proxy
    url: http://alertmanager:9093
    editable: true
```

#### Dashboard Provisioning

Dashboards are auto-provisioned from `config/grafana/provisioning/dashboards/dashboards.yml`:

```yaml
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
```

#### Customizing Grafana

**Change Admin Credentials**:
```yaml
# In docker-compose.yml
services:
  grafana:
    environment:
      - GF_SECURITY_ADMIN_USER=your_username
      - GF_SECURITY_ADMIN_PASSWORD=your_password
```

**Install Plugins**:
```yaml
# In docker-compose.yml
services:
  grafana:
    environment:
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
```

**Custom Settings**:
```yaml
# In docker-compose.yml
services:
  grafana:
    environment:
      - GF_DEFAULT_INSTANCE_NAME=MojoRust Monitoring
      - GF_DEFAULT_THEME=light
      - GF_ANALYTICS_REPORTING_ENABLED=false
```

### Node Exporter Configuration

#### Custom Collectors

Node Exporter collectors can be customized in `docker-compose.yml`:

```yaml
services:
  node-exporter:
    command:
      - '--path.rootfs=/host'
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem'
      - '--collector.meminfo'
      - '--collector.cpu'
      - '--collector.diskstats'
      - '--collector.netdev'
      - '--collector.loadaverage'
      - '--collector.time'
      - '--collector.vmstat'
      - '--no-collector.ipvs'
      - '--no-collector.netdev'
```

#### Enable Additional Metrics

```yaml
# Add more collectors
command:
  - '--collector.systemd'
  - '--collector.processes'
  - '--collector.tcpstat'
  - '--collector.wifi'
```

## Troubleshooting

### Common Issues

#### Prometheus Issues

**Issue**: Prometheus not accessible
```bash
# Check container status
docker-compose ps prometheus

# Check logs
docker-compose logs prometheus

# Check port availability
lsof -i :9090

# Restart Prometheus
docker-compose restart prometheus
```

**Issue**: Targets showing as "DOWN"
```bash
# Check target configuration
docker exec trading-bot-prometheus cat /etc/prometheus/prometheus.yml | grep -A 10 "job_name.*trading-bot"

# Test connectivity from Prometheus
docker exec trading-bot-prometheus wget -O- http://trading-bot:8082/metrics

# Check target service status
docker-compose ps trading-bot
```

**Issue**: High memory usage
```bash
# Check Prometheus data size
docker exec trading-bot-prometheus du -sh /prometheus

# Reduce retention period
# Edit docker-compose.yml line 76
# Change --storage.tsdb.retention.time=30d to 15d

# Restart Prometheus
docker-compose restart prometheus
```

#### Grafana Issues

**Issue**: Cannot login to Grafana
```bash
# Check Grafana logs
docker-compose logs grafana | grep -i auth

# Reset admin password
docker exec trading-bot-grafana grafana-cli admin reset-admin-password newpassword

# Check environment variables
docker exec trading-bot-grafana env | grep GRAFANA_ADMIN
```

**Issue**: Dashboards not loading
```bash
# Check dashboard directory mount
docker inspect trading-bot-grafana | grep -A 10 Mounts

# Check provisioning logs
docker-compose logs grafana | grep -i dashboard

# Manual import
./scripts/import_grafana_dashboards.sh

# Check dashboard JSON syntax
jq . config/grafana/dashboards/system_health.json
```

**Issue**: No data in dashboards
```bash
# Check datasource configuration
curl -s -u admin:trading_admin http://localhost:3001/api/datasources | jq '.[] | select(.name=="Prometheus")'

# Test datasource connectivity
curl -s -u admin:trading_admin http://localhost:3001/api/datasources/proxy/1/api/v1/query?query=up

# Check Prometheus has data
curl -s http://localhost:9090/api/v1/query?query=trading_bot_cpu_usage

# Adjust dashboard time range
# Use "Last 1 hour" instead of "Last 24 hours"
```

#### Node Exporter Issues

**Issue**: No system metrics
```bash
# Check Node Exporter is running
docker-compose ps node-exporter

# Check metrics endpoint
curl -f http://localhost:9100/metrics

# Check volume mounts
docker inspect trading-bot-node-exporter | grep -A 20 Mounts

# Check permissions
docker exec trading-bot-node-exporter ls -la /host/proc
```

**Issue**: Permission errors
```bash
# Check host path permissions
ls -la /proc /sys / | head -10

# Restart with privileged mode (if needed)
# Edit docker-compose.yml to add: privileged: true
docker-compose restart node-exporter
```

### Recovery Procedures

#### Complete Reset

```bash
# Stop all monitoring services
docker-compose stop prometheus grafana node-exporter alertmanager

# Remove containers
docker-compose rm -f prometheus grafana node-exporter alertmanager

# Remove data volumes (WARNING: deletes all data)
docker volume rm trading-bot_prometheus_data trading-bot_grafana_data trading-bot_alertmanager_data

# Restart services
docker-compose up -d prometheus grafana node-exporter alertmanager

# Verify
./scripts/verify_monitoring_stack.sh
```

#### Individual Service Recovery

```bash
# Restart specific service
docker-compose restart prometheus

# Recreate service
docker-compose up -d --force-recreate prometheus

# Clear and restart
docker-compose stop prometheus
docker-compose rm -f prometheus
docker-compose up -d prometheus
```

## Maintenance

### Daily Tasks

```bash
#!/bin/bash
# daily_monitoring_maintenance.sh

echo "🔧 Daily Monitoring Maintenance - $(date)"
echo "================================"

# Check monitoring stack health
./scripts/verify_monitoring_stack.sh --json > /var/log/trading-bot/monitoring-health-$(date +%Y%m%d).json

# Check Prometheus storage usage
storage_usage=$(docker exec trading-bot-prometheus du -sh /prometheus | cut -f1)
echo "Prometheus storage usage: $storage_usage"

# Check target status
down_targets=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health!="up") | .labels.job')
if [[ -n "$down_targets" ]]; then
    echo "❌ Down targets: $down_targets"
fi

# Check Grafana dashboard health
dashboard_count=$(curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq 'length')
echo "Active dashboards: $dashboard_count"

echo "✅ Daily monitoring maintenance completed"
```

### Weekly Tasks

```bash
#!/bin/bash
# weekly_monitoring_maintenance.sh

echo "🔧 Weekly Monitoring Maintenance - $(date)"
echo "================================="

# Backup Grafana dashboards
echo "📊 Backing up Grafana dashboards..."
mkdir -p backups/grafana
for uid in $(curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq -r '.[].uid'); do
    curl -s -u admin:trading_admin http://localhost:3001/api/dashboards/uid/$uid | jq .dashboard > "backups/grafana/dashboard-$uid-$(date +%Y%m%d).json"
done

# Review Prometheus targets
echo "🎯 Reviewing Prometheus targets..."
down_targets=$(curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.health!="up")')
if [[ $(echo "$down_targets" | jq 'length') -gt 0 ]]; then
    echo "❌ Targets with issues:"
    echo "$down_targets" | jq -r '.labels.job + " (" + .health + ")"'
fi

# Check AlertManager alerts
echo "🚨 Checking AlertManager status..."
alert_count=$(curl -s http://localhost:9093/api/v2/alerts | jq 'length')
echo "Active alerts: $alert_count"

# Review dashboard usage
echo "📈 Dashboard usage review..."
curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq -r '.[] | "\(.title): \(.views) views"'

echo "✅ Weekly monitoring maintenance completed"
```

### Monthly Tasks

```bash
#!/bin/bash
# monthly_monitoring_maintenance.sh

echo "🔧 Monthly Monitoring Maintenance - $(date)"
echo "================================="

# Review Prometheus retention and storage
echo "💾 Prometheus storage review..."
prometheus_size=$(docker exec trading-bot-prometheus du -sh /prometheus | cut -f1)
echo "Current Prometheus data size: $prometheus_size"

# Update Grafana plugins
echo "🔌 Updating Grafana plugins..."
docker exec trading-bot-grafana grafana-cli plugins update-all || echo "Plugin update completed"

# Audit dashboard usage
echo "📊 Dashboard usage audit..."
curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq -r '.[] | "\(.title): \(.views) views"' | sort -k2 -nr

# Check recording rules performance
echo "⚡ Recording rules review..."
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.type=="recording") | {name: .name, health: .health}'

# Backup Prometheus configuration
echo "📋 Backing up Prometheus configuration..."
mkdir -p backups/prometheus
docker exec trading-bot-prometheus cp /etc/prometheus/prometheus.yml /tmp/prometheus.yml.backup
docker cp trading-bot-prometheus:/tmp/prometheus.yml.backup "backups/prometheus/prometheus-config-$(date +%Y%m%d).yml"

echo "✅ Monthly monitoring maintenance completed"
```

## Integration

### Trading Bot Integration

The monitoring stack is fully integrated with the trading bot:

1. **Metrics Endpoint**: Trading bot exposes metrics at `/metrics` (port 8082)
2. **Health Checks**: Trading bot includes `/health` endpoint for monitoring
3. **Alerting**: Critical trading bot metrics can trigger alerts
4. **Dashboard Context**: Trading-specific dashboards show relevant metrics

### External Systems Integration

#### TimescaleDB Integration

Grafana can query TimescaleDB directly for historical trading data:

```sql
-- Example query for Grafana
SELECT
    time_bucket('1 hour', timestamp) as hour,
    SUM(profit_loss) as total_pnl,
    COUNT(*) as trade_count,
    AVG(profit_loss) as avg_pnl
FROM trades
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY hour
ORDER BY hour;
```

#### AlertManager Integration

AlertManager can send notifications to multiple channels:

```yaml
# alertmanager.yml
global:
  smtp_smarthost: localhost:587
  smtp_from: alerts@trading-bot.local

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
  - name: 'web.hook'
    email_configs:
      - to: 'admin@trading-bot.local'
    slack_configs:
      - api_url: 'http://localhost:8093/'
```

## Best Practices

### Performance Optimization

1. **Prometheus Optimization**:
   - Use appropriate scrape intervals (10s for trading, 15s for system)
   - Implement recording rules for frequently used queries
   - Monitor TSDB size and adjust retention as needed
   - Use appropriate metric labels to avoid high cardinality

2. **Grafana Optimization**:
   - Use appropriate refresh intervals (5-30s)
   - Implement template variables for flexible dashboards
   - Use panel grouping and row organization
   - Limit time range queries to reasonable periods

3. **Dashboard Design**:
   - Keep dashboards focused on specific use cases
   - Use consistent color schemes and layouts
   - Include helpful descriptions and annotations
   - Test dashboard performance with real data

### Security Considerations

1. **Access Control**:
   - Change default Grafana credentials
   - Use strong passwords for all services
   - Limit network access to monitoring services
   - Use HTTPS in production environments

2. **Data Protection**:
   - Regular backups of Grafana dashboards and configurations
   - Sensitive data should not be exposed in metrics
   - Use secure authentication methods
   - Audit dashboard access and modifications

3. **Network Security**:
   - Use internal networks where possible
   - Implement firewall rules for monitoring ports
   - Use VPN for remote access
   - Monitor for unauthorized access attempts

## Documentation and References

### Configuration Files

- `docker-compose.yml`: Service definitions (lines 67-324)
- `config/prometheus.yml`: Prometheus configuration
- `config/grafana/provisioning/datasources/datasources.yml`: Grafana datasources
- `config/grafana/provisioning/dashboards/dashboards.yml`: Dashboard auto-provisioning
- `config/grafana/dashboards/*.json`: Dashboard definitions
- `config/prometheus_rules/*.yml`: Alert and recording rules

### Scripts

- `scripts/start_monitoring_stack.sh`: Start monitoring services
- `scripts/verify_monitoring_stack.sh`: Verify monitoring health
- `scripts/import_grafana_dashboards.sh`: Manual dashboard import

### Documentation

- `OPERATIONS_RUNBOOK.md`: Operational procedures
- `docs/monitoring_troubleshooting_guide.md`: Troubleshooting guide
- Official Prometheus documentation: https://prometheus.io/docs/
- Official Grafana documentation: https://grafana.com/docs/
- Node Exporter documentation: https://github.com/prometheus/node_exporter

### Support

For monitoring-related issues:
1. Check this guide first
2. Review troubleshooting guide
3. Check service logs
4. Verify configurations
5. Contact the monitoring team

---

**Version**: 1.0
**Last Updated**: 2025-01-15
**Related Documents**: [OPERATIONS_RUNBOOK.md](../OPERATIONS_RUNBOOK.md), [monitoring_troubleshooting_guide.md](monitoring_troubleshooting_guide.md)