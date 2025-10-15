#!/bin/bash

# =============================================================================
# MojoRust Trading Bot - Monitoring Stack Orchestration Script
# =============================================================================
# This script starts the monitoring stack in the correct order with health checks

set -euo pipefail

# =============================================================================
# Colors for output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration Variables
# =============================================================================
COMPOSE_FILE="docker-compose.yml"
SERVICES=("prometheus" "grafana" "node-exporter" "alertmanager")
WAIT_TIMEOUT=120
SKIP_VERIFY=false
SPECIFIC_SERVICE=""
VERBOSE=false

# =============================================================================
# Functions
# =============================================================================

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
        log_error "curl is not installed"
    else
        log_detail "curl is available: $(curl --version | head -1)"
    fi

    # Check for docker-compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        missing_deps+=("docker-compose")
        log_error "docker-compose is not installed"
    else
        log_detail "docker-compose is available: $(docker-compose --version)"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        log_info "Installation instructions:"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
        echo "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
        echo "  macOS:         brew install ${missing_deps[*]}"
        echo ""
        log_info "Please install the missing dependencies and try again."
        exit 1
    fi

    log_success "All dependencies are available"
}

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🚀 STARTING MONITORING STACK 🚀                            ║"
    echo "║                                                              ║"
    echo "║    Prometheus + Grafana + Node Exporter + AlertManager       ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_detail() {
    if [[ "${VERBOSE:-false}" == true ]]; then
        echo -e "${BLUE}[DETAIL]${NC} $1"
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running or not accessible"
        exit 1
    fi
    log_success "Docker is running"

    # Check if docker-compose is installed
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "docker-compose is not installed"
        exit 1
    fi
    log_success "docker-compose is available"

    # Check if docker-compose.yml exists and is valid
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        log_error "docker-compose.yml not found at $COMPOSE_FILE"
        exit 1
    fi

    if ! docker-compose config >/dev/null 2>&1; then
        log_error "docker-compose.yml is invalid"
        exit 1
    fi
    log_success "docker-compose.yml is valid"

    # Check required ports are available
    local required_ports=(9090 3001 9100 9093)
    local port_conflicts=()
    local port_check_cmd=""

    # Determine port checking command based on availability
    if command -v lsof >/dev/null 2>&1; then
        port_check_cmd="lsof -i :"
        log_detail "Using lsof for port checking"
    elif command -v ss >/dev/null 2>&1; then
        port_check_cmd="ss -lnt | grep -q ':"
        log_detail "Using ss for port checking"
    elif command -v netstat >/dev/null 2>&1; then
        port_check_cmd="netstat -lnt | grep -q ':"
        log_detail "Using netstat for port checking"
    else
        log_warning "No port checking tools found (lsof, ss, netstat)"
        log_info "Proceeding without port conflict detection"
        log_info "If services fail to start, check if ports are already in use"
        return 0
    fi

    for port in "${required_ports[@]}"; do
        local port_in_use=false

        if [[ "$port_check_cmd" == "lsof -i :"* ]]; then
            if lsof -i :"$port" >/dev/null 2>&1; then
                port_in_use=true
            fi
        elif [[ "$port_check_cmd" == "ss -lnt | grep -q ':"* ]]; then
            if ss -lnt | grep -q ":$port "; then
                port_in_use=true
            fi
        elif [[ "$port_check_cmd" == "netstat -lnt | grep -q ':"* ]]; then
            if netstat -lnt | grep -q ":$port "; then
                port_in_use=true
            fi
        fi

        if [[ "$port_in_use" == true ]]; then
            port_conflicts+=("$port")
        fi
    done

    if [[ ${#port_conflicts[@]} -gt 0 ]]; then
        log_warning "Port conflicts detected: ${port_conflicts[*]}"
        echo ""
        log_info "Port conflict resolution instructions:"
        echo "1. Identify processes using the ports:"
        echo "   - With lsof: lsof -i :<port>"
        echo "   - With ss:    ss -lntp | grep :<port>"
        echo "   - With netstat: netstat -lntp | grep :<port>"
        echo ""
        echo "2. Stop conflicting processes or use different ports"
        echo ""
        echo "3. Alternatively, modify docker-compose.yml to use different ports"

        # Ask user if they want to continue
        echo ""
        read -p "Do you want to continue despite port conflicts? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Please resolve port conflicts and try again"
            exit 1
        fi
    else
        log_success "All required ports are available"
    fi

    log_success "Prerequisites check passed"
}

start_service() {
    local service_name=$1
    local max_attempts=30
    local attempt=1

    log_info "Starting $service_name..."

    # Start the service
    if ! docker-compose up -d "$service_name"; then
        log_error "Failed to start $service_name"
        return 1
    fi

    # Wait for service to be healthy
    while [[ $attempt -le $max_attempts ]]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "trading-bot-$service_name" 2>/dev/null || echo "unknown")

        case "$health_status" in
            "healthy")
                log_success "$service_name is healthy"
                return 0
                ;;
            "unhealthy")
                log_error "$service_name is unhealthy"
                return 1
                ;;
            "starting")
                log_detail "$service_name is starting... (attempt $attempt/$max_attempts)"
                ;;
            *)
                log_detail "$service_name health status: $health_status (attempt $attempt/$max_attempts)"
                ;;
        esac

        sleep 2
        ((attempt++))
    done

    log_error "$service_name did not become healthy within $((max_attempts * 2)) seconds"
    return 1
}

