#!/bin/bash

# =============================================================================
# 🛡️ Filter Performance Verification Script for MojoRust Trading Bot
# =============================================================================
# This script analyzes logs to ensure 90%+ spam rejection rate is maintained
# Reference: src/monitoring/filter_monitor.mojo lines 180-216 for filter statistics

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
LOG_DIR="logs"
HOURS_TO_ANALYZE=24
JSON_OUTPUT=false
SPECIFIC_LOG_FILE=""
VERBOSE=false

# Filter performance thresholds
MIN_HEALTHY_REJECTION=85
MAX_HEALTHY_REJECTION=97

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --hours)
            HOURS_TO_ANALYZE="$2"
            shift 2
            ;;
        --log)
            SPECIFIC_LOG_FILE="$2"
            shift 2
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --hours <N>         Analyze last N hours (default: 24)"
            echo "  --log <FILE>         Analyze specific log file"
            echo "  --json               Output results in JSON format"
            echo "  --verbose            Show detailed analysis"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "EXAMPLES:"
            echo "  $0                                    # Analyze all logs (last 24h)"
            echo "  $0 --hours 48                        # Analyze last 48 hours"
            echo "  $0 --log logs/trading-bot-20241015.log  # Analyze specific log"
            echo "  $0 --json                          # JSON output for automation"
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

# Logging functions
log_info() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${BLUE}ℹ️  $1${NC}"
    fi
}

log_success() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}✅ $1${NC}"
    fi
}

log_warning() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${YELLOW}⚠️  $1${NC}"
    fi
}

log_error() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${RED}❌ $1${NC}"
    fi
}

log_header() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}$1${NC}"
    fi
}

log_verbose() {
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "${CYAN}  $1${NC}"
    fi
}

# JSON output structure
declare -A analysis_results

