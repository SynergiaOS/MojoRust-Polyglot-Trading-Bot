# =============================================================================
# Risk Management Module
# =============================================================================

from time import time
from collections import Dict, List
from math import sqrt
from core.types import (
    TradingSignal, RiskApproval, RiskAnalysis, RiskLevel,
    Portfolio, Position, MarketData, TradingAction
)
from core.constants import (
    MAX_CORRELATION_THRESHOLD,
    MIN_DIVERSIFICATION_SCORE,
    MAX_POSITION_PERCENTAGE,
    CIRCUIT_BREAKER_THRESHOLD,
    MIN_RISK_REWARD_RATIO
)

@value
struct RiskManager:
    """
    Advanced risk management system
    """
    var config  # We'll add the type later
    var portfolio: Portfolio
    var max_daily_trades: Int
    var trades_today: Int
    var last_reset_date: Float

    fn __init__(config):
        self.config = config
        self.portfolio = Portfolio(0.0, 0.0)
        self.max_daily_trades = config.trading.daily_trade_limit
        self.trades_today = 0
        self.last_reset_date = time()

    def approve_trade(self, signal: TradingSignal) -> RiskApproval:
        """
        Approve or reject a trading signal based on risk criteria
        """
        # Reset daily counter if needed
        self._check_daily_reset()

        # Check circuit breaker
        if self._check_circuit_breaker():
            return RiskApproval(
                approved=False,
                reason="Circuit breaker triggered - maximum drawdown exceeded"
            )

        # Check daily trade limit
        if self.trades_today >= self.max_daily_trades:
            return RiskApproval(
                approved=False,
                reason=f"Daily trade limit reached ({self.max_daily_trades})"
            )

        # Check basic signal validity
        risk_analysis = self._analyze_signal_risk(signal)
        if risk_analysis.risk_level == RiskLevel.CRITICAL:
            return RiskApproval(
                approved=False,
                reason=f"Critical risk level: {', '.join(risk_analysis.risk_factors)}"
            )

        # Check portfolio correlation
        if self._check_correlation(signal):
            return RiskApproval(
                approved=False,
                reason="High correlation with existing positions"
            )

        # Check position sizing
        max_size = self._calculate_max_position_size(signal, risk_analysis)
        if max_size <= 0:
            return RiskApproval(
                approved=False,
                reason="Insufficient risk-adjusted position size"
            )

        # Check liquidity and volume
        if not self._check_liquidity_risk(signal):
            return RiskApproval(
                approved=False,
                reason="Insufficient liquidity or volume"
            )

        # Calculate risk-reward ratio
        risk_reward_ratio = self._calculate_risk_reward_ratio(signal)
        if risk_reward_ratio < MIN_RISK_REWARD_RATIO:
            return RiskApproval(
                approved=False,
                reason=f"Insufficient risk-reward ratio ({risk_reward_ratio:.2f})"
            )

        # Approve trade with calculated position size
        position_size = min(
            max_size,
            self.portfolio.total_value * self.config.trading.max_position_size
        )

        return RiskApproval(
            approved=True,
            reason="Risk assessment passed",
            position_size=position_size,
            stop_loss_price=signal.stop_loss,
            max_position_size=max_size,
            expected_risk_reward_ratio=risk_reward_ratio
        )

    fn _analyze_signal_risk(self, signal: TradingSignal) -> RiskAnalysis:
        """
        Analyze risk factors for a trading signal
        """
        risk_factors = []
        risk_score = 0.0
        wash_trading_score = 0.0
        liquidity_risk_score = 0.0
        volatility_score = 0.0

        # RSI-based risk
        if signal.rsi_value > 90:
            risk_factors.append("Extremely overbought (RSI > 90)")
            risk_score += 0.3
        elif signal.rsi_value > 80:
            risk_factors.append("Very overbought (RSI > 80)")
            risk_score += 0.2
        elif signal.rsi_value < 10:
            risk_factors.append("Extremely oversold (RSI < 10)")
            risk_score += 0.2
        elif signal.rsi_value < 20:
            risk_factors.append("Very oversold (RSI < 20)")
            risk_score += 0.1

        # Volume-based risk
        if signal.volume < self.config.risk.min_volume:
            risk_factors.append("Low volume")
            risk_score += 0.3
            liquidity_risk_score += 0.2

        # Liquidity-based risk
        if signal.liquidity < self.config.risk.min_liquidity:
            risk_factors.append("Low liquidity")
            risk_score += 0.4
            liquidity_risk_score += 0.3

        # Price movement risk
        if abs(signal.price_change_5m) > 0.2:  # 20% in 5 minutes
            risk_factors.append("Extreme price movement")
            risk_score += 0.3
            volatility_score += 0.3
        elif abs(signal.price_change_5m) > 0.1:  # 10% in 5 minutes
            risk_factors.append("High price movement")
            risk_score += 0.2
            volatility_score += 0.2

        # Confidence-based risk
        if signal.confidence < 0.6:
            risk_factors.append("Low signal confidence")
            risk_score += 0.2

        # Wash trading risk (simplified)
        if signal.volume > 1000000 and signal.liquidity < 10000:
            risk_factors.append("Potential wash trading")
            risk_score += 0.4
            wash_trading_score += 0.8

        # Determine risk level
        risk_level = RiskLevel.LOW
        if risk_score >= 0.7:
            risk_level = RiskLevel.CRITICAL
        elif risk_score >= 0.5:
            risk_level = RiskLevel.HIGH
        elif risk_score >= 0.3:
            risk_level = RiskLevel.MEDIUM

        return RiskAnalysis(
            risk_level=risk_level,
            confidence=max(0.0, 1.0 - risk_score),
            risk_factors=risk_factors,
            wash_trading_score=wash_trading_score,
            liquidity_risk_score=liquidity_risk_score,
            volatility_score=volatility_score
        )

    fn _check_circuit_breaker(self) -> Bool:
        """
        Check if circuit breaker should trigger
        """
        if self.portfolio.peak_value <= 0:
            return False
        current_drawdown = (self.portfolio.peak_value - self.portfolio.total_value) / self.portfolio.peak_value
        return current_drawdown > self.config.trading.max_drawdown

    fn _check_daily_reset(self):
        """
        Reset daily trading counter
        """
        current_date = int(time() / 86400)  # Days since epoch
        last_date = int(self.last_reset_date / 86400)

        if current_date > last_date:
            self.trades_today = 0
            self.last_reset_date = time()

    fn _check_correlation(self, signal: TradingSignal) -> Bool:
        """
        Check if new position would be too correlated with existing ones
        """
        # Simplified correlation check
        # In a real implementation, this would use actual correlation analysis
        return len(self.portfolio.positions) >= self.config.risk.diversification_target

    fn _calculate_max_position_size(self, signal: TradingSignal, risk_analysis: RiskAnalysis) -> Float:
        """
        Calculate maximum position size based on risk factors
        """
        base_size = self.portfolio.total_value * MAX_POSITION_PERCENTAGE

        # Reduce size based on risk factors
        size_multiplier = 1.0

        # Confidence adjustment
        size_multiplier *= signal.confidence

        # Risk level adjustment
        if risk_analysis.risk_level == RiskLevel.HIGH:
            size_multiplier *= 0.5
        elif risk_analysis.risk_level == RiskLevel.MEDIUM:
            size_multiplier *= 0.75

        # Liquidity risk adjustment
        if risk_analysis.liquidity_risk_score > 0.5:
            size_multiplier *= 0.7

        # Volatility adjustment
        if risk_analysis.volatility_score > 0.3:
            size_multiplier *= 0.8

        # Kelly criterion adjustment
        kelly_multiplier = self.config.trading.kelly_fraction
        size_multiplier *= kelly_multiplier

        max_size = base_size * size_multiplier
        return max(0.0, max_size)

    fn _check_liquidity_risk(self, signal: TradingSignal) -> Bool:
        """
        Check if liquidity is sufficient for the trade
        """
        # Check if we can reasonably enter/exit the position
        if signal.liquidity < 5000:  # Minimum $5k liquidity
            return False

        # Check volume consistency
        if signal.volume > signal.liquidity * 20:  # Volume > 20x liquidity
            return False

        return True

    fn _calculate_risk_reward_ratio(self, signal: TradingSignal) -> Float:
        """
        Calculate risk-reward ratio for a signal
        """
        if signal.price_target <= 0 or signal.stop_loss <= 0:
            return 0.0

        # For buy signals
        if signal.action == TradingAction.BUY:
            potential_profit = signal.price_target - signal.stop_loss
            potential_loss = signal.stop_loss
        else:  # Sell signals
            potential_profit = signal.stop_loss - signal.price_target
            potential_loss = signal.price_target

        if potential_loss <= 0:
            return 0.0

        return potential_profit / potential_loss

    def record_trade(self, signal: TradingSignal, approval: RiskApproval, result):
        """
        Record a trade for risk tracking
        """
        if result.success:
            self.trades_today += 1

        # Update portfolio state
        if hasattr(self, 'portfolio'):
            self.portfolio.total_value = self._recalculate_portfolio_value()

    def _recalculate_portfolio_value(self) -> Float:
        """
        Recalculate total portfolio value
        """
        total = self.portfolio.available_cash
        for position in self.portfolio.positions.values():
            total += position.current_price * position.size
        return total

    def get_portfolio_risk_metrics(self) -> Dict[str, Any]:
        """
        Get current portfolio risk metrics
        """
        if self.portfolio.total_value <= 0:
            return {
                "total_risk": 0.0,
                "correlation_risk": 0.0,
                "concentration_risk": 0.0,
                "liquidity_risk": 0.0,
                "overall_risk_level": RiskLevel.LOW
            }

        # Calculate concentration risk
        max_position_value = 0.0
        for position in self.portfolio.positions.values():
            position_value = position.current_price * position.size
            max_position_value = max(max_position_value, position_value)

        concentration_risk = max_position_value / self.portfolio.total_value

        # Calculate correlation risk (simplified)
        correlation_risk = min(1.0, len(self.portfolio.positions) / 10.0)

        # Calculate liquidity risk
        liquidity_risk = 0.0
        if len(self.portfolio.positions) > 0:
            total_liquidity = sum(pos.size * pos.current_price for pos in self.portfolio.positions.values())
            liquidity_risk = 1.0 - min(1.0, total_liquidity / (self.portfolio.total_value * 0.1))

        # Overall risk score
        total_risk = (concentration_risk + correlation_risk + liquidity_risk) / 3.0

        # Determine risk level
        risk_level = RiskLevel.LOW
        if total_risk >= 0.7:
            risk_level = RiskLevel.CRITICAL
        elif total_risk >= 0.5:
            risk_level = RiskLevel.HIGH
        elif total_risk >= 0.3:
            risk_level = RiskLevel.MEDIUM

        return {
            "total_risk": total_risk,
            "correlation_risk": correlation_risk,
            "concentration_risk": concentration_risk,
            "liquidity_risk": liquidity_risk,
            "overall_risk_level": risk_level,
            "position_count": len(self.portfolio.positions),
            "trades_today": self.trades_today,
            "max_daily_trades": self.max_daily_trades
        }

    def should_reduce_risk(self) -> bool:
        """
        Check if we should reduce overall portfolio risk
        """
        risk_metrics = self.get_portfolio_risk_metrics()

        # Reduce risk if overall risk is high
        if risk_metrics["overall_risk_level"] in [RiskLevel.HIGH, RiskLevel.CRITICAL]:
            return True

        # Reduce risk if approaching daily limits
        if self.trades_today >= self.max_daily_trades * 0.8:
            return True

        # Reduce risk if concentration is too high
        if risk_metrics["concentration_risk"] > 0.3:
            return True

        return False

    def get_risk_adjusted_position_size(self, signal: TradingSignal) -> Float:
        """
        Get risk-adjusted position size for a signal
        """
        approval = self.approve_trade(signal)
        if approval.approved:
            return approval.position_size
        return 0.0

    def update_portfolio_state(self, portfolio: Portfolio):
        """
        Update portfolio state for risk calculations
        """
        self.portfolio = portfolio

    def reset_daily_limits(self):
        """
        Reset daily trading limits
        """
        self.trades_today = 0
        self.last_reset_date = time()