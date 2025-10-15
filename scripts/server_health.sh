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
DEFAULT_API_BASE=""

# Configuration variables
SERVER_IP="${SERVER_IP:-$DEFAULT_SERVER_IP}"
SSH_USER="${SSH_USER:-$DEFAULT_SSH_USER}"
DEPLOY_DIR="${DEPLOY_DIR:-$DEFAULT_DEPLOY_DIR}"
API_BASE="${API_BASE:-$DEFAULT_API_BASE}"

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
    --api-base <URL>       API base URL (default: auto-detected)
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
    $0 --api-base http://localhost:8082  # Use specific API base URL

ENVIRONMENT VARIABLES:
    SERVER_IP       - Override server IP
    SSH_USER        - Override SSH user
    DEPLOY_DIR      - Override deployment directory
    API_BASE        - Override API base URL

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
        --api-base)
            API_BASE="$2"
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

# Helper function to check if command exists
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    local missing_tools=()

    if ! has_cmd "ss"; then
        missing_tools+=("ss")
    fi

    if ! has_cmd "bc"; then
        missing_tools+=("bc")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        if [ "$JSON_OUTPUT" = false ]; then
            print_status "WARNING" "Missing tools: ${missing_tools[*]}"
            print_status "INFO" "Some features may be limited"
        fi
        return 1
    fi

    return 0
}

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
        # Use portable awk comparison instead of bc
        if awk -v v="$cpu_usage" 'BEGIN{exit !(v>80)}'; then
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
        # Use portable awk comparison instead of bc
        if awk -v v="$memory_info" 'BEGIN{exit !(v>85)}'; then
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

# Function to check Docker services
check_docker_services() {
    print_status "HEADER" "Docker Services"

    # Check if Docker is running
    local docker_status=$(execute "docker --version 2>/dev/null && echo 'running' || echo 'not-running'" true)
    if [ "$docker_status" = "running" ]; then
        print_status "SUCCESS" "Docker is installed and running"
        json_output["docker_status"]="running"

        # Check docker-compose
        local compose_status=$(execute "docker-compose --version 2>/dev/null && echo 'available' || echo 'not-available'" true)
        if [ "$compose_status" = "available" ]; then
            print_status "SUCCESS" "Docker Compose is available"
            json_output["docker_compose"]="available"
        else
            print_status "WARNING" "Docker Compose not available"
            json_output["docker_compose"]="not-available"
        fi

        # Check if in correct directory for docker-compose
        local compose_file_exists=$(execute "test -f $DEPLOY_DIR/docker-compose.yml && echo 'exists' || echo 'not-found'" true)
        if [ "$compose_file_exists" = "exists" ]; then
            json_output["docker_compose_file"]="exists"

            # Get Docker Compose status
            local compose_status=$(execute "cd $DEPLOY_DIR && docker-compose ps 2>/dev/null || echo 'failed'" true)
            if [ "$compose_status" != "failed" ]; then
                # Count running containers
                local running_containers=$(execute "cd $DEPLOY_DIR && docker-compose ps --services --filter 'status=running' | wc -l" true)
                local total_services=$(execute "cd $DEPLOY_DIR && docker-compose config --services | wc -l" true)

                if [ "$running_containers" != "ERROR" ] && [ "$total_services" != "ERROR" ]; then
                    print_status "SUCCESS" "Docker Compose: $running_containers/$total_services services running"
                    json_output["running_containers"]="$running_containers"
                    json_output["total_services"]="$total_services"

                    # Check critical services
                    local critical_services=("timescaledb" "trading-bot" "prometheus" "grafana")
                    for service in "${critical_services[@]}"; do
                        local service_status=$(execute "cd $DEPLOY_DIR && docker-compose ps $service --format '{{.Status}}' 2>/dev/null || echo 'not-found'" true)
                        if [[ "$service_status" == *"Up"* ]]; then
                            print_status "SUCCESS" "Service $service: Running"
                            json_output["service_${service}"]="running"
                        else
                            print_status "WARNING" "Service $service: $service_status"
                            json_output["service_${service}"]="not-running"
                        fi
                    done

                    # Check container health
                    local unhealthy_containers=$(execute "cd $DEPLOY_DIR && docker-compose ps --format '{{.Name}}\t{{.Status}}' | grep -v 'healthy\|Up' | wc -l" true)
                    if [ "$unhealthy_containers" != "ERROR" ] && [ "$unhealthy_containers" -gt 0 ]; then
                        print_status "WARNING" "Found $unhealthy_containers unhealthy containers"
                        json_output["unhealthy_containers"]="$unhealthy_containers"
                    else
                        json_output["unhealthy_containers"]="0"
                    fi
                else
                    print_status "ERROR" "Could not get Docker Compose status"
                    json_output["docker_compose_status"]="error"
                fi
            else
                print_status "ERROR" "Docker Compose status check failed"
                json_output["docker_compose_status"]="failed"
            fi
        else
            print_status "WARNING" "docker-compose.yml not found in $DEPLOY_DIR"
            json_output["docker_compose_file"]="not-found"
        fi
    else
        print_status "ERROR" "Docker is not running or not installed"
        json_output["docker_status"]="not-running"
    fi
}

