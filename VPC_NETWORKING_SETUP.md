# VPC Networking Setup for DragonflyDB Cloud Integration

## Overview

This guide covers the VPC networking configuration required to connect your MojoRust Trading Bot deployment to DragonflyDB Cloud securely.

## Network Configuration

### Current VPC Details
- **VPC ID**: `vpc-00e79f7555aa68c0e`
- **CIDR Block**: `192.168.0.0/16`
- **AWS Account ID**: `962364259018`
- **Region**: [Your AWS Region - set as AWS_REGION]

### DragonflyDB Cloud Details
- **DragonflyDB Host**: `612ehcb9i.dragonflydb.cloud`
- **DragonflyDB Port**: `6385`
- **DragonflyDB VPC ID**: [Request from DragonflyDB Support]
- **DragonflyDB VPC CIDR**: [Request from DragonflyDB Support]
- **DragonflyDB Account ID**: [Request from DragonflyDB Support]
- **DragonflyDB Region**: [Request from DragonflyDB Support]

### Network Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AWS VPC (vpc-00e79f7555aa68c0e)            │
│                     CIDR: 192.168.0.0/16                 │
│                                                             │
│  ┌─────────────────┐    ┌─────────────────┐    ┌──────────────┐ │
│  │  Public Subnet   │    │ Private Subnet  │    │ DragonflyDB  │ │
│  │ 192.168.1.0/24   │◄──►│ 192.168.2.0/24   │◄──►│    Cloud     │ │
│  │                 │    │                 │    │ (External)   │ │
│  │ ┌─────────────┐ │    │ ┌─────────────┐ │    │              │ │
│  │ │ Trading Bot │ │    │ │   TimescaleDB│ │    │              │ │
│  │ │   Server    │ │    │ │   Database   │ │    │              │ │
│  │ └─────────────┘ │    │ └─────────────┘ │    │              │ │
│  └─────────────────┘    └─────────────────┘    └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **VPC Peering**: Establish VPC peering between your VPC and DragonflyDB Cloud VPC
2. **Security Groups**: Configure security groups to allow traffic on required ports
3. **Route Tables**: Update route tables for VPC peering connectivity
4. **DNS Resolution**: Ensure DNS resolution works for DragonflyDB endpoints

## Step 1: VPC Peering Configuration

### 1.1 Create VPC Peering Connection

```bash
# AWS CLI command to create VPC peering
aws ec2 create-vpc-peering-connection \
    --vpc-id vpc-00e79f7555aa68c0e \
    --peer-vpc-id DRAGONFLYDB_VPC_ID \
    --peer-owner-id DRAGONFLYDB_ACCOUNT_ID \
    --peer-region DRAGONFLYDB_REGION
```

### 1.2 Accept VPC Peering Request

DragonflyDB team will need to accept the peering request from their side.

### 1.3 Update Route Tables

```bash
# Update main route table for private subnet
aws ec2 create-route \
    --route-table-id rtb-xxxxxxxx \
    --destination-cidr-block DRAGONFLYDB_VPC_CIDR \
    --vpc-peering-connection-id pcx-xxxxxxxx

# Update DragonflyDB route table (handled by DragonflyDB team)
```

## Step 2: Security Group Configuration

### 2.1 Trading Bot Security Group

```bash
# Create security group for trading bot
aws ec2 create-security-group \
    --group-name trading-bot-sg \
    --description "Security group for MojoRust Trading Bot" \
    --vpc-id vpc-00e79f7555aa68c0e

# Allow outbound traffic to DragonflyDB (port 6385)
aws ec2 authorize-security-group-egress \
    --group-id <sg-id> \
    --protocol tcp \
    --port 6385 \
    --cidr <DRAGONFLYDB_VPC_CIDR>

# Allow outbound traffic to DragonflyDB (port 443 for management)
aws ec2 authorize-security-group-egress \
    --group-id <sg-id> \
    --protocol tcp \
    --port 443 \
    --cidr <DRAGONFLYDB_VPC_CIDR>
```

### 2.2 DragonflyDB Security Group

DragonflyDB team will configure inbound rules to accept traffic from your VPC.

## Step 3: DNS Configuration

### 3.1 Private DNS Resolution

```bash
# Enable DNS resolution for VPC peering
aws ec2 modify-vpc-attribute \
    --vpc-id vpc-00e79f7555aa68c0e \
    --enable-dns-support

aws ec2 modify-vpc-attribute \
    --vpc-id vpc-00e79f7555aa68c0e \
    --enable-dns-hostnames

# Create DNS records for DragonflyDB endpoints
# (Managed by DragonflyDB team)
```

## Step 4: Network Validation

### 4.1 Connectivity Tests

