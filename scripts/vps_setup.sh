#!/bin/bash

# =============================================================================
# Automated VPS Setup Script for MojoRust Trading Bot
# =============================================================================
# This script prepares a VPS for trading bot deployment with all dependencies
# Run this as root on a fresh Ubuntu 22.04+ VPS

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SKIP_FIREWALL=false
SKIP_MONITORING=false
TRADING_USER="tradingbot"
LOG_FILE="/var/log/vps-setup.log"

# =============================================================================
# Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

print_banner() {
    echo -e "${PURPLE}"
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║                                                                   ║"
    echo "║    🚀 AUTOMATED VPS SETUP FOR TRADING BOT 🚀                     ║"
    echo "║                                                                   ║"
    echo "║    Preparing server for MojoRust Trading Bot deployment          ║"
    echo "║    with aggressive spam filtering and security                    ║"
    echo "║                                                                   ║"
    echo "╚═════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root (sudo)"
        echo "Usage: sudo bash $0"
        exit 1
    fi
}

check_system() {
    log_step "Checking system requirements..."

    # Check OS
    if ! grep -q "Ubuntu" /etc/os-release; then
        log_warning "This script is optimized for Ubuntu 22.04+"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        log_warning "Architecture $ARCH may not be supported by all tools"
    fi

    # Check memory
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $MEMORY_GB -lt 4 ]]; then
        log_warning "System has only ${MEMORY_GB}GB RAM (4GB+ recommended)"
    else
        log_success "✅ System has ${MEMORY_GB}GB RAM"
    fi

    # Check disk space
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $DISK_GB -lt 20 ]]; then
        log_warning "System has only ${DISK_GB}GB free disk space (20GB+ recommended)"
    else
        log_success "✅ System has ${DISK_GB}GB free disk space"
    fi

    log_success "✅ System requirements check completed"
}

update_system() {
    log_step "Updating system packages..."

    # Update package list
    apt update

    # Upgrade existing packages
    apt upgrade -y

    # Install essential packages
    apt install -y \
        curl \
        wget \
        git \
        build-essential \
        software-properties-common \
        unzip \
        htop \
        iotop \
        nethogs \
        tree \
        vim \
        nano \
        tmux \
        screen \
        bc \
        jq \
        netcat-openbsd

    # Clean up
    apt autoremove -y
    apt autoclean

    log_success "✅ System updated and essential packages installed"
}

create_trading_user() {
    log_step "Creating trading bot user..."

    if id "$TRADING_USER" &>/dev/null; then
        log_warning "User $TRADING_USER already exists"

        # Add to sudo group if not already
        if ! groups "$TRADING_USER" | grep -q sudo; then
            usermod -aG sudo "$TRADING_USER"
            log_success "✅ Added $TRADING_USER to sudo group"
        fi
    else
        # Create new user
        adduser --disabled-password --gecos "" "$TRADING_USER"
        usermod -aG sudo "$TRADING_USER"

        log_success "✅ User $TRADING_USER created and added to sudo group"
    fi

    # Setup user directory structure
    su - "$TRADING_USER" -c "
        mkdir -p ~/.config/solana
        mkdir -p ~/logs
        mkdir -p ~/data/portfolio
        mkdir -p ~/data/backups
        mkdir -p ~/data/cache
        chmod 700 ~/.config/solana
        chmod 755 ~/logs
        chmod 755 ~/data
    "

    log_success "✅ User directories created with proper permissions"
}

configure_firewall() {
    if [[ "$SKIP_FIREWALL" == true ]]; then
        log_warning "⚠️  Skipping firewall configuration"
        return 0
    fi

    log_step "Configuring firewall..."

    # Reset firewall rules
    ufw --force reset

    # Allow SSH (important: don't lock yourself out!)
    ufw allow 22/tcp

    # Allow trading bot monitoring ports (optional)
    ufw allow 9090/tcp comment "Prometheus metrics"
    ufw allow 3000/tcp comment "Grafana dashboard"

    # Enable firewall
    ufw --force enable

    # Check status
    ufw status

    log_success "✅ Firewall configured and enabled"
}

install_mojo() {
    log_step "Installing Mojo programming language..."

    # Install Mojo as trading bot user
    su - "$TRADING_USER" -c '
        echo "🔧 Installing Mojo Modular..."
        curl -s https://get.modular.com | sh
        modular install mojo

        # Add to PATH
        echo "export PATH=\"\$HOME/.modular/pkg/packages.modular.com_mojo/bin:\$PATH\"" >> ~/.bashrc

        # Source PATH in current session
        export PATH="\$HOME/.modular/pkg/packages.modular.com_mojo/bin:\$PATH"

        # Verify installation
        if command -v mojo &> /dev/null; then
            echo "✅ Mojo installed successfully"
            mojo --version
        else
            echo "❌ Mojo installation failed"
            exit 1
        fi
    '

    log_success "✅ Mojo installed successfully"
}

