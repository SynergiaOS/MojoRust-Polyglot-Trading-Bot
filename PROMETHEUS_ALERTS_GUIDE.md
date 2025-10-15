# Prometheus Alerts Configuration Guide
## MojoRust Trading Bot - Comprehensive Alert Setup for Production Monitoring

---

## Overview

This guide provides comprehensive instructions for configuring Prometheus alerts for the MojoRust Trading Bot deployed via Docker Compose on server `38.242.239.150`. The alerting system covers 32 critical alerts across system health, trading performance, Docker services, and DragonflyDB connectivity.

**Prerequisites:**
- Docker Compose deployment running
- Prometheus server configured and scraping metrics
- AlertManager service configured
- Basic understanding of Prometheus query language (PromQL)

---

## Alert Configuration Architecture

### File Structure
```
config/
├── prometheus/
│   ├── alerts/
│   │   ├── bot-alerts.yml           # Trading bot performance alerts
│   │   ├── system-alerts.yml        # System resource alerts
│   │   ├── docker-alerts.yml        # Docker service health alerts
│   │   └── dragonflydb-alerts.yml   # DragonflyDB connectivity alerts
│   └── prometheus.yml               # Main Prometheus configuration
└── alertmanager/
    └── alertmanager.yml             # AlertManager routing configuration
```

### Alert Categories

1. **Trading Bot Performance (8 alerts)**
   - Bot not running
   - High rejection rate (>95%)
   - Low rejection rate (<80%)
   - No trades executed
   - High error rate
   - Memory usage
   - API endpoint failures
   - Performance degradation

2. **System Resources (6 alerts)**
   - CPU usage >80%
   - Memory usage >85%
   - Disk usage >90%
   - Load average
   - Network connectivity
   - Disk I/O pressure

3. **Docker Services (10 alerts)**
   - Container failures
   - Health check failures
   - Resource limits
   - Volume issues
   - Network problems
   - Orphaned containers
   - Image pull failures
   - Restart loops
   - Service downtime
   - Configuration errors

4. **DragonflyDB (8 alerts)**
   - Connection failures
   - High memory usage
   - Connection pool exhaustion
   - Latency spikes
   - Replication lag
   - Backup failures
   - Authentication errors
   - SSL/TLS issues

---

## Alert Rules Configuration

### 1. Trading Bot Performance Alerts (`config/prometheus/alerts/bot-alerts.yml`)

```yaml
groups:
  - name: trading-bot.rules
    rules:
      # Alert: Bot not running
      - alert: TradingBotDown
        expr: up{job="trading-bot"} == 0
        for: 1m
        labels:
          severity: critical
          service: trading-bot
        annotations:
          summary: "Trading bot is down"
          description: "Trading bot has been down for more than 1 minute on {{ $labels.instance }}"

      # Alert: High spam rejection rate (filter too aggressive)
      - alert: HighRejectionRate
        expr: trading_bot_rejection_rate > 95
        for: 5m
        labels:
          severity: warning
          service: trading-bot
        annotations:
          summary: "Filter rejection rate too high: {{ $value }}%"
          description: "Spam filter rejection rate is {{ $value }}% on {{ $labels.instance }}, potentially blocking legitimate trades"

      # Alert: Low rejection rate (filter too lenient)
      - alert: LowRejectionRate
        expr: trading_bot_rejection_rate < 80
        for: 10m
        labels:
          severity: warning
          service: trading-bot
        annotations:
          summary: "Filter rejection rate too low: {{ $value }}%"
          description: "Spam filter rejection rate is {{ $value }}% on {{ $labels.instance }}, may allow spam trades"

      # Alert: No trades executed in time window
      - alert: NoTradingActivity
        expr: increase(trading_bot_trades_total[1h]) == 0
        for: 2h
        labels:
          severity: warning
          service: trading-bot
        annotations:
          summary: "No trading activity detected"
          description: "No trades have been executed in the last 2 hours on {{ $labels.instance }}"

      # Alert: High error rate
      - alert: HighErrorRate
        expr: rate(trading_bot_errors_total[5m]) > 0.1
        for: 5m
        labels:
          severity: critical
          service: trading-bot
        annotations:
          summary: "High error rate: {{ $value }} errors/sec"
          description: "Trading bot error rate is {{ $value }} errors/sec on {{ $labels.instance }}"

      # Alert: Bot memory usage high
      - alert: TradingBotHighMemory
        expr: container_memory_usage_bytes{name="trading-bot"} / container_spec_memory_limit_bytes{name="trading-bot"} > 0.8
        for: 5m
        labels:
          severity: warning
          service: trading-bot
        annotations:
          summary: "Trading bot memory usage high: {{ $value | humanizePercentage }}"
          description: "Trading bot memory usage is {{ $value | humanizePercentage }} of limit on {{ $labels.instance }}"

      # Alert: API endpoint failures
      - alert: APIEndpointFailures
        expr: rate(http_requests_total{job="trading-bot",status=~"5.."}[5m]) > 0.05
        for: 3m
        labels:
          severity: critical
          service: trading-bot
        annotations:
          summary: "API endpoint failures detected"
          description: "API 5xx error rate is {{ $value }} requests/sec on {{ $labels.instance }}"

      # Alert: Performance degradation
      - alert: PerformanceDegradation
        expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="trading-bot"}[5m])) > 2
        for: 5m
        labels:
          severity: warning
          service: trading-bot
        annotations:
          summary: "API performance degraded: {{ $value }}s 95th percentile"
          description: "API response time 95th percentile is {{ $value }}s on {{ $labels.instance }}"
```

