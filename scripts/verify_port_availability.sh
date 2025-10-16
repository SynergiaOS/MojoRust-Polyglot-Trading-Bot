#!/bin/bash

# =============================================================================
# 🔍 Port Availability Verification Tool for MojoRust Trading Bot
# =============================================================================
# This script verifies all required ports are available before Docker Compose deployment

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

# Required ports for Docker Compose services
declare -A PORT_SERVICES=(
    [5432]="TimescaleDB"
    [9090]="Prometheus"
    [3001]="Grafana"
    [8082]="Trading Bot"
    [9093]="AlertManager"
    [8081]="pgAdmin"
    [9191]="Data Consumer"
    [9100]="Node Exporter"
    [8083]="cAdvisor"
)

# Required ports array
REQUIRED_PORTS=(5432 9090 3001 8082 9093 8081 9191 9100 8083)

# Port check results
declare -A PORT_STATUS
declare -A PORT_PROCESS

# Options
JSON_OUTPUT=false
WATCH_MODE=false
PRE_DEPLOY_MODE=false
SINGLE_PORT=""
VERBOSE=false

# Logging functions
log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}ℹ️  $1${NC}"
    fi
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}✅ $1${NC}"
    fi
}

log_warning() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}⚠️  $1${NC}"
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}❌ $1${NC}"
    fi
}

log_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}$1${NC}"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "${CYAN}  $1${NC}"
    fi
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                               ║"
        echo "║    🔍 Port Availability Verification - MojoRust Trading Bot     ║"
        echo "║                                                               ║"
        echo "║    Project: $PROJECT_ROOT"
        echo "║    Required Ports: ${#REQUIRED_PORTS[@]}"
        echo "║                                                               ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Check individual port
check_port() {
    local port=$1
    local service_name=${PORT_SERVICES[$port]:-"Unknown"}
    local port_check_result=""
    local process_info=""

    # Try different tools to check port
    if command -v lsof >/dev/null 2>&1; then
        port_check_result=$(lsof -i :$port 2>/dev/null || echo "")
        if [ -n "$port_check_result" ]; then
            # Parse lsof output for process info
            process_info=$(echo "$port_check_result" | awk 'NR==1 {print $1 " (PID: " $2 ", User: " $3 ")"}')
        fi
    elif command -v netstat >/dev/null 2>&1; then
        port_check_result=$(netstat -tulpn 2>/dev/null | grep ":$port " || echo "")
        if [ -n "$port_check_result" ]; then
            # Parse netstat output
            local pid=$(echo "$port_check_result" | awk '{print $7}' | cut -d'/' -f1)
            if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                local process_user=$(ps -p "$pid" -o user= 2>/dev/null || echo "unknown")
                process_info="$process_name (PID: $pid, User: $process_user)"
            fi
        fi
    elif command -v ss >/dev/null 2>&1; then
        port_check_result=$(ss -tulpn 2>/dev/null | grep ":$port " || echo "")
        if [ -n "$port_check_result" ]; then
            # Parse ss output
            local pid=$(echo "$port_check_result" | awk '{print $7}' | cut -d'/' -f1)
            if [ -n "$pid" ] && [ "$pid" != "-" ]; then
                local process_name=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                local process_user=$(ps -p "$pid" -o user= 2>/dev/null || echo "unknown")
                process_info="$process_name (PID: $pid, User: $process_user)"
            fi
        fi
    fi

    if [ -n "$port_check_result" ]; then
        PORT_STATUS[$port]="in_use"
        PORT_PROCESS[$port]="$process_info"
        if [ "$JSON_OUTPUT" = false ]; then
            log_verbose "Port $port ($service_name): IN USE - $process_info"
        fi
        return 1
    else
        PORT_STATUS[$port]="available"
        PORT_PROCESS[$port]=""
        if [ "$JSON_OUTPUT" = false ]; then
            log_verbose "Port $port ($service_name): Available"
        fi
        return 0
    fi
}

