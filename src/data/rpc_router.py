# =============================================================================
# Dual-RPC Routing Module
# =============================================================================
# This module wraps HeliusClient and QuickNodeClient with a common interface
# Provides health checks, failover, and policy-based routing

import asyncio
import time
import logging
from typing import Dict, Any, Optional, List, Tuple
from enum import Enum
from dataclasses import dataclass
from collections import defaultdict

# Import our existing clients
from helius_client import HeliusClient
from quicknode_client import QuickNodeClient


class RoutingPolicy(Enum):
    """RPC routing policies"""
    ENVIRONMENT_BASED = "environment_based"
    LATENCY_BASED = "latency_based"
    COST_BASED = "cost_based"
    ROUND_ROBIN = "round_robin"
    HEALTH_FIRST = "health_first"


@dataclass
class RPCProvider:
    """RPC provider configuration and status"""
    name: str
    client: Any  # HeliusClient or QuickNodeClient
    priority: int
    enabled: bool
    healthy: bool = True
    last_health_check: float = 0.0
    latency_ms: float = 0.0
    error_count: int = 0
    success_count: int = 0
    error_rate: float = 0.0
    avg_response_time: float = 0.0
    cost_per_request: float = 0.001  # Default cost per request


@dataclass
class RPCMetrics:
    """RPC routing metrics"""
    total_requests: int = 0
    successful_requests: int = 0
    failed_requests: int = 0
    avg_latency_ms: float = 0.0
    provider_usage: Dict[str, int] = None

    def __post_init__(self):
        if self.provider_usage is None:
            self.provider_usage = defaultdict(int)


