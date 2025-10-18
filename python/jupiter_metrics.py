#!/usr/bin/env python3
"""
Jupiter Metrics Module

Comprehensive Prometheus metrics collection for Jupiter API integration,
price monitoring, swap execution, and arbitrage detection.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass

import prometheus_client as prom
import redis.asyncio as redis
import structlog

from .jupiter_pipeline import JupiterDataPipeline, JupiterPriceEvent, JupiterQuoteEvent
from .jupiter_executor import JupiterSwapExecutor, SwapExecutionResult

logger = structlog.get_logger()

@dataclass
class JupiterMetricsConfig:
    """Jupiter metrics configuration"""
    metrics_port: int = 9095
    metrics_update_interval: float = 5.0
    price_history_hours: int = 24
    execution_history_hours: int = 168  # 1 week

class JupiterMetricsCollector:
    """
    Comprehensive Jupiter metrics collector for Prometheus
    """

    def __init__(
        self,
        pipeline: JupiterDataPipeline,
        executor: JupiterSwapExecutor,
        redis_url: str = "redis://localhost:6379",
        config: Optional[JupiterMetricsConfig] = None
    ):
        """
        Initialize Jupiter metrics collector

        Args:
            pipeline: Jupiter data pipeline instance
            executor: Jupiter swap executor instance
            redis_url: Redis connection URL
            config: Metrics configuration
        """
        self.pipeline = pipeline
        self.executor = executor
        self.redis_url = redis_url
        self.config = config or JupiterMetricsConfig()

        # Initialize Redis client
        self.redis_client: Optional[redis.Redis] = None

        # Metrics collection state
        self.is_running = False
        self.metrics_task: Optional[asyncio.Task] = None

        # Initialize Prometheus metrics
        self._initialize_prometheus_metrics()

        # Historical data for trend analysis
        self.price_history: Dict[str, List[Dict]] = {}
        self.execution_history: List[Dict] = []

    def _initialize_prometheus_metrics(self) -> None:
        """Initialize all Prometheus metrics"""

        # Price API Metrics
        self.jupiter_price_api_requests_total = prom.Counter(
            'jupiter_price_api_requests_total',
            'Total number of Jupiter Price API requests',
            ['token', 'status']
        )

        self.jupiter_price_api_response_time_seconds = prom.Histogram(
            'jupiter_price_api_response_time_seconds',
            'Jupiter Price API response time in seconds',
            ['token'],
            buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
        )

        # Swap API Metrics
        self.jupiter_swap_api_requests_total = prom.Counter(
            'jupiter_swap_api_requests_total',
            'Total number of Jupiter Swap API requests',
            ['input_token', 'output_token', 'status']
        )

        self.jupiter_swap_api_response_time_seconds = prom.Histogram(
            'jupiter_swap_api_response_time_seconds',
            'Jupiter Swap API response time in seconds',
            ['input_token', 'output_token'],
            buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0]
        )

        # Price Monitoring Metrics
        self.jupiter_token_price = prom.Gauge(
            'jupiter_token_price',
            'Current token price from Jupiter',
            ['token_symbol', 'token_mint', 'reliability']
        )

        self.jupiter_token_price_change_24h = prom.Gauge(
            'jupiter_token_price_change_24h',
            'Token price change over 24 hours',
            ['token_symbol']
        )

        self.jupiter_token_volume_24h = prom.Gauge(
            'jupiter_token_volume_24h',
            'Token trading volume over 24 hours',
            ['token_symbol']
        )

        self.jupiter_price_update_timestamp = prom.Gauge(
            'jupiter_price_update_timestamp',
            'Timestamp of last price update',
            ['token_symbol']
        )

        # Quote Metrics
        self.jupiter_active_quotes = prom.Gauge(
            'jupiter_active_quotes',
            'Number of active Jupiter quotes',
            ['trading_pair']
        )

        self.jupiter_quote_price_impact = prom.Histogram(
            'jupiter_quote_price_impact',
            'Price impact from Jupiter quotes',
            ['trading_pair', 'dex'],
            buckets=[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5]
        )

        # Swap Execution Metrics
        self.jupiter_swap_executions_total = prom.Counter(
            'jupiter_swap_executions_total',
            'Total number of Jupiter swap executions',
            ['status', 'urgency_level', 'execution_type']
        )

        self.jupiter_swap_execution_time_seconds = prom.Histogram(
            'jupiter_swap_execution_time_seconds',
            'Jupiter swap execution time in seconds',
            ['urgency_level', 'execution_type'],
            buckets=[0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
        )

        self.jupiter_swap_volume_usd = prom.Counter(
            'jupiter_swap_volume_usd',
            'Total USD volume swapped through Jupiter',
            ['token_pair']
        )

        self.jupiter_priority_fees_paid_total = prom.Counter(
            'jupiter_priority_fees_paid_total',
            'Total priority fees paid for Jupiter swaps',
            ['urgency_level']
        )

        self.jupiter_actual_slippage = prom.Histogram(
            'jupiter_actual_slippage',
            'Actual slippage experienced in Jupiter swaps',
            ['token_pair'],
            buckets=[0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5]
        )

        # Jito Bundle Metrics
        self.jupiter_jito_bundles_total = prom.Counter(
            'jupiter_jito_bundles_total',
            'Total number of Jito bundles submitted',
            ['status']
        )

        self.jupiter_jito_bundle_success_rate = prom.Gauge(
            'jupiter_jito_bundle_success_rate',
            'Jito bundle success rate',
        )

        self.jupiter_jito_tip_lamports_total = prom.Counter(
            'jupiter_jito_tip_lamports_total',
            'Total lamports paid in Jito tips',
        )

        # Arbitrage Detection Metrics
        self.jupiter_arbitrage_opportunities = prom.Gauge(
            'jupiter_arbitrage_opportunities',
            'Number of detected arbitrage opportunities',
            ['profit_tier']  # low: <0.5%, medium: 0.5-2%, high: >2%
        )

        self.jupiter_arbitrage_opportunities_total = prom.Counter(
            'jupiter_arbitrage_opportunities_total',
            'Total arbitrage opportunities detected',
            ['profit_tier']
        )

        self.jupiter_arbitrage_profit_potential = prom.Gauge(
            'jupiter_arbitrage_profit_potential',
            'Potential profit from arbitrage opportunities in USD',
            ['profit_tier']
        )

        # Pipeline Health Metrics
        self.jupiter_pipeline_status = prom.Gauge(
            'jupiter_pipeline_status',
            'Jupiter pipeline status (1=running, 0=stopped)',
        )

        self.jupiter_pipeline_cached_prices = prom.Gauge(
            'jupiter_pipeline_cached_prices',
            'Number of cached prices in pipeline',
        )

        self.jupiter_pipeline_cached_quotes = prom.Gauge(
            'jupiter_pipeline_cached_quotes',
            'Number of cached quotes in pipeline',
        )

        self.jupiter_redis_connection_status = prom.Gauge(
            'jupiter_redis_connection_status',
            'Redis connection status (1=connected, 0=disconnected)',
        )

        # Performance Metrics
        self.jupiter_price_update_rate = prom.Gauge(
            'jupiter_price_update_rate',
            'Rate of price updates per second',
        )

        self.jupiter_quote_generation_rate = prom.Gauge(
            'jupiter_quote_generation_rate',
            'Rate of quote generation per second',
        )

        self.jupiter_swap_success_rate = prom.Gauge(
            'jupiter_swap_success_rate',
            'Success rate of Jupiter swaps',
        )

        # Error Metrics
        self.jupiter_api_errors_total = prom.Counter(
            'jupiter_api_errors_total',
            'Total Jupiter API errors',
            ['api_type', 'error_type']
        )

        self.jupiter_execution_errors_total = prom.Counter(
            'jupiter_execution_errors_total',
            'Total Jupiter execution errors',
            ['error_type']
        )

        # Rate Limiting Metrics
        self.jupiter_rate_limit_hits_total = prom.Counter(
            'jupiter_rate_limit_hits_total',
            'Total number of rate limit hits',
            ['api_type']
        )

        self.jupiter_rate_limit_remaining = prom.Gauge(
            'jupiter_rate_limit_remaining',
            'Remaining API calls in rate limit window',
            ['api_type']
        )

    async def start(self) -> None:
        """Start the Jupiter metrics collector"""
        try:
            logger.info("Starting Jupiter metrics collector...")

            # Initialize Redis connection
            self.redis_client = redis.from_url(self.redis_url, decode_responses=True)
            await self.redis_client.ping()

            # Start metrics collection task
            self.is_running = True
            self.metrics_task = asyncio.create_task(self._metrics_collection_loop())

            logger.info("Jupiter metrics collector started successfully")

        except Exception as e:
            logger.error("Failed to start Jupiter metrics collector", error=str(e))
            await self.stop()
            raise

    async def stop(self) -> None:
        """Stop the Jupiter metrics collector"""
        try:
            logger.info("Stopping Jupiter metrics collector...")

            self.is_running = False

            if self.metrics_task and not self.metrics_task.done():
                self.metrics_task.cancel()
                try:
                    await self.metrics_task
                except asyncio.CancelledError:
                    pass

            if self.redis_client:
                await self.redis_client.close()

            logger.info("Jupiter metrics collector stopped")

        except Exception as e:
            logger.error("Error stopping Jupiter metrics collector", error=str(e))

    async def _metrics_collection_loop(self) -> None:
        """Main metrics collection loop"""
        logger.info("Starting metrics collection loop...")

        while self.is_running:
            try:
                start_time = time.time()

                # Collect all metrics
                await self._collect_pipeline_metrics()
                await self._collect_executor_metrics()
                await self._collect_price_metrics()
                await self._collect_arbitrage_metrics()
                await self._collect_performance_metrics()
                await self._collect_error_metrics()

                # Calculate collection time
                collection_time = time.time() - start_time
                logger.debug("Metrics collection completed", collection_time_s=collection_time)

                # Wait for next collection
                await asyncio.sleep(self.config.metrics_update_interval)

            except Exception as e:
                logger.error("Error in metrics collection loop", error=str(e))
                await asyncio.sleep(5)  # Wait before retrying

    async def _collect_pipeline_metrics(self) -> None:
        """Collect pipeline-related metrics"""
        try:
            # Get pipeline statistics
            pipeline_stats = await self.pipeline.get_statistics()

            # Update pipeline status
            self.jupiter_pipeline_status.set(1 if pipeline_stats["is_running"] else 0)

            # Update cached items
            self.jupiter_pipeline_cached_prices.set(pipeline_stats["cached_prices"])
            self.jupiter_pipeline_cached_quotes.set(pipeline_stats["cached_quotes"])

            # Update Redis connection status
            redis_status = 1 if self.redis_client else 0
            try:
                if self.redis_client:
                    await self.redis_client.ping()
                    redis_status = 1
            except:
                redis_status = 0
            self.jupiter_redis_connection_status.set(redis_status)

        except Exception as e:
            logger.error("Error collecting pipeline metrics", error=str(e))

    async def _collect_executor_metrics(self) -> None:
        """Collect executor-related metrics"""
        try:
            # Get executor statistics
            executor_stats = await self.executor.get_statistics()

            # Update success rate
            self.jupiter_swap_success_rate.set(executor_stats.get("success_rate", 0))

            # Update Jito metrics
            jito_success_rate = executor_stats.get("jito_success_rate", 0)
            self.jupiter_jito_bundle_success_rate.set(jito_success_rate)

        except Exception as e:
            logger.error("Error collecting executor metrics", error=str(e))

    async def _collect_price_metrics(self) -> None:
        """Collect price-related metrics"""
        try:
            # Get current prices from pipeline
            current_prices = await self.pipeline.get_current_prices()

            for token_id, price_event in current_prices.items():
                symbol = price_event.symbol
                mint = price_event.token_id
                reliability = price_event.reliability

                # Update price gauges
                self.jupiter_token_price.labels(
                    token_symbol=symbol,
                    token_mint=mint,
                    reliability=reliability
                ).set(price_event.price)

                self.jupiter_token_price_change_24h.labels(
                    token_symbol=symbol
                ).set(price_event.price_change_24h)

                self.jupiter_token_volume_24h.labels(
                    token_symbol=symbol
                ).set(price_event.volume_24h)

                self.jupiter_price_update_timestamp.labels(
                    token_symbol=symbol
                ).set(price_event.timestamp.timestamp())

        except Exception as e:
            logger.error("Error collecting price metrics", error=str(e))

    async def _collect_arbitrage_metrics(self) -> None:
        """Collect arbitrage-related metrics"""
        try:
            if not self.redis_client:
                return

            # Get active arbitrage opportunities from Redis
            opportunities = await self.redis_client.zrevrangebyscore(
                "jupiter:arbitrage:active_opportunities",
                "+inf", "-inf",
                start=0, end=99,  # Get top 100
                withscores=True
            )

            # Count by profit tiers
            low_profit = 0
            medium_profit = 0
            high_profit = 0
            total_potential = 0.0

            for opportunity_str, profit_pct in opportunities:
                try:
                    opportunity = json.loads(opportunity_str)
                    profit_pct = float(profit_pct)

                    if profit_pct < 0.5:
                        low_profit += 1
                    elif profit_pct < 2.0:
                        medium_profit += 1
                    else:
                        high_profit += 1

                    # Estimate potential profit (simplified)
                    total_potential += profit_pct * 1000  # Rough estimate

                except (json.JSONDecodeError, ValueError):
                    continue

            # Update arbitrage metrics
            self.jupiter_arbitrage_opportunities.labels(profit_tier="low").set(low_profit)
            self.jupiter_arbitrage_opportunities.labels(profit_tier="medium").set(medium_profit)
            self.jupiter_arbitrage_opportunities.labels(profit_tier="high").set(high_profit)

            self.jupiter_arbitrage_profit_potential.labels(profit_tier="low").set(low_profit * 50)
            self.jupiter_arbitrage_profit_potential.labels(profit_tier="medium").set(medium_profit * 200)
            self.jupiter_arbitrage_profit_potential.labels(profit_tier="high").set(high_profit * 1000)

        except Exception as e:
            logger.error("Error collecting arbitrage metrics", error=str(e))

    async def _collect_performance_metrics(self) -> None:
        """Collect performance-related metrics"""
        try:
            # Calculate rates from statistics
            pipeline_stats = await self.pipeline.get_statistics()
            executor_stats = await self.executor.get_statistics()

            if pipeline_stats.get("start_time") and executor_stats.get("start_time"):
                pipeline_uptime = pipeline_stats["uptime_seconds"]
                executor_uptime = executor_stats["uptime_seconds"]

                if pipeline_uptime > 0:
                    price_update_rate = pipeline_stats["price_updates"] / pipeline_uptime
                    self.jupiter_price_update_rate.set(price_update_rate)

                    quote_generation_rate = pipeline_stats["quotes_generated"] / pipeline_uptime
                    self.jupiter_quote_generation_rate.set(quote_generation_rate)

        except Exception as e:
            logger.error("Error collecting performance metrics", error=str(e))

    async def _collect_error_metrics(self) -> None:
        """Collect error-related metrics"""
        try:
            # Get error counts from Redis if available
            if self.redis_client:
                # This would typically read from error logs or Redis error counters
                # For now, we'll update based on recent failures
                pass

        except Exception as e:
            logger.error("Error collecting error metrics", error=str(e))

    # Public methods for recording specific events
    def record_price_api_request(
        self,
        token: str,
        status: str,
        response_time: float
    ) -> None:
        """Record a Price API request"""
        self.jupiter_price_api_requests_total.labels(token=token, status=status).inc()
        self.jupiter_price_api_response_time_seconds.labels(token=token).observe(response_time)

    def record_swap_api_request(
        self,
        input_token: str,
        output_token: str,
        status: str,
        response_time: float
    ) -> None:
        """Record a Swap API request"""
        self.jupiter_swap_api_requests_total.labels(
            input_token=input_token,
            output_token=output_token,
            status=status
        ).inc()

        self.jupiter_swap_api_response_time_seconds.labels(
            input_token=input_token,
            output_token=output_token
        ).observe(response_time)

    def record_swap_execution(
        self,
        status: str,
        urgency_level: str,
        execution_type: str,
        execution_time: float,
        volume_usd: float,
        priority_fee: int,
        actual_slippage: float
    ) -> None:
        """Record a swap execution"""
        self.jupiter_swap_executions_total.labels(
            status=status,
            urgency_level=urgency_level,
            execution_type=execution_type
        ).inc()

        self.jupiter_swap_execution_time_seconds.labels(
            urgency_level=urgency_level,
            execution_type=execution_type
        ).observe(execution_time)

        # Extract token pair from volume tracking
        token_pair = "unknown"  # Would be passed from caller
        self.jupiter_swap_volume_usd.labels(token_pair=token_pair).inc(volume_usd)

        self.jupiter_priority_fees_paid_total.labels(
            urgency_level=urgency_level
        ).inc(priority_fee)

        if actual_slippage is not None:
            self.jupiter_actual_slippage.labels(token_pair=token_pair).observe(actual_slippage)

    def record_jito_bundle(
        self,
        status: str,
        tip_amount: int
    ) -> None:
        """Record a Jito bundle submission"""
        self.jupiter_jito_bundles_total.labels(status=status).inc()
        if status == "success":
            self.jupiter_jito_tip_lamports_total.inc(tip_amount)

    def record_arbitrage_opportunity(
        self,
        profit_pct: float,
        estimated_profit_usd: float
    ) -> None:
        """Record an arbitrage opportunity"""
        if profit_pct < 0.5:
            profit_tier = "low"
        elif profit_pct < 2.0:
            profit_tier = "medium"
        else:
            profit_tier = "high"

        self.jupiter_arbitrage_opportunities_total.labels(profit_tier=profit_tier).inc()

    def record_api_error(
        self,
        api_type: str,
        error_type: str
    ) -> None:
        """Record an API error"""
        self.jupiter_api_errors_total.labels(
            api_type=api_type,
            error_type=error_type
        ).inc()

    def record_execution_error(
        self,
        error_type: str
    ) -> None:
        """Record an execution error"""
        self.jupiter_execution_errors_total.labels(error_type=error_type).inc()

    def record_rate_limit_hit(
        self,
        api_type: str,
        remaining_calls: int
    ) -> None:
        """Record a rate limit hit"""
        self.jupiter_rate_limit_hits_total.labels(api_type=api_type).inc()
        self.jupiter_rate_limit_remaining.labels(api_type=api_type).set(remaining_calls)

    def get_metrics_summary(self) -> Dict[str, Any]:
        """Get a summary of current metrics values"""
        try:
            # Collect key metrics for summary
            summary = {
                "timestamp": datetime.now().isoformat(),
                "pipeline_status": self.jupiter_pipeline_status._value._value,
                "cached_prices": int(self.jupiter_pipeline_cached_prices._value._value),
                "cached_quotes": int(self.jupiter_pipeline_cached_quotes._value._value),
                "swap_success_rate": self.jupiter_swap_success_rate._value._value,
                "jito_success_rate": self.jupiter_jito_bundle_success_rate._value._value,
                "active_arbitrage_opportunities": {
                    "low": int(self.jupiter_arbitrage_opportunities.labels(profit_tier="low")._value._value),
                    "medium": int(self.jupiter_arbitrage_opportunities.labels(profit_tier="medium")._value._value),
                    "high": int(self.jupiter_arbitrage_opportunities.labels(profit_tier="high")._value._value),
                },
                "total_swaps_executed": int(self.jupiter_swap_executions_total._value._value),
                "total_api_errors": int(self.jupiter_api_errors_total._value._value),
                "redis_connection_status": int(self.jupiter_redis_connection_status._value._value),
            }

            return summary

        except Exception as e:
            logger.error("Error generating metrics summary", error=str(e))
            return {"error": str(e), "timestamp": datetime.now().isoformat()}