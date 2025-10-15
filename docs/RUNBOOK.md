# 📖 MojoRust Trading Bot - Operational Runbook

## Table of Contents
1. System Overview
2. Normal Operations
3. Restart Procedures
4. Rollback Procedures
5. Emergency Stop Procedures
6. Incident Response
7. Monitoring & Alerting
8. Troubleshooting Guide
9. Escalation Procedures
10. Maintenance Windows

## 1. System Overview

**Architecture:**
- **Application**: Mojo/Rust/Python hybrid trading bot
- **Server**: 38.242.239.150 (Ubuntu 22.04)
- **User**: tradingbot
- **Directory**: ~/mojo-trading-bot
- **Process**: trading-bot (Mojo runtime)
- **Database**: TimescaleDB (PostgreSQL 15)
- **Monitoring**: Prometheus, Grafana, Loki, Sentry

**Critical Dependencies:**
- Helius API (token metadata, organic score)
- QuickNode RPC (blockchain transactions)
- Jupiter API (swap routing, price data)
- DexScreener API (market data)
- Infisical (secrets management)

**Service Ports:**
- 8080: Main API
- 8082: Health check endpoints
- 9090: Prometheus metrics
- 3000: Grafana dashboards
- 5432: PostgreSQL database

## 2. Normal Operations

**Daily Checks:**
- Review Grafana dashboards (trading performance, system health)
- Check Telegram alerts for warnings
- Verify portfolio value and P&L
- Review filter performance (should be 85-97% rejection rate)
- Check for errors in logs: `grep ERROR logs/trading-bot-*.log | tail -20`

**Weekly Tasks:**
- Review backup integrity: `ls -lh /home/tradingbot/backups/`
- Rotate API keys (Helius, QuickNode)
- Update dependencies: `./scripts/update_dependencies.sh`
- Review performance metrics and adjust parameters

**Monthly Tasks:**
- Full system backup verification (test restore)
- Security audit (check for exposed secrets)
- Performance optimization review
- Capacity planning (disk space, memory trends)

## 3. Restart Procedures

### 3.1 Graceful Restart (Preferred)

**When to use:** Routine maintenance, configuration changes, minor updates

**Steps:**
1. **Prepare for restart:**
   ```bash
   cd ~/mojo-trading-bot
   # Verify no critical positions open
   curl http://localhost:8080/api/status | jq '.open_positions'
   ```

2. **Stop bot gracefully:**
   ```bash
   # If using systemd:
   sudo systemctl stop trading-bot
   
   # Or manual:
   pkill -SIGTERM -f "mojo run"
   
   # Wait for graceful shutdown (max 60 seconds)
   timeout 60 bash -c 'while pgrep -f "mojo run" > /dev/null; do sleep 1; done'
   ```

3. **Verify shutdown:**
   ```bash
   pgrep -f "mojo run"  # Should return empty
   tail -20 logs/trading-bot-*.log  # Check for "Shutdown complete" message
   ```

4. **Apply changes** (if any):
   ```bash
   git pull origin main  # Update code
   # Or edit configuration files
   ```

5. **Restart bot:**
   ```bash
   # If using systemd:
   sudo systemctl start trading-bot
   
   # Or manual:
   ./scripts/start_bot.sh
   ```

6. **Verify startup:**
   ```bash
   # Check process running
   pgrep -f "mojo run"
   
   # Check health endpoint
   curl http://localhost:8082/health
   
   # Monitor logs
   tail -f logs/trading-bot-*.log
   ```

**Expected downtime:** 1-2 minutes

### 3.2 Quick Restart (Emergency)

**When to use:** Bot hung, unresponsive, critical bug

**Steps:**
```bash
# Force kill
pkill -SIGKILL -f "mojo run"

# Wait 5 seconds
sleep 5

# Restart
./scripts/restart_bot.sh

# Verify
curl http://localhost:8082/health
```

**Expected downtime:** 10-30 seconds

### 3.3 Restart with State Recovery

**When to use:** After crash, data corruption, unexpected shutdown

