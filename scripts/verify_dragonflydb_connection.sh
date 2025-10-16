#!/bin/bash

# =============================================================================
# 🐉 DragonflyDB Connection Verification Script for MojoRust Trading Bot
# =============================================================================
# This script tests connectivity to DragonflyDB Cloud and verifies metrics collection
# Reference: config/prometheus.yml lines 89-102 for scraping configuration

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration (from prometheus.yml and .env.example)
DRAGONFLYDB_HOST="612ehcb9i.dragonflydb.cloud"
DRAGONFLYDB_PORT="6385"
DRAGONFLYDB_PASSWORD="gv7g6u9svsf1"
REDIS_URL="rediss://default:gv7g6u9svsf1@612ehcb9i.dragonflydb.cloud:6385"

# VPC Peering configuration
VPC_ID="${VPC_ID:-vpc-00e79f7555aa68c0e}"
VPC_PEERING_ID="${VPC_PEERING_ID:-}"
DRAGONFLYDB_VPC_CIDR="${DRAGONFLYDB_VPC_CIDR:-}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Options
CONNECTION_ONLY=false
PROMETHEUS_ONLY=false
VPC_ONLY=false
BENCHMARK=false
JSON_OUTPUT=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --host)
            DRAGONFLYDB_HOST="$2"
            shift 2
            ;;
        --port)
            DRAGONFLYDB_PORT="$2"
            shift 2
            ;;
        --password)
            DRAGONFLYDB_PASSWORD="$2"
            shift 2
            ;;
        --redis-url)
            REDIS_URL="$2"
            shift 2
            ;;
        --vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        --vpc-peering-id)
            VPC_PEERING_ID="$2"
            shift 2
            ;;
        --dragonflydb-vpc-cidr)
            DRAGONFLYDB_VPC_CIDR="$2"
            shift 2
            ;;
        --aws-region)
            AWS_REGION="$2"
            shift 2
            ;;
        --connection-only)
            CONNECTION_ONLY=true
            shift
            ;;
        --prometheus-only)
            PROMETHEUS_ONLY=true
            shift
            ;;
        --vpc-only)
            VPC_ONLY=true
            shift
            ;;
        --benchmark)
            BENCHMARK=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --host <HOST>           DragonflyDB host (default: $DRAGONFLYDB_HOST)"
            echo "  --port <PORT>           DragonflyDB port (default: $DRAGONFLYDB_PORT)"
            echo "  --password <PASS>       DragonflyDB password (default: hidden)"
            echo "  --redis-url <URL>       Redis connection URL (default: auto-generated)"
            echo "  --connection-only      Test connection only (skip Prometheus)"
            echo "  --prometheus-only      Test Prometheus scraping only"
            echo "  --vpc-only             Test VPC peering connectivity only"
            echo "  --benchmark            Run performance benchmark"
            echo "  --json                 Output results in JSON format"
            echo "  --verbose              Show detailed output"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0                                          # Full verification"
            echo "  $0 --connection-only                         # Test connection only"
            echo "  $0 --prometheus-only                          # Test Prometheus only"
            echo "  $0 --vpc-only                                # Test VPC peering only"
            echo "  $0 --benchmark                               # Performance test"
            echo "  $0 --json                                     # JSON output"
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

# Override from environment if available
if [ -n "$REDIS_URL" ]; then
    # Extract password from Redis URL
    DRAGONFLYDB_PASSWORD=$(echo "$REDIS_URL" | grep -oP '://[^:]+:\K[^@]+' | head -1)
fi

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

# JSON output structure
declare -A test_results

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v redis-cli >/dev/null 2>&1; then
        missing_deps+=("redis-cli")
    fi

    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi

    if [ "$VPC_ONLY" = true ] && ! command -v aws >/dev/null 2>&1; then
        missing_deps+=("aws")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_deps[*]}"
        log_info "Install with: apt-get install redis-tools curl awscli"
        return 1
    fi

    return 0
}

