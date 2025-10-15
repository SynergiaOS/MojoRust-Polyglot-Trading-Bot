#!/bin/bash

# =============================================================================
# MojoRust Trading Bot - Grafana Dashboard Import Script
# =============================================================================
# This script manually imports Grafana dashboards if auto-provisioning fails

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
GRAFANA_URL="http://localhost:3001"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="trading_admin"
DASHBOARDS_DIR="config/grafana/dashboards"
FOLDER_NAME="Trading Bot"
FORCE_IMPORT=false
SPECIFIC_DASHBOARD=""

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    📊 GRAFANA DASHBOARD IMPORT SCRIPT 📊                   ║"
    echo "║                                                              ║"
    echo "║    Manual dashboard import for Grafana visualization        ║"
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
    echo -e "${BLUE}[DETAIL]${NC} $1"
}

check_grafana_health() {
    log_info "Checking Grafana health..."

    # Check if Grafana is accessible
    if ! curl -sf "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
        log_error "Grafana is not accessible at $GRAFANA_URL"
        echo ""
        log_info "Please ensure Grafana is running:"
        echo "  docker-compose up -d grafana"
        echo "  Wait for Grafana to start, then run this script again"
        return 1
    fi

    # Test authentication
    if ! curl -sf -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/org" >/dev/null 2>&1; then
        log_error "Grafana authentication failed"
        echo ""
        log_info "Please check Grafana credentials:"
        echo "  Username: $GRAFANA_USER"
        echo "  Password: $GRAFANA_PASSWORD"
        echo "  URL: $GRAFANA_URL"
        return 1
    fi

    log_success "Grafana is healthy and accessible"
    return 0
}

