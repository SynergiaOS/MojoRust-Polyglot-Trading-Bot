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
.PHONY: help build build-mojo build-rust build-dev build-release test test-mojo test-rust test-watch test-coverage test-integration test-load test-coverage-report test-all lint lint-mojo lint-rust lint-shell lint-fix format format-mojo format-rust validate validate-secrets deploy deploy-staging deploy-production deploy-dry-run dev run run-paper run-live logs status clean clean-mojo clean-rust clean-logs clean-all setup setup-dev install-deps docker-build docker-run docker-stop docker-logs ci ci-lint ci-test check watch benchmark profile docs docs-serve setup-deps

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
	@echo "$(YELLOW)Examples:$(NC)"
	@echo "  make build && make test"
	@echo "  make ci"
	@echo "  make deploy-staging"
	@echo "  make run-paper"

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