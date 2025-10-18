#!/usr/bin/env python3
"""
Jupiter Data Pipeline Module

Real-time data pipeline for Jupiter Price API V3 and Swap API V6 integration.
Provides continuous price monitoring, quote tracking, and arbitrage opportunity detection.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, asdict
import redis.asyncio as redis
from aiohttp import ClientSession, ClientTimeout

from .geyser_client import JupiterPriceClient

logger = logging.getLogger(__name__)

@dataclass
class JupiterPriceEvent:
    """Jupiter price event data structure"""
    token_id: str
    symbol: str
    price: float
    price_change_24h: float
    volume_24h: float
    volume_change_24h: float
    timestamp: datetime
    source: str = "jupiter_api_v3"
    reliability: str = "unknown"

@dataclass
class JupiterQuoteEvent:
    """Jupiter quote event data structure"""
    input_mint: str
    output_mint: str
    input_symbol: str
    output_symbol: str
    in_amount: int
    out_amount: int
    price_impact_pct: float
    quote_id: str
    dexes: List[str]
    timestamp: datetime
    source: str = "jupiter_swap_api_v6"

@dataclass
class ArbitrageOpportunity:
    """Arbitrage opportunity data structure"""
    route_key: str
    input_symbol: str
    output_symbol: str
    buy_price: float
    sell_price: float
    profit_pct: float
    buy_quote: Dict[str, Any]
    sell_quote: Dict[str, Any]
    timestamp: datetime

class JupiterDataPipeline:
    """
    Jupiter data pipeline for real-time price monitoring and arbitrage detection
    """

    def __init__(
        self,
        redis_url: str = "redis://localhost:6379",
        monitoring_tokens: Optional[List[str]] = None,
        price_update_interval: float = 5.0,
        arbitrage_check_interval: float = 2.0
    ):
        """
        Initialize Jupiter data pipeline

        Args:
            redis_url: Redis connection URL
            monitoring_tokens: List of token mint addresses to monitor
            price_update_interval: Price update interval in seconds
            arbitrage_check_interval: Arbitrage check interval in seconds
        """
        self.redis_url = redis_url
        self.redis_client: Optional[redis.Redis] = None
        self.jupiter_client = JupiterPriceClient()

        # Default tokens to monitor (SOL, USDT, USDC, WBTC, LINK, etc.)
        self.monitoring_tokens = monitoring_tokens or [
            "So11111111111111111111111111111111111111112",  # SOL
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY",  # USDT
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
            "9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4",  # WBTC
            "CDJ3U8VdFqk8bLjNKZgCyKJ5aK19ed2TdLiBdMjxwFg",  # LINK
            "2hDzxz8vEM5DHiB4SZZNDnpZ8dqbhNvYDQq2EBsJpump",  # USDE
            "USDSso9sEL8Knk955DJdQGGzo9RJBcGoDNVKY4gouvM",  # USDS
            "J1toso1uCk3RLmjorhTtrVwY9HJ7X8V9yYac6Y7kGCPn",  # CBBTC
            "CZxPwLkHbEZDcNsBBeq3rGmkR7hzkkfENJHhZ3mFgCh",  # SUSDE
            "WLFiZAVKUWSGQq6CDmjg9PqNDxQsTpCfy3cRFGHvN5W",  # WLFI
        ]

        self.price_update_interval = price_update_interval
        self.arbitrage_check_interval = arbitrage_check_interval

        # Pipeline state
        self.is_running = False
        self.price_cache: Dict[str, JupiterPriceEvent] = {}
        self.quote_cache: Dict[str, JupiterQuoteEvent] = {}
        self.last_price_update: Dict[str, float] = {}
        self.last_quote_update: Dict[str, float] = {}

        # Tasks
        self.price_monitor_task: Optional[asyncio.Task] = None
        self.arbitrage_detector_task: Optional[asyncio.Task] = None
        self.cleanup_task: Optional[asyncio.Task] = None

        # Statistics
        self.stats = {
            "price_updates": 0,
            "quotes_generated": 0,
            "arbitrage_opportunities": 0,
            "errors": 0,
            "start_time": None
        }

    async def start(self) -> None:
        """Start the Jupiter data pipeline"""
        try:
            logger.info("Starting Jupiter data pipeline...")

            # Initialize Redis connection
            self.redis_client = redis.from_url(self.redis_url, decode_responses=True)
            await self.redis_client.ping()

            # Set running state
            self.is_running = True
            self.stats["start_time"] = datetime.now()

            # Start monitoring tasks
            self.price_monitor_task = asyncio.create_task(self._price_monitor_loop())
            self.arbitrage_detector_task = asyncio.create_task(self._arbitrage_detector_loop())
            self.cleanup_task = asyncio.create_task(self._cleanup_loop())

            logger.info("Jupiter data pipeline started successfully")

        except Exception as e:
            logger.error(f"Failed to start Jupiter data pipeline: {e}")
            await self.stop()
            raise

    async def stop(self) -> None:
        """Stop the Jupiter data pipeline"""
        try:
            logger.info("Stopping Jupiter data pipeline...")

            self.is_running = False

            # Cancel tasks
            tasks = [
                self.price_monitor_task,
                self.arbitrage_detector_task,
                self.cleanup_task
            ]

            for task in tasks:
                if task and not task.done():
                    task.cancel()
                    try:
                        await task
                    except asyncio.CancelledError:
                        pass

            # Close Redis connection
            if self.redis_client:
                await self.redis_client.close()

            logger.info("Jupiter data pipeline stopped")

        except Exception as e:
            logger.error(f"Error stopping Jupiter data pipeline: {e}")

    async def _price_monitor_loop(self) -> None:
        """Continuous price monitoring loop"""
        logger.info("Starting price monitoring loop...")

        while self.is_running:
            try:
                # Fetch prices for all monitoring tokens
                price_data = await self.jupiter_client.get_token_prices(
                    tokens=self.monitoring_tokens
                )

                if price_data and "data" in price_data:
                    current_time = datetime.now()

                    # Process each token price
                    for token_id, token_info in price_data["data"].items():
                        await self._process_price_update(token_id, token_info, current_time)

                # Publish batch price update
                await self._publish_batch_price_update(price_data)

                self.stats["price_updates"] += 1

            except Exception as e:
                logger.error(f"Error in price monitor loop: {e}")
                self.stats["errors"] += 1

            # Wait for next update
            await asyncio.sleep(self.price_update_interval)

    async def _process_price_update(self, token_id: str, token_info: Dict, timestamp: datetime) -> None:
        """Process individual price update"""
        try:
            # Create price event
            price_event = JupiterPriceEvent(
                token_id=token_id,
                symbol=token_info.get("symbol", "UNKNOWN"),
                price=float(token_info.get("price", 0)),
                price_change_24h=float(token_info.get("priceChange24h", 0)),
                volume_24h=float(token_info.get("volume24h", 0)),
                volume_change_24h=float(token_info.get("volumeChange24h", 0)),
                timestamp=timestamp,
                reliability=token_info.get("reliability", "unknown")
            )

            # Update cache
            self.price_cache[token_id] = price_event
            self.last_price_update[token_id] = timestamp.timestamp()

            # Publish to Redis
            await self._publish_price_event(price_event)

        except Exception as e:
            logger.error(f"Error processing price update for {token_id}: {e}")

    async def _arbitrage_detector_loop(self) -> None:
        """Arbitrage opportunity detection loop"""
        logger.info("Starting arbitrage detection loop...")

        while self.is_running:
            try:
                # Generate quotes for monitoring pairs
                await self._generate_arbitrage_quotes()

                # Detect arbitrage opportunities
                opportunities = await self._detect_arbitrage_opportunities()

                # Publish opportunities
                for opportunity in opportunities:
                    await self._publish_arbitrage_opportunity(opportunity)
                    self.stats["arbitrage_opportunities"] += 1

                self.stats["quotes_generated"] += len(self.price_cache) * 2  # Approximate

            except Exception as e:
                logger.error(f"Error in arbitrage detector loop: {e}")
                self.stats["errors"] += 1

            # Wait for next check
            await asyncio.sleep(self.arbitrage_check_interval)

    async def _generate_arbitrage_quotes(self) -> None:
        """Generate quotes for arbitrage detection"""
        # Define key trading pairs (SOL/USDC, USDT/USDC, WBTC/USDC, etc.)
        trading_pairs = [
            ("So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # SOL/USDC
            ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # USDT/USDC
            ("9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # WBTC/USDC
            ("CDJ3U8VdFqk8bLjNKZgCyKJ5aK19ed2TdLiBdMjxwFg", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # LINK/USDC
        ]

        for input_mint, output_mint in trading_pairs:
            try:
                # Generate quote (1 unit of input token)
                quote = await self.jupiter_client.get_swap_quote(
                    input_mint=input_mint,
                    output_mint=output_mint,
                    amount=1_000_000  # 1 unit (assuming 6 decimals)
                )

                if quote:
                    await self._process_quote_update(quote, input_mint, output_mint)

            except Exception as e:
                logger.error(f"Error generating quote for {input_mint[:8]}...{output_mint[:8]}: {e}")

    async def _process_quote_update(self, quote: Dict, input_mint: str, output_mint: str) -> None:
        """Process individual quote update"""
        try:
            # Get token symbols from price cache
            input_symbol = self.price_cache.get(input_mint, JupiterPriceEvent(
                token_id=input_mint, symbol="INPUT", price=0, price_change_24h=0,
                volume_24h=0, volume_change_24h=0, timestamp=datetime.now()
            )).symbol

            output_symbol = self.price_cache.get(output_mint, JupiterPriceEvent(
                token_id=output_mint, symbol="OUTPUT", price=0, price_change_24h=0,
                volume_24h=0, volume_change_24h=0, timestamp=datetime.now()
            )).symbol

            # Create quote event
            quote_event = JupiterQuoteEvent(
                input_mint=input_mint,
                output_mint=output_mint,
                input_symbol=input_symbol,
                output_symbol=output_symbol,
                in_amount=int(quote.get("inAmount", 0)),
                out_amount=int(quote.get("outAmount", 0)),
                price_impact_pct=float(quote.get("priceImpactPct", 0)),
                quote_id=quote.get("quoteId", ""),
                dexes=quote.get("routePlan", [{}])[0].get("swapInfo", {}).get("dexKey", "unknown"),
                timestamp=datetime.now()
            )

            # Update cache
            route_key = f"{input_mint[:8]}-{output_mint[:8]}"
            self.quote_cache[route_key] = quote_event
            self.last_quote_update[route_key] = datetime.now().timestamp()

            # Publish to Redis
            await self._publish_quote_event(quote_event)

        except Exception as e:
            logger.error(f"Error processing quote update: {e}")

    async def _detect_arbitrage_opportunities(self) -> List[ArbitrageOpportunity]:
        """Detect arbitrage opportunities from cached quotes"""
        opportunities = []

        try:
            # For simplicity, check for reverse route arbitrage
            for route_key, quote_event in self.quote_cache.items():
                # Generate reverse quote
                reverse_quote = await self.jupiter_client.get_swap_quote(
                    input_mint=quote_event.output_mint,
                    output_mint=quote_event.input_mint,
                    amount=quote_event.out_amount
                )

                if reverse_quote:
                    # Calculate potential profit
                    reverse_out = int(reverse_quote.get("outAmount", 0))
                    profit = reverse_out - quote_event.in_amount
                    profit_pct = (profit / quote_event.in_amount) * 100

                    # If profitable (>0.1%), create opportunity
                    if profit_pct > 0.1:
                        opportunity = ArbitrageOpportunity(
                            route_key=route_key,
                            input_symbol=quote_event.input_symbol,
                            output_symbol=quote_event.output_symbol,
                            buy_price=float(quote_event.out_amount) / float(quote_event.in_amount),
                            sell_price=float(reverse_out) / float(quote_event.out_amount),
                            profit_pct=profit_pct,
                            buy_quote=asdict(quote_event),
                            sell_quote=reverse_quote,
                            timestamp=datetime.now()
                        )
                        opportunities.append(opportunity)

        except Exception as e:
            logger.error(f"Error detecting arbitrage opportunities: {e}")

        return opportunities

    async def _publish_price_event(self, price_event: JupiterPriceEvent) -> None:
        """Publish price event to Redis"""
        try:
            channel = f"jupiter:price:{price_event.symbol.lower()}"
            message = asdict(price_event)
            message["timestamp"] = price_event.timestamp.isoformat()

            await self.redis_client.publish(channel, json.dumps(message))

            # Store in sorted set for history
            score = price_event.timestamp.timestamp()
            await self.redis_client.zadd(
                f"jupiter:history:{price_event.symbol.lower()}",
                {json.dumps(message): score}
            )

            # Keep only last 24 hours
            await self.redis_client.zremrangebyscore(
                f"jupiter:history:{price_event.symbol.lower()}",
                0, score - 86400
            )

        except Exception as e:
            logger.error(f"Error publishing price event: {e}")

    async def _publish_quote_event(self, quote_event: JupiterQuoteEvent) -> None:
        """Publish quote event to Redis"""
        try:
            channel = f"jupiter:quote:{quote_event.input_symbol.lower()}-{quote_event.output_symbol.lower()}"
            message = asdict(quote_event)
            message["timestamp"] = quote_event.timestamp.isoformat()

            await self.redis_client.publish(channel, json.dumps(message))

            # Store for arbitrage detection (30 second TTL)
            route_key = f"{quote_event.input_mint[:8]}-{quote_event.output_mint[:8]}"
            await self.redis_client.hset(
                "jupiter:arbitrage:quotes",
                route_key,
                json.dumps(message)
            )
            await self.redis_client.expire("jupiter:arbitrage:quotes", 30)

        except Exception as e:
            logger.error(f"Error publishing quote event: {e}")

    async def _publish_arbitrage_opportunity(self, opportunity: ArbitrageOpportunity) -> None:
        """Publish arbitrage opportunity to Redis"""
        try:
            message = asdict(opportunity)
            message["timestamp"] = opportunity.timestamp.isoformat()

            await self.redis_client.publish("jupiter:arbitrage:opportunities", json.dumps(message))

            # Store in sorted set with priority based on profit percentage
            score = opportunity.profit_pct
            await self.redis_client.zadd(
                "jupiter:arbitrage:active_opportunities",
                {json.dumps(message): score}
            )

            # Keep only last 100 opportunities
            await self.redis_client.zremrangebyrank(
                "jupiter:arbitrage:active_opportunities",
                0, -101
            )

            logger.info(f"Arbitrage opportunity: {opportunity.input_symbol}/{opportunity.output_symbol} - {opportunity.profit_pct:.2f}% profit")

        except Exception as e:
            logger.error(f"Error publishing arbitrage opportunity: {e}")

    async def _publish_batch_price_update(self, price_data: Dict) -> None:
        """Publish batch price update to Redis"""
        try:
            message = {
                "data": price_data,
                "timestamp": datetime.now().isoformat(),
                "source": "jupiter_api_v3"
            }

            await self.redis_client.publish("jupiter:prices:batch", json.dumps(message))

            # Store latest prices
            if "data" in price_data:
                await self.redis_client.hset(
                    "jupiter:latest_prices",
                    mapping={
                        token_id: json.dumps(token_info)
                        for token_id, token_info in price_data["data"].items()
                    }
                )

        except Exception as e:
            logger.error(f"Error publishing batch price update: {e}")

    async def _cleanup_loop(self) -> None:
        """Cleanup old data loop"""
        logger.info("Starting cleanup loop...")

        while self.is_running:
            try:
                current_time = time.time()

                # Clean old price cache entries (older than 5 minutes)
                expired_tokens = [
                    token_id for token_id, last_update in self.last_price_update.items()
                    if current_time - last_update > 300
                ]

                for token_id in expired_tokens:
                    del self.price_cache[token_id]
                    del self.last_price_update[token_id]

                # Clean old quote cache entries (older than 30 seconds)
                expired_quotes = [
                    route_key for route_key, last_update in self.last_quote_update.items()
                    if current_time - last_update > 30
                ]

                for route_key in expired_quotes:
                    del self.quote_cache[route_key]
                    del self.last_quote_update[route_key]

                logger.debug(f"Cleaned {len(expired_tokens)} old price entries and {len(expired_quotes)} old quote entries")

            except Exception as e:
                logger.error(f"Error in cleanup loop: {e}")

            # Run cleanup every minute
            await asyncio.sleep(60)

    async def get_statistics(self) -> Dict[str, Any]:
        """Get pipeline statistics"""
        stats = self.stats.copy()

        if stats["start_time"]:
            uptime = datetime.now() - stats["start_time"]
            stats["uptime_seconds"] = uptime.total_seconds()
            stats["uptime_formatted"] = str(uptime).split(".")[0]

        stats["cached_prices"] = len(self.price_cache)
        stats["cached_quotes"] = len(self.quote_cache)
        stats["monitoring_tokens"] = len(self.monitoring_tokens)
        stats["is_running"] = self.is_running

        return stats

    async def get_current_prices(self) -> Dict[str, JupiterPriceEvent]:
        """Get current cached prices"""
        return self.price_cache.copy()

    async def get_current_quotes(self) -> Dict[str, JupiterQuoteEvent]:
        """Get current cached quotes"""
        return self.quote_cache.copy()