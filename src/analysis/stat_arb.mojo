# Mojo Statistical Arbitrage Engine
# High-performance pairs trading with Rust FFI integration

from memory.unsafe import Pointer
from tensor import Tensor
from time import now
from sys import get_module
from python import Python
from math import sqrt, abs, exp, log, pow
from collections import Dict

# FFI externs to Rust statistical arbitrage functions
fn stat_arb_test_cointegration(
    prices_a: Pointer[DType.float64],
    prices_b: Pointer[DType.float64],
    len: Int,
    out_hedge_ratio: Pointer[DType.float64],
    out_p_value: Pointer[DType.float64]
) -> Int

fn stat_arb_calculate_spread(
    prices_a: Pointer[DType.float64],
    prices_b: Pointer[DType.float64],
    len: Int,
    hedge_ratio: DType.float64,
    out_spread: Pointer[DType.float64]
) -> Int

fn stat_arb_calculate_z_scores_batch(
    values: Pointer[DType.float64],
    len: Int,
    mean: DType.float64,
    std: DType.float64,
    out_z_scores: Pointer[DType.float64]
) -> Int

fn stat_arb_calculate_hurst_exponent(
    prices: Pointer[DType.float64],
    len: Int,
    out_hurst: Pointer[DType.float64]
) -> Int

fn stat_arb_calculate_half_life(
    spread: Pointer[DType.float64],
    len: Int,
    out_half_life: Pointer[DType.float64]
) -> Int

fn stat_arb_calculate_mean(
    values: Pointer[DType.float64],
    len: Int,
    out_mean: Pointer[DType.float64]
) -> Int

fn stat_arb_calculate_std(
    values: Pointer[DType.float64],
    len: Int,
    mean: DType.float64,
    out_std: Pointer[DType.float64]
) -> Int

# Price history for a trading pair
@value
struct PairPriceHistory:
    var token_a: String
    var token_b: String
    var timestamps: Tensor[DType.float64]
    var prices_a: Tensor[DType.float64]
    var prices_b: Tensor[DType.float64]
    var max_points: Int
    var last_update: Int

    fn __init__(inout self, token_a: String, token_b: String, max_points: Int = 1000):
        self.token_a = token_a
        self.token_b = token_b
        self.timestamps = Tensor[DType.float64]()
        self.prices_a = Tensor[DType.float64]()
        self.prices_b = Tensor[DType.float64]()
        self.max_points = max_points
        self.last_update = 0

    fn add_prices(inout self, timestamp: Int, price_a: DType.float64, price_b: DType.float64):
        """Add new price data point"""
        # Add new data
        self.timestamps.append(DType.float64(timestamp))
        self.prices_a.append(price_a)
        self.prices_b.append(price_b)

        # Maintain maximum history length
        if self.timestamps.size() > self.max_points:
            self.timestamps = self.timestamps[-self.max_points:]
            self.prices_a = self.prices_a[-self.max_points:]
            self.prices_b = self.prices_b[-self.max_points:]

        self.last_update = timestamp

    fn get_history_length(self) -> Int:
        """Get current history length"""
        return self.timestamps.size()

    fn is_sufficient_history(self, min_length: Int = 50) -> Bool:
        """Check if we have sufficient history for analysis"""
        return self.get_history_length() >= min_length

# Cointegration test result
@value
struct CointegrationResult:
    var is_cointegrated: Bool
    var hedge_ratio: DType.float64
    var p_value: DType.float64
    var test_time_ns: DType.float64
    var cache_time: Int

    fn __init__(inout self, is_cointegrated: Bool = False, hedge_ratio: DType.float64 = 0.0,
               p_value: DType.float64 = 1.0, test_time_ns: DType.float64 = 0.0, cache_time: Int = 0):
        self.is_cointegrated = is_cointegrated
        self.hedge_ratio = hedge_ratio
        self.p_value = p_value
        self.test_time_ns = test_time_ns
        self.cache_time = cache_time

    fn is_valid(self) -> Bool:
        """Check if cointegration result is valid"""
        return self.hedge_ratio > 0.0 and self.p_value >= 0.0 and self.p_value <= 1.0

    fn is_significant(self, significance_level: DType.float64 = 0.05) -> Bool:
        """Check if cointegration is statistically significant"""
        return self.is_cointegrated and self.p_value <= significance_level

