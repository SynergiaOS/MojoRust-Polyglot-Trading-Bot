#!/usr/bin/env python3
"""
Test suite for RPC Router functionality
"""

import pytest
import asyncio
import time
from unittest.mock import Mock, AsyncMock, patch
from src.data.rpc_router import (
    RPCRouter, RPCProvider, RoutingPolicy, RPCMetrics,
    create_rpc_router
)


class TestRPCProvider:
    """Test RPCProvider dataclass and methods"""

    def test_rpc_provider_creation(self):
        """Test RPCProvider initialization"""
        mock_client = Mock()
        provider = RPCProvider(
            name="test_provider",
            client=mock_client,
            priority=1,
            enabled=True,
            cost_per_request=0.001
        )

        assert provider.name == "test_provider"
        assert provider.client == mock_client
        assert provider.priority == 1
        assert provider.enabled is True
        assert provider.healthy is True  # Default value
        assert provider.cost_per_request == 0.001

    def test_update_metrics(self):
        """Test provider metrics update"""
        provider = RPCProvider(
            name="test",
            client=Mock(),
            priority=1,
            enabled=True
        )

        # Simulate some activity
        provider.success_count = 8
        provider.error_count = 2
        provider.latency_ms = 100.0

        provider._update_provider_metrics()

        assert provider.error_rate == 0.2  # 2/10
        assert provider.avg_response_time == 100.0


