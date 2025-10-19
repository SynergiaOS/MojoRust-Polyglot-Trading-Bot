#!/usr/bin/env python3
"""
Save Flash Loan Production Deployment Tests
Live environment testing with monitoring and validation
"""

import pytest
import asyncio
import json
import logging
import time
import subprocess
import requests
from typing import Dict, Any, List, Optional
from dataclasses import dataclass
from datetime import datetime, timedelta

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class DeploymentTest:
    """Production deployment test configuration"""
    name: str
    test_type: str  # "health", "integration", "performance", "load"
    endpoint: str
    expected_status: int
    timeout_seconds: int
    critical: bool

@dataclass
class TestResult:
    """Test execution result"""
    test_name: str
    success: bool
    response_time_ms: float
    status_code: Optional[int]
    error_message: Optional[str]
    timestamp: datetime

class ProductionDeploymentTester:
    """Production deployment testing for Save Flash Loans"""

    def __init__(self, base_url: str = "http://localhost"):
        self.base_url = base_url
        self.test_results = []
        self.metrics_endpoints = {
            "health": f"{base_url}:8080/health",
            "metrics": f"{base_url}:8080/metrics",
            "flash_loan_status": f"{base_url}:8080/api/flash-loan/status",
            "save_provider": f"{base_url}:8080/api/providers/save/status",
            "trading_metrics": f"{base_url}:8080/api/trading/metrics"
        }

    async def run_production_tests(self):
        """Run comprehensive production deployment tests"""
        logger.info("🚀 Starting Save Flash Loan Production Deployment Tests")
        logger.info("=" * 60)

        # Phase 1: Basic Health Checks
        await self.test_health_checks()

        # Phase 2: Service Integration Tests
        await self.test_service_integrations()

        # Phase 3: Flash Loan Functionality Tests
        await self.test_flash_loan_functionality()

        # Phase 4: Performance Tests
        await self.test_performance_metrics()

        # Phase 5: Load Testing
        await self.test_load_handling()

        # Phase 6: Monitoring and Alerting Tests
        await self.test_monitoring_integration()

        # Generate comprehensive report
        self.generate_deployment_report()

    async def test_health_checks(self):
        """Test basic health endpoints"""
        logger.info("🔍 Phase 1: Basic Health Checks")

        health_tests = [
            DeploymentTest(
                name="Main Health Check",
                test_type="health",
                endpoint=self.metrics_endpoints["health"],
                expected_status=200,
                timeout_seconds=10,
                critical=True
            ),
            DeploymentTest(
                name="Metrics Endpoint",
                test_type="health",
                endpoint=self.metrics_endpoints["metrics"],
                expected_status=200,
                timeout_seconds=5,
                critical=True
            ),
            DeploymentTest(
                name="Flash Loan Status",
                test_type="health",
                endpoint=self.metrics_endpoints["flash_loan_status"],
                expected_status=200,
                timeout_seconds=5,
                critical=True
            )
        ]

        for test in health_tests:
            result = await self.execute_http_test(test)
            self.test_results.append(result)

            status = "✅" if result.success else "❌"
            logger.info(f"{status} {test.name}: {result.response_time_ms:.2f}ms")

            if test.critical and not result.success:
                raise Exception(f"Critical health check failed: {test.name}")

    async def test_service_integrations(self):
        """Test service integrations"""
        logger.info("🔗 Phase 2: Service Integration Tests")

        integration_tests = [
            DeploymentTest(
                name="Save Provider Status",
                test_type="integration",
                endpoint=self.metrics_endpoints["save_provider"],
                expected_status=200,
                timeout_seconds=10,
                critical=True
            ),
            DeploymentTest(
                name="Trading Metrics",
                test_type="integration",
                endpoint=self.metrics_endpoints["trading_metrics"],
                expected_status=200,
                timeout_seconds=5,
                critical=True
            )
        ]

        for test in integration_tests:
            result = await self.execute_http_test(test)
            self.test_results.append(result)

            status = "✅" if result.success else "❌"
            logger.info(f"{status} {test.name}: {result.response_time_ms:.2f}ms")

            # Additional validation for integration tests
            if result.success and result.status_code == 200:
                await self.validate_integration_response(test.name, test.endpoint)

    async def test_flash_loan_functionality(self):
        """Test Save flash loan functionality"""
        logger.info("💰 Phase 3: Flash Loan Functionality Tests")

        # Test flash loan configuration
        config_test = DeploymentTest(
            name="Flash Loan Configuration",
            test_type="functionality",
            endpoint=f"{self.base_url}:8080/api/flash-loan/config",
            expected_status=200,
            timeout_seconds=5,
            critical=True
        )

        result = await self.execute_http_test(config_test)
        self.test_results.append(result)

        if result.success:
            await self.validate_flash_loan_config()

        # Test quote generation
        quote_test = DeploymentTest(
            name="Jupiter Quote Generation",
            test_type="functionality",
            endpoint=f"{self.base_url}:8080/api/jupiter/quote",
            expected_status=200,
            timeout_seconds=10,
            critical=True
        )

        result = await self.execute_http_test(quote_test)
        self.test_results.append(result)

        # Test provider status
        provider_tests = [
            ("Save Provider", "save"),
            ("Solend Provider", "solend"),
            ("Jupiter Integration", "jupiter")
        ]

        for provider_name, provider_id in provider_tests:
            provider_test = DeploymentTest(
                name=f"{provider_name} Status",
                test_type="functionality",
                endpoint=f"{self.base_url}:8080/api/providers/{provider_id}/status",
                expected_status=200,
                timeout_seconds=5,
                critical=False
            )

            result = await self.execute_http_test(provider_test)
            self.test_results.append(result)

            status = "✅" if result.success else "❌"
            logger.info(f"{status} {provider_name}: {result.response_time_ms:.2f}ms")

    async def test_performance_metrics(self):
        """Test performance metrics collection"""
        logger.info("⚡ Phase 4: Performance Metrics Tests")

        performance_tests = [
            DeploymentTest(
                name="Prometheus Metrics",
                test_type="performance",
                endpoint=f"{self.base_url}:9090/metrics",
                expected_status=200,
                timeout_seconds=5,
                critical=False
            ),
            DeploymentTest(
                name="Grafana Health",
                test_type="performance",
                endpoint=f"{self.base_url}:3001/api/health",
                expected_status=200,
                timeout_seconds=5,
                critical=False
            )
        ]

        for test in performance_tests:
            result = await self.execute_http_test(test)
            self.test_results.append(result)

            status = "✅" if result.success else "❌"
            logger.info(f"{status} {test.name}: {result.response_time_ms:.2f}ms")

        # Test latency metrics
        await self.test_latency_metrics()

        # Test throughput metrics
        await self.test_throughput_metrics()

    async def test_latency_metrics(self):
        """Test latency metrics collection"""
        logger.info("📊 Testing Latency Metrics")

        # Make multiple requests to measure latency
        latencies = []
        for i in range(10):
            start_time = time.time()
            try:
                response = requests.get(self.metrics_endpoints["health"], timeout=5)
                latency_ms = (time.time() - start_time) * 1000
                latencies.append(latency_ms)
                await asyncio.sleep(0.1)
            except Exception as e:
                logger.warning(f"Latency test {i+1} failed: {e}")

        if latencies:
            avg_latency = sum(latencies) / len(latencies)
            min_latency = min(latencies)
            max_latency = max(latencies)

            logger.info(f"  Average Latency: {avg_latency:.2f}ms")
            logger.info(f"  Min/Max Latency: {min_latency:.2f}ms / {max_latency:.2f}ms")

            # Validate latency targets
            assert avg_latency < 100, f"Average latency too high: {avg_latency:.2f}ms"
            assert max_latency < 500, f"Maximum latency too high: {max_latency:.2f}ms"

            # Record latency test result
            test_result = TestResult(
                test_name="Latency Metrics",
                success=avg_latency < 100 and max_latency < 500,
                response_time_ms=avg_latency,
                status_code=200,
                error_message=None,
                timestamp=datetime.now()
            )
            self.test_results.append(test_result)

    async def test_throughput_metrics(self):
        """Test throughput metrics"""
        logger.info("📈 Testing Throughput Metrics")

        # Test concurrent requests
        concurrent_count = 20
        start_time = time.time()

        async def make_request():
            try:
                response = requests.get(self.metrics_endpoints["health"], timeout=2)
                return response.status_code == 200
            except:
                return False

        tasks = [make_request() for _ in range(concurrent_count)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        end_time = time.time()
        total_time = end_time - start_time
        successful_requests = sum(1 for r in results if r is True)
        throughput = successful_requests / total_time

        logger.info(f"  Concurrent Requests: {concurrent_count}")
        logger.info(f"  Successful: {successful_requests}/{concurrent_count}")
        logger.info(f"  Throughput: {throughput:.2f} requests/second")

        # Validate throughput targets
        assert throughput > 10, f"Throughput too low: {throughput:.2f} req/s"
        assert successful_requests >= concurrent_count * 0.8, f"Success rate too low: {successful_requests}/{concurrent_count}"

        # Record throughput test result
        test_result = TestResult(
            test_name="Throughput Metrics",
            success=throughput > 10 and successful_requests >= concurrent_count * 0.8,
            response_time_ms=total_time * 1000,
            status_code=200,
            error_message=None,
            timestamp=datetime.now()
        )
        self.test_results.append(test_result)

    async def test_load_handling(self):
        """Test system load handling"""
        logger.info("🔄 Phase 5: Load Handling Tests")

        # Test sustained load
        duration_seconds = 30
        requests_per_second = 10
        total_requests = duration_seconds * requests_per_second

        logger.info(f"  Running {total_requests} requests over {duration_seconds}s")

        successful_requests = 0
        failed_requests = 0
        response_times = []

        start_time = time.time()
        end_time = start_time + duration_seconds

        request_interval = 1.0 / requests_per_second
        next_request_time = start_time

        while time.time() < end_time:
            current_time = time.time()
            if current_time >= next_request_time:
                next_request_time += request_interval

                request_start = time.time()
                try:
                    response = requests.get(self.metrics_endpoints["health"], timeout=2)
                    response_time = (time.time() - request_start) * 1000
                    response_times.append(response_time)

                    if response.status_code == 200:
                        successful_requests += 1
                    else:
                        failed_requests += 1

                except Exception as e:
                    failed_requests += 1
                    logger.warning(f"Load test request failed: {e}")

                # Small delay to maintain request rate
                await asyncio.sleep(0.01)

        # Calculate load test metrics
        actual_duration = time.time() - start_time
        actual_rps = successful_requests / actual_duration
        success_rate = successful_requests / total_requests

        if response_times:
            avg_response_time = sum(response_times) / len(response_times)
            p95_response_time = sorted(response_times)[int(len(response_times) * 0.95)]
        else:
            avg_response_time = 0
            p95_response_time = 0

        logger.info(f"  Duration: {actual_duration:.2f}s")
        logger.info(f"  Requests: {successful_requests}/{total_requests} ({success_rate:.1%})")
        logger.info(f"  Actual RPS: {actual_rps:.2f}")
        logger.info(f"  Avg Response Time: {avg_response_time:.2f}ms")
        logger.info(f"  95th Percentile: {p95_response_time:.2f}ms")

        # Validate load test results
        assert success_rate >= 0.95, f"Success rate too low: {success_rate:.1%}"
        assert actual_rps >= requests_per_second * 0.9, f"RPS too low: {actual_rps:.2f}"
        assert avg_response_time < 200, f"Average response time too high: {avg_response_time:.2f}ms"

        # Record load test result
        test_result = TestResult(
            test_name="Load Handling Test",
            success=(success_rate >= 0.95 and actual_rps >= requests_per_second * 0.9 and avg_response_time < 200),
            response_time_ms=avg_response_time,
            status_code=200,
            error_message=None,
            timestamp=datetime.now()
        )
        self.test_results.append(test_result)

    async def test_monitoring_integration(self):
        """Test monitoring and alerting integration"""
        logger.info("📊 Phase 6: Monitoring Integration Tests")

        monitoring_tests = [
            DeploymentTest(
                name="Prometheus Target Status",
                test_type="monitoring",
                endpoint=f"{self.base_url}:9090/api/v1/targets",
                expected_status=200,
                timeout_seconds=5,
                critical=False
            ),
            DeploymentTest(
                name="AlertManager Health",
                test_type="monitoring",
                endpoint=f"{self.base_url}:9093/-/healthy",
                expected_status=200,
                timeout_seconds=5,
                critical=False
            )
        ]

        for test in monitoring_tests:
            result = await self.execute_http_test(test)
            self.test_results.append(result)

            status = "✅" if result.success else "❌"
            logger.info(f"{status} {test.name}: {result.response_time_ms:.2f}ms")

        # Test Docker container health
        await self.test_container_health()

        # Test resource usage
        await self.test_resource_usage()

    async def test_container_health(self):
        """Test Docker container health"""
        logger.info("🐳 Testing Container Health")

        try:
            # Check if Docker is running and containers are healthy
            result = subprocess.run(
                ["docker", "ps", "--filter", "name=trading-bot", "--format", "{{.Names}}\t{{.Status}}"],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0:
                containers = result.stdout.strip().split('\n')
                healthy_containers = [c for c in containers if 'healthy' in c.lower()]

                logger.info(f"  Total Containers: {len(containers)}")
                logger.info(f"  Healthy Containers: {len(healthy_containers)}")

                success = len(healthy_containers) > 0
            else:
                logger.warning("Docker command failed")
                success = False

        except subprocess.TimeoutExpired:
            logger.warning("Docker command timed out")
            success = False
        except Exception as e:
            logger.warning(f"Container health check failed: {e}")
            success = False

        # Record container health test result
        test_result = TestResult(
            test_name="Container Health",
            success=success,
            response_time_ms=0,
            status_code=None,
            error_message=None if success else "Container health check failed",
            timestamp=datetime.now()
        )
        self.test_results.append(test_result)

    async def test_resource_usage(self):
        """Test system resource usage"""
        logger.info("💾 Testing Resource Usage")

        try:
            import psutil

            # CPU usage
            cpu_percent = psutil.cpu_percent(interval=1)
            memory_info = psutil.virtual_memory()
            disk_usage = psutil.disk_usage('/')

            logger.info(f"  CPU Usage: {cpu_percent:.1f}%")
            logger.info(f"  Memory Usage: {memory_info.percent:.1f}%")
            logger.info(f"  Disk Usage: {disk_usage.percent:.1f}%")

            # Check resource thresholds
            cpu_ok = cpu_percent < 80
            memory_ok = memory_info.percent < 85
            disk_ok = disk_usage.percent < 90

            success = cpu_ok and memory_ok and disk_ok

            if not cpu_ok:
                logger.warning(f"High CPU usage: {cpu_percent:.1f}%")
            if not memory_ok:
                logger.warning(f"High memory usage: {memory_info.percent:.1f}%")
            if not disk_ok:
                logger.warning(f"High disk usage: {disk_usage.percent:.1f}%")

        except ImportError:
            logger.warning("psutil not available for resource monitoring")
            success = True
        except Exception as e:
            logger.warning(f"Resource usage check failed: {e}")
            success = False

        # Record resource usage test result
        test_result = TestResult(
            test_name="Resource Usage",
            success=success,
            response_time_ms=0,
            status_code=None,
            error_message=None if success else "Resource usage too high",
            timestamp=datetime.now()
        )
        self.test_results.append(test_result)

    async def execute_http_test(self, test: DeploymentTest) -> TestResult:
        """Execute individual HTTP test"""
        start_time = time.time()
        error_message = None
        status_code = None

        try:
            response = requests.get(test.endpoint, timeout=test.timeout_seconds)
            status_code = response.status_code
            success = status_code == test.expected_status

            if not success:
                error_message = f"Expected status {test.expected_status}, got {status_code}"

        except requests.exceptions.Timeout:
            error_message = f"Request timed out after {test.timeout_seconds}s"
            success = False
        except requests.exceptions.ConnectionError:
            error_message = "Connection error"
            success = False
        except Exception as e:
            error_message = str(e)
            success = False

        response_time_ms = (time.time() - start_time) * 1000

        return TestResult(
            test_name=test.name,
            success=success,
            response_time_ms=response_time_ms,
            status_code=status_code,
            error_message=error_message,
            timestamp=datetime.now()
        )

    async def validate_integration_response(self, test_name: str, endpoint: str):
        """Validate integration response data"""
        try:
            response = requests.get(endpoint, timeout=5)
            if response.status_code == 200:
                data = response.json()

                # Validate response structure based on test type
                if "Save Provider" in test_name:
                    assert "status" in data, "Save provider response missing status field"
                    assert "available_liquidity" in data, "Save provider response missing liquidity field"
                    assert "fee_bps" in data, "Save provider response missing fee field"

                elif "Trading Metrics" in test_name:
                    assert "total_trades" in data, "Trading metrics missing total_trades"
                    assert "success_rate" in data, "Trading metrics missing success_rate"
                    assert "average_profit" in data, "Trading metrics missing average_profit"

                logger.info(f"  ✅ {test_name} response validation passed")

        except Exception as e:
            logger.warning(f"  ❌ {test_name} response validation failed: {e}")

    async def validate_flash_loan_config(self):
        """Validate flash loan configuration"""
        try:
            response = requests.get(f"{self.base_url}:8080/api/flash-loan/config", timeout=5)
            if response.status_code == 200:
                config = response.json()

                # Validate required configuration fields
                required_fields = [
                    "max_loan_amount",
                    "save_enabled",
                    "solend_enabled",
                    "slippage_bps",
                    "min_confidence"
                ]

                for field in required_fields:
                    assert field in config, f"Flash loan config missing required field: {field}"

                # Validate configuration values
                assert config["max_loan_amount"] > 0, "Invalid max_loan_amount"
                assert isinstance(config["save_enabled"], bool), "Invalid save_enabled type"
                assert 0 <= config["slippage_bps"] <= 1000, "Invalid slippage_bps range"
                assert 0 <= config["min_confidence"] <= 1, "Invalid min_confidence range"

                logger.info("  ✅ Flash loan configuration validation passed")

        except Exception as e:
            logger.warning(f"  ❌ Flash loan configuration validation failed: {e}")

    def generate_deployment_report(self):
        """Generate comprehensive deployment report"""
        logger.info("📊 PRODUCTION DEPLOYMENT REPORT")
        logger.info("=" * 60)

        # Test summary
        total_tests = len(self.test_results)
        successful_tests = sum(1 for r in self.test_results if r.success)
        failed_tests = total_tests - successful_tests
        success_rate = (successful_tests / total_tests) * 100 if total_tests > 0 else 0

        logger.info(f"Total Tests: {total_tests}")
        logger.info(f"Successful: {successful_tests} ({success_rate:.1f}%)")
        logger.info(f"Failed: {failed_tests} ({100-success_rate:.1f}%)")

        # Response time analysis
        response_times = [r.response_time_ms for r in self.test_results if r.response_time_ms > 0]
        if response_times:
            avg_response_time = sum(response_times) / len(response_times)
            min_response_time = min(response_times)
            max_response_time = max(response_times)

            logger.info(f"Average Response Time: {avg_response_time:.2f}ms")
            logger.info(f"Response Time Range: {min_response_time:.2f}ms - {max_response_time:.2f}ms")

        # Test type breakdown
        test_types = {}
        for result in self.test_results:
            test_type = "unknown"
            for test in ["health", "integration", "functionality", "performance", "monitoring"]:
                if test in result.test_name.lower():
                    test_type = test
                    break

            if test_type not in test_types:
                test_types[test_type] = {"total": 0, "successful": 0}

            test_types[test_type]["total"] += 1
            if result.success:
                test_types[test_type]["successful"] += 1

        logger.info("\n📈 Test Type Breakdown:")
        for test_type, counts in test_types.items():
            success_rate = (counts["successful"] / counts["total"]) * 100
            logger.info(f"  {test_type.title()}: {counts['successful']}/{counts['total']} ({success_rate:.1f}%)")

        # Failed tests
        failed_test_results = [r for r in self.test_results if not r.success]
        if failed_test_results:
            logger.info("\n❌ Failed Tests:")
            for result in failed_test_results:
                logger.info(f"  {result.test_name}: {result.error_message}")

        # Recommendations
        logger.info("\n💡 Deployment Recommendations:")

        if success_rate >= 95:
            logger.info("  ✅ Excellent deployment health!")
        elif success_rate >= 85:
            logger.info("  ⚠️ Good deployment health, but some issues need attention")
        else:
            logger.warning("  🚨 Deployment has significant issues - investigate immediately")

        if response_times:
            if avg_response_time > 200:
                logger.warning("  - Average response time is high - consider optimization")
            if max_response_time > 1000:
                logger.warning("  - Some responses are very slow - check for bottlenecks")

        # Health recommendations
        health_tests = [r for r in self.test_results if "health" in r.test_name.lower()]
        failed_health_tests = [r for r in health_tests if not r.success]

        if failed_health_tests:
            logger.warning(f"  - {len(failed_health_tests)} health tests failed - immediate attention required")

        logger.info("=" * 60)

        # Final verdict
        if success_rate >= 95 and len(failed_health_tests) == 0:
            logger.info("🎉 DEPLOYMENT READY FOR PRODUCTION!")
        elif success_rate >= 85:
            logger.info("⚠️ DEPLOYMENT READY WITH CAUTION")
        else:
            logger.error("❌ DEPLOYMENT NOT READY - FIX CRITICAL ISSUES")

class TestProductionDeployment:
    """Pytest test class for production deployment"""

    @pytest.fixture
    def deployment_tester(self):
        """Create deployment tester instance"""
        return ProductionDeploymentTester()

    @pytest.mark.asyncio
    async def test_production_deployment(self, deployment_tester):
        """Run complete production deployment test suite"""
        await deployment_tester.run_production_tests()

        # Verify all critical tests passed
        critical_tests = [r for r in deployment_tester.test_results if r.test_name in [
            "Main Health Check",
            "Metrics Endpoint",
            "Flash Loan Status",
            "Save Provider Status"
        ]]

        failed_critical = [r for r in critical_tests if not r.success]
        assert len(failed_critical) == 0, f"Critical tests failed: {[r.test_name for r in failed_critical]}"

        # Verify overall success rate
        total_tests = len(deployment_tester.test_results)
        successful_tests = sum(1 for r in deployment_tester.test_results if r.success)
        success_rate = (successful_tests / total_tests) * 100

        assert success_rate >= 80, f"Overall success rate too low: {success_rate:.1f}%"

    @pytest.mark.asyncio
    async def test_save_provider_readiness(self, deployment_tester):
        """Specific test for Save provider readiness"""
        save_provider_test = DeploymentTest(
            name="Save Provider Readiness",
            test_type="health",
            endpoint=f"{deployment_tester.base_url}:8080/api/providers/save/status",
            expected_status=200,
            timeout_seconds=10,
            critical=True
        )

        result = await deployment_tester.execute_http_test(save_provider_test)
        assert result.success, f"Save provider not ready: {result.error_message}"

        # Additional Save-specific validation
        try:
            response = requests.get(save_provider_test.endpoint, timeout=10)
            if response.status_code == 200:
                data = response.json()

                # Validate Save provider specific fields
                assert "protocol" in data and data["protocol"] == "save", "Protocol field mismatch"
                assert "status" in data and data["status"] == "active", "Save provider not active"
                assert "max_loan_amount" in data, "Missing max_loan_amount field"
                assert data["max_loan_amount"] >= 5_000_000_000, "Save max loan amount too low"

                logger.info("✅ Save provider readiness validation passed")

        except Exception as e:
            pytest.fail(f"Save provider validation failed: {e}")

if __name__ == "__main__":
    # Run production deployment tests
    pytest.main([__file__, "-v", "--tb=short", "--asyncio-mode=auto"])