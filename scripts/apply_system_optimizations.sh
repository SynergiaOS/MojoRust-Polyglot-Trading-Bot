#!/bin/bash

# =============================================================================
# 🔧 System Optimization Script for MojoRust Trading Bot
# =============================================================================
# This script applies comprehensive system-level optimizations for maximum performance:
# - System limits and resource management
# - CPU governor and frequency optimization
# - Memory management and swappiness tuning
# - Network performance optimization
# - File system and I/O optimization
# - Process priority and scheduling optimization

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
JSON_OUTPUT=false
VERBOSE=false
DRY_RUN=false
BACKUP_CONFIGS=true
FORCE_RESTART=false

# Global variables
SYSTEM_INFO=""
OPTIMIZATIONS_APPLIED=()
RESTART_REQUIRED=false
BACKUP_DIR="/tmp/system_optimization_backup_$(date +%Y%m%d_%H%M%S)"

# Logging functions
log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

log_warning() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

log_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}$1${NC}"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                              ║"
        echo "║    🔧 System Optimization Script - MojoRust Trading Bot      ║"
        echo "║                                                              ║"
        echo "║    Applying comprehensive system-level optimizations         ║"
        echo "║                                                              ║"
        echo "║    Project: $PROJECT_ROOT"
        echo "║    Timestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')"
        echo "║                                                              ║"
        echo "╚═════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Check root privileges
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges for system optimizations"
        log_info "Please run with sudo: sudo $0 $*"
        exit 1
    fi
}

# Collect system information
collect_system_info() {
    log_header "System Information Collection"

    # Basic system info
    local cpu_count=$(nproc)
    local total_mem=$(free -h | awk '/^Mem:/ {print $2}')
    local kernel_version=$(uname -r)
    local os_info=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)

    # Current limits
    local file_limit=$(ulimit -n)
    local process_limit=$(ulimit -u)

    # Current sysctl values
    local current_file_max=$(sysctl -n fs.file-max 2>/dev/null || echo "N/A")
    local current_pid_max=$(sysctl -n kernel.pid_max 2>/dev/null || echo "N/A")
    local current_swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "N/A")

    SYSTEM_INFO="CPU Count: $cpu_count | Memory: $total_mem | Kernel: $kernel_version | OS: $os_info | File Limit: $file_limit | Process Limit: $process_limit | File-Max: $current_file_max | PID-Max: $current_pid_max | Swappiness: $current_swappiness"

    if [ "$JSON_OUTPUT" = false ]; then
        echo "System Information:"
        echo "  CPU Count: $cpu_count cores"
        echo "  Total Memory: $total_mem"
        echo "  Kernel Version: $kernel_version"
        echo "  OS: $os_info"
        echo "  Current File Limit: $file_limit"
        echo "  Current Process Limit: $process_limit"
        echo "  Current fs.file-max: $current_file_max"
        echo "  Current kernel.pid_max: $current_pid_max"
        echo "  Current vm.swappiness: $current_swappiness"
        echo ""
    fi
}

# Create backup directory
create_backup() {
    if [ "$BACKUP_CONFIGS" = true ] && [ "$DRY_RUN" = false ]; then
        log_info "Creating backup directory: $BACKUP_DIR"
        mkdir -p "$BACKUP_DIR"

        # Backup existing sysctl configurations
        if [ -f "/etc/sysctl.conf" ]; then
            cp /etc/sysctl.conf "$BACKUP_DIR/sysctl.conf.backup"
        fi

        if [ -d "/etc/sysctl.d" ]; then
            cp -r /etc/sysctl.d "$BACKUP_DIR/"
        fi

        # Backup limits configuration
        if [ -f "/etc/security/limits.conf" ]; then
            cp /etc/security/limits.conf "$BACKUP_DIR/limits.conf.backup"
        fi

        # Backup system services
        if [ -f "/etc/systemd/system.conf" ]; then
            cp /etc/systemd/system.conf "$BACKUP_DIR/system.conf.backup"
        fi

        log_success "Backup created at: $BACKUP_DIR"
    fi
}

