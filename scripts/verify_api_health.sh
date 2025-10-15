#!/bin/bash

# =============================================================================
# 🔍 API Health Verification Script for MojoRust Trading Bot
# =============================================================================
# This script tests all health endpoints exposed by the trading bot after Docker deployment
# Reference: python/health_api.py lines 330-773 for endpoint definitions

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
SERVER="localhost"
PORT="8082"
TIMEOUT=10
JSON_OUTPUT=false
SPECIFIC_ENDPOINT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            SERVER="$2"
            shift 2
            ;;
        --port)
            PORT="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --endpoint)
            SPECIFIC_ENDPOINT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --server <HOST>      Server host (default: localhost)"
            echo "  --port <PORT>        Server port (default: 8082)"
            echo "  --timeout <SECONDS> Request timeout (default: 10)"
            echo "  --json               Output results in JSON format"
            echo "  --endpoint <PATH>    Test specific endpoint only"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0                                    # Test localhost:8082"
            echo "  $0 --server 38.242.239.150        # Test remote server"
            echo "  $0 --endpoint /health               # Test health endpoint only"
            echo "  $0 --json                          # Output JSON for automation"
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

# Base URL
BASE_URL="http://${SERVER}:${PORT}"

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

# JSON output structure
declare -A results
declare -a endpoints_tested

# Test function
test_endpoint() {
    local endpoint="$1"
    local description="$2"
    local expected_status="${3:-200}"
    local required_fields="$4"

    local url="${BASE_URL}${endpoint}"
    local status_code
    local response_body
    local test_passed=false

    log_info "Testing $description: $url"

    # Make HTTP request
    if [ "$JSON_OUTPUT" = true ]; then
        status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" "$url" 2>/dev/null || echo "000")
        response_body=$(curl -s --connect-timeout "$TIMEOUT" "$url" 2>/dev/null || echo "")
    else
        status_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" "$url" 2>/dev/null || echo "000")
        response_body=$(curl -s --connect-timeout "$TIMEOUT" "$url" 2>/dev/null || echo "")
    fi

    # Check HTTP status
    if [ "$status_code" = "$expected_status" ]; then
        # Parse JSON response if we have jq
        if command -v jq >/dev/null 2>&1 && [ -n "$response_body" ]; then
            # Validate required fields
            local field_missing=""
            if [ -n "$required_fields" ]; then
                IFS=',' read -ra fields <<< "$required_fields"
                for field in "${fields[@]}"; do
                    field=$(echo "$field" | xargs) # trim whitespace
                    if ! echo "$response_body" | jq -e ".$field" >/dev/null 2>&1; then
                        field_missing="$field"
                        break
                    fi
                done
            fi

            if [ -z "$field_missing" ]; then
                test_passed=true
                log_success "$description: OK"

                # Extract relevant information
                case "$endpoint" in
                    "/health")
                        local status=$(echo "$response_body" | jq -r '.status // "unknown"')
                        local uptime=$(echo "$response_body" | jq -r '.uptime // 0')
                        log_info "  Status: $status (uptime: ${uptime}s)"
                        results["health_status"]="$status"
                        results["health_uptime"]="$uptime"
                        ;;
                    "/ready")
                        local ready=$(echo "$response_body" | jq -r '.ready // false')
                        local database=$(echo "$response_body" | jq -r '.checks.database // false')
                        local redis=$(echo "$response_body" | jq -r '.checks.redis // false')
                        local apis=$(echo "$response_body" | jq -r '.checks.apis // false')
                        log_info "  Ready: $ready (database: $database, redis: $redis, apis: $apis)"
                        results["ready_status"]="$ready"
                        ;;
                    "/metrics")
                        local metrics_count=$(echo "$response_body" | wc -l)
                        log_info "  Metrics exported: $metrics_count lines"
                        results["metrics_count"]="$metrics_count"
                        ;;
                    "/arbitrage/status")
                        local running=$(echo "$response_body" | jq -r '.is_running // false')
                        local opportunities=$(echo "$response_body" | jq -r '.opportunities_available // 0')
                        log_info "  Arbitrage: $running (opportunities: $opportunities)"
                        results["arbitrage_running"]="$running"
                        results["arbitrage_opportunities"]="$opportunities"
                        ;;
                    "/arbitrage/metrics")
                        local total_opportunities=$(echo "$response_body" | jq -r '.total_opportunities_detected // 0')
                        local executed_trades=$(echo "$response_body" | jq -r '.executed_trades // 0')
                        local success_rate=$(echo "$response_body" | jq -r '.success_rate // 0')
                        log_info "  Opportunities: $total_opportunities, Executed: $executed_trades, Success: ${success_rate}%"
                        results["arbitrage_opportunities_total"]="$total_opportunities"
                        results["arbitrage_executed_trades"]="$executed_trades"
                        results["arbitrage_success_rate"]="$success_rate"
                        ;;
                esac
            else
                log_error "$description: Missing required field: $field_missing"
                results["${endpoint//\//}_error"]="Missing field: $field_missing"
            fi
        else
            # If no jq, just check if response is not empty
            if [ -n "$response_body" ]; then
                test_passed=true
                log_success "$description: OK"
                results["${endpoint//\//}_status"]="ok"
            else
                log_error "$description: Empty response"
                results["${endpoint//\//}_error"]="Empty response"
            fi
        fi
    else
        log_error "$description: HTTP $status_code (expected $expected_status)"
        results["${endpoint//\//}_status_code"]="$status_code"
    fi

    # Store result
    if [ "$test_passed" = true ]; then
        results["${endpoint//\//}_result"]="pass"
    else
        results["${endpoint//\//}_result"]="fail"
    fi

    endpoints_tested+=("$endpoint")
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                               ║"
        echo "║    🔍 API Health Verification - MojoRust Trading Bot          ║"
        echo "║                                                               ║"
        echo "║    Server: $SERVER:$PORT                                     ║"
        echo "║                                                               ║"
        echo "╚═════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Summary function
