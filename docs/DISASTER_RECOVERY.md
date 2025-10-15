# 🆘 Disaster Recovery Plan - MojoRust Trading Bot

## Executive Summary

**Recovery Objectives:**
- **RTO (Recovery Time Objective)**: 15 minutes for critical systems
- **RPO (Recovery Point Objective)**: 5 minutes of data loss maximum

**Disaster Scenarios Covered:**
1. Server failure (hardware, OS crash)
2. Database corruption or loss
3. Configuration corruption
4. Security breach (compromised keys)
5. Data center outage
6. Human error (accidental deletion)

## 1. Backup Strategy

**Backup Types:**

**1.1 Automated Daily Backups**
- **Schedule**: 2:00 AM UTC daily
- **Script**: `scripts/backup.sh`
- **Location**: `/home/tradingbot/backups/`
- **Retention**: 30 days
- **Contents**: Configuration, database dump, portfolio state, logs (7 days)

**1.2 Real-Time Database Replication** (Optional)
- **Method**: PostgreSQL streaming replication
- **Standby server**: Secondary VPS (if configured)
- **Lag**: <1 minute
- **Failover**: Automatic or manual

**1.3 Configuration Backups**
- **Method**: Git repository
- **Frequency**: On every change (git commit)
- **Location**: GitHub repository
- **Retention**: Indefinite (git history)

**1.4 Off-Site Backups** (Recommended)
- **Method**: Sync to S3/Backblaze/Google Cloud Storage
- **Frequency**: Daily
- **Encryption**: GPG encrypted before upload
- **Retention**: 90 days

## 2. Disaster Scenarios & Recovery Procedures

### 2.1 Server Failure (Hardware/OS Crash)

**Symptoms:**
- Server unreachable via SSH
- Health checks failing
- No response from any services

**Recovery Steps:**

**Option A: Restore on Same Server (if accessible)**
1. **Access server** (console, IPMI, or provider dashboard)
2. **Diagnose issue**: Check system logs, hardware status
3. **Repair if possible**: Reboot, fix filesystem, repair OS
4. **Restore from backup**: `./scripts/rollback.sh --latest`
5. **Verify restoration**: Check portfolio value, API connectivity
6. **Resume trading**: Monitor closely for 1 hour

**Option B: Failover to New Server**
1. **Provision new VPS** (same specs: 4 CPU, 8GB RAM, 50GB SSD)
2. **Run VPS setup**: `./scripts/vps_setup.sh`
3. **Restore latest backup**:
   ```bash
   # Download backup from off-site storage
   aws s3 cp s3://backups/mojorust-backup-latest.tar.gz.gpg .
   
   # Decrypt
   gpg --decrypt mojorust-backup-latest.tar.gz.gpg > mojorust-backup-latest.tar.gz
   
   # Extract
   tar -xzf mojorust-backup-latest.tar.gz -C ~/mojo-trading-bot
   
   # Restore database
   psql -h localhost -U trading_user trading_db < backup.sql
   ```
4. **Update DNS/IP** (if using domain)
5. **Start bot**: `./scripts/start_bot.sh`
6. **Verify**: Check health, portfolio value, API connectivity

**RTO:** 15-30 minutes (Option A), 30-60 minutes (Option B)
**RPO:** 5 minutes (last backup) to 24 hours (daily backup)

### 2.2 Database Corruption/Loss

**Symptoms:**
- Database connection errors
- Query failures
- Data inconsistencies

**Recovery Steps:**
1. **Stop bot**: `sudo systemctl stop trading-bot`
2. **Assess damage**: `psql -h localhost -U trading_user trading_db -c "SELECT COUNT(*) FROM trades"`
3. **Restore from backup**:
   ```bash
   # Drop corrupted database
   dropdb -h localhost -U postgres trading_db
   
   # Recreate database
   createdb -h localhost -U postgres trading_db
   
   # Restore from backup
   psql -h localhost -U trading_user trading_db < /home/tradingbot/backups/backup_latest.sql
   ```
4. **Verify restoration**: Check row counts, data integrity
5. **Restart bot**: `sudo systemctl start trading-bot`
6. **Reconcile portfolio**: Compare database state with blockchain state

**RTO:** 10-15 minutes
**RPO:** 5 minutes (if real-time replication), 24 hours (daily backup)

### 2.3 Security Breach (Compromised Keys)

**Symptoms:**
- Unauthorized transactions
- Unexpected fund movements
- API key usage from unknown IPs

**Recovery Steps:**

