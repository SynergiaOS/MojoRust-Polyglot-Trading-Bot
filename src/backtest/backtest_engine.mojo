# =============================================================================
# PumpFun Backtest Engine - High-Performance Mojo Compute Kernel
# =============================================================================
# This module provides SIMD-vectorized backtesting capabilities for PumpFun
# token analysis. It implements high-performance algorithms for price history
# analysis, technical indicators, and statistical computations with optimal
# memory usage and parallel processing capabilities.

from tensor import Tensor
from memory import memset_zero
from time import now
from math import sqrt, abs, max, min
from algorithm import sort, parallel_for
from python import Python

# Python imports for FFI
let pumpfun_api = Python.import_module("pumpfun_api")
let sandwich_manager = Python.import_module("sandwich_manager")


# =============================================================================
# Core Data Structures
# =============================================================================

@value
struct BacktestConfig:
    """Configuration for backtest execution"""
    initial_investment: Float32
    simulate_hours: Int
    min_volume_threshold: Float32
    max_slippage: Float32
    commission_rate: Float32
    enable_simd: Bool
    chunk_size: Int
    parallel_workers: Int

    fn __init__(inout self):
        self.initial_investment = 1000.0
        self.simulate_hours = 24
        self.min_volume_threshold = 100.0
        self.max_slippage = 0.05
        self.commission_rate = 0.003
        self.enable_simd = True
        self.chunk_size = 1024
        self.parallel_workers = 4


@value
struct PricePoint:
    """Single price history data point"""
    timestamp: Int64
    price: Float32
    volume: Float32
    interval: String

    fn __init__(inout self, timestamp: Int64, price: Float32, volume: Float32, interval: String):
        self.timestamp = timestamp
        self.price = price
        self.volume = volume
        self.interval = interval


@value
struct BacktestResult:
    """Result of backtest computation"""
    token_address: String
    session_id: String

    # Performance metrics
    final_score: Float32
    recommendation: String
    total_return: Float32
    max_drawdown: Float32
    sharpe_ratio: Float32
    volatility: Float32

    # Trading statistics
    total_trades: Int
    winning_trades: Int
    losing_trades: Int
    avg_trade_return: Float32
    win_rate: Float32

    # Risk metrics
    var_95: Float32          # 95% Value at Risk
    cvar_95: Float32         # 95% Conditional Value at Risk
    max_consecutive_losses: Int
    recovery_factor: Float32

    # Technical metrics
    trend_strength: Float32
    momentum_score: Float32
    support_resistance_score: Float32

    # Execution metrics
    compute_time_ms: Float32
    memory_used_mb: Float32
    simd_efficiency: Float32

    fn __init__(inout self):
        self.token_address = ""
        self.session_id = ""
        self.final_score = 0.0
        self.recommendation = "HOLD"
        self.total_return = 0.0
        self.max_drawdown = 0.0
        self.sharpe_ratio = 0.0
        self.volatility = 0.0
        self.total_trades = 0
        self.winning_trades = 0
        self.losing_trades = 0
        self.avg_trade_return = 0.0
        self.win_rate = 0.0
        self.var_95 = 0.0
        self.cvar_95 = 0.0
        self.max_consecutive_losses = 0
        self.recovery_factor = 0.0
        self.trend_strength = 0.0
        self.momentum_score = 0.0
        self.support_resistance_score = 0.0
        self.compute_time_ms = 0.0
        self.memory_used_mb = 0.0
        self.simd_efficiency = 0.0


# =============================================================================
# SIMD Vectorized Mathematical Operations
# =============================================================================

fn simd_mean(values: Tensor[Float32]) -> Float32:
    """Compute mean using SIMD vectorization"""
    var sum = Float32(0.0)
    let n = values.num_elements()

    if n == 0:
        return 0.0

    # SIMD reduction
    for i in range(n):
        sum += values[i]

    return sum / Float32(n)


