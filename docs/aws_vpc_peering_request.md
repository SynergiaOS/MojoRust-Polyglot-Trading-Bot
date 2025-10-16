# AWS VPC Peering Request for DragonflyDB Cloud Integration

## Overview

This document provides the information needed to establish VPC peering between our AWS VPC and DragonflyDB Cloud for the MojoRust Trading Bot deployment.

## Request Details

### Contact Information
- **Requesting Organization**: MojoRust Trading Bot
- **Technical Contact**: [Your Name/Email]
- **Support Contact**: DragonflyDB Support - support@dragonflydb.com

### Your AWS Infrastructure Details
- **AWS Account ID**: `962364259018`
- **VPC ID**: `vpc-00e79f7555aa68c0e`
- **VPC CIDR Block**: `192.168.0.0/16`
- **AWS Region**: [Your AWS Region - specify actual region]
- **DragonflyDB Instance**: `612ehcb9i`

### Purpose of VPC Peering
- **Use Case**: High-performance Redis/DragonflyDB caching for trading bot
- **Application**: MojoRust Trading Bot (cryptocurrency arbitrage and market making)
- **Traffic Type**: Redis protocol over SSL/TLS (port 6385)
- **Expected Bandwidth**: Low to moderate latency-sensitive operations
- **Security Requirements**: End-to-end encryption, private network connectivity

## Information Needed from DragonflyDB

Please provide the following information to complete the VPC peering setup:

### Network Information
- [ ] **DragonflyDB VPC ID**: The VPC ID where your DragonflyDB instance is deployed
- [ ] **DragonflyDB VPC CIDR**: The CIDR block of your DragonflyDB VPC
- [ ] **DragonflyDB AWS Account ID**: Your AWS account ID
- [ ] **DragonflyDB AWS Region**: The AWS region where your DragonflyDB instance is located

### Security Requirements
- [ ] **Security Group Requirements**: Any specific inbound rules needed from our VPC
- [ ] **Port Requirements**: Confirmation of port 6385 (Redis SSL) and 443 (HTTPS) requirements
- [ ] **IP Whitelisting**: Any specific IP ranges or security considerations

### Timeline and Process
- [ ] **Expected Timeline**: How long will acceptance take once requested?
- [ ] **Approval Process**: Who needs to approve the peering request?
- [ ] **Contact Person**: DragonflyDB technical contact for coordination

### Additional Requirements
- [ ] **DNS Resolution**: Will you provide private DNS resolution for the DragonflyDB endpoint?
- [ ] **Monitoring**: Any specific monitoring or logging requirements?
- [ ] **Backup Considerations**: Any special considerations for backup/replication traffic?

## Communication Log

| Date | Communication | Response | Next Actions |
|------|----------------|----------|--------------|
| [Date] | Initial VPC peering request sent via email | [Response] | [Actions] |
| [Date] | Follow-up on missing information | [Response] | [Actions] |
| [Date] | VPC peering connection created (pcx-xxxxx) | [Response] | [Actions] |
| [Date] | VPC peering accepted and active | [Response] | [Actions] |
| [Date] | Connectivity verification completed | [Response] | [Actions] |

## Request Template for DragonflyDB

**Subject**: VPC Peering Request - MojoRust Trading Bot to DragonflyDB Cloud

**Email Body**:

```
Dear DragonflyDB Support Team,

We would like to establish VPC peering between our AWS VPC and DragonflyDB Cloud for our MojoRust Trading Bot deployment.

Our AWS Infrastructure Details:
- AWS Account ID: 962364259018
- VPC ID: vpc-00e79f7555aa68c0e
- VPC CIDR: 192.168.0.0/16
- AWS Region: [Your AWS Region]
- DragonflyDB Instance: 612ehcb9i

Purpose: High-performance caching for cryptocurrency trading operations with low latency requirements.

Required from DragonflyDB:
1. Your VPC ID where the DragonflyDB instance is deployed
2. Your VPC CIDR block
3. Your AWS account ID
4. Your AWS region
5. Any security group requirements for inbound traffic from our VPC (ports 6385 and 443)
6. Expected timeline for peering acceptance

We need private network connectivity to endpoint: 612ehcb9i.dragonflydb.cloud:6385

Please let us know the process and timeline for establishing this VPC peering connection.

Thank you for your assistance.

Best regards,
[Your Name]
MojoRust Trading Bot Team
```

## Post-Acceptance Verification Checklist

Once DragonflyDB accepts the VPC peering request, complete the following verification steps:

### 1. AWS Configuration Verification
- [ ] VPC peering connection status is "active"
- [ ] Route tables configured with routes to DragonflyDB VPC
- [ ] Security group egress rules created for ports 6385 and 443
- [ ] DNS support and hostnames enabled for VPC

### 2. Network Connectivity Testing
- [ ] DNS resolution test: `nslookup 612ehcb9i.dragonflydb.cloud`
- [ ] TCP connectivity test: `nc -vz 612ehcb9i.dragonflydb.cloud 6385`
- [ ] SSL/TLS handshake test: `openssl s_client -connect 612ehcb9i.dragonflydb.cloud:6385`
- [ ] Redis connection test using our verification script

### 3. Application Configuration
- [ ] Update `.env` file with VPC peering details
- [ ] Update DragonflyDB connection string to use VPC peering endpoint
- [ ] Test application connectivity to DragonflyDB
- [ ] Verify performance metrics are within expected ranges

### 4. Monitoring and Alerting
- [ ] Set up CloudWatch monitoring for VPC peering
- [ ] Configure alerts for connectivity issues
- [ ] Enable VPC Flow Logs for traffic monitoring
- [ ] Test alerting and notification systems

## Automated Verification Script

After VPC peering is established, run our automated verification script:

```bash
# Test VPC peering connectivity specifically
./scripts/verify_dragonflydb_connection.sh --vpc-only

# Run full DragonflyDB verification
./scripts/verify_dragonflydb_connection.sh --verbose
```

## Troubleshooting Contacts

If issues arise during or after VPC peering setup:

### DragonflyDB Support
- **Email**: support@dragonflydb.com
- **Documentation**: https://www.dragonflydb.cloud/docs/networking
- **Priority**: Production connectivity issue

### AWS Support
- **Issue Type**: VPC peering configuration
- **Priority**: High (production system dependency)
- **Reference**: VPC peering with DragonflyDB Cloud

## Security Considerations

1. **Network Isolation**: VPC peering provides private network connectivity between our VPC and DragonflyDB VPC
2. **Encryption**: All traffic uses SSL/TLS encryption (Redis protocol over port 6385)
3. **Access Control**: Security groups restrict traffic to specific ports and source/destination ranges
4. **Monitoring**: VPC Flow Logs and CloudWatch metrics for security and performance monitoring

## Documentation References

- [VPC Networking Setup Guide](../VPC_NETWORKING_SETUP.md)
- [DragonflyDB Connection Verification](../scripts/verify_dragonflydb_connection.sh)
- [Troubleshooting Guide](vpc_peering_troubleshooting.md)

---

**Version**: 1.0
**Last Updated**: [Current Date]
**Next Review**: After VPC peering completion