### 2. System Resources Alerts (`config/prometheus/alerts/system-alerts.yml`)

```yaml
groups:
  - name: system-resources.rules
    rules:
      # Alert: High CPU usage
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
          service: system
        annotations:
          summary: "High CPU usage: {{ $value }}%"
          description: "CPU usage is {{ $value }}% on {{ $labels.instance }}"

      # Alert: High memory usage
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        labels:
          severity: warning
          service: system
        annotations:
          summary: "High memory usage: {{ $value }}%"
          description: "Memory usage is {{ $value }}% on {{ $labels.instance }}"

      # Alert: Critical disk usage
      - alert: CriticalDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100 > 90
        for: 2m
        labels:
          severity: critical
          service: system
        annotations:
          summary: "Critical disk usage: {{ $value }}%"
          description: "Disk usage is {{ $value }}% on {{ $labels.instance }}:{{ $labels.mountpoint }}"

      # Alert: High load average
      - alert: HighLoadAverage
        expr: node_load15 > 2.0
        for: 5m
        labels:
          severity: warning
          service: system
        annotations:
          summary: "High load average: {{ $value }}"
          description: "15-minute load average is {{ $value }} on {{ $labels.instance }}"

      # Alert: Network connectivity issues
      - alert: NetworkConnectivityIssue
        expr: up{job="node-exporter"} == 0
        for: 2m
        labels:
          severity: critical
          service: system
        annotations:
          summary: "Network connectivity issue"
          description: "Cannot reach node-exporter on {{ $labels.instance }}"

      # Alert: Disk I/O pressure
      - alert: DiskIOPressure
        expr: rate(node_disk_io_time_seconds_total[5m]) * 100 > 80
        for: 5m
        labels:
          severity: warning
          service: system
        annotations:
          summary: "Disk I/O pressure: {{ $value }}%"
          description: "Disk I/O utilization is {{ $value }}% on {{ $labels.instance }}"
```

### 3. Docker Services Alerts (`config/prometheus/alerts/docker-alerts.yml`)