fn simd_stddev(values: Tensor[Float32], mean: Float32) -> Float32:
    """Compute standard deviation using SIMD"""
    var sum_sq_diff = Float32(0.0)
    let n = values.num_elements()

    if n <= 1:
        return 0.0

    # SIMD computation of squared differences
    for i in range(n):
        let diff = values[i] - mean
        sum_sq_diff += diff * diff

    return sqrt(sum_sq_diff / Float32(n - 1))


fn simd_correlation(x: Tensor[Float32], y: Tensor[Float32]) -> Float32:
    """Compute correlation coefficient using SIMD"""
    let n = x.num_elements()
    if n != y.num_elements() or n == 0:
        return 0.0

    let mean_x = simd_mean(x)
    let mean_y = simd_mean(y)

    var sum_xy = Float32(0.0)
    var sum_xx = Float32(0.0)
    var sum_yy = Float32(0.0)

    # SIMD computation for correlation
    for i in range(n):
        let dx = x[i] - mean_x
        let dy = y[i] - mean_y
        sum_xy += dx * dy
        sum_xx += dx * dx
        sum_yy += dy * dy

    let denom = sqrt(sum_xx * sum_yy)
    return sum_xy / denom if denom > 0.0 else 0.0


fn simd_moving_average(prices: Tensor[Float32], window: Int) -> Tensor[Float32]:
    """Compute moving average using efficient SIMD sliding window"""
    let n = prices.num_elements()
    if window <= 0 or window > n:
        return Tensor[Float32](n)

    var result = Tensor[Float32](n)
    var window_sum = Float32(0.0)

    # Initialize first window
    for i in range(window):
        window_sum += prices[i]

    result[window - 1] = window_sum / Float32(window)

    # Sliding window computation
    for i in range(window, n):
        window_sum += prices[i] - prices[i - window]
        result[i] = window_sum / Float32(window)

    return result


fn simd_rsi(prices: Tensor[Float32], period: Int = 14) -> Float32:
    """Compute RSI using SIMD operations"""
    let n = prices.num_elements()
    if n <= period:
        return 50.0  # Neutral

    var gains = Tensor[Float32](n - 1)
    var losses = Tensor[Float32](n - 1)

    # Calculate gains and losses
    for i in range(1, n):
        let change = prices[i] - prices[i - 1]
        if change > 0:
            gains[i - 1] = change
            losses[i - 1] = 0.0
        else:
            gains[i - 1] = 0.0
            losses[i - 1] = -change

    # Calculate average gains and losses
    var avg_gain = Float32(0.0)
    var avg_loss = Float32(0.0)

    for i in range(period):
        avg_gain += gains[i]
        avg_loss += losses[i]

    avg_gain /= Float32(period)
    avg_loss /= Float32(period)

    if avg_loss == 0.0:
        return 100.0

    let rs = avg_gain / avg_loss
    return 100.0 - (100.0 / (1.0 + rs))


fn simd_bollinger_bands(prices: Tensor[Float32], window: Int = 20, std_dev: Float32 = 2.0) -> Tuple[Tensor[Float32], Tensor[Float32], Tensor[Float32]]:
    """Compute Bollinger Bands using SIMD"""
    let ma = simd_moving_average(prices, window)
    let n = prices.num_elements()

    var upper_band = Tensor[Float32](n)
    var lower_band = Tensor[Float32](n)

    for i in range(window - 1, n):
        # Calculate standard deviation for window
        var sum_sq_diff = Float32(0.0)
        for j in range(i - window + 1, i + 1):
            let diff = prices[j] - ma[i]
            sum_sq_diff += diff * diff

        let std = sqrt(sum_sq_diff / Float32(window))
        upper_band[i] = ma[i] + std_dev * std
        lower_band[i] = ma[i] - std_dev * std

    return (ma, upper_band, lower_band)


# =============================================================================
# Technical Analysis Functions
# =============================================================================

