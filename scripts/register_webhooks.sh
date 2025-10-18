#!/bin/bash
# Webhook Registration Script
#
# This script registers webhooks with Helius and QuickNode for real-time alerts
# Usage: ./scripts/register_webhooks.sh [--list] [--unregister] [--test]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    source "$PROJECT_ROOT/.env"
fi

# Default configuration
WEBHOOK_URL="${WEBHOOK_URL:-http://localhost:8082}"
HELIUS_API_KEY="${HELIUS_LASERSTREAM_KEY:-$HELIUS_API_KEY}"
QUICKNODE_API_KEY="${PRIORITY_FEE_API_KEY:-$QUICKNODE_API_KEY}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check if required tools are installed
check_dependencies() {
    log_info "Checking dependencies..."

    local missing_deps=()

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Install missing dependencies and try again"
        exit 1
    fi

    log_success "All dependencies are available"
}

# Validate environment variables
validate_environment() {
    log_info "Validating environment variables..."

    if [[ -z "$HELIUS_API_KEY" ]]; then
        log_error "HELIUS_LASERSTREAM_KEY or HELIUS_API_KEY must be set"
        exit 1
    fi

    if [[ -z "$QUICKNODE_API_KEY" ]]; then
        log_warning "PRIORITY_FEE_API_KEY or QUICKNODE_API_KEY not set - QuickNode webhooks will be skipped"
    fi

    log_success "Environment variables validated"
}

# Test webhook endpoint
test_webhook_endpoint() {
    log_info "Testing webhook endpoint at $WEBHOOK_URL..."

    local test_payload='{
        "event_type": "test",
        "message": "Webhook registration test",
        "timestamp": "'$(date -Iseconds)'"
    }'

    if curl_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$test_payload" \
        "$WEBHOOK_URL/webhook/test" 2>/dev/null); then

        local http_code="${curl_response: -3}"
        if [[ "$http_code" == "200" ]]; then
            log_success "Webhook endpoint is responding correctly"
            return 0
        else
            log_error "Webhook endpoint returned HTTP $http_code"
            return 1
        fi
    else
        log_error "Could not connect to webhook endpoint"
        return 1
    fi
}

# Register Helius webhooks
register_helius_webhooks() {
    log_info "Registering Helius webhooks..."

    local helius_api_url="https://api.helius.xyz/v0/webhooks"

    # Register transaction webhook
    log_info "Registering Helius transaction webhook..."

    local transaction_payload='{
        "webhookURL": "'$WEBHOOK_URL'/webhook/helius",
        "transactionTypes": ["TRANSFER", "SWAP"],
        "accountAddresses": [],
        "webhookType": "enhanced",
        "authHeader": "Bearer '$HELIUS_API_KEY'"
    }'

    if curl_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $HELIUS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$transaction_payload" \
        "$helius_api_url" 2>/dev/null); then

        local http_code="${curl_response: -3}"
        local response_body="${curl_response%[0-9][0-9][0-9]}"

        if [[ "$http_code" == "200" ]]; then
            local webhook_id=$(echo "$response_body" | jq -r '.webhookID // empty')
            log_success "Helius transaction webhook registered successfully (ID: $webhook_id)"
            echo "$webhook_id" > /tmp/helius_transaction_webhook_id.txt
        else
            log_error "Failed to register Helius transaction webhook (HTTP $http_code)"
            echo "$response_body" | jq -r '.message // .error // "Unknown error"' >&2
        fi
    else
        log_error "Failed to call Helius API"
    fi

    # Register token launch webhook
    log_info "Registering Helius token launch webhook..."

    local token_payload='{
        "webhookURL": "'$WEBHOOK_URL'/webhook/helius",
        "transactionTypes": ["CREATE_TOKEN", "INITIALIZE_MINT"],
        "accountAddresses": [],
        "webhookType": "enhanced"
    }'

    if curl_response=$(curl -s -w "%{http_code}" -X POST \
        -H "Authorization: Bearer $HELIUS_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$token_payload" \
        "$helius_api_url" 2>/dev/null); then

        local http_code="${curl_response: -3}"
        local response_body="${curl_response%[0-9][0-9][0-9]}"

        if [[ "$http_code" == "200" ]]; then
            local webhook_id=$(echo "$response_body" | jq -r '.webhookID // empty')
            log_success "Helius token launch webhook registered successfully (ID: $webhook_id)"
            echo "$webhook_id" > /tmp/helius_token_webhook_id.txt
        else
            log_error "Failed to register Helius token launch webhook (HTTP $http_code)"
            echo "$response_body" | jq -r '.message // .error // "Unknown error"' >&2
        fi
    else
        log_error "Failed to call Helius API"
    fi
}

