# MojoRust Trading Bot Makefile

.PHONY: help install install-dev test test-fast test-coverage lint format clean build run docker-build docker-run

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
	# Add build commands here

run:
	@echo "Running MojoRust trading bot..."
	python src/main.mojo

# Docker
docker-build:
	docker build -t mojorust/trading-bot .

docker-run:
	docker-compose up -d

# Development helpers
dev-setup: install-dev
	@echo "Development environment setup complete!"
	@echo "Run 'source .venv/bin/activate' to activate virtual environment"

check: lint test
	@echo "All checks passed!"

ci: install-dev lint test-coverage
	@echo "CI pipeline completed!"