start_prometheus() {
    log_info "Starting Prometheus..."

    if ! start_service "prometheus"; then
        log_error "Failed to start Prometheus"
        return 1
    fi

    # Verify Prometheus is accessible
    local prometheus_url="http://localhost:9090"
    local max_attempts=10
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "$prometheus_url/-/healthy" >/dev/null 2>&1; then
            log_success "Prometheus is accessible at $prometheus_url"

            # Check configuration
            if curl -sf "$prometheus_url/api/v1/status/config" >/dev/null 2>&1; then
                log_success "Prometheus configuration is loaded"
            else
                log_warning "Prometheus configuration may not be fully loaded"
            fi

            echo "  Prometheus URL: $prometheus_url"
            echo "  Targets: $prometheus_url/targets"
            echo "  Alerts: $prometheus_url/alerts"

            return 0
        fi

        log_detail "Waiting for Prometheus to be accessible... (attempt $attempt/$max_attempts)"
        sleep 3
        ((attempt++))
    done

    log_error "Prometheus is not accessible after $((max_attempts * 3)) seconds"
    return 1
}

start_grafana() {
    log_info "Starting Grafana (depends on Prometheus)..."

    # Ensure Prometheus is running first
    if ! docker-compose ps prometheus | grep -q "Up"; then
        log_error "Prometheus is not running - cannot start Grafana"
        return 1
    fi

    if ! start_service "grafana"; then
        log_error "Failed to start Grafana"
        return 1
    fi

    # Wait for Grafana API to be ready
    local grafana_url="http://localhost:3001"
    local max_attempts=15
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "$grafana_url/api/health" >/dev/null 2>&1; then
            log_success "Grafana API is ready at $grafana_url"
            break
        fi

        log_detail "Waiting for Grafana API... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    # Verify datasources are provisioned
    log_info "Checking Grafana datasources..."
    local datasource_check_attempts=5
    local datasource_attempt=1

    while [[ $datasource_attempt -le $datasource_check_attempts ]]; do
        local datasource_count
        if datasource_count=$(curl -s -u admin:trading_admin "$grafana_url/api/datasources" | jq 'length' 2>/dev/null); then
            if [[ $datasource_count -gt 0 ]]; then
                log_success "Grafana datasources are provisioned ($datasource_count datasources)"
                break
            fi
        fi

        log_detail "Waiting for datasources to be provisioned... (attempt $datasource_attempt/$datasource_check_attempts)"
        sleep 3
        ((datasource_attempt++))
    done

    # Verify dashboards are loaded
    log_info "Checking Grafana dashboards..."
    local dashboard_check_attempts=5
    local dashboard_attempt=1

    while [[ $dashboard_attempt -le $dashboard_check_attempts ]]; do
        local dashboard_count
        if dashboard_count=$(curl -s -u admin:trading_admin "$grafana_url/api/search?type=dash-db" | jq 'length' 2>/dev/null); then
            if [[ $dashboard_count -gt 0 ]]; then
                log_success "Grafana dashboards are loaded ($dashboard_count dashboards)"
                break
            fi
        fi

        log_detail "Waiting for dashboards to be loaded... (attempt $dashboard_attempt/$dashboard_check_attempts)"
        sleep 3
        ((dashboard_attempt++))
    done

    echo "  Grafana URL: $grafana_url"
    echo "  Credentials: admin/trading_admin"
    echo "  Dashboards: $grafana_url/dashboards"

    return 0
}

