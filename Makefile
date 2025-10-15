# MojoRust Trading Bot Makefile

.PHONY: help install install-dev test test-fast test-coverage lint format clean build run docker-build docker-run \
        monitoring-start monitoring-stop monitoring-restart monitoring-status monitoring-verify \
        monitoring-health monitoring-import-dashboards monitoring-logs monitoring-backup \
        monitoring-cleanup monitoring-test-alerts monitoring-update-config monitoring-check-ports \
        cpu-diagnose cpu-optimize-vscode cpu-optimize-system cpu-monitor cpu-optimize-all \
        start-monitoring stop-monitoring restart-monitoring status-monitoring verify-monitoring \
        prometheus-targets grafana-dashboards import-dashboards logs-monitoring health-monitoring

# Monitoring configuration variables
PROMETHEUS_URL=http://localhost:9090
GRAFANA_URL=http://localhost:3001
ALERTMANAGER_URL=http://localhost:9093

# Default target
help:
	@echo "Available targets:"
	@echo "  install      - Install production dependencies"
	@echo "  install-dev  - Install development dependencies"
	@echo "  test         - Run all tests"
	@echo "  test-fast    - Run tests without slow tests"
	@echo "  test-coverage - Run tests with coverage"
	@echo "  lint         - Run linting"
	@echo "  format       - Format code"
	@echo "  clean        - Clean up temporary files"
	@echo "  build        - Build the project"
	@echo "  run          - Run the trading bot"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-run   - Run with Docker"
	@echo ""
	@echo "Monitoring targets:"
	@echo "  monitoring-start          - Start monitoring stack"
	@echo "  monitoring-stop           - Stop monitoring stack"
	@echo "  monitoring-restart        - Restart monitoring stack"
	@echo "  monitoring-status         - Check monitoring stack status"
	@echo "  monitoring-verify         - Verify monitoring stack health"
	@echo "  monitoring-health         - Quick health checks"
	@echo "  monitoring-import-dashboards - Import Grafana dashboards"
	@echo "  monitoring-logs           - Show monitoring service logs"
	@echo "  monitoring-backup         - Backup monitoring configurations"
	@echo "  monitoring-cleanup        - Clean monitoring data"
	@echo "  monitoring-test-alerts    - Test alert delivery"
	@echo "  monitoring-update-config  - Reload monitoring configurations"
	@echo "  monitoring-check-ports    - Check monitoring port availability"
	@echo "  start-monitoring          - Start monitoring services (alias)"
	@echo "  stop-monitoring           - Stop monitoring services (alias)"
	@echo "  restart-monitoring        - Restart monitoring services (alias)"
	@echo "  status-monitoring         - Show monitoring status (alias)"
	@echo "  verify-monitoring         - Verify monitoring health (alias)"
	@echo "  prometheus-targets        - Show Prometheus targets status"
	@echo "  grafana-dashboards        - List Grafana dashboards"
	@echo "  import-dashboards         - Import Grafana dashboards (alias)"
	@echo "  logs-monitoring           - View monitoring logs (alias)"
	@echo "  health-monitoring         - Quick monitoring health check (alias)"
	@echo ""
	@echo "CPU Optimization targets:"
	@echo "  cpu-diagnose             - Diagnose CPU usage and identify bottlenecks"
	@echo "  cpu-optimize-vscode      - Optimize VS Code CPU usage"
	@echo "  cpu-optimize-system      - Apply system-level CPU optimizations"
	@echo "  cpu-monitor              - Start continuous CPU monitoring"
	@echo "  cpu-optimize-all         - Run complete CPU optimization suite"

# Installation
install:
	pip install -r requirements.txt

install-dev:
	pip install -r requirements-dev.txt
	pre-commit install

# Testing
test:
	python run_tests.py

test-fast:
	python run_tests.py --fast

test-coverage:
	python run_tests.py --coverage

# Code quality
lint:
	mypy src/ python/
	flake8 src/ python/
	bandit -r src/ python/

