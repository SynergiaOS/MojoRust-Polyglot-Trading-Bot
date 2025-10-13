#!/bin/bash

# =============================================================================
# 📊 MojoRust Trading Bot - Performance Profiling Script
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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
        "METRIC")
            echo -e "${CYAN}📊 $message${NC}"
            ;;
    esac
}

# Function to show help
show_help() {
    cat << EOF
📊 MojoRust Trading Bot - Performance Profiling Script

USAGE:
    $0 [OPTIONS] [COMMAND]

OPTIONS:
    --duration SECONDS   Profile duration (default: 300 = 5 minutes)
    --output FILE        Output log file (default: logs/profile-<timestamp>.log)
    --memory-profiling   Enable memory profiling
    --cpu-profiling      Enable CPU profiling
    --benchmark          Run benchmark tests instead of live profiling
    --analyze-only       Analyze existing profile log file
    --help, -h           Show this help message

COMMANDS:
    profile              Run bot with profiling (default)
    benchmark            Run benchmark suite
    analyze              Analyze profiling results
    memory-check         Check memory usage patterns

EXAMPLES:
    $0                                  # Profile for 5 minutes
    $0 --duration 600                    # Profile for 10 minutes
    $0 --memory-profiling --cpu-profiling # Full profiling
    $0 --benchmark                       # Run benchmarks
    $0 --analyze-only --output logs/profile-20231201_120000.log

DESCRIPTION:
    This script profiles the trading bot performance:
    - CPU and memory usage monitoring
    - Execution timing analysis
    - Performance bottlenecks identification
    - Benchmark testing
    - Historical profiling data analysis

    Results are saved to logs/profile-*.log files.

EXIT CODES:
    0   Success
    1   Error (profiling failed, missing dependencies, etc.)

EOF
}

# Parse command line arguments
DURATION=300
OUTPUT_FILE=""
MEMORY_PROFILING=false
CPU_PROFILING=false
BENCHMARK_MODE=false
ANALYZE_ONLY=false
COMMAND="profile"

while [[ $# -gt 0 ]]; do
    case $1 in
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --memory-profiling)
            MEMORY_PROFILING=true
            shift
            ;;
        --cpu-profiling)
            CPU_PROFILING=true
            shift
            ;;
        --benchmark)
            BENCHMARK_MODE=true
            COMMAND="benchmark"
            shift
            ;;
        --analyze-only)
            ANALYZE_ONLY=true
            COMMAND="analyze"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        profile|benchmark|analyze|memory-check)
            COMMAND="$1"
            shift
            ;;
        *)
            print_status "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate duration
if ! [[ "$DURATION" =~ ^[0-9]+$ ]] || [ "$DURATION" -lt 10 ]; then
    print_status "ERROR" "Duration must be a positive integer (minimum 10 seconds)"
    exit 1
fi

# Set default output file if not specified
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="logs/profile-$(date +%Y%m%d_%H%M%S).log"
fi

# Create logs directory
mkdir -p logs

# Function to check dependencies
check_dependencies() {
    print_status "PROGRESS" "Checking profiling dependencies..."

    local missing_deps=()

    # Check basic commands
    for cmd in time ps grep tail awk bc; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    # Check for advanced profiling tools
    if [ "$CPU_PROFILING" = true ]; then
        if ! command -v perf >/dev/null 2>&1; then
            print_status "WARNING" "perf not found, CPU profiling will be limited"
        fi
    fi

    if [ "$MEMORY_PROFILING" = true ]; then
        if ! command -v valgrind >/dev/null 2>&1; then
            print_status "WARNING" "valgrind not found, memory profiling will be limited"
        fi
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_status "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        print_status "INFO" "Install missing tools with: apt install time coreutils perf valgrind"
        exit 1
    fi

    print_status "SUCCESS" "All dependencies available"
}

