#!/bin/bash

# =============================================================================
# MojoRust Trading Bot - Build and Deploy Script
# =============================================================================
# This script orchestrates the complete build and deployment process,
# including Mojo binary, Rust modules, Docker image, and deployment verification.

set -euo pipefail

# =============================================================================
# Colors for output
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# =============================================================================
# Configuration Variables
# =============================================================================
BUILD_TARGET="release"  # Can be "debug" or "release"
SKIP_TESTS=false
SKIP_DOCKER_BUILD=false
SKIP_DEPLOY=false
SKIP_VERIFICATION=false
CLEAN_BUILD=false
VERBOSE=false
ENVIRONMENT="production"
DEPLOY_TIMEOUT=300
DOCKER_REGISTRY=""
DOCKER_TAG="latest"
SKIP_HEALTH_CHECK=false

# =============================================================================
# Functions
# =============================================================================

print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║    🚀 MOJORUST BUILD & DEPLOY SCRIPT 🚀                   ║"
    echo "║                                                              ║"
    echo "║    Complete build and deployment automation                ║"
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

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

show_help() {
    cat << EOF
MojoRust Trading Bot - Build and Deploy Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --debug                Build in debug mode (default: release)
    --verbose              Enable verbose output
    --skip-tests            Skip running tests
    --skip-docker-build     Skip Docker image build
    --skip-deploy           Skip deployment
    --skip-verification     Skip post-deployment verification
    --clean                Clean all artifacts before building
    --environment <env>     Set deployment environment (default: production)
    --registry <registry>    Docker registry for image push
    --tag <tag>            Docker image tag (default: latest)
    --skip-health-check     Skip health check during verification
    --help                 Show this help message

EXAMPLES:
    $0                      # Full build and deploy in release mode
    $0 --debug             # Debug build and deploy
    $0 --skip-tests --skip-docker-build  # Build only, no tests or Docker
    $0 --clean             # Clean and rebuild everything
    $0 --environment staging --tag v1.2.3  # Deploy to staging with custom tag

WORKFLOW:
    1. Prerequisites check
    2. Clean artifacts (if requested)
    3. Build Rust modules
    4. Build Mojo binary
    5. Run tests (if not skipped)
    6. Build Docker image
    7. Deploy services
    8. Verify deployment
    9. Show access information

REQUIREMENTS:
    - Rust 1.70+ installed
    - Mojo 24.4+ installed
    - Docker and Docker Compose
    - Sufficient disk space
    - Proper configuration files

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --debug)
                BUILD_TARGET="debug"
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --skip-docker-build)
                SKIP_DOCKER_BUILD=true
                shift
                ;;
            --skip-deploy)
                SKIP_DEPLOY=true
                shift
                ;;
            --skip-verification)
                SKIP_VERIFICATION=true
                shift
                ;;
            --skip-health-check)
                SKIP_HEALTH_CHECK=true
                shift
                ;;
            --clean)
                CLEAN_BUILD=true
                shift
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --registry)
                DOCKER_REGISTRY="$2"
                shift 2
                ;;
            --tag)
                DOCKER_TAG="$2"
                shift 2
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

    # Validate environment
    case "$ENVIRONMENT" in
        development|staging|production)
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Must be development, staging, or production"
            exit 1
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."

    # Check for required tools
    local required_tools=("rustc" "cargo" "mojo" "docker" "docker-compose")
    local missing_tools=()

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    # Check Docker Compose file
    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "docker-compose.yml not found in current directory"
        exit 1
    fi

    # Check environment file
    local env_file=".env"
    if [[ "$ENVIRONMENT" != "production" ]]; then
        env_file=".env.$ENVIRONMENT"
        if [[ ! -f "$env_file" ]]; then
            env_file=".env"
        fi
    fi

    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        exit 1
    fi

    # Check source directories
    if [[ ! -d "src" ]]; then
        log_error "Source directory 'src' not found"
        exit 1
    fi

    if [[ ! -d "rust-modules" ]]; then
        log_error "Rust modules directory not found"
        exit 1
    fi

    # Check available disk space
    local available_space
    available_space=$(df . | awk 'NR==2{print $4}')
    local required_space=5242880  # 5GB in KB

    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 5GB, Available: $((available_space/1024/1024))GB"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Clean all build artifacts
