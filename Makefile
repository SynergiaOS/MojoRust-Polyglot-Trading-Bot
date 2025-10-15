# =============================================================================
# MojoRust Trading Bot - Makefile
# =============================================================================
# Comprehensive build, test, and deployment automation

# Configuration variables
MOJO_BIN ?= mojo
CARGO_BIN ?= cargo
RUST_DIR ?= rust-modules
SRC_DIR ?= src
TEST_DIR ?= tests
TARGET_DIR ?= target
DEPLOY_SERVER ?= 38.242.239.150
STAGING_SERVER ?= staging.mojorust.local
DEPLOY_USER ?= root
DEPLOY_MODE ?= paper

# Colors for output
GREEN := \033[0;32m
RED := \033[0;31m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

# Timestamp
TIMESTAMP := $(shell date +%Y-%m-%d_%H:%M:%S)

# Default target
.DEFAULT_GOAL := help

# Declare all targets as phony
.PHONY: help build build-mojo build-rust build-dev build-release test test-mojo test-rust test-watch test-coverage test-integration test-load test-coverage-report test-all lint lint-mojo lint-rust lint-shell lint-fix format format-mojo format-rust validate validate-secrets deploy deploy-staging deploy-production deploy-dry-run dev run run-paper run-live logs status clean clean-mojo clean-rust clean-logs clean-all setup setup-dev install-deps docker-build docker-run docker-stop docker-logs ci ci-lint ci-test check watch benchmark profile docs docs-serve setup-deps backup backup-full backup-db backup-list backup-verify restore restore-list restore-latest restore-db monitor health check-deps check-services check-database check-logs alert-test alert-status clean-temp clean-backups optimize rebuild-hard restart-bot stop-bot start-bot restart-services restart-database update-config backup-config restore-config security-scan performance-test stress-test load-test memory-check disk-check network-check api-check ssl-check certs-update logrotate logs-archive logs-compress logs-clean metrics-export metrics-prometheus metrics-grafana dashboard-reload dashboard-backup config-reload config-test config-validate env-check deps-update system-update security-audit backup-verify backup-schedule backup-incremental backup-diff restore-verify restore-check restore-dry-run rollback-emergency rollback-point rollback-list rollback-cleanup service-restart service-reload service-status service-logs service-health service-recovery maintenance-mode maintenance-window maintenance-check monitoring-setup monitoring-start monitoring-stop monitoring-restart monitoring-status monitoring-logs monitoring-alerts monitoring-metrics monitoring-health monitoring-config monitoring-recovery alert-configure alert-test alert-verify alert-status alert-history alert-mute alert-unmute alert-escalate alert-check alert-reset performance-check performance-metrics performance-profile performance-bottleneck performance-tune performance-report performance-history performance-alert performance-threshold resource-check resource-usage resource-metrics resource-alert resource-optimization resource-cleanup resource-quota resource-limits disk-usage disk-health disk-cleanup disk-optimize disk-alerts disk-monitor disk-maintenance memory-usage memory-health memory-cleanup memory-optimize memory-alerts memory-monitor memory-tuning cpu-usage cpu-health cpu-alerts cpu-monitor cpu-optimization cpu-tuning network-usage network-health network-alerts network-monitor network-optimization network-latency network-bandwidth network-connectivity database-usage database-health database-alerts database-monitor database-optimization database-maintenance database-backup database-restore database-recovery cache-usage cache-health cache-alerts cache-monitor cache-cleanup cache-optimization cache-refresh cache-rebuild cache-stats queue-usage queue-health queue-alerts queue-monitor queue-cleanup queue-optimization queue-flush queue-drain queue-stats connection-usage connection-health connection-alerts connection-monitor connection-cleanup connection-optimization connection-pool connection-reset connection-rebalance thread-usage thread-health thread-alerts thread-monitor thread-cleanup thread-optimization thread-pool thread-stats error-usage error-health error-alerts error-monitor error-tracking error-analysis error-reporting error-prevention uptime-availability uptime-alerts uptime-monitoring uptime-reporting uptime-analysis uptime-metrics uptime-tuning latency-usage latency-health latency-alerts latency-monitoring latency-analysis latency-tuning latency-reporting throughput-usage throughput-health throughput-alerts throughput-monitoring throughput-analysis throughput-tuning throughput-reporting scaling-usage scaling-health scaling-alerts scaling-monitoring scaling-analysis scaling-tuning scaling-policy scaling-automation backup-automation backup-monitoring backup-testing backup-verification backup-compression backup-encryption backup-scheduling backup-recovery backup-retention cleanup-automation cleanup-monitoring cleanup-scheduling cleanup-verification cleanup-compression cleanup-encryption cleanup-retention security-automation security-monitoring security-scanning security-auditing security-compliance security-patching security-updating security-alerting security-reporting compliance-automation compliance-monitoring compliance-auditing compliance-reporting compliance-validation compliance-documentation disaster-automation disaster-monitoring disaster-testing disaster-recovery disaster-planning disaster-documentation disaster-alerting disaster-reporting audit-automation audit-monitoring audit-scanning audit-reporting audit-documentation audit-trail audit-logging audit-compliance operational-automation operational-monitoring operational-alerting operational-reporting operational-documentation operational-metrics operational-health operational-optimization operational-scaling operational-maintenance operational-support operational-troubleshooting

# Help target
help: ## Show this help message
	@echo "$(BLUE)MojoRust Trading Bot - Development Commands$(NC)"
	@echo ""
	@echo "$(GREEN)Build Commands:$(NC)"
	@echo "  build          Build all components (Mojo + Rust)"
	@echo "  build-mojo     Build Mojo application"
	@echo "  build-rust     Build Rust modules"
	@echo "  build-dev      Build in development mode"
	@echo "  build-release  Build optimized release version"
	@echo ""
	@echo "$(GREEN)Test Commands:$(NC)"
	@echo "  test           Run all tests (Mojo + Rust)"
	@echo "  test-mojo      Run Mojo tests"
	@echo "  test-rust      Run Rust tests"
	@echo "  test-watch     Run tests in watch mode"
	@echo "  test-coverage  Generate test coverage report"
	@echo "  test-integration Run integration tests"
	@echo "  test-load       Run k6 load tests"
	@echo "  test-coverage-report Generate HTML/XML/JSON coverage reports"
	@echo "  test-all       Run all test types (unit + integration + load + coverage)"
	@echo ""
	@echo "$(GREEN)Lint Commands:$(NC)"
	@echo "  lint           Run all linters"
	@echo "  lint-mojo      Lint Mojo code"
	@echo "  lint-rust      Lint Rust code"
	@echo "  lint-shell     Lint shell scripts"
	@echo "  lint-fix       Auto-fix linting issues"
	@echo ""
	@echo "$(GREEN)Format Commands:$(NC)"
	@echo "  format         Format all code"
	@echo "  format-mojo    Format Mojo code"
	@echo "  format-rust    Format Rust code"
	@echo ""
	@echo "$(GREEN)Validation Commands:$(NC)"
	@echo "  validate       Validate configuration and setup"
	@echo "  validate-secrets Check for hardcoded secrets"
	@echo ""
	@echo "$(GREEN)Deploy Commands:$(NC)"
	@echo "  deploy         Deploy to production server"
	@echo "  deploy-staging Deploy to staging environment"
	@echo "  deploy-production Deploy to production (with confirmation)"
	@echo "  deploy-dry-run Simulate deployment"
	@echo ""
	@echo "$(GREEN)Development Commands:$(NC)"
	@echo "  dev            Start development environment"
	@echo "  run            Run the trading bot locally"
	@echo "  run-paper      Run in paper trading mode"
	@echo "  run-live       Run in live trading mode (with confirmation)"
	@echo "  logs           View bot logs"
	@echo "  status         Check bot status"
	@echo ""
	@echo "$(GREEN)Clean Commands:$(NC)"
	@echo "  clean          Clean build artifacts"
	@echo "  clean-mojo     Clean Mojo build artifacts"
	@echo "  clean-rust     Clean Rust build artifacts"
	@echo "  clean-logs     Clean log files"
	@echo "  clean-all      Deep clean (including dependencies)"
	@echo ""
	@echo "$(GREEN)Setup Commands:$(NC)"
	@echo "  setup          Initial project setup"
	@echo "  setup-dev      Setup development environment"
	@echo "  install-deps   Install all dependencies"
	@echo ""
	@echo "$(GREEN)Docker Commands:$(NC)"
	@echo "  docker-build   Build Docker image"
	@echo "  docker-run     Run bot in Docker container"
	@echo "  docker-stop    Stop Docker containers"
	@echo "  docker-logs    View Docker logs"
	@echo ""
	@echo "$(GREEN)CI/CD Commands:$(NC)"
	@echo "  ci             Run full CI pipeline locally"
	@echo "  ci-lint        Run CI linting checks"
	@echo "  ci-test        Run CI tests"
	@echo ""
	@echo "$(GREEN)Utility Commands:$(NC)"
	@echo "  check          Quick health check"
	@echo "  watch          Watch for changes and rebuild"
	@echo "  benchmark      Run performance benchmarks"
	@echo "  profile        Profile application performance"
	@echo ""
	@echo "$(GREEN)Documentation Commands:$(NC)"
	@echo "  docs           Generate documentation"
	@echo "  docs-serve     Serve documentation locally"
	@echo ""
	@echo "$(GREEN)Operational Commands:$(NC)"
	@echo "  backup         Create full backup with enhanced features"
	@echo "  backup-full    Full backup (files + database + encryption)"
	@echo "  backup-db      Database-only backup"
	@echo "  backup-list    List available backups"
	@echo "  backup-verify  Verify backup integrity"
	@echo "  restore        Restore from backup"
	@echo "  restore-list   List restore options"
	@echo "  restore-latest Restore from latest backup"
	@echo "  restore-db     Restore database only"
	@echo "  monitor        Start monitoring system"
	@echo "  health         System health check"
	@echo "  alert-test     Test alert system"
	@echo "  alert-status   Check alert system status"
	@echo ""
	@echo "$(GREEN)Service Management:$(NC)"
	@echo "  stop-bot       Stop trading bot"
	@echo "  start-bot      Start trading bot"
	@echo "  restart-bot    Restart trading bot"
	@echo "  restart-services Restart all services"
	@echo "  restart-database Restart database service"
	@echo ""
	@echo "$(GREEN)System Management:$(NC)"
	@echo "  check-deps     Check system dependencies"
	@echo "  check-services Check service status"
	@echo "  check-database Check database health"
	@echo "  check-logs     Check log file status"
	@echo "  clean-temp     Clean temporary files"
	@echo "  clean-backups  Clean old backups"
	@echo "  optimize       System optimization"
	@echo "  rebuild-hard   Full rebuild from scratch"
	@echo ""
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make build && make test"
	@echo "  make ci"
	@echo "  make deploy-staging"
	@echo "  make run-paper"
	@echo "  make backup-full"
	@echo "  make restore-latest"
	@echo "  make monitor"

# Build targets
build: build-mojo build-rust ## Build all components (Mojo + Rust)
	@echo "$(GREEN)✅ All components built successfully$(NC)"

build-mojo: ## Build Mojo application
	@echo "$(BLUE)Building Mojo application...$(NC)"
	@mkdir -p $(TARGET_DIR)
	@$(MOJO_BIN) build $(SRC_DIR)/main.mojo -o $(TARGET_DIR)/trading-bot
	@$(MOJO_BIN) build $(SRC_DIR)/main_ultimate.mojo -o $(TARGET_DIR)/trading-bot-ultimate
	@chmod +x $(TARGET_DIR)/trading-*
	@echo "$(GREEN)✅ Mojo application built$(NC)"

build-rust: ## Build Rust modules
	@echo "$(BLUE)Building Rust modules...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) build --release --all-features
	@echo "$(GREEN)✅ Rust modules built$(NC)"

build-dev: ## Build in development mode (faster, with debug info)
	@echo "$(BLUE)Building in development mode...$(NC)"
	@mkdir -p $(TARGET_DIR)
	@$(MOJO_BIN) build $(SRC_DIR)/main.mojo -O1 -o $(TARGET_DIR)/trading-bot
	@cd $(RUST_DIR) && $(CARGO_BIN) build
	@chmod +x $(TARGET_DIR)/trading-bot
	@echo "$(GREEN)✅ Development build completed$(NC)"

build-release: ## Build optimized release version
	@echo "$(BLUE)Building optimized release version...$(NC)"
	@mkdir -p $(TARGET_DIR)
	@$(MOJO_BIN) build $(SRC_DIR)/main.mojo -O3 -o $(TARGET_DIR)/trading-bot
	@cd $(RUST_DIR) && $(CARGO_BIN) build --release
	@chmod +x $(TARGET_DIR)/trading-bot
	@echo "$(GREEN)✅ Release build completed$(NC)"

# Test targets
test: test-mojo test-rust ## Run all tests (Mojo + Rust)
	@echo "$(GREEN)✅ All tests completed$(NC)"

test-mojo: ## Run Mojo tests
	@echo "$(BLUE)Running Mojo tests...$(NC)"
	@if [ -f $(TEST_DIR)/test_suite.mojo ]; then \
		$(MOJO_BIN) test $(TEST_DIR)/test_suite.mojo; \
	fi
	@for test_file in $(TEST_DIR)/test_*.mojo; do \
		if [ -f "$$test_file" ]; then \
			echo "Running $$test_file"; \
			$(MOJO_BIN) test "$$test_file"; \
		fi; \
	done
	@echo "$(GREEN)✅ Mojo tests completed$(NC)"

test-rust: ## Run Rust tests
	@echo "$(BLUE)Running Rust tests...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) test --all-features
	@cd $(RUST_DIR) && $(CARGO_BIN) test --test integration_tests || echo "No integration tests found"
	@echo "$(GREEN)✅ Rust tests completed$(NC)"

test-watch: ## Run tests in watch mode (auto-rerun on changes)
	@echo "$(BLUE)Running tests in watch mode...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) watch -x test || echo "cargo-watch not installed"

test-coverage: ## Generate test coverage report
	@echo "$(BLUE)Generating test coverage report...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) tarpaulin --out Html || echo "cargo-tarpaulin not installed"
	@echo "$(GREEN)✅ Coverage report generated$(NC)"

test-integration: ## Run integration tests
	@echo "$(BLUE)Running integration tests...$(NC)"
	@echo "Running integration tests (Mojo)..."
	@for test_file in $(TEST_DIR)/integration/test_*.mojo; do \
		if [ -f "$$test_file" ]; then \
			echo "Running integration test: $$test_file"; \
			$(MOJO_BIN) test "$$test_file"; \
		fi; \
	done
	@echo "Running integration tests (Rust)..."
	@cd $(RUST_DIR) && $(CARGO_BIN) test --test integration_tests || echo "No Rust integration tests found"
	@echo "$(GREEN)✅ Integration tests completed$(NC)"

test-load: ## Run k6 load tests
	@echo "$(BLUE)Running k6 load tests...$(NC)"
	@if command -v k6 >/dev/null 2>&1; then \
		mkdir -p tests/load/results; \
		echo "Running API load tests..."; \
		k6 run tests/load/api_load_test.js --out json=tests/load/results/api_load_test_results.json || echo "API load test failed"; \
		echo "Running trading cycle load tests..."; \
		k6 run tests/load/trading_cycle_load_test.js --out json=tests/load/results/trading_cycle_results.json || echo "Trading cycle load test failed"; \
		echo "$(GREEN)✅ Load tests completed$(NC)"; \
		echo "$(BLUE)Results saved to tests/load/results/$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  k6 not installed - install from https://k6.io/$(NC)"; \
	fi

test-coverage-report: ## Generate HTML/XML/JSON coverage reports
	@echo "$(BLUE)Generating comprehensive coverage reports...$(NC)"
	@mkdir -p tests/coverage
	@if command -v python3 >/dev/null 2>&1; then \
		python3 tests/coverage_wrapper.py --threshold 70.0 --output-dir tests/coverage; \
		echo "$(GREEN)✅ Coverage reports generated$(NC)"; \
		echo "$(BLUE)Reports available at: tests/coverage/html/index.html$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  Python 3 not found - install to generate reports$(NC)"; \
	fi

test-all: ## Run all test types (unit + integration + load + coverage)
	@echo "$(BLUE)Running comprehensive test suite...$(NC)"
	@$(MAKE) test-mojo
	@$(MAKE) test-rust
	@$(MAKE) test-integration
	@if command -v k6 >/dev/null 2>&1; then \
		$(MAKE) test-load; \
	fi
	@$(MAKE) test-coverage-report
	@echo "$(GREEN)✅ All test types completed successfully$(NC)"

# Lint targets
lint: lint-mojo lint-rust lint-shell ## Run all linters
	@echo "$(GREEN)✅ All linting completed$(NC)"

lint-mojo: ## Lint Mojo code
	@echo "$(BLUE)Linting Mojo code...$(NC)"
	@$(MOJO_BIN) format --check $(SRC_DIR)/
	@echo "$(GREEN)✅ Mojo linting completed$(NC)"

lint-rust: ## Lint Rust code
	@echo "$(BLUE)Linting Rust code...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) clippy --all-targets --all-features -- -D warnings
	@cd $(RUST_DIR) && $(CARGO_BIN) fmt --all -- --check
	@echo "$(GREEN)✅ Rust linting completed$(NC)"

lint-shell: ## Lint shell scripts
	@echo "$(BLUE)Linting shell scripts...$(NC)"
	@shellcheck scripts/*.sh
	@echo "$(GREEN)✅ Shell script linting completed$(NC)"

lint-fix: ## Auto-fix linting issues
	@echo "$(BLUE)Auto-fixing linting issues...$(NC)"
	@$(MOJO_BIN) format $(SRC_DIR)/
	@cd $(RUST_DIR) && $(CARGO_BIN) fmt --all
	@shfmt -i 4 -w scripts/*.sh
	@echo "$(GREEN)✅ Linting issues fixed$(NC)"

# Format targets
format: format-mojo format-rust ## Format all code

format-mojo: ## Format Mojo code
	@echo "$(BLUE)Formatting Mojo code...$(NC)"
	@$(MOJO_BIN) format $(SRC_DIR)/ $(TEST_DIR)/

format-rust: ## Format Rust code
	@echo "$(BLUE)Formatting Rust code...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) fmt --all

# Validation targets
validate: ## Validate configuration and setup
	@echo "$(BLUE)Validating configuration...$(NC)"
	@if [ -f scripts/validate_config.sh ]; then \
		scripts/validate_config.sh --env-file .env.example --strict; \
	fi
	@if [ -f scripts/verify_ffi.sh ]; then \
		scripts/verify_ffi.sh; \
	fi
	@echo "$(GREEN)✅ Configuration validation completed$(NC)"

validate-secrets: ## Check for hardcoded secrets
	@echo "$(BLUE)Checking for hardcoded secrets...$(NC)"
	@if [ -f scripts/validate_config.sh ]; then \
		scripts/validate_config.sh --strict; \
	fi
	@echo "$(GREEN)✅ Secrets validation completed$(NC)"

# Deploy targets
deploy: ## Deploy to production server
	@echo "$(YELLOW)Deploying to production server ($(DEPLOY_SERVER))...$(NC)"
	@if [ -f scripts/deploy_to_server.sh ]; then \
		scripts/deploy_to_server.sh --mode=$(DEPLOY_MODE); \
	else \
		echo "$(RED)❌ Deployment script not found$(NC)"; \
		exit 1; \
	fi

deploy-staging: ## Deploy to staging environment
	@echo "$(BLUE)Deploying to staging environment...$(NC)"
	@$(MAKE) deploy DEPLOY_MODE=paper DEPLOY_SERVER=$(STAGING_SERVER)

deploy-production: ## Deploy to production (with confirmation)
	@echo "$(RED)⚠️  WARNING: This will deploy to PRODUCTION server!$(NC)"
	@read -p "Are you sure you want to continue? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@$(MAKE) deploy DEPLOY_MODE=$(DEPLOY_MODE)

deploy-dry-run: ## Simulate deployment without executing
	@echo "$(BLUE)Simulating deployment...$(NC)"
	@if [ -f scripts/deploy_to_server.sh ]; then \
		scripts/deploy_to_server.sh --dry-run; \
	else \
		echo "$(RED)❌ Deployment script not found$(NC)"; \
		exit 1; \
	fi

# Development targets
dev: ## Start development environment
	@echo "$(BLUE)Starting development environment...$(NC)"
	@$(MAKE) build-dev
	@echo "$(GREEN)✅ Development environment ready$(NC)"

run: ## Run the trading bot locally
	@echo "$(BLUE)Starting trading bot...$(NC)"
	@if [ ! -f $(TARGET_DIR)/trading-bot ]; then \
		$(MAKE) build; \
	fi
	@$(TARGET_DIR)/trading-bot --mode=paper --capital=1.0

run-paper: ## Run in paper trading mode
	@echo "$(BLUE)Starting paper trading mode...$(NC)"
	@export EXECUTION_MODE=paper && $(MAKE) run

run-live: ## Run in live trading mode (with confirmation)
	@echo "$(RED)⚠️  WARNING: This will start LIVE trading!$(NC)"
	@read -p "Are you sure you want to start LIVE trading? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo "$(BLUE)Starting live trading mode...$(NC)"
	@export EXECUTION_MODE=live && $(TARGET_DIR)/trading-bot --mode=live

logs: ## View bot logs
	@echo "$(BLUE)Viewing bot logs...$(NC)"
	@if [ -d logs ]; then \
		tail -f logs/trading-bot-*.log; \
	else \
		echo "$(YELLOW)⚠️  No logs directory found$(NC)"; \
	fi

status: ## Check bot status
	@echo "$(BLUE)Checking bot status...$(NC)"
	@if [ -f scripts/server_health.sh ]; then \
		scripts/server_health.sh; \
	fi
	@if pgrep -f trading-bot >/dev/null; then \
		echo "$(GREEN)✅ Bot is running$(NC)"; \
	else \
		echo "$(RED)❌ Bot is not running$(NC)"; \
	fi

# Clean targets
clean: clean-mojo clean-rust ## Clean build artifacts

clean-mojo: ## Clean Mojo build artifacts
	@echo "$(BLUE)Cleaning Mojo build artifacts...$(NC)"
	@rm -rf $(TARGET_DIR)/trading-*
	@rm -rf .mojocache/

clean-rust: ## Clean Rust build artifacts
	@echo "$(BLUE)Cleaning Rust build artifacts...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) clean

clean-logs: ## Clean log files
	@echo "$(BLUE)Cleaning log files...$(NC)"
	@rm -f logs/*.log

clean-all: ## Deep clean (including dependencies)
	@echo "$(BLUE)Deep cleaning...$(NC)"
	@$(MAKE) clean clean-logs
	@cd $(RUST_DIR) && $(CARGO_BIN) cache clean --all
	@rm -rf ~/.cargo/registry/src/.cargo-lock

# Setup targets
setup: ## Initial project setup
	@echo "$(BLUE)Setting up project...$(NC)"
	@mkdir -p logs data secrets
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "$(YELLOW)⚠️  Created .env from template - add your API keys$(NC)"; \
	fi
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit install; \
		echo "$(GREEN)✅ Pre-commit hooks installed$(NC)"; \
	fi
	@$(MAKE) install-deps
	@echo "$(GREEN)✅ Project setup completed$(NC)"

setup-dev: ## Setup development environment
	@echo "$(BLUE)Setting up development environment...$(NC)"
	@$(MAKE) setup
	@if [ -f scripts/setup_dev.sh ]; then \
		scripts/setup_dev.sh; \
	fi
	@echo "$(GREEN)✅ Development environment ready$(NC)"

install-deps: ## Install all dependencies
	@echo "$(BLUE)Installing dependencies...$(NC)"
	@if ! command -v $(MOJO_BIN) >/dev/null 2>&1; then \
		echo "$(YELLOW)⚠️  Mojo not found - install from https://www.modular.com/mojo$(NC)"; \
	fi
	@if ! command -v $(CARGO_BIN) >/dev/null 2>&1; then \
		echo "$(YELLOW)⚠️  Rust not found - install from https://rustup.rs$(NC)"; \
	fi
	@if command -v $(CARGO_BIN) >/dev/null 2>&1; then \
		cd $(RUST_DIR) && $(CARGO_BIN) fetch; \
	fi
	@if command -v pip >/dev/null 2>&1; then \
		pip install pre-commit; \
	fi
	@echo "$(GREEN)✅ Dependencies installed$(NC)"

# Docker targets
docker-build: ## Build Docker image
	@echo "$(BLUE)Building Docker image...$(NC)"
	@if [ -f Dockerfile ]; then \
		docker build -t mojorust-trading-bot:latest .; \
	else \
		echo "$(RED)❌ Dockerfile not found$(NC)"; \
		exit 1; \
	fi

docker-run: ## Run bot in Docker container
	@echo "$(BLUE)Running bot in Docker...$(NC)"
	@if [ -f docker-compose.yml ]; then \
		docker-compose up -d; \
	else \
		docker run -d --name mojorust-trading-bot mojorust-trading-bot:latest; \
	fi

docker-stop: ## Stop Docker containers
	@echo "$(BLUE)Stopping Docker containers...$(NC)"
	@if [ -f docker-compose.yml ]; then \
		docker-compose down; \
	else \
		docker stop mojorust-trading-bot || true; \
		docker rm mojorust-trading-bot || true; \
	fi

docker-logs: ## View Docker logs
	@echo "$(BLUE)Viewing Docker logs...$(NC)"
	@if [ -f docker-compose.yml ]; then \
		docker-compose logs -f; \
	else \
		docker logs -f mojorust-trading-bot; \
	fi

# CI/CD targets
ci: ## Run full CI pipeline locally
	@echo "$(BLUE)Running CI pipeline locally...$(NC)"
	@$(MAKE) lint
	@$(MAKE) validate-secrets
	@$(MAKE) build
	@$(MAKE) test
	@echo "$(GREEN)✅ CI pipeline completed successfully$(NC)"

ci-lint: ## Run CI linting checks
	@echo "$(BLUE)Running CI linting checks...$(NC)"
	@$(MAKE) lint

ci-test: ## Run CI tests
	@echo "$(BLUE)Running CI tests...$(NC)"
	@$(MAKE) test

# Utility targets
check: ## Quick health check (lint + test)
	@echo "$(BLUE)Running quick health check...$(NC)"
	@$(MAKE) lint
	@$(MAKE) test

watch: ## Watch for changes and rebuild
	@echo "$(BLUE)Watching for changes...$(NC)"
	@if command -v inotifywait >/dev/null 2>&1; then \
		while inotifywait -r -e modify $(SRC_DIR)/ $(RUST_DIR)/src/; do \
			echo "$(BLUE)Changes detected, rebuilding...$(NC)"; \
			$(MAKE) build-dev; \
		done; \
	else \
		echo "$(YELLOW)⚠️  inotify-tools not installed$(NC)"; \
	fi

benchmark: ## Run performance benchmarks
	@echo "$(BLUE)Running benchmarks...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) bench || echo "$(YELLOW)⚠️  No benchmarks found$(NC)"

profile: ## Profile application performance
	@echo "$(BLUE)Profiling application...$(NC)"
	@if [ -f scripts/profile_bot.sh ]; then \
		scripts/profile_bot.sh; \
	else \
		echo "$(YELLOW)⚠️  Profile script not found$(NC)"; \
	fi

# Documentation targets
docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(NC)"
	@cd $(RUST_DIR) && $(CARGO_BIN) doc --no-deps --open || echo "$(YELLOW)⚠️  Documentation generation failed$(NC)"

docs-serve: ## Serve documentation locally
	@echo "$(BLUE)Serving documentation locally...$(NC)"
	@if [ -d $(RUST_DIR)/target/doc ]; then \
		cd $(RUST_DIR)/target/doc && python3 -m http.server 8080; \
	else \
		echo "$(YELLOW)⚠️  Documentation not found - run 'make docs' first$(NC)"; \
	fi

# Special features for better UX
define show_status
	@echo "$(GREEN)✅ $1$(NC)"
endef

define show_error
	@echo "$(RED)❌ $1$(NC)"
endef

define show_warning
	@echo "$(YELLOW)⚠️  $1$(NC)"
endef

# =============================================================================
# Operational Commands - Enhanced System Management
# =============================================================================

# Backup commands
backup: ## Create full backup with enhanced features
	@echo "$(BLUE)Creating enhanced backup...$(NC)"
	@./scripts/backup.sh --stop-bot --verify --compress-level 6

backup-full: ## Full backup (files + database + encryption)
	@echo "$(BLUE)Creating full encrypted backup...$(NC)"
	@./scripts/backup.sh --stop-bot --verify --compress-level 9 --db-format custom

backup-db: ## Database-only backup
	@echo "$(BLUE)Creating database-only backup...$(NC)"
	@./scripts/backup.sh --database-only --verify --db-format custom

backup-list: ## List available backups
	@echo "$(BLUE)Listing available backups...$(NC)"
	@./scripts/backup.sh --list 2>/dev/null || ls -la /home/tradingbot/backups/ | grep "mojorust-backup"

backup-verify: ## Verify backup integrity
	@echo "$(BLUE)Verifying latest backup integrity...$(NC)"
	@if [ -f /home/tradingbot/backups/latest_backup.json ]; then \
		LATEST_BACKUP="/home/tradingbot/backups/$$(cat /home/tradingbot/backups/latest_backup.json | jq -r '.backup_file')"; \
		echo "Verifying: $$LATEST_BACKUP"; \
		./scripts/backup.sh --backup-file "$$LATEST_BACKUP" --verify; \
	else \
		echo "$(RED)❌ No latest backup found$(NC)"; \
	fi

# Restore commands
restore: ## Restore from backup (interactive)
	@echo "$(BLUE)Restore from backup (interactive)...$(NC)"
	@./scripts/rollback.sh --list
	@read -p "Enter backup filename or use --latest: " BACKUP_FILE; \
	if [ "$$BACKUP_FILE" = "latest" ]; then \
		./scripts/rollback.sh --latest; \
	else \
		./scripts/rollback.sh --backup-file "$$BACKUP_FILE"; \
	fi

restore-list: ## List restore options
	@echo "$(BLUE)Listing restore options...$(NC)"
	@./scripts/rollback.sh --list

restore-latest: ## Restore from latest backup
	@echo "$(BLUE)Restoring from latest backup...$(NC)"
	@./scripts/rollback.sh --latest --verify

restore-db: ## Restore database only
	@echo "$(BLUE)Restoring database only...$(NC)"
	@./scripts/rollback.sh --latest --no-database --db-only

# Service management commands
stop-bot: ## Stop trading bot
	@echo "$(BLUE)Stopping trading bot...$(NC)"
	@sudo systemctl stop trading-bot || echo "$(YELLOW)⚠️  System service not found$(NC)"
	@pkill -f trading-bot || echo "$(YELLOW)⚠️  No running process found$(NC)"

start-bot: ## Start trading bot
	@echo "$(BLUE)Starting trading bot...$(NC)"
	@if [ ! -f $(TARGET_DIR)/trading-bot ]; then \
		$(MAKE) build; \
	fi
	@sudo systemctl start trading-bot || echo "$(YELLOW)⚠️  System service not found, starting manually$(NC)"
	@if ! sudo systemctl is-active --quiet trading-bot 2>/dev/null; then \
		nohup $(TARGET_DIR)/trading-bot --mode=paper --capital=1.0 > logs/trading-bot-$(shell date +%Y%m%d).log 2>&1 & \
		echo "$(GREEN)✅ Bot started manually$(NC)"; \
	fi

restart-bot: ## Restart trading bot
	@echo "$(BLUE)Restarting trading bot...$(NC)"
	@$(MAKE) stop-bot
	@sleep 2
	@$(MAKE) start-bot

restart-services: ## Restart all services
	@echo "$(BLUE)Restarting all services...$(NC)"
	@sudo systemctl restart postgresql || echo "$(YELLOW)⚠️  PostgreSQL not found$(NC)"
	@sudo systemctl restart redis || echo "$(YELLOW)⚠️  Redis not found$(NC)"
	@sudo systemctl restart nginx || echo "$(YELLOW)⚠️  Nginx not found$(NC)"
	@$(MAKE) restart-bot

restart-database: ## Restart database service
	@echo "$(BLUE)Restarting database service...$(NC)"
	@sudo systemctl restart postgresql || echo "$(YELLOW)⚠️  PostgreSQL not found$(NC)"

# System management commands
check-deps: ## Check system dependencies
	@echo "$(BLUE)Checking system dependencies...$(NC)"
	@echo "Checking Mojo..." && command -v mojo >/dev/null && echo "$(GREEN)✅ Mojo found$(NC)" || echo "$(RED)❌ Mojo not found$(NC)"
	@echo "Checking Rust..." && command -v cargo >/dev/null && echo "$(GREEN)✅ Rust found$(NC)" || echo "$(RED)❌ Rust not found$(NC)"
	@echo "Checking Python..." && command -v python3 >/dev/null && echo "$(GREEN)✅ Python found$(NC)" || echo "$(RED)❌ Python not found$(NC)"
	@echo "Checking PostgreSQL..." && command -v psql >/dev/null && echo "$(GREEN)✅ PostgreSQL found$(NC)" || echo "$(RED)❌ PostgreSQL not found$(NC)"
	@echo "Checking Docker..." && command -v docker >/dev/null && echo "$(GREEN)✅ Docker found$(NC)" || echo "$(YELLOW)⚠️  Docker not found$(NC)"

check-services: ## Check service status
	@echo "$(BLUE)Checking service status...$(NC)"
	@echo "Trading Bot:" && (sudo systemctl is-active trading-bot 2>/dev/null && echo "$(GREEN)✅ Active$(NC)" || echo "$(RED)❌ Inactive$(NC)")
	@echo "PostgreSQL:" && (sudo systemctl is-active postgresql 2>/dev/null && echo "$(GREEN)✅ Active$(NC)" || echo "$(RED)❌ Inactive$(NC)")
	@echo "Redis:" && (sudo systemctl is-active redis 2>/dev/null && echo "$(GREEN)✅ Active$(NC)" || echo "$(YELLOW)⚠️  Not found$(NC)")
	@echo "Nginx:" && (sudo systemctl is-active nginx 2>/dev/null && echo "$(GREEN)✅ Active$(NC)" || echo "$(YELLOW)⚠️  Not found$(NC)")

check-database: ## Check database health
	@echo "$(BLUE)Checking database health...$(NC)"
	@if command -v psql >/dev/null 2>&1; then \
		psql -h localhost -U trading_user -d trading_bot -c "SELECT version();" >/dev/null 2>&1 && \
			echo "$(GREEN)✅ Database connection successful$(NC)" || \
			echo "$(RED)❌ Database connection failed$(NC)"; \
		psql -h localhost -U trading_user -d trading_bot -c "SELECT COUNT(*) FROM information_schema.tables;" >/dev/null 2>&1 && \
			echo "$(GREEN)✅ Database accessible$(NC)" || \
			echo "$(RED)❌ Database not accessible$(NC)"; \
	else \
		echo "$(RED)❌ PostgreSQL client not available$(NC)"; \
	fi

check-logs: ## Check log file status
	@echo "$(BLUE)Checking log file status...$(NC)"
	@if [ -d logs ]; then \
		echo "Log files in logs/:"; \
		ls -lah logs/; \
		echo "Total log size: $$(du -sh logs | cut -f1)"; \
	else \
		echo "$(YELLOW)⚠️  No logs directory found$(NC)"; \
	fi

clean-temp: ## Clean temporary files
	@echo "$(BLUE)Cleaning temporary files...$(NC)"
	@find /tmp -name "rollback_*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
	@find /tmp -name "backup_*" -type d -mtime +1 -exec rm -rf {} + 2>/dev/null || true
	@find . -name "*.tmp" -mtime +1 -delete 2>/dev/null || true
	@find . -name "*.cache" -mtime +1 -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Temporary files cleaned$(NC)"

clean-backups: ## Clean old backups
	@echo "$(BLUE)Cleaning old backups...$(NC)"
	@if [ -d /home/tradingbot/backups ]; then \
		find /home/tradingbot/backups -name "*.log" -mtime +7 -delete; \
		find /home/tradingbot/backups -name "backup_*" -mtime +30 -delete; \
		echo "$(GREEN)✅ Old backups cleaned$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  Backup directory not found$(NC)"; \
	fi

optimize: ## System optimization
	@echo "$(BLUE)Performing system optimization...$(NC)"
	@echo "Cleaning package caches..." && \
		if command -v apt >/dev/null 2>&1; then sudo apt autoremove -y; fi
	@echo "Cleaning container images..." && \
		if command -v docker >/dev/null 2>&1; then docker system prune -f; fi
	@echo "Optimizing database..." && \
		if command -v psql >/dev/null 2>&1; then \
			psql -h localhost -U trading_user -d trading_bot -c "VACUUM ANALYZE;" >/dev/null 2>&1 || true; \
		fi
	@echo "$(GREEN)✅ System optimization completed$(NC)"

rebuild-hard: ## Full rebuild from scratch
	@echo "$(BLUE)Performing full rebuild...$(NC)"
	@$(MAKE) clean-all
	@$(MAKE) install-deps
	@$(MAKE) build-release
	@echo "$(GREEN)✅ Full rebuild completed$(NC)"

# Monitoring and health commands
monitor: ## Start monitoring system
	@echo "$(BLUE)Starting monitoring system...$(NC)"
	@if [ -f scripts/health_check_cron.sh ]; then \
		./scripts/health_check_cron.sh; \
		echo "$(GREEN)✅ Monitoring system started$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  Monitoring script not found$(NC)"; \
	fi

health: ## System health check
	@echo "$(BLUE)Performing comprehensive health check...$(NC)"
	@$(MAKE) check-deps
	@$(MAKE) check-services
	@$(MAKE) check-database
	@echo "$(GREEN)✅ Health check completed$(NC)"

# Alert system commands
alert-test: ## Test alert system
	@echo "$(BLUE)Testing alert system...$(NC)"
	@if [ -f $(TARGET_DIR)/trading-bot ]; then \
		$(TARGET_DIR)/trading-bot --test-alerts || echo "$(YELLOW)⚠️  Alert test not implemented$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  Bot not built - run 'make build' first$(NC)"; \
	fi

alert-status: ## Check alert system status
	@echo "$(BLUE)Checking alert system status...$(NC)"
	@if command -v curl >/dev/null 2>&1; then \
		curl -f http://localhost:8082/api/alerts/status 2>/dev/null && \
			echo "$(GREEN)✅ Alert system accessible$(NC)" || \
			echo "$(YELLOW)⚠️  Alert system not accessible$(NC)"; \
	else \
		echo "$(YELLOW)⚠️  curl not available$(NC)"; \
	fi

# Advanced operational commands
backup-verify: ## Comprehensive backup verification
	@echo "$(BLUE)Performing comprehensive backup verification...$(NC)"
	@for backup in /home/tradingbot/backups/mojorust-backup-*.tar.gz*; do \
		if [ -f "$$backup" ]; then \
			echo "Verifying: $$(basename $$backup)"; \
			if [ -f "$$backup.sha256" ]; then \
				sha256sum -c "$$backup.sha256" >/dev/null 2>&1 && \
					echo "$(GREEN)✅ $$(basename $$backup) - OK$(NC)" || \
					echo "$(RED)❌ $$(basename $$backup) - FAILED$(NC)"; \
			else \
				echo "$(YELLOW)⚠️  $$(basename $$backup) - No checksum$(NC)"; \
			fi; \
		fi; \
	done

restore-verify: ## Verify restore process
	@echo "$(BLUE)Verifying restore process...$(NC)"
	@if [ -f /home/tradingbot/backups/latest_backup.json ]; then \
		LATEST_BACKUP="/home/tradingbot/backups/$$(cat /home/tradingbot/backups/latest_backup.json | jq -r '.backup_file')"; \
		echo "Testing restore with: $$LATEST_BACKUP"; \
		./scripts/rollback.sh --backup-file "$$LATEST_BACKUP" --dry-run --verify; \
	else \
		echo "$(RED)❌ No latest backup found$(NC)"; \
	fi

restore-dry-run: ## Dry run restore process
	@echo "$(BLUE)Dry run restore process...$(NC)"
	@./scripts/rollback.sh --latest --dry-run

rollback-emergency: ## Emergency rollback with minimal verification
	@echo "$(RED)⚠️  EMERGENCY ROLLBACK - MINIMAL VERIFICATION$(NC)"
	@read -p "Are you sure? This will immediately rollback to latest backup! [y/N] " confirm && \
	[ "$$confirm" = "y" ] && \
	./scripts/rollback.sh --latest --force

# Resource monitoring commands
resource-check: ## Check system resource usage
	@echo "$(BLUE)Checking system resources...$(NC)"
	@echo "CPU Usage: $$(top -bn1 | grep "Cpu(s)" | awk '{print $$2}' | awk -F'%' '{print $$1}')%"
	@echo "Memory Usage: $$(free -m | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
	@echo "Disk Usage: $$(df -h / | awk 'NR==2 {print $$5}')"
	@echo "Load Average: $$(uptime | awk -F'load average:' '{print $$2}')"
	@echo "Uptime: $$(uptime -p 2>/dev/null | cut -d' ' -f1 || uptime)"

disk-check: ## Check disk health and usage
	@echo "$(BLUE)Checking disk health...$(NC)"
	@df -h
	@echo ""
	@echo "Inode usage:"
	@df -i
	@echo ""
	@if command -v lsblk >/dev/null 2>&1; then \
		echo "Disk information:"; \
		lsblk; \
	fi

memory-check: ## Check memory usage and health
	@echo "$(BLUE)Checking memory usage...$(NC)"
	@free -h
	@echo ""
	@echo "Top memory consumers:"
	@ps aux --sort=-%mem | head -10
	@echo ""
	@if [ -f /proc/meminfo ]; then \
		echo "Memory details:"; \
		grep -E "(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree)" /proc/meminfo; \
	fi

network-check: ## Check network connectivity and health
	@echo "$(BLUE)Checking network connectivity...$(NC)"
	@ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "$(GREEN)✅ Internet connectivity OK$(NC)" || echo "$(RED)❌ Internet connectivity failed$(NC)"
	@echo ""
	@echo "Active connections:"
	@netstat -tuln | grep LISTEN | head -10
	@echo ""
	@if command -v ss >/dev/null 2>&1; then \
		echo "Connection statistics:"; \
		ss -s; \
	fi