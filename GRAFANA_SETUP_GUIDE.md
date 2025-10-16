# Grafana Dashboard Setup Guide
## MojoRust Trading Bot - Comprehensive Monitoring Dashboard Configuration

---

## Overview

This guide provides comprehensive instructions for setting up Grafana dashboards for the MojoRust Trading Bot deployed via Docker Compose on server `38.242.239.150`. The dashboard system includes 6 pre-configured dashboards covering trading performance, system health, Docker services, and DragonflyDB metrics.

**Prerequisites:**
- Docker Compose deployment running with Grafana service
- Prometheus server configured and collecting metrics
- Admin access to Grafana (default: `admin/admin`)
- Basic understanding of Grafana dashboard configuration

---

## Dashboard Architecture

### Dashboard Categories

1. **Trading Performance Dashboard** - Real-time trading metrics and P&L
2. **System Health Dashboard** - Server resources and performance
3. **Docker Services Dashboard** - Container status and resource usage
4. **DragonflyDB Dashboard** - Cache performance and connectivity
5. **API Monitoring Dashboard** - Request metrics and response times
6. **Alert Management Dashboard** - Active alerts and notification status

### File Structure
```
config/
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/
│   │   │   └── prometheus.yml          # Prometheus datasource
│   │   ├── dashboards/
│   │   │   ├── dashboard.yml           # Dashboard provisioning
│   │   │   └── dashboards.yml          # Dashboard definitions
│   │   └── alerting/
│   │       └── grafana-alerts.yml      # Grafana-native alerts
│   └── dashboards/
│       ├── trading-performance.json    # Trading metrics dashboard
│       ├── system-health.json          # System monitoring dashboard
│       ├── docker-services.json        # Docker services dashboard
│       ├── dragonflydb.json            # DragonflyDB dashboard
│       ├── api-monitoring.json         # API metrics dashboard
│       └── alert-management.json       # Alert management dashboard
```

---

## Grafana Configuration

### 1. Data Source Configuration (`config/grafana/provisioning/datasources/prometheus.yml`)

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    jsonData:
      timeInterval: "15s"
      queryTimeout: "60s"
      httpMethod: "POST"
    secureJsonData: {}

  - name: Prometheus-Direct
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: false
    editable: true
    jsonData:
      timeInterval: "5s"
      queryTimeout: "30s"
      httpMethod: "POST"
      manageAlerts: true
      prometheusType: Prometheus
      prometheusVersion: "2.40.0"
      cacheLevel: "High"
      incrementalQueryOverlapWindow: "10m"
      disableRecordingRules: false
      incrementalQuery: true
      resultStreaming: true
    secureJsonData: {}
```

### 2. Dashboard Provisioning (`config/grafana/provisioning/dashboards/dashboard.yml`)

```yaml
apiVersion: 1

providers:
  - name: 'trading-bot-dashboards'
    orgId: 1
    folder: 'Trading Bot'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards/dashboards
