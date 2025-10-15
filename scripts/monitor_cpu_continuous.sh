#!/bin/bash

# =============================================================================
# 📊 Continuous CPU Monitoring Script for MojoRust Trading Bot
# =============================================================================
# This script provides continuous CPU monitoring with real-time alerts:
# - Real-time CPU usage monitoring
# - Threshold-based alerting
# - Historical data collection
# - Automated optimization suggestions
# - Integration with monitoring systems
# - JSON output for dashboard integration

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
DAEMON_MODE=false
LOG_FILE="/var/log/trading-bot-cpu-monitor.log"
METRICS_FILE="/var/lib/trading-bot/cpu-metrics.json"
ALERT_WEBHOOK=""
SLACK_WEBHOOK=""
DISCORD_WEBHOOK=""

# Monitoring thresholds
CPU_WARNING_THRESHOLD=70
CPU_CRITICAL_THRESHOLD=90
SYSTEM_LOAD_WARNING=2.0
SYSTEM_LOAD_CRITICAL=4.0
VS_CODE_WARNING_THRESHOLD=50
VS_CODE_CRITICAL_THRESHOLD=100

# Monitoring intervals
MONITOR_INTERVAL=30
ALERT_COOLDOWN=300
METRICS_RETENTION_DAYS=7

# Global variables
MONITOR_PID=""
START_TIME=$(date +%s)
LAST_ALERT_TIME=0
ALERT_COUNT=0
METRICS_DATA=()