```yaml
groups:
  - name: docker-services.rules
    rules:
      # Alert: Container failed to start
      - alert: ContainerFailed
        expr: time() - container_start_time_seconds < 60 and container_state != "running"
        for: 1m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Container failed: {{ $labels.name }}"
          description: "Container {{ $labels.name }} failed to start on {{ $labels.instance }}"

      # Alert: Health check failure
      - alert: HealthCheckFailure
        expr: container_health_status != "healthy"
        for: 3m
        labels:
          severity: warning
          service: docker
        annotations:
          summary: "Health check failed for {{ $labels.name }}"
          description: "Health check failed for container {{ $labels.name }} on {{ $labels.instance }}"

      # Alert: Container resource limit exceeded
      - alert: ContainerResourceLimitExceeded
        expr: container_memory_usage_bytes / container_spec_memory_limit_bytes > 0.95
        for: 5m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Container memory limit exceeded: {{ $labels.name }}"
          description: "Container {{ $labels.name }} memory usage is {{ $value | humanizePercentage }} of limit"

      # Alert: Volume mount issue
      - alert: VolumeMountIssue
        expr: container_volume_mounts_total == 0
        for: 1m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Volume mount issue: {{ $labels.name }}"
          description: "Container {{ $labels.name }} has no volume mounts mounted"

      # Alert: Docker service down
      - alert: DockerServiceDown
        expr: up{job=~"timescaledb|trading-bot|prometheus|grafana"} == 0
        for: 1m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Docker service down: {{ $labels.job }}"
          description: "Docker service {{ $labels.job }} is down on {{ $labels.instance }}"

      # Alert: Container restart loop
      - alert: ContainerRestartLoop
        expr: rate(container_start_time_seconds[10m]) > 0.1
        for: 5m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Container restart loop: {{ $labels.name }}"
          description: "Container {{ $labels.name }} is restarting frequently on {{ $labels.instance }}"

      # Alert: Docker daemon issues
      - alert: DockerDaemonIssues
        expr: up{job="docker-exporter"} == 0
        for: 2m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Docker daemon issues"
          description: "Docker daemon is not responding on {{ $labels.instance }}"

      # Alert: Service downtime
      - alert: ServiceDowntime
        expr: time() - container_start_time_seconds > 300 and container_state == "running" and up{job=~"timescaledb|trading-bot|prometheus|grafana"} == 0
        for: 2m
        labels:
          severity: warning
          service: docker
        annotations:
          summary: "Service downtime: {{ $labels.job }}"
          description: "Service {{ $labels.job }} has been down for more than 5 minutes"

      # Alert: Orphaned containers
      - alert: OrphanedContainers
        expr: container_labels_com_docker_compose_project == "" and container_state == "running"
        for: 10m
        labels:
          severity: warning
          service: docker
        annotations:
          summary: "Orphaned containers detected"
          description: "Found {{ $value }} containers without docker-compose labels on {{ $labels.instance }}"

      # Alert: Configuration errors
      - alert: ConfigurationError
        expr: container_exit_code != 0 and container_state == "exited"
        for: 1m
        labels:
          severity: critical
          service: docker
        annotations:
          summary: "Configuration error: {{ $labels.name }}"
          description: "Container {{ $labels.name }} exited with code {{ $labels.exit_code }}"
```

### 4. DragonflyDB Alerts (`config/prometheus/alerts/dragonflydb-alerts.yml`)