```bash
# Test DNS resolution
nslookup your-dragonflydb-host.dragonflydb.cloud

# Test network connectivity (from trading bot server)
telnet your-dragonflydb-host.dragonflydb.cloud 6385

# Test SSL connectivity
openssl s_client -connect your-dragonflydb-host.dragonflydb.cloud:6385 -servername your-dragonflydb-host.dragonflydb.cloud
```

### 4.2 DragonflyDB Connection Test

```python
import redis
import ssl
import os

def test_dragonflydb_connection():
    try:
        # DragonflyDB Cloud connection with SSL
        redis_url = "rediss://user:password@your-dragonflydb-host.dragonflydb.cloud:6385"

        client = redis.from_url(
            redis_url,
            ssl_cert_reqs=ssl.CERT_REQUIRED,
            ssl_check_hostname=True,
            socket_timeout=10,
            socket_connect_timeout=5
        )

        # Test connection
        result = client.ping()
        print(f"✅ DragonflyDB connection successful: {result}")

        # Test basic operations
        client.set("vpc:test", "connected", ex=60)
        value = client.get("vpc:test")
        print(f"✅ DragonflyDB operations working: {value}")

        return True

    except Exception as e:
        print(f"❌ DragonflyDB connection failed: {e}")
        return False

if __name__ == "__main__":
    test_dragonflydb_connection()
```

## Step 5: Monitoring and Logging

### 5.1 VPC Flow Logs

```bash
# Enable VPC Flow Logs for monitoring
# Prerequisites: Create log group and IAM role first
aws logs create-log-group --log-group-name vpc-flow-logs --region $AWS_REGION

# Create IAM role for VPC Flow Logs (if not exists)
aws iam create-role --role-name VPCFlowLogsRole --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name VPCFlowLogsRole --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess

aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids vpc-00e79f7555aa68c0e \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name vpc-flow-logs \
    --max-aggregation-interval 60 \
    --deliver-logs-status ENABLED
```

### 5.2 CloudWatch Metrics

```bash
# Create CloudWatch alarm for VPC peering connectivity
aws cloudwatch put-metric-alarm \
    --alarm-name "DragonflyDB-VPC-Peering-Connectivity" \
    --alarm-description "Monitor VPC peering connectivity to DragonflyDB" \
    --metric-name VpcPacketsDropped \
    --namespace AWS/VPC \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 2
```

## Step 6: Security Considerations

### 6.1 Network Security

1. **VPC Peering**: Only peer with DragonflyDB Cloud VPC
2. **Security Groups**: Restrict access to specific ports and source IPs
3. **NACLs**: Additional network layer security if needed
4. **Encryption**: All traffic uses SSL/TLS encryption

### 6.2 Access Control

```bash
# Restrict DragonflyDB access to specific instances
aws ec2 authorize-security-group-egress \
    --group-id sg-trading-bot \
    --protocol tcp \
    --port 6385 \
    --destination-prefix-list-id pl-dragonflydb-endpoints
```

## Step 7: Troubleshooting

### 7.1 Common Issues

#### VPC Peering Issues
```bash
# Check VPC peering status
aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-xxxxxxxx

# Check route tables
aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-00e79f7555aa68c0e
```

#### DNS Resolution Issues
```bash
# Test DNS from within VPC
nslookup your-dragonflydb-host.dragonflydb.cloud

# Check DNS settings
aws ec2 describe-vpc-attribute --vpc-id vpc-00e79f7555aa68c0e --attribute enableDnsSupport
```

#### Security Group Issues
```bash
# Check security group rules
aws ec2 describe-security-groups --group-ids sg-xxxxxxxx

# Check network ACLs
aws ec2 describe-network-acls --filters Name=vpc-id,Values=vpc-00e79f7555aa68c0e
```

### 7.2 Performance Monitoring

```python
# Monitor VPC peering performance
import time
import redis

def monitor_vpc_performance():
    redis_client = redis.from_url(os.getenv("REDIS_URL"))

    while True:
        try:
            start_time = time.time()
            redis_client.ping()
            latency = (time.time() - start_time) * 1000

            print(f"VPC Latency: {latency:.2f}ms")

            if latency > 100:  # Alert if latency > 100ms
                print("⚠️ High VPC latency detected!")

        except Exception as e:
            print(f"❌ VPC connectivity issue: {e}")

        time.sleep(60)  # Check every minute

if __name__ == "__main__":
    monitor_vpc_performance()
```

## Step 8: Production Deployment

### 8.1 Environment Configuration

Update your `.env` file with VPC configuration:

```bash
# VPC Configuration
VPC_ID=vpc-00e79f7555aa68c0e
VPC_CIDR=192.168.0.0/16
AWS_ACCOUNT_ID=962364259018
AWS_REGION=us-east-1

# DragonflyDB Cloud Connection
REDIS_URL=rediss://user:password@your-dragonflydb-host.dragonflydb.cloud:6385
DRAGONFLYDB_HOST=your-dragonflydb-host.dragonflydb.cloud
DRAGONFLYDB_PORT=6385

# Security
ENABLE_VPC_PEERING=true
VPC_PEERING_ID=pcx-xxxxxxxx
```