print_summary() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_header "=========================="

        local passed=0
        local total=${#endpoints_tested[@]}

        for endpoint in "${endpoints_tested[@]}"; do
            if [ "${results[${endpoint//\//}_result]}" = "pass" ]; then
                ((passed++))
            fi
        done

        if [ "$passed" -eq "$total" ]; then
            log_success "✅ All checks passed ($passed/$total)"
        else
            log_error "❌ Some checks failed ($passed/$total)"
        fi

        echo ""
        log_info "Results Summary:"
        for endpoint in "${endpoints_tested[@]}"; do
            local result="${results[${endpoint//\//}_result]}"
            local symbol="❓"
            if [ "$result" = "pass" ]; then
                symbol="✅"
            elif [ "$result" = "fail" ]; then
                symbol="❌"
            fi
            echo "  $symbol $endpoint"
        done

    else
        # JSON output
        echo "{"
        echo "  \"server\": \"$SERVER:$PORT\","
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"total_checks\": ${#endpoints_tested[@]},"
        echo "  \"passed\": $passed,"
        echo "  \"results\": {"
        local first=true
        for endpoint in "${endpoints_tested[@]}"; do
            if [ "$first" = false ]; then
                echo ","
            fi
            echo -n "    \"${endpoint//\//}\": {"
            echo -n "\"result\": \"${results[${endpoint//\//}_result]}\""

            # Add additional results
            for key in "${!results[@]}"; do
                if [[ "$key" == "${endpoint//\//}_"* ]]; then
                    echo -n ",\"$key\": \"${results[$key]}\""
                fi
            done

            echo -n "}"
            first=false
        done
        echo ""
        echo "  }"
        echo "}"
    fi
}

# Main execution
main() {
    print_banner

    if [ -n "$SPECIFIC_ENDPOINT" ]; then
        # Test specific endpoint
        case "$SPECIFIC_ENDPOINT" in
            "/")
                test_endpoint "/" "Root endpoint" "200"
                ;;
            "/health")
                test_endpoint "/health" "Health check" "200" "status"
                ;;
            "/ready")
                test_endpoint "/ready" "Readiness check" "200" "ready"
                ;;
            "/metrics")
                test_endpoint "/metrics" "Metrics endpoint" "200"
                ;;
            "/arbitrage/status")
                test_endpoint "/arbitrage/status" "Arbitrage status" "200" "is_running"
                ;;
            "/arbitrage/metrics")
                test_endpoint "/arbitrage/metrics" "Arbitrage metrics" "200"
                ;;
            *)
                log_error "Unknown endpoint: $SPECIFIC_ENDPOINT"
                log_info "Available endpoints: /, /health, /ready, /metrics, /arbitrage/status, /arbitrage/metrics"
                exit 1
                ;;
        esac
    else
        # Test all endpoints
        test_endpoint "/" "Root endpoint" "200"
        test_endpoint "/health" "Health check" "200" "status"
        test_endpoint "/ready" "Readiness check" "200" "ready"
        test_endpoint "/metrics" "Metrics endpoint" "200"
        test_endpoint "/arbitrage/status" "Arbitrage status" "200" "is_running"
        test_endpoint "/arbitrage/metrics" "Arbitrage metrics" "200"
    fi

    print_summary

    # Exit with appropriate code
    local passed=0
    for endpoint in "${endpoints_tested[@]}"; do
        if [ "${results[${endpoint//\//}_result]}" = "pass" ]; then
            ((passed++))
        fi
    done

    if [ "$passed" -eq "${#endpoints_tested[@]}" ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"