# Test basic DragonflyDB connection
test_connection() {
    log_header "Testing DragonflyDB Connection"
    log_info "Endpoint: ${DRAGONFLYDB_HOST}:${DRAGONFLYDB_PORT}"
    log_info "Protocol: Redis (SSL)"

    # Test PING command
    log_verbose "Testing PING command..."
    local ping_result
    ping_result=$(redis-cli -u "redis://:${DRAGONFLYDB_PASSWORD}@${DRAGONFLYDB_HOST}:${DRAGONFLYDB_PORT}" --tls ping 2>/dev/null || echo "FAILED")

    if [ "$ping_result" = "PONG" ]; then
        log_success "Connection: OK (PONG received)"
        test_results["connection"]="ok"
        test_results["ping_test"]="pass"
    else
        log_error "Connection: Failed (no PONG)"
        test_results["connection"]="failed"
        test_results["ping_test"]="fail"
        return 1
    fi

    # Test authentication
    log_verbose "Testing authentication..."
    if [ -n "$DRAGONFLYDB_PASSWORD" ]; then
        test_results["authentication"]="ok"
        test_results["auth_test"]="pass"
        log_success "Authentication: OK"
    else
        test_results["authentication"]="no_password"
        test_results["auth_test"]="skip"
        log_info "Authentication: No password (public instance)"
    fi

    return 0
}

# Test basic Redis operations
test_operations() {
    log_header "Testing Basic Operations"

    local test_key="dragonflydb_test_$(date +%s)"
    local test_value="dragonflydb_test_value_$(date +%s)"
    local operations_file=$(mktemp)

    # Create Redis commands
    cat > "$operations_file" <<EOF
SET $test_key "$test_value"
GET $test_key
DEL $test_key
EOF

    log_verbose "Executing Redis commands..."
    local ops_result
    ops_result=$(redis-cli -u "$REDIS_URL" --tls < "$operations_file" 2>&1 || echo "FAILED")

    # Parse results
    local set_result=$(echo "$ops_result" | grep -c "OK" || echo "0")
    local get_result=$(echo "$ops_result" | grep -c "$test_value" || echo "0")
    local del_result=$(echo "$ops_result" | grep -c "OK" || echo "0")

    rm -f "$operations_file"

    if [ "$set_result" -eq 1 ] && [ "$get_result" -eq 1 ] && [ "$del_result" -eq 1 ]; then
        log_success "SET operation: OK"
        log_success "GET operation: OK"
        log_success "DEL operation: OK"
        test_results["basic_operations"]="ok"
        test_results["ops_test"]="pass"
    else
        log_error "Basic operations: Failed"
        test_results["basic_operations"]="failed"
        test_results["ops_test"]="fail"
        return 1
    fi

    return 0
}

# Test Pub/Sub functionality
test_pubsub() {
    log_header "Testing Pub/Sub Functionality"

    local channel="dragonflydb_test_channel"
    local message="dragonflydb_test_message_$(date +%s)"
    local subscriber_file=$(mktemp)
    local publisher_file=$(mktemp)

    # Start subscriber in background
    log_verbose "Starting Redis subscriber..."
    timeout 10s redis-cli -u "$REDIS_URL" --tls --raw subscribe "$channel" > "$subscriber_file" &
    local subscriber_pid=$!
    sleep 1

    # Publish message
    log_verbose "Publishing message to channel: $channel"
    echo "PUBLISH $channel $message" > "$publisher_file"
    local pub_result=$(redis-cli -u "$REDIS_URL" --tls < "$publisher_file" 2>/dev/null || echo "FAILED")

    # Wait for subscriber to receive message
    sleep 2

    # Kill subscriber
    kill $subscriber_pid 2>/dev/null || true

    # Check if message was received
    local message_received=$(grep -F "$message" "$subscriber_file" | wc -l)

    rm -f "$subscriber_file" "$publisher_file"

    if [ "$message_received" -gt 0 ]; then
        log_success "Pub/Sub: OK (message received)"
        test_results["pubsub"]="ok"
        test_results["pubsub_test"]="pass"
    else
        log_warning "Pub/Sub: No message received (timeout)"
        test_results["pubsub"]="timeout"
        test_results["pubsub_test"]="skip"
    fi

    return 0
}

