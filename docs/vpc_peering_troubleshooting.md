# VPC Peering Troubleshooting Guide

## Overview

This guide provides comprehensive troubleshooting procedures for VPC peering connectivity issues between the MojoRust Trading Bot and DragonflyDB Cloud. It covers common problems, diagnostic techniques, and resolution strategies.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS VPC (Trading Bot)                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │               ECS/Docker Containers                 │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│  │  │Trading Bot  │  │TimescaleDB  │  │Monitoring   │ │    │
│  │  │             │  │             │  │Services     │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │    │
│  └─────────────────────────────────────────────────────┘    │
│                         │                                   │
│                    VPC Peering                                │
│                    Connection                                 │
│                         │                                   │
│  ┌─────────────────────────────────────────────────────┐    │
│  │               DragonflyDB Cloud VPC                  │    │
│  │            ┌─────────────────────────┐               │    │
│  │            │    DragonflyDB Cluster  │               │    │
│  │            │   (Private IP: 10.0.0.5) │               │    │
│  │            └─────────────────────────┘               │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Quick Diagnostic Commands

### 1. Basic Connectivity Tests

```bash
# Test DNS resolution
nslookup 612ehcb9i.dragonflydb.cloud

# Test TCP connectivity
timeout 5 bash -c "</dev/tcp/612ehcb9i.dragonflydb.cloud/6385"

# Test from within container
docker-compose exec trading-bot nslookup 612ehcb9i.dragonflydb.cloud

# Test Redis connection
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} ping
```

### 2. VPC Peering Status Check

```bash
# Check VPC peering connection status
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-0123456789abcdef0

# Check route table entries
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0

# Verify DragonflyDB connection
./scripts/verify_dragonflydb_connection.sh --vpc-only --verbose
```

### 3. Performance Metrics

```bash
# Check latency
./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms'

# Monitor bandwidth
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | jq '.data.result[0].value[1]'

# Check packet loss
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_packets_dropped_total[5m])' | jq '.data.result[0].value[1]'
```

## Common Issues and Solutions

### Issue 1: VPC Peering Connection Down

**Symptoms:**
- `VPCPeeringConnectionDown` alert firing
- DragonflyDB connection timeouts
- Trading bot unable to connect to Redis

**Diagnostic Steps:**

1. **Check VPC Peering Status**
```bash
# Get peering connection status
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-0123456789abcdef0 \
  --query 'VpcPeeringConnections[0].Status.Code'
```

2. **Verify Route Tables**
```bash
# Check if routes exist in both VPCs
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0 \
  --query 'RouteTables[*].Routes[?DestinationCidrBlock==`10.1.0.0/16`]'
```

3. **Check Security Group Rules**
```bash
# Verify egress rules from trading bot VPC
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissionsEgress[?IpProtocol==`tcp`]'
```

**Resolution Steps:**

1. **Restart VPC Peering Connection**
```bash
# If peering is in 'failed' state, delete and recreate
aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id pcx-0123456789abcdef0

# Recreate using setup script
./scripts/setup_vpc_peering.sh --recreate
```

2. **Update Route Tables**
```bash
# Add missing routes
aws ec2 create-route \
  --route-table-id rtb-0123456789abcdef0 \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id pcx-0123456789abcdef0
```

3. **Update Security Groups**
```bash
# Add egress rule for DragonflyDB port
aws ec2 authorize-security-group-egress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp \
  --port 6385 \
  --cidr 10.1.0.0/16
```

### Issue 2: High Latency on VPC Connection

**Symptoms:**
- `DragonflyDBHighLatency` alerts firing
- Slow trading bot performance
- High response times from Redis

**Diagnostic Steps:**

1. **Measure Current Latency**
```bash
# Check real-time latency
./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms'

# Monitor latency trends
curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m]))' \
  --data-urlencode 'start='$(( $(date +%s) - 3600 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1m' | jq '.data.result[0].values[-10:]'
```

2. **Check Bandwidth Utilization**
```bash
# Monitor bandwidth usage
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | \
  jq -r '"Current bandwidth: " + (.data.result[0].value[1] | tonumber / 1024 / 1024 | floor | tostring) + " MB/s"'
```

3. **Check for Network Congestion**
```bash
# Check packet loss
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_packets_dropped_total[5m])' | jq '.data.result[0].value[1]'

# Check retransmissions
netstat -s | grep -i "segments retransmitted"
```

