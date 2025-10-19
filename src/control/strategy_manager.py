#!/usr/bin/env python3
"""
MojoRust Strategy Manager

Manages trading strategies, including loading, switching,
and parameter updates during runtime.

Features:
- Dynamic strategy switching
- Strategy parameter management
- Strategy performance tracking
- Multi-strategy coordination
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass, asdict
from enum import Enum
import importlib
import sys
import os

import redis.asyncio as aioredis

from ..api.trading_control_api import TradingStrategy

logger = logging.getLogger(__name__)

class StrategyStatus(str, Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    LOADING = "loading"
    ERROR = "error"
    EVALUATING = "evaluating"

@dataclass
class StrategyConfig:
    """Configuration for a trading strategy"""
    name: str
    strategy_type: TradingStrategy
    enabled: bool
    parameters: Dict[str, Any]
    performance_metrics: Dict[str, float]
    last_updated: datetime
    status: StrategyStatus
    error_message: Optional[str] = None

@dataclass
class StrategyPerformance:
    """Performance metrics for a strategy"""
    total_trades: int
    successful_trades: int
    failed_trades: int
    total_pnl: float
    win_rate: float
    avg_trade_pnl: float
    max_drawdown: float
    sharpe_ratio: float
    profit_factor: float
    last_trade_time: Optional[datetime]

class StrategyManager:
    """
    Manages trading strategies with dynamic loading and switching capabilities.
    """

    def __init__(self, redis_client: aioredis.Redis):
        self.redis_client = redis_client

        # Strategy registry
        self.strategies: Dict[str, StrategyConfig] = {}
        self.strategy_instances: Dict[str, Any] = {}
        self.active_strategy: Optional[str] = None

        # Strategy configuration
        self.config = {
            'strategy_switch_cooldown': 300,  # 5 minutes
            'performance_evaluation_interval': 3600,  # 1 hour
            'max_concurrent_strategies': 3,
            'strategy_timeout': 30,  # seconds
            'auto_optimization': True
        }

        # Strategy modules path
        self.strategies_path = os.path.join(os.path.dirname(__file__), '../../strategies')

        # Background tasks
        self.performance_task: Optional[asyncio.Task] = None
        self.optimization_task: Optional[asyncio.Task] = None

        # Strategy switching controls
        self.last_switch_time: Optional[datetime] = None
        self.switch_history: List[Dict[str, Any]] = []

    async def initialize(self):
        """Initialize the strategy manager."""
        try:
            # Load built-in strategies
            await self._load_builtin_strategies()

            # Load strategies from Redis
            await self._load_strategies_from_redis()

            # Start background tasks
            await self._start_background_tasks()

            logger.info("Strategy Manager initialized")

        except Exception as e:
            logger.error(f"Failed to initialize Strategy Manager: {e}")
            raise

    async def load_strategy(self,
                          strategy_name: str,
                          strategy_type: TradingStrategy,
                          parameters: Optional[Dict[str, Any]] = None,
                          enabled: bool = False) -> bool:
        """
        Load a new trading strategy.

        Args:
            strategy_name: Name of the strategy
            strategy_type: Type of strategy
            parameters: Strategy parameters
            enabled: Whether to enable the strategy immediately

        Returns:
            True if loaded successfully
        """
        try:
            if strategy_name in self.strategies:
                logger.warning(f"Strategy {strategy_name} already loaded")
                return False

            # Create strategy configuration
            strategy_config = StrategyConfig(
                name=strategy_name,
                strategy_type=strategy_type,
                enabled=enabled,
                parameters=parameters or {},
                performance_metrics={},
                last_updated=datetime.utcnow(),
                status=StrategyStatus.LOADING
            )

            # Load strategy instance
            strategy_instance = await self._load_strategy_instance(strategy_type, parameters)
            if not strategy_instance:
                strategy_config.status = StrategyStatus.ERROR
                strategy_config.error_message = "Failed to load strategy instance"
                self.strategies[strategy_name] = strategy_config
                return False

            # Store strategy
            self.strategies[strategy_name] = strategy_config
            self.strategy_instances[strategy_name] = strategy_instance

            strategy_config.status = StrategyStatus.INACTIVE
            strategy_config.last_updated = datetime.utcnow()

            # Store in Redis
            await self._store_strategy_config(strategy_config)

            logger.info(f"Loaded strategy: {strategy_name}")
            return True

        except Exception as e:
            logger.error(f"Error loading strategy {strategy_name}: {e}")
            if strategy_name in self.strategies:
                self.strategies[strategy_name].status = StrategyStatus.ERROR
                self.strategies[strategy_name].error_message = str(e)
            return False

    async def switch_strategy(self, strategy_name: str, force: bool = False) -> bool:
        """
        Switch to a different trading strategy.

        Args:
            strategy_name: Name of the strategy to switch to
            force: Force switch even if in cooldown period

        Returns:
            True if switched successfully
        """
        try:
            # Validate strategy exists
            if strategy_name not in self.strategies:
                logger.error(f"Strategy {strategy_name} not found")
                return False

            strategy_config = self.strategies[strategy_name]

            # Check if strategy is enabled
            if not strategy_config.enabled:
                logger.error(f"Strategy {strategy_name} is not enabled")
                return False

            # Check cooldown period
            if not force and self.last_switch_time:
                cooldown_remaining = self.config['strategy_switch_cooldown'] - \
                                   (datetime.utcnow() - self.last_switch_time).total_seconds()
                if cooldown_remaining > 0:
                    logger.warning(f"Strategy switch cooldown: {cooldown_remaining:.0f}s remaining")
                    return False

            # Deactivate current strategy
            if self.active_strategy:
                old_strategy = self.strategies[self.active_strategy]
                old_strategy.status = StrategyStatus.INACTIVE

            # Activate new strategy
            strategy_config.status = StrategyStatus.ACTIVE
            self.active_strategy = strategy_name
            self.last_switch_time = datetime.utcnow()

            # Record switch
            switch_record = {
                'from_strategy': self.active_strategy,
                'to_strategy': strategy_name,
                'timestamp': self.last_switch_time.isoformat(),
                'forced': force
            }
            self.switch_history.append(switch_record)

            # Store in Redis
            await self._store_active_strategy(strategy_name)
            await self._store_switch_history(switch_record)

            logger.info(f"Switched to strategy: {strategy_name}")
            return True

        except Exception as e:
            logger.error(f"Error switching strategy to {strategy_name}: {e}")
            return False

    async def update_strategy_parameters(self,
                                       strategy_name: str,
                                       parameters: Dict[str, Any]) -> bool:
        """
        Update parameters for a strategy.

        Args:
            strategy_name: Name of the strategy
            parameters: New parameters

        Returns:
            True if updated successfully
        """
        try:
            if strategy_name not in self.strategies:
                logger.error(f"Strategy {strategy_name} not found")
                return False

            strategy_config = self.strategies[strategy_name]

            # Update parameters
            strategy_config.parameters.update(parameters)
            strategy_config.last_updated = datetime.utcnow()

            # Reload strategy instance with new parameters
            new_instance = await self._load_strategy_instance(
                strategy_config.strategy_type,
                strategy_config.parameters
            )

            if new_instance:
                # Replace old instance
                if strategy_name in self.strategy_instances:
                    await self._unload_strategy_instance(self.strategy_instances[strategy_name])

                self.strategy_instances[strategy_name] = new_instance

                # Store updated configuration
                await self._store_strategy_config(strategy_config)

                logger.info(f"Updated parameters for strategy: {strategy_name}")
                return True
            else:
                logger.error(f"Failed to reload strategy instance: {strategy_name}")
                return False

        except Exception as e:
            logger.error(f"Error updating strategy parameters: {e}")
            return False

    async def get_active_strategy_signals(self, market_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Get trading signals from the active strategy.

        Args:
            market_data: Current market data

        Returns:
            List of trading signals
        """
        try:
            if not self.active_strategy:
                return []

            if self.active_strategy not in self.strategy_instances:
                logger.error(f"Active strategy {self.active_strategy} not loaded")
                return []

            strategy_instance = self.strategy_instances[self.active_strategy]

            # Get signals from strategy
            signals = await self._get_strategy_signals(strategy_instance, market_data)

            # Add metadata to signals
            for signal in signals:
                signal['strategy_name'] = self.active_strategy
                signal['strategy_type'] = self.strategies[self.active_strategy].strategy_type.value
                signal['timestamp'] = datetime.utcnow().isoformat()

            return signals

        except Exception as e:
            logger.error(f"Error getting strategy signals: {e}")
            return []

    async def evaluate_strategy_performance(self, strategy_name: str) -> Optional[StrategyPerformance]:
        """
        Evaluate the performance of a strategy.

        Args:
            strategy_name: Name of the strategy

        Returns:
            Performance metrics or None if evaluation fails
        """
        try:
            if strategy_name not in self.strategies:
                return None

            # Get performance data from Redis or trading history
            performance_data = await self._get_strategy_performance_data(strategy_name)

            if not performance_data:
                return None

            # Calculate performance metrics
            performance = StrategyPerformance(
                total_trades=performance_data.get('total_trades', 0),
                successful_trades=performance_data.get('successful_trades', 0),
                failed_trades=performance_data.get('failed_trades', 0),
                total_pnl=performance_data.get('total_pnl', 0.0),
                win_rate=performance_data.get('win_rate', 0.0),
                avg_trade_pnl=performance_data.get('avg_trade_pnl', 0.0),
                max_drawdown=performance_data.get('max_drawdown', 0.0),
                sharpe_ratio=performance_data.get('sharpe_ratio', 0.0),
                profit_factor=performance_data.get('profit_factor', 0.0),
                last_trade_time=datetime.fromisoformat(performance_data['last_trade_time']) if performance_data.get('last_trade_time') else None
            )

            # Update strategy configuration
            self.strategies[strategy_name].performance_metrics = asdict(performance)

            # Store updated metrics
            await self._store_strategy_config(self.strategies[strategy_name])

            return performance

        except Exception as e:
            logger.error(f"Error evaluating strategy performance: {e}")
            return None

    async def get_strategy_list(self, include_performance: bool = True) -> List[Dict[str, Any]]:
        """
        Get list of all loaded strategies.

        Args:
            include_performance: Whether to include performance metrics

        Returns:
            List of strategy configurations
        """
        try:
            strategies = []

            for name, config in self.strategies.items():
                strategy_data = asdict(config)
                strategy_data['last_updated'] = config.last_updated.isoformat()

                # Add performance data if requested
                if include_performance:
                    performance = await self.evaluate_strategy_performance(name)
                    if performance:
                        strategy_data['performance'] = asdict(performance)

                # Mark active strategy
                strategy_data['is_active'] = (name == self.active_strategy)

                strategies.append(strategy_data)

            return strategies

        except Exception as e:
            logger.error(f"Error getting strategy list: {e}")
            return []

    async def get_switch_history(self, limit: int = 50) -> List[Dict[str, Any]]:
        """
        Get history of strategy switches.

        Args:
            limit: Maximum number of records to return

        Returns:
            List of switch records
        """
        try:
            return self.switch_history[-limit:] if self.switch_history else []

        except Exception as e:
            logger.error(f"Error getting switch history: {e}")
            return []

    # Private methods

    async def _load_builtin_strategies(self):
        """Load built-in strategies."""
        try:
            builtin_strategies = [
                (TradingStrategy.ENHANCED_RSI, {
                    'rsi_period': 14,
                    'oversold_threshold': 25.0,
                    'overbought_threshold': 75.0,
                    'min_confluence_strength': 0.7
                }),
                (TradingStrategy.MOMENTUM, {
                    'momentum_period': 20,
                    'min_momentum_score': 0.6,
                    'volume_threshold': 1.5
                }),
                (TradingStrategy.MEAN_REVERSION, {
                    'lookback_period': 50,
                    'deviation_threshold': 2.0,
                    'min_reversal_strength': 0.5
                }),
                (TradingStrategy.ARBITRAGE, {
                    'min_spread_percentage': 0.5,
                    'max_slippage': 0.1,
                    'execution_speed': 'fast'
                })
            ]

            for strategy_type, parameters in builtin_strategies:
                strategy_name = f"{strategy_type.value}_builtin"
                await self.load_strategy(
                    strategy_name=strategy_name,
                    strategy_type=strategy_type,
                    parameters=parameters,
                    enabled=True
                )

            logger.info(f"Loaded {len(builtin_strategies)} built-in strategies")

        except Exception as e:
            logger.error(f"Error loading built-in strategies: {e}")

    async def _load_strategies_from_redis(self):
        """Load strategies from Redis."""
        try:
            keys = await self.redis_client.keys("strategy:*")

            for key in keys:
                try:
                    data = await self.redis_client.get(key)
                    if data:
                        strategy_data = json.loads(data)

                        strategy_config = StrategyConfig(
                            name=strategy_data['name'],
                            strategy_type=TradingStrategy(strategy_data['strategy_type']),
                            enabled=strategy_data['enabled'],
                            parameters=strategy_data['parameters'],
                            performance_metrics=strategy_data.get('performance_metrics', {}),
                            last_updated=datetime.fromisoformat(strategy_data['last_updated']),
                            status=StrategyStatus(strategy_data['status']),
                            error_message=strategy_data.get('error_message')
                        )

                        self.strategies[strategy_config.name] = strategy_config

                        # Load strategy instance if enabled
                        if strategy_config.enabled:
                            instance = await self._load_strategy_instance(
                                strategy_config.strategy_type,
                                strategy_config.parameters
                            )
                            if instance:
                                self.strategy_instances[strategy_config.name] = instance

                except Exception as e:
                    logger.error(f"Error loading strategy from {key}: {e}")

            # Load active strategy
            active_strategy_name = await self.redis_client.get("active_strategy")
            if active_strategy_name and active_strategy_name in self.strategies:
                self.active_strategy = active_strategy_name.decode()
                self.strategies[self.active_strategy].status = StrategyStatus.ACTIVE

            logger.info(f"Loaded {len(self.strategies)} strategies from Redis")

        except Exception as e:
            logger.error(f"Error loading strategies from Redis: {e}")

    async def _load_strategy_instance(self, strategy_type: TradingStrategy, parameters: Dict[str, Any]) -> Optional[Any]:
        """
        Load an instance of a trading strategy.
        This would integrate with your existing Mojo/Python strategies.
        """
        try:
            # This is where you would load your actual strategy implementations
            # For demonstration, we'll create a mock strategy instance

            if strategy_type == TradingStrategy.ENHANCED_RSI:
                return MockEnhancedRSIStrategy(parameters)
            elif strategy_type == TradingStrategy.MOMENTUM:
                return MockMomentumStrategy(parameters)
            elif strategy_type == TradingStrategy.MEAN_REVERSION:
                return MockMeanReversionStrategy(parameters)
            elif strategy_type == TradingStrategy.ARBITRAGE:
                return MockArbitrageStrategy(parameters)
            elif strategy_type == TradingStrategy.FLASH_LOAN:
                return MockFlashLoanStrategy(parameters)
            else:
                logger.error(f"Unknown strategy type: {strategy_type}")
                return None

        except Exception as e:
            logger.error(f"Error loading strategy instance: {e}")
            return None

    async def _unload_strategy_instance(self, strategy_instance: Any):
        """Unload a strategy instance."""
        try:
            # Cleanup strategy instance if needed
            if hasattr(strategy_instance, 'cleanup'):
                await strategy_instance.cleanup()

        except Exception as e:
            logger.error(f"Error unloading strategy instance: {e}")

    async def _get_strategy_signals(self, strategy_instance: Any, market_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Get signals from a strategy instance."""
        try:
            # This would call the actual strategy's signal generation method
            if hasattr(strategy_instance, 'generate_signals'):
                return await strategy_instance.generate_signals(market_data)
            else:
                # Generate mock signals for demonstration
                return await self._generate_mock_signals(strategy_instance, market_data)

        except Exception as e:
            logger.error(f"Error getting strategy signals: {e}")
            return []

    async def _generate_mock_signals(self, strategy_instance: Any, market_data: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Generate mock trading signals for demonstration."""
        try:
            signals = []

            # Simulate signal generation based on strategy type
            if hasattr(strategy_instance, 'strategy_type'):
                strategy_type = strategy_instance.strategy_type

                # Random signal generation (30% chance)
                if time.time() % 10 < 3:
                    signal = {
                        'token_address': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',  # USDC example
                        'action': 'buy' if time.time() % 2 == 0 else 'sell',
                        'confidence': 0.6 + (time.time() % 40) / 100,
                        'amount_sol': 0.01 + (time.time() % 50) / 1000,
                        'price': 1.0 + (time.time() % 100) / 1000,
                        'reasoning': f"Mock signal from {strategy_type} strategy"
                    }
                    signals.append(signal)

            return signals

        except Exception as e:
            logger.error(f"Error generating mock signals: {e}")
            return []

    async def _get_strategy_performance_data(self, strategy_name: str) -> Optional[Dict[str, Any]]:
        """Get performance data for a strategy from Redis."""
        try:
            data = await self.redis_client.get(f"strategy_performance:{strategy_name}")
            if data:
                return json.loads(data)
            return None

        except Exception as e:
            logger.error(f"Error getting strategy performance data: {e}")
            return None

    async def _store_strategy_config(self, strategy_config: StrategyConfig):
        """Store strategy configuration in Redis."""
        try:
            config_data = asdict(strategy_config)
            config_data['last_updated'] = strategy_config.last_updated.isoformat()

            await self.redis_client.set(
                f"strategy:{strategy_config.name}",
                json.dumps(config_data),
                ex=86400 * 7  # 7 days
            )

        except Exception as e:
            logger.error(f"Error storing strategy config: {e}")

    async def _store_active_strategy(self, strategy_name: str):
        """Store active strategy in Redis."""
        try:
            await self.redis_client.set(
                "active_strategy",
                strategy_name,
                ex=86400 * 7  # 7 days
            )

        except Exception as e:
            logger.error(f"Error storing active strategy: {e}")

    async def _store_switch_history(self, switch_record: Dict[str, Any]):
        """Store strategy switch record in Redis."""
        try:
            await self.redis_client.lpush(
                "strategy_switches",
                json.dumps(switch_record)
            )
            await self.redis_client.ltrim("strategy_switches", 0, 999)  # Keep last 1000

        except Exception as e:
            logger.error(f"Error storing switch history: {e}")

    async def _start_background_tasks(self):
        """Start background tasks."""
        try:
            self.performance_task = asyncio.create_task(self._performance_monitoring_loop())

            if self.config['auto_optimization']:
                self.optimization_task = asyncio.create_task(self._strategy_optimization_loop())

            logger.info("Background tasks started")

        except Exception as e:
            logger.error(f"Error starting background tasks: {e}")

    async def _performance_monitoring_loop(self):
        """Background task to monitor strategy performance."""
        try:
            while True:
                try:
                    # Evaluate performance of all strategies
                    for strategy_name in self.strategies.keys():
                        await self.evaluate_strategy_performance(strategy_name)

                    # Wait before next evaluation
                    await asyncio.sleep(self.config['performance_evaluation_interval'])

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in performance monitoring loop: {e}")
                    await asyncio.sleep(300)  # Wait before retrying

        except Exception as e:
            logger.error(f"Fatal error in performance monitoring loop: {e}")

    async def _strategy_optimization_loop(self):
        """Background task to optimize strategy parameters."""
        try:
            while True:
                try:
                    # Check if strategy should be optimized
                    if self.active_strategy:
                        await self._optimize_strategy(self.active_strategy)

                    # Wait before next optimization
                    await asyncio.sleep(3600 * 6)  # Every 6 hours

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in strategy optimization loop: {e}")
                    await asyncio.sleep(3600)  # Wait before retrying

        except Exception as e:
            logger.error(f"Fatal error in strategy optimization loop: {e}")

    async def _optimize_strategy(self, strategy_name: str):
        """Optimize strategy parameters based on performance."""
        try:
            if strategy_name not in self.strategies:
                return

            strategy_config = self.strategies[strategy_name]
            performance = await self.evaluate_strategy_performance(strategy_name)

            if not performance:
                return

            # Simple optimization logic (would be more sophisticated in practice)
            if performance.win_rate < 0.4:  # Low win rate
                # Adjust parameters to be more conservative
                if 'confidence_threshold' in strategy_config.parameters:
                    strategy_config.parameters['confidence_threshold'] = min(
                        0.9, strategy_config.parameters['confidence_threshold'] + 0.1
                    )

            elif performance.win_rate > 0.8:  # High win rate
                # Can be more aggressive
                if 'confidence_threshold' in strategy_config.parameters:
                    strategy_config.parameters['confidence_threshold'] = max(
                        0.5, strategy_config.parameters['confidence_threshold'] - 0.05
                    )

            # Store optimized parameters
            await self._store_strategy_config(strategy_config)

            logger.info(f"Optimized parameters for strategy: {strategy_name}")

        except Exception as e:
            logger.error(f"Error optimizing strategy: {e}")

    async def shutdown(self):
        """Shutdown the strategy manager."""
        try:
            # Cancel background tasks
            if self.performance_task and not self.performance_task.done():
                self.performance_task.cancel()

            if self.optimization_task and not self.optimization_task.done():
                self.optimization_task.cancel()

            # Unload all strategy instances
            for strategy_instance in self.strategy_instances.values():
                await self._unload_strategy_instance(strategy_instance)

            logger.info("Strategy Manager shutdown complete")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")


# Mock strategy classes for demonstration
class MockEnhancedRSIStrategy:
    """Mock Enhanced RSI Strategy"""
    def __init__(self, parameters):
        self.strategy_type = TradingStrategy.ENHANCED_RSI
        self.parameters = parameters

class MockMomentumStrategy:
    """Mock Momentum Strategy"""
    def __init__(self, parameters):
        self.strategy_type = TradingStrategy.MOMENTUM
        self.parameters = parameters

class MockMeanReversionStrategy:
    """Mock Mean Reversion Strategy"""
    def __init__(self, parameters):
        self.strategy_type = TradingStrategy.MEAN_REVERSION
        self.parameters = parameters

class MockArbitrageStrategy:
    """Mock Arbitrage Strategy"""
    def __init__(self, parameters):
        self.strategy_type = TradingStrategy.ARBITRAGE
        self.parameters = parameters

class MockFlashLoanStrategy:
    """Mock Flash Loan Strategy"""
    def __init__(self, parameters):
        self.strategy_type = TradingStrategy.FLASH_LOAN
        self.parameters = parameters