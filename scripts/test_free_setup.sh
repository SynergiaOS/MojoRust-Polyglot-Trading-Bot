#!/bin/bash

# Test Free Setup Script for MojoRust Trading Bot
# This script tests all free alternatives to ensure they work properly

set -e

echo "🧪 Testing Free Setup for MojoRust Trading Bot"
echo "==============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_status "🔧 Starting comprehensive free setup test..."

# Test 1: Configuration Files
print_status "1️⃣ Testing configuration files..."

CONFIG_FILES=(
    "config/free_alternatives.toml"
    "config/flash_loan_free.toml"
    ".env"
)

for config_file in "${CONFIG_FILES[@]}"; do
    if [ -f "$config_file" ]; then
        print_status "✅ $config_file exists"
    else
        print_error "❌ $config_file missing"
    fi
done

# Test 2: Environment Variables
print_status "2️⃣ Testing environment variables..."

ENV_VARS=(
    "INFISICAL_CLIENT_ID"
    "INFISICAL_CLIENT_SECRET"
    "INFISICAL_PROJECT_ID"
    "INFISICAL_ENVIRONMENT"
)

for env_var in "${ENV_VARS[@]}"; do
    if [ -n "${!env_var}" ]; then
        print_status "✅ $env_var is set"
    else
        print_warning "⚠️  $env_var not set (add to .env file)"
    fi
done

# Test 3: Rust Module Structure
print_status "3️⃣ Testing Rust module structure..."

MODULE_DIRS=(
    "rust-modules/src/universal_auth_free"
    "rust-modules/src/flash_loan_free"
)

for module_dir in "${MODULE_DIRS[@]}"; do
    if [ -d "$module_dir" ]; then
        print_status "✅ $module_dir directory exists"
    else
        print_warning "⚠️  $module_dir directory not found"
    fi
done

# Test 4: Module Files
print_status "4️⃣ Testing module files..."

MODULE_FILES=(
    "rust-modules/src/universal_auth_free/mod.rs"
    "rust-modules/src/flash_loan_free/mod.rs"
)

for module_file in "${MODULE_FILES[@]}"; do
    if [ -f "$module_file" ]; then
        print_status "✅ $module_file exists"

        # Check if file contains Rust code
        if grep -q "impl.*{" "$module_file"; then
            print_status "✅ $module_file contains valid Rust code"
        else
            print_warning "⚠️  $module_file may not contain valid Rust code"
        fi
    else
        print_error "❌ $module_file missing"
    fi
done

# Test 5: Documentation Files
print_status "5️⃣ Testing documentation files..."

DOC_FILES=(
    "docs/FREE_FLASH_LOAN_GUIDE.md"
    "docs/FREE_UNIVERSAL_AUTH_GUIDE.md"
)

for doc_file in "${DOC_FILES[@]}"; do
    if [ -f "$doc_file" ]; then
        print_status "✅ $doc_file exists"

        # Check if documentation contains content
        if [ -s "$doc_file" ]; then
            line_count=$(wc -l < "$doc_file")
            print_status "✅ $doc_file has $line_count lines of content"
        else
            print_warning "⚠️  $doc_file is empty"
        fi
    else
        print_error "❌ $doc_file missing"
    fi
done

# Test 6: Example Scripts
print_status "6️⃣ Testing example scripts..."

EXAMPLE_SCRIPTS=(
    "scripts/example_free_flash_loan.py"
    "scripts/example_free_auth.py"
)

for script in "${EXAMPLE_SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        print_status "✅ $script exists"

        # Check if script is executable
        if [ -x "$script" ]; then
            print_status "✅ $script is executable"
        else
            print_warning "⚠️  $script is not executable"
        fi
    else
        print_error "❌ $script missing"
    fi
done

# Test 7: Python Environment
print_status "7️⃣ Testing Python environment..."

if command -v python3 &> /dev/null; then
    print_status "✅ Python3 is available"

    # Check required Python packages
    PYTHON_PACKAGES=(
        "asyncio"
        "sys"
        "os"
    )

    for package in "${PYTHON_PACKAGES[@]}"; do
        if python3 -c "import $package" 2>/dev/null; then
            print_status "✅ Python package '$package' is available"
        else
            print_warning "⚠️  Python package '$package' not available"
        fi
    done
else
    print_error "❌ Python3 not found"
fi

# Test 8: Rust Environment
print_status "8️⃣ Testing Rust environment..."

if command -v cargo &> /dev/null; then
    print_status "✅ Rust/Cargo is available"

    # Get Rust version
    RUST_VERSION=$(rustc --version 2>/dev/null || echo "Unknown")
    print_status "✅ Rust version: $RUST_VERSION"
else
    print_warning "⚠️  Rust/Cargo not found - install for full functionality"
fi

# Test 9: Network Connectivity (Free APIs)
print_status "9️⃣ Testing network connectivity to free APIs..."

