# VPS Setup Verification Checklist
### Server: 38.242.239.150
### Phase 2: Infrastructure Setup Validation

---

## Quick Verification Commands

Run these commands in sequence to verify the setup:

```bash
#!/bin/bash
# VPS Setup Verification Script
# Run this after vps_setup.sh completes

echo "=== VPS SETUP VERIFICATION ==="
echo ""

# 1. User Verification
echo "[1/15] Checking tradingbot user..."
id tradingbot && echo "✅ User exists" || echo "❌ User missing"

# 2. Directory Structure
echo "[2/15] Checking directory structure..."
ls -ld /home/tradingbot/.config/solana /home/tradingbot/logs /home/tradingbot/data && echo "✅ Directories exist" || echo "❌ Directories missing"

# 3. Mojo Installation
echo "[3/15] Checking Mojo installation..."
su - tradingbot -c "mojo --version" && echo "✅ Mojo installed" || echo "❌ Mojo missing"

# 4. Rust Installation
echo "[4/15] Checking Rust installation..."
su - tradingbot -c "rustc --version && cargo --version" && echo "✅ Rust installed" || echo "❌ Rust missing"

# 5. Infisical CLI
echo "[5/15] Checking Infisical CLI..."
infisical --version && echo "✅ Infisical installed" || echo "❌ Infisical missing"

# 6. Docker
echo "[6/15] Checking Docker..."
docker --version && systemctl is-active docker && echo "✅ Docker running" || echo "❌ Docker not running"

# 7. Docker Compose
echo "[7/15] Checking Docker Compose..."
docker-compose --version && echo "✅ Docker Compose installed" || echo "❌ Docker Compose missing"

# 8. Firewall
echo "[8/15] Checking firewall..."
ufw status | grep -q "Status: active" && echo "✅ Firewall active" || echo "❌ Firewall inactive"

# 9. Firewall Rules
echo "[9/15] Checking firewall rules..."
ufw status | grep -E "22/tcp|9090/tcp|3000/tcp|8080/tcp" && echo "✅ Required ports open" || echo "❌ Ports not configured"

# 10. Log Rotation
echo "[10/15] Checking log rotation..."
test -f /etc/logrotate.d/trading-bot && echo "✅ Log rotation configured" || echo "❌ Log rotation missing"

# 11. SSH Security
echo "[11/15] Checking SSH security..."
test -f /etc/ssh/sshd_config.d/trading-bot-security.conf && echo "✅ SSH hardened" || echo "❌ SSH config missing"

# 12. System Optimization
echo "[12/15] Checking system optimization..."
test -f /etc/sysctl.d/99-trading-bot.conf && echo "✅ Sysctl configured" || echo "❌ Sysctl config missing"

# 13. Backup Script
echo "[13/15] Checking backup script..."
test -x /home/tradingbot/backup-trading-bot.sh && echo "✅ Backup script exists" || echo "❌ Backup script missing"

# 14. Cron Job
echo "[14/15] Checking backup cron job..."
su - tradingbot -c "crontab -l | grep -q backup-trading-bot.sh" && echo "✅ Cron job scheduled" || echo "❌ Cron job missing"

# 15. Setup Log
echo "[15/15] Checking setup log..."
test -f /var/log/vps-setup.log && echo "✅ Setup log exists" || echo "❌ Setup log missing"

echo ""
echo "=== VERIFICATION COMPLETE ==="
echo ""
echo "Check for any ❌ marks above and resolve issues before proceeding."
```

---

## Detailed Verification Steps

### 1. User and Permissions ✓

**Check user exists:**
```bash
id tradingbot
# Expected: uid=1001(tradingbot) gid=1001(tradingbot) groups=1001(tradingbot),27(sudo)
```

**Check sudo access:**
```bash
su - tradingbot
sudo whoami
# Expected: root
```

**Check directory permissions:**
```bash
stat -c "%a %n" /home/tradingbot/.config/solana
# Expected: 700 /home/tradingbot/.config/solana

stat -c "%a %n" /home/tradingbot/logs
# Expected: 755 /home/tradingbot/logs

stat -c "%a %n" /home/tradingbot/data
# Expected: 755 /home/tradingbot/data
```

### 2. Dependencies ✓

**Mojo:**
```bash
su - tradingbot -c "mojo --version"
# Expected: mojo 24.4.0 (or higher)

su - tradingbot -c "which mojo"
# Expected: /home/tradingbot/.modular/pkg/packages.modular.com_mojo/bin/mojo
```

**Rust:**
```bash
su - tradingbot -c "rustc --version"
# Expected: rustc 1.75.0 (or higher)

su - tradingbot -c "cargo --version"
# Expected: cargo 1.75.0 (or higher)
```

