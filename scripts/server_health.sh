#!/bin/bash

# =============================================================================
# 🔍 MojoRust Trading Bot - Server Health Monitoring Script
# Server: 38.242.239.150
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_SERVER_IP="38.242.239.150"
DEFAULT_SSH_USER="root"
DEFAULT_DEPLOY_DIR="~/mojo-trading-bot"

# Configuration variables
SERVER_IP="${SERVER_IP:-$DEFAULT_SERVER_IP}"
SSH_USER="${SSH_USER:-$DEFAULT_SSH_USER}"
DEPLOY_DIR="${DEPLOY_DIR:-$DEFAULT_DEPLOY_DIR}"

# Parse command line arguments
REMOTE_MODE=false
JSON_OUTPUT=false
WATCH_MODE=false
ALERTS_ONLY=false

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local no_newline="${3:-false}"

    local color_code=""
    case $status in
        "SUCCESS") color_code="${GREEN}✅ ${BOLD}" ;;
        "ERROR") color_code="${RED}❌ ${BOLD}" ;;
        "WARNING") color_code="${YELLOW}⚠️  ${BOLD}" ;;
        "INFO") color_code="${BLUE}ℹ️  ${BOLD}" ;;
        "PROGRESS") color_code="${PURPLE}🔄 ${BOLD}" ;;
        "HEADER") color_code="${CYAN}📋 ${BOLD}" ;;
        "CRITICAL") color_code="${RED}🚨 ${BOLD}" ;;
        *) color_code="${NC}" ;;
    esac

    if [ "$JSON_OUTPUT" = true ]; then
        return 0  # Skip colored output in JSON mode
    fi

    if [ "$no_newline" = true ]; then
        echo -ne "${color_code}${message}${NC}"
    else
        echo -e "${color_code}${message}${NC}"
    fi
}

# Function to show help
show_help() {
    cat << EOF
🔍 MojoRust Trading Bot - Server Health Monitor

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --server-ip <IP>       Server IP address (default: $DEFAULT_SERVER_IP)
    --ssh-user <USER>      SSH user (default: $DEFAULT_SSH_USER)
    --deploy-dir <PATH>    Deployment directory (default: $DEFAULT_DEPLOY_DIR)
    --remote               Run via SSH from local machine
    --json                 Output in JSON format
    --watch                Continuous monitoring mode
    --alerts-only          Show only warnings and errors
    --help                 Show this help message

EXAMPLES:
    $0                                    # Run locally on server
    $0 --remote                           # Run from local machine via SSH
    $0 --json                             # Output in JSON format
    $0 --watch                            # Continuous monitoring
    $0 --alerts-only                      # Show only issues

ENVIRONMENT VARIABLES:
    SERVER_IP       - Override server IP
    SSH_USER        - Override SSH user
    DEPLOY_DIR      - Override deployment directory

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server-ip)
            SERVER_IP="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --deploy-dir)
            DEPLOY_DIR="$2"
            shift 2
            ;;
        --remote)
            REMOTE_MODE=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --alerts-only)
            ALERTS_ONLY=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_status "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# JSON output structure
declare -A json_output

# Function to execute command locally or via SSH
execute() {
    local cmd="$1"
    local use_ssh="${2:-true}"

    if [ "$JSON_OUTPUT" = true ]; then
        # In JSON mode, capture output
        if [ "$use_ssh" = true ] && [ "$REMOTE_MODE" = true ]; then
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "$cmd" 2>/dev/null || echo "ERROR"
        else
            eval "$cmd" 2>/dev/null || echo "ERROR"
        fi
    else
        # Normal mode with error handling
        if [ "$use_ssh" = true ] && [ "$REMOTE_MODE" = true ]; then
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "$cmd" 2>/dev/null || echo "ERROR"
        else
            eval "$cmd" 2>/dev/null || echo "ERROR"
        fi
    fi
}

# Function to check connection
check_connection() {
    print_status "HEADER" "Connection Check"

    local connection_result
    if [ "$REMOTE_MODE" = true ]; then
        connection_result=$(execute "echo 'CONNECTED'" true)
    else
        connection_result="CONNECTED"
    fi

    if [ "$connection_result" = "CONNECTED" ]; then
        print_status "SUCCESS" "SSH connection to $SSH_USER@$SERVER_IP established"
        json_output["connection"]="healthy"
        return 0
    else
        print_status "ERROR" "Cannot connect to server $SSH_USER@$SERVER_IP"
        json_output["connection"]="failed"
        return 1
    fi
}