# Function to extract filter performance from logs
extract_filter_performance() {
    local log_pattern="🛡️  Filter Performance: "
    local temp_file=$(mktemp)

    if [ -n "$SPECIFIC_LOG_FILE" ]; then
        # Analyze specific log file
        if [ ! -f "$SPECIFIC_LOG_FILE" ]; then
            log_error "Log file not found: $SPECIFIC_LOG_FILE"
            return 1
        fi
        log_verbose "Extracting from: $SPECIFIC_LOG_FILE"
        grep "$log_pattern" "$SPECIFIC_LOG_FILE" > "$temp_file" 2>/dev/null || true
    else
        # Analyze all log files in the directory
        if [ ! -d "$LOG_DIR" ]; then
            log_error "Log directory not found: $LOG_DIR"
            return 1
        fi

        # Find log files modified within the specified time range
        local time_filter=""
        if [ "$HOURS_TO_ANALYZE" != "all" ]; then
            time_filter="-mtime -${HOURS_TO_ANALYZE}"
        fi

        log_verbose "Searching log files in $LOG_DIR (last ${HOURS_TO_ANALYZE} hours)"
        find "$LOG_DIR" -name "trading-bot-*.log" $time_filter -type f -exec grep -l "$log_pattern" {} \; | \
            xargs grep "$log_pattern" {} 2>/dev/null > "$temp_file" || true
    fi

    # Count total samples
    local total_samples=$(wc -l < "$temp_file" 2>/dev/null || echo "0")
    analysis_results["total_samples"]="$total_samples"

    if [ "$total_samples" -eq 0 ]; then
        log_warning "No filter performance logs found"
        rm -f "$temp_file"
        return 1
    fi

    log_verbose "Found $total_samples filter performance entries"

    # Extract rejection rates
    local rejection_rates_file=$(mktemp)
    grep -oP '\d+\.\d+(?=% rejection)' "$temp_file" > "$rejection_rates_file" 2>/dev/null || true

    # Calculate statistics
    local rates_count=$(wc -l < "$rejection_rates_file" 2>/dev/null || echo "0")

    if [ "$rates_count" -eq 0 ]; then
        log_error "Could not parse rejection rates from logs"
        rm -f "$temp_file" "$rejection_rates_file"
        return 1
    fi

    # Calculate statistics using awk
    local stats=$(awk '
    BEGIN {
        sum = 0
        min = 999
        max = 0
        count = 0
    }
    {
        rate = $1
        sum += rate
        if (rate < min) min = rate
        if (rate > max) max = rate
        count++
    }
    END {
        if (count > 0) {
            avg = sum / count
            # Calculate standard deviation
            close("'$rejection_rates_file'")
            while ((getline line < "'$rejection_rates_file'")) {
                rate = $1
                diff = rate - avg
                sum_sq += diff * diff
            }
            if (count > 1) {
                std_dev = sqrt(sum_sq / (count - 1))
            } else {
                std_dev = 0
            }
            printf "%.2f %.2f %.2f %.2f %.0f", avg, min, max, std_dev, count
        }
    }' "$rejection_rates_file")

    # Parse statistics
    local avg_rate=$(echo "$stats" | cut -d' ' -f1)
    local min_rate=$(echo "$stats" | cut -d' ' -f2)
    local max_rate=$(echo "$stats" | cut -d' ' -f3)
    local std_dev=$(echo "$stats" | cut -d' ' -f4)
    local count=$(echo "$stats" | cut -d' ' -f5)

    analysis_results["avg_rejection"]="$avg_rate"
    analysis_results["min_rejection"]="$min_rate"
    analysis_results["max_rejection"]="$max_rate"
    analysis_results["std_dev_rejection"]="$std_dev"
    analysis_results["analyzed_count"]="$count"

    # Get latest sample
    local latest_sample=$(tail -1 "$temp_file")
    local latest_rate=$(echo "$latest_sample" | grep -oP '\d+\.\d+(?=% rejection)' || echo "0")
    analysis_results["latest_rejection"]="$latest_rate"

    # Parse filter breakdown if available
    parse_filter_breakdown "$temp_file"

    # Cleanup
    rm -f "$temp_file" "$rejection_rates_file"
}

# Function to parse filter breakdown by type
parse_filter_breakdown() {
    local log_file="$1"
    local breakdown_file=$(mktemp)

    # Extract breakdown lines (look for multi-line filter breakdown)
    awk '/Filter Performance:/ {
        # Found a line, extract the next few lines for breakdown
        line = $0
        print line

        # Get next lines until we find a different log line or EOF
        while ((getline next_line > 0)) {
            if (next_line ~ /Filter Performance:/ || next_line ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) {
                # New filter performance entry or new log entry, stop
                print ""
                close("'$breakdown_file'")
                return
            }
            if (next_line ~ /Instant Filter:|Aggressive Filter:|Micro Filter:|Cooldown:|Volume Quality:/) {
                print next_line
            }
        }
    }' "$log_file" > "$breakdown_file"

    # Parse breakdown data
    # Use robust AWK parsing instead of fragile grep-awk chains
    local counts=$(awk '
    BEGIN {
        instant = 0; aggressive = 0; micro = 0; cooldown = 0; volume_quality = 0; errors = 0
    }
    /Instant Filter:/ {
        if (match($0, /\(([0-9]+)/, arr)) instant += arr[1]
        else errors++
    }
    /Aggressive Filter:/ {
        if (match($0, /\(([0-9]+)/, arr)) aggressive += arr[1]
        else errors++
    }
    /Micro Filter:/ {
        if (match($0, /\(([0-9]+)/, arr)) micro += arr[1]
        else errors++
    }
    /Cooldown:/ {
        if (match($0, /\(([0-9]+)/, arr)) cooldown += arr[1]
        else errors++
    }
    /Volume Quality:/ {
        if (match($0, /\(([0-9]+)/, arr)) volume_quality += arr[1]
        else errors++
    }
    END {
        print instant, aggressive, micro, cooldown, volume_quality, errors
    }
    ' "$breakdown_file")

    local instant_count=$(echo "$counts" | cut -d' ' -f1)
    local aggressive_count=$(echo "$counts" | cut -d' ' -f2)
    local micro_count=$(echo "$counts" | cut -d' ' -f3)
    local cooldown_count=$(echo "$counts" | cut -d' ' -f4)
    local volume_quality_count=$(echo "$counts" | cut -d' ' -f5)
    local parsing_errors=$(echo "$counts" | cut -d' ' -f6)

    if [[ $parsing_errors -gt 0 ]]; then
        echo "WARNING: Found $parsing_errors parsing errors in filter log" >&2
    fi

    local total_signals=$((instant_count + aggressive_count + micro_count + cooldown_count + volume_quality_count))

    analysis_results["instant_filter_count"]="$instant_count"
    analysis_results["aggressive_filter_count"]="$aggressive_count"
    analysis_results["micro_filter_count"]="$micro_count"
    analysis_results["cooldown_count"]="$cooldown_count"
    analysis_results["volume_quality_count"]="$volume_quality_count"
    analysis_results["total_signals_processed"]="$total_signals"

    if [ "$VERBOSE" = true ] && [ "$total_signals" -gt 0 ]; then
        log_verbose "Filter Breakdown:"
        log_verbose "  Instant Filter:    $instant_count ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "$instant_count $total_signals")%)"
        log_verbose "  Aggressive Filter: $aggressive_count ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "$aggressive_count $total_signals")%)"
        log_verbose "  Micro Filter:      $micro_count ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "$micro_count $total_signals")%)"
        log_verbose "  Cooldown:          $cooldown_count ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "$cooldown_count $total_signals")%)"
        log_verbose "  Volume Quality:    $volume_quality_count ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "$volume_quality_count $total_signals")%)"
    fi

    rm -f "$breakdown_file"
}

# Function to check filter health
check_filter_health() {
    local latest_rate="${analysis_results[latest_rejection]}"
    local avg_rate="${analysis_results[avg_rejection]}"

    # Convert to integer for comparison
    local latest_int=$(echo "$latest_rate" | cut -d'.' -f1)
    local avg_int=$(echo "$avg_rate" | cut -d'.' -f1)

    local health_status="healthy"
    local health_message=""

    if (( latest_int >= MIN_HEALTHY_REJECTION && latest_int <= MAX_HEALTHY_REJECTION )); then
        health_status="healthy"
        health_message="Within optimal range ($MIN_HEALTHY_REJECTION%-$MAX_HEALTHY_REJECTION%)"
        analysis_results["health_status"]="healthy"
        analysis_results["health_message"]="$health_message"
    elif (( latest_int < MIN_HEALTHY_REJECTION )); then
        health_status="too_lenient"
        health_message="Below minimum threshold ($MIN_HEALTHY_REJECTION%)"
        analysis_results["health_status"]="too_lenient"
        analysis_results["health_message"]="$health_message"
    else
        health_status="too_aggressive"
        health_message="Above maximum threshold ($MAX_HEALTHY_REJECTION%)"
        analysis_results["health_status"]="too_aggressive"
        analysis_results["health_message"]="$health_message"
    fi

    # Check for anomalies (deviation from mean)
    local std_dev="${analysis_results[std_dev_rejection]}"
    local deviation=$(echo "scale=2; $latest_rate - $avg_rate" | bc 2>/dev/null || echo "0")
    local deviation_magnitude=$(echo "scale=2; $deviation / $std_dev" | bc 2>/dev/null || echo "0")
    local deviation_int=$(echo "$deviation_magnitude" | cut -d'.' -f1)

    if [ "$deviation_int" -gt 2 ]; then
        analysis_results["anomaly_detected"]="true"
        analysis_results["anomaly_message"]="Rejection rate deviates ${deviation_magnitude}σ from mean"
    else
        analysis_results["anomaly_detected"]="false"
        analysis_results["anomaly_message"]="No anomalies detected"
    fi
}

# Banner function
print_banner() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo -e "${PURPLE}"
        echo "╔═════════════════════════════════════════════════════════════════╗"
        echo "║                                                               ║"
        echo "║    🛡️  Filter Performance Analysis - MojoRust Trading Bot    ║"
        echo "║                                                               ║"
        if [ -n "$SPECIFIC_LOG_FILE" ]; then
            echo "║    Log File: $SPECIFIC_LOG_FILE                      ║"
        else
            echo "║    Time Range: Last $HOURS_TO_ANALYZE hours             ║"
        fi
        echo "║                                                               ║"
        echo "╚═════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
        echo ""
    fi
}

# Summary function
print_summary() {
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        log_header "================================"

        local total_samples="${analysis_results[total_samples]}"
        local analyzed_count="${analysis_results[analyzed_count]}"
        local avg_rate="${analysis_results[avg_rejection]}"
        local min_rate="${analysis_results[min_rejection]}"
        local max_rate="${analysis_results[max_rejection]}"
        local latest_rate="${analysis_results[latest_rejection]}"
        local health_status="${analysis_results[health_status]}"

        echo "Log Files Analyzed: $total_samples"
        echo "Time Range: Last $HOURS_TO_ANALYZE hours"
        echo "Valid Samples: $analyzed_count"
        echo ""

        echo "Rejection Rate Statistics:"
        echo "  Current:  ${latest_rate}%"
        echo "  Average:  ${avg_rate}%"
        echo "  Min:      ${min_rate}%"
        echo "  Max:      ${max_rate}%"
        echo "  Std Dev:  ${analysis_results[std_dev_rejection]}"
        echo ""

        # Health status
        if [ "$health_status" = "healthy" ]; then
            log_success "Health Status: ✅ $health_message"
        else
            log_warning "Health Status: ⚠️ $health_message"
        fi

        # Anomaly detection
        if [ "${analysis_results[anomaly_detected]}" = "true" ]; then
            log_warning "Anomaly Detected: ${analysis_results[anomaly_message]}"
        else
            log_info "Anomaly Detection: ✅ ${analysis_results[anomaly_message]}"
        fi

        # Filter breakdown
        local total_signals="${analysis_results[total_signals_processed]}"
        if [ "$total_signals" -gt 0 ]; then
            echo ""
            echo "Rejection Breakdown:"
            echo "  Instant Filter:    ${analysis_results[instant_filter_count]} ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "${analysis_results[instant_filter_count]} $total_signals")%)"
            echo "  Aggressive Filter: ${analysis_results[aggressive_filter_count]} ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "${analysis_results[aggressive_filter_count]} $total_signals")%)"
            echo "  Micro Filter:      ${analysis_results[micro_filter_count]} ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "${analysis_results[micro_filter_count]} $total_signals")%)"
            echo "  Cooldown:          ${analysis_results[cooldown_count]} ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "${analysis_results[cooldown_count]} $total_signals")%)"
            echo "  Volume Quality:    ${analysis_results[volume_quality_count]} ($(awk "BEGIN{printf \"%.1f\", ($1/$total_signals)*100}" <<< "${analysis_results[volume_quality_count]} $total_signals")%)"
            echo "  Total:              $total_signals"
        fi

        echo ""
        echo "================================"

        # Final verdict
        if [ "$health_status" = "healthy" ] && [ "${analysis_results[anomaly_detected]}" = "false" ]; then
            log_success "✅ Filter performance verified: ${avg_rate}% average rejection"
        else
            log_warning "⚠️  Filter performance requires attention"
        fi

    else
        # JSON output
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"time_range_hours\": $HOURS_TO_ANALYZE,"
        echo "  \"total_samples\": ${analysis_results[total_samples]},"
        echo "  \"analyzed_count\": ${analysis_results[analyzed_count]},"
        echo "  \"rejection_rate\": {"
        echo "    \"latest\": \"${analysis_results[latest_rejection]}%\","
        echo "    \"average\": \"${analysis_results[avg_rejection]}%\","
        echo "    \"minimum\": \"${analysis_results[min_rejection]}%\","
        echo "    \"maximum\": \"${analysis_results[max_rejection]}%\","
        echo "    \"std_deviation\": \"${analysis_results[std_dev_rejection]}%\""
        echo "  },"
        echo "  \"health\": {"
        echo "    \"status\": \"${analysis_results[health_status]}\","
        echo "    \"message\": \"${analysis_results[health_message]}\""
        echo "  },"
        echo "  \"anomaly\": {"
        echo "    \"detected\": ${analysis_results[anomaly_detected]},"
        echo "    \"message\": \"${analysis_results[anomaly_message]}\""
        echo "  },"
        echo "  \"filter_breakdown\": {"
        echo "    \"instant_filter\": ${analysis_results[instant_filter_count]},"
        echo "    \"aggressive_filter\": ${analysis_results[aggressive_filter_count]},"
        echo "    \"micro_filter\": ${analysis_results[micro_filter_count]},"
        echo "    \"cooldown\": ${analysis_results[cooldown_count]},"
        echo "    \"volume_quality\": ${analysis_results[volume_quality_count]},"
        echo "    \"total_signals\": ${analysis_results[total_signals_processed]}"
        echo "  }"
        echo "}"
    fi
}

# Main execution
main() {
    print_banner

    # Extract and analyze filter performance
    if extract_filter_performance; then
        # Check filter health
        check_filter_health

        # Print summary
        print_summary

        # Exit with appropriate code
        if [ "${analysis_results[health_status]}" = "healthy" ] && [ "${analysis_results[anomaly_detected]}" = "false" ]; then
            exit 0
        else
            exit 2  # Warning exit code
        fi
    else
        log_error "Failed to extract filter performance data"
        exit 1
    fi
}

# Run main function
main "$@"