#!/bin/bash

# =============================================================================
# MojoRust Trading Bot - Monitoring Stack Verification Script
# =============================================================================
# This script verifies that all monitoring services are properly configured
# and operational, including Prometheus, Grafana, Node Exporter, and AlertManager

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
PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3001"
NODE_EXPORTER_URL="http://localhost:9100"
ALERTMANAGER_URL="http://localhost:9093"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="trading_admin"

EXPECTED_TARGETS=("trading-bot" "prometheus" "node-exporter" "data-consumer" "cadvisor" "alertmanager")
EXPECTED_DASHBOARDS=("system-health" "trading-performance" "api-metrics" "ingestion-pipeline" "arbitrage-dashboard" "sniper-trading-dashboard" "reliability-metrics")

# Output mode flags
JSON_OUTPUT=false
DETAILED_OUTPUT=false
SPECIFIC_CHECK=""

# =============================================================================
# Functions
# =============================================================================

check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    # Check for jq
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
        log_error "jq is not installed"
    else
        log_detail "jq is available: $(jq --version)"
    fi

    # Check for curl
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
        log_error "curl is not installed"
    else
        log_detail "curl is available: $(curl --version | head -1)"
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
    echo "║    📊 MONITORING STACK VERIFICATION SCRIPT 📊              ║"
    echo "║                                                              ║"
    echo "║    Verifying Prometheus, Grafana, Node Exporter & more       ║"
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
    if [[ "$DETAILED_OUTPUT" == true ]]; then
        echo -e "${BLUE}[DETAIL]${NC} $1"
    fi
}

check_prometheus_health() {
    log_info "Checking Prometheus health..."

    local prometheus_healthy=true

    # Check if Prometheus is accessible
    if ! curl -sf "$PROMETHEUS_URL/-/healthy" >/dev/null 2>&1; then
        log_error "Prometheus is not accessible at $PROMETHEUS_URL"
        prometheus_healthy=false
    else
        log_success "Prometheus is accessible"
    fi

    # Check Prometheus readiness
    if ! curl -sf "$PROMETHEUS_URL/-/ready" >/dev/null 2>&1; then
        log_warning "Prometheus is not ready yet"
        prometheus_healthy=false
    else
        log_success "Prometheus is ready"
    fi

    # Get Prometheus version
    if prometheus_version=$(curl -s "$PROMETHEUS_URL/api/v1/status/buildinfo" | jq -r '.data.version' 2>/dev/null); then
        log_detail "Prometheus version: $prometheus_version"
    else
        log_warning "Could not get Prometheus version"
    fi

    # Check storage retention - try multiple endpoints
    local retention=""

    # Try runtimeinfo endpoint first
    if retention=$(curl -s "$PROMETHEUS_URL/api/v1/status/runtimeinfo" | jq -r '.data.storageRetention' 2>/dev/null); then
        log_detail "Storage retention: $retention"
    else
        # Try flags endpoint as fallback
        if retention=$(curl -s "$PROMETHEUS_URL/api/v1/status/flags" | jq -r '.data[] | select(.flag == "storage.tsdb.retention.time") | .value' 2>/dev/null); then
            log_detail "Storage retention (from flags): $retention"
        else
            log_warning "Could not get storage retention info from runtimeinfo or flags endpoints"
            log_detail "This may be expected for older Prometheus versions or different configurations"
        fi
    fi

    if [[ "$prometheus_healthy" == true ]]; then
        return 0
    else
        return 1
    fi
}