# Function to check system resources
check_system_resources() {
    print_status "HEADER" "System Resources"

    # CPU usage
    local cpu_usage=$(execute "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" true)
    if [ "$cpu_usage" != "ERROR" ] && [ -n "$cpu_usage" ]; then
        if (( $(echo "$cpu_usage > 80" | bc -l) )); then
            print_status "WARNING" "High CPU usage: ${cpu_usage}%"
            json_output["cpu_usage"]="${cpu_usage}%"
        else
            print_status "SUCCESS" "CPU usage: ${cpu_usage}%"
            json_output["cpu_usage"]="${cpu_usage}%"
        fi
    else
        print_status "ERROR" "Could not get CPU usage"
        json_output["cpu_usage"]="unknown"
    fi

    # Memory usage
    local memory_info=$(execute "free -m | awk 'NR==2{printf \"%.1f\", \$3*100/\$2}'" true)
    if [ "$memory_info" != "ERROR" ] && [ -n "$memory_info" ]; then
        if (( $(echo "$memory_info > 85" | bc -l) )); then
            print_status "WARNING" "High memory usage: ${memory_info}%"
            json_output["memory_usage"]="${memory_info}%"
        else
            print_status "SUCCESS" "Memory usage: ${memory_info}%"
            json_output["memory_usage"]="${memory_info}%"
        fi
    else
        print_status "ERROR" "Could not get memory usage"
        json_output["memory_usage"]="unknown"
    fi

    # Disk space
    local disk_usage=$(execute "df -h / | awk 'NR==2 {print \$5}' | cut -d'%' -f1" true)
    if [ "$disk_usage" != "ERROR" ] && [ -n "$disk_usage" ]; then
        if [ "$disk_usage" -gt 90 ]; then
            print_status "CRITICAL" "Very high disk usage: ${disk_usage}%"
            json_output["disk_usage"]="${disk_usage}%"
        elif [ "$disk_usage" -gt 80 ]; then
            print_status "WARNING" "High disk usage: ${disk_usage}%"
            json_output["disk_usage"]="${disk_usage}%"
        else
            print_status "SUCCESS" "Disk usage: ${disk_usage}%"
            json_output["disk_usage"]="${disk_usage}%"
        fi
    else
        print_status "ERROR" "Could not get disk usage"
        json_output["disk_usage"]="unknown"
    fi

    # Load average
    local load_avg=$(execute "uptime | awk -F'load average:' '{print \$2}' | cut -d',' -f1 | xargs" true)
    if [ "$load_avg" != "ERROR" ] && [ -n "$load_avg" ]; then
        print_status "INFO" "Load average: $load_avg"
        json_output["load_average"]="$load_avg"
    else
        json_output["load_average"]="unknown"
    fi

    # Network reachability tests
    print_status "INFO" "Testing network connectivity..."

    # Test basic internet connectivity
    local internet_test=$(execute "ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo 'online' || echo 'offline'" true)
    if [ "$internet_test" = "online" ]; then
        print_status "SUCCESS" "Internet connectivity: OK"
        json_output["internet_connectivity"]="online"
    else
        print_status "WARNING" "Internet connectivity: FAILED"
        json_output["internet_connectivity"]="offline"
    fi

    # Test DNS resolution
    local dns_test=$(execute "nslookup google.com >/dev/null 2>&1 && echo 'working' || echo 'failed'" true)
    if [ "$dns_test" = "working" ]; then
        print_status "SUCCESS" "DNS resolution: OK"
        json_output["dns_resolution"]="working"
    else
        print_status "WARNING" "DNS resolution: FAILED"
        json_output["dns_resolution"]="failed"
    fi

    # Test Solana RPC connectivity (if QUICKNODE_RPC_URL is set)
    local rpc_url=$(execute "echo \$QUICKNODE_RPC_URL | head -c 50" true)
    if [ "$rpc_url" != "ERROR" ] && [ -n "$rpc_url" ] && [[ "$rpc_url" == *"quicknode"* ]]; then
        local rpc_test=$(execute "timeout 10 curl -s -X POST -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSlot\"}' \$QUICKNODE_RPC_URL | grep -q 'result' && echo 'connected' || echo 'failed'" true)
        if [ "$rpc_test" = "connected" ]; then
            print_status "SUCCESS" "QuickNode RPC: Connected"
            json_output["quicknode_rpc"]="connected"
        else
            print_status "WARNING" "QuickNode RPC: Failed"
            json_output["quicknode_rpc"]="failed"
        fi
    else
        print_status "INFO" "QuickNode RPC: Not configured"
        json_output["quicknode_rpc"]="not_configured"
    fi
}