**Immediate (0-5 minutes):**
1. **Stop bot**: `sudo pkill -SIGKILL -f "mojo run"`
2. **Revoke all API keys**:
   - Helius: Dashboard → API Keys → Revoke
   - QuickNode: Dashboard → Endpoints → Delete
   - Infisical: Dashboard → Access Tokens → Revoke
3. **Secure wallet**:
   ```bash
   # Move funds to cold storage
   # Generate new wallet keypair
   solana-keygen new --outfile ~/.config/solana/new-id.json
   ```

**Investigation (5-60 minutes):**
1. Review access logs: `grep "API" logs/trading-bot-*.log | tail -200`
2. Check for unauthorized transactions on blockchain
3. Identify breach vector (exposed .env, compromised server, etc.)
4. Assess damage: funds lost, data exposed

**Recovery (1-4 hours):**
1. **Rotate all credentials**:
   - Generate new API keys (Helius, QuickNode)
   - Create new Infisical project
   - Generate new wallet (transfer remaining funds)
2. **Patch vulnerability**: Fix exposed secrets, update security
3. **Restore from clean backup**: Use backup from before breach
4. **Update configuration**: New API keys, new wallet
5. **Restart with monitoring**: Watch for suspicious activity

**Post-Incident:**
1. Security audit: Review all code for exposed secrets
2. Implement additional security: 2FA, IP whitelisting, key rotation
3. Document incident and prevention measures

**RTO:** 1-4 hours
**RPO:** Depends on breach timing (may lose recent trades)

### 2.4 Configuration Corruption

**Symptoms:**
- Bot fails to start
- Configuration validation errors
- Unexpected trading behavior

**Recovery Steps:**
1. **Restore configuration from git**:
   ```bash
   cd ~/mojo-trading-bot
   git checkout config/trading.toml
   git checkout .env.example
   cp .env.example .env
   # Re-enter API keys
   ```
2. **Or restore from backup**: `./scripts/rollback.sh --latest --config-only`
3. **Validate configuration**: `./scripts/validate_config.sh`
4. **Restart bot**: `./scripts/restart_bot.sh`

**RTO:** 5-10 minutes
**RPO:** 0 (configuration is version controlled)

### 2.5 Data Center Outage

**Symptoms:**
- All services unreachable
- Network connectivity lost
- Provider status page shows outage

**Recovery Steps:**

**If outage < 1 hour:**
- Wait for provider to restore service
- Verify services when back online
- Check for data corruption
- Resume trading

**If outage > 1 hour:**
1. **Provision new server** in different data center/provider
2. **Restore from off-site backup**
3. **Update DNS** (if using domain)
4. **Start bot** on new server
5. **Verify** and resume trading

**RTO:** 1-2 hours (new server provisioning)
**RPO:** 5 minutes to 24 hours (depends on backup frequency)

## 3. Recovery Verification Checklist

**After any recovery, verify:**
- [ ] Bot process running: `pgrep -f "mojo run"`
- [ ] Health endpoint responding: `curl http://localhost:8082/health`
- [ ] Database connected: `psql -h localhost -U trading_user trading_db -c "SELECT 1"`
- [ ] API connectivity: Test Helius, QuickNode, Jupiter
- [ ] Portfolio value correct: Compare with last known state
- [ ] No open positions (unless expected)
- [ ] Logs show normal operation: `tail -50 logs/trading-bot-*.log`
- [ ] Metrics exporting: `curl http://localhost:8082/metrics`
- [ ] Alerts configured: Test Telegram notification
- [ ] Circuit breakers reset: Check Grafana dashboard

## 4. Backup Verification

**Monthly Backup Test:**
1. **Select random backup**: Choose backup from 7-14 days ago
2. **Restore to test environment**: Use separate VPS or local machine
3. **Verify data integrity**: Check trade counts, portfolio value
4. **Test bot startup**: Ensure bot starts successfully
5. **Document results**: Log test date, backup file, success/failure

**Backup Integrity Checks:**
```bash
# Verify checksum
sha256sum -c mojorust-backup-YYYYMMDD.tar.gz.sha256

# Test tarball integrity
tar -tzf mojorust-backup-YYYYMMDD.tar.gz > /dev/null

# Test GPG decryption
gpg --decrypt mojorust-backup-YYYYMMDD.tar.gz.gpg > /dev/null
```

## 5. Contact Information

**Emergency Contacts:**
- On-Call Engineer: [Phone/Telegram]
- Senior Engineer: [Phone/Email]
- Infrastructure Team: [Email]

**Service Providers:**
- VPS Provider: [Support URL/Phone]
- Helius Support: support@helius.dev
- QuickNode Support: support@quicknode.com