### 8.2 Docker Compose Configuration

```yaml
version: '3.8'
services:
  trading-bot:
    build: .
    environment:
      - REDIS_URL=rediss://user:password@your-dragonflydb-host.dragonflydb.cloud:6385
      - VPC_ID=vpc-00e79f7555aa68c0e
      - AWS_ACCOUNT_ID=962364259018
    networks:
      - trading-network
    depends_on:
      - timescaledb

networks:
  trading-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

## Post-Configuration Steps

### Actual Configuration Details

After completing the VPC peering setup, record the following details:

**VPC Peering Connection:**
- **Peering Connection ID**: `pcx-[generated-id]`
- **Status**: `active`
- **Requester VPC**: `vpc-00e79f7555aa68c0e` (192.168.0.0/16)
- **Accepter VPC**: `[DragonflyDB VPC ID]` ([DragonflyDB VPC CIDR])

**Route Table Configuration:**
- **Route Table IDs**: [List of updated route table IDs]
- **Routes Added**:
  - Destination: `[DragonflyDB VPC CIDR]` → Target: `pcx-[generated-id]`
  - Status: `active`

**Security Group Configuration:**
- **Security Group ID**: [Your security group ID]
- **Egress Rules Added**:
  - Rule ID: [sg-rule-id-6385] - Port 6385 to `[DragonflyDB VPC CIDR]`
  - Rule ID: [sg-rule-id-443] - Port 443 to `[DragonflyDB VPC CIDR]`

**DragonflyDB Cloud Details:**
- **Host**: `612ehcb9i.dragonflydb.cloud`
- **Port**: `6385`
- **VPC ID**: `[DragonflyDB VPC ID]`
- **VPC CIDR**: `[DragonflyDB VPC CIDR]`
- **Account ID**: `[DragonflyDB Account ID]`
- **Region**: `[DragonflyDB Region]`

### Verification Steps

1. **VPC Peering Status Check**:
   ```bash
   aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids pcx-[generated-id]
   ```

2. **Route Table Verification**:
   ```bash
   aws ec2 describe-route-tables --filters Name=vpc-id,Values=vpc-00e79f7555aa68c0e
   ```

3. **Security Group Rules Check**:
   ```bash
   aws ec2 describe-security-groups --group-ids [your-sg-id]
   ```

4. **Connectivity Test**:
   ```bash
   ./scripts/verify_dragonflydb_connection.sh --vpc-only
   ```

5. **DNS Resolution Test**:
   ```bash
   nslookup 612ehcb9i.dragonflydb.cloud
   ```

6. **TCP Connection Test**:
   ```bash
   nc -vz 612ehcb9i.dragonflydb.cloud 6385
   ```

### Environment Configuration Updates

Update your `.env` file with the VPC peering details:

```bash
# VPC Configuration
VPC_ID=vpc-00e79f7555aa68c0e
VPC_CIDR=192.168.0.0/16
AWS_ACCOUNT_ID=962364259018
AWS_REGION=[your-region]

# VPC Peering
ENABLE_VPC_PEERING=true
VPC_PEERING_ID=pcx-[generated-id]
DRAGONFLYDB_VPC_ID=[DragonflyDB VPC ID]
DRAGONFLYDB_VPC_CIDR=[DragonflyDB VPC CIDR]

# DragonflyDB Connection (aligned with VPC peering)
REDIS_URL=rediss://default:<password>@612ehcb9i.dragonflydb.cloud:6385
DRAGONFLYDB_HOST=612ehcb9i.dragonflydb.cloud
DRAGONFLYDB_PORT=6385
```

## Verification Checklist

- [ ] VPC peering connection established and active
- [ ] Route tables configured correctly
- [ ] Security groups allow necessary traffic
- [ ] DNS resolution working for DragonflyDB endpoints
- [ ] SSL certificate validation successful
- [ ] DragonflyDB connection test passing
- [ ] VPC Flow Logs enabled
- [ ] CloudWatch alarms configured
- [ ] Performance monitoring active
- [ ] Backup and recovery procedures documented

## Support Contact

For DragonflyDB Cloud networking issues:
- **DragonflyDB Support**: support@dragonflydb.com
- **AWS Support**: For VPC peering issues
- **Documentation**: [DragonflyDB Cloud Networking Guide](https://www.dragonflydb.cloud/docs/networking)

---

**VPC networking setup complete!** Your MojoRust Trading Bot is now configured to securely connect to DragonflyDB Cloud through VPC peering, ensuring low-latency, high-performance caching and database operations. 🚀