verify_prometheus_targets() {
    log_info "Verifying Prometheus targets..."

    local targets_json
    if ! targets_json=$(curl -s "$PROMETHEUS_URL/api/v1/targets"); then
        log_error "Failed to fetch Prometheus targets"
        return 1
    fi

    local healthy_targets=0
    local total_targets=0
    local missing_targets=()

    echo "Target Status:"
    echo "============="
    printf "%-20s %-25s %-10s %-20s\n" "JOB" "INSTANCE" "STATE" "LAST SCRAPE"
    echo "----------------------------------------------------------------------------"

    for target in "${EXPECTED_TARGETS[@]}"; do
        local target_info
        target_info=$(echo "$targets_json" | jq -r --arg job "$target" '.data.activeTargets[] | select(.labels.job == $job)')

        if [[ -n "$target_info" ]]; then
            local instance=$(echo "$target_info" | jq -r '.labels.instance // "unknown"')
            local state=$(echo "$target_info" | jq -r '.health')
            local last_scrape=$(echo "$target_info" | jq -r '.lastScrape // "never"')

            if [[ "$state" == "up" ]]; then
                printf "%-20s %-25s ${GREEN}%-10s${NC} %-20s\n" "$target" "$instance" "$state" "$last_scrape"
                ((healthy_targets++))
            else
                printf "%-20s %-25s ${RED}%-10s${NC} %-20s\n" "$target" "$instance" "$state" "$last_scrape"
            fi
            ((total_targets++))
        else
            printf "%-20s %-25s ${RED}%-10s${NC} %-20s\n" "$target" "MISSING" "DOWN" "never"
            missing_targets+=("$target")
            ((total_targets++))
        fi
    done

    echo ""
    log_detail "Total targets: $total_targets"
    log_detail "Healthy targets: $healthy_targets"

    if [[ ${#missing_targets[@]} -gt 0 ]]; then
        log_warning "Missing targets: ${missing_targets[*]}"
        return 1
    fi

    if [[ $healthy_targets -eq $total_targets ]]; then
        log_success "All Prometheus targets are healthy"
        return 0
    else
        log_error "Some Prometheus targets are down"
        return 1
    fi
}

verify_prometheus_metrics() {
    log_info "Verifying Prometheus metrics collection..."

    local metrics_count=0
    local trading_metrics_available=false

    # Count total metrics
    if metrics_count=$(curl -s "$PROMETHEUS_URL/api/v1/label/__name__/values" | jq '.data | length' 2>/dev/null); then
        log_detail "Total metrics available: $metrics_count"
    else
        log_error "Could not get metrics count from Prometheus"
        return 1
    fi

    # Check for key trading bot metrics
    local trading_metrics=("trading_bot_cpu_usage" "trading_bot_memory_usage" "trading_bot_total_pnl" "trading_bot_win_rate" "trading_bot_total_trades")

    echo "Trading Bot Metrics Check:"
    echo "=========================="

    for metric in "${trading_metrics[@]}"; do
        if curl -s "$PROMETHEUS_URL/api/v1/query?query=$metric" | jq -e '.data.result' >/dev/null 2>&1; then
            local result_count=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$metric" | jq '.data.result | length')
            if [[ $result_count -gt 0 ]]; then
                printf "%-30s ${GREEN}%-10s${NC}\n" "$metric" "AVAILABLE"
                trading_metrics_available=true
            else
                printf "%-30s ${YELLOW}%-10s${NC}\n" "$metric" "NO DATA"
            fi
        else
            printf "%-30s ${RED}%-10s${NC}\n" "$metric" "MISSING"
        fi
    done

    # Check for system metrics
    local system_metrics=("node_cpu_seconds_total" "node_memory_MemAvailable_bytes" "container_cpu_usage_seconds_total")

    echo ""
    echo "System Metrics Check:"
    echo "===================="

    for metric in "${system_metrics[@]}"; do
        if curl -s "$PROMETHEUS_URL/api/v1/query?query=$metric" | jq -e '.data.result' >/dev/null 2>&1; then
            printf "%-30s ${GREEN}%-10s${NC}\n" "$metric" "AVAILABLE"
        else
            printf "%-30s ${RED}%-10s${NC}\n" "$metric" "MISSING"
        fi
    done

    if [[ "$trading_metrics_available" == true && $metrics_count -gt 0 ]]; then
        log_success "Prometheus is collecting metrics"
        return 0
    else
        log_error "Prometheus is not collecting required metrics"
        return 1
    fi
}

check_grafana_health() {
    log_info "Checking Grafana health..."

    local grafana_healthy=true

    # Check if Grafana is accessible
    if ! curl -sf "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
        log_error "Grafana is not accessible at $GRAFANA_URL"
        grafana_healthy=false
    else
        log_success "Grafana is accessible"
    fi

    # Get Grafana version
    if grafana_version=$(curl -s "$GRAFANA_URL/api/health" | jq -r '.version' 2>/dev/null); then
        log_detail "Grafana version: $grafana_version"
    else
        log_warning "Could not get Grafana version"
    fi

    # Check database status
    if db_status=$(curl -s "$GRAFANA_URL/api/health" | jq -r '.database' 2>/dev/null); then
        if [[ "$db_status" == "ok" ]]; then
            log_detail "Grafana database: $db_status"
        else
            log_warning "Grafana database status: $db_status"
            grafana_healthy=false
        fi
    fi

    # Test authentication
    if ! curl -sf -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/org" >/dev/null 2>&1; then
        log_error "Grafana authentication failed"
        grafana_healthy=false
    else
        log_success "Grafana authentication successful"
    fi

    if [[ "$grafana_healthy" == true ]]; then
        return 0
    else
        return 1
    fi
}

verify_grafana_datasources() {
    log_info "Verifying Grafana datasources..."

    local datasources_json
    if ! datasources_json=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/datasources"); then
        log_error "Failed to fetch Grafana datasources"
        return 1
    fi

    local datasource_count=$(echo "$datasources_json" | jq 'length')
    local healthy_datasources=0

    echo "Grafana Datasources:"
    echo "===================="
    printf "%-15s %-15s %-10s %-10s\n" "NAME" "TYPE" "DEFAULT" "HEALTH"
    echo "------------------------------------------------"

    # Check for expected datasources
    local expected_datasources=("Prometheus" "TimescaleDB" "Loki" "AlertManager")

    for ds_name in "${expected_datasources[@]}"; do
        local ds_info
        ds_info=$(echo "$datasources_json" | jq -r --arg name "$ds_name" '.[] | select(.name == $name)')

        if [[ -n "$ds_info" ]]; then
            local type=$(echo "$ds_info" | jq -r '.type')
            local is_default=$(echo "$ds_info" | jq -r '.isDefault')
            local id=$(echo "$ds_info" | jq -r '.id')
            local uid=$(echo "$ds_info" | jq -r '.uid')

            # Test datasource connectivity
            local health_check="UNKNOWN"
            if [[ "$type" == "prometheus" ]]; then
                if curl -sf -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/datasources/proxy/$id/api/v1/query?query=up" >/dev/null 2>&1; then
                    health_check="OK"
                    ((healthy_datasources++))
                else
                    health_check="ERROR"
                fi
            else
                # For non-Prometheus datasources, just check if they exist
                health_check="PRESENT"
                ((healthy_datasources++))
            fi

            local default_status="No"
            [[ "$is_default" == "true" ]] && default_status="Yes"

            printf "%-15s %-15s %-10s %-10s\n" "$ds_name" "$type" "$default_status" "$health_check"
        else
            printf "%-15s %-15s %-10s ${RED}%-10s${NC}\n" "$ds_name" "MISSING" "No" "ERROR"
        fi
    done

    echo ""
    log_detail "Total datasources: $datasource_count"
    log_detail "Healthy datasources: $healthy_datasources"

    if [[ $healthy_datasources -gt 0 ]]; then
        log_success "Grafana datasources are configured"
        return 0
    else
        log_error "No healthy Grafana datasources found"
        return 1
    fi
}

verify_grafana_dashboards() {
    log_info "Verifying Grafana dashboards..."

    local dashboards_json
    if ! dashboards_json=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/search?type=dash-db"); then
        log_error "Failed to fetch Grafana dashboards"
        return 1
    fi

    local dashboard_count=$(echo "$dashboards_json" | jq 'length')
    local loaded_dashboards=0
    local missing_dashboards=()

    echo "Grafana Dashboards:"
    echo "==================="
    printf "%-25s %-15s %-15s %-40s\n" "TITLE" "UID" "FOLDER" "URL"
    echo "--------------------------------------------------------------------------------"

    for expected_dashboard_uid in "${EXPECTED_DASHBOARDS[@]}"; do
        local dashboard_info
        dashboard_info=$(echo "$dashboards_json" | jq -r --arg uid "$expected_dashboard_uid" '.[] | select(.uid == $uid)')

        if [[ -n "$dashboard_info" ]]; then
            local title=$(echo "$dashboard_info" | jq -r '.title')
            local uid=$(echo "$dashboard_info" | jq -r '.uid')
            local folder=$(echo "$dashboard_info" | jq -r '.folderTitle // "General"')
            local url=$(echo "$dashboard_info" | jq -r '.url')

            printf "%-25s %-15s %-15s %-40s\n" "$title" "$uid" "$folder" "$GRAFANA_URL$url"
            ((loaded_dashboards++))
        else
            printf "%-25s %-15s %-15s ${RED}%-40s${NC}\n" "$expected_dashboard_uid" "MISSING" "N/A" "N/A"
            missing_dashboards+=("$expected_dashboard_uid")
        fi
    done

    echo ""
    log_detail "Total dashboards found: $dashboard_count"
    log_detail "Expected dashboards loaded: $loaded_dashboards"

    if [[ ${#missing_dashboards[@]} -gt 0 ]]; then
        log_warning "Missing dashboards: ${missing_dashboards[*]}"
        echo ""
        log_info "To import missing dashboards, run:"
        echo "  ./scripts/import_grafana_dashboards.sh"
        return 1
    else
        log_success "All expected Grafana dashboards are loaded"
        return 0
    fi
}

check_node_exporter_health() {
    log_info "Checking Node Exporter health..."

    local node_exporter_healthy=true

    # Check if Node Exporter is accessible
    if ! curl -sf "$NODE_EXPORTER_URL/metrics" >/dev/null 2>&1; then
        log_error "Node Exporter is not accessible at $NODE_EXPORTER_URL/metrics"
        node_exporter_healthy=false
    else
        log_success "Node Exporter is accessible"
    fi

    # Verify Node Exporter is collecting metrics
    local node_metrics_count
    if node_metrics_count=$(curl -s "$NODE_EXPORTER_URL/metrics" | grep -c "^node_" 2>/dev/null); then
        log_detail "Node Exporter metrics count: $node_metrics_count"

        if [[ $node_metrics_count -lt 50 ]]; then
            log_warning "Node Exporter has fewer metrics than expected"
            node_exporter_healthy=false
        fi
    else
        log_error "Could not count Node Exporter metrics"
        node_exporter_healthy=false
    fi

    # Check for key system metrics
    local key_metrics=("node_cpu_seconds_total" "node_memory_MemTotal_bytes" "node_filesystem_avail_bytes")

    echo "Key Node Exporter Metrics:"
    echo "=========================="

    for metric in "${key_metrics[@]}"; do
        if curl -s "$NODE_EXPORTER_URL/metrics" | grep -q "^$metric"; then
            # Get a sample value
            local sample_value=$(curl -s "$NODE_EXPORTER_URL/metrics" | grep "^$metric" | head -1 | cut -d' ' -f2)
            printf "%-30s %-15s\n" "$metric" "$sample_value"
        else
            printf "%-30s ${RED}%-15s${NC}\n" "$metric" "MISSING"
            node_exporter_healthy=false
        fi
    done

    if [[ "$node_exporter_healthy" == true ]]; then
        log_success "Node Exporter is healthy"
        return 0
    else
        log_error "Node Exporter has issues"
        return 1
    fi
}

check_docker_services() {
    log_info "Checking Docker services status..."

    local services_healthy=true
    local monitoring_services=("prometheus" "grafana" "node-exporter" "alertmanager")

    echo "Docker Services Status:"
    echo "======================="
    printf "%-20s %-15s %-15s %-15s\n" "SERVICE" "STATE" "HEALTH" "UPTIME"
    echo "---------------------------------------------------------------"

    for service in "${monitoring_services[@]}"; do
        local container_name="trading-bot-$service"
        local state="DOWN"
        local health="UNKNOWN"
        local uptime="N/A"

        if docker ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; then
            state="UP"

            # Get health status
            if health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null); then
                health="$health_status"
            else
                health="N/A"
            fi

            # Get uptime
            if uptime_seconds=$(docker inspect --format='{{.State.StartedAt}}' "$container_name" 2>/dev/null); then
                uptime=$(date -d "$uptime_seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Unknown")
            fi
        fi

        # Color code the output
        if [[ "$state" == "UP" && "$health" == "healthy" ]]; then
            printf "%-20s ${GREEN}%-15s${NC} ${GREEN}%-15s${NC} %-15s\n" "$service" "$state" "$health" "$uptime"
        elif [[ "$state" == "UP" ]]; then
            printf "%-20s ${YELLOW}%-15s${NC} ${YELLOW}%-15s${NC} %-15s\n" "$service" "$state" "$health" "$uptime"
        else
            printf "%-20s ${RED}%-15s${NC} ${RED}%-15s${NC} %-15s\n" "$service" "$state" "$health" "$uptime"
            services_healthy=false
        fi
    done

    if [[ "$services_healthy" == true ]]; then
        log_success "All Docker services are running"
        return 0
    else
        log_error "Some Docker services are not running properly"
        return 1
    fi
}

run_all_checks() {
    local checks_passed=0
    local checks_failed=0
    local check_results=()

    # Initialize check results
    local prometheus_healthy=false
    local targets_healthy=false
    local metrics_healthy=false
    local grafana_healthy=false
    local datasources_healthy=false
    local dashboards_healthy=false
    local node_exporter_healthy=false
    local docker_healthy=false

    if [[ -n "$SPECIFIC_CHECK" ]]; then
        case "$SPECIFIC_CHECK" in
            "prometheus")
                if check_prometheus_health; then
                    prometheus_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "targets")
                if verify_prometheus_targets; then
                    targets_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "metrics")
                if verify_prometheus_metrics; then
                    metrics_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "grafana")
                if check_grafana_health; then
                    grafana_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "datasources")
                if verify_grafana_datasources; then
                    datasources_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "dashboards")
                if verify_grafana_dashboards; then
                    dashboards_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "node-exporter")
                if check_node_exporter_health; then
                    node_exporter_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            "docker")
                if check_docker_services; then
                    docker_healthy=true
                    ((checks_passed++))
                else
                    ((checks_failed++))
                fi
                ;;
            *)
                log_error "Unknown check: $SPECIFIC_CHECK"
                echo "Available checks: prometheus, targets, metrics, grafana, datasources, dashboards, node-exporter, docker"
                exit 1
                ;;
        esac
    else
        # Run all checks and track individual results
        if check_prometheus_health; then
            prometheus_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if verify_prometheus_targets; then
            targets_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if verify_prometheus_metrics; then
            metrics_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if check_grafana_health; then
            grafana_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if verify_grafana_datasources; then
            datasources_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if verify_grafana_dashboards; then
            dashboards_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if check_node_exporter_health; then
            node_exporter_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi

        if check_docker_services; then
            docker_healthy=true
            ((checks_passed++))
        else
            ((checks_failed++))
        fi
    fi

    if [[ "$JSON_OUTPUT" == true ]]; then
        # Generate valid JSON with explicit boolean values
        jq -n \
            --argjson prometheus "$prometheus_healthy" \
            --argjson targets "$targets_healthy" \
            --argjson metrics "$metrics_healthy" \
            --argjson grafana "$grafana_healthy" \
            --argjson datasources "$datasources_healthy" \
            --argjson dashboards "$dashboards_healthy" \
            --argjson node_exporter "$node_exporter_healthy" \
            --argjson docker "$docker_healthy" \
            --arg prometheus_url "$PROMETHEUS_URL" \
            --arg grafana_url "$GRAFANA_URL" \
            --arg grafana_user "$GRAFANA_USER" \
            --arg grafana_password "$GRAFANA_PASSWORD" \
            --arg node_exporter_url "$NODE_EXPORTER_URL/metrics" \
            --argjson total_checks $((checks_passed + checks_failed)) \
            --argjson passed $checks_passed \
            --argjson failed $checks_failed \
            --argjson overall_status $([[ $checks_failed -eq 0 ]] && echo true || echo false) \
            '{
                "services": {
                    "prometheus": {
                        "healthy": $prometheus,
                        "url": $prometheus_url
                    },
                    "targets": {
                        "healthy": $targets
                    },
                    "metrics": {
                        "healthy": $metrics
                    },
                    "grafana": {
                        "healthy": $grafana,
                        "url": $grafana_url,
                        "credentials": ($grafana_user + "/" + $grafana_password)
                    },
                    "datasources": {
                        "healthy": $datasources
                    },
                    "dashboards": {
                        "healthy": $dashboards
                    },
                    "node_exporter": {
                        "healthy": $node_exporter,
                        "url": $node_exporter_url
                    },
                    "docker": {
                        "healthy": $docker
                    }
                },
                "summary": {
                    "total_checks": $total_checks,
                    "passed": $passed,
                    "failed": $failed,
                    "overall_status": $overall_status
                },
                "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            }'
    else
        print_summary_report $checks_passed $checks_failed
    fi

    return $checks_failed
}

