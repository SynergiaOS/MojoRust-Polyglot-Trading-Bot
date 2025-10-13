#!/bin/bash

# =============================================================================
# 🔄 MojoRust Trading Bot - Update Dependencies Script
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
🔄 MojoRust Trading Bot - Update Dependencies Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --system-only       Update only system packages
    --rust-only         Update only Rust and Rust packages
    --mojo-only         Update only Mojo (if available)
    --skip-system       Skip system package updates
    --help, -h          Show this help message

EXAMPLES:
    $0                  # Update all dependencies
    $0 --rust-only      # Update Rust components only
    $0 --skip-system    # Skip system package updates

DESCRIPTION:
    This script updates all dependencies for the trading bot including:
    - System packages (apt/yum)
    - Rust toolchain and crates
    - Mojo (if installed)
    - Python packages (if needed)

    The script will backup current configurations before updating
    and verify installations after completion.

EXIT CODES:
    0   Success
    1   Error (update failed, dependency conflicts, etc.)

EOF
}

# Parse command line arguments
UPDATE_SYSTEM=true
UPDATE_RUST=true
UPDATE_MOJO=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --system-only)
            UPDATE_SYSTEM=true
            UPDATE_RUST=false
            UPDATE_MOJO=false
            shift
            ;;
        --rust-only)
            UPDATE_SYSTEM=false
            UPDATE_RUST=true
            UPDATE_MOJO=false
            shift
            ;;
        --mojo-only)
            UPDATE_SYSTEM=false
            UPDATE_RUST=false
            UPDATE_MOJO=true
            shift
            ;;
        --skip-system)
            UPDATE_SYSTEM=false
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

# Function to detect package manager
detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Function to update system packages
update_system_packages() {
    print_status "PROGRESS" "Updating system packages..."

    local pkg_manager=$(detect_package_manager)
    local update_success=false

    case $pkg_manager in
        "apt")
            print_status "INFO" "Using apt package manager"

            # Update package list
            print_status "INFO" "Updating package list..."
            if sudo apt update; then
                print_status "SUCCESS" "Package list updated"
            else
                print_status "ERROR" "Failed to update package list"
                return 1
            fi

            # Upgrade packages
            print_status "INFO" "Upgrading packages..."
            if sudo apt upgrade -y; then
                print_status "SUCCESS" "System packages upgraded"
                update_success=true
            else
                print_status "ERROR" "Failed to upgrade packages"
                return 1
            fi

            # Install essential packages if missing
            print_status "INFO" "Checking essential packages..."
            local essential_packages="build-essential pkg-config libssl-dev curl wget git"
            if sudo apt install -y $essential_packages; then
                print_status "SUCCESS" "Essential packages verified"
            else
                print_status "WARNING" "Some essential packages may be missing"
            fi
            ;;

        "yum"|"dnf")
            print_status "INFO" "Using $pkg_manager package manager"

            # Update packages
            print_status "INFO" "Updating packages..."
            if sudo $pkg_manager update -y; then
                print_status "SUCCESS" "System packages updated"
                update_success=true
            else
                print_status "ERROR" "Failed to update packages"
                return 1
            fi

            # Install development tools
            print_status "INFO" "Installing development tools..."
            local dev_packages="gcc gcc-c++ make openssl-devel curl wget git"
            if sudo $pkg_manager groupinstall -y "Development Tools" && sudo $pkg_manager install -y $dev_packages; then
                print_status "SUCCESS" "Development tools installed"
            else
                print_status "WARNING" "Some development tools may be missing"
            fi
            ;;

        "pacman")
            print_status "INFO" "Using pacman package manager"

            # Update packages
            print_status "INFO" "Updating packages..."
            if sudo pacman -Syu --noconfirm; then
                print_status "SUCCESS" "System packages updated"
                update_success=true
            else
                print_status "ERROR" "Failed to update packages"
                return 1
            fi

            # Install base development packages
            print_status "INFO" "Installing base development packages..."
            local dev_packages="base-devel curl wget git"
            if sudo pacman -S --noconfirm $dev_packages; then
                print_status "SUCCESS" "Development packages installed"
            else
                print_status "WARNING" "Some development packages may be missing"
            fi
            ;;

        "unknown")
            print_status "WARNING" "Unknown package manager, skipping system updates"
            return 0
            ;;
    esac

    if [ "$update_success" = true ]; then
        print_status "SUCCESS" "✅ System packages updated successfully"
    else
        print_status "ERROR" "❌ System package update failed"
        return 1
    fi
}