clean_all() {
    if [[ "$CLEAN_BUILD" == true ]]; then
        log_step "Cleaning all build artifacts..."

        # Clean Mojo artifacts
        if [[ -d ".mojo_cache" ]]; then
            rm -rf .mojo_cache
            log_success "Removed .mojo_cache"
        fi

        if [[ -d "target" ]]; then
            rm -rf target
            log_success "Removed target directory"
        fi

        # Clean Rust artifacts
        if [[ -d "rust-modules/target" ]]; then
            rm -rf rust-modules/target
            log_success "Removed rust-modules/target directory"
        fi

        # Clean Docker artifacts
        if command -v docker &> /dev/null; then
            docker system prune -f > /dev/null 2>&1 || true
            log_success "Cleaned Docker system cache"
        fi

        # Clean temp files
        find . -name "*.tmp" -delete 2>/dev/null || true
        find . -name "*.log" -delete 2>/dev/null || true

        log_success "All build artifacts cleaned"
    fi
}

# Build Rust modules
build_rust_modules() {
    log_step "Building Rust modules..."

    local rust_script="scripts/build_rust_modules.sh"
    local rust_args=()

    if [[ "$BUILD_TARGET" == "debug" ]]; then
        rust_args+=("--debug")
    fi

    if [[ "$VERBOSE" == true ]]; then
        rust_args+=("--verbose")
    fi

    if [[ "$SKIP_TESTS" == true ]]; then
        rust_args+=("--skip-tests")
    fi

    if [[ "$CLEAN_BUILD" == true ]]; then
        rust_args+=("--clean")
    fi

    if [[ ! -f "$rust_script" ]]; then
        log_error "Rust build script not found: $rust_script"
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log_info "Running: $rust_script ${rust_args[*]}"
    fi

    if ! "$rust_script" "${rust_args[@]}"; then
        log_error "Rust modules build failed"
        exit 1
    fi

    log_success "Rust modules built successfully"
}

# Build Mojo binary
build_mojo_binary() {
    log_step "Building Mojo binary..."

    local mojo_script="scripts/build_mojo_binary.sh"
    local mojo_args=()

    if [[ "$BUILD_TARGET" == "debug" ]]; then
        mojo_args+=("--debug")
    fi

    if [[ "$VERBOSE" == true ]]; then
        mojo_args+=("--verbose")
    fi

    if [[ "$SKIP_TESTS" == true ]]; then
        mojo_args+=("--skip-tests")
    fi

    if [[ "$CLEAN_BUILD" == true ]]; then
        mojo_args+=("--clean")
    fi

    if [[ ! -f "$mojo_script" ]]; then
        log_error "Mojo build script not found: $mojo_script"
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log_info "Running: $mojo_script ${mojo_args[*]}"
    fi

    if ! "$mojo_script" "${mojo_args[@]}"; then
        log_error "Mojo binary build failed"
        exit 1
    fi

    log_success "Mojo binary built successfully"
}

# Build Docker image
build_docker_image() {
    if [[ "$SKIP_DOCKER_BUILD" == true ]]; then
        log_warning "Skipping Docker image build"
        return 0
    fi

    log_step "Building Docker image..."

    # Set build arguments
    local build_args=""
    if [[ "$BUILD_TARGET" == "debug" ]]; then
        build_args="--build-arg BUILD_TARGET=debug"
    else
        build_args="--build-arg BUILD_TARGET=release"
    fi

    # Set image name
    local image_name="mojorust/trading-bot"
    if [[ -n "$DOCKER_REGISTRY" ]]; then
        image_name="$DOCKER_REGISTRY/$image_name"
    fi
    image_name="$image_name:$DOCKER_TAG"

    # Build command
    local build_cmd="docker build $build_args -t $image_name ."

    if [[ "$VERBOSE" == true ]]; then
        log_info "Running: $build_cmd"
        eval "$build_cmd"
    else
        eval "$build_cmd" > /dev/null 2>&1
    fi

    # Check if build was successful
    if ! docker image inspect "$image_name" &> /dev/null; then
        log_error "Docker image build failed"
        exit 1
    fi

    log_success "Docker image built successfully: $image_name"

    # Push to registry if specified
    if [[ -n "$DOCKER_REGISTRY" ]]; then
        log_info "Pushing image to registry..."
        if docker push "$image_name"; then
            log_success "Image pushed successfully to registry"
        else
            log_error "Failed to push image to registry"
            exit 1
        fi
    fi
}

