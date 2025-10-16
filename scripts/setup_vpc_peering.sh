#!/bin/bash

# =============================================================================
# 🔗 VPC Peering Setup Script for DragonflyDB Cloud Integration
# =============================================================================
# This script automates VPC peering setup between your AWS VPC and DragonflyDB Cloud

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
VPC_ID="${VPC_ID:-vpc-00e79f7555aa68c0e}"
VPC_CIDR="${VPC_CIDR:-192.168.0.0/16}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-962364259018}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# DragonflyDB Cloud variables (placeholders - need to get from DragonflyDB)
DRAGONFLYDB_VPC_ID="${DRAGONFLYDB_VPC_ID:-}"
DRAGONFLYDB_VPC_CIDR="${DRAGONFLYDB_VPC_CIDR:-}"
DRAGONFLYDB_ACCOUNT_ID="${DRAGONFLYDB_ACCOUNT_ID:-}"
DRAGONFLYDB_REGION="${DRAGONFLYDB_REGION:-}"
DRAGONFLYDB_HOST="${DRAGONFLYDB_HOST:-612ehcb9i.dragonflydb.cloud}"
DRAGONFLYDB_PORT="${DRAGONFLYDB_PORT:-6385}"

# Script state variables
VPC_PEERING_ID=""
CREATED_SG_RULES=()
CREATED_ROUTE_TABLES=()
ROLLBACK_RESOURCES=()

# Options
INTERACTIVE=true
SKIP_PROMETHEUS_TEST=false

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

# Rollback function
rollback() {
    log_warning "Initiating rollback..."

    for resource in "${ROLLBACK_RESOURCES[@]}"; do
        resource_type=$(echo "$resource" | cut -d':' -f1)
        resource_id=$(echo "$resource" | cut -d':' -f2)

        case "$resource_type" in
            "sg_rule")
                log_info "Removing security group rule: $resource_id"
                aws ec2 revoke-security-group-egress --group-id "$(echo "$resource_id" | cut -d',' -f1)" --security-group-rule-ids "$(echo "$resource_id" | cut -d',' -f2)" 2>/dev/null || true
                ;;
            "route")
                log_info "Removing route: $resource_id"
                aws ec2 delete-route --route-table-id "$(echo "$resource_id" | cut -d',' -f1)" --destination-cidr-block "$(echo "$resource_id" | cut -d',' -f2)" 2>/dev/null || true
                ;;
            "peering")
                log_info "Deleting VPC peering connection: $resource_id"
                aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$resource_id" 2>/dev/null || true
                ;;
        esac
    done

    log_warning "Rollback completed"
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"

    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI not found. Install with: pip install awscli"
        exit 1
    fi

    # Check AWS credentials
    log_step "Verifying AWS credentials..."
    local aws_identity
    if ! aws_identity=$(aws sts get-caller-identity 2>/dev/null); then
        log_error "AWS credentials not configured or invalid"
        exit 1
    fi

    local account_id=$(echo "$aws_identity" | jq -r '.Account')
    if [ "$account_id" != "$AWS_ACCOUNT_ID" ]; then
        log_error "AWS Account ID mismatch. Expected: $AWS_ACCOUNT_ID, Got: $account_id"
        exit 1
    fi

    log_success "AWS credentials verified for account: $AWS_ACCOUNT_ID"

    # Check VPC exists
    log_step "Verifying VPC exists..."
    local vpc_info
    if ! vpc_info=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" 2>/dev/null); then
        log_error "VPC $VPC_ID not found in region $AWS_REGION"
        exit 1
    fi

    local vpc_cidr_check=$(echo "$vpc_info" | jq -r '.Vpcs[0].CidrBlock')
    if [ "$vpc_cidr_check" != "$VPC_CIDR" ]; then
        log_error "VPC CIDR mismatch. Expected: $VPC_CIDR, Got: $vpc_cidr_check"
        exit 1
    fi

    log_success "VPC $VPC_ID verified with CIDR: $VPC_CIDR"

    # Check DragonflyDB configuration
    if [ -z "$DRAGONFLYDB_VPC_ID" ] || [ -z "$DRAGONFLYDB_VPC_CIDR" ] || [ -z "$DRAGONFLYDB_ACCOUNT_ID" ] || [ -z "$DRAGONFLYDB_REGION" ]; then
        log_error "DragonflyDB configuration incomplete. Set the following environment variables:"
        log_error "  DRAGONFLYDB_VPC_ID (DragonflyDB VPC ID)"
        log_error "  DRAGONFLYDB_VPC_CIDR (DragonflyDB VPC CIDR block)"
        log_error "  DRAGONFLYDB_ACCOUNT_ID (DragonflyDB AWS Account ID)"
        log_error "  DRAGONFLYDB_REGION (DragonflyDB AWS Region)"
        exit 1
    fi

    log_success "DragonflyDB configuration verified"

    # Check for existing VPC peering
    log_step "Checking for existing VPC peering connections..."
    local existing_peering
    existing_peering=$(aws ec2 describe-vpc-peering-connections \
        --filters "Name=requester-vpc-info.vpc-id,Values=$VPC_ID" "Name=peer-vpc-info.vpc-id,Values=$DRAGONFLYDB_VPC_ID" \
        --region "$AWS_REGION" 2>/dev/null || echo "[]")

    local peering_count=$(echo "$existing_peering" | jq '.VpcPeeringConnections | length')
    if [ "$peering_count" -gt 0 ]; then
        local existing_status=$(echo "$existing_peering" | jq -r '.VpcPeeringConnections[0].Status.Code')
        local existing_id=$(echo "$existing_peering" | jq -r '.VpcPeeringConnections[0].VpcPeeringConnectionId')

        if [ "$existing_status" = "active" ]; then
            log_warning "VPC peering already exists and is active: $existing_id"
            VPC_PEERING_ID="$existing_id"
            if [ "$INTERACTIVE" = true ]; then
                read -p "Continue with existing peering? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    exit 0
                fi
            fi
        else
            log_warning "Found existing VPC peering with status: $existing_status"
            VPC_PEERING_ID="$existing_id"
        fi
    fi

    log_success "Prerequisites check completed"
}

