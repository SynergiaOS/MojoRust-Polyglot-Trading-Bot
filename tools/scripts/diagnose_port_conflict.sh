#!/bin/bash

# =============================================================================
# 🔍 Port 5432 Conflict Diagnostic Tool for MojoRust Trading Bot
# =============================================================================
# This script identifies processes occupying port 5432 and provides detailed diagnostics

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
PORT_TO_CHECK=5432
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Global variables
PORT_IN_USE=false
PROCESS_PID=""
PROCESS_NAME=""
PROCESS_USER=""
PROCESS_CMD=""
POSTGRES_SERVICE_STATUS=""
POSTGRES_VERSION=""
POSTGRES_DATA_DIR=""
POSTGRES_CONFIG_FILE=""
POSTGRES_CONFIGURED_PORT=""
DOCKER_CONTAINERS_ON_5432=()

# Options
JSON_OUTPUT=false
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
        echo "║    🔍 Port 5432 Conflict Diagnostic Tool - MojoRust Trading Bot   ║"
        echo "║                                                               ║"
        echo "║    Project: $PROJECT_ROOT"
        echo "║    Port to Check: $PORT_TO_CHECK"
        echo "║                                                               ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Check port 5432 status
check_port_5432() {
    log_header "Checking Port $PORT_TO_CHECK Status"

    local port_check_result=""

    # Try lsof first (most comprehensive)
    if command -v lsof >/dev/null 2>&1; then
        log_verbose "Using lsof to check port $PORT_TO_CHECK..."
        port_check_result=$(lsof -i :$PORT_TO_CHECK 2>/dev/null || echo "")
    fi

    # Fallback to netstat if lsof fails
    if [ -z "$port_check_result" ] && command -v netstat >/dev/null 2>&1; then
        log_verbose "Using netstat to check port $PORT_TO_CHECK..."
        port_check_result=$(netstat -tulpn 2>/dev/null | grep ":$PORT_TO_CHECK " || echo "")
    fi

    # Fallback to ss if both lsof and netstat fail
    if [ -z "$port_check_result" ] && command -v ss >/dev/null 2>&1; then
        log_verbose "Using ss to check port $PORT_TO_CHECK..."
        port_check_result=$(ss -tulpn 2>/dev/null | grep ":$PORT_TO_CHECK " || echo "")
    fi

    if [ -n "$port_check_result" ]; then
        PORT_IN_USE=true
        log_verbose "Port check result: $port_check_result"

        # Parse process information
        if command -v lsof >/dev/null 2>&1; then
            # lsof output format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            PROCESS_PID=$(echo "$port_check_result" | awk 'NR==1 {print $2}')
            PROCESS_NAME=$(echo "$port_check_result" | awk 'NR==1 {print $1}')
            PROCESS_USER=$(echo "$port_check_result" | awk 'NR==1 {print $3}')
            PROCESS_CMD=$(ps -p "$PROCESS_PID" -o args= 2>/dev/null || echo "N/A")
        else
            # Parse netstat/ss output
            PROCESS_PID=$(echo "$port_check_result" | awk '{print $7}' | cut -d'/' -f1)
            PROCESS_NAME=$(ps -p "$PROCESS_PID" -o comm= 2>/dev/null || echo "unknown")
            PROCESS_USER=$(ps -p "$PROCESS_PID" -o user= 2>/dev/null || echo "unknown")
            PROCESS_CMD=$(ps -p "$PROCESS_PID" -o args= 2>/dev/null || echo "N/A")
        fi

        log_error "🔴 Port $PORT_TO_CHECK CONFLICT DETECTED"
        log_error "Process: $PROCESS_NAME (PID: $PROCESS_PID, User: $PROCESS_USER)"
        log_error "Command: $PROCESS_CMD"

    else
        log_success "✅ Port $PORT_TO_CHECK is available"
    fi
}

