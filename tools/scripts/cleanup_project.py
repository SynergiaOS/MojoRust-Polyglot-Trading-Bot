#!/usr/bin/env python3
"""
Project cleanup and organization script
"""

import os
import shutil
import sys
from pathlib import Path
from typing import List, Dict


def create_directory_structure():
    """Create organized directory structure"""
    directories = [
        "python",
        "python/utils",
        "python/integrations",
        "python/web",
        "docs/api",
        "docs/architecture",
        "docs/tutorials",
        "scripts/deployment",
        "scripts/development",
        "tests/unit",
        "tests/integration",
        "tests/performance",
        "config/environments",
        "config/monitoring",
        "logs",
        "data/backups",
        "data/cache",
        "artifacts"
    ]

    base_path = Path(".")
    for directory in directories:
        dir_path = base_path / directory
        dir_path.mkdir(parents=True, exist_ok=True)
        print(f"Created directory: {dir_path}")


def move_files_to_correct_locations():
    """Move misplaced files to correct locations"""
    file_moves = {
        # Move Python files to python directory
        "src/monitoring/health_api.py": "python/health_api.py",

        # Move test files to tests directory
        "test_rpc_router.py": "tests/test_rpc_router.py",
        "test_dto_contracts.py": "tests/test_dto_contracts.py",
        "test_task_pool_manager.py": "tests/test_task_pool_manager.py",

        # Move documentation
        "FREE_DATA_SOURCES_GUIDE.md": "docs/FREE_DATA_SOURCES_GUIDE.md",
        "IMPLEMENTATION_ROADMAP.md": "docs/IMPLEMENTATION_ROADMAP.md"
    }

    base_path = Path(".")
    for src, dst in file_moves.items():
        src_path = base_path / src
        dst_path = base_path / dst

        if src_path.exists():
            # Create destination directory if needed
            dst_path.parent.mkdir(parents=True, exist_ok=True)

            # Move file
            shutil.move(str(src_path), str(dst_path))
            print(f"Moved: {src} -> {dst}")
        else:
            print(f"Source file not found: {src}")


def create_gitignore_entries():
    """Add entries to .gitignore if not present"""
    gitignore_path = Path(".gitignore")

    entries_to_add = [
        "# Python",
        "__pycache__/",
        "*.py[cod]",
        "*$py.class",
        ".python-version",
        "pip-log.txt",
        "pip-delete-this-directory.txt",
        ".venv",
        "env/",
        "venv/",
        "ENV/",
        "env.bak/",
        "venv.bak/",

        "# Mojo",
        "*.mojo_cache",
        ".mojo/",

        "# Logs",
        "logs/",
        "*.log",

        # Data and cache
        "data/cache/",
        "data/backups/",
        ".cache/",

        # Test artifacts
        "htmlcov/",
        ".coverage",
        ".pytest_cache/",
        "coverage.xml",

        # IDE
        ".vscode/",
        ".idea/",
        "*.swp",
        "*.swo",

        # OS
        ".DS_Store",
        "Thumbs.db",

        # Environment files
        ".env.local",
        ".env.production",
        "config/local/",
    ]

    existing_content = ""
    if gitignore_path.exists():
        existing_content = gitignore_path.read_text()

    new_entries = []
    for entry in entries_to_add:
        if entry not in existing_content:
            new_entries.append(entry)

    if new_entries:
        with open(gitignore_path, "a") as f:
            f.write("\n# Auto-generated entries\n")
            f.write("\n".join(new_entries) + "\n")
        print(f"Added {len(new_entries)} entries to .gitignore")


def create_development_environment_files():
    """Create development environment configuration files"""

    # Create requirements files
    requirements = [
        "# Core dependencies",
        "pytest>=7.0.0",
        "pytest-asyncio>=0.21.0",
        "pytest-mock>=3.10.0",
        "pytest-cov>=4.0.0",
        "pytest-xdist>=3.0.0",
        "",
        "# Development tools",
        "black>=23.0.0",
        "isort>=5.12.0",
        "mypy>=1.0.0",
        "flake8>=6.0.0",
        "pre-commit>=3.0.0",
        "",
        "# Data processing",
        "pandas>=2.0.0",
        "numpy>=1.24.0",
        "asyncio-mqtt>=0.13.0",
        "aioredis>=2.0.0",
        "",
        "# API clients",
        "aiohttp>=3.8.0",
        "websockets>=11.0.0",
        "",
        "# Monitoring",
        "prometheus-client>=0.16.0",
        "structlog>=23.0.0",
        "",
        "# Configuration",
        "python-dotenv>=1.0.0",
        "pydantic>=2.0.0",
        "toml>=0.10.0"
    ]

    requirements_path = Path("requirements.txt")
    requirements_path.write_text("\n".join(requirements))
    print(f"Created: {requirements_path}")

    # Create requirements-dev.txt
    dev_requirements = [
        "# Development and testing",
        "pytest>=7.0.0",
        "pytest-asyncio>=0.21.0",
        "pytest-mock>=3.10.0",
        "pytest-cov>=4.0.0",
        "pytest-xdist>=3.0.0",
        "",
        "# Code quality",
        "black>=23.0.0",
        "isort>=5.12.0",
        "mypy>=1.0.0",
        "flake8>=6.0.0",
        "bandit>=1.7.0",
        "",
        "# Pre-commit hooks",
        "pre-commit>=3.0.0",
        "",
        "# Documentation",
        "sphinx>=6.0.0",
        "sphinx-rtd-theme>=1.2.0",
        "",
        "# Performance profiling",
        "memory-profiler>=0.61.0",
        "py-spy>=0.3.0"
    ]

    dev_requirements_path = Path("requirements-dev.txt")
    dev_requirements_path.write_text("\n".join(dev_requirements))
    print(f"Created: {dev_requirements_path}")


