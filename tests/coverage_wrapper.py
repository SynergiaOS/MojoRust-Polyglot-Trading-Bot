#!/usr/bin/env python3
"""
Coverage Wrapper for MojoRust Trading Bot

This script runs all Mojo tests with coverage measurement and generates
comprehensive reports in multiple formats.

Usage:
    python tests/coverage_wrapper.py --threshold 70.0 --output-dir tests/coverage --fail-under
"""

import argparse
import os
import sys
import subprocess
import json
import time
from pathlib import Path
from typing import List, Dict, Any, Optional
import coverage

class MojoCoverageRunner:
    """Main coverage runner for Mojo tests"""

    def __init__(self, source_dirs: List[str] = None, output_dir: str = "tests/coverage"):
        self.source_dirs = source_dirs or ["src"]
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Initialize coverage
        self.cov = coverage.Coverage(
            source=source_dirs,
            omit=[
                "*/tests/*",
                "*/__pycache__/*",
                "*/venv/*",
                "*/env/*",
                "*/site-packages/*",
            ],
            config_file=".coveragerc",
            data_file=str(self.output_dir / ".coverage"),
        )

        self.test_files: List[str] = []
        self.test_results: List[Dict[str, Any]] = []
        self.start_time: float = 0
        self.end_time: float = 0

    def discover_mojo_tests(self) -> List[str]:
        """Discover all Mojo test files"""
        test_patterns = [
            "tests/test_*.mojo",
            "tests/*_test.mojo",
            "tests/integration/test_*.mojo",
            "tests/integration/*_test.mojo",
        ]

        test_files = []

        for pattern in test_patterns:
            try:
                result = subprocess.run(
                    ["find", ".", "-name", pattern.split("/")[-1], "-type", "f"],
                    capture_output=True,
                    text=True,
                    check=True
                )

                found_files = [line.strip() for line in result.stdout.split("\n") if line.strip()]
                test_files.extend(found_files)

            except subprocess.CalledProcessError:
                # Fallback to glob pattern
                import glob
                found_files = glob.glob(pattern)
                test_files.extend(found_files)

        # Remove duplicates and sort
        test_files = sorted(list(set(test_files)))

        # Filter for actual Mojo files
        test_files = [f for f in test_files if f.endswith('.mojo') and os.path.exists(f)]

        print(f"Discovered {len(test_files)} Mojo test files")
        for test_file in test_files:
            print(f"  - {test_file}")

        return test_files

    def run_single_test(self, test_file: str, timeout: int = 60) -> Dict[str, Any]:
        """Run a single Mojo test file"""
        test_name = os.path.basename(test_file)
        print(f"\n🧪 Running {test_name}...")

        start_time = time.time()

        try:
            # Run the test with timeout
            result = subprocess.run(
                ["mojo", "test", test_file],
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=os.getcwd()
            )

            end_time = time.time()
            duration = end_time - start_time

            test_result = {
                "file": test_file,
                "name": test_name,
                "success": result.returncode == 0,
                "duration": duration,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "returncode": result.returncode,
                "timestamp": start_time,
            }

            # Print result summary
            if test_result["success"]:
                print(f"✅ PASS: {test_name} ({duration:.2f}s)")
            else:
                print(f"❌ FAIL: {test_name} ({duration:.2f}s)")
                if result.stderr:
                    print(f"   Error: {result.stderr[:200]}...")

            return test_result

        except subprocess.TimeoutExpired:
            duration = timeout
            print(f"⏰ TIMEOUT: {test_name} (>{timeout}s)")

            return {
                "file": test_file,
                "name": test_name,
                "success": False,
                "duration": duration,
                "stdout": "",
                "stderr": f"Test timed out after {timeout} seconds",
                "returncode": -1,
                "timestamp": start_time,
                "timeout": True,
            }

        except Exception as e:
            print(f"💥 ERROR: {test_name} - {str(e)}")

            return {
                "file": test_file,
                "name": test_name,
                "success": False,
                "duration": 0,
                "stdout": "",
                "stderr": str(e),
                "returncode": -2,
                "timestamp": start_time,
                "exception": True,
            }

    def run_all_tests(self, timeout: int = 60) -> bool:
        """Run all discovered tests with coverage"""
        print("🚀 Starting Mojo Test Coverage Analysis")
        print("=" * 60)

        self.start_time = time.time()

        # Discover tests
        self.test_files = self.discover_mojo_tests()

        if not self.test_files:
            print("❌ No Mojo test files found!")
            return False

        # Start coverage
        print("\n📊 Starting coverage measurement...")
        self.cov.start()

        # Run tests
        total_tests = len(self.test_files)
        passed_tests = 0
        failed_tests = 0

        for i, test_file in enumerate(self.test_files, 1):
            print(f"\n[{i}/{total_tests}] ", end="")

            result = self.run_single_test(test_file, timeout)
            self.test_results.append(result)

            if result["success"]:
                passed_tests += 1
            else:
                failed_tests += 1

        # Stop coverage
        print("\n📊 Stopping coverage measurement...")
        self.cov.stop()
        self.cov.save()

        self.end_time = time.time()
        total_duration = self.end_time - self.start_time

        # Print test summary
        print("\n" + "=" * 60)
        print("📊 Test Execution Summary")
        print("=" * 60)
        print(f"Total Tests: {total_tests}")
        print(f"Passed: {passed_tests} ✅")
        print(f"Failed: {failed_tests} ❌")
        print(f"Duration: {total_duration:.2f}s")

        if failed_tests == 0:
            print("\n🎉 All tests passed!")
        else:
            print(f"\n⚠️  {failed_tests} test(s) failed.")
            print("\nFailed tests:")
            for result in self.test_results:
                if not result["success"]:
                    print(f"  - {result['name']}: {result['stderr'][:100]}...")

        return failed_tests == 0

    def generate_reports(self) -> Dict[str, Any]:
        """Generate coverage reports in multiple formats"""
        print("\n📈 Generating coverage reports...")

        reports = {}

        # HTML Report
        try:
            html_file = self.output_dir / "html" / "index.html"
            self.cov.html_report(str(self.output_dir / "html"))
            reports["html"] = str(html_file)
            print(f"✅ HTML report: {html_file}")
        except Exception as e:
            print(f"❌ HTML report failed: {e}")
            reports["html"] = None

        # XML Report (Cobertura)
        try:
            xml_file = self.output_dir / "coverage.xml"
            self.cov.xml_report(str(xml_file))
            reports["xml"] = str(xml_file)
            print(f"✅ XML report: {xml_file}")
        except Exception as e:
            print(f"❌ XML report failed: {e}")
            reports["xml"] = None

        # Console Report
        try:
            print("\n📊 Coverage Report:")
            self.cov.report()

            # Get coverage data
            coverage_data = self.cov.get_data()
            total_coverage = coverage_data.coverage

            reports["total_coverage"] = total_coverage
            reports["console_summary"] = self._get_coverage_summary()

        except Exception as e:
            print(f"❌ Console report failed: {e}")
            reports["total_coverage"] = 0
            reports["console_summary"] = None

        # JSON Report
        try:
            json_file = self.output_dir / "coverage.json"
            json_data = self._generate_json_report()
            with open(json_file, 'w') as f:
                json.dump(json_data, f, indent=2, default=str)
            reports["json"] = str(json_file)
            print(f"✅ JSON report: {json_file}")
        except Exception as e:
            print(f"❌ JSON report failed: {e}")
            reports["json"] = None

        return reports

    def _get_coverage_summary(self) -> Dict[str, Any]:
        """Get coverage summary statistics"""
        try:
            coverage_data = self.cov.get_data()

            summary = {
                "total_lines": 0,
                "covered_lines": 0,
                "missing_lines": 0,
                "percentage": 0.0,
            }

            for filename in coverage_data.measured_files():
                analysis = coverage_data.analysis(filename)
                for line_num in analysis:
                    if line_num > 0:  # Only count executable lines
                        summary["total_lines"] += 1
                        if line_num in coverage_data._lines[filename]:
                            summary["covered_lines"] += 1
                        else:
                            summary["missing_lines"] += 1

            if summary["total_lines"] > 0:
                summary["percentage"] = (summary["covered_lines"] / summary["total_lines"]) * 100

            return summary

        except Exception as e:
            print(f"Error generating coverage summary: {e}")
            return {"percentage": 0.0, "error": str(e)}

    def _generate_json_report(self) -> Dict[str, Any]:
        """Generate comprehensive JSON report"""
        coverage_summary = self._get_coverage_summary()

        report = {
            "metadata": {
                "generated_at": time.time(),
                "generated_at_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "tool": "coverage.py",
                "version": coverage.__version__,
                "source_dirs": self.source_dirs,
                "output_dir": str(self.output_dir),
            },
            "test_execution": {
                "start_time": self.start_time,
                "end_time": self.end_time,
                "duration": self.end_time - self.start_time,
                "total_tests": len(self.test_results),
                "passed_tests": len([r for r in self.test_results if r["success"]]),
                "failed_tests": len([r for r in self.test_results if not r["success"]]),
                "test_files": self.test_files,
            },
            "test_results": self.test_results,
            "coverage": coverage_summary,
            "files_coverage": self._get_per_file_coverage(),
        }

        return report

    def _get_per_file_coverage(self) -> Dict[str, Any]:
        """Get coverage data for each file"""
        try:
            coverage_data = self.cov.get_data()
            files_coverage = {}

            for filename in coverage_data.measured_files():
                analysis = coverage_data.analysis(filename)

                total_lines = 0
                covered_lines = 0
                missing_lines = []

                for line_num in analysis:
                    if line_num > 0:  # Only count executable lines
                        total_lines += 1
                        if line_num in coverage_data._lines[filename]:
                            covered_lines += 1
                        else:
                            missing_lines.append(line_num)

                percentage = (covered_lines / total_lines * 100) if total_lines > 0 else 0

                files_coverage[filename] = {
                    "total_lines": total_lines,
                    "covered_lines": covered_lines,
                    "missing_lines": missing_lines,
                    "percentage": percentage,
                }

            return files_coverage

        except Exception as e:
            print(f"Error getting per-file coverage: {e}")
            return {}

    def check_threshold(self, threshold: float) -> bool:
        """Check if coverage meets the threshold"""
        coverage_summary = self._get_coverage_summary()
        actual_coverage = coverage_summary.get("percentage", 0.0)

        print(f"\n📊 Coverage Threshold Check:")
        print(f"   Required: {threshold:.1f}%")
        print(f"   Actual:   {actual_coverage:.1f}%")

        if actual_coverage >= threshold:
            print(f"✅ PASSED: Coverage meets threshold")
            return True
        else:
            print(f"❌ FAILED: Coverage below threshold by {threshold - actual_coverage:.1f}%")
            return False

    def run(self, threshold: Optional[float] = None, fail_under: bool = False, timeout: int = 60) -> int:
        """Run the complete coverage analysis"""
        try:
            # Run tests with coverage
            tests_passed = self.run_all_tests(timeout)

            if not tests_passed:
                print("\n❌ Tests failed - coverage analysis incomplete")
                return 1

            # Generate reports
            reports = self.generate_reports()

            # Check threshold if specified
            if threshold is not None:
                threshold_passed = self.check_threshold(threshold)

                if not threshold_passed and fail_under:
                    print(f"\n❌ Coverage threshold ({threshold:.1f}%) not met - failing build")
                    return 1

            print(f"\n✅ Coverage analysis completed successfully!")
            print(f"📁 Reports available in: {self.output_dir}")

            return 0

        except KeyboardInterrupt:
            print("\n⚠️  Coverage analysis interrupted by user")
            return 130
        except Exception as e:
            print(f"\n💥 Unexpected error: {e}")
            return 1

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="MojoRust Coverage Wrapper",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    # Run coverage with default settings
    python tests/coverage_wrapper.py

    # Run with 70% threshold but don't fail build
    python tests/coverage_wrapper.py --threshold 70.0

    # Run with 70% threshold and fail build if not met
    python tests/coverage_wrapper.py --threshold 70.0 --fail-under

    # Custom output directory
    python tests/coverage_wrapper.py --output-dir reports/coverage
        """
    )

    parser.add_argument(
        "--threshold",
        type=float,
        default=70.0,
        help="Coverage percentage threshold (default: 70.0)"
    )

    parser.add_argument(
        "--fail-under",
        action="store_true",
        help="Fail with non-zero exit code if coverage below threshold"
    )

    parser.add_argument(
        "--output-dir",
        default="tests/coverage",
        help="Output directory for coverage reports (default: tests/coverage)"
    )

    parser.add_argument(
        "--source",
        nargs="+",
        default=["src"],
        help="Source directories to measure coverage for (default: src)"
    )

    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="Test timeout in seconds (default: 60)"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose output"
    )

    args = parser.parse_args()

    # Create and run coverage analyzer
    runner = MojoCoverageRunner(
        source_dirs=args.source,
        output_dir=args.output_dir
    )

    if args.verbose:
        print(f"Configuration:")
        print(f"  Source directories: {args.source}")
        print(f"  Output directory: {args.output_dir}")
        print(f"  Coverage threshold: {args.threshold}%")
        print(f"  Fail under threshold: {args.fail_under}")
        print(f"  Test timeout: {args.timeout}s")
        print()

    # Run coverage analysis
    exit_code = runner.run(
        threshold=args.threshold,
        fail_under=args.fail_under,
        timeout=args.timeout
    )

    sys.exit(exit_code)

if __name__ == "__main__":
    main()