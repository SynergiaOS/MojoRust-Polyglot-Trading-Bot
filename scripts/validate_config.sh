#!/bin/bash

# =============================================================================
# ✅ MojoRust Trading Bot - Configuration Validation Script
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2

    case $status in
        "SUCCESS")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
        "PROGRESS")
            echo -e "${PURPLE}🔄 $message${NC}"
            ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
✅ MojoRust Trading Bot - Configuration Validation Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --env-file FILE      Specify custom .env file (default: .env)
    --strict            Fail on warnings as well as errors
    --fix-permissions   Attempt to fix file permissions automatically
    --help, -h          Show this help message

EXAMPLES:
    $0                  # Validate .env file
    $0 --env-file .env.production  # Validate specific file
    $0 --strict         # Fail on any issues
    $0 --fix-permissions           # Auto-fix permissions

DESCRIPTION:
    This script validates the configuration for the trading bot:
    - Checks .env file format and required keys
    - Verifies file permissions
    - Tests Infisical connectivity
    - Validates API key formats
    - Checks for required directories

EXIT CODES:
    0   Success (all checks passed)
    1   Error (critical issues found)
    2   Warning (non-critical issues found, unless --strict used)

EOF
}

# Parse command line arguments
ENV_FILE=".env"
STRICT_MODE=false
FIX_PERMISSIONS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --strict)
            STRICT_MODE=true
            shift
            ;;
        --fix-permissions)
            FIX_PERMISSIONS=true
            shift
            ;;
        --help|-h)
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

# Validation counters
ERRORS=0
WARNINGS=0

# Function to increment error counter
add_error() {
    ((ERRORS++))
    print_status "ERROR" "$1"
}

# Function to increment warning counter
add_warning() {
    ((WARNINGS++))
    print_status "WARNING" "$1"
}

