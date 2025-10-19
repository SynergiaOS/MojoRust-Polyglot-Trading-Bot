#!/usr/bin/env python3
"""
MojoRust Manual Targeting Service

Allows manual addition of token addresses for sniper trading.
Users can add specific token addresses they want the bot to monitor
and potentially trade based on configurable criteria.

Features:
- Add/remove token addresses from watchlist
- Configure individual token parameters
- Monitor multiple tokens simultaneously
- Priority-based token targeting
- Real-time token analysis
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, asdict
from enum import Enum
import uuid

import redis.asyncio as aioredis

logger = logging.getLogger(__name__)

class TokenPriority(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class TokenStatus(str, Enum):
    WATCHING = "watching"
    ANALYZING = "analyzing"
    TRADING = "trading"
    COMPLETED = "completed"
    FAILED = "failed"
    REMOVED = "removed"

@dataclass
class ManualTokenTarget:
    """Represents a manually added token target"""
    token_address: str
    token_symbol: Optional[str]
    token_name: Optional[str]
    added_at: datetime
    added_by: str  # user_id or system
    priority: TokenPriority
    status: TokenStatus
    max_buy_amount_sol: float
    min_liquidity_sol: float
    target_roi: float
    stop_loss_percentage: float
    take_profit_percentage: float
    confidence_threshold: float
    notes: Optional[str]
    expires_at: Optional[datetime]
    analysis_data: Optional[Dict[str, Any]]
    trade_executed: bool = False
    execution_time: Optional[datetime] = None
    result_pnl: Optional[float] = None

class ManualTargetingService:
    """
    Service for managing manually added token targets.
    """

    def __init__(self, redis_client: aioredis.Redis):
        self.redis_client = redis_client

        # Token watchlist
        self.watchlist: Dict[str, ManualTokenTarget] = {}
        self.active_analysis: Set[str] = set()

        # Configuration
        self.config = {
            'max_watchlist_size': 100,
            'default_max_buy_amount': 0.1,  # 0.1 SOL
            'default_min_liquidity': 10.0,   # 10 SOL
            'default_target_roi': 0.5,       # 50%
            'default_stop_loss': 0.2,        # 20%
            'default_take_profit': 1.0,      # 100%
            'default_confidence': 0.7,       # 70%
            'default_expiry_hours': 24,       # 24 hours
            'analysis_interval': 30,          # 30 seconds
            'max_concurrent_analysis': 5
        }

        # Background tasks
        self.analysis_task: Optional[asyncio.Task] = None
        self.cleanup_task: Optional[asyncio.Task] = None

        # Statistics
        self.stats = {
            'total_tokens_added': 0,
            'tokens_traded': 0,
            'successful_trades': 0,
            'total_pnl': 0.0,
            'avg_analysis_time': 0.0
        }

    async def initialize(self):
        """Initialize the service."""
        try:
            # Load existing watchlist from Redis
            await self._load_watchlist()

            # Start background tasks
            await self._start_background_tasks()

            logger.info("Manual Targeting Service initialized")

        except Exception as e:
            logger.error(f"Failed to initialize Manual Targeting Service: {e}")
            raise

    async def add_token_target(self,
                              token_address: str,
                              token_symbol: Optional[str] = None,
                              token_name: Optional[str] = None,
                              priority: TokenPriority = TokenPriority.MEDIUM,
                              max_buy_amount_sol: Optional[float] = None,
                              min_liquidity_sol: Optional[float] = None,
                              target_roi: Optional[float] = None,
                              stop_loss_percentage: Optional[float] = None,
                              take_profit_percentage: Optional[float] = None,
                              confidence_threshold: Optional[float] = None,
                              expires_hours: Optional[int] = None,
                              notes: Optional[str] = None,
                              added_by: str = "user") -> str:
        """
        Add a new token target to the watchlist.

        Args:
            token_address: The token contract address
            token_symbol: Token symbol (optional)
            token_name: Token name (optional)
            priority: Priority level for monitoring
            max_buy_amount_sol: Maximum amount to buy in SOL
            min_liquidity_sol: Minimum liquidity required
            target_roi: Target return on investment
            stop_loss_percentage: Stop loss percentage
            take_profit_percentage: Take profit percentage
            confidence_threshold: Minimum confidence for trading
            expires_hours: Hours until token target expires
            notes: User notes about the token
            added_by: Who added the token

        Returns:
            Target ID for reference
        """
        try:
            # Validate token address
            if not await self._validate_token_address(token_address):
                raise ValueError(f"Invalid token address: {token_address}")

            # Check if token already exists
            if token_address in self.watchlist:
                logger.warning(f"Token {token_address} already in watchlist")
                return self.watchlist[token_address].token_address

            # Check watchlist size limit
            if len(self.watchlist) >= self.config['max_watchlist_size']:
                # Remove lowest priority oldest token
                await self._cleanup_old_tokens()

            # Create target
            target_id = str(uuid.uuid4())
            now = datetime.utcnow()

            expires_at = None
            if expires_hours:
                expires_at = now + timedelta(hours=expires_hours)

            target = ManualTokenTarget(
                token_address=token_address,
                token_symbol=token_symbol,
                token_name=token_name,
                added_at=now,
                added_by=added_by,
                priority=priority,
                status=TokenStatus.WATCHING,
                max_buy_amount_sol=max_buy_amount_sol or self.config['default_max_buy_amount'],
                min_liquidity_sol=min_liquidity_sol or self.config['default_min_liquidity'],
                target_roi=target_roi or self.config['default_target_roi'],
                stop_loss_percentage=stop_loss_percentage or self.config['default_stop_loss'],
                take_profit_percentage=take_profit_percentage or self.config['default_take_profit'],
                confidence_threshold=confidence_threshold or self.config['default_confidence'],
                notes=notes,
                expires_at=expires_at,
                analysis_data=None
            )

            # Add to watchlist
            self.watchlist[token_address] = target
            self.stats['total_tokens_added'] += 1

            # Store in Redis
            await self._store_target(target)

            # Log addition
            logger.info(f"Added token target: {token_address} (Symbol: {token_symbol}, Priority: {priority})")

            return target_id

        except Exception as e:
            logger.error(f"Error adding token target: {e}")
            raise

    async def remove_token_target(self, token_address: str, reason: str = "user_removed") -> bool:
        """
        Remove a token target from the watchlist.

        Args:
            token_address: Token address to remove
            reason: Reason for removal

        Returns:
            True if removed successfully
        """
        try:
            if token_address not in self.watchlist:
                logger.warning(f"Token {token_address} not found in watchlist")
                return False

            target = self.watchlist[token_address]
            target.status = TokenStatus.REMOVED

            # Remove from active analysis
            if token_address in self.active_analysis:
                self.active_analysis.discard(token_address)

            # Remove from watchlist
            del self.watchlist[token_address]

            # Update Redis
            await self._remove_target_from_redis(token_address, reason)

            logger.info(f"Removed token target: {token_address} (Reason: {reason})")
            return True

        except Exception as e:
            logger.error(f"Error removing token target: {e}")
            return False

    async def get_watchlist(self,
                           status_filter: Optional[TokenStatus] = None,
                           priority_filter: Optional[TokenPriority] = None,
                           limit: Optional[int] = None) -> List[Dict[str, Any]]:
        """
        Get the current watchlist with optional filtering.

        Args:
            status_filter: Filter by token status
            priority_filter: Filter by priority level
            limit: Maximum number of results

        Returns:
            List of token targets
        """
        try:
            targets = []

            # Sort by priority and added time
            sorted_targets = sorted(
                self.watchlist.values(),
                key=lambda t: (t.priority.value, t.added_at),
                reverse=True
            )

            for target in sorted_targets:
                # Apply filters
                if status_filter and target.status != status_filter:
                    continue
                if priority_filter and target.priority != priority_filter:
                    continue

                # Convert to dict
                target_dict = asdict(target)
                target_dict['added_at'] = target.added_at.isoformat()
                if target.expires_at:
                    target_dict['expires_at'] = target.expires_at.isoformat()
                if target.execution_time:
                    target_dict['execution_time'] = target.execution_time.isoformat()

                targets.append(target_dict)

                # Apply limit
                if limit and len(targets) >= limit:
                    break

            return targets

        except Exception as e:
            logger.error(f"Error getting watchlist: {e}")
            return []

    async def get_token_analysis(self, token_address: str) -> Optional[Dict[str, Any]]:
        """
        Get detailed analysis for a specific token.

        Args:
            token_address: Token address to analyze

        Returns:
            Analysis data or None if not found
        """
        try:
            if token_address not in self.watchlist:
                return None

            target = self.watchlist[token_address]

            # Get real-time analysis
            analysis = await self._analyze_token(token_address, target)

            return {
                'target_info': asdict(target),
                'real_time_analysis': analysis,
                'recommendation': await self._get_trading_recommendation(target, analysis)
            }

        except Exception as e:
            logger.error(f"Error getting token analysis: {e}")
            return None

    async def update_target_parameters(self,
                                     token_address: str,
                                     **kwargs) -> bool:
        """
        Update parameters for an existing token target.

        Args:
            token_address: Token address to update
            **kwargs: Parameters to update

        Returns:
            True if updated successfully
        """
        try:
            if token_address not in self.watchlist:
                logger.warning(f"Token {token_address} not found in watchlist")
                return False

            target = self.watchlist[token_address]

            # Update allowed parameters
            updatable_fields = [
                'priority', 'max_buy_amount_sol', 'min_liquidity_sol',
                'target_roi', 'stop_loss_percentage', 'take_profit_percentage',
                'confidence_threshold', 'notes', 'expires_at'
            ]

            for field, value in kwargs.items():
                if field in updatable_fields:
                    setattr(target, field, value)

            # Store updated target
            await self._store_target(target)

            logger.info(f"Updated parameters for token: {token_address}")
            return True

        except Exception as e:
            logger.error(f"Error updating target parameters: {e}")
            return False

    async def execute_manual_trade(self,
                                  token_address: str,
                                  action: str,
                                  amount_sol: Optional[float] = None,
                                  force_execution: bool = False) -> Dict[str, Any]:
        """
        Execute a manual trade for a watched token.

        Args:
            token_address: Token address to trade
            action: 'buy' or 'sell'
            amount_sol: Amount in SOL (uses target default if not provided)
            force_execution: Force execution even if criteria not met

        Returns:
            Trade execution result
        """
        try:
            if token_address not in self.watchlist:
                return {'success': False, 'error': 'Token not in watchlist'}

            target = self.watchlist[token_address]

            # Use target default amount if not provided
            if amount_sol is None:
                amount_sol = target.max_buy_amount_sol

            # Get current analysis
            analysis = await self._analyze_token(token_address, target)

            # Check if trade meets criteria (unless forced)
            if not force_execution:
                recommendation = await self._get_trading_recommendation(target, analysis)
                if not recommendation['should_trade']:
                    return {
                        'success': False,
                        'error': f"Trade criteria not met: {recommendation['reason']}"
                    }

            # Execute trade (this would integrate with your trading controller)
            trade_result = await self._execute_trade_with_controller(
                token_address, action, amount_sol, target
            )

            if trade_result['success']:
                # Update target status
                target.trade_executed = True
                target.execution_time = datetime.utcnow()
                target.status = TokenStatus.COMPLETED

                # Update statistics
                self.stats['tokens_traded'] += 1
                if trade_result.get('pnl', 0) > 0:
                    self.stats['successful_trades'] += 1
                self.stats['total_pnl'] += trade_result.get('pnl', 0)

                # Store updated target
                await self._store_target(target)

            return trade_result

        except Exception as e:
            logger.error(f"Error executing manual trade: {e}")
            return {'success': False, 'error': str(e)}

    async def get_statistics(self) -> Dict[str, Any]:
        """Get service statistics."""
        try:
            # Calculate additional stats
            success_rate = 0.0
            if self.stats['tokens_traded'] > 0:
                success_rate = self.stats['successful_trades'] / self.stats['tokens_traded']

            return {
                **self.stats,
                'success_rate': success_rate,
                'watchlist_size': len(self.watchlist),
                'active_analysis_count': len(self.active_analysis),
                'status_distribution': self._get_status_distribution(),
                'priority_distribution': self._get_priority_distribution()
            }

        except Exception as e:
            logger.error(f"Error getting statistics: {e}")
            return {}

    # Private methods

    async def _validate_token_address(self, token_address: str) -> bool:
        """Validate token address format."""
        try:
            # Basic Solana address validation
            if len(token_address) not in [43, 44]:  # Solana addresses are 43-44 chars
                return False
            if not token_address.isalnum():
                return False

            # Could add more sophisticated validation here
            return True

        except Exception:
            return False

    async def _store_target(self, target: ManualTokenTarget):
        """Store target in Redis."""
        try:
            target_data = asdict(target)
            target_data['added_at'] = target.added_at.isoformat()
            if target.expires_at:
                target_data['expires_at'] = target.expires_at.isoformat()

            await self.redis_client.set(
                f"watchlist:{target.token_address}",
                json.dumps(target_data),
                ex=86400 * 7  # 7 days
            )

        except Exception as e:
            logger.error(f"Error storing target: {e}")

    async def _remove_target_from_redis(self, token_address: str, reason: str):
        """Remove target from Redis."""
        try:
            await self.redis_client.delete(f"watchlist:{token_address}")

            # Store removal record
            removal_data = {
                'token_address': token_address,
                'removed_at': datetime.utcnow().isoformat(),
                'reason': reason
            }

            await self.redis_client.lpush(
                'watchlist:removed',
                json.dumps(removal_data)
            )
            await self.redis_client.ltrim('watchlist:removed', 0, 999)  # Keep last 1000

        except Exception as e:
            logger.error(f"Error removing target from Redis: {e}")

    async def _load_watchlist(self):
        """Load watchlist from Redis."""
        try:
            # Get all watchlist keys
            keys = await self.redis_client.keys("watchlist:*")

            for key in keys:
                try:
                    data = await self.redis_client.get(key)
                    if data:
                        target_data = json.loads(data)

                        # Reconstruct target object
                        target = ManualTokenTarget(
                            token_address=target_data['token_address'],
                            token_symbol=target_data.get('token_symbol'),
                            token_name=target_data.get('token_name'),
                            added_at=datetime.fromisoformat(target_data['added_at']),
                            added_by=target_data['added_by'],
                            priority=TokenPriority(target_data['priority']),
                            status=TokenStatus(target_data['status']),
                            max_buy_amount_sol=target_data['max_buy_amount_sol'],
                            min_liquidity_sol=target_data['min_liquidity_sol'],
                            target_roi=target_data['target_roi'],
                            stop_loss_percentage=target_data['stop_loss_percentage'],
                            take_profit_percentage=target_data['take_profit_percentage'],
                            confidence_threshold=target_data['confidence_threshold'],
                            notes=target_data.get('notes'),
                            expires_at=datetime.fromisoformat(target_data['expires_at']) if target_data.get('expires_at') else None,
                            analysis_data=target_data.get('analysis_data')
                        )

                        # Check if expired
                        if target.expires_at and datetime.utcnow() > target.expires_at:
                            target.status = TokenStatus.COMPLETED
                            await self._remove_target_from_redis(target.token_address, "expired")
                        else:
                            self.watchlist[target.token_address] = target

                except Exception as e:
                    logger.error(f"Error loading target from {key}: {e}")

            logger.info(f"Loaded {len(self.watchlist)} targets from Redis")

        except Exception as e:
            logger.error(f"Error loading watchlist: {e}")

    async def _start_background_tasks(self):
        """Start background tasks."""
        try:
            self.analysis_task = asyncio.create_task(self._analysis_loop())
            self.cleanup_task = asyncio.create_task(self._cleanup_loop())

            logger.info("Background tasks started")

        except Exception as e:
            logger.error(f"Error starting background tasks: {e}")

    async def _analysis_loop(self):
        """Background task to analyze tokens."""
        try:
            while True:
                try:
                    # Get tokens that need analysis
                    tokens_to_analyze = await self._get_tokens_for_analysis()

                    # Analyze tokens concurrently
                    if tokens_to_analyze:
                        tasks = []
                        for token_address in tokens_to_analyze:
                            if len(self.active_analysis) < self.config['max_concurrent_analysis']:
                                self.active_analysis.add(token_address)
                                task = asyncio.create_task(self._analyze_and_store(token_address))
                                tasks.append((token_address, task))

                        # Wait for analysis to complete
                        for token_address, task in tasks:
                            try:
                                await task
                            except Exception as e:
                                logger.error(f"Error analyzing token {token_address}: {e}")
                            finally:
                                self.active_analysis.discard(token_address)

                    # Wait before next cycle
                    await asyncio.sleep(self.config['analysis_interval'])

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in analysis loop: {e}")
                    await asyncio.sleep(60)

        except Exception as e:
            logger.error(f"Fatal error in analysis loop: {e}")

    async def _cleanup_loop(self):
        """Background task to clean up expired tokens."""
        try:
            while True:
                try:
                    await self._cleanup_expired_tokens()
                    await asyncio.sleep(300)  # Check every 5 minutes

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in cleanup loop: {e}")
                    await asyncio.sleep(300)

        except Exception as e:
            logger.error(f"Fatal error in cleanup loop: {e}")

    async def _get_tokens_for_analysis(self) -> List[str]:
        """Get list of tokens that need analysis."""
        try:
            tokens = []

            for token_address, target in self.watchlist.items():
                if (target.status in [TokenStatus.WATCHING, TokenStatus.ANALYZING] and
                    token_address not in self.active_analysis):
                    tokens.append(token_address)

            # Sort by priority
            tokens.sort(key=lambda addr: self.watchlist[addr].priority.value, reverse=True)

            return tokens

        except Exception as e:
            logger.error(f"Error getting tokens for analysis: {e}")
            return []

    async def _analyze_and_store(self, token_address: str):
        """Analyze token and store results."""
        try:
            if token_address not in self.watchlist:
                return

            target = self.watchlist[token_address]
            target.status = TokenStatus.ANALYZING

            # Perform analysis
            analysis = await self._analyze_token(token_address, target)
            target.analysis_data = analysis

            # Store updated target
            await self._store_target(target)

            # Check if token meets criteria for trading
            if await self._check_trading_criteria(target, analysis):
                target.status = TokenStatus.TRADING
                logger.info(f"Token {token_address} meets trading criteria")

            else:
                target.status = TokenStatus.WATCHING

        except Exception as e:
            logger.error(f"Error analyzing and storing token {token_address}: {e}")
            if token_address in self.watchlist:
                self.watchlist[token_address].status = TokenStatus.FAILED

    async def _analyze_token(self, token_address: str, target: ManualTokenTarget) -> Dict[str, Any]:
        """
        Perform real-time analysis of a token.
        This would integrate with your existing analysis systems.
        """
        try:
            # This is where you would integrate with your existing analysis:
            # - Mojo analysis engine
            # - Sentiment analysis
            # - Technical indicators
            # - On-chain data analysis

            # For demonstration, return simulated analysis data
            current_time = time.time()

            return {
                'token_address': token_address,
                'analysis_time': datetime.utcnow().isoformat(),
                'price': 1.0 + (current_time % 100) / 1000,  # Simulated price
                'liquidity_sol': 50.0 + (current_time % 200),  # Simulated liquidity
                'volume_24h': 1000.0 + (current_time % 5000),  # Simulated volume
                'holders': 100 + (current_time % 1000),  # Simulated holders
                'market_cap': 10000.0 + (current_time % 50000),  # Simulated market cap
                'sentiment_score': 0.5 + (current_time % 100) / 200,  # Simulated sentiment
                'technical_indicators': {
                    'rsi': 50.0 + (current_time % 100),
                    'macd': 0.1 + (current_time % 50) / 100,
                    'volume_spike': current_time % 10 == 0
                },
                'on_chain_metrics': {
                    'buy_pressure': 0.6,
                    'sell_pressure': 0.4,
                    'large_transactions': current_time % 20 == 0,
                    'whale_activity': current_time % 30 == 0
                },
                'confidence_score': 0.7 + (current_time % 60) / 200,  # Simulated confidence
                'risk_score': 0.3 + (current_time % 40) / 100  # Simulated risk
            }

        except Exception as e:
            logger.error(f"Error analyzing token {token_address}: {e}")
            return {}

    async def _check_trading_criteria(self, target: ManualTokenTarget, analysis: Dict[str, Any]) -> bool:
        """Check if token meets trading criteria."""
        try:
            if not analysis:
                return False

            # Check liquidity
            if analysis.get('liquidity_sol', 0) < target.min_liquidity_sol:
                return False

            # Check confidence
            if analysis.get('confidence_score', 0) < target.confidence_threshold:
                return False

            # Check risk
            if analysis.get('risk_score', 1.0) > 0.8:  # High risk threshold
                return False

            # Additional criteria checks could go here
            return True

        except Exception as e:
            logger.error(f"Error checking trading criteria: {e}")
            return False

    async def _get_trading_recommendation(self, target: ManualTokenTarget, analysis: Dict[str, Any]) -> Dict[str, Any]:
        """Get trading recommendation for a token."""
        try:
            should_trade = await self._check_trading_criteria(target, analysis)

            recommendation = {
                'should_trade': should_trade,
                'reason': '',
                'confidence': analysis.get('confidence_score', 0),
                'risk_level': 'low' if analysis.get('risk_score', 0) < 0.5 else 'high',
                'recommended_amount': min(target.max_buy_amount_sol, analysis.get('liquidity_sol', 0) * 0.1),
                'entry_price': analysis.get('price', 0),
                'stop_loss': analysis.get('price', 0) * (1 - target.stop_loss_percentage),
                'take_profit': analysis.get('price', 0) * (1 + target.take_profit_percentage)
            }

            if should_trade:
                recommendation['reason'] = "Token meets all trading criteria"
            else:
                reasons = []
                if analysis.get('liquidity_sol', 0) < target.min_liquidity_sol:
                    reasons.append("Insufficient liquidity")
                if analysis.get('confidence_score', 0) < target.confidence_threshold:
                    reasons.append("Low confidence score")
                if analysis.get('risk_score', 0) > 0.8:
                    reasons.append("High risk score")

                recommendation['reason'] = "; ".join(reasons) if reasons else "Criteria not met"

            return recommendation

        except Exception as e:
            logger.error(f"Error getting trading recommendation: {e}")
            return {'should_trade': False, 'reason': 'Analysis error'}

    async def _execute_trade_with_controller(self,
                                           token_address: str,
                                           action: str,
                                           amount_sol: float,
                                           target: ManualTokenTarget) -> Dict[str, Any]:
        """
        Execute trade through the trading controller.
        This would integrate with your existing TradingController.
        """
        try:
            # This is where you would integrate with your existing trading system
            # For demonstration, simulate trade execution

            logger.info(f"Executing {action} trade for {token_address}: {amount_sol} SOL")

            # Simulate execution
            await asyncio.sleep(0.5)

            # Simulate result
            success = time.time() % 10 < 8  # 80% success rate

            if success:
                return {
                    'success': True,
                    'trade_id': str(uuid.uuid4()),
                    'token_address': token_address,
                    'action': action,
                    'amount_sol': amount_sol,
                    'executed_at': datetime.utcnow().isoformat(),
                    'tx_signature': f"sim_tx_{str(uuid.uuid4())[:8]}",
                    'pnl': (time.time() % 100) / 1000 if action == 'sell' else 0
                }
            else:
                return {
                    'success': False,
                    'error': 'Simulated execution failure'
                }

        except Exception as e:
            logger.error(f"Error executing trade: {e}")
            return {'success': False, 'error': str(e)}

    async def _cleanup_expired_tokens(self):
        """Remove expired tokens from watchlist."""
        try:
            now = datetime.utcnow()
            expired_tokens = []

            for token_address, target in self.watchlist.items():
                if target.expires_at and now > target.expires_at:
                    expired_tokens.append(token_address)

            for token_address in expired_tokens:
                await self.remove_token_target(token_address, "expired")

            if expired_tokens:
                logger.info(f"Cleaned up {len(expired_tokens)} expired tokens")

        except Exception as e:
            logger.error(f"Error cleaning up expired tokens: {e}")

    async def _cleanup_old_tokens(self):
        """Remove old tokens when watchlist is full."""
        try:
            # Sort by priority and age, remove oldest low priority tokens
            sorted_tokens = sorted(
                self.watchlist.items(),
                key=lambda x: (x[1].priority.value, x[1].added_at)
            )

            # Remove oldest 10% of tokens
            to_remove = max(1, len(sorted_tokens) // 10)

            for i in range(to_remove):
                token_address, target = sorted_tokens[i]
                await self.remove_token_target(token_address, "watchlist_full")

            logger.info(f"Removed {to_remove} old tokens due to watchlist size limit")

        except Exception as e:
            logger.error(f"Error cleaning up old tokens: {e}")

    def _get_status_distribution(self) -> Dict[str, int]:
        """Get distribution of token statuses."""
        distribution = {}
        for status in TokenStatus:
            distribution[status.value] = 0

        for target in self.watchlist.values():
            distribution[target.status.value] += 1

        return distribution

    def _get_priority_distribution(self) -> Dict[str, int]:
        """Get distribution of token priorities."""
        distribution = {}
        for priority in TokenPriority:
            distribution[priority.value] = 0

        for target in self.watchlist.values():
            distribution[target.priority.value] += 1

        return distribution

    async def shutdown(self):
        """Shutdown the service."""
        try:
            # Cancel background tasks
            if self.analysis_task and not self.analysis_task.done():
                self.analysis_task.cancel()

            if self.cleanup_task and not self.cleanup_task.done():
                self.cleanup_task.cancel()

            logger.info("Manual Targeting Service shutdown complete")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")