# Statistical arbitrage trading signal
@value
struct StatArbSignal:
    var signal_type: String      # "LONG_SPREAD", "SHORT_SPREAD", "EXIT", "HOLD"
    var z_score: DType.float64
    var confidence: DType.float64
    var hedge_ratio: DType.float64
    var hurst_exponent: DType.float64
    var half_life: DType.float64
    var entry_threshold: DType.float64
    var exit_threshold: DType.float64
    var stop_loss_threshold: DType.float64
    var calculation_time_ns: DType.float64
    var timestamp: Int

    fn __init__(inout self, signal_type: String = "HOLD"):
        self.signal_type = signal_type
        self.z_score = 0.0
        self.confidence = 0.0
        self.hedge_ratio = 1.0
        self.hurst_exponent = 0.5
        self.half_life = 24.0
        self.entry_threshold = 2.0
        self.exit_threshold = 0.5
        self.stop_loss_threshold = 3.0
        self.calculation_time_ns = 0.0
        self.timestamp = now()

    fn is_entry_signal(self) -> Bool:
        """Check if signal is an entry signal"""
        return self.signal_type == "LONG_SPREAD" or self.signal_type == "SHORT_SPREAD"

    fn is_exit_signal(self) -> Bool:
        """Check if signal is an exit signal"""
        return self.signal_type == "EXIT"

    fn should_trade(self) -> Bool:
        """Check if signal should generate a trade"""
        return self.is_entry_signal() and self.confidence > 0.6

