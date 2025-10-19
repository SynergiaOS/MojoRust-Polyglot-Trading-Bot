"""
End-to-End Integration Tests for MojoRust Trading System

Tests the complete pipeline from opportunity detection to execution.
Covers manual targeting API, opportunity queue, and orchestrator coordination.
"""

import pytest
import asyncio
import json
import time
import aiohttp
import redis.asyncio as redis
from typing import Dict, Any

# Test configuration
TEST_CONFIG = {
    "redis_url": "redis://localhost:6379",
    "health_api_url": "http://localhost:8082",
    "data_consumer_url": "http://localhost:9191",
    "test_timeout": 30,
}

class TestOrchestratorIntegration:
    """Integration tests for the complete orchestrator system"""

    @pytest.fixture
    async def redis_client(self):
        """Create Redis client for testing"""
        client = redis.from_url(TEST_CONFIG["redis_url"])
        try:
            # Test connection
            await client.ping()
            yield client
        finally:
            await client.close()

    @pytest.fixture
    async def http_client(self):
        """Create HTTP client for testing APIs"""
        async with aiohttp.ClientSession() as session:
            yield session

    async def setup_method(self):
        """Setup before each test"""
        # Wait for services to be ready
        await self._wait_for_services()

    async def _wait_for_services(self):
        """Wait for all services to be ready"""
        start_time = time.time()

        while time.time() - start_time < TEST_CONFIG["test_timeout"]:
            try:
                async with aiohttp.ClientSession() as session:
                    # Check health API
                    async with session.get(f"{TEST_CONFIG['health_api_url']}/health", timeout=5) as resp:
                        if resp.status == 200:
                            # Check data consumer
                            async with session.get(f"{TEST_CONFIG['data_consumer_url']}/health", timeout=5) as resp2:
                                if resp2.status == 200:
                                    return True
            except Exception:
                pass

            await asyncio.sleep(1)

        raise Exception("Services not ready within timeout")

    @pytest.mark.asyncio
    async def test_manual_targeting_api_endpoints(self, http_client: aiohttp.ClientSession):
        """Test manual targeting API endpoints"""
        # Test health endpoint
        async with http_client.get(f"{TEST_CONFIG['health_api_url']}/health") as resp:
            assert resp.status == 200
            health_data = await resp.json()
            assert health_data["status"] in ["healthy", "degraded"]

        # Test root endpoint documentation
        async with http_client.get(f"{TEST_CONFIG['health_api_url']}/") as resp:
            assert resp.status == 200
            docs_data = await resp.json()
            assert "manual_targeting" in docs_data["endpoints"]
            assert "create_target" in docs_data["endpoints"]["manual_targeting"]

    @pytest.mark.asyncio
    async def test_manual_target_creation(self, http_client: aiohttp.ClientSession, redis_client):
        """Test creating manual trading targets"""
        target_data = {
            "token_mint": "So11111111111111111111111111111111111111112",
            "action": "BUY",
            "amount_sol": 1.0,
            "strategy_type": "manual",
            "confidence": 0.8,
            "risk_score": 0.3,
            "expected_return": 0.05,
            "flash_loan_amount": 0.95,
            "max_slippage_bps": 500,
            "ttl_seconds": 60,
            "priority": "high",
            "metadata": {
                "test_target": True,
                "source": "integration_test"
            }
        }

        # Create manual target
        async with http_client.post(
            f"{TEST_CONFIG['health_api_url']}/api/targeting/manual",
            json=target_data
        ) as resp:
            assert resp.status == 201
            response_data = await resp.json()
            assert response_data["success"] is True
            assert "target_id" in response_data

            target_id = response_data["target_id"]
            print(f"✅ Created manual target: {target_id}")

        # Verify target appears in opportunity queue
        await asyncio.sleep(1)  # Allow for processing
        queue_data = await redis_client.zrevrange("opportunity_queue", 0, -1, withscores=True)

        found_target = False
        for opportunity_json, score in queue_data:
            try:
                opportunity = json.loads(opportunity_json)
                if opportunity.get("id") == target_id:
                    found_target = True
                    assert opportunity["strategy_type"] == "manual"
                    assert opportunity["token"] == target_data["token_mint"]
                    assert opportunity["required_capital"] == target_data["amount_sol"]
                    print(f"✅ Found target in queue with score: {score}")
                    break
            except (json.JSONDecodeError, KeyError):
                continue

        assert found_target, "Target not found in opportunity queue"

        # Test target status endpoint
        async with http_client.get(f"{TEST_CONFIG['health_api_url']}/api/targeting/status/{target_id}") as resp:
            assert resp.status == 200
            status_data = await resp.json()
            assert status_data["target_id"] == target_id
            assert status_data["status"] in ["queued", "processed"]

    @pytest.mark.asyncio
    async def test_bulk_target_creation(self, http_client: aiohttp.ClientSession, redis_client):
        """Test creating multiple manual targets in bulk"""
        bulk_data = {
            "targets": [
                {
                    "token_mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                    "action": "BUY",
                    "amount_sol": 0.5,
                    "strategy_type": "manual",
                    "confidence": 0.9,
                    "risk_score": 0.2,
                    "expected_return": 0.03,
                    "priority": "normal"
                },
                {
                    "token_mint": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
                    "action": "FLASH_LOAN",
                    "amount_sol": 2.0,
                    "strategy_type": "manual",
                    "confidence": 0.7,
                    "risk_score": 0.4,
                    "expected_return": 0.08,
                    "priority": "high"
                }
            ],
            "batch_name": "test_integration_batch",
            "execution_mode": "sequential"
        }

        # Create bulk targets
        async with http_client.post(
            f"{TEST_CONFIG['health_api_url']}/api/targeting/bulk",
            json=bulk_data
        ) as resp:
            assert resp.status == 201
            responses = await resp.json()
            assert len(responses) == 2

            target_ids = []
            for i, response in enumerate(responses):
                assert response["success"] is True
                assert "target_id" in response
                target_ids.append(response["target_id"])
                print(f"✅ Created bulk target {i+1}: {response['target_id']}")

        # Verify targets appear in queue
        await asyncio.sleep(2)  # Allow for processing
        queue_data = await redis_client.zrevrange("opportunity_queue", 0, 4, withscores=True)

        found_targets = 0
        for opportunity_json, score in queue_data:
            try:
                opportunity = json.loads(opportunity_json)
                if opportunity.get("id") in target_ids:
                    found_targets += 1
                    print(f"✅ Found bulk target in queue: {opportunity['id']} (score: {score})")
            except (json.JSONDecodeError, KeyError):
                continue

        assert found_targets == 2, f"Expected 2 targets in queue, found {found_targets}"

    @pytest.mark.asyncio
    async def test_opportunity_queue_status(self, http_client: aiohttp.ClientSession, redis_client):
        """Test opportunity queue monitoring endpoint"""
        # Add some test opportunities to queue
        test_opportunities = [
            {
                "id": "test_opportunity_1",
                "strategy_type": "manual",
                "token": "TEST_TOKEN_1",
                "confidence": 0.8,
                "expected_return": 0.05,
                "risk_score": 0.3,
                "required_capital": 1.0,
                "timestamp": int(time.time()),
                "ttl_seconds": 300,
                "metadata": {"test": True}
            },
            {
                "id": "test_opportunity_2",
                "strategy_type": "sniper_momentum",
                "token": "TEST_TOKEN_2",
                "confidence": 0.9,
                "expected_return": 0.08,
                "risk_score": 0.2,
                "required_capital": 0.5,
                "timestamp": int(time.time()),
                "ttl_seconds": 300,
                "metadata": {"test": True}
            }
        ]

        # Add opportunities to queue with different scores
        for i, opportunity in enumerate(test_opportunities):
            score = 100.0 - i * 10.0  # Different scores for ordering
            await redis_client.zadd("opportunity_queue", {json.dumps(opportunity): score})

        # Test queue status endpoint
        async with http_client.get(f"{TEST_CONFIG['health_api_url']}/api/targeting/queue?limit=10") as resp:
            assert resp.status == 200
            queue_status = await resp.json()

            assert "total_queue_size" in queue_status
            assert "opportunities" in queue_status
            assert len(queue_status["opportunities"]) >= 2

            # Check that opportunities are ordered by score (descending)
            opportunities = queue_status["opportunities"]
            if len(opportunities) >= 2:
                assert opportunities[0]["score"] >= opportunities[1]["score"]

            # Check manual target detection
            manual_count = queue_status.get("manual_targets_in_page", 0)
            assert manual_count >= 1  # At least one manual target should be present

            print(f"✅ Queue status: {queue_status['total_queue_size']} total opportunities")

    @pytest.mark.asyncio
    async def test_target_cancellation(self, http_client: aiohttp.ClientSession, redis_client):
        """Test canceling manual targets"""
        # Create a target first
        target_data = {
            "token_mint": "TEST_CANCEL_TOKEN",
            "action": "BUY",
            "amount_sol": 1.0,
            "strategy_type": "manual",
            "confidence": 0.8,
            "risk_score": 0.3,
            "ttl_seconds": 300,
            "priority": "normal"
        }

        async with http_client.post(
            f"{TEST_CONFIG['health_api_url']}/api/targeting/manual",
            json=target_data
        ) as resp:
            assert resp.status == 201
            response_data = await resp.json()
            target_id = response_data["target_id"]

        # Verify target is in queue
        await asyncio.sleep(1)
        queue_data_before = await redis_client.zrevrange("opportunity_queue", 0, -1)
        target_in_queue_before = any(target_id in json.loads(op)["id"] for op in queue_data_before if op)
        assert target_in_queue_before

        # Cancel the target
        async with http_client.delete(f"{TEST_CONFIG['health_api_url']}/api/targeting/manual/{target_id}") as resp:
            assert resp.status == 200
            cancel_response = await resp.json()
            assert cancel_response["success"] is True
            assert cancel_response["removed_from_queue"] is True

        # Verify target is removed from queue
        queue_data_after = await redis_client.zrevrange("opportunity_queue", 0, -1)
        target_in_queue_after = any(target_id in json.loads(op)["id"] for op in queue_data_after if op)
        assert not target_in_queue_after

        print(f"✅ Successfully cancelled target: {target_id}")

    @pytest.mark.asyncio
    async def test_data_consumer_integration(self, http_client: aiohttp.ClientSession):
        """Test data consumer health and metrics"""
        # Test data consumer health
        async with http_client.get(f"{TEST_CONFIG['data_consumer_url']}/health") as resp:
            assert resp.status == 200
            health_data = await resp.json()
            assert health_data["status"] in ["healthy", "degraded"]
            assert "uptime" in health_data

        # Test data consumer metrics
        async with http_client.get(f"{TEST_CONFIG['data_consumer_url']}/metrics") as resp:
            assert resp.status == 200
            metrics_data = await resp.text
            assert "http_requests_total" in metrics_data  # Prometheus metrics format

        print("✅ Data consumer integration verified")

    @pytest.mark.asyncio
    async def test_complete_pipeline_flow(self, http_client: aiohttp.ClientSession, redis_client):
        """Test complete flow from target creation to queue processing"""
        # Create high-priority manual target
        target_data = {
            "token_mint": "PIPELINE_TEST_TOKEN",
            "action": "FLASH_LOAN",
            "amount_sol": 5.0,
            "strategy_type": "manual",
            "confidence": 0.95,
            "risk_score": 0.1,
            "expected_return": 0.15,
            "flash_loan_amount": 4.75,
            "ttl_seconds": 30,
            "priority": "critical",
            "metadata": {
                "pipeline_test": True,
                "source": "integration_test"
            }
        }

        # Create target
        async with http_client.post(
            f"{TEST_CONFIG['health_api_url']}/api/targeting/manual",
            json=target_data
        ) as resp:
            assert resp.status == 201
            response_data = await resp.json()
            target_id = response_data["target_id"]

        # Monitor queue for processing
        processed = False
        for _ in range(10):  # Wait up to 10 seconds
            await asyncio.sleep(1)

            # Check if target is still in queue
            queue_data = await redis_client.zrevrange("opportunity_queue", 0, -1, withscores=True)
            target_still_in_queue = any(
                target_id in json.loads(op)["id"]
                for op in queue_data
                if op
            )

            if not target_still_in_queue:
                processed = True
                break

        print(f"✅ Pipeline test completed - target {target_id} processed: {processed}")

        # Verify target status
        async with http_client.get(f"{TEST_CONFIG['health_api_url']}/api/targeting/status/{target_id}") as resp:
            assert resp.status == 200
            status_data = await resp.json()
            # Status could be "processed" if removed from queue, or still "queued"
            assert status_data["status"] in ["queued", "processed", "cancelled"]

    @pytest.mark.asyncio
    async def test_error_handling(self, http_client: aiohttp.ClientSession):
        """Test API error handling"""
        # Test invalid target data
        invalid_target = {
            "token_mint": "invalid_token_address",  # Invalid format
            "action": "INVALID_ACTION",  # Invalid action
            "amount_sol": -1.0,  # Invalid amount
            "confidence": 1.5,  # Invalid confidence
            "risk_score": -0.1  # Invalid risk score
        }

        async with http_client.post(
            f"{TEST_CONFIG['health_api_url']}/api/targeting/manual",
            json=invalid_target
        ) as resp:
            assert resp.status == 400  # Bad Request
            error_data = await resp.json()
            assert "detail" in error_data

        # Test non-existent target
        async with http_client.get(f"{TEST_CONFIG['health_api_url']}/api/targeting/status/non_existent") as resp:
            assert resp.status == 404
            error_data = await resp.json()
            assert "detail" in error_data

        # Test cancelling non-existent target
        async with http_client.delete(f"{TEST_CONFIG['health_api_url']}/api/targeting/manual/non_existent") as resp:
            assert resp.status == 404
            error_data = await resp.json()
            assert "detail" in error_data

        print("✅ Error handling verified")

# Test runner
if __name__ == "__main__":
    import sys

    # Run tests
    print("🚀 Running MojoRust Integration Tests")
    print("=" * 50)

    # Check if services are available
    try:
        import aiohttp
        async with aiohttp.ClientSession() as session:
            async with session.get("http://localhost:8082/health", timeout=5) as resp:
                if resp.status != 200:
                    print("❌ Health API not available. Start services first:")
                    print("   ./scripts/start_orchestrator.sh")
                    sys.exit(1)
    except Exception as e:
        print(f"❌ Cannot connect to services: {e}")
        print("   Start services first: ./scripts/start_orchestrator.sh")
        sys.exit(1)

    print("✅ Services are available")
    print("   Run with: pytest tests/test_orchestrator_integration.py -v")