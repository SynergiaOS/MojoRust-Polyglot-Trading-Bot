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
from data.honeypot_client import HoneypotClient
from data.social_client import SocialClient

@value
struct MasterFilter:
    """Master orchestrator for multi-stage signal filtering"""

    # Filter instances
    var instant_detector: InstantSpamDetector
    var spam_filter: SpamFilter
    var micro_filter: MicroTimeframeFilter

    # Sniper filter clients
    var honeypot_client: HoneypotClient
    var social_client: SocialClient

    # Logger
    var logger

    # Statistics tracking
    var total_signals_processed: Int
    var total_signals_rejected: Int
    var instant_rejections: Int
    var aggressive_rejections: Int
    var sniper_rejections: Int
    var micro_rejections: Int

    fn __init__(inout self, helius_client, config):
        """Initialize master filter with four-stage filtering pipeline"""
        # Initialize filters
        self.instant_detector = InstantSpamDetector()
        self.spam_filter = SpamFilter(helius_client, config)
        self.micro_filter = MicroTimeframeFilter()

        # Initialize sniper clients
        self.honeypot_client = HoneypotClient(
            api_key=config.api.honeypot_api_key if hasattr(config.api, "honeypot_api_key") else "",
            enabled=config.sniper_filters.honeypot_check
        )
        self.social_client = SocialClient(
            twitter_api_key=config.api.twitter_api_key if hasattr(config.api, "twitter_api_key") else "",
            enabled=config.sniper_filters.social_check_enabled
        )

        # Initialize logger
        self.logger = get_logger("MasterFilter")

        # Initialize statistics
        self.total_signals_processed = 0
        self.total_signals_rejected = 0
        self.instant_rejections = 0
        self.aggressive_rejections = 0
        self.sniper_rejections = 0
        self.micro_rejections = 0

        self.logger.info("master_filter_initialized", {
            "filter_chain": ["InstantSpamDetector", "SpamFilter", "SniperFilter", "MicroTimeframeFilter"],
            "sniper_filters_enabled": True,
            "honeypot_check_enabled": config.sniper_filters.honeypot_check,
            "social_check_enabled": config.sniper_filters.social_check_enabled,
            "target_rejection_rate": "90-95%",
            "max_processing_time_ms": 100
        })

    fn filter_all_signals(inout self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Filter all trading signals through four-stage pipeline
        Stage 1: Instant Detection → Stage 2: Aggressive Spam Filter → Stage 3: Sniper Filter → Stage 4: Micro Timeframe Filter
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

        # Stage 3: Sniper Filter
        sniper_passed = self._apply_sniper_filters(aggressive_passed)
        stage3_rejected = len(aggressive_passed) - len(sniper_passed)
        self.sniper_rejections += stage3_rejected

        sniper_rate = (stage3_rejected / len(aggressive_passed)) * 100.0 if len(aggressive_passed) > 0 else 0.0
        self.logger.info("stage_3_sniper_complete", {
            "input": len(aggressive_passed),
            "passed": len(sniper_passed),
            "rejected": stage3_rejected,
            "rejection_rate": sniper_rate,
            "honeypot_enabled": self.honeypot_client.enabled,
            "social_enabled": self.social_client.enabled
        })

        # Stage 4: Micro Timeframe Filter
        final_passed = self.micro_filter.filter_signals(sniper_passed)
        stage4_rejected = len(sniper_passed) - len(final_passed)
        self.micro_rejections += stage4_rejected

        micro_rate = (stage4_rejected / len(sniper_passed)) * 100.0 if len(sniper_passed) > 0 else 0.0
        self.logger.info("stage_4_micro_complete", {
            "input": len(sniper_passed),
            "passed": len(final_passed),
            "rejected": stage4_rejected,
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
                "sniper": stage3_rejected,
                "micro": stage4_rejected
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
            "sniper_rejections": Float(self.sniper_rejections),
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
        self.sniper_rejections = 0
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

    fn _apply_sniper_filters(self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Apply advanced sniper filters to trading signals
        Combines LP burn, authority, distribution, social, and honeypot analysis
        """
        if not signals:
            return signals

        filtered_signals = []

        for signal in signals:
            # Only apply sniper filters to signals marked as sniper candidates
            if not signal.metadata.get("is_sniper_candidate", False):
                filtered_signals.append(signal)
                continue

            # Call spam filter's comprehensive sniper filter method
            sniper_result = self.spam_filter.check_sniper_filters(signal, self.honeypot_client, self.social_client)

            if sniper_result["passed"]:
                # Add sniper metadata to the signal
                signal.metadata["sniper_analysis"] = sniper_result
                signal.metadata["sniper_confidence"] = sniper_result["confidence_score"]
                signal.metadata["sniper_recommendation"] = sniper_result["recommendation"]
                filtered_signals.append(signal)

                self.logger.info("sniper_filter_passed", {
                    "symbol": signal.symbol,
                    "token_address": signal.metadata.get("token_address", "unknown"),
                    "confidence_score": sniper_result["confidence_score"],
                    "recommendation": sniper_result["recommendation"]
                })
            else:
                self.logger.debug("sniper_filter_rejected", {
                    "symbol": signal.symbol,
                    "token_address": signal.metadata.get("token_address", "unknown"),
                    "confidence": signal.confidence,
                    "reason": sniper_result.get("reason", "Unknown reason"),
                    "confidence_score": sniper_result.get("confidence_score", 0.0)
                })

        return filtered_signals


    def get_sniper_filter_stats(self) -> Dict[String, Any]:
        """
        Get detailed sniper filter statistics and client status
        """
        return {
            "sniper_rejections": Float(self.sniper_rejections),
            "sniper_rejection_rate": (Float(self.sniper_rejections) / Float(self.total_signals_processed)) * 100.0 if self.total_signals_processed > 0 else 0.0,
            "honeypot_client": {
                "enabled": self.honeypot_client.enabled,
                "api_configured": len(self.honeypot_client.api_key) > 0
            },
            "social_client": {
                "enabled": self.social_client.enabled,
                "api_configured": len(self.social_client.twitter_api_key) > 0
            },
            "filter_settings": {
                "min_lp_burn_rate": self.config.sniper_filters.min_lp_burn_rate,
                "revoke_authority_required": self.config.sniper_filters.revoke_authority_required,
                "max_top_holders_share": self.config.sniper_filters.max_top_holders_share,
                "min_social_mentions": self.config.sniper_filters.min_social_mentions,
                "social_check_enabled": self.config.sniper_filters.social_check_enabled,
                "honeypot_check": self.config.sniper_filters.honeypot_check
            }
        }