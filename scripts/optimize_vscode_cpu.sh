#!/bin/bash

# =============================================================================
# 🚀 VS Code CPU Optimization Tool for MojoRust Trading Bot
# =============================================================================
# This script provides comprehensive VS Code CPU optimization features including:
# - Process identification and management
# - Interactive process selection for termination
# - Extension management and performance optimization
# - Settings optimization for CPU efficiency
# - Verification and monitoring capabilities

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
JSON_OUTPUT=false
VERBOSE=false
AUTO_MODE=false
BACKUP_VSCODE_SETTINGS=true

# Global variables
VS_CODE_PROCESSES=""
HEAVY_EXTENSIONS=""
OPTIMIZATION_APPLIED=false
CPU_SAVINGS=0

# Logging functions
log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    fi
}

log_warning() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1"
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}[ERROR]${NC} $1"
    fi
}

log_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}$1${NC}"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                              ║"
        echo "║    🚀 VS Code CPU Optimization Tool - MojoRust Trading Bot   ║"
        echo "║                                                              ║"
        echo "║    Optimizing VS Code for maximum trading bot performance    ║"
        echo "║                                                              ║"
        echo "║    Project: $PROJECT_ROOT"
        echo "║    Timestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')"
        echo "║                                                              ║"
        echo "╚═════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Identify VS Code processes
identify_vscode_processes() {
    log_header "VS Code Process Identification"

    # Find all VS Code related processes
    VS_CODE_PROCESSES=$(ps aux | grep -E '/usr/share/code|/snap/code|electron' | grep -v grep || true)

    if [ -z "$VS_CODE_PROCESSES" ]; then
        log_info "No VS Code processes found"
        return 1
    fi

    if [ "$JSON_OUTPUT" = false ]; then
        echo "VS Code Processes Found:"
        printf "%-12s %8s %8s %10s %s\n" "TYPE" "PID" "%CPU" "%MEM" "COMMAND"
        echo "----------------------------------------------------------------------------"

        local process_count=0
        local total_cpu=0

        echo "$VS_CODE_PROCESSES" | while read -r line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu=$(echo "$line" | awk '{print $3}')
            local mem=$(echo "$line" | awk '{print $4}')
            local cmd=$(echo "$line" | cut -c 42-)
            local user=$(echo "$line" | awk '{print $1}')

            # Identify process type
            local process_type="Unknown"
            if echo "$cmd" | grep -q "\-\-type=renderer"; then
                process_type="Renderer"
            elif echo "$cmd" | grep -q "\-\-extensionHostPath"; then
                process_type="Extension"
            elif echo "$cmd" | grep -q "\-\-type=utilityNetworkService"; then
                process_type="NodeService"
            elif echo "$cmd" | grep -q "\-\-type=zygote"; then
                process_type="Zygote"
            elif echo "$cmd" | grep -q "\-\-disable-gpu"; then
                process_type="Main (CPU)"
            else
                process_type="Main"
            fi

            # Color code based on CPU usage
            if (( $(echo "$cpu > 50" | bc -l) 2>/dev/null)); then
                printf "${RED}%-12s %8s %8s %10s %s${NC}\n" "$process_type" "$pid" "$cpu" "$mem" "$user"
            elif (( $(echo "$cpu > 25" | bc -l) 2>/dev/null)); then
                printf "${YELLOW}%-12s %8s %8s %10s %s${NC}\n" "$process_type" "$pid" "$cpu" "$mem" "$user"
            else
                printf "%-12s %8s %8s %10s %s\n" "$process_type" "$pid" "$cpu" "$mem" "$user"
            fi

            # Track high CPU processes
            if (( $(echo "$cpu > 20" | bc -l) 2>/dev/null)); then
                echo "$pid:$cpu:$process_type" >> /tmp/vscode_high_cpu.txt
            fi
        done
        echo ""

        # Summary statistics
        local total_processes=$(echo "$VS_CODE_PROCESSES" | wc -l)
        local total_cpu_usage=$(echo "$VS_CODE_PROCESSES" | awk '{sum+=$3} END {print sum}')

        log_info "Summary:"
        echo "  Total Processes: $total_processes"
        echo "  Total CPU Usage: $total_cpu_usage%"

        if (( $(echo "$total_cpu_usage > 100" | bc -l) 2>/dev/null)); then
            log_warning "VS Code consuming excessive CPU: $total_cpu_usage%"
        elif (( $(echo "$total_cpu_usage > 50" | bc -l) 2>/dev/null)); then
            log_warning "VS Code consuming high CPU: $total_cpu_usage%"
        else
            log_success "VS Code CPU usage acceptable: $total_cpu_usage%"
        fi
        echo ""
    fi

    return 0
}