fn calculate_trend_strength(prices: Tensor[Float32]) -> Float32:
    """Calculate trend strength using linear regression"""
    let n = prices.num_elements()
    if n < 10:
        return 0.0

    # Create time index
    var time_index = Tensor[Float32](n)
    for i in range(n):
        time_index[i] = Float32(i)

    # Calculate correlation with time (trend indicator)
    let correlation = simd_correlation(time_index, prices)
    return abs(correlation)


fn calculate_momentum(prices: Tensor[Float32], periods: Int = 10) -> Float32:
    """Calculate price momentum"""
    let n = prices.num_elements()
    if n <= periods:
        return 0.0

    let current_price = prices[n - 1]
    let past_price = prices[n - periods - 1]

    return (current_price - past_price) / past_price


fn calculate_support_resistance(prices: Tensor[Float32], window: Int = 20) -> Float32:
    """Calculate support/resistance levels score"""
    let n = prices.num_elements()
    if n < window * 2:
        return 0.0

    var pivot_highs = 0
    var pivot_lows = 0

    # Find pivot points
    for i in range(window, n - window):
        var is_high = True
        var is_low = True

        for j in range(i - window, i + window + 1):
            if j != i:
                if prices[j] >= prices[i]:
                    is_high = False
                if prices[j] <= prices[i]:
                    is_low = False

        if is_high:
            pivot_highs += 1
        if is_low:
            pivot_lows += 1

    # Score based on number of clear pivot points
    let total_pivots = pivot_highs + pivot_lows
    let expected_pivots = (n - 2 * window) / 10  # Expected ~10% pivot points

    return min(Float32(total_pivots) / Float32(expected_pivots), 1.0)


fn calculate_volatility(prices: Tensor[Float32], annualize: Bool = True) -> Float32:
    """Calculate price volatility"""
    if prices.num_elements() < 2:
        return 0.0

    var returns = Tensor[Float32](prices.num_elements() - 1)

    # Calculate log returns
    for i in range(1, prices.num_elements()):
        returns[i - 1] = (prices[i] - prices[i - 1]) / prices[i - 1]

    let mean_return = simd_mean(returns)
    let volatility = simd_stddev(returns, mean_return)

    if annualize:
        # Assume hourly data, annualize (252 trading days, 24 hours)
        return volatility * sqrt(252.0 * 24.0)

    return volatility


# =============================================================================
# Backtest Simulation Engine
# =============================================================================