format:
	black src/ python/
	isort src/ python/

# Cleanup
clean:
	find . -type d -name "__pycache__" -exec rm -rf {} +
	find . -type f -name "*.pyc" -delete
	find . -type f -name "*.pyo" -delete
	rm -rf .pytest_cache
	rm -rf htmlcov
	rm -rf .coverage
	rm -rf .mypy_cache
	rm -rf build/
	rm -rf dist/
	rm -rf *.egg-info/

# Build and run
build:
	@echo "Building MojoRust trading bot..."
	./scripts/build_and_deploy.sh --skip-deploy --skip-docker-build

build-all:
	@echo "Building all components (Rust + Mojo + Docker)..."
	./scripts/build_and_deploy.sh --skip-deploy

build-rust:
	@echo "Building Rust modules..."
	./scripts/build_rust_modules.sh

build-mojo:
	@echo "Building Mojo binary..."
	./scripts/build_mojo_binary.sh

deploy:
	@echo "Building and deploying trading bot..."
	./scripts/build_and_deploy.sh

deploy-docker:
	@echo "Deploying with Docker Compose..."
	docker-compose up -d

run:
	@echo "Running MojoRust trading bot..."
	./target/release/trading-bot --mode=paper --capital=1.0

# Docker
docker-build:
	docker build -t mojorust/trading-bot .

docker-run:
	docker-compose up -d

# Development helpers
dev-setup: install-dev
	@echo "Development environment setup complete!"
	@echo "Run 'source .venv/bin/activate' to activate virtual environment"

# Verification and health checks
verify-build:
	@echo "Verifying build output..."
	@if [ -f target/release/trading-bot ]; then \
		echo "✅ Mojo binary built successfully"; \
	else \
		echo "❌ Mojo binary not found"; \
		exit 1; \
	fi
	@if [ -d rust-modules/target/release ]; then \
		echo "✅ Rust modules built successfully"; \
	else \
		echo "❌ Rust modules not found"; \
		exit 1; \
	fi

verify-deploy:
	@echo "Verifying deployment..."
	@curl -s http://localhost:8082/health > /dev/null && echo "✅ Trading bot healthy" || echo "❌ Trading bot not responding"
	@docker-compose ps | grep -q "Up" && echo "✅ Services running" || echo "❌ Services not running"

clean-all: clean
	@echo "Cleaning all build artifacts..."
	@rm -rf .mojo_cache
	@rm -rf target/
	@rm -rf rust-modules/target/
	@docker system prune -f

check: lint test
	@echo "All checks passed!"

ci: install-dev lint test-coverage
	@echo "CI pipeline completed!"

# =============================================================================
# Monitoring Stack Management
# =============================================================================

# Start monitoring stack
monitoring-start:
	@echo "🚀 Starting monitoring stack..."
	./scripts/start_monitoring_stack.sh
	@echo "✅ Monitoring stack started successfully!"
	@echo "📊 Grafana: http://localhost:3001 (admin/trading_admin)"
	@echo "📈 Prometheus: http://localhost:9090"
	@echo "🚨 AlertManager: http://localhost:9093"

# Stop monitoring stack
monitoring-stop:
	@echo "⏹️  Stopping monitoring stack..."
	docker-compose stop prometheus grafana alertmanager node-exporter
	@echo "✅ Monitoring stack stopped!"

# Restart monitoring stack
monitoring-restart:
	@echo "🔄 Restarting monitoring stack..."
	$(MAKE) monitoring-stop
	sleep 5
	$(MAKE) monitoring-start

# Check monitoring stack status
monitoring-status:
	@echo "📊 Monitoring Stack Status:"
	@echo "=========================="
	docker-compose ps prometheus grafana alertmanager node-exporter
	@echo ""
	@echo "🔗 Service URLs:"
	@echo "Grafana:     http://localhost:3001 (admin/trading_admin)"
	@echo "Prometheus:  http://localhost:9090"
	@echo "AlertManager: http://localhost:9093"
	@echo "Node Exporter: http://localhost:9100/metrics"

