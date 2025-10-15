# Phase 2: VPS Infrastructure Setup - Execution Plan
### Target Server: 38.242.239.150

---

## Pre-Execution Checklist

**1. Verify SSH Access**
- Ensure you have root SSH access to 38.242.239.150
- Test connection: `ssh root@38.242.239.150`
- Verify you can execute commands with root privileges
- If using SSH keys, ensure they're properly configured

**2. Backup Current Server State** (if server has existing data)
- Document currently installed packages: `dpkg --get-selections > /tmp/packages-before.txt`
- List running services: `systemctl list-units --type=service --state=running > /tmp/services-before.txt`
- Check current firewall rules: `ufw status numbered > /tmp/firewall-before.txt`
- Note current users: `cat /etc/passwd > /tmp/users-before.txt`

**3. Verify Server Specifications**
- Check OS version: `lsb_release -a` (should be Ubuntu 22.04+)
- Check RAM: `free -h` (should be 4GB+ minimum, 8GB+ recommended)
- Check disk space: `df -h` (should have 20GB+ free)
- Check CPU: `lscpu` (should be 2+ cores)
- Check architecture: `uname -m` (should be x86_64)

**4. Prepare Local Machine**
- Ensure you have the repository cloned locally: `/home/marcin/Projects/MojoRust/`
- Verify script exists and is readable: `ls -la scripts/vps_setup.sh`
- Make script executable if needed: `chmod +x scripts/vps_setup.sh`
- Review script contents to understand what it will do

**5. Transfer Script to Server**
Option A - Direct transfer:
```bash
scp scripts/vps_setup.sh root@38.242.239.150:/tmp/
```

Option B - Clone entire repository on server:
```bash
ssh root@38.242.239.150
apt update && apt install -y git
git clone https://github.com/YOUR_USERNAME/MojoRust.git /root/mojo-trading-bot
cd /root/mojo-trading-bot
chmod +x scripts/vps_setup.sh
```

---

## Script Execution

**1. Connect to Server**
```bash
ssh root@38.242.239.150
```

**2. Navigate to Script Location**
```bash
cd /root/mojo-trading-bot
# OR if you transferred just the script:
cd /tmp
```

**3. Review Script Options**
The script supports several command-line flags:
- `--skip-firewall`: Skip firewall configuration (use if you manage firewall separately)
- `--skip-monitoring`: Skip Prometheus/Grafana installation (use if you have external monitoring)
- `--user=USERNAME`: Use custom username instead of default `tradingbot`
- `--help`: Display help message

**4. Execute Script**

**Standard Execution** (recommended for fresh server):
```bash
sudo bash scripts/vps_setup.sh
```

**With Custom Options** (if needed):
```bash
# Skip monitoring tools if using external monitoring
sudo bash scripts/vps_setup.sh --skip-monitoring

# Use custom username
sudo bash scripts/vps_setup.sh --user=mytrader

# Skip firewall if managing separately
sudo bash scripts/vps_setup.sh --skip-firewall
```

**5. Monitor Execution**
The script will:
- Display colored output for each step (BLUE=info, GREEN=success, YELLOW=warning, RED=error)
- Log all output to `/var/log/vps-setup.log`
- Show progress through multiple phases
- Prompt for confirmation on critical steps
- Take approximately 10-20 minutes to complete

**Expected Output Sequence:**
1. Banner display with ASCII art
2. Root privilege check
3. System requirements validation
4. Package updates (may take 5-10 minutes)
5. Trading user creation
6. Firewall configuration
7. Mojo installation (may take 3-5 minutes)
8. Rust installation (may take 2-3 minutes)
9. Infisical CLI installation
10. Monitoring tools installation (Docker, Prometheus, Grafana)
11. Log rotation setup
12. SSH security hardening
13. System optimization
14. Backup script creation
15. Summary display

**6. Handle Prompts**
- If running on non-Ubuntu system, you'll be asked to confirm continuation
- SSH security configuration will warn about disabling root login
- Make sure you have SSH keys configured for the `tradingbot` user before the script completes

---

## Post-Execution Verification

**1. Check Script Completion**
- Verify script exited with success (exit code 0)
- Review summary output displayed at the end
- Check for any ERROR messages in output
- Review log file: `cat /var/log/vps-setup.log | grep -i error`

