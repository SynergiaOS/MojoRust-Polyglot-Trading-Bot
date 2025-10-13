#!/bin/bash

# =============================================================================
# 🔐 MojoRust Trading Bot - Wallet Verification Script
# =============================================================================

set -e

# POSIX shell compatibility
# Ensure we're using a POSIX-compliant shell
if [ -z "$BASH_VERSION" ] && [ -z "$ZSH_VERSION" ]; then
    # We're likely in a basic POSIX shell
    # Fallback to basic functionality
    POSIX_MODE=1
else
    POSIX_MODE=0
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
WALLET_PATH="$HOME/.config/solana/id.json"
VERBOSE=false
AUTO_FIX=false
EXIT_CODE=0

# Functions for colored output (basic POSIX compatibility)
print_status() {
    local status=$1
    local message=$2

    if [ "$POSIX_MODE" = 1 ]; then
        # Basic POSIX without colors
        case $status in
            "SUCCESS") echo "✅ $message" ;;
            "ERROR") echo "❌ $message" ;;
            "WARNING") echo "⚠️  $message" ;;
            "INFO") echo "ℹ️  $message" ;;
        esac
    else
        # Full color support
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
    fi
}

# Function to show help
show_help() {
    cat << 'EOF'
🔐 MojoRust Trading Bot - Wallet Verification Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --verbose, -v        Enable verbose output
    --fix, -f           Automatically fix issues (permissions, etc.)
    --wallet-path PATH  Custom wallet path (default: ~/.config/solana/id.json)
    --help, -h          Show this help message

EXAMPLES:
    $0                  # Basic wallet check
    $0 --verbose        # Detailed output
    $0 --fix             # Auto-fix permissions
    $0 --wallet-path /custom/path/wallet.json

DESCRIPTION:
    This script performs comprehensive wallet verification:
    - File existence and accessibility
    - Permission security (600)
    - JSON format and structure validation
    - Base58 public key extraction
    - Network connectivity testing
    - Environment variable validation

EXIT CODES:
    0   Success (all checks passed)
    1   Error (critical issues found)
    2   Warning (non-critical issues found, unless --strict used)

EOF
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --fix|-f)
            AUTO_FIX=true
            shift
            ;;
        --wallet-path)
            WALLET_PATH="$2"
            shift 2
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

# Function to check file existence
check_file_existence() {
    print_status "PROGRESS" "Checking wallet file existence..."

    if [ ! -f "$WALLET_PATH" ]; then
        print_status "ERROR" "Wallet file not found: $WALLET_PATH"
        if [ "$VERBOSE" = true ]; then
            echo "  Expected location: ~/.config/solana/id.json"
            echo "  Current directory: $(pwd)"
            echo "  Create directory: mkdir -p ~/.config/solana"
        fi
        return 1
    fi

    if [ ! -r "$WALLET_PATH" ]; then
        print_status "ERROR" "Wallet file not readable: $WALLET_PATH"
        return 1
    fi

    if [ ! -s "$WALLET_PATH" ]; then
        print_status "ERROR" "Wallet file is empty: $WALLET_PATH"
        return 1
    fi

    print_status "SUCCESS" "Wallet file found and readable: $WALLET_PATH"
    if [ "$VERBOSE" = true ]; then
        local file_size=$(wc -c < "$WALLET_PATH" 2>/dev/null || echo "unknown")
        echo "  File size: $file_size bytes"
    fi
    return 0
}

# Function to check and fix permissions
check_permissions() {
    print_status "PROGRESS" "Checking wallet file permissions..."

    if ! command -v stat >/dev/null 2>&1; then
        print_status "WARNING" "stat command not available, cannot check permissions"
        return 0
    fi

    local perms
    if command -v stat >/dev/null 2>&1; then
        perms=$(stat -c "%a" "$WALLET_PATH" 2>/dev/null)
    else
        # Fallback for systems without stat
        perms=$(ls -l "$WALLET_PATH" | cut -d' ' -f1)
    fi

    if [ -z "$perms" ]; then
        print_status "ERROR" "Could not determine file permissions"
        return 1
    fi

    if [ "$perms" = "600" ]; then
        print_status "SUCCESS" "Wallet permissions are secure: 600"
        if [ "$VERBOSE" = true ]; then
            echo "  Owner: read/write"
            echo "  Group: no access"
            echo "  Others: no access"
        fi
        return 0
    fi

    print_status "WARNING" "Wallet permissions are insecure: $perms (should be 600)"
    if [ "$VERBOSE" = true ]; then
        echo "  Current permissions allow unwanted access"
        echo "  This poses a security risk for your private keys"
    fi

    if [ "$AUTO_FIX" = true ]; then
        print_status "INFO" "Attempting to fix permissions..."
        if chmod 600 "$WALLET_PATH" 2>/dev/null; then
            print_status "SUCCESS" "Permissions fixed to 600"
        else
            print_status "ERROR" "Failed to fix permissions"
            print_status "INFO" "Try manually: chmod 600 $WALLET_PATH"
            return 1
        fi
    else
        print_status "INFO" "Run with --fix to automatically correct permissions"
        return 2
    fi

    return 0
}