# Function to check bot service status
check_bot_service() {
    print_status "HEADER" "Trading Bot Service"

    # Check if trading-bot process is running (check multiple patterns)
    local bot_processes=$(execute "pgrep -f 'trading-bot\\|mojo run\\|main.mojo' | wc -l" true)
    if [ "$bot_processes" != "ERROR" ]; then
        if [ "$bot_processes" -gt 0 ]; then
            print_status "SUCCESS" "Trading bot is running ($bot_processes processes)"
            json_output["bot_processes"]="$bot_processes"
            json_output["bot_status"]="running"

            # Get process details with memory usage
            local bot_details=$(execute "ps aux | grep -E 'trading-bot|mojo run|main.mojo' | grep -v grep | head -5" true)
            if [ "$bot_details" != "ERROR" ] && [ -n "$bot_details" ]; then
                print_status "INFO" "Process details:"
                echo "$bot_details" | while IFS= read -r line; do
                    echo "  $line"
                done
            fi

            # Get PIDs and uptime/memory for each process
            local bot_pids=$(execute "pgrep -f 'trading-bot\\|mojo run\\|main.mojo'" true)
            if [ "$bot_pids" != "ERROR" ] && [ -n "$bot_pids" ]; then
                echo "$bot_pids" | while IFS= read -r pid; do
                    if [ -n "$pid" ]; then
                        local bot_uptime=$(execute "ps -o etimes= -p $pid 2>/dev/null | xargs" true)
                        local bot_memory=$(execute "ps -o rss= -p $pid 2>/dev/null | xargs" true)
                        local bot_cmd=$(execute "ps -o cmd= -p $pid 2>/dev/null" true)

                        if [ "$bot_uptime" != "ERROR" ] && [ -n "$bot_uptime" ]; then
                            local uptime_hours=$((bot_uptime / 3600))
                            local uptime_minutes=$(((bot_uptime % 3600) / 60))
                            local memory_mb=0
                            if [ "$bot_memory" != "ERROR" ] && [ -n "$bot_memory" ]; then
                                memory_mb=$((bot_memory / 1024))
                            fi
                            print_status "INFO" "PID $pid: ${uptime_hours}h ${uptime_minutes}m, ${memory_mb}MB RAM"
                            json_output["pid_${pid}_uptime"]="${uptime_hours}h ${uptime_minutes}m"
                            json_output["pid_${pid}_memory"]="${memory_mb}MB"
                        fi
                    fi
                done
            fi
        else
            print_status "ERROR" "Trading bot process not found"
            json_output["bot_processes"]="0"
            json_output["bot_status"]="stopped"
        fi
    else
        print_status "ERROR" "Could not check bot processes"
        json_output["bot_status"]="unknown"
    fi

    # Check if systemd service exists and show status
    local service_status=$(execute "systemctl is-active trading-bot 2>/dev/null || echo 'no-service'" true)
    local service_enabled=$(execute "systemctl is-enabled trading-bot 2>/dev/null || echo 'not-found'" true)

    if [ "$service_status" != "no-service" ] && [ "$service_status" != "ERROR" ]; then
        print_status "INFO" "Systemd service 'trading-bot' status: $service_status"
        json_output["systemd_service"]="$service_status"

        # Show detailed service status if available
        local detailed_status=$(execute "systemctl status trading-bot --no-pager 2>/dev/null | head -10" true)
        if [ "$detailed_status" != "ERROR" ] && [ -n "$detailed_status" ]; then
            print_status "INFO" "Service details:"
            echo "$detailed_status" | sed 's/^/  /'
        fi

        if [ "$service_enabled" != "not-found" ]; then
            print_status "INFO" "Service enabled: $service_enabled"
            json_output["systemd_enabled"]="$service_enabled"
        fi
    else
        print_status "INFO" "No systemd service 'trading-bot' found"
        json_output["systemd_service"]="not-found"
    fi
}