# Function to update Rust
update_rust() {
    print_status "PROGRESS" "Updating Rust toolchain..."

    # Check if Rust is installed
    if ! command -v rustup >/dev/null 2>&1; then
        print_status "WARNING" "Rust not installed via rustup, skipping update"
        return 0
    fi

    local rust_current=$(rustc --version 2>/dev/null || echo "unknown")
    print_status "INFO" "Current Rust version: $rust_current"

    # Update Rust toolchain
    print_status "INFO" "Updating Rust toolchain..."
    if rustup update; then
        print_status "SUCCESS" "Rust toolchain updated"
    else
        print_status "ERROR" "Failed to update Rust toolchain"
        return 1
    fi

    # Show new version
    local rust_new=$(rustc --version 2>/dev/null || echo "unknown")
    print_status "INFO" "New Rust version: $rust_new"

    # Update Rust components
    print_status "INFO" "Updating Rust components..."
    if rustup component add rust-src rustfmt clippy 2>/dev/null; then
        print_status "SUCCESS" "Rust components updated"
    else
        print_status "WARNING" "Some Rust components may not be available"
    fi

    # Check if we're in a Rust project and update dependencies
    if [ -f "Cargo.toml" ]; then
        print_status "INFO" "Found Cargo.toml, updating Rust dependencies..."

        # Clean and rebuild
        print_status "INFO" "Cleaning previous build..."
        if cargo clean 2>/dev/null; then
            print_status "SUCCESS" "Build cleaned"
        fi

        print_status "INFO" "Updating Cargo dependencies..."
        if cargo update; then
            print_status "SUCCESS" "Cargo dependencies updated"
        else
            print_status "WARNING" "Cargo update had issues, continuing anyway"
        fi

        # Check build
        print_status "INFO" "Verifying build..."
        if cargo check; then
            print_status "SUCCESS" "Project builds correctly"
        else
            print_status "WARNING" "Project has build issues, update may have introduced conflicts"
        fi
    fi

    print_status "SUCCESS" "✅ Rust update completed"
}

# Function to update Mojo
update_mojo() {
    print_status "PROGRESS" "Updating Mojo..."

    # Check if Mojo is installed
    local mojo_cmd=""
    if command -v mojo >/dev/null 2>&1; then
        mojo_cmd="mojo"
    elif [ -f "$HOME/.modular/bin/mojo" ]; then
        mojo_cmd="$HOME/.modular/bin/mojo"
        export PATH="$HOME/.modular/bin:$PATH"
    else
        print_status "WARNING" "Mojo not found, skipping update"
        return 0
    fi

    local mojo_current=$($mojo_cmd --version 2>/dev/null || echo "unknown")
    print_status "INFO" "Current Mojo version: $mojo_current"

    # Try to update via modular CLI if available
    if command -v modular >/dev/null 2>&1; then
        print_status "INFO" "Updating via modular CLI..."
        if modular update; then
            print_status "SUCCESS" "Mojo updated via modular CLI"

            # Show new version
            local mojo_new=$($mojo_cmd --version 2>/dev/null || echo "unknown")
            print_status "INFO" "New Mojo version: $mojo_new"
        else
            print_status "WARNING" "Modular CLI update failed"
        fi
    else
        print_status "WARNING" "Modular CLI not found, cannot update Mojo automatically"
        print_status "INFO" "To update Mojo manually, visit: https://docs.modular.com/mojo/manual/install/"
    fi

    # Check if we can build a simple Mojo program
    if [ -f "src/main.mojo" ]; then
        print_status "INFO" "Testing Mojo build..."
        if $mojo_cmd build src/main.mojo 2>/dev/null; then
            print_status "SUCCESS" "Mojo build test passed"
        else
            print_status "WARNING" "Mojo build test failed, may need manual intervention"
        fi
    fi

    print_status "SUCCESS" "✅ Mojo update completed"
}

