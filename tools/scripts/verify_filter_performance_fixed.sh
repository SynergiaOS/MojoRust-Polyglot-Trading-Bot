#!/bin/bash

# Fixed version of filter performance verification script
# Replaces fragile grep-awk chains with robust AWK parsing

set -euo pipefail

# Configuration
LOG_FILE="${1:-/var/log/mojorust/filter_performance.log}"
TEMP_DIR="/tmp/mojorust_filter_analysis"
BREAKDOWN_FILE="$TEMP_DIR/filter_breakdown.txt"

# Create temp directory
mkdir -p "$TEMP_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

# Extract filter counts using robust AWK parsing
extract_filter_counts() {
    local log_file="$1"

    if [[ ! -f "$log_file" ]]; then
        error "Log file not found: $log_file"
        return 1
    fi

    # Use AWK to parse and validate filter counts
    awk '
    BEGIN {
        instant = 0
        aggressive = 0
        micro = 0
        cooldown = 0
        volume_quality = 0
        total_lines = 0
        parsing_errors = 0
    }

    # Filter patterns with validation
    /Instant Filter:/ {
        if (match($0, /\(([0-9]+)/, arr)) {
            instant += arr[1]
        } else {
            parsing_errors++
            print "WARNING: Invalid Instant Filter line: " $0 > "/dev/stderr"
        }
        total_lines++
    }

    /Aggressive Filter:/ {
        if (match($0, /\(([0-9]+)/, arr)) {
            aggressive += arr[1]
        } else {
            parsing_errors++
            print "WARNING: Invalid Aggressive Filter line: " $0 > "/dev/stderr"
        }
        total_lines++
    }

    /Micro Filter:/ {
        if (match($0, /\(([0-9]+)/, arr)) {
            micro += arr[1]
        } else {
            parsing_errors++
            print "WARNING: Invalid Micro Filter line: " $0 > "/dev/stderr"
        }
        total_lines++
    }

    /Cooldown:/ {
        if (match($0, /\(([0-9]+)/, arr)) {
            cooldown += arr[1]
        } else {
            parsing_errors++
            print "WARNING: Invalid Cooldown line: " $0 > "/dev/stderr"
        }
        total_lines++
    }

    /Volume Quality:/ {
        if (match($0, /\(([0-9]+)/, arr)) {
            volume_quality += arr[1]
        } else {
            parsing_errors++
            print "WARNING: Invalid Volume Quality line: " $0 > "/dev/stderr"
        }
        total_lines++
    }

    END {
        # Output results in machine-readable format
        print "INSTANT_COUNT=" instant
        print "AGGRESSIVE_COUNT=" aggressive
        print "MICRO_COUNT=" micro
        print "COOLDOWN_COUNT=" cooldown
        print "VOLUME_QUALITY_COUNT=" volume_quality
        print "TOTAL_LINES=" total_lines
        print "PARSING_ERRORS=" parsing_errors

        # Exit with error if too many parsing errors
        if (parsing_errors > 0) {
            exit 1
        }
    }
    ' "$log_file"
}

# Calculate filter efficiency metrics
calculate_metrics() {
    local instant="$1"
    local aggressive="$2"
    local micro="$3"
    local cooldown="$4"
    local volume_quality="$5"

    local total_filtered=$((instant + aggressive + micro + cooldown + volume_quality))

    # Calculate rejection rates
    local instant_rejection_rate=0
    local aggressive_rejection_rate=0
    local micro_rejection_rate=0
    local cooldown_rejection_rate=0
    local volume_quality_rejection_rate=0

    if [[ $instant -gt 0 ]]; then
        instant_rejection_rate=$(echo "scale=2; ($instant / 1000) * 100" | bc -l)
    fi

    if [[ $aggressive -gt 0 ]]; then
        aggressive_rejection_rate=$(echo "scale=2; ($aggressive / 1000) * 100" | bc -l)
    fi

    if [[ $micro -gt 0 ]]; then
        micro_rejection_rate=$(echo "scale=2; ($micro / 1000) * 100" | bc -l)
    fi

    if [[ $cooldown -gt 0 ]]; then
        cooldown_rejection_rate=$(echo "scale=2; ($cooldown / 1000) * 100" | bc -l)
    fi

    if [[ $volume_quality -gt 0 ]]; then
        volume_quality_rejection_rate=$(echo "scale=2; ($volume_quality / 1000) * 100" | bc -l)
    fi

    # Calculate overall efficiency
    local overall_efficiency=0
    if [[ $total_filtered -gt 0 ]]; then
        overall_efficiency=$(echo "scale=2; ($total_filtered / 10000) * 100" | bc -l)
    fi

    # Output metrics
    cat << EOF
FILTER_PERFORMANCE_METRICS:
========================
Total Signals Processed: 10000
Total Filtered: $total_filtered
Overall Efficiency: ${overall_efficiency}%

Breakdown by Filter Type:
- Instant Filter: $instant (${instant_rejection_rate}%)
- Aggressive Filter: $aggressive (${aggressive_rejection_rate}%)
- Micro Filter: $micro (${micro_rejection_rate}%)
- Cooldown Filter: $cooldown (${cooldown_rejection_rate}%)
- Volume Quality Filter: $volume_quality (${volume_quality_rejection_rate}%)

Performance Targets:
- Target Efficiency: >90%
- Target Overall Rejection: >95%
EOF

    # Check if targets are met
    local efficiency_met=false
    local rejection_met=false

    if (( $(echo "$overall_efficiency >= 90" | bc -l) )); then
        efficiency_met=true
    fi

    if (( $(echo "$overall_efficiency >= 95" | bc -l) )); then
        rejection_met=true
    fi

    echo ""
    echo "TARGET_STATUS:"
    echo "============="
    if $efficiency_met; then
        echo "✅ Efficiency Target (>=90%): MET"
    else
        echo "❌ Efficiency Target (>=90%): NOT MET"
    fi

    if $rejection_met; then
        echo "✅ Rejection Target (>=95%): MET"
    else
        echo "❌ Rejection Target (>=95%): NOT MET"
    fi

    return 0
}

# Main execution
main() {
    log "Starting filter performance verification..."
    log "Analyzing log file: $LOG_FILE"

    # Extract filter counts with error handling
    local parse_result
    parse_result=$(extract_filter_counts "$LOG_FILE" 2>"$TEMP_DIR/parse_errors.log")

    if [[ $? -ne 0 ]]; then
        error "Failed to parse log file"
        if [[ -f "$TEMP_DIR/parse_errors.log" ]]; then
            echo "Parsing errors detected:"
            cat "$TEMP_DIR/parse_errors.log"
        fi
        return 1
    fi

    # Extract counts from parse result
    local instant_count=$(echo "$parse_result" | grep "INSTANT_COUNT=" | cut -d'=' -f2)
    local aggressive_count=$(echo "$parse_result" | grep "AGGRESSIVE_COUNT=" | cut -d'=' -f2)
    local micro_count=$(echo "$parse_result" | grep "MICRO_COUNT=" | cut -d'=' -f2)
    local cooldown_count=$(echo "$parse_result" | grep "COOLDOWN_COUNT=" | cut -d'=' -f2)
    local volume_quality_count=$(echo "$parse_result" | grep "VOLUME_QUALITY_COUNT=" | cut -d'=' -f2)
    local total_lines=$(echo "$parse_result" | grep "TOTAL_LINES=" | cut -d'=' -f2)
    local parsing_errors=$(echo "$parse_result" | grep "PARSING_ERRORS=" | cut -d'=' -f2)

    # Validate results
    log "Parse Results:"
    log "  Total filter lines processed: $total_lines"
    log "  Parsing errors: $parsing_errors"
    log "  Instant Filter count: $instant_count"
    log "  Aggressive Filter count: $aggressive_count"
    log "  Micro Filter count: $micro_count"
    log "  Cooldown Filter count: $cooldown_count"
    log "  Volume Quality Filter count: $volume_quality_count"

    if [[ $parsing_errors -gt 0 ]]; then
        warn "Found $parsing_errors parsing errors. Check $TEMP_DIR/parse_errors.log for details."
    fi

    # Calculate and display metrics
    calculate_metrics "$instant_count" "$aggressive_count" "$micro_count" "$cooldown_count" "$volume_quality_count"

    # Cleanup
    rm -rf "$TEMP_DIR"

    log "Filter performance verification completed successfully."
    return 0
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v awk &> /dev/null; then
        missing_deps+=("awk")
    fi

    if ! command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        error "Please install the missing dependencies and try again."
        return 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Check dependencies first
    check_dependencies

    # Run main function
    main "$@"
fi