# Function to check API endpoints
check_api_endpoints() {
    print_status "HEADER" "API Endpoints"

    local api_base="http://localhost:8080"

    # Health check
    local health_status=$(execute "curl -s --max-time 5 $api_base/api/health || echo 'failed'" true)
    if [[ "$health_status" == *"healthy"* ]] || [[ "$health_status" == *"ok"* ]]; then
        print_status "SUCCESS" "API health endpoint responding"
        json_output["api_health"]="healthy"
    else
        print_status "WARNING" "API health endpoint not responding"
        json_output["api_health"]="failed"
    fi

    # Status endpoint
    local status_status=$(execute "curl -s --max-time 5 $api_base/api/status || echo 'failed'" true)
    if [[ "$status_status" == *"status"* ]] || [[ "$status_status" == *"running"* ]]; then
        print_status "SUCCESS" "API status endpoint responding"
        json_output["api_status"]="responding"
    else
        print_status "WARNING" "API status endpoint not responding"
        json_output["api_status"]="failed"
    fi

    # Metrics endpoint
    local metrics_status=$(execute "curl -s --max-time 5 $api_base/api/metrics || echo 'failed'" true)
    if [[ "$metrics_status" == *"metrics"* ]] || [[ "$metrics_status" == *"performance"* ]]; then
        print_status "SUCCESS" "API metrics endpoint responding"
        json_output["api_metrics"]="responding"
    else
        print_status "WARNING" "API metrics endpoint not responding"
        json_output["api_metrics"]="failed"
    fi

    # Port check
    local port_check=$(execute "netstat -ln | grep :8080 || echo 'port-not-found'" true)
    if [[ "$port_check" == *"8080"* ]]; then
        print_status "SUCCESS" "Port 8080 is listening"
        json_output["port_8080"]="listening"
    else
        print_status "WARNING" "Port 8080 not found listening"
        json_output["port_8080"]="not-listening"
    fi
}

# Function to check recent logs
check_recent_logs() {
    print_status "HEADER" "Recent Log Analysis"

    local log_dir="$DEPLOY_DIR/logs"

    # Check log directory exists
    local log_exists=$(execute "test -d $log_dir && echo 'exists' || echo 'not-found'" true)
    if [ "$log_exists" = "exists" ]; then
        # Find latest log file
        local latest_log=$(execute "ls -t $log_dir/trading-bot-*.log 2>/dev/null | head -1" true)

        if [ "$latest_log" != "ERROR" ] && [ -n "$latest_log" ]; then
            # Count errors and critical issues in last 200 lines
            local error_count=$(execute "tail -n 200 $latest_log | grep -i 'ERROR\\|CRITICAL' | wc -l" true)
            local warning_count=$(execute "tail -n 200 $latest_log | grep -i 'warning' | wc -l" true)

            if [ "$error_count" -gt 0 ]; then
                print_status "ERROR" "Found $error_count errors/critical issues in last 200 lines"
                json_output["log_errors"]="$error_count"

                # Show last 3 errors
                local last_errors=$(execute "tail -n 200 $latest_log | grep -i 'ERROR\\|CRITICAL' | tail -3" true)
                if [ "$last_errors" != "ERROR" ] && [ -n "$last_errors" ]; then
                    print_status "INFO" "Last 3 errors:"
                    echo "$last_errors" | while IFS= read -r line; do
                        echo "  $line"
                    done
                fi
            else
                print_status "SUCCESS" "No errors/critical issues in last 200 lines"
                json_output["log_errors"]="0"
            fi

            if [ "$warning_count" -gt 10 ]; then
                print_status "WARNING" "Found $warning_count warnings in last 200 lines"
                json_output["log_warnings"]="$warning_count"
            else
                print_status "SUCCESS" "Low warning count: $warning_count"
                json_output["log_warnings"]="$warning_count"
            fi

            # Summarize filter performance
            local filter_performance=$(execute "tail -n 200 $latest_log | grep -i 'Filter Performance' | tail -5" true)
            if [ "$filter_performance" != "ERROR" ] && [ -n "$filter_performance" ]; then
                print_status "INFO" "Recent filter performance:"
                echo "$filter_performance" | while IFS= read -r line; do
                    echo "  $line"
                done
                json_output["filter_performance"]="available"
            else
                print_status "INFO" "No filter performance data in recent logs"
                json_output["filter_performance"]="not-found"
            fi

            # Summarize recent trades (EXECUTED|PROFIT|LOSS)
            local recent_trades=$(execute "tail -n 200 $latest_log | grep -i 'EXECUTED\\|PROFIT\\|LOSS' | tail -5" true)
            if [ "$recent_trades" != "ERROR" ] && [ -n "$recent_trades" ]; then
                print_status "INFO" "Recent trade results:"
                echo "$recent_trades" | while IFS= read -r line; do
                    echo "  $line"
                done
                json_output["recent_activity"]="yes"

                # Count trades
                local executed_count=$(execute "tail -n 200 $latest_log | grep -i 'EXECUTED' | wc -l" true)
                local profit_count=$(execute "tail -n 200 $latest_log | grep -i 'PROFIT' | wc -l" true)
                local loss_count=$(execute "tail -n 200 $latest_log | grep -i 'LOSS' | wc -l" true)
                json_output["trades_executed"]="$executed_count"
                json_output["trades_profit"]="$profit_count"
                json_output["trades_loss"]="$loss_count"
            else
                print_status "INFO" "No recent trading activity in logs"
                json_output["recent_activity"]="no"
            fi
        else
            print_status "WARNING" "No log files found"
            json_output["log_files"]="not-found"
        fi
    else
        print_status "WARNING" "Log directory not found: $log_dir"
        json_output["log_directory"]="not-found"
    fi
}