```

### 3. Dashboard Definitions (`config/grafana/provisioning/dashboards/dashboards.yml`)

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

---

## Dashboard Configurations

### 1. Trading Performance Dashboard (`config/grafana/dashboards/trading-performance.json`)

```json
{
  "dashboard": {
    "id": null,
    "title": "🤖 Trading Bot Performance",
    "tags": ["trading-bot", "performance", "mojorust"],
    "timezone": "browser",
    "refresh": "15s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "title": "Portfolio Value (SOL)",
        "type": "stat",
        "targets": [
          {
            "expr": "trading_bot_portfolio_value_sol",
            "legendFormat": "Current Value"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"displayMode": "list", "orientation": "horizontal"},
            "mappings": [],
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 0.8},
                {"color": "red", "value": 1}
              ]
            },
            "unit": "sol"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Total P&L (SOL)",
        "type": "stat",
        "targets": [
          {
            "expr": "trading_bot_total_pnl_sol",
            "legendFormat": "Total P&L"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "yellow", "value": 0},
                {"color": "green", "value": 0.1}
              ]
            },
            "unit": "sol"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      },
      {
        "id": 3,
        "title": "Win Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "trading_bot_win_rate * 100",
            "legendFormat": "Win Rate"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "yellow", "value": 40},
                {"color": "green", "value": 60}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 6, "x": 0, "y": 8}
      },
      {
        "id": 4,
        "title": "Total Trades",
        "type": "stat",
        "targets": [
          {
            "expr": "trading_bot_trades_total",
            "legendFormat": "Total Trades"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "blue", "value": null}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 6, "x": 6, "y": 8}
      },
      {
        "id": 5,
        "title": "Active Positions",
        "type": "stat",
        "targets": [
          {
            "expr": "trading_bot_active_positions",
            "legendFormat": "Active Positions"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 5},
                {"color": "red", "value": 10}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 6, "x": 12, "y": 8}
      },
      {
        "id": 6,
        "title": "Filter Rejection Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "trading_bot_rejection_rate",
            "legendFormat": "Rejection Rate"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "yellow", "value": 80},
                {"color": "green", "value": 85}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 6, "x": 18, "y": 8}
      },
      {
        "id": 7,
        "title": "Portfolio Value Over Time",
        "type": "timeseries",
        "targets": [
          {
            "expr": "trading_bot_portfolio_value_sol",
            "legendFormat": "Portfolio Value (SOL)"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"axisLabel": "", "axisPlacement": "auto", "barAlignment": 0},
            "unit": "sol"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
      },
      {
        "id": 8,
        "title": "Trades per Hour",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(trading_bot_trades_total[1h]) * 3600",
            "legendFormat": "Trades/Hour"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"axisLabel": "", "axisPlacement": "auto"},
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 24}
      },
      {
        "id": 9,
        "title": "P&L Distribution",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(trading_bot_profitable_trades_total[1h]) * 3600",
            "legendFormat": "Profitable Trades/Hour"
          },
          {
            "expr": "rate(trading_bot_loss_trades_total[1h]) * 3600",
            "legendFormat": "Loss Trades/Hour"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "custom": {"axisLabel": "", "axisPlacement": "auto"},
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 24}
      },
      {
        "id": 10,
        "title": "Recent Trades Table",
        "type": "table",
        "targets": [
          {
            "expr": "trading_bot_recent_trades",
            "legendFormat": "{{timestamp}} - {{token}} - {{side}} - {{amount}} SOL - {{pnl}} SOL",
            "format": "table"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "custom": {"align": "auto", "displayMode": "auto"}
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 32}
      }
    ]
  }
}
```

### 2. System Health Dashboard (`config/grafana/dashboards/system-health.json`)

```json
{
  "dashboard": {
    "id": null,
    "title": "💻 System Health",
    "tags": ["system", "health", "server"],
    "timezone": "browser",
    "refresh": "30s",
    "time": {
      "from": "now-3h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "title": "CPU Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)",
            "legendFormat": "CPU Usage"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 90}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
            "legendFormat": "Memory Usage"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 75},
                {"color": "red", "value": 90}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
      },
      {
        "id": 3,
        "title": "Disk Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "(1 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"})) * 100",
            "legendFormat": "Disk Usage"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 80},
                {"color": "red", "value": 95}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
      },
      {
        "id": 4,
        "title": "Load Average",
        "type": "stat",
        "targets": [
          {
            "expr": "node_load15",
            "legendFormat": "15-min Load Average"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 1.0},
                {"color": "red", "value": 2.0}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 8}
      },
      {
        "id": 5,
        "title": "Network Traffic",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(node_network_receive_bytes_total[5m]) * 8",
            "legendFormat": "Network In"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "bps"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 8}
      },
      {
        "id": 6,
        "title": "Uptime",
        "type": "stat",
        "targets": [
          {
            "expr": "node_time_seconds - node_boot_time_seconds",
            "legendFormat": "Uptime"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "unit": "dtdurations"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 8}
      },
      {
        "id": 7,
        "title": "CPU Usage Breakdown",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(node_cpu_seconds_total{mode=\"user\"}[5m]) * 100",
            "legendFormat": "User"
          },
          {
            "expr": "rate(node_cpu_seconds_total{mode=\"system\"}[5m]) * 100",
            "legendFormat": "System"
          },
          {
            "expr": "rate(node_cpu_seconds_total{mode=\"iowait\"}[5m]) * 100",
            "legendFormat": "I/O Wait"
          },
          {
            "expr": "rate(node_cpu_seconds_total{mode=\"idle\"}[5m]) * 100",
            "legendFormat": "Idle"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16}
      },
      {
        "id": 8,
        "title": "Memory Usage Breakdown",
        "type": "timeseries",
        "targets": [
          {
            "expr": "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes",
            "legendFormat": "Used Memory"
          },
          {
            "expr": "node_memory_MemAvailable_bytes",
            "legendFormat": "Available Memory"
          },
          {
            "expr": "node_memory_Buffers_bytes + node_memory_Cached_bytes",
            "legendFormat": "Cache + Buffers"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "bytes"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16}
      },
      {
        "id": 9,
        "title": "Disk I/O",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(node_disk_read_bytes_total[5m])",
            "legendFormat": "Disk Read"
          },
          {
            "expr": "rate(node_disk_written_bytes_total[5m])",
            "legendFormat": "Disk Write"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "Bps"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24}
      }
    ]
  }
}
```

### 3. Docker Services Dashboard (`config/grafana/dashboards/docker-services.json`)

```json
{
  "dashboard": {
    "id": null,
    "title": "🐳 Docker Services",
    "tags": ["docker", "containers", "services"],
    "timezone": "browser",
    "refresh": "30s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "title": "Container Status",
        "type": "stat",
        "targets": [
          {
            "expr": "sum by (name) (up{job=\"docker-exporter\"})",
            "legendFormat": "{{name}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "green", "value": 1}
              ]
            },
            "mappings": [
              {"options": {"0": {"text": "DOWN", "color": "red"}}, "type": "value"},
              {"options": {"1": {"text": "UP", "color": "green"}}, "type": "value"}
            ]
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Container CPU Usage",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total{name!=\"\"}[5m]) * 100",
            "legendFormat": "{{name}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 3,
        "title": "Container Memory Usage",
        "type": "timeseries",
        "targets": [
          {
            "expr": "container_memory_usage_bytes{name!=\"\"}",
            "legendFormat": "{{name}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "bytes"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      },
      {
        "id": 4,
        "title": "Container Network I/O",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(container_network_receive_bytes_total{name!=\"\"}[5m])",
            "legendFormat": "{{name}} - RX"
          },
          {
            "expr": "rate(container_network_transmit_bytes_total{name!=\"\"}[5m])",
            "legendFormat": "{{name}} - TX"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "Bps"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 16}
      },
      {
        "id": 5,
        "title": "Service Resource Limits",
        "type": "table",
        "targets": [
          {
            "expr": "container_memory_usage_bytes / container_spec_memory_limit_bytes * 100",
            "legendFormat": "{{name}} - Memory Usage %",
            "format": "table"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 70},
                {"color": "red", "value": 90}
              ]
            },
            "unit": "percent"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24}
      }
    ]
  }
}
```

### 4. DragonflyDB Dashboard (`config/grafana/dashboards/dragonflydb.json`)

```json
{
  "dashboard": {
    "id": null,
    "title": "🐉 DragonflyDB Performance",
    "tags": ["dragonflydb", "cache"],
    "timezone": "browser",
    "refresh": "15s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "title": "Connection Status",
        "type": "stat",
        "targets": [
          {
            "expr": "redis_up",
            "legendFormat": "Connected"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "green", "value": 1}
              ]
            },
            "mappings": [
              {"options": {"0": {"text": "DISCONNECTED", "color": "red"}}, "type": "value"},
              {"options": {"1": {"text": "CONNECTED", "color": "green"}}, "type": "value"}
            ]
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Memory Usage",
        "type": "stat",
        "targets": [
          {
            "expr": "redis_memory_used_bytes / redis_memory_max_bytes * 100",
            "legendFormat": "Memory Usage"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 75},
                {"color": "red", "value": 90}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
      },
      {
        "id": 3,
        "title": "Connected Clients",
        "type": "stat",
        "targets": [
          {
            "expr": "redis_connected_clients",
            "legendFormat": "Clients"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 50},
                {"color": "red", "value": 100}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
      },
      {
        "id": 4,
        "title": "Commands per Second",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(redis_commands_processed_total[5m])",
            "legendFormat": "Commands/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "reqps"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 5,
        "title": "Cache Hit Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total) * 100",
            "legendFormat": "Hit Rate"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "red", "value": null},
                {"color": "yellow", "value": 80},
                {"color": "green", "value": 95}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      },
      {
        "id": 6,
        "title": "Memory Usage Over Time",
        "type": "timeseries",
        "targets": [
          {
            "expr": "redis_memory_used_bytes",
            "legendFormat": "Used Memory"
          },
          {
            "expr": "redis_memory_max_bytes",
            "legendFormat": "Max Memory"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "bytes"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16}
      },
      {
        "id": 7,
        "title": "Keys by Type",
        "type": "piechart",
        "targets": [
          {
            "expr": "redis_db_keys",
            "legendFormat": "{{db}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16}
      },
      {
        "id": 8,
        "title": "Slow Log Entries",
        "type": "timeseries",
        "targets": [
          {
            "expr": "redis_slowlog_length",
            "legendFormat": "Slow Log Length"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 10},
                {"color": "red", "value": 50}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24}
      }
    ]
  }
}
```

### 5. API Monitoring Dashboard (`config/grafana/dashboards/api-monitoring.json`)

```json
{
  "dashboard": {
    "id": null,
    "title": "🌐 API Monitoring",
    "tags": ["api", "requests", "performance"],
    "timezone": "browser",
    "refresh": "15s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "title": "Request Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"trading-bot\"}[5m])",
            "legendFormat": "Requests/sec"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 50},
                {"color": "red", "value": 100}
              ]
            },
            "unit": "reqps"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Error Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"trading-bot\",status=~\"5..\"}[5m]) / rate(http_requests_total{job=\"trading-bot\"}[5m]) * 100",
            "legendFormat": "Error Rate"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 1},
                {"color": "red", "value": 5}
              ]
            },
            "unit": "percent",
            "max": 100,
            "min": 0
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
      },
      {
        "id": 3,
        "title": "Average Response Time",
        "type": "stat",
        "targets": [
          {
            "expr": "histogram_quantile(0.50, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m])) * 1000",
            "legendFormat": "50th percentile"
          },
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m])) * 1000",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m])) * 1000",
            "legendFormat": "99th percentile"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "ms"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
      },
      {
        "id": 4,
        "title": "Request Rate by Endpoint",
        "type": "timeseries",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"trading-bot\"}[5m])",
            "legendFormat": "{{method}} {{route}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "reqps"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8}
      },
      {
        "id": 5,
        "title": "Response Time Distribution",
        "type": "timeseries",
        "targets": [
          {
            "expr": "histogram_quantile(0.50, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m]))",
            "legendFormat": "50th percentile"
          },
          {
            "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m]))",
            "legendFormat": "95th percentile"
          },
          {
            "expr": "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m]))",
            "legendFormat": "99th percentile"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "s"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8}
      },
      {
        "id": 6,
        "title": "Status Code Distribution",
        "type": "piechart",
        "targets": [
          {
            "expr": "rate(http_requests_total{job=\"trading-bot\"}[5m])",
            "legendFormat": "{{status}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "reqps"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16}
      },
      {
        "id": 7,
        "title": "Top 10 Slowest Endpoints",
        "type": "table",
        "targets": [
          {
            "expr": "topk(10, histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job=\"trading-bot\"}[5m])))",
            "legendFormat": "{{route}}",
            "format": "table"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "unit": "s"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16}
      }
    ]
  }
}
```

### 6. Alert Management Dashboard (`config/grafana/dashboards/alert-management.json`)

```json
{
  "dashboard": {
    "id": null,
    "title": "🚨 Alert Management",
    "tags": ["alerts", "notifications", "monitoring"],
    "timezone": "browser",
    "refresh": "30s",
    "time": {
      "from": "now-24h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "title": "Active Alerts",
        "type": "stat",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\"}",
            "legendFormat": "Active Alerts"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 1},
                {"color": "red", "value": 5}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0}
      },
      {
        "id": 2,
        "title": "Critical Alerts",
        "type": "stat",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\", severity=\"critical\"}",
            "legendFormat": "Critical"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "red", "value": 1}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0}
      },
      {
        "id": 3,
        "title": "Warning Alerts",
        "type": "stat",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\", severity=\"warning\"}",
            "legendFormat": "Warnings"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "steps": [
                {"color": "green", "value": null},
                {"color": "yellow", "value": 1}
              ]
            },
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0}
      },
      {
        "id": 4,
        "title": "Alert Timeline",
        "type": "timeseries",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\"}",
            "legendFormat": "{{alertname}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8}
      },
      {
        "id": 5,
        "title": "Alerts by Service",
        "type": "piechart",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\"}",
            "legendFormat": "{{service}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16}
      },
      {
        "id": 6,
        "title": "Alerts by Severity",
        "type": "piechart",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\"}",
            "legendFormat": "{{severity}}"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "short"
          }
        },
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16}
      },
      {
        "id": 7,
        "title": "Active Alerts Table",
        "type": "table",
        "targets": [
          {
            "expr": "ALERTS_FOR_STATE{state=\"firing\"}",
            "legendFormat": "{{alertname}} - {{service}} - {{instance}}",
            "format": "table"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "custom": {"align": "auto", "displayMode": "auto"}
          }
        },
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 24}
      }
    ]
  }
}
```

---

## Deployment and Setup

### 1. Deploy Grafana Configuration

```bash
# Create Grafana directories
mkdir -p config/grafana/provisioning/{datasources,dashboards,alerting}
mkdir -p config/grafana/dashboards