**Infisical:**
```bash
infisical --version
# Expected: infisical version X.X.X
```

**Docker:**
```bash
docker --version
# Expected: Docker version 20.10.0 (or higher)

systemctl status docker | grep Active
# Expected: Active: active (running)

groups tradingbot | grep docker
# Expected: docker in the list
```

**Docker Compose:**
```bash
docker-compose --version
# Expected: docker-compose version 1.29.0 (or higher)
```

### 3. Firewall Configuration ✓

**Check firewall status:**
```bash
ufw status verbose
# Expected:
# Status: active
# Logging: on (low)
# Default: deny (incoming), allow (outgoing), disabled (routed)
```

**Verify required ports:**
```bash
ufw status numbered
# Expected:
# [ 1] 22/tcp                     ALLOW IN    Anywhere
# [ 2] 9090/tcp                   ALLOW IN    Anywhere    # Prometheus metrics
# [ 3] 3000/tcp                   ALLOW IN    Anywhere    # Grafana dashboard
# [ 4] 8080/tcp                   ALLOW IN    Anywhere    # Trading Bot API
```

**Test port accessibility from local machine:**
```bash
# From local machine:
nc -zv 38.242.239.150 22
# Expected: Connection to 38.242.239.150 22 port [tcp/ssh] succeeded!

nc -zv 38.242.239.150 9090
# Expected: Connection to 38.242.239.150 9090 port [tcp/*] succeeded!

nc -zv 38.242.239.150 3000
# Expected: Connection to 38.242.239.150 3000 port [tcp/*] succeeded!

nc -zv 38.242.239.150 8080
# Expected: Connection to 38.242.239.150 8080 port [tcp/*] succeeded!
```

### 4. System Optimization ✓

**Check sysctl configuration:**
```bash
cat /etc/sysctl.d/99-trading-bot.conf
# Verify file exists and contains optimization settings
```

**Verify applied settings:**
```bash
sysctl net.core.rmem_max
# Expected: net.core.rmem_max = 134217728

sysctl net.core.wmem_max
# Expected: net.core.wmem_max = 134217728

sysctl vm.swappiness
# Expected: vm.swappiness = 10

sysctl net.ipv4.tcp_congestion_control
# Expected: net.ipv4.tcp_congestion_control = bbr
```

**Check user limits:**
```bash
cat /etc/security/limits.d/trading-bot.conf
# Expected:
# tradingbot soft nofile 65536
# tradingbot hard nofile 65536
# tradingbot soft nproc 32768
# tradingbot hard nproc 32768

# Verify limits are applied (as tradingbot user):
su - tradingbot
ulimit -n
# Expected: 65536

ulimit -u
# Expected: 32768
```

### 5. Log Rotation ✓

**Check configuration files:**
```bash
cat /etc/logrotate.d/trading-bot
# Verify daily rotation, 30 days retention, compression

cat /etc/logrotate.d/trading-bot-system
# Verify daily rotation, 7 days retention
```

**Test configuration (dry run):**
```bash
logrotate -d /etc/logrotate.d/trading-bot 2>&1 | head -20
# Expected: No errors, shows rotation plan
```

**Check log directory:**
```bash
ls -la /var/log/trading-bot/
# Expected: Directory exists with proper permissions
```

### 6. SSH Security ✓

**Check SSH configuration:**
```bash
cat /etc/ssh/sshd_config.d/trading-bot-security.conf
# Verify:
# - PermitRootLogin no
# - PasswordAuthentication no
# - MaxAuthTries 3
# - AllowUsers tradingbot
```

**Test SSH configuration syntax:**
```bash
sshd -t
# Expected: No output (configuration is valid)
```

**Verify SSH service:**
```bash
systemctl status ssh
# Expected: Active: active (running)
```

**CRITICAL: Test SSH access as tradingbot:**
```bash
# From local machine (before logging out of root):
ssh tradingbot@38.242.239.150
# Expected: Successful connection with SSH key
```

### 7. Backup System ✓

**Check backup script:**
```bash
ls -la /home/tradingbot/backup-trading-bot.sh
# Expected: -rwxr-xr-x (executable permissions)

cat /home/tradingbot/backup-trading-bot.sh | head -20
# Verify script contents
```

**Check cron job:**
```bash
su - tradingbot
crontab -l
# Expected: 0 2 * * * /home/tradingbot/backup-trading-bot.sh >> /home/tradingbot/logs/backup.log 2>&1
```

**Test backup script (dry run):**
```bash
su - tradingbot
bash -n /home/tradingbot/backup-trading-bot.sh
# Expected: No syntax errors
```

### 8. System Health ✓