# Function to check bot service status (updated for Docker)
check_bot_service() {
    print_status "HEADER" "Trading Bot Service"

    # Check Docker-based bot first
    local docker_status=$(execute "cd $DEPLOY_DIR && docker-compose ps trading-bot --format '{{.Status}}' 2>/dev/null || echo 'not-found'" true)
    if [[ "$docker_status" == *"Up"* ]]; then
        print_status "SUCCESS" "Trading bot container is running"
        json_output["bot_status"]="running"
        json_output["bot_deployment"]="docker"

        # Get container details
        local container_details=$(execute "cd $DEPLOY_DIR && docker-compose ps trading-bot --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null" true)
        if [ "$container_details" != "ERROR" ] && [ -n "$container_details" ]; then
            print_status "INFO" "Container details:"
            echo "$container_details" | tail -n +2 | while IFS= read -r line; do
                echo "  $line"
            done
        fi

        # Check container resource usage
        local resource_usage=$(execute "cd $DEPLOY_DIR && docker stats trading-bot --no-stream --format 'table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}' 2>/dev/null" true)
        if [ "$resource_usage" != "ERROR" ] && [ -n "$resource_usage" ]; then
            print_status "INFO" "Resource usage:"
            echo "$resource_usage" | tail -n +2 | while IFS= read -r line; do
                echo "  $line"
            done
        fi

        # Get container logs health check
        local recent_errors=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=50 trading-bot 2>/dev/null | grep -i 'error\\|critical' | wc -l" true)
        if [ "$recent_errors" != "ERROR" ]; then
            if [ "$recent_errors" -gt 0 ]; then
                print_status "WARNING" "Found $recent_errors errors in recent container logs"
                json_output["container_log_errors"]="$recent_errors"
            else
                print_status "SUCCESS" "No errors in recent container logs"
                json_output["container_log_errors"]="0"
            fi
        fi

    elif [ "$docker_status" != "not-found" ]; then
        print_status "WARNING" "Trading bot container exists but not running: $docker_status"
        json_output["bot_status"]="not-running"
        json_output["bot_deployment"]="docker"
    else
        # Fallback to process-based check (for non-Docker deployments)
        local bot_processes=$(execute "pgrep -f 'trading-bot\\|mojo run\\|main.mojo' | wc -l" true)
        if [ "$bot_processes" != "ERROR" ]; then
            if [ "$bot_processes" -gt 0 ]; then
                print_status "SUCCESS" "Trading bot is running ($bot_processes processes)"
                json_output["bot_processes"]="$bot_processes"
                json_output["bot_status"]="running"
                json_output["bot_deployment"]="process"

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
    fi
}

