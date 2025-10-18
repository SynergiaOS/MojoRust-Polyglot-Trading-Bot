#!/bin/bash

# =============================================================================
# 🔍 CPU Usage Diagnostic Tool for MojoRust Trading Bot
# =============================================================================
# This script provides comprehensive CPU usage analysis and identifies performance bottlenecks

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
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
JSON_OUTPUT=false
WATCH_MODE=false
REFRESH_INTERVAL=5
CPU_THRESHOLD_WARNING=70
CPU_THRESHOLD_CRITICAL=90

# Global variables
VS_CODE_TOTAL_CPU=0
SYSTEM_CPU=0
TOP_PROCESSES=""
DOCKER_CPU_INFO=""

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

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                              ║"
        echo "║    🔍 CPU Usage Diagnostic Tool - MojoRust Trading Bot          ║"
        echo "║                                                              ║"
        echo "║    Project: $PROJECT_ROOT"
        echo "║    Timestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')"
        echo "║                                                              ║"
        echo "╚═════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Show system overview
show_system_overview() {
    log_header "System Overview"

    # Get system information
    local uptime_info=$(uptime)
    local cpu_count=$(nproc)
    local load_avg=$(echo "$uptime_info" | awk '{print $(NF-2)}' | tr -d ',')
    local mem_info=$(free -h)
    local disk_io=$(iostat -x 1 2 | tail -n +4)

    # Calculate load per CPU
    local load_per_cpu=$(echo "scale=2; $load_avg / $cpu_count" | bc)

    if [ "$JSON_OUTPUT" = false ]; then
        echo "Uptime: $uptime_info"
        echo "CPU Count: $cpu_count cores"
        echo "Load Average: $load_avg"
        echo "Load per CPU: $load_per_cpu"
        echo ""

        # Color code load average
        if (( $(echo "$load_per_cpu < 1.0" | bc -l) )); then
            log_success "System Load: $load_avg (OPTIMAL)"
        elif (( $(echo "$load_per_cpu < 2.0" | bc -l) )); then
            log_warning "System Load: $load_avg (MODERATE)"
        else
            log_error "System Load: $load_avg (HIGH)"
        fi

        echo "Memory Usage:"
        echo "$mem_info"
        echo ""

        echo "Disk I/O (last 1 second):"
        echo "$disk_io"
        echo ""
    fi

    # Store for JSON output
    SYSTEM_CPU=$load_avg
}

# Show top CPU processes
show_top_cpu_processes() {
    log_header "Top CPU Processes"

    # Get top 20 processes
    TOP_PROCESSES=$(ps aux --sort=-%cpu | head -21)

    if [ "$JSON_OUTPUT" = false ]; then
        printf "%-12s %8s %8s %10s %s\n" "USER" "PID" "%CPU" "%MEM" "COMMAND"
        echo "----------------------------------------------------------------------------"

        echo "$TOP_PROCESSES" | while read -r line; do
            local user=$(echo "$line" | awk '{print $1}')
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu=$(echo "$line" | awk '{print $3}')
            local mem=$(echo "$line" | awk '{print $4}')
            local cmd=$(echo "$line" | cut -c 42-)

            # Color code based on CPU usage
            if (( $(echo "$cpu > 50" | bc -l) 2>/dev/null)); then
                printf "${RED}%-12s %8s %8s %10s %s${NC}\n" "$user" "$pid" "$cpu" "$mem" "$cmd"
            elif (( $(echo "$cpu > 25" | bc -l) 2>/dev/null)); then
                printf "${YELLOW}%-12s %8s %8s %10s %s${NC}\n" "$user" "$pid" "$cpu" "$mem" "$cmd"
            else
                printf "%-12s %8s %8s %10s %s\n" "$user" "$pid" "$cpu" "$mem" "$cmd"
            fi
        done
        echo ""

        # Group processes by name
        log_info "Process Groups by Total CPU:"
        ps aux --sort=-%cpu | awk 'NR>1 {print $11}' | sort | uniq -c | sort -nr | head -10 | while read count name; do
            local total_cpu=$(ps aux --sort=-%cpu | awk -v name="$name" '$11==name {sum+=$3} END {print sum}')
            printf "%-8s %s %.1f%%\n" "$count" "$name" "$total_cpu"
        done
        echo ""
    fi
}