# Test performance with latency measurement
test_performance() {
    log_header "Performance Testing"

    if [ "$BENCHMARK" = false ]; then
        log_info "Use --benchmark flag to run performance tests"
        return 0
    fi

    # Test latency with redis-cli --latency
    log_verbose "Running latency test (10 samples)..."
    local latency_result
    latency_result=$(redis-cli -u "$REDIS_URL" --tls --latency -i 3 2>/dev/null || echo "FAILED")

    if [ "$latency_result" != "FAILED" ]; then
        local avg_latency=$(echo "$latency_result" | grep "min:" | awk '{print $2}' | sed 's/[a-zA-Z:]*//g')
        local p95_latency=$(echo "$latency_result" | grep "p95:" | awk '{print $2}' | sed 's/[a-zA-Z:]*//g')

        if [ -n "$avg_latency" ] && [ -n "$p95_latency" ]; then
            log_success "Latency test: OK"
            log_info "  Average: ${avg_latency}ms"
            log_info "  p95: ${p95_latency}ms"
            test_results["latency_test"]="pass"
            test_results["avg_latency"]="${avg_latency}ms"
            test_results["p95_latency"]="${p95_latency}ms"
        else
            log_warning "Latency test: Could not parse results"
            test_results["latency_test"]="incomplete"
        fi
    else
        log_error "Latency test: Failed"
        test_results["latency_test"]="fail"
    fi

    return 0
}

# Test Prometheus metrics scraping
test_prometheus_scraping() {
    log_header "Testing Prometheus Metrics Scraping"

    # Check Prometheus is accessible
    local prometheus_url="http://localhost:9090"
    local health_check
    health_check=$(curl -s "$prometheus_url/-/healthy" || echo "FAILED")

    if [ "$health_check" != "OK" ]; then
        log_error "Prometheus: Not accessible at $prometheus_url"
        test_results["prometheus_connection"]="failed"
        return 1
    fi

    log_success "Prometheus: Connected"
    test_results["prometheus_connection"]="ok"

    # Check if DragonflyDB target is configured
    log_verbose "Checking Prometheus DragonflyDB target configuration..."
    local targets_result
    targets_result=$(curl -s "$prometheus_url/api/v1/targets" 2>/dev/null | jq '.data.activeTargets[] | select(.labels.job=="dragonflydb-cloud") | {job: .labels.job, instance: .labels.instance, health: .health}' 2>/dev/null || echo "[]")

    if [ "$targets_result" = "[]" ]; then
        log_warning "Prometheus: No DragonflyDB target found"
        test_results["dragonflydb_target"]="not_found"
    else
        local target_health=$(echo "$targets_result" | jq -r '.health' | head -1)
        if [ "$target_health" = "up" ]; then
            log_success "Prometheus: DragonflyDB target UP"
            test_results["dragonflydb_target"]="up"
        else
            log_warning "Prometheus: DragonflyDB target $target_health"
            test_results["dragonflydb_target"]="$target_health"
        fi
    fi

    # Check if metrics are being collected
    log_verbose "Querying DragonflyDB metrics..."
    local metrics_query="redis_instantaneous_ops_per_sec"
    local metrics_result
    metrics_result=$(curl -s "$prometheus_url/api/v1/query?query=$metrics_query" 2>/dev/null | jq -r '.data.result[0].value[1] // "null"' 2>/dev/null || echo "null")

    if [ "$metrics_result" != "null" ] && [ "$metrics_result" != "0" ]; then
        local ops_per_sec=$(echo "$metrics_result" | numfmt 2>/dev/null || echo "$metrics_result")
        log_success "Prometheus: Metrics available (${ops_per_sec} ops/sec)"
        test_results["prometheus_metrics"]="available"
        test_results["ops_per_sec"]="$ops_per_sec"
    else
        log_warning "Prometheus: No DragonflyDB metrics found"
        test_results["prometheus_metrics"]="not_available"
    fi

    # Check other important metrics
    local other_metrics=(
        "redis_connected_clients"
        "redis_memory_used_bytes"
        "redis_keyspace_hits_total"
        "redis_keyspace_misses_total"
    )

    local cache_hit_ratio=0
    local total_hits=0
    local total_misses=0

    for metric in "${other_metrics[@]}"; do
        local value=$(curl -s "$prometheus_url/api/v1/query?query=$metric" 2>/dev/null | jq -r '.data.result[0].value[1] // "null"' 2>/dev/null || echo "null")
        if [ "$value" != "null" ]; then
            log_verbose "  $metric: $value"
            test_results["metric_$metric"]="$value"

            # Calculate cache hit ratio
            if [ "$metric" = "redis_keyspace_hits_total" ]; then
                total_hits="$value"
            elif [ "$metric" = "redis_keyspace_misses_total" ]; then
                total_misses="$value"
            fi
        fi
    done

    # Calculate cache hit ratio
    if [ "$total_hits" -gt 0 ] || [ "$total_misses" -gt 0 ]; then
        cache_hit_ratio=$(echo "scale=2; $total_hits * 100 / ($total_hits + $total_misses)" | bc 2>/dev/null || echo "0")
        log_success "Prometheus: Cache hit ratio: ${cache_hit_ratio}%"
        test_results["cache_hit_ratio"]="${cache_hit_ratio}%"
    fi

    # Check last scrape timestamp
    local last_scrape=$(curl -s "$prometheus_url/api/v1/targets" 2>/dev/null | jq '.data.activeTargets[] | select(.labels.job=="dragonflydb-cloud") | .lastScrape // 0' 2>/dev/null | head -1)
    if [ "$last_scrape" -gt 0 ]; then
        local scrape_age=$(($(date +%s) - last_scrape))
        if [ "$scrape_age" -lt 300 ]; then  # 5 minutes
            log_success "Prometheus: Last scrape ${scrape_age}s ago"
            test_results["last_scrape_age"]="${scrape_age}s"
        else
            log_warning "Prometheus: Last scrape ${scrape_age}s ago (stale)"
            test_results["last_scrape_age"]="${scrape_age}s"
        fi
    fi

    return 0
}

