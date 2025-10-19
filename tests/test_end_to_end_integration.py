#!/usr/bin/env python3
"""
End-to-End Integration Tests for MojoRust Trading Bot

This test suite validates the complete trading system integration:
- Data Consumer (Geyser/Redis)
- Manual Targeting API
- Opportunity Queue System
- Cross-component JSON communication

Run with: python tests/test_end_to_end_integration.py
"""

import asyncio
import json
import os
import sys
import time
import uuid
from datetime import datetime
from typing import Dict, Any, List

import aiohttp
import pytest
import redis.asyncio as redis

# Add src to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

class TestConfig:
    """Test configuration"""
    REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379')
    HEALTH_API_URL = 'http://localhost:8082'
    DATA_CONSUMER_URL = 'http://localhost:9191'
    TEST_TIMEOUT = 30  # seconds
    TEST_TOKENS = [
        'So11111111111111111111111111111111111111112',  # SOL
        'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',  # USDC
        'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263',  # BONK
    ]

class IntegrationTestSuite:
    """End-to-end integration test suite"""

    def __init__(self):
        self.redis_client = None
        self.http_session = None
        self.test_results = []

    async def setup(self):
        """Initialize test environment"""
        print("🔧 Setting up test environment...")

        # Initialize Redis client
        self.redis_client = redis.from_url(
            TestConfig.REDIS_URL,
            decode_responses=True
        )

        # Initialize HTTP session
        self.http_session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=TestConfig.TEST_TIMEOUT)
        )

        # Verify connections
        await self._verify_connections()
        print("✅ Test environment ready")

    async def teardown(self):
        """Cleanup test environment"""
        print("🧹 Cleaning up test environment...")

        # Clean up Redis test data
        await self._cleanup_redis()

        # Close HTTP session
        if self.http_session:
            await self.http_session.close()

        # Close Redis client
        if self.redis_client:
            await self.redis_client.close()

        print("✅ Cleanup completed")

    async def _verify_connections(self):
        """Verify all required services are available"""
        # Test Redis connection
        try:
            await self.redis_client.ping()
        except Exception as e:
            raise Exception(f"Redis connection failed: {e}")

        # Test Health API
        try:
            async with self.http_session.get(f"{TestConfig.HEALTH_API_URL}/health") as resp:
                if resp.status != 200:
                    raise Exception(f"Health API returned status {resp.status}")
        except Exception as e:
            raise Exception(f"Health API connection failed: {e}")

        # Test Data Consumer
        try:
            async with self.http_session.get(f"{TestConfig.DATA_CONSUMER_URL}/health") as resp:
                if resp.status != 200:
                    raise Exception(f"Data Consumer returned status {resp.status}")
        except Exception as e:
            raise Exception(f"Data Consumer connection failed: {e}")

    async def _cleanup_redis(self):
        """Clean up test data from Redis"""
        # Clean up opportunity queue
        await self.redis_client.delete("opportunity_queue")

        # Clean up manual targets
        keys = await self.redis_client.keys("manual_target:*")
        if keys:
            await self.redis_client.delete(*keys)

        # Clean up capital reservations
        keys = await self.redis_client.keys("capital_reservation:*")
        if keys:
            await self.redis_client.delete(*keys)

    def _log_test_result(self, test_name: str, success: bool, details: str = ""):
        """Log test result"""
        result = {
            "test_name": test_name,
            "success": success,
            "details": details,
            "timestamp": datetime.now().isoformat()
        }
        self.test_results.append(result)

        status = "✅ PASS" if success else "❌ FAIL"
        print(f"{status} {test_name}")
        if details:
            print(f"   Details: {details}")

    # ============================================================================
    # Manual Targeting API Tests
    # ============================================================================

    async def test_manual_targeting_api_health(self):
        """Test manual targeting API health endpoint"""
        try:
            async with self.http_session.get(f"{TestConfig.HEALTH_API_URL}/health") as resp:
                data = await resp.json()

                assert "status" in data
                assert "uptime" in data

                self._log_test_result("Manual Targeting API Health", True, f"Status: {data['status']}")

        except Exception as e:
            self._log_test_result("Manual Targeting API Health", False, str(e))

    async def test_create_manual_target(self):
        """Test creating a manual trading target"""
        try:
            target_data = {
                "token_mint": TestConfig.TEST_TOKENS[2],  # BONK
                "action": "BUY",
                "amount_sol": 1.0,
                "strategy_type": "manual",
                "confidence": 0.8,
                "risk_score": 0.3,
                "expected_return": 0.1,
                "priority": "high",
                "max_slippage_bps": 500,
                "ttl_seconds": 60
            }

            async with self.http_session.post(
                f"{TestConfig.HEALTH_API_URL}/api/targeting/manual",
                json=target_data
            ) as resp:
                data = await resp.json()

                assert resp.status == 201
                assert "target_id" in data
                assert "success" in data
                assert data["success"] is True

                target_id = data["target_id"]
                self._log_test_result("Create Manual Target", True, f"Target ID: {target_id}")

                return target_id

        except Exception as e:
            self._log_test_result("Create Manual Target", False, str(e))
            return None

    async def test_get_target_status(self, target_id: str):
        """Test getting target status"""
        if not target_id:
            self._log_test_result("Get Target Status", False, "No target ID provided")
            return

        try:
            async with self.http_session.get(
                f"{TestConfig.HEALTH_API_URL}/api/targeting/status/{target_id}"
            ) as resp:
                data = await resp.json()

                assert resp.status == 200
                assert "target_id" in data
                assert "status" in data

                self._log_test_result(
                    "Get Target Status",
                    True,
                    f"Status: {data['status']}, Queue: {data.get('in_queue', False)}"
                )

        except Exception as e:
            self._log_test_result("Get Target Status", False, str(e))

    async def test_bulk_targets(self):
        """Test creating multiple targets in bulk"""
        try:
            bulk_data = {
                "targets": [
                    {
                        "token_mint": TestConfig.TEST_TOKENS[0],  # SOL
                        "action": "FLASH_LOAN",
                        "amount_sol": 5.0,
                        "strategy_type": "statistical_arbitrage",
                        "flash_loan_amount_sol": 4.75,
                        "priority": "critical"
                    },
                    {
                        "token_mint": TestConfig.TEST_TOKENS[1],  # USDC
                        "action": "HOLD",
                        "amount_sol": 10.0,
                        "strategy_type": "liquidity_mining",
                        "priority": "normal"
                    }
                ],
                "batch_name": "Test Batch",
                "execution_mode": "sequential"
            }

            async with self.http_session.post(
                f"{TestConfig.HEALTH_API_URL}/api/targeting/bulk",
                json=bulk_data
            ) as resp:
                data = await resp.json()

                assert resp.status == 201
                assert isinstance(data, list)
                assert len(data) == 2

                success_count = sum(1 for result in data if result.get("success", False))
                self._log_test_result(
                    "Bulk Targets",
                    True,
                    f"Created {success_count}/2 targets successfully"
                )

        except Exception as e:
            self._log_test_result("Bulk Targets", False, str(e))

    async def test_queue_status(self):
        """Test opportunity queue status"""
        try:
            async with self.http_session.get(
                f"{TestConfig.HEALTH_API_URL}/api/targeting/queue?limit=10"
            ) as resp:
                data = await resp.json()

                assert resp.status == 200
                assert "total_queue_size" in data
                assert "opportunities" in data

                queue_size = data["total_queue_size"]
                manual_targets = data.get("manual_targets_in_page", 0)

                self._log_test_result(
                    "Queue Status",
                    True,
                    f"Queue size: {queue_size}, Manual targets: {manual_targets}"
                )

        except Exception as e:
            self._log_test_result("Queue Status", False, str(e))

    # ============================================================================
    # Integration Tests
    # ============================================================================

    async def test_opportunity_queue_flow(self):
        """Test complete opportunity queue flow"""
        try:
            # Create a test opportunity directly in Redis
            opportunity_id = f"test_{uuid.uuid4().hex[:8]}"
            opportunity = {
                "id": opportunity_id,
                "strategy_type": "test_manual",
                "token": TestConfig.TEST_TOKENS[2],
                "confidence": 0.9,
                "expected_return": 0.15,
                "risk_score": 0.2,
                "required_capital": 2.0,
                "flash_loan_amount": 1.9,
                "timestamp": int(time.time()),
                "ttl_seconds": 60,
                "metadata": {
                    "manual_target": True,
                    "opportunity_type": "test_integration"
                }
            }

            # Add to opportunity queue with high score
            score = 1000.0  # High priority
            await self.redis_client.zadd("opportunity_queue", {json.dumps(opportunity): score})

            # Verify it's in the queue
            queue_size = await self.redis_client.zcard("opportunity_queue")

            # Retrieve from queue
            top_opportunities = await self.redis_client.zrevrange("opportunity_queue", 0, 0)

            assert queue_size >= 1
            assert len(top_opportunities) > 0

            retrieved = json.loads(top_opportunities[0])
            assert retrieved["id"] == opportunity_id

            self._log_test_result(
                "Opportunity Queue Flow",
                True,
                f"Added and retrieved opportunity {opportunity_id}"
            )

            # Clean up
            await self.redis_client.zrem("opportunity_queue", top_opportunities[0])

        except Exception as e:
            self._log_test_result("Opportunity Queue Flow", False, str(e))

    async def test_json_message_format(self):
        """Test JSON message format consistency across components"""
        try:
            # Test manual target message format
            target_data = {
                "token_mint": TestConfig.TEST_TOKENS[0],
                "action": "BUY",
                "amount_sol": 1.0,
                "strategy_type": "test_format",
                "confidence": 0.85,
                "risk_score": 0.25,
                "expected_return": 0.12,
                "max_slippage_bps": 300,
                "ttl_seconds": 60,
                "priority": "normal"
            }

            # Create target and verify response format
            async with self.http_session.post(
                f"{TestConfig.HEALTH_API_URL}/api/targeting/manual",
                json=target_data
            ) as resp:
                response_data = await resp.json()

                # Verify response has expected fields
                required_fields = ["success", "target_id", "message", "timestamp"]
                for field in required_fields:
                    assert field in response_data

                # Verify JSON can be parsed back
                assert isinstance(json.loads(json.dumps(response_data)), dict)

                # Check queue for consistent format
                queue_data = await self.redis_client.zrange("opportunity_queue", 0, -1)
                if queue_data:
                    for item in queue_data:
                        opportunity = json.loads(item)
                        required_opportunity_fields = [
                            "id", "strategy_type", "token", "confidence",
                            "expected_return", "risk_score", "required_capital",
                            "flash_loan_amount", "timestamp", "ttl_seconds", "metadata"
                        ]
                        for field in required_opportunity_fields:
                            assert field in opportunity

                self._log_test_result(
                    "JSON Message Format",
                    True,
                    "All components use consistent JSON format"
                )

        except Exception as e:
            self._log_test_result("JSON Message Format", False, str(e))

    async def test_redis_operations(self):
        """Test Redis operations used by the system"""
        try:
            # Test sorted set operations (opportunity queue)
            test_key = f"test_queue_{uuid.uuid4().hex[:8]}"

            # Add test opportunities
            opportunities = [
                (json.dumps({"id": "test1", "score": 100}), 100.0),
                (json.dumps({"id": "test2", "score": 200}), 200.0),
                (json.dumps({"id": "test3", "score": 150}), 150.0),
            ]

            await self.redis_client.zadd(test_key, dict(opportunities))

            # Test ZPOPMAX (highest score first)
            top = await self.redis_client.zpopmax(test_key, 1)
            assert len(top) > 0
            assert json.loads(top[0][0])["id"] == "test2"  # Highest score

            # Clean remaining
            await self.redis_client.delete(test_key)

            # Test hash operations (capital reservations)
            reservation_key = f"test_reservation_{uuid.uuid4().hex[:8]}"
            reservation_data = {
                "opportunity_id": "test123",
                "allocated_capital": "5.0",
                "flash_loan_amount": "4.75",
                "timestamp": str(int(time.time())),
                "ttl": "300"
            }

            await self.redis_client.hset(reservation_key, reservation_data)
            await self.redis_client.expire(reservation_key, 60)

            # Verify reservation
            stored_data = await self.redis_client.hgetall(reservation_key)
            assert stored_data["opportunity_id"] == "test123"

            # Clean up
            await self.redis_client.delete(reservation_key)

            self._log_test_result(
                "Redis Operations",
                True,
                "Sorted set and hash operations working correctly"
            )

        except Exception as e:
            self._log_test_result("Redis Operations", False, str(e))

    # ============================================================================
    # Performance Tests
    # ============================================================================

    async def test_api_response_times(self):
        """Test API response times"""
        try:
            start_time = time.time()

            # Test health endpoint
            async with self.http_session.get(f"{TestConfig.HEALTH_API_URL}/health") as resp:
                health_time = time.time() - start_time
                assert resp.status == 200

            # Test queue status
            start_time = time.time()
            async with self.http_session.get(f"{TestConfig.HEALTH_API_URL}/api/targeting/queue") as resp:
                queue_time = time.time() - start_time
                assert resp.status == 200

            # Test simple target creation
            target_data = {
                "token_mint": TestConfig.TEST_TOKENS[1],
                "action": "HOLD",
                "amount_sol": 1.0,
                "strategy_type": "performance_test"
            }

            start_time = time.time()
            async with self.http_session.post(
                f"{TestConfig.HEALTH_API_URL}/api/targeting/manual",
                json=target_data
            ) as resp:
                create_time = time.time() - start_time
                assert resp.status == 201

            max_response_time = 2.0  # 2 seconds max
            all_times = [health_time, queue_time, create_time]

            if all(t < max_response_time for t in all_times):
                self._log_test_result(
                    "API Response Times",
                    True,
                    f"Health: {health_time:.3f}s, Queue: {queue_time:.3f}s, Create: {create_time:.3f}s"
                )
            else:
                slow_times = [f"{t:.3f}s" for t in all_times if t >= max_response_time]
                self._log_test_result(
                    "API Response Times",
                    False,
                    f"Slow responses: {', '.join(slow_times)} (threshold: {max_response_time}s)"
                )

        except Exception as e:
            self._log_test_result("API Response Times", False, str(e))

    # ============================================================================
    # Test Runner
    # ============================================================================

    async def run_all_tests(self):
        """Run all integration tests"""
        print("🚀 Starting End-to-End Integration Tests")
        print("=" * 60)

        try:
            await self.setup()

            # Run tests in logical order
            tests = [
                # Health checks
                self.test_manual_targeting_api_health,

                # Manual Targeting API
                self.test_create_manual_target,
                self.test_get_target_status,
                self.test_bulk_targets,
                self.test_queue_status,

                # Integration tests
                self.test_opportunity_queue_flow,
                self.test_json_message_format,
                self.test_redis_operations,

                # Performance tests
                self.test_api_response_times,
            ]

            for test_func in tests:
                try:
                    await test_func()
                except Exception as e:
                    self._log_test_result(test_func.__name__, False, f"Test failed with exception: {e}")

                # Small delay between tests
                await asyncio.sleep(0.5)

            await self.teardown()

        except Exception as e:
            print(f"❌ Test suite failed: {e}")

        finally:
            self._print_summary()

    def _print_summary(self):
        """Print test summary"""
        print("\n" + "=" * 60)
        print("📊 TEST SUMMARY")
        print("=" * 60)

        total_tests = len(self.test_results)
        passed_tests = sum(1 for r in self.test_results if r["success"])
        failed_tests = total_tests - passed_tests

        print(f"Total Tests: {total_tests}")
        print(f"✅ Passed: {passed_tests}")
        print(f"❌ Failed: {failed_tests}")
        print(f"Success Rate: {(passed_tests/total_tests)*100:.1f}%")

        if failed_tests > 0:
            print("\n❌ Failed Tests:")
            for result in self.test_results:
                if not result["success"]:
                    print(f"   • {result['test_name']}: {result['details']}")

        print("\n" + "=" * 60)

# ============================================================================
# Main Test Execution
# ============================================================================

async def main():
    """Main test execution function"""
    test_suite = IntegrationTestSuite()
    await test_suite.run_all_tests()

if __name__ == "__main__":
    print("🧪 MojoRust End-to-End Integration Test Suite")
    print("This test suite validates the complete trading system integration")
    print("Make sure all services are running before executing tests")
    print()

    # Check if required services are available
    try:
        import redis.asyncio as redis
        redis_client = redis.from_url('redis://localhost:6379')
        await redis_client.ping()
        await redis_client.close()
        print("✅ Redis is available")
    except:
        print("❌ Redis is not available. Please start Redis/DragonflyDB.")
        sys.exit(1)

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get('http://localhost:8082/health') as resp:
                if resp.status == 200:
                    print("✅ Health API is available")
                else:
                    raise Exception("Health API returned non-200 status")
    except:
        print("❌ Health API is not available. Please start the Health API service.")
        print("   Run: cd python && python health_api.py")
        sys.exit(1)

    print("✅ All required services are available")
    print()

    # Run tests
    asyncio.run(main())