**Resolution Steps:**

1. **Optimize Connection Pooling**
```bash
# Update Redis connection pool settings
docker-compose exec trading-bot python -c "
import redis
import json
r = redis.Redis(connection_pool_max_connections=50, socket_timeout=5)
print('Connection pool optimized')
"
```

2. **Consider VPC Peering Upgrade**
```bash
# Check if upgrade to Enhanced VPC Peering is needed
current_bandwidth=$(curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | \
  jq -r '.data.result[0].value[1] | tonumber / 1024 / 1024 | floor')

if [ "$current_bandwidth" -gt 800 ]; then
    echo "Consider upgrading to Enhanced VPC Peering"
fi
```

3. **Optimize DragonflyDB Queries**
```bash
# Check slow queries
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} slowlog get 10

# Monitor DragonflyDB performance
docker-compose exec trading-bot redis-cli -u ${REDIS_URL} info stats
```

### Issue 3: DNS Resolution Failures

**Symptoms:**
- `DragonflyDBDNSFailure` alerts firing
- Unable to resolve DragonflyDB endpoint
- Connection timeouts

**Diagnostic Steps:**

1. **Test DNS Resolution**
```bash
# Test from host
nslookup 612ehcb9i.dragonflydb.cloud

# Test from within container
docker-compose exec trading-bot nslookup 612ehcb9i.dragonflydb.cloud

# Test with different DNS servers
nslookup 612ehcb9i.dragonflydb.cloud 8.8.8.8
nslookup 612ehcb9i.dragonflydb.cloud 1.1.1.1
```

2. **Check DNS Configuration**
```bash
# Check Docker DNS settings
docker info | grep -i dns

# Check container DNS configuration
docker-compose exec trading-bot cat /etc/resolv.conf

# Check system DNS configuration
cat /etc/resolv.conf
```

3. **Test Direct IP Connection**
```bash
# Get DragonflyDB private IP
DRAGONFLY_IP=$(aws ec2 describe-instances --filters Name=tag:Name,Values=dragonflydb \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

# Test direct IP connection
timeout 5 bash -c "</dev/tcp/$DRAGONFLY_IP/6385"
```

**Resolution Steps:**

1. **Fix DNS Configuration**
```bash
# Update Docker daemon DNS settings
cat > /etc/docker/daemon.json << EOF
{
  "dns": ["8.8.8.8", "1.1.1.1", "10.0.0.2"]
}
EOF

systemctl restart docker

# Restart containers
docker-compose restart trading-bot
```

2. **Use IP Address Fallback**
```bash
# Update Redis URL to use IP address
sed -i 's/612ehcb9i.dragonflydb.cloud/10.1.0.5/g' .env

# Restart services
docker-compose restart trading-bot

# Test connection
./scripts/verify_dragonflydb_connection.sh --vpc-only
```

3. **Add DNS Entries**
```bash
# Add local DNS entry
echo "10.1.0.5 612ehcb9i.dragonflydb.cloud" >> /etc/hosts

# Add to container hosts file
docker-compose exec trading-bot sh -c "echo '10.1.0.5 612ehcb9i.dragonflydb.cloud' >> /etc/hosts"
```

### Issue 4: Security Group Blocking Traffic

**Symptoms:**
- Connection timeouts
- `SecurityGroupMisconfigured` alerts
- Traffic being dropped

**Diagnostic Steps:**

1. **Check Security Group Rules**
```bash
# Check egress rules from trading bot VPC
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissionsEgress[]'

# Check ingress rules to DragonflyDB VPC
aws ec2 describe-security-groups --filters Name=vpc-id,Values=vpc-0123456789abcdef1 \
  --query 'SecurityGroups[].IpPermissions[?FromPort==`6385`]'
```

2. **Test Traffic Flow**
```bash
# Use tcpdump to monitor traffic
tcpdump -i any host 612ehcb9i.dragonflydb.cloud and port 6385

# Use netstat to check connections
netstat -an | grep 6385
```

3. **Check Network ACLs**
```bash
# Check NACLs for both subnets
aws ec2 describe-network-acls --filters Name=vpc-id,Values=vpc-0123456789abcdef0

# Check NACL associations
aws ec2 describe-network-acls --filters Name=association.subnet-id,Values=subnet-0123456789abcdef0
```

**Resolution Steps:**