# Function to check performance metrics
check_performance_metrics() {
    print_status "HEADER" "Performance Metrics"

    local api_base="http://localhost:8080"

    # Get performance summary
    local perf_data=$(execute "curl -s --max-time 5 $api_base/api/performance/summary || echo 'failed'" true)

    if [ "$perf_data" != "failed" ] && [ -n "$perf_data" ]; then
        # Extract key metrics (simplified parsing)
        if [[ "$perf_data" == *"trades"* ]]; then
            print_status "SUCCESS" "Performance data available"
            json_output["performance_data"]="available"

            # Try to extract some basic metrics
            local trade_count=$(echo "$perf_data" | grep -o '"total_trades":[0-9]*' | cut -d':' -f2 | head -1)
            if [ -n "$trade_count" ]; then
                print_status "INFO" "Total trades: $trade_count"
                json_output["total_trades"]="$trade_count"
            fi

            local win_rate=$(echo "$perf_data" | grep -o '"win_rate":[0-9.]*' | cut -d':' -f2 | head -1)
            if [ -n "$win_rate" ]; then
                print_status "INFO" "Win rate: ${win_rate}%"
                json_output["win_rate"]="${win_rate}%"
            fi
        else
            print_status "WARNING" "Performance data format unexpected"
            json_output["performance_data"]="invalid"
        fi
    else
        print_status "WARNING" "Could not retrieve performance metrics"
        json_output["performance_data"]="unavailable"
    fi
}

