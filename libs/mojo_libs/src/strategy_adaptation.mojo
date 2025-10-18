from collections import Dict, List, Any
from monitoring.performance_analytics import TradeRecord
from core.types import MarketData
from core.config import Config
from core.logger import get_logger
from time import time

enum MarketRegime:
    TRENDING_UP
    TRENDING_DOWN
    RANGING
    VOLATILE
    UNKNOWN

struct StrategyAdjustment:
    """
    Strategy parameter adjustments
    """
    var confidence_threshold_delta: Float
    var position_size_multiplier: Float
    var stop_loss_multiplier: Float
    var take_profit_multiplier: Float
    var max_positions_delta: Int
    var reason: String
    var timestamp: Float

    fn __init__(
        confidence_threshold_delta: Float = 0.0,
        position_size_multiplier: Float = 1.0,
        stop_loss_multiplier: Float = 1.0,
        take_profit_multiplier: Float = 1.0,
        max_positions_delta: Int = 0,
        reason: String = "",
        timestamp: Float = 0.0
    ):
        self.confidence_threshold_delta = confidence_threshold_delta
        self.position_size_multiplier = position_size_multiplier
        self.stop_loss_multiplier = stop_loss_multiplier
        self.take_profit_multiplier = take_profit_multiplier
        self.max_positions_delta = max_positions_delta
        self.reason = reason
        self.timestamp = timestamp if timestamp > 0 else time()

struct PerformanceAnalysis:
    """
    Analysis of recent trading performance
    """
    var win_rate: Float
    var profit_factor: Float
    var sharpe_ratio: Float
    var max_drawdown: Float
    var average_win: Float
    var average_loss: Float
    var total_trades: Int
    var period_hours: Int

    fn __init__(
        win_rate: Float = 0.0,
        profit_factor: Float = 0.0,
        sharpe_ratio: Float = 0.0,
        max_drawdown: Float = 0.0,
        average_win: Float = 0.0,
        average_loss: Float = 0.0,
        total_trades: Int = 0,
        period_hours: Int = 0
    ):
        self.win_rate = win_rate
        self.profit_factor = profit_factor
        self.sharpe_ratio = sharpe_ratio
        self.max_drawdown = max_drawdown
        self.average_win = average_win
        self.average_loss = average_loss
        self.total_trades = total_trades
        self.period_hours = period_hours