# Detect PostgreSQL service
detect_postgres_service() {
    log_header "Detecting PostgreSQL Service"

    # Check systemd PostgreSQL service
    if command -v systemctl >/dev/null 2>&1; then
        log_verbose "Checking systemd PostgreSQL service..."

        # Try common PostgreSQL service names
        local service_names=("postgresql" "postgresql@14-main" "postgresql@13-main" "postgresql@12-main" "postgresql@15-main")

        for service in "${service_names[@]}"; do
            if systemctl is-active --quiet "$service" 2>/dev/null; then
                POSTGRES_SERVICE_STATUS="active"
                log_verbose "Found active PostgreSQL service: $service"

                # Get PostgreSQL version from service status
                POSTGRES_VERSION=$(systemctl status "$service" 2>/dev/null | grep -o "PostgreSQL [0-9]\+\.[0-9]\+" | head -1 | grep -o "[0-9]\+\.[0-9]\+" || echo "unknown")

                break
            elif systemctl list-unit-files | grep -q "$service" 2>/dev/null; then
                POSTGRES_SERVICE_STATUS="installed"
                log_verbose "Found installed PostgreSQL service: $service (not active)"
            fi
        done

        if [ -z "$POSTGRES_SERVICE_STATUS" ]; then
            POSTGRES_SERVICE_STATUS="not_found"
            log_verbose "No systemd PostgreSQL service found"
        fi
    else
        POSTGRES_SERVICE_STATUS="systemd_unavailable"
        log_verbose "systemctl not available"
    fi

    # Check for running PostgreSQL processes
    log_verbose "Checking for PostgreSQL processes..."
    local postgres_processes
    postgres_processes=$(ps aux | grep postgres | grep -v grep || echo "")

    if [ -n "$postgres_processes" ]; then
        log_verbose "PostgreSQL processes found:"
        if [ "$VERBOSE" = true ]; then
            echo "$postgres_processes"
        fi

        # Extract version and data directory from process command line
        local postgres_cmd=$(echo "$postgres_processes" | head -1 | awk '{print $0}')

        # Try to extract PostgreSQL version
        if echo "$postgres_cmd" | grep -q "postgres"; then
            POSTGRES_VERSION=$(echo "$postgres_cmd" | grep -o "PostgreSQL [0-9]\+\.[0-9]\+" | grep -o "[0-9]\+\.[0-9]\+" || echo "unknown")
        fi

        # Try to extract data directory
        if echo "$postgres_cmd" | grep -q "-D"; then
            POSTGRES_DATA_DIR=$(echo "$postgres_cmd" | grep -o "\-D [^ ]*" | awk '{print $2}' || echo "")
        fi
    else
        log_verbose "No PostgreSQL processes found"
    fi

    # Check if PostgreSQL is installed via package manager
    log_verbose "Checking PostgreSQL installation..."
    if command -v dpkg >/dev/null 2>&1; then
        if dpkg -l | grep -q postgresql; then
            log_verbose "PostgreSQL installed via apt/dpkg"
        fi
    elif command -v rpm >/dev/null 2>&1; then
        if rpm -qa | grep -q postgresql; then
            log_verbose "PostgreSQL installed via rpm/yum"
        fi
    fi

    # Report findings
    if [ "$JSON_OUTPUT" = false ]; then
        echo "PostgreSQL Service Status: $POSTGRES_SERVICE_STATUS"
        if [ -n "$POSTGRES_VERSION" ]; then
            echo "PostgreSQL Version: $POSTGRES_VERSION"
        fi
        if [ -n "$POSTGRES_DATA_DIR" ]; then
            echo "PostgreSQL Data Directory: $POSTGRES_DATA_DIR"
        fi
    fi
}

# Check Docker containers
check_docker_containers() {
    log_header "Checking Docker Containers"

    if command -v docker >/dev/null 2>&1; then
        log_verbose "Checking Docker containers using port $PORT_TO_CHECK..."

        # Check running containers
        local running_containers
        running_containers=$(docker ps --filter "publish=$PORT_TO_CHECK" --format "{{.Names}}" 2>/dev/null || echo "")

        if [ -n "$running_containers" ]; then
            log_warning "Found Docker containers using port $PORT_TO_CHECK:"
            while IFS= read -r container; do
                if [ -n "$container" ]; then
                    DOCKER_CONTAINERS_ON_5432+=("$container")
                    if [ "$JSON_OUTPUT" = false ]; then
                        echo "  - $container (running)"
                    fi
                fi
            done <<< "$running_containers"
        fi

        # Check all containers (including stopped ones)
        local all_containers
        all_containers=$(docker ps -a --filter "publish=$PORT_TO_CHECK" --format "{{.Names}}" 2>/dev/null || echo "")

        if [ -n "$all_containers" ]; then
            log_verbose "All Docker containers with port $PORT_TO_CHECK mapping: $all_containers"
        fi

        if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -eq 0 ]; then
            log_success "No Docker containers using port $PORT_TO_CHECK"
        fi
    else
        log_warning "Docker not available for container checks"
    fi
}

