#!/bin/bash

# =============================================================================
# 🔧 Port 5432 Conflict Resolution Tool for MojoRust Trading Bot
# =============================================================================
# This script provides interactive options to resolve port 5432 conflicts

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
CONFLICT_PORT=5432
ALTERNATIVE_PORT=5433
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
ENV_FILE="$PROJECT_ROOT/.env"
BACKUP_DIR="$PROJECT_ROOT/backups/port-conflict-$(date +%Y%m%d-%H%M%S)"
DIAGNOSTIC_SCRIPT="$PROJECT_ROOT/scripts/diagnose_port_conflict.sh"

# Global variables from diagnostic
PORT_IN_USE=false
PROCESS_PID=""
PROCESS_NAME=""
PROCESS_USER=""
POSTGRES_SERVICE_STATUS=""
DOCKER_CONTAINERS_ON_5432=()

# Options
VERBOSE=false
FORCE=false

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_header() {
    echo -e "${PURPLE}$1${NC}"
}

log_step() {
    echo -e "${CYAN}▶ $1${NC}"
}

# Banner function
print_banner() {
    echo -e "${PURPLE}"
    echo "╔═════════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║    🔧 Port 5432 Conflict Resolution - MojoRust Trading Bot     ║"
    echo "║                                                               ║"
    echo "║    Project: $PROJECT_ROOT"
    echo "║    Backup Location: $BACKUP_DIR"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"

    # Verify project root and docker-compose.yml
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        log_error "docker-compose.yml not found at $DOCKER_COMPOSE_FILE"
        log_error "Please run this script from the project root directory"
        exit 1
    fi

    # Check user permissions
    if [ "$EUID" -ne 0 ]; then
        log_warning "This script may require sudo privileges for some operations"
        log_warning "You may be prompted for password during execution"
    fi

    # Verify diagnostic script exists
    if [ ! -f "$DIAGNOSTIC_SCRIPT" ]; then
        log_error "Diagnostic script not found: $DIAGNOSTIC_SCRIPT"
        exit 1
    fi

    # Make diagnostic script executable
    chmod +x "$DIAGNOSTIC_SCRIPT"

    log_success "Prerequisites check completed"
}

# Run diagnostic script
run_diagnostic() {
    log_header "Running Port Conflict Diagnosis"

    # Guard before executing
    if [ ! -f "$DIAGNOSTIC_SCRIPT" ] || [ ! -x "$DIAGNOSTIC_SCRIPT" ]; then
        log_error "Diagnostic script not found or not executable: $DIAGNOSTIC_SCRIPT"
        exit 1
    fi

    log_step "Running diagnostic script..."
    local diagnostic_output
    diagnostic_output=$("$DIAGNOSTIC_SCRIPT" --json 2>/dev/null)
    local diagnostic_exit_code=$?

    if [ $diagnostic_exit_code -eq 0 ]; then
        # Port is available
        PORT_IN_USE=false
        log_success "✅ Port $CONFLICT_PORT is available - no resolution needed"
        echo ""
        log_info "TimescaleDB can use port $CONFLICT_PORT safely"
        log_info "Proceeding with deployment preparation..."
        return 0
    else
        # Port conflict detected
        PORT_IN_USE=true

        # Parse JSON output
        if command -v jq >/dev/null 2>&1; then
            PROCESS_PID=$(echo "$diagnostic_output" | jq -r '.process.pid // ""')
            PROCESS_NAME=$(echo "$diagnostic_output" | jq -r '.process.name // ""')
            PROCESS_USER=$(echo "$diagnostic_output" | jq -r '.process.user // ""')
            POSTGRES_SERVICE_STATUS=$(echo "$diagnostic_output" | jq -r '.postgres_service.status // ""')

            # Parse Docker containers
            local containers_json
            containers_json=$(echo "$diagnostic_output" | jq -r '.docker_containers[]' 2>/dev/null || echo "")
            while IFS= read -r container; do
                if [ -n "$container" ]; then
                    DOCKER_CONTAINERS_ON_5432+=("$container")
                fi
            done <<< "$containers_json"
        else
            log_warning "jq not available, falling back to plain diagnostic output"
            "$DIAGNOSTIC_SCRIPT"
        fi

        log_error "🔴 Port $CONFLICT_PORT CONFLICT DETECTED"
        if [ -n "$PROCESS_NAME" ]; then
            log_error "Process: $PROCESS_NAME (PID: $PROCESS_PID, User: $PROCESS_USER)"
        fi
        if [ -n "$POSTGRES_SERVICE_STATUS" ] && [ "$POSTGRES_SERVICE_STATUS" = "active" ]; then
            log_error "PostgreSQL Service: $POSTGRES_SERVICE_STATUS"
        fi
        if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
            log_error "Docker Containers: ${DOCKER_CONTAINERS_ON_5432[*]}"
        fi

        return 1
    fi
}

