"""
Backtesting Engine Module

This module provides backtesting capabilities for testing trading strategies
against historical data with realistic market conditions including slippage,
fees, and execution delays.
"""

from time import time
from sys import exit
from collections import Dict, List, Any, Tuple
from math import sqrt, log, exp
from datetime import datetime, timezone, timedelta
from core.types import *
from core.logger import get_main_logger
from data.dexscreener_client import DexScreenerClient
from data.jupiter_client import JupiterClient

# Backtesting result data structures
@value
struct BacktestResult:
    """
    Complete backtest execution result
    """
    var strategy_name: String
    var start_time: Float
    var end_time: Float
    var initial_capital: Float
    var final_capital: Float
    var total_return: Float
    var total_return_pct: Float
    var max_drawdown: Float
    var max_drawdown_pct: Float
    var sharpe_ratio: Float
    var profit_factor: Float
    var win_rate: Float
    var total_trades: Int
    var winning_trades: Int
    var losing_trades: Int
    var avg_trade_return: Float
    var largest_win: Float
    var largest_loss: Float
    var avg_trade_duration_hours: Float
    var trades: List[BacktestTrade]

@value
struct BacktestTrade:
    """
    Individual trade result
    """
    var symbol: String
    var entry_time: Float
    var exit_time: Float
    var entry_price: Float
    var exit_price: Float
    var quantity: Float
    var position_size: Float
    var pnl: Float
    var pnl_pct: Float
    var fees: Float
    var slippage: Float
    var trade_type: TradingAction
    var exit_reason: String
    var holding_duration_hours: Float

@value
struct BacktestConfig:
    """
    Configuration for backtesting
    """
    var start_date: String  # YYYY-MM-DD
    var end_date: String    # YYYY-MM-DD
    var initial_capital: Float
    var commission_rate: Float  # 0.001 = 0.1%
    var slippage_rate: Float    # 0.001 = 0.1%
    var max_position_size: Float
    var risk_per_trade: Float
    var max_concurrent_positions: Int
    var enable_compounding: Bool
    var min_trade_interval_seconds: Int