**Check system resources:**
```bash
free -h
# Verify sufficient memory (4GB+ available)

df -h
# Verify sufficient disk space (20GB+ available)

lscpu | grep "CPU(s):"
# Verify CPU count (2+ cores)
```

**Check for errors in setup log:**
```bash
grep -i error /var/log/vps-setup.log
# Expected: No critical errors

grep -i warning /var/log/vps-setup.log
# Review any warnings
```

**Check system journal for errors:**
```bash
journalctl -p err -b --no-pager
# Review any error messages
```

### 9. Network Connectivity ✓

**Test internet connectivity:**
```bash
ping -c 3 google.com
# Expected: 0% packet loss
```

**Test DNS resolution:**
```bash
nslookup api.helius.xyz
# Expected: Resolves to IP address
```

**Test Solana RPC connectivity:**
```bash
curl -X POST https://api.mainnet-beta.solana.com \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"getHealth"}'
# Expected: {"jsonrpc":"2.0","result":"ok","id":1}
```

---

## Final Validation Checklist

Before proceeding to Phase 3, ensure all items are checked:

**Infrastructure:**
- [ ] Server accessible via SSH as `tradingbot` user with key-based authentication
- [ ] Root SSH login is disabled (security hardening)
- [ ] Firewall is active with required ports open (22, 9090, 3000, 8080)
- [ ] System resources meet requirements (4GB+ RAM, 20GB+ disk, 2+ CPU cores)

**Dependencies:**
- [ ] Mojo 24.4+ installed and accessible: `mojo --version`
- [ ] Rust 1.75+ installed and accessible: `rustc --version`, `cargo --version`
- [ ] Infisical CLI installed: `infisical --version`
- [ ] Docker installed and running: `docker ps`
- [ ] Docker Compose installed: `docker-compose --version`
- [ ] `tradingbot` user is in docker group: `groups tradingbot | grep docker`

**Configuration:**
- [ ] Directory structure created: `~/.config/solana`, `~/logs`, `~/data`
- [ ] Directory permissions correct (700 for .config/solana, 755 for others)
- [ ] Log rotation configured: `/etc/logrotate.d/trading-bot` exists
- [ ] SSH security hardened: `/etc/ssh/sshd_config.d/trading-bot-security.conf` exists
- [ ] System optimizations applied: `/etc/sysctl.d/99-trading-bot.conf` exists
- [ ] User limits configured: `/etc/security/limits.d/trading-bot.conf` exists

**Automation:**
- [ ] Backup script created: `/home/tradingbot/backup-trading-bot.sh` is executable
- [ ] Backup cron job scheduled: `crontab -l` shows daily backup at 2 AM
- [ ] Setup log exists and shows no critical errors: `/var/log/vps-setup.log`

**Network:**
- [ ] Internet connectivity working: `ping google.com`
- [ ] DNS resolution working: `nslookup api.helius.xyz`
- [ ] Solana RPC accessible: `curl` test to mainnet-beta
- [ ] All required ports accessible from external network

**Security:**
- [ ] SSH keys configured for `tradingbot` user
- [ ] Cannot SSH as root (security test)
- [ ] Password authentication disabled
- [ ] Firewall blocks unauthorized ports
- [ ] System logs show no security warnings

---

## Troubleshooting Quick Reference

**If Mojo is not found:**
```bash
su - tradingbot
export PATH="$HOME/.modular/pkg/packages.modular.com_mojo/bin:$PATH"
echo 'export PATH="$HOME/.modular/pkg/packages.modular.com_mojo/bin:$PATH"' >> ~/.bashrc
```

**If Rust is not found:**
```bash
su - tradingbot
source ~/.cargo/env
echo 'source ~/.cargo/env' >> ~/.bashrc
```

**If Docker permission denied:**
```bash
sudo usermod -aG docker tradingbot
# Log out and back in for group changes to take effect
```

**If firewall blocks SSH:**
```bash
sudo ufw allow 22/tcp
sudo ufw reload
```

**If sysctl settings not applied:**
```bash
sudo sysctl -p /etc/sysctl.d/99-trading-bot.conf
```

---

## Success Criteria

Phase 2 is complete when:

1. ✅ All verification commands pass without errors
2. ✅ All checklist items are marked as complete
3. ✅ No critical errors in `/var/log/vps-setup.log`
4. ✅ SSH access works as `tradingbot` user
5. ✅ All dependencies are installed and functional
6. ✅ System is optimized and secured
7. ✅ Ready to proceed to Phase 3: Docker Compose deployment

---

**Next Phase:** Deploy Docker Compose Stack with Trading Bot and Monitoring Services

Refer to `DEPLOY_NOW.md` (Step 6) or `DEPLOYMENT.md` (Production Deployment section) for Phase 3 instructions.