#!/usr/bin/env python3
"""
Statistical Arbitrage Integration Module

Advanced pairs trading system with cointegration testing, z-score calculations,
and integration with Jupiter Price API V3 and Swap API V6.
Bridges Rust statistical engine with Python orchestration layer.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
import numpy as np
import pandas as pd
from scipy import stats
import redis.asyncio as redis
from aiohttp import ClientSession, ClientTimeout
import structlog

from .jupiter_pipeline import JupiterPriceClient
from .jupiter_executor import JupiterSwapExecutor, SwapExecutionRequest

logger = structlog.get_logger()

@dataclass
class StatisticalArbitrageConfig:
    """Configuration for statistical arbitrage system"""
    # Trading parameters
    min_correlation: float = 0.3
    max_correlation: float = 0.95
    cointegration_significance: float = 0.05
    entry_z_threshold: float = 2.0
    exit_z_threshold: float = 0.5
    stop_loss_z_threshold: float = 4.0

    # Data parameters
    min_history_points: int = 100
    max_history_points: int = 1000
    update_interval_seconds: int = 60
    price_history_hours: int = 24  # Hours of price history to maintain

    # Risk management
    min_profit_bps: int = 25  # 0.25%
    max_position_size_usd: float = 5000.0
    max_concurrent_positions: int = 5
    position_timeout_minutes: int = 60

    # Token pairs to monitor
    monitored_pairs: List[Tuple[str, str]] = None

    def __post_init__(self):
        if self.monitored_pairs is None:
            self.monitored_pairs = [
                ("So11111111111111111111111111111111111111112", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # SOL/USDC
                ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # USDT/USDC
                ("9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # WBTC/USDC
                ("CDJ3U8VdFqk8bLjNKZgCyKJ5aK19ed2TdLiBdMjxwFg", "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),  # LINK/USDC
            ]

@dataclass
class TradingPair:
    """Trading pair information"""
    token_a: str
    token_b: str
    symbol_a: str
    symbol_b: str
    correlation: float
    hedge_ratio: float
    cointegration_p_value: float
    is_cointegrated: bool
    last_updated: datetime
    half_life: float
    hurst_exponent: float

@dataclass
class StatisticalArbitrageOpportunity:
    """Statistical arbitrage opportunity"""
    pair: TradingPair
    current_price_a: float
    current_price_b: float
    current_spread: float
    current_z_score: float
    expected_spread_mean: float
    spread_std_dev: float
    deviation_percentage: float
    confidence_score: float
    signal_type: str  # "LONG_A_SHORT_B", "SHORT_A_LONG_B", "CLOSE"
    holding_period_secs: int
    expected_return: float
    risk_score: float
    entry_threshold: float
    exit_threshold: float
    stop_loss_threshold: float
    timestamp: datetime

@dataclass
class Position:
    """Active statistical arbitrage position"""
    pair_key: str
    signal_type: str
    entry_price_a: float
    entry_price_b: float
    entry_spread: float
    entry_z_score: float
    position_size_usd: float
    entry_time: datetime
    expected_holding_period_secs: int
    stop_loss_threshold: float
    take_profit_threshold: float

class StatisticalArbitrageEngine:
    """
    Advanced statistical arbitrage engine with real-time Jupiter integration
    """

    def __init__(
        self,
        config: StatisticalArbitrageConfig,
        redis_url: str = "redis://localhost:6379",
        jupiter_client: Optional[JupiterPriceClient] = None,
        swap_executor: Optional[JupiterSwapExecutor] = None
    ):
        """
        Initialize statistical arbitrage engine

        Args:
            config: Statistical arbitrage configuration
            redis_url: Redis connection URL
            jupiter_client: Jupiter price client (optional, will create if None)
            swap_executor: Jupiter swap executor (optional, will create if None)
        """
        self.config = config
        self.redis_url = redis_url
        self.jupiter_client = jupiter_client or JupiterPriceClient()
        self.swap_executor = swap_executor

        # Data storage
        self.price_histories: Dict[str, pd.DataFrame] = {}  # pair_key -> DataFrame
        self.trading_pairs: Dict[str, TradingPair] = {}
        self.active_opportunities: Dict[str, StatisticalArbitrageOpportunity] = {}
        self.active_positions: Dict[str, Position] = {}

        # State management
        self.is_running = False
        self.last_update = datetime.now()
        self.update_task: Optional[asyncio.Task] = None
        self.execution_task: Optional[asyncio.Task] = None
        self.position_monitor_task: Optional[asyncio.Task] = None

        # Initialize Redis client
        self.redis_client: Optional[redis.Redis] = None

        # Performance statistics
        self.stats = {
            "total_opportunities": 0,
            "executed_trades": 0,
            "successful_trades": 0,
            "total_profit_usd": 0.0,
            "total_fees_paid": 0.0,
            "average_holding_time_minutes": 0.0,
            "start_time": None
        }

    async def start(self) -> None:
        """Start the statistical arbitrage engine"""
        try:
            logger.info("Starting statistical arbitrage engine...")

            # Initialize Redis connection
            self.redis_client = redis.from_url(self.redis_url, decode_responses=True)
            await self.redis_client.ping()

            # Load historical price data
            await self.load_historical_data()

            # Start background tasks
            self.is_running = True
            self.stats["start_time"] = datetime.now()

            self.update_task = asyncio.create_task(self._update_loop())
            self.execution_task = asyncio.create_task(self._execution_loop())
            self.position_monitor_task = asyncio.create_task(self._position_monitor_loop())

            logger.info("Statistical arbitrage engine started successfully")

        except Exception as e:
            logger.error("Failed to start statistical arbitrage engine", error=str(e))
            await self.stop()
            raise

    async def stop(self) -> None:
        """Stop the statistical arbitrage engine"""
        try:
            logger.info("Stopping statistical arbitrage engine...")

            self.is_running = False

            # Cancel background tasks
            tasks = [
                self.update_task,
                self.execution_task,
                self.position_monitor_task
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

            logger.info("Statistical arbitrage engine stopped")

        except Exception as e:
            logger.error("Error stopping statistical arbitrage engine", error=str(e))

    async def load_historical_data(self) -> None:
        """Load historical price data for all monitored pairs"""
        try:
            logger.info("Loading historical price data...")

            current_time = datetime.now()
            start_time = current_time - timedelta(hours=self.config.price_history_hours)

            for token_a, token_b in self.config.monitored_pairs:
                pair_key = f"{token_a[:8]}-{token_b[:8]}"

                try:
                    # Fetch historical prices from Jupiter API
                    prices_a = await self._fetch_historical_prices(token_a, start_time, current_time)
                    prices_b = await self._fetch_historical_prices(token_b, start_time, current_time)

                    if prices_a and prices_b:
                        # Create DataFrame with aligned timestamps
                        df = pd.DataFrame({
                            'timestamp': list(prices_a.keys()),
                            'price_a': list(prices_a.values()),
                            'price_b': [prices_b.get(ts, np.nan) for ts in prices_a.keys()]
                        })

                        # Remove rows with missing data
                        df = df.dropna()

                        if len(df) >= self.config.min_history_points:
                            # Calculate returns
                            df['return_a'] = df['price_a'].pct_change()
                            df['return_b'] = df['price_b'].pct_change()
                            df = df.dropna()

                            # Store price history
                            self.price_histories[pair_key] = df

                            # Analyze pair
                            await self._analyze_pair(pair_key, token_a, token_b, df)

                            logger.info(f"Loaded {len(df)} data points for pair {pair_key}")
                        else:
                            logger.warning(f"Insufficient data for pair {pair_key}: {len(df)} points")
                    else:
                        logger.warning(f"Failed to fetch historical data for pair {pair_key}")

                except Exception as e:
                    logger.error(f"Error loading data for pair {pair_key}", error=str(e))

            logger.info(f"Loaded historical data for {len(self.price_histories)} pairs")

        except Exception as e:
            logger.error("Error loading historical data", error=str(e))

    async def _update_loop(self) -> None:
        """Main update loop for price data and analysis"""
        logger.info("Starting statistical arbitrage update loop...")

        while self.is_running:
            try:
                start_time = time.time()

                # Update price data
                await self._update_price_data()

                # Analyze pairs for opportunities
                await self._scan_opportunities()

                # Publish statistics to Redis
                await self._publish_statistics()

                update_time = time.time() - start_time
                logger.debug(f"Update completed in {update_time:.2f}s")

                # Wait for next update
                await asyncio.sleep(self.config.update_interval_seconds)

            except Exception as e:
                logger.error("Error in update loop", error=str(e))
                await asyncio.sleep(10)

    async def _update_price_data(self) -> None:
        """Update price data for all monitored pairs"""
        try:
            current_time = datetime.now()

            for token_a, token_b in self.config.monitored_pairs:
                pair_key = f"{token_a[:8]}-{token_b[:8]}"

                try:
                    # Fetch current prices
                    price_a = await self._fetch_current_price(token_a)
                    price_b = await self._fetch_current_price(token_b)

                    if price_a and price_b:
                        # Update price history
                        if pair_key not in self.price_histories:
                            self.price_histories[pair_key] = pd.DataFrame(columns=[
                                'timestamp', 'price_a', 'price_b', 'return_a', 'return_b'
                            ])

                        # Add new data point
                        new_row = pd.DataFrame([{
                            'timestamp': current_time,
                            'price_a': price_a,
                            'price_b': price_b,
                            'return_a': np.nan,  # Will be calculated below
                            'return_b': np.nan
                        }])

                        df = pd.concat([self.price_histories[pair_key], new_row], ignore_index=True)

                        # Calculate returns
                        if len(df) > 1:
                            df.loc[df.index[-1], 'return_a'] = df['price_a'].iloc[-1] / df['price_a'].iloc[-2] - 1
                            df.loc[df.index[-1], 'return_b'] = df['price_b'].iloc[-1] / df['price_b'].iloc[-2] - 1

                        # Limit history size
                        if len(df) > self.config.max_history_points:
                            df = df.tail(self.config.max_history_points).copy()

                        self.price_histories[pair_key] = df

                        # Re-analyze pair if we have enough data
                        if len(df) >= self.config.min_history_points:
                            await self._analyze_pair(pair_key, token_a, token_b, df)

                except Exception as e:
                    logger.error(f"Error updating pair {pair_key}", error=str(e))

        except Exception as e:
            logger.error("Error updating price data", error=str(e))

    async def _analyze_pair(self, pair_key: str, token_a: str, token_b: str, df: pd.DataFrame) -> None:
        """Analyze trading pair for cointegration and statistical properties"""
        try:
            if len(df) < self.config.min_history_points:
                return

            # Calculate correlation
            correlation = df['return_a'].corr(df['return_b'])

            # Skip if correlation is outside acceptable range
            if correlation < self.config.min_correlation or correlation > self.config.max_correlation:
                return

            # Test for cointegration
            hedge_ratio, cointegration_p_value = self._test_cointegration(
                df['price_a'].values, df['price_b'].values
            )

            # Calculate spread and z-scores
            spread = df['price_a'] - hedge_ratio * df['price_b']
            spread_mean = spread.mean()
            spread_std = spread.std()
            z_scores = (spread - spread_mean) / spread_std

            # Calculate Hurst exponent
            hurst_exponent = self._calculate_hurst_exponent(spread.values)

            # Calculate half-life
            half_life = self._calculate_half_life(spread.values)

            # Create trading pair object
            pair = TradingPair(
                token_a=token_a,
                token_b=token_b,
                symbol_a=await self._get_token_symbol(token_a),
                symbol_b=await self._get_token_symbol(token_b),
                correlation=correlation,
                hedge_ratio=hedge_ratio,
                cointegration_p_value=cointegration_p_value,
                is_cointegrated=cointegration_p_value < self.config.cointegration_significance,
                last_updated=datetime.now(),
                half_life=half_life,
                hurst_exponent=hurst_exponent
            )

            self.trading_pairs[pair_key] = pair

            # Update price history with calculated values
            df['spread'] = spread
            df['z_score'] = z_scores
            self.price_histories[pair_key] = df

            logger.debug(f"Analyzed pair {pair_key}: correlation={correlation:.3f}, "
                        f"cointegrated={pair.is_cointegrated}, hurst={hurst_exponent:.3f}")

        except Exception as e:
            logger.error(f"Error analyzing pair {pair_key}", error=str(e))

    async def _scan_opportunities(self) -> None:
        """Scan all pairs for statistical arbitrage opportunities"""
        try:
            new_opportunities = {}

            for pair_key, pair in self.trading_pairs.items():
                # Skip if not cointegrated or no price history
                if not pair.is_cointegrated or pair_key not in self.price_histories:
                    continue

                df = self.price_histories[pair_key]
                if len(df) < 2:
                    continue

                # Get current values
                current_spread = df['spread'].iloc[-1]
                current_z_score = df['z_score'].iloc[-1]
                spread_mean = df['spread'].mean()
                spread_std = df['spread'].std()

                # Determine signal type
                signal_type = self._determine_signal_type(current_z_score)

                # Skip if no signal
                signal_type == "NO_SIGNAL":
                    continue

                # Calculate opportunity metrics
                expected_return = self._calculate_expected_return(
                    current_z_score, spread_std, signal_type
                )
                confidence_score = self._calculate_confidence_score(
                    current_z_score, pair.correlation, pair.cointegration_p_value, pair.hurst_exponent
                )
                risk_score = self._calculate_risk_score(
                    current_z_score, spread_std, pair.hurst_exponent, pair.correlation
                )

                # Skip if minimum thresholds not met
                if confidence_score < 0.3 or expected_return < (self.config.min_profit_bps / 10000):
                    continue

                # Calculate holding period
                holding_period_secs = int(pair.half_life * 3600)

                # Create opportunity
                opportunity = StatisticalArbitrageOpportunity(
                    pair=pair,
                    current_price_a=df['price_a'].iloc[-1],
                    current_price_b=df['price_b'].iloc[-1],
                    current_spread=current_spread,
                    current_z_score=current_z_score,
                    expected_spread_mean=spread_mean,
                    spread_std_dev=spread_std,
                    deviation_percentage=abs(current_spread - spread_mean) / spread_mean * 100,
                    confidence_score=confidence_score,
                    signal_type=signal_type,
                    holding_period_secs=holding_period_secs,
                    expected_return=expected_return,
                    risk_score=risk_score,
                    entry_threshold=self.config.entry_z_threshold,
                    exit_threshold=self.config.exit_z_threshold,
                    stop_loss_threshold=self.config.stop_loss_z_threshold,
                    timestamp=datetime.now()
                )

                new_opportunities[pair_key] = opportunity

            self.active_opportunities = new_opportunities

            if new_opportunities:
                logger.info(f"Found {len(new_opportunities)} statistical arbitrage opportunities")

                # Publish opportunities to Redis
                await self._publish_opportunities()

        except Exception as e:
            logger.error("Error scanning opportunities", error=str(e))

    def _determine_signal_type(self, z_score: float) -> str:
        """Determine signal type based on z-score"""
        if z_score > self.config.entry_z_threshold:
            return "SHORT_A_LONG_B"  # Spread too wide, short A long B
        elif z_score < -self.config.entry_z_threshold:
            return "LONG_A_SHORT_B"  # Spread too narrow, long A short B
        elif abs(z_score) < self.config.exit_z_threshold:
            return "CLOSE"  # Mean reversion achieved
        else:
            return "NO_SIGNAL"

    async def _execution_loop(self) -> None:
        """Main execution loop for statistical arbitrage opportunities"""
        logger.info("Starting statistical arbitrage execution loop...")

        while self.is_running:
            try:
                # Check if we can open new positions
                if len(self.active_positions) >= self.config.max_concurrent_positions:
                    await asyncio.sleep(10)
                    continue

                # Find best opportunity to execute
                best_opportunity = self._select_best_opportunity()

                if best_opportunity:
                    await self._execute_opportunity(best_opportunity)

                # Wait before next execution check
                await asyncio.sleep(5)

            except Exception as e:
                logger.error("Error in execution loop", error=str(e))
                await asyncio.sleep(10)

    def _select_best_opportunity(self) -> Optional[StatisticalArbitrageOpportunity]:
        """Select the best opportunity to execute based on risk-adjusted return"""
        if not self.active_opportunities:
            return None

        # Filter out opportunities for pairs we already have positions in
        available_opportunities = [
            opp for key, opp in self.active_opportunities.items()
            if not any(opp.pair.token_a == pos.pair_key.split('-')[0] or
                      opp.pair.token_b == pos.pair_key.split('-')[1]
                      for pos in self.active_positions.values())
        ]

        if not available_opportunities:
            return None

        # Sort by risk-adjusted return (expected return / risk score)
        available_opportunities.sort(
            key=lambda opp: (opp.expected_return / max(opp.risk_score, 0.01)) * opp.confidence_score,
            reverse=True
        )

        return available_opportunities[0]

    async def _execute_opportunity(self, opportunity: StatisticalArbitrageOpportunity) -> None:
        """Execute a statistical arbitrage opportunity"""
        try:
            pair_key = f"{opportunity.pair.token_a[:8]}-{opportunity.pair.token_b[:8]}"

            logger.info(f"Executing statistical arbitrage opportunity for {pair_key}",
                       signal_type=opportunity.signal_type,
                       expected_return=opportunity.expected_return,
                       confidence=opportunity.confidence_score)

            # Calculate position size
            position_size_usd = min(
                self.config.max_position_size_usd,
                1000.0  # Conservative starting size
            )

            # Create position
            position = Position(
                pair_key=pair_key,
                signal_type=opportunity.signal_type,
                entry_price_a=opportunity.current_price_a,
                entry_price_b=opportunity.current_price_b,
                entry_spread=opportunity.current_spread,
                entry_z_score=opportunity.current_z_score,
                position_size_usd=position_size_usd,
                entry_time=datetime.now(),
                expected_holding_period_secs=opportunity.holding_period_secs,
                stop_loss_threshold=opportunity.stop_loss_threshold,
                take_profit_threshold=opportunity.exit_threshold
            )

            # Execute trades based on signal type
            if opportunity.signal_type == "LONG_A_SHORT_B":
                success = await self._execute_long_a_short_b(opportunity, position)
            elif opportunity.signal_type == "SHORT_A_LONG_B":
                success = await self._execute_short_a_long_b(opportunity, position)
            else:
                return  # Skip CLOSE signals in execution loop

            if success:
                self.active_positions[pair_key] = position
                self.stats["executed_trades"] += 1

                logger.info(f"Successfully executed statistical arbitrage position for {pair_key}")
            else:
                logger.warning(f"Failed to execute statistical arbitrage position for {pair_key}")

        except Exception as e:
            logger.error("Error executing opportunity", error=str(e))

    async def _execute_long_a_short_b(
        self,
        opportunity: StatisticalArbitrageOpportunity,
        position: Position
    ) -> bool:
        """Execute long A short B position"""
        try:
            if not self.swap_executor:
                logger.warning("No swap executor available")
                return False

            # Calculate trade amounts
            amount_a = position.position_size_usd / opportunity.current_price_a
            amount_b = amount_a * opportunity.pair.hedge_ratio

            # For now, simulate execution
            # In production, this would execute actual swaps via Jupiter

            logger.info(f"Simulated LONG_A_SHORT_B execution: "
                       f"Long {amount_a:.6f} {opportunity.pair.symbol_a}, "
                       f"Short {amount_b:.6f} {opportunity.pair.symbol_b}")

            return True

        except Exception as e:
            logger.error("Error executing long A short B", error=str(e))
            return False

    async def _execute_short_a_long_b(
        self,
        opportunity: StatisticalArbitrageOpportunity,
        position: Position
    ) -> bool:
        """Execute short A long B position"""
        try:
            if not self.swap_executor:
                logger.warning("No swap executor available")
                return False

            # Calculate trade amounts
            amount_a = position.position_size_usd / opportunity.current_price_a
            amount_b = amount_a * opportunity.pair.hedge_ratio

            # For now, simulate execution
            # In production, this would execute actual swaps via Jupiter

            logger.info(f"Simulated SHORT_A_LONG_B execution: "
                       f"Short {amount_a:.6f} {opportunity.pair.symbol_a}, "
                       f"Long {amount_b:.6f} {opportunity.pair.symbol_b}")

            return True

        except Exception as e:
            logger.error("Error executing short A long B", error=str(e))
            return False

    async def _position_monitor_loop(self) -> None:
        """Monitor and manage active positions"""
        logger.info("Starting position monitoring loop...")

        while self.is_running:
            try:
                current_time = datetime.now()
                positions_to_close = []

                for pair_key, position in self.active_positions.items():
                    # Check if position should be closed
                    should_close, close_reason = await self._should_close_position(
                        pair_key, position, current_time
                    )

                    if should_close:
                        positions_to_close.append((pair_key, position, close_reason))

                # Close positions that need closing
                for pair_key, position, reason in positions_to_close:
                    await self._close_position(pair_key, position, reason)

                # Wait before next check
                await asyncio.sleep(10)

            except Exception as e:
                logger.error("Error in position monitoring loop", error=str(e))
                await asyncio.sleep(10)

    async def _should_close_position(
        self,
        pair_key: str,
        position: Position,
        current_time: datetime
    ) -> Tuple[bool, str]:
        """Determine if a position should be closed"""
        try:
            # Check timeout
            time_elapsed = (current_time - position.entry_time).total_seconds()
            if time_elapsed > position.expected_holding_period_secs * 2:
                return True, "TIMEOUT"

            # Get current spread and z-score
            if pair_key not in self.price_histories:
                return False, ""

            df = self.price_histories[pair_key]
            if len(df) == 0:
                return False, ""

            current_spread = df['spread'].iloc[-1]
            current_z_score = df['z_score'].iloc[-1]

            # Check take profit (z-score crossed zero)
            if (position.signal_type == "LONG_A_SHORT_B" and current_z_score > -position.take_profit_threshold) or \
               (position.signal_type == "SHORT_A_LONG_B" and current_z_score < position.take_profit_threshold):
                return True, "TAKE_PROFIT"

            # Check stop loss
            if abs(current_z_score) > position.stop_loss_threshold:
                return True, "STOP_LOSS"

            return False, ""

        except Exception as e:
            logger.error(f"Error checking if position {pair_key} should close", error=str(e))
            return False, ""

    async def _close_position(self, pair_key: str, position: Position, reason: str) -> None:
        """Close a statistical arbitrage position"""
        try:
            logger.info(f"Closing position {pair_key} due to {reason}",
                       entry_time=position.entry_time,
                       holding_time=(datetime.now() - position.entry_time).total_seconds())

            # Calculate P&L (simplified)
            if pair_key in self.price_histories:
                df = self.price_histories[pair_key]
                current_spread = df['spread'].iloc[-1] if len(df) > 0 else position.entry_spread

                # Calculate profit based on spread reversion
                spread_change = (position.entry_spread - current_spread) * position.position_size_usd / position.entry_spread

                self.stats["total_profit_usd"] += spread_change

                if spread_change > 0:
                    self.stats["successful_trades"] += 1

                # Update average holding time
                holding_time_minutes = (datetime.now() - position.entry_time).total_seconds() / 60
                total_trades = self.stats["executed_trades"]
                if total_trades > 0:
                    self.stats["average_holding_time_minutes"] = (
                        (self.stats["average_holding_time_minutes"] * (total_trades - 1) + holding_time_minutes) / total_trades
                    )

            # Remove from active positions
            del self.active_positions[pair_key]

            # Publish position close to Redis
            await self._publish_position_close(pair_key, position, reason)

        except Exception as e:
            logger.error(f"Error closing position {pair_key}", error=str(e))

    # Statistical analysis methods
    def _test_cointegration(self, x: np.ndarray, y: np.ndarray) -> Tuple[float, float]:
        """Test for cointegration using Engle-Granger method"""
        try:
            # Perform linear regression to find hedge ratio
            slope, intercept, _, _, _ = stats.linregress(x, y)
            hedge_ratio = slope

            # Calculate residuals
            residuals = y - (hedge_ratio * x + intercept)

            # Perform Augmented Dickey-Fuller test on residuals
            # Using simplified implementation
            # In production, use statsmodels.tsa.stattools.adfuller

            # Calculate first differences
            diff_residuals = np.diff(residuals)

            if len(diff_residuals) < 10:
                return hedge_ratio, 1.0  # Not enough data

            # Simple test statistic
            mean_diff = np.mean(diff_residuals)
            std_diff = np.std(diff_residuals)

            if std_diff > 0:
                test_statistic = mean_diff / std_diff
                # Approximate p-value
                if test_statistic < -3.0:
                    p_value = 0.01
                elif test_statistic < -2.5:
                    p_value = 0.05
                elif test_statistic < -2.0:
                    p_value = 0.10
                else:
                    p_value = 0.50
            else:
                p_value = 1.0

            return hedge_ratio, p_value

        except Exception as e:
            logger.error("Error in cointegration test", error=str(e))
            return 1.0, 1.0

    def _calculate_hurst_exponent(self, series: np.ndarray) -> float:
        """Calculate Hurst exponent (0-0.5: mean reversion, 0.5-1: trending)"""
        try:
            if len(series) < 20:
                return 0.5  # Default to random walk

            # Simplified Hurst exponent calculation
            # Calculate rescaled range for different window sizes
            window_sizes = [10, 20, min(len(series) // 4, 50)]
            log_rs = []
            log_n = []

            for window_size in window_sizes:
                if window_size >= len(series):
                    continue

                rs_values = []

                for i in range(len(series) - window_size + 1):
                    window = series[i:i + window_size]
                    window_mean = np.mean(window)
                    window_std = np.std(window)

                    if window_std > 0:
                        # Calculate cumulative deviation
                        cum_dev = np.cumsum(window - window_mean)
                        range_val = np.max(cum_dev) - np.min(cum_dev)
                        rs = range_val / window_std
                        rs_values.append(rs)

                if rs_values:
                    avg_rs = np.mean(rs_values)
                    log_rs.append(np.log(avg_rs))
                    log_n.append(np.log(window_size))

            if len(log_rs) >= 2:
                # Calculate slope (Hurst exponent)
                slope, _, _, _, _ = stats.linregress(log_n, log_rs)
                return np.clip(slope, 0.0, 1.0)
            else:
                return 0.5

        except Exception as e:
            logger.error("Error calculating Hurst exponent", error=str(e))
            return 0.5

    def _calculate_half_life(self, spread: np.ndarray) -> float:
        """Calculate half-life of mean reversion"""
        try:
            if len(spread) < 10:
                return 24.0  # Default 24 hours

            # Calculate changes in spread
            delta_spread = np.diff(spread)
            lagged_spread = spread[:-1]

            if len(lagged_spread) == 0 or len(delta_spread) == 0:
                return 24.0

            # Run regression: delta_spread = alpha + beta * lagged_spread
            slope, _, _, _, _ = stats.linregress(lagged_spread, delta_spread)

            # Half-life = -ln(2) / beta
            if slope <= 0:
                return 24.0  # Default if not mean reverting

            half_life = -0.693147 / slope  # -ln(2) / slope
            return np.clip(half_life, 1.0, 168.0)  # Clamp between 1 hour and 1 week

        except Exception as e:
            logger.error("Error calculating half-life", error=str(e))
            return 24.0

    def _calculate_expected_return(self, z_score: float, spread_std: float, signal_type: str) -> float:
        """Calculate expected return based on z-score and signal"""
        expected_z_reversion = {
            "LONG_A_SHORT_B": -abs(z_score),  # Expect negative z-score to revert to 0
            "SHORT_A_LONG_B": abs(z_score),   # Expect positive z-score to revert to 0
            "CLOSE": 0.0,
            "NO_SIGNAL": 0.0
        }.get(signal_type, 0.0)

        # Expected return = expected z-reversion * spread standard deviation
        return expected_z_reversion * spread_std

    def _calculate_confidence_score(
        self,
        z_score: float,
        correlation: float,
        cointegration_p: float,
        hurst: float
    ) -> float:
        """Calculate confidence score for the opportunity"""
        z_confidence = min(abs(z_score) / 3.0, 1.0)  # Higher z-score = higher confidence

        if 0.5 < correlation < 0.9:
            correlation_confidence = 1.0 - abs(correlation - 0.7) / 0.2  # Optimal around 0.7
        else:
            correlation_confidence = 0.3

        cointegration_confidence = 1.0 - cointegration_p  # Lower p-value = higher confidence
        mean_reversion_confidence = 1.0 - (hurst * 2.0) if hurst < 0.5 else 0.1

        # Weighted average
        return np.clip(
            z_confidence * 0.3 +
            correlation_confidence * 0.2 +
            cointegration_confidence * 0.3 +
            mean_reversion_confidence * 0.2,
            0.0, 1.0
        )

    def _calculate_risk_score(
        self,
        z_score: float,
        spread_std: float,
        hurst: float,
        correlation: float
    ) -> float:
        """Calculate risk score for the opportunity"""
        volatility_risk = min(spread_std / 100.0, 1.0)  # Higher spread std = higher risk
        momentum_risk = max(hurst - 0.5, 0.0) if hurst > 0.5 else 0.0  # Trending = higher risk
        correlation_risk = max(correlation - 0.9, 0.0) if correlation > 0.9 else 0.0  # Very high correlation = risk
        extreme_z_risk = max(abs(z_score) - 3.0, 0.0) / 2.0 if abs(z_score) > 3.0 else 0.0

        # Combined risk score (0 = low risk, 1 = high risk)
        return np.clip(
            volatility_risk * 0.3 +
            momentum_risk * 0.3 +
            correlation_risk * 0.2 +
            extreme_z_risk * 0.2,
            0.0, 1.0
        )

    # API integration methods
    async def _fetch_historical_prices(
        self,
        token: str,
        start_time: datetime,
        end_time: datetime
    ) -> Dict[datetime, float]:
        """Fetch historical prices for a token"""
        try:
            # In production, integrate with Jupiter Price API V3
            # For now, return mock data

            prices = {}
            current_time = start_time
            base_price = 100.0 if token == "So11111111111111111111111111111111111111112" else 1.0

            while current_time <= end_time:
                # Generate mock price with some randomness
                import random
                variation = (random.random() - 0.5) * 0.02  # ±1% variation
                price = base_price * (1.0 + variation)

                prices[current_time] = price
                current_time += timedelta(minutes=5)  # 5-minute intervals

            return prices

        except Exception as e:
            logger.error(f"Error fetching historical prices for {token}", error=str(e))
            return {}

    async def _fetch_current_price(self, token: str) -> Optional[float]:
        """Fetch current price for a token"""
        try:
            # Use Jupiter Price API
            price_data = await self.jupiter_client.get_token_price(token)

            if price_data and 'data' in price_data and token in price_data['data']:
                return float(price_data['data'][token]['price'])

            return None

        except Exception as e:
            logger.error(f"Error fetching current price for {token}", error=str(e))
            return None

    async def _get_token_symbol(self, token: str) -> str:
        """Get token symbol from mint address"""
        symbols = {
            "So11111111111111111111111111111111111111112": "SOL",
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": "USDC",
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY": "USDT",
            "9n4nbM75f5Ui33ZbPYXn59JwjuGzs3gT9p5dYjFrUsU4": "WBTC",
            "CDJ3U8VdFqk8bLjNKZgCyKJ5aK19ed2TdLiBdMjxwFg": "LINK",
        }
        return symbols.get(token, token[:8])

    # Redis publishing methods
    async def _publish_opportunities(self) -> None:
        """Publish opportunities to Redis"""
        try:
            if not self.redis_client:
                return

            opportunities_data = {
                pair_key: asdict(opportunity) for pair_key, opportunity in self.active_opportunities.items()
            }

            message = {
                "opportunities": opportunities_data,
                "timestamp": datetime.now().isoformat(),
                "source": "statistical_arbitrage"
            }

            await self.redis_client.publish("statistical_arbitrage:opportunities", json.dumps(message))

            # Store latest opportunities
            await self.redis_client.hset(
                "statistical_arbitrage:latest_opportunities",
                mapping={pair_key: json.dumps(asdict(opp)) for pair_key, opp in self.active_opportunities.items()}
            )

        except Exception as e:
            logger.error("Error publishing opportunities to Redis", error=str(e))

    async def _publish_statistics(self) -> None:
        """Publish statistics to Redis"""
        try:
            if not self.redis_client:
                return

            stats = self.get_statistics()
            stats["timestamp"] = datetime.now().isoformat()

            await self.redis_client.publish("statistical_arbitrage:statistics", json.dumps(stats))

            # Store latest statistics
            await self.redis_client.set("statistical_arbitrage:latest_stats", json.dumps(stats))

        except Exception as e:
            logger.error("Error publishing statistics to Redis", error=str(e))

    async def _publish_position_close(self, pair_key: str, position: Position, reason: str) -> None:
        """Publish position close event to Redis"""
        try:
            if not self.redis_client:
                return

            message = {
                "pair_key": pair_key,
                "position": asdict(position),
                "close_reason": reason,
                "close_time": datetime.now().isoformat(),
                "source": "statistical_arbitrage"
            }

            await self.redis_client.publish("statistical_arbitrage:position_closed", json.dumps(message))

        except Exception as e:
            logger.error("Error publishing position close to Redis", error=str(e))

    # Public API methods
    def get_opportunities(self) -> Dict[str, StatisticalArbitrageOpportunity]:
        """Get current arbitrage opportunities"""
        return self.active_opportunities.copy()

    def get_positions(self) -> Dict[str, Position]:
        """Get active positions"""
        return self.active_positions.copy()

    def get_trading_pairs(self) -> Dict[str, TradingPair]:
        """Get analyzed trading pairs"""
        return self.trading_pairs.copy()

    def get_statistics(self) -> Dict[str, Any]:
        """Get engine statistics"""
        stats = self.stats.copy()

        if stats["start_time"]:
            uptime = datetime.now() - stats["start_time"]
            stats["uptime_seconds"] = uptime.total_seconds()
            stats["uptime_formatted"] = str(uptime).split(".")[0]

        stats["active_opportunities"] = len(self.active_opportunities)
        stats["active_positions"] = len(self.active_positions)
        stats["analyzed_pairs"] = len(self.trading_pairs)
        stats["cointegrated_pairs"] = sum(1 for pair in self.trading_pairs.values() if pair.is_cointegrated)
        stats["is_running"] = self.is_running

        # Calculate success rate
        if stats["executed_trades"] > 0:
            stats["success_rate"] = (stats["successful_trades"] / stats["executed_trades"]) * 100
        else:
            stats["success_rate"] = 0.0

        return stats