# Deploy services
deploy_services() {
    if [[ "$SKIP_DEPLOY" == true ]]; then
        log_warning "Skipping deployment"
        return 0
    fi

    log_step "Deploying services..."

    # Set environment file
    local env_file_arg=""
    if [[ "$ENVIRONMENT" != "production" && -f ".env.$ENVIRONMENT" ]]; then
        env_file_arg="--env-file .env.$ENVIRONMENT"
    fi

    # Deploy command
    local deploy_cmd="docker-compose up -d $env_file_arg"

    if [[ "$VERBOSE" == true ]]; then
        log_info "Running: $deploy_cmd"
    fi

    if ! eval "$deploy_cmd"; then
        log_error "Deployment failed"
        exit 1
    fi

    log_success "Services deployed successfully"
}

# Verify deployment
verify_deployment() {
    if [[ "$SKIP_VERIFICATION" == true ]]; then
        log_warning "Skipping deployment verification"
        return 0
    fi

    log_step "Verifying deployment..."

    # Wait for services to start
    log_info "Waiting for services to start..."
    sleep 30

    # Check service status
    log_info "Checking service status..."
    local service_status
    service_status=$(docker-compose ps --format "table {{.Name}}\t{{.Status}}" | grep -E "(Up|healthy)")

    if [[ -z "$service_status" ]]; then
        log_error "No services appear to be running"
        docker-compose ps
        exit 1
    fi

    echo "$service_status"

    # Count healthy services
    local healthy_services
    healthy_services=$(echo "$service_status" | grep -c "Up\|healthy" || echo "0")

    if [[ $healthy_services -lt 3 ]]; then
        log_warning "Only $healthy_services service(s) appear to be healthy"
    fi

    # Health checks
    if [[ "$SKIP_HEALTH_CHECK" == false ]]; then
        log_info "Performing comprehensive health checks..."

        # Check trading bot health with retry logic
        local max_attempts=5
        local attempt=1
        while [[ $attempt -le $max_attempts ]]; do
            if bot_health=$(curl -s http://localhost:8082/health 2>/dev/null); then
                log_success "Trading bot health check passed (attempt $attempt)"
                break
            else
                log_warning "Trading bot health check failed (attempt $attempt/$max_attempts)"
                if [[ $attempt -lt $max_attempts ]]; then
                    sleep 10
                    ((attempt++))
                else
                    log_error "Trading bot health check failed after $max_attempts attempts"
                    docker-compose logs trading-bot --tail=20
                fi
            fi
        done

        # Check API endpoints
        log_info "Checking API endpoints..."
        if curl -s http://localhost:8082/api/status &> /dev/null; then
            log_success "Trading bot API status endpoint responding"
        else
            log_warning "Trading bot API status endpoint not responding"
        fi

        # Check metrics endpoint
        if curl -s http://localhost:8082/metrics &> /dev/null; then
            log_success "Trading bot metrics endpoint responding"
        else
            log_warning "Trading bot metrics endpoint not responding"
        fi

        # Check database connections
        log_info "Checking database connectivity..."
        if docker-compose exec -T timescaledb pg_isready -U ${TIMESCALEDB_USER:-trading_user} -d ${TIMESCALEDB_DBNAME:-trading_db} &> /dev/null; then
            log_success "TimescaleDB connection successful"
        else
            log_warning "TimescaleDB connection failed"
        fi

        # Check DragonflyDB/Redis connection
        if docker-compose exec -T trading-bot python -c "
import redis
import os
try:
    r = redis.from_url(os.environ.get('REDIS_URL', 'redis://localhost:6379'))
    r.ping()
    print('Redis connection successful')
except Exception as e:
    print(f'Redis connection failed: {e}')
    exit(1)
" &> /dev/null; then
            log_success "DragonflyDB/Redis connection successful"
        else
            log_warning "DragonflyDB/Redis connection failed"
        fi

        # Check monitoring services
        if curl -s http://localhost:9090/-/healthy &> /dev/null; then
            log_success "Prometheus health check passed"
            # Check Prometheus targets
            if curl -s http://localhost:9090/api/v1/targets | grep -q "up"; then
                log_success "Prometheus targets are being scraped"
            else
                log_warning "Prometheus targets may not be configured properly"
            fi
        else
            log_warning "Prometheus health check failed"
        fi

        if curl -s http://localhost:3001/api/health &> /dev/null; then
            log_success "Grafana health check passed"
        else
            log_warning "Grafana health check failed"
        fi

        # Verify data pipeline if Rust consumer is enabled
        if [[ "${ENABLE_RUST_CONSUMER:-true}" == "true" ]]; then
            if curl -s http://localhost:9191/health &> /dev/null; then
                log_success "Rust data consumer health check passed"
            else
                log_warning "Rust data consumer health check failed"
            fi
        fi
    fi

    # Final verification checklist
    log_info "Running final verification checklist..."
    local verification_passed=true

    # Check if critical services are running
    if ! docker-compose ps trading-bot | grep -q "Up"; then
        log_error "Trading bot service is not running"
        verification_passed=false
    fi

    if ! docker-compose ps timescaledb | grep -q "Up"; then
        log_error "TimescaleDB service is not running"
        verification_passed=false
    fi

    # Check if configuration files are properly loaded
    if docker-compose exec -T trading-bot python -c "
import os
required_vars = ['HELIUS_API_KEY', 'QUICKNODE_RPC_URL', 'WALLET_ADDRESS']
missing = [var for var in required_vars if not os.environ.get(var)]
if missing:
    print(f'Missing environment variables: {missing}')
    exit(1)
else:
    print('All required environment variables are set')
" &> /dev/null; then
        log_success "Environment configuration verified"
    else
        log_error "Environment configuration incomplete"
        verification_passed=false
    fi

    if [[ "$verification_passed" == true ]]; then
        log_success "✅ All critical verifications passed"
    else
        log_error "❌ Some verifications failed - check logs above"
        exit 1
    fi

    log_success "Deployment verification completed"
}

# Show access information
show_access_info() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    DEPLOYMENT SUMMARY                   ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "🚀 Deployment Configuration:"
    echo "   Environment: $ENVIRONMENT"
    echo "   Build Target: $BUILD_TARGET"
    echo "   Docker Image: ${DOCKER_REGISTRY:-mojorust}/trading-bot:$DOCKER_TAG"
    echo ""
    echo "🔗 Service Access:"
    echo "   Trading Bot:    http://localhost:8082"
    echo "   Health Check:   http://localhost:8082/health"
    echo "   Metrics:        http://localhost:8082/metrics"
    echo ""
    if [[ -f "docker-compose.yml" ]] && grep -q "prometheus:" docker-compose.yml; then
        echo "📊 Monitoring Stack:"
        echo "   Grafana:        http://localhost:3001 (admin/trading_admin)"
        echo "   Prometheus:     http://localhost:9090"
        echo "   AlertManager:  http://localhost:9093"
        echo ""
    fi
    echo "🛠️ Management Commands:"
    echo "   View logs:       docker-compose logs -f"
    echo "   Check status:    docker-compose ps"
    echo "   Stop services:   docker-compose down"
    echo "   Restart:         docker-compose restart"
    echo ""
    echo "📚 Documentation:"
    echo "   Deployment Guide: docs/BUILD_AND_DEPLOYMENT_GUIDE.md"
    echo "   Operations:      OPERATIONS_RUNBOOK.md"
    echo "   Troubleshooting: docs/monitoring_troubleshooting_guide.md"
    echo ""
    echo "📊 Deployment completed at: $(date)"
    echo ""
}