install_rust() {
    log_step "Installing Rust programming language..."

    # Install Rust as trading bot user
    su - "$TRADING_USER" -c '
        echo "🔧 Installing Rust..."
        curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

        # Source cargo env
        source ~/.cargo/env

        # Add to bashrc
        echo "source ~/.cargo/env" >> ~/.bashrc

        # Verify installation
        if command -v rustc &> /dev/null; then
            echo "✅ Rust installed successfully"
            rustc --version
            cargo --version
        else
            echo "❌ Rust installation failed"
            exit 1
        fi
    '

    log_success "✅ Rust installed successfully"
}

install_infisical_cli() {
    log_step "Installing Infisical CLI..."

    # Download and install Infisical CLI
    curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | bash

    # Update package list and install
    apt-get update
    apt-get install -y infisical

    # Verify installation
    if command -v infisical &> /dev/null; then
        log_success "✅ Infisical CLI installed successfully"
        infisical --version
    else
        log_error "❌ Infisical CLI installation failed"
        return 1
    fi
}

install_monitoring_tools() {
    if [[ "$SKIP_MONITORING" == true ]]; then
        log_warning "⚠️  Skipping monitoring tools installation"
        return 0
    fi

    log_step "Installing monitoring tools..."

    # Install additional monitoring tools
    apt install -y \
        prometheus \
        grafana \
        docker.io \
        docker-compose

    # Start and enable services
    systemctl enable docker
    systemctl start docker

    # Add trading bot user to docker group
    usermod -aG docker "$TRADING_USER"

    log_success "✅ Monitoring tools installed"
}

setup_log_rotation() {
    log_step "Configuring log rotation..."

    # Create logrotate configuration for trading bot
    cat > /etc/logrotate.d/trading-bot <<EOF
/home/tradingbot/logs/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 tradingbot tradingbot
    postrotate
        # Send signal to trading bot to reopen logs if running
        pkill -SIGUSR1 -f trading-bot || true
    endscript
}
EOF

    # Create logrotate configuration for system logs
    cat > /etc/logrotate.d/trading-bot-system <<EOF
/var/log/trading-bot/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
EOF

    # Create directory for system logs
    mkdir -p /var/log/trading-bot
    chmod 755 /var/log/trading-bot

    # Test log rotation configuration
    logrotate -d /etc/logrotate.d/trading-bot 2>&1 | head -20

    log_success "✅ Log rotation configured"
}

setup_ssh_security() {
    log_step "Configuring SSH security..."

    # Backup original SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

    # Secure SSH configuration
    cat > /etc/ssh/sshd_config.d/trading-bot-security.conf <<EOF
# SSH Security Configuration for Trading Bot
# Generated by VPS setup script

# Disable root login
PermitRootLogin no

# Disable password authentication (use keys only)
PasswordAuthentication no
ChallengeResponseAuthentication no

# Disable empty passwords
PermitEmptyPasswords no

# Limit login attempts
MaxAuthTries 3
MaxSessions 2

# Use specific protocol
Protocol 2

# Set idle timeout
ClientAliveInterval 300
ClientAliveCountMax 2

# Allow only trading bot user and sudo
AllowUsers tradingbot
AllowGroups sudo

# Use specific port (optional - change from 22 if desired)
# Port 2222
EOF

    # Test SSH configuration
    sshd -t

    # Restart SSH service
    systemctl restart ssh

    log_success "✅ SSH security configured"
    log_warning "⚠️  Root login disabled. Make sure you have SSH keys set up for $TRADING_USER user"
}

setup_system_optimization() {
    log_step "Optimizing system performance..."

    # Create sysctl configuration for trading bot
    cat > /etc/sysctl.d/99-trading-bot.conf <<EOF
# System Optimization for Trading Bot
# Generated by VPS setup script

# Network optimization
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# File descriptor limits
fs.file-max = 2097152

# Process limits
kernel.pid_max = 4194303

# Memory management
vm.swappiness = 10
vm.dirty_ratio = 60
vm.dirty_background_ratio = 2

# Network stack optimization
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
EOF

    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-trading-bot.conf

    # Set limits for trading bot user
    cat > /etc/security/limits.d/trading-bot.conf <<EOF
# Limits for trading bot user
tradingbot soft nofile 65536
tradingbot hard nofile 65536
tradingbot soft nproc 32768
tradingbot hard nproc 32768
EOF

    log_success "✅ System optimization applied"
}