# Function to check filter performance
check_filter_performance() {
    print_status "HEADER" "Filter Performance Health"

    local docker_deployment="${json_output[bot_deployment]}"
    local filter_log=""
    local rejection_rate=""

    if [ "$docker_deployment" = "docker" ]; then
        # Get filter performance from Docker logs
        filter_log=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=1000 trading-bot 2>/dev/null | grep -i 'Filter Performance' | tail -1" true)
    else
        # Get filter performance from file logs
        local latest_log=$(execute "ls -t $DEPLOY_DIR/logs/trading-bot-*.log 2>/dev/null | head -1" true)
        if [ "$latest_log" != "ERROR" ] && [ -n "$latest_log" ]; then
            filter_log=$(execute "tail -n 1000 $latest_log 2>/dev/null | grep -i 'Filter Performance' | tail -1" true)
        fi
    fi

    if [ "$filter_log" != "ERROR" ] && [ -n "$filter_log" ]; then
        # Extract rejection rate from log line
        rejection_rate=$(echo "$filter_log" | grep -oP '\d+\.?\d+(?=% rejection)' | head -1)

        if [ -n "$rejection_rate" ]; then
            json_output["filter_rejection_rate"]="$rejection_rate"

            # Classify filter health
            if awk -v v="$rejection_rate" 'BEGIN{exit !(v>=85 && v<=97)}'; then
                json_output["filter_health"]="healthy"
                print_status "SUCCESS" "Filter Performance: ${rejection_rate}% rejection (healthy)"
            elif awk -v v="$rejection_rate" 'BEGIN{exit !(v<85)}'; then
                json_output["filter_health"]="too_lenient"
                print_status "WARNING" "Filter Performance: ${rejection_rate}% rejection (too lenient)"
            else
                json_output["filter_health"]="too_aggressive"
                print_status "WARNING" "Filter Performance: ${rejection_rate}% rejection (too aggressive)"
            fi
        else
            json_output["filter_rejection_rate"]="unknown"
            json_output["filter_health"]="unknown"
            print_status "WARNING" "Filter Performance: Could not parse rejection rate"
        fi
    else
        json_output["filter_rejection_rate"]="unknown"
        json_output["filter_health"]="unknown"
        print_status "INFO" "Filter Performance: No data available"
    fi
}

# Function to check DragonflyDB connectivity
check_dragonflydb() {
    print_status "HEADER" "DragonflyDB Connectivity"

    # Check DragonflyDB Cloud connection using REDIS_URL from environment
    local redis_url=$(execute "echo \$REDIS_URL" true)
    if [ "$redis_url" != "ERROR" ] && [ -n "$redis_url" ]; then
        json_output["dragonflydb_configured"]="true"

        # Test DragonflyDB connection using redis-cli
        local ping_result=$(execute "redis-cli -u '$redis_url' ping 2>/dev/null || echo 'FAILED'" true)
        if [ "$ping_result" = "PONG" ]; then
            print_status "SUCCESS" "DragonflyDB Cloud: Connected (PONG)"
            json_output["dragonflydb_status"]="connected"

            # Get DragonflyDB info
            local db_info=$(execute "redis-cli -u '$redis_url' info server 2>/dev/null | head -10" true)
            if [ "$db_info" != "ERROR" ] && [ -n "$db_info" ]; then
                print_status "INFO" "DragonflyDB server info available"
                json_output["dragonflydb_info"]="available"
            fi

            # Test basic operations
            local test_result=$(execute "redis-cli -u '$redis_url' set health_check 'ok' 2>/dev/null && redis-cli -u '$redis_url' get health_check 2>/dev/null || echo 'FAILED'" true)
            if [ "$test_result" = "ok" ]; then
                print_status "SUCCESS" "DragonflyDB operations: Working"
                json_output["dragonflydb_operations"]="working"
            else
                print_status "WARNING" "DragonflyDB operations: Failed"
                json_output["dragonflydb_operations"]="failed"
            fi

            # Get memory usage
            local memory_info=$(execute "redis-cli -u '$redis_url' info memory 2>/dev/null | grep 'used_memory_human:' | cut -d':' -f2 | tr -d '\\r'" true)
            if [ "$memory_info" != "ERROR" ] && [ -n "$memory_info" ]; then
                print_status "INFO" "DragonflyDB memory usage: $memory_info"
                json_output["dragonflydb_memory"]="$memory_info"
            fi

        else
            print_status "ERROR" "DragonflyDB Cloud: Connection failed"
            json_output["dragonflydb_status"]="failed"
        fi
    else
        print_status "WARNING" "DragonflyDB Cloud: REDIS_URL not configured"
        json_output["dragonflydb_configured"]="false"

        # Fallback: Check local Redis if DragonflyDB not configured
        local local_redis=$(execute "redis-cli ping 2>/dev/null || echo 'FAILED'" true)
        if [ "$local_redis" = "PONG" ]; then
            print_status "INFO" "Local Redis: Available (fallback)"
            json_output["local_redis_status"]="available"
        else
            print_status "WARNING" "No Redis/DragonflyDB connection available"
            json_output["local_redis_status"]="unavailable"
        fi
    fi
}