# Verify monitoring stack health
monitoring-verify:
	@echo "🔍 Verifying monitoring stack health..."
	./scripts/verify_monitoring_stack.sh
	@echo "✅ Monitoring stack verification completed!"

# Quick health checks
monitoring-health:
	@echo "🏥 Quick Monitoring Health Check:"
	@echo "================================="
	@echo "Checking Prometheus..."
	@curl -s http://localhost:9090/-/healthy > /dev/null && echo "✅ Prometheus: HEALTHY" || echo "❌ Prometheus: UNHEALTHY"
	@echo "Checking Grafana..."
	@curl -s http://localhost:3001/api/health > /dev/null && echo "✅ Grafana: HEALTHY" || echo "❌ Grafana: UNHEALTHY"
	@echo "Checking AlertManager..."
	@curl -s http://localhost:9093/-/healthy > /dev/null && echo "✅ AlertManager: HEALTHY" || echo "❌ AlertManager: UNHEALTHY"
	@echo "Checking Node Exporter..."
	@curl -s http://localhost:9100/metrics | head -1 > /dev/null && echo "✅ Node Exporter: HEALTHY" || echo "❌ Node Exporter: UNHEALTHY"

# Import Grafana dashboards
monitoring-import-dashboards:
	@echo "📊 Importing Grafana dashboards..."
	./scripts/import_grafana_dashboards.sh --force
	@echo "✅ Dashboards imported successfully!"

# Show monitoring service logs
monitoring-logs:
	@echo "📋 Monitoring Service Logs:"
	@echo "=========================="
	@echo "🔍 Select service to view logs:"
	@echo "1) Prometheus"
	@echo "2) Grafana"
	@echo "3) AlertManager"
	@echo "4) Node Exporter"
	@echo "5) All services"
	@read -p "Enter choice (1-5): " choice; \
	case $$choice in \
		1) docker-compose logs -f prometheus ;; \
		2) docker-compose logs -f grafana ;; \
		3) docker-compose logs -f alertmanager ;; \
		4) docker-compose logs -f node-exporter ;; \
		5) docker-compose logs -f prometheus grafana alertmanager node-exporter ;; \
		*) echo "Invalid choice" ;; \
	esac

# Backup monitoring configurations
monitoring-backup:
	@echo "💾 Backing up monitoring configurations..."
	@mkdir -p backups/monitoring
	@docker-compose exec prometheus cat /etc/prometheus/prometheus.yml > backups/monitoring/prometheus_$(shell date +%Y%m%d_%H%M%S).yml
	@docker-compose exec grafana cat /etc/grafana/grafana.ini > backups/monitoring/grafana_$(shell date +%Y%m%d_%H%M%S).ini
	@docker-compose exec alertmanager cat /etc/alertmanager/alertmanager.yml > backups/monitoring/alertmanager_$(shell date +%Y%m%d_%H%M%S).yml
	@tar -czf backups/monitoring/dashboards_$(shell date +%Y%m%d_%H%M%S).tar.gz config/grafana/dashboards/
	@echo "✅ Monitoring configurations backed up to backups/monitoring/"

# Clean monitoring data
monitoring-cleanup:
	@echo "🧹 Cleaning monitoring data..."
	@echo "⚠️  This will remove all monitoring data. Are you sure? [y/N]"
	@read -r confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker-compose stop prometheus grafana alertmanager; \
		docker volume rm trading-bot_prometheus_data trading-bot_grafana_data trading-bot_alertmanager_data 2>/dev/null || true; \
		echo "✅ Monitoring data cleaned. Restart with 'make monitoring-start'"; \
	else \
		echo "❌ Cleanup cancelled"; \
	fi