# Backup configurations
backup_configurations() {
    log_header "Creating Configuration Backups"

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Backup docker-compose.yml
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        cp "$DOCKER_COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml.backup"
        log_success "Backed up docker-compose.yml"
    fi

    # Backup .env file if it exists
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$BACKUP_DIR/.env.backup"
        log_success "Backed up .env file"
    fi

    # Create actions log
    {
        echo "Port Conflict Resolution Log - $(date)"
        echo "========================================"
        echo "Project Root: $PROJECT_ROOT"
        echo "Backup Directory: $BACKUP_DIR"
        echo "Port in Use: $PORT_IN_USE"
        echo "Process PID: $PROCESS_PID"
        echo "Process Name: $PROCESS_NAME"
        echo "PostgreSQL Service: $POSTGRES_SERVICE_STATUS"
    } > "$BACKUP_DIR/actions.log"

    log_success "Backup completed - files saved to $BACKUP_DIR"
}

# Show resolution menu
show_resolution_menu() {
    log_header "Resolution Options"

    echo ""
    echo "Choose a resolution option:"
    echo ""

    local option=1

    if [ "$POSTGRES_SERVICE_STATUS" = "active" ]; then
        echo "  $option) Stop and disable system PostgreSQL service"
        option=$((option + 1))
    fi

    if [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
        echo "  $option) Stop conflicting Docker container(s)"
        option=$((option + 1))
    fi

    if [ -n "$PROCESS_PID" ]; then
        echo "  $option) Kill conflicting process by PID ($PROCESS_PID)"
        option=$((option + 1))
    fi

    echo "  $option) Reconfigure TimescaleDB to use alternative port ($ALTERNATIVE_PORT)"
    option=$((option + 1))

    echo "  $option) Show detailed diagnostic report"
    option=$((option + 1))

    echo "  $option) Exit without changes"
    echo ""

    while true; do
        read -p "Enter your choice (1-$option): " choice
        if [[ "$choice" =~ ^[1-9][0-9]*$ ]] && [ "$choice" -le "$option" ]; then
            break
        else
            echo "Invalid choice. Please enter a number between 1 and $option."
        fi
    done

    echo ""
    log_step "You selected option $choice"

    case $choice in
        1)
            if [ "$POSTGRES_SERVICE_STATUS" = "active" ]; then
                stop_postgres_service
            elif [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
                stop_docker_container
            elif [ -n "$PROCESS_PID" ]; then
                kill_conflicting_process
            else
                reconfigure_timescaledb_port
            fi
            ;;
        2)
            if [ "$POSTGRES_SERVICE_STATUS" = "active" ] && [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ]; then
                stop_docker_container
            elif [ "$POSTGRES_SERVICE_STATUS" = "active" ] && [ -n "$PROCESS_PID" ]; then
                kill_conflicting_process
            elif [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ] && [ -n "$PROCESS_PID" ]; then
                kill_conflicting_process
            else
                reconfigure_timescaledb_port
            fi
            ;;
        3)
            if [ "$POSTGRES_SERVICE_STATUS" = "active" ] && [ ${#DOCKER_CONTAINERS_ON_5432[@]} -gt 0 ] && [ -n "$PROCESS_PID" ]; then
                kill_conflicting_process
            else
                reconfigure_timescaledb_port
            fi
            ;;
        4)
            reconfigure_timescaledb_port
            ;;
        5)
            show_diagnostic_report
            show_resolution_menu
            return
            ;;
        6)
            log_info "Exiting without making changes"
            exit 0
            ;;
    esac
}