**2. Verify User Creation**
```bash
# Check if tradingbot user exists
id tradingbot
# Expected: uid=1001(tradingbot) gid=1001(tradingbot) groups=1001(tradingbot),27(sudo)

# Check user directories
ls -la /home/tradingbot/
# Expected: .config/, logs/, data/ directories

# Check Solana directory permissions
ls -la /home/tradingbot/.config/solana/
# Expected: drwx------ (700 permissions)
```

**3. Verify Dependency Installations**

**Mojo Installation:**
```bash
su - tradingbot
mojo --version
# Expected: mojo 24.4.0 (or higher)

# Test Mojo execution
mojo -c "print('Mojo is working!')"
# Expected: Mojo is working!
```

**Rust Installation:**
```bash
su - tradingbot
rustc --version
# Expected: rustc 1.75.0 (or higher)

cargo --version
# Expected: cargo 1.75.0 (or higher)
```

**Infisical CLI:**
```bash
infisical --version
# Expected: infisical version X.X.X
```

**Docker:**
```bash
docker --version
# Expected: Docker version 20.10+ or higher

docker-compose --version
# Expected: docker-compose version 1.29+ or higher

# Check Docker service
systemctl status docker
# Expected: active (running)

# Verify tradingbot user in docker group
groups tradingbot | grep docker
# Expected: docker should be in the list
```

**4. Verify Firewall Configuration**
```bash
ufw status numbered
# Expected output:
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 9090/tcp                   ALLOW IN    Anywhere    # Prometheus metrics
[ 3] 3000/tcp                   ALLOW IN    Anywhere    # Grafana dashboard
[ 4] 8080/tcp                   ALLOW IN    Anywhere    # Trading Bot API
```

**Test Firewall Rules:**
```bash
# From local machine, test SSH (should work)
ssh tradingbot@38.242.239.150

# Test Prometheus port (should be accessible after services start)
curl http://38.242.239.150:9090

# Test Grafana port (should be accessible after services start)
curl http://38.242.239.150:3000

# Test Trading Bot API port (should be accessible after services start)
curl http://38.242.239.150:8080
```

**5. Verify System Optimizations**
```bash
# Check sysctl configuration
cat /etc/sysctl.d/99-trading-bot.conf
# Expected: Network and memory optimization settings

# Verify settings are applied
sysctl net.core.rmem_max
# Expected: net.core.rmem_max = 134217728

sysctl vm.swappiness
# Expected: vm.swappiness = 10

# Check user limits
cat /etc/security/limits.d/trading-bot.conf
# Expected: nofile and nproc limits for tradingbot user
```

**6. Verify Log Rotation**
```bash
# Check logrotate configuration
cat /etc/logrotate.d/trading-bot
# Expected: Daily rotation, 30 days retention, compression enabled

# Test logrotate configuration (dry run)
logrotate -d /etc/logrotate.d/trading-bot
# Expected: No errors, shows what would be rotated
```

**7. Verify SSH Security**
```bash
# Check SSH configuration
cat /etc/ssh/sshd_config.d/trading-bot-security.conf
# Expected: PermitRootLogin no, PasswordAuthentication no

# Test SSH configuration syntax
sshd -t
# Expected: No output (means configuration is valid)

# Check SSH service status
systemctl status ssh
# Expected: active (running)
```

**CRITICAL**: Before logging out of root session, ensure you can SSH as tradingbot user:
```bash
# From another terminal on local machine
ssh tradingbot@38.242.239.150
# If this fails, you need to set up SSH keys before logging out of root
```

**8. Verify Backup Script**
```bash
# Check backup script exists
ls -la /home/tradingbot/backup-trading-bot.sh
# Expected: -rwxr-xr-x (executable)

# Check cron job
su - tradingbot
crontab -l
# Expected: 0 2 * * * /home/tradingbot/backup-trading-bot.sh >> /home/tradingbot/logs/backup.log 2>&1

# Test backup script (dry run)
su - tradingbot
bash -x /home/tradingbot/backup-trading-bot.sh
# Expected: Creates backup in /home/tradingbot/backups/
```