class TestRPCRouter:
    """Test RPCRouter functionality"""

    @pytest.fixture
    def mock_config(self):
        """Mock configuration for testing"""
        return {
            "helius": {
                "api_key": "test_key",
                "base_url": "https://api.helius.xyz",
                "timeout_seconds": 10.0,
                "enabled": True
            },
            "quicknode": {
                "primary_rpc": "https://rpc.test.com",
                "backup_rpc": "https://backup.test.com",
                "timeout_seconds": 10.0,
                "enabled": True
            },
            "routing": {
                "policy": "health_first",
                "health_check_interval": 1.0,
                "health_check_timeout": 5.0,
                "max_error_rate": 0.1,
                "max_latency_ms": 1000.0,
                "circuit_breaker_threshold": 5,
                "circuit_breaker_timeout": 60.0
            }
        }

    @pytest.fixture
    def mock_helius_client(self):
        """Mock HeliusClient"""
        client = Mock()
        client.health_check.return_value = True
        client.call = AsyncMock(return_value={"result": "mock_result"})
        return client

    @pytest.fixture
    def mock_quicknode_client(self):
        """Mock QuickNodeClient"""
        client = Mock()
        client.health_check.return_value = True
        client.call = AsyncMock(return_value={"result": "mock_result"})
        return client

    @patch('src.data.rpc_router.HeliusClient')
    @patch('src.data.rpc_router.QuickNodeClient')
    def test_router_initialization(self, mock_qn, mock_helius, mock_config):
        """Test router initialization"""
        mock_helius.return_value = mock_config['helius']
        mock_qn.return_value = mock_config['quicknode']

        router = RPCRouter(mock_config)

        assert router.routing_policy == RoutingPolicy.HEALTH_FIRST
        assert len(router.providers) == 2
        assert "helius" in router.providers
        assert "quicknode" in router.providers
        assert router.providers["helius"].priority == 1
        assert router.providers["quicknode"].priority == 2

    def test_provider_selection_health_first(self, mock_config):
        """Test provider selection with health_first policy"""
        router = RPCRouter(mock_config)
        router.routing_policy = RoutingPolicy.HEALTH_FIRST

        # Mock providers with different health scores
        healthy_provider = RPCProvider("healthy", Mock(), 1, True)
        healthy_provider.error_rate = 0.05
        healthy_provider.priority = 2

        sick_provider = RPCProvider("sick", Mock(), 1, True)
        sick_provider.error_rate = 0.5
        sick_provider.priority = 1

        router.providers = {"healthy": healthy_provider, "sick": sick_provider}

        selected = router._select_provider()
        assert selected.name == "healthy"  # Should pick healthier provider despite higher priority

    def test_provider_selection_latency_based(self, mock_config):
        """Test provider selection with latency_based policy"""
        router = RPCRouter(mock_config)
        router.routing_policy = RoutingPolicy.LATENCY_BASED

        fast_provider = RPCProvider("fast", Mock(), 2, True)
        fast_provider.latency_ms = 50.0

        slow_provider = RPCProvider("slow", Mock(), 1, True)
        slow_provider.latency_ms = 200.0

        router.providers = {"fast": fast_provider, "slow": slow_provider}

        selected = router._select_provider()
        assert selected.name == "fast"

    def test_provider_selection_cost_based(self, mock_config):
        """Test provider selection with cost_based policy"""
        router = RPCRouter(mock_config)
        router.routing_policy = RoutingPolicy.COST_BASED

        cheap_provider = RPCProvider("cheap", Mock(), 2, True)
        cheap_provider.cost_per_request = 0.001

        expensive_provider = RPCProvider("expensive", Mock(), 1, True)
        expensive_provider.cost_per_request = 0.005

        router.providers = {"cheap": cheap_provider, "expensive": expensive_provider}

        selected = router._select_provider()
        assert selected.name == "cheap"

    def test_provider_selection_round_robin(self, mock_config):
        """Test provider selection with round_robin policy"""
        router = RPCRouter(mock_config)
        router.routing_policy = RoutingPolicy.ROUND_ROBIN

        provider1 = RPCProvider("p1", Mock(), 1, True)
        provider2 = RPCProvider("p2", Mock(), 2, True)

        router.providers = {"p1": provider1, "p2": provider2}

        # Test round-robin behavior
        selected1 = router._select_provider()
        selected2 = router._select_provider()
        selected3 = router._select_provider()

        assert selected1.name == "p1"
        assert selected2.name == "p2"
        assert selected3.name == "p1"  # Should wrap around

    @pytest.mark.asyncio
    async def test_successful_rpc_call(self, mock_config, mock_helius_client, mock_quicknode_client):
        """Test successful RPC call with failover"""
        with patch('src.data.rpc_router.HeliusClient', return_value=mock_helius_client), \
             patch('src.data.rpc_router.QuickNodeClient', return_value=mock_quicknode_client):

            router = RPCRouter(mock_config)

            result = await router.call("test_method", ["param1", "param2"])

            assert result == {"result": "mock_result"}
            assert router.metrics.total_requests == 1
            assert router.metrics.successful_requests == 1

    @pytest.mark.asyncio
    async def test_rpc_call_failover(self, mock_config):
        """Test RPC call failover mechanism"""
        # Mock clients
        primary_client = Mock()
        primary_client.call = AsyncMock(side_effect=Exception("Primary failed"))
        primary_client.health_check.return_value = True

        backup_client = Mock()
        backup_client.call = AsyncMock(return_value={"result": "backup_result"})
        backup_client.health_check.return_value = True

        with patch('src.data.rpc_router.HeliusClient', return_value=primary_client), \
             patch('src.data.rpc_router.QuickNodeClient', return_value=backup_client):

            router = RPCRouter(mock_config)

            result = await router.call("test_method", ["param1"])

            assert result == {"result": "backup_result"}
            assert router.metrics.total_requests == 1
            assert router.metrics.successful_requests == 1
            assert router.providers["helius"].error_count == 1
            assert router.providers["quicknode"].success_count == 1

    @pytest.mark.asyncio
    async def test_all_providers_fail(self, mock_config):
        """Test behavior when all providers fail"""
        # Mock failing clients
        failing_client = Mock()
        failing_client.call = AsyncMock(side_effect=Exception("All failed"))
        failing_client.health_check.return_value = True

        with patch('src.data.rpc_router.HeliusClient', return_value=failing_client), \
             patch('src.data.rpc_router.QuickNodeClient', return_value=failing_client):

            router = RPCRouter(mock_config)

            with pytest.raises(Exception, match="All RPC providers failed"):
                await router.call("test_method", ["param1"])

            assert router.metrics.total_requests == 1
            assert router.metrics.failed_requests == 1

    def test_health_status(self, mock_config):
        """Test health status reporting"""
        router = RPCRouter(mock_config)

        # Set up mock providers
        router.providers["helius"].healthy = True
        router.providers["helius"].latency_ms = 100.0
        router.providers["helius"].error_rate = 0.05
        router.providers["quicknode"].healthy = False
        router.providers["quicknode"].latency_ms = 500.0
        router.providers["quicknode"].error_rate = 0.5

        health = router.health()

        assert health["healthy"] is True  # At least one healthy provider
        assert health["total_providers"] == 2
        assert health["healthy_providers"] == 1
        assert health["unhealthy_providers"] == 1
        assert "provider_status" in health
        assert "helius" in health["provider_status"]
        assert "quicknode" in health["provider_status"]

    def test_comprehensive_metrics(self, mock_config):
        """Test comprehensive metrics collection"""
        router = RPCRouter(mock_config)

        # Simulate some activity
        router.metrics.total_requests = 100
        router.metrics.successful_requests = 95
        router.metrics.failed_requests = 5

        # Set up provider metrics
        router.providers["helius"].success_count = 60
        router.providers["helius"].error_count = 5
        router.providers["quicknode"].success_count = 35
        router.providers["quicknode"].error_count = 0

        metrics = router.get_metrics()

        assert "router" in metrics
        assert "providers" in metrics
        assert "usage" in metrics

        router_metrics = metrics["router"]
        assert router_metrics["total_requests"] == 100
        assert router_metrics["success_rate"] == 0.95

        provider_metrics = metrics["providers"]
        assert "helius" in provider_metrics
        assert "quicknode" in provider_metrics
        assert provider_metrics["helius"]["success_count"] == 60
        assert provider_metrics["quicknode"]["error_count"] == 0