# Function to start bot with profiling
start_profiling() {
    print_status "PROGRESS" "Starting trading bot profiling..."
    print_status "INFO" "Duration: $DURATION seconds"
    print_status "INFO" "Output file: $OUTPUT_FILE"

    # Initialize profile log
    {
        echo "=== MojoRust Trading Bot Performance Profile ==="
        echo "Start Time: $(date)"
        echo "Duration: $DURATION seconds"
        echo "Memory Profiling: $MEMORY_PROFILING"
        echo "CPU Profiling: $CPU_PROFILING"
        echo "Command: $0 $*"
        echo "System Info:"
        echo "  OS: $(uname -s -r)"
        echo "  CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)"
        echo "  Memory: $(free -h | grep '^Mem:' | awk '{print $2}')"
        echo "  Cores: $(nproc)"
        echo ""
    } > "$OUTPUT_FILE"

    # Start background monitoring
    local monitoring_pid=""
    if [ "$MEMORY_PROFILING" = true ] || [ "$CPU_PROFILING" = true ]; then
        print_status "INFO" "Starting background monitoring..."
        start_background_monitoring &
        monitoring_pid=$!
    fi

    # Start the bot with profiling
    local start_time=$(date +%s)
    local end_time=$((start_time + DURATION))

    print_status "INFO" "Starting bot with time command..."
    print_status "INFO" "Press Ctrl+C to stop profiling early"

    {
        echo "=== Bot Execution ==="
        echo "Start: $(date)"
        echo ""

        # Run bot with time command
        if [ -f "src/main.mojo" ]; then
            # Try to run with mojo
            if command -v mojo >/dev/null 2>&1; then
                echo "Running with Mojo..."
                timeout "$DURATION" time -v mojo run src/main.mojo 2>&1 || echo "Bot execution completed or timed out"
            else
                print_status "WARNING" "Mojo not found, trying alternative execution..."
                timeout "$DURATION" time -v ./scripts/deploy_with_filters.sh 2>&1 || echo "Bot execution completed or timed out"
            fi
        else
            print_status "ERROR" "src/main.mojo not found"
            echo "Cannot run bot profiling - main.mojo not found"
        fi

        echo ""
        echo "End: $(date)"
        echo "Duration: $(($(date +%s) - start_time)) seconds"
    } >> "$OUTPUT_FILE" 2>&1

    # Stop background monitoring
    if [ -n "$monitoring_pid" ]; then
        kill "$monitoring_pid" 2>/dev/null || true
        wait "$monitoring_pid" 2>/dev/null || true
    fi

    # Add profiling summary
    {
        echo ""
        echo "=== Profiling Summary ==="
        echo "End Time: $(date)"
        echo "Total Duration: $(($(date +%s) - start_time)) seconds"
        echo "Log File: $OUTPUT_FILE"
        echo ""
    } >> "$OUTPUT_FILE"

    print_status "SUCCESS" "Profiling completed"
}

# Function to start background monitoring
start_background_monitoring() {
    local monitor_interval=5
    local counter=0

    while [ $counter -lt $((DURATION / monitor_interval)) ]; do
        {
            echo "--- Monitor Entry $((counter * monitor_interval))s ---"
            date

            # System stats
            echo "System Load: $(uptime | awk -F'load average:' '{print $2}')"
            echo "Memory Usage: $(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
            echo "Disk Usage: $(df -h . | awk 'NR==2{print $5}')"

            # Bot process stats
            local bot_pids=$(pgrep -f 'trading-bot|mojo run|main.mojo' 2>/dev/null || true)
            if [ -n "$bot_pids" ]; then
                echo "Bot Processes:"
                echo "$bot_pids" | while read -r pid; do
                    if [ -n "$pid" ]; then
                        local cpu_usage=$(ps -p "$pid" -o %cpu --no-headers 2>/dev/null | xargs)
                        local mem_usage=$(ps -p "$pid" -o %mem --no-headers 2>/dev/null | xargs)
                        local rss=$(ps -p "$pid" -o rss --no-headers 2>/dev/null | xargs)
                        echo "  PID $pid: CPU ${cpu_usage}%, MEM ${mem_usage}%, RSS ${rss}KB"
                    fi
                done
            else
                echo "No bot processes found"
            fi

            echo ""
        } >> "$OUTPUT_FILE"

        sleep $monitor_interval
        ((counter++))
    done
}

# Function to run benchmarks
run_benchmarks() {
    print_status "PROGRESS" "Running performance benchmarks..."

    {
        echo "=== MojoRust Trading Bot Benchmarks ==="
        echo "Start Time: $(date)"
        echo ""

        # Test system performance
        echo "--- System Benchmarks ---"
        echo "CPU Benchmark:"
        time $(python3 -c "import math; [math.sqrt(i) for i in range(1000000)]" 2>/dev/null || echo "Python benchmark failed") 2>&1 || true

        echo "Memory Benchmark:"
        time python3 -c "data = [0] * 1000000; sum(data)" 2>/dev/null || echo "Memory benchmark failed" 2>&1 || true

        echo "I/O Benchmark:"
        time dd if=/dev/zero of=/tmp/benchmark bs=1M count=100 2>&1 | grep -E "copied|real" || true
        rm -f /tmp/benchmark

        echo ""

        # Test Rust compilation
        if [ -f "Cargo.toml" ]; then
            echo "--- Rust Compilation Benchmark ---"
            time cargo check --release 2>&1 || echo "Cargo check failed"
            echo ""
        fi

        # Test Mojo compilation
        if [ -f "src/main.mojo" ] && command -v mojo >/dev/null 2>&1; then
            echo "--- Mojo Compilation Benchmark ---"
            time mojo build src/main.mojo 2>&1 || echo "Mojo build failed"
            echo ""
        fi

        # Network benchmarks
        echo "--- Network Benchmarks ---"
        time curl -s -o /dev/null -w "%{time_total}" https://api.github.com 2>/dev/null || echo "Network benchmark failed"
        echo ""

        echo "End Time: $(date)"
    } > "$OUTPUT_FILE" 2>&1

    print_status "SUCCESS" "Benchmarks completed"
}