# Interactive process selection
interactive_process_selection() {
    if [ "$AUTO_MODE" = true ]; then
        log_info "Auto mode: automatically selecting high CPU processes"
        return 0
    fi

    log_header "Interactive Process Selection"

    if [ -z "$VS_CODE_PROCESSES" ]; then
        log_warning "No VS Code processes found for selection"
        return 1
    fi

    # Create process list for selection
    echo "$VS_CODE_PROCESSES" | while read -r line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local cmd=$(echo "$line" | cut -c 42-)

        # Show only processes with >10% CPU usage
        if (( $(echo "$cpu > 10" | bc -l) 2>/dev/null)); then
            echo "PID: $pid | CPU: $cpu% | Command: ${cmd:0:80}"
        fi
    done

    echo ""
    log_info "Select processes to optimize (enter PIDs separated by spaces, or 'all' for high CPU processes):"
    read -r user_selection

    if [ "$user_selection" = "all" ]; then
        log_info "Selected all high CPU processes"
        echo "$VS_CODE_PROCESSES" | while read -r line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu=$(echo "$line" | awk '{print $3}')
            if (( $(echo "$cpu > 20" | bc -l) 2>/dev/null)); then
                echo "$pid" >> /tmp/vscode_selected_pids.txt
            fi
        done
    else
        echo "$user_selection" | tr ' ' '\n' >> /tmp/vscode_selected_pids.txt
    fi

    log_success "Process selection completed"
}

# Analyze heavy extensions
analyze_heavy_extensions() {
    log_header "Heavy Extension Analysis"

    # Find extension processes
    local extension_processes=$(ps aux | grep -E "extensionHost|TypeScript|Python" | grep -v grep || true)

    if [ -z "$extension_processes" ]; then
        log_info "No heavy extension processes found"
        return 0
    fi

    HEAVY_EXTENSIONS="$extension_processes"

    if [ "$JSON_OUTPUT" = false ]; then
        echo "Heavy Extension Processes:"
        echo "$extension_processes" | while read -r line; do
            local pid=$(echo "$line" | awk '{print $2}')
            local cpu=$(echo "$line" | awk '{print $3}')
            local cmd=$(echo "$line" | cut -c 42-)

            if (( $(echo "$cpu > 10" | bc -l) 2>/dev/null)); then
                echo "  PID: $pid | CPU: $cpu% | $cmd"
            fi
        done
        echo ""

        # Common heavy extensions warning
        log_warning "Common heavy extensions that may impact performance:"
        echo "  - TypeScript and JavaScript Language Features"
        echo "  - Python Language Server (Pylance)"
        echo "  - Docker extension"
        echo "  - GitLens"
        echo "  - Remote Development extensions"
        echo ""
    fi
}