# Create VPC peering connection
create_vpc_peering() {
    log_header "Creating VPC Peering Connection"

    if [ -n "$VPC_PEERING_ID" ]; then
        log_info "Using existing VPC peering: $VPC_PEERING_ID"
        return 0
    fi

    log_step "Creating VPC peering connection..."
    local peering_result
    if ! peering_result=$(aws ec2 create-vpc-peering-connection \
        --vpc-id "$VPC_ID" \
        --peer-vpc-id "$DRAGONFLYDB_VPC_ID" \
        --peer-owner-id "$DRAGONFLYDB_ACCOUNT_ID" \
        --peer-region "$DRAGONFLYDB_REGION" \
        --region "$AWS_REGION" 2>/dev/null); then
        log_error "Failed to create VPC peering connection"
        exit 1
    fi

    VPC_PEERING_ID=$(echo "$peering_result" | jq -r '.VpcPeeringConnection.VpcPeeringConnectionId')
    log_success "VPC peering connection created: $VPC_PEERING_ID"

    # Add to rollback resources
    ROLLBACK_RESOURCES+=("peering:$VPC_PEERING_ID")

    # Wait for acceptance or prompt user
    log_step "Waiting for VPC peering acceptance..."
    local max_wait=300  # 5 minutes
    local wait_interval=10
    local waited=0

    while [ $waited -lt $max_wait ]; do
        local status_result
        status_result=$(aws ec2 describe-vpc-peering-connections \
            --vpc-peering-connection-ids "$VPC_PEERING_ID" \
            --region "$AWS_REGION" 2>/dev/null)

        local status=$(echo "$status_result" | jq -r '.VpcPeeringConnections[0].Status.Code')

        if [ "$status" = "active" ]; then
            log_success "VPC peering connection is active!"
            return 0
        elif [ "$status" = "pending-acceptance" ]; then
            log_info "VPC peering pending acceptance... (${waited}s/${max_wait}s)"

            if [ "$INTERACTIVE" = true ]; then
                log_warning "Please contact DragonflyDB support to accept the VPC peering request:"
                log_warning "  Peering Connection ID: $VPC_PEERING_ID"
                log_warning "  Your VPC ID: $VPC_ID"
                log_warning "  Your Account ID: $AWS_ACCOUNT_ID"
                log_warning "  DragonflyDB VPC ID: $DRAGONFLYDB_VPC_ID"
                log_warning "  DragonflyDB Account ID: $DRAGONFLYDB_ACCOUNT_ID"

                read -p "Press Enter to continue waiting, or Ctrl+C to exit..."
            fi
        else
            log_error "VPC peering failed with status: $status"
            exit 1
        fi

        sleep $wait_interval
        waited=$((waited + wait_interval))
    done

    log_error "VPC peering acceptance timeout"
    exit 1
}

