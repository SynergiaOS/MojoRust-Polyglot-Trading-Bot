# Monitoring Stack Troubleshooting Guide
## MojoRust Trading Bot - Complete Monitoring Issue Resolution

---

## Overview

This troubleshooting guide provides comprehensive procedures for diagnosing and resolving issues with the MojoRust Trading Bot monitoring stack, including Prometheus, Grafana, AlertManager, Node Exporter, and associated components.

**Monitoring Stack Components:**
- **Prometheus** (port 9090): Metrics collection and storage
- **Grafana** (port 3001): Visualization dashboards
- **AlertManager** (port 9093): Alert routing and notifications
- **Node Exporter** (port 9100): System metrics collection
- **Docker Exporter** (port 9323): Container metrics
- **Trading Bot Metrics** (port 8082): Application metrics

---

## Table of Contents

1. [Quick Diagnostics](#quick-diagnostics)
2. [Service-Specific Issues](#service-specific-issues)
3. [Common Problems](#common-problems)
4. [Performance Issues](#performance-issues)
5. [Data Issues](#data-issues)
6. [Network Issues](#network-issues)
7. [Configuration Issues](#configuration-issues)
8. [Emergency Procedures](#emergency-procedures)

---

## Quick Diagnostics

### Health Check Commands

```bash
# Run comprehensive monitoring stack verification
./scripts/verify_monitoring_stack.sh

# Check service status
docker-compose ps prometheus grafana alertmanager node-exporter

# Quick health checks
curl -s http://localhost:9090/-/healthy && echo "✅ Prometheus OK"
curl -s http://localhost:3001/api/health && echo "✅ Grafana OK"
curl -s http://localhost:9093/-/healthy && echo "✅ AlertManager OK"
curl -s http://localhost:9100/metrics | head -1 && echo "✅ Node Exporter OK"
```

### Verification Scripts

```bash
# Detailed monitoring stack analysis
./scripts/verify_monitoring_stack.sh --detailed

# JSON output for automation
./scripts/verify_monitoring_stack.sh --json

# Check specific service
./scripts/start_monitoring_stack.sh --service=prometheus
./scripts/start_monitoring_stack.sh --service=grafana
```

---

## Service-Specific Issues

### 1. Prometheus Issues

#### Problem: Prometheus Not Starting

**Symptoms:**
- Container exits immediately
- Port 9090 not accessible
- `docker-compose ps` shows "Restarting" status

**Diagnosis:**
```bash
# Check container logs
docker-compose logs prometheus

# Check configuration syntax
docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Check port availability
lsof -i :9090
netstat -tlnp | grep 9090

# Check disk space
df -h /var/lib/prometheus
```

**Solutions:**
```bash
# Fix configuration errors
docker-compose exec prometheus cat /etc/prometheus/prometheus.yml
# Edit config and restart
docker-compose restart prometheus

# Clear corrupted data
docker-compose stop prometheus
docker volume rm trading-bot_prometheus_data
docker-compose up -d prometheus

# Fix permissions
docker-compose exec prometheus chown -R 65534:65534 /prometheus
```

#### Problem: Prometheus Not Collecting Metrics

**Symptoms:**
- Prometheus UI shows "up" metric as 0 for targets
- Dashboards show "No Data"
- `scrape_duration_seconds` metrics missing

**Diagnosis:**
```bash
# Check target status
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'

# Test endpoint connectivity
curl -s http://localhost:8082/metrics | head -5
curl -s http://localhost:9100/metrics | head -5

# Check network connectivity from Prometheus container
docker-compose exec prometheus wget -qO- http://trading-bot-app:8082/metrics | head -3
```

**Solutions:**
```bash
# Restart services with connectivity issues
docker-compose restart trading-bot
docker-compose restart node-exporter

# Update Prometheus configuration
docker-compose exec prometheus cat /etc/prometheus/prometheus.yml
# Reload configuration
curl -X POST http://localhost:9090/-/reload

# Check Docker network
docker network ls | grep trading-bot
docker network inspect trading-bot_default
```

#### Problem: High Memory Usage

**Symptoms:**
- Prometheus container OOM killed
- Memory usage > 2GB
- Container restarting frequently

**Diagnosis:**
```bash
# Check memory usage
docker stats prometheus --no-stream

# Check Prometheus memory metrics
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=prometheus_memory_usage_bytes' | jq

# Check WAL size
docker-compose exec prometheus du -sh /prometheus/wal
```

**Solutions:**
```bash
# Reduce retention period
docker-compose exec prometheus sed -i 's/storage.tsdb.retention.time: 30d/storage.tsdb.retention.time: 7d/' /etc/prometheus/prometheus.yml
docker-compose restart prometheus

# Enable memory compression
echo 'storage.tsdb.max-block-duration: 2h' >> /etc/prometheus/prometheus.yml

# Clean up old data
docker-compose exec prometheus promtool tsdb delete -i 0 --start '2024-01-01' --end '2024-10-01' /prometheus/
```

### 2. Grafana Issues

#### Problem: Grafana Login Fails

**Symptoms:**
- Cannot access Grafana UI
- Login page loops
- "Invalid username or password" error

**Diagnosis:**
```bash
# Check Grafana logs
docker-compose logs grafana

# Check configuration
docker-compose exec grafana cat /etc/grafana/grafana.ini | grep -E "(admin_user|admin_password)"

# Test API connectivity
curl -s http://localhost:3001/api/health
```

**Solutions:**
```bash
# Reset admin password
docker-compose exec grafana grafana-cli admin reset-admin-password admin123

# Check environment variables
docker-compose exec grafana env | grep -E "(GF_SECURITY_ADMIN|GF_AUTH)"

# Restart Grafana
docker-compose restart grafana
```

#### Problem: Dashboards Not Loading

**Symptoms:**
- Dashboards show "No Data"
- Data source connection errors
- Panels show "NaN" values

**Diagnosis:**
```bash
# Check data source status
curl -s -u admin:trading_admin http://localhost:3001/api/datasources | jq '.[] | {name: .name, type: .type, access: .access}'

# Test Prometheus data source
curl -s -u admin:trading_admin http://localhost:3001/api/datasources/proxy/1/api/v1/query?query=up

# Check dashboard availability
curl -s -u admin:trading_admin http://localhost:3001/api/search?type=dash-db | jq 'length'
```

**Solutions:**
```bash
# Re-import dashboards
./scripts/import_grafana_dashboards.sh --force

# Fix data source configuration
curl -X PUT -u admin:trading_admin \
  -H "Content-Type: application/json" \
  -d '{"name":"Prometheus","type":"prometheus","url":"http://prometheus:9090","access":"proxy","isDefault":true}' \
  http://localhost:3001/api/datasources/1

# Check Grafana-Prometheus connectivity
docker-compose exec grafana wget -qO- http://prometheus:9090/-/healthy
```

#### Problem: Grafana Slow Performance

**Symptoms:**
- Dashboard loading > 10 seconds
- UI lagging
- High CPU usage

**Diagnosis:**
```bash
# Check Grafana performance
curl -s http://localhost:3001/api/health | jq

# Check query performance
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"queries":[{"expr":"rate(container_cpu_usage_seconds_total[5m])","range":"1h"}]}' \
  http://localhost:3001/api/ds/query

# Check resource usage
docker stats grafana --no-stream
```

**Solutions:**
```bash
# Optimize dashboard queries
# Simplify complex queries
# Increase query timeout
echo 'GF_QUERY_TIMEOUT=60s' >> .env

# Enable caching
echo 'GF_DATABASE_CACHE_DURATION=300' >> .env

# Scale Grafana resources
# Update docker-compose.yml memory limits
docker-compose restart grafana
```

### 3. AlertManager Issues

#### Problem: Alerts Not Firing

**Symptoms:**
- No alerts despite threshold breaches
- AlertManager UI shows no active alerts
- Notifications not being sent

**Diagnosis:**
```bash
# Check alert rules
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.state == "firing")'

# Check AlertManager alerts
curl -s http://localhost:9093/api/v1/alerts | jq '.data.alerts'

# Test alert generation
curl -X POST http://localhost:9093/api/v1/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname":"TestAlert","severity":"warning"},
  "annotations": {"summary":"Test alert"}
}]'
```

**Solutions:**
```bash
# Reload Prometheus rules
curl -X POST http://localhost:9090/-/reload

# Check rule files
docker-compose exec prometheus find /etc/prometheus/rules -name "*.yml" -exec cat {} \;

# Validate rule syntax
docker-compose exec prometheus promtool check rules /etc/prometheus/rules/*.yml

# Restart AlertManager
docker-compose restart alertmanager
```

#### Problem: Notifications Not Working

**Symptoms:**
- Alerts firing but no notifications
- Webhook timeouts
- Email delivery failures

**Diagnosis:**
```bash
# Check AlertManager configuration
docker-compose exec alertmanager cat /etc/alertmanager/alertmanager.yml

# Check notification logs
docker-compose logs alertmanager | grep -i "notification\|webhook\|email"

# Test webhook endpoint
curl -X POST -H "Content-Type: application/json" \
  -d '{"alerts":[{"status":"firing","labels":{"alertname":"Test"}}]}' \
  http://localhost:9093/api/v1/alerts
```

**Solutions:**
```bash
# Test webhook manually
curl -X POST -H "Content-Type: application/json" \
  -d '{"text":"Test notification"}' \
  YOUR_WEBHOOK_URL

# Update AlertManager configuration
# Fix webhook URLs and authentication
docker-compose restart alertmanager

# Check network connectivity
docker-compose exec alertmanager wget -qO- --timeout=5 YOUR_WEBHOOK_URL
```

### 4. Node Exporter Issues

#### Problem: No System Metrics

**Symptoms:**
- Node Exporter not responding
- Missing `node_*` metrics
- System monitoring dashboards empty

**Diagnosis:**
```bash
# Check Node Exporter status
curl -s http://localhost:9100/metrics | grep "node_" | wc -l

# Check process
ps aux | grep node_exporter

# Check container logs
docker-compose logs node-exporter
```

**Solutions:**
```bash
# Restart Node Exporter
docker-compose restart node-exporter

# Check host access permissions
docker-compose exec node-exporter cat /proc/meminfo | head -3

# Update command line flags
# Add specific collectors in docker-compose.yml
docker-compose up -d node-exporter
```

---

## Common Problems

### 1. Port Conflicts

**Symptoms:**
- Services fail to start
- "Port already in use" errors
- Services accessible on wrong ports

**Diagnosis:**
```bash
# Check port usage
lsof -i :9090 :3001 :9093 :9100

# Check Docker port bindings
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Run port verification
./scripts/verify_port_availability.sh
```

**Solutions:**
```bash
# Resolve conflicts automatically
./scripts/resolve_port_conflict.sh

# Manual resolution
sudo kill -9 $(lsof -ti :9090)

# Restart services
docker-compose restart prometheus grafana alertmanager node-exporter
```

### 2. Docker Network Issues

**Symptoms:**
- Services cannot communicate
- Connection refused errors
- Name resolution failures

**Diagnosis:**
```bash
# Check Docker network
docker network ls | grep trading-bot
docker network inspect trading-bot_default

# Test inter-container connectivity
docker-compose exec prometheus ping trading-bot-app
docker-compose exec grafana ping prometheus

# Check DNS resolution
docker-compose exec prometheus nslookup prometheus
```

**Solutions:**
```bash
# Recreate Docker network
docker-compose down
docker network prune
docker-compose up -d

# Fix service names in configurations
# Use correct container names in Prometheus config
docker-compose restart prometheus grafana
```

### 3. Disk Space Issues

**Symptoms:**
- Services stopping unexpectedly
- OOM errors
- High disk usage

**Diagnosis:**
```bash
# Check disk usage
df -h /
docker system df

# Check Prometheus data size
docker-compose exec prometheus du -sh /prometheus

# Check log sizes
docker-compose logs --tail=0 | wc -c
```

**Solutions:**
```bash
# Clean Docker
docker system prune -f --volumes

# Reduce Prometheus retention
# Edit prometheus.yml: storage.tsdb.retention.time: 7d
docker-compose restart prometheus

# Implement log rotation
# Add log rotation to docker-compose.yml
```

---

## Performance Issues

### 1. Slow Dashboard Loading

**Causes:**
- Complex queries
- Large time ranges
- Too many panels

**Diagnosis:**
```bash
# Check query timing
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"queries":[{"expr":"rate(container_cpu_usage_seconds_total[5m])","range":"1h","datasource":{"uid":"prometheus"}}]}' \
  http://localhost:3001/api/ds/query | jq '.results[].frames[0].schema.fields[1].config'

# Check Grafana performance metrics
curl -s http://localhost:3001/api/health/metrics | grep grafana_
```

**Solutions:**
```bash
# Optimize queries
# Use recording rules
# Reduce dashboard complexity

# Add recording rules to Prometheus
cat > config/prometheus/recording_rules.yml << EOF
groups:
  - name: performance.recording.rules
    interval: 30s
    rules:
      - record: instance:cpu_usage:rate5m
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
EOF
```

### 2. High Resource Usage

**Diagnosis:**
```bash
# Monitor resource usage
watch -n 5 'docker stats --no-stream'

# Check Prometheus memory usage
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=prometheus_memory_usage_bytes' | jq

# Check Grafana CPU usage
curl -s http://localhost:3001/api/health/metrics | grep grafana_request_duration_seconds
```

**Solutions:**
```bash
# Optimize Prometheus configuration
echo 'storage.tsdb.max-block-duration: 2h' >> /etc/prometheus/prometheus.yml
echo 'storage.tsdb.retention.time: 7d' >> /etc/prometheus/prometheus.yml

# Scale resources in docker-compose.yml
# Increase memory limits
docker-compose restart prometheus grafana
```

---

## Data Issues

### 1. Missing Metrics

**Symptoms:**
- Dashboards showing gaps
- "No Data" errors
- Inconsistent metric collection

**Diagnosis:**
```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}'

# Check specific metrics
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up' | jq '.data.result[] | .metric.job'

# Check scrape intervals
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=prometheus_target_interval_length_seconds' | jq
```

**Solutions:**
```bash
# Restart failing targets
docker-compose restart trading-bot node-exporter

# Fix Prometheus configuration
# Check scrape intervals and timeouts
docker-compose exec prometheus cat /etc/prometheus/prometheus.yml

# Reload Prometheus
curl -X POST http://localhost:9090/-/reload
```

### 2. Data Corruption

**Symptoms:**
- Strange metric values
- Gaps in data
- Errors in Prometheus logs

**Diagnosis:**
```bash
# Check Prometheus logs for errors
docker-compose logs prometheus | grep -i "error\|corruption\|invalid"

# Check data consistency
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=prometheus_tsdb_head_series' | jq

# Validate data blocks
docker-compose exec prometheus promtool tsdb list /prometheus/
```

**Solutions:**
```bash
# Export and reimport data
docker-compose exec prometheus promtool tsdb dump /prometheus/ > /tmp/metrics.txt

# Start fresh (last resort)
docker-compose stop prometheus
docker volume rm trading-bot_prometheus_data
docker-compose up -d prometheus
```

---

## Network Issues

### 1. Service Connectivity

**Symptoms:**
- Connection refused errors
- Timeouts
- Name resolution failures

**Diagnosis:**
```bash
# Test connectivity between containers
docker-compose exec prometheus wget -qO- http://trading-bot-app:8082/metrics
docker-compose exec grafana wget -qO- http://prometheus:9090/-/healthy

# Check DNS resolution
docker-compose exec prometheus nslookup trading-bot-app
docker-compose exec grafana nslookup prometheus

# Check firewall rules
sudo iptables -L -n | grep -E "(9090|3001|9093|9100)"
```

**Solutions:**
```bash
# Recreate Docker network
docker-compose down
docker network prune
docker-compose up -d

# Fix service names in configurations
# Update Prometheus config to use correct service names
docker-compose restart prometheus grafana

# Check Docker daemon
sudo systemctl restart docker
```

### 2. External Access Issues

**Symptoms:**
- Cannot access services from host
- Remote access blocked
- SSL/TLS errors

**Diagnosis:**
```bash
# Check port bindings
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Test from host
curl -s http://localhost:9090/-/healthy
curl -s http://127.0.0.1:3001/api/health

# Check host firewall
sudo ufw status
sudo iptables -L -n | grep -E "(9090|3001|9093|9100)"
```

**Solutions:**
```bash
# Update port bindings in docker-compose.yml
ports:
  - "9090:9090"  # host:container

# Open firewall ports
sudo ufw allow 9090/tcp
sudo ufw allow 3001/tcp
sudo ufw allow 9093/tcp
sudo ufw allow 9100/tcp

# Restart services
docker-compose restart
```

---

## Configuration Issues

### 1. Prometheus Configuration

**Common Issues:**
- Invalid YAML syntax
- Incorrect scrape configs
- Wrong service names

**Diagnosis:**
```bash
# Validate configuration
docker-compose exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Check rule files
docker-compose exec prometheus promtool check rules /etc/prometheus/rules/*.yml

# View current configuration
docker-compose exec prometheus cat /etc/prometheus/prometheus.yml
```

**Solutions:**
```bash
# Fix YAML syntax
# Use YAML validator
# Fix indentation and quotes

# Update scrape configs
scrape_configs:
  - job_name: 'trading-bot'
    static_configs:
      - targets: ['trading-bot-app:8082']
    scrape_interval: 15s
    scrape_timeout: 10s

# Reload configuration
curl -X POST http://localhost:9090/-/reload
docker-compose restart prometheus
```

### 2. Grafana Configuration

**Common Issues:**
- Invalid data source config
- Missing dashboard files
- Permission issues

**Diagnosis:**
```bash
# Check data sources
curl -s -u admin:trading_admin http://localhost:3001/api/datasources | jq

# Check dashboard provisioning
docker-compose exec grafana ls -la /etc/grafana/provisioning/dashboards/

# Check permissions
docker-compose exec grafana ls -la /var/lib/grafana/
```

**Solutions:**
```bash
# Reconfigure data sources
curl -X POST -u admin:trading_admin \
  -H "Content-Type: application/json" \
  -d '{"name":"Prometheus","type":"prometheus","url":"http://prometheus:9090","access":"proxy","isDefault":true}' \
  http://localhost:3001/api/datasources

# Re-import dashboards
./scripts/import_grafana_dashboards.sh --force

# Fix permissions
docker-compose exec grafana chown -R grafana:grafana /var/lib/grafana/
```

---

## Emergency Procedures

### Complete Monitoring Stack Recovery

```bash
#!/bin/bash
# scripts/emergency_monitoring_recovery.sh

echo "🚨 EMERGENCY MONITORING RECOVERY - $(date)"
echo "=========================================="

# 1. Stop all monitoring services
echo "⏹️  Stopping monitoring services..."
docker-compose stop prometheus grafana alertmanager node-exporter

# 2. Backup current configurations
echo "💾 Backing up configurations..."
mkdir -p /tmp/monitoring_backup_$(date +%Y%m%d_%H%M%S)
docker-compose exec prometheus cat /etc/prometheus/prometheus.yml > /tmp/monitoring_backup_$(date +%Y%m%d_%H%M%S)/prometheus.yml
docker-compose exec grafana cat /etc/grafana/grafana.ini > /tmp/monitoring_backup_$(date +%Y%m%d_%H%M%S)/grafana.ini
docker-compose exec alertmanager cat /etc/alertmanager/alertmanager.yml > /tmp/monitoring_backup_$(date +%Y%m%d_%H%M%S)/alertmanager.yml

# 3. Clear corrupted data (if needed)
echo "🧹 Clearing corrupted data..."
docker-compose exec prometheus rm -rf /prometheus/wal/*
docker-compose exec grafana rm -rf /var/lib/grafana/data/*

# 4. Restart services in correct order
echo "🔄 Restarting monitoring stack..."
docker-compose up -d node-exporter
sleep 10
docker-compose up -d prometheus
sleep 20
docker-compose up -d alertmanager
sleep 10
docker-compose up -d grafana

# 5. Verify health
echo "✅ Verifying health..."
sleep 30
./scripts/verify_monitoring_stack.sh

# 6. Import dashboards
echo "📊 Importing dashboards..."
./scripts/import_grafana_dashboards.sh --force

# 7. Test alert delivery
echo "🚨 Testing alerts..."
curl -XPOST http://localhost:9093/api/v1/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname":"RecoveryTest","severity":"info"},
  "annotations": {"summary":"Emergency recovery test"}
}]'

echo "🎉 Emergency monitoring recovery completed"
echo "📋 Post-recovery checklist:"
echo "1. Verify all services are running"
echo "2. Check dashboards are loading data"
echo "3. Confirm alerts are being delivered"
echo "4. Monitor system performance for 1 hour"
echo "5. Document the incident"
```

### Service-Specific Recovery

```bash
# Prometheus recovery
docker-compose stop prometheus
docker volume rm trading-bot_prometheus_data  # CAUTION: Deletes all data
docker-compose up -d prometheus

# Grafana recovery
docker-compose stop grafana
docker-compose exec grafana rm -rf /var/lib/grafana/data/*
docker-compose up -d grafana
./scripts/import_grafana_dashboards.sh --force

# AlertManager recovery
docker-compose restart alertmanager
curl -XPOST http://localhost:9093/api/v1/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {"alertname":"RecoveryTest","severity":"info"}
}]'
```

---

## Prevention and Maintenance

### Regular Health Checks

```bash
# Daily monitoring verification
echo "0 9 * * * /path/to/scripts/verify_monitoring_stack.sh" | crontab -

# Weekly configuration backup
echo "0 2 * * 0 tar -czf /backup/monitoring_config_$(date +\%Y\%m\%d).tar.gz config/prometheus/ config/grafana/ config/alertmanager/" | crontab -

# Monthly data cleanup
echo "0 3 1 * * docker-compose exec prometheus promtool tsdb delete -i 0 --start $(date -d '2 months ago' --iso-8601) /prometheus/" | crontab -
```

### Monitoring Best Practices

1. **Resource Monitoring**: Monitor monitoring stack resources
2. **Alert Quality**: Regularly review and test alerts
3. **Documentation**: Keep configurations documented
4. **Backups**: Regular configuration and data backups
5. **Testing**: Test recovery procedures monthly

### Performance Optimization

1. **Recording Rules**: Pre-compute expensive queries
2. **Retention Policies**: Balance storage vs. history
3. **Query Optimization**: Use efficient PromQL patterns
4. **Dashboard Design**: Limit panels and complexity
5. **Resource Allocation**: Right-size containers

---

## Getting Help

### Log Analysis

```bash
# Collect troubleshooting information
echo "=== Monitoring Stack Status ===" > /tmp/monitoring_debug.txt
date >> /tmp/monitoring_debug.txt
docker-compose ps prometheus grafana alertmanager node-exporter >> /tmp/monitoring_debug.txt

echo -e "\n=== Service Logs ===" >> /tmp/monitoring_debug.txt
docker-compose logs --tail=50 prometheus >> /tmp/monitoring_debug.txt
docker-compose logs --tail=50 grafana >> /tmp/monitoring_debug.txt
docker-compose logs --tail=50 alertmanager >> /tmp/monitoring_debug.txt

echo -e "\n=== Health Checks ===" >> /tmp/monitoring_debug.txt
curl -s http://localhost:9090/-/healthy >> /tmp/monitoring_debug.txt
curl -s http://localhost:3001/api/health >> /tmp/monitoring_debug.txt
curl -s http://localhost:9093/-/healthy >> /tmp/monitoring_debug.txt

echo "Debug information saved to /tmp/monitoring_debug.txt"
```

### Community Resources

- **Prometheus Documentation**: https://prometheus.io/docs/
- **Grafana Documentation**: https://grafana.com/docs/
- **AlertManager Documentation**: https://prometheus.io/docs/alerting/latest/alertmanager/
- **Node Exporter**: https://github.com/prometheus/node_exporter

### Escalation Procedures

1. **Level 1**: Use this troubleshooting guide
2. **Level 2**: Check service logs and configurations
3. **Level 3**: Contact support with debug information
4. **Emergency**: Use complete recovery procedures

---

## Conclusion

This comprehensive troubleshooting guide provides systematic procedures for diagnosing and resolving monitoring stack issues. Regular maintenance and monitoring of the monitoring infrastructure itself ensures reliable operation of the MojoRust Trading Bot system.

**Key Takeaways:**
- Use the verification scripts for quick diagnostics
- Check logs first for most issues
- Understand service dependencies
- Keep configurations under version control
- Test recovery procedures regularly
- Document incidents and resolutions

Remember: The monitoring stack is critical for system observability. Address monitoring issues promptly to maintain system visibility and reliability.