# Check all required ports
check_all_ports() {
    log_header "Checking Required Ports"

    local available_count=0
    local total_count=${#REQUIRED_PORTS[@]}

    for port in "${REQUIRED_PORTS[@]}"; do
        if check_port "$port"; then
            available_count=$((available_count + 1))
        fi
    done

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_info "Port Status Summary:"
        echo "  Available: $available_count / $total_count ports"
        echo "  Conflicts: $((total_count - available_count)) / $total_count ports"
        echo ""
    fi
}

# Extract Docker Compose ports
extract_docker_compose_ports() {
    log_header "Extracting Docker Compose Ports"

    if [ ! -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        log_error "docker-compose.yml not found at $PROJECT_ROOT/docker-compose.yml"
        return 1
    fi

    log_verbose "Parsing docker-compose.yml for port mappings..."

    # Use docker-compose config to get port information
    if cd "$PROJECT_ROOT" && docker-compose config >/dev/null 2>&1; then
        local compose_ports
        compose_ports=$(docker-compose config 2>/dev/null | grep -A 20 "ports:" | grep -E "[0-9]+:[0-9]+" | sed 's/.*\([0-9]\+\):\([0-9]\+\).*/\1:\2/' | sort -u)

        if [ -n "$compose_ports" ]; then
            log_verbose "Docker Compose ports found:"
            if [ "$VERBOSE" = true ]; then
                echo "$compose_ports"
            fi

            # Compare with required ports
            local missing_ports=()
            for port in "${REQUIRED_PORTS[@]}"; do
                local found=false
                while IFS= read -r compose_port; do
                    local external_port=$(echo "$compose_port" | cut -d: -f1)
                    local internal_port=$(echo "$compose_port" | cut -d: -f2)
                    if [ "$external_port" = "$port" ] || [ "$internal_port" = "$port" ]; then
                        found=true
                        break
                    fi
                done <<< "$compose_ports"

                if [ "$found" = false ]; then
                    missing_ports+=("$port")
                fi
            done

            if [ ${#missing_ports[@]} -gt 0 ]; then
                log_warning "Ports not found in docker-compose.yml: ${missing_ports[*]}"
            fi
        else
            log_warning "No port mappings found in docker-compose.yml"
        fi
    else
        log_error "Failed to parse docker-compose.yml"
        return 1
    fi

    return 0
}

# Suggest alternative ports
suggest_alternative_ports() {
    log_header "Suggesting Alternative Ports"

    if [ "$JSON_OUTPUT" = false ]; then
        echo "Alternative ports for conflicting services:"
        echo ""
    fi

    for port in "${!PORT_STATUS[@]}"; do
        if [ "${PORT_STATUS[$port]}" = "in_use" ]; then
            local service_name=${PORT_SERVICES[$port]:-"Unknown"}
            local alternatives=()

            case $port in
                5432)
                    alternatives=(5433 5434 5435 5436)
                    ;;
                9090)
                    alternatives=(9091 9092 9093 9094)
                    ;;
                3001)
                    alternatives=(3002 3003 3004 3005)
                    ;;
                8082)
                    alternatives=(8083 8084 8085 8086)
                    ;;
                9093)
                    alternatives=(9094 9095 9096 9097)
                    ;;
                8081)
                    alternatives=(8082 8083 8084 8085)
                    ;;
                9191)
                    alternatives=(9192 9193 9194 9195)
                    ;;
                9100)
                    alternatives=(9101 9102 9103 9104)
                    ;;
                8083)
                    alternatives=(8084 8085 8086 8087)
                    ;;
                *)
                    alternatives=$((port + 1))
                    ;;
            esac

            # Test suggested alternatives
            local available_alternatives=()
            for alt_port in "${alternatives[@]}"; do
                if check_port "$alt_port"; then
                    available_alternatives+=("$alt_port")
                fi
            done

            if [ "$JSON_OUTPUT" = false ]; then
                echo "  $service_name (Port $port):"
                echo "    Original: $port (${PORT_PROCESS[$port]})"
                if [ ${#available_alternatives[@]} -gt 0 ]; then
                    echo "    Suggested: ${available_alternatives[0]} (available)"
                else
                    echo "    Suggested: No available alternatives in range"
                fi
                echo ""
            fi
        fi
    done
}

# Check environment variable port configuration
check_env_port_config() {
    log_header "Checking Environment Variable Port Configuration"

    local env_file="$PROJECT_ROOT/.env"
    if [ ! -f "$env_file" ]; then
        log_verbose ".env file not found"
        return 0
    fi

    # Check TIMESCALEDB_PORT if defined
    if grep -q "^TIMESCALEDB_PORT=" "$env_file"; then
        local env_port=$(grep "^TIMESCALEDB_PORT=" "$env_file" | cut -d'=' -f2 | tr -d '"')
        local service_name=${PORT_SERVICES[5432]:-"TimescaleDB"}

        log_verbose "Found TIMESCALEDB_PORT=$env_port in .env file"

        if [ "$env_port" != "5432" ]; then
            log_info "$service_name configured for port: $env_port"

            # Check if configured port is available
            if check_port "$env_port"; then
                log_success "Configured port $env_port is available"
            else
                log_warning "Configured port $env_port is in use"
            fi
        fi

        # Check TIMESCALEDB_URL consistency
        if grep -q "^TIMESCALEDB_URL=" "$env_file"; then
            local env_url=$(grep "^TIMESCALEDB_URL=" "$env_file" | cut -d'=' -f2 | tr -d '"')
            local url_port=$(echo "$env_url" | grep -o ":[0-9]\+" | sed 's/://' || echo "")

            if [ -n "$url_port" ]; then
                if [ "$url_port" != "$env_port" ]; then
                    log_warning "Port mismatch: TIMESCALEDB_PORT=$env_port but TIMESCALEDB_URL uses port $url_port"
                else
                    log_success "TIMESCALEDB_URL port matches TIMESCALEDB_PORT configuration"
                fi
            fi
        fi
    else
        log_verbose "TIMESCALEDB_PORT not defined in .env file (will use default)"
    fi

    return 0
}

# Validate for deployment
validate_for_deployment() {
    log_header "Pre-Deployment Validation"

    local validation_passed=true

    # Check Docker is running
    log_step "Checking Docker..."
    if docker info >/dev/null 2>&1; then
        log_success "Docker is running"
    else
        log_error "Docker is not running or not accessible"
        validation_passed=false
    fi

    # Check Docker Compose is installed
    log_step "Checking Docker Compose..."
    if docker-compose --version >/dev/null 2>&1; then
        log_success "Docker Compose is installed"
    else
        log_error "Docker Compose is not installed"
        validation_passed=false
    fi

    # Check docker-compose.yml syntax
    log_step "Validating docker-compose.yml syntax..."
    if cd "$PROJECT_ROOT" && docker-compose config >/dev/null 2>&1; then
        log_success "docker-compose.yml syntax is valid"
    else
        log_error "docker-compose.yml has syntax errors"
        validation_passed=false
    fi

    # Check all required ports
    log_step "Checking required ports..."
    check_all_ports

    local available_count=0
    local total_count=${#REQUIRED_PORTS[@]}
    for port in "${REQUIRED_PORTS[@]}"; do
        if [ "${PORT_STATUS[$port]}" = "available" ]; then
            available_count=$((available_count + 1))
        fi
    done

    if [ "$available_count" -eq "$total_count" ]; then
        log_success "All required ports are available"
    else
        log_error "Port conflicts detected: $((total_count - available_count)) ports in use"
        validation_passed=false
    fi

    # Generate validation report
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_header "Pre-Deployment Validation Report"
        echo "=============================================="
        echo "Docker Status: $(docker info >/dev/null 2>&1 && echo "Running" || echo "Not Running")"
        echo "Docker Compose: $(docker-compose --version >/dev/null 2>&1 && echo "Installed" || echo "Not Installed")"
        echo "Config Syntax: $(cd "$PROJECT_ROOT" && docker-compose config >/dev/null 2>&1 && echo "Valid" || echo "Invalid")"
        echo "Port Availability: $available_count/$total_count available"
        echo "=============================================="
        echo ""

        if [ "$validation_passed" = true ]; then
            log_success "✅ Pre-deployment validation PASSED"
            echo ""
            log_info "System is ready for Docker Compose deployment"
            echo "Command: docker-compose up -d"
        else
            log_error "❌ Pre-deployment validation FAILED"
            echo ""
            log_info "Please resolve the issues above before deploying"
            echo "Run: ./scripts/resolve_port_conflict.sh to resolve port conflicts"
        fi
    fi

    return $([ "$validation_passed" = true ] && echo 0 || echo 1)
}

# Continuous monitoring mode
start_watch_mode() {
    log_header "Starting Continuous Port Monitoring Mode"
    log_info "Monitoring ports every 5 seconds. Press Ctrl+C to stop."
    echo ""

    local previous_status=""

    while true; do
        # Clear port status
        for port in "${REQUIRED_PORTS[@]}"; do
            unset PORT_STATUS[$port]
            unset PORT_PROCESS[$port]
        done

        # Check all ports
        check_all_ports

        # Generate current status string
        local current_status=""
        for port in "${REQUIRED_PORTS[@]}"; do
            if [ "${PORT_STATUS[$port]}" = "in_use" ]; then
                current_status+=" $port:IN_USE"
            else
                current_status+=" $port:AVAIL"
            fi
        done

        # Only output if status changed
        if [ "$current_status" != "$previous_status" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Port Status Change Detected:"

            for port in "${REQUIRED_PORTS[@]}"; do
                local service_name=${PORT_SERVICES[$port]:-"Unknown"}
                if [ "${PORT_STATUS[$port]}" = "in_use" ]; then
                    echo "  🚨 Port $port ($service_name): IN USE - ${PORT_PROCESS[$port]}"
                else
                    echo "  ✅ Port $port ($service_name): Available"
                fi
            done
            echo ""
        fi

        previous_status="$current_status"
        sleep 5
    done
}

# Generate port report
generate_port_report() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_header "Port Availability Report"
        echo "============================================"
        echo ""

        # Create table header
        printf "%-8s | %-15s | %-10s | %s\n" "Port" "Service" "Status" "Process"
        printf "--------+-----------------+------------+------------------------\n"

        # Sort ports numerically
        local sorted_ports=($(printf '%s\n' "${REQUIRED_PORTS[@]}" | sort -n))

        for port in "${sorted_ports[@]}"; do
            local service_name=${PORT_SERVICES[$port]:-"Unknown"}
            local status="${PORT_STATUS[$port]:-"unknown"}"
            local process="${PORT_PROCESS[$port]:-""}"

            if [ "$status" = "available" ]; then
                printf "%-8s | %-15s | ${GREEN}%-10s${NC} | %s\n" "$port" "$service_name" "Available" "$process"
            else
                printf "%-8s | %-15s | ${RED}%-10s${NC} | %s\n" "$port" "$service_name" "IN USE" "$process"
            fi
        done

        echo ""
        echo "============================================"

        # Show summary
        local available_count=0
        local total_count=${#REQUIRED_PORTS[@]}
        for port in "${REQUIRED_PORTS[@]}"; do
            if [ "${PORT_STATUS[$port]}" = "available" ]; then
                available_count=$((available_count + 1))
            fi
        done

        echo "Summary: $available_count of $total_count ports available"
        echo "Conflicts: $((total_count - available_count)) ports in use"
        echo ""

        if [ $available_count -eq $total_count ]; then
            echo -e "${GREEN}✅ All required ports are available for deployment${NC}"
        else
            echo -e "${RED}❌ Port conflicts detected - resolve before deployment${NC}"
            echo ""
            echo "Next steps:"
            echo "1. Run: ./scripts/diagnose_port_conflict.sh"
            echo "2. Run: ./scripts/resolve_port_conflict.sh"
            echo "3. Run: ./scripts/verify_port_availability.sh --pre-deploy"
        fi
    fi
}

# JSON output
output_json() {
    local json_output="{"
    json_output+='"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    json_output+='"ports": ['

    # Sort ports numerically for consistent output
    local sorted_ports=($(printf '%s\n' "${REQUIRED_PORTS[@]}" | sort -n))
    local first=true

    for port in "${sorted_ports[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_output+=','
        fi

        local service_name=${PORT_SERVICES[$port]:-"Unknown"}
        local status="${PORT_STATUS[$port]:-"unknown"}"
        local process="${PORT_PROCESS[$port]:-""}"

        json_output+="{"
        json_output+='"port": '$port','
        json_output+='"service": "'$service_name'",'
        json_output+='"available": '$([ "$status" = "available" ] && echo "true" || echo "false")','
        json_output+='"process": "'$process'"'
        json_output+="}"
    done

    json_output+='],'

    # Summary
    local available_count=0
    local total_count=${#REQUIRED_PORTS[@]}
    for port in "${REQUIRED_PORTS[@]}"; do
        if [ "${PORT_STATUS[$port]}" = "available" ]; then
            available_count=$((available_count + 1))
        fi
    done

    json_output+='"summary": {'
    json_output+='"total": '$total_count','
    json_output+='"available": '$available_count','
    json_output+='"conflicts": '$((total_count - available_count))'
    json_output+='}'
    json_output+='}'

    echo "$json_output"
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
            --pre-deploy)
                PRE_DEPLOY_MODE=true
                shift
                ;;
            --port)
                SINGLE_PORT="$2"
                REQUIRED_PORTS=("$2")
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --json                 Output results in JSON format"
                echo "  --watch               Continuous monitoring mode (updates every 5s)"
                echo "  --pre-deploy          Run comprehensive pre-deployment validation"
                echo "  --port <port>         Check only specific port"
                echo "  --verbose, -v          Show detailed output"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "EXAMPLES:"
                echo "  $0                                          # Standard port check"
                echo "  $0 --json                                    # JSON output"
                echo "  $0 --watch                                   # Continuous monitoring"
                echo "  $0 --pre-deploy                              # Pre-deployment validation"
                echo "  $0 --port 5432                              # Check specific port"
                echo "  $0 --verbose                                 # Detailed output"
                echo ""
                echo "This script verifies all required ports for the MojoRust Trading Bot"
                echo "Docker Compose deployment and provides recommendations for"
                echo "resolving conflicts when detected."
                echo ""
                echo "Required Ports by Service:"
                echo "  - 5432: TimescaleDB (PostgreSQL)"
                echo "  - 9090: Prometheus (Metrics Collection)"
                echo "  - 3001: Grafana (Visualization Dashboard)"
                echo "  - 8082: Trading Bot (Main Application)"
                echo "  - 9093: AlertManager (Alert Routing)"
                echo "  - 8081: pgAdmin (Database Administration)"
                echo "  - 9191: Data Consumer (Geyser Streaming)"
                echo "  - 9100: Node Exporter (System Metrics)"
                echo "  - 8083: cAdvisor (Container Metrics)"
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run main workflow
    print_banner

    if [ "$WATCH_MODE" = true ]; then
        start_watch_mode
    elif [ "$PRE_DEPLOY_MODE" = true ]; then
        validate_for_deployment
    else
        # Standard port checking
        extract_docker_compose_ports
        check_all_ports
        check_env_port_config
        suggest_alternative_ports
        generate_port_report
    fi
}

# Run main function
main "$@"