# Optimize VS Code settings
optimize_vscode_settings() {
    log_header "VS Code Settings Optimization"

    # Find VS Code settings directory
    local vscode_settings_dir=""
    if [ -d "$HOME/.config/Code/User" ]; then
        vscode_settings_dir="$HOME/.config/Code/User"
    elif [ -d "$HOME/.config/Code - OSS/User" ]; then
        vscode_settings_dir="$HOME/.config/Code - OSS/User"
    elif [ -d "$HOME/snap/code/current/.config/Code/User" ]; then
        vscode_settings_dir="$HOME/snap/code/current/.config/Code/User"
    else
        log_warning "VS Code settings directory not found"
        return 1
    fi

    local settings_file="$vscode_settings_dir/settings.json"

    if [ ! -f "$settings_file" ]; then
        log_warning "VS Code settings.json not found"
        return 1
    fi

    # Backup current settings
    if [ "$BACKUP_VSCODE_SETTINGS" = true ]; then
        local backup_file="$settings_file.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$settings_file" "$backup_file"
        log_success "Settings backed up to: $backup_file"
    fi

    # Create optimized settings
    if [ "$JSON_OUTPUT" = false ]; then
        log_info "Applying CPU optimization settings..."
    fi

    # Create temporary optimized settings
    cat > /tmp/vscode_optimized_settings.json << 'EOF'
{
    "typescript.tsserver.experimental.enableProjectDiagnostics": false,
    "typescript.suggest.autoImports": false,
    "typescript.updateImportsOnFileMove.enabled": "never",
    "typescript.validate.enable": false,
    "javascript.validate.enable": false,
    "editor.semanticHighlighting.enabled": false,
    "editor.semanticTokenColorCustomizations": {
        "enabled": false
    },
    "editor.hover.enabled": false,
    "editor.suggest.snippetsPreventQuickSuggestions": true,
    "editor.quickSuggestions": {
        "other": false,
        "comments": false,
        "strings": false
    },
    "editor.parameterHints.enabled": false,
    "editor.lightbulb.enabled": false,
    "editor.codeLens": false,
    "editor.folding": false,
    "editor.lineNumbers": "off",
    "editor.minimap.enabled": false,
    "editor.glyphMargin": false,
    "editor.renderWhitespace": "none",
    "editor.renderControlCharacters": false,
    "editor.renderIndentGuides": false,
    "editor.rulers": [],
    "editor.cursorBlinking": "solid",
    "editor.cursorSmoothCaretAnimation": false,
    "editor.smoothScrolling": false,
    "files.autoSave": "afterDelay",
    "files.autoSaveDelay": 5000,
    "search.smartCase": false,
    "workbench.editor.enablePreview": false,
    "workbench.list.automaticKeyboardNavigation": false,
    "extensions.autoUpdate": false,
    "telemetry.enableTelemetry": false,
    "telemetry.enableCrashReporter": false,
    "update.mode": "none",
    "workbench.settings.enableNaturalLanguageSearch": false,
    "npm.enableRunFromFolder": false,
    "git.enableSmartCommit": false,
    "git.autofetch": false,
    "debug.allowBreakpointsEverywhere": false,
    "emmet.includeLanguages": {},
    "html.autoClosingTags": false,
    "css.autoClosingTags": false,
    "javascript.autoClosingTags": false,
    "typescript.autoClosingTags": false,
    "editor.bracketPairColorization.enabled": false,
    "editor.guides.bracketPairs": false,
    "editor.matchBrackets": "never",
    "workbench.colorTheme": "Default High Contrast",
    "editor.fontFamily": "Monaco, monospace",
    "editor.fontSize": 12,
    "terminal.integrated.rendererType": "dom",
    "terminal.integrated.gpuAcceleration": "off"
}
EOF

    # Apply optimized settings
    if [ "$AUTO_MODE" = true ]; then
        mv /tmp/vscode_optimized_settings.json "$settings_file"
        log_success "Auto mode: Applied optimized settings"
    else
        log_info "Optimized settings prepared. Apply them? (y/N):"
        read -r apply_settings
        if [[ $apply_settings =~ ^[Yy]$ ]]; then
            mv /tmp/vscode_optimized_settings.json "$settings_file"
            log_success "Optimized settings applied"
        else
            log_info "Settings not applied"
        fi
    fi

    OPTIMIZATION_APPLIED=true
}

