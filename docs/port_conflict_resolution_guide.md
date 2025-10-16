# Port Conflict Resolution Guide

## Overview

This guide provides comprehensive procedures for identifying, diagnosing, and resolving port conflicts in the MojoRust Trading Bot deployment, with special focus on TimescaleDB port 5432 conflicts.

## Common Port Conflicts

### TimescaleDB Port 5432
- **Primary Conflict**: System PostgreSQL service
- **Secondary Conflicts**: Other PostgreSQL containers, applications using port 5432
- **Resolution**: Reconfigure to use port 5433 or stop conflicting services

### Grafana Port 3000
- **Conflicts**: Other Grafana instances, web applications
- **Resolution**: Reconfigure to port 3001 or higher

### Prometheus Port 9090
- **Conflicts**: Other Prometheus instances, monitoring tools
- **Resolution**: Reconfigure to port 9091 or higher

### AlertManager Port 9093
- **Conflicts**: Other AlertManager instances
- **Resolution**: Reconfigure to port 9094 or higher

## Automated Resolution Tools

### 1. Port Conflict Diagnosis

**Script**: `./scripts/diagnose_port_conflict.sh`

**Usage**:
```bash
# Standard diagnosis
./scripts/diagnose_port_conflict.sh

# JSON output for automation
./scripts/diagnose_port_conflict.sh --json

# Verbose diagnostic information
./scripts/diagnose_port_conflict.sh --verbose

# Check specific port
./scripts/diagnose_port_conflict.sh --port 5433
```

**Features**:
- Multi-tool support (lsof, netstat, ss)
- PostgreSQL service detection
- Docker container analysis
- Configuration file parsing
- JSON output for automation

### 2. Port Conflict Resolution

**Script**: `./scripts/resolve_port_conflict.sh`

**Usage**:
```bash
# Interactive resolution menu
./scripts/resolve_port_conflict.sh

# Non-automatic resolution with backups
./scripts/resolve_port_conflict.sh --no-backup
```

**Resolution Options**:
1. **Stop System PostgreSQL Service** - Safely stops systemd PostgreSQL service
2. **Stop Conflicting Docker Container** - Stops containers using the port
3. **Kill Process** - Direct process termination (last resort)
4. **Reconfigure TimescaleDB** - Changes port to 5433 (recommended)

### 3. Port Availability Verification

**Script**: `./scripts/verify_port_availability.sh`

**Usage**:
```bash
# Verify all required ports
./scripts/verify_port_availability.sh

# Continuous monitoring mode
./scripts/verify_port_availability.sh --watch

# JSON output
./scripts/verify_port_availability.sh --json

# Pre-deployment validation
./scripts/verify_port_availability.sh --pre-deploy
```

**Monitored Ports**:
- TimescaleDB: 5432 (or configured port)
- Prometheus: 9090
- Grafana: 3001
- AlertManager: 9093
- pgAdmin: 8081
- Trading Bot: 8082
- cAdvisor: 8083
- Node Exporter: 9100
- Data Consumer: 9191

## Manual Resolution Procedures

### Option 1: Stop System PostgreSQL Service

**When to Use**: System PostgreSQL service is not needed for the trading bot

```bash
# Check if PostgreSQL service is active
sudo systemctl status postgresql

# Stop PostgreSQL service
sudo systemctl stop postgresql

# Disable PostgreSQL service (prevent auto-start)
sudo systemctl disable postgresql

# Verify port 5432 is now available
./scripts/verify_port_availability.sh --port 5432
```

**Rollback**:
```bash
# Re-enable PostgreSQL service
sudo systemctl enable postgresql
sudo systemctl start postgresql
```

### Option 2: Reconfigure TimescaleDB Port

**When to Use**: Want to keep system PostgreSQL running

1. **Update .env file**:
```bash
# Edit .env file
TIMESCALEDB_PORT=5433
```

2. **Update docker-compose.yml** (already configured):
```yaml
ports:
  - "${TIMESCALEDB_PORT:-5432}:5432"
```

3. **Restart services**:
```bash
docker-compose down
docker-compose up -d timescaledb
```

### Option 3: Stop Conflicting Docker Container

**When to Use**: Another Docker container is using the port

```bash
# Find containers using port 5432
docker ps --filter "publish=5432"

# Stop conflicting container
docker stop <container_name>

# Optional: Remove container
docker rm <container_name>
```

## Port Configuration Architecture

### Environment Variable Configuration

The system supports flexible port configuration through environment variables:

```bash
# TimescaleDB external port
TIMESCALEDB_PORT=5432

# Grafana port (hardcoded in docker-compose.yml)
GRAFANA_PORT=3001

# Prometheus port (hardcoded in docker-compose.yml)
PROMETHEUS_PORT=9090
```

### Docker Compose Port Mapping

```yaml
services:
  timescaledb:
    ports:
      # External port can be configured via TIMESCALEDB_PORT
      # Internal container port remains 5432 for container communication
      - "${TIMESCALEDB_PORT:-5432}:5432"
```

### Application Configuration Updates

Applications automatically use the configured external ports:

- **Trading Bot**: Connects to `timescaledb:5432` (internal container port)
- **Monitoring Tools**: Connect to external ports via host network
- **External Access**: Uses configured external ports

## Prevention Strategies

### 1. Pre-Deployment Port Check

Always run port availability verification before deployment:

```bash
#!/bin/bash
# Pre-deployment check script
./scripts/verify_port_availability.sh --pre-deploy

if [ $? -eq 0 ]; then
    echo "✅ All ports available, proceeding with deployment"
    docker-compose up -d
else
    echo "❌ Port conflicts detected, resolve before deployment"
    exit 1
fi
```

### 2. Development Environment Isolation

Use different ports for development:

```bash
# Development .env configuration
TIMESCALEDB_PORT=5433
```

### 3. Docker Network Isolation

Use custom Docker networks to avoid port conflicts:

```yaml
networks:
  trading-network:
    driver: bridge
    internal: false  # Set to true for complete isolation
```

## Troubleshooting

### Port Still in Use After Service Stop

**Symptoms**: Port shows as in use even after stopping services

**Causes**:
- Process is running in a different namespace
- Docker container is still running
- Service is being restarted automatically

**Solutions**:
1. Check for running processes:
```bash
sudo lsof -i :5432
```

2. Check Docker containers:
```bash
docker ps --filter "publish=5432"
```

3. Kill process directly:
```bash
sudo kill -TERM <PID>
```

### Permission Denied Errors

**Symptoms**: Cannot stop services or bind to ports

**Causes**: Insufficient privileges

**Solutions**:
1. Use sudo for system services:
```bash
sudo systemctl stop postgresql
```

2. Add user to docker group:
```bash
sudo usermod -aG docker $USER
# Log out and back in for changes to take effect
```

### Service Auto-Restart Issues

**Symptoms**: Service restarts after being stopped

**Causes**: Systemd service is configured to auto-restart

**Solutions**:
1. Disable the service:
```bash
sudo systemctl disable postgresql
sudo systemctl mask postgresql
```

2. Use kill signal:
```bash
sudo systemctl kill postgresql
```

## Integration with Deployment Scripts

### Automated Port Conflict Resolution

The deployment pipeline can automatically detect and resolve port conflicts:

```bash
#!/bin/bash
# deploy_with_port_resolution.sh

# Check for port conflicts
if ! ./scripts/verify_port_availability.sh --pre-deploy; then
    echo "Port conflicts detected, attempting resolution..."

    # Try to resolve conflicts automatically
    ./scripts/resolve_port_conflict.sh --force

    # Verify resolution
    if ! ./scripts/verify_port_availability.sh --pre-deploy; then
        echo "Failed to resolve port conflicts automatically"
        echo "Please run: ./scripts/resolve_port_conflict.sh"
        exit 1
    fi
fi

# Proceed with deployment
echo "All ports available, proceeding with deployment..."
docker-compose up -d
```

### Health Check Integration

Health checks verify port availability:

```bash
#!/bin/bash
# Health check script
./scripts/verify_port_availability.sh --json > /tmp/port_status.json

# Integrate with monitoring
if [ $? -ne 0 ]; then
    # Send alert
    curl -X POST "$ALERT_WEBHOOK_URL" -d "Port conflicts detected"
fi
```

## Best Practices

### 1. Port Planning
- Plan port assignments ahead of time
- Document port usage in configuration files
- Use environment-specific port configurations

### 2. Monitoring
- Regularly monitor port usage
- Set up alerts for port conflicts
- Log port allocation changes

### 3. Documentation
- Document all port changes
- Keep port configuration in version control
- Maintain port conflict resolution procedures

### 4. Testing
- Test port conflict resolution procedures
- Validate port availability before deployments
- Use staging environments for port configuration testing

## Emergency Procedures

### Production Port Conflict

**Scenario**: Critical port conflict in production environment

**Procedure**:
1. **Assess Impact**: Identify affected services
2. **Quick Resolution**: Use automated resolution script
3. **Service Recovery**: Restart affected services
4. **Monitoring**: Verify all services are healthy
5. **Documentation**: Record incident and resolution

### Complete Port Reassignment

**Scenario**: Major port reassignment needed

**Procedure**:
1. **Planning**: Map new port assignments
2. **Configuration**: Update all configuration files
3. **Testing**: Validate in staging environment
4. **Deployment**: Deploy with zero-downtime if possible
5. **Verification**: Confirm all services working
6. **Cleanup**: Remove old port configurations

## Support and Escalation

### When to Escalate
- Automated resolution fails repeatedly
- Critical services remain unavailable
- Unknown processes are using ports
- Security concerns about port usage

### Information to Collect
- Port conflict diagnostic output
- System logs
- Docker container status
- Service configuration files
- Recent changes to the system

### Escalation Contacts
- System Administrator
- Network Team
- Security Team
- Application Support

---

**Version**: 1.0
**Last Updated**: 2024-10-15
**Related Documents**: [OPERATIONS_RUNBOOK.md](./OPERATIONS_RUNBOOK.md), [DOCKER_DEPLOYMENT_GUIDE.md](./DOCKER_DEPLOYMENT_GUIDE.md)