class TestFactoryFunction:
    """Test factory function"""

    def test_create_rpc_router(self):
        """Test create_rpc_router factory function"""
        config = {
            "helius": {"api_key": "test", "enabled": True},
            "quicknode": {"primary_rpc": "test", "enabled": True},
            "routing": {"policy": "health_first"}
        }

        with patch('src.data.rpc_router.RPCRouter') as mock_router_class:
            create_rpc_router(config)
            mock_router_class.assert_called_once_with(config)


class TestIntegrationScenarios:
    """Integration test scenarios"""

    @pytest.mark.asyncio
    async def test_circuit_breaker_behavior(self):
        """Test circuit breaker behavior"""
        config = {
            "helius": {"api_key": "test", "enabled": True},
            "quicknode": {"primary_rpc": "test", "enabled": True},
            "routing": {
                "policy": "health_first",
                "circuit_breaker_threshold": 3,
                "max_error_rate": 0.1
            }
        }

        # Mock failing client
        failing_client = Mock()
        failing_client.call = AsyncMock(side_effect=Exception("Service unavailable"))
        failing_client.health_check.return_value = True

        working_client = Mock()
        working_client.call = AsyncMock(return_value={"result": "success"})
        working_client.health_check.return_value = True

        with patch('src.data.rpc_router.HeliusClient', return_value=failing_client), \
             patch('src.data.rpc_router.QuickNodeClient', return_value=working_client):

            router = RPCRouter(config)

            # Make multiple calls to trigger circuit breaker
            for _ in range(5):
                try:
                    await router.call("test_method")
                except:
                    pass

            # Check that the failing provider is marked as unhealthy
            assert not router.providers["helius"].healthy

    @pytest.mark.asyncio
    async def test_health_check_simulation(self):
        """Test health check simulation"""
        config = {
            "helius": {"api_key": "test", "enabled": True},
            "quicknode": {"primary_rpc": "test", "enabled": True},
            "routing": {
                "policy": "health_first",
                "health_check_interval": 0.1,  # Very fast for testing
                "max_latency_ms": 100.0
            }
        }

        # Mock clients with different response times
        fast_client = Mock()
        fast_client.health_check.return_value = True

        slow_client = Mock()
        slow_client.health_check.return_value = True

        with patch('src.data.rpc_router.HeliusClient', return_value=fast_client), \
             patch('src.data.rpc_router.QuickNodeClient', return_value=slow_client):

            router = RPCRouter(config)

            # Manually trigger health check
            await router._check_provider_health("helius", router.providers["helius"])
            await router._check_provider_health("quicknode", router.providers["quicknode"])

            # Both should be healthy (both return True)
            assert router.providers["helius"].healthy
            assert router.providers["quicknode"].healthy


if __name__ == "__main__":
    pytest.main([__file__, "-v"])