1. **Update Security Group Rules**
```bash
# Add egress rule for DragonflyDB
aws ec2 authorize-security-group-egress \
  --group-id sg-0123456789abcdef0 \
  --protocol tcp \
  --port 6385 \
  --cidr 10.1.0.0/16

# Add ingress rule to DragonflyDB security group
aws ec2 authorize-security-group-ingress \
  --group-id sg-fedcba9876543210f \
  --protocol tcp \
  --port 6385 \
  --cidr 10.0.0.0/16
```

2. **Update Network ACLs**
```bash
# Allow traffic in NACLs
aws ec2 create-network-acl-entry \
  --network-acl-id acl-0123456789abcdef0 \
  --rule-number 100 \
  --protocol -1 \
  --rule-action allow \
  --egress \
  --cidr-block 10.1.0.0/16
```

### Issue 5: Route Table Misconfiguration

**Symptoms:**
- VPC peering connection active but no traffic
- Routes not being applied
- Blackhole routes in route tables

**Diagnostic Steps:**

1. **Check Route Tables**
```bash
# List all route tables for VPC
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0 \
  --query 'RouteTables[*].{Id:RouteTableId, Routes:Routes}'

# Check for blackhole routes
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0 \
  --query 'RouteTables[].Routes[?State==`blackhole`]'
```

2. **Verify Route Propagation**
```bash
# Check if routes are being propagated
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0 \
  --query 'RouteTables[*].PropagatingVgws'
```

3. **Check VPC Peering Status**
```bash
# Verify peering is active
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-0123456789abcdef0 \
  --query 'VpcPeeringConnections[0].Status.Code'
```

**Resolution Steps:**

1. **Add Missing Routes**
```bash
# Add route to DragonflyDB VPC
aws ec2 create-route \
  --route-table-id rtb-0123456789abcdef0 \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id pcx-0123456789abcdef0

# Add return route
aws ec2 create-route \
  --route-table-id rtb-fedcba9876543210f \
  --destination-cidr-block 10.0.0.0/16 \
  --vpc-peering-connection-id pcx-0123456789abcdef0
```

2. **Replace Blackhole Routes**
```bash
# Delete blackhole route
aws ec2 delete-route \
  --route-table-id rtb-0123456789abcdef0 \
  --destination-cidr-block 10.1.0.0/16

# Recreate route
aws ec2 create-route \
  --route-table-id rtb-0123456789abcdef0 \
  --destination-cidr-block 10.1.0.0/16 \
  --vpc-peering-connection-id pcx-0123456789abcdef0
```

## Advanced Troubleshooting

### Network Performance Analysis

**Bandwidth Utilization Analysis:**
```bash
# Analyze bandwidth usage patterns
curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' \
  --data-urlencode 'start='$(( $(date +%s) - 86400 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=5m' | jq '.data.result[0].values[] | select(.[1] | tonumber > 800000000)'

# Check for bandwidth spikes
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | \
  jq -r 'if (.data.result[0].value[1] | tonumber) > 800000000 then "HIGH BANDWIDTH: " + (.data.result[0].value[1] | tonumber / 1024 / 1024 | floor | tostring) + " MB/s" else "Bandwidth normal" end'
```

**Packet Loss Analysis:**
```bash
# Monitor packet loss over time
curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_packets_dropped_total[5m])' \
  --data-urlencode 'start='$(( $(date +%s) - 3600 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1m' | jq '.data.result[0].values[] | select(.[1] | tonumber > 0)'

# Check connection quality
./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering | {latency_ms, packet_loss_percent, connection_quality}'
```

### Connection Pool Optimization

**Redis Connection Pool Tuning:**
```bash
# Monitor connection pool metrics
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=redis_connected_clients' | jq '.data.result[0].value[1]'

# Monitor connection creation rate
curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(redis_connections_received_total[5m])' | jq '.data.result[0].value[1]'

# Optimize connection pool
docker-compose exec trading-bot python -c "
import redis
import json

# Create optimized connection pool
pool = redis.ConnectionPool(
    host='612ehcb9i.dragonflydb.cloud',
    port=6385,
    password='gv7g6u9svsf1',
    ssl=True,
    max_connections=50,
    socket_keepalive=True,
    socket_keepalive_options={},
    health_check_interval=30
)

r = redis.Redis(connection_pool=pool)
print('Connection pool optimized:', pool.connection_kwargs)
"
```

