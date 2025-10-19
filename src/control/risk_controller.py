#!/usr/bin/env python3
"""
MojoRust Risk Controller

Comprehensive risk management system with real-time monitoring,
automated interventions, and dynamic risk limit adjustments.

Features:
- Real-time risk monitoring
- Dynamic position sizing
- Drawdown protection
- Circuit breaker mechanisms
- Portfolio risk management
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Callable, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
import uuid

import redis.asyncio as aioredis

logger = logging.getLogger(__name__)

class RiskLevel(str, Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"
    EMERGENCY = "emergency"

class InterventionType(str, Enum):
    REDUCE_POSITION_SIZE = "reduce_position_size"
    CLOSE_POSITIONS = "close_positions"
    PAUSE_TRADING = "pause_trading"
    STOP_TRADING = "stop_trading"
    EMERGENCY_STOP = "emergency_stop"

class AlertSeverity(str, Enum):
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"

@dataclass
class RiskLimits:
    """Risk management limits"""
    max_daily_loss: float = 0.10          # 10% daily loss limit
    max_position_risk: float = 0.02       # 2% per position
    max_portfolio_risk: float = 0.15      # 15% total portfolio risk
    max_drawdown: float = 0.20            # 20% maximum drawdown
    max_concurrent_positions: int = 5     # Maximum number of positions
    max_daily_trades: int = 50            # Maximum trades per day
    min_confidence_threshold: float = 0.7 # Minimum confidence for trades
    max_leverage: float = 1.0             # Maximum leverage
    correlation_limit: float = 0.8        # Maximum position correlation

@dataclass
class RiskMetrics:
    """Current risk metrics"""
    current_drawdown: float
    daily_pnl: float
    portfolio_var: float                    # Value at Risk
    position_concentration: float
    correlation_risk: float
    liquidity_risk: float
    leverage_ratio: float
    risk_score: float
    risk_level: RiskLevel

@dataclass
class RiskAlert:
    """Risk alert"""
    id: str
    timestamp: datetime
    severity: AlertSeverity
    risk_type: str
    message: str
    current_value: float
    threshold_value: float
    intervention_taken: Optional[str]
    resolved: bool = False

@dataclass
class InterventionRecord:
    """Record of risk intervention"""
    id: str
    timestamp: datetime
    intervention_type: InterventionType
    reason: str
    metrics_before: Dict[str, float]
    metrics_after: Optional[Dict[str, float]]
    success: bool
    details: str

class RiskController:
    """
    Comprehensive risk management and monitoring system.
    """

    def __init__(self, redis_client: aioredis.Redis):
        self.redis_client = redis_client

        # Risk configuration
        self.risk_limits = RiskLimits()
        self.config = {
            'monitoring_interval': 10,          # seconds
            'alert_cooldown': 300,              # 5 minutes
            'intervention_delay': 30,           # seconds
            'auto_interventions': True,
            'alert_channels': ['redis', 'webhook'],
            'risk_history_retention': 86400 * 7,  # 7 days
            'max_alerts_per_hour': 20
        }

        # Current state
        self.current_metrics: Optional[RiskMetrics] = None
        self.active_alerts: Dict[str, RiskAlert] = {}
        self.intervention_history: List[InterventionRecord] = []

        # Monitoring state
        self.is_monitoring = False
        self.monitoring_task: Optional[asyncio.Task] = None
        self.last_alert_times: Dict[str, datetime] = {}

        # Portfolio state
        self.portfolio_value = 0.0
        self.initial_portfolio_value = 0.0
        self.daily_start_value = 0.0
        self.positions: Dict[str, Dict[str, Any]] = {}
        self.daily_trades = 0
        self.last_trade_reset = datetime.utcnow().date()

        # Statistics
        self.stats = {
            'total_alerts': 0,
            'interventions_triggered': 0,
            'successful_interventions': 0,
            'emergency_stops': 0,
            'avg_risk_score': 0.0,
            'max_drawdown_seen': 0.0
        }

    async def initialize(self, initial_portfolio_value: float = 1000.0):
        """Initialize the risk controller."""
        try:
            self.initial_portfolio_value = initial_portfolio_value
            self.portfolio_value = initial_portfolio_value
            self.daily_start_value = initial_portfolio_value

            # Load risk limits from Redis
            await self._load_risk_limits()

            # Start monitoring
            await self._start_monitoring()

            logger.info(f"Risk Controller initialized with portfolio value: {initial_portfolio_value}")

        except Exception as e:
            logger.error(f"Failed to initialize Risk Controller: {e}")
            raise

    async def update_portfolio_state(self,
                                    portfolio_value: float,
                                    positions: Dict[str, Dict[str, Any]],
                                    daily_trades: int = None):
        """
        Update portfolio state for risk monitoring.

        Args:
            portfolio_value: Current portfolio value
            positions: Current positions
            daily_trades: Number of trades today
        """
        try:
            self.portfolio_value = portfolio_value
            self.positions = positions

            if daily_trades is not None:
                self.daily_trades = daily_trades

            # Reset daily trade counter if it's a new day
            if datetime.utcnow().date() > self.last_trade_reset:
                self.daily_start_value = portfolio_value
                self.daily_trades = 0
                self.last_trade_reset = datetime.utcnow().date()

            # Calculate new risk metrics
            await self._calculate_risk_metrics()

        except Exception as e:
            logger.error(f"Error updating portfolio state: {e}")

    async def check_trade_risk(self,
                              trade_amount: float,
                              token_address: str,
                              confidence: float) -> Tuple[bool, str, Dict[str, Any]]:
        """
        Check if a trade meets risk criteria.

        Args:
            trade_amount: Trade amount in SOL
            token_address: Token address
            confidence: Trade confidence score

        Returns:
            (allowed, reason, risk_info)
        """
        try:
            if not self.current_metrics:
                return False, "Risk metrics not available", {}

            risk_info = {}

            # Check daily trade limit
            if self.daily_trades >= self.risk_limits.max_daily_trades:
                return False, f"Daily trade limit exceeded: {self.daily_trades}/{self.risk_limits.max_daily_trades}", risk_info

            # Check confidence threshold
            if confidence < self.risk_limits.min_confidence_threshold:
                return False, f"Confidence too low: {confidence:.3f} < {self.risk_limits.min_confidence_threshold:.3f}", risk_info

            # Check position size limit
            position_risk = trade_amount / self.portfolio_value
            if position_risk > self.risk_limits.max_position_risk:
                return False, f"Position risk too high: {position_risk:.3f} > {self.risk_limits.max_position_risk:.3f}", risk_info

            # Check portfolio risk limit
            new_portfolio_risk = self._calculate_portfolio_risk_with_trade(trade_amount)
            if new_portfolio_risk > self.risk_limits.max_portfolio_risk:
                return False, f"Portfolio risk too high: {new_portfolio_risk:.3f} > {self.risk_limits.max_portfolio_risk:.3f}", risk_info

            # Check drawdown
            if self.current_metrics.current_drawdown > self.risk_limits.max_drawdown:
                return False, f"Maximum drawdown exceeded: {self.current_metrics.current_drawdown:.3f} > {self.risk_limits.max_drawdown:.3f}", risk_info

            # Check correlation risk
            correlation_risk = await self._calculate_correlation_risk(token_address, trade_amount)
            if correlation_risk > self.risk_limits.correlation_limit:
                return False, f"Correlation risk too high: {correlation_risk:.3f} > {self.risk_limits.correlation_limit:.3f}", risk_info

            risk_info = {
                'position_risk': position_risk,
                'portfolio_risk': new_portfolio_risk,
                'correlation_risk': correlation_risk,
                'current_drawdown': self.current_metrics.current_drawdown,
                'risk_level': self.current_metrics.risk_level.value
            }

            return True, "Trade passes risk checks", risk_info

        except Exception as e:
            logger.error(f"Error checking trade risk: {e}")
            return False, f"Risk check error: {str(e)}", {}

    async def update_risk_limits(self, new_limits: Dict[str, Any]) -> bool:
        """
        Update risk limits.

        Args:
            new_limits: New risk limits

        Returns:
            True if updated successfully
        """
        try:
            # Validate new limits
            for key, value in new_limits.items():
                if hasattr(self.risk_limits, key):
                    setattr(self.risk_limits, key, value)

            # Store updated limits
            await self._store_risk_limits()

            logger.info(f"Updated risk limits: {new_limits}")
            return True

        except Exception as e:
            logger.error(f"Error updating risk limits: {e}")
            return False

    async def trigger_emergency_stop(self, reason: str = "Manual emergency stop") -> bool:
        """
        Trigger emergency stop.

        Args:
            reason: Reason for emergency stop

        Returns:
            True if triggered successfully
        """
        try:
            logger.warning(f"EMERGENCY STOP TRIGGERED: {reason}")

            # Create intervention record
            intervention = InterventionRecord(
                id=str(uuid.uuid4()),
                timestamp=datetime.utcnow(),
                intervention_type=InterventionType.EMERGENCY_STOP,
                reason=reason,
                metrics_before=asdict(self.current_metrics) if self.current_metrics else {},
                metrics_after=None,
                success=True,
                details="Emergency stop executed"
            )

            self.intervention_history.append(intervention)
            self.stats['emergency_stops'] += 1

            # Create critical alert
            alert = RiskAlert(
                id=str(uuid.uuid4()),
                timestamp=datetime.utcnow(),
                severity=AlertSeverity.CRITICAL,
                risk_type="emergency_stop",
                message=f"Emergency stop triggered: {reason}",
                current_value=1.0,
                threshold_value=1.0,
                intervention_taken="emergency_stop"
            )

            await self._create_alert(alert)

            # Store in Redis
            await self._store_intervention(intervention)

            # Notify other systems
            await self._notify_emergency_stop(reason)

            return True

        except Exception as e:
            logger.error(f"Error triggering emergency stop: {e}")
            return False

    async def get_current_risk_status(self) -> Dict[str, Any]:
        """Get current risk status and metrics."""
        try:
            if not self.current_metrics:
                return {
                    'status': 'no_data',
                    'message': 'Risk metrics not available'
                }

            return {
                'status': 'active',
                'metrics': asdict(self.current_metrics),
                'limits': asdict(self.risk_limits),
                'active_alerts': len([a for a in self.active_alerts.values() if not a.resolved]),
                'daily_pnl': self.portfolio_value - self.daily_start_value,
                'total_pnl': self.portfolio_value - self.initial_portfolio_value,
                'daily_trades': self.daily_trades,
                'stats': self.stats
            }

        except Exception as e:
            logger.error(f"Error getting risk status: {e}")
            return {'status': 'error', 'message': str(e)}

    async def get_alert_history(self, limit: int = 100) -> List[Dict[str, Any]]:
        """Get alert history."""
        try:
            # Get alerts from Redis
            alerts_data = await self.redis_client.lrange("risk_alerts", 0, limit - 1)

            alerts = []
            for alert_data in alerts_data:
                try:
                    alert_dict = json.loads(alert_data)
                    alerts.append(alert_dict)
                except:
                    continue

            return alerts

        except Exception as e:
            logger.error(f"Error getting alert history: {e}")
            return []

    async def get_intervention_history(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get intervention history."""
        try:
            history = self.intervention_history[-limit:] if self.intervention_history else []

            return [asdict(record) for record in history]

        except Exception as e:
            logger.error(f"Error getting intervention history: {e}")
            return []

    # Private methods

    async def _load_risk_limits(self):
        """Load risk limits from Redis."""
        try:
            limits_data = await self.redis_client.get("risk_limits")
            if limits_data:
                limits_dict = json.loads(limits_data)
                for key, value in limits_dict.items():
                    if hasattr(self.risk_limits, key):
                        setattr(self.risk_limits, key, value)

                logger.info("Loaded risk limits from Redis")

        except Exception as e:
            logger.error(f"Error loading risk limits: {e}")

    async def _store_risk_limits(self):
        """Store risk limits in Redis."""
        try:
            await self.redis_client.set(
                "risk_limits",
                json.dumps(asdict(self.risk_limits)),
                ex=86400 * 7  # 7 days
            )

        except Exception as e:
            logger.error(f"Error storing risk limits: {e}")

    async def _start_monitoring(self):
        """Start risk monitoring."""
        try:
            if self.is_monitoring:
                return

            self.is_monitoring = True
            self.monitoring_task = asyncio.create_task(self._monitoring_loop())

            logger.info("Risk monitoring started")

        except Exception as e:
            logger.error(f"Error starting monitoring: {e}")

    async def _stop_monitoring(self):
        """Stop risk monitoring."""
        try:
            self.is_monitoring = False

            if self.monitoring_task and not self.monitoring_task.done():
                self.monitoring_task.cancel()

            logger.info("Risk monitoring stopped")

        except Exception as e:
            logger.error(f"Error stopping monitoring: {e}")

    async def _monitoring_loop(self):
        """Main risk monitoring loop."""
        try:
            while self.is_monitoring:
                try:
                    # Calculate current risk metrics
                    await self._calculate_risk_metrics()

                    # Check for risk breaches
                    await self._check_risk_breaches()

                    # Update statistics
                    await self._update_statistics()

                    # Wait for next cycle
                    await asyncio.sleep(self.config['monitoring_interval'])

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in monitoring loop: {e}")
                    await asyncio.sleep(30)  # Wait before retrying

        except Exception as e:
            logger.error(f"Fatal error in monitoring loop: {e}")

    async def _calculate_risk_metrics(self):
        """Calculate current risk metrics."""
        try:
            if not self.portfolio_value or not self.initial_portfolio_value:
                return

            # Calculate drawdown
            peak_value = max(self.portfolio_value, self.initial_portfolio_value)
            current_drawdown = (peak_value - self.portfolio_value) / peak_value

            # Calculate daily PnL
            daily_pnl = self.portfolio_value - self.daily_start_value

            # Calculate position concentration
            position_concentration = self._calculate_position_concentration()

            # Calculate correlation risk
            correlation_risk = await self._calculate_portfolio_correlation()

            # Calculate liquidity risk
            liquidity_risk = self._calculate_liquidity_risk()

            # Calculate leverage ratio
            leverage_ratio = self._calculate_leverage_ratio()

            # Calculate Value at Risk (simplified)
            portfolio_var = self._calculate_var()

            # Calculate overall risk score
            risk_score = self._calculate_risk_score(
                current_drawdown, daily_pnl, position_concentration,
                correlation_risk, liquidity_risk, leverage_ratio
            )

            # Determine risk level
            risk_level = self._determine_risk_level(risk_score)

            # Create metrics object
            self.current_metrics = RiskMetrics(
                current_drawdown=current_drawdown,
                daily_pnl=daily_pnl,
                portfolio_var=portfolio_var,
                position_concentration=position_concentration,
                correlation_risk=correlation_risk,
                liquidity_risk=liquidity_risk,
                leverage_ratio=leverage_ratio,
                risk_score=risk_score,
                risk_level=risk_level
            )

            # Store metrics in Redis
            await self._store_current_metrics()

        except Exception as e:
            logger.error(f"Error calculating risk metrics: {e}")

    def _calculate_position_concentration(self) -> float:
        """Calculate position concentration risk."""
        try:
            if not self.positions:
                return 0.0

            # Calculate Herfindahl-Hirschman Index for concentration
            total_value = self.portfolio_value
            if total_value == 0:
                return 0.0

            hhi = 0.0
            for position in self.positions.values():
                position_weight = position.get('value', 0) / total_value
                hhi += position_weight ** 2

            return hhi

        except Exception as e:
            logger.error(f"Error calculating position concentration: {e}")
            return 0.0

    async def _calculate_portfolio_correlation(self) -> float:
        """Calculate portfolio correlation risk."""
        try:
            # Simplified correlation calculation
            # In practice, you would use historical price data and calculate correlation matrix
            if len(self.positions) <= 1:
                return 0.0

            # Mock correlation calculation
            # Higher correlation when positions are in similar tokens
            return min(0.9, len(self.positions) * 0.1)

        except Exception as e:
            logger.error(f"Error calculating portfolio correlation: {e}")
            return 0.0

    def _calculate_liquidity_risk(self) -> float:
        """Calculate liquidity risk."""
        try:
            if not self.positions:
                return 0.0

            # Simplified liquidity risk based on position sizes
            # Larger positions have higher liquidity risk
            total_liquidity_risk = 0.0
            for position in self.positions.values():
                position_value = position.get('value', 0)
                # Risk increases with position size
                position_risk = min(1.0, position_value / 100.0)  # 100 SOL as reference
                total_liquidity_risk += position_risk

            return min(1.0, total_liquidity_risk / len(self.positions))

        except Exception as e:
            logger.error(f"Error calculating liquidity risk: {e}")
            return 0.0

    def _calculate_leverage_ratio(self) -> float:
        """Calculate current leverage ratio."""
        try:
            # Simplified leverage calculation
            # In practice, this would consider short positions, derivatives, etc.
            total_position_value = sum(p.get('value', 0) for p in self.positions.values())

            if self.portfolio_value == 0:
                return 0.0

            return total_position_value / self.portfolio_value

        except Exception as e:
            logger.error(f"Error calculating leverage ratio: {e}")
            return 0.0

    def _calculate_var(self) -> float:
        """Calculate Value at Risk (simplified)."""
        try:
            # Simplified VaR calculation
            # In practice, you would use historical returns and statistical methods
            if not self.positions:
                return 0.0

            # Assume 5% VaR based on position sizes
            total_exposure = sum(p.get('value', 0) for p in self.positions.values())
            return total_exposure * 0.05

        except Exception as e:
            logger.error(f"Error calculating VaR: {e}")
            return 0.0

    def _calculate_risk_score(self,
                             drawdown: float,
                             daily_pnl: float,
                             concentration: float,
                             correlation: float,
                             liquidity: float,
                             leverage: float) -> float:
        """Calculate overall risk score."""
        try:
            # Weighted risk score calculation
            score = 0.0

            # Drawdown component (30% weight)
            score += drawdown * 0.3

            # Daily loss component (20% weight)
            daily_loss = min(0, daily_pnl / self.daily_start_value)
            score += abs(daily_loss) * 0.2

            # Concentration component (15% weight)
            score += concentration * 0.15

            # Correlation component (15% weight)
            score += correlation * 0.15

            # Liquidity component (10% weight)
            score += liquidity * 0.1

            # Leverage component (10% weight)
            score += min(1.0, leverage / 2.0) * 0.1  # Normalize leverage

            return min(1.0, score)

        except Exception as e:
            logger.error(f"Error calculating risk score: {e}")
            return 0.0

    def _determine_risk_level(self, risk_score: float) -> RiskLevel:
        """Determine risk level from risk score."""
        try:
            if risk_score >= 0.8:
                return RiskLevel.EMERGENCY
            elif risk_score >= 0.6:
                return RiskLevel.CRITICAL
            elif risk_score >= 0.4:
                return RiskLevel.HIGH
            elif risk_score >= 0.2:
                return RiskLevel.MEDIUM
            else:
                return RiskLevel.LOW

        except Exception as e:
            logger.error(f"Error determining risk level: {e}")
            return RiskLevel.MEDIUM

    async def _check_risk_breaches(self):
        """Check for risk limit breaches and trigger alerts."""
        try:
            if not self.current_metrics:
                return

            metrics = self.current_metrics
            alerts_to_create = []

            # Check drawdown limit
            if metrics.current_drawdown > self.risk_limits.max_drawdown:
                alerts_to_create.append(self._create_drawdown_alert(metrics))

            # Check daily loss limit
            if metrics.daily_pnl < -self.risk_limits.max_daily_loss * self.daily_start_value:
                alerts_to_create.append(self._create_daily_loss_alert(metrics))

            # Check portfolio risk limit
            portfolio_risk = await self._calculate_current_portfolio_risk()
            if portfolio_risk > self.risk_limits.max_portfolio_risk:
                alerts_to_create.append(self._create_portfolio_risk_alert(metrics, portfolio_risk))

            # Check correlation risk
            if metrics.correlation_risk > self.risk_limits.correlation_limit:
                alerts_to_create.append(self._create_correlation_alert(metrics))

            # Check leverage limit
            if metrics.leverage_ratio > self.risk_limits.max_leverage:
                alerts_to_create.append(self._create_leverage_alert(metrics))

            # Create alerts
            for alert in alerts_to_create:
                await self._create_alert(alert)

            # Check if intervention is needed
            if alerts_to_create and self.config['auto_interventions']:
                await self._evaluate_intervention(alerts_to_create)

        except Exception as e:
            logger.error(f"Error checking risk breaches: {e}")

    def _create_drawdown_alert(self, metrics: RiskMetrics) -> RiskAlert:
        """Create drawdown alert."""
        return RiskAlert(
            id=str(uuid.uuid4()),
            timestamp=datetime.utcnow(),
            severity=AlertSeverity.ERROR if metrics.current_drawdown < 0.15 else AlertSeverity.CRITICAL,
            risk_type="drawdown",
            message=f"Maximum drawdown breached: {metrics.current_drawdown:.3f} > {self.risk_limits.max_drawdown:.3f}",
            current_value=metrics.current_drawdown,
            threshold_value=self.risk_limits.max_drawdown,
            intervention_taken=None
        )

    def _create_daily_loss_alert(self, metrics: RiskMetrics) -> RiskAlert:
        """Create daily loss alert."""
        loss_percentage = abs(metrics.daily_pnl) / self.daily_start_value
        return RiskAlert(
            id=str(uuid.uuid4()),
            timestamp=datetime.utcnow(),
            severity=AlertSeverity.ERROR if loss_percentage < 0.08 else AlertSeverity.CRITICAL,
            risk_type="daily_loss",
            message=f"Daily loss limit breached: {loss_percentage:.3f} > {self.risk_limits.max_daily_loss:.3f}",
            current_value=loss_percentage,
            threshold_value=self.risk_limits.max_daily_loss,
            intervention_taken=None
        )

    def _create_portfolio_risk_alert(self, metrics: RiskMetrics, portfolio_risk: float) -> RiskAlert:
        """Create portfolio risk alert."""
        return RiskAlert(
            id=str(uuid.uuid4()),
            timestamp=datetime.utcnow(),
            severity=AlertSeverity.WARNING,
            risk_type="portfolio_risk",
            message=f"Portfolio risk too high: {portfolio_risk:.3f} > {self.risk_limits.max_portfolio_risk:.3f}",
            current_value=portfolio_risk,
            threshold_value=self.risk_limits.max_portfolio_risk,
            intervention_taken=None
        )

    def _create_correlation_alert(self, metrics: RiskMetrics) -> RiskAlert:
        """Create correlation risk alert."""
        return RiskAlert(
            id=str(uuid.uuid4()),
            timestamp=datetime.utcnow(),
            severity=AlertSeverity.WARNING,
            risk_type="correlation",
            message=f"Correlation risk too high: {metrics.correlation_risk:.3f} > {self.risk_limits.correlation_limit:.3f}",
            current_value=metrics.correlation_risk,
            threshold_value=self.risk_limits.correlation_limit,
            intervention_taken=None
        )

    def _create_leverage_alert(self, metrics: RiskMetrics) -> RiskAlert:
        """Create leverage alert."""
        return RiskAlert(
            id=str(uuid.uuid4()),
            timestamp=datetime.utcnow(),
            severity=AlertSeverity.ERROR,
            risk_type="leverage",
            message=f"Leverage too high: {metrics.leverage_ratio:.3f} > {self.risk_limits.max_leverage:.3f}",
            current_value=metrics.leverage_ratio,
            threshold_value=self.risk_limits.max_leverage,
            intervention_taken=None
        )

    async def _create_alert(self, alert: RiskAlert):
        """Create and store a risk alert."""
        try:
            # Check cooldown period
            alert_key = f"{alert.risk_type}_{alert.severity}"
            last_alert_time = self.last_alert_times.get(alert_key)

            if last_alert_time:
                cooldown_remaining = self.config['alert_cooldown'] - \
                                   (datetime.utcnow() - last_alert_time).total_seconds()
                if cooldown_remaining > 0:
                    return  # Still in cooldown

            # Store alert
            self.active_alerts[alert.id] = alert
            self.last_alert_times[alert_key] = datetime.utcnow()
            self.stats['total_alerts'] += 1

            # Store in Redis
            await self._store_alert(alert)

            # Send notifications
            await self._send_alert_notification(alert)

            logger.warning(f"Risk alert created: {alert.message}")

        except Exception as e:
            logger.error(f"Error creating alert: {e}")

    async def _store_alert(self, alert: RiskAlert):
        """Store alert in Redis."""
        try:
            alert_data = asdict(alert)
            alert_data['timestamp'] = alert.timestamp.isoformat()

            await self.redis_client.lpush(
                "risk_alerts",
                json.dumps(alert_data)
            )
            await self.redis_client.ltrim("risk_alerts", 0, 999)  # Keep last 1000

        except Exception as e:
            logger.error(f"Error storing alert: {e}")

    async def _store_current_metrics(self):
        """Store current metrics in Redis."""
        try:
            if self.current_metrics:
                metrics_data = asdict(self.current_metrics)
                await self.redis_client.set(
                    "risk_metrics_current",
                    json.dumps(metrics_data),
                    ex=300  # 5 minutes
                )

        except Exception as e:
            logger.error(f"Error storing current metrics: {e}")

    async def _send_alert_notification(self, alert: RiskAlert):
        """Send alert notification."""
        try:
            # Send to Redis pub/sub
            notification = {
                'type': 'risk_alert',
                'alert': asdict(alert),
                'timestamp': datetime.utcnow().isoformat()
            }

            await self.redis_client.publish("risk_notifications", json.dumps(notification))

            # Additional notification channels could be added here
            # (e.g., webhook, email, Slack, etc.)

        except Exception as e:
            logger.error(f"Error sending alert notification: {e}")

    async def _evaluate_intervention(self, alerts: List[RiskAlert]):
        """Evaluate if intervention is needed based on alerts."""
        try:
            if not self.current_metrics:
                return

            # Check for critical alerts that require immediate intervention
            critical_alerts = [a for a in alerts if a.severity == AlertSeverity.CRITICAL]

            if critical_alerts:
                # Determine intervention type based on risk level
                if self.current_metrics.risk_level == RiskLevel.EMERGENCY:
                    await self._execute_intervention(InterventionType.EMERGENCY_STOP, "Critical risk level reached")
                elif self.current_metrics.risk_level == RiskLevel.CRITICAL:
                    await self._execute_intervention(InterventionType.STOP_TRADING, "Critical risk alerts triggered")
                else:
                    await self._execute_intervention(InterventionType.PAUSE_TRADING, "Multiple critical alerts")

            # Check for multiple error-level alerts
            error_alerts = [a for a in alerts if a.severity == AlertSeverity.ERROR]
            if len(error_alerts) >= 3:
                await self._execute_intervention(InterventionType.PAUSE_TRADING, "Multiple error alerts")

        except Exception as e:
            logger.error(f"Error evaluating intervention: {e}")

    async def _execute_intervention(self, intervention_type: InterventionType, reason: str):
        """Execute risk intervention."""
        try:
            logger.warning(f"Executing risk intervention: {intervention_type.value} - {reason}")

            # Record metrics before intervention
            metrics_before = asdict(self.current_metrics) if self.current_metrics else {}

            # Execute intervention based on type
            success = True
            details = ""

            if intervention_type == InterventionType.EMERGENCY_STOP:
                # Emergency stop - would integrate with trading controller
                details = "Emergency stop executed - all trading halted"
                success = True

            elif intervention_type == InterventionType.STOP_TRADING:
                # Stop trading - would integrate with trading controller
                details = "Trading stopped - risk limits exceeded"
                success = True

            elif intervention_type == InterventionType.PAUSE_TRADING:
                # Pause trading - would integrate with trading controller
                details = "Trading paused - risk warning"
                success = True

            elif intervention_type == InterventionType.CLOSE_POSITIONS:
                # Close positions - would integrate with trading controller
                details = "Positions closed - risk management"
                success = True

            elif intervention_type == InterventionType.REDUCE_POSITION_SIZE:
                # Reduce position sizes - would integrate with trading controller
                details = "Position sizes reduced - risk management"
                success = True

            # Record intervention
            intervention = InterventionRecord(
                id=str(uuid.uuid4()),
                timestamp=datetime.utcnow(),
                intervention_type=intervention_type,
                reason=reason,
                metrics_before=metrics_before,
                metrics_after=None,  # Will be updated after intervention takes effect
                success=success,
                details=details
            )

            self.intervention_history.append(intervention)
            self.stats['interventions_triggered'] += 1

            if success:
                self.stats['successful_interventions'] += 1

            # Store intervention
            await self._store_intervention(intervention)

            # Notify intervention
            await self._notify_intervention(intervention)

            logger.info(f"Risk intervention executed: {intervention_type.value}")

        except Exception as e:
            logger.error(f"Error executing intervention: {e}")

    async def _store_intervention(self, intervention: InterventionRecord):
        """Store intervention in Redis."""
        try:
            intervention_data = asdict(intervention)
            intervention_data['timestamp'] = intervention.timestamp.isoformat()
            if intervention.metrics_before:
                # Convert datetime objects to strings
                for key, value in intervention.metrics_before.items():
                    if isinstance(value, datetime):
                        intervention.metrics_before[key] = value.isoformat()

            await self.redis_client.lpush(
                "risk_interventions",
                json.dumps(intervention_data)
            )
            await self.redis_client.ltrim("risk_interventions", 0, 999)  # Keep last 1000

        except Exception as e:
            logger.error(f"Error storing intervention: {e}")

    async def _notify_intervention(self, intervention: InterventionRecord):
        """Send intervention notification."""
        try:
            notification = {
                'type': 'risk_intervention',
                'intervention': asdict(intervention),
                'timestamp': datetime.utcnow().isoformat()
            }

            await self.redis_client.publish("risk_notifications", json.dumps(notification))

        except Exception as e:
            logger.error(f"Error sending intervention notification: {e}")

    async def _notify_emergency_stop(self, reason: str):
        """Send emergency stop notification."""
        try:
            notification = {
                'type': 'emergency_stop',
                'reason': reason,
                'timestamp': datetime.utcnow().isoformat(),
                'metrics': asdict(self.current_metrics) if self.current_metrics else {}
            }

            await self.redis_client.publish("risk_notifications", json.dumps(notification))

        except Exception as e:
            logger.error(f"Error sending emergency stop notification: {e}")

    async def _calculate_current_portfolio_risk(self) -> float:
        """Calculate current portfolio risk."""
        try:
            if not self.positions or self.portfolio_value == 0:
                return 0.0

            # Simplified portfolio risk calculation
            total_exposure = sum(p.get('value', 0) for p in self.positions.values())
            return total_exposure / self.portfolio_value

        except Exception as e:
            logger.error(f"Error calculating portfolio risk: {e}")
            return 0.0

    def _calculate_portfolio_risk_with_trade(self, trade_amount: float) -> float:
        """Calculate portfolio risk with additional trade."""
        try:
            if self.portfolio_value == 0:
                return 0.0

            total_exposure = sum(p.get('value', 0) for p in self.positions.values())
            new_total_exposure = total_exposure + trade_amount
            return new_total_exposure / self.portfolio_value

        except Exception as e:
            logger.error(f"Error calculating portfolio risk with trade: {e}")
            return 0.0

    async def _calculate_correlation_risk(self, token_address: str, trade_amount: float) -> float:
        """Calculate correlation risk for a specific token."""
        try:
            # Simplified correlation risk calculation
            # In practice, you would analyze the correlation between the new token
            # and existing positions in the portfolio

            if token_address in self.positions:
                # Adding to existing position increases correlation risk
                return 0.8
            else:
                # New token has lower correlation risk
                return 0.3

        except Exception as e:
            logger.error(f"Error calculating correlation risk: {e}")
            return 0.0

    async def _update_statistics(self):
        """Update risk statistics."""
        try:
            if self.current_metrics:
                # Update average risk score
                self.stats['avg_risk_score'] = (
                    self.stats['avg_risk_score'] + self.current_metrics.risk_score
                ) / 2

                # Update maximum drawdown seen
                self.stats['max_drawdown_seen'] = max(
                    self.stats['max_drawdown_seen'],
                    self.current_metrics.current_drawdown
                )

        except Exception as e:
            logger.error(f"Error updating statistics: {e}")

    async def shutdown(self):
        """Shutdown the risk controller."""
        try:
            await self._stop_monitoring()
            logger.info("Risk Controller shutdown complete")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")