# Function to validate JSON format
check_json_format() {
    print_status "PROGRESS" "Validating JSON format..."

    if ! command -v python3 >/dev/null 2>&1; then
        # Fallback validation without Python
        print_status "WARNING" "Python3 not available for JSON validation, using basic checks"

        # Basic JSON validation - check for brackets and quotes
        local first_char=$(head -c 1 "$WALLET_PATH")
        local last_char=$(tail -c 1 "$WALLET_PATH")

        if [ "$first_char" = "[" ] && [ "$last_char" = "]" ]; then
            print_status "SUCCESS" "Basic JSON structure looks correct"
            return 0
        else
            print_status "ERROR" "Invalid JSON format (should be an array)"
            return 1
        fi
    fi

    # Full Python validation
    local json_check_result
    json_check_result=$(python3 -c "
import json
import sys
try:
    with open('$WALLET_PATH', 'r') as f:
        data = json.load(f)
    if isinstance(data, list):
        print('VALID_ARRAY')
        print(len(data))
    else:
        print('NOT_ARRAY')
        sys.exit(1)
except Exception as e:
    print(f'JSON_ERROR: {e}')
    sys.exit(1)
" 2>/dev/null || echo "FAILED")

    case $json_check_result in
        "VALID_ARRAY"*)
            local array_length=$(echo "$json_check_result" | tail -1)
            if [ "$array_length" -eq 64 ]; then
                print_status "SUCCESS" "Valid JSON array with 64 elements"
                if [ "$VERBOSE" = true ]; then
                    echo "  Structure: [0, 1, 2, ..., 61, 62, 63]"
                    echo "  First element: $(head -20 "$WALLET_PATH" | grep -o '\[0-9\]' | head -1)"
                    echo "  Last element: $(tail -20 "$WALLET_PATH" | grep -o '[0-9]\]' | tail -1)"
                fi
                return 0
            else
                print_status "ERROR" "Invalid array length: $array_length (expected 64)"
                return 1
            fi
            ;;
        "NOT_ARRAY")
            print_status "ERROR" "Invalid JSON format (expected array)"
            return 1
            ;;
        *)
            print_status "ERROR" "JSON validation failed: $json_check_result"
            if [ "$VERBOSE" = true ]; then
                echo "  Check if file contains valid JSON array"
            fi
            return 1
            ;;
    esac
}