# Analyze PostgreSQL configuration
analyze_postgres_config() {
    log_header "Analyzing PostgreSQL Configuration"

    # Look for PostgreSQL configuration files in common locations
    local config_paths=(
        "/etc/postgresql/*/main/postgresql.conf"
        "/var/lib/pgsql/data/postgresql.conf"
        "/usr/local/pgsql/data/postgresql.conf"
        "/opt/postgresql/*/data/postgresql.conf"
    )

    for config_path in "${config_paths[@]}"; do
        # Expand wildcards
        for expanded_path in $config_path; do
            if [ -f "$expanded_path" ]; then
                POSTGRES_CONFIG_FILE="$expanded_path"
                log_verbose "Found PostgreSQL config: $POSTGRES_CONFIG_FILE"
                break 2
            fi
        done
    done

    if [ -n "$POSTGRES_CONFIG_FILE" ]; then
        # Extract port setting from configuration
        if [ -r "$POSTGRES_CONFIG_FILE" ]; then
            POSTGRES_CONFIGURED_PORT=$(grep "^port" "$POSTGRES_CONFIG_FILE" | awk '{print $3}' || echo "5432")
            log_verbose "PostgreSQL configured port: $POSTGRES_CONFIGURED_PORT"

            if [ "$JSON_OUTPUT" = false ]; then
                echo "PostgreSQL Config File: $POSTGRES_CONFIG_FILE"
                echo "Configured Port: $POSTGRES_CONFIGURED_PORT"
            fi
        else
            log_warning "PostgreSQL config file found but not readable: $POSTGRES_CONFIG_FILE"
        fi
    else
        log_verbose "No PostgreSQL configuration file found"
        if [ "$JSON_OUTPUT" = false ]; then
            echo "PostgreSQL Config File: Not found"
        fi
    fi
}

# Generate diagnostic report
generate_diagnostic_report() {
    log_header "Diagnostic Report"

    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "=============================================="
        echo "Port $PORT_TO_CHECK Diagnostic Results"
        echo "=============================================="
        echo ""

        if [ "$PORT_IN_USE" = true ]; then
            echo -e "${RED}🔴 CONFLICT DETECTED${NC}"
            echo ""
            echo "Port $PORT_TO_CHECK Status: IN USE"
            echo "Process Name: $PROCESS_NAME"
            echo "Process PID: $PROCESS_PID"
            echo "Process User: $PROCESS_USER"
            echo "Command: $PROCESS_CMD"
            echo ""

            if [ -n "$POSTGRES_SERVICE_STATUS" ] && [ "$POSTGRES_SERVICE_STATUS" = "active" ]; then
                echo -e "${YELLOW}⚠️  This appears to be a system PostgreSQL service${NC}"
            fi

            if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
                echo -e "${YELLOW}⚠️  Docker containers are also using this port${NC}"
                for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
                    echo "  Container: $container"
                done
            fi
        else
            echo -e "${GREEN}✅ NO CONFLICT DETECTED${NC}"
            echo ""
            echo "Port $PORT_TO_CHECK Status: AVAILABLE"
            echo "TimescaleDB can use this port safely"
        fi

        echo ""
        echo "PostgreSQL Service Information:"
        echo "  Service Status: $POSTGRES_SERVICE_STATUS"
        if [ -n "$POSTGRES_VERSION" ]; then
            echo "  Version: $POSTGRES_VERSION"
        fi
        if [ -n "$POSTGRES_DATA_DIR" ]; then
            echo "  Data Directory: $POSTGRES_DATA_DIR"
        fi
        if [ -n "$POSTGRES_CONFIG_FILE" ]; then
            echo "  Config File: $POSTGRES_CONFIG_FILE"
            echo "  Configured Port: $POSTGRES_CONFIGURED_PORT"
        fi

        if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
            echo ""
            echo "Docker Containers Using Port $PORT_TO_CHECK:"
            for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
                echo "  - $container"
            done
        fi

        echo ""
        echo "=============================================="
    fi
}