start_node_exporter() {
    log_info "Starting Node Exporter..."

    # Start node-exporter directly without using start_service (no healthcheck defined)
    if ! docker-compose up -d node-exporter; then
        log_error "Failed to start Node Exporter"
        return 1
    fi

    # Wait for Node Exporter to be responsive by polling the metrics endpoint
    local node_exporter_url="http://localhost:9100"
    local max_attempts=15
    local attempt=1

    log_detail "Waiting for Node Exporter to become responsive..."

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "$node_exporter_url/metrics" >/dev/null 2>&1; then
            local metrics_count
            metrics_count=$(curl -s "$node_exporter_url/metrics" | grep -c "^node_" || echo "0")

            if [[ $metrics_count -gt 0 ]]; then
                log_success "Node Exporter is collecting metrics ($metrics_count metrics)"
                echo "  Node Exporter URL: $node_exporter_url/metrics"
                return 0
            else
                log_detail "Node Exporter is responsive but not collecting metrics yet... (attempt $attempt/$max_attempts)"
            fi
        else
            log_detail "Node Exporter is not yet responsive... (attempt $attempt/$max_attempts)"
        fi

        sleep 2
        ((attempt++))
    done

    log_error "Node Exporter did not become responsive within $((max_attempts * 2)) seconds"
    return 1
}

start_alertmanager() {
    log_info "Starting AlertManager..."

    if ! start_service "alertmanager"; then
        log_error "Failed to start AlertManager"
        return 1
    fi

    # Verify AlertManager is accessible
    local alertmanager_url="http://localhost:9093"
    local max_attempts=5
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if curl -sf "$alertmanager_url/-/healthy" >/dev/null 2>&1; then
            log_success "AlertManager is accessible at $alertmanager_url"
            echo "  AlertManager URL: $alertmanager_url"
            echo "  Alerts: $alertmanager_url/#/alerts"
            return 0
        fi

        log_detail "Waiting for AlertManager to be accessible... (attempt $attempt/$max_attempts)"
        sleep 2
        ((attempt++))
    done

    log_error "AlertManager is not accessible"
    return 1
}

verify_monitoring_stack() {
    if [[ "$SKIP_VERIFY" == true ]]; then
        log_info "Skipping verification as requested"
        return 0
    fi

    log_info "Running monitoring stack verification..."

    if ./scripts/verify_monitoring_stack.sh; then
        log_success "Monitoring stack verification passed"
        return 0
    else
        log_error "Monitoring stack verification failed"
        echo ""
        log_info "Troubleshooting tips:"
        echo "  1. Check service logs: docker-compose logs <service>"
        echo "  2. Restart failed services: docker-compose restart <service>"
        echo "  3. Run detailed verification: ./scripts/verify_monitoring_stack.sh --detailed"
        echo "  4. Check troubleshooting guide: docs/monitoring_troubleshooting_guide.md"
        return 1
    fi
}

show_success_message() {
    echo ""
    echo "🎉 MONITORING STACK STARTED SUCCESSFULLY! 🎉"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "📊 Service Access URLs:"
    echo "────────────────────────────────"
    echo "Prometheus:      http://localhost:9090"
    echo "Grafana:         http://localhost:3001 (admin/trading_admin)"
    echo "Node Exporter:   http://localhost:9100/metrics"
    echo "AlertManager:    http://localhost:9093"
    echo ""
    echo "📈 Grafana Dashboards:"
    echo "────────────────────"
    echo "System Health:      http://localhost:3001/d/system-health"
    echo "Trading Performance: http://localhost:3001/d/trading-performance"
    echo "API Metrics:         http://localhost:3001/d/api-metrics"
    echo "Data Ingestion:      http://localhost:3001/d/data-ingestion"
    echo "Arbitrage:           http://localhost:3001/d/arbitrage-dashboard"
    echo "Sniper:              http://localhost:3001/d/sniper-dashboard"
    echo "Reliability:         http://localhost:3001/d/reliability-metrics"
    echo ""
    echo "🔍 Next Steps:"
    echo "────────────"
    echo "1. Access Grafana dashboards at: http://localhost:3001"
    echo "2. Login with admin/trading_admin"
    echo "3. Navigate to the Trading Bot folder"
    echo "4. Monitor system health and trading performance"
    echo "5. Check Prometheus targets at: http://localhost:9090/targets"
    echo ""
    echo "📖 Documentation:"
    echo "────────────────"
    echo "Deployment Guide: docs/monitoring_deployment_guide.md"
    echo "Troubleshooting: docs/monitoring_troubleshooting_guide.md"
    echo "Operations: OPERATIONS_RUNBOOK.md"
    echo ""
    echo "💡 Management Commands:"
    echo "──────────────────────"
    echo "Stop monitoring:  docker-compose stop prometheus grafana node-exporter alertmanager"
    echo "Check status:     docker-compose ps"
    echo "View logs:        docker-compose logs -f <service>"
    echo "Verify stack:     ./scripts/verify_monitoring_stack.sh"
    echo ""
    echo "═══════════════════════════════════════════════════════"
}