# Test alert delivery
monitoring-test-alerts:
	@echo "🚨 Testing alert delivery..."
	@curl -XPOST http://localhost:9093/api/v1/alerts \
		-H "Content-Type: application/json" \
		-d '[{"labels":{"alertname":"TestAlert","severity":"warning","instance":"test"},"annotations":{"summary":"Test alert notification","description":"This is a test alert to verify notifications are working"}}]' \
		&& echo "✅ Test alert sent successfully!" || echo "❌ Failed to send test alert"

# Update monitoring configurations
monitoring-update-config:
	@echo "🔄 Updating monitoring configurations..."
	@echo "Reloading Prometheus configuration..."
	@curl -X POST http://localhost:9090/-/reload > /dev/null && echo "✅ Prometheus configuration reloaded!" || echo "❌ Failed to reload Prometheus configuration"
	@echo "Restarting Grafana to apply changes..."
	@docker-compose restart grafana && echo "✅ Grafana restarted!" || echo "❌ Failed to restart Grafana"
	@echo "Restarting AlertManager to apply changes..."
	@docker-compose restart alertmanager && echo "✅ AlertManager restarted!" || echo "❌ Failed to restart AlertManager"

# Check monitoring port availability
monitoring-check-ports:
	@echo "🔍 Checking monitoring port availability..."
	@echo "Checking required ports: 9090, 3001, 9093, 9100"
	@./scripts/verify_port_availability.sh --port 9090 --port 3001 --port 9093 --port 9100
	@echo "✅ Port availability check completed!"

# Complete monitoring health check
monitoring-full-check: monitoring-status monitoring-health monitoring-verify
	@echo ""
	@echo "🎉 Complete monitoring health check finished!"
	@echo "📊 Access dashboards at: http://localhost:3001 (admin/trading_admin)"

# Development monitoring setup (includes monitoring in dev workflow)
dev-with-monitoring: install-dev monitoring-start
	@echo "🚀 Development environment with monitoring ready!"
	@echo "📊 Grafana: http://localhost:3001 (admin/trading_admin)"

# Test with monitoring
test-with-monitoring: monitoring-start test
	@echo "✅ Tests completed with monitoring active!"

# Production deployment with monitoring
deploy-with-monitoring: monitoring-start docker-run
	@echo "🚀 Production deployment with monitoring complete!"
	@echo "📊 Monitor at: http://localhost:3001"

# =============================================================================
# Additional Monitoring Targets (Aliases & Convenience Functions)
# =============================================================================

# Start monitoring services (alias)
start-monitoring: monitoring-start
	@echo "✅ Monitoring services started"

# Stop monitoring services (alias)
stop-monitoring: monitoring-stop
	@echo "⏹️  Monitoring services stopped"

# Restart monitoring services (alias)
restart-monitoring: monitoring-restart
	@echo "🔄 Monitoring services restarted"

# Show monitoring status (alias)
status-monitoring: monitoring-status
	@echo "📊 Monitoring status displayed above"

# Verify monitoring health (alias)
verify-monitoring: monitoring-verify
	@echo "✅ Monitoring verification completed"

# Show Prometheus targets status
prometheus-targets:
	@echo "🎯 Prometheus Targets Status:"
	@echo "=========================="
	@curl -s "$(PROMETHEUS_URL)/api/v1/targets" | jq -r '.data.activeTargets[] | "\(.labels.job): \(.health) (\(.labels.instance // "unknown"))"' || echo "❌ Failed to fetch Prometheus targets"
	@echo ""
	@echo "📊 Prometheus UI: $(PROMETHEUS_URL)/targets"

# List Grafana dashboards
grafana-dashboards:
	@echo "📊 Grafana Dashboards:"
	@echo "===================="
	@curl -s -u admin:trading_admin "$(GRAFANA_URL)/api/search?type=dash-db" | jq -r '.[] | "\(.title): $(GRAFANA_URL)/d/\(.uid)"' || echo "❌ Failed to fetch Grafana dashboards"
	@echo ""
	@echo "📈 Grafana UI: $(GRAFANA_URL)/dashboards"

