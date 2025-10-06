# =============================================================================
# Instant Spam Detector - Lightning Fast Obvious Spam Detection
# =============================================================================
# <10ms ultra-fast checks for obvious spam cases
# No external dependencies for maximum speed

from core.types import TradingSignal, Config
from core.logger import get_logger
from collections import List, Dict

@value
struct InstantSpamDetector:
    """
    Lightning-fast spam detector for obvious spam cases
    Designed for <10ms processing time with zero external dependencies
    """

    # Configuration-driven thresholds for maximum flexibility
    var config: Config
    var MIN_VOLUME_USD: Float
    var MIN_LIQUIDITY_USD: Float
    var MIN_CONFIDENCE: Float
    var EXTREME_RSI_LOW: Float
    var EXTREME_RSI_HIGH: Float

    # Logger
    var logger

    fn __init__(config: Config):
        """Initialize with configuration-driven thresholds and logger"""
        # Load thresholds from config for instant filter
        self.config = config
        self.MIN_VOLUME_USD = config.filters.instant_min_volume_usd
        self.MIN_LIQUIDITY_USD = config.filters.instant_min_liquidity_usd
        self.MIN_CONFIDENCE = config.filters.instant_min_confidence
        self.EXTREME_RSI_LOW = config.filters.instant_extreme_rsi_low
        self.EXTREME_RSI_HIGH = config.filters.instant_extreme_rsi_high

        # Initialize logger
        self.logger = get_logger("InstantSpamDetector")

        self.logger.info("instant_spam_detector_initialized", {
            "min_volume_usd": self.MIN_VOLUME_USD,
            "min_liquidity_usd": self.MIN_LIQUIDITY_USD,
            "min_confidence": self.MIN_CONFIDENCE,
            "extreme_rsi_low": self.EXTREME_RSI_LOW,
            "extreme_rsi_high": self.EXTREME_RSI_HIGH,
            "loaded_from": "config.filters.instant_*"
        })

    fn instant_check(self, signal: TradingSignal) -> Bool:
        """
        Main filtering method - returns True if signal passes, False if rejected
        Perform checks in order of fastest to slowest
        """
        # Check 1: Volume threshold (fastest check)
        if signal.volume < self.MIN_VOLUME_USD:
            return False

        # Check 2: Liquidity threshold
        if signal.liquidity < self.MIN_LIQUIDITY_USD:
            return False

        # Check 3: Confidence threshold
        if signal.confidence < self.MIN_CONFIDENCE:
            return False

        # Check 4: Extreme RSI values
        if signal.rsi_value < self.EXTREME_RSI_LOW or signal.rsi_value > self.EXTREME_RSI_HIGH:
            return False

        # All checks passed
        return True

    def get_rejection_reason(self, signal: TradingSignal) -> String:
        """
        Helper method that returns human-readable rejection reason
        Re-runs checks and returns first failure reason (used for logging)
        """
        # Check volume threshold
        if signal.volume < self.MIN_VOLUME_USD:
            return f"Insufficient volume: ${signal.volume:.2f} < ${self.MIN_VOLUME_USD:.2f}"

        # Check liquidity threshold
        if signal.liquidity < self.MIN_LIQUIDITY_USD:
            return f"Insufficient liquidity: ${signal.liquidity:.2f} < ${self.MIN_LIQUIDITY_USD:.2f}"

        # Check confidence threshold
        if signal.confidence < self.MIN_CONFIDENCE:
            return f"Low confidence: {signal.confidence:.2f} < {self.MIN_CONFIDENCE:.2f}"

        # Check extreme RSI values
        if signal.rsi_value < self.EXTREME_RSI_LOW:
            return f"Extreme oversold RSI: {signal.rsi_value:.1f} < {self.EXTREME_RSI_LOW:.1f}"

        if signal.rsi_value > self.EXTREME_RSI_HIGH:
            return f"Extreme overbought RSI: {signal.rsi_value:.1f} > {self.EXTREME_RSI_HIGH:.1f}"

        # Should not reach here if instant_check() returned False
        return "Unknown reason"

    def process_signals(self, signals: List[TradingSignal]) -> (List[TradingSignal], Int):
        """
        Batch process signals for efficiency
        Returns: (passed_signals, rejected_count)
        """
        passed_signals = List[TradingSignal]()
        rejected_count = 0

        for signal in signals:
            if self.instant_check(signal):
                passed_signals.append(signal)
            else:
                rejected_count += 1

        return (passed_signals, rejected_count)

    def get_thresholds(self) -> Dict[String, Float]:
        """
        Get current threshold values for monitoring
        """
        return {
            "min_volume_usd": self.MIN_VOLUME_USD,
            "min_liquidity_usd": self.MIN_LIQUIDITY_USD,
            "min_confidence": self.MIN_CONFIDENCE,
            "extreme_rsi_low": self.EXTREME_RSI_LOW,
            "extreme_rsi_high": self.EXTREME_RSI_HIGH
        }