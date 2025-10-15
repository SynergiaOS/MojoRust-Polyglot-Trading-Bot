#!/bin/bash

# scripts/health_check_cron.sh

# Configuration
CHECK_INTERVAL=300
ALERT_THRESHOLD=3
STATE_FILE="/tmp/health_check_state.json"
LOG_FILE="/var/log/trading-bot-health.log"

# Command Line Options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --check-interval) 
            CHECK_INTERVAL="$2"
            shift 2
            ;; 
        --alert-threshold) 
            ALERT_THRESHOLD="$2"
            shift 2
            ;; 
        --no-restart) 
            NO_RESTART=true
            shift
            ;; 
        --verbose) 
            VERBOSE=true
            shift
            ;; 
        --test) 
            TEST=true
            shift
            ;; 
        *) 
            echo "Unknown option: $1"
            exit 1
            ;; 
    esac
done

# Health Checks
function check_process() {
    pgrep -f "mojo run|trading-bot" > /dev/null
}

function check_api() {
    curl -s --max-time 5 http://localhost:8082/health | grep -q '"status":"healthy"'
}

function check_resources() {
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    MEMORY_USAGE=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

    if (( $(echo "$CPU_USAGE > 95" | bc -l) )); then return 1; fi
    if (( $(echo "$MEMORY_USAGE > 95" | bc -l) )); then return 1; fi
    if (( $(echo "$DISK_USAGE > 95" | bc -l) )); then return 1; fi
    return 0
}

function check_database() {
    psql -h localhost -U trading_user -c "SELECT 1" trading_db > /dev/null
}

function send_alert() {
    if [ "${TEST}" != true ]; then
        # Add your Telegram alert command here
        echo "Alert: $1"
    fi
}

# Main Logic
consecutive_failures=0
if [ -f "${STATE_FILE}" ]; then
    consecutive_failures=$(jq '.consecutive_failures' "${STATE_FILE}")
fi

failed=false
failure_reason=""

if ! check_process; then
    failed=true
    failure_reason="Process not running"
    if [ "${NO_RESTART}" != true ] && [ "${consecutive_failures}" -lt "${ALERT_THRESHOLD}" ]; then
        sudo systemctl restart trading-bot
    fi
fi

if ! check_api; then
    failed=true
    failure_reason="API unhealthy"
fi

if ! check_resources; then
    failed=true
    failure_reason="High resource usage"
fi

if ! check_database; then
    failed=true
    failure_reason="Database connection failed"
fi

if [ "${failed}" = true ]; then
    consecutive_failures=$((consecutive_failures + 1))
    if [ "${consecutive_failures}" -ge "${ALERT_THRESHOLD}" ]; then
        send_alert "Trading bot health check failed (${consecutive_failures} consecutive failures): ${failure_reason}"
    fi
else
    if [ "${consecutive_failures}" -ge "${ALERT_THRESHOLD}" ]; then
        send_alert "Trading bot health restored"
    fi
    consecutive_failures=0
fi

echo "{\"last_check\": $(date +%s), \"consecutive_failures\": ${consecutive_failures}, \"last_failure_reason\": \"${failure_reason}\"}" > "${STATE_FILE}"