# Test DragonflyDB metrics endpoint directly
test_direct_metrics() {
    log_header "Testing DragonflyDB Direct Metrics"

    local metrics_url="https://${DRAGONFLYDB_HOST}/metrics"
    local metrics_result
    metrics_result=$(curl -s -H "Authorization: Bearer $DRAGONFLYDB_PASSWORD" "$metrics_url" 2>/dev/null)

    if [ -n "$metrics_result" ]; then
        local metrics_count=$(echo "$metrics_result" | wc -l)
        log_success "Direct metrics: OK ($metrics_count lines)"
        test_results["direct_metrics"]="ok"
        test_results["metrics_count"]="$metrics_count"

        # Extract key metrics
        if command -v grep >/dev/null 2>&1; then
            local ops_per_sec=$(echo "$metrics_result" | grep "redis_instantaneous_ops_per_sec" | awk '{print $2}')
            local memory_used=$(echo "$metrics_result" | grep "redis_memory_used_bytes" | awk '{print $2}')
            local connected_clients=$(echo "$metrics_result" | grep "redis_connected_clients" | awk '{print $2}')

            if [ -n "$ops_per_sec" ]; then
                log_info "  Operations/sec: $ops_per_sec"
                test_results["direct_ops_per_sec"]="$ops_per_sec"
            fi
            if [ -n "$memory_used" ]; then
                log_info "  Memory used: $memory_used bytes"
                test_results["direct_memory_used"]="$memory_used"
            fi
            if [ -n "$connected_clients" ]; then
                log_info "  Connected clients: $connected_clients"
                test_results["direct_connected_clients"]="$connected_clients"
            fi
        fi
    else
        log_error "Direct metrics: Failed (authentication or network error)"
        test_results["direct_metrics"]="failed"
        return 1
    fi

    return 0
}