**Steps:**
1. Check for saved state: `ls -lh data/last_shutdown.json`
2. Review shutdown reason: `cat data/last_shutdown.json | jq '.reason'`
3. Restore portfolio state from database: automatic on startup
4. Verify portfolio value matches last known state
5. Start bot and monitor closely for 30 minutes

## 4. Rollback Procedures

### 4.1 Rollback to Previous Version

**When to use:** Failed deployment, critical bug in new version, performance degradation

**Steps:**
1. **Identify rollback target:**
   ```bash
   # List available backups
   ./scripts/rollback.sh --list
   
   # Or use latest backup
   ROLLBACK_TARGET="latest"
   ```

2. **Execute rollback:**
   ```bash
   ./scripts/rollback.sh --backup-file ${ROLLBACK_TARGET}
   
   # Or rollback to latest:
   ./scripts/rollback.sh --latest
   ```

3. **Verify rollback:**
   ```bash
   # Check version
   grep "version" config/trading.toml
   
   # Check portfolio value
   curl http://localhost:8080/api/status | jq '.portfolio_value'
   
   # Monitor for 15 minutes
   tail -f logs/trading-bot-*.log
   ```

**Expected downtime:** 3-5 minutes

### 4.2 Rollback Database Only

**When to use:** Database corruption, bad migration

**Steps:**
```bash
# Stop bot
sudo systemctl stop trading-bot

# Restore database from backup
psql -h localhost -U trading_user trading_db < /home/tradingbot/backups/backup_YYYYMMDD.sql

# Restart bot
sudo systemctl start trading-bot
```

### 4.3 Rollback Configuration Only

**When to use:** Bad configuration change

**Steps:**
```bash
# Restore config from backup
tar -xzf /home/tradingbot/backups/mojorust-backup-YYYYMMDD.tar.gz config/

# Restart bot
./scripts/restart_bot.sh
```

## 5. Emergency Stop Procedures

### 5.1 Immediate Stop (Critical)

**When to use:** Runaway losses, security breach, critical bug

**Steps:**
1. **Stop bot immediately:**
   ```bash
   # Force kill
   sudo pkill -SIGKILL -f "mojo run"
   
   # Verify stopped
   pgrep -f "mojo run"  # Should return empty
   ```

2. **Close all open positions** (if needed):
   ```bash
   # Use emergency close script (if available)
   # Or manually close positions via exchange UI
   ```

3. **Secure wallet:**
   ```bash
   # Move funds to cold storage if necessary
   # Revoke API keys if security breach suspected
   ```

4. **Document incident:**
   ```bash
   # Save logs
   cp logs/trading-bot-*.log /home/tradingbot/incidents/incident-${TIMESTAMP}/
   
   # Save portfolio state
   curl http://localhost:8080/api/status > /home/tradingbot/incidents/incident-${TIMESTAMP}/portfolio-state.json
   ```

**Expected downtime:** Indefinite (manual review required)

### 5.2 Graceful Emergency Stop

**When to use:** Planned emergency stop, suspicious activity

**Steps:**
```bash
# Graceful stop (closes positions)
sudo systemctl stop trading-bot

# Wait for shutdown
timeout 60 bash -c 'while pgrep -f "mojo run" > /dev/null; do sleep 1; done'

# Verify positions closed
curl http://localhost:8080/api/status | jq '.open_positions'
```

## 6. Incident Response

### 6.1 Incident Classification

**Severity Levels:**
- **P0 (Critical)**: Trading halted, security breach, data loss, runaway losses
- **P1 (High)**: Degraded performance, API failures, high error rate
- **P2 (Medium)**: Warnings, minor errors, performance degradation
- **P3 (Low)**: Informational, optimization opportunities

### 6.2 P0 Incident Response

**Immediate Actions (0-5 minutes):**
1. Execute emergency stop: `sudo pkill -SIGKILL -f "mojo run"`
2. Assess impact: check portfolio value, open positions, recent trades
3. Secure systems: revoke API keys if security breach
4. Notify stakeholders: send alert via Telegram/email