# Stop PostgreSQL service
stop_postgres_service() {
    log_header "Stopping PostgreSQL Service"

    echo ""
    log_warning "This will stop the system PostgreSQL service."
    echo "PostgreSQL service: $POSTGRES_SERVICE_STATUS"
    echo ""

    if [ "$FORCE" = false ]; then
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 1
        fi
    fi

    log_step "Stopping PostgreSQL service..."
    if sudo systemctl stop postgresql 2>/dev/null; then
        log_success "PostgreSQL service stopped"
        echo "sudo systemctl stop postgresql" >> "$BACKUP_DIR/actions.log"
    else
        # Try alternative service names
        local stopped=false
        for service in postgresql@14-main postgresql@13-main postgresql@12-main postgresql@15-main; do
            if sudo systemctl stop "$service" 2>/dev/null; then
                log_success "PostgreSQL service stopped: $service"
                echo "sudo systemctl stop $service" >> "$BACKUP_DIR/actions.log"
                stopped=true
                break
            fi
        done

        if [ "$stopped" = false ]; then
            log_error "Failed to stop PostgreSQL service"
            return 1
        fi
    fi

    log_step "Disabling PostgreSQL service from auto-start..."
    if sudo systemctl disable postgresql 2>/dev/null; then
        log_success "PostgreSQL service disabled from auto-start"
        echo "sudo systemctl disable postgresql" >> "$BACKUP_DIR/actions.log"
    fi

    # Verify service is stopped
    log_step "Verifying PostgreSQL service status..."
    local service_status
    service_status=$(systemctl is-active postgresql 2>/dev/null || echo "unknown")

    if [ "$service_status" = "inactive" ]; then
        log_success "✅ PostgreSQL service is stopped"
    else
        log_warning "PostgreSQL service status: $service_status"
    fi

    # Check if port is now available
    log_step "Checking port availability..."
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :$CONFLICT_PORT >/dev/null 2>&1; then
            log_error "Port $CONFLICT_PORT is still in use"
            return 1
        else
            log_success "✅ Port $CONFLICT_PORT is now available"
        fi
    fi

    return 0
}

# Stop Docker container
stop_docker_container() {
    log_header "Stopping Docker Container(s)"

    echo ""
    echo "Docker containers using port $CONFLICT_PORT:"
    for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
        echo "  - $container"
    done
    echo ""

    if [ "$FORCE" = false ]; then
        read -p "Stop these containers? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 1
        fi
    fi

    for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
        log_step "Stopping container: $container"
        if docker stop "$container" 2>/dev/null; then
            log_success "Container stopped: $container"
            echo "docker stop $container" >> "$BACKUP_DIR/actions.log"
        else
            log_error "Failed to stop container: $container"
        fi
    done

    # Ask if user wants to remove containers
    echo ""
    if [ "$FORCE" = false ]; then
        read -p "Remove the stopped containers? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for container in "${DOCKER_CONTAINERS_ON_5432[@]}"; do
                log_step "Removing container: $container"
                if docker rm "$container" 2>/dev/null; then
                    log_success "Container removed: $container"
                    echo "docker rm $container" >> "$BACKUP_DIR/actions.log"
                else
                    log_error "Failed to remove container: $container"
                fi
            done
        fi
    fi

    # Check if port is now available
    log_step "Checking port availability..."
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :$CONFLICT_PORT >/dev/null 2>&1; then
            log_error "Port $CONFLICT_PORT is still in use"
            return 1
        else
            log_success "✅ Port $CONFLICT_PORT is now available"
        fi
    fi

    return 0
}

# Kill conflicting process
kill_conflicting_process() {
    log_header "Killing Conflicting Process"

    echo ""
    echo "Process Details:"
    echo "  PID: $PROCESS_PID"
    echo "  Name: $PROCESS_NAME"
    echo "  User: $PROCESS_USER"
    echo ""
    log_warning "⚠️  WARNING: This may cause data loss if the process is important!"
    echo ""

    if [ "$FORCE" = false ]; then
        read -p "Kill process $PROCESS_PID ($PROCESS_NAME)? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 1
        fi
    fi

    log_step "Attempting graceful termination..."
    if sudo kill -TERM "$PROCESS_PID" 2>/dev/null; then
        log_success "Sent TERM signal to process $PROCESS_PID"
        echo "sudo kill -TERM $PROCESS_PID" >> "$BACKUP_DIR/actions.log"

        # Wait for process to terminate
        log_step "Waiting for process to terminate..."
        sleep 5

        if kill -0 "$PROCESS_PID" 2>/dev/null; then
            log_warning "Process still running, attempting force kill..."
            if sudo kill -9 "$PROCESS_PID" 2>/dev/null; then
                log_success "Force killed process $PROCESS_PID"
                echo "sudo kill -9 $PROCESS_PID" >> "$BACKUP_DIR/actions.log"
            else
                log_error "Failed to kill process $PROCESS_PID"
                return 1
            fi
        else
            log_success "✅ Process terminated gracefully"
        fi
    else
        log_error "Failed to send TERM signal to process $PROCESS_PID"
        return 1
    fi

    # Check if port is now available
    log_step "Checking port availability..."
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :$CONFLICT_PORT >/dev/null 2>&1; then
            log_error "Port $CONFLICT_PORT is still in use"
            return 1
        else
            log_success "✅ Port $CONFLICT_PORT is now available"
        fi
    fi

    return 0
}