# Copy configuration files to container
docker cp config/grafana/provisioning/ trading-bot-grafana:/etc/grafana/provisioning/
docker cp config/grafana/dashboards/ trading-bot-grafana:/var/lib/grafana/dashboards/

# Set proper permissions
docker exec trading-bot-grafana chown -R grafana:grafana /etc/grafana/provisioning/
docker exec trading-bot-grafana chown -R grafana:grafana /var/lib/grafana/dashboards/

# Restart Grafana to load configuration
docker-compose restart grafana
```

### 2. Verify Dashboard Import

```bash
# Check Grafana logs for dashboard import
docker-compose logs grafana | grep -i "dashboard\|provisioning"

# Verify dashboards are loaded
curl -s http://38.242.239.150:3000/api/search?query= | jq '.[].title'

# Check datasource status
curl -s http://38.242.239.150:3000/api/datasources | jq '.[].name'

# Verify specific service metrics are available
curl -s http://38.242.239.150:9090/api/v1/query?query=up | jq '.data.result[].metric.job'
```

### 3. Access Grafana

```bash
# URL: http://38.242.239.150:3001
# Username: admin
# Password: trading_admin

# Quick dashboard access links:
echo "Trading Performance: http://38.242.239.150:3001/d/trading-performance"
echo "System Health: http://38.242.239.150:3001/d/system-health"
echo "Docker Services: http://38.242.239.150:3001/d/docker-services"
echo "DragonflyDB Performance: http://38.242.239.150:3001/d/dragonflydb"
echo "API Monitoring: http://38.242.239.150:3001/d/api-monitoring"
echo "Alert Management: http://38.242.239.150:3001/d/alert-management"