```yaml
groups:
  - name: dragonflydb.rules
    rules:
      # Alert: DragonflyDB connection failure
      - alert: DragonflyDBConnectionFailure
        expr: redis_up == 0
        for: 1m
        labels:
          severity: critical
          service: dragonflydb
        annotations:
          summary: "DragonflyDB connection failed"
          description: "Cannot connect to DragonflyDB on {{ $labels.instance }}"

      # Alert: High memory usage
      - alert: DragonflyDBHighMemoryUsage
        expr: redis_memory_used_bytes / redis_memory_max_bytes > 0.9
        for: 5m
        labels:
          severity: warning
          service: dragonflydb
        annotations:
          summary: "DragonflyDB high memory usage: {{ $value | humanizePercentage }}"
          description: "DragonflyDB memory usage is {{ $value | humanizePercentage }} on {{ $labels.instance }}"

      # Alert: Connection pool exhaustion
      - alert: DragonflyDBConnectionPoolExhaustion
        expr: redis_connected_clients > 80
        for: 3m
        labels:
          severity: warning
          service: dragonflydb
        annotations:
          summary: "DragonflyDB high connection count: {{ $value }}"
          description: "DragonflyDB has {{ $value }} connected clients on {{ $labels.instance }}"

      # Alert: Latency spikes
      - alert: DragonflyDBHighLatency
        expr: histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m])) > 0.1
        for: 5m
        labels:
          severity: warning
          service: dragonflydb
        annotations:
          summary: "DragonflyDB high latency: {{ $value }}s"
          description: "DragonflyDB 95th percentile latency is {{ $value }}s on {{ $labels.instance }}"

      # Alert: Replication lag (if applicable)
      - alert: DragonflyDBReplicationLag
        expr: redis_replication_offset_bytes - redis_master_repl_offset_bytes > 1048576
        for: 5m
        labels:
          severity: warning
          service: dragonflydb
        annotations:
          summary: "DragonflyDB replication lag: {{ $value }} bytes"
          description: "DragonflyDB replication lag is {{ $value }} bytes on {{ $labels.instance }}"

      # Alert: Backup failures
      - alert: DragonflyDBBackupFailure
        expr: redis_last_save_timestamp_seconds == 0 or time() - redis_last_save_timestamp_seconds > 86400
        for: 1m
        labels:
          severity: critical
          service: dragonflydb
        annotations:
          summary: "DragonflyDB backup failure"
          description: "DragonflyDB backup has not succeeded in the last 24 hours on {{ $labels.instance }}"

      # Alert: Authentication errors
      - alert: DragonflyDBAuthenticationError
        expr: rate(redis_auth_errors_total[5m]) > 0
        for: 1m
        labels:
          severity: critical
          service: dragonflydb
        annotations:
          summary: "DragonflyDB authentication errors"
          description: "DragonflyDB authentication errors detected on {{ $labels.instance }}"

      # Alert: SSL/TLS issues
      - alert: DragonflyDBSSLIssue
        expr: redis_ssl_connections_total == 0 and redis_tls_enabled == 1
        for: 2m
        labels:
          severity: critical
          service: dragonflydb
        annotations:
          summary: "DragonflyDB SSL/TLS issues"
          description: "DragonflyDB SSL/TLS is enabled but no secure connections detected on {{ $labels.instance }}"
```

---

## Prometheus Configuration

### Main Configuration (`config/prometheus/prometheus.yml`)

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - "alerts/bot-alerts.yml"
  - "alerts/system-alerts.yml"
  - "alerts/docker-alerts.yml"
  - "alerts/dragonflydb-alerts.yml"

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

scrape_configs:
  # Trading Bot Metrics (Unified port 8082)
  - job_name: 'trading-bot'
    static_configs:
      - targets: ['trading-bot:8082']
    scrape_interval: 15s
    metrics_path: '/metrics'

  # System Metrics (Node Exporter)
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 15s

  # Docker Metrics
  - job_name: 'docker-exporter'
    static_configs:
      - targets: ['docker-exporter:9323']
    scrape_interval: 15s

  # Data Consumer Metrics (Geyser streaming)
  - job_name: 'data-consumer'
    static_configs:
      - targets: ['data-consumer:9191']
    scrape_interval: 15s
    metrics_path: '/metrics'

  # DragonflyDB Metrics
  - job_name: 'dragonflydb'
    static_configs:
      - targets: ['dragonflydb-exporter:9121']
    scrape_interval: 15s

  # Prometheus Self
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 15s

  # AlertManager
  - job_name: 'alertmanager'
    static_configs:
      - targets: ['alertmanager:9093']
    scrape_interval: 15s
```

---

## AlertManager Configuration

### AlertManager Routing (`config/alertmanager/alertmanager.yml`)

```yaml
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@trading-bot.local'

route:
  group_by: ['alertname', 'service', 'instance']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default-receiver'
  routes:
    # Critical alerts go to all channels
    - match:
        severity: critical
      receiver: 'critical-alerts'
      group_wait: 0s
      repeat_interval: 5m

    # System alerts go to email only
    - match:
        service: system
      receiver: 'system-alerts'

    # Docker service alerts
    - match:
        service: docker
      receiver: 'docker-alerts'

    # Trading bot alerts
    - match:
        service: trading-bot
      receiver: 'trading-bot-alerts'