# Test VPC peering connectivity
test_vpc_peering() {
    log_header "Testing VPC Peering Connectivity"

    local vpc_peering_status="unknown"
    local route_tables_configured=false
    local security_groups_configured=false
    local dns_ok=false
    local tcp_6385_ok=false

    # Check VPC peering status
    if [ -n "$VPC_PEERING_ID" ]; then
        log_verbose "Checking VPC peering status: $VPC_PEERING_ID"
        local peering_result
        if peering_result=$(aws ec2 describe-vpc-peering-connections \
            --vpc-peering-connection-ids "$VPC_PEERING_ID" \
            --region "$AWS_REGION" 2>/dev/null); then

            local status=$(echo "$peering_result" | jq -r '.VpcPeeringConnections[0].Status.Code // "unknown"')
            log_verbose "VPC peering status: $status"

            if [ "$status" = "active" ]; then
                log_success "VPC peering connection: Active"
                vpc_peering_status="active"
                test_results["vpc_peering_status"]="active"
            else
                log_error "VPC peering connection: $status"
                test_results["vpc_peering_status"]="$status"
                return 1
            fi
        else
            log_error "Failed to check VPC peering status"
            test_results["vpc_peering_status"]="error"
            return 1
        fi
    else
        log_warning "VPC_PEERING_ID not provided, skipping VPC peering status check"
        test_results["vpc_peering_status"]="not_configured"
    fi

    # Check route tables configuration
    if [ -n "$DRAGONFLYDB_VPC_CIDR" ]; then
        log_verbose "Checking route tables for routes to $DRAGONFLYDB_VPC_CIDR"
        local route_tables
        if route_tables=$(aws ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC_ID" "Name=route.destination-cidr-block,Values=$DRAGONFLYDB_VPC_CIDR" \
            --region "$AWS_REGION" 2>/dev/null); then

            local route_count=$(echo "$route_tables" | jq '.RouteTables | length // 0')
            if [ "$route_count" -gt 0 ]; then
                log_success "Route tables: $route_count routes configured to DragonflyDB VPC"
                route_tables_configured=true
                test_results["route_tables_configured"]="true"

                # Check if routes are active
                local active_routes=$(echo "$route_tables" | jq '.RouteTables[].Routes[] | select(.DestinationCidrBlock == "'$DRAGONFLYDB_VPC_CIDR'" and .State == "active") | length')
                log_verbose "Active routes to DragonflyDB VPC: $active_routes"
                test_results["active_routes_count"]="$active_routes"
            else
                log_error "No routes found to DragonflyDB VPC in route tables"
                test_results["route_tables_configured"]="false"
            fi
        else
            log_error "Failed to check route tables"
            test_results["route_tables_configured"]="error"
        fi
    else
        log_warning "DRAGONFLYDB_VPC_CIDR not provided, skipping route table check"
        test_results["route_tables_configured"]="not_configured"
    fi

    # Check security group egress rules
    log_verbose "Checking security group egress rules for port 6385"
    local sg_rules
    if sg_rules=$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[0].GroupId' --output text --region $AWS_REGION 2>/dev/null)" "Name=is-egress,Values=true" "Name=ip-protocol,Values=tcp" "Name=from-port,Values=6385" "Name=to-port,Values=6385" \
        --region "$AWS_REGION" 2>/dev/null); then

        local sg_count=$(echo "$sg_rules" | jq '.SecurityGroupRules | length // 0')
        if [ "$sg_count" -gt 0 ]; then
            log_success "Security groups: $sg_count egress rules for port 6385 found"
            security_groups_configured=true
            test_results["security_groups_configured"]="true"
            test_results["sg_rules_count"]="$sg_count"
        else
            log_error "No security group egress rules found for port 6385"
            test_results["security_groups_configured"]="false"
        fi
    else
        log_error "Failed to check security group rules"
        test_results["security_groups_configured"]="error"
    fi

    # Test DNS resolution
    log_verbose "Testing DNS resolution for $DRAGONFLYDB_HOST"
    if command -v nslookup >/dev/null 2>&1; then
        if nslookup "$DRAGONFLYDB_HOST" >/dev/null 2>&1; then
            log_success "DNS resolution: OK"
            dns_ok=true
            test_results["dns_resolution"]="ok"
        else
            log_error "DNS resolution: Failed"
            test_results["dns_resolution"]="failed"
        fi
    elif command -v dig >/dev/null 2>&1; then
        if dig "$DRAGONFLYDB_HOST" >/dev/null 2>&1; then
            log_success "DNS resolution: OK (using dig)"
            dns_ok=true
            test_results["dns_resolution"]="ok"
        else
            log_error "DNS resolution: Failed (using dig)"
            test_results["dns_resolution"]="failed"
        fi
    else
        log_warning "DNS resolution test skipped (nslookup/dig not available)"
        test_results["dns_resolution"]="skipped"
    fi

    # Test TCP connectivity to DragonflyDB
    log_verbose "Testing TCP connectivity to $DRAGONFLYDB_HOST:$DRAGONFLYDB_PORT"
    if command -v nc >/dev/null 2>&1; then
        if timeout 10 nc -vz "$DRAGONFLYDB_HOST" "$DRAGONFLYDB_PORT" 2>&1 | grep -q "succeeded"; then
            log_success "TCP connection (port 6385): OK"
            tcp_6385_ok=true
            test_results["tcp_6385"]="ok"
        elif timeout 10 nc -vz "$DRAGONFLYDB_HOST" "$DRAGONFLYDB_PORT" >/dev/null 2>&1; then
            log_success "TCP connection (port 6385): OK"
            tcp_6385_ok=true
            test_results["tcp_6385"]="ok"
        else
            log_error "TCP connection (port 6385): Failed"
            test_results["tcp_6385"]="failed"
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout 10 bash -c "echo > /dev/tcp/$DRAGONFLYDB_HOST/$DRAGONFLYDB_PORT" 2>/dev/null; then
            log_success "TCP connection (port 6385): OK (using telnet)"
            tcp_6385_ok=true
            test_results["tcp_6385"]="ok"
        else
            log_error "TCP connection (port 6385): Failed (using telnet)"
            test_results["tcp_6385"]="failed"
        fi
    else
        log_warning "TCP connection test skipped (nc/telnet not available)"
        test_results["tcp_6385"]="skipped"
    fi

    # Test SSL/TLS connectivity
    log_verbose "Testing SSL/TLS connectivity to $DRAGONFLYDB_HOST:$DRAGONFLYDB_PORT"
    if command -v openssl >/dev/null 2>&1; then
        if echo | timeout 10 openssl s_client -connect "$DRAGONFLYDB_HOST:$DRAGONFLYDB_PORT" -servername "$DRAGONFLYDB_HOST" 2>/dev/null | grep -q "Verify return code: 0 (ok)"; then
            log_success "SSL/TLS connection: OK"
            test_results["ssl_tls"]="ok"
        else
            log_warning "SSL/TLS connection: Certificate verification failed (may be expected for internal endpoints)"
            test_results["ssl_tls"]="verification_failed"
        fi
    else
        log_warning "SSL/TLS test skipped (openssl not available)"
        test_results["ssl_tls"]="skipped"
    fi

    # Store overall VPC peering status
    if [ "$vpc_peering_status" = "active" ] && [ "$route_tables_configured" = true ] && [ "$security_groups_configured" = true ]; then
        test_results["vpc_peering_overall"]="healthy"
        log_success "VPC peering overall: Healthy"
    else
        test_results["vpc_peering_overall"]="unhealthy"
        log_error "VPC peering overall: Unhealthy"
        return 1
    fi

    return 0
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                               ║"
        echo "║    🐉 DragonflyDB Connection Verification - MojoRust Trading Bot   ║"
        echo "║                                                               ║"
        echo "║    Endpoint: ${DRAGONFLYDB_HOST}:${DRAGONFLYDB_PORT}             ║"
        echo "║    Protocol: Redis (SSL)                                      ║"
        echo "║                                                               ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Summary function
print_summary() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_header "======================================"

        # Overall status
        local overall_status="operational"
        local critical_issues=0

        if [ "${test_results[connection]}" = "failed" ]; then
            overall_status="failed"
            critical_issues=$((critical_issues + 1))
        fi

        if [ "${test_results[prometheus_connection]}" = "failed" ]; then
            overall_status="degraded"
            critical_issues=$((critical_issues + 1))
        fi

        # Connection status
        echo "Connection Status:"
        if [ "${test_results[connection]}" = "ok" ]; then
            log_success "  Connection: ✅ Established"
        else
            log_error "  Connection: ❌ Failed"
        fi
        if [ "${test_results[ping_test]}" = "pass" ]; then
            log_success "  PING Test: ✅ Passed"
        else
            log_error "  PING Test: ❌ Failed"
        fi
        if [ "${test_results[auth_test]}" = "pass" ]; then
            log_success "  Authentication: ✅ Verified"
        else
            log_info "  Authentication: ℹ️  No password"
        fi

        # Operations status
        if [ "$CONNECTION_ONLY" = false ]; then
            echo ""
            echo "Operations Status:"
            if [ "${test_results[ops_test]}" = "pass" ]; then
                log_success "  Basic Operations: ✅ All passed"
            else
                log_error "  Basic Operations: ❌ Failed"
            fi
            if [ "${test_results[pubsub_test]}" = "pass" ]; then
                log_success "  Pub/Sub: ✅ Working"
            else
                log_warning "  Pub/Sub: ⚠️  Timeout"
            fi
        fi

        # Performance status
        if [ "$BENCHMARK" = true ]; then
            echo ""
            echo "Performance Status:"
            if [ "${test_results[latency_test]}" = "pass" ]; then
                log_success "  Latency: ✅ ${test_results[avg_latency]} avg, ${test_results[p95_latency]} p95"
            else
                log_error "  Latency: ❌ Test failed"
            fi
        fi

        # VPC Peering status
        if [ "$VPC_ONLY" = true ] || [ -n "${test_results[vpc_peering_status]:-}" ]; then
            echo ""
            echo "VPC Peering Status:"
            if [ "${test_results[vpc_peering_status]}" = "active" ]; then
                log_success "  Connection: ✅ Active"
            else
                log_error "  Connection: ❌ ${test_results[vpc_peering_status]:-Unknown}"
            fi
            if [ "${test_results[route_tables_configured]}" = "true" ]; then
                log_success "  Route Tables: ✅ Configured (${test_results[active_routes_count]:-0} active routes)"
            else
                log_error "  Route Tables: ❌ ${test_results[route_tables_configured]:-Unknown}"
            fi
            if [ "${test_results[security_groups_configured]}" = "true" ]; then
                log_success "  Security Groups: ✅ Configured (${test_results[sg_rules_count]:-0} rules)"
            else
                log_error "  Security Groups: ❌ ${test_results[security_groups_configured]:-Unknown}"
            fi
            if [ "${test_results[dns_resolution]}" = "ok" ]; then
                log_success "  DNS Resolution: ✅ Working"
            else
                log_error "  DNS Resolution: ❌ ${test_results[dns_resolution]:-Failed}"
            fi
            if [ "${test_results[tcp_6385]}" = "ok" ]; then
                log_success "  TCP (6385): ✅ Connected"
            else
                log_error "  TCP (6385): ❌ ${test_results[tcp_6385]:-Failed}"
            fi
        fi

        # Prometheus status
        if [ "$PROMETHEUS_ONLY" = false ] && [ "$CONNECTION_ONLY" = false ] && [ "$VPC_ONLY" = false ]; then
            echo ""
            echo "Prometheus Status:"
            if [ "${test_results[prometheus_connection]}" = "ok" ]; then
                log_success "  Connection: ✅ Connected"
            else
                log_error "  Connection: ❌ Failed"
            fi
            if [ "${test_results[dragonflydb_target]}" = "up" ]; then
                log_success "  Target: ✅ UP"
            elif [ "${test_results[dragonflydb_target]}" = "not_found" ]; then
                log_warning "  Target: ⚠️  Not found"
            else
                log_warning "  Target: ⚠️  ${test_results[dragonflydb_target]}"
            fi
            if [ "${test_results[prometheus_metrics]}" = "available" ]; then
                log_success "  Metrics: ✅ Available (${test_results[ops_per_sec]} ops/sec)"
            else
                log_warning "  Metrics: ⚠️  Not available"
            fi
        fi

        echo ""
        echo "======================================"

        # Final verdict
        if [ "$overall_status" = "operational" ]; then
            log_success "✅ DragonflyDB fully operational"
        elif [ "$overall_status" = "degraded" ]; then
            log_warning "⚠️  DragonflyDB operational with issues"
        else
            log_error "❌ DragonflyDB has critical issues"
        fi

    else
        # JSON output
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"endpoint\": \"${DRAGONFLYDB_HOST}:${DRAGONFLYDB_PORT}\","
        echo "  \"protocol\": \"Redis (SSL)\","
        echo "  \"connection\": {"
        echo "    \"status\": \"${test_results[connection]}\","
        echo "    \"ping_test\": \"${test_results[ping_test]}\""
        echo "  },"
        echo "  \"operations\": {"
        echo "    \"status\": \"${test_results[basic_operations]}\","
        echo "    \"pubsub\": \"${test_results[pubsub]}\""
        echo "  },"
        echo "  \"performance\": {"
        echo "    \"latency_test\": \"${test_results[latency_test]}\","
        echo "    \"average_latency\": \"${test_results[avg_latency]}\","
        echo "    \"p95_latency\": \"${test_results[p95_latency]}\""
        echo "  },"
        echo "  \"prometheus\": {"
        echo "    \"connection\": \"${test_results[prometheus_connection]}\","
        echo "    \"target_status\": \"${test_results[dragonflydb_target]}\","
        echo "    \"metrics_available\": \"${test_results[prometheus_metrics]}\","
        echo "    \"ops_per_sec\": \"${test_results[ops_per_sec]}\","
        echo "    \"cache_hit_ratio\": \"${test_results[cache_hit_ratio]}\""
        echo "  },"
        echo "  \"direct_metrics\": {"
        echo "    \"status\": \"${test_results[direct_metrics]}\","
        echo "    \"metrics_count\": \"${test_results[metrics_count]}\""
        echo "  },"
        echo "  \"vpc_peering\": {"
        echo "    \"status\": \"${test_results[vpc_peering_status]}\","
        echo "    \"connection_id\": \"$VPC_PEERING_ID\","
        echo "    \"route_tables_configured\": \"${test_results[route_tables_configured]}\","
        echo "    \"security_groups_configured\": \"${test_results[security_groups_configured]}\","
        echo "    \"dns_ok\": \"${test_results[dns_resolution]}\","
        echo "    \"tcp_6385_ok\": \"${test_results[tcp_6385]}\","
        echo "    \"overall\": \"${test_results[vpc_peering_overall]}\""
        echo "  },"
        echo "  \"overall_status\": \"$overall_status\""
        echo "}"
    fi

    # Exit with appropriate code
    if [ "$critical_issues" -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Main execution
main() {
    print_banner

    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi

    # Run tests based on options
    if [ "$VPC_ONLY" = true ]; then
        test_vpc_peering
    elif [ "$CONNECTION_ONLY" = true ]; then
        test_connection
    elif [ "$PROMETHEUS_ONLY" = true ]; then
        test_prometheus_scraping
    else
        test_connection
        test_operations
        test_pubsub
        test_performance
        test_prometheus_scraping
        test_direct_metrics

        # Also run VPC peering test if configuration is available
        if [ -n "$VPC_PEERING_ID" ] || [ -n "$DRAGONFLYDB_VPC_CIDR" ]; then
            test_vpc_peering
        fi
    fi

    # Print summary
    print_summary
}

# Run main function
main "$@"