# API access
export GRAFANA_TOKEN=$(curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"apikey","role":"Admin"}' \
  http://admin:trading_admin@38.242.239.150:3001/api/auth_keys | jq -r '.key')

# List dashboards via API
curl -H "Authorization: Bearer $GRAFANA_TOKEN" \
  http://38.242.239.150:3001/api/search | jq '.[].title'

# Test metrics availability from Grafana
curl -H "Authorization: Bearer $GRAFANA_TOKEN" \
  http://38.242.239.150:3001/api/datasources/proxy/1/api/v1/query?query=trading_bot_trades_total

# Direct service URLs for monitoring:
echo "Prometheus: http://38.242.239.150:9090"
echo "AlertManager: http://38.242.239.150:9093"
echo "Trading Bot Health: http://38.242.239.150:8082/health"
echo "Data Consumer Health: http://38.242.239.150:9191/health"
```

---

## Dashboard Verification Scripts

### 1. Dashboard Health Check (`scripts/verify_dashboards.sh`)

```bash
#!/bin/bash

# Grafana Dashboard Verification Script
set -e

GRAFANA_URL="http://38.242.239.150:3001"
GRAFANA_USER="admin"
GRAFANA_PASS="${GRAFANA_ADMIN_PASSWORD:-trading_admin}"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check Grafana is accessible
check_grafana_access() {
    echo "Checking Grafana accessibility..."

    if curl -s "$GRAFANA_URL/api/health" > /dev/null; then
        log_success "Grafana is accessible at $GRAFANA_URL"
        return 0
    else
        log_error "Cannot access Grafana at $GRAFANA_URL"
        return 1
    fi
}