# Optimize system limits
optimize_system_limits() {
    log_header "System Limits Optimization"

    local limits_config="/etc/security/limits.conf"
    local limits_d_config="/etc/security/limits.d/99-trading-bot.conf"

    # Check if limits file exists and create backup
    if [ -f "$limits_config" ] && [ "$BACKUP_CONFIGS" = true ] && [ "$DRY_RUN" = false ]; then
        cp "$limits_config" "$BACKUP_DIR/limits.conf.original.backup"
    fi

    # Create custom limits configuration
    local limits_content="# MojoRust Trading Bot Performance Optimizations
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 32768
* hard nproc 32768
* soft memlock unlimited
* hard memlock unlimited
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 32768
root hard nproc 32768
root soft memlock unlimited
root hard memlock unlimited"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create limits configuration: $limits_d_config"
        echo "$limits_content"
    else
        log_info "Creating optimized limits configuration: $limits_d_config"
        echo "$limits_content" > "$limits_d_config"
        OPTIMIZATIONS_APPLIED+=("System limits optimized")
        RESTART_REQUIRED=true
    fi

    # Verify limits
    local current_nofile=$(ulimit -n)
    local current_nproc=$(ulimit -u)

    log_verbose "Current limits: nofile=$current_nofile, nproc=$current_nproc"
}

# Optimize kernel parameters
optimize_kernel_parameters() {
    log_header "Kernel Parameters Optimization"

    local sysctl_config="/etc/sysctl.d/99-trading-bot.conf"

    # Create comprehensive sysctl configuration
    local sysctl_content="# MojoRust Trading Bot Performance Optimizations
# Generated on $(date)

# === File System and I/O Optimization ===
fs.file-max = 2097152
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 256

# === Memory Management ===
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# === Network Performance ===
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 65535
net.ipv4.tcp_rmem = 4096 65536 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535

# === Process Management ===
kernel.pid_max = 4194303
kernel.sched_migration_cost_ns = 5000000

# === Security and Hardening ===
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# === Trading Bot Specific ===
# Reduce context switching overhead
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 15000000

# Improve real-time performance
kernel.sched_rt_runtime_us = -1"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create sysctl configuration: $sysctl_config"
        echo "$sysctl_content"
    else
        log_info "Creating optimized sysctl configuration: $sysctl_config"
        echo "$sysctl_content" > "$sysctl_config"
        OPTIMIZATIONS_APPLIED+=("Kernel parameters optimized")

        # Apply sysctl settings immediately
        log_info "Applying sysctl settings..."
        sysctl -p "$sysctl_config" >/dev/null 2>&1 || {
            log_warning "Some sysctl settings could not be applied immediately"
        }
    fi
}

# Optimize CPU governor and frequency
optimize_cpu_governor() {
    log_header "CPU Governor and Frequency Optimization"

    # Check if CPU frequency scaling is available
    if [ ! -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
        log_warning "CPU frequency scaling not available"
        return 1
    fi

    # Get current governor
    local current_governor=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | head -1)

    log_info "Current CPU governor: $current_governor"

    # Set performance governor
    if [ "$current_governor" != "performance" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would set CPU governor to 'performance'"
        else
            log_info "Setting CPU governor to 'performance'..."
            for cpu_dir in /sys/devices/system/cpu/cpu*/cpufreq; do
                if [ -w "$cpu_dir/scaling_governor" ]; then
                    echo performance > "$cpu_dir/scaling_governor"
                fi
            done
            OPTIMIZATIONS_APPLIED+=("CPU governor set to performance")
        fi
    else
        log_success "CPU governor already set to 'performance'"
    fi

    # Check for turbo boost
    if [ -f "/sys/devices/system/cpu/intel_pstate/no_turbo" ]; then
        local turbo_disabled=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo)
        if [ "$turbo_disabled" = "0" ]; then
            log_info "Turbo boost is enabled"
        else
            log_info "Turbo boost is disabled"
        fi
    fi
}

