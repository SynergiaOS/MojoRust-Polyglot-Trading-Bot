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

# Import our Python async adapters
import sys
import os

# Add data directory to Python path for relative imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'py'))

from helius_adapter import HeliusAdapter
from quicknode_adapter import QuickNodeAdapter


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

    # Bundle-aware routing metrics
    bundle_submissions: int = 0
    bundle_successes: int = 0
    bundle_success_rate: float = 0.0
    shredstream_latency_ms: float = 0.0
    supports_shredstream: bool = False
    supports_lil_jit: bool = False
    priority_fee_api_available: bool = False

    # Enhanced bundle and feature metrics
    bundle_confirmed_count: int = 0
    bundle_pending_count: int = 0
    bundle_failed_count: int = 0
    bundle_avg_confirmation_time_ms: float = 0.0
    shredstream_health_score: float = 0.0  # 0-100 score
    lil_jit_health_score: float = 0.0        # 0-100 score
    priority_fee_response_time_ms: float = 0.0
    webhook_delivery_success_rate: float = 0.0
    organic_transaction_score: float = 0.0
    last_bundle_confirmation: float = 0.0
    last_shredstream_check: float = 0.0
    last_priority_fee_check: float = 0.0

    # Feature-specific health checks
    shredstream_connected: bool = False
    lil_jit_connected: bool = False
    webhooks_configured: bool = False
    priority_fee_active: bool = False


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

        # Bundle-aware routing configuration
        routing_config = config.get("routing", {})
        self.latency_threshold_ms = routing_config.get("latency_threshold_ms", 100)
        self.bundle_success_rate_threshold = routing_config.get("bundle_success_rate_threshold", 0.90)
        self.track_bundle_metrics = routing_config.get("track_bundle_metrics", True)
        self.prefer_shredstream_for_mev = routing_config.get("prefer_shredstream_for_mev", True)

        # Priority fee cache (10-second TTL)
        self.priority_fee_cache: Dict[str, Dict[str, Any]] = {}
        self.priority_fee_cache_ttl = 10.0

        # Metrics
        self.metrics = RPCMetrics()

        # Note: Providers will be initialized asynchronously
        self._initialization_complete = False

        # Start health monitoring
        self._health_check_task = None
        self._start_health_monitoring()

    async def initialize_providers_async(self):
        """Async method to initialize providers - call this after constructor"""
        if not self._initialization_complete:
            await self._initialize_providers()
            self._initialization_complete = True
            self.logger.info("Async provider initialization completed")

    async def _initialize_providers(self):
        """Initialize RPC providers from configuration using async adapters"""
        try:
            # Initialize Helius adapter
            helius_config = self.config.get("helius", {})
            helius_adapter = HeliusAdapter(
                api_key=helius_config.get("api_key", ""),
                base_url=helius_config.get("base_url", "https://api.helius.xyz")
            )

            self.providers["helius"] = RPCProvider(
                name="helius",
                client=helius_adapter,
                priority=1,  # Primary provider
                enabled=helius_config.get("enabled", True),
                cost_per_request=0.001,  # Helius pricing
                supports_shredstream=helius_config.get("enable_shredstream", False),
                supports_lil_jit=False,  # QuickNode-specific
                priority_fee_api_available=helius_config.get("enable_priority_fee_api", False)
            )

            # Initialize QuickNode adapter
            quicknode_config = self.config.get("quicknode", {})
            quicknode_adapter = QuickNodeAdapter(
                rpc_url=quicknode_config.get("primary_rpc", ""),
                backup_rpc_url=quicknode_config.get("backup_rpc", ""),
                archive_rpc_url=quicknode_config.get("archive_rpc", "")
            )

            self.providers["quicknode"] = RPCProvider(
                name="quicknode",
                client=quicknode_adapter,
                priority=2,  # Secondary provider
                enabled=quicknode_config.get("enabled", True),
                cost_per_request=0.002,  # QuickNode pricing
                supports_shredstream=False,  # Helius-specific
                supports_lil_jit=quicknode_config.get("enable_lil_jit", False),
                priority_fee_api_available=quicknode_config.get("enable_priority_fee_api", False)
            )

            self.logger.info(f"Initialized {len(self.providers)} RPC providers with async adapters")

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
        """Check health of a specific provider with enhanced bundle/feature probes"""
        try:
            start_time = time.time()

            # Perform basic health check
            basic_health = await self._check_basic_health(provider_name, provider)

            # Perform feature-specific health checks
            await self._check_feature_health(provider_name, provider)

            # Perform bundle-specific health checks
            await self._check_bundle_health(provider_name, provider)

            latency_ms = (time.time() - start_time) * 1000

            # Update provider status
            provider.last_health_check = time.time()
            provider.latency_ms = latency_ms

            # Determine overall health
            feature_health_score = self._calculate_feature_health_score(provider)
            overall_health = basic_health and feature_health_score >= 0.5

            if overall_health:
                provider.success_count += 1
                provider.healthy = latency_ms <= self.max_latency_ms
                self.logger.debug(f"Provider {provider_name} enhanced health check passed "
                               f"(latency: {latency_ms:.2f}ms, feature_score: {feature_health_score:.2f})")
            else:
                provider.error_count += 1
                provider.healthy = False
                self.logger.warning(f"Provider {provider_name} enhanced health check failed "
                                 f"(basic_health: {basic_health}, feature_score: {feature_health_score:.2f})")

            # Update metrics
            self._update_provider_metrics(provider)

        except Exception as e:
            provider.error_count += 1
            provider.healthy = False
            provider.last_health_check = time.time()
            self.logger.error(f"Enhanced health check error for {provider_name}: {e}")

    async def _check_basic_health(self, provider_name: str, provider: RPCProvider) -> bool:
        """Perform basic health check using async adapters"""
        try:
            if provider_name == "helius":
                return await provider.client.health_check()
            elif provider_name == "quicknode":
                return await provider.client.health_check()
            else:
                return True  # Unknown provider, assume healthy
        except Exception as e:
            self.logger.error(f"Basic health check failed for {provider_name}: {e}")
            return False

    async def _check_feature_health(self, provider_name: str, provider: RPCProvider):
        """Check provider-specific feature health"""
        try:
            # Check ShredStream health (Helius only)
            if provider.supports_shredstream and provider_name == "helius":
                await self._check_shredstream_health(provider)

            # Check Li'l JIT health (QuickNode only)
            if provider.supports_lil_jit and provider_name == "quicknode":
                await self._check_lil_jit_health(provider)

            # Check priority fee API health
            if provider.priority_fee_api_available:
                await self._check_priority_fee_health(provider)

            # Check webhook health (Helius only)
            if provider_name == "helius" and provider.webhooks_configured:
                await self._check_webhook_health(provider)

        except Exception as e:
            self.logger.error(f"Feature health check failed for {provider_name}: {e}")

    async def _check_shredstream_health(self, provider: RPCProvider):
        """Check ShredStream connectivity and health using real WebSocket probe"""
        try:
            start_time = time.time()

            # Use real ShredStream health check via HeliusAdapter
            if hasattr(provider.client, 'get_shredstream_data'):
                shredstream_data = await provider.client.get_shredstream_data()

                # Update provider metrics with real data
                provider.shredstream_latency_ms = (time.time() - start_time) * 1000
                provider.shredstream_connected = shredstream_data.get("connected", False)
                provider.shredstream_health_score = shredstream_data.get("health_score", 0.0)
                provider.last_shredstream_check = time.time()

                self.logger.debug(f"Real ShredStream health check: connected={provider.shredstream_connected}, "
                               f"score={provider.shredstream_health_score:.1f}, "
                               f"latency={provider.shredstream_latency_ms:.1f}ms")
            else:
                # Fallback to simulation for providers without ShredStream support
                shredstream_status = await self._simulate_shredstream_check(provider)
                provider.shredstream_latency_ms = (time.time() - start_time) * 1000
                provider.shredstream_connected = shredstream_status.get("connected", False)
                provider.shredstream_health_score = shredstream_status.get("health_score", 0.0)
                provider.last_shredstream_check = time.time()

        except Exception as e:
            provider.shredstream_connected = False
            provider.shredstream_health_score = 0.0
            self.logger.error(f"ShredStream health check error: {e}")

    async def _check_lil_jit_health(self, provider: RPCProvider):
        """Check Li'l JIT connectivity and health using real probes"""
        try:
            start_time = time.time()

            # Use real Lil' JIT health check via QuickNodeAdapter
            if hasattr(provider.client, 'get_lil_jit_health'):
                lil_jit_health = await provider.client.get_lil_jit_health()

                # Update provider metrics with real data
                provider.lil_jit_connected = lil_jit_health.get("connected", False)
                provider.lil_jit_health_score = lil_jit_health.get("health_score", 0.0)

                self.logger.debug(f"Real Lil' JIT health check: connected={provider.lil_jit_connected}, "
                               f"score={provider.lil_jit_health_score:.1f}, "
                               f"latency={lil_jit_health.get('latency_ms', -1):.1f}ms")
            else:
                # Fallback to simulation for providers without Lil' JIT support
                jit_status = await self._simulate_lil_jit_check(provider)
                provider.lil_jit_connected = jit_status.get("connected", False)
                provider.lil_jit_health_score = jit_status.get("health_score", 0.0)

        except Exception as e:
            provider.lil_jit_connected = False
            provider.lil_jit_health_score = 0.0
            self.logger.error(f"Li'l JIT health check error: {e}")

    async def _check_priority_fee_health(self, provider: RPCProvider):
        """Check priority fee API health using real API calls with timing measurements"""
        try:
            start_time = time.time()

            # Use provider-specific priority fee health checks
            if hasattr(provider.client, 'get_priority_fee_health'):
                # QuickNode has dedicated priority fee health check
                priority_fee_health = await provider.client.get_priority_fee_health()
                provider.priority_fee_active = priority_fee_health.get("active", False)
                provider.priority_fee_response_time_ms = priority_fee_health.get("response_time_ms", -1)
                provider.last_priority_fee_check = time.time()

                self.logger.debug(f"Real priority fee health check via {provider.name}: active={provider.priority_fee_active}, "
                               f"response_time={provider.priority_fee_response_time_ms:.1f}ms")
            elif hasattr(provider.client, 'get_priority_fee_estimate'):
                # Fallback to general priority fee estimation
                fee_estimate = await provider.client.get_priority_fee_estimate("normal")

                # Extract response time from the estimate if available
                if "response_time_ms" in fee_estimate:
                    provider.priority_fee_response_time_ms = fee_estimate["response_time_ms"]
                else:
                    provider.priority_fee_response_time_ms = (time.time() - start_time) * 1000

                provider.priority_fee_active = True
                provider.last_priority_fee_check = time.time()

                self.logger.debug(f"Real priority fee health check via {provider.name}: active={provider.priority_fee_active}, "
                               f"response_time={provider.priority_fee_response_time_ms:.1f}ms")
            else:
                # Fallback for providers without priority fee support
                provider.priority_fee_active = False
                provider.priority_fee_response_time_ms = -1

        except Exception as e:
            provider.priority_fee_active = False
            provider.priority_fee_response_time_ms = -1
            self.logger.error(f"Priority fee health check error: {e}")

    async def _check_webhook_health(self, provider: RPCProvider):
        """Check webhook configuration and delivery health using real API calls"""
        try:
            # Use real webhook health check via HeliusAdapter
            if hasattr(provider.client, 'get_webhook_health'):
                webhook_health = await provider.client.get_webhook_health()

                # Update provider metrics with real data
                provider.webhooks_configured = webhook_health.get("webhook_system_healthy", False)
                provider.webhook_delivery_success_rate = webhook_health.get("health_score", 0.0) / 100.0

                self.logger.debug(f"Real webhook health check: configured={provider.webhooks_configured}, "
                               f"delivery_rate={provider.webhook_delivery_success_rate:.2%}, "
                               f"total_webhooks={webhook_health.get('total_webhooks', 0)}")
            else:
                # Fallback to simulation for providers without webhook support
                webhook_status = await self._simulate_webhook_check(provider)
                provider.webhooks_configured = webhook_status.get("configured", False)
                provider.webhook_delivery_success_rate = webhook_status.get("delivery_rate", 0.0)

        except Exception as e:
            provider.webhooks_configured = False
            provider.webhook_delivery_success_rate = 0.0
            self.logger.error(f"Webhook health check error: {e}")

    async def _check_bundle_health(self, provider_name: str, provider: RPCProvider):
        """Check bundle submission and confirmation health"""
        try:
            # Update bundle statistics
            total_submissions = provider.bundle_submissions
            if total_submissions > 0:
                provider.bundle_success_rate = provider.bundle_successes / total_submissions
                provider.bundle_avg_confirmation_time_ms = self._calculate_avg_confirmation_time(provider)

            # Update pending and failed counts
            # In real implementation, this would check blockchain status
            provider.bundle_pending_count = await self._get_pending_bundle_count(provider)
            provider.bundle_failed_count = await self._get_failed_bundle_count(provider)

        except Exception as e:
            self.logger.error(f"Bundle health check error for {provider_name}: {e}")

    async def _simulate_shredstream_check(self, provider: RPCProvider) -> Dict[str, Any]:
        """Simulate ShredStream health check (replace with real implementation)"""
        # Placeholder for actual ShredStream health check
        # In real implementation, this would:
        # 1. Check WebSocket connection status
        # 2. Test data flow
        # 3. Validate latency
        # 4. Check connection stability

        connected = provider.shredstream_connected
        health_score = 80.0 if connected else 0.0

        return {
            "connected": connected,
            "health_score": health_score,
            "latency_ms": provider.shredstream_latency_ms
        }

    async def _simulate_lil_jit_check(self, provider: RPCProvider) -> Dict[str, Any]:
        """Simulate Li'l JIT health check (replace with real implementation)"""
        # Placeholder for actual Li'l JIT health check
        # In real implementation, this would:
        # 1. Test bundle submission endpoint
        # 2. Check MEV capabilities
        # 3. Validate response times

        connected = provider.lil_jit_connected
        health_score = 75.0 if connected else 0.0

        return {
            "connected": connected,
            "health_score": health_score
        }

    async def _simulate_webhook_check(self, provider: RPCProvider) -> Dict[str, Any]:
        """Simulate webhook health check (replace with real implementation)"""
        # Placeholder for actual webhook health check
        # In real implementation, this would:
        # 1. Check webhook endpoint configuration
        # 2. Test webhook delivery
        # 3. Validate delivery rates

        configured = provider.webhooks_configured
        delivery_rate = 0.95 if configured else 0.0

        return {
            "configured": configured,
            "delivery_rate": delivery_rate
        }

    def _calculate_feature_health_score(self, provider: RPCProvider) -> float:
        """Calculate overall feature health score (0-100)"""
        try:
            score_components = []

            # ShredStream score (if supported)
            if provider.supports_shredstream:
                score_components.append(provider.shredstream_health_score)

            # Li'l JIT score (if supported)
            if provider.supports_lil_jit:
                score_components.append(provider.lil_jit_health_score)

            # Priority fee score
            if provider.priority_fee_api_available:
                priority_fee_score = 100.0 if provider.priority_fee_active else 0.0
                score_components.append(priority_fee_score)

            # Webhook score
            if provider.webhooks_configured:
                webhook_score = provider.webhook_delivery_success_rate * 100.0
                score_components.append(webhook_score)

            # Bundle success rate
            if provider.bundle_submissions > 0:
                bundle_score = provider.bundle_success_rate * 100.0
                score_components.append(bundle_score)

            # Return average of all components
            return sum(score_components) / len(score_components) if score_components else 50.0

        except Exception as e:
            self.logger.error(f"Error calculating feature health score: {e}")
            return 0.0

    def _calculate_avg_confirmation_time(self, provider: RPCProvider) -> float:
        """Calculate average bundle confirmation time"""
        # Placeholder for actual implementation
        # In real implementation, this would track actual confirmation times
        return provider.bundle_avg_confirmation_time_ms

    async def _get_pending_bundle_count(self, provider: RPCProvider) -> int:
        """Get count of pending bundles"""
        # Placeholder for actual implementation
        return provider.bundle_pending_count

    async def _get_failed_bundle_count(self, provider: RPCProvider) -> int:
        """Get count of failed bundles"""
        # Placeholder for actual implementation
        return provider.bundle_failed_count

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
        if not self._initialization_complete:
            raise Exception("RPCRouter not fully initialized - call initialize_providers_async() first")

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
            # Make the call using async adapters
            start_time = time.time()

            # All adapters should support the call method
            result = await provider.client.call(method, params, **kwargs)

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
        current_provider = self._select_provider()
        alternative_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy and p.name != current_provider.name
        ]

        # Sort by priority
        alternative_providers.sort(key=lambda p: p.priority)

        for provider in alternative_providers:
            try:
                self.logger.info(f"Trying failover provider: {provider.name}")

                # All adapters should support the call method
                result = await provider.client.call(method, params, **kwargs)

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

    def _select_provider(self) -> RPCProvider:
        """Select provider based on routing policy"""
        healthy_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy
        ]

        if not healthy_providers:
            raise Exception("No healthy RPC providers available")

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
            raise Exception("No providers available for round-robin selection")

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
        """Get enhanced router health status with bundle and feature metrics"""
        healthy_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy
        ]

        # Calculate overall feature health scores
        provider_feature_health = {}
        total_bundle_stats = {
            "submissions": 0,
            "successes": 0,
            "confirmed": 0,
            "pending": 0,
            "failed": 0,
            "avg_confirmation_time_ms": 0.0
        }

        for name, provider in self.providers.items():
            # Calculate feature health score
            feature_score = self._calculate_feature_health_score(provider)
            provider_feature_health[name] = feature_score

            # Aggregate bundle statistics
            total_bundle_stats["submissions"] += provider.bundle_submissions
            total_bundle_stats["successes"] += provider.bundle_successes
            total_bundle_stats["confirmed"] += provider.bundle_confirmed_count
            total_bundle_stats["pending"] += provider.bundle_pending_count
            total_bundle_stats["failed"] += provider.bundle_failed_count

        # Calculate average confirmation time across all providers
        provider_count_with_time = sum(1 for p in self.providers.values() if p.bundle_avg_confirmation_time_ms > 0)
        if provider_count_with_time > 0:
            total_bundle_stats["avg_confirmation_time_ms"] = (
                sum(p.bundle_avg_confirmation_time_ms for p in self.providers.values() if p.bundle_avg_confirmation_time_ms > 0)
                / provider_count_with_time
            )

        # Calculate overall bundle success rate
        bundle_success_rate = (
            total_bundle_stats["successes"] / max(total_bundle_stats["submissions"], 1)
        )

        # Calculate feature readiness scores
        shredstream_ready = any(
            p.supports_shredstream and p.shredstream_health_score >= 70.0
            for p in self.providers.values()
        )
        lil_jit_ready = any(
            p.supports_lil_jit and p.lil_jit_health_score >= 70.0
            for p in self.providers.values()
        )
        priority_fee_ready = any(
            p.priority_fee_api_available and p.priority_fee_active
            for p in self.providers.values()
        )
        webhooks_ready = any(
            p.webhooks_configured and p.webhook_delivery_success_rate >= 0.9
            for p in self.providers.values()
        )

        return {
            # Basic health status
            "healthy": len(healthy_providers) > 0,
            "total_providers": len(self.providers),
            "healthy_providers": len(healthy_providers),
            "unhealthy_providers": len(self.providers) - len(healthy_providers),
            "routing_policy": self.routing_policy.value,
            "total_requests": self.metrics.total_requests,
            "success_rate": (
                self.metrics.successful_requests / max(self.metrics.total_requests, 1)
            ),

            # Enhanced bundle metrics
            "bundle_metrics": {
                "total_submissions": total_bundle_stats["submissions"],
                "total_successes": total_bundle_stats["successes"],
                "total_confirmed": total_bundle_stats["confirmed"],
                "total_pending": total_bundle_stats["pending"],
                "total_failed": total_bundle_stats["failed"],
                "success_rate": bundle_success_rate,
                "avg_confirmation_time_ms": total_bundle_stats["avg_confirmation_time_ms"],
                "track_bundle_metrics": self.track_bundle_metrics
            },

            # Feature readiness status
            "feature_readiness": {
                "shredstream_ready": shredstream_ready,
                "lil_jit_ready": lil_jit_ready,
                "priority_fee_ready": priority_fee_ready,
                "webhooks_ready": webhooks_ready,
                "bundle_success_rate_threshold_met": bundle_success_rate >= self.bundle_success_rate_threshold,
                "overall_feature_health": sum(provider_feature_health.values()) / max(len(provider_feature_health), 1)
            },

            # Detailed provider status with enhanced metrics
            "provider_status": {
                name: {
                    # Basic status
                    "healthy": provider.healthy,
                    "enabled": provider.enabled,
                    "priority": provider.priority,
                    "latency_ms": provider.latency_ms,
                    "error_rate": provider.error_rate,
                    "last_health_check": provider.last_health_check,

                    # Enhanced bundle metrics
                    "bundle_submissions": provider.bundle_submissions,
                    "bundle_successes": provider.bundle_successes,
                    "bundle_success_rate": provider.bundle_success_rate,
                    "bundle_confirmed": provider.bundle_confirmed_count,
                    "bundle_pending": provider.bundle_pending_count,
                    "bundle_failed": provider.bundle_failed_count,
                    "bundle_avg_confirmation_time_ms": provider.bundle_avg_confirmation_time_ms,
                    "last_bundle_confirmation": provider.last_bundle_confirmation,

                    # Feature-specific health
                    "supports_shredstream": provider.supports_shredstream,
                    "shredstream_connected": provider.shredstream_connected,
                    "shredstream_health_score": provider.shredstream_health_score,
                    "shredstream_latency_ms": provider.shredstream_latency_ms,
                    "last_shredstream_check": provider.last_shredstream_check,

                    "supports_lil_jit": provider.supports_lil_jit,
                    "lil_jit_connected": provider.lil_jit_connected,
                    "lil_jit_health_score": provider.lil_jit_health_score,

                    "priority_fee_api_available": provider.priority_fee_api_available,
                    "priority_fee_active": provider.priority_fee_active,
                    "priority_fee_response_time_ms": provider.priority_fee_response_time_ms,
                    "last_priority_fee_check": provider.last_priority_fee_check,

                    "webhooks_configured": provider.webhooks_configured,
                    "webhook_delivery_success_rate": provider.webhook_delivery_success_rate,

                    "overall_feature_health_score": provider_feature_health[name]
                }
                for name, provider in self.providers.items()
            }
        }

    def get_metrics(self) -> Dict[str, Any]:
        """Get comprehensive metrics with enhanced bundle and feature statistics"""

        # Calculate aggregated bundle statistics
        total_bundle_metrics = {
            "submissions": sum(p.bundle_submissions for p in self.providers.values()),
            "successes": sum(p.bundle_successes for p in self.providers.values()),
            "confirmed": sum(p.bundle_confirmed_count for p in self.providers.values()),
            "pending": sum(p.bundle_pending_count for p in self.providers.values()),
            "failed": sum(p.bundle_failed_count for p in self.providers.values()),
            "avg_confirmation_time_ms": 0.0
        }

        # Calculate average confirmation time
        providers_with_time = [p for p in self.providers.values() if p.bundle_avg_confirmation_time_ms > 0]
        if providers_with_time:
            total_bundle_metrics["avg_confirmation_time_ms"] = (
                sum(p.bundle_avg_confirmation_time_ms for p in providers_with_time) / len(providers_with_time)
            )

        # Calculate feature availability metrics
        feature_metrics = {
            "shredstream": {
                "available_providers": sum(1 for p in self.providers.values() if p.supports_shredstream),
                "healthy_providers": sum(1 for p in self.providers.values() if p.supports_shredstream and p.shredstream_connected),
                "avg_health_score": 0.0,
                "avg_latency_ms": 0.0
            },
            "lil_jit": {
                "available_providers": sum(1 for p in self.providers.values() if p.supports_lil_jit),
                "healthy_providers": sum(1 for p in self.providers.values() if p.supports_lil_jit and p.lil_jit_connected),
                "avg_health_score": 0.0
            },
            "priority_fee": {
                "available_providers": sum(1 for p in self.providers.values() if p.priority_fee_api_available),
                "active_providers": sum(1 for p in self.providers.values() if p.priority_fee_active),
                "avg_response_time_ms": 0.0
            },
            "webhooks": {
                "configured_providers": sum(1 for p in self.providers.values() if p.webhooks_configured),
                "avg_delivery_rate": 0.0
            }
        }

        # Calculate feature-specific averages
        shredstream_providers = [p for p in self.providers.values() if p.supports_shredstream]
        if shredstream_providers:
            feature_metrics["shredstream"]["avg_health_score"] = (
                sum(p.shredstream_health_score for p in shredstream_providers) / len(shredstream_providers)
            )
            feature_metrics["shredstream"]["avg_latency_ms"] = (
                sum(p.shredstream_latency_ms for p in shredstream_providers) / len(shredstream_providers)
            )

        lil_jit_providers = [p for p in self.providers.values() if p.supports_lil_jit]
        if lil_jit_providers:
            feature_metrics["lil_jit"]["avg_health_score"] = (
                sum(p.lil_jit_health_score for p in lil_jit_providers) / len(lil_jit_providers)
            )

        priority_fee_providers = [p for p in self.providers.values() if p.priority_fee_api_available]
        if priority_fee_providers:
            feature_metrics["priority_fee"]["avg_response_time_ms"] = (
                sum(p.priority_fee_response_time_ms for p in priority_fee_providers) / len(priority_fee_providers)
            )

        webhook_providers = [p for p in self.providers.values() if p.webhooks_configured]
        if webhook_providers:
            feature_metrics["webhooks"]["avg_delivery_rate"] = (
                sum(p.webhook_delivery_success_rate for p in webhook_providers) / len(webhook_providers)
            )

        return {
            # Router metrics
            "router": {
                "total_requests": self.metrics.total_requests,
                "successful_requests": self.metrics.successful_requests,
                "failed_requests": self.metrics.failed_requests,
                "success_rate": (
                    self.metrics.successful_requests / max(self.metrics.total_requests, 1)
                ),
                "avg_latency_ms": self.metrics.avg_latency_ms,
                "routing_policy": self.routing_policy.value,
                "health_check_interval": self.health_check_interval,
                "track_bundle_metrics": self.track_bundle_metrics,
                "prefer_shredstream_for_mev": self.prefer_shredstream_for_mev,
                "bundle_success_rate_threshold": self.bundle_success_rate_threshold,
                "latency_threshold_ms": self.latency_threshold_ms
            },

            # Enhanced bundle metrics
            "bundle_metrics": {
                **total_bundle_metrics,
                "success_rate": (
                    total_bundle_metrics["successes"] / max(total_bundle_metrics["submissions"], 1)
                ),
                "confirmation_rate": (
                    total_bundle_metrics["confirmed"] / max(total_bundle_metrics["successes"], 1)
                ),
                "failure_rate": (
                    total_bundle_metrics["failed"] / max(total_bundle_metrics["submissions"], 1)
                ),
                "pending_rate": (
                    total_bundle_metrics["pending"] / max(total_bundle_metrics["submissions"], 1)
                )
            },

            # Feature availability and health metrics
            "feature_metrics": feature_metrics,

            # Detailed provider metrics with enhanced statistics
            "providers": {
                name: {
                    # Basic metrics
                    "name": provider.name,
                    "priority": provider.priority,
                    "healthy": provider.healthy,
                    "enabled": provider.enabled,
                    "latency_ms": provider.latency_ms,
                    "error_rate": provider.error_rate,
                    "success_count": provider.success_count,
                    "error_count": provider.error_count,
                    "cost_per_request": provider.cost_per_request,
                    "last_health_check": provider.last_health_check,

                    # Enhanced bundle metrics
                    "bundle_submissions": provider.bundle_submissions,
                    "bundle_successes": provider.bundle_successes,
                    "bundle_success_rate": provider.bundle_success_rate,
                    "bundle_confirmed": provider.bundle_confirmed_count,
                    "bundle_pending": provider.bundle_pending_count,
                    "bundle_failed": provider.bundle_failed_count,
                    "bundle_avg_confirmation_time_ms": provider.bundle_avg_confirmation_time_ms,
                    "last_bundle_confirmation": provider.last_bundle_confirmation,

                    # Feature-specific metrics
                    "supports_shredstream": provider.supports_shredstream,
                    "shredstream_connected": provider.shredstream_connected,
                    "shredstream_health_score": provider.shredstream_health_score,
                    "shredstream_latency_ms": provider.shredstream_latency_ms,
                    "last_shredstream_check": provider.last_shredstream_check,

                    "supports_lil_jit": provider.supports_lil_jit,
                    "lil_jit_connected": provider.lil_jit_connected,
                    "lil_jit_health_score": provider.lil_jit_health_score,

                    "priority_fee_api_available": provider.priority_fee_api_available,
                    "priority_fee_active": provider.priority_fee_active,
                    "priority_fee_response_time_ms": provider.priority_fee_response_time_ms,
                    "last_priority_fee_check": provider.last_priority_fee_check,

                    "webhooks_configured": provider.webhooks_configured,
                    "webhook_delivery_success_rate": provider.webhook_delivery_success_rate,

                    # Performance scores
                    "overall_feature_health_score": self._calculate_feature_health_score(provider),
                    "bundle_performance_score": min(provider.bundle_success_rate * 100, 100.0) if provider.bundle_submissions > 0 else 0.0
                }
                for name, provider in self.providers.items()
            },

            # Usage statistics
            "usage": dict(self.metrics.provider_usage),

            # Cache statistics
            "cache_stats": {
                "priority_fee_cache_size": len(self.priority_fee_cache),
                "priority_fee_cache_ttl": self.priority_fee_cache_ttl
            }
        }

    async def submit_bundle(self, bundle_data: Dict[str, Any], urgency: str = "normal") -> Dict[str, Any]:
        """
        Submit bundle using optimal provider based on urgency and features

        Args:
            bundle_data: Bundle transaction data
            urgency: Transaction urgency ("low", "normal", "high", "critical")

        Returns:
            Bundle submission result with enhanced tracking
        """
        if not self._initialization_complete:
            raise Exception("RPCRouter not fully initialized - call initialize_providers_async() first")

        provider = self._select_bundle_provider(urgency)
        if not provider:
            raise Exception("No suitable provider available for bundle submission")

        submission_start_time = time.time()
        bundle_id = bundle_data.get("bundle_id", f"bundle_{int(time.time())}")

        try:
            # Track bundle submission
            if self.track_bundle_metrics:
                provider.bundle_submissions += 1

            # Submit via provider adapter - all adapters support submit_bundle
            result = await provider.client.submit_bundle(bundle_data)

            # Enhance result with tracking metadata
            submission_time_ms = (time.time() - submission_start_time) * 1000

            enhanced_result = {
                "success": result.get("success", False),
                "bundle_id": bundle_id,
                "provider": provider.name,
                "submission_time_ms": submission_time_ms,
                "urgency": urgency,
                "timestamp": time.time(),
                "original_result": result
            }

            # Track submission success
            if self.track_bundle_metrics:
                if enhanced_result["success"]:
                    provider.bundle_successes += 1
                    provider.bundle_success_rate = provider.bundle_successes / provider.bundle_submissions
                    # Track as pending until confirmed
                    provider.bundle_pending_count += 1
                else:
                    provider.bundle_failed_count += 1
                    provider.bundle_success_rate = provider.bundle_successes / max(provider.bundle_submissions, 1)

            self.logger.info(f"Bundle {bundle_id} submitted via {provider.name} "
                           f"(urgency: {urgency}, time: {submission_time_ms:.2f}ms, "
                           f"success: {enhanced_result['success']})")

            return enhanced_result

        except Exception as e:
            submission_time_ms = (time.time() - submission_start_time) * 1000

            if self.track_bundle_metrics:
                # Submission failed, don't increment successes
                provider.bundle_failed_count += 1
                provider.bundle_success_rate = provider.bundle_successes / max(provider.bundle_submissions, 1)

            error_result = {
                "success": False,
                "bundle_id": bundle_id,
                "provider": provider.name,
                "submission_time_ms": submission_time_ms,
                "urgency": urgency,
                "timestamp": time.time(),
                "error": str(e)
            }

            self.logger.error(f"Bundle {bundle_id} submission failed via {provider.name}: {e}")
            raise Exception(f"Bundle submission failed: {e}") from e

    def _select_bundle_provider(self, urgency: str) -> Optional[RPCProvider]:
        """
        Select optimal provider for bundle submission based on:
        - ShredStream support for high urgency
        - Lil' JIT support for MEV
        - Bundle success rates
        - Latency thresholds
        """
        healthy_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy and p.latency_ms <= self.latency_threshold_ms
        ]

        if not healthy_providers:
            # Fallback to any healthy provider
            healthy_providers = [
                p for p in self.providers.values()
                if p.enabled and p.healthy
            ]

        if not healthy_providers:
            return None

        # For high urgency transactions, prefer ShredStream
        if urgency in ["high", "critical"] and self.prefer_shredstream_for_mev:
            shredstream_providers = [p for p in healthy_providers if p.supports_shredstream]
            if shredstream_providers:
                return max(shredstream_providers, key=lambda p: (
                    p.bundle_success_rate >= self.bundle_success_rate_threshold,
                    p.bundle_success_rate,
                    -p.latency_ms
                ))

        # For MEV opportunities, prefer providers with best bundle success rates
        if urgency in ["normal", "high"]:
            # Filter by success rate threshold
            qualified_providers = [
                p for p in healthy_providers
                if p.bundle_success_rate >= self.bundle_success_rate_threshold or p.bundle_submissions == 0
            ]
            if qualified_providers:
                return max(qualified_providers, key=lambda p: (
                    p.bundle_success_rate,
                    -p.latency_ms,
                    p.supports_shredstream  # Prefer ShredStream capability
                ))

        # For low urgency, use standard routing
        return self._select_provider()

    async def get_priority_fee_estimate(self, urgency: str = "normal") -> Dict[str, Any]:
        """
        Get priority fee estimate from optimal provider

        Args:
            urgency: Transaction urgency level

        Returns:
            Priority fee estimate with provider metadata
        """
        if not self._initialization_complete:
            raise Exception("RPCRouter not fully initialized - call initialize_providers_async() first")

        # Check cache first
        cache_key = f"priority_fee_{urgency}"
        if cache_key in self.priority_fee_cache:
            cached = self.priority_fee_cache[cache_key]
            if time.time() - cached["timestamp"] < self.priority_fee_cache_ttl:
                return cached["data"]

        # Select provider with priority fee API
        provider = self._select_priority_fee_provider()
        if not provider:
            # Fallback estimate
            return {
                "priority_fee": 1000000,  # 0.001 SOL
                "confidence": 0.5,
                "provider": "fallback",
                "urgency": urgency
            }

        try:
            # All adapters should support get_priority_fee_estimate
            result = await provider.client.get_priority_fee_estimate(urgency)

            # Cache result
            self.priority_fee_cache[cache_key] = {
                "data": result,
                "timestamp": time.time()
            }

            return result

        except Exception as e:
            self.logger.error(f"Priority fee estimation failed via {provider.name}: {e}")
            # Return fallback estimate
            return {
                "priority_fee": 1000000,
                "confidence": 0.3,
                "provider": "fallback_error",
                "urgency": urgency,
                "error": str(e)
            }

    def _select_priority_fee_provider(self) -> Optional[RPCProvider]:
        """Select provider with priority fee API capability"""
        priority_fee_providers = [
            p for p in self.providers.values()
            if p.enabled and p.healthy and p.priority_fee_api_available
        ]

        if priority_fee_providers:
            # Prefer lowest latency
            return min(priority_fee_providers, key=lambda p: p.latency_ms)

        return None

    def track_bundle_confirmation(self, bundle_id: str, provider_name: str, confirmed: bool,
                               confirmation_time_ms: float = 0.0, block_height: int = None):
        """
        Track bundle confirmation result for enhanced metrics

        Args:
            bundle_id: Bundle transaction ID
            provider_name: Name of provider that submitted the bundle
            confirmed: Whether the bundle was confirmed
            confirmation_time_ms: Time from submission to confirmation (in milliseconds)
            block_height: Block height where bundle was confirmed
        """
        if not self.track_bundle_metrics:
            return

        provider = self.providers.get(provider_name)
        if not provider:
            self.logger.warning(f"Provider {provider_name} not found for bundle {bundle_id} tracking")
            return

        # Update confirmation statistics
        if confirmed:
            provider.bundle_confirmed_count += 1
            provider.last_bundle_confirmation = time.time()

            # Update pending count (move from pending to confirmed)
            if provider.bundle_pending_count > 0:
                provider.bundle_pending_count -= 1

            # Update average confirmation time
            if confirmation_time_ms > 0:
                total_confirmed = provider.bundle_confirmed_count
                current_avg = provider.bundle_avg_confirmation_time_ms
                provider.bundle_avg_confirmation_time_ms = (
                    (current_avg * (total_confirmed - 1) + confirmation_time_ms) / total_confirmed
                )
        else:
            # Bundle failed confirmation, move to failed
            if provider.bundle_pending_count > 0:
                provider.bundle_pending_count -= 1
            provider.bundle_failed_count += 1

        # Update success rate
        if provider.bundle_submissions > 0:
            provider.bundle_success_rate = provider.bundle_successes / provider.bundle_submissions

        # Log detailed confirmation information
        self.logger.info(
            f"Bundle {bundle_id} confirmation tracked for {provider_name}: "
            f"confirmed={confirmed}, "
            f"confirmation_time={confirmation_time_ms:.2f}ms, "
            f"block_height={block_height}, "
            f"success_rate={provider.bundle_success_rate:.2%}, "
            f"total_submissions={provider.bundle_submissions}, "
            f"confirmed={provider.bundle_confirmed_count}, "
            f"pending={provider.bundle_pending_count}, "
            f"failed={provider.bundle_failed_count}"
        )

    def track_bundle_timeout(self, bundle_id: str, provider_name: str, timeout_seconds: int = 30):
        """
        Track bundle timeout for metrics

        Args:
            bundle_id: Bundle transaction ID
            provider_name: Name of provider that submitted the bundle
            timeout_seconds: Timeout duration in seconds
        """
        if not self.track_bundle_metrics:
            return

        provider = self.providers.get(provider_name)
        if not provider:
            return

        # Move from pending to failed
        if provider.bundle_pending_count > 0:
            provider.bundle_pending_count -= 1
        provider.bundle_failed_count += 1

        # Update success rate
        if provider.bundle_submissions > 0:
            provider.bundle_success_rate = provider.bundle_successes / max(provider.bundle_submissions, 1)

        self.logger.warning(
            f"Bundle {bundle_id} timeout tracked for {provider_name}: "
            f"timeout_seconds={timeout_seconds}, "
            f"success_rate={provider.bundle_success_rate:.2%}"
        )

    def get_bundle_statistics(self, provider_name: str = None) -> Dict[str, Any]:
        """
        Get comprehensive bundle statistics for a provider or all providers

        Args:
            provider_name: Specific provider name, or None for all providers

        Returns:
            Bundle statistics dictionary
        """
        if provider_name:
            provider = self.providers.get(provider_name)
            if not provider:
                return {}

            return self._get_provider_bundle_stats(provider)

        # Return statistics for all providers
        all_stats = {}
        for name, provider in self.providers.items():
            all_stats[name] = self._get_provider_bundle_stats(provider)

        return all_stats

    def _get_provider_bundle_stats(self, provider: RPCProvider) -> Dict[str, Any]:
        """Get bundle statistics for a specific provider"""
        total = provider.bundle_submissions
        if total == 0:
            return {
                "submissions": 0,
                "successes": 0,
                "confirmed": 0,
                "pending": 0,
                "failed": 0,
                "success_rate": 0.0,
                "confirmation_rate": 0.0,
                "failure_rate": 0.0,
                "pending_rate": 0.0,
                "avg_confirmation_time_ms": 0.0,
                "last_confirmation": None
            }

        return {
            "submissions": provider.bundle_submissions,
            "successes": provider.bundle_successes,
            "confirmed": provider.bundle_confirmed_count,
            "pending": provider.bundle_pending_count,
            "failed": provider.bundle_failed_count,
            "success_rate": provider.bundle_success_rate,
            "confirmation_rate": provider.bundle_confirmed_count / max(provider.bundle_successes, 1),
            "failure_rate": provider.bundle_failed_count / total,
            "pending_rate": provider.bundle_pending_count / total,
            "avg_confirmation_time_ms": provider.bundle_avg_confirmation_time_ms,
            "last_confirmation": provider.last_bundle_confirmation,
            "track_metrics": self.track_bundle_metrics
        }

    async def subscribe_webhook(self, webhook_url: str, account_addresses: List[str] = None,
                           transaction_types: List[str] = None, provider_name: str = "helius") -> Dict[str, Any]:
        """
        Subscribe to webhook via specified provider

        Args:
            webhook_url: URL to receive webhook events
            account_addresses: List of account addresses to monitor
            transaction_types: List of transaction types to monitor
            provider_name: Provider to use for webhook subscription

        Returns:
            Webhook subscription result
        """
        if not self._initialization_complete:
            raise Exception("RPCRouter not fully initialized - call initialize_providers_async() first")

        provider = self.providers.get(provider_name)
        if not provider:
            raise Exception(f"Provider {provider_name} not available")

        if not provider.enabled or not provider.healthy:
            raise Exception(f"Provider {provider_name} is not enabled or healthy")

        try:
            if hasattr(provider.client, 'subscribe_webhook'):
                result = await provider.client.subscribe_webhook(webhook_url, account_addresses, transaction_types)
                self.logger.info(f"Webhook subscription successful via {provider_name}: {result.get('webhook_id')}")
                return result
            else:
                raise Exception(f"Provider {provider_name} does not support webhook subscriptions")

        except Exception as e:
            self.logger.error(f"Webhook subscription failed via {provider_name}: {e}")
            raise

    async def list_webhooks(self, provider_name: str = "helius") -> Dict[str, Any]:
        """
        List webhooks for specified provider

        Args:
            provider_name: Provider to list webhooks for

        Returns:
            List of active webhooks
        """
        if not self._initialization_complete:
            raise Exception("RPCRouter not fully initialized - call initialize_providers_async() first")

        provider = self.providers.get(provider_name)
        if not provider:
            raise Exception(f"Provider {provider_name} not available")

        try:
            if hasattr(provider.client, 'list_webhooks'):
                result = await provider.client.list_webhooks()
                self.logger.debug(f"Listed {result.get('count', 0)} webhooks via {provider_name}")
                return result
            else:
                raise Exception(f"Provider {provider_name} does not support webhook listing")

        except Exception as e:
            self.logger.error(f"Webhook listing failed via {provider_name}: {e}")
            raise

    async def unsubscribe_webhook(self, webhook_id: str, provider_name: str = "helius") -> Dict[str, Any]:
        """
        Unsubscribe from webhook via specified provider

        Args:
            webhook_id: ID of webhook to unsubscribe
            provider_name: Provider to unsubscribe from

        Returns:
            Webhook unsubscription result
        """
        if not self._initialization_complete:
            raise Exception("RPCRouter not fully initialized - call initialize_providers_async() first")

        provider = self.providers.get(provider_name)
        if not provider:
            raise Exception(f"Provider {provider_name} not available")

        try:
            if hasattr(provider.client, 'unsubscribe_webhook'):
                result = await provider.client.unsubscribe_webhook(webhook_id)
                self.logger.info(f"Webhook unsubscription successful via {provider_name}: {webhook_id}")
                return result
            else:
                raise Exception(f"Provider {provider_name} does not support webhook unsubscription")

        except Exception as e:
            self.logger.error(f"Webhook unsubscription failed via {provider_name}: {e}")
            raise

    def get_shredstream_readiness(self) -> Dict[str, Any]:
        """
        Get ShredStream readiness status across all providers

        Returns:
            ShredStream readiness metrics
        """
        shredstream_providers = []
        for provider in self.providers.values():
            if provider.supports_shredstream:
                readiness = {
                    "provider": provider.name,
                    "supports_shredstream": provider.supports_shredstream,
                    "connected": provider.shredstream_connected,
                    "health_score": provider.shredstream_health_score,
                    "latency_ms": provider.shredstream_latency_ms,
                    "last_check": provider.last_shredstream_check,
                    "ready": provider.shredstream_health_score >= 70.0 and provider.shredstream_connected
                }
                shredstream_providers.append(readiness)

        # Calculate overall readiness
        ready_providers = [p for p in shredstream_providers if p["ready"]]
        overall_ready = len(ready_providers) > 0
        avg_health_score = sum(p["health_score"] for p in shredstream_providers) / len(shredstream_providers) if shredstream_providers else 0.0

        return {
            "shredstream_ready": overall_ready,
            "ready_providers": len(ready_providers),
            "total_providers": len(shredstream_providers),
            "avg_health_score": avg_health_score,
            "providers": shredstream_providers,
            "timestamp": time.time()
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
async def create_rpc_router(config: Dict[str, Any]) -> RPCRouter:
    """Create and configure RPC router with async initialization"""
    router = RPCRouter(config)
    await router.initialize_providers_async()
    return router

# Synchronous factory for backward compatibility
def create_rpc_router_sync(config: Dict[str, Any]) -> RPCRouter:
    """Create RPC router (must call initialize_providers_async() separately)"""
    return RPCRouter(config)