receivers:
  # Default receiver
  - name: 'default-receiver'
    email_configs:
      - to: 'admin@trading-bot.local'
        subject: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
        body: |
          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance }}
          Service: {{ .Labels.service }}
          {{ end }}

  # Critical alerts (all channels)
  - name: 'critical-alerts'
    email_configs:
      - to: 'admin@trading-bot.local'
        subject: '🚨 CRITICAL: {{ .GroupLabels.alertname }}'
        body: |
          🚨 CRITICAL ALERT 🚨

          {{ range .Alerts }}
          Alert: {{ .Annotations.summary }}
          Description: {{ .Annotations.description }}
          Instance: {{ .Labels.instance }}
          Service: {{ .Labels.service }}
          Timestamp: {{ .StartsAt }}
          {{ end }}
    webhook_configs:
      - url: 'http://localhost:8080/webhooks/critical'
        send_resolved: true

  # System alerts
  - name: 'system-alerts'
    email_configs:
      - to: 'sysadmin@trading-bot.local'
        subject: 'System Alert: {{ .GroupLabels.alertname }}'

  # Docker alerts
  - name: 'docker-alerts'
    email_configs:
      - to: 'devops@trading-bot.local'
        subject: 'Docker Alert: {{ .GroupLabels.alertname }}'

  # Trading bot alerts
  - name: 'trading-bot-alerts'
    email_configs:
      - to: 'trading-team@trading-bot.local'
        subject: 'Trading Bot Alert: {{ .GroupLabels.alertname }}'

inhibit_rules:
  # Inhibit system alerts if trading bot is down
  - source_match:
      alertname: TradingBotDown
    target_match:
      service: trading-bot
    equal: ['instance']

  # Inhibit lower severity alerts if critical alerts are firing
  - source_match:
      severity: critical
    target_match:
      severity: warning
    equal: ['alertname', 'instance']
```

---

## Deployment and Verification

### 1. Deploy Alert Configuration

```bash
# Copy alert rules to Prometheus container
docker cp config/prometheus/alerts/ trading-bot-prometheus:/etc/prometheus/alerts/

# Copy updated Prometheus configuration
docker cp config/prometheus/prometheus.yml trading-bot-prometheus:/etc/prometheus/prometheus.yml

# Copy AlertManager configuration
docker cp config/alertmanager/alertmanager.yml trading-bot-alertmanager:/etc/alertmanager/alertmanager.yml

# Restart Prometheus to load new rules
docker-compose restart prometheus

# Restart AlertManager to load new configuration
docker-compose restart alertmanager
```

### 2. Verify Alert Rules

```bash
# Check Prometheus loaded alert rules
curl http://38.242.239.150:9090/api/v1/rules | jq '.data.groups[].rules[] | {name: .name, state: .state, health: .health}'

# Check AlertManager configuration
curl http://38.242.239.150:9093/api/v1/status | jq '.data.config'

# List active alerts
curl http://38.242.239.150:9093/api/v1/alerts | jq '.data.alerts[] | {labels: .labels, status: .status}'

# Check specific service targets
curl http://38.242.239.150:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'
```

### 3. Test Alert Firing

```bash
# Test critical alert - stop trading bot
docker-compose stop trading-bot
# Wait 1-2 minutes, then check alerts
curl http://38.242.239.150:9093/api/v1/alerts

# Test system alert - generate CPU load
docker exec trading-bot-app dd if=/dev/zero of=/dev/null &
# Wait 5 minutes, then check alerts
curl http://38.242.239.150:9093/api/v1/alerts

# Test DragonflyDB alert - stop DragonflyDB connection
# Edit REDIS_URL to invalid value, restart trading bot
# Check for DragonflyDB connection failure alert
curl http://38.242.239.150:9093/api/v1/alerts

# Test data consumer alert - stop data consumer
docker-compose stop data-consumer
# Wait 2 minutes, then check alerts
curl http://38.242.239.150:9093/api/v1/alerts

# Restore normal operation
docker-compose start trading-bot data-consumer
docker-compose restart trading-bot data-consumer
```

### 4. Verify Alert Notifications

```bash
# Check AlertManager logs for notification attempts
docker-compose logs alertmanager | grep -i "notification"

# Test email configuration (if SMTP configured)
# Send test email through AlertManager API
curl -XPOST http://38.242.239.150:9093/api/v1/alerts -H 'Content-Type: application/json' -d '[{
  "labels": {
    "alertname": "TestAlert",
    "severity": "info",
    "instance": "test"
  },
  "annotations": {
    "summary": "Test alert notification",
    "description": "This is a test alert to verify notifications are working"
  }
}]'

# Verify trading bot metrics collection
curl -s http://38.242.239.150:8082/metrics | grep -E "(trading_bot_|up|http_requests)"