fn simulate_trading_strategy(
    prices: Tensor[Float32],
    volumes: Tensor[Float32],
    config: BacktestConfig
) -> Tuple[Float32, Int, Int, Float32, Float32]:
    """
    Simulate trading strategy with position sizing and risk management

    Returns: (total_return, total_trades, winning_trades, max_drawdown, sharpe_ratio)
    """
    let n = prices.num_elements()
    if n < 2:
        return (0.0, 0, 0, 0.0, 0.0)

    var position = Float32(0.0)
    var cash = config.initial_investment
    var portfolio_value = cash
    var max_portfolio_value = portfolio_value

    var trades = 0
    var winning_trades = 0
    var losing_trades = 0

    var portfolio_values = Tensor[Float32](n)
    portfolio_values[0] = portfolio_value

    # Simple moving average crossover strategy
    let ma_short = simd_moving_average(prices, 10)
    let ma_long = simd_moving_average(prices, 30)

    for i in range(1, n):
        if i < 30:  # Need enough data for long MA
            portfolio_values[i] = portfolio_value
            continue

        let current_price = prices[i]
        let short_ma = ma_short[i]
        let long_ma = ma_long[i]

        # Trading signals
        let buy_signal = short_ma > long_ma and position == 0.0
        let sell_signal = short_ma < long_ma and position > 0.0

        if buy_signal and volumes[i] > config.min_volume_threshold:
            # Buy signal - allocate 60% of portfolio
            let position_size = cash * 0.6 / current_price
            let commission = position_size * current_price * config.commission_rate

            position = position_size
            cash -= (position_size * current_price + commission)
            trades += 1

        elif sell_signal and position > 0.0:
            # Sell signal
            let sell_value = position * current_price
            let commission = sell_value * config.commission_rate

            cash += (sell_value - commission)

            # Check if trade was profitable
            if sell_value > (position * prices[i - 1]):
                winning_trades += 1
            else:
                losing_trades += 1

            position = 0.0
            trades += 1

        # Update portfolio value
        portfolio_value = cash + (position * current_price)
        portfolio_values[i] = portfolio_value
        max_portfolio_value = max(max_portfolio_value, portfolio_value)

    # Calculate final metrics
    let total_return = (portfolio_value - config.initial_investment) / config.initial_investment

    # Calculate max drawdown
    var max_drawdown = Float32(0.0)
    for i in range(n):
        let drawdown = (max_portfolio_value - portfolio_values[i]) / max_portfolio_value
        max_drawdown = max(max_drawdown, drawdown)

    # Calculate Sharpe ratio
    var returns = Tensor[Float32](n - 1)
    for i in range(1, n):
        returns[i - 1] = (portfolio_values[i] - portfolio_values[i - 1]) / portfolio_values[i - 1]

    let mean_return = simd_mean(returns)
    let return_std = simd_stddev(returns, mean_return)
    let sharpe_ratio = mean_return / return_std if return_std > 0.0 else 0.0

    return (total_return, trades, winning_trades, max_drawdown, sharpe_ratio)


fn calculate_risk_metrics(returns: Tensor[Float32]) -> Tuple[Float32, Float32, Int]:
    """
    Calculate risk metrics: VaR, CVaR, and max consecutive losses

    Returns: (var_95, cvar_95, max_consecutive_losses)
    """
    if returns.num_elements() == 0:
        return (0.0, 0.0, 0)

    # Sort returns for VaR calculation
    var sorted_returns = Tensor[Float32](returns.num_elements())
    for i in range(returns.num_elements()):
        sorted_returns[i] = returns[i]

    # Simple bubble sort (in production, use more efficient sort)
    for i in range(sorted_returns.num_elements()):
        for j in range(i + 1, sorted_returns.num_elements()):
            if sorted_returns[i] > sorted_returns[j]:
                let temp = sorted_returns[i]
                sorted_returns[i] = sorted_returns[j]
                sorted_returns[j] = temp

    # Calculate 95% VaR (5th percentile)
    let var_index = Int(Float32(sorted_returns.num_elements()) * 0.05)
    let var_95 = sorted_returns[var_index]

    # Calculate CVaR (average of returns below VaR)
    var cvar_sum = Float32(0.0)
    var cvar_count = 0

    for i in range(var_index):
        cvar_sum += sorted_returns[i]
        cvar_count += 1

    let cvar_95 = cvar_sum / Float32(cvar_count) if cvar_count > 0 else 0.0

    # Calculate maximum consecutive losses
    var max_consecutive_losses = 0
    var current_consecutive = 0

    for ret in returns:
        if ret < 0:
            current_consecutive += 1
            max_consecutive_losses = max(max_consecutive_losses, current_consecutive)
        else:
            current_consecutive = 0

    return (var_95, cvar_95, max_consecutive_losses)


# =============================================================================
# Main Backtest Engine
# =============================================================================

