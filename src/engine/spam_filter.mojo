# =============================================================================
# Advanced Spam Filter Module
# =============================================================================

from time import time
from collections import Dict, List, Set, Any
from core.types import TradingSignal, MarketData, RiskAnalysis, RiskLevel
from core.logger import get_logger
from core.constants import (
    WASH_TRADING_SCORE_THRESHOLD,
    PUMP_DUMP_RISK_THRESHOLD,
    MIN_UNIQUE_TRADERS,
    MAX_TOP_HOLDER_CONCENTRATION,
    MIN_LIQUIDITY_LOCK_RATIO
)

@value
struct SpamFilter:
    """
    Advanced spam filter for detecting wash trading, pump & dump, and other manipulation
    """
    var helius_client  # We'll add the type later
    var config  # We'll add the type later

    # Enhanced filtering fields
    var last_signal_times: Dict[String, Float]
    var signal_counts: Dict[String, Int]
    var MIN_VOLUME_USD: Float
    var MIN_LIQUIDITY_USD: Float
    var MIN_CONFIDENCE: Float
    var COOLDOWN_SECONDS: Float
    var MAX_SIGNALS_PER_SYMBOL: Int
    var logger

    fn __init__(helius_client, config):
        self.helius_client = helius_client
        self.config = config

        # Initialize enhanced filtering fields
        self.last_signal_times = {}
        self.signal_counts = {}

        # Load all values from configuration instead of hardcoded
        self.MIN_VOLUME_USD = config.filters.spam_min_volume_usd
        self.MIN_LIQUIDITY_USD = config.filters.spam_min_liquidity_usd
        self.MIN_CONFIDENCE = config.filters.spam_min_confidence
        self.COOLDOWN_SECONDS = config.filters.spam_cooldown_seconds
        self.MAX_SIGNALS_PER_SYMBOL = config.filters.spam_max_signals_per_symbol

        # Initialize logger
        self.logger = get_logger("SpamFilter")

        self.logger.info("spam_filter_enhanced_initialized", {
            "min_volume_usd": self.MIN_VOLUME_USD,
            "min_liquidity_usd": self.MIN_LIQUIDITY_USD,
            "min_confidence": self.MIN_CONFIDENCE,
            "cooldown_seconds": self.COOLDOWN_SECONDS,
            "max_signals_per_symbol": self.MAX_SIGNALS_PER_SYMBOL,
            "loaded_from": "config.filters.spam_*"
        })

    fn filter_signals(self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Filter out spam and low-quality signals
        """
        filtered_signals = []

        for signal in signals:
            if self._is_legitimate_signal(signal):
                filtered_signals.append(signal)
            else:
                self.logger.debug("spam_signal_rejected", symbol=signal.symbol, reason=self._get_spam_reason(signal))

        return filtered_signals

    fn _is_legitimate_signal(self, signal: TradingSignal) -> Bool:
        """
        Check if a signal is legitimate
        """
        # Basic validation
        if not self._basic_validation(signal):
            return False

        # New: Cooldown check
        if not self._check_cooldown(signal):
            return False

        # New: Signal count check
        if not self._check_signal_count(signal):
            return False

        # New: Volume quality assessment
        volume_quality = self._assess_volume_quality(signal)
        if volume_quality < self.config.filters.spam_volume_quality_threshold:
            self.logger.debug("poor_volume_quality", {
                "symbol": signal.symbol,
                "quality_score": volume_quality,
                "avg_tx_size": signal.metadata.get("avg_tx_size", 0.0),
                "volume_consistency": signal.metadata.get("volume_consistency", 0.0)
            })
            return False

        # Liquidity check
        if not self._liquidity_check(signal):
            return False

        # Volume check
        if not self._volume_check(signal):
            return False

        # Holder distribution check
        if not self._holder_distribution_check(signal):
            return False

        # Wash trading check
        if not self._wash_trading_check(signal):
            return False

        # Pump & dump pattern check
        if not self._pump_dump_check(signal):
            return False

        # Age check (avoid very new tokens)
        if not self._age_check(signal):
            return False

        # Price manipulation check
        if not self._price_manipulation_check(signal):
            return False

        return True

    fn _basic_validation(self, signal: TradingSignal) -> Bool:
        """
        Basic signal validation with enhanced thresholds
        """
        if not signal.symbol or signal.symbol == "":
            return False

        if signal.confidence < self.MIN_CONFIDENCE:  # Enhanced confidence threshold (0.70)
            return False

        if signal.liquidity < self.MIN_LIQUIDITY_USD:  # Enhanced liquidity threshold ($20k)
            return False

        if signal.volume < self.MIN_VOLUME_USD:  # Enhanced volume threshold ($10k)
            return False

        return True

    fn _check_cooldown(inout self, signal: TradingSignal) -> Bool:
        """
        Check if enough time has passed since last signal for this symbol
        """
        current_time = signal.timestamp
        last_time = self.last_signal_times.get(signal.symbol, 0.0)

        time_since_last = current_time - last_time

        if time_since_last < self.COOLDOWN_SECONDS:
            self.logger.debug("cooldown_active", {
                "symbol": signal.symbol,
                "time_since_last": time_since_last,
                "required_cooldown": self.COOLDOWN_SECONDS
            })
            return False

        # Update last signal time
        self.last_signal_times[signal.symbol] = current_time
        return True

    fn _check_signal_count(inout self, signal: TradingSignal) -> Bool:
        """
        Check if signal count exceeds maximum per symbol
        """
        current_count = self.signal_counts.get(signal.symbol, 0)

        if current_count >= self.MAX_SIGNALS_PER_SYMBOL:
            self.logger.debug("signal_limit_exceeded", {
                "symbol": signal.symbol,
                "current_count": current_count,
                "max_allowed": self.MAX_SIGNALS_PER_SYMBOL
            })
            return False

        # Increment counter
        self.signal_counts[signal.symbol] = current_count + 1
        return True

    fn _assess_volume_quality(self, signal: TradingSignal) -> Float:
        """
        Assess volume quality to detect wash trading patterns
        Returns quality score from 0.0 to 1.0
        """
        quality_score = 1.0

        # Extract transaction data
        avg_tx_size = signal.metadata.get("avg_tx_size", 0.0)
        volume_consistency = signal.metadata.get("volume_consistency", 0.0)

        # Check average transaction size (using config threshold)
        if avg_tx_size < self.config.filters.spam_avg_tx_size_threshold:
            quality_score -= 0.4

        # Check volume consistency (using config threshold)
        if volume_consistency < self.config.filters.spam_volume_consistency_threshold:
            quality_score -= 0.3

        # Check volume to liquidity ratio (using config threshold)
        if signal.liquidity > 0:
            volume_to_liquidity_ratio = signal.volume / signal.liquidity
            if volume_to_liquidity_ratio > self.config.filters.spam_volume_to_liquidity_ratio:
                quality_score -= 0.3

        return max(quality_score, 0.0)

    fn _liquidity_check(self, signal: TradingSignal) -> Bool:
        """
        Check liquidity sufficiency
        """
        # Check minimum liquidity
        if signal.liquidity < self.config.risk.min_liquidity:
            return False

        # Check liquidity depth (ratio of volume to liquidity)
        liquidity_depth = signal.volume / signal.liquidity
        if liquidity_depth > self.config.filters.spam_volume_to_liquidity_ratio:  # Using config threshold
            return False

        return True

    fn _volume_check(self, signal: TradingSignal) -> Bool:
        """
        Check volume patterns
        """
        # Check minimum volume
        if signal.volume < self.config.risk.min_volume:
            return False

        # Check for suspicious volume spikes (using config thresholds)
        # In a real implementation, we'd compare with historical volume
        # For now, we'll use basic heuristics
        if signal.volume > self.config.risk_thresholds.wash_trading_volume_threshold and signal.liquidity < self.config.risk_thresholds.wash_trading_liquidity_threshold:
            # Very high volume with low liquidity is suspicious
            return False

        return True

    fn _holder_distribution_check(self, signal: TradingSignal) -> Bool:
        """
        Check holder distribution for concentration
        """
        try:
            # Get top holders from Helius
            top_holders = self.helius_client.get_top_holders(signal.symbol, 10)

            if len(top_holders) == 0:
                return True  # Skip if data unavailable

            # Calculate concentration
            total_percentage = 0.0
            for holder in top_holders[:5]:  # Top 5 holders
                total_percentage += holder.get("percentage", 0.0)

            # Check if too concentrated
            if total_percentage > MAX_TOP_HOLDER_CONCENTRATION:
                return False

            # Check minimum unique holders
            unique_holders = len(top_holders)
            if unique_holders < MIN_UNIQUE_TRADERS:
                return False

            return True
        except e:
            print(f"⚠️  Error checking holder distribution: {e}")
            return True  # Allow if check fails

    fn _wash_trading_check(self, signal: TradingSignal) -> Bool:
        """
        Check for wash trading patterns
        """
        try:
            # Get transaction history from Helius
            tx_history = self.helius_client.get_transaction_history(signal.symbol)

            # Check wash trading score (using config threshold)
            if tx_history.wash_trading_score > self.config.filters.spam_wash_trading_threshold:
                return False

            # Check transaction frequency (using config threshold)
            if tx_history.transaction_frequency > self.config.filters.spam_high_frequency_threshold:
                return False

            # Check large transactions (using config thresholds)
            if tx_history.large_transactions > self.config.filters.spam_large_tx_count and signal.liquidity < self.config.filters.spam_large_tx_liquidity:
                # Many large transactions with low liquidity
                return False

            return True
        except e:
            print(f"⚠️  Error checking wash trading: {e}")
            return True  # Allow if check fails

    fn _pump_dump_check(self, signal: TradingSignal) -> Bool:
        """
        Check for pump & dump patterns
        """
        # Check for rapid price increases (using config threshold)
        if signal.rsi_value > self.config.filters.spam_extreme_rsi_threshold:
            return False

        # Check if price increase is too rapid (using config threshold)
        let pc5 = signal.metadata.get("price_change_5m", 0.0)
        if pc5 > self.config.filters.spam_rapid_price_change:
            return False

        # Check if there's no real support level
        if signal.support_level <= 0 and signal.resistance_level > 0:
            # Has resistance but no support - might be artificial
            return False

        # Check liquidity lock ratio
        try:
            liquidity_info = self.helius_client.check_liquidity_locks(signal.symbol)
            if not liquidity_info.get("is_locked", False):
                return False

            lock_ratio = liquidity_info.get("percentage_locked", 0.0)
            if lock_ratio < MIN_LIQUIDITY_LOCK_RATIO:
                return False
        except e:
            print(f"⚠️  Error checking liquidity locks: {e}")

        return True

    fn _age_check(self, signal: TradingSignal) -> Bool:
        """
        Check token age to avoid very new tokens
        """
        try:
            # Get token age from Helius
            age_hours = self.helius_client.analyze_token_age(signal.symbol)

            # Skip very new tokens (using config threshold)
            if age_hours < self.config.filters.spam_new_token_age_hours:
                return False

            # Be more careful with very new tokens (using config threshold)
            if age_hours < self.config.filters.spam_careful_token_age_hours:
                # Require higher confidence for new tokens (using config threshold)
                return signal.confidence > self.config.filters.spam_high_confidence_new_token

            return True
        except e:
            print(f"⚠️  Error checking token age: {e}")
            return True  # Allow if check fails

    fn _price_manipulation_check(self, signal: TradingSignal) -> Bool:
        """
        Check for price manipulation patterns
        """
        # Check for unrealistic price targets (using config threshold)
        if signal.price_target > 0:
            expected_return = (signal.price_target - signal.stop_loss) / signal.stop_loss
            if expected_return > self.config.filters.spam_expected_return_limit:  # Using config threshold
                return False

        # Check stop loss placement
        if signal.stop_loss <= 0:
            return False

        # Check if stop loss is too tight (using config threshold)
        current_price_estimate = signal.price_target if signal.price_target > 0 else signal.stop_loss * 1.5
        stop_loss_distance = abs(current_price_estimate - signal.stop_loss) / current_price_estimate
        if stop_loss_distance < self.config.filters.spam_min_stop_loss_distance:  # Using config threshold
            return False

        # Check for round number targets (might be psychological manipulation)
        if signal.price_target > 0:
            if self._is_round_number(signal.price_target):
                # Reduce confidence for round number targets (using config threshold)
                return signal.confidence > self.config.filters.spam_round_number_confidence

        return True

    fn _is_round_number(self, price: Float) -> Bool:
        """
        Check if a price is a round number
        """
        # Check if price has few significant digits
        price_str = f"{price:.10f}".rstrip('0').rstrip('.')
        significant_digits = len(price_str.replace('.', ''))

        return significant_digits <= 3  # 3 or fewer significant digits

    fn _get_spam_reason(self, signal: TradingSignal) -> String:
        """
        Get the reason why a signal was marked as spam
        """
        if signal.confidence < 0.5:
            return "Low confidence"

        if signal.liquidity < self.config.risk.min_liquidity:
            return "Insufficient liquidity"

        if signal.volume < self.config.risk.min_volume:
            return "Insufficient volume"

        if signal.rsi_value > 80.0:
            return "Extremely overbought"

        let pc5 = signal.metadata.get("price_change_5m", 0.0)
        if pc5 > 50.0:
            return "Suspicious price movement"

        return "Multiple spam factors detected"

    def analyze_market_health(self, market_data: MarketData) -> Dict[String, Any]:
        """
        Analyze overall market health for a token
        """
        health_score = 1.0
        risk_factors = []

        # Check holder distribution
        try:
            top_holders = self.helius_client.get_top_holders(market_data.symbol, 10)
            if len(top_holders) > 0:
                concentration = sum(h.get("percentage", 0.0) for h in top_holders[:5])
                if concentration > MAX_TOP_HOLDER_CONCENTRATION:
                    health_score -= 0.3
                    risk_factors.append("High holder concentration")
        except:
            pass

        # Check transaction history
        try:
            tx_history = self.helius_client.get_transaction_history(market_data.symbol)
            if tx_history.wash_trading_score > WASH_TRADING_SCORE_THRESHOLD:
                health_score -= 0.4
                risk_factors.append("High wash trading score")

            if tx_history.unique_traders < MIN_UNIQUE_TRADERS:
                health_score -= 0.2
                risk_factors.append("Low unique trader count")
        except:
            pass

        # Check liquidity locks
        try:
            liquidity_info = self.helius_client.check_liquidity_locks(market_data.symbol)
            if not liquidity_info.get("is_locked", False):
                health_score -= 0.3
                risk_factors.append("Liquidity not locked")
        except:
            pass

        # Check volume patterns (using config threshold)
        if market_data.volume_24h > 0 and market_data.liquidity_usd > 0:
            volume_to_liquidity = market_data.volume_24h / market_data.liquidity_usd
            if volume_to_liquidity > self.config.risk_thresholds.volume_to_liquidity_suspicious:
                health_score -= 0.2
                risk_factors.append("Unusual volume patterns")

        return {
            "health_score": max(0.0, health_score),
            "risk_factors": risk_factors,
            "is_healthy": health_score > 0.6,
            "recommendation": "AVOID" if health_score < 0.4 else ("CAUTION" if health_score < 0.7 else "PROCEED")
        }

    def get_market_quality_score(self, market_data: MarketData) -> Float:
        """
        Get overall market quality score (0.0 to 1.0)
        """
        health_analysis = self.analyze_market_health(market_data)
        return health_analysis["health_score"]

    def get_filter_statistics(self) -> Dict[String, Int]:
        """
        Get basic filter statistics
        """
        return {
            "spam_filter_rejections": 0,
            "liquidity_rejections": 0,
            "volume_rejections": 0,
            "holder_concentration_rejections": 0,
            "wash_trading_rejections": 0,
            "price_manipulation_rejections": 0,
            "age_rejections": 0,
            "total_rejections": 0
        }

    fn reset_counters(inout self):
        """
        Reset signal counters and cleanup old cooldown entries
        """
        current_time = time()

        # Clear signal counts
        self.signal_counts.clear()

        # Clean up old cooldown entries (older than 1 hour)
        old_symbols = []
        for symbol, last_time in self.last_signal_times.items():
            if current_time - last_time > 3600.0:  # 1 hour
                old_symbols.append(symbol)

        for symbol in old_symbols:
            del self.last_signal_times[symbol]

        self.logger.info("spam_filter_counters_reset", {
            "cooldown_entries_remaining": len(self.last_signal_times),
            "old_entries_cleaned": len(old_symbols)
        })