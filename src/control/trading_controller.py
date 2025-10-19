#!/usr/bin/env python3
"""
MojoRust Trading Controller

Central controller responsible for managing all trading operations,
including strategy execution, risk management, and position monitoring.

This controller integrates with the existing task pool manager and
provides high-level trading control functionality.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Callable
from dataclasses import dataclass
from enum import Enum
import uuid

import redis.asyncio as aioredis

from ..api.trading_control_api import TradingConfig, TradingStatus, ExecutionMode, TradingStrategy

logger = logging.getLogger(__name__)

@dataclass
class Trade:
    """Represents a single trade"""
    id: str
    token_address: str
    action: str  # buy/sell
    amount_sol: float
    token_amount: float
    price: float
    timestamp: datetime
    strategy: str
    status: str  # pending, executed, failed, cancelled
    pnl: Optional[float] = None
    fees: Optional[float] = None
    tx_signature: Optional[str] = None

@dataclass
class Position:
    """Represents an open position"""
    token_address: str
    amount: float
    avg_price: float
    current_price: float
    unrealized_pnl: float
    realized_pnl: float
    strategy: str
    open_time: datetime

class TradingController:
    """
    Main trading controller responsible for orchestrating all trading activities.
    """

    def __init__(self, redis_client: aioredis.Redis):
        self.redis_client = redis_client

        # Trading state
        self.is_running = False
        self.is_paused = False
        self.emergency_stop_flag = False

        # Configuration
        self.config: Optional[TradingConfig] = None

        # Trading data
        self.trades: List[Trade] = []
        self.positions: Dict[str, Position] = {}
        self.portfolio_value = 0.0
        self.available_cash = 0.0

        # Performance metrics
        self.metrics = {
            'total_trades': 0,
            'successful_trades': 0,
            'failed_trades': 0,
            'total_pnl': 0.0,
            'win_rate': 0.0,
            'avg_trade_pnl': 0.0,
            'max_drawdown': 0.0,
            'current_drawdown': 0.0,
            'daily_pnl': 0.0,
            'start_time': None,
            'last_trade_time': None
        }

        # Rate limiting and controls
        self.daily_trade_count = 0
        self.last_trade_reset = datetime.utcnow().date()

        # Risk controls
        self.risk_limits = {
            'max_daily_loss': 0.1,  # 10% daily loss limit
            'max_position_risk': 0.02,  # 2% per position
            'max_portfolio_risk': 0.15,  # 15% total portfolio risk
            'min_confidence': 0.7
        }

        # Strategy execution
        self.active_strategy = None
        self.strategy_task = None

        # Background tasks
        self.monitoring_task = None
        self.metrics_update_task = None

    async def start_trading(self, config: TradingConfig):
        """
        Start trading with the specified configuration.

        Args:
            config: Trading configuration including strategy, capital, and risk parameters
        """
        try:
            logger.info(f"Starting trading with strategy: {config.strategy}")

            self.config = config
            self.is_running = True
            self.is_paused = False
            self.emergency_stop_flag = False

            # Initialize portfolio
            self.available_cash = config.initial_capital
            self.portfolio_value = config.initial_capital
            self.metrics['start_time'] = datetime.utcnow()

            # Reset daily trade counter
            self.daily_trade_count = 0
            self.last_trade_reset = datetime.utcnow().date()

            # Store configuration in Redis
            await self._store_config()

            # Start strategy execution
            await self._start_strategy()

            # Start monitoring tasks
            await self._start_monitoring()

            logger.info("Trading started successfully")

        except Exception as e:
            logger.error(f"Failed to start trading: {e}")
            self.is_running = False
            raise

    async def stop_trading(self):
        """Stop all trading activity gracefully."""
        try:
            logger.info("Stopping trading...")

            self.is_running = False

            # Stop strategy execution
            await self._stop_strategy()

            # Stop monitoring tasks
            await self._stop_monitoring()

            # Close all positions (optional - based on configuration)
            await self._cleanup_positions()

            logger.info("Trading stopped successfully")

        except Exception as e:
            logger.error(f"Error stopping trading: {e}")
            raise

    async def pause_trading(self):
        """Pause trading temporarily."""
        try:
            logger.info("Pausing trading...")
            self.is_paused = True

            # Pause strategy execution
            if self.strategy_task and not self.strategy_task.done():
                # Strategy will check pause flag in its main loop
                pass

            logger.info("Trading paused")

        except Exception as e:
            logger.error(f"Error pausing trading: {e}")
            raise

    async def resume_trading(self):
        """Resume paused trading."""
        try:
            logger.info("Resuming trading...")
            self.is_paused = False

            # Resume strategy execution
            if not self.is_running:
                await self._start_strategy()

            logger.info("Trading resumed")

        except Exception as e:
            logger.error(f"Error resuming trading: {e}")
            raise

    async def emergency_stop(self):
        """Emergency stop all trading immediately."""
        try:
            logger.warning("EMERGENCY STOP ACTIVATED")

            self.emergency_stop_flag = True
            self.is_running = False
            self.is_paused = False

            # Cancel all tasks immediately
            if self.strategy_task and not self.strategy_task.done():
                self.strategy_task.cancel()

            if self.monitoring_task and not self.monitoring_task.done():
                self.monitoring_task.cancel()

            if self.metrics_update_task and not self.metrics_update_task.done():
                self.metrics_update_task.cancel()

            # Store emergency stop status
            await self.redis_client.set(
                'trading:emergency_stop',
                json.dumps({
                    'timestamp': datetime.utcnow().isoformat(),
                    'reason': 'manual_emergency_stop'
                }),
                ex=86400  # 24 hours
            )

            logger.warning("Emergency stop completed")

        except Exception as e:
            logger.error(f"Error during emergency stop: {e}")

    async def execute_trade(self, trade_request: Dict[str, Any]) -> Optional[Trade]:
        """
        Execute a trade with proper validation and risk management.

        Args:
            trade_request: Dictionary containing trade details

        Returns:
            Trade object if executed successfully, None otherwise
        """
        try:
            # Check if trading is active and not paused
            if not self.is_running or self.is_paused or self.emergency_stop_flag:
                logger.warning(f"Trade rejected - trading not active (running={self.is_running}, paused={self.is_paused}, emergency={self.emergency_stop_flag})")
                return None

            # Validate trade request
            if not await self._validate_trade_request(trade_request):
                return None

            # Check risk limits
            if not await self._check_risk_limits(trade_request):
                return None

            # Create trade object
            trade = Trade(
                id=str(uuid.uuid4()),
                token_address=trade_request['token_address'],
                action=trade_request['action'],
                amount_sol=trade_request['amount_sol'],
                token_amount=0.0,  # Will be filled during execution
                price=trade_request.get('price', 0.0),
                timestamp=datetime.utcnow(),
                strategy=trade_request.get('strategy', 'manual'),
                status='pending'
            )

            # Execute trade
            success = await self._execute_trade_implementation(trade)

            if success:
                trade.status = 'executed'
                self.trades.append(trade)
                self.metrics['total_trades'] += 1
                self.metrics['successful_trades'] += 1
                self.metrics['last_trade_time'] = trade.timestamp
                self.daily_trade_count += 1

                # Update portfolio and positions
                await self._update_portfolio_after_trade(trade)

                # Store trade in Redis
                await self._store_trade(trade)

                logger.info(f"Trade executed successfully: {trade.id}")
                return trade
            else:
                trade.status = 'failed'
                self.metrics['total_trades'] += 1
                self.metrics['failed_trades'] += 1
                logger.error(f"Trade execution failed: {trade.id}")
                return None

        except Exception as e:
            logger.error(f"Error executing trade: {e}")
            return None

    async def get_metrics(self) -> Dict[str, Any]:
        """Get current trading metrics."""
        try:
            # Update portfolio value
            await self._update_portfolio_value()

            # Calculate performance metrics
            await self._calculate_performance_metrics()

            # Return comprehensive metrics
            return {
                'trading_status': 'running' if self.is_running else 'stopped',
                'portfolio_value': self.portfolio_value,
                'available_cash': self.available_cash,
                'total_positions': len(self.positions),
                'total_trades': self.metrics['total_trades'],
                'successful_trades': self.metrics['successful_trades'],
                'failed_trades': self.metrics['failed_trades'],
                'win_rate': self.metrics['win_rate'],
                'total_pnl': self.metrics['total_pnl'],
                'daily_pnl': self.metrics['daily_pnl'],
                'current_drawdown': self.metrics['current_drawdown'],
                'max_drawdown': self.metrics['max_drawdown'],
                'daily_trade_count': self.daily_trade_count,
                'uptime_seconds': (datetime.utcnow() - self.metrics['start_time']).total_seconds() if self.metrics['start_time'] else 0,
                'last_trade_time': self.metrics['last_trade_time'].isoformat() if self.metrics['last_trade_time'] else None,
                'emergency_stop_active': self.emergency_stop_flag
            }

        except Exception as e:
            logger.error(f"Error getting metrics: {e}")
            return {}

    async def get_positions(self) -> List[Dict[str, Any]]:
        """Get current open positions."""
        try:
            positions_data = []
            for token_address, position in self.positions.items():
                positions_data.append({
                    'token_address': token_address,
                    'amount': position.amount,
                    'avg_price': position.avg_price,
                    'current_price': position.current_price,
                    'unrealized_pnl': position.unrealized_pnl,
                    'realized_pnl': position.realized_pnl,
                    'strategy': position.strategy,
                    'open_time': position.open_time.isoformat(),
                    'duration_hours': (datetime.utcnow() - position.open_time).total_seconds() / 3600
                })

            return positions_data

        except Exception as e:
            logger.error(f"Error getting positions: {e}")
            return []

    async def get_recent_trades(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get recent trades."""
        try:
            recent_trades = sorted(self.trades, key=lambda t: t.timestamp, reverse=True)[:limit]

            trades_data = []
            for trade in recent_trades:
                trades_data.append({
                    'id': trade.id,
                    'token_address': trade.token_address,
                    'action': trade.action,
                    'amount_sol': trade.amount_sol,
                    'token_amount': trade.token_amount,
                    'price': trade.price,
                    'timestamp': trade.timestamp.isoformat(),
                    'strategy': trade.strategy,
                    'status': trade.status,
                    'pnl': trade.pnl,
                    'fees': trade.fees,
                    'tx_signature': trade.tx_signature
                })

            return trades_data

        except Exception as e:
            logger.error(f"Error getting recent trades: {e}")
            return []

    # Private methods

    async def _store_config(self):
        """Store trading configuration in Redis."""
        try:
            config_data = {
                'config': self.config.to_dict(),
                'start_time': self.metrics['start_time'].isoformat(),
                'initial_capital': self.config.initial_capital
            }

            await self.redis_client.set(
                'trading:config',
                json.dumps(config_data),
                ex=86400 * 7  # 7 days
            )

        except Exception as e:
            logger.error(f"Error storing config: {e}")

    async def _start_strategy(self):
        """Start the active trading strategy."""
        try:
            # This would integrate with your existing strategy system
            # For now, we'll simulate strategy execution

            logger.info(f"Starting strategy: {self.config.strategy}")

            # Start strategy execution task
            self.strategy_task = asyncio.create_task(self._strategy_execution_loop())

        except Exception as e:
            logger.error(f"Error starting strategy: {e}")
            raise

    async def _stop_strategy(self):
        """Stop the active trading strategy."""
        try:
            if self.strategy_task and not self.strategy_task.done():
                self.strategy_task.cancel()
                try:
                    await self.strategy_task
                except asyncio.CancelledError:
                    pass

            logger.info("Strategy stopped")

        except Exception as e:
            logger.error(f"Error stopping strategy: {e}")

    async def _strategy_execution_loop(self):
        """Main strategy execution loop."""
        try:
            while self.is_running and not self.emergency_stop_flag:
                try:
                    # Check if paused
                    if self.is_paused:
                        await asyncio.sleep(1)
                        continue

                    # Execute strategy logic
                    await self._execute_strategy_logic()

                    # Wait for next cycle
                    await asyncio.sleep(self.config.cycle_interval)

                except asyncio.CancelledError:
                    logger.info("Strategy execution cancelled")
                    break
                except Exception as e:
                    logger.error(f"Error in strategy execution loop: {e}")
                    await asyncio.sleep(5)  # Wait before retrying

        except Exception as e:
            logger.error(f"Fatal error in strategy execution loop: {e}")

    async def _execute_strategy_logic(self):
        """Execute the actual trading strategy logic."""
        try:
            # This is where you would integrate with your existing Mojo/Rust strategies
            # For demonstration, we'll simulate trading decisions

            # Simulate finding a trading opportunity
            if time.time() % 100 < 5:  # 5% chance per cycle
                trade_request = {
                    'token_address': 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',  # USDC example
                    'action': 'buy' if time.time() % 2 == 0 else 'sell',
                    'amount_sol': min(0.01, self.available_cash * 0.1),
                    'strategy': self.config.strategy.value,
                    'confidence': 0.8
                }

                await self.execute_trade(trade_request)

        except Exception as e:
            logger.error(f"Error executing strategy logic: {e}")

    async def _start_monitoring(self):
        """Start background monitoring tasks."""
        try:
            # Start metrics update task
            self.metrics_update_task = asyncio.create_task(self._metrics_update_loop())

            # Start position monitoring task
            self.monitoring_task = asyncio.create_task(self._position_monitoring_loop())

            logger.info("Monitoring tasks started")

        except Exception as e:
            logger.error(f"Error starting monitoring: {e}")

    async def _stop_monitoring(self):
        """Stop background monitoring tasks."""
        try:
            # Cancel monitoring tasks
            if self.metrics_update_task and not self.metrics_update_task.done():
                self.metrics_update_task.cancel()

            if self.monitoring_task and not self.monitoring_task.done():
                self.monitoring_task.cancel()

            logger.info("Monitoring tasks stopped")

        except Exception as e:
            logger.error(f"Error stopping monitoring: {e}")

    async def _metrics_update_loop(self):
        """Background task to update metrics."""
        try:
            while self.is_running and not self.emergency_stop_flag:
                try:
                    # Update portfolio value
                    await self._update_portfolio_value()

                    # Calculate performance metrics
                    await self._calculate_performance_metrics()

                    # Store metrics in Redis for dashboard
                    metrics_data = await self.get_metrics()
                    await self.redis_client.set(
                        'trading:metrics',
                        json.dumps(metrics_data),
                        ex=300  # 5 minutes
                    )

                    # Check daily trade limit reset
                    if datetime.utcnow().date() > self.last_trade_reset:
                        self.daily_trade_count = 0
                        self.last_trade_reset = datetime.utcnow().date()

                    await asyncio.sleep(30)  # Update every 30 seconds

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in metrics update loop: {e}")
                    await asyncio.sleep(60)  # Wait before retrying

        except Exception as e:
            logger.error(f"Fatal error in metrics update loop: {e}")

    async def _position_monitoring_loop(self):
        """Background task to monitor positions."""
        try:
            while self.is_running and not self.emergency_stop_flag:
                try:
                    # Update position prices and PnL
                    await self._update_position_prices()

                    # Check for stop-loss or take-profit conditions
                    await self._check_position_exit_conditions()

                    await asyncio.sleep(10)  # Update every 10 seconds

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in position monitoring loop: {e}")
                    await asyncio.sleep(30)

        except Exception as e:
            logger.error(f"Fatal error in position monitoring loop: {e}")

    async def _validate_trade_request(self, trade_request: Dict[str, Any]) -> bool:
        """Validate trade request."""
        try:
            required_fields = ['token_address', 'action', 'amount_sol']
            for field in required_fields:
                if field not in trade_request:
                    logger.error(f"Missing required field: {field}")
                    return False

            # Validate action
            if trade_request['action'] not in ['buy', 'sell']:
                logger.error(f"Invalid action: {trade_request['action']}")
                return False

            # Validate amount
            if trade_request['amount_sol'] <= 0:
                logger.error(f"Invalid amount: {trade_request['amount_sol']}")
                return False

            # Check available cash for buys
            if trade_request['action'] == 'buy':
                if trade_request['amount_sol'] > self.available_cash:
                    logger.error(f"Insufficient cash: {trade_request['amount_sol']} > {self.available_cash}")
                    return False

            return True

        except Exception as e:
            logger.error(f"Error validating trade request: {e}")
            return False

    async def _check_risk_limits(self, trade_request: Dict[str, Any]) -> bool:
        """Check if trade passes risk limits."""
        try:
            # Check daily trade limit
            if self.daily_trade_count >= 50:  # Max 50 trades per day
                logger.warning(f"Daily trade limit reached: {self.daily_trade_count}")
                return False

            # Check position size limit
            if trade_request['amount_sol'] > (self.portfolio_value * self.config.max_position_size):
                logger.warning(f"Trade exceeds max position size")
                return False

            # Check portfolio risk
            trade_risk = trade_request['amount_sol'] / self.portfolio_value
            if trade_risk > self.risk_limits['max_position_risk']:
                logger.warning(f"Trade exceeds position risk limit")
                return False

            # Check confidence threshold
            confidence = trade_request.get('confidence', 0.0)
            if confidence < self.risk_limits['min_confidence']:
                logger.warning(f"Trade confidence too low: {confidence}")
                return False

            return True

        except Exception as e:
            logger.error(f"Error checking risk limits: {e}")
            return False

    async def _execute_trade_implementation(self, trade: Trade) -> bool:
        """
        Implement actual trade execution.
        This would integrate with your Rust execution engine.
        """
        try:
            # This is where you would integrate with your existing Rust/Mojo execution system
            # For demonstration, we'll simulate successful execution

            # Simulate execution delay
            await asyncio.sleep(0.1)

            # Simulate price
            if trade.price == 0.0:
                trade.price = 1.0  # Default price for demonstration

            # Calculate token amount (simplified)
            trade.token_amount = trade.amount_sol / trade.price

            # Simulate transaction signature
            trade.tx_signature = f"sim_tx_{trade.id[:8]}"

            # Simulate fees
            trade.fees = trade.amount_sol * 0.001  # 0.1% fee

            return True

        except Exception as e:
            logger.error(f"Error executing trade implementation: {e}")
            return False

    async def _update_portfolio_after_trade(self, trade: Trade):
        """Update portfolio and positions after trade execution."""
        try:
            if trade.action == 'buy':
                # Update cash
                self.available_cash -= (trade.amount_sol + (trade.fees or 0))

                # Update or create position
                if trade.token_address in self.positions:
                    position = self.positions[trade.token_address]
                    # Calculate new average price
                    total_cost = (position.avg_price * position.amount) + trade.amount_sol
                    position.amount += trade.token_amount
                    position.avg_price = total_cost / position.amount
                else:
                    # Create new position
                    self.positions[trade.token_address] = Position(
                        token_address=trade.token_address,
                        amount=trade.token_amount,
                        avg_price=trade.price,
                        current_price=trade.price,
                        unrealized_pnl=0.0,
                        realized_pnl=0.0,
                        strategy=trade.strategy,
                        open_time=trade.timestamp
                    )

            elif trade.action == 'sell':
                # Update cash
                self.available_cash += (trade.amount_sol - (trade.fees or 0))

                # Update or close position
                if trade.token_address in self.positions:
                    position = self.positions[trade.token_address]

                    # Calculate realized PnL
                    realized_pnl = (trade.price - position.avg_price) * trade.token_amount
                    position.realized_pnl += realized_pnl

                    # Reduce position
                    position.amount -= trade.token_amount

                    # Close position if amount is zero or very small
                    if position.amount <= 0.001:
                        del self.positions[trade.token_address]

                # Update trade PnL
                trade.pnl = realized_pnl if trade.action == 'sell' else 0.0

            # Update portfolio value
            await self._update_portfolio_value()

        except Exception as e:
            logger.error(f"Error updating portfolio after trade: {e}")

    async def _update_portfolio_value(self):
        """Update total portfolio value including unrealized PnL."""
        try:
            total_value = self.available_cash

            # Add value of positions
            for position in self.positions.values():
                # Update current price (this would fetch real prices)
                # For now, simulate price movement
                price_change = (time.time() % 20 - 10) / 100  # -10% to +10%
                position.current_price = position.avg_price * (1 + price_change)

                # Calculate unrealized PnL
                position.unrealized_pnl = (position.current_price - position.avg_price) * position.amount

                # Add position value to total
                total_value += position.amount * position.current_price

            self.portfolio_value = total_value

        except Exception as e:
            logger.error(f"Error updating portfolio value: {e}")

    async def _update_position_prices(self):
        """Update current prices for all positions."""
        try:
            # This would integrate with real price feeds
            # For now, simulate price updates
            for position in self.positions.values():
                # Simulate price movement
                price_change = (time.time() % 20 - 10) / 100  # -10% to +10%
                position.current_price = position.avg_price * (1 + price_change)
                position.unrealized_pnl = (position.current_price - position.avg_price) * position.amount

        except Exception as e:
            logger.error(f"Error updating position prices: {e}")

    async def _check_position_exit_conditions(self):
        """Check if any positions should be closed based on exit conditions."""
        try:
            for token_address, position in list(self.positions.items()):
                # Check stop-loss
                if position.current_price < position.avg_price * (1 - self.config.max_drawdown):
                    logger.info(f"Stop-loss triggered for position {token_address}")
                    await self._close_position(token_address, "stop_loss")

                # Check take-profit (simplified)
                elif position.current_price > position.avg_price * 1.2:  # 20% profit target
                    logger.info(f"Take-profit triggered for position {token_address}")
                    await self._close_position(token_address, "take_profit")

        except Exception as e:
            logger.error(f"Error checking position exit conditions: {e}")

    async def _close_position(self, token_address: str, reason: str):
        """Close a position."""
        try:
            if token_address not in self.positions:
                return

            position = self.positions[token_address]

            # Create sell trade request
            trade_request = {
                'token_address': token_address,
                'action': 'sell',
                'amount_sol': position.amount * position.current_price,
                'strategy': f"position_close_{reason}",
                'confidence': 1.0
            }

            await self.execute_trade(trade_request)

        except Exception as e:
            logger.error(f"Error closing position {token_address}: {e}")

    async def _calculate_performance_metrics(self):
        """Calculate performance metrics."""
        try:
            if not self.metrics['start_time']:
                return

            # Calculate win rate
            if self.metrics['total_trades'] > 0:
                self.metrics['win_rate'] = self.metrics['successful_trades'] / self.metrics['total_trades']

            # Calculate total PnL
            total_pnl = 0.0
            for trade in self.trades:
                if trade.pnl is not None:
                    total_pnl += trade.pnl

            self.metrics['total_pnl'] = total_pnl

            # Calculate average trade PnL
            if self.metrics['successful_trades'] > 0:
                profitable_trades = [t for t in self.trades if t.pnl and t.pnl > 0]
                if profitable_trades:
                    self.metrics['avg_trade_pnl'] = sum(t.pnl for t in profitable_trades) / len(profitable_trades)

            # Calculate drawdown
            if self.config:
                peak_value = self.config.initial_capital
                for trade in self.trades:
                    # This is simplified - you'd track portfolio value over time
                    if trade.pnl and trade.pnl > 0:
                        peak_value = max(peak_value, self.portfolio_value)

                if peak_value > 0:
                    self.metrics['current_drawdown'] = (peak_value - self.portfolio_value) / peak_value
                    self.metrics['max_drawdown'] = max(self.metrics['max_drawdown'], self.metrics['current_drawdown'])

            # Calculate daily PnL
            today = datetime.utcnow().date()
            daily_pnl = 0.0
            for trade in self.trades:
                if trade.pnl and trade.timestamp.date() == today:
                    daily_pnl += trade.pnl

            self.metrics['daily_pnl'] = daily_pnl

        except Exception as e:
            logger.error(f"Error calculating performance metrics: {e}")

    async def _cleanup_positions(self):
        """Clean up positions on shutdown."""
        try:
            logger.info(f"Cleaning up {len(self.positions)} positions...")

            # Optionally close all positions on shutdown
            # This depends on your risk management preferences

            for token_address in list(self.positions.keys()):
                logger.info(f"Position {token_address} left open on shutdown")

        except Exception as e:
            logger.error(f"Error cleaning up positions: {e}")

    async def _store_trade(self, trade: Trade):
        """Store trade in Redis."""
        try:
            trade_data = {
                'id': trade.id,
                'token_address': trade.token_address,
                'action': trade.action,
                'amount_sol': trade.amount_sol,
                'token_amount': trade.token_amount,
                'price': trade.price,
                'timestamp': trade.timestamp.isoformat(),
                'strategy': trade.strategy,
                'status': trade.status,
                'pnl': trade.pnl,
                'fees': trade.fees,
                'tx_signature': trade.tx_signature
            }

            # Store in Redis with expiration
            await self.redis_client.set(
                f'trade:{trade.id}',
                json.dumps(trade_data),
                ex=86400 * 30  # 30 days
            )

            # Add to recent trades list
            await self.redis_client.lpush(
                'trading:recent_trades',
                json.dumps(trade_data)
            )
            await self.redis_client.ltrim('trading:recent_trades', 0, 999)  # Keep last 1000 trades

        except Exception as e:
            logger.error(f"Error storing trade: {e}")