# Function to check API endpoints (updated for Docker)
check_api_endpoints() {
    print_status "HEADER" "API Endpoints"

    # Determine API base URL
    local api_base="$API_BASE"
    if [ -z "$api_base" ]; then
        # Auto-detect based on deployment type
        local docker_deployment="${json_output[bot_deployment]}"
        if [ "$docker_deployment" = "docker" ]; then
            api_base="http://localhost:8082"
            print_status "INFO" "Auto-detected Docker API base: $api_base"
        else
            api_base="http://localhost:8080"
            print_status "INFO" "Auto-detected process API base: $api_base"
        fi
    else
        print_status "INFO" "Using provided API base: $api_base"
    fi

    # Store API base for JSON output
    json_output["api_base"]="$api_base"

    # Extract port for display
    local api_port=$(echo "$api_base" | sed 's/.*:\([0-9]*\).*/\1/')
    json_output["api_port"]="$api_port"

    # Health check
    local health_status=$(execute "curl -s --max-time 5 $api_base/health || echo 'failed'" true)
    if [[ "$health_status" == *"healthy"* ]] || [[ "$health_status" == *"ok"* ]] || [[ "$health_status" == *"status"* ]]; then
        print_status "SUCCESS" "API health endpoint responding"
        json_output["api_health"]="healthy"
    else
        print_status "WARNING" "API health endpoint not responding"
        json_output["api_health"]="failed"
    fi

    # Ready check
    local ready_status=$(execute "curl -s --max-time 5 $api_base/ready || echo 'failed'" true)
    if [[ "$ready_status" == *"ready"* ]] || [[ "$ready_status" == *"true"* ]]; then
        print_status "SUCCESS" "API ready endpoint responding"
        json_output["api_ready"]="ready"
    else
        print_status "INFO" "API ready endpoint: Not responding (optional)"
        json_output["api_ready"]="not-ready"
    fi

    # Metrics endpoint - use the same port as API base (FastAPI /metrics)
    local metrics_status=$(execute "curl -s --max-time 5 $api_base/metrics || echo 'failed'" true)
    if [[ "$metrics_status" == *"trading_bot"* ]] || [[ "$metrics_status" == *"metrics"* ]] || [[ "$metrics_status" == *"# HELP"* ]]; then
        print_status "SUCCESS" "Metrics endpoint responding (port $api_port)"
        json_output["api_metrics"]="responding"
        json_output["metrics_port"]="$api_port"
    else
        print_status "WARNING" "Metrics endpoint not responding (port $api_port)"
        json_output["api_metrics"]="failed"
    fi

    # Port check using ss instead of netstat
    local port_check_result="unknown"
    if has_cmd "ss"; then
        if execute "ss -lnt | awk '{print \$4}' | grep -q \":$api_port\"" true; then
            port_check_result="listening"
        else
            port_check_result="not-listening"
        fi
    else
        # Fallback to curl health check if ss is not available
        if [[ "$health_status" != *"failed"* ]]; then
            port_check_result="listening"
        else
            port_check_result="unknown"
        fi
    fi

    if [ "$port_check_result" = "listening" ]; then
        print_status "SUCCESS" "Port $api_port is listening"
        json_output["port_api"]="listening"
    else
        print_status "WARNING" "Port $api_port not found listening"
        json_output["port_api"]="not-listening"
    fi

    # Additional endpoint checks
    local arbitrage_status=$(execute "curl -s --max-time 5 $api_base/arbitrage/status || echo 'failed'" true)
    if [[ "$arbitrage_status" == *"is_running"* ]] || [[ "$arbitrage_status" == *"running"* ]]; then
        print_status "SUCCESS" "Arbitrage status endpoint responding"
        json_output["arbitrage_status"]="responding"
    else
        print_status "INFO" "Arbitrage status endpoint: Not configured or not responding"
        json_output["arbitrage_status"]="not-responding"
    fi
}