# Import dashboards (alias)
import-dashboards: monitoring-import-dashboards
	@echo "📊 Dashboards imported successfully"

# View monitoring logs (alias)
logs-monitoring: monitoring-logs
	@echo "📋 Monitoring logs displayed above"

# Quick monitoring health check (alias)
health-monitoring: monitoring-health
	@echo "🏥 Monitoring health check completed"

# =============================================================================
# CPU Optimization Suite
# =============================================================================

# Diagnose CPU usage and identify bottlenecks
cpu-diagnose:
	@echo "🔍 Diagnosing CPU usage and identifying bottlenecks..."
	./scripts/diagnose_cpu_usage.sh --watch
	@echo "✅ CPU diagnostics completed!"

# Optimize VS Code CPU usage
cpu-optimize-vscode:
	@echo "⚡ Optimizing VS Code CPU usage..."
	./scripts/optimize_vscode_cpu.sh --auto
	@echo "✅ VS Code optimization completed!"

# Apply system-level CPU optimizations
cpu-optimize-system:
	@echo "🔧 Applying system-level CPU optimizations..."
	./scripts/apply_system_optimizations.sh --auto
	@echo "✅ System optimization completed!"

# Start continuous CPU monitoring
cpu-monitor:
	@echo "📊 Starting continuous CPU monitoring..."
	./scripts/monitor_cpu_continuous.sh --daemon --threshold 80 --webhook http://localhost:3001/api/webhooks
	@echo "✅ CPU monitoring started in background!"
	@echo "📊 View real-time metrics at: http://localhost:3001"

# Run complete CPU optimization suite
cpu-optimize-all: cpu-diagnose cpu-optimize-vscode cpu-optimize-system cpu-monitor
	@echo ""
	@echo "🎉 Complete CPU optimization suite finished!"
	@echo "📊 System is now optimized for maximum performance"
	@echo "🔍 Monitor CPU usage with: make cpu-diagnose"
	@echo "📊 View monitoring dashboard at: http://localhost:3001"

# Quick CPU health check
cpu-health:
	@echo "🏥 Quick CPU Health Check:"
	@echo "========================="
	@echo "Current CPU usage:"
	@top -bn1 | grep "Cpu(s)" | awk '{print "  CPU Load: " $$2 " (user), " $$4 " (system), " $$8 " (idle)"}'
	@echo "VS Code processes:"
	@ps aux | grep -i "code" | grep -v grep | awk '{sum += $$3} END {if (sum > 0) print "  VS Code CPU: " sum "%"}' || echo "  VS Code CPU: 0%"
	@echo "Docker container CPU usage:"
	@docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}" | grep -v CONTAINER || echo "  No running containers"
	@echo ""

# CPU usage alerting test
cpu-test-alerts:
	@echo "🚨 Testing CPU alerting..."
	@curl -X POST http://localhost:8082/metrics \
		-H "Content-Type: application/json" \
		-d '{"cpu_usage": 95, "memory_usage": 80, "timestamp": "'$$(date -Iseconds)'"}' \
		&& echo "✅ CPU alert test sent!" || echo "❌ Failed to send CPU alert test"

# Stop CPU monitoring
cpu-stop-monitor:
	@echo "⏹️ Stopping CPU monitoring..."
	@pkill -f "monitor_cpu_continuous.sh" && echo "✅ CPU monitoring stopped!" || echo "❌ CPU monitoring not running"

# Generate CPU optimization report
cpu-report:
	@echo "📋 Generating CPU optimization report..."
	@mkdir -p reports
	@./scripts/diagnose_cpu_usage.sh --json > reports/cpu_report_$$(date +%Y%m%d_%H%M%S).json
	@echo "✅ CPU optimization report generated in reports/"
	@echo "📊 View the latest report: reports/cpu_report_$$(date +%Y%m%d_%H%M%S).json"