# Function to show alerts and recommendations
show_alerts() {
    print_status "HEADER" "Alerts and Recommendations"

    local alerts=0

    # Check for critical issues
    if [ "${json_output[bot_status]}" = "stopped" ]; then
        print_status "CRITICAL" "🚨 Bot is not running - requires immediate attention"
        ((alerts++))
    fi

    if [ "${json_output[disk_usage]}" != "unknown" ] && [ "${json_output[disk_usage]%?}" -gt 90 ]; then
        print_status "CRITICAL" "🚨 Disk usage critically high (${json_output[disk_usage]})"
        ((alerts++))
    fi

    if [ "${json_output[memory_usage]}" != "unknown" ] && [ "${json_output[memory_usage]%?}" -gt 90 ]; then
        print_status "ERROR" "❌ Memory usage very high (${json_output[memory_usage]})"
        ((alerts++))
    fi

    if [ "${json_output[cpu_usage]}" != "unknown" ] && [ "${json_output[cpu_usage]%?}" -gt 90 ]; then
        print_status "ERROR" "❌ CPU usage very high (${json_output[cpu_usage]})"
        ((alerts++))
    fi

    if [ "${json_output[api_health]}" = "failed" ]; then
        print_status "ERROR" "❌ API endpoints not responding"
        ((alerts++))
    fi

    if [ "${json_output[log_errors]}" != "0" ]; then
        print_status "WARNING" "⚠️  Recent errors detected in logs (${json_output[log_errors]})"
        ((alerts++))
    fi

    # Show recommendations based on alerts
    if [ $alerts -eq 0 ]; then
        print_status "SUCCESS" "✅ No critical issues detected - everything looks good!"
    else
        print_status "WARNING" "⚠️  Found $alerts issue(s) that need attention"
        echo ""
        print_status "INFO" "Recommendations:"
        echo "  • Check logs: tail -f $DEPLOY_DIR/logs/trading-bot-*.log"
        echo "  • Restart bot: cd $DEPLOY_DIR && ./scripts/restart_bot.sh"
        echo "  • Monitor resources: htop, df -h"
        echo "  • Check API: curl http://localhost:8080/api/health"
    fi

    json_output["total_alerts"]="$alerts"

    # Return non-zero exit code if critical issues found
    if [ $alerts -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Function to output JSON
output_json() {
    echo "{"
    local first=true
    for key in "${!json_output[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        echo "  \"$key\": \"${json_output[$key]}\""
    done
    echo ""
    echo "}"
}

# Function to show summary dashboard
show_summary() {
    print_status "HEADER" "📊 Health Summary Dashboard"
    echo ""

    # Connection status
    local conn_status="${json_output[connection]}"
    local conn_color="$GREEN"
    if [ "$conn_status" != "healthy" ]; then conn_color="$RED"; fi
    echo -e "${conn_color}🔌 Connection: $conn_status${NC}"

    # Bot status
    local bot_status="${json_output[bot_status]}"
    local bot_color="$GREEN"
    if [ "$bot_status" = "stopped" ]; then bot_color="$RED";
    elif [ "$bot_status" = "unknown" ]; then bot_color="$YELLOW"; fi
    echo -e "${bot_color}🤖 Bot Status: $bot_status${NC}"

    # System resources
    echo -e "${BLUE}💻 CPU: ${json_output[cpu_usage]}${NC}"
    echo -e "${BLUE}🧠 Memory: ${json_output[memory_usage]}${NC}"
    echo -e "${BLUE}💾 Disk: ${json_output[disk_usage]}${NC}"

    # API status
    local api_health="${json_output[api_health]}"
    local api_color="$GREEN"
    if [ "$api_health" = "failed" ]; then api_color="$RED"; fi
    echo -e "${api_color}🌐 API: $api_health${NC}"

    # Recent activity
    local activity="${json_output[recent_activity]}"
    local activity_color="$YELLOW"
    if [ "$activity" = "yes" ]; then activity_color="$GREEN"; fi
    echo -e "${activity_color}📈 Activity: $activity${NC}"

    # Alerts
    local alerts="${json_output[total_alerts]}"
    local alert_color="$GREEN"
    if [ "$alerts" -gt 0 ]; then alert_color="$RED"; fi
    echo -e "${alert_color}🚨 Alerts: $alerts${NC}"

    echo ""
    print_status "INFO" "Server: $SSH_USER@$SERVER_IP | Mode: $DEPLOY_DIR"
}

# Main health check function
main_health_check() {
    if [ "$JSON_OUTPUT" = false ]; then
        print_status "INFO" "🔍 MojoRust Trading Bot - Health Monitor"
        print_status "INFO" "Server: $SSH_USER@$SERVER_IP"
        echo ""
    fi

    # Run all checks
    check_connection
    check_system_resources
    check_bot_service
    check_api_endpoints
    check_recent_logs
    check_performance_metrics

    local alerts_result=0
    if [ "$ALERTS_ONLY" = false ]; then
        show_alerts
        alerts_result=$?
        if [ "$JSON_OUTPUT" = false ]; then
            echo ""
            show_summary
        fi
    else
        # Show only alerts
        local total_alerts="${json_output[total_alerts]}"
        if [ "$total_alerts" -gt 0 ]; then
            show_alerts
            alerts_result=$?
        else
            if [ "$JSON_OUTPUT" = false ]; then
                print_status "SUCCESS" "✅ No alerts - all systems healthy"
            fi
        fi
    fi

    # Output JSON if requested
    if [ "$JSON_OUTPUT" = true ]; then
        output_json
    fi

    # Return the alerts result for exit code
    return $alerts_result
}

# Function to run in watch mode
watch_mode() {
    print_status "INFO" "🔄 Starting continuous monitoring (Press Ctrl+C to stop)"
    echo ""

    while true; do
        clear
        main_health_check
        echo ""
        print_status "INFO" "Next check in 30 seconds... $(date)"
        sleep 30
    done
}

# Main execution
if [ "$WATCH_MODE" = true ]; then
    watch_mode
else
    main_health_check
    exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        exit $exit_code
    fi
fi