# Show next steps
show_next_steps() {
    echo "🎯 Recommended Next Steps:"
    echo ""
    echo "1. Verify the deployment:"
    echo "   curl http://localhost:8082/health"
    echo "   docker-compose ps"
    echo ""
    echo "2. Check application logs:"
    echo "   docker-compose logs -f trading-bot"
    echo ""
    echo "3. Access the dashboard:"
    if [[ -f "docker-compose.yml" ]] && grep -q "grafana:" docker-compose.yml; then
        echo "   http://localhost:3001 (admin/trading_admin)"
    fi
    echo "   http://localhost:8082"
    echo ""
    echo "4. Run health verification:"
    echo "   ./scripts/verify_monitoring_stack.sh"
    echo ""
    if [[ "$ENVIRONMENT" == "production" ]]; then
        echo "5. Configure alerts and monitoring:"
        echo "   - Set up notification channels"
        echo "   - Review alert thresholds"
        echo "   - Test alert delivery"
        echo ""
    fi
}

# =============================================================================
# Main execution
# =============================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Print banner
    print_banner

    # Set error handling
    set -e

    # Execute workflow
    check_prerequisites
    clean_all
    build_rust_modules
    build_mojo_binary
    build_docker_image
    deploy_services
    verify_deployment

    # Show results
    show_access_info
    show_next_steps

    log_success "Build and deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"