# Function to check recent logs (updated for Docker)
check_recent_logs() {
    print_status "HEADER" "Recent Log Analysis"

    local docker_deployment="${json_output[bot_deployment]}"

    if [ "$docker_deployment" = "docker" ]; then
        # Docker-based log checking
        print_status "INFO" "Checking Docker container logs"

        # Check if container is running
        local container_running=$(execute "cd $DEPLOY_DIR && docker-compose ps trading-bot --format '{{.Status}}' 2>/dev/null | grep -q 'Up' && echo 'yes' || echo 'no'" true)

        if [ "$container_running" = "yes" ]; then
            # Count errors and critical issues in last 200 lines of container logs
            local error_count=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'error\\|critical' | wc -l" true)
            local warning_count=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'warning' | wc -l" true)

            if [ "$error_count" != "ERROR" ] && [ "$warning_count" != "ERROR" ]; then
                if [ "$error_count" -gt 0 ]; then
                    print_status "ERROR" "Found $error_count errors/critical issues in last 200 lines"
                    json_output["log_errors"]="$error_count"

                    # Show last 3 errors
                    local last_errors=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'error\\|critical' | tail -3" true)
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
                local filter_performance=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'Filter Performance' | tail -5" true)
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
                local recent_trades=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'EXECUTED\\|PROFIT\\|LOSS' | tail -5" true)
                if [ "$recent_trades" != "ERROR" ] && [ -n "$recent_trades" ]; then
                    print_status "INFO" "Recent trade results:"
                    echo "$recent_trades" | while IFS= read -r line; do
                        echo "  $line"
                    done
                    json_output["recent_activity"]="yes"

                    # Count trades
                    local executed_count=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'EXECUTED' | wc -l" true)
                    local profit_count=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'PROFIT' | wc -l" true)
                    local loss_count=$(execute "cd $DEPLOY_DIR && docker-compose logs --tail=200 trading-bot 2>/dev/null | grep -i 'LOSS' | wc -l" true)
                    json_output["trades_executed"]="$executed_count"
                    json_output["trades_profit"]="$profit_count"
                    json_output["trades_loss"]="$loss_count"
                else
                    print_status "INFO" "No recent trading activity in logs"
                    json_output["recent_activity"]="no"
                fi
            else
                print_status "ERROR" "Could not analyze container logs"
                json_output["log_analysis"]="failed"
            fi
        else
            print_status "WARNING" "Trading bot container not running - cannot check logs"
            json_output["container_status"]="not-running"
        fi
    else
        # Process-based log checking (original logic)
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
    fi
}