**9. Verify Directory Structure**
```bash
# Check all required directories exist
ls -la /home/tradingbot/
# Expected directories:
# - .config/solana (700 permissions)
# - logs (755 permissions)
# - data (755 permissions)
# - data/portfolio
# - data/backups
# - data/cache

# Verify permissions
stat -c "%a %n" /home/tradingbot/.config/solana
# Expected: 700 /home/tradingbot/.config/solana
```

**10. System Health Check**
```bash
# Check system resources
free -h
# Verify sufficient memory available

df -h
# Verify sufficient disk space

top -bn1 | head -20
# Check CPU usage and running processes

# Check for system errors
journalctl -p err -b
# Review any error messages
```

---

## Manual Configuration Adjustments

**1. SSH Key Setup for tradingbot User** (CRITICAL)

If not already done, set up SSH key authentication:

```bash
# On local machine, generate SSH key if needed
ssh-keygen -t ed25519 -C "tradingbot@38.242.239.150"

# Copy public key to server
ssh-copy-id tradingbot@38.242.239.150

# Test SSH access
ssh tradingbot@38.242.239.150
# Should connect without password
```

**2. Firewall Port Adjustments** (if needed)

If you need additional ports:
```bash
# Add API port (8080) if not already added
ufw allow 8080/tcp comment "Trading Bot API"

# Add custom monitoring ports if needed
ufw allow 5432/tcp comment "PostgreSQL" # Only if exposing database

# Reload firewall
ufw reload

# Verify
ufw status numbered
```

**3. System Optimization Tuning** (optional)

For high-frequency trading, consider additional optimizations:

```bash
# Edit sysctl configuration
nano /etc/sysctl.d/99-trading-bot.conf

# Add additional settings:
# net.ipv4.tcp_fastopen = 3
# net.ipv4.tcp_low_latency = 1
# net.core.busy_poll = 50

# Apply changes
sysctl -p /etc/sysctl.d/99-trading-bot.conf
```

**4. Monitoring Service Configuration** (if installed)

If monitoring tools were installed:

```bash
# Start Prometheus
systemctl start prometheus
systemctl enable prometheus

# Start Grafana
systemctl start grafana-server
systemctl enable grafana-server

# Verify services
systemctl status prometheus
systemctl status grafana-server

# Access Grafana
# URL: http://38.242.239.150:3000
# Default credentials: admin/admin
```

**5. Log Directory Permissions** (if needed)

```bash
# Ensure tradingbot can write to logs
chown -R tradingbot:tradingbot /home/tradingbot/logs
chmod 755 /home/tradingbot/logs

# Create system log directory if needed
mkdir -p /var/log/trading-bot
chown tradingbot:tradingbot /var/log/trading-bot
chmod 755 /var/log/trading-bot
```

---

## Troubleshooting Common Issues

**Issue 1: Mojo Installation Fails**

**Symptoms:**
- Error during Mojo installation
- `mojo --version` command not found
- Modular installation script fails

**Solutions:**
```bash
# Check if Modular is accessible
curl -I https://get.modular.com
# Should return 200 OK

# Manual Mojo installation
su - tradingbot
curl -s https://get.modular.com | sh -
modular install mojo

# Add to PATH manually
echo 'export PATH="$HOME/.modular/pkg/packages.modular.com_mojo/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
mojo --version
```

**Issue 2: Rust Installation Fails**

**Symptoms:**
- Error during Rust installation
- `rustc` or `cargo` command not found

**Solutions:**
```bash
# Manual Rust installation
su - tradingbot
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Source cargo environment
source ~/.cargo/env

# Add to bashrc
echo 'source ~/.cargo/env' >> ~/.bashrc

# Verify
rustc --version
cargo --version
```

**Issue 3: Infisical CLI Installation Fails**

**Symptoms:**
- Error during Infisical installation
- `infisical` command not found

**Solutions:**
```bash
# Check if repository is accessible
curl -I https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh

# Manual installation
curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo bash
sudo apt-get update
sudo apt-get install -y infisical

# Verify
infisical --version
```

**Issue 4: Docker Installation Fails**

**Symptoms:**
- Docker service not running
- `docker` command not found
- Permission denied errors