### Monitoring and Alerting

**Set Up Custom Alerts:**
```bash
# Create high latency alert
cat > config/prometheus_rules/vpc_custom_alerts.yml << EOF
groups:
  - name: vpc.peering.custom.rules
    rules:
      - alert: VPCPeeringHighLatencySpike
        expr: histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m])) > 0.1
        for: 2m
        labels:
          severity: warning
          service: vpc-peering
        annotations:
          summary: "VPC peering latency spike detected"
          description: "VPC peering latency is {{ $value }}s for the last 2 minutes"

      - alert: VPCPeeringBandwidthSpike
        expr: rate(aws_vpc_flow_logs_bytes_total[5m]) > 1000000000
        for: 5m
        labels:
          severity: warning
          service: vpc-peering
        annotations:
          summary: "VPC peering bandwidth spike"
          description: "VPC peering bandwidth is {{ $value | humanizeBytes }}/s"
EOF

# Reload Prometheus rules
curl -X POST http://localhost:9090/-/reload
```

## Emergency Procedures

### Complete VPC Peering Failover

**Scenario**: VPC peering completely fails

```bash
#!/bin/bash
# scripts/vpc_emergency_failover.sh

echo "🚨 VPC Peering Emergency Failover - $(date)"
echo "========================================"

# 1. Confirm VPC peering is down
echo "🔍 Confirming VPC peering failure..."
if ! ./scripts/verify_dragonflydb_connection.sh --vpc-only --quiet; then
    echo "❌ VPC peering confirmed down"
else
    echo "✅ VPC peering is working, aborting failover"
    exit 1
fi

# 2. Start local Redis fallback
echo "🐉 Starting local Redis fallback..."
docker-compose up -d redis-fallback

# 3. Update configuration to use local Redis
echo "⚙️  Updating configuration..."
cp .env .env.backup
sed -i 's|rediss://612ehcb9i.dragonflydb.cloud:6385|redis://localhost:6379|g' .env

# 4. Restart services
echo "🔄 Restarting services..."
docker-compose restart trading-bot

# 5. Verify failover
echo "✅ Verifying failover..."
sleep 30
if ./scripts/verify_dragonflydb_connection.sh --quiet; then
    echo "✅ Failover successful"
else
    echo "❌ Failover failed"
    # Restore original configuration
    mv .env.backup .env
    docker-compose restart trading-bot
    exit 1
fi

# 6. Notify team
echo "📢 Sending failover notification..."
echo "VPC peering emergency failover completed at $(date)" | \
    mail -s "EMERGENCY: VPC Peering Failover" admin@trading-bot.local

echo "🎉 Emergency failover completed"
echo "📋 Next steps:"
echo "1. Investigate VPC peering failure"
echo "2. Contact DragonflyDB support if needed"
echo "3. Restore VPC peering when available"
echo "4. Switch back to VPC peering"
```

### Partial Service Degradation

**Scenario**: VPC peering working but with high latency

```bash
#!/bin/bash
# scripts/vpc_performance_degradation.sh

echo "⚠️  VPC Peering Performance Degradation - $(date)"
echo "=============================================="

# 1. Check current performance
echo "📊 Checking current performance..."
latency=$(./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms')
bandwidth=$(curl -s -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' | \
  jq -r '.data.result[0].value[1] | tonumber / 1024 / 1024 | floor')

echo "Current latency: ${latency}ms"
echo "Current bandwidth: ${bandwidth}MB/s"

# 2. Apply performance optimizations
echo "⚡ Applying performance optimizations..."

# Increase connection pool size
docker-compose exec trading-bot python -c "
import redis
pool = redis.ConnectionPool(max_connections=100, socket_timeout=10)
r = redis.Redis(connection_pool=pool)
print('Connection pool increased to 100')
"

# Enable connection keepalive
docker-compose exec trading-bot python -c "
import redis
pool = redis.ConnectionPool(socket_keepalive=True, health_check_interval=15)
r = redis.Redis(connection_pool=pool)
print('Keepalive enabled with 15s health check')
"

# 3. Monitor improvements
echo "📈 Monitoring improvements..."
sleep 60

new_latency=$(./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms')
echo "New latency: ${new_latency}ms"

if (( $(echo "$new_latency < $latency" | bc -l) )); then
    echo "✅ Performance improved"
else
    echo "❌ Performance not improved"
    echo "💡 Consider failover to local Redis"
fi

# 4. Set up enhanced monitoring
echo "📊 Setting up enhanced monitoring..."
curl -X POST http://localhost:9090/-/reload

echo "✅ Performance degradation handling completed"
```