# Main statistical arbitrage engine
struct StatArbEngine:
    var entry_z_threshold: DType.float64
    var exit_z_threshold: DType.float64
    var stop_loss_z_threshold: DType.float64
    var min_history_points: Int
    var max_history_points: Int
    var cointegration_significance: DType.float64
    var cointegration_cache_hours: Int
    var min_correlation: DType.float64
    var max_correlation: DType.float64
    var min_profit_bps: DType.float64
    var max_position_size_pct: DType.float64

    # Internal state
    var price_histories: Dict[String, PairPriceHistory]
    var cointegration_cache: Dict[String, CointegrationResult]
    var last_cache_cleanup: Int

    fn __init__(inout self):
        # Default parameters
        self.entry_z_threshold = 2.0
        self.exit_z_threshold = 0.5
        self.stop_loss_z_threshold = 3.0
        self.min_history_points = 50
        self.max_history_points = 1000
        self.cointegration_significance = 0.05
        self.cointegration_cache_hours = 24
        self.min_correlation = 0.7
        self.max_correlation = 0.95
        self.min_profit_bps = 10.0
        self.max_position_size_pct = 0.2

        # Initialize internal state
        self.price_histories = Dict[String, PairPriceHistory]()
        self.cointegration_cache = Dict[String, CointegrationResult]()
        self.last_cache_cleanup = now()

    fn update_pair_history(inout self, token_a: String, token_b: String,
                          timestamp: Int, price_a: DType.float64, price_b: DType.float64):
        """Update price history for a trading pair"""
        # Create pair key (sorted for consistency)
        var pair_key = token_a + "-" + token_b
        if token_a > token_b:
            pair_key = token_b + "-" + token_a
            # Swap prices if needed
            var temp = price_a
            price_a = price_b
            price_b = temp

        # Get or create price history
        if not self.price_histories.contains(pair_key):
            self.price_histories[pair_key] = PairPriceHistory(
                token_a if token_a < token_b else token_b,
                token_b if token_a < token_b else token_a,
                self.max_history_points
            )

        # Add new price data
        self.price_histories[pair_key].add_prices(timestamp, price_a, price_b)

    def get_pair_history(self, token_a: String, token_b: String) -> PairPriceHistory:
        """Get price history for a trading pair"""
        var pair_key = token_a + "-" + token_b
        if token_a > token_b:
            pair_key = token_b + "-" + token_a

        if self.price_histories.contains(pair_key):
            return self.price_histories[pair_key]
        else:
            return PairPriceHistory(token_a, token_b, self.max_history_points)

    fn test_cointegration_with_cache(inout self, token_a: String, token_b: String) -> CointegrationResult:
        """Test cointegration with caching"""
        var pair_key = token_a + "-" + token_b
        if token_a > token_b:
            pair_key = token_b + "-" + token_a

        var current_time = now()
        var cache_hours = (current_time - self.last_cache_cleanup) / 3600000000000  # Convert to hours

        # Check cache
        if self.cointegration_cache.contains(pair_key):
            var cached = self.cointegration_cache[pair_key]
            var age_hours = (current_time - cached.cache_time) / 3600000000000
            if age_hours < self.cointegration_cache_hours:
                return cached

        # Get price history
        var history = self.get_pair_history(token_a, token_b)
        if not history.is_sufficient_history(self.min_history_points):
            return CointegrationResult(False, 0.0, 1.0, 0.0, current_time)

        # Perform cointegration test
        var len = history.get_history_length()
        var hedge_ratio = 0.0
        var p_value = 1.0

        var start_time = now()
        var result = stat_arb_test_cointegration(
            history.prices_a.data(),
            history.prices_b.data(),
            len,
            Pointer[DType.float64].address_of(hedge_ratio),
            Pointer[DType.float64].address_of(p_value)
        )
        var test_time = DType.float64(now() - start_time)

        var is_cointegrated = (result == 0) and (p_value <= self.cointegration_significance)

        # Cache result
        var coint_result = CointegrationResult(is_cointegrated, hedge_ratio, p_value, test_time, current_time)
        self.cointegration_cache[pair_key] = coint_result

        # Cleanup old cache entries periodically
        if cache_hours > 1.0:
            self._cleanup_cache()

        return coint_result

    fn _cleanup_cache(inout self):
        """Clean up old cache entries"""
        var current_time = now()
        var keys_to_remove = List[String]()

        for (key, value) in self.cointegration_cache.items():
            var age_hours = (current_time - value.cache_time) / 3600000000000
            if age_hours > self.cointegration_cache_hours * 2:
                keys_to_remove.append(key)

        for key in keys_to_remove:
            self.cointegration_cache.remove(key)

        self.last_cache_cleanup = current_time

    fn calculate_spread_and_zscores(self, token_a: String, token_b: String, hedge_ratio: DType.float64) -> (Tensor[DType.float64], Tensor[DType.float64]):
        """Calculate spread and z-scores for a pair"""
        var history = self.get_pair_history(token_a, token_b)
        if not history.is_sufficient_history(self.min_history_points):
            return Tensor[DType.float64](), Tensor[DType.float64]()

        var len = history.get_history_length()
        var spread = Tensor[DType.float64](len)

        # Calculate spread using FFI
        var result = stat_arb_calculate_spread(
            history.prices_a.data(),
            history.prices_b.data(),
            len,
            hedge_ratio,
            spread.data()
        )

        if result != 0:
            # Fallback to scalar calculation
            for i in range(len):
                spread[i] = history.prices_b[i] - hedge_ratio * history.prices_a[i]

        # Calculate mean and standard deviation
        var mean = 0.0
        var std = 0.0

        var mean_result = stat_arb_calculate_mean(
            spread.data(),
            len,
            Pointer[DType.float64].address_of(mean)
        )

        if mean_result == 0:
            var std_result = stat_arb_calculate_std(
                spread.data(),
                len,
                mean,
                Pointer[DType.float64].address_of(std)
            )
        else:
            # Fallback scalar calculation
            mean = spread.sum() / DType.float64(len)
            var variance = 0.0
            for i in range(len):
                variance += pow(spread[i] - mean, 2)
            std = sqrt(variance / DType.float64(len))

        # Calculate z-scores
        var z_scores = Tensor[DType.float64](len)
        if std > 0.0:
            var z_result = stat_arb_calculate_z_scores_batch(
                spread.data(),
                len,
                mean,
                std,
                z_scores.data()
            )

            if result != 0:
                # Fallback scalar calculation
                for i in range(len):
                    z_scores[i] = (spread[i] - mean) / std
        else:
            z_scores.fill(0.0)

        return spread, z_scores

    fn calculate_mean_reversion_metrics(self, spread: Tensor[DType.float64]) -> (DType.float64, DType.float64):
        """Calculate Hurst exponent and half-life for spread"""
        if spread.size() < 20:
            return 0.5, 24.0  # Default values

        var len = spread.size()
        var hurst = 0.5
        var half_life = 24.0

        # Calculate Hurst exponent
        var hurst_result = stat_arb_calculate_hurst_exponent(
            spread.data(),
            len,
            Pointer[DType.float64].address_of(hurst)
        )

        # Calculate half-life
        var half_life_result = stat_arb_calculate_half_life(
            spread.data(),
            len,
            Pointer[DType.float64].address_of(half_life)
        )

        return hurst, half_life

    def generate_signal(inout self, token_a: String, token_b: String) -> StatArbSignal:
        """Generate statistical arbitrage signal for a pair"""
        var start_time = now()
        var signal = StatArbSignal()

        # Test cointegration
        var coint_result = self.test_cointegration_with_cache(token_a, token_b)
        if not coint_result.is_valid() or not coint_result.is_significant():
            signal.signal_type = "HOLD"
            signal.calculation_time_ns = DType.float64(now() - start_time)
            return signal

        # Calculate spread and z-scores
        var (spread, z_scores) = self.calculate_spread_and_zscores(token_a, token_b, coint_result.hedge_ratio)
        if z_scores.size() == 0:
            signal.signal_type = "HOLD"
            signal.calculation_time_ns = DType.float64(now() - start_time)
            return signal

        # Get current z-score
        var current_z = z_scores[-1]

        # Calculate mean reversion metrics
        var (hurst, half_life) = self.calculate_mean_reversion_metrics(spread)

        # Generate signal based on z-score thresholds
        if abs(current_z) >= self.stop_loss_z_threshold:
            signal.signal_type = "EXIT"  # Stop loss
            signal.confidence = 0.9
        elif abs(current_z) <= self.exit_z_threshold:
            signal.signal_type = "EXIT"  # Take profit
            signal.confidence = 0.7
        elif current_z >= self.entry_z_threshold:
            signal.signal_type = "SHORT_SPREAD"  # Spread is too high
            signal.confidence = min(1.0, (current_z - self.entry_z_threshold) / 2.0)
        elif current_z <= -self.entry_z_threshold:
            signal.signal_type = "LONG_SPREAD"   # Spread is too low
            signal.confidence = min(1.0, (abs(current_z) - self.entry_z_threshold) / 2.0)
        else:
            signal.signal_type = "HOLD"
            signal.confidence = 0.0

        # Set signal parameters
        signal.z_score = current_z
        signal.hedge_ratio = coint_result.hedge_ratio
        signal.hurst_exponent = hurst
        signal.half_life = half_life
        signal.entry_threshold = self.entry_z_threshold
        signal.exit_threshold = self.exit_z_threshold
        signal.stop_loss_threshold = self.stop_loss_z_threshold
        signal.calculation_time_ns = DType.float64(now() - start_time)
        signal.timestamp = now()

        return signal

    def get_engine_stats(self) -> Dict[String, Any]:
        """Get engine statistics"""
        var stats = Dict[String, Any]()
        stats["tracked_pairs"] = self.price_histories.size()
        stats["cached_cointegration_tests"] = self.cointegration_cache.size()
        stats["min_history_points"] = self.min_history_points
        stats["max_history_points"] = self.max_history_points
        stats["entry_z_threshold"] = self.entry_z_threshold
        stats["exit_z_threshold"] = self.exit_z_threshold
        stats["cointegration_significance"] = self.cointegration_significance
        return stats