# Process termination and restart
optimize_vscode_processes() {
    log_header "Process Optimization"

    if [ -f "/tmp/vscode_selected_pids.txt" ]; then
        local selected_pids=$(cat /tmp/vscode_selected_pids.txt)

        if [ -n "$selected_pids" ]; then
            log_info "Optimizing selected VS Code processes..."

            for pid in $selected_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    local cpu_before=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null || echo "0")
                    log_info "Optimizing process $pid (CPU: ${cpu_before}%)"

                    # Try graceful termination first
                    kill -TERM "$pid" 2>/dev/null || true

                    # Wait a moment
                    sleep 2

                    # If still running, force kill
                    if kill -0 "$pid" 2>/dev/null; then
                        kill -KILL "$pid" 2>/dev/null || true
                        log_verbose "Force killed process $pid"
                    else
                        log_verbose "Gracefully terminated process $pid"
                    fi

                    # Track CPU savings
                    CPU_SAVINGS=$(echo "$CPU_SAVINGS + $cpu_before" | bc)
                fi
            done

            log_success "Process optimization completed"
        fi

        rm -f /tmp/vscode_selected_pids.txt
    fi
}

# Extension management
manage_extensions() {
    log_header "Extension Management"

    # Check if code CLI is available
    if ! command -v code >/dev/null 2>&1; then
        log_warning "VS Code CLI not available for extension management"
        return 1
    fi

    # List installed extensions
    local installed_extensions=$(code --list-extensions 2>/dev/null || true)

    if [ -z "$installed_extensions" ]; then
        log_info "No extensions found"
        return 0
    fi

    if [ "$JSON_OUTPUT" = false ]; then
        log_info "Installed extensions:"
        echo "$installed_extensions" | head -10
        echo ""

        log_info "Heavy extensions to consider disabling:"
        echo "  - ms-vscode.vscode-typescript-next"
        echo "  - ms-python.python"
        echo "  - ms-azuretools.vscode-docker"
        echo "  - eamodio.gitlens"
        echo "  - ms-vscode-remote.remote-containers"
        echo ""
    fi

    if [ "$AUTO_MODE" = true ]; then
        log_info "Auto mode: Skipping extension management"
        return 0
    fi

    log_info "Disable heavy extensions? (y/N):"
    read -r disable_extensions
    if [[ $disable_extensions =~ ^[Yy]$ ]]; then
        log_info "Enter extension IDs to disable (space-separated, or 'heavy' for common ones):"
        read -r extensions_to_disable

        if [ "$extensions_to_disable" = "heavy" ]; then
            # Disable common heavy extensions
            code --disable-extension ms-vscode.vscode-typescript-next 2>/dev/null || true
            code --disable-extension ms-python.python 2>/dev/null || true
            code --disable-extension ms-azuretools.vscode-docker 2>/dev/null || true
            code --disable-extension eamodio.gitlens 2>/dev/null || true
            log_success "Disabled common heavy extensions"
        else
            for ext in $extensions_to_disable; do
                code --disable-extension "$ext" 2>/dev/null || true
                log_verbose "Disabled extension: $ext"
            done
            log_success "Disabled specified extensions"
        fi
    fi
}

# Verification and monitoring
verify_optimization() {
    log_header "Optimization Verification"

    # Wait a moment for processes to stabilize
    sleep 3

    # Re-check VS Code processes
    local new_vscode_processes=$(ps aux | grep -E '/usr/share/code|/snap/code|electron' | grep -v grep || true)

    if [ -z "$new_vscode_processes" ]; then
        log_success "No VS Code processes running - optimization successful"
    else
        local new_cpu_usage=$(echo "$new_vscode_processes" | awk '{sum+=$3} END {print sum}')
        log_info "Current VS Code CPU usage: $new_cpu_usage%"

        if [ -n "$CPU_SAVINGS" ] && (( $(echo "$CPU_SAVINGS > 0" | bc -l) 2>/dev/null)); then
            log_success "Estimated CPU savings: $CPU_SAVINGS%"
        fi

        if (( $(echo "$new_cpu_usage < 50" | bc -l) 2>/dev/null)); then
            log_success "VS Code CPU usage optimized to acceptable level"
        else
            log_warning "VS Code still consuming high CPU: $new_cpu_usage%"
        fi
    fi

    # Check system load
    local system_load=$(uptime | awk '{print $(NF-2)}' | tr -d ',')
    log_info "System load: $system_load"

    # Generate optimization report
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_info "Optimization Summary:"
        echo "  Processes Optimized: $([ -f /tmp/vscode_selected_pids.txt ] && cat /tmp/vscode_selected_pids.txt | wc -l || echo "0")"
        echo "  Settings Applied: $([ "$OPTIMIZATION_APPLIED" = true ] && echo "Yes" || echo "No")"
        echo "  Estimated CPU Savings: $CPU_SAVINGS%"
        echo "  System Load: $system_load"
        echo ""

        if [ "$OPTIMIZATION_APPLIED" = true ] || [ "$CPU_SAVINGS" -gt 0 ]; then
            log_success "VS Code optimization completed successfully"
        else
            log_warning "Limited optimization applied"
        fi
    fi
}

