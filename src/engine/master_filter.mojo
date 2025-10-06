# =============================================================================
# Master Filter Orchestrator
# =============================================================================
# Complete orchestrator chaining InstantSpamDetector → Enhanced SpamFilter → MicroTimeframeFilter

from time import time
from core.types import TradingSignal
from collections import List, Dict, Any
from core.logger import get_logger
from engine.instant_spam_detector import InstantSpamDetector
from engine.spam_filter import SpamFilter
from engine.micro_timeframe_filter import MicroTimeframeFilter

@value
struct MasterFilter:
    """Master orchestrator for multi-stage signal filtering"""

    # Filter instances
    var instant_detector: InstantSpamDetector
    var spam_filter: SpamFilter
    var micro_filter: MicroTimeframeFilter

    # Logger
    var logger

    # Statistics tracking
    var total_signals_processed: Int
    var total_signals_rejected: Int
    var instant_rejections: Int
    var aggressive_rejections: Int
    var micro_rejections: Int

    fn __init__(inout self, helius_client, config):
        """Initialize master filter with all three filter stages"""
        # Initialize filters
        self.instant_detector = InstantSpamDetector()
        self.spam_filter = SpamFilter(helius_client, config)
        self.micro_filter = MicroTimeframeFilter()

        # Initialize logger
        self.logger = get_logger("MasterFilter")

        # Initialize statistics
        self.total_signals_processed = 0
        self.total_signals_rejected = 0
        self.instant_rejections = 0
        self.aggressive_rejections = 0
        self.micro_rejections = 0

        self.logger.info("master_filter_initialized", {
            "filter_chain": ["InstantSpamDetector", "SpamFilter", "MicroTimeframeFilter"],
            "target_rejection_rate": "90-95%",
            "max_processing_time_ms": 100
        })

    fn filter_all_signals(inout self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Filter all trading signals through three-stage pipeline
        Stage 1: Instant Detection → Stage 2: Aggressive Spam Filter → Stage 3: Micro Timeframe Filter
        """
        start_time = time()
        input_count = len(signals)
        self.total_signals_processed += input_count

        self.logger.info("master_filter_processing_started", {
            "signal_count": input_count
        })

        # Stage 1: Instant Detection (fastest first)
        instant_passed, instant_rejected = self.instant_detector.process_signals(signals)
        self.instant_rejections += instant_rejected

        instant_rate = (instant_rejected / input_count) * 100.0 if input_count > 0 else 0.0
        self.logger.info("stage_1_instant_complete", {
            "input": input_count,
            "passed": len(instant_passed),
            "rejected": instant_rejected,
            "rejection_rate": instant_rate
        })

        # Stage 2: Aggressive Spam Filter
        aggressive_passed = self.spam_filter.filter_signals(instant_passed)
        stage2_rejected = len(instant_passed) - len(aggressive_passed)
        self.aggressive_rejections += stage2_rejected

        aggressive_rate = (stage2_rejected / len(instant_passed)) * 100.0 if len(instant_passed) > 0 else 0.0
        self.logger.info("stage_2_aggressive_complete", {
            "input": len(instant_passed),
            "passed": len(aggressive_passed),
            "rejected": stage2_rejected,
            "rejection_rate": aggressive_rate
        })

        # Stage 3: Micro Timeframe Filter
        final_passed = self.micro_filter.filter_signals(aggressive_passed)
        stage3_rejected = len(aggressive_passed) - len(final_passed)
        self.micro_rejections += stage3_rejected

        micro_rate = (stage3_rejected / len(aggressive_passed)) * 100.0 if len(aggressive_passed) > 0 else 0.0
        self.logger.info("stage_3_micro_complete", {
            "input": len(aggressive_passed),
            "passed": len(final_passed),
            "rejected": stage3_rejected,
            "rejection_rate": micro_rate
        })

        # Calculate final statistics
        total_rejected = input_count - len(final_passed)
        self.total_signals_rejected += total_rejected
        rejection_rate = (total_rejected / input_count) * 100.0 if input_count > 0 else 0.0
        processing_time_ms = (time() - start_time) * 1000.0

        # Log comprehensive results
        self.logger.info("master_filter_complete", {
            "approved": len(final_passed),
            "rejected": total_rejected,
            "rejection_rate": rejection_rate,
            "processing_time_ms": processing_time_ms,
            "breakdown": {
                "instant": instant_rejected,
                "aggressive": stage2_rejected,
                "micro": stage3_rejected
            }
        })

        # Performance check
        if processing_time_ms > 100.0:
            self.logger.warning("master_filter_slow_processing", {
                "processing_time_ms": processing_time_ms,
                "input_count": input_count,
                "target_time_ms": 100.0
            })

        return final_passed

    def get_filter_stats(self) -> Dict[String, Float]:
        """
        Get comprehensive filter statistics
        """
        return {
            "total_processed": Float(self.total_signals_processed),
            "total_rejected": Float(self.total_signals_rejected),
            "rejection_rate": (Float(self.total_signals_rejected) / Float(self.total_signals_processed)) * 100.0 if self.total_signals_processed > 0 else 0.0,
            "instant_rejections": Float(self.instant_rejections),
            "aggressive_rejections": Float(self.aggressive_rejections),
            "micro_rejections": Float(self.micro_rejections)
        }

    fn reset_statistics(inout self):
        """
        Reset all statistics counters
        """
        self.total_signals_processed = 0
        self.total_signals_rejected = 0
        self.instant_rejections = 0
        self.aggressive_rejections = 0
        self.micro_rejections = 0

        # Reset sub-filter counters
        self.spam_filter.reset_counters()

        self.logger.info("master_filter_statistics_reset")

    def get_performance_metrics(self) -> Dict[String, Any]:
        """
        Get current performance metrics
        """
        stats = self.get_filter_stats()

        return {
            "filter_statistics": stats,
            "current_rejection_rate": stats["rejection_rate"],
            "target_range": "90-95%",
            "is_within_target": 90.0 <= stats["rejection_rate"] <= 95.0,
            "filter_health": "HEALTHY" if 90.0 <= stats["rejection_rate"] <= 95.0 else "ADJUST"
        }