create_backup_script() {
    log_step "Creating backup script..."

    # Create backup script
    cat > /home/tradingbot/backup-trading-bot.sh <<'EOF'
#!/bin/bash

# Trading Bot Backup Script
# Generated by VPS setup script

BACKUP_DIR="/home/tradingbot/backups"
DATE=$(date +%Y%m%d-%H%M%S)
PROJECT_DIR="/home/tradingbot/mojo-trading-bot"
RETENTION_DAYS=7

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration and data
echo "Creating backup: $DATE"

# Compress important files
tar -czf "$BACKUP_DIR/trading-bot-backup-$DATE.tar.gz" \
    -C "$PROJECT_DIR" \
    .env \
    data/ \
    config/ \
    --exclude="data/cache/*" \
    --exclude="logs/*.log" \
    --exclude="target/*" 2>/dev/null || true

# Backup system configuration
tar -czf "$BACKUP_DIR/system-backup-$DATE.tar.gz" \
    /etc/systemd/system/trading-bot.service \
    /etc/logrotate.d/trading-bot* \
    /etc/sysctl.d/99-trading-bot.conf \
    2>/dev/null || true

# Clean old backups
find "$BACKUP_DIR" -name "trading-bot-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "system-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $BACKUP_DIR/trading-bot-backup-$DATE.tar.gz"
echo "System backup: $BACKUP_DIR/system-backup-$DATE.tar.gz"
echo "Retention: $RETENTION_DAYS days"
EOF

    # Make backup script executable
    chmod +x /home/tradingbot/backup-trading-bot.sh

    # Setup cron job for daily backups
    su - "$TRADING_USER" -c '
        # Create crontab entry
        (crontab -l 2>/dev/null; echo "0 2 * * * /home/tradingbot/backup-trading-bot.sh >> /home/tradingbot/logs/backup.log 2>&1") | crontab
    '

    log_success "✅ Backup script and cron job created"
}

print_setup_summary() {
    echo ""
    log_success "🎉 VPS SETUP COMPLETE!"
    echo "======================================"
    echo ""
    echo "📋 Setup Summary:"
    echo "   • Trading User: $TRADING_USER"
    echo "   • Mojo: ✅ Installed"
    echo "   • Rust: ✅ Installed"
    echo "   • Infisical CLI: ✅ Installed"
    echo "   • Firewall: ✅ Configured"
    echo "   • Log Rotation: ✅ Configured"
    echo "   • SSH Security: ✅ Hardened"
    echo "   • System Optimization: ✅ Applied"
    echo "   • Backup Script: ✅ Created"
    echo ""
    echo "🔑 Security Notes:"
    echo "   • Root login disabled via SSH"
    echo "   • Password authentication disabled"
    echo "   • Only key-based authentication allowed"
    echo "   • Firewall configured with essential ports"
    echo ""
    echo "📁 Directories Created:"
    echo "   • /home/tradingbot/.config/solana"
    echo "   • /home/tradingbot/logs"
    echo "   • /home/tradingbot/data/portfolio"
    echo "   • /home/tradingbot/data/backups"
    echo "   • /home/tradingbot/data/cache"
    echo ""
    echo "🚀 Next Steps:"
    echo "   1. Switch to trading bot user:"
    echo "      su - $TRADING_USER"
    echo ""
    echo "   2. Clone your repository:"
    echo "      git clone https://github.com/YOUR_USERNAME/mojo-trading-bot.git"
    echo "      cd mojo-trading-bot"
    echo ""
    echo "   3. Configure Infisical:"
    echo "      infisical login"
    echo "      export INFISICAL_PROJECT_ID=your_project_id"
    echo ""
    echo "   4. Setup wallet:"
    echo "      nano ~/.config/solana/id.json"
    echo "      chmod 600 ~/.config/solana/id.json"
    echo ""
    echo "   5. Run deployment:"
    echo "      ./scripts/deploy_with_filters.sh"
    echo ""
    echo "📚 For detailed instructions, see DEPLOYMENT.md"
    echo "📝 Setup log: $LOG_FILE"
    echo ""
    echo "⚠️  IMPORTANT: Make sure you have SSH keys configured for $TRADING_USER"
    echo "   before logging out of root, as SSH password auth is disabled!"
    echo ""
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    # Start logging
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1

    print_banner

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-firewall)
                SKIP_FIREWALL=true
                shift
                ;;
            --skip-monitoring)
                SKIP_MONITORING=true
                shift
                ;;
            --user=*)
                TRADING_USER="${1#*=}"
                shift
                ;;
            --help|-h)
                echo "Usage: sudo bash $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-firewall     Skip firewall configuration"
                echo "  --skip-monitoring   Skip monitoring tools installation"
                echo "  --user=USERNAME     Use custom username (default: tradingbot)"
                echo "  --help, -h          Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run setup steps
    check_root
    check_system
    update_system
    create_trading_user
    configure_firewall
    install_mojo
    install_rust
    install_infisical_cli
    install_monitoring_tools
    setup_log_rotation
    setup_ssh_security
    setup_system_optimization
    create_backup_script

    # Print summary
    print_setup_summary
}

# Trap for cleanup
trap 'log_error "Setup script interrupted"' INT TERM

# Run main function
main "$@"