## Recovery Procedures

### VPC Peering Recovery

```bash
#!/bin/bash
# scripts/vpc_recovery.sh

echo "🔄 VPC Peering Recovery - $(date)"
echo "==============================="

# 1. Diagnose the issue
echo "🔍 Diagnosing VPC peering issue..."
./scripts/verify_dragonflydb_connection.sh --vpc-only --verbose

# 2. Check if it's a known issue
echo -e "\n🔍 Checking for known issues..."

# Check DNS resolution
if ! nslookup 612ehcb9i.dragonflydb.cloud >/dev/null 2>&1; then
    echo "❌ DNS resolution failed"
    echo "🔄 Fixing DNS..."
    systemctl restart systemd-resolved
    sleep 10
fi

# Check VPC peering status
peering_status=$(aws ec2 describe-vpc-peering-connections \
  --vpc-peering-connection-ids pcx-0123456789abcdef0 \
  --query 'VpcPeeringConnections[0].Status.Code' --output text)

if [ "$peering_status" != "active" ]; then
    echo "❌ VPC peering not active: $peering_status"
    echo "🔄 Recreating VPC peering..."
    ./scripts/setup_vpc_peering.sh --recreate
fi

# 3. Test connectivity
echo -e "\n🔗 Testing connectivity..."
if ./scripts/verify_dragonflydb_connection.sh --vpc-only --quiet; then
    echo "✅ Connectivity restored"
else
    echo "❌ Connectivity still failing"
    echo "🔄 Checking security groups and routes..."

    # Check security group rules
    aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0 \
      --query 'SecurityGroups[0].IpPermissionsEgress[?ToPort==`6385`]'

    # Check route tables
    aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0 \
      --query 'RouteTables[*].Routes[?DestinationCidrBlock==`10.1.0.0/16`]'
fi

# 4. If still failing, use direct IP
echo -e "\n🔄 Attempting direct IP connection..."
DRAGONFLY_IP=$(aws ec2 describe-instances --filters Name=tag:Name,Values=dragonflydb \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

if [ -n "$DRAGONFLY_IP" ] && timeout 5 bash -c "</dev/tcp/$DRAGONFLY_IP/6385"; then
    echo "✅ Direct IP connection successful"
    echo "🔄 Updating configuration..."
    sed -i "s/612ehcb9i.dragonflydb.cloud/$DRAGONFLY_IP/g" .env
    docker-compose restart trading-bot
else
    echo "❌ Direct IP connection failed"
    echo "🔄 Initiating emergency failover..."
    ./scripts/vpc_emergency_failover.sh
fi

# 5. Verify recovery
echo -e "\n✅ Verifying recovery..."
sleep 30
./scripts/verify_dragonflydb_connection.sh --vpc-only

echo "🎉 VPC peering recovery completed"
```

## Monitoring and Prevention

### Proactive Monitoring

**Set Up Automated Monitoring:**
```bash
#!/bin/bash
# scripts/vpc_monitoring.sh

echo "📊 VPC Peering Monitoring Setup - $(date)"
echo "=========================================="

# 1. Create monitoring script
cat > /usr/local/bin/vpc_health_check.sh << 'EOF'
#!/bin/bash

# Check VPC peering health
if ! ./scripts/verify_dragonflydb_connection.sh --vpc-only --quiet; then
    echo "❌ VPC peering health check failed at $(date)"

    # Send alert
    curl -X POST "$ALERT_WEBHOOK_URL" -d "VPC peering health check failed"

    # Log incident
    echo "$(date): VPC peering health check failed" >> /var/log/vpeering_health.log

    # Attempt recovery
    ./scripts/vpc_recovery.sh
else
    echo "✅ VPC peering health check passed at $(date)"
fi
EOF

chmod +x /usr/local/bin/vpc_health_check.sh

# 2. Set up cron job
echo "*/5 * * * * root /usr/local/bin/vpc_health_check.sh" > /etc/cron.d/vpc_health_check

# 3. Create performance monitoring script
cat > /usr/local/bin/vpc_performance_check.sh << 'EOF'
#!/bin/bash

# Check VPC peering performance
latency=$(./scripts/verify_dragonflydb_connection.sh --vpc-only --json | jq '.vpc_peering.latency_ms')

if (( $(echo "$latency > 100" | bc -l) )); then
    echo "⚠️  High latency detected: ${latency}ms"

    # Send alert
    curl -X POST "$ALERT_WEBHOOK_URL" -d "VPC peering high latency: ${latency}ms"

    # Log incident
    echo "$(date): High latency ${latency}ms" >> /var/log/vpc_performance.log
fi
EOF

chmod +x /usr/local/bin/vpc_performance_check.sh

# 4. Set up performance monitoring cron
echo "*/10 * * * * root /usr/local/bin/vpc_performance_check.sh" > /etc/cron.d/vpc_performance_check

echo "✅ VPC peering monitoring setup completed"
```