# Create security group egress rules
create_security_group_rules() {
    log_header "Configuring Security Group Rules"

    # Get default security group for the VPC
    local sg_id
    sg_id=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=default" \
        --region "$AWS_REGION" \
        --query "SecurityGroups[0].GroupId" \
        --output text 2>/dev/null)

    if [ "$sg_id" = "None" ] || [ -z "$sg_id" ]; then
        log_error "Default security group not found for VPC $VPC_ID"
        exit 1
    fi

    log_info "Using security group: $sg_id"

    # Remove existing egress rules to DragonflyDB CIDR if they exist
    log_step "Checking for existing egress rules..."
    local existing_rules
    existing_rules=$(aws ec2 describe-security-group-rules \
        --filters "Name=group-id,Values=$sg_id" "Name=is-egress,Values=true" "Name=cidr,Values=$DRAGONFLYDB_VPC_CIDR" \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[*].SecurityGroupRuleId" \
        --output text 2>/dev/null || echo "")

    if [ -n "$existing_rules" ] && [ "$existing_rules" != "None" ]; then
        log_warning "Found existing egress rules to DragonflyDB CIDR, removing them..."
        for rule_id in $existing_rules; do
            aws ec2 revoke-security-group-egress \
                --group-id "$sg_id" \
                --security-group-rule-ids "$rule_id" \
                --region "$AWS_REGION" 2>/dev/null || true
        done
    fi

    # Add egress rule for DragonflyDB Redis port (6385)
    log_step "Adding egress rule for port 6385..."
    local sg_rule_6385
    sg_rule_6385=$(aws ec2 authorize-security-group-egress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 6385 \
        --cidr "$DRAGONFLYDB_VPC_CIDR" \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[0].SecurityGroupRuleId" \
        --output text 2>/dev/null)

    if [ -n "$sg_rule_6385" ] && [ "$sg_rule_6385" != "None" ]; then
        log_success "Security group rule for port 6385 created: $sg_rule_6385"
        CREATED_SG_RULES+=("$sg_id,$sg_rule_6385")
        ROLLBACK_RESOURCES+=("sg_rule:$sg_id,$sg_rule_6385")
    else
        log_error "Failed to create security group rule for port 6385"
        exit 1
    fi

    # Add egress rule for HTTPS port (443)
    log_step "Adding egress rule for port 443..."
    local sg_rule_443
    sg_rule_443=$(aws ec2 authorize-security-group-egress \
        --group-id "$sg_id" \
        --protocol tcp \
        --port 443 \
        --cidr "$DRAGONFLYDB_VPC_CIDR" \
        --region "$AWS_REGION" \
        --query "SecurityGroupRules[0].SecurityGroupRuleId" \
        --output text 2>/dev/null)

    if [ -n "$sg_rule_443" ] && [ "$sg_rule_443" != "None" ]; then
        log_success "Security group rule for port 443 created: $sg_rule_443"
        CREATED_SG_RULES+=("$sg_id,$sg_rule_443")
        ROLLBACK_RESOURCES+=("sg_rule:$sg_id,$sg_rule_443")
    else
        log_error "Failed to create security group rule for port 443"
        exit 1
    fi

    log_success "Security group rules configured"
}

# Update route tables
update_route_tables() {
    log_header "Updating Route Tables"

    # Get all route tables for the VPC
    local route_tables
    route_tables=$(aws ec2 describe-route-tables \
        --filters "Name=vpc-id,Values=$VPC_ID" \
        --region "$AWS_REGION" \
        --query "RouteTables[*].RouteTableId" \
        --output text 2>/dev/null)

    if [ -z "$route_tables" ] || [ "$route_tables" = "None" ]; then
        log_error "No route tables found for VPC $VPC_ID"
        exit 1
    fi

    log_info "Found route tables: $route_tables"

    for rt_id in $route_tables; do
        log_step "Updating route table: $rt_id"

        # Check if route already exists
        local existing_route
        existing_route=$(aws ec2 describe-routes \
            --route-table-id "$rt_id" \
            --filters "Name=destination-cidr-block,Values=$DRAGONFLYDB_VPC_CIDR" \
            --region "$AWS_REGION" \
            --query "Routes[0]" \
            --output json 2>/dev/null || echo "{}")

        local has_route=$(echo "$existing_route" | jq -r '.DestinationCidrBlock // empty')
        if [ "$has_route" = "$DRAGONFLYDB_VPC_CIDR" ]; then
            local existing_gateway=$(echo "$existing_route" | jq -r '.GatewayId // .NatGatewayId // .VpcPeeringConnectionId // empty')
            if [ "$existing_gateway" = "$VPC_PEERING_ID" ]; then
                log_info "Route already exists and is correct"
                continue
            else
                log_warning "Route exists but points to different target: $existing_gateway"
                log_step "Replacing existing route..."
                aws ec2 replace-route \
                    --route-table-id "$rt_id" \
                    --destination-cidr-block "$DRAGONFLYDB_VPC_CIDR" \
                    --vpc-peering-connection-id "$VPC_PEERING_ID" \
                    --region "$AWS_REGION" 2>/dev/null || true
            fi
        else
            # Create new route
            log_step "Creating new route to DragonflyDB VPC..."
            if aws ec2 create-route \
                --route-table-id "$rt_id" \
                --destination-cidr-block "$DRAGONFLYDB_VPC_CIDR" \
                --vpc-peering-connection-id "$VPC_PEERING_ID" \
                --region "$AWS_REGION" >/dev/null 2>&1; then
                log_success "Route created successfully"
            else
                log_warning "Route creation failed (may already exist)"
            fi
        fi

        CREATED_ROUTE_TABLES+=("$rt_id")
        ROLLBACK_RESOURCES+=("route:$rt_id,$DRAGONFLYDB_VPC_CIDR")
    done

    log_success "Route tables updated"
}

# Enable DNS support and hostnames
enable_dns_support() {
    log_header "Enabling DNS Support"

    # Enable DNS support
    log_step "Enabling DNS support..."
    if aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-support \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "DNS support enabled"
    else
        log_warning "Failed to enable DNS support (may already be enabled)"
    fi

    # Enable DNS hostnames
    log_step "Enabling DNS hostnames..."
    if aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-hostnames \
        --region "$AWS_REGION" >/dev/null 2>&1; then
        log_success "DNS hostnames enabled"
    else
        log_warning "Failed to enable DNS hostnames (may already be enabled)"
    fi

    log_success "DNS support configured"
}

# Verify VPC peering setup
verify_vpc_peering() {
    log_header "Verifying VPC Peering Setup"

    # Check peering status
    log_step "Checking VPC peering status..."
    local peering_status
    peering_status=$(aws ec2 describe-vpc-peering-connections \
        --vpc-peering-connection-ids "$VPC_PEERING_ID" \
        --region "$AWS_REGION" \
        --query "VpcPeeringConnections[0].Status.Code" \
        --output text 2>/dev/null)

    if [ "$peering_status" = "active" ]; then
        log_success "VPC peering is active"
    else
        log_error "VPC peering status: $peering_status"
        return 1
    fi

    # Check route table routes
    log_step "Verifying route table routes..."
    local routes_ok=true
    for rt_id in "${CREATED_ROUTE_TABLES[@]}"; do
        local route_exists
        route_exists=$(aws ec2 describe-routes \
            --route-table-id "$rt_id" \
            --filters "Name=destination-cidr-block,Values=$DRAGONFLYDB_VPC_CIDR" \
            --region "$AWS_REGION" \
            --query "Routes[0].State" \
            --output text 2>/dev/null || echo "failed")

        if [ "$route_exists" = "active" ]; then
            log_success "Route table $rt_id: OK"
        else
            log_error "Route table $rt_id: FAILED ($route_exists)"
            routes_ok=false
        fi
    done

    if [ "$routes_ok" = false ]; then
        log_error "Some route table routes are not active"
        return 1
    fi

    # Check security group rules
    log_step "Verifying security group rules..."
    local sg_rules_ok=true
    for sg_rule in "${CREATED_SG_RULES[@]}"; do
        local sg_id=$(echo "$sg_rule" | cut -d',' -f1)
        local rule_id=$(echo "$sg_rule" | cut -d',' -f2)

        local rule_exists
        rule_exists=$(aws ec2 describe-security-group-rules \
            --filters "Name=group-id,Values=$sg_id" "Name=security-group-rule-id,Values=$rule_id" \
            --region "$AWS_REGION" \
            --query "SecurityGroupRules[0].IsEgress" \
            --output text 2>/dev/null || echo "failed")

        if [ "$rule_exists" = "true" ]; then
            log_success "Security group rule $rule_id: OK"
        else
            log_error "Security group rule $rule_id: FAILED"
            sg_rules_ok=false
        fi
    done

    if [ "$sg_rules_ok" = false ]; then
        log_error "Some security group rules are not active"
        return 1
    fi

    log_success "VPC peering verification completed successfully"
    return 0
}

# Print setup summary
print_summary() {
    log_header "VPC Peering Setup Summary"
    echo ""
    log_success "✅ VPC Peering Connection: $VPC_PEERING_ID"
    log_success "✅ Security Group Rules: ${#CREATED_SG_RULES[@]} created"
    log_success "✅ Route Tables Updated: ${#CREATED_ROUTE_TABLES[@]} tables"
    log_success "✅ DNS Support: Enabled"
    echo ""

    log_info "Configuration Details:"
    log_info "  Your VPC ID: $VPC_ID"
    log_info "  Your VPC CIDR: $VPC_CIDR"
    log_info "  DragonflyDB VPC ID: $DRAGONFLYDB_VPC_ID"
    log_info "  DragonflyDB VPC CIDR: $DRAGONFLYDB_VPC_CIDR"
    log_info "  DragonflyDB Host: $DRAGONFLYDB_HOST"
    log_info "  DragonflyDB Port: $DRAGONFLYDB_PORT"
    echo ""

    log_info "Created Resources:"
    for sg_rule in "${CREATED_SG_RULES[@]}"; do
        log_info "  Security Group Rule: $sg_rule"
    done
    for rt_id in "${CREATED_ROUTE_TABLES[@]}"; do
        log_info "  Route Table: $rt_id -> $DRAGONFLYDB_VPC_CIDR via $VPC_PEERING_ID"
    done
    echo ""

    log_info "Next Steps:"
    log_info "1. Update your .env file with VPC peering configuration"
    log_info "2. Test DragonflyDB connectivity using: ./scripts/verify_dragonflydb_connection.sh --vpc-only"
    log_info "3. Update application configuration to use DragonflyDB endpoint"
    log_info "4. Monitor VPC peering performance and metrics"
    echo ""

    log_warning "Save this information for future reference:"
    log_warning "VPC_PEERING_ID=$VPC_PEERING_ID"
    log_warning "DRAGONFLYDB_VPC_ID=$DRAGONFLYDB_VPC_ID"
    log_warning "DRAGONFLYDB_VPC_CIDR=$DRAGONFLYDB_VPC_CIDR"
    log_warning "ENABLE_VPC_PEERING=true"
}

# Main execution function
main() {
    # Set up error handling
    trap rollback ERR

    log_header "🔗 VPC Peering Setup for DragonflyDB Cloud"
    log_info "This script will set up VPC peering between your VPC and DragonflyDB Cloud"
    echo ""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --skip-prometheus-test)
                SKIP_PROMETHEUS_TEST=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "OPTIONS:"
                echo "  --non-interactive      Run without prompts"
                echo "  --skip-prometheus-test Skip Prometheus verification"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "ENVIRONMENT VARIABLES:"
                echo "  VPC_ID                 Your VPC ID (default: vpc-00e79f7555aa68c0e)"
                echo "  VPC_CIDR               Your VPC CIDR (default: 192.168.0.0/16)"
                echo "  AWS_ACCOUNT_ID         Your AWS Account ID (default: 962364259018)"
                echo "  AWS_REGION             Your AWS Region (default: us-east-1)"
                echo "  DRAGONFLYDB_VPC_ID      DragonflyDB VPC ID (required)"
                echo "  DRAGONFLYDB_VPC_CIDR    DragonflyDB VPC CIDR (required)"
                echo "  DRAGONFLYDB_ACCOUNT_ID  DragonflyDB AWS Account ID (required)"
                echo "  DRAGONFLYDB_REGION      DragonflyDB AWS Region (required)"
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

    # Check prerequisites
    check_prerequisites

    # Create VPC peering
    create_vpc_peering

    # Configure security groups
    create_security_group_rules

    # Update route tables
    update_route_tables

    # Enable DNS support
    enable_dns_support

    # Verify setup
    verify_vpc_peering

    # Run DragonflyDB verification if requested
    if [ "$SKIP_PROMETHEUS_TEST" = false ] && command -v ./scripts/verify_dragonflydb_connection.sh >/dev/null 2>&1; then
        log_step "Running DragonflyDB connection verification..."
        if ./scripts/verify_dragonflydb_connection.sh --vpc-only; then
            log_success "DragonflyDB connection verification passed"
        else
            log_warning "DragonflyDB connection verification failed - check logs"
        fi
    fi

    # Print summary
    print_summary

    log_success "VPC peering setup completed successfully! 🚀"
}

# Run main function
main "$@"