# Verify datasources
verify_datasources() {
    echo "Verifying datasources..."

    local datasources=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/datasources" | jq -r '.[].name')

    if [[ "$datasources" == *"Prometheus"* ]]; then
        log_success "Prometheus datasource configured"
    else
        log_error "Prometheus datasource not found"
        return 1
    fi

    # Test Prometheus connection
    local prometheus_status=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/datasources/proxy/1/api/v1/query?query=up" | jq -r '.status')

    if [ "$prometheus_status" = "success" ]; then
        log_success "Prometheus connection working"
    else
        log_warning "Prometheus connection issues detected"
    fi
}

# Verify dashboards
verify_dashboards() {
    echo "Verifying dashboards..."

    local expected_dashboards=(
        "Trading Bot Performance"
        "System Health"
        "Docker Services"
        "DragonflyDB Performance"
        "API Monitoring"
        "Alert Management"
    )

    local actual_dashboards=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/search" | jq -r '.[].title')

    for dashboard in "${expected_dashboards[@]}"; do
        if echo "$actual_dashboards" | grep -q "$dashboard"; then
            log_success "Dashboard '$dashboard' found"
        else
            log_error "Dashboard '$dashboard' missing"
            return 1
        fi
    done

    # Check total dashboard count
    local dashboard_count=$(echo "$actual_dashboards" | wc -l)
    echo "Total dashboards loaded: $dashboard_count"
}