struct StrategyAdaptation:
    """
    Dynamic strategy parameter adjustment engine
    """

    # Adaptation settings
    var adaptation_enabled: Bool
    var adaptation_interval_hours: Int
    var performance_window_hours: Int
    var min_trades_for_adaptation: Int

    # Timing
    var last_adaptation_time: Float

    # Current adjustments
    var current_adjustments: Dict[String, Float]

    # Configuration
    var config: Config
    var logger: Any

    # Safety counters
    var adaptations_today: Int
    var last_reset_date: Int

    fn __init__(config: Config):
        self.config = config
        self.logger = get_logger("StrategyAdaptation")

        # Initialize settings
        self.adaptation_enabled = self.config.strategy_adaptation.enabled
        self.adaptation_interval_hours = self.config.strategy_adaptation.adaptation_interval_hours
        self.performance_window_hours = self.config.strategy_adaptation.performance_window_hours
        self.min_trades_for_adaptation = self.config.strategy_adaptation.min_trades_for_adaptation

        # Initialize timing
        self.last_adaptation_time = 0.0

        # Initialize current adjustments
        self.current_adjustments = {
            "confidence_threshold": 0.0,
            "position_size_multiplier": 1.0,
            "stop_loss_multiplier": 1.0,
            "take_profit_multiplier": 1.0,
            "max_positions_delta": 0
        }

        # Initialize safety counters
        self.adaptations_today = 0
        self.last_reset_date = 0

        self.logger.info("Strategy adaptation initialized",
                        enabled=self.adaptation_enabled,
                        interval_hours=self.adaptation_interval_hours,
                        performance_window=self.performance_window_hours,
                        min_trades=self.min_trades_for_adaptation)

    fn should_adapt(self) -> Bool:
        """
        Check if it's time to adapt strategy
        """
        if not self.adaptation_enabled:
            return False

        current_time = time()
        hours_since_last = (current_time - self.last_adaptation_time) / 3600.0

        # Check if enough time has passed
        if hours_since_last < self.adaptation_interval_hours:
            return False

        # Check daily adaptation limit
        self._check_daily_reset()
        if self.adaptations_today >= 3:  # Max 3 adaptations per day
            self.logger.warn("Daily adaptation limit reached", adaptations=self.adaptations_today)
            return False

        return True

    fn adapt_strategy(self, trades: List[TradeRecord], market_data: List[MarketData]) -> StrategyAdjustment:
        """
        Main adaptation logic - analyze performance and determine adjustments
        """
        if len(trades) < self.min_trades_for_adaptation:
            self.logger.info("Insufficient trades for adaptation",
                            trades=len(trades),
                            required=self.min_trades_for_adaptation)
            return StrategyAdjustment()  # Return empty adjustment

        # Analyze recent performance
        performance = self.analyze_recent_performance(trades)

        # Detect market regime
        market_regime = self.detect_market_regime(market_data)

        # Calculate optimal adjustments
        adjustment = self.calculate_optimal_adjustments(performance, market_regime)

        # Apply safety limits
        adjustment = self.apply_safety_limits(adjustment)

        if adjustment.reason:  # If there's a reason, adjustment is needed
            self.last_adaptation_time = time()
            self.adaptations_today += 1

            self.logger.info("Strategy adaptation calculated",
                            win_rate=performance.win_rate,
                            profit_factor=performance.profit_factor,
                            market_regime=str(market_regime),
                            adjustment_reason=adjustment.reason)

        return adjustment

    def analyze_recent_performance(self, trades: List[TradeRecord]) -> PerformanceAnalysis:
        """
        Analyze performance of recent trades
        """
        if len(trades) == 0:
            return PerformanceAnalysis()

        # Filter trades within performance window
        current_time = time()
        cutoff_time = current_time - (self.performance_window_hours * 3600.0)
        recent_trades = [trade for trade in trades if trade.exit_timestamp >= cutoff_time]

        if len(recent_trades) == 0:
            return PerformanceAnalysis()

        # Calculate performance metrics
        winning_trades = [trade for trade in recent_trades if trade.was_profitable]
        losing_trades = [trade for trade in recent_trades if not trade.was_profitable]

        win_rate = len(winning_trades) / len(recent_trades)

        # Calculate profit factor
        gross_profit = sum(trade.pnl for trade in winning_trades)
        gross_loss = sum(abs(trade.pnl) for trade in losing_trades)
        profit_factor = gross_profit / gross_loss if gross_loss > 0 else float('inf') if gross_profit > 0 else 0.0

        # Calculate average win/loss
        average_win = sum(trade.pnl for trade in winning_trades) / len(winning_trades) if len(winning_trades) > 0 else 0.0
        average_loss = sum(abs(trade.pnl) for trade in losing_trades) / len(losing_trades) if len(losing_trades) > 0 else 0.0

        # Calculate max drawdown (simplified - just from trade P&L)
        cumulative_pnl = 0.0
        peak_pnl = 0.0
        max_drawdown = 0.0

        for trade in recent_trades:
            cumulative_pnl += trade.pnl
            if cumulative_pnl > peak_pnl:
                peak_pnl = cumulative_pnl
            else:
                drawdown = (peak_pnl - cumulative_pnl) / peak_pnl if peak_pnl > 0 else 0.0
                max_drawdown = max(max_drawdown, drawdown)

        return PerformanceAnalysis(
            win_rate=win_rate,
            profit_factor=profit_factor,
            sharpe_ratio=0.0,  # Would need more data for accurate Sharpe
            max_drawdown=max_drawdown,
            average_win=average_win,
            average_loss=average_loss,
            total_trades=len(recent_trades),
            period_hours=self.performance_window_hours
        )

    fn detect_market_regime(self, market_data: List[MarketData]) -> MarketRegime:
        """
        Identify current market conditions
        """
        if len(market_data) < 10:
            return MarketRegime.UNKNOWN

        # Sort by timestamp
        sorted_data = sorted(market_data, key=lambda x: x.timestamp)

        # Calculate price changes
        prices = [data.price for data in sorted_data]
        price_changes = []

        for i in range(1, len(prices)):
            if prices[i-1] > 0:
                change = (prices[i] - prices[i-1]) / prices[i-1]
                price_changes.append(change)

        if len(price_changes) == 0:
            return MarketRegime.UNKNOWN

        # Calculate metrics
        avg_change = sum(price_changes) / len(price_changes)
        volatility = sum((change - avg_change) ** 2 for change in price_changes) / len(price_changes)
        volatility = volatility ** 0.5  # Standard deviation

        # Determine regime
        if volatility > 0.05:  # High volatility threshold
            return MarketRegime.VOLATILE
        elif avg_change > 0.02:  # Strong uptrend
            return MarketRegime.TRENDING_UP
        elif avg_change < -0.02:  # Strong downtrend
            return MarketRegime.TRENDING_DOWN
        elif abs(avg_change) < 0.01:  # Small changes - ranging
            return MarketRegime.RANGING
        else:
            return MarketRegime.UNKNOWN

    fn calculate_optimal_adjustments(self, performance: PerformanceAnalysis, regime: MarketRegime) -> StrategyAdjustment:
        """
        Determine optimal parameter adjustments based on performance and market regime
        """
        adjustment = StrategyAdjustment(timestamp=time())

        # Rule 1: Low Win Rate (<40%)
        if performance.win_rate < 0.4:
            adjustment.confidence_threshold_delta = 0.10  # Increase confidence threshold
            adjustment.position_size_multiplier = 0.8      # Reduce position size
            adjustment.reason = "Low win rate - increasing selectivity"

        # Rule 2: High Win Rate (>70%)
        elif performance.win_rate > 0.7:
            adjustment.confidence_threshold_delta = -0.05  # Decrease confidence threshold
            adjustment.position_size_multiplier = 1.2      # Increase position size
            adjustment.reason = "High win rate - increasing aggression"

        # Rule 3: Poor Profit Factor (<1.5)
        if performance.profit_factor < 1.5:
            adjustment.stop_loss_multiplier = 0.8          # Tighten stops
            adjustment.take_profit_multiplier = 1.3        # Widen targets
            if adjustment.reason:
                adjustment.reason += "; poor profit factor"
            else:
                adjustment.reason = "Poor profit factor - adjusting risk/reward"

        # Rule 4: High Volatility Market
        if regime == MarketRegime.VOLATILE:
            adjustment.position_size_multiplier *= 0.7      # Further reduce position size
            adjustment.max_positions_delta = -1            # Reduce max positions
            if adjustment.reason:
                adjustment.reason += "; high volatility"
            else:
                adjustment.reason = "High volatility - reducing exposure"

        # Rule 5: Ranging Market
        elif regime == MarketRegime.RANGING:
            adjustment.confidence_threshold_delta -= 0.05  # More trades in ranging market
            adjustment.take_profit_multiplier *= 0.8       # Quicker exits
            if adjustment.reason:
                adjustment.reason += "; ranging market"
            else:
                adjustment.reason = "Ranging market - mean reversion focus"

        # Rule 6: High Max Drawdown (>15%)
        if performance.max_drawdown > 0.15:
            adjustment.position_size_multiplier *= 0.6      # Significant position reduction
            adjustment.stop_loss_multiplier *= 0.7          # Tighter stops
            if adjustment.reason:
                adjustment.reason += "; high drawdown"
            else:
                adjustment.reason = "High drawdown - reducing risk"

        return adjustment

    fn apply_safety_limits(self, adjustment: StrategyAdjustment) -> StrategyAdjustment:
        """
        Apply safety limits to prevent extreme adjustments
        """
        # Confidence threshold limits
        max_confidence = self.config.strategy_adaptation.max_confidence_threshold
        min_confidence = self.config.strategy_adaptation.min_confidence_threshold
        baseline_confidence = self.config.strategy_adaptation.baseline_confidence_threshold

        new_confidence = baseline_confidence + adjustment.confidence_threshold_delta
        new_confidence = max(min_confidence, min(max_confidence, new_confidence))
        adjustment.confidence_threshold_delta = new_confidence - baseline_confidence

        # Position size multiplier limits
        max_multiplier = self.config.strategy_adaptation.max_position_size_multiplier
        min_multiplier = self.config.strategy_adaptation.min_position_size_multiplier
        adjustment.position_size_multiplier = max(min_multiplier, min(max_multiplier, adjustment.position_size_multiplier))

        # Stop loss and take profit limits (reasonable bounds)
        adjustment.stop_loss_multiplier = max(0.5, min(1.5, adjustment.stop_loss_multiplier))
        adjustment.take_profit_multiplier = max(0.5, min(2.0, adjustment.take_profit_multiplier))

        # Max positions limits
        baseline_max_positions = self.config.strategy_adaptation.baseline_max_positions
        new_max_positions = baseline_max_positions + adjustment.max_positions_delta
        new_max_positions = max(1, min(10, new_max_positions))  # Between 1 and 10 positions
        adjustment.max_positions_delta = new_max_positions - baseline_max_positions

        return adjustment

    fn apply_adjustments(self, adjustment: StrategyAdjustment):
        """
        Apply calculated adjustments to strategy parameters
        """
        if not adjustment.reason:  # No adjustment needed
            return

        # Update current adjustments
        self.current_adjustments["confidence_threshold"] = adjustment.confidence_threshold_delta
        self.current_adjustments["position_size_multiplier"] = adjustment.position_size_multiplier
        self.current_adjustments["stop_loss_multiplier"] = adjustment.stop_loss_multiplier
        self.current_adjustments["take_profit_multiplier"] = adjustment.take_profit_multiplier
        self.current_adjustments["max_positions_delta"] = adjustment.max_positions_delta

        # Apply to configuration (this would affect the actual trading components)
        self._apply_to_config(adjustment)

        self.logger.info("Strategy adaptation applied",
                        reason=adjustment.reason,
                        confidence_delta=adjustment.confidence_threshold_delta,
                        position_multiplier=adjustment.position_size_multiplier,
                        stop_loss_multiplier=adjustment.stop_loss_multiplier,
                        take_profit_multiplier=adjustment.take_profit_multiplier,
                        max_positions_delta=adjustment.max_positions_delta)

    fn revert_adjustments(self):
        """
        Reset all adjustments to baseline parameters
        """
        self.current_adjustments = {
            "confidence_threshold": 0.0,
            "position_size_multiplier": 1.0,
            "stop_loss_multiplier": 1.0,
            "take_profit_multiplier": 1.0,
            "max_positions_delta": 0
        }

        self._reset_config_to_baseline()

        self.logger.info("Strategy adjustments reverted to baseline")

    fn get_current_adjustments(self) -> Dict[String, Float]:
        """
        Return current active adjustments
        """
        return self.current_adjustments.copy()

    fn log_adaptation(self, adjustment: StrategyAdjustment):
        """
        Log adaptation event for audit trail
        """
        if not adjustment.reason:  # No adaptation to log
            return

        log_data = {
            "timestamp": adjustment.timestamp,
            "reason": adjustment.reason,
            "confidence_threshold_delta": adjustment.confidence_threshold_delta,
            "position_size_multiplier": adjustment.position_size_multiplier,
            "stop_loss_multiplier": adjustment.stop_loss_multiplier,
            "take_profit_multiplier": adjustment.take_profit_multiplier,
            "max_positions_delta": adjustment.max_positions_delta
        }

        self.logger.info("Strategy adaptation event", **log_data)

    fn _apply_to_config(self, adjustment: StrategyAdjustment):
        """
        Apply adjustments to configuration (mock implementation)
        """
        # In real implementation, this would update the actual config objects
        # used by strategy_engine, risk_manager, master_filter, etc.

        # For now, just log what would be updated
        baseline = self.config.strategy_adaptation

        new_confidence = baseline.baseline_confidence_threshold + adjustment.confidence_threshold_delta
        new_position_size = baseline.baseline_position_size * adjustment.position_size_multiplier
        new_stop_loss = baseline.baseline_stop_loss_percentage * adjustment.stop_loss_multiplier
        new_take_profit = baseline.baseline_take_profit_percentage * adjustment.take_profit_multiplier
        new_max_positions = baseline.baseline_max_positions + adjustment.max_positions_delta

        self.logger.debug("Config parameters would be updated",
                         new_confidence_threshold=new_confidence,
                         new_position_size=new_position_size,
                         new_stop_loss=new_stop_loss,
                         new_take_profit=new_take_profit,
                         new_max_positions=new_max_positions)

    fn _reset_config_to_baseline(self):
        """
        Reset configuration to baseline parameters
        """
        # In real implementation, reset all affected config objects
        self.logger.debug("Config parameters reset to baseline")

    fn _check_daily_reset(self):
        """
        Reset daily counters at midnight
        """
        current_time = time()
        current_date = int(current_time / 86400)  # Unix timestamp / seconds in day

        if current_date > self.last_reset_date:
            self.adaptations_today = 0
            self.last_reset_date = current_date
            self.logger.debug("Daily adaptation counter reset")

    fn get_adaptation_status(self) -> Dict[String, Any]:
        """
        Return current adaptation system status
        """
        current_time = time()
        hours_since_last = (current_time - self.last_adaptation_time) / 3600.0

        return {
            "enabled": self.adaptation_enabled,
            "last_adaptation_hours_ago": hours_since_last,
            "adaptations_today": self.adaptations_today,
            "next_adaptation_hours": max(0, self.adaptation_interval_hours - hours_since_last),
            "current_adjustments": self.current_adjustments.copy(),
            "min_trades_required": self.min_trades_for_adaptation,
            "performance_window_hours": self.performance_window_hours
        }