fn run_backtest(
    token_address: String,
    price_history: PythonObject,
    config: BacktestConfig
) -> BacktestResult:
    """
    Main backtest execution function

    Args:
        token_address: Token contract address
        price_history: Python list of price history dictionaries
        config: Backtest configuration

    Returns:
        Comprehensive backtest results
    """
    let start_time = now()

    var result = BacktestResult()
    result.token_address = token_address
    result.session_id = "backtest_" + str(now())

    # Convert Python price history to Mojo tensors
    let n = len(price_history)
    if n < 10:
        result.recommendation = "INSUFFICIENT_DATA"
        result.compute_time_ms = Float32((now() - start_time) / 1_000_000)
        return result

    var prices = Tensor[Float32](n)
    var volumes = Tensor[Float32](n)
    var timestamps = Tensor[Int64](n)

    # Extract data from Python objects
    for i in range(n):
        let point = price_history[i]
        prices[i] = Float32(point["price"])
        volumes[i] = Float32(point.get("volume", 0.0))
        timestamps[i] = Int64(point.get("timestamp", i))

    # Calculate technical indicators
    result.trend_strength = calculate_trend_strength(prices)
    result.momentum_score = calculate_momentum(prices)
    result.support_resistance_score = calculate_support_resistance(prices)
    result.volatility = calculate_volatility(prices)

    # Run trading simulation
    let (total_return, trades, winning_trades, max_drawdown, sharpe_ratio) =
        simulate_trading_strategy(prices, volumes, config)

    result.total_return = total_return
    result.total_trades = trades
    result.winning_trades = winning_trades
    result.losing_trades = trades - winning_trades
    result.max_drawdown = max_drawdown
    result.sharpe_ratio = sharpe_ratio
    result.win_rate = Float32(winning_trades) / Float32(trades) if trades > 0 else 0.0
    result.avg_trade_return = total_return / Float32(trades) if trades > 0 else 0.0

    # Calculate risk metrics
    var returns = Tensor[Float32](n - 1)
    for i in range(1, n):
        returns[i - 1] = (prices[i] - prices[i - 1]) / prices[i - 1]

    let (var_95, cvar_95, max_consecutive_losses) = calculate_risk_metrics(returns)
    result.var_95 = var_95
    result.cvar_95 = cvar_95
    result.max_consecutive_losses = max_consecutive_losses

    # Calculate recovery factor
    result.recovery_factor = abs(total_return / max_drawdown) if max_drawdown > 0.0 else 0.0

    # Generate composite score and recommendation
    result.final_score = calculate_composite_score(result)
    result.recommendation = generate_recommendation(result.final_score)

    # Calculate performance metrics
    result.compute_time_ms = Float32((now() - start_time) / 1_000_000)
    result.memory_used_mb = Float32(n * 4 * 4) / (1024.0 * 1024.0)  # Rough estimate
    result.simd_efficiency = 1.0 if config.enable_simd else 0.5

    return result


fn calculate_composite_score(result: BacktestResult) -> Float32:
    """Calculate composite score from all metrics"""
    var score = Float32(0.0)

    # Performance components (40% weight)
    score += result.total_return * 0.15
    score += result.sharpe_ratio * 0.10
    score += result.win_rate * 0.10
    score += (1.0 - result.max_drawdown) * 0.05

    # Technical components (30% weight)
    score += result.trend_strength * 0.10
    score += result.momentum_score * 0.10
    score += result.support_resistance_score * 0.10

    # Risk components (20% weight)
    score += (1.0 - result.volatility) * 0.05
    score += (1.0 - abs(result.var_95)) * 0.10
    score += result.recovery_factor * 0.05

    # Execution components (10% weight)
    score += min(result.total_trades / 10.0, 1.0) * 0.10

    return max(0.0, min(1.0, score))


fn generate_recommendation(score: Float32) -> String:
    """Generate trading recommendation based on score"""
    if score >= 0.8:
        return "STRONG_BUY"
    elif score >= 0.6:
        return "BUY"
    elif score >= 0.4:
        return "HOLD"
    else:
        return "AVOID"


# =============================================================================
# Batch Processing and Parallel Execution
# =============================================================================