# Verify data consumer metrics collection
curl -s http://38.242.239.150:9191/metrics | grep -E "(geyser_|redis_|up)"
```

---

## Alert Maintenance and Operations

### Daily Operations

```bash
# Check alert rule status
./scripts/verify_alerts.sh --status

# Check for any firing alerts
./scripts/verify_alerts.sh --firing

# Get alert summary
./scripts/verify_alerts.sh --summary

# Check alert notification delivery
./scripts/verify_alerts.sh --notifications
```

### Weekly Maintenance

```bash
# Review alert performance
./scripts/verify_alerts.sh --performance

# Check for alert fatigue
./scripts/verify_alerts.sh --fatigue

# Update alert thresholds if needed
./scripts/verify_alerts.sh --optimize

# Backup alert configurations
./scripts/backup_alerts.sh
```

### Alert Troubleshooting

```bash
# Check specific alert rule
curl http://localhost:9090/api/v1/rules | jq '.data.groups[].rules[] | select(.name=="TradingBotDown")'

# Debug alert not firing
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up{job="trading-bot"}'

# Check alert evaluation timing
curl http://localhost:9090/api/v1/rules?type=alert | jq '.data.groups[].rules[] | {name: .name, evaluationTime: .evaluationTime}'
```

---

## Alert Performance Optimization

### Reducing Alert Fatigue

1. **Adjust thresholds**: Tune alert thresholds to reduce false positives
2. **Group related alerts**: Use routing rules to group related alerts
3. **Increase for duration**: Require alerts to persist before notification
4. **Use inhibition rules**: Suppress less important alerts during critical issues

### Alert Priority Levels

- **Critical**: Immediate action required (bot down, security issues)
- **Warning**: Attention needed within 1 hour (performance degradation)
- **Info**: For awareness only (scheduled maintenance)

### Custom Alert Templates

```yaml
# Custom annotation templates
templates:
  - '/etc/alertmanager/templates/*.tmpl'