# Logging functions
log_info() {
    local message="[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}$message${NC}"
    fi
    if [ "$DAEMON_MODE" = true ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

log_success() {
    local message="[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}$message${NC}"
    fi
    if [ "$DAEMON_MODE" = true ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

log_warning() {
    local message="[WARNING] $(date '+%Y-%m-%d %H:%M:%S') $1"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}$message${NC}"
    fi
    if [ "$DAEMON_MODE" = true ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

log_error() {
    local message="[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1"
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}$message${NC}"
    fi
    if [ "$DAEMON_MODE" = true ]; then
        echo "$message" >> "$LOG_FILE"
    fi
}

log_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}$1${NC}"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        local message="[VERBOSE] $(date '+%Y-%m-%d %H:%M:%S') $1"
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "${CYAN}$message${NC}"
        fi
        if [ "$DAEMON_MODE" = true ]; then
            echo "$message" >> "$LOG_FILE"
        fi
    fi
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                              ║"
        echo "║   📊 Continuous CPU Monitoring - MojoRust Trading Bot        ║"
        echo "║                                                              ║"
        echo "║   Real-time CPU monitoring with alerting and analytics       ║"
        echo "║                                                              ║"
        echo "║   Project: $PROJECT_ROOT"
        echo "║   Started: $(date '+%Y-%m-%d %H:%M:%S UTC')"
        echo "║   PID: $$"
        echo "║                                                              ║"
        echo "╚═════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking monitoring prerequisites..."

    # Check required commands
    local required_commands=("bc" "jq" "ps" "awk" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done

    # Create log directory
    if [ "$DAEMON_MODE" = true ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        mkdir -p "$(dirname "$METRICS_FILE")"
    fi

    # Check if we can write to log file
    if [ "$DAEMON_MODE" = true ] && [ ! -w "$(dirname "$LOG_FILE")" ]; then
        log_error "Cannot write to log directory: $(dirname "$LOG_FILE")"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Collect system metrics
collect_system_metrics() {
    local timestamp=$(date -Iseconds)
    local uptime_seconds=$(cat /proc/uptime | awk '{print $1}')
    local load_avg=$(uptime | awk '{print $(NF-2)}' | tr -d ',')
    local cpu_count=$(nproc)
    local load_per_cpu=$(echo "scale=2; $load_avg / $cpu_count" | bc)

    # Memory information
    local mem_info=$(free -m | grep '^Mem:')
    local total_mem=$(echo "$mem_info" | awk '{print $2}')
    local used_mem=$(echo "$mem_info" | awk '{print $3}')
    local mem_usage_percent=$(echo "scale=1; $used_mem * 100 / $total_mem" | bc)

    # VS Code processes
    local vscode_processes=$(ps aux | grep -E '/usr/share/code|/snap/code|electron' | grep -v grep || true)
    local vscode_cpu_usage=0
    local vscode_process_count=0

    if [ -n "$vscode_processes" ]; then
        vscode_cpu_usage=$(echo "$vscode_processes" | awk '{sum+=$3} END {print sum}')
        vscode_process_count=$(echo "$vscode_processes" | wc -l)
    fi

    # Top CPU processes
    local top_processes=$(ps aux --sort=-%cpu | head -11 | tail -10 | awk '{print "{\n  \"pid\": \"" $2 "\",\n  \"name\": \"" $11 "\",\n  \"cpu\": " $3 ",\n  \"mem\": " $4 "\n},"}' | sed '$s/,$//')

    # Docker container CPU usage
    local docker_cpu_info="{}"
    if command -v docker >/dev/null 2>&1; then
        local docker_stats=$(docker stats --no-stream --format "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null || true)
        if [ -n "$docker_stats" ]; then
            docker_cpu_info=$(echo "$docker_stats" | awk 'BEGIN{print "["} {split($2, cpu, "%"); gsub(/"/, "\\\\"", $1); print "{\n  \"name\": \"" $1 "\",\n  \"cpu\": " cpu[1] ",\n  \"memory\": \"" $3 "\"\n},"} END{print "]"}' | sed '$s/,$//')
        fi
    fi

    # Create metrics object
    local metrics=$(cat << EOF
{
    "timestamp": "$timestamp",
    "uptime_seconds": $uptime_seconds,
    "system": {
        "load_average": $load_avg,
        "load_per_cpu": $load_per_cpu,
        "cpu_count": $cpu_count
    },
    "memory": {
        "total_mb": $total_mem,
        "used_mb": $used_mem,
        "usage_percent": $mem_usage_percent
    },
    "vscode": {
        "cpu_usage": $vscode_cpu_usage,
        "process_count": $vscode_process_count
    },
    "top_processes": [
        $top_processes
    ],
    "docker_containers": $docker_cpu_info,
    "monitoring": {
        "pid": $$,
        "uptime_seconds": $(($(date +%s) - START_TIME)),
        "alerts_sent": $ALERT_COUNT
    }
}
EOF
)

    echo "$metrics"
}

# Check thresholds and generate alerts
check_thresholds() {
    local metrics="$1"

    # Extract values using jq
    local load_avg=$(echo "$metrics" | jq -r '.system.load_average')
    local load_per_cpu=$(echo "$metrics" | jq -r '.system.load_per_cpu')
    local vscode_cpu=$(echo "$metrics" | jq -r '.vscode.cpu_usage')
    local mem_usage=$(echo "$metrics" | jq -r '.memory.usage_percent')

    local alerts=()
    local alert_level="info"

    # System load checks
    if (( $(echo "$load_per_cpu > $SYSTEM_LOAD_CRITICAL" | bc -l) )); then
        alerts+=("CRITICAL: System load per CPU is $load_per_cpu (threshold: $SYSTEM_LOAD_CRITICAL)")
        alert_level="critical"
    elif (( $(echo "$load_per_cpu > $SYSTEM_LOAD_WARNING" | bc -l) )); then
        alerts+=("WARNING: System load per CPU is $load_per_cpu (threshold: $SYSTEM_LOAD_WARNING)")
        if [ "$alert_level" = "info" ]; then
            alert_level="warning"
        fi
    fi

    # VS Code CPU checks
    if (( $(echo "$vscode_cpu > $VS_CODE_CRITICAL_THRESHOLD" | bc -l) )); then
        alerts+=("CRITICAL: VS Code CPU usage is $vscode_cpu% (threshold: $VS_CODE_CRITICAL_THRESHOLD%)")
        alert_level="critical"
    elif (( $(echo "$vscode_cpu > $VS_CODE_WARNING_THRESHOLD" | bc -l) )); then
        alerts+=("WARNING: VS Code CPU usage is $vscode_cpu% (threshold: $VS_CODE_WARNING_THRESHOLD%)")
        if [ "$alert_level" = "info" ]; then
            alert_level="warning"
        fi
    fi

    # Memory usage checks
    if (( $(echo "$mem_usage > 90" | bc -l) )); then
        alerts+=("CRITICAL: Memory usage is $mem_usage% (threshold: 90%)")
        alert_level="critical"
    elif (( $(echo "$mem_usage > 80" | bc -l) )); then
        alerts+=("WARNING: Memory usage is $mem_usage% (threshold: 80%)")
        if [ "$alert_level" = "info" ]; then
            alert_level="warning"
        fi
    fi

    # Generate alerts if any
    if [ ${#alerts[@]} -gt 0 ]; then
        generate_alert "$alert_level" "$metrics" "${alerts[@]}"
    fi
}

# Generate and send alerts
generate_alert() {
    local level="$1"
    local metrics="$2"
    shift 2
    local alerts=("$@")

    local current_time=$(date +%s)
    local time_since_last_alert=$((current_time - LAST_ALERT_TIME))

    # Respect alert cooldown
    if [ "$time_since_last_alert" -lt "$ALERT_COOLDOWN" ]; then
        log_verbose "Alert cooldown active, skipping alert"
        return
    fi

    LAST_ALERT_TIME=$current_time
    ((ALERT_COUNT++))

    local timestamp=$(echo "$metrics" | jq -r '.timestamp')
    local load_avg=$(echo "$metrics" | jq -r '.system.load_average')
    local vscode_cpu=$(echo "$metrics" | jq -r '.vscode.cpu_usage')
    local mem_usage=$(echo "$metrics" | jq -r '.memory.usage_percent')

    # Create alert message
    local alert_message="🚨 **Trading Bot CPU Alert - $level** 🚨

Timestamp: $timestamp
System Load: $load_avg
VS Code CPU: ${vscode_cpu}%
Memory Usage: ${mem_usage}%

Alerts:"
    for alert in "${alerts[@]}"; do
        alert_message+="$alert_message\\n- $alert"
    done

    alert_message+="
\\nRecommendations:"
    if (( $(echo "$vscode_cpu > 50" | bc -l) )); then
        alert_message+="\\n- Run: ./scripts/optimize_vscode_cpu.sh --auto"
    fi
    if (( $(echo "$load_avg > 2.0" | bc -l) )); then
        alert_message+="\\n- Check system processes: htop"
        alert_message+="\\n- Apply system optimizations: sudo ./scripts/apply_system_optimizations.sh"
    fi
    alert_message+="\\n- View diagnostics: ./scripts/diagnose_cpu_usage.sh"

    # Log alert
    if [ "$level" = "critical" ]; then
        log_error "$alert_message"
    elif [ "$level" = "warning" ]; then
        log_warning "$alert_message"
    else
        log_info "$alert_message"
    fi

    # Send webhooks if configured
    if [ -n "$SLACK_WEBHOOK" ]; then
        send_slack_alert "$level" "$alert_message"
    fi

    if [ -n "$DISCORD_WEBHOOK" ]; then
        send_discord_alert "$level" "$alert_message"
    fi

    if [ -n "$ALERT_WEBHOOK" ]; then
        send_generic_webhook "$level" "$alert_message"
    fi
}

# Send Slack alert
send_slack_alert() {
    local level="$1"
    local message="$2"

    local color="good"
    if [ "$level" = "critical" ]; then
        color="danger"
    elif [ "$level" = "warning" ]; then
        color="warning"
    fi

    local slack_payload=$(cat << EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "Trading Bot CPU Alert - $level",
            "text": "$message",
            "footer": "MojoRust Trading Bot",
            "ts": $(date +%s)
        }
    ]
}
EOF
)

    curl -X POST -H 'Content-type: application/json' \
        --data "$slack_payload" \
        "$SLACK_WEBHOOK" \
        >/dev/null 2>&1 || log_verbose "Failed to send Slack alert"
}

# Send Discord alert
send_discord_alert() {
    local level="$1"
    local message="$2"

    local discord_payload=$(cat << EOF
{
    "embeds": [
        {
            "title": "Trading Bot CPU Alert - $level",
            "description": "$message",
            "color": $([ "$level" = "critical" ] && echo "16711680" || ([ "$level" = "warning" ] && echo "16776960" || echo "65280")),
            "footer": {
                "text": "MojoRust Trading Bot"
            },
            "timestamp": "$(date -Iseconds)"
        }
    ]
}
EOF
)

    curl -X POST -H 'Content-type: application/json' \
        --data "$discord_payload" \
        "$DISCORD_WEBHOOK" \
        >/dev/null 2>&1 || log_verbose "Failed to send Discord alert"
}

# Send generic webhook
send_generic_webhook() {
    local level="$1"
    local message="$2"

    local webhook_payload=$(cat << EOF
{
    "level": "$level",
    "service": "trading-bot-cpu-monitor",
    "message": "$message",
    "timestamp": "$(date -Iseconds)",
    "metadata": {
        "pid": $$,
        "alerts_sent": $ALERT_COUNT
    }
}
EOF
)

    curl -X POST -H 'Content-type: application/json' \
        --data "$webhook_payload" \
        "$ALERT_WEBHOOK" \
        >/dev/null 2>&1 || log_verbose "Failed to send generic webhook"
}

# Store metrics
store_metrics() {
    local metrics="$1"

    if [ "$DAEMON_MODE" = false ]; then
        return
    fi

    # Append to metrics file
    echo "$metrics" >> "$METRICS_FILE"

    # Keep only recent metrics (retention policy)
    local cutoff_time=$(date -d "$METRICS_RETENTION_DAYS days ago" -Iseconds 2>/dev/null || true)
    if [ -n "$cutoff_time" ] && [ -f "$METRICS_FILE" ]; then
        jq --arg cutoff "$cutoff_time" 'map(select(.timestamp >= $cutoff))' "$METRICS_FILE" > "$METRICS_FILE.tmp"
        mv "$METRICS_FILE.tmp" "$METRICS_FILE"
    fi

    log_verbose "Metrics stored"
}

# Display real-time dashboard
display_dashboard() {
    local metrics="$1"

    if [ "$JSON_OUTPUT" = true ]; then
        echo "$metrics"
        return
    fi

    # Clear screen for dashboard mode
    if [ "$DAEMON_MODE" = false ]; then
        clear
        print_banner
    fi

    # Extract values
    local timestamp=$(echo "$metrics" | jq -r '.timestamp')
    local load_avg=$(echo "$metrics" | jq -r '.system.load_average')
    local load_per_cpu=$(echo "$metrics" | jq -r '.system.load_per_cpu')
    local cpu_count=$(echo "$metrics" | jq -r '.system.cpu_count')
    local mem_usage=$(echo "$metrics" | jq -r '.memory.usage_percent')
    local vscode_cpu=$(echo "$metrics" | jq -r '.vscode.cpu_usage')
    local vscode_count=$(echo "$metrics" | jq -r '.vscode.process_count')
    local uptime_hours=$(echo "$metrics" | jq -r '.monitoring.uptime_seconds / 3600')

    # System Overview
    log_header "System Overview"
    printf "%-20s %s\n" "Timestamp:" "$timestamp"
    printf "%-20s %s\n" "System Load:" "$load_avg"
    printf "%-20s %s\n" "Load per CPU:" "$load_per_cpu"
    printf "%-20s %s\n" "CPU Count:" "$cpu_count"
    printf "%-20s %s\n" "Memory Usage:" "${mem_usage}%"
    printf "%-20s %s\n" "VS Code CPU:" "${vscode_cpu}%"
    printf "%-20s %s\n" "VS Code Processes:" "$vscode_count"
    printf "%-20s %.1f hours\n" "Monitor Uptime:" "$uptime_hours"
    printf "%-20s %s\n" "Alerts Sent:" "$ALERT_COUNT"
    echo ""

    # Status indicators
    log_header "Status Indicators"

    # System load status
    if (( $(echo "$load_per_cpu < 1.0" | bc -l) )); then
        printf "%-20s %s\n" "System Load:" "${GREEN}✓ Optimal${NC}"
    elif (( $(echo "$load_per_cpu < 2.0" | bc -l) )); then
        printf "%-20s %s\n" "System Load:" "${YELLOW}⚠ Moderate${NC}"
    else
        printf "%-20s %s\n" "System Load:" "${RED}✗ High${NC}"
    fi

    # VS Code status
    if (( $(echo "$vscode_cpu < 25" | bc -l) )); then
        printf "%-20s %s\n" "VS Code:" "${GREEN}✓ Optimal${NC}"
    elif (( $(echo "$vscode_cpu < 50" | bc -l) )); then
        printf "%-20s %s\n" "VS Code:" "${YELLOW}⚠ Moderate${NC}"
    else
        printf "%-20s %s\n" "VS Code:" "${RED}✗ High${NC}"
    fi

    # Memory status
    if (( $(echo "$mem_usage < 70" | bc -l) )); then
        printf "%-20s %s\n" "Memory:" "${GREEN}✓ Optimal${NC}"
    elif (( $(echo "$mem_usage < 85" | bc -l) )); then
        printf "%-20s %s\n" "Memory:" "${YELLOW}⚠ Moderate${NC}"
    else
        printf "%-20s %s\n" "Memory:" "${RED}✗ High${NC}"
    fi

    echo ""

    # Top processes
    log_header "Top CPU Processes"
    printf "%-8s %-20s %8s %8s\n" "PID" "Process" "%CPU" "%MEM"
    echo "----------------------------------------"
    echo "$metrics" | jq -r '.top_processes[] | "\(.pid) \(.name) \(.cpu) \(.mem)"' | head -5 | while read -r line; do
        local pid=$(echo "$line" | awk '{print $1}')
        local name=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')

        # Color code based on CPU usage
        if (( $(echo "$cpu > 50" | bc -l) 2>/dev/null)); then
            printf "%-8s %-20s ${RED}%8s${NC} %8s\n" "$pid" "${name:0:19}" "$cpu" "$mem"
        elif (( $(echo "$cpu > 25" | bc -l) 2>/dev/null)); then
            printf "%-8s %-20s ${YELLOW}%8s${NC} %8s\n" "$pid" "${name:0:19}" "$cpu" "$mem"
        else
            printf "%-8s %-20s %8s %8s\n" "$pid" "${name:0:19}" "$cpu" "$mem"
        fi
    done

    echo ""

    # Quick actions
    log_header "Quick Actions"
    echo "1. Diagnose CPU usage: ./scripts/diagnose_cpu_usage.sh"
    echo "2. Optimize VS Code: ./scripts/optimize_vscode_cpu.sh --auto"
    echo "3. System optimization: sudo ./scripts/apply_system_optimizations.sh"
    echo "4. View historical metrics: jq . $METRICS_FILE | tail -20"
    echo ""

    if [ "$DAEMON_MODE" = false ]; then
        echo "Press Ctrl+C to stop monitoring"
        echo "Next update in $MONITOR_INTERVAL seconds..."
    fi
}

# Main monitoring loop
monitor_loop() {
    log_info "Starting continuous CPU monitoring (interval: ${MONITOR_INTERVAL}s)"

    while true; do
        # Collect metrics
        local metrics=$(collect_system_metrics)

        # Store metrics
        store_metrics "$metrics"

        # Check thresholds and generate alerts
        check_thresholds "$metrics"

        # Display dashboard
        display_dashboard "$metrics"

        # Sleep until next iteration
        if [ "$DAEMON_MODE" = false ]; then
            sleep "$MONITOR_INTERVAL"
        else
            sleep "$MONITOR_INTERVAL"
        fi
    done
}

# Signal handlers
cleanup() {
    log_info "Shutting down CPU monitor..."
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi
    exit 0
}

# Parse configuration file
load_config() {
    local config_file="$PROJECT_ROOT/.cpu-monitor.conf"

    if [ -f "$config_file" ]; then
        log_verbose "Loading configuration from $config_file"
        # Source the configuration file
        # shellcheck source=/dev/null
        source "$config_file"
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
            --verbose)
                VERBOSE=true
                shift
                ;;
            --daemon)
                DAEMON_MODE=true
                shift
                ;;
            --interval=*)
                MONITOR_INTERVAL="${1#*=*}"
                shift
                ;;
            --log-file=*)
                LOG_FILE="${1#*=*}"
                shift
                ;;
            --metrics-file=*)
                METRICS_FILE="${1#*=*}"
                shift
                ;;
            --slack-webhook=*)
                SLACK_WEBHOOK="${1#*=*}"
                shift
                ;;
            --discord-webhook=*)
                DISCORD_WEBHOOK="${1#*=*}"
                shift
                ;;
            --webhook=*)
                ALERT_WEBHOOK="${1#*=*}"
                shift
                ;;
            --cpu-warning=*)
                CPU_WARNING_THRESHOLD="${1#*=*}"
                shift
                ;;
            --cpu-critical=*)
                CPU_CRITICAL_THRESHOLD="${1#*=*}"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --json                     Output metrics in JSON format"
                echo "  --verbose                  Enable verbose logging"
                echo "  --daemon                   Run in daemon mode with logging"
                echo "  --interval=N               Set monitoring interval in seconds [default: 30]"
                echo "  --log-file=PATH           Set log file path [default: /var/log/trading-bot-cpu-monitor.log]"
                echo "  --metrics-file=PATH       Set metrics file path [default: /var/lib/trading-bot/cpu-metrics.json]"
                echo "  --slack-webhook=URL       Slack webhook URL for alerts"
                echo "  --discord-webhook=URL     Discord webhook URL for alerts"
                echo "  --webhook=URL             Generic webhook URL for alerts"
                echo "  --cpu-warning=N           Set CPU warning threshold [default: 70]"
                echo "  --cpu-critical=N          Set CPU critical threshold [default: 90]"
                echo "  --help, -h                Show this help message"
                echo ""
                echo "This script provides continuous CPU monitoring for the MojoRust Trading Bot."
                echo "It includes real-time monitoring, threshold-based alerting, and historical data collection."
                echo ""
                echo "Example usage:"
                echo "  $0                          # Interactive monitoring dashboard"
                echo "  $0 --daemon                 # Run as daemon with logging"
                echo "  $0 --json                   # JSON metrics output"
                echo "  $0 --interval 10             # 10-second monitoring interval"
                echo "  $0 --slack-webhook=URL      # Send alerts to Slack"
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

    # Load configuration
    load_config

    # Set up signal handlers
    trap cleanup SIGINT SIGTERM

    # Main execution flow
    print_banner
    check_prerequisites
    monitor_loop
}

# Run main function
main "$@"