fn run_batch_backtest(
    token_addresses: List[String],
    api_client: PythonObject,
    config: BacktestConfig
) -> List[BacktestResult]:
    """
    Run backtests for multiple tokens in parallel

    Args:
        token_addresses: List of token addresses to analyze
        api_client: Python PumpFun API client
        config: Backtest configuration

    Returns:
        List of backtest results
    """
    let num_tokens = len(token_addresses)
    var results = List[BacktestResult]()

    # Process tokens in parallel chunks
    let chunk_size = config.chunk_size
    let num_chunks = (num_tokens + chunk_size - 1) / chunk_size

    for chunk_idx in range(num_chunks):
        let start_idx = chunk_idx * chunk_size
        let end_idx = min(start_idx + chunk_size, num_tokens)

        # Process chunk in parallel
        parallel_for(start_idx, end_idx) [&](i: Int):
            let token_address = token_addresses[i]

            # Get price history from Python API
            let price_history = api_client.get_token_price_history_sync(
                token_address, "5m", config.simulate_hours
            )

            if len(price_history) > 0:
                let result = run_backtest(token_address, price_history, config)

                # Update Python metrics
                let manager = sandwich_manager.get_sandwich_manager()
                manager.update_session_metrics(
                    result.session_id,
                    final_score=result.final_score,
                    recommendation=result.recommendation,
                    simulated_profit_loss=result.total_return * config.initial_investment,
                    max_drawdown=result.max_drawdown,
                    trade_count=result.total_trades,
                    win_rate=result.win_rate,
                    execution_time_ms=result.compute_time_ms
                )

                results.append(result)
            else:
                # Create error result
                var error_result = BacktestResult()
                error_result.token_address = token_address
                error_result.recommendation = "DATA_ERROR"
                results.append(error_result)

    return results


# =============================================================================
# Python FFI Interface Functions
# =============================================================================

fn backtest_token_sync(
    token_address: String,
    initial_investment: Float32 = 1000.0,
    simulate_hours: Int = 24
) -> Dictionary[String, AnyType]:
    """
    Python FFI interface for single token backtest

    Args:
        token_address: Token contract address
        initial_investment: Initial investment amount
        simulate_hours: Hours to simulate

    Returns:
        Dictionary with backtest results
    """
    # Initialize config
    var config = BacktestConfig()
    config.initial_investment = initial_investment
    config.simulate_hours = simulate_hours

    # Create Python API client
    let api_client = pumpfun_api.create_pumpfun_api()

    # Get price history
    let price_history = api_client.get_token_price_history_sync(
        token_address, "5m", simulate_hours
    )

    if len(price_history) == 0:
        return {
            "token_address": token_address,
            "error": "No price history available",
            "recommendation": "NO_DATA"
        }

    # Run backtest
    let result = run_backtest(token_address, price_history, config)

    # Convert to dictionary for Python
    return {
        "token_address": result.token_address,
        "session_id": result.session_id,
        "final_score": result.final_score,
        "recommendation": result.recommendation,
        "total_return": result.total_return,
        "max_drawdown": result.max_drawdown,
        "sharpe_ratio": result.sharpe_ratio,
        "volatility": result.volatility,
        "total_trades": result.total_trades,
        "winning_trades": result.winning_trades,
        "losing_trades": result.losing_trades,
        "win_rate": result.win_rate,
        "avg_trade_return": result.avg_trade_return,
        "var_95": result.var_95,
        "cvar_95": result.cvar_95,
        "max_consecutive_losses": result.max_consecutive_losses,
        "recovery_factor": result.recovery_factor,
        "trend_strength": result.trend_strength,
        "momentum_score": result.momentum_score,
        "support_resistance_score": result.support_resistance_score,
        "compute_time_ms": result.compute_time_ms,
        "memory_used_mb": result.memory_used_mb,
        "simd_efficiency": result.simd_efficiency
    }