# Optimize memory management
optimize_memory_management() {
    log_header "Memory Management Optimization"

    # Check current swappiness
    local current_swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "N/A")
    log_info "Current swappiness: $current_swappiness"

    # Clear system caches (if not dry run)
    if [ "$DRY_RUN" = false ]; then
        log_info "Clearing system caches..."
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || log_warning "Could not clear system caches"
        OPTIMIZATIONS_APPLIED+=("System caches cleared")
    else
        log_info "[DRY RUN] Would clear system caches"
    fi

    # Set transparent huge pages to madvise
    if [ -f "/sys/kernel/mm/transparent_hugepage/enabled" ]; then
        local current_thp=$(cat /sys/kernel/mm/transparent_hugepage/enabled)
        log_info "Current transparent huge pages: $current_thp"

        if [[ "$current_thp" != *"madvise"* ]]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY RUN] Would set transparent huge pages to madvise"
            else
                log_info "Setting transparent huge pages to madvise..."
                echo madvise > /sys/kernel/mm/transparent_hugepage/enabled
                OPTIMIZATIONS_APPLIED+=("Transparent huge pages optimized")
            fi
        fi
    fi

    # Optimize NUMA balancing (if available)
    if [ -f "/proc/sys/kernel/numa_balancing" ]; then
        local current_numa=$(cat /proc/sys/kernel/numa_balancing)
        log_info "Current NUMA balancing: $current_numa"

        if [ "$current_numa" = "1" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY RUN] Would disable NUMA balancing for performance"
            else
                log_info "Disabling NUMA balancing for better performance..."
                echo 0 > /proc/sys/kernel/numa_balancing
                OPTIMIZATIONS_APPLIED+=("NUMA balancing disabled")
            fi
        fi
    fi
}