# Function to analyze profiling results
analyze_results() {
    print_status "PROGRESS" "Analyzing profiling results..."

    if [ ! -f "$OUTPUT_FILE" ]; then
        print_status "ERROR" "Profile log file not found: $OUTPUT_FILE"
        exit 1
    fi

    print_status "INFO" "Analyzing: $OUTPUT_FILE"

    {
        echo "=== Performance Analysis ==="
        echo "Analysis Time: $(date)"
        echo "Source File: $OUTPUT_FILE"
        echo ""

        # Extract timing information
        echo "--- Timing Analysis ---"
        grep -E "real|user|sys" "$OUTPUT_FILE" | tail -10 || echo "No timing data found"
        echo ""

        # Extract memory usage
        echo "--- Memory Usage Analysis ---"
        grep -E "Memory Usage|MEM.*%|RSS.*KB" "$OUTPUT_FILE" | tail -20 || echo "No memory data found"
        echo ""

        # Extract CPU usage
        echo "--- CPU Usage Analysis ---"
        grep -E "CPU.*%|Load Average" "$OUTPUT_FILE" | tail -20 || echo "No CPU data found"
        echo ""

        # Extract errors/warnings
        echo "--- Issues Analysis ---"
        grep -iE "error|warning|failed|exception" "$OUTPUT_FILE" | tail -10 || echo "No issues found"
        echo ""

        # Performance summary
        echo "--- Performance Summary ---"
        local lines_count=$(wc -l < "$OUTPUT_FILE")
        echo "Total log lines: $lines_count"

        local error_count=$(grep -ci "error" "$OUTPUT_FILE" || echo "0")
        echo "Error count: $error_count"

        local warning_count=$(grep -ci "warning" "$OUTPUT_FILE" || echo "0")
        echo "Warning count: $warning_count"

        echo ""
    } | tee -a "$OUTPUT_FILE"

    print_status "SUCCESS" "Analysis completed"
    print_status "INFO" "Results appended to: $OUTPUT_FILE"
}

# Function to check memory usage patterns
memory_check() {
    print_status "PROGRESS" "Checking memory usage patterns..."

    {
        echo "=== Memory Usage Check ==="
        echo "Check Time: $(date)"
        echo ""

        # Current system memory
        echo "--- Current System Memory ---"
        free -h
        echo ""

        # Bot process memory
        echo "--- Bot Process Memory ---"
        local bot_pids=$(pgrep -f 'trading-bot|mojo run|main.mojo' 2>/dev/null || true)
        if [ -n "$bot_pids" ]; then
            echo "$bot_pids" | while read -r pid; do
                if [ -n "$pid" ]; then
                    echo "PID $pid:"
                    ps -p "$pid" -o pid,ppid,%cpu,%mem,rss,vsz,cmd --no-headers 2>/dev/null || echo "  Process info not available"
                    echo ""
                fi
            done
        else
            echo "No bot processes running"
        fi

        # Memory leaks check
        echo "--- Memory Leak Indicators ---"
        if command -v valgrind >/dev/null 2>&1; then
            echo "Valgrind available - can run: valgrind --leak-check=full --show-leak-kinds=all ./scripts/deploy_with_filters.sh"
        else
            echo "Valgrind not available - install with: apt install valgrind"
        fi

        echo ""
    } > "$OUTPUT_FILE"

    print_status "SUCCESS" "Memory check completed"
}

# Function to show summary
show_summary() {
    local command_name=$1
    print_status "INFO" "📊 ${command_name^} Summary:"
    echo ""

    echo "Results saved to: $OUTPUT_FILE"
    echo "File size: $(du -h "$OUTPUT_FILE" | cut -f1)"
    echo "Log lines: $(wc -l < "$OUTPUT_FILE")"

    echo ""
    print_status "INFO" "Next steps:"
    echo "  • View results: less $OUTPUT_FILE"
    echo "  • Analyze: $0 --analyze-only --output $OUTPUT_FILE"
    echo "  • Monitor: tail -f $OUTPUT_FILE"
    echo "  • System health: ./scripts/server_health.sh"

    echo ""
    print_status "SUCCESS" "✅ ${command_name^} completed successfully!"
}

# Main execution
main() {
    print_status "INFO" "📊 MojoRust Trading Bot - Performance Profiling"
    print_status "INFO" "Command: $COMMAND"
    print_status "INFO" "Output: $OUTPUT_FILE"
    echo ""

    # Check dependencies
    check_dependencies

    # Execute command
    case $COMMAND in
        "profile")
            start_profiling
            if [ "$ANALYZE_ONLY" = false ]; then
                analyze_results
            fi
            show_summary "profiling"
            ;;
        "benchmark")
            run_benchmarks
            show_summary "benchmark"
            ;;
        "analyze")
            analyze_results
            show_summary "analysis"
            ;;
        "memory-check")
            memory_check
            show_summary "memory check"
            ;;
        *)
            print_status "ERROR" "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Handle script interruption gracefully
trap 'print_status "WARNING"; print_status "WARNING" "Profiling interrupted by user"; exit 130' INT TERM

# Run main function
main