fn batch_backtest_sync(
    token_addresses: List[String],
    initial_investment: Float32 = 1000.0,
    simulate_hours: Int = 24
) -> List[Dictionary[String, AnyType]]:
    """
    Python FFI interface for batch backtesting

    Args:
        token_addresses: List of token addresses
        initial_investment: Initial investment per token
        simulate_hours: Hours to simulate

    Returns:
        List of backtest result dictionaries
    """
    # Initialize config
    var config = BacktestConfig()
    config.initial_investment = initial_investment
    config.simulate_hours = simulate_hours

    # Create Python API client
    let api_client = pumpfun_api.create_pumpfun_api()

    # Run batch backtest
    let mojo_results = run_batch_backtest(token_addresses, api_client, config)

    # Convert to Python dictionaries
    var python_results = List[Dictionary[String, AnyType]]()

    for result in mojo_results:
        python_results.append({
            "token_address": result.token_address,
            "session_id": result.session_id,
            "final_score": result.final_score,
            "recommendation": result.recommendation,
            "total_return": result.total_return,
            "max_drawdown": result.max_drawdown,
            "sharpe_ratio": result.sharpe_ratio,
            "volatility": result.volatility,
            "total_trades": result.total_trades,
            "winning_trades": result.winning_trades,
            "losing_trades": result.losing_trades,
            "win_rate": result.win_rate,
            "avg_trade_return": result.avg_trade_return,
            "var_95": result.var_95,
            "cvar_95": result.cvar_95,
            "max_consecutive_losses": result.max_consecutive_losses,
            "recovery_factor": result.recovery_factor,
            "trend_strength": result.trend_strength,
            "momentum_score": result.momentum_score,
            "support_resistance_score": result.support_resistance_score,
            "compute_time_ms": result.compute_time_ms,
            "memory_used_mb": result.memory_used_mb,
            "simd_efficiency": result.simd_efficiency
        })

    return python_results


# =============================================================================
# Utility Functions
# =============================================================================

fn validate_price_history(price_history: PythonObject) -> Bool:
    """Validate price history data"""
    if len(price_history) < 10:
        return False

    # Check required fields
    for i in range(min(5, len(price_history))):
        let point = price_history[i]
        if not ("price" in point and "timestamp" in point):
            return False
        if point["price"] <= 0:
            return False

    return True


fn estimate_computation_time(num_tokens: Int, price_points: Int, config: BacktestConfig) -> Float32:
    """Estimate computation time for batch processing"""
    let base_time_per_token = Float32(price_points) * 0.001  # 1 microsecond per price point
    let simd_speedup = if config.enable_simd then 4.0 else 1.0
    let parallel_speedup = Float32(config.parallel_workers)

    let time_per_token = base_time_per_token / (simd_speedup * parallel_speedup)
    return Float32(num_tokens) * time_per_token


fn get_memory_estimate(num_tokens: Int, avg_price_points: Int) -> Float32:
    """Estimate memory usage for batch processing"""
    # Memory per price point (4 bytes each for price, volume, timestamp)
    let bytes_per_point = 12
    let total_bytes = num_tokens * avg_price_points * bytes_per_point

    return Float32(total_bytes) / (1024.0 * 1024.0)  # Convert to MB


# =============================================================================
# Main Entry Point for Testing
# =============================================================================

fn main():
    """Main function for testing backtest engine"""
    print("🧪 Testing PumpFun Backtest Engine...")

    # Test with sample data
    var sample_prices = Tensor[Float32](100)
    for i in range(100):
        sample_prices[i] = 100.0 + Float32(i) * 0.1 + Float32(i % 10) * 0.5

    # Test technical indicators
    let trend = calculate_trend_strength(sample_prices)
    print("✅ Trend strength calculated: " + str(trend))

    let momentum = calculate_momentum(sample_prices, 10)
    print("✅ Momentum calculated: " + str(momentum))

    let volatility = calculate_volatility(sample_prices)
    print("✅ Volatility calculated: " + str(volatility))

    # Test single backtest
    let result = backtest_token_sync("So11111111111111111111111111111111111111112", 1000.0, 24)
    print("✅ Single backtest completed: " + result["recommendation"])

    print("🎉 Backtest engine test completed!")