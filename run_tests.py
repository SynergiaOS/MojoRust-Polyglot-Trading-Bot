#!/usr/bin/env python3
"""
Test runner for MojoRust trading bot
"""

import sys
import subprocess
import argparse
from pathlib import Path


def run_command(cmd, description):
    """Run a command and handle the result"""
    print(f"\n{'='*60}")
    print(f"Running: {description}")
    print(f"Command: {' '.join(cmd)}")
    print('='*60)

    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {description} failed with exit code {e.returncode}")
        print("STDOUT:", e.stdout)
        print("STDERR:", e.stderr)
        return False


def main():
    """Main test runner"""
    parser = argparse.ArgumentParser(description="Run MojoRust trading bot tests")
    parser.add_argument(
        "--unit", action="store_true",
        help="Run only unit tests"
    )
    parser.add_argument(
        "--integration", action="store_true",
        help="Run only integration tests"
    )
    parser.add_argument(
        "--rpc", action="store_true",
        help="Run only RPC router tests"
    )
    parser.add_argument(
        "--dto", action="store_true",
        help="Run only DTO contract tests"
    )
    parser.add_argument(
        "--taskpool", action="store_true",
        help="Run only TaskPoolManager tests"
    )
    parser.add_argument(
        "--coverage", action="store_true",
        help="Run tests with coverage report"
    )
    parser.add_argument(
        "--fast", action="store_true",
        help="Run tests without slow tests"
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Verbose output"
    )

    args = parser.parse_args()

    # Check if pytest is available
    try:
        import pytest
    except ImportError:
        print("❌ pytest is not installed. Please install it with:")
        print("   pip install pytest pytest-asyncio pytest-mock")
        sys.exit(1)

    # Build test command
    cmd = [sys.executable, "-m", "pytest"]

    # Add verbosity
    if args.verbose:
        cmd.append("-vv")
    else:
        cmd.append("-v")

    # Add coverage if requested
    if args.coverage:
        try:
            import pytest_cov
            cmd.extend(["--cov=src", "--cov-report=html", "--cov-report=term"])
        except ImportError:
            print("⚠️  pytest-cov not installed. Install with: pip install pytest-cov")

    # Add test selection
    if args.unit:
        cmd.extend(["-m", "unit"])
    elif args.integration:
        cmd.extend(["-m", "integration"])
    elif args.rpc:
        cmd.append("tests/test_rpc_router.py")
    elif args.dto:
        cmd.append("tests/test_dto_contracts.py")
    elif args.taskpool:
        cmd.append("tests/test_task_pool_manager.py")
    elif args.fast:
        cmd.extend(["-m", "not slow"])
    else:
        # Run all tests
        cmd.append("tests/")

    # Run tests
    success = run_command(cmd, "Running test suite")

    if success:
        print("\n✅ All tests passed!")

        # Run linting if available
        if not any([args.unit, args.integration, args.rpc, args.dto, args.taskpool]):
            print("\n" + "="*60)
            print("Running additional checks...")
            print("="*60)

            # Check code formatting
            try:
                import black
                run_command([sys.executable, "-m", "black", "--check", "src/"], "Code formatting check (black)")
            except ImportError:
                print("⚠️  black not installed. Install with: pip install black")

            # Check import sorting
            try:
                import isort
                run_command([sys.executable, "-m", "isort", "--check-only", "src/"], "Import sorting check (isort)")
            except ImportError:
                print("⚠️  isort not installed. Install with: pip install isort")

            # Type checking
            try:
                import mypy
                run_command([sys.executable, "-m", "mypy", "src/"], "Type checking (mypy)")
            except ImportError:
                print("⚠️  mypy not installed. Install with: pip install mypy")

        sys.exit(0)
    else:
        print("\n❌ Some tests failed!")
        sys.exit(1)


if __name__ == "__main__":
    main()