# Function to extract public key
extract_public_key() {
    print_status "PROGRESS" "Extracting public key from keypair..."

    if command -v solana-keygen >/dev/null 2>&1; then
        # Use Solana CLI for proper extraction
        local pubkey_result
        pubkey_result=$(solana-keygen pubkey "$WALLET_PATH" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$pubkey_result" ]; then
            print_status "SUCCESS" "Public key extracted: $pubkey_result"
            PUBLIC_KEY="$pubkey_result"

            if [ "$VERBOSE" = true ]; then
                echo "  Extraction method: solana-keygen pubkey"
                echo "  KeyPair source: $WALLET_PATH"
            fi
            return 0
        else
            print_status "WARNING" "Failed to extract public key with Solana CLI"
        fi
    else
        print_status "WARNING" "Solana CLI not available for key extraction"
    fi

    # Fallback: Manual extraction with base58
    if command -v python3 >/dev/null 2>&1; then
        print_status "INFO" "Attempting manual public key extraction..."
        local manual_result
        manual_result=$(python3 -c "
import json
import base58
import sys

try:
    with open('$WALLET_PATH', 'r') as f:
        keypair = json.load(f)

    if len(keypair) == 64:
        # First 32 bytes for private key, last 32 bytes for public key
        public_key_bytes = bytes(keypair[32:64])
        public_key = base58.b58encode(public_key_bytes)
        print(public_key)
    else:
        print('INVALID_KEYPAIR_LENGTH')
        sys.exit(1)
except Exception as e:
    print(f'EXTRACTION_ERROR: {e}')
    sys.exit(1)
" 2>/dev/null)

        if [ "$manual_result" != "INVALID_KEYPAIR_LENGTH" ] && [ "$manual_result" != "EXTRACTION_ERROR" ]; then
            print_status "SUCCESS" "Public key extracted (fallback method): $manual_result"
            PUBLIC_KEY="$manual_result"

            if [ "$VERBOSE" = true ]; then
                echo "  Extraction method: Manual base58 fallback"
            fi
            return 0
        else
            print_status "ERROR" "Failed to extract public key (fallback method): $manual_result"
        fi
    else
        print_status "WARNING" "Python3 not available for fallback extraction"
    fi

    return 1
}

# Function to check network connectivity
check_network_connectivity() {
    print_status "PROGRESS" "Testing Solana network connectivity..."

    # Test RPC connection
    local rpc_url="https://api.mainnet-beta.solana.com"
    local slot_result
    slot_result=$(curl -s -X POST -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
        "$rpc_url" 2>/dev/null)

    if [ -n "$slot_result" ] && echo "$slot_result" | grep -q '"result"'; then
        local current_slot=$(echo "$slot_result" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['result'])
except:
    print('0')
" 2>/dev/null || echo "0")
        print_status "SUCCESS" "Solana RPC connection successful"
        print_status "INFO" "Current slot: $current_slot"

        if [ "$VERBOSE" = true ]; then
            echo "  RPC endpoint: $rpc_url"
            echo "  Method: getSlot"
        fi
        return 0
    else
        print_status "ERROR" "Failed to connect to Solana RPC"
        if [ "$VERBOSE" = true ]; then
            echo "  RPC endpoint: $rpc_url"
            echo "  Network may be unreachable"
        fi
        return 1
    fi
}

# Function to check balance
check_balance() {
    if command -v solana >/dev/null 2>&1; then
        print_status "PROGRESS" "Checking wallet balance..."

        local balance_result
        balance_result=$(solana balance "$WALLET_PATH" 2>/dev/null)

        if [ $? -eq 0 ]; then
            local balance_amount=$(echo "$balance_result" | awk '{print $1}')
            print_status "SUCCESS" "Wallet balance: $balance_amount SOL"

            if [ "$VERBOSE" = true ]; then
                echo "  Full result: $balance_result"
            fi

            # Check if balance is zero
            if [ "$balance_amount" = "0" ] || [ "$balance_amount" = "0.000000000" ]; then
                print_status "WARNING" "Wallet balance is zero - you may need SOL for transaction fees"
            fi
        else
            print_status "WARNING" "Failed to check wallet balance"
        fi
    else
        print_status "INFO" "Solana CLI not available for balance check"
    fi
}

# Function to validate environment variables
check_environment() {
    print_status "PROGRESS" "Validating environment variables..."

    # Check WALLET_ADDRESS
    if [ -n "$WALLET_ADDRESS" ]; then
        if [ -n "$PUBLIC_KEY" ]; then
            if [ "$WALLET_ADDRESS" = "$PUBLIC_KEY" ]; then
                print_status "SUCCESS" "WALLET_ADDRESS matches keypair public key"
            else
                print_status "ERROR" "WALLET_ADDRESS mismatch"
                if [ "$VERBOSE" = true ]; then
                    echo "  Environment WALLET_ADDRESS: $WALLET_ADDRESS"
                    echo "  Keypair PUBLIC_KEY: $PUBLIC_KEY"
                    echo "  These addresses should match"
                fi
                return 1
            fi
        else
            print_status "WARNING" "WALLET_ADDRESS set but public key extraction failed"
        fi
    else
        if [ -n "$PUBLIC_KEY" ]; then
            print_status "WARNING" "WALLET_ADDRESS not set"
            print_status "INFO" "Recommended: export WALLET_ADDRESS=$PUBLIC_KEY"
        else
            print_status "WARNING" "WALLET_ADDRESS not set and public key extraction failed"
        fi
    fi

    # Check WALLET_PRIVATE_KEY_PATH
    if [ -n "$WALLET_PRIVATE_KEY_PATH" ]; then
        if [ "$WALLET_PRIVATE_KEY_PATH" != "$WALLET_PATH" ]; then
            print_status "INFO" "Using custom wallet path: $WALLET_PRIVATE_KEY_PATH"

            if [ -f "$WALLET_PRIVATE_KEY_PATH" ]; then
                print_status "SUCCESS" "Custom wallet file found"
            else
                print_status "ERROR" "Custom wallet file not found: $WALLET_PRIVATE_KEY_PATH"
                return 1
            fi
        else
            if [ "$VERBOSE" = true ]; then
                echo "  Using default wallet path: $WALLET_PATH"
            fi
        fi
    else
        if [ "$VERBOSE" = true ]; then
            echo "  WALLET_PRIVATE_KEY_PATH not set, using default"
        fi
    fi

    return 0
}

# Function to check Solana CLI
check_solana_cli() {
    if command -v solana >/dev/null 2>&1; then
        local version
        version=$(solana --version 2>/dev/null | head -1)
        print_status "SUCCESS" "Solana CLI available: $version"

        if [ "$VERBOSE" = true ]; then
            echo "  Installation: solana-keygen, solana balance, etc."
        fi
        return 0
    else
        print_status "WARNING" "Solana CLI not available"
        if [ "$VERBOSE" = true ]; then
            echo "  Installation: sh -c \"\$(curl -sSfL https://release.solana.com/v1.36/install)\""
            echo "  Features: key generation, balance checking, etc."
        fi
        return 1
    fi
}

# Function to show wallet summary
show_wallet_summary() {
    print_status "INFO" "🔐 Wallet Verification Summary"
    echo ""

    echo "Configuration:"
    echo "  Wallet Path: $WALLET_PATH"
    echo "  Verbose Mode: $VERBOSE"
    echo "  Auto-Fix: $AUTO_FIX"
    echo ""

    echo "Results:"
    if [ $EXIT_CODE -eq 0 ]; then
        echo "  ✅ All checks passed - Wallet is ready for trading"
    elif [ $EXIT_CODE -eq 2 ]; then
        echo "  ⚠️  Some warnings found - Bot may still work"
    else
        echo "  ❌ Critical issues found - Fix before starting bot"
    fi

    if [ -n "$PUBLIC_KEY" ]; then
        echo ""
        echo "Public Key: $PUBLIC_KEY"
    fi

    echo ""
    print_status "INFO" "Next Steps:"
    if [ $EXIT_CODE -eq 0 ]; then
        echo "  • Start bot: ./scripts/start_bot.sh --mode=paper"
        echo "  • Monitor: tail -f logs/trading-bot-*.log"
    else
        echo "  • Fix issues above and re-run check"
        echo "  • Use --fix flag to auto-correct permissions"
        echo "  • See docs/WALLET_SETUP_GUIDE.md for help"
    fi
}

# Main verification function
main() {
    print_status "INFO" "🔐 MojoRust Trading Bot - Wallet Verification"
    print_status "INFO" "Starting comprehensive wallet check..."
    echo ""

    # Run all checks
    local check_result

    # Pre-flight checks
    if [ ! -f "$WALLET_PATH" ]; then
        print_status "INFO" "Checking Solana CLI availability..."
        check_solana_cli || true  # Continue even if CLI not available
    fi

    # Core wallet checks
    if ! check_file_existence; then
        EXIT_CODE=1
    fi

    if ! check_permissions; then
        if [ $? -eq 1 ]; then
            EXIT_CODE=1
        else
            EXIT_CODE=2
        fi
    fi

    if ! check_json_format; then
        EXIT_CODE=1
    fi

    if ! extract_public_key; then
        if [ $EXIT_CODE -eq 0 ]; then
            EXIT_CODE=1
        fi
    fi

    # Network checks
    if ! check_network_connectivity; then
        if [ $EXIT_CODE -eq 0 ]; then
            EXIT_CODE=1
        fi
    fi

    check_balance || true  # Balance check is non-critical

    # Environment validation
    if ! check_environment; then
        if [ $EXIT_CODE -eq 0 ]; then
            EXIT_CODE=1
        fi
    fi

    # Show summary
    show_wallet_summary

    # Exit with appropriate code
    exit $EXIT_CODE
}

# Handle script interruption gracefully
trap 'print_status "WARNING"; print_status "WARNING" "Wallet verification interrupted by user"; exit 130' INT TERM

# Run main function
main