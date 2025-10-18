#!/usr/bin/env python3
"""
Jupiter Trading Integration Example

Comprehensive example demonstrating the complete Jupiter trading workflow:
- Price monitoring with real-time data pipeline
- Arbitrage opportunity detection
- Swap execution with Jito MEV protection
- Metrics collection and monitoring
"""

import asyncio
import logging
import os
import time
from datetime import datetime
from typing import Dict, List, Optional

import structlog
from prometheus_client import start_http_server

# Import Jupiter components
from python.jupiter_pipeline import JupiterDataPipeline
from python.jupiter_executor import JupiterSwapExecutor, SwapExecutionRequest, JitoBundleConfig
from python.jupiter_metrics import JupiterMetricsCollector, JupiterMetricsConfig
from python.geyser_client import JupiterPriceClient

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = structlog.get_logger()

class JupiterTradingBot:
    """
    Complete Jupiter trading bot with all components integrated
    """

    def __init__(self, config: Dict):
        """
        Initialize Jupiter trading bot

        Args:
            config: Trading configuration dictionary
        """
        self.config = config
        self.redis_url = config.get("redis_url", "redis://localhost:6379")
        self.rpc_url = config.get("rpc_url", "https://api.mainnet-beta.solana.com")

        # Trading parameters
        self.max_position_size_usd = config.get("max_position_size_usd", 1000)
        self.min_profit_pct = config.get("min_profit_pct", 0.5)
        self.max_slippage_bps = config.get("max_slippage_bps", 100)
        self.max_concurrent_swaps = config.get("max_concurrent_swaps", 5)

        # Initialize components
        self.pipeline: Optional[JupiterDataPipeline] = None
        self.executor: Optional[JupiterSwapExecutor] = None
        self.metrics_collector: Optional[JupiterMetricsCollector] = None

        # Trading state
        self.is_running = False
        self.active_swaps: Dict[str, asyncio.Task] = {}
        self.trading_stats = {
            "total_swaps": 0,
            "successful_swaps": 0,
            "total_profit_usd": 0.0,
            "total_fees_paid": 0.0,
            "start_time": None
        }

    async def start(self) -> None:
        """Start the Jupiter trading bot"""
        try:
            logger.info("Starting Jupiter trading bot...")

            # Initialize Jupiter components
            await self._initialize_components()

            # Start all components
            await self.pipeline.start()
            await self.executor.start()
            await self.metrics_collector.start()

            # Start trading loops
            self.is_running = True
            self.trading_stats["start_time"] = datetime.now()

            # Start trading tasks
            trading_tasks = [
                asyncio.create_task(self._arbitrage_trading_loop()),
                asyncio.create_task(self._position_management_loop()),
                asyncio.create_task(self._health_monitoring_loop()),
            ]

            logger.info("Jupiter trading bot started successfully")

            # Wait for all tasks
            await asyncio.gather(*trading_tasks, return_exceptions=True)

        except Exception as e:
            logger.error("Failed to start Jupiter trading bot", error=str(e))
            await self.stop()
            raise

    async def stop(self) -> None:
        """Stop the Jupiter trading bot"""
        try:
            logger.info("Stopping Jupiter trading bot...")

            self.is_running = False

            # Cancel active swaps
            for swap_id, task in self.active_swaps.items():
                logger.info(f"Cancelling active swap: {swap_id}")
                task.cancel()

            if self.active_swaps:
                await asyncio.gather(*self.active_swaps.values(), return_exceptions=True)

            # Stop components
            if self.metrics_collector:
                await self.metrics_collector.stop()
            if self.executor:
                await self.executor.stop()
            if self.pipeline:
                await self.pipeline.stop()

            logger.info("Jupiter trading bot stopped")

        except Exception as e:
            logger.error("Error stopping Jupiter trading bot", error=str(e))

    async def _initialize_components(self) -> None:
        """Initialize all Jupiter components"""
        try:
            # Initialize data pipeline
            self.pipeline = JupiterDataPipeline(
                redis_url=self.redis_url,
                monitoring_tokens=self.config.get("monitoring_tokens"),
                price_update_interval=self.config.get("price_update_interval", 5.0),
                arbitrage_check_interval=self.config.get("arbitrage_check_interval", 2.0)
            )

            # Initialize swap executor with Jito configuration
            jito_config = JitoBundleConfig(
                use_jito=self.config.get("use_jito", True),
                jito_auth_key=os.getenv("JITO_AUTH_KEY"),
                bundle_tip_lamports=self.config.get("jito_tip_lamports", 10000),
                max_bundle_size=self.config.get("max_bundle_size", 5)
            )

            self.executor = JupiterSwapExecutor(
                rpc_url=self.rpc_url,
                redis_url=self.redis_url,
                jito_config=jito_config,
                max_concurrent_swaps=self.max_concurrent_swaps
            )

            # Initialize metrics collector
            metrics_config = JupiterMetricsConfig(
                metrics_port=self.config.get("metrics_port", 9095),
                metrics_update_interval=self.config.get("metrics_update_interval", 5.0)
            )

            self.metrics_collector = JupiterMetricsCollector(
                pipeline=self.pipeline,
                executor=self.executor,
                redis_url=self.redis_url,
                config=metrics_config
            )

            # Start Prometheus metrics server
            start_http_server(metrics_config.metrics_port)

            logger.info("Jupiter components initialized successfully")

        except Exception as e:
            logger.error("Failed to initialize Jupiter components", error=str(e))
            raise

    async def _arbitrage_trading_loop(self) -> None:
        """Main arbitrage trading loop"""
        logger.info("Starting arbitrage trading loop...")

        while self.is_running:
            try:
                # Get current arbitrage opportunities from Redis
                opportunities = await self._get_arbitrage_opportunities()

                # Filter and execute profitable opportunities
                for opportunity in opportunities:
                    if opportunity["profit_pct"] >= self.min_profit_pct:
                        await self._execute_arbitrage_opportunity(opportunity)

                # Wait before next check
                await asyncio.sleep(self.config.get("arbitrage_check_interval", 2.0))

            except Exception as e:
                logger.error("Error in arbitrage trading loop", error=str(e))
                await asyncio.sleep(5)

    async def _get_arbitrage_opportunities(self) -> List[Dict]:
        """Get current arbitrage opportunities from Redis"""
        try:
            import redis.asyncio as redis
            import json

            redis_client = redis.from_url(self.redis_url, decode_responses=True)

            # Get top arbitrage opportunities
            opportunities = await redis_client.zrevrangebyscore(
                "jupiter:arbitrage:active_opportunities",
                "+inf", "-inf",
                start=0, end=9,  # Get top 10
                withscores=True
            )

            result = []
            for opportunity_str, profit_pct in opportunities:
                try:
                    opportunity = json.loads(opportunity_str)
                    opportunity["profit_pct"] = float(profit_pct)
                    result.append(opportunity)
                except (json.JSONDecodeError, ValueError):
                    continue

            await redis_client.close()
            return result

        except Exception as e:
            logger.error("Error getting arbitrage opportunities", error=str(e))
            return []

    async def _execute_arbitrage_opportunity(self, opportunity: Dict) -> None:
        """Execute an arbitrage opportunity"""
        try:
            # Extract opportunity details
            route_key = opportunity["route_key"]
            input_symbol = opportunity["input_symbol"]
            output_symbol = opportunity["output_symbol"]
            profit_pct = opportunity["profit_pct"]

            # Calculate position size based on risk parameters
            position_size_usd = min(self.max_position_size_usd, 100)  # Conservative starting size

            # Get current price for position sizing
            current_prices = await self.pipeline.get_current_prices()

            # Find token mints from symbols (simplified)
            input_mint = await self._find_token_mint(input_symbol, current_prices)
            output_mint = await self._find_token_mint(output_symbol, current_prices)

            if not input_mint or not output_mint:
                logger.warning("Could not find token mints for arbitrage",
                             input_symbol=input_symbol, output_symbol=output_symbol)
                return

            # Calculate input amount based on position size
            input_price = current_prices.get(input_mint)
            if not input_price:
                logger.warning("Could not get input token price", token=input_symbol)
                return

            input_amount = int((position_size_usd / input_price.price) * 1e6)  # Assuming 6 decimals

            # Generate fresh quote
            jupiter_client = JupiterPriceClient()
            quote = await jupiter_client.get_swap_quote(
                input_mint=input_mint,
                output_mint=output_mint,
                amount=input_amount,
                slippage_bps=self.max_slippage_bps
            )

            if not quote:
                logger.warning("Failed to get quote for arbitrage", route_key=route_key)
                return

            # Calculate priority fee based on urgency
            priority_fee = await self._calculate_priority_fee("high")

            # Create swap request
            swap_request = SwapExecutionRequest(
                input_mint=input_mint,
                output_mint=output_mint,
                input_amount=input_amount,
                slippage_bps=self.max_slippage_bps,
                user_public_key=os.getenv("WALLET_PUBLIC_KEY"),
                quote_response=quote,
                priority_fee=priority_fee,
                urgency_level="high",
                max_retries=3
            )

            # Execute swap
            swap_id = f"arbitrage_{int(time.time())}_{route_key}"

            # Limit concurrent swaps
            if len(self.active_swaps) >= self.max_concurrent_swaps:
                logger.info("Max concurrent swaps reached, skipping opportunity", route_key=route_key)
                return

            # Execute swap asynchronously
            swap_task = asyncio.create_task(self._execute_swap_with_tracking(swap_id, swap_request))
            self.active_swaps[swap_id] = swap_task

            logger.info("Arbitrage swap initiated",
                       swap_id=swap_id,
                       route_key=route_key,
                       profit_pct=profit_pct,
                       position_size_usd=position_size_usd)

        except Exception as e:
            logger.error("Error executing arbitrage opportunity", error=str(e))

    async def _execute_swap_with_tracking(self, swap_id: str, swap_request: SwapExecutionRequest) -> None:
        """Execute swap with tracking and cleanup"""
        try:
            result = await self.executor.execute_swap(swap_request, swap_id)

            # Update trading statistics
            self.trading_stats["total_swaps"] += 1

            if result.success:
                self.trading_stats["successful_swaps"] += 1
                # Estimate profit (simplified)
                estimated_profit = swap_request.input_amount * (swap_request.priority_fee / 1e9)
                self.trading_stats["total_profit_usd"] += estimated_profit

            self.trading_stats["total_fees_paid"] += result.priority_fee_used

            logger.info("Swap execution completed",
                       swap_id=swap_id,
                       success=result.success,
                       execution_time_ms=result.execution_time_ms)

        except Exception as e:
            logger.error("Error in swap execution", swap_id=swap_id, error=str(e))
        finally:
            # Clean up from active swaps
            if swap_id in self.active_swaps:
                del self.active_swaps[swap_id]

    async def _find_token_mint(self, symbol: str, current_prices: Dict) -> Optional[str]:
        """Find token mint address from symbol"""
        for token_mint, price_event in current_prices.items():
            if price_event.symbol == symbol:
                return token_mint
        return None

    async def _calculate_priority_fee(self, urgency_level: str) -> int:
        """Calculate priority fee based on urgency"""
        # This would use the PriorityFeeCalculator in production
        base_fees = {
            "low": 1000,
            "normal": 5000,
            "high": 20000,
            "critical": 100000
        }
        return base_fees.get(urgency_level, 5000)

    async def _position_management_loop(self) -> None:
        """Position management and risk monitoring loop"""
        logger.info("Starting position management loop...")

        while self.is_running:
            try:
                # Check position sizes and risk metrics
                await self._check_position_risks()

                # Monitor active swaps
                await self._monitor_active_swaps()

                # Update risk metrics
                await self._update_risk_metrics()

                # Wait before next check
                await asyncio.sleep(10)  # Check every 10 seconds

            except Exception as e:
                logger.error("Error in position management loop", error=str(e))
                await asyncio.sleep(5)

    async def _check_position_risks(self) -> None:
        """Check position sizes and risk limits"""
        try:
            # Calculate current exposure
            active_exposure = len(self.active_swaps) * self.max_position_size_usd

            # Log risk metrics
            logger.info("Position risk check",
                       active_swaps=len(self.active_swaps),
                       active_exposure_usd=active_exposure,
                       max_position_size_usd=self.max_position_size_usd)

        except Exception as e:
            logger.error("Error checking position risks", error=str(e))

    async def _monitor_active_swaps(self) -> None:
        """Monitor and manage active swap executions"""
        try:
            # Check for stuck or failed swaps
            completed_swaps = []
            for swap_id, task in self.active_swaps.items():
                if task.done():
                    completed_swaps.append(swap_id)

            # Clean up completed swaps
            for swap_id in completed_swaps:
                del self.active_swaps[swap_id]

        except Exception as e:
            logger.error("Error monitoring active swaps", error=str(e))

    async def _update_risk_metrics(self) -> None:
        """Update risk-related metrics"""
        try:
            # Calculate success rate
            if self.trading_stats["total_swaps"] > 0:
                success_rate = (self.trading_stats["successful_swaps"] / self.trading_stats["total_swaps"]) * 100
            else:
                success_rate = 0.0

            # Log performance metrics
            if self.trading_stats["start_time"]:
                uptime = datetime.now() - self.trading_stats["start_time"]
                swaps_per_hour = (self.trading_stats["total_swaps"] / uptime.total_seconds()) * 3600
            else:
                swaps_per_hour = 0.0

            logger.info("Risk metrics updated",
                       success_rate=success_rate,
                       total_swaps=self.trading_stats["total_swaps"],
                       swaps_per_hour=swaps_per_hour,
                       total_profit_usd=self.trading_stats["total_profit_usd"])

        except Exception as e:
            logger.error("Error updating risk metrics", error=str(e))

    async def _health_monitoring_loop(self) -> None:
        """Health monitoring and system status loop"""
        logger.info("Starting health monitoring loop...")

        while self.is_running:
            try:
                # Check component health
                pipeline_stats = await self.pipeline.get_statistics()
                executor_stats = await self.executor.get_statistics()

                # Log health status
                logger.info("System health check",
                           pipeline_running=pipeline_stats["is_running"],
                           executor_active=len(self.active_swaps),
                           cached_prices=pipeline_stats["cached_prices"],
                           cached_quotes=pipeline_stats["cached_quotes"])

                # Check for any issues
                if not pipeline_stats["is_running"]:
                    logger.error("Jupiter pipeline is not running!")

                if pipeline_stats["cached_prices"] == 0:
                    logger.warning("No cached prices in pipeline")

                # Wait before next check
                await asyncio.sleep(30)  # Check every 30 seconds

            except Exception as e:
                logger.error("Error in health monitoring loop", error=str(e))
                await asyncio.sleep(10)

    def get_trading_statistics(self) -> Dict:
        """Get current trading statistics"""
        stats = self.trading_stats.copy()

        if stats["start_time"]:
            uptime = datetime.now() - stats["start_time"]
            stats["uptime_seconds"] = uptime.total_seconds()
            stats["uptime_formatted"] = str(uptime).split(".")[0]

        if stats["total_swaps"] > 0:
            stats["success_rate"] = (stats["successful_swaps"] / stats["total_swaps"]) * 100
        else:
            stats["success_rate"] = 0.0

        stats["active_swaps"] = len(self.active_swaps)
        stats["is_running"] = self.is_running

        return stats


