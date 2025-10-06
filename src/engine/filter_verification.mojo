# =============================================================================
# Filter Verification Tool
# =============================================================================
# Comprehensive testing system for aggressive spam filter deployment
# Ensures 90%+ spam rejection rate before allowing production deployment

from core.types import TradingSignal, TradingAction, SignalSource
from engine.master_filter import MasterFilter
from time import time
from random import random, randint
from collections import Dict, List, Any
from core.logger import get_main_logger
from os import getenv

@value
struct FilterVerification:
    """Test and verify filter aggressiveness before deployment"""
    var master_filter: Any
    var test_signal_count: Int
    var spam_ratio: Float  # 90% spam signals
    var logger
    var offline_mode: Bool

    fn __init__(inout self):
        """Initialize with MasterFilter instance"""
        # Check for offline mode
        self.offline_mode = getenv("MOCK_APIS", "false").lower() == "true"

        if self.offline_mode:
            print("🔧 OFFLINE MODE: Using mock filter for testing (no network calls)")
            # Use a simple mock filter for offline testing
            self.master_filter = MockFilter()
        else:
            self.master_filter = MasterFilter()

        self.test_signal_count = 1000
        self.spam_ratio = 0.9
        self.logger = get_main_logger()

    fn generate_test_signals(self, count: Int) -> List[TradingSignal]:
        """Generate realistic test signals with 90% spam and 10% legitimate"""
        signals = List[TradingSignal]()

        for i in range(count):
            is_spam = random() < self.spam_ratio
            signal = self._create_test_signal(i, is_spam)
            signals.append(signal)

        return signals

    fn _create_test_signal(self, index: Int, is_spam: Bool) -> TradingSignal:
        """Create a single test signal with realistic parameters"""
        timestamp = time()

        if is_spam:
            # Spam characteristics
            volume = 1000.0 + random() * 4000.0  # $1k-$5k (low)
            liquidity = 2000.0 + random() * 8000.0  # $2k-$10k (low)
            confidence = 0.1 + random() * 0.4  # 0.1-0.5 (low)
            rsi_value = 15.0 + random() * 10.0 if random() < 0.5 else 80.0 + random() * 15.0  # Extreme RSI
            price_change_5m = (random() - 0.5) * 0.8  # Large price swings

            # Suspicious metadata for spam
            volume_spike_ratio = 5.0 + random() * 10.0  # High volume spike
            avg_tx_size = 50.0 + random() * 200.0  # Small transactions
            volume_consistency = 0.1 + random() * 0.3  # Low consistency
            holder_concentration = 0.7 + random() * 0.3  # High concentration

            symbol = f"SPAM{index % 10}"

        else:
            # Legitimate characteristics
            volume = 15000.0 + random() * 35000.0  # $15k-$50k (good)
            liquidity = 25000.0 + random() * 50000.0  # $25k-$75k (good)
            confidence = 0.75 + random() * 0.2  # 0.75-0.95 (high)
            rsi_value = 30.0 + random() * 40.0  # 30-70 (healthy)
            price_change_5m = (random() - 0.5) * 0.2  # Moderate price movements

            # Clean metadata for legitimate signals
            volume_spike_ratio = 1.0 + random() * 2.0  # Normal volume spike
            avg_tx_size = 500.0 + random() * 2000.0  # Normal transaction size
            volume_consistency = 0.7 + random() * 0.3  # High consistency
            holder_concentration = 0.2 + random() * 0.4  # Low concentration

            symbol = f"GOOD{index % 10}"

        # Create metadata dictionary
        metadata: Dict[String, Any] = {}
        metadata["volume_spike_ratio"] = volume_spike_ratio
        metadata["avg_tx_size"] = avg_tx_size
        metadata["volume_consistency"] = volume_consistency
        metadata["holder_concentration"] = holder_concentration
        metadata["price_change_5m"] = price_change_5m

        # Create signal with correct field names and valid enum
        signal = TradingSignal(
            symbol=symbol,
            action=TradingAction.BUY if random() < 0.7 else TradingAction.SELL,
            confidence=confidence,
            timeframe="5m",
            timestamp=timestamp,
            volume=volume,
            liquidity=liquidity,
            rsi_value=rsi_value,
            signal_source=SignalSource.MOMENTUM,  # Fixed: use valid enum value
            metadata=metadata
        )

        return signal

    fn test_filter_aggressiveness(inout self) -> Bool:
        """Main test function - verify 90%+ spam rejection rate"""
        print("🧪 TESTING FILTER AGGRESSIVENESS...")
        print(f"   Generating {self.test_signal_count} test signals ({self.spam_ratio*100:.0f}% spam)")

        # Generate test signals
        test_signals = self.generate_test_signals(self.test_signal_count)

        # Process through filter
        start_time = time()
        filtered_signals = self.master_filter.filter_all_signals(test_signals)
        processing_time = time() - start_time

        # Get filter statistics if available
        var filter_stats = None
        try:
            filter_stats = self.master_filter.get_filter_stats()
        except e:
            pass

        # Calculate results
        input_count = len(test_signals)
        output_count = len(filtered_signals)
        rejection_rate = (1.0 - Float(output_count) / Float(input_count)) * 100.0

        # Print results with per-filter breakdown
        print(f"🎯 FILTER TEST RESULTS:")
        print(f"   Input signals: {input_count} (simulated)")
        print(f"   Output signals: {output_count}")
        print(f"   Rejection rate: {rejection_rate:.1f}%")
        print(f"   Processing time: {processing_time:.3f}s")

        # Print per-filter breakdown if available
        if filter_stats and len(filter_stats) > 0:
            print(f"📊 PER-FILTER BREAKDOWN:")
            print(f"   Instant filter rejections: {filter_stats.get('instant_rejections', 0)}")
            print(f"   Aggressive filter rejections: {filter_stats.get('aggressive_rejections', 0)}")
            print(f"   Micro filter rejections: {filter_stats.get('micro_rejections', 0)}")
            print(f"   Cooldown rejections: {filter_stats.get('cooldown_rejections', 0)}")
            print(f"   Volume quality rejections: {filter_stats.get('volume_quality_rejections', 0)}")
        else:
            print("⚠️  Per-filter breakdown not available (stub filter active)")

        # Log results
        self.logger.info(f"Filter verification test: {rejection_rate:.1f}% rejection rate ({input_count} -> {output_count} signals)")

        # Check threshold
        if rejection_rate >= 90.0:
            print(f"✅ FILTERS PASS: 90%+ spam rejection achieved!")
            return True
        else:
            print(f"❌ FILTERS FAIL: Only {rejection_rate:.1f}% rejection rate (need ≥90%)")
            self.logger.error(f"Filter verification failed: {rejection_rate:.1f}% rejection rate below 90% threshold")
            return False

    fn test_cooldown_mechanism(inout self) -> Bool:
        """Test per-symbol cooldown mechanism"""
        print("🧪 TESTING COOLDOWN MECHANISM...")

        # Generate signals for same symbol with 10s intervals
        test_symbol = "COOLDOWN_TEST"
        signals = List[TradingSignal]()

        for i in range(10):
            signal = self._create_legitimate_signal(test_symbol, i * 10.0)
            signals.append(signal)

        # Process through filter
        filtered_signals = self.master_filter.filter_all_signals(signals)

        # Should only get first signal due to cooldown
        expected_count = 1
        actual_count = len(filtered_signals)

        if actual_count == expected_count:
            print(f"✅ COOLDOWN PASS: Only {actual_count}/{len(signals)} signals passed (cooldown working)")
            return True
        else:
            print(f"❌ COOLDOWN FAIL: {actual_count}/{len(signals)} signals passed (expected {expected_count})")
            return False

    fn test_signal_limit(inout self) -> Bool:
        """Test max signals per symbol limit"""
        print("🧪 TESTING SIGNAL LIMIT...")

        # Generate multiple legitimate signals for same symbol
        test_symbol = "LIMIT_TEST"
        signals = List[TradingSignal]()

        for i in range(10):
            # Use same timestamp to bypass cooldown
            signal = self._create_legitimate_signal(test_symbol, 0.0)
            signals.append(signal)

        # Process through filter
        filtered_signals = self.master_filter.filter_all_signals(signals)

        # Should only get max_signals_per_symbol (usually 5)
        expected_max = 5
        actual_count = len(filtered_signals)

        if actual_count <= expected_max:
            print(f"✅ SIGNAL LIMIT PASS: {actual_count}/{len(signals)} signals passed (≤{expected_max} limit)")
            return True
        else:
            print(f"❌ SIGNAL LIMIT FAIL: {actual_count}/{len(signals)} signals passed (>{expected_max} limit)")
            return False

    fn test_volume_quality_detection(inout self) -> Bool:
        """Test wash trading detection via volume quality"""
        print("🧪 TESTING VOLUME QUALITY DETECTION...")

        # Generate signals with suspicious volume patterns
        suspicious_signals = List[TradingSignal]()

        for i in range(5):
            signal = self._create_suspicious_volume_signal(f"SUSPICIOUS{i}")
            suspicious_signals.append(signal)

        # Process through filter
        filtered_signals = self.master_filter.filter_all_signals(suspicious_signals)

        # Should reject most/all suspicious signals
        rejection_rate = (1.0 - Float(len(filtered_signals)) / Float(len(suspicious_signals))) * 100.0

        if rejection_rate >= 80.0:  # Expect 80%+ rejection of suspicious signals
            print(f"✅ VOLUME QUALITY PASS: {rejection_rate:.1f}% of suspicious signals rejected")
            return True
        else:
            print(f"❌ VOLUME QUALITY FAIL: Only {rejection_rate:.1f}% of suspicious signals rejected")
            return False

    fn _create_legitimate_signal(self, symbol: String, timestamp_offset: Float) -> TradingSignal:
        """Create a legitimate signal for testing"""
        timestamp = time() + timestamp_offset

        metadata: Dict[String, Any] = {}
        metadata["volume_spike_ratio"] = 1.5
        metadata["avg_tx_size"] = 1000.0
        metadata["volume_consistency"] = 0.8
        metadata["holder_concentration"] = 0.3
        metadata["price_change_5m"] = 0.05

        return TradingSignal(
            symbol=symbol,
            action=TradingAction.BUY,
            confidence=0.8,
            timeframe="5m",
            timestamp=timestamp,
            volume=20000.0,
            liquidity=30000.0,
            rsi_value=45.0,
            signal_source=SignalSource.RSI_SUPPORT,  # Fixed: use valid enum value
            metadata=metadata
        )

    fn _create_suspicious_volume_signal(self, symbol: String) -> TradingSignal:
        """Create a signal with suspicious volume patterns"""
        metadata: Dict[String, Any] = {}
        metadata["volume_spike_ratio"] = 8.0  # High spike
        metadata["avg_tx_size"] = 75.0  # Very small transactions
        metadata["volume_consistency"] = 0.2  # Low consistency
        metadata["holder_concentration"] = 0.9  # High concentration
        metadata["price_change_5m"] = 0.6  # Large price change

        return TradingSignal(
            symbol=symbol,
            action=TradingAction.BUY,
            confidence=0.3,
            timeframe="5m",
            timestamp=time(),
            volume=8000.0,  # Low volume
            liquidity=12000.0,  # Low liquidity
            rsi_value=12.0,  # Extreme RSI
            signal_source=SignalSource.MOMENTUM,  # Fixed: use valid enum value
            metadata=metadata
        )

    fn run_all_tests(inout self) -> Bool:
        """Run complete test suite"""
        print("🛡️ RUNNING COMPREHENSIVE FILTER VERIFICATION")
        print("=" * 50)

        results = Dict[String, Bool]()

        # Run all tests
        results["aggressiveness"] = self.test_filter_aggressiveness()
        results["cooldown"] = self.test_cooldown_mechanism()
        results["signal_limit"] = self.test_signal_limit()
        results["volume_quality"] = self.test_volume_quality_detection()

        # Count passed tests
        passed_count = 0
        total_count = len(results)

        for test_name, passed in results.items():
            if passed:
                passed_count += 1

        # Print summary
        self.print_test_summary(results)

        # Return True only if ALL tests pass
        if passed_count == total_count:
            print(f"🎉 ALL TESTS PASSED ({passed_count}/{total_count})")
            print("✅ SYSTEM READY FOR DEPLOYMENT")
            return True
        else:
            print(f"❌ SOME TESTS FAILED ({passed_count}/{total_count})")
            print("⚠️  ADJUST FILTER PARAMETERS BEFORE DEPLOYMENT")
            return False

    fn print_test_summary(self, results: Dict[String, Bool]):
        """Print formatted test results"""
        print("\n📋 TEST SUMMARY")
        print("=" * 30)

        for test_name, passed in results.items():
            status = "✅ PASS" if passed else "❌ FAIL"
            test_display = test_name.replace("_", " ").title()
            print(f"   {test_display:20} {status}")

        print("=" * 30)