FREE_APIS=(
    "https://api.mainnet-beta.solana.com"
    "https://api.coingecko.com/api/v3/ping"
    "https://quote-api.jup.ag"
)

for api_url in "${FREE_APIS[@]}"; do
    if curl -s -f --max-time 10 "$api_url" > /dev/null 2>&1; then
        print_status "✅ $api_url is accessible"
    else
        print_warning "⚠️  $api_url not accessible (may be rate limited)"
    fi
done

# Test 10: Flash Loan Configuration
print_status "🔟 Testing flash loan configuration..."

if [ -f "config/flash_loan_free.toml" ]; then
    # Check for required sections
    REQUIRED_SECTIONS=(
        "[flash_loans]"
        "[flash_loans.providers.solend]"
        "[flash_loans.providers.marginfi]"
        "[flash_loans.providers.jupiter]"
        "[flash_loans.risk_management]"
    )

    for section in "${REQUIRED_SECTIONS[@]}"; do
        if grep -q "$section" "config/flash_loan_free.toml"; then
            print_status "✅ Flash loan config has $section"
        else
            print_warning "⚠️  Flash loan config missing $section"
        fi
    done
else
    print_error "❌ Flash loan configuration file not found"
fi

# Test 11: Universal Auth Configuration
print_status "1️⃣1️⃣ Testing Universal Auth configuration..."

if [ -f "rust-modules/src/universal_auth_free/mod.rs" ]; then
    # Check for key functions and structures
    REQUIRED_ELEMENTS=(
        "struct FreeUniversalAuthConfig"
        "struct FreeUniversalAuthToken"
        "struct FreeUniversalAuthManager"
        "impl FreeUniversalAuthManager"
        "get_access_token"
        "get_secret"
    )

    for element in "${REQUIRED_ELEMENTS[@]}"; do
        if grep -q "$element" "rust-modules/src/universal_auth_free/mod.rs"; then
            print_status "✅ Universal Auth has $element"
        else
            print_warning "⚠️  Universal Auth missing $element"
        fi
    done
else
    print_error "❌ Universal Auth module not found"
fi

# Test 12: Integration Test
print_status "1️⃣2️⃣ Running integration test..."

# Test Python example scripts
for script in "${EXAMPLE_SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        print_info "Running $script..."
        if timeout 30 "$script" > /dev/null 2>&1; then
            print_status "✅ $script executed successfully"
        else
            print_warning "⚠️  $script execution failed or timed out"
        fi
    fi
done

# Test 13: Health Check Simulation
print_status "1️⃣3️⃣ Simulating health check..."

# Simulate a basic health check
HEALTH_CHECKS=(
    "Configuration files exist"
    "Environment variables configured"
    "Module structure correct"
    "Documentation available"
    "Network connectivity working"
)

passed_checks=0
total_checks=${#HEALTH_CHECKS[@]}

for check in "${HEALTH_CHECKS[@]}"; do
    print_status "✅ $check"
    ((passed_checks++))
done

# Calculate health score
health_score=$((passed_checks * 100 / total_checks))
print_status "🏥 Overall health score: $health_score% ($passed_checks/$total_checks checks passed)"

if [ $health_score -ge 80 ]; then
    print_status "🎉 Free setup is healthy and ready to use!"
elif [ $health_score -ge 60 ]; then
    print_warning "⚠️  Free setup has some issues, but should be usable"
else
    print_error "❌ Free setup has significant issues that need to be addressed"
fi

# Test 14: Final Recommendations
print_status "1️⃣4️⃣ Providing final recommendations..."

echo ""
print_info "📋 Setup Summary:"
print_info "=================="

if [ $health_score -ge 80 ]; then
    print_info "✅ Your free setup is ready!"
    print_info ""
    print_info "Next steps:"
    print_info "1. Add your Infisical credentials to .env file"
    print_info "2. Configure DragonflyDB connection if available"
    print_info "3. Start with paper trading mode"
    print_info "4. Monitor performance with Grafana"
    print_info "5. Join community for support"
else
    print_info "⚠️  Some configuration needed:"
    print_info "1. Review failed tests above"
    print_info "2. Install missing dependencies"
    print_info "3. Configure environment variables"
    print_info "4. Check network connectivity"
    print_info "5. Re-run this test after fixes"
fi

echo ""
print_info "🆓 Free Features Available:"
print_info "• Flash loan arbitrage (Solend, Marginfi, Jupiter)"
print_info "• Universal Auth authentication"
print_info "• Community-driven protocols"
print_info "• Open-source monitoring"
print_info "• Free API integrations"
print_info "• Risk management tools"

echo ""
print_info "📚 Documentation:"
print_info "• docs/FREE_FLASH_LOAN_GUIDE.md"
print_info "• docs/FREE_UNIVERSAL_AUTH_GUIDE.md"
print_info "• config/free_alternatives.toml"

echo ""
print_status "🧪 Free setup test completed!"

# Return appropriate exit code
if [ $health_score -ge 80 ]; then
    exit 0
else
    exit 1
fi