**Solutions:**
```bash
# Check Docker installation
docker --version

# If not installed, manual installation
sudo apt-get update
sudo apt-get install -y docker.io docker-compose

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group
sudo usermod -aG docker tradingbot

# Verify (may need to log out and back in)
su - tradingbot
docker ps
```

**Issue 5: Firewall Blocks SSH After Configuration**

**Symptoms:**
- Cannot SSH to server after firewall setup
- Connection timeout or refused

**Solutions:**
```bash
# If you still have root access via console:
sudo ufw allow 22/tcp
sudo ufw reload

# If completely locked out, use VPS console/recovery mode:
# Boot into recovery mode
# Mount filesystem
# Edit /etc/ufw/ufw.conf and set ENABLED=no
# Reboot and reconfigure firewall
```

**Issue 6: SSH Root Login Disabled Too Early**

**Symptoms:**
- Cannot SSH as root
- Cannot SSH as tradingbot (keys not set up)
- Locked out of server

**Solutions:**
```bash
# Use VPS console/recovery mode
# Edit /etc/ssh/sshd_config.d/trading-bot-security.conf
# Temporarily set: PermitRootLogin yes
# Restart SSH: systemctl restart ssh
# Set up SSH keys for tradingbot
# Re-disable root login
```

**Issue 7: Insufficient Disk Space**

**Symptoms:**
- Installation fails with "No space left on device"
- Script stops during package installation

**Solutions:**
```bash
# Check disk usage
df -h

# Clean up package cache
sudo apt-get clean
sudo apt-get autoclean

# Remove old kernels
sudo apt-get autoremove --purge

# Check for large files
du -sh /* | sort -h

# Expand disk if needed (VPS provider specific)
```

**Issue 8: System Optimization Not Applied**

**Symptoms:**
- `sysctl` values don't match configuration
- Performance issues

**Solutions:**
```bash
# Manually apply sysctl settings
sudo sysctl -p /etc/sysctl.d/99-trading-bot.conf

# Verify specific settings
sysctl net.core.rmem_max
sysctl vm.swappiness

# Check for conflicts with other sysctl files
ls -la /etc/sysctl.d/

# Reboot if necessary
sudo reboot
```

---

## Validation Checklist

Before proceeding to Phase 3 (Docker Compose deployment), verify:

- [ ] Server is accessible via SSH as `tradingbot` user
- [ ] Mojo 24.4+ is installed and working: `mojo --version`
- [ ] Rust 1.75+ is installed and working: `rustc --version`
- [ ] Infisical CLI is installed: `infisical --version`
- [ ] Docker is installed and running: `docker ps`
- [ ] Docker Compose is installed: `docker-compose --version`
- [ ] Firewall is configured with ports: 22, 9090, 3000, 8080
- [ ] User `tradingbot` exists with sudo privileges
- [ ] Directory structure exists: `~/.config/solana`, `~/logs`, `~/data`
- [ ] Log rotation is configured: `/etc/logrotate.d/trading-bot`
- [ ] SSH security is hardened (root login disabled, key-based auth only)
- [ ] System optimizations are applied: `/etc/sysctl.d/99-trading-bot.conf`
- [ ] Backup script is created and scheduled: `crontab -l`
- [ ] No critical errors in setup log: `/var/log/vps-setup.log`
- [ ] System resources are adequate (RAM, disk, CPU)
- [ ] Network connectivity is stable (ping test to Solana RPCs)

---

## Next Steps

Once all verification steps pass:

1. **Proceed to Phase 3**: Deploy Docker Compose Stack
   - Transfer deployment files to server
   - Configure `docker-compose.yml` with environment variables
   - Build and start services

2. **Document Server Configuration**
   - Record server IP, ports, and access credentials
   - Document any custom configurations made
   - Save SSH keys and access methods securely

3. **Set Up Monitoring**
   - Configure Prometheus targets
   - Import Grafana dashboards
   - Set up alerting rules

4. **Prepare for Application Deployment**
   - Transfer `.env` file with configuration
   - Set up Solana wallet keypair
   - Configure Infisical secrets

Refer to `DEPLOY_NOW.md` for the complete deployment workflow and `DEPLOYMENT.md` for detailed documentation on each subsequent phase.