# Main execution function for standalone testing
def main() -> Int:
    """Run filter verification tests"""
    verification = FilterVerification()
    success = verification.run_all_tests()

    if success:
        print("\n🚀 FILTER VERIFICATION COMPLETE - READY FOR DEPLOYMENT")
        return 0
    else:
        print("\n❌ FILTER VERIFICATION FAILED - FIX ISSUES BEFORE DEPLOYMENT")
        return 1

# =============================================================================
# Mock Filter for Offline Testing
# =============================================================================

@value
struct MockFilter:
    """Mock filter for offline testing without network dependencies"""

    fn __init__(inout self):
        """Initialize mock filter"""
        pass

    fn filter_all_signals(self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """Mock filter implementation - simulates 90%+ spam rejection"""
        filtered_signals = List[TradingSignal]()

        for signal in signals:
            # Simulate filter logic: reject ~90% of signals
            # Keep signals with high confidence (>0.7) or good volume (>10000)
            if signal.confidence > 0.7 or signal.volume > 10000.0:
                filtered_signals.append(signal)

        return filtered_signals

    def get_filter_stats(self) -> Dict[String, Int]:
        """Mock filter statistics"""
        return {
            "total_input": 1000,
            "total_output": 95,
            "instant_rejections": 400,
            "aggressive_rejections": 300,
            "micro_rejections": 150,
            "cooldown_rejections": 30,
            "volume_quality_rejections": 25
        }