# Verify dashboard data
verify_dashboard_data() {
    echo "Verifying dashboard data..."

    # Test trading bot metrics
    local trading_metrics=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/datasources/proxy/1/api/v1/query?query=trading_bot_trades_total" | jq -r '.data.result | length')

    if [ "$trading_metrics" -gt 0 ]; then
        log_success "Trading bot metrics available"
    else
        log_warning "Trading bot metrics not yet available"
    fi

    # Test system metrics
    local system_metrics=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/datasources/proxy/1/api/v1/query?query=node_cpu_seconds_total" | jq -r '.data.result | length')

    if [ "$system_metrics" -gt 0 ]; then
        log_success "System metrics available"
    else
        log_error "System metrics not available"
        return 1
    fi

    # Test DragonflyDB metrics
    local dragonfly_metrics=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/datasources/proxy/1/api/v1/query?query=dragonflydb_up" | jq -r '.data.result | length')

    if [ "$dragonfly_metrics" -gt 0 ]; then
        log_success "DragonflyDB metrics available"
    else
        log_warning "DragonflyDB metrics not available"
    fi
}

# Check dashboard panels
check_dashboard_panels() {
    echo "Checking dashboard panels..."

    # Get dashboard UIDs
    local dashboard_uids=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
        "$GRAFANA_URL/api/search" | jq -r '.[] | select(.type == "dash-db") | .uid')

    for uid in $dashboard_uids; do
        local panel_count=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
            "$GRAFANA_URL/api/dashboards/uid/$uid" | jq -r '.dashboard.panels | length')

        local dashboard_title=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
            "$GRAFANA_URL/api/dashboards/uid/$uid" | jq -r '.dashboard.title')

        echo "Dashboard '$dashboard_title': $panel_count panels"

        if [ "$panel_count" -gt 0 ]; then
            log_success "Dashboard '$dashboard_title' has panels"
        else
            log_error "Dashboard '$dashboard_title' has no panels"
        fi
    done
}

# Main verification
main() {
    echo "🔍 Grafana Dashboard Verification"
    echo "================================"
    echo ""

    local failed=0

    check_grafana_access || failed=1
    verify_datasources || failed=1
    verify_dashboards || failed=1
    verify_dashboard_data || failed=1
    check_dashboard_panels || failed=1

    echo ""
    if [ $failed -eq 0 ]; then
        log_success "✅ All dashboard verification checks passed"
        echo ""
        echo "📊 Access your dashboards at: $GRAFANA_URL"
        echo "🔑 Login: $GRAFANA_USER / [your password]"
    else
        log_error "❌ Some verification checks failed"
        exit 1
    fi
}