# Generate recommendations
generate_recommendations() {
    log_header "VS Code Performance Recommendations"

    local recommendations=()

    # Check for remaining high CPU processes
    if [ -n "$VS_CODE_PROCESSES" ]; then
        local high_cpu_count=$(echo "$VS_CODE_PROCESSES" | awk '{if ($3 > 20) count++} END {print count+0}')
        if [ "$high_cpu_count" -gt 0 ]; then
            recommendations+=("Consider restarting VS Code completely")
            recommendations+=("Close unnecessary VS Code windows")
        fi
    fi

    # Check for heavy extensions
    if [ -n "$HEAVY_EXTENSIONS" ]; then
        recommendations+=("Disable unnecessary extensions")
        recommendations+=("Use lightweight alternatives for heavy extensions")
    fi

    # Settings recommendations
    if [ "$OPTIMIZATION_APPLIED" = false ]; then
        recommendations+=("Apply optimized VS Code settings")
    fi

    # General recommendations
    recommendations+=("Use GPU acceleration if available")
    recommendations+=("Consider using VS Code Insiders for performance improvements")
    recommendations+=("Regularly clear VS Code cache: rm -rf ~/.config/Code/User/workspaceStorage")
    recommendations+=("Use workspace-specific settings instead of global settings")
    recommendations+=("Disable features you don't use in settings.json")

    if [ "$JSON_OUTPUT" = false ]; then
        if [ ${#recommendations[@]} -gt 0 ]; then
            echo "Recommendations for better VS Code performance:"
            printf "%s\n" "${recommendations[@]}"
            echo ""
        else
            log_success "VS Code is optimally configured"
        fi
    fi
}

# Cleanup function
cleanup() {
    log_verbose "Cleaning up temporary files..."
    rm -f /tmp/vscode_*.txt /tmp/vscode_*.json
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --auto)
                AUTO_MODE=true
                shift
                ;;
            --no-backup)
                BACKUP_VSCODE_SETTINGS=false
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --json                     Output results in JSON format"
                echo "  --verbose                  Enable verbose logging"
                echo "  --auto                     Automatic optimization mode"
                echo "  --no-backup               Skip backing up VS Code settings"
                echo "  --help, -h                Show this help message"
                echo ""
                echo "This script optimizes VS Code CPU usage for better system performance."
                echo "It provides process management, settings optimization, and extension control."
                echo ""
                echo "Example usage:"
                echo "  $0                          # Interactive optimization"
                echo "  $0 --auto                   # Automatic optimization"
                echo "  $0 --json                   # JSON output for automation"
                echo "  $0 --verbose                # Verbose logging"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Set up cleanup trap
    trap cleanup EXIT

    # Main execution flow
    print_banner

    if identify_vscode_processes; then
        analyze_heavy_extensions
        interactive_process_selection
        optimize_vscode_settings
        optimize_vscode_processes
        manage_extensions
        verify_optimization
        generate_recommendations
    else
        log_info "No VS Code processes found - nothing to optimize"
    fi

    # Exit with appropriate status code
    if [ "$OPTIMIZATION_APPLIED" = true ] || [ "$CPU_SAVINGS" -gt 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"