# Analyze VS Code processes
analyze_vscode_processes() {
    log_header "VS Code Process Analysis"

    # Find all VS Code related processes
    local vscode_processes=$(ps aux | grep -E '/usr/share/code|/snap/code|electron' | grep -v grep || true)

    if [ -z "$vscode_processes" ]; then
        log_info "No VS Code processes found"
        return
    fi

    # Calculate total VS Code CPU usage
    VS_CODE_TOTAL_CPU=$(echo "$vscode_processes" | awk '{sum+=$3} END {print sum}')

    if [ "$JSON_OUTPUT" = false ]; then
        echo "VS Code Total CPU Usage: $VS_CODE_TOTAL_CPU%"
        echo ""

        # Categorize VS Code processes
        log_info "VS Code Process Breakdown:"
        echo "$vscode_processes" | while read -r line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu=$(echo "$line" | awk '{print $3}')
            local mem=$(echo "$line" | awk '{print $4}')
            local cmd=$(echo "$line" | cut -c 42-)
            local user=$(echo "$line" | awk '{print $1}')

            # Identify process type
            local process_type="Unknown"
            if echo "$cmd" | grep -q "\-\-type=renderer"; then
                process_type="Renderer"
            elif echo "$cmd" | grep -q "\-\-extensionHostPath"; then
                process_type="Extension Host"
            elif echo "$cmd" | grep -q "\-\-type=utilityNetworkService"; then
                process_type="NodeService"
            elif echo "$cmd" | grep -q "\-\-type=zygote"; then
                process_type="Zygote"
            elif echo "$cmd" | grep -q "\-\-disable-gpu"; then
                process_type="Main (CPU mode)"
            else
                process_type="Main"
            fi

            printf "%-12s %8s %8s %8s %s\n" "$process_type" "$pid" "$cpu" "$mem" "$user"
        done
        echo ""

        # Check for open VS Code windows (if wmctrl is available)
        if command -v wmctrl >/dev/null 2>&1; then
            local vscode_windows=$(wmctrl -l 2>/dev/null | grep 'Visual Studio Code' || true)
            if [ -n "$vscode_windows" ]; then
                log_info "Open VS Code Windows:"
                echo "$vscode_windows" | while read -r window_line; do
                    local window_id=$(echo "$window_line" | awk '{print $1}')
                    local title=$(echo "$window_line" | cut -c 9-)
                    echo "  Window ID: $window_id | Title: $title"
                done
                echo ""
            fi
        fi

        # Check for heavy extensions by examining process arguments
        log_info "Potentially Heavy Extensions (check these in VS Code):"
        echo "$vscode_processes" | grep -E "extensionHost|TypeScript Language Server|Python Language Server" | while read -r line; do
            local cmd=$(echo "$line" | cut -c 42-)
            if echo "$cmd" | grep -q "\-\-extensionId"; then
                local ext_id=$(echo "$cmd" | sed -n 's/.*--extension-id=\([^[:space:]]*\).*/\1/p')
                echo "  Extension: $ext_id (PID: $(echo "$line" | awk '{print $2}'))"
            fi
        done
        echo ""
    fi
}

# Show Docker container CPU usage
show_docker_cpu_usage() {
    log_header "Docker Container CPU Usage"

    # Check if Docker is running
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker not available"
        return
    fi

    # Get Docker container stats
    DOCKER_CPU_INFO=$(docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || true)

    if [ -z "$DOCKER_CPU_INFO" ]; then
        log_info "No Docker containers running"
        return
    fi

    if [ "$JSON_OUTPUT" = false ]; then
        echo "$DOCKER_CPU_INFO"
        echo ""

        # Identify containers using >50% CPU
        local high_cpu_containers=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}" | sed 's/%//' | awk '{if ($2 > 50) print $1}' | head -5)
        if [ -n "$high_cpu_containers" ]; then
            log_warning "Containers with >50% CPU:"
            echo "$high_cpu_containers" | while read -r container; do
                echo "  - $container"
            done
            echo ""
        fi
    fi
}