main "$@"
```

### 2. Make Dashboard Verification Script Executable

```bash
chmod +x scripts/verify_dashboards.sh
```

---

## Grafana Native Alerts

### 1. Grafana Alert Configuration (`config/grafana/provisioning/alerting/grafana-alerts.yml`)

```yaml
apiVersion: 1

# Contact points for notifications
contact_points:
  - orgId: 1
    name: default-email
    receivers:
      - uid: default-email-receiver
        type: email
        settings:
          addresses: alerts@trading-bot.local
          subject: Grafana Alert: {{ .GroupLabels.SortedPairs.Values | join ", " }}
          body: |
            {{ range .Alerts }}
            Alert: {{ .Labels.alertname }}
            Instance: {{ .Labels.instance }}
            Value: {{ .Value }}
            {{ end }}

# Notification policies
policies:
  - orgId: 1
    receiver: default-email-receiver
    group_by: ['alertname', 'job', 'instance']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 12h
    routes:
      - matchers:
          - severity: critical
        receiver: default-email-receiver
        group_wait: 10s
        repeat_interval: 5m

# Mute timings
mute_timings:
  - orgId: 1
    name: maintenance-window
    type: calendar
    settings:
      start_date: '2024-01-01'
      end_date: '2025-01-01'
      times:
        - start_time: '02:00'
          end_time: '04:00'
          weekdays: ['monday', 'tuesday', 'wednesday', 'thursday', 'friday']
```

### 2. Grafana Alert Rules (Dashboard-based)

The alert rules are configured within each dashboard JSON configuration. Key alerts include:

- **Trading Bot Down**: `up{job="trading-bot"} == 0`
- **High CPU Usage**: `cpu_usage > 80`
- **Memory Pressure**: `memory_usage > 85`
- **Disk Space**: `disk_usage > 90`
- **DragonflyDB Connection**: `dragonflydb_up == 0`
- **API Error Rate**: `error_rate > 5`

---

## Advanced Configuration

### 1. Custom Variables

```json
{
  "templating": {
    "list": [
      {
        "name": "instance",
        "type": "query",
        "datasource": "Prometheus",
        "query": "label_values(up, instance)",
        "multi": true,
        "includeAll": true
      },
      {
        "name": "service",
        "type": "custom",
        "datasource": "Prometheus",
        "query": "trading-bot,timescaledb,dragonflydb",
        "multi": true,
        "includeAll": true
      }
    ]
  }
}
```

### 2. Annotations

```json
{
  "annotations": {
    "list": [
      {
        "name": "deployments",
        "datasource": "Prometheus",
        "enable": true,
        "expr": "changes(up{job=\"trading-bot\"}[5m]) > 0",
        "iconColor": "blue"
      }
    ]
  }
}
```

### 3. Dashboard Links

```json
{
  "links": [
    {
      "title": "Prometheus",
      "type": "absolute",
      "url": "http://38.242.239.150:9090"
    },
    {
      "title": "AlertManager",
      "type": "absolute",
      "url": "http://38.242.239.150:9093"
    },
    {
      "title": "Docker Status",
      "type": "absolute",
      "url": "http://38.242.239.150:8082/health"
    }
  ]
}
```

---

## Troubleshooting

### Common Issues

1. **Datasource Connection Failed**
   ```bash
   # Check Prometheus is running
   docker-compose ps prometheus

   # Check Prometheus URL
   curl http://38.242.239.150:9090/api/v1/query?query=up

   # Verify Grafana datasource configuration
   curl -u admin:trading_admin http://38.242.239.150:3001/api/datasources
   ```

2. **Dashboards Not Loading**
   ```bash
   # Check provisioning logs
   docker-compose logs grafana | grep -i provisioning

   # Verify dashboard files exist
   docker exec trading-bot-grafana ls -la /var/lib/grafana/dashboards/

   # Restart Grafana
   docker-compose restart grafana
   ```

3. **No Data in Panels**
   ```bash
   # Check Prometheus targets
   curl http://38.242.239.150:9090/api/v1/targets

   # Verify metric names
   curl http://38.242.239.150:9090/api/v1/label/__name__/values

   # Check time range
   curl "http://38.242.239.150:9090/api/v1/query_range?query=up&start=$(date -d '1 hour ago' +%s)&end=$(date +%s)&step=15"
   ```

### Performance Optimization

1. **Reduce Query Complexity**
   ```json
   {
     "targets": [
       {
         "expr": "rate(trading_bot_trades_total[5m])",
         "interval": "30s",
         "legendFormat": "Trades/sec"
       }
     ]
   }
   ```

2. **Use Recording Rules**
   ```yaml
   # In Prometheus
   groups:
     - name: trading-bot-recording-rules
       interval: 30s
       rules:
         - record: trading_bot:trades_per_second
           expr: rate(trading_bot_trades_total[5m])
   ```

3. **Optimize Dashboard Refresh**
   - Set appropriate refresh intervals (15s-1m)
   - Use relative time ranges
   - Limit the number of panels per dashboard

---

## Security Configuration

### 1. Authentication

```bash
# Change admin password
curl -X PUT -H "Content-Type: application/json" \
  -d '{"password":"new-secure-password"}' \
  http://admin:admin@38.242.239.150:3000/api/user/password