# Optimize I/O scheduler
optimize_io_scheduler() {
    log_header "I/O Scheduler Optimization"

    # Find block devices
    for device in /sys/block/*/queue/scheduler; do
        if [ -f "$device" ]; then
            local block_device=$(echo "$device" | cut -d'/' -f4)
            local current_scheduler=$(cat "$device" | grep -o '\[.*\]' | tr -d '[]')

            log_info "Device $block_device: Current scheduler = $current_scheduler"

            # For SSDs, use noop or deadline scheduler
            if [ "$current_scheduler" != "deadline" ] && [ "$current_scheduler" != "noop" ]; then
                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would set I/O scheduler for $block_device to 'deadline'"
                else
                    log_info "Setting I/O scheduler for $block_device to 'deadline'..."
                    echo deadline > "$device" 2>/dev/null || {
                        log_warning "Could not set I/O scheduler for $block_device"
                    }
                    OPTIMIZATIONS_APPLIED+=("I/O scheduler optimized for $block_device")
                fi
            fi
        fi
    done
}

# Optimize system services
optimize_system_services() {
    log_header "System Services Optimization"

    # Disable unnecessary services
    local services_to_disable=(
        "bluetooth"
        "cups"
        "avahi-daemon"
        "whoopsie"
        "snapd"
    )

    for service in "${services_to_disable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY RUN] Would disable service: $service"
            else
                log_info "Disabling service: $service"
                systemctl disable "$service" 2>/dev/null || log_warning "Could not disable $service"
                systemctl stop "$service" 2>/dev/null || log_warning "Could not stop $service"
                OPTIMIZATIONS_APPLIED+=("Service $service disabled")
            fi
        fi
    done

    # Enable performance-related services
    local services_to_enable=(
        "systemd-udevd"
    )

    for service in "${services_to_enable[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            log_success "Service $service already enabled"
        else
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY RUN] Would enable service: $service"
            else
                log_info "Enabling service: $service"
                systemctl enable "$service" 2>/dev/null || log_warning "Could not enable $service"
                OPTIMIZATIONS_APPLIED+=("Service $service enabled")
            fi
        fi
    done
}

# Optimize process priority for trading bot
optimize_process_priority() {
    log_header "Process Priority Optimization"

    # Check if trading bot is running
    local trading_bot_processes=$(pgrep -f "trading-bot\|mojo\|rust-modules" || true)

    if [ -n "$trading_bot_processes" ]; then
        log_info "Found trading bot processes, optimizing priority..."

        echo "$trading_bot_processes" | while read -r pid; do
            if [ -d "/proc/$pid" ]; then
                local current_priority=$(ps -p "$pid" -o ni --no-headers 2>/dev/null || echo "N/A")
                local process_name=$(ps -p "$pid" -o comm --no-headers 2>/dev/null || echo "unknown")

                log_info "Process $pid ($process_name): Current priority = $current_priority"

                if [ "$DRY_RUN" = true ]; then
                    log_info "[DRY RUN] Would set priority for $pid to -10"
                else
                    # Set higher priority (lower nice value)
                    renice -10 "$pid" >/dev/null 2>&1 || log_warning "Could not set priority for $pid"
                    OPTIMIZATIONS_APPLIED+=("Process priority optimized for $pid")
                fi
            fi
        done
    else
        log_info "No trading bot processes found"
    fi
}

# Apply systemd optimizations
optimize_systemd() {
    log_header "SystemD Optimization"

    local systemd_config="/etc/systemd/system.conf"

    # Create systemd optimizations
    local systemd_content="# MojoRust Trading Bot SystemD Optimizations
[Manager]
# Reduce CPU usage by systemd
DefaultCPUAccounting=no
DefaultMemoryAccounting=no
DefaultTasksAccounting=no

# Improve startup performance
DefaultTimeoutStartSec=10s
DefaultTimeoutStopSec=10s
DefaultTimeoutAbortSec=10s

# Optimize logging
SystemMaxUse=100M
RuntimeMaxUse=50M

# Improve performance for high-frequency operations
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=32768"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create systemd optimization: $systemd_config"
    else
        # Backup original config
        if [ -f "$systemd_config" ] && [ "$BACKUP_CONFIGS" = true ]; then
            cp "$systemd_config" "$BACKUP_DIR/systemd.conf.original.backup"
        fi

        # Apply optimizations (append if file exists)
        echo "$systemd_content" >> "$systemd_config"
        OPTIMIZATIONS_APPLIED+=("SystemD optimized")
        RESTART_REQUIRED=true
    fi
}

# Verify optimizations
verify_optimizations() {
    log_header "Optimization Verification"

    # Check file limits
    local new_file_limit=$(ulimit -n)
    local new_process_limit=$(ulimit -u)

    log_info "Updated limits:"
    echo "  File limit: $new_file_limit"
    echo "  Process limit: $new_process_limit"

    # Check sysctl values
    local new_file_max=$(sysctl -n fs.file-max 2>/dev/null || echo "N/A")
    local new_swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "N/A")
    local new_rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "N/A")

    log_info "Updated sysctl values:"
    echo "  fs.file-max: $new_file_max"
    echo "  vm.swappiness: $new_swappiness"
    echo "  net.core.rmem_max: $new_rmem_max"

    # Check CPU governor
    if [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
        local new_governor=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | head -1)
        log_info "CPU governor: $new_governor"
    fi

    # Summary
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_info "Optimization Summary:"
        echo "  Optimizations Applied: ${#OPTIMIZATIONS_APPLIED[@]}"
        for optimization in "${OPTIMIZATIONS_APPLIED[@]}"; do
            echo "    - $optimization"
        done

        if [ "$RESTART_REQUIRED" = true ]; then
            log_warning "System restart required for some optimizations to take full effect"
            log_info "Run: sudo reboot"
        fi

        if [ ${#OPTIMIZATIONS_APPLIED[@]} -gt 0 ]; then
            log_success "System optimization completed successfully"
        else
            log_warning "No optimizations were applied"
        fi
    fi
}

# Generate final report
generate_report() {
    log_header "Optimization Report"

    if [ "$JSON_OUTPUT" = true ]; then
        cat << EOF
{
    "timestamp": "$(date -Iseconds)",
    "system_info": "$SYSTEM_INFO",
    "optimizations_applied": ${#OPTIMIZATIONS_APPLIED[@]},
    "optimizations": [$(printf '"%s",' "${OPTIMIZATIONS_APPLIED[@]}" | sed 's/,$//')],
    "restart_required": $RESTART_REQUIRED,
    "backup_location": "$BACKUP_DIR",
    "dry_run": $DRY_RUN
}
EOF
    else
        echo "=== System Optimization Report ==="
        echo "Generated: $(date)"
        echo "System Info: $SYSTEM_INFO"
        echo ""
        echo "Optimizations Applied (${#OPTIMIZATIONS_APPLIED[@]}):"
        for optimization in "${OPTIMIZATIONS_APPLIED[@]}"; do
            echo "  ✓ $optimization"
        done
        echo ""
        echo "Backup Location: $BACKUP_DIR"
        echo "Restart Required: $([ "$RESTART_REQUIRED" = true ] && echo "Yes" || echo "No")"
        echo "Dry Run: $([ "$DRY_RUN" = true ] && echo "Yes" || echo "No")"
        echo ""
        echo "=== Next Steps ==="
        if [ "$RESTART_REQUIRED" = true ] && [ "$DRY_RUN" = false ]; then
            echo "1. Restart the system: sudo reboot"
        fi
        echo "2. Monitor system performance: ./scripts/diagnose_cpu_usage.sh --watch"
        echo "3. Verify trading bot performance"
        echo ""
        echo "=== Rollback Information ==="
        if [ "$BACKUP_CONFIGS" = true ] && [ -d "$BACKUP_DIR" ]; then
            echo "Backup files available at: $BACKUP_DIR"
            echo "To restore: sudo cp $BACKUP_DIR/* /etc/"
        fi
    fi
}

# Cleanup function
cleanup() {
    log_verbose "Cleanup completed"
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-backup)
                BACKUP_CONFIGS=false
                shift
                ;;
            --force-restart)
                FORCE_RESTART=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --json                     Output results in JSON format"
                echo "  --verbose                  Enable verbose logging"
                echo "  --dry-run                  Show what would be done without making changes"
                echo "  --no-backup               Skip creating backup files"
                echo "  --force-restart           Force restart after optimization"
                echo "  --help, -h                Show this help message"
                echo ""
                echo "This script applies comprehensive system optimizations for trading bot performance."
                echo "It modifies system limits, kernel parameters, and various performance settings."
                echo ""
                echo "WARNING: This script requires root privileges and modifies system configurations."
                echo "Always review changes before applying and ensure you have backups."
                echo ""
                echo "Example usage:"
                echo "  sudo $0 --dry-run         # Preview changes without applying"
                echo "  sudo $0                   # Apply optimizations"
                echo "  sudo $0 --verbose         # Verbose output"
                echo "  sudo $0 --json            # JSON output"
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

    # Check for root privileges
    check_root_privileges

    # Set up cleanup trap
    trap cleanup EXIT

    # Main execution flow
    print_banner
    collect_system_info
    create_backup
    optimize_system_limits
    optimize_kernel_parameters
    optimize_cpu_governor
    optimize_memory_management
    optimize_io_scheduler
    optimize_system_services
    optimize_process_priority
    optimize_systemd
    verify_optimizations
    generate_report

    # Handle restart
    if [ "$FORCE_RESTART" = true ] && [ "$RESTART_REQUIRED" = true ] && [ "$DRY_RUN" = false ]; then
        log_info "Force restart requested. Restarting system in 10 seconds..."
        log_info "Press Ctrl+C to cancel"
        sleep 10
        reboot
    fi

    # Exit with appropriate status code
    if [ ${#OPTIMIZATIONS_APPLIED[@]} -gt 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"