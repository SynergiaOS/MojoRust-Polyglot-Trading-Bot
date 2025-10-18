#!/usr/bin/env python3
"""
Benchmark Comparison Script for FFI Performance Regression Testing

This script compares benchmark results between two different commits/branches
to detect performance regressions in the FFI optimizations.
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Dict, List, Any, Optional
import statistics

class BenchmarkResult:
    """Represents a single benchmark result"""
    def __init__(self, name: str, value: float, unit: str, extra_info: Dict[str, Any] = None):
        self.name = name
        self.value = value
        self.unit = unit
        self.extra_info = extra_info or {}

class BenchmarkComparison:
    """Compares two sets of benchmark results"""

    def __init__(self, baseline_results: Dict[str, BenchmarkResult],
                 current_results: Dict[str, BenchmarkResult],
                 regression_threshold: float = 0.1):
        self.baseline = baseline_results
        self.current = current_results
        self.regression_threshold = regression_threshold
        self.comparisons = {}

    def compare(self) -> Dict[str, Any]:
        """Perform benchmark comparison"""
        results = {
            "summary": {
                "total_benchmarks": 0,
                "comparable_benchmarks": 0,
                "regressions": 0,
                "improvements": 0,
                "no_change": 0
            },
            "details": {},
            "regressions": [],
            "improvements": []
        }

        # Compare each benchmark
        for name, baseline_result in self.baseline.items():
            results["summary"]["total_benchmarks"] += 1

            if name in self.current:
                results["summary"]["comparable_benchmarks"] += 1
                current_result = self.current[name]

                comparison = self._compare_single(baseline_result, current_result)
                results["details"][name] = comparison

                # Categorize result
                if comparison["percent_change"] > self.regression_threshold:
                    results["summary"]["regressions"] += 1
                    results["regressions"].append({
                        "name": name,
                        "baseline": baseline_result.value,
                        "current": current_result.value,
                        "percent_change": comparison["percent_change"]
                    })
                elif comparison["percent_change"] < -self.regression_threshold:
                    results["summary"]["improvements"] += 1
                    results["improvements"].append({
                        "name": name,
                        "baseline": baseline_result.value,
                        "current": current_result.value,
                        "percent_change": comparison["percent_change"]
                    })
                else:
                    results["summary"]["no_change"] += 1

        return results

    def _compare_single(self, baseline: BenchmarkResult, current: BenchmarkResult) -> Dict[str, Any]:
        """Compare two individual benchmark results"""
        if baseline.unit != current.unit:
            return {
                "error": f"Unit mismatch: {baseline.unit} vs {current.unit}",
                "percent_change": 0.0
            }

        if baseline.value == 0:
            return {
                "error": "Baseline value is zero",
                "percent_change": 0.0
            }

        percent_change = ((current.value - baseline.value) / baseline.value) * 100.0

        return {
            "baseline_value": baseline.value,
            "current_value": current.value,
            "unit": baseline.unit,
            "absolute_change": current.value - baseline.value,
            "percent_change": percent_change,
            "significant": abs(percent_change) > self.regression_threshold
        }

def load_criterion_json(file_path: Path) -> Dict[str, BenchmarkResult]:
    """Load Criterion benchmark results from JSON file"""
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)

        results = {}

        # Parse Criterion JSON structure
        for benchmark_name, benchmark_data in data.items():
            if "median" in benchmark_data:
                # Individual benchmark result
                results[benchmark_name] = BenchmarkResult(
                    name=benchmark_name,
                    value=benchmark_data["median"],
                    unit=benchmark_data.get("unit", "ns"),
                    extra_info={
                        "min": benchmark_data.get("min"),
                        "max": benchmark_data.get("max"),
                        "std_dev": benchmark_data.get("std_dev")
                    }
                )
            elif "groups" in benchmark_data:
                # Benchmark group with multiple sub-benchmarks
                for sub_name, sub_data in benchmark_data["groups"].items():
                    full_name = f"{benchmark_name}/{sub_name}"
                    if "median" in sub_data:
                        results[full_name] = BenchmarkResult(
                            name=full_name,
                            value=sub_data["median"],
                            unit=sub_data.get("unit", "ns"),
                            extra_info={
                                "min": sub_data.get("min"),
                                "max": sub_data.get("max"),
                                "std_dev": sub_data.get("std_dev")
                            }
                        )

        return results

    except Exception as e:
        print(f"Error loading benchmark file {file_path}: {e}")
        return {}

def parse_custom_format(file_path: Path) -> Dict[str, BenchmarkResult]:
    """Parse custom benchmark format (fallback)"""
    results = {}

    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()

        for line in lines:
            line = line.strip()
            if line and not line.startswith("#"):
                # Expected format: "benchmark_name value unit"
                parts = line.split()
                if len(parts) >= 2:
                    name = parts[0]
                    value = float(parts[1])
                    unit = parts[2] if len(parts) > 2 else "ns"

                    results[name] = BenchmarkResult(name, value, unit)

    except Exception as e:
        print(f"Error parsing custom benchmark file {file_path}: {e}")

    return results

def generate_report(comparison: Dict[str, Any], output_file: Optional[Path] = None) -> str:
    """Generate a human-readable comparison report"""

    report = []
    summary = comparison["summary"]

    report.append("# FFI Performance Benchmark Comparison Report")
    report.append("")
    report.append(f"Total benchmarks: {summary['total_benchmarks']}")
    report.append(f"Comparable benchmarks: {summary['comparable_benchmarks']}")
    report.append(f"Regressions detected: {summary['regressions']}")
    report.append(f"Improvements found: {summary['improvements']}")
    report.append(f"No significant change: {summary['no_change']}")
    report.append("")

    # Regressions section
    if comparison["regressions"]:
        report.append("## 🚨 Performance Regressions")
        report.append("")
        for regression in comparison["regressions"]:
            report.append(f"### {regression['name']}")
            report.append(f"- **Baseline**: {regression['baseline']:.2f}")
            report.append(f"- **Current**: {regression['current']:.2f}")
            report.append(f"- **Change**: +{regression['percent_change']:.2f}%")
            report.append("")

    # Improvements section
    if comparison["improvements"]:
        report.append("## ✅ Performance Improvements")
        report.append("")
        for improvement in comparison["improvements"]:
            report.append(f"### {improvement['name']}")
            report.append(f"- **Baseline**: {improvement['baseline']:.2f}")
            report.append(f"- **Current**: {improvement['current']:.2f}")
            report.append(f"- **Change**: {improvement['percent_change']:.2f}%")
            report.append("")

    # Detailed results
    report.append("## Detailed Results")
    report.append("")

    for name, details in comparison["details"].items():
        if "error" not in details:
            status = "🟢"
            if details["significant"]:
                status = "🔴" if details["percent_change"] > 0 else "🟢"

            report.append(f"### {status} {name}")
            report.append(f"- **Baseline**: {details['baseline_value']:.2f} {details['unit']}")
            report.append(f"- **Current**: {details['current_value']:.2f} {details['unit']}")
            report.append(f"- **Change**: {details['percent_change']:+.2f}%")
            report.append("")

    return "\n".join(report)

def main():
    parser = argparse.ArgumentParser(description="Compare FFI benchmark results")
    parser.add_argument("baseline", help="Baseline benchmark file (JSON)")
    parser.add_argument("current", help="Current benchmark file (JSON)")
    parser.add_argument("--threshold", type=float, default=0.1,
                       help="Regression threshold (default: 0.1 = 10%)")
    parser.add_argument("--output", help="Output report file (optional)")
    parser.add_argument("--format", choices=["criterion", "custom"], default="criterion",
                       help="Input file format (default: criterion)")

    args = parser.parse_args()

    # Load benchmark results
    baseline_path = Path(args.baseline)
    current_path = Path(args.current)

    if not baseline_path.exists():
        print(f"Error: Baseline file not found: {baseline_path}")
        sys.exit(1)

    if not current_path.exists():
        print(f"Error: Current file not found: {current_path}")
        sys.exit(1)

    print(f"Loading baseline results from {baseline_path}")
    print(f"Loading current results from {current_path}")

    if args.format == "criterion":
        baseline_results = load_criterion_json(baseline_path)
        current_results = load_criterion_json(current_path)
    else:
        baseline_results = parse_custom_format(baseline_path)
        current_results = parse_custom_format(current_path)

    if not baseline_results:
        print("Error: No baseline results loaded")
        sys.exit(1)

    if not current_results:
        print("Error: No current results loaded")
        sys.exit(1)

    print(f"Loaded {len(baseline_results)} baseline results")
    print(f"Loaded {len(current_results)} current results")

    # Perform comparison
    comparison = BenchmarkComparison(baseline_results, current_results, args.threshold)
    results = comparison.compare()

    # Generate and output report
    report = generate_report(results, args.output)

    if args.output:
        output_path = Path(args.output)
        with open(output_path, 'w') as f:
            f.write(report)
        print(f"Report saved to {output_path}")
    else:
        print("\n" + "="*60)
        print(report)
        print("="*60)

    # Exit with appropriate code
    if results["summary"]["regressions"] > 0:
        print(f"\n❌ {results['summary']['regressions']} regression(s) detected!")
        sys.exit(1)
    else:
        print(f"\n✅ No significant regressions detected!")
        sys.exit(0)

if __name__ == "__main__":
    main()