handle_error() {
    local failed_service=$1
    log_error "Failed to start $failed_service"

    echo ""
    log_info "Troubleshooting steps:"
    echo "1. Check service logs: docker-compose logs $failed_service"
    echo "2. Check container status: docker-compose ps $failed_service"
    echo "3. Inspect container: docker inspect trading-bot-$failed_service"
    echo "4. Check resource usage: docker stats"
    echo "5. Verify port availability: lsof -i :<port>"

    echo ""
    log_info "Would you like to see the service logs? (y/N): "
    read -r -n 1 response
    echo

    if [[ $response =~ ^[Yy]$ ]]; then
        echo ""
        echo "=== $failed_service logs ==="
        docker-compose logs --tail=50 "$failed_service"
        echo "============================="
    fi

    echo ""
    log_info "For more help, see: docs/monitoring_troubleshooting_guide.md"
}

show_help() {
    cat << EOF
MojoRust Trading Bot - Monitoring Stack Orchestration Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --service=<name>       Start only specified service
                          Available: prometheus, grafana, node-exporter, alertmanager
    --skip-verify          Skip verification after starting
    --verbose, -v          Show detailed output during startup
    --help                  Show this help message

EXAMPLES:
    $0                              # Start all monitoring services
    $0 --service=prometheus         # Start only Prometheus
    $0 --service=grafana            # Start only Grafana
    $0 --skip-verify                 # Start without verification
    $0 --verbose                     # Start with detailed output

SERVICES STARTED (in order):
    1. Prometheus      - Metrics collection and storage (port 9090)
    2. Grafana         - Visualization dashboards (port 3001)
    3. Node Exporter   - System metrics collection (port 9100)
    4. AlertManager    - Alert routing and management (port 9093)

DEPENDENCIES:
    - Docker running
    - docker-compose installed
    - Ports 9090, 3001, 9100, 9093 available
    - docker-compose.yml valid

VERIFICATION:
    - Automatic verification of all services
    - Health checks for each service
    - Metrics collection verification
    - Dashboard provisioning verification

DOCUMENTATION:
    - Deployment Guide: docs/monitoring_deployment_guide.md
    - Troubleshooting: docs/monitoring_troubleshooting_guide.md
    - Operations: OPERATIONS_RUNBOOK.md

EOF
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service=*)
                SPECIFIC_SERVICE="${1#*=}"
                shift
                ;;
            --skip-verify)
                SKIP_VERIFY=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_banner

    # Check dependencies
    check_dependencies

    # Check prerequisites
    check_prerequisites

    # Start services
    if [[ -n "$SPECIFIC_SERVICE" ]]; then
        case "$SPECIFIC_SERVICE" in
            "prometheus")
                start_prometheus || handle_error "prometheus"
                ;;
            "grafana")
                start_grafana || handle_error "grafana"
                ;;
            "node-exporter")
                start_node_exporter || handle_error "node-exporter"
                ;;
            "alertmanager")
                start_alertmanager || handle_error "alertmanager"
                ;;
            *)
                log_error "Unknown service: $SPECIFIC_SERVICE"
                echo "Available services: prometheus, grafana, node-exporter, alertmanager"
                exit 1
                ;;
        esac
    else
        # Start all services in order
        start_prometheus || handle_error "prometheus"
        start_grafana || handle_error "grafana"
        start_node_exporter || handle_error "node-exporter"
        start_alertmanager || handle_error "alertmanager"
    fi

    # Verify stack
    if [[ -z "$SPECIFIC_SERVICE" ]]; then
        verify_monitoring_stack
    fi

    # Show success message
    if [[ -z "$SPECIFIC_SERVICE" ]]; then
        show_success_message
    else
        log_success "$SPECIFIC_SERVICE started successfully"
    fi
}

# Set up error handling
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"