# Suggest resolutions
suggest_resolutions() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_header "Resolution Suggestions"

        if [ "$PORT_IN_USE" = true ]; then
            echo ""
            echo "Based on the diagnostic results, here are your options:"
            echo ""

            if [ "$POSTGRES_SERVICE_STATUS" = "active" ]; then
                echo -e "${GREEN}Option 1: Stop System PostgreSQL Service${NC}"
                echo "  sudo systemctl stop postgresql"
                echo "  sudo systemctl disable postgresql"
                echo "  This will free port 5432 for TimescaleDB use"
                echo ""
            fi

            if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
                echo -e "${GREEN}Option 2: Stop Conflicting Docker Container${NC}"
                for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
                    echo "  docker stop $container"
                done
                echo "  Optionally: docker rm <container_name>"
                echo ""
            fi

            if [ -n "$PROCESS_PID" ] && [ "$POSTGRES_SERVICE_STATUS" != "active" ]; then
                echo -e "${YELLOW}Option 3: Kill Process (Last Resort)${NC}"
                echo "  sudo kill -TERM $PROCESS_PID"
                echo "  If needed: sudo kill -9 $PROCESS_PID"
                echo "  ⚠️  This may cause data loss if process is important"
                echo ""
            fi

            echo -e "${BLUE}Option 4: Reconfigure TimescaleDB (Recommended)${NC}"
            echo "  Use the automated resolution script:"
            echo "  ./scripts/resolve_port_conflict.sh"
            echo ""
            echo "  This will reconfigure TimescaleDB to use port 5433"
            echo "  and update all necessary configuration files"
            echo ""

            echo -e "${PURPLE}Next Steps:${NC}"
            echo "1. Run: ./scripts/resolve_port_conflict.sh"
            echo "2. Follow the interactive prompts"
            echo "3. Verify: ./scripts/verify_port_availability.sh"
            echo "4. Deploy: docker-compose up -d"
        else
            echo ""
            echo -e "${GREEN}✅ No action required${NC}"
            echo "Port $PORT_TO_CHECK is available for TimescaleDB deployment"
            echo ""
            echo "Proceed with: docker-compose up -d"
        fi
    fi
}

# JSON output
output_json() {
    local json_output="{"
    json_output+='"timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    json_output+='"port_in_use": '$PORT_IN_USE','
    json_output+='"port": '$PORT_TO_CHECK','

    if [ "$PORT_IN_USE" = true ]; then
        json_output+='"process": {'
        json_output+='"pid": "'$PROCESS_PID'",'
        json_output+='"name": "'$PROCESS_NAME'",'
        json_output+='"user": "'$PROCESS_USER'",'
        json_output+='"command": "'$PROCESS_CMD'"'
        json_output+='},'
    else
        json_output+='"process": null,'
    fi

    json_output+='"postgres_service": {'
    json_output+='"status": "'$POSTGRES_SERVICE_STATUS'",'
    json_output+='"version": "'$POSTGRES_VERSION'",'
    json_output+='"data_directory": "'$POSTGRES_DATA_DIR'",'
    json_output+='"config_file": "'$POSTGRES_CONFIG_FILE'",'
    json_output+='"configured_port": "'$POSTGRES_CONFIGURED_PORT'"'
    json_output+='},'

    json_output+='"docker_containers": ['
    local first=true
    for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_output+=','
        fi
        json_output+='"'$container'"'
    done
    json_output+='],'

    json_output+='"recommendations": ['
    if [ "$PORT_IN_USE" = true ]; then
        if [ "$POSTGRES_SERVICE_STATUS" = "active" ]; then
            json_output+='"Stop PostgreSQL service with systemctl stop postgresql",'
        fi
        if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
            json_output+='"Stop conflicting Docker containers",'
        fi
        json_output+='"Run ./scripts/resolve_port_conflict.sh for automated resolution",'
        json_output+'"Reconfigure TimescaleDB to use port 5433"'
    else
        json_output+='"Port is available, proceed with deployment"'
    fi
    json_output+=']'
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
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --port)
                PORT_TO_CHECK="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --json                 Output results in JSON format"
                echo "  --verbose, -v          Show detailed diagnostic information"
                echo "  --port <port>          Port to check (default: 5432)"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "EXAMPLES:"
                echo "  $0                                          # Standard diagnostic output"
                echo "  $0 --json                                    # JSON output for automation"
                echo "  $0 --verbose                                 # Detailed diagnostics"
                echo "  $0 --port 9090                              # Check different port"
                echo ""
                echo "This script helps diagnose port conflicts, particularly for port 5432"
                echo "which is used by TimescaleDB in the MojoRust Trading Bot deployment."
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

    # Run diagnostic checks
    print_banner
    check_port_5432
    detect_postgres_service
    check_docker_containers
    analyze_postgres_config

    # Generate report and suggestions
    if [ "$JSON_OUTPUT" = true ]; then
        output_json
    else
        generate_diagnostic_report
        suggest_resolutions
    fi

    # Exit with appropriate code
    if [ "$PORT_IN_USE" = true ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"