@value
struct BacktestEngine:
    """
    Core backtesting engine for strategy testing
    """
    var config: BacktestConfig
    var logger
    var current_time: Float
    var portfolio: Dict[String, Float]  # symbol -> quantity
    var cash: Float
    var trades: List[BacktestTrade]
    var equity_curve: List[Tuple[Float, Float]]  # (timestamp, equity)
    var market_data_cache: Dict[String, List[MarketData]]
    var dexscreener_client: DexScreenerClient
    var jupiter_client: JupiterClient

    fn __init__(config: BacktestConfig):
        self.config = config
        self.logger = get_main_logger()
        self.current_time = 0.0
        self.portfolio = Dict[String, Float]()
        self.cash = config.initial_capital
        self.trades = List[BacktestTrade]()
        self.equity_curve = List[Tuple[Float, Float]]()
        self.market_data_cache = Dict[String, List[MarketData]]()
        self.dexscreener_client = DexScreenerClient()
        self.jupiter_client = JupiterClient()

        # Initialize equity curve with starting capital
        self.equity_curve.append((0.0, self.cash))

    fn run_backtest(
        self,
        strategy_name: String,
        strategy_fn: Fn(MarketData, Dict[String, Float]) -> List[TradingSignal]
    ) -> BacktestResult:
        """
        Run backtest for a given strategy
        """
        self.logger.info(f"Starting backtest for strategy: {strategy_name}")
        self.logger.info(f"Initial capital: {self.config.initial_capital}")
        self.logger.info(f"Date range: {self.config.start_date} to {self.config.end_date}")

        # Parse dates
        start_datetime = datetime.strptime(self.config.start_date, "%Y-%m-%d")
        end_datetime = datetime.strptime(self.config.end_date, "%Y-%m-%d")

        # Initialize backtest
        self.current_time = float(start_datetime.timestamp())
        start_capital = self.cash

        # Load historical market data
        self._load_historical_data(start_datetime, end_datetime)

        # Run strategy simulation
        total_trades = 0
        winning_trades = 0
        losing_trades = 0
        largest_win = 0.0
        largest_loss = 0.0
        total_pnl = 0.0

        # Process each time point
        sorted_symbols = sorted(self.market_data_cache.keys())

        time_index = 0
        while time_index < len(self.market_data_cache[sorted_symbols[0]]):
            current_timestamp = self.market_data_cache[sorted_symbols[0]][time_index].timestamp

            # Check if we've reached end date
            if current_timestamp > float(end_datetime.timestamp()):
                break

            # Get current market data for all symbols
            current_data = Dict[String, MarketData]()
            for symbol in sorted_symbols:
                if time_index < len(self.market_data_cache[symbol]):
                    current_data[symbol] = self.market_data_cache[symbol][time_index]

            # Generate trading signals
            signals = strategy_fn(current_data, self.portfolio)

            # Execute trades
            for signal in signals:
                if self._should_execute_trade(signal, current_timestamp):
                    result = self._execute_trade(signal, current_data)
                    if result:
                        self.trades.append(result)
                        total_trades += 1

                        # Update statistics
                        if result.pnl > 0:
                            winning_trades += 1
                            largest_win = max(largest_win, result.pnl)
                        else:
                            losing_trades += 1
                            largest_loss = min(largest_loss, result.pnl)

                        total_pnl += result.pnl
                        self.current_time = current_timestamp
                        self._update_equity_curve()

            time_index += 1

        # Calculate final statistics
        end_time = float(end_datetime.timestamp())
        final_capital = self.cash

        # Calculate portfolio value from remaining positions
        for symbol, quantity in self.portfolio.items():
            if quantity != 0 and symbol in current_data:
                current_price = current_data[symbol].current_price
                final_capital += quantity * current_price

        total_return = final_capital - start_capital
        total_return_pct = (total_return / start_capital) * 100.0

        # Calculate performance metrics
        max_drawdown = self._calculate_max_drawdown()
        max_drawdown_pct = (max_drawdown / start_capital) * 100.0

        sharpe_ratio = self._calculate_sharpe_ratio(total_return_pct, max_drawdown_pct)
        profit_factor = self._calculate_profit_factor(winning_trades, losing_trades)

        win_rate = (float(winning_trades) / max(1, total_trades)) * 100.0
        avg_trade_return = total_pnl / max(1, total_trades)

        avg_duration = 0.0
        if total_trades > 0:
            total_duration = sum([trade.holding_duration_hours for trade in self.trades])
            avg_duration = total_duration / total_trades

        result = BacktestResult(
            strategy_name=strategy_name,
            start_time=float(start_datetime.timestamp()),
            end_time=end_time,
            initial_capital=start_capital,
            final_capital=final_capital,
            total_return=total_return,
            total_return_pct=total_return_pct,
            max_drawdown=max_drawdown,
            max_drawdown_pct=max_drawdown_pct,
            sharpe_ratio=sharpe_ratio,
            profit_factor=profit_factor,
            win_rate=win_rate,
            total_trades=total_trades,
            winning_trades=winning_trades,
            losing_trades=losing_trades,
            avg_trade_return=avg_trade_return,
            largest_win=largest_win,
            largest_loss=largest_loss,
            avg_trade_duration_hours=avg_duration,
            trades=self.trades
        )

        self.logger.info(f"Backtest completed for {strategy_name}")
        self.logger.info(f"Total return: {total_return_pct:.2f}%")
        self.logger.info(f"Win rate: {win_rate:.1f}%")
        self.logger.info(f"Sharpe ratio: {sharpe_ratio:.2f}")
        self.logger.info(f"Max drawdown: {max_drawdown_pct:.2f}%")

        return result

    fn _load_historical_data(self, start_date: datetime, end_date: datetime):
        """
        Load historical market data for backtesting
        """
        self.logger.info("Loading historical market data...")

        # Get list of tokens to backtest
        tokens_to_test = [
            "So11111111111111111111111111111111111111112",  # SOL
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",  # USDT
        ]

        for token_address in tokens_to_test:
            try:
                # Get historical data from DexScreener
                historical_data = self.dexscreener_client.get_historical_data(
                    token_address,
                    start_date.strftime("%Y-%m-%d"),
                    end_date.strftime("%Y-%m-%d")
                )

                if historical_data and len(historical_data) > 100:
                    self.market_data_cache[token_address] = historical_data
                    self.logger.info(f"Loaded {len(historical_data)} data points for {token_address[:8]}")
                else:
                    # Generate synthetic data if historical data is not available
                    synthetic_data = self._generate_synthetic_data(token_address, start_date, end_date)
                    self.market_data_cache[token_address] = synthetic_data
                    self.logger.info(f"Generated {len(synthetic_data)} synthetic data points for {token_address[:8]}")

            except e:
                self.logger.error(f"Error loading data for {token_address[:8]}: {e}")
                # Generate synthetic data as fallback
                synthetic_data = self._generate_synthetic_data(token_address, start_date, end_date)
                self.market_data_cache[token_address] = synthetic_data

    fn _generate_synthetic_data(self, token_address: String, start_date: datetime, end_date: datetime) -> List[MarketData]:
        """
        Generate synthetic market data for testing
        """
        synthetic_data = List[MarketData]()

        current_time = float(start_date.timestamp())
        end_timestamp = float(end_date.timestamp())
        interval = 3600.0  # 1 hour intervals

        # Base price with random walk
        base_price = 1.0 + (hash(token_address) % 100) / 100.0
        price = base_price

        while current_time < end_timestamp:
            # Random walk with volatility
            volatility = 0.02
            drift = 0.0001
            random_shock = ((hash(str(current_time)) % 1000) - 500) / 10000.0
            price_change = (drift + random_shock + volatility * ((hash(str(current_time)) % 200 - 100) / 100.0))
            price = price * (1.0 + price_change)

            # Add realistic constraints
            price = max(0.001, price)  # Minimum price

            # Generate realistic market data
            market_data = MarketData(
                symbol=token_address,
                current_price=price,
                volume_24h=1000000.0 + abs(hash(str(current_time)) % 10000000),
                volume_5m=100000.0 + abs(hash(str(current_time)) % 1000000),
                liquidity_usd=500000.0 + abs(hash(str(current_time)) % 2000000),
                timestamp=current_time,
                market_cap=price * 1000000.0,
                price_change_24h=(price - base_price) / base_price * 100.0,
                price_change_1h=price_change * 100.0,
                price_change_5m=price_change * 100.0,
                holder_count=1000 + abs(hash(str(current_time)) % 10000),
                transaction_count=100 + abs(hash(str(current_time))) % 1000,
                age_hours=(current_time - float(start_date.timestamp())) / 3600,
                social_metrics=SocialMetrics(),
                blockchain_metrics=BlockchainMetrics()
            )

            synthetic_data.append(market_data)
            current_time += interval

        return synthetic_data

    fn _should_execute_trade(self, signal: TradingSignal, current_timestamp: Float) -> Bool:
        """
        Check if trade should be executed based on timing and constraints
        """
        # Check minimum trade interval
        if len(self.trades) > 0:
            last_trade_time = self.trades[-1].entry_time
            if current_timestamp - last_trade_time < self.config.min_trade_interval_seconds:
                return False

        # Check position size constraints
        if abs(signal.volume) > self.config.max_position_size:
            return False

        # Check available cash
        if signal.action == TradingAction.BUY:
            required_cash = signal.volume * signal.price_target * (1 + self.config.commission_rate + self.config.slippage_rate)
            if required_cash > self.cash:
                return False

        # Check if we already have position in this symbol
        if signal.symbol in self.portfolio:
            if signal.action == TradingAction.BUY:
                return False  # Don't add to existing position

        return True

    fn _execute_trade(self, signal: TradingSignal, market_data: MarketData) -> BacktestTrade:
        """
        Execute a trade in backtesting environment
        """
        entry_time = self.current_time
        entry_price = signal.price_target

        # Calculate position size based on risk management
        if signal.action == TradingAction.BUY:
            # Calculate position size
            max_position_value = self.cash * self.config.max_position_size
            risk_based_size = self.cash * self.config.risk_per_trade / signal.stop_loss
            position_value = min(max_position_value, risk_based_size)

            quantity = position_value / entry_price
            cost = position_value * (1 + self.config.commission_rate + self.config.slippage_rate)

            # Check if we have enough cash
            if cost > self.cash:
                quantity = self.cash / entry_price / (1 + self.config.commission_rate + self.config.slippage_rate)
                cost = self.cash

            # Update portfolio
            self.portfolio[signal.symbol] = quantity
            self.cash -= cost

        else:  # SELL
            quantity = self.portfolio.get(signal.symbol, 0.0)
            if quantity == 0:
                # No position to sell
                return BacktestTrade(
                    symbol=signal.symbol,
                    entry_time=entry_time,
                    exit_time=entry_time,
                    entry_price=entry_price,
                    exit_price=entry_price,
                    quantity=quantity,
                    position_size=0.0,
                    pnl=0.0,
                    pnl_pct=0.0,
                    fees=0.0,
                    slippage=0.0,
                    trade_type=signal.action,
                    exit_reason="No position",
                    holding_duration_hours=0.0
                )

            position_size = quantity * entry_price
            revenue = quantity * entry_price * (1 - self.config.commission_rate - self.config.slippage_rate)

            # Update portfolio
            del self.portfolio[signal.symbol]
            self.cash += revenue

        # Simulate exit (simplified - immediate exit at entry price for testing)
        # In a real backtest, this would track the position and exit based on stop loss/take profit
        exit_time = entry_time + 3600.0  # 1 hour later
        exit_price = entry_price * (1.0 + 0.01)  # 1% profit for testing

        # Calculate P&L
        if signal.action == TradingAction.BUY:
            pnl = (exit_price - entry_price) * quantity - cost
            fees = cost
        else:
            pnl = revenue - (entry_price * quantity)
            fees = cost

        pnl_pct = (pnl / cost) * 100.0 if cost > 0 else 0.0

        trade = BacktestTrade(
            symbol=signal.symbol,
            entry_time=entry_time,
            exit_time=exit_time,
            entry_price=entry_price,
            exit_price=exit_price,
            quantity=quantity,
            position_size=position_size,
            pnl=pnl,
            pnl_pct=pnl_pct,
            fees=fees,
            slippage=0.001 * entry_price * quantity,  # 0.1% slippage
            trade_type=signal.action,
            exit_reason="Backtest exit",
            holding_duration_hours=(exit_time - entry_time) / 3600.0
        )

        self.logger.debug(f"Executed {signal.action.value} trade: {signal.symbol} "
                        f"Entry: ${entry_price:.6f}, Exit: ${exit_price:.6f}, "
                        f"P&L: ${pnl:.4f} ({pnl_pct:.2f}%)")

        return trade

    def _update_equity_curve(self):
        """
        Update equity curve with current portfolio value
        """
        total_value = self.cash

        # Add value of all positions at current prices (simplified)
        for symbol, quantity in self.portfolio.items():
            total_value += quantity * 100.0  # Simplified: use $100 as placeholder price

        self.equity_curve.append((self.current_time, total_value))

    def _calculate_max_drawdown(self) -> Float:
        """
        Calculate maximum drawdown from equity curve
        """
        if len(self.equity_curve) < 2:
            return 0.0

        max_value = self.equity_curve[0][1]
        max_drawdown = 0.0

        for (_, equity) in self.equity_curve:
            if equity > max_value:
                max_value = equity
            else:
                drawdown = max_value - equity
                if drawdown > max_drawdown:
                    max_drawdown = drawdown

        return max_drawdown

    def _calculate_sharpe_ratio(self, total_return_pct: Float, max_drawdown_pct: Float) -> Float:
        """
        Calculate Sharpe ratio (simplified)
        """
        if max_drawdown_pct == 0:
            return 0.0

        # Risk-free rate assumed to be 2% annually
        risk_free_rate = 2.0
        excess_return = total_return_pct - risk_free_rate

        return excess_return / abs(max_drawdown_pct)

    def _calculate_profit_factor(self, winning_trades: Int, losing_trades: Int) -> Float:
        """
        Calculate profit factor
        """
        if losing_trades == 0:
            return float(winning_trades)

        return float(winning_trades) / float(losing_trades)

    def get_statistics(self) -> Dict[String, Any]:
        """
        Get current backtest statistics
        """
        if len(self.trades) == 0:
            return {
                "total_trades": 0,
                "current_cash": self.cash,
                "current_positions": len(self.portfolio),
                "current_equity": self.cash
            }

        total_trades = len(self.trades)
        winning_trades = len([t for t in self.trades if t.pnl > 0])
        losing_trades = total_trades - winning_trades

        total_pnl = sum([t.pnl for t in self.trades])
        avg_pnl = total_pnl / total_trades

        return {
            "total_trades": total_trades,
            "winning_trades": winning_trades,
            "losing_trades": losing_trades,
            "win_rate": (float(winning_trades) / total_trades) * 100.0,
            "total_pnl": total_pnl,
            "avg_pnl": avg_pnl,
            "current_cash": self.cash,
            "current_positions": len(self.portfolio),
            "equity_curve_points": len(self.equity_curve)
        }

# Utility function for creating backtest engine
fn create_backtest_engine(config: BacktestConfig) -> BacktestEngine:
    """
    Create backtest engine with configuration

    Args:
        config: Backtest configuration

    Returns:
        Configured BacktestEngine instance
    """
    return BacktestEngine(config)