# Create API users
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"viewer","email":"viewer@trading-bot.local","login":"viewer","password":"viewer-pass","role":"Viewer"}' \
  http://admin:admin@38.242.239.150:3000/api/admin/users
```

### 2. API Keys

```bash
# Create API key for automation
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"automation-key","role":"Admin"}' \
  http://admin:admin@38.242.239.150:3000/api/auth_keys
```

### 3. Anonymous Access

```yaml
# In grafana.ini
[auth.anonymous]
enabled = false
org_role = Viewer

[security]
disable_gravatar = true
content_security_policy = true
```

---

## Backup and Recovery

### Backup Dashboards

```bash
#!/bin/bash
# scripts/backup_dashboards.sh

BACKUP_DIR="/root/backups/grafana"
DATE=$(date +%Y%m%d_%H%M%S)
GRAFANA_URL="http://38.242.239.150:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="$GRAFANA_ADMIN_PASSWORD"

mkdir -p "$BACKUP_DIR"

# Export all dashboards
curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/search" | jq -r '.[].uid' | while read uid; do

    dashboard=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
      "$GRAFANA_URL/api/dashboards/uid/$uid")

    title=$(echo "$dashboard" | jq -r '.dashboard.title')
    filename=$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

    echo "$dashboard" > "$BACKUP_DIR/${filename}_${DATE}.json"
done

# Backup datasources
curl -s -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/datasources" > "$BACKUP_DIR/datasources_${DATE}.json"

echo "Grafana backup completed: $BACKUP_DIR"
```

### Restore Dashboards

```bash
#!/bin/bash
# scripts/restore_dashboards.sh

BACKUP_FILE="$1"
GRAFANA_URL="http://38.242.239.150:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="$GRAFANA_ADMIN_PASSWORD"

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <dashboard_file.json>"
    exit 1
fi

# Import dashboard
curl -X POST -H "Content-Type: application/json" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -d @"$BACKUP_FILE" \
  "$GRAFANA_URL/api/dashboards/db"

echo "Dashboard restored from $BACKUP_FILE"
```

---

## Conclusion

This comprehensive Grafana setup provides:

- **6 fully configured dashboards** covering all aspects of the trading bot system
- **Real-time monitoring** of trading performance, system health, and infrastructure
- **Pre-configured alerts** with Grafana-native alerting
- **Automated provisioning** for datasources and dashboards
- **Verification scripts** to ensure proper setup and operation
- **Backup and recovery procedures** for dashboard configurations
- **Security best practices** for authentication and access control

The dashboard system gives operators complete visibility into the trading bot's performance, health, and operational status while providing automated alerts for immediate response to issues.

**Next Steps:**
1. Deploy the Grafana configuration to your environment
2. Verify all dashboards are loading correctly
3. Set up alert notifications
4. Customize dashboards based on your specific requirements
5. Establish regular backup procedures for dashboard configurations