async def main():
    """Main function to run the Jupiter trading bot"""
    try:
        # Load configuration
        config = {
            "redis_url": os.getenv("REDIS_URL", "redis://localhost:6379"),
            "rpc_url": os.getenv("SOLANA_RPC_URL", "https://api.mainnet-beta.solana.com"),

            # Trading parameters
            "max_position_size_usd": float(os.getenv("MAX_POSITION_SIZE_USD", "1000")),
            "min_profit_pct": float(os.getenv("MIN_PROFIT_PCT", "0.5")),
            "max_slippage_bps": int(os.getenv("MAX_SLIPPAGE_BPS", "100")),
            "max_concurrent_swaps": int(os.getenv("MAX_CONCURRENT_SWAPS", "5")),

            # Component settings
            "price_update_interval": float(os.getenv("PRICE_UPDATE_INTERVAL", "5.0")),
            "arbitrage_check_interval": float(os.getenv("ARBITRAGE_CHECK_INTERVAL", "2.0")),
            "metrics_update_interval": float(os.getenv("METRICS_UPDATE_INTERVAL", "5.0")),
            "metrics_port": int(os.getenv("METRICS_PORT", "9095")),

            # Jito configuration
            "use_jito": os.getenv("USE_JITO", "true").lower() == "true",
            "jito_tip_lamports": int(os.getenv("JITO_TIP_LAMPORTS", "10000")),
            "max_bundle_size": int(os.getenv("MAX_BUNDLE_SIZE", "5")),

            # Monitoring tokens (SOL, USDT, USDC, WBTC, LINK, etc.)
            "monitoring_tokens": [
                "So11111111111111111111111111111111111111112",  # SOL
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY",  # USDT
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
                "9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4",  # WBTC
                "CDJ3U8VdFqk8bLjNKZgCyKJ5aK19ed2TdLiBdMjxwFg",  # LINK
            ]
        }

        # Create and start trading bot
        trading_bot = JupiterTradingBot(config)

        # Handle shutdown gracefully
        import signal
        def signal_handler(signum, frame):
            logger.info("Received shutdown signal, stopping trading bot...")
            asyncio.create_task(trading_bot.stop())

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

        # Start the bot
        await trading_bot.start()

    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt, shutting down...")
    except Exception as e:
        logger.error("Fatal error in main", error=str(e))
        raise


if __name__ == "__main__":
    # Run the Jupiter trading bot
    asyncio.run(main())