# Function to validate .env file
validate_env_file() {
    print_status "PROGRESS" "Validating environment configuration..."

    if [ ! -f "$ENV_FILE" ]; then
        add_error "Environment file not found: $ENV_FILE"
        return 1
    fi

    print_status "INFO" "Found environment file: $ENV_FILE"

    # Check file permissions
    local file_perms=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || stat -f "%A" "$ENV_FILE" 2>/dev/null)
    if [ -n "$file_perms" ]; then
        if [[ "$file_perms" =~ ^[0-9]+$ ]]; then
            local file_perms_num=$((file_perms))
            local others_read=$((file_perms_num & 4))
            local others_write=$((file_perms_num & 2))

            if [ $others_write -eq 2 ]; then
                add_warning "Environment file is writable by others (permissions: $file_perms)"
                if [ "$FIX_PERMISSIONS" = true ]; then
                    print_status "INFO" "Fixing permissions..."
                    chmod 600 "$ENV_FILE"
                    print_status "SUCCESS" "Permissions fixed to 600"
                fi
            elif [ $others_read -eq 4 ]; then
                add_warning "Environment file is readable by others (permissions: $file_perms)"
                if [ "$FIX_PERMISSIONS" = true ]; then
                    print_status "INFO" "Fixing permissions..."
                    chmod 600 "$ENV_FILE"
                    print_status "SUCCESS" "Permissions fixed to 600"
                fi
            else
                print_status "SUCCESS" "Environment file permissions are secure: $file_perms"
            fi
        fi
    fi

    # Check for required keys
    local required_keys=(
        "EXECUTION_MODE"
        "SERVER_HOST"
        "SERVER_PORT"
        "INITIAL_CAPITAL"
        "MAX_POSITION_SIZE"
        "MAX_DRAWDOWN"
    )

    local missing_keys=()
    local found_keys=()

    # Read .env file and check for keys
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue

        # Remove surrounding whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Check if this is a required key
        for required_key in "${required_keys[@]}"; do
            if [ "$key" = "$required_key" ]; then
                if [ -n "$value" ]; then
                    found_keys+=("$key")
                else
                    missing_keys+=("$key")
                fi
                break
            fi
        done
    done < "$ENV_FILE"

    # Report missing keys
    for required_key in "${required_keys[@]}"; do
        local found=false
        for found_key in "${found_keys[@]}"; do
            if [ "$found_key" = "$required_key" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            missing_keys+=("$required_key")
        fi
    done

    if [ ${#missing_keys[@]} -gt 0 ]; then
        add_error "Missing required configuration keys: ${missing_keys[*]}"
    else
        print_status "SUCCESS" "All required keys found in $ENV_FILE"
    fi

    # Validate key values
    print_status "INFO" "Validating key values..."

    # Check execution mode
    local execution_mode=$(grep "^EXECUTION_MODE=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -n "$execution_mode" ]; then
        if [[ "$execution_mode" =~ ^(paper|live|test)$ ]]; then
            print_status "SUCCESS" "Valid execution mode: $execution_mode"
            if [ "$execution_mode" = "live" ]; then
                add_warning "⚠️  LIVE TRADING MODE DETECTED - Please ensure you want to trade with real funds"
            fi
        else
            add_error "Invalid execution mode: $execution_mode (should be: paper, live, or test)"
        fi
    fi

    # Check server host
    local server_host=$(grep "^SERVER_HOST=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -n "$server_host" ]; then
        if [[ "$server_host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$server_host" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            print_status "SUCCESS" "Valid server host: $server_host"
        else
            add_error "Invalid server host: $server_host"
        fi
    fi

    # Check server port
    local server_port=$(grep "^SERVER_PORT=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -n "$server_port" ]; then
        if [[ "$server_port" =~ ^[0-9]+$ ]] && [ "$server_port" -ge 1 ] && [ "$server_port" -le 65535 ]; then
            print_status "SUCCESS" "Valid server port: $server_port"
        else
            add_error "Invalid server port: $server_port (should be 1-65535)"
        fi
    fi

    # Check initial capital
    local initial_capital=$(grep "^INITIAL_CAPITAL=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -n "$initial_capital" ]; then
        if [[ "$initial_capital" =~ ^[0-9]+\.?[0-9]*$ ]] && [ "$(echo "$initial_capital > 0" | bc 2>/dev/null || echo 0)" -eq 1 ]; then
            print_status "SUCCESS" "Valid initial capital: $initial_capital SOL"
            if (( $(echo "$initial_capital > 100" | bc -l) )); then
                add_warning "Large initial capital amount: $initial_capital SOL"
            fi
        else
            add_error "Invalid initial capital: $initial_capital (should be positive number)"
        fi
    fi

    # Check for API keys
    print_status "INFO" "Checking API key configuration..."

    local helius_key=$(grep "^HELIUS_API_KEY=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -n "$helius_key" ]; then
        if [ ${#helius_key} -ge 20 ]; then
            print_status "SUCCESS" "Helius API key appears valid"
        else
            add_warning "Helius API key seems too short: ${#helius_key} characters"
        fi
    else
        add_warning "Helius API key not found"
    fi

    local quicknode_url=$(grep "^QUICKNODE_RPC_URL=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -n "$quicknode_url" ]; then
        if [[ "$quicknode_url" =~ ^https?:// ]] && [[ "$quicknode_url" =~ quicknode ]]; then
            print_status "SUCCESS" "QuickNode RPC URL appears valid"
        else
            add_warning "QuickNode RPC URL may be invalid"
        fi
    else
        add_warning "QuickNode RPC URL not found"
    fi

    print_status "INFO" "Environment file validation completed"
}

# Function to test Infisical connectivity
test_infisical() {
    print_status "PROGRESS" "Testing Infisical connectivity..."

    # Check if infisical CLI is installed
    if ! command -v infisical >/dev/null 2>&1; then
        add_warning "Infisical CLI not installed"
        print_status "INFO" "To install Infisical CLI: npm install -g infisical"
        return 1
    fi

    print_status "SUCCESS" "Infisical CLI found"

    # Extract project ID from .env file
    local project_id=$(grep "^INFISICAL_PROJECT_ID=" "$ENV_FILE" | cut -d'=' -f2 | tr -d ' "')
    if [ -z "$project_id" ]; then
        add_warning "INFISICAL_PROJECT_ID not found in $ENV_FILE"
        project_id=""
    else
        print_status "SUCCESS" "Infisical project ID found: ${project_id:0:8}..."
    fi

    # Test connectivity
    print_status "INFO" "Testing Infisical API connection..."

    if [ -n "$project_id" ]; then
        if infisical secrets list --projectId "$project_id" --env production >/dev/null 2>&1; then
            print_status "SUCCESS" "Infisical API connection successful"

            # List available secrets
            print_status "INFO" "Available secrets:"
            infisical secrets list --projectId "$project_id" --env production 2>/dev/null | head -10 | while read -r line; do
                if [ -n "$line" ]; then
                    echo "  - $line"
                fi
            done
        else
            add_error "Failed to connect to Infisical API"
            print_status "INFO" "Please check:"
            print_status "INFO" "  - Project ID is correct"
            print_status "INFO" "  - You are logged in: infisical login"
            print_status "INFO" "  - Network connectivity"
        fi
    else
        print_status "INFO" "Skipping Infisical API test (no project ID)"
    fi
}

# Function to validate required directories
validate_directories() {
    print_status "PROGRESS" "Validating directory structure..."

    local required_dirs=(
        "src"
        "scripts"
        "logs"
        "secrets"
    )

    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            print_status "SUCCESS" "Directory exists: $dir"

            # Check directory permissions
            local dir_perms=$(stat -c "%a" "$dir" 2>/dev/null || stat -f "%A" "$dir" 2>/dev/null)
            if [ -n "$dir_perms" ]; then
                print_status "INFO" "Directory permissions: $dir_perms"
            fi
        else
            add_warning "Directory not found: $dir"
            if [ "$FIX_PERMISSIONS" = true ]; then
                print_status "INFO" "Creating directory: $dir"
                mkdir -p "$dir"
                print_status "SUCCESS" "Directory created: $dir"
            fi
        fi
    done

    # Check for key files
    local key_files=(
        "src/main.mojo"
        "scripts/deploy_with_filters.sh"
        "Cargo.toml"
    )

    for file in "${key_files[@]}"; do
        if [ -f "$file" ]; then
            print_status "SUCCESS" "Key file exists: $file"
        else
            add_warning "Key file not found: $file"
        fi
    done
}

# Function to validate configuration files
validate_config_files() {
    print_status "PROGRESS" "Validating configuration files..."

    # Check if Cargo.toml exists and is valid
    if [ -f "Cargo.toml" ]; then
        if grep -q "^\[package\]" Cargo.toml; then
            print_status "SUCCESS" "Cargo.toml is valid"
        else
            add_error "Cargo.toml appears to be invalid"
        fi
    else
        add_warning "Cargo.toml not found"
    fi

    # Check if mojo.toml exists
    if [ -f "mojo.toml" ]; then
        print_status "SUCCESS" "mojo.toml found"
    else
        add_warning "mojo.toml not found"
    fi
}

# Function to show validation summary
show_summary() {
    print_status "INFO" "📊 Configuration Validation Summary:"
    echo ""

    echo "Validation Results:"
    if [ $ERRORS -eq 0 ]; then
        echo "  ✅ No critical errors found"
    else
        echo "  ❌ $ERRORS critical error(s) found"
    fi

    if [ $WARNINGS -eq 0 ]; then
        echo "  ✅ No warnings found"
    else
        echo "  ⚠️  $WARNINGS warning(s) found"
    fi

    echo ""
    echo "Files checked:"
    echo "  📄 Environment file: $ENV_FILE"
    echo "  📁 Directory structure"
    echo "  🔧 Configuration files"
    echo "  🔗 Infisical connectivity"

    echo ""
    if [ $ERRORS -eq 0 ] && ([ $WARNINGS -eq 0 ] || [ "$STRICT_MODE" = false ]); then
        print_status "SUCCESS" "✅ Configuration validation passed!"
        print_status "INFO" "You can proceed with deployment"
    else
        print_status "ERROR" "❌ Configuration validation failed!"
        print_status "INFO" "Please fix the issues above before proceeding"
    fi
}

# Main execution
main() {
    print_status "INFO" "✅ MojoRust Trading Bot - Configuration Validation"
    print_status "INFO" "Validating configuration: $ENV_FILE"
    echo ""

    # Run validation checks
    validate_env_file
    test_infisical
    validate_directories
    validate_config_files

    # Show summary
    echo ""
    show_summary

    # Determine exit code
    if [ $ERRORS -gt 0 ]; then
        exit 1
    elif [ $WARNINGS -gt 0 ] && [ "$STRICT_MODE" = true ]; then
        exit 2
    else
        exit 0
    fi
}

# Handle script interruption gracefully
trap 'print_status "WARNING"; print_status "WARNING" "Validation interrupted by user"; exit 130' INT TERM

# Run main function
main