print_summary_report() {
    local passed=$1
    local failed=$2
    local total=$((passed + failed))

    echo ""
    echo "═════════════════════════════════════════════════════════════════"
    echo "                    VERIFICATION SUMMARY"
    echo "═════════════════════════════════════════════════════════════════"

    if [[ $failed -eq 0 ]]; then
        echo -e "${GREEN}🎉 OVERALL STATUS: PASS${NC}"
    else
        echo -e "${RED}❌ OVERALL STATUS: FAIL${NC}"
    fi

    echo ""
    echo "Checks performed: $total"
    echo "Passed: $passed"
    echo "Failed: $failed"

    echo ""
    echo "Service Access URLs:"
    echo "────────────────────"
    echo "Prometheus:      $PROMETHEUS_URL"
    echo "Grafana:         $GRAFANA_URL ($GRAFANA_USER/$GRAFANA_PASSWORD)"
    echo "Node Exporter:   $NODE_EXPORTER_URL/metrics"
    echo "AlertManager:    $ALERTMANAGER_URL"

    echo ""
    echo "Next Steps:"
    echo "──────────"
    if [[ $failed -eq 0 ]]; then
        echo "✅ All monitoring services are operational"
        echo "📊 Access Grafana dashboards at: $GRAFANA_URL"
        echo "🔍 Monitor metrics at: $PROMETHEUS_URL"
        echo "📖 For detailed guide: docs/monitoring_deployment_guide.md"
    else
        echo "❌ Some monitoring services need attention"
        echo "🔧 Check service logs: docker-compose logs <service>"
        echo "📖 Troubleshooting guide: docs/monitoring_troubleshooting_guide.md"
        echo "🔄 Restart services: docker-compose restart <service>"
    fi

    echo "═════════════════════════════════════════════════════════════════"
}

show_help() {
    cat << EOF
MojoRust Trading Bot - Monitoring Stack Verification Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --json                  Output results in JSON format
    --detailed              Show detailed output
    --check=<service>       Run only specific check
                            Available: prometheus, targets, metrics, grafana, datasources, dashboards, node-exporter, docker
    --help                  Show this help message

EXAMPLES:
    $0                              # Run all verification checks
    $0 --json                       # Output in JSON format
    $0 --detailed                   # Show detailed output
    $0 --check=prometheus           # Check only Prometheus
    $0 --check=dashboards           # Check only Grafana dashboards

SERVICES VERIFIED:
    - Prometheus (metrics collection and storage)
    - Grafana (visualization and dashboards)
    - Node Exporter (system metrics)
    - AlertManager (alert routing)
    - Docker services health
    - Metrics collection from trading bot

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
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --detailed)
                DETAILED_OUTPUT=true
                shift
                ;;
            --check=*)
                SPECIFIC_CHECK="${1#*=}"
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

    # Run verification checks
    run_all_checks
    local exit_code=$?

    exit $exit_code
}

# Run main function
main "$@"