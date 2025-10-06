# =============================================================================
# Micro Timeframe Filter - Ultra-Strict Spam Detection
# =============================================================================
# Specialized filter for 5s-15s timeframes with highest spam risk detection
# Implements volume, confidence, cooldown, price stability, and P&D pattern detection

from time import time
from collections import Dict, List, Set
from core.types import TradingSignal, TradingAction
from core.logger import get_main_logger

@value
struct MicroTimeframeFilter:
    """
    Ultra-strict filter for micro timeframes (1s, 5s, 15s)
    Highest spam risk timeframes requiring extreme filtering
    """

    # Filter configuration constants
    var MIN_VOLUME_USD: Float
    var MIN_CONFIDENCE: Float
    var COOLDOWN_SECONDS: Float
    var MIN_PRICE_STABILITY: Float
    var MAX_PRICE_CHANGE_5MIN: Float
    var EXTREME_PRICE_SPIKE_THRESHOLD: Float

    # Target timeframes for this filter
    var TARGET_TIMEFRAMES: Set[String]

    # Cooldown tracking per symbol
    var last_signal_times: Dict[String, Float]

    # Logger
    var logger

    fn __init__(inout self):
        """Initialize micro timeframe filter with ultra-strict parameters"""
        # Ultra-strict thresholds for high-risk timeframes
        self.MIN_VOLUME_USD = 15000.0  # $15k minimum volume
        self.MIN_CONFIDENCE = 0.75      # 75% minimum confidence
        self.COOLDOWN_SECONDS = 60.0     # 60s cooldown between signals
        self.MIN_PRICE_STABILITY = 0.80   # 80% minimum price stability
        self.MAX_PRICE_CHANGE_5MIN = 0.30 # 30% max price change in 5min
        self.EXTREME_PRICE_SPIKE_THRESHOLD = 0.50  # 50% extreme spike threshold

        # Target ultra-short timeframes
        self.TARGET_TIMEFRAMES = {"1s", "5s", "15s"}

        # Cooldown tracking
        self.last_signal_times = {}

        # Logger
        self.logger = get_main_logger()

        self.logger.info("micro_timeframe_filter_initialized", {
            "min_volume_usd": self.MIN_VOLUME_USD,
            "min_confidence": self.MIN_CONFIDENCE,
            "cooldown_seconds": self.COOLDOWN_SECONDS,
            "target_timeframes": list(self.TARGET_TIMEFRAMES)
        })

    fn filter_signals(self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Filter signals for micro timeframes with ultra-strict criteria
        """
        filtered_signals = List[TradingSignal]()
        rejected_count = 0
        rejection_reasons = Dict[String, Int]()

        for signal in signals:
            # Check if this signal should be processed by this filter
            if signal.timeframe not in self.TARGET_TIMEFRAMES:
                # Not our target timeframe, let it pass
                filtered_signals.append(signal)
                continue

            # Apply ultra-strict filtering
            is_valid, reason = self._is_valid_micro_signal(signal)

            if is_valid:
                filtered_signals.append(signal)
                # Update cooldown timestamp
                self.last_signal_times[signal.symbol] = signal.timestamp
            else:
                rejected_count += 1
                rejection_reasons[reason] = rejection_reasons.get(reason, 0) + 1

                self.logger.warning("micro_signal_rejected", {
                    "symbol": signal.symbol,
                    "timeframe": signal.timeframe,
                    "reason": reason,
                    "volume": signal.volume,
                    "confidence": signal.confidence,
                    "timestamp": signal.timestamp
                })

        # Log filtering statistics
        self.logger.info("micro_timeframe_filter_stats", {
            "input_signals": len(signals),
            "output_signals": len(filtered_signals),
            "rejection_rate": (rejected_count / Float(len(signals))) * 100.0 if len(signals) > 0 else 0.0,
            "rejected_count": rejected_count,
            "rejection_reasons": rejection_reasons
        })

        return filtered_signals

    fn _is_valid_micro_signal(self, signal: TradingSignal) -> (Bool, String):
        """
        Validate micro timeframe signal with ultra-strict criteria
        Returns: (is_valid, rejection_reason)
        """

        # 1. Check volume threshold
        if signal.volume < self.MIN_VOLUME_USD:
            return (False, f"insufficient_volume_${signal.volume}_min_{self.MIN_VOLUME_USD}")

        # 2. Check confidence threshold
        if signal.confidence < self.MIN_CONFIDENCE:
            return (False, f"low_confidence_{signal.confidence}_min_{self.MIN_CONFIDENCE}")

        # 3. Check cooldown mechanism
        if not self._check_cooldown(signal):
            return (False, "cooldown_active")

        # 4. Check price stability
        if not self._check_price_stability(signal):
            return (False, "price_instability")

        # 5. Check for pump & dump patterns
        if self._is_pump_dump_pattern(signal):
            return (False, "pump_dump_pattern_detected")

        # 6. Additional ultra-strict checks for micro timeframes
        if not self._micro_timeframe_checks(signal):
            return (False, "micro_timeframe_checks_failed")

        # All checks passed
        return (True, "valid")

    fn _check_cooldown(self, signal: TradingSignal) -> Bool:
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

        return True

    fn _check_price_stability(self, signal: TradingSignal) -> Bool:
        """
        Check price stability requirements for micro timeframes
        """
        # Extract price change from metadata if available
        price_change_5m = signal.metadata.get("price_change_5m", 0.0)

        # Check if price change is within acceptable limits
        if abs(price_change_5m) > self.MAX_PRICE_CHANGE_5MIN:
            self.logger.debug("price_instability", {
                "symbol": signal.symbol,
                "price_change_5m": price_change_5m,
                "max_allowed": self.MAX_PRICE_CHANGE_5MIN
            })
            return False

        # Check price stability score if available
        price_stability = signal.metadata.get("price_stability", 0.0)
        if price_stability < self.MIN_PRICE_STABILITY:
            self.logger.debug("low_price_stability", {
                "symbol": signal.symbol,
                "stability": price_stability,
                "min_required": self.MIN_PRICE_STABILITY
            })
            return False

        return True

    fn _is_pump_dump_pattern(self, signal: TradingSignal) -> Bool:
        """
        Detect pump & dump patterns in micro timeframes
        """
        # Extract volume and price metrics
        volume_spike_ratio = signal.metadata.get("volume_spike_ratio", 1.0)
        price_change_5m = signal.metadata.get("price_change_5m", 0.0)
        holder_concentration = signal.metadata.get("holder_concentration", 0.0)

        # Check for extreme price spikes with low volume
        if abs(price_change_5m) > self.EXTREME_PRICE_SPIKE_THRESHOLD:
            if signal.volume < self.MIN_VOLUME_USD * 2:  # Even higher threshold for spikes
                self.logger.debug("extreme_price_spike_low_volume", {
                    "symbol": signal.symbol,
                    "price_change": price_change_5m,
                    "volume": signal.volume,
                    "spike_threshold": self.EXTREME_PRICE_SPIKE_THRESHOLD
                })
                return True

        # Check for classic pump & dump indicators
        pump_dump_indicators = 0

        # High volume spike (>3x normal)
        if volume_spike_ratio > 3.0:
            pump_dump_indicators += 1

        # Extreme price change (>20% in 5min)
        if abs(price_change_5m) > 0.20:
            pump_dump_indicators += 1

        # High holder concentration (>80%)
        if holder_concentration > 0.80:
            pump_dump_indicators += 1

        # Low liquidity relative to volume
        liquidity_to_volume_ratio = signal.liquidity / signal.volume if signal.volume > 0 else 0.0
        if liquidity_to_volume_ratio < 0.5:  # Liquidity less than 50% of volume
            pump_dump_indicators += 1

        # If 2 or more indicators, flag as pump & dump
        if pump_dump_indicators >= 2:
            self.logger.debug("pump_dump_pattern_detected", {
                "symbol": signal.symbol,
                "indicators": pump_dump_indicators,
                "volume_spike": volume_spike_ratio,
                "price_change": price_change_5m,
                "holder_concentration": holder_concentration
            })
            return True

        return False

    fn _micro_timeframe_checks(self, signal: TradingSignal) -> Bool:
        """
        Additional ultra-strict checks specific to micro timeframes
        """
        micro_checks_passed = 0
        total_checks = 0

        # 1. RSI sanity check for micro timeframes
        total_checks += 1
        if 20.0 <= signal.rsi_value <= 80.0:  # Not extreme RSI
            micro_checks_passed += 1
        else:
            self.logger.debug("extreme_rsi_micro", {
                "symbol": signal.symbol,
                "rsi": signal.rsi_value,
                "timeframe": signal.timeframe
            })

        # 2. Volume consistency check
        total_checks += 1
        volume_consistency = signal.metadata.get("volume_consistency", 0.0)
        if volume_consistency > 0.6:  # Reasonable volume consistency
            micro_checks_passed += 1
        else:
            self.logger.debug("poor_volume_consistency", {
                "symbol": signal.symbol,
                "consistency": volume_consistency,
                "timeframe": signal.timeframe
            })

        # 3. Liquidity depth check
        total_checks += 1
        if signal.liquidity > signal.volume * 1.5:  # Liquidity should be 1.5x volume
            micro_checks_passed += 1
        else:
            self.logger.debug("insufficient_liquidity_depth", {
                "symbol": signal.symbol,
                "liquidity": signal.liquidity,
                "volume": signal.volume,
                "timeframe": signal.timeframe
            })

        # 4. Transaction size consistency
        total_checks += 1
        avg_tx_size = signal.metadata.get("avg_tx_size", 0.0)
        if avg_tx_size > 0:  # Should have transaction data
            # Check if transaction sizes are reasonable (not too small, not too large)
            tx_size_to_volume_ratio = avg_tx_size / signal.volume if signal.volume > 0 else 0.0
            if 0.001 <= tx_size_to_volume_ratio <= 0.1:  # 0.1% to 10% of volume
                micro_checks_passed += 1
            else:
                self.logger.debug("suspicious_tx_sizes", {
                    "symbol": signal.symbol,
                    "avg_tx_size": avg_tx_size,
                    "tx_size_ratio": tx_size_to_volume_ratio,
                    "timeframe": signal.timeframe
                })
        else:
            self.logger.debug("missing_tx_data", {
                "symbol": signal.symbol,
                "timeframe": signal.timeframe
            })

        # Must pass at least 75% of micro timeframe checks
        required_passes = int(total_checks * 0.75)
        return micro_checks_passed >= required_passes

    def get_filter_statistics(self) -> Dict[String, Int]:
        """
        Get statistics about filter performance
        """
        return {
            "micro_filter_rejections": 0,  # Will be updated by filter system
            "cooldown_rejections": 0,
            "volume_rejections": 0,
            "confidence_rejections": 0,
            "price_stability_rejections": 0,
            "pump_dump_rejections": 0,
            "micro_check_rejections": 0
        }

    def get_rejection_breakdown(self) -> Dict[String, Int]:
        """
        Get detailed breakdown of rejection reasons
        """
        return {
            "insufficient_volume": 0,
            "low_confidence": 0,
            "cooldown_active": 0,
            "price_instability": 0,
            "pump_dump_pattern_detected": 0,
            "micro_timeframe_checks_failed": 0
        }

    fn should_process_signal(self, signal: TradingSignal) -> Bool:
        """
        Check if this filter should process the given signal
        """
        return signal.timeframe in self.TARGET_TIMEFRAMES

    def get_target_timeframes(self) -> Set[String]:
        """
        Get the timeframes this filter is designed for
        """
        return self.TARGET_TIMEFRAMES.copy()

    def update_configuration(self, min_volume: Float = 15000.0, min_confidence: Float = 0.75,
                           cooldown_seconds: Float = 60.0):
        """
        Update filter configuration parameters
        """
        self.MIN_VOLUME_USD = min_volume
        self.MIN_CONFIDENCE = min_confidence
        self.COOLDOWN_SECONDS = cooldown_seconds

        self.logger.info("micro_filter_config_updated", {
            "min_volume_usd": self.MIN_VOLUME_USD,
            "min_confidence": self.MIN_CONFIDENCE,
            "cooldown_seconds": self.COOLDOWN_SECONDS
        })