**Investigation (5-30 minutes):**
1. Collect logs: `tar -czf incident-logs-${TIMESTAMP}.tar.gz logs/`
2. Review recent trades: `grep EXECUTED logs/trading-bot-*.log | tail -50`
3. Check for errors: `grep ERROR logs/trading-bot-*.log | tail -100`
4. Review system metrics: Grafana dashboards
5. Identify root cause

**Resolution (30-120 minutes):**
1. Develop fix or workaround
2. Test fix in staging environment (if available)
3. Apply fix to production
4. Restart bot with monitoring
5. Verify resolution

**Post-Incident (1-24 hours):**
1. Write incident report
2. Update runbook with lessons learned
3. Implement preventive measures
4. Review and improve monitoring

### 6.3 P1 Incident Response

**Similar to P0 but less urgent:**
- No immediate stop required
- Investigate while bot running
- Plan maintenance window for fix
- Monitor closely until resolved

## 7. Monitoring & Alerting

**Grafana Dashboards:**
- Trading Performance: http://38.242.239.150:3000/d/trading-performance
- System Health: http://38.242.239.150:3000/d/system-health
- API Metrics: http://38.242.239.150:3000/d/api-metrics

**Alert Channels:**
- Telegram: Critical alerts (P0, P1)
- Email: All alerts
- Syslog: All events

**Key Alerts:**
- Trading halted (circuit breaker triggered)
- High error rate (>5% in 5 minutes)
- API failures (Helius, QuickNode down)
- High latency (p95 > 500ms)
- Low balance (<0.1 SOL)
- High drawdown (>15%)

## 8. Troubleshooting Guide

**Common Issues:**

**Issue: Bot not starting**
- Check logs: `tail -50 logs/trading-bot-*.log`
- Verify configuration: `./scripts/validate_config.sh`
- Check dependencies: `mojo --version`, `rustc --version`
- Test API connectivity: `curl https://api.helius.xyz/v0/health`

**Issue: High error rate**
- Check API status: Helius, QuickNode status pages
- Review circuit breaker state: `curl http://localhost:8082/metrics | grep circuit_breaker`
- Check network connectivity: `ping api.helius.xyz`
- Review recent errors: `grep ERROR logs/trading-bot-*.log | tail -50`

**Issue: No trades executing**
- Check filter performance: `grep "Filter Performance" logs/trading-bot-*.log | tail -10`
- Verify market activity: check DexScreener for new tokens
- Review signal generation: `grep "Signal generated" logs/trading-bot-*.log | tail -20`
- Check circuit breaker status: may be halted due to losses

**Issue: Database connection failed**
- Check PostgreSQL running: `sudo systemctl status postgresql`
- Test connection: `psql -h localhost -U trading_user trading_db -c "SELECT 1"`
- Check credentials: verify DB_PASSWORD in .env
- Review database logs: `sudo tail -50 /var/log/postgresql/postgresql-15-main.log`

## 9. Escalation Procedures

**Level 1: Automated Recovery**
- Health check cron attempts automatic restart
- Circuit breakers halt trading automatically
- Retry logic handles transient failures

**Level 2: On-Call Engineer**
- Review alerts and logs
- Execute runbook procedures
- Escalate if unable to resolve in 30 minutes

**Level 3: Senior Engineer**
- Complex incidents requiring code changes
- Security incidents
- Data recovery scenarios

**Level 4: Emergency Contact**
- Critical security breaches
- Regulatory issues
- Major financial losses

## 10. Maintenance Windows

**Scheduled Maintenance:**
- **Daily**: 2:00-2:30 AM UTC (automated backups)
- **Weekly**: Sunday 3:00-4:00 AM UTC (dependency updates)
- **Monthly**: First Sunday 2:00-6:00 AM UTC (full system maintenance)

**Maintenance Procedures:**
1. Announce maintenance window (24 hours notice)
2. Stop bot gracefully
3. Perform maintenance tasks
4. Test in staging (if available)
5. Restart bot
6. Monitor for 1 hour post-maintenance
7. Send completion notification