# Function to check performance metrics
check_performance_metrics() {
    print_status "HEADER" "Performance Metrics"

    # Use the same API base as determined in check_api_endpoints
    local api_base="${json_output[api_base]}"
    if [ -z "$api_base" ]; then
        print_status "WARNING" "API base not available for performance metrics"
        json_output["performance_data"]="unavailable"
        return 1
    fi

    # Get performance summary - try the documented endpoint first
    local perf_data=$(execute "curl -s --max-time 5 $api_base/api/performance/summary || echo 'failed'" true)

    if [ "$perf_data" = "failed" ]; then
        # Fallback to metrics endpoint if performance summary is not available
        perf_data=$(execute "curl -s --max-time 5 $api_base/metrics || echo 'failed'" true)
    fi

    if [ "$perf_data" != "failed" ] && [ -n "$perf_data" ]; then
        # Extract key metrics from metrics format if performance summary failed
        if [[ "$perf_data" == *"trading_bot_trades_total"* ]]; then
            print_status "SUCCESS" "Performance metrics available from /metrics"
            json_output["performance_data"]="available"

            # Extract trade count from metrics
            local trade_count=$(echo "$perf_data" | grep "trading_bot_trades_total" | awk '{print $2}' | head -1)
            if [ -n "$trade_count" ]; then
                print_status "INFO" "Total trades: $trade_count"
                json_output["total_trades"]="$trade_count"
            fi

            # Extract portfolio value from metrics
            local portfolio_value=$(echo "$perf_data" | grep "trading_bot_portfolio_value" | awk '{print $2}' | head -1)
            if [ -n "$portfolio_value" ]; then
                print_status "INFO" "Portfolio value: $portfolio_value SOL"
                json_output["portfolio_value"]="$portfolio_value"
            fi

        elif [[ "$perf_data" == *"trades"* ]]; then
            # Original performance summary format
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

    # Docker-specific critical issues
    if [ "${json_output[docker_status]}" = "not-running" ]; then
        print_status "CRITICAL" "🚨 Docker is not running - required for containerized deployment"
        ((alerts++))
    fi

    if [ "${json_output[dragonflydb_status]}" = "failed" ] && [ "${json_output[dragonflydb_configured]}" = "true" ]; then
        print_status "ERROR" "❌ DragonflyDB Cloud connection failed"
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

    if [ "${json_output[log_errors]}" != "0" ] && [ "${json_output[log_errors]}" != "ERROR" ]; then
        print_status "WARNING" "⚠️  Recent errors detected in logs (${json_output[log_errors]})"
        ((alerts++))
    fi

    # Docker service alerts
    if [ "${json_output[unhealthy_containers]}" != "0" ] && [ "${json_output[unhealthy_containers]}" != "ERROR" ]; then
        print_status "WARNING" "⚠️  Found ${json_output[unhealthy_containers]} unhealthy containers"
        ((alerts++))
    fi

    # Show recommendations based on alerts
    if [ $alerts -eq 0 ]; then
        print_status "SUCCESS" "✅ No critical issues detected - everything looks good!"
    else
        print_status "WARNING" "⚠️  Found $alerts issue(s) that need attention"
        echo ""
        print_status "INFO" "Recommendations:"

        # Show Docker-specific recommendations
        if [ "${json_output[bot_deployment]}" = "docker" ]; then
            echo "  • Check Docker services: cd $DEPLOY_DIR && docker-compose ps"
            echo "  • Check container logs: cd $DEPLOY_DIR && docker-compose logs trading-bot"
            echo "  • Restart services: cd $DEPLOY_DIR && docker-compose restart trading-bot"
            echo "  • Check API: curl http://localhost:8082/health"
        else
            echo "  • Check logs: tail -f $DEPLOY_DIR/logs/trading-bot-*.log"
            echo "  • Restart bot: cd $DEPLOY_DIR && ./scripts/restart_bot.sh"
            echo "  • Check API: curl http://localhost:8080/api/health"
        fi

        echo "  • Monitor resources: htop, df -h"

        # DragonflyDB-specific recommendations
        if [ "${json_output[dragonflydb_status]}" = "failed" ]; then
            echo "  • Check DragonflyDB: redis-cli -u \$REDIS_URL ping"
        fi
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

    # Filter health
    local filter_health="${json_output[filter_health]}"
    local filter_color="$GREEN"
    if [ "$filter_health" = "too_lenient" ] || [ "$filter_health" = "too_aggressive" ]; then
        filter_color="$YELLOW";
    elif [ "$filter_health" = "unknown" ]; then
        filter_color="$RED";
    fi
    echo -e "${filter_color}🛡️  Filter: $filter_health${NC}"

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

    # Check dependencies first
    check_dependencies

    # Run all checks
    check_connection
    check_system_resources
    check_docker_services
    check_dragonflydb
    check_bot_service
    check_api_endpoints
    check_recent_logs
    check_filter_performance
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