create_dashboard_folder() {
    log_info "Creating dashboard folder: $FOLDER_NAME"

    # Check if folder already exists
    local existing_folder
    existing_folder=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/folders" | jq -r --arg name "$FOLDER_NAME" '.[] | select(.title == $name) | .uid' 2>/dev/null)

    if [[ -n "$existing_folder" ]]; then
        log_success "Folder '$FOLDER_NAME' already exists (UID: $existing_folder)"
        echo "$existing_folder"
        return 0
    fi

    # Create new folder
    local folder_payload
    folder_payload=$(cat << EOF
{
    "title": "$FOLDER_NAME"
}
EOF
)

    local folder_response
    if folder_response=$(curl -s -X POST -H "Content-Type: application/json" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" -d "$folder_payload" "$GRAFANA_URL/api/folders"); then
        local folder_uid
        folder_uid=$(echo "$folder_response" | jq -r '.uid')
        log_success "Created folder '$FOLDER_NAME' (UID: $folder_uid)"
        echo "$folder_uid"
        return 0
    else
        log_error "Failed to create dashboard folder"
        return 1
    fi
}

import_dashboard() {
    local dashboard_file=$1
    local folder_id=$2

    if [[ ! -f "$dashboard_file" ]]; then
        log_error "Dashboard file not found: $dashboard_file"
        return 1
    fi

    # Read and validate dashboard JSON
    local dashboard_json
    if ! dashboard_json=$(jq . "$dashboard_file" 2>/dev/null); then
        log_error "Invalid JSON in dashboard file: $dashboard_file"
        return 1
    fi

    # Extract dashboard title and UID
    local dashboard_title
    local dashboard_uid
    dashboard_title=$(echo "$dashboard_json" | jq -r '.title // "Unknown"')
    dashboard_uid=$(echo "$dashboard_json" | jq -r '.uid // ""')

    if [[ -z "$dashboard_uid" ]]; then
        log_warning "Dashboard '$dashboard_title' has no UID, generating one..."
        # Generate URL-safe UID using base62 characters
        dashboard_uid=$(uuidgen 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 12 | tr '[:upper:]' '[:lower:]' || echo "dashboard-$(date +%s)" | tr -dc 'a-zA-Z0-9')
        # Ensure it starts with a letter and is URL-safe
        dashboard_uid=$(echo "$dashboard_uid" | sed 's/^[0-9]/d\0/' | tr -cd 'a-z0-9-')
        dashboard_json=$(echo "$dashboard_json" | jq --arg uid "$dashboard_uid" '.uid = $uid')
        log_detail "Generated URL-safe UID: $dashboard_uid"
    else
        # Normalize existing UID to be URL-safe
        dashboard_uid=$(echo "$dashboard_uid" | tr -cd 'a-zA-Z0-9-' | tr '[:upper:]' '[:lower:]')
        # Ensure it starts with a letter
        dashboard_uid=$(echo "$dashboard_uid" | sed 's/^[0-9]/d\0/')
        dashboard_json=$(echo "$dashboard_json" | jq --arg uid "$dashboard_uid" '.uid = $uid')
        log_detail "Normalized UID to URL-safe format: $dashboard_uid"
    fi

    log_info "Importing dashboard: $dashboard_title (UID: $dashboard_uid)"

    # Check if dashboard already exists by checking HTTP status
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/dashboards/uid/$dashboard_uid" 2>/dev/null)

    if [[ "$http_status" == "200" && "$FORCE_IMPORT" != true ]]; then
        log_warning "Dashboard '$dashboard_title' already exists"
        echo "  Existing dashboard: $GRAFANA_URL/d/$dashboard_uid"
        echo "  To overwrite, use: --force flag"
        return 0
    elif [[ "$http_status" == "404" ]]; then
        log_detail "Dashboard '$dashboard_title' does not exist yet, proceeding with import"
    elif [[ "$http_status" != "200" && "$http_status" != "404" ]]; then
        log_warning "Unexpected HTTP status $http_status when checking dashboard '$dashboard_title', proceeding with import"
    fi

    # Prepare import payload
    local import_payload
    import_payload=$(cat << EOF
{
    "dashboard": $dashboard_json,
    "folderId": $folder_id,
    "overwrite": true,
    "inputs": []
}
EOF
)

    # Import dashboard
    local import_response
    if import_response=$(curl -s -X POST -H "Content-Type: application/json" -u "$GRAFANA_USER:$GRAFANA_PASSWORD" -d "$import_payload" "$GRAFANA_URL/api/dashboards/db"); then
        local import_status
        import_status=$(echo "$import_response" | jq -r '.status // "unknown"')

        if [[ "$import_status" == "success" ]]; then
            local imported_uid
            imported_uid=$(echo "$import_response" | jq -r '.uid')
            local imported_url="$GRAFANA_URL/d/$imported_uid"
            log_success "Dashboard '$dashboard_title' imported successfully"
            echo "  URL: $imported_url"
            return 0
        else
            local import_error
            import_error=$(echo "$import_response" | jq -r '.message // "Unknown error"')
            log_error "Failed to import dashboard '$dashboard_title': $import_error"
            return 1
        fi
    else
        log_error "Failed to send import request for dashboard '$dashboard_title'"
        return 1
    fi
}

import_all_dashboards() {
    log_info "Importing all dashboards from $DASHBOARDS_DIR"

    # Check if dashboard directory exists
    if [[ ! -d "$DASHBOARDS_DIR" ]]; then
        log_error "Dashboard directory not found: $DASHBOARDS_DIR"
        return 1
    fi

    # Create dashboard folder
    local folder_id
    folder_id=$(create_dashboard_folder)

    if [[ -z "$folder_id" ]]; then
        log_error "Failed to create or find dashboard folder"
        return 1
    fi

    # Find all JSON dashboard files
    local dashboard_files=()
    while IFS= read -r -d '' file; do
        dashboard_files+=("$file")
    done < <(find "$DASHBOARDS_DIR" -name "*.json" -print0 2>/dev/null)

    if [[ ${#dashboard_files[@]} -eq 0 ]]; then
        log_warning "No JSON dashboard files found in $DASHBOARDS_DIR"
        return 0
    fi

    log_info "Found ${#dashboard_files[@]} dashboard files"

    local success_count=0
    local failure_count=0

    # Import each dashboard
    for dashboard_file in "${dashboard_files[@]}"; do
        echo ""
        log_info "Processing: $(basename "$dashboard_file")"

        if import_dashboard "$dashboard_file" "$folder_id"; then
            ((success_count++))
        else
            ((failure_count++))
        fi
    done

    # Summary
    echo ""
    log_info "Dashboard import summary:"
    echo "  Total dashboards: ${#dashboard_files[@]}"
    echo "  Successfully imported: $success_count"
    echo "  Failed: $failure_count"

    if [[ $failure_count -eq 0 ]]; then
        log_success "All dashboards imported successfully"
        return 0
    else
        log_warning "Some dashboards failed to import"
        return 1
    fi
}

verify_imported_dashboards() {
    log_info "Verifying imported dashboards..."

    # Get all dashboards from Grafana
    local grafana_dashboards
    if ! grafana_dashboards=$(curl -s -u "$GRAFANA_USER:$GRAFANA_PASSWORD" "$GRAFANA_URL/api/search?type=dash-db"); then
        log_error "Failed to fetch dashboards from Grafana"
        return 1
    fi

    # Get expected dashboards from directory
    local expected_dashboards=()
    while IFS= read -r -d '' file; do
        local dashboard_title
        dashboard_title=$(jq -r '.title // ""' "$file" 2>/dev/null)
        if [[ -n "$dashboard_title" ]]; then
            expected_dashboards+=("$dashboard_title")
        fi
    done < <(find "$DASHBOARDS_DIR" -name "*.json" -print0 2>/dev/null)

    echo "Dashboard Verification:"
    echo "======================="
    printf "%-35s %-15s %-40s\n" "TITLE" "STATUS" "URL"
    echo "-------------------------------------------------------------------------"

    local verified_count=0
    local total_count=${#expected_dashboards[@]}

    for expected_title in "${expected_dashboards[@]}"; do
        local dashboard_info
        dashboard_info=$(echo "$grafana_dashboards" | jq -r --arg title "$expected_title" '.[] | select(.title | test($title; "i"))')

        if [[ -n "$dashboard_info" ]]; then
            local dashboard_uid=$(echo "$dashboard_info" | jq -r '.uid')
            local dashboard_url="$GRAFANA_URL/d/$dashboard_uid"
            printf "%-35s ${GREEN}%-15s${NC} %-40s\n" "$expected_title" "IMPORTED" "$dashboard_url"
            ((verified_count++))
        else
            printf "%-35s ${RED}%-15s${NC} %-40s\n" "$expected_title" "MISSING" "N/A"
        fi
    done

    echo ""
    log_detail "Total expected dashboards: $total_count"
    log_detail "Verified dashboards: $verified_count"

    if [[ $verified_count -eq $total_count ]]; then
        log_success "All expected dashboards are verified"
        return 0
    else
        log_warning "Some dashboards are missing"
        return 1
    fi
}

show_help() {
    cat << EOF
MojoRust Trading Bot - Grafana Dashboard Import Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --dashboard=<file>     Import only specified dashboard file
    --folder=<name>        Use custom folder name (default: "Trading Bot")
    --force               Overwrite existing dashboards without prompting
    --help                 Show this help message

EXAMPLES:
    $0                              # Import all dashboards
    $0 --dashboard=system_health.json  # Import specific dashboard
    $0 --folder="My Dashboards"       # Use custom folder name
    $0 --force                        # Overwrite existing dashboards

DASHBOARD DIRECTORY:
    $DASHBOARDS_DIR

REQUIREMENTS:
    - Grafana running and accessible
    - Valid Grafana credentials
    - Dashboard JSON files in $DASHBOARDS_DIR
    - jq command for JSON processing

AFTER IMPORT:
    - Access dashboards at: $GRAFANA_URL/dashboards
    - Navigate to the "$FOLDER_NAME" folder
    - Verify dashboards are loading data from Prometheus

TROUBLESHOOTING:
    - If dashboards show "No Data": Check Prometheus datasource configuration
    - If import fails: Verify dashboard JSON syntax with jq
    - If authentication fails: Check Grafana credentials and URL
    - For detailed help: docs/monitoring_troubleshooting_guide.md

EOF
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dashboard=*)
                SPECIFIC_DASHBOARD="${1#*=}"
                shift
                ;;
            --folder=*)
                FOLDER_NAME="${1#*=}"
                shift
                ;;
            --force)
                FORCE_IMPORT=true
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

    # Check prerequisites
    if ! check_grafana_health; then
        exit 1
    fi

    # Import dashboards
    if [[ -n "$SPECIFIC_DASHBOARD" ]]; then
        # Import specific dashboard
        local folder_id
        folder_id=$(create_dashboard_folder)

        if [[ -z "$folder_id" ]]; then
            log_error "Failed to create dashboard folder"
            exit 1
        fi

        if import_dashboard "$SPECIFIC_DASHBOARD" "$folder_id"; then
            log_success "Dashboard import completed"
        else
            log_error "Dashboard import failed"
            exit 1
        fi
    else
        # Import all dashboards
        if import_all_dashboards; then
            # Verify imported dashboards
            verify_imported_dashboards
        else
            log_error "Dashboard import failed"
            exit 1
        fi
    fi

    echo ""
    log_success "Dashboard import process completed"
    echo ""
    echo "📊 Access your dashboards at: $GRAFANA_URL"
    echo "🔑 Credentials: $GRAFANA_USER/$GRAFANA_PASSWORD"
    echo "📁 Folder: $FOLDER_NAME"
}

# Check dependencies
if ! command -v jq >/dev/null 2>&1; then
    log_error "jq command is required but not installed"
    echo "Please install jq: apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    exit 1
fi

# Check if uuidgen is available (used for generating UIDs if needed)
if ! command -v uuidgen >/dev/null 2>&1; then
    log_warning "uuidgen command not found, using timestamp-based UIDs"
fi

# Run main function
main "$@"