# Register QuickNode webhooks
register_quicknode_webhooks() {
    if [[ -z "$QUICKNODE_API_KEY" ]]; then
        log_warning "Skipping QuickNode webhook registration (no API key)"
        return
    fi

    log_info "Registering QuickNode webhooks..."

    local quicknode_api_url="https://api.quicknode.com/v1/streams/webhooks"

    # Register bundle webhook
    log_info "Registering QuickNode bundle webhook..."

    local bundle_payload='{
        "url": "'$WEBHOOK_URL'/webhook/quicknode",
        "eventTypes": ["bundle.submitted", "bundle.confirmed"],
        "network": "mainnet",
        "description": "MojoRust trading bot webhook"
    }'

    if curl_response=$(curl -s -w "%{http_code}" -X POST \
        -H "x-api-key: $QUICKNODE_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$bundle_payload" \
        "$quicknode_api_url" 2>/dev/null); then

        local http_code="${curl_response: -3}"
        local response_body="${curl_response%[0-9][0-9][0-9]}"

        if [[ "$http_code" == "200" || "$http_code" == "201" ]]; then
            local webhook_id=$(echo "$response_body" | jq -r '.id // .webhookID // empty')
            log_success "QuickNode bundle webhook registered successfully (ID: $webhook_id)"
            echo "$webhook_id" > /tmp/quicknode_bundle_webhook_id.txt
        else
            log_error "Failed to register QuickNode bundle webhook (HTTP $http_code)"
            echo "$response_body" | jq -r '.message // .error // "Unknown error"' >&2
        fi
    else
        log_error "Failed to call QuickNode API"
    fi
}

# List registered webhooks
list_webhooks() {
    log_info "Listing registered webhooks..."

    # List Helius webhooks
    if [[ -n "$HELIUS_API_KEY" ]]; then
        log_info "Helius webhooks:"

        local helius_api_url="https://api.helius.xyz/v0/webhooks"

        if curl_response=$(curl -s -H "Authorization: Bearer $HELIUS_API_KEY" \
            "$helius_api_url" 2>/dev/null); then

            echo "$curl_response" | jq -r '.webhooks[] | "- \(.webhookID): \(.webhookURL) (\(.subscriptionStatus))"' 2>/dev/null || \
                log_warning "Could not parse Helius webhook list"
        else
            log_error "Failed to fetch Helius webhooks"
        fi
    fi

    # List QuickNode webhooks
    if [[ -n "$QUICKNODE_API_KEY" ]]; then
        log_info "QuickNode webhooks:"

        local quicknode_api_url="https://api.quicknode.com/v1/streams/webhooks"

        if curl_response=$(curl -s -H "x-api-key: $QUICKNODE_API_KEY" \
            "$quicknode_api_url" 2>/dev/null); then

            echo "$curl_response" | jq -r '.[] | "- \(.id // .webhookID): \(.url) (\(.status // .subscriptionStatus))"' 2>/dev/null || \
                log_warning "Could not parse QuickNode webhook list"
        else
            log_error "Failed to fetch QuickNode webhooks"
        fi
    fi
}

# Unregister webhooks
unregister_webhooks() {
    log_info "Unregistering webhooks..."

    local helius_api_url="https://api.helius.xyz/v0/webhooks"
    local quicknode_api_url="https://api.quicknode.com/v1/streams/webhooks"

    # Unregister Helius webhooks
    if [[ -n "$HELIUS_API_KEY" ]]; then
        log_info "Unregistering Helius webhooks..."

        # Get list of webhooks
        if curl_response=$(curl -s -H "Authorization: Bearer $HELIUS_API_KEY" \
            "$helius_api_url" 2>/dev/null); then

            echo "$curl_response" | jq -r '.webhooks[].webhookID' 2>/dev/null | while read -r webhook_id; do
                if [[ -n "$webhook_id" && "$webhook_id" != "null" ]]; then
                    log_info "Unregistering Helius webhook: $webhook_id"

                    if curl -s -X DELETE \
                        -H "Authorization: Bearer $HELIUS_API_KEY" \
                        "$helius_api_url/$webhook_id" >/dev/null 2>&1; then
                        log_success "Unregistered Helius webhook: $webhook_id"
                    else
                        log_error "Failed to unregister Helius webhook: $webhook_id"
                    fi
                fi
            done
        fi
    fi

    # Unregister QuickNode webhooks
    if [[ -n "$QUICKNODE_API_KEY" ]]; then
        log_info "Unregistering QuickNode webhooks..."

        # Get list of webhooks
        if curl_response=$(curl -s -H "x-api-key: $QUICKNODE_API_KEY" \
            "$quicknode_api_url" 2>/dev/null); then

            echo "$curl_response" | jq -r '.[].id // .webhookID' 2>/dev/null | while read -r webhook_id; do
                if [[ -n "$webhook_id" && "$webhook_id" != "null" ]]; then
                    log_info "Unregistering QuickNode webhook: $webhook_id"

                    if curl -s -X DELETE \
                        -H "x-api-key: $QUICKNODE_API_KEY" \
                        "$quicknode_api_url/$webhook_id" >/dev/null 2>&1; then
                        log_success "Unregistered QuickNode webhook: $webhook_id"
                    else
                        log_error "Failed to unregister QuickNode webhook: $webhook_id"
                    fi
                fi
            done
        fi
    fi
}