### Preventive Maintenance

**Weekly VPC Health Check:**
```bash
#!/bin/bash
# scripts/weekly_vpc_health_check.sh

echo "🔍 Weekly VPC Peering Health Check - $(date)"
echo "============================================="

# 1. Check VPC peering configuration
echo "📋 Checking VPC peering configuration..."
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-0123456789abcdef0 \
  --query 'VpcPeeringConnections[0].{Status:Status, RequesterVpc:RequesterVpcId, AccepterVpc:AccepterVpcId}'

# 2. Check route tables
echo -e "\n🛣️  Checking route tables..."
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-0123456789abcdef0 \
  --query 'RouteTables[*].{Id:RouteTableId, Routes:Routes[?DestinationCidrBlock==`10.1.0.0/16`]}'

# 3. Check security groups
echo -e "\n🛡️  Checking security groups..."
aws ec2 describe-security-groups --group-ids sg-0123456789abcdef0 \
  --query 'SecurityGroups[0].IpPermissionsEgress[?ToPort==`6385`]'

# 4. Performance analysis
echo -e "\n📊 Performance analysis..."
curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=histogram_quantile(0.95, rate(redis_slowlog_length_seconds_bucket[5m]))' \
  --data-urlencode 'start='$(( $(date +%s) - 604800 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1h' | jq -r '"Average 95th percentile latency: " + (.data.result[0].values | map(.value[1] | tonumber) | add / length | . * 1000 | floor | tostring) + "ms"'

# 5. Bandwidth utilization
echo -e "\n📈 Bandwidth utilization..."
total_bytes=$(curl -s -G 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(aws_vpc_flow_logs_bytes_total[5m])' \
  --data-urlencode 'start='$(( $(date +%s) - 604800 )) \
  --data-urlencode 'end='$(date +%s) \
  --data-urlencode 'step=1h' | jq -r '.data.result[0].values | map(.value[1] | tonumber) | add | floor')

echo "Total weekly bandwidth: $(( total_bytes / 1024 / 1024 / 1024 )) GB"

# 6. Generate recommendations
echo -e "\n💡 Recommendations:"
echo "- Monitor bandwidth utilization weekly"
echo "- Set up alerts for latency > 100ms"
echo "- Review VPC peering configuration monthly"
echo "- Test failover procedures quarterly"

echo "✅ Weekly VPC health check completed"
```

## Conclusion

This VPC peering troubleshooting guide provides comprehensive procedures for:

- **Quick diagnosis** of VPC peering issues
- **Step-by-step resolution** of common problems
- **Emergency procedures** for complete failures
- **Performance optimization** techniques
- **Preventive maintenance** and monitoring

By following these procedures, you can ensure reliable VPC peering connectivity between the MojoRust Trading Bot and DragonflyDB Cloud, minimizing downtime and maintaining optimal performance.

**Key Takeaways:**
1. Always verify both DNS resolution and TCP connectivity
2. Monitor latency and bandwidth utilization regularly
3. Set up automated health checks and alerts
4. Have a failover plan ready
5. Document all incidents and resolutions

**Regular Reviews:**
- Review this guide quarterly
- Update procedures based on incident learnings
- Test all recovery procedures monthly
- Stay updated with AWS VPC peering best practices

---

**Version**: 1.0
**Last Updated**: 2024-10-15
**Related Documents**: [VPC_NETWORKING_SETUP.md](../VPC_NETWORKING_SETUP.md), [OPERATIONS_RUNBOOK.md](../OPERATIONS_RUNBOOK.md)