# Function to update Python packages (if needed)
update_python_packages() {
    # Check if Python is used in the project
    if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || find . -name "*.py" -type f | head -1 | grep -q .; then
        print_status "INFO" "Python files found, updating Python packages..."

        if command -v pip >/dev/null 2>&1; then
            print_status "INFO" "Updating pip..."
            if pip install --upgrade pip; then
                print_status "SUCCESS" "pip updated"
            else
                print_status "WARNING" "Failed to update pip"
            fi

            if [ -f "requirements.txt" ]; then
                print_status "INFO" "Installing Python requirements..."
                if pip install -r requirements.txt; then
                    print_status "SUCCESS" "Python requirements installed"
                else
                    print_status "WARNING" "Some Python requirements may have failed"
                fi
            fi
        else
            print_status "INFO" "pip not found, skipping Python updates"
        fi
    else
        print_status "INFO" "No Python files found, skipping Python updates"
    fi
}

# Function to verify installations
verify_installations() {
    print_status "PROGRESS" "Verifying installations..."

    # Verify Rust
    if command -v rustc >/dev/null 2>&1; then
        local rust_version=$(rustc --version)
        print_status "SUCCESS" "Rust verified: $rust_version"
    else
        print_status "WARNING" "Rust not found"
    fi

    # Verify Cargo
    if command -v cargo >/dev/null 2>&1; then
        local cargo_version=$(cargo --version)
        print_status "SUCCESS" "Cargo verified: $cargo_version"
    else
        print_status "WARNING" "Cargo not found"
    fi

    # Verify Mojo
    local mojo_cmd=""
    if command -v mojo >/dev/null 2>&1; then
        mojo_cmd="mojo"
    elif [ -f "$HOME/.modular/bin/mojo" ]; then
        mojo_cmd="$HOME/.modular/bin/mojo"
    fi

    if [ -n "$mojo_cmd" ]; then
        local mojo_version=$($mojo_cmd --version 2>/dev/null || echo "version check failed")
        print_status "SUCCESS" "Mojo verified: $mojo_version"
    else
        print_status "WARNING" "Mojo not found"
    fi

    # Verify Git
    if command -v git >/dev/null 2>&1; then
        local git_version=$(git --version)
        print_status "SUCCESS" "Git verified: $git_version"
    else
        print_status "WARNING" "Git not found"
    fi
}

# Function to show update summary
show_summary() {
    print_status "INFO" "📊 Update Summary:"
    echo ""

    echo "Updated components:"
    [ "$UPDATE_SYSTEM" = true ] && echo "  ✅ System packages"
    [ "$UPDATE_RUST" = true ] && echo "  ✅ Rust toolchain and dependencies"
    [ "$UPDATE_MOJO" = true ] && echo "  ✅ Mojo (if available)"

    echo ""
    print_status "INFO" "Next steps:"
    echo "  • Restart the trading bot: ./scripts/restart_bot.sh"
    echo "  • Check system health: ./scripts/server_health.sh"
    echo "  • Run tests: cargo test (if available)"

    echo ""
    print_status "SUCCESS" "✅ Dependency update completed!"
}

# Main execution
main() {
    print_status "INFO" "🔄 MojoRust Trading Bot - Update Dependencies Script"
    echo ""

    local start_time=$(date +%s)
    local update_errors=0

    # Create backup of current state
    if [ -f "Cargo.lock" ]; then
        print_status "INFO" "Creating backup of Cargo.lock..."
        cp Cargo.lock Cargo.lock.backup.$(date +%Y%m%d_%H%M%S)
    fi

    # Update based on flags
    if [ "$UPDATE_SYSTEM" = true ]; then
        if ! update_system_packages; then
            ((update_errors++))
        fi
    fi

    if [ "$UPDATE_RUST" = true ]; then
        if ! update_rust; then
            ((update_errors++))
        fi
    fi

    if [ "$UPDATE_MOJO" = true ]; then
        if ! update_mojo; then
            ((update_errors++))
        fi
    fi

    # Update Python packages if needed
    update_python_packages

    # Verify installations
    verify_installations

    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local duration_minutes=$((duration / 60))
    local duration_seconds=$((duration % 60))

    # Show summary
    show_summary
    print_status "INFO" "Update completed in ${duration_minutes}m ${duration_seconds}s"

    # Exit with error code if there were any errors
    if [ $update_errors -gt 0 ]; then
        print_status "ERROR" "❌ $update_errors error(s) occurred during update"
        exit 1
    else
        exit 0
    fi
}

# Handle script interruption gracefully
trap 'print_status "WARNING"; print_status "WARNING" "Update interrupted by user"; exit 130' INT TERM

# Run main function
main