# Reconfigure TimescaleDB port
reconfigure_timescaledb_port() {
    log_header "Reconfiguring TimescaleDB to Port $ALTERNATIVE_PORT"

    echo ""
    log_info "This will reconfigure TimescaleDB to use port $ALTERNATIVE_PORT instead of $CONFLICT_PORT"
    log_info "This allows both services to coexist on the same server"
    echo ""

    if [ "$FORCE" = false ]; then
        read -p "Proceed with port reconfiguration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled"
            return 1
        fi
    fi

    log_step "Updating docker-compose.yml port mapping..."

    # Backup current docker-compose.yml
    cp "$DOCKER_COMPOSE_FILE" "$BACKUP_DIR/docker-compose.yml.before-reconfig"

    # Update port mapping using sed
    if sed -i.bak "s/$CONFLICT_PORT:$CONFLICT_PORT/$ALTERNATIVE_PORT:$CONFLICT_PORT/" "$DOCKER_COMPOSE_FILE"; then
        log_success "Updated docker-compose.yml port mapping"
        echo "sed -i.bak s/$CONFLICT_PORT:$CONFLICT_PORT/$ALTERNATIVE_PORT:$CONFLICT_PORT/ $DOCKER_COMPOSE_FILE" >> "$BACKUP_DIR/actions.log"
    else
        log_error "Failed to update docker-compose.yml"
        return 1
    fi

    log_step "Updating .env file..."

    # Create .env file if it doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        touch "$ENV_FILE"
        log_info "Created new .env file"
    fi

    # Backup current .env
    cp "$ENV_FILE" "$BACKUP_DIR/.env.before-reconfig"

    # Add/update TIMESCALEDB_PORT in .env
    if grep -q "^TIMESCALEDB_PORT=" "$ENV_FILE"; then
        # Update existing line
        sed -i "s/^TIMESCALEDB_PORT=.*/TIMESCALEDB_PORT=$ALTERNATIVE_PORT/" "$ENV_FILE"
        log_success "Updated TIMESCALEDB_PORT in .env file"
    else
        # Add new line
        echo "TIMESCALEDB_PORT=$ALTERNATIVE_PORT" >> "$ENV_FILE"
        log_success "Added TIMESCALEDB_PORT to .env file"
    fi

    echo "TIMESCALEDB_PORT=$ALTERNATIVE_PORT" >> "$BACKUP_DIR/actions.log"

    # Show changes made
    echo ""
    log_info "Changes made:"
    echo "  docker-compose.yml: Port mapping changed from $CONFLICT_PORT:$CONFLICT_PORT to $ALTERNATIVE_PORT:$CONFLICT_PORT"
    echo "  .env: Added/updated TIMESCALEDB_PORT=$ALTERNATIVE_PORT"
    echo ""

    if [ "$FORCE" = false ]; then
        read -p "Review changes above. Confirm and apply? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rolling back changes..."

            # Restore docker-compose.yml
            cp "$BACKUP_DIR/docker-compose.yml.before-reconfig" "$DOCKER_COMPOSE_FILE"

            # Restore .env
            if [ -f "$BACKUP_DIR/.env.before-reconfig" ]; then
                cp "$BACKUP_DIR/.env.before-reconfig" "$ENV_FILE"
            fi

            log_success "Changes rolled back"
            return 1
        fi
    fi

    log_success "✅ Port reconfiguration completed"
    log_info "TimescaleDB will now use port $ALTERNATIVE_PORT"
    return 0
}

# Show diagnostic report
show_diagnostic_report() {
    log_header "Detailed Diagnostic Report"

    echo ""
    "$PROJECT_ROOT/scripts/diagnose_port_conflict.sh" --verbose
}

# Verify resolution
verify_resolution() {
    log_header "Verifying Resolution"

    log_step "Running post-resolution verification..."

    # Run diagnostic script again
    if "$DIAGNOSTIC_SCRIPT" --json >/dev/null 2>&1; then
        log_success "✅ Port $CONFLICT_PORT is now available"

        if [ "$ALTERNATIVE_PORT" != "$CONFLICT_PORT" ]; then
            log_step "Verifying alternative port $ALTERNATIVE_PORT..."
            if command -v lsof >/dev/null 2>&1; then
                if ! lsof -i :$ALTERNATIVE_PORT >/dev/null 2>&1; then
                    log_success "✅ Alternative port $ALTERNATIVE_PORT is also available"
                else
                    log_warning "⚠️  Alternative port $ALTERNATIVE_PORT is in use"
                fi
            fi
        fi

        # Validate Docker Compose configuration
        log_step "Validating Docker Compose configuration..."
        if cd "$PROJECT_ROOT" && docker-compose config >/dev/null 2>&1; then
            log_success "✅ Docker Compose configuration is valid"
        else
            log_error "❌ Docker Compose configuration has errors"
            return 1
        fi

        return 0
    else
        log_error "❌ Port $CONFLICT_PORT is still in use"
        return 1
    fi
}