def create_makefile():
    """Create a comprehensive Makefile"""
    makefile_content = """# MojoRust Trading Bot Makefile

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
"""

    makefile_path = Path("Makefile")
    makefile_path.write_text(makefile_content)
    print(f"Created: {makefile_path}")


def update_imports_for_moved_files():
    """Update import statements in affected files"""
    updates = {
        # Update main.mojo imports
        "src/main.mojo": [
            ("from python.social_intelligence_engine import SocialIntelligenceEngine",
             "from python import SocialIntelligenceEngine"),
            ("from python.geyser_client import ProductionGeyserClient",
             "from python import ProductionGeyserClient")
        ]
    }

    base_path = Path(".")
    for file_path, import_updates in updates.items():
        full_path = base_path / file_path
        if full_path.exists():
            content = full_path.read_text()
            modified = False

            for old_import, new_import in import_updates:
                if old_import in content:
                    content = content.replace(old_import, new_import)
                    modified = True

            if modified:
                full_path.write_text(content)
                print(f"Updated imports in: {file_path}")


def create_readme_update():
    """Update README with project structure information"""
    readme_path = Path("README.md")
    if readme_path.exists():
        content = readme_path.read_text()

        structure_section = """
## Project Structure

```
MojoRust/
├── src/                    # Main source code (Mojo)
│   ├── core/              # Core functionality
│   ├── data/              # Data layer (Mojo + typed DTOs)
│   ├── engine/            # Trading engines
│   ├── risk/              # Risk management
│   ├── monitoring/        # Monitoring & alerting
│   └── orchestration/     # Task orchestration (Python)
│
├── python/                # Pure Python modules
│   ├── social_intelligence_engine.py
│   ├── geyser_client.py
│   └── jupiter_price_api.py
│
├── rust-modules/          # High-performance Rust components
├── tests/                 # Comprehensive test suite
├── config/                # Configuration files
├── scripts/               # Utility scripts
└── docs/                  # Documentation
```

### Technology Stack

- **Mojo**: High-performance core components
- **Python**: Orchestration and external integrations
- **Rust**: Ultra-performance data processing
- **Docker**: Containerized deployment
- **Prometheus/Grafana**: Monitoring stack

### Getting Started

1. **Clone and setup**:
   ```bash
   git clone <repository-url>
   cd MojoRust
   make dev-setup
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your API keys
   ```

3. **Run tests**:
   ```bash
   make test
   ```

4. **Start the bot**:
   ```bash
   make run
   ```

### Development

- **Code formatting**: `make format`
- **Linting**: `make lint`
- **Testing**: `make test`
- **Coverage**: `make test-coverage`
- **Docker**: `make docker-build && make docker-run`

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for detailed information.
"""

        # Add structure section if not present
        if "## Project Structure" not in content:
            content += structure_section
            readme_path.write_text(content)
            print("Updated README.md with project structure information")
        else:
            print("README.md already contains project structure information")


def main():
    """Main cleanup function"""
    print("🧹 Cleaning and organizing MojoRust project structure...")
    print("="*60)

    try:
        print("1. Creating directory structure...")
        create_directory_structure()

        print("\n2. Moving files to correct locations...")
        move_files_to_correct_locations()

        print("\n3. Creating development environment files...")
        create_development_environment_files()

        print("\n4. Creating Makefile...")
        create_makefile()

        print("\n5. Updating .gitignore...")
        create_gitignore_entries()

        print("\n6. Updating import statements...")
        update_imports_for_moved_files()

        print("\n7. Updating README...")
        create_readme_update()

        print("\n" + "="*60)
        print("✅ Project cleanup and organization completed!")
        print("\nNext steps:")
        print("1. Run 'make dev-setup' to set up development environment")
        print("2. Run 'make test' to verify everything works")
        print("3. Check the new project structure in PROJECT_STRUCTURE.md")

    except Exception as e:
        print(f"❌ Error during cleanup: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()