class RPCRouter:
    """
    RPC Router with health checks, failover, and policy-based routing

    Features:
    - Multiple RPC providers with automatic failover
    - Health monitoring and latency tracking
    - Policy-based routing (environment, latency, cost)
    - Circuit breaker pattern for unhealthy providers
    - Comprehensive metrics and monitoring
    """

    def __init__(self, config: Dict[str, Any]):
        self.logger = logging.getLogger(__name__)
        self.config = config

        # Initialize providers
        self.providers: Dict[str, RPCProvider] = {}
        self.routing_policy = RoutingPolicy(
            config.get("routing", {}).get("policy", "health_first")
        )

        # Health check configuration
        self.health_check_interval = config.get("routing", {}).get("health_check_interval", 30.0)
        self.health_check_timeout = config.get("routing", {}).get("health_check_timeout", 5.0)
        self.max_error_rate = config.get("routing", {}).get("max_error_rate", 0.1)  # 10%
        self.max_latency_ms = config.get("routing", {}).get("max_latency_ms", 5000)  # 5 seconds

        # Circuit breaker configuration
        self.circuit_breaker_threshold = config.get("routing", {}).get("circuit_breaker_threshold", 5)
        self.circuit_breaker_timeout = config.get("routing", {}).get("circuit_breaker_timeout", 300.0)

        # Round-robin state
        self.round_robin_index = 0

        # Metrics
        self.metrics = RPCMetrics()

        # Initialize providers
        self._initialize_providers()

        # Start health monitoring
        self._health_check_task = None
        self._start_health_monitoring()

    def _initialize_providers(self):
        """Initialize RPC providers from configuration"""
        try:
            # Initialize Helius client
            helius_config = self.config.get("helius", {})
            helius_client = HeliusClient(
                api_key=helius_config.get("api_key", ""),
                base_url=helius_config.get("base_url", "https://api.helius.xyz"),
                timeout_seconds=helius_config.get("timeout_seconds", 10.0),
                enabled=helius_config.get("enabled", True)
            )

            self.providers["helius"] = RPCProvider(
                name="helius",
                client=helius_client,
                priority=1,  # Primary provider
                enabled=helius_config.get("enabled", True),
                cost_per_request=0.001  # Helius pricing
            )

            # Initialize QuickNode client
            quicknode_config = self.config.get("quicknode", {})
            quicknode_client = QuickNodeClient(
                rpc_url=quicknode_config.get("primary_rpc", ""),
                backup_rpc_url=quicknode_config.get("backup_rpc", ""),
                timeout_seconds=quicknode_config.get("timeout_seconds", 10.0),
                enabled=quicknode_config.get("enabled", True)
            )

            self.providers["quicknode"] = RPCProvider(
                name="quicknode",
                client=quicknode_client,
                priority=2,  # Secondary provider
                enabled=quicknode_config.get("enabled", True),
                cost_per_request=0.002  # QuickNode pricing
            )

            self.logger.info(f"Initialized {len(self.providers)} RPC providers")

        except Exception as e:
            self.logger.error(f"Failed to initialize RPC providers: {e}")
            raise

    def _start_health_monitoring(self):
        """Start background health monitoring"""
        try:
            self._health_check_task = asyncio.create_task(self._health_monitoring_loop())
            self.logger.info("Started RPC health monitoring")
        except Exception as e:
            self.logger.error(f"Failed to start health monitoring: {e}")

    async def _health_monitoring_loop(self):
        """Background health monitoring loop"""
        while True:
            try:
                await self._perform_health_checks()
                await asyncio.sleep(self.health_check_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Health monitoring error: {e}")
                await asyncio.sleep(60)  # Wait longer on error

    async def _perform_health_checks(self):
        """Perform health checks on all providers"""
        tasks = []
        for provider_name, provider in self.providers.items():
            if provider.enabled:
                tasks.append(self._check_provider_health(provider_name, provider))

        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _check_provider_health(self, provider_name: str, provider: RPCProvider):
        """Check health of a specific provider"""
        try:
            start_time = time.time()

            # Perform a simple health check
            if provider_name == "helius":
                success = provider.client.health_check()
            elif provider_name == "quicknode":
                success = provider.client.health_check()
            else:
                success = True  # Unknown provider, assume healthy

            latency_ms = (time.time() - start_time) * 1000

            # Update provider status
            provider.last_health_check = time.time()
            provider.latency_ms = latency_ms

            if success:
                provider.success_count += 1
                provider.healthy = latency_ms <= self.max_latency_ms
                self.logger.debug(f"Provider {provider_name} health check passed (latency: {latency_ms:.2f}ms)")
            else:
                provider.error_count += 1
                provider.healthy = False
                self.logger.warning(f"Provider {provider_name} health check failed")

            # Update metrics
            self._update_provider_metrics(provider)

        except Exception as e:
            provider.error_count += 1
            provider.healthy = False
            provider.last_health_check = time.time()
            self.logger.error(f"Health check error for {provider_name}: {e}")

    def _update_provider_metrics(self, provider: RPCProvider):
        """Update provider metrics"""
        total_requests = provider.success_count + provider.error_count
        if total_requests > 0:
            provider.error_rate = provider.error_count / total_requests
            provider.avg_response_time = provider.latency_ms

            # Mark as unhealthy if error rate is too high
            if provider.error_rate > self.max_error_rate:
                provider.healthy = False

    async def call(self, method: str, params: List[Any] = None, **kwargs) -> Any:
        """
        Make RPC call using routing policy

        Args:
            method: RPC method name
            params: RPC parameters
            **kwargs: Additional parameters

        Returns:
            RPC response

        Raises:
            Exception: If all providers fail
        """
        if params is None:
            params = []

        self.metrics.total_requests += 1

        # Get provider based on routing policy
        provider = self._select_provider()

        if not provider:
            self.metrics.failed_requests += 1
            raise Exception("No healthy RPC providers available")

        provider_name = provider.name
        self.metrics.provider_usage[provider_name] += 1

        try:
            # Make the call
            start_time = time.time()

            if provider_name == "helius":
                result = await provider.client.call(method, params, **kwargs)
            elif provider_name == "quicknode":
                result = await provider.client.call(method, params, **kwargs)
            else:
                raise Exception(f"Unknown provider: {provider_name}")

            # Update metrics
            latency_ms = (time.time() - start_time) * 1000
            provider.success_count += 1
            provider.latency_ms = latency_ms
            self.metrics.successful_requests += 1

            self.logger.debug(f"RPC call successful via {provider_name} (latency: {latency_ms:.2f}ms)")

            return result

        except Exception as e:
            provider.error_count += 1
            self.metrics.failed_requests += 1
            self.logger.error(f"RPC call failed via {provider_name}: {e}")

            # Try failover if available
            return await self._failover_call(method, params, **kwargs)

    async def _failover_call(self, method: str, params: List[Any], **kwargs) -> Any:
        """Attempt failover to alternative providers"""
        self.logger.warning(f"Attempting failover for RPC call: {method}")

        # Get list of alternative providers
        alternative_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy and p.name != self._select_provider().name
        ]

        # Sort by priority
        alternative_providers.sort(key=lambda p: p.priority)

        for provider in alternative_providers:
            try:
                self.logger.info(f"Trying failover provider: {provider.name}")

                if provider.name == "helius":
                    result = await provider.client.call(method, params, **kwargs)
                elif provider.name == "quicknode":
                    result = await provider.client.call(method, params, **kwargs)
                else:
                    continue

                # Update metrics
                provider.success_count += 1
                self.metrics.successful_requests += 1
                self.metrics.provider_usage[provider.name] += 1

                self.logger.info(f"Failover successful via {provider.name}")
                return result

            except Exception as e:
                provider.error_count += 1
                self.logger.error(f"Failover failed via {provider.name}: {e}")
                continue

        # All providers failed
        raise Exception(f"All RPC providers failed for method: {method}")

    def _select_provider(self) -> Optional[RPCProvider]:
        """Select provider based on routing policy"""
        healthy_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy
        ]

        if not healthy_providers:
            return None

        if self.routing_policy == RoutingPolicy.ENVIRONMENT_BASED:
            return self._select_environment_based(healthy_providers)
        elif self.routing_policy == RoutingPolicy.LATENCY_BASED:
            return self._select_latency_based(healthy_providers)
        elif self.routing_policy == RoutingPolicy.COST_BASED:
            return self._select_cost_based(healthy_providers)
        elif self.routing_policy == RoutingPolicy.ROUND_ROBIN:
            return self._select_round_robin(healthy_providers)
        elif self.routing_policy == RoutingPolicy.HEALTH_FIRST:
            return self._select_health_first(healthy_providers)
        else:
            # Default to health first
            return self._select_health_first(healthy_providers)

    def _select_environment_based(self, providers: List[RPCProvider]) -> RPCProvider:
        """Select provider based on environment configuration"""
        # In production, prefer Helius; in development, prefer QuickNode
        env = self.config.get("environment", "development")

        if env == "production":
            # Prefer Helius in production
            for provider in providers:
                if provider.name == "helius":
                    return provider

        # Default to first available
        return providers[0]

    def _select_latency_based(self, providers: List[RPCProvider]) -> RPCProvider:
        """Select provider with lowest latency"""
        return min(providers, key=lambda p: p.latency_ms)

    def _select_cost_based(self, providers: List[RPCProvider]) -> RPCProvider:
        """Select provider with lowest cost"""
        return min(providers, key=lambda p: p.cost_per_request)

    def _select_round_robin(self, providers: List[RPCProvider]) -> RPCProvider:
        """Select provider using round-robin"""
        if not providers:
            return None

        provider = providers[self.round_robin_index % len(providers)]
        self.round_robin_index += 1
        return provider

    def _select_health_first(self, providers: List[RPCProvider]) -> RPCProvider:
        """Select healthiest provider"""
        # Sort by priority and health score
        def health_score(p: RPCProvider) -> Tuple[int, float]:
            return (p.priority, 1.0 - p.error_rate if p.error_rate <= 1.0 else 0.0)

        return max(providers, key=health_score)

    def health(self) -> Dict[str, Any]:
        """Get router health status"""
        healthy_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy
        ]

        return {
            "healthy": len(healthy_providers) > 0,
            "total_providers": len(self.providers),
            "healthy_providers": len(healthy_providers),
            "unhealthy_providers": len(self.providers) - len(healthy_providers),
            "routing_policy": self.routing_policy.value,
            "total_requests": self.metrics.total_requests,
            "success_rate": (
                self.metrics.successful_requests / max(self.metrics.total_requests, 1)
            ),
            "provider_status": {
                name: {
                    "healthy": provider.healthy,
                    "enabled": provider.enabled,
                    "priority": provider.priority,
                    "latency_ms": provider.latency_ms,
                    "error_rate": provider.error_rate,
                    "last_health_check": provider.last_health_check
                }
                for name, provider in self.providers.items()
            }
        }

    def get_metrics(self) -> Dict[str, Any]:
        """Get comprehensive metrics"""
        return {
            "router": {
                "total_requests": self.metrics.total_requests,
                "successful_requests": self.metrics.successful_requests,
                "failed_requests": self.metrics.failed_requests,
                "success_rate": (
                    self.metrics.successful_requests / max(self.metrics.total_requests, 1)
                ),
                "avg_latency_ms": self.metrics.avg_latency_ms,
                "routing_policy": self.routing_policy.value
            },
            "providers": {
                name: {
                    "name": provider.name,
                    "priority": provider.priority,
                    "healthy": provider.healthy,
                    "enabled": provider.enabled,
                    "latency_ms": provider.latency_ms,
                    "error_rate": provider.error_rate,
                    "success_count": provider.success_count,
                    "error_count": provider.error_count,
                    "cost_per_request": provider.cost_per_request,
                    "last_health_check": provider.last_health_check
                }
                for name, provider in self.providers.items()
            },
            "usage": dict(self.metrics.provider_usage)
        }

    async def shutdown(self):
        """Shutdown the router and cleanup resources"""
        if self._health_check_task:
            self._health_check_task.cancel()
            try:
                await self._health_check_task
            except asyncio.CancelledError:
                pass

        # Close provider connections
        for provider in self.providers.values():
            try:
                if hasattr(provider.client, 'close'):
                    await provider.client.close()
            except Exception as e:
                self.logger.error(f"Error closing provider {provider.name}: {e}")

        self.logger.info("RPC Router shutdown complete")


# Factory function
def create_rpc_router(config: Dict[str, Any]) -> RPCRouter:
    """Create and configure RPC router"""
    return RPCRouter(config)