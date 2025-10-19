#!/usr/bin/env python3
"""
MojoRust Automated Strategy Executor

Automatically executes trading strategies based on discovered opportunities
without manual intervention. Integrates with token discovery, risk management,
and execution engines to create a fully automated trading system.

Features:
- Automatic opportunity identification
- Multi-strategy execution
- Intelligent position sizing
- Automated entry/exit decisions
- Performance tracking and optimization
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
import uuid

import redis.asyncio as aioredis

from ..control.strategy_manager import StrategyManager
from ..control.risk_controller import RiskController
from ..control.trading_controller import TradingController
from ..automation.auto_token_discovery import AutoTokenDiscovery, DiscoveredToken
from ..api.trading_control_api import TradingStrategy

logger = logging.getLogger(__name__)

class ExecutionPriority(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class TradeStatus(str, Enum):
    PENDING = "pending"
    EXECUTING = "executing"
    EXECUTED = "executed"
    FAILED = "failed"
    CANCELLED = "cancelled"

@dataclass
class TradingOpportunity:
    """Represents a trading opportunity"""
    id: str
    token_address: str
    token_symbol: str
    token_name: str
    strategy: TradingStrategy
    action: str  # buy/sell
    confidence: float
    expected_roi: float
    risk_score: float
    position_size_sol: float
    entry_price: float
    stop_loss_price: float
    take_profit_price: float
    priority: ExecutionPriority
    discovered_at: datetime
    expires_at: datetime
    metadata: Dict[str, Any]

@dataclass
class AutomatedTrade:
    """Represents an automated trade"""
    id: str
    opportunity_id: str
    token_address: str
    strategy: TradingStrategy
    action: str
    amount_sol: float
    status: TradeStatus
    created_at: datetime
    executed_at: Optional[datetime]
    completed_at: Optional[datetime]
    execution_price: Optional[float]
    realized_pnl: Optional[float]
    fees: Optional[float]
    tx_signature: Optional[str]
    error_message: Optional[str]

class AutoStrategyExecutor:
    """
    Automated strategy execution engine that trades without manual intervention.
    """

    def __init__(self,
                 redis_client: aioredis.Redis,
                 strategy_manager: StrategyManager,
                 risk_controller: RiskController,
                 trading_controller: TradingController,
                 token_discovery: AutoTokenDiscovery):
        self.redis_client = redis_client
        self.strategy_manager = strategy_manager
        self.risk_controller = risk_controller
        self.trading_controller = trading_controller
        self.token_discovery = token_discovery

        # Configuration
        self.config = {
            'execution_interval': 15,          # seconds
            'opportunity_timeout': 300,        # 5 minutes
            'max_concurrent_trades': 3,       # Maximum concurrent trades
            'min_confidence_threshold': 0.6,   # Minimum confidence for trades
            'max_position_size': 0.2,          # Maximum position size per trade
            'auto_rebalance': True,            # Automatic portfolio rebalancing
            'performance_tracking': True,       # Track strategy performance
            'opportunity_queue_size': 100,     # Maximum queued opportunities
        }

        # State
        self.opportunities: Dict[str, TradingOpportunity] = {}
        self.active_trades: Dict[str, AutomatedTrade] = {}
        self.execution_queue: List[str] = []  # Queue of opportunity IDs
        self.is_running = False

        # Performance tracking
        self.performance_metrics = {
            'total_opportunities': 0,
            'trades_executed': 0,
            'successful_trades': 0,
            'failed_trades': 0,
            'total_pnl': 0.0,
            'avg_execution_time': 0.0,
            'strategy_performance': {},
            'last_execution_time': None
        }

        # Background tasks
        self.execution_task: Optional[asyncio.Task] = None
        self.monitoring_task: Optional[asyncio.Task] = None
        self.cleanup_task: Optional[asyncio.Task] = None

    async def initialize(self):
        """Initialize the auto strategy executor."""
        try:
            # Start background tasks
            await self._start_background_tasks()

            # Load existing opportunities and trades
            await self._load_existing_data()

            # Subscribe to token discovery notifications
            await self._subscribe_to_discoveries()

            self.is_running = True
            logger.info("Auto Strategy Executor initialized")

        except Exception as e:
            logger.error(f"Failed to initialize Auto Strategy Executor: {e}")
            raise

    async def start_automated_trading(self):
        """Start automated trading execution."""
        try:
            if self.is_running:
                logger.warning("Automated trading is already running")
                return

            self.is_running = True
            logger.info("Started automated trading execution")

        except Exception as e:
            logger.error(f"Error starting automated trading: {e}")

    async def stop_automated_trading(self):
        """Stop automated trading execution."""
        try:
            self.is_running = False

            # Cancel pending opportunities
            await self._cancel_pending_opportunities()

            logger.info("Stopped automated trading execution")

        except Exception as e:
            logger.error(f"Error stopping automated trading: {e}")

    async def evaluate_opportunity(self, token: DiscoveredToken) -> List[TradingOpportunity]:
        """
        Evaluate a discovered token for trading opportunities.

        Args:
            token: Discovered token to evaluate

        Returns:
            List of trading opportunities
        """
        try:
            opportunities = []

            # Get current trading status
            trading_status = await self.trading_controller.get_metrics()

            # Check if we can add new positions
            if trading_status.get('total_positions', 0) >= self.config['max_concurrent_trades']:
                logger.debug("Maximum concurrent trades reached, skipping opportunity")
                return opportunities

            # Evaluate each strategy
            strategies_to_check = [
                TradingStrategy.ENHANCED_RSI,
                TradingStrategy.MOMENTUM,
                TradingStrategy.ARBITRAGE,
                TradingStrategy.FLASH_LOAN
            ]

            for strategy in strategies_to_check:
                opportunity = await self._evaluate_strategy_opportunity(token, strategy, trading_status)
                if opportunity:
                    opportunities.append(opportunity)

            return opportunities

        except Exception as e:
            logger.error(f"Error evaluating opportunity for {token.token_address}: {e}")
            return []

    async def _evaluate_strategy_opportunity(self,
                                           token: DiscoveredToken,
                                           strategy: TradingStrategy,
                                           trading_status: Dict[str, Any]) -> Optional[TradingOpportunity]:
        """Evaluate opportunity for a specific strategy."""
        try:
            # Get strategy configuration and performance
            strategy_config = await self.strategy_manager.get_strategy_list()
            active_strategy = None
            for s in strategy_config:
                if s['strategy_type'] == strategy.value and s['enabled']:
                    active_strategy = s
                    break

            if not active_strategy:
                return None

            # Strategy-specific evaluation
            opportunity = await self._strategy_specific_evaluation(token, strategy, active_strategy)

            if not opportunity:
                return None

            # Risk assessment
            risk_allowed, risk_reason, risk_info = await self.risk_controller.check_trade_risk(
                opportunity.position_size_sol,
                token.token_address,
                opportunity.confidence
            )

            if not risk_allowed:
                logger.debug(f"Risk check failed for {token.token_address}: {risk_reason}")
                return None

            # Calculate position sizing
            position_size = await self._calculate_optimal_position_size(
                token, strategy, trading_status, risk_info
            )

            if position_size <= 0:
                return None

            # Create opportunity
            opportunity_id = str(uuid.uuid4())
            trading_opportunity = TradingOpportunity(
                id=opportunity_id,
                token_address=token.token_address,
                token_symbol=token.token_symbol,
                token_name=token.token_name,
                strategy=strategy,
                action=opportunity['action'],
                confidence=opportunity['confidence'],
                expected_roi=opportunity['expected_roi'],
                risk_score=opportunity['risk_score'],
                position_size_sol=position_size,
                entry_price=opportunity['entry_price'],
                stop_loss_price=opportunity['stop_loss_price'],
                take_profit_price=opportunity['take_profit_price'],
                priority=self._determine_priority(opportunity, token),
                discovered_at=datetime.utcnow(),
                expires_at=datetime.utcnow() + timedelta(seconds=self.config['opportunity_timeout']),
                metadata={
                    'source': token.discovery_source.value,
                    'quality_score': token.quality_score,
                    'trending_score': token.trending_score,
                    'risk_info': risk_info
                }
            )

            return trading_opportunity

        except Exception as e:
            logger.error(f"Error evaluating strategy opportunity: {e}")
            return None

    async def _strategy_specific_evaluation(self,
                                          token: DiscoveredToken,
                                          strategy: TradingStrategy,
                                          strategy_config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Strategy-specific opportunity evaluation."""
        try:
            if strategy == TradingStrategy.ENHANCED_RSI:
                return await self._evaluate_rsi_opportunity(token, strategy_config)
            elif strategy == TradingStrategy.MOMENTUM:
                return await self._evaluate_momentum_opportunity(token, strategy_config)
            elif strategy == TradingStrategy.ARBITRAGE:
                return await self._evaluate_arbitrage_opportunity(token, strategy_config)
            elif strategy == TradingStrategy.FLASH_LOAN:
                return await self._evaluate_flash_loan_opportunity(token, strategy_config)
            else:
                return None

        except Exception as e:
            logger.error(f"Error in strategy-specific evaluation: {e}")
            return None

    async def _evaluate_rsi_opportunity(self,
                                       token: DiscoveredToken,
                                       strategy_config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Evaluate RSI-based trading opportunity."""
        try:
            # Simulate RSI calculation (would use real price data)
            current_price = 1.0 + (time.time() % 100) / 1000
            rsi = 30 + (time.time() % 40)  # Simulate RSI between 30-70

            oversold_threshold = strategy_config.get('parameters', {}).get('oversold_threshold', 25)
            overbought_threshold = strategy_config.get('parameters', {}).get('overbought_threshold', 75)

            if rsi < oversold_threshold:
                # Oversold - buy opportunity
                confidence = max(0.6, 1.0 - (rsi / oversold_threshold))
                return {
                    'action': 'buy',
                    'confidence': confidence,
                    'expected_roi': 0.3 + (oversold_threshold - rsi) / 100,
                    'risk_score': (oversold_threshold - rsi) / oversold_threshold,
                    'entry_price': current_price,
                    'stop_loss_price': current_price * 0.85,
                    'take_profit_price': current_price * 1.3
                }
            elif rsi > overbought_threshold:
                # Overbought - sell opportunity (if we have position)
                confidence = max(0.6, (rsi - overbought_threshold) / (100 - overbought_threshold))
                return {
                    'action': 'sell',
                    'confidence': confidence,
                    'expected_roi': 0.2 + (rsi - overbought_threshold) / 100,
                    'risk_score': (rsi - overbought_threshold) / (100 - overbought_threshold),
                    'entry_price': current_price,
                    'stop_loss_price': current_price * 1.15,
                    'take_profit_price': current_price * 0.9
                }

            return None

        except Exception as e:
            logger.error(f"Error evaluating RSI opportunity: {e}")
            return None

    async def _evaluate_momentum_opportunity(self,
                                           token: DiscoveredToken,
                                           strategy_config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Evaluate momentum-based trading opportunity."""
        try:
            # Simulate momentum calculation
            price_change_1h = (time.time() % 40 - 20) / 100  # -20% to +20%
            volume_spike = token.volume_spike
            trending_score = token.trending_score

            # Momentum signal
            momentum_score = (price_change_1h + (trending_score - 0.5) * 0.4 + (0.2 if volume_spike else 0)) / 2

            if momentum_score > 0.3:
                current_price = 1.0 + (time.time() % 100) / 1000
                confidence = min(0.9, abs(momentum_score) + 0.4)

                return {
                    'action': 'buy' if momentum_score > 0 else 'sell',
                    'confidence': confidence,
                    'expected_roi': abs(momentum_score) * 2,
                    'risk_score': abs(momentum_score),
                    'entry_price': current_price,
                    'stop_loss_price': current_price * (0.9 if momentum_score > 0 else 1.1),
                    'take_profit_price': current_price * (1.2 if momentum_score > 0 else 0.8)
                }

            return None

        except Exception as e:
            logger.error(f"Error evaluating momentum opportunity: {e}")
            return None

    async def _evaluate_arbitrage_opportunity(self,
                                            token: DiscoveredToken,
                                            strategy_config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Evaluate arbitrage opportunity."""
        try:
            # Simulate arbitrage detection
            # In practice, this would compare prices across different DEXs
            price_differential = (time.time() % 30) / 1000  # 0-3% price difference
            liquidity = token.liquidity_sol

            if price_differential > 0.5 and liquidity > 10000:  # 0.5% spread threshold
                current_price = 1.0 + (time.time() % 100) / 1000
                confidence = min(0.8, price_differential / 2)

                return {
                    'action': 'buy',  # Buy on lower price DEX, sell on higher
                    'confidence': confidence,
                    'expected_roi': price_differential / 100,
                    'risk_score': 0.2,  # Lower risk for arbitrage
                    'entry_price': current_price,
                    'stop_loss_price': current_price * 0.98,  # Tight stop loss
                    'take_profit_price': current_price * (1 + price_differential / 100)
                }

            return None

        except Exception as e:
            logger.error(f"Error evaluating arbitrage opportunity: {e}")
            return None

    async def _evaluate_flash_loan_opportunity(self,
                                             token: DiscoveredToken,
                                             strategy_config: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """Evaluate flash loan arbitrage opportunity."""
        try:
            # Simulate flash loan opportunity detection
            arbitrage_potential = (time.time() % 50) / 1000  # 0-5% potential
            gas_cost = 0.001  # Simulated gas cost

            if arbitrage_potential > 1.0:  # 1% minimum threshold after gas
                current_price = 1.0 + (time.time() % 100) / 1000
                net_profit = arbitrage_potential - gas_cost

                return {
                    'action': 'buy',
                    'confidence': min(0.9, net_profit / 5),
                    'expected_roi': net_profit / 100,
                    'risk_score': 0.3,  # Moderate risk for flash loans
                    'entry_price': current_price,
                    'stop_loss_price': current_price * 0.95,
                    'take_profit_price': current_price * (1 + net_profit / 100)
                }

            return None

        except Exception as e:
            logger.error(f"Error evaluating flash loan opportunity: {e}")
            return None

    def _determine_priority(self, opportunity: Dict[str, Any], token: DiscoveredToken) -> ExecutionPriority:
        """Determine execution priority for an opportunity."""
        try:
            score = 0

            # Confidence score
            score += opportunity['confidence'] * 0.3

            # Expected ROI
            score += min(0.3, opportunity['expected_roi'] / 2)

            # Token quality
            score += token.quality_score * 0.2

            # Trending score
            score += token.trending_score * 0.1

            # Risk score (lower is better)
            score += (1.0 - opportunity['risk_score']) * 0.1

            if score >= 0.8:
                return ExecutionPriority.CRITICAL
            elif score >= 0.6:
                return ExecutionPriority.HIGH
            elif score >= 0.4:
                return ExecutionPriority.MEDIUM
            else:
                return ExecutionPriority.LOW

        except Exception as e:
            logger.error(f"Error determining priority: {e}")
            return ExecutionPriority.MEDIUM

    async def _calculate_optimal_position_size(self,
                                             token: DiscoveredToken,
                                             strategy: TradingStrategy,
                                             trading_status: Dict[str, Any],
                                             risk_info: Dict[str, Any]) -> float:
        """Calculate optimal position size for a trade."""
        try:
            # Base position size from configuration
            base_size = self.config['max_position_size']

            # Adjust based on confidence
            confidence_multiplier = 0.5 + (token.confidence * 0.5)

            # Adjust based on token quality
            quality_multiplier = 0.7 + (token.quality_score * 0.3)

            # Adjust based on available capital
            available_capital = trading_status.get('available_cash', 1.0)
            capital_multiplier = min(1.0, available_capital / 0.1)  # Adjust based on 0.1 SOL reference

            # Adjust based on risk
            risk_multiplier = 1.0 - risk_info.get('portfolio_risk', 0)

            # Calculate final position size
            position_size = base_size * confidence_multiplier * quality_multiplier * capital_multiplier * risk_multiplier

            # Apply minimum and maximum limits
            min_size = 0.001  # 0.001 SOL minimum
            max_size = min(base_size, available_capital * 0.3)  # Max 30% of available capital

            return max(min_size, min(max_size, position_size))

        except Exception as e:
            logger.error(f"Error calculating position size: {e}")
            return 0.001  # Minimum position size

    async def execute_opportunity(self, opportunity: TradingOpportunity) -> bool:
        """
        Execute a trading opportunity.

        Args:
            opportunity: Trading opportunity to execute

        Returns:
            True if execution was successful
        """
        try:
            if not self.is_running:
                logger.debug("Auto executor is not running, skipping execution")
                return False

            # Check if opportunity has expired
            if datetime.utcnow() > opportunity.expires_at:
                logger.debug(f"Opportunity {opportunity.id} has expired")
                return False

            # Check concurrent trade limit
            if len(self.active_trades) >= self.config['max_concurrent_trades']:
                logger.debug("Maximum concurrent trades reached")
                return False

            # Create automated trade record
            trade_id = str(uuid.uuid4())
            automated_trade = AutomatedTrade(
                id=trade_id,
                opportunity_id=opportunity.id,
                token_address=opportunity.token_address,
                strategy=opportunity.strategy,
                action=opportunity.action,
                amount_sol=opportunity.position_size_sol,
                status=TradeStatus.PENDING,
                created_at=datetime.utcnow(),
                executed_at=None,
                completed_at=None,
                execution_price=None,
                realized_pnl=None,
                fees=None,
                tx_signature=None,
                error_message=None
            )

            self.active_trades[trade_id] = automated_trade

            # Update opportunity status
            opportunity.metadata['execution_started'] = datetime.utcnow().isoformat()

            # Execute trade through trading controller
            execution_start = time.time()

            trade_request = {
                'token_address': opportunity.token_address,
                'action': opportunity.action,
                'amount_sol': opportunity.position_size_sol,
                'strategy': opportunity.strategy.value,
                'confidence': opportunity.confidence,
                'stop_loss': opportunity.stop_loss_price,
                'take_profit': opportunity.take_profit_price
            }

            # Execute the trade
            trade_result = await self.trading_controller.execute_trade(trade_request)

            execution_time = time.time() - execution_start

            if trade_result and trade_result.get('success', False):
                # Successful execution
                automated_trade.status = TradeStatus.EXECUTED
                automated_trade.executed_at = datetime.utcnow()
                automated_trade.execution_price = trade_result.get('execution_price', opportunity.entry_price)
                automated_trade.tx_signature = trade_result.get('tx_signature')
                automated_trade.fees = trade_result.get('fees', 0.0)

                # Update performance metrics
                self.performance_metrics['trades_executed'] += 1
                self.performance_metrics['successful_trades'] += 1
                self.performance_metrics['last_execution_time'] = datetime.utcnow()

                # Update average execution time
                total_trades = self.performance_metrics['trades_executed']
                current_avg = self.performance_metrics['avg_execution_time']
                self.performance_metrics['avg_execution_time'] = (
                    (current_avg * (total_trades - 1) + execution_time) / total_trades
                )

                # Store trade completion
                await self._store_completed_trade(automated_trade, trade_result)

                logger.info(f"Successfully executed automated trade: {trade_id} ({opportunity.action} {opportunity.token_symbol})")
                return True

            else:
                # Failed execution
                automated_trade.status = TradeStatus.FAILED
                automated_trade.error_message = trade_result.get('error', 'Unknown error') if trade_result else 'Execution failed'

                self.performance_metrics['trades_executed'] += 1
                self.performance_metrics['failed_trades'] += 1

                logger.error(f"Failed to execute automated trade: {trade_id} - {automated_trade.error_message}")
                return False

        except Exception as e:
            logger.error(f"Error executing opportunity {opportunity.id}: {e}")
            if opportunity.id in self.active_trades:
                self.active_trades[opportunity.id].status = TradeStatus.FAILED
                self.active_trades[opportunity.id].error_message = str(e)
            return False

    # Background tasks

    async def _start_background_tasks(self):
        """Start background execution and monitoring tasks."""
        try:
            self.execution_task = asyncio.create_task(self._execution_loop())
            self.monitoring_task = asyncio.create_task(self._monitoring_loop())
            self.cleanup_task = asyncio.create_task(self._cleanup_loop())

            logger.info("Background execution tasks started")

        except Exception as e:
            logger.error(f"Error starting background tasks: {e}")

    async def _execution_loop(self):
        """Main execution loop for processing opportunities."""
        try:
            while True:
                try:
                    if self.is_running:
                        await self._process_execution_queue()

                    await asyncio.sleep(self.config['execution_interval'])

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in execution loop: {e}")
                    await asyncio.sleep(30)

        except Exception as e:
            logger.error(f"Fatal error in execution loop: {e}")

    async def _monitoring_loop(self):
        """Background task for monitoring active trades."""
        try:
            while True:
                try:
                    await self._monitor_active_trades()
                    await self._track_strategy_performance()
                    await self._update_performance_metrics()

                    await asyncio.sleep(30)  # Every 30 seconds

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in monitoring loop: {e}")
                    await asyncio.sleep(60)

        except Exception as e:
            logger.error(f"Fatal error in monitoring loop: {e}")

    async def _cleanup_loop(self):
        """Background task for cleanup operations."""
        try:
            while True:
                try:
                    await self._cleanup_expired_opportunities()
                    await self._cleanup_completed_trades()
                    await self._rebalance_portfolio()

                    await asyncio.sleep(300)  # Every 5 minutes

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in cleanup loop: {e}")
                    await asyncio.sleep(300)

        except Exception as e:
            logger.error(f"Fatal error in cleanup loop: {e}")

    async def _process_execution_queue(self):
        """Process the execution queue of opportunities."""
        try:
            if not self.execution_queue:
                return

            # Sort queue by priority
            self.execution_queue.sort(key=lambda opp_id: self._get_priority_weight(self.opportunities.get(opp_id)), reverse=True)

            # Process top opportunities
            executed_count = 0
            for opportunity_id in self.execution_queue[:]:
                if executed_count >= 3:  # Max 3 executions per cycle
                    break

                opportunity = self.opportunities.get(opportunity_id)
                if not opportunity:
                    self.execution_queue.remove(opportunity_id)
                    continue

                # Check if still valid
                if datetime.utcnow() > opportunity.expires_at:
                    self.execution_queue.remove(opportunity_id)
                    del self.opportunities[opportunity_id]
                    continue

                # Execute opportunity
                if await self.execute_opportunity(opportunity):
                    executed_count += 1
                    self.execution_queue.remove(opportunity_id)

        except Exception as e:
            logger.error(f"Error processing execution queue: {e}")

    def _get_priority_weight(self, opportunity: Optional[TradingOpportunity]) -> int:
        """Get numerical weight for priority sorting."""
        if not opportunity:
            return 0

        priority_weights = {
            ExecutionPriority.CRITICAL: 4,
            ExecutionPriority.HIGH: 3,
            ExecutionPriority.MEDIUM: 2,
            ExecutionPriority.LOW: 1
        }

        return priority_weights.get(opportunity.priority, 1)

    async def _monitor_active_trades(self):
        """Monitor and manage active trades."""
        try:
            for trade_id, trade in list(self.active_trades.items()):
                if trade.status == TradeStatus.EXECUTED:
                    # Check if trade should be completed (stop loss/take profit)
                    await self._check_trade_completion(trade)

                elif trade.status == TradeStatus.FAILED:
                    # Remove failed trades after some time
                    if datetime.utcnow() - trade.created_at > timedelta(minutes=5):
                        self.active_trades.pop(trade_id, None)

        except Exception as e:
            logger.error(f"Error monitoring active trades: {e}")

    async def _check_trade_completion(self, trade: AutomatedTrade):
        """Check if a trade should be completed (stop loss/take profit)."""
        try:
            # Get current token price
            current_price = await self._get_current_price(trade.token_address)
            if current_price is None:
                return

            opportunity = self.opportunities.get(trade.opportunity_id)
            if not opportunity:
                return

            should_close = False
            close_reason = ""

            # Check stop loss
            if trade.action == 'buy' and current_price <= opportunity.stop_loss_price:
                should_close = True
                close_reason = "stop_loss"
            elif trade.action == 'sell' and current_price >= opportunity.stop_loss_price:
                should_close = True
                close_reason = "stop_loss"

            # Check take profit
            elif trade.action == 'buy' and current_price >= opportunity.take_profit_price:
                should_close = True
                close_reason = "take_profit"
            elif trade.action == 'sell' and current_price <= opportunity.take_profit_price:
                should_close = True
                close_reason = "take_profit"

            # Execute closing trade if needed
            if should_close:
                await self._execute_closing_trade(trade, current_price, close_reason)

        except Exception as e:
            logger.error(f"Error checking trade completion: {e}")

    async def _execute_closing_trade(self, trade: AutomatedTrade, current_price: float, reason: str):
        """Execute a closing trade for an automated trade."""
        try:
            # Create closing trade request
            closing_action = 'sell' if trade.action == 'buy' else 'buy'

            closing_request = {
                'token_address': trade.token_address,
                'action': closing_action,
                'amount_sol': trade.amount_sol,
                'strategy': f"{trade.strategy.value}_close_{reason}",
                'confidence': 1.0,  # High confidence for closing
                'reason': reason
            }

            # Execute closing trade
            closing_result = await self.trading_controller.execute_trade(closing_request)

            if closing_result and closing_result.get('success', False):
                # Calculate realized P&L
                if trade.action == 'buy':
                    realized_pnl = (current_price - trade.execution_price) * trade.amount_sol
                else:
                    realized_pnl = (trade.execution_price - current_price) * trade.amount_sol

                # Update trade record
                trade.status = TradeStatus.EXECUTED
                trade.completed_at = datetime.utcnow()
                trade.realized_pnl = realized_pnl

                # Update performance metrics
                self.performance_metrics['total_pnl'] += realized_pnl

                logger.info(f"Closed automated trade {trade.id} with P&L: {realized_pnl:.6f} SOL ({reason})")

                # Store completion
                await self._store_trade_completion(trade, reason, realized_pnl)

            else:
                logger.error(f"Failed to close automated trade {trade.id}")

        except Exception as e:
            logger.error(f"Error executing closing trade: {e}")

    async def _track_strategy_performance(self):
        """Track performance of different strategies."""
        try:
            for trade_id, trade in self.active_trades.items():
                if trade.status == TradeStatus.EXECUTED and trade.realized_pnl is not None:
                    strategy = trade.strategy.value

                    if strategy not in self.performance_metrics['strategy_performance']:
                        self.performance_metrics['strategy_performance'][strategy] = {
                            'trades': 0,
                            'pnl': 0.0,
                            'win_rate': 0.0,
                            'avg_pnl': 0.0
                        }

                    perf = self.performance_metrics['strategy_performance'][strategy]
                    perf['trades'] += 1
                    perf['pnl'] += trade.realized_pnl
                    perf['avg_pnl'] = perf['pnl'] / perf['trades']

                    # Calculate win rate
                    profitable_trades = sum(
                        1 for t in self.active_trades.values()
                        if t.strategy == strategy and t.realized_pnl and t.realized_pnl > 0
                    )
                    perf['win_rate'] = profitable_trades / perf['trades']

        except Exception as e:
            logger.error(f"Error tracking strategy performance: {e}")

    async def _cleanup_expired_opportunities(self):
        """Clean up expired opportunities."""
        try:
            current_time = datetime.utcnow()
            expired_opportunities = []

            for opp_id, opportunity in self.opportunities.items():
                if current_time > opportunity.expires_at:
                    expired_opportunities.append(opp_id)

            for opp_id in expired_opportunities:
                self.opportunities.pop(opp_id, None)
                if opp_id in self.execution_queue:
                    self.execution_queue.remove(opp_id)

            if expired_opportunities:
                logger.debug(f"Cleaned up {len(expired_opportunities)} expired opportunities")

        except Exception as e:
            logger.error(f"Error cleaning up expired opportunities: {e}")

    async def _cleanup_completed_trades(self):
        """Clean up old completed trades."""
        try:
            cutoff_time = datetime.utcnow() - timedelta(hours=24)
            old_trades = []

            for trade_id, trade in self.active_trades.items():
                if (trade.status in [TradeStatus.EXECUTED, TradeStatus.FAILED] and
                    trade.created_at < cutoff_time):
                    old_trades.append(trade_id)

            for trade_id in old_trades:
                self.active_trades.pop(trade_id, None)

            if old_trades:
                logger.debug(f"Cleaned up {len(old_trades)} old trades")

        except Exception as e:
            logger.error(f"Error cleaning up completed trades: {e}")

    async def _rebalance_portfolio(self):
        """Automatically rebalance portfolio if enabled."""
        try:
            if not self.config['auto_rebalance']:
                return

            # Get current portfolio status
            portfolio_status = await self.trading_controller.get_portfolio_state()

            # Simple rebalancing logic - could be more sophisticated
            total_value = portfolio_status.get('portfolio_value', 0)
            if total_value == 0:
                return

            # Check for concentration risk
            positions = portfolio_status.get('positions', {})
            if len(positions) > 0:
                max_position_ratio = max(
                    pos.get('value', 0) / total_value for pos in positions.values()
                )

                # If any position is more than 50% of portfolio, consider rebalancing
                if max_position_ratio > 0.5:
                    logger.info(f"Portfolio concentration detected: {max_position_ratio:.2%}")
                    # Could implement rebalancing logic here

        except Exception as e:
            logger.error(f"Error rebalancing portfolio: {e}")

    async def _subscribe_to_discoveries(self):
        """Subscribe to token discovery notifications."""
        try:
            # This would subscribe to Redis pub/sub for token discoveries
            # For now, we'll simulate the subscription
            pass

        except Exception as e:
            logger.error(f"Error subscribing to discoveries: {e}")

    async def _load_existing_data(self):
        """Load existing opportunities and trades."""
        try:
            # Load existing opportunities from Redis
            opportunity_data = await self.redis_client.lrange("auto_opportunities", 0, 99)

            for data in opportunity_data:
                try:
                    opp_dict = json.loads(data)
                    opportunity = TradingOpportunity(**opp_dict)
                    opportunity.discovered_at = datetime.fromisoformat(opp_dict['discovered_at'])
                    opportunity.expires_at = datetime.fromisoformat(opp_dict['expires_at'])

                    # Check if still valid
                    if datetime.utcnow() < opportunity.expires_at:
                        self.opportunities[opportunity.id] = opportunity
                        self.execution_queue.append(opportunity.id)

                except Exception as e:
                    logger.error(f"Error loading opportunity: {e}")

            logger.info(f"Loaded {len(self.opportunities)} existing opportunities")

        except Exception as e:
            logger.error(f"Error loading existing data: {e}")

    async def _store_completed_trade(self, trade: AutomatedTrade, trade_result: Dict[str, Any]):
        """Store completed trade information."""
        try:
            trade_data = asdict(trade)
            trade_data['created_at'] = trade.created_at.isoformat()
            if trade.executed_at:
                trade_data['executed_at'] = trade.executed_at.isoformat()

            await self.redis_client.lpush(
                "auto_trades_completed",
                json.dumps(trade_data)
            )
            await self.redis_client.ltrim("auto_trades_completed", 0, 999)  # Keep last 1000

        except Exception as e:
            logger.error(f"Error storing completed trade: {e}")

    async def _store_trade_completion(self, trade: AutomatedTrade, reason: str, pnl: float):
        """Store trade completion details."""
        try:
            completion_data = {
                'trade_id': trade.id,
                'strategy': trade.strategy.value,
                'token_address': trade.token_address,
                'action': trade.action,
                'amount_sol': trade.amount_sol,
                'pnl': pnl,
                'reason': reason,
                'completed_at': datetime.utcnow().isoformat()
            }

            await self.redis_client.lpush(
                "auto_trade_completions",
                json.dumps(completion_data)
            )
            await self.redis_client.ltrim("auto_trade_completions", 0, 999)

        except Exception as e:
            logger.error(f"Error storing trade completion: {e}")

    async def _get_current_price(self, token_address: str) -> Optional[float]:
        """Get current price for a token."""
        try:
            # This would integrate with your price feed API
            # For now, simulate price
            return 1.0 + (time.time() % 100) / 1000

        except Exception as e:
            logger.error(f"Error getting current price: {e}")
            return None

    async def _update_performance_metrics(self):
        """Store performance metrics in Redis."""
        try:
            metrics_data = self.performance_metrics.copy()
            if metrics_data['last_execution_time']:
                metrics_data['last_execution_time'] = metrics_data['last_execution_time'].isoformat()

            await self.redis_client.set(
                "auto_executor_metrics",
                json.dumps(metrics_data),
                ex=3600  # 1 hour
            )

        except Exception as e:
            logger.error(f"Error updating performance metrics: {e}")

    async def _cancel_pending_opportunities(self):
        """Cancel all pending opportunities."""
        try:
            for opportunity_id in list(self.opportunities.keys()):
                opportunity = self.opportunities[opportunity_id]
                opportunity.metadata['cancelled_at'] = datetime.utcnow().isoformat()
                opportunity.metadata['cancellation_reason'] = "auto_stop"

            self.opportunities.clear()
            self.execution_queue.clear()

            logger.info("Cancelled all pending opportunities")

        except Exception as e:
            logger.error(f"Error cancelling opportunities: {e}")

    # Public API methods

    async def add_opportunity(self, opportunity: TradingOpportunity) -> bool:
        """Add a trading opportunity to the execution queue."""
        try:
            if len(self.execution_queue) >= self.config['opportunity_queue_size']:
                logger.warning("Opportunity queue is full, dropping opportunity")
                return False

            self.opportunities[opportunity.id] = opportunity
            self.execution_queue.append(opportunity.id)
            self.performance_metrics['total_opportunities'] += 1

            logger.debug(f"Added opportunity {opportunity.id} to execution queue")
            return True

        except Exception as e:
            logger.error(f"Error adding opportunity: {e}")
            return False

    async def get_active_opportunities(self) -> List[Dict[str, Any]]:
        """Get current active opportunities."""
        try:
            return [asdict(opp) for opp in self.opportunities.values()]

        except Exception as e:
            logger.error(f"Error getting active opportunities: {e}")
            return []

    async def get_active_trades(self) -> List[Dict[str, Any]]:
        """Get current active trades."""
        try:
            return [asdict(trade) for trade in self.active_trades.values()]

        except Exception as e:
            logger.error(f"Error getting active trades: {e}")
            return []

    async def get_performance_metrics(self) -> Dict[str, Any]:
        """Get current performance metrics."""
        try:
            return self.performance_metrics.copy()

        except Exception as e:
            logger.error(f"Error getting performance metrics: {e}")
            return {}

    async def shutdown(self):
        """Shutdown the auto strategy executor."""
        try:
            await self.stop_automated_trading()

            # Cancel background tasks
            if self.execution_task and not self.execution_task.done():
                self.execution_task.cancel()

            if self.monitoring_task and not self.monitoring_task.done():
                self.monitoring_task.cancel()

            if self.cleanup_task and not self.cleanup_task.done():
                self.cleanup_task.cancel()

            logger.info("Auto Strategy Executor shutdown complete")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")