# Template example (custom.tmpl)
{{ define "custom.email.subject" }}
[{{ .Status | toUpper }}{{ if eq .Status "firing" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .GroupLabels.alertname }}
{{ end }}

{{ define "custom.email.body" }}
{{ range .Alerts }}
{{ if .Labels.severity }}{{ .Labels.severity | toUpper }}{{ end }}: {{ .Annotations.summary }}

Description: {{ .Annotations.description }}
Instance: {{ .Labels.instance }}
Service: {{ .Labels.service }}
Time: {{ .StartsAt.Format "2006-01-02 15:04:05" }}

{{ end }}
{{ end }}
```

---

## Monitoring Alert Effectiveness

### Key Metrics to Track

1. **Alert Rate**: Number of alerts per hour/day
2. **Mean Time to Acknowledge (MTTA)**: How quickly alerts are acknowledged
3. **Mean Time to Resolution (MTTR)**: How quickly alerts are resolved
4. **False Positive Rate**: Percentage of alerts that don't require action
5. **Alert Fatigue Index**: Number of alerts per operator per shift

### Alert Quality Improvement

```bash
# Generate alert effectiveness report
./scripts/alert_effectiveness_report.sh --period=7d

# Identify frequently firing alerts
curl http://localhost:9090/api/v1/query_range \
  --data-urlencode 'query=ALERTS_FOR_STATE' \
  --data-urlencode 'start=2024-10-08T00:00:00Z' \
  --data-urlencode 'end=2024-10-15T00:00:00Z' \
  --data-urlencode 'step=1h'
```

---

## Integration with External Systems

### Slack Integration

```yaml
# Add to AlertManager receivers
- name: 'slack-alerts'
  slack_configs:
    - api_url: 'YOUR_SLACK_WEBHOOK_URL'
      channel: '#trading-bot-alerts'
      title: 'Trading Bot Alert: {{ .GroupLabels.alertname }}'
      text: |
        {{ range .Alerts }}
        *{{ .Annotations.summary }}*
        {{ .Annotations.description }}
        Instance: {{ .Labels.instance }}
        {{ end }}
```

### PagerDuty Integration

```yaml
# Add to AlertManager receivers
- name: 'pagerduty-critical'
  pagerduty_configs:
    - service_key: 'YOUR_PAGERDUTY_SERVICE_KEY'
      description: '{{ .GroupLabels.alertname }}: {{ .Annotations.summary }}'
      details:
        instance: '{{ .Labels.instance }}'
        service: '{{ .Labels.service }}'
        severity: '{{ .Labels.severity }}'
```

### Custom Webhook Integration

```bash
# Custom webhook handler
# File: scripts/webhook_handler.py
import json
import requests
from flask import Flask, request

app = Flask(__name__)

@app.route('/webhooks/critical', methods=['POST'])
def handle_critical_alert():
    data = request.json
    alerts = data.get('alerts', [])

    for alert in alerts:
        # Custom processing for critical alerts
        print(f"CRITICAL: {alert['labels']['alertname']}")

        # Send to custom notification system
        requests.post('https://your-notification-system.com/alerts', json=alert)

    return 'OK', 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

---

## Security Considerations

### Alert Data Protection

1. **Sanitize alert annotations**: Remove sensitive information from alert descriptions
2. **Secure notification channels**: Use HTTPS for webhooks and TLS for email
3. **Access control**: Limit who can view and modify alert configurations
4. **Audit logging**: Log all alert configuration changes

### Authentication

```yaml
# Basic authentication for AlertManager API
basic_auth_users:
  admin: $2b$12$...
  viewer: $2b$12$...

# TLS configuration
tls_config:
  cert_file: /etc/alertmanager/certs/server.crt
  key_file: /etc/alertmanager/certs/server.key
```

---

## Backup and Recovery

### Backup Alert Configurations

```bash
#!/bin/bash
# scripts/backup_alerts.sh

BACKUP_DIR="/root/backups/alerts"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup alert rules
docker cp trading-bot-prometheus:/etc/prometheus/alerts "$BACKUP_DIR/alerts_$DATE"

# Backup Prometheus configuration
docker cp trading-bot-prometheus:/etc/prometheus/prometheus.yml "$BACKUP_DIR/prometheus_$DATE.yml"

# Backup AlertManager configuration
docker cp trading-bot-alertmanager:/etc/alertmanager/alertmanager.yml "$BACKUP_DIR/alertmanager_$DATE.yml"

# Compress backups
tar -czf "$BACKUP_DIR/alerts_backup_$DATE.tar.gz" "$BACKUP_DIR"/*_$DATE*

# Cleanup old backups (keep 30 days)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete

echo "Alert configuration backup completed: alerts_backup_$DATE.tar.gz"
```

### Restore Alert Configurations

```bash
#!/bin/bash
# scripts/restore_alerts.sh

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup_file.tar.gz>"
    exit 1
fi

# Extract backup
tar -xzf "$BACKUP_FILE" -C /tmp/

# Restore alert rules
docker cp /tmp/alerts/ trading-bot-prometheus:/etc/prometheus/

# Restore Prometheus configuration
docker cp /tmp/prometheus_*.yml trading-bot-prometheus:/etc/prometheus/prometheus.yml

# Restore AlertManager configuration
docker cp /tmp/alertmanager_*.yml trading-bot-alertmanager:/etc/alertmanager/alertmanager.yml

# Restart services
docker-compose restart prometheus alertmanager

echo "Alert configuration restored from $BACKUP_FILE"
```

---

## Conclusion

This comprehensive alert configuration provides:

- **32 critical alerts** covering all aspects of the trading bot system
- **Multi-tier severity levels** with appropriate notification routing
- **Integration with Docker Compose** monitoring
- **DragonflyDB Cloud** connectivity and performance monitoring
- **Automated verification scripts** for alert health checking
- **Backup and recovery procedures** for alert configurations
- **Integration with external systems** (Slack, PagerDuty, custom webhooks)
- **Security best practices** for alert data protection

The alerting system ensures rapid detection and response to issues affecting the trading bot's performance, availability, and security while minimizing alert fatigue through proper tuning and intelligent grouping.

**Next Steps:**
1. Deploy the alert configurations to your Prometheus server
2. Verify all alerts are loading correctly
3. Test alert notifications
4. Monitor and tune alert thresholds based on your environment
5. Set up regular backups of alert configurations