# Rollback changes
rollback_changes() {
    log_header "Rolling Back Changes"

    if [ -d "$BACKUP_DIR" ]; then
        log_step "Restoring docker-compose.yml..."
        if [ -f "$BACKUP_DIR/docker-compose.yml.backup" ]; then
            cp "$BACKUP_DIR/docker-compose.yml.backup" "$DOCKER_COMPOSE_FILE"
            log_success "Restored docker-compose.yml"
        fi

        log_step "Restoring .env file..."
        if [ -f "$BACKUP_DIR/.env.backup" ]; then
            cp "$BACKUP_DIR/.env.backup" "$ENV_FILE"
            log_success "Restored .env file"
        fi

        log_step "Restarting PostgreSQL service if it was stopped..."
        # Check if PostgreSQL was stopped by looking at actions log
        if grep -q "systemctl stop postgresql" "$BACKUP_DIR/actions.log" 2>/dev/null; then
            if sudo systemctl start postgresql 2>/dev/null; then
                log_success "Restarted PostgreSQL service"
                sudo systemctl enable postgresql 2>/dev/null || true
            else
                log_warning "Failed to restart PostgreSQL service"
            fi
        fi

        log_success "Rollback completed"
    else
        log_warning "No backup directory found for rollback"
    fi
}

# Error handling trap
trap 'echo ""; log_error "Script interrupted. Rolling back changes..."; rollback_changes; exit 1' INT TERM

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --force|-f)
                FORCE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --verbose, -v          Show detailed output"
                echo "  --force, -f            Skip confirmation prompts"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "This script provides interactive options to resolve port 5432 conflicts"
                echo "for TimescaleDB deployment in the MojoRust Trading Bot."
                echo ""
                echo "Common scenarios:"
                echo "  - System PostgreSQL service is using port 5432"
                echo "  - Docker container is using port 5432"
                echo "  - Unknown process is using port 5432"
                echo "  - Reconfigure TimescaleDB to use alternative port 5433"
                echo ""
                echo "This script automatically creates backups before making any changes."
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

    # Run main workflow
    print_banner
    check_prerequisites
    backup_configurations

    # Run diagnostic
    if run_diagnostic; then
        # Port is available, prepare for deployment
        log_header "Deployment Preparation Complete"
        log_success "✅ Port $CONFLICT_PORT is available for TimescaleDB"
        echo ""
        log_info "Next steps:"
        echo "1. Run: cd $PROJECT_ROOT"
        echo "2. Deploy: docker-compose up -d"
        echo "3. Verify: docker-compose ps"
        exit 0
    fi

    # Port conflict detected, show resolution menu
    show_resolution_menu

    # Verify resolution was successful
    if verify_resolution; then
        log_header "Resolution Successful"
        log_success "✅ Port conflict resolved successfully"
        echo ""
        log_info "Backup files are located at: $BACKUP_DIR"
        log_info "Actions log: $BACKUP_DIR/actions.log"
        echo ""
        log_info "Next steps:"
        echo "1. Run: cd $PROJECT_ROOT"
        echo "2. Deploy: docker-compose up -d"
        echo "3. Verify: docker-compose ps"
        echo "4. Check services: docker-compose logs -f"

        if [ "$ALTERNATIVE_PORT" != "$CONFLICT_PORT" ]; then
            echo ""
            log_info "Note: TimescaleDB is now configured to use port $ALTERNATIVE_PORT"
            echo "External connections should use: localhost:$ALTERNATIVE_PORT"
        fi
    else
        log_error "Resolution failed or incomplete"
        echo ""
        log_info "Troubleshooting:"
        echo "1. Check the actions log: $BACKUP_DIR/actions.log"
        echo "2. Run diagnostic script again: $PROJECT_ROOT/scripts/diagnose_port_conflict.sh"
        echo "3. Consider manual intervention or alternative port configuration"
        exit 1
    fi
}

# Run main function
main "$@"