# Test webhook functionality
test_webhooks() {
    log_info "Testing webhook functionality..."

    # Test Helius webhook
    log_info "Testing Helius webhook..."

    local helius_test_payload='{
        "event_type": "token_launch",
        "token_address": "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr",
        "token_symbol": "TEST",
        "lp_burned": 95,
        "initial_liquidity": 50000000000
    }'

    if curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$helius_test_payload" \
        "$WEBHOOK_URL/webhook/helius" >/dev/null 2>&1; then
        log_success "Helius webhook test sent successfully"
    else
        log_error "Failed to send Helius webhook test"
    fi

    # Test QuickNode webhook
    log_info "Testing QuickNode webhook..."

    local quicknode_test_payload='{
        "type": "bundle_submitted",
        "bundle_id": "test_bundle_123",
        "transactions_count": 3,
        "priority_fee": 50000
    }'

    if curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$quicknode_test_payload" \
        "$WEBHOOK_URL/webhook/quicknode" >/dev/null 2>&1; then
        log_success "QuickNode webhook test sent successfully"
    else
        log_error "Failed to send QuickNode webhook test"
    fi

    log_info "Check Telegram channel for notifications"
}

# Show usage
show_usage() {
    cat << EOF
Webhook Registration Script

Usage: $0 [OPTIONS]

OPTIONS:
    --list          List registered webhooks
    --unregister     Unregister all webhooks
    --test          Test webhook functionality
    --no-check       Skip webhook endpoint test
    --help          Show this help message

ENVIRONMENT VARIABLES:
    WEBHOOK_URL              Webhook endpoint URL (default: http://localhost:8082)
    HELIUS_LASERSTREAM_KEY   Helius API key for webhook registration
    PRIORITY_FEE_API_KEY     QuickNode API key for webhook registration

EXAMPLES:
    $0                     # Register all webhooks
    $0 --list              # List registered webhooks
    $0 --test              # Test webhook functionality
    $0 --unregister        # Unregister all webhooks

EOF
}

# Main function
main() {
    local list_webhooks=false
    local unregister_webhooks=false
    local test_webhooks=false
    local skip_check=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                list_webhooks=true
                shift
                ;;
            --unregister)
                unregister_webhooks=true
                shift
                ;;
            --test)
                test_webhooks=true
                shift
                ;;
            --no-check)
                skip_check=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Check dependencies
    check_dependencies

    # Validate environment
    validate_environment

    # Execute requested actions
    if [[ "$list_webhooks" == "true" ]]; then
        list_webhooks
        exit 0
    fi

    if [[ "$unregister_webhooks" == "true" ]]; then
        unregister_webhooks
        exit 0
    fi

    if [[ "$test_webhooks" == "true" ]]; then
        test_webhooks
        exit 0
    fi

    # Default action: register webhooks
    log_info "Starting webhook registration..."
    log_info "Webhook URL: $WEBHOOK_URL"

    # Test webhook endpoint
    if [[ "$skip_check" != "true" ]]; then
        if ! test_webhook_endpoint; then
            log_error "Webhook endpoint test failed"
            log_info "Make sure the webhook manager is running: python python/webhook_manager.py"
            log_info "Or use --no-check to skip the endpoint test"
            exit 1
        fi
    fi

    # Register webhooks
    register_helius_webhooks
    register_quicknode_webhooks

    log_success "Webhook registration completed!"
    log_info "Test webhooks with: $0 --test"
    log_info "List webhooks with: $0 --list"
    log_info "Unregister webhooks with: $0 --unregister"
}

# Run main function
main "$@"