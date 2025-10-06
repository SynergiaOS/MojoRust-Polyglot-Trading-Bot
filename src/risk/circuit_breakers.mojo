from collections import Dict, List, Any
from core.types import Portfolio, Position, TradingAction
from core.config import Config
from core.logger import get_logger
from time import time

struct CircuitBreakers:
    """
    Comprehensive circuit breaker system for trading safety
    """

    # Trading halt status
    var is_trading_halted: Bool
    var halt_reason: String
    var halt_timestamp: Float

    # Consecutive loss/win tracking
    var consecutive_losses: Int
    var consecutive_wins: Int
    var daily_loss_count: Int
    var last_trade_result: Bool

    # Trade velocity tracking
    var velocity_tracker: Dict[String, Float]
    var last_reset_time: Float

    # Configuration
    var config: Config
    var logger: Any

    fn __init__(config: Config):
        self.config = config
        self.logger = get_logger("CircuitBreakers")

        # Initialize state
        self.is_trading_halted = False
        self.halt_reason = ""
        self.halt_timestamp = 0.0

        self.consecutive_losses = 0
        self.consecutive_wins = 0
        self.daily_loss_count = 0
        self.last_trade_result = True  # Assume win initially

        self.velocity_tracker = {}
        self.last_reset_time = time()

        self.logger.info("Circuit breakers initialized",
                        max_drawdown=self.config.circuit_breakers.max_drawdown,
                        max_consecutive_losses=self.config.circuit_breakers.max_consecutive_losses)

    fn check_all_conditions(self, portfolio: Portfolio) -> Bool:
        """
        Run all circuit breaker checks, return True if safe to continue trading
        """
        # Reset daily counters at midnight UTC
        self._check_daily_reset()

        # Skip all checks if already halted (manual resume required)
        if self.is_trading_halted:
            return False

        # Check each condition
        if self.check_max_drawdown(portfolio):
            return False

        if self.check_consecutive_losses():
            return False

        if self.check_daily_loss_limit(portfolio):
            return False

        if self.check_position_concentration(portfolio):
            return False

        if self.check_rapid_drawdown(portfolio):
            return False

        return True

    fn check_max_drawdown(self, portfolio: Portfolio) -> Bool:
        """
        Check if maximum drawdown threshold exceeded
        Returns True if trading should be halted
        """
        if portfolio.peak_value <= 0:
            return False

        current_drawdown = (portfolio.peak_value - portfolio.total_value) / portfolio.peak_value

        if current_drawdown >= self.config.circuit_breakers.max_drawdown:
            self.halt_trading(f"Maximum drawdown exceeded: {current_drawdown:.1%}")
            self.logger.error("Maximum drawdown triggered",
                            current_drawdown=current_drawdown,
                            threshold=self.config.circuit_breakers.max_drawdown,
                            portfolio_value=portfolio.total_value,
                            peak_value=portfolio.peak_value)
            return True

        return False

    fn check_consecutive_losses(self) -> Bool:
        """
        Check if consecutive loss threshold exceeded
        Returns True if trading should be halted
        """
        if self.consecutive_losses >= self.config.circuit_breakers.max_consecutive_losses:
            self.halt_trading(f"Maximum consecutive losses reached: {self.consecutive_losses}")
            self.logger.error("Consecutive losses triggered",
                            consecutive_losses=self.consecutive_losses,
                            threshold=self.config.circuit_breakers.max_consecutive_losses)
            return True

        return False

    fn check_daily_loss_limit(self, portfolio: Portfolio) -> Bool:
        """
        Check if daily loss limit exceeded
        Returns True if trading should be halted
        """
        if portfolio.total_value <= 0:
            return False

        daily_loss_percentage = abs(portfolio.daily_pnl) / portfolio.total_value

        if portfolio.daily_pnl < 0 and daily_loss_percentage >= self.config.circuit_breakers.max_daily_loss_percentage:
            self.halt_trading(f"Daily loss limit exceeded: {daily_loss_percentage:.1%}")
            self.logger.error("Daily loss limit triggered",
                            daily_loss=portfolio.daily_pnl,
                            daily_loss_percentage=daily_loss_percentage,
                            threshold=self.config.circuit_breakers.max_daily_loss_percentage)
            return True

        return False

    fn check_position_concentration(self, portfolio: Portfolio) -> Bool:
        """
        Check if any single position is too large
        Returns True if trading should be halted
        """
        if portfolio.total_value <= 0:
            return False

        for symbol, position in portfolio.positions.items():
            position_value = position.size * position.current_price
            position_percentage = position_value / portfolio.total_value

            if position_percentage >= self.config.circuit_breakers.max_position_concentration:
                self.halt_trading(f"Position concentration exceeded for {symbol}: {position_percentage:.1%}")
                self.logger.error("Position concentration triggered",
                                symbol=symbol,
                                position_percentage=position_percentage,
                                threshold=self.config.circuit_breakers.max_position_concentration)
                return True

        return False

    fn check_trade_velocity(self, symbol: String) -> Bool:
        """
        Check if trading same symbol too frequently
        Returns True if trading should be halted for this symbol
        """
        current_time = time()
        last_trade_time = self.velocity_tracker.get(symbol, 0.0)

        if last_trade_time > 0:
            time_since_last = current_time - last_trade_time
            if time_since_last < self.config.circuit_breakers.min_trade_interval_seconds:
                self.logger.warn("Trade velocity check triggered for symbol",
                               symbol=symbol,
                               time_since_last=time_since_last,
                               min_interval=self.config.circuit_breakers.min_trade_interval_seconds)
                return True

        # Update last trade time
        self.velocity_tracker[symbol] = current_time
        return False

    fn check_rapid_drawdown(self, portfolio: Portfolio) -> Bool:
        """
        Check for rapid drawdown (sudden portfolio value drop)
        Returns True if trading should be halted
        """
        # This would require tracking portfolio value over time
        # For now, implement basic check based on daily loss velocity

        if portfolio.daily_pnl < 0:
            # Check if daily loss is accumulating rapidly
            hours_since_reset = (time() - self.last_reset_time) / 3600.0
            if hours_since_reset > 0:
                daily_loss_rate = abs(portfolio.daily_pnl) / hours_since_reset
                portfolio_value_rate = daily_loss_rate / portfolio.total_value if portfolio.total_value > 0 else 0

                if portfolio_value_rate >= self.config.circuit_breakers.rapid_drawdown_threshold:
                    self.halt_trading(f"Rapid drawdown detected: {portfolio_value_rate:.1%} per hour")
                    self.logger.error("Rapid drawdown triggered",
                                    hourly_loss_rate=portfolio_value_rate,
                                    threshold=self.config.circuit_breakers.rapid_drawdown_threshold)
                    return True

        return False

    fn halt_trading(self, reason: String):
        """
        Trigger trading halt with reason
        """
        self.is_trading_halted = True
        self.halt_reason = reason
        self.halt_timestamp = time()

        self.logger.error("Trading halted", reason=reason, timestamp=self.halt_timestamp)

    fn resume_trading(self):
        """
        Resume trading after manual review
        """
        self.is_trading_halted = False
        self.halt_reason = ""
        self.halt_timestamp = 0.0

        # Reset consecutive losses but keep other counters
        self.consecutive_losses = 0

        self.logger.info("Trading resumed after manual review")

    fn record_trade_result(self, success: Bool, pnl: Float):
        """
        Update consecutive loss/win counters and daily loss count
        """
        self.last_trade_result = success

        if pnl < 0:
            self.consecutive_losses += 1
            self.consecutive_wins = 0
            self.daily_loss_count += 1

            self.logger.debug("Loss recorded",
                            consecutive_losses=self.consecutive_losses,
                            pnl=pnl)
        elif pnl > 0:
            self.consecutive_wins += 1
            self.consecutive_losses = 0

            self.logger.debug("Win recorded",
                            consecutive_wins=self.consecutive_wins,
                            pnl=pnl)
        # PnL = 0 doesn't affect streaks

    fn reset_daily_counters(self):
        """
        Reset daily statistics (called at midnight UTC)
        """
        self.daily_loss_count = 0
        self.last_reset_time = time()
        self.velocity_tracker.clear()

        self.logger.info("Daily counters reset")

    fn _check_daily_reset(self):
        """
        Check if it's time to reset daily counters (midnight UTC)
        """
        current_time = time()

        # Simple check: reset if more than 24 hours have passed
        if current_time - self.last_reset_time >= 86400:  # 24 hours
            self.reset_daily_counters()

    fn get_halt_status(self) -> Dict[String, Any]:
        """
        Return current halt status and statistics
        """
        current_time = time()

        return {
            "status": "HALTED" if self.is_trading_halted else "ACTIVE",
            "is_trading_halted": self.is_trading_halted,
            "halt_reason": self.halt_reason,
            "halt_timestamp": self.halt_timestamp,
            "halt_duration_hours": (current_time - self.halt_timestamp) / 3600.0 if self.is_trading_halted else 0.0,
            "consecutive_losses": self.consecutive_losses,
            "consecutive_wins": self.consecutive_wins,
            "daily_loss_count": self.daily_loss_count,
            "last_trade_result": self.last_trade_result,
            "velocity_tracker_size": len(self.velocity_tracker),
            "hours_since_reset": (current_time - self.last_reset_time) / 360.0
        }

    fn get_system_health(self, portfolio: Portfolio) -> Dict[String, Any]:
        """
        Return comprehensive system health metrics
        """
        current_drawdown = (portfolio.peak_value - portfolio.total_value) / portfolio.peak_value if portfolio.peak_value > 0 else 0.0
        daily_loss_percentage = abs(portfolio.daily_pnl) / portfolio.total_value if portfolio.total_value > 0 else 0.0

        # Find max position concentration
        max_position_concentration = 0.0
        for position in portfolio.positions.values():
            position_value = position.size * position.current_price
            position_percentage = position_value / portfolio.total_value if portfolio.total_value > 0 else 0.0
            max_position_concentration = max(max_position_concentration, position_percentage)

        return {
            "overall_health": "HEALTHY" if not self.is_trading_halted else "HALTED",
            "current_drawdown": current_drawdown,
            "drawdown_threshold": self.config.circuit_breakers.max_drawdown,
            "drawdown_utilization": current_drawdown / self.config.circuit_breakers.max_drawdown,
            "consecutive_losses": self.consecutive_losses,
            "loss_threshold": self.config.circuit_breakers.max_consecutive_losses,
            "loss_utilization": self.consecutive_losses / self.config.circuit_breakers.max_consecutive_losses,
            "daily_loss_percentage": daily_loss_percentage if portfolio.daily_pnl < 0 else 0.0,
            "daily_loss_threshold": self.config.circuit_breakers.max_daily_loss_percentage,
            "daily_loss_utilization": (daily_loss_percentage / self.config.circuit_breakers.max_daily_loss_percentage) if portfolio.daily_pnl < 0 else 0.0,
            "max_position_concentration": max_position_concentration,
            "concentration_threshold": self.config.circuit_breakers.max_position_concentration,
            "concentration_utilization": max_position_concentration / self.config.circuit_breakers.max_position_concentration,
            "velocity_tracker_entries": len(self.velocity_tracker),
            "portfolio_value": portfolio.total_value,
            "peak_value": portfolio.peak_value
        }