# Check system resource limits
check_resource_limits() {
    log_header "System Resource Limits Check"

    # Check sysctl settings
    local current_settings=$(sysctl -a | grep -E 'file-max|pid_max|swappiness|rmem_max|wmem_max|tcp_congestion_control' || true)

    if [ "$JSON_OUTPUT" = false ]; then
        echo "Current System Limits:"
        echo "$current_settings"
        echo ""

        # Compare with recommended settings from vps_setup.sh
        log_info "Recommended Settings (from scripts/vps_setup.sh):"
        echo "  fs.file-max = 2097152"
        echo "  kernel.pid_max = 4194303"
        echo "  vm.swappiness = 10"
        echo "  net.core.rmem_max = 134217728"
        echo "  net.core.wmem_max = 134217728"
        echo "  net.ipv4.tcp_congestion_control = bbr"
        echo ""

        # Check for differences
        local file_max=$(sysctl -n fs.file-max | awk '{print $2}')
        if [ "$file_max" -lt 2097152 ]; then
            log_warning "File descriptor limit below recommended (current: $file_max, recommended: 2097152)"
        fi

        local pid_max=$(sysctl -n kernel.pid_max | awk '{print $2}')
        if [ "$pid_max" -lt 4194303 ]; then
            log_warning "Process limit below recommended (current: $pid_max, recommended: 4194303)"
        fi

        local swappiness=$(sysctl -n vm.swappiness | awk '{print $2}')
        if [ "$swappiness" -ne 10 ]; then
            log_warning "Swappiness not optimized (current: $swappiness, recommended: 10)"
        fi

        # Check if optimized config exists
        if [ -f "/etc/sysctl.d/99-trading-bot.conf" ]; then
            log_success "System optimization configuration found: /etc/sysctl.d/99-trading-bot.conf"
        else
            log_warning "System optimization configuration not found. Run: sudo ./scripts/apply_system_optimizations.sh"
        fi
        echo ""
    fi
}

# Check CPU frequency and governor
check_cpu_governor() {
    log_header "CPU Frequency and Governor Analysis"

    # Get CPU frequency
    local cpu_freq=$(cat /proc/cpuinfo | grep 'cpu MHz' | head -1 | awk '{print $4}')

    # Get CPU governor
    local cpu_governor=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | head -1)

    if [ "$JSON_OUTPUT" = false ]; then
        echo "CPU Frequency: $cpu_freq MHz"
        echo "CPU Governor: $cpu_governor"
        echo ""

        # Recommend performance governor for trading bot
        if [ "$cpu_governor" != "performance" ]; then
            log_warning "CPU governor is '$cpu_governor', recommend 'performance' for trading bot"
            echo "To set performance governor:"
            echo "  echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
            echo ""
        else
            log_success "CPU governor set to '$cpu_governor' (optimal for trading)"
        fi

        # Check for CPU throttling
        local throttling=$(dmesg | grep -i 'cpu.*throtl' | tail -5 || true)
        if [ -n "$throttling" ]; then
            log_warning "CPU throttling detected in system logs:"
            echo "$throttling"
            echo ""
        fi
    fi
}

# Generate recommendations
generate_recommendations() {
    log_header "Performance Recommendations"

    local recommendations=()

    # Analyze VS Code CPU usage
    if (( $(echo "$VS_CODE_TOTAL_CPU > 100" | bc -l) 2>/dev/null)); then
        recommendations+=("CRITICAL: VS Code consuming $VS_CODE_TOTAL_CPU% CPU")
        recommendations+=("Close unnecessary VS Code windows and disable heavy extensions")
        recommendations+=("Run: ./scripts/optimize_vscode_cpu.sh")
    fi

    # Analyze system load
    local cpu_count=$(nproc)
    if (( $(echo "$SYSTEM_CPU > $cpu_count" | bc -l) 2>/dev/null)); then
        recommendations+=("HIGH: System load ($SYSTEM_CPU) exceeds CPU count ($cpu_count)")
        recommendations+=("Identify and stop CPU-intensive processes")
        recommendations+=("Consider upgrading hardware or reducing concurrent processes")
    fi

    # Analyze Docker containers
    if [ -n "$DOCKER_CPU_INFO" ]; then
        local high_cpu_count=$(echo "$DOCKER_CPU_INFO" | grep -E '[0-9]+\.[0-9]+%' | wc -l)
        if [ "$high_cpu_count" -gt 0 ]; then
            recommendations+=("WARNING: Docker containers consuming high CPU")
            recommendations+=("Apply resource limits in docker-compose.yml")
            recommendations+=("Check: docker stats")
        fi
    fi

    # Check system optimizations
    if [ ! -f "/etc/sysctl.d/99-trading-bot.conf" ]; then
        recommendations+=("OPTIMIZATION: System optimizations not applied")
        recommendations+=("Run: sudo ./scripts/apply_system_optimizations.sh")
    fi

    # CPU governor
    local cpu_governor=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor 2>/dev/null | sort -u | head -1)
    if [ "$cpu_governor" != "performance" ]; then
        recommendations+=("OPTIMIZATION: CPU governor not set to performance")
        recommendations+=("Run: echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor")
    fi

    if [ "$JSON_OUTPUT" = false ]; then
        if [ ${#recommendations[@]} -eq 0 ]; then
            log_success "System CPU usage appears normal"
            echo "All performance metrics are within acceptable ranges."
        else
            echo "Recommendations:"
            printf "%s\n" "${recommendations[@]}"
            echo ""
        fi
    fi
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
            --watch)
                WATCH_MODE=true
                shift
                ;;
            --interval=*)
                REFRESH_INTERVAL="${1#*=*}"
                shift
                ;;
            --threshold-warning=*)
                CPU_THRESHOLD_WARNING="${1#*=*}"
                shift
                ;;
            --threshold-critical=*)
                CPU_THRESHOLD_CRITICAL="${1#*=*}"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --json                     Output results in JSON format"
                echo "  --watch                    Continuous monitoring mode (refreshes every ${REFRESH_INTERVAL}s)"
                "  --interval=N             Set refresh interval in seconds (default: 5)"
                echo "  --threshold-warning=N      Set warning threshold percentage (default: $CPU_THRESHOLD_WARNING)"
                echo "  --threshold-critical=N     Set critical threshold percentage (default: $CPU_THRESHOLD_CRITICAL)"
                echo "  --help, -h                Show this help message"
                echo ""
                echo "This script provides comprehensive CPU usage analysis for the MojoRust Trading Bot."
                echo "It identifies performance bottlenecks and provides optimization recommendations."
                echo ""
                echo "Example usage:"
                echo "  $0                          # Run diagnostic"
                echo "  $0 --json                    # Output JSON for automation"
                echo "  $0 --watch                   # Continuous monitoring"
                echo "  $0 --interval 10             # Refresh every 10 seconds"
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

    # Main execution flow
    print_banner
    show_system_overview
    show_top_cpu_processes
    analyze_vscode_processes
    show_docker_cpu_usage
    check_resource_limits
    check_cpu_governor
    generate_recommendations

    # Exit with appropriate status code
    local cpu_count=$(nproc)
    if (( $(echo "$SYSTEM_CPU > $cpu_count" | bc -l) 2>/dev/null)) || (( $(echo "$VS_CODE_TOTAL_CPU > 100" | bc -l) 2>/dev/null)); then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"