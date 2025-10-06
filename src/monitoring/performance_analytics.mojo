from collections import Dict, List, Any, Tuple
from core.types import TradingAction
from core.config import Config
from core.logger import get_logger
from time import time
from math import sqrt

struct TradeRecord:
    """
    Complete trade record for performance analysis
    """
    var symbol: String
    var action: TradingAction
    var entry_price: Float
    var exit_price: Float
    var size: Float
    var pnl: Float
    var pnl_percentage: Float
    var entry_timestamp: Float
    var exit_timestamp: Float
    var hold_duration_seconds: Float
    var was_profitable: Bool
    var close_reason: String

    fn __init__(
        symbol: String,
        action: TradingAction,
        entry_price: Float,
        exit_price: Float,
        size: Float,
        pnl: Float,
        pnl_percentage: Float,
        entry_timestamp: Float,
        exit_timestamp: Float,
        hold_duration_seconds: Float,
        was_profitable: Bool,
        close_reason: String
    ):
        self.symbol = symbol
        self.action = action
        self.entry_price = entry_price
        self.exit_price = exit_price
        self.size = size
        self.pnl = pnl
        self.pnl_percentage = pnl_percentage
        self.entry_timestamp = entry_timestamp
        self.exit_timestamp = exit_timestamp
        self.hold_duration_seconds = hold_duration_seconds
        self.was_profitable = was_profitable
        self.close_reason = close_reason

struct PerformanceAnalytics:
    """
    Comprehensive performance analytics engine
    """

    # Trade data
    var trade_history: List[TradeRecord]
    var daily_returns: List[Float]
    var equity_curve: List[Float]
    var timestamps: List[Float]

    # Configuration
    var config: Config
    var risk_free_rate: Float
    var logger: Any

    # Performance cache
    var cached_metrics: Dict[String, Float]
    var cache_timestamp: Float
    var cache_valid_seconds: Float

    fn __init__(config: Config, risk_free_rate: Float = 0.02):
        self.config = config
        self.risk_free_rate = risk_free_rate
        self.logger = get_logger("PerformanceAnalytics")

        # Initialize data structures
        self.trade_history = []
        self.daily_returns = []
        self.equity_curve = []
        self.timestamps = []

        self.cached_metrics = {}
        self.cache_timestamp = 0.0
        self.cache_valid_seconds = 300.0  # 5 minutes cache

        self.logger.info("Performance analytics initialized", risk_free_rate=risk_free_rate)

    fn record_trade(self, trade: TradeRecord):
        """
        Add completed trade to history
        """
        self.trade_history.append(trade)

        # Invalidate cache
        self._invalidate_cache()

        self.logger.info("Trade recorded",
                        symbol=trade.symbol,
                        pnl=trade.pnl,
                        pnl_percentage=trade.pnl_percentage,
                        was_profitable=trade.was_profitable,
                        close_reason=trade.close_reason)

    fn update_equity_curve(self, portfolio_value: Float):
        """
        Track portfolio value over time
        """
        current_time = time()

        # Calculate daily return if we have previous data
        if len(self.equity_curve) > 0:
            previous_value = self.equity_curve[-1]
            daily_return = (portfolio_value - previous_value) / previous_value
            self.daily_returns.append(daily_return)

        self.equity_curve.append(portfolio_value)
        self.timestamps.append(current_time)

        # Keep only last 1000 data points to prevent memory growth
        if len(self.equity_curve) > 1000:
            self.equity_curve = self.equity_curve[-1000:]
            self.timestamps = self.timestamps[-1000:]
            if len(self.daily_returns) > 1000:
                self.daily_returns = self.daily_returns[-1000:]

    def calculate_win_rate(self) -> Float:
        """
        Calculate percentage of profitable trades
        """
        if len(self.trade_history) == 0:
            return 0.0

        winning_trades = sum(1 for trade in self.trade_history if trade.was_profitable)
        return Float(winning_trades) / Float(len(self.trade_history))

    def calculate_sharpe_ratio(self) -> Float:
        """
        Calculate Sharpe ratio: (Mean Return - Risk Free Rate) / Std Dev of Returns
        """
        if len(self.daily_returns) < 2:
            return 0.0

        # Calculate mean daily return
        mean_return = sum(self.daily_returns) / len(self.daily_returns)

        # Calculate standard deviation
        variance = sum((r - mean_return) ** 2 for r in self.daily_returns) / len(self.daily_returns)
        std_dev = sqrt(variance)

        if std_dev == 0:
            return 0.0

        # Annualize and calculate Sharpe (assuming 252 trading days per year)
        annual_return = mean_return * 252
        annual_std_dev = std_dev * sqrt(252)

        return (annual_return - self.risk_free_rate) / annual_std_dev

    def calculate_sortino_ratio(self) -> Float:
        """
        Calculate Sortino ratio: (Mean Return - Risk Free Rate) / Downside Deviation
        """
        if len(self.daily_returns) < 2:
            return 0.0

        # Calculate mean daily return
        mean_return = sum(self.daily_returns) / len(self.daily_returns)

        # Calculate downside deviation (only negative returns)
        negative_returns = [r for r in self.daily_returns if r < 0]
        if len(negative_returns) == 0:
            return float('inf')  # No downside risk

        downside_variance = sum((r - mean_return) ** 2 for r in negative_returns) / len(negative_returns)
        downside_std_dev = sqrt(downside_variance)

        if downside_std_dev == 0:
            return 0.0

        # Annualize
        annual_return = mean_return * 252
        annual_downside_std_dev = downside_std_dev * sqrt(252)

        return (annual_return - self.risk_free_rate) / annual_downside_std_dev

    def calculate_max_drawdown(self) -> Float:
        """
        Calculate maximum peak-to-trough decline
        """
        if len(self.equity_curve) < 2:
            return 0.0

        peak = self.equity_curve[0]
        max_drawdown = 0.0

        for value in self.equity_curve:
            if value > peak:
                peak = value
            else:
                drawdown = (peak - value) / peak
                max_drawdown = max(max_drawdown, drawdown)

        return max_drawdown

    def calculate_profit_factor(self) -> Float:
        """
        Calculate profit factor: Gross Profit / Gross Loss
        """
        gross_profit = 0.0
        gross_loss = 0.0

        for trade in self.trade_history:
            if trade.pnl > 0:
                gross_profit += trade.pnl
            elif trade.pnl < 0:
                gross_loss += abs(trade.pnl)

        if gross_loss == 0:
            return float('inf') if gross_profit > 0 else 0.0

        return gross_profit / gross_loss

    def calculate_average_win(self) -> Float:
        """
        Calculate average profit per winning trade
        """
        winning_trades = [trade for trade in self.trade_history if trade.was_profitable]
        if len(winning_trades) == 0:
            return 0.0

        total_profit = sum(trade.pnl for trade in winning_trades)
        return total_profit / len(winning_trades)

    def calculate_average_loss(self) -> Float:
        """
        Calculate average loss per losing trade
        """
        losing_trades = [trade for trade in self.trade_history if not trade.was_profitable]
        if len(losing_trades) == 0:
            return 0.0

        total_loss = sum(abs(trade.pnl) for trade in losing_trades)
        return total_loss / len(losing_trades)

    def calculate_expectancy(self) -> Float:
        """
        Calculate expected value per trade
        """
        win_rate = self.calculate_win_rate()
        avg_win = self.calculate_average_win()
        avg_loss = self.calculate_average_loss()
        loss_rate = 1.0 - win_rate

        return (win_rate * avg_win) - (loss_rate * avg_loss)

    def calculate_recovery_factor(self) -> Float:
        """
        Calculate recovery factor: Net Profit / Max Drawdown
        """
        total_profit = sum(trade.pnl for trade in self.trade_history)
        max_drawdown = self.calculate_max_drawdown()

        if max_drawdown == 0:
            return 0.0

        return total_profit / max_drawdown

    def get_performance_summary(self) -> Dict[String, Float]:
        """
        Return all key performance metrics in one dictionary
        """
        current_time = time()

        # Check cache validity
        if current_time - self.cache_timestamp < self.cache_valid_seconds and len(self.cached_metrics) > 0:
            return self.cached_metrics

        # Calculate all metrics
        metrics = {
            "total_trades": Float(len(self.trade_history)),
            "win_rate": self.calculate_win_rate(),
            "sharpe_ratio": self.calculate_sharpe_ratio(),
            "sortino_ratio": self.calculate_sortino_ratio(),
            "max_drawdown": self.calculate_max_drawdown(),
            "profit_factor": self.calculate_profit_factor(),
            "average_win": self.calculate_average_win(),
            "average_loss": self.calculate_average_loss(),
            "expectancy": self.calculate_expectancy(),
            "recovery_factor": self.calculate_recovery_factor(),
        }

        # Add trade count breakdowns
        winning_trades = sum(1 for trade in self.trade_history if trade.was_profitable)
        losing_trades = sum(1 for trade in self.trade_history if not trade.was_profitable)

        metrics["winning_trades"] = Float(winning_trades)
        metrics["losing_trades"] = Float(losing_trades)

        # Add total P&L
        total_pnl = sum(trade.pnl for trade in self.trade_history)
        metrics["total_pnl"] = total_pnl

        # Add average hold duration
        if len(self.trade_history) > 0:
            avg_hold_duration = sum(trade.hold_duration_seconds for trade in self.trade_history) / len(self.trade_history)
            metrics["average_hold_duration_hours"] = avg_hold_duration / 3600.0
        else:
            metrics["average_hold_duration_hours"] = 0.0

        # Update cache
        self.cached_metrics = metrics
        self.cache_timestamp = current_time

        return metrics

    def get_recent_performance(self, hours: Int) -> Dict[String, Float]:
        """
        Calculate performance metrics for recent trades only
        """
        current_time = time()
        cutoff_time = current_time - (hours * 3600.0)

        recent_trades = [trade for trade in self.trade_history if trade.exit_timestamp >= cutoff_time]

        if len(recent_trades) == 0:
            return {
                "total_trades": 0.0,
                "win_rate": 0.0,
                "total_pnl": 0.0,
                "period_hours": Float(hours)
            }

        winning_trades = sum(1 for trade in recent_trades if trade.was_profitable)
        win_rate = Float(winning_trades) / Float(len(recent_trades))
        total_pnl = sum(trade.pnl for trade in recent_trades)

        return {
            "total_trades": Float(len(recent_trades)),
            "win_rate": win_rate,
            "total_pnl": total_pnl,
            "period_hours": Float(hours),
            "winning_trades": Float(winning_trades),
            "losing_trades": Float(len(recent_trades) - winning_trades)
        }

    def analyze_trade_distribution(self) -> Dict[String, Any]:
        """
        Analyze distribution of wins and losses
        """
        if len(self.trade_history) == 0:
            return {}

        wins = [trade.pnl for trade in self.trade_history if trade.was_profitable]
        losses = [trade.pnl for trade in self.trade_history if not trade.was_profitable]

        result = {
            "total_trades": len(self.trade_history),
            "winning_trades": len(wins),
            "losing_trades": len(losses),
            "win_rate": len(wins) / len(self.trade_history)
        }

        # Win statistics
        if len(wins) > 0:
            result.update({
                "largest_win": max(wins),
                "smallest_win": min(wins),
                "average_win": sum(wins) / len(wins),
                "total_wins": sum(wins)
            })
        else:
            result.update({
                "largest_win": 0.0,
                "smallest_win": 0.0,
                "average_win": 0.0,
                "total_wins": 0.0
            })

        # Loss statistics
        if len(losses) > 0:
            result.update({
                "largest_loss": min(losses),  # Most negative
                "smallest_loss": max(losses),  # Least negative
                "average_loss": sum(abs(l) for l in losses) / len(losses),
                "total_losses": sum(abs(l) for l in losses)
            })
        else:
            result.update({
                "largest_loss": 0.0,
                "smallest_loss": 0.0,
                "average_loss": 0.0,
                "total_losses": 0.0
            })

        return result

    def get_best_worst_trades(self, n: Int) -> Tuple[List[TradeRecord], List[TradeRecord]]:
        """
        Return best and worst trades by P&L
        """
        if len(self.trade_history) == 0:
            return ([], [])

        # Sort by P&L
        sorted_trades = sorted(self.trade_history, key=lambda trade: trade.pnl, reverse=True)

        best_trades = sorted_trades[:n]
        worst_trades = sorted_trades[-n:]

        return (best_trades, worst_trades)

    def print_performance_report(self):
        """
        Print detailed performance report to console
        """
        metrics = self.get_performance_summary()
        distribution = self.analyze_trade_distribution()
        current_time = time()

        print("\n" + "="*60)
        print(f"📊 PERFORMANCE ANALYTICS REPORT - {time()}")
        print("="*60)

        # Basic metrics
        print(f"📈 Total Trades: {int(metrics['total_trades'])}")
        print(f"🏆 Win Rate: {metrics['win_rate']:.1%}")
        print(f"💰 Total P&L: {metrics['total_pnl']:.4f} SOL")
        print(f"📊 Winning Trades: {int(metrics['winning_trades'])}")
        print(f"📉 Losing Trades: {int(metrics['losing_trades'])}")

        if metrics['total_trades'] > 0:
            print(f"⚖️  Profit Factor: {metrics['profit_factor']:.2f}")
            print(f"🎯 Expectancy: {metrics['expectancy']:.4f} SOL per trade")
            print(f"⏱️  Avg Hold Duration: {metrics['average_hold_duration_hours']:.1f} hours")

        # Risk metrics
        if len(self.daily_returns) >= 2:
            print(f"📊 Sharpe Ratio: {metrics['sharpe_ratio']:.2f}")
            print(f"📈 Sortino Ratio: {metrics['sortino_ratio']:.2f}")
        else:
            print(f"📊 Sharpe Ratio: N/A (insufficient data)")
            print(f"📈 Sortino Ratio: N/A (insufficient data)")

        print(f"📉 Max Drawdown: {metrics['max_drawdown']:.2%}")
        print(f"🔄 Recovery Factor: {metrics['recovery_factor']:.2f}")

        # Distribution details
        if len(distribution) > 0:
            print(f"\n💹 BEST TRADE: +{distribution['largest_win']:.4f} SOL")
            print(f"💸 WORST TRADE: {distribution['largest_loss']:.4f} SOL")
            print(f"📊 Average Win: +{distribution['average_win']:.4f} SOL")
            print(f"📊 Average Loss: -{distribution['average_loss']:.4f} SOL")

        # Recent performance
        recent_24h = self.get_recent_performance(24)
        recent_7d = self.get_recent_performance(168)  # 7 days

        print(f"\n🕐 Last 24 Hours: {int(recent_24h['total_trades'])} trades, {recent_24h['win_rate']:.1%} win rate, {recent_24h['total_pnl']:+.4f} SOL")
        print(f"📅 Last 7 Days: {int(recent_7d['total_trades'])} trades, {recent_7d['win_rate']:.1%} win rate, {recent_7d['total_pnl']:+.4f} SOL")

        print("="*60)

    def export_to_json(self) -> String:
        """
        Export performance data to JSON format
        """
        metrics = self.get_performance_summary()
        distribution = self.analyze_trade_distribution()

        # Convert trade history to list of dicts
        trade_data = []
        for trade in self.trade_history:
            trade_dict = {
                "symbol": trade.symbol,
                "action": str(trade.action),
                "entry_price": trade.entry_price,
                "exit_price": trade.exit_price,
                "size": trade.size,
                "pnl": trade.pnl,
                "pnl_percentage": trade.pnl_percentage,
                "entry_timestamp": trade.entry_timestamp,
                "exit_timestamp": trade.exit_timestamp,
                "hold_duration_seconds": trade.hold_duration_seconds,
                "was_profitable": trade.was_profitable,
                "close_reason": trade.close_reason
            }
            trade_data.append(trade_dict)

        export_data = {
            "timestamp": time(),
            "summary": metrics,
            "distribution": distribution,
            "trade_history": trade_data,
            "equity_curve": self.equity_curve,
            "timestamps": self.timestamps
        }

        # Note: In a real implementation, you'd use a JSON library
        # For now, return a simple string representation
        return f"Performance Analytics Export - {len(self.trade_history)} trades"

    def generate_daily_summary(self) -> String:
        """
        Generate daily performance summary for alerts
        """
        current_time = time()
        today_trades = [trade for trade in self.trade_history if trade.exit_timestamp >= current_time - 86400]

        if len(today_trades) == 0:
            return "📊 Daily Summary: No trades completed today"

        wins = sum(1 for trade in today_trades if trade.was_profitable)
        total_pnl = sum(trade.pnl for trade in today_trades)
        win_rate = wins / len(today_trades)

        return f"📊 Daily Summary: {len(today_trades)} trades, {win_rate:.1%} win rate, {total_pnl:+.4f} SOL"

    fn _invalidate_cache(self):
        """
        Invalidate performance metrics cache
        """
        self.cached_metrics = {}
        self.cache_timestamp = 0.0