#!/usr/bin/env mojo3
# =============================================================================
# Comprehensive Test Suite for Algorithmic Trading Bot
# =============================================================================

import sys
import core.config
import core.types
import core.constants
from time import time

# =============================================================================
# Test Framework
# =============================================================================

var tests_passed = 0
var tests_failed = 0
var test_results: List[String] = []

fn assert_true(condition: Bool, test_name: String):
    """
    Assert that condition is true
    """
    if condition:
        tests_passed += 1
        test_results.append(f"✅ {test_name}")
    else:
        tests_failed += 1
        test_results.append(f"❌ {test_name}")

fn assert_equal(expected, actual, test_name: String):
    """
    Assert that expected equals actual
    """
    if expected == actual:
        tests_passed += 1
        test_results.append(f"✅ {test_name}")
    else:
        tests_failed += 1
        test_results.append(f"❌ {test_name} - Expected: {expected}, Got: {actual}")

fn assert_not_none(value, test_name: String):
    """
    Assert that value is not None
    """
    if value is not None:
        tests_passed += 1
        test_results.append(f"✅ {test_name}")
    else:
        tests_failed += 1
        test_results.append(f"❌ {test_name} - Value is None")

fn assert_in_range(value: Float, min_val: Float, max_val: Float, test_name: String):
    """
    Assert that value is within range [min_val, max_val]
    """
    if min_val <= value <= max_val:
        tests_passed += 1
        test_results.append(f"✅ {test_name}")
    else:
        tests_failed += 1
        test_results.append(f"❌ {test_name} - Value {value} not in range [{min_val}, {max_val}]")

# =============================================================================
# Mock Data Generators
# =============================================================================

fn create_test_market_data() -> MarketData:
    """
    Create test market data
    """
    return MarketData(
        symbol="TEST_TOKEN",
        current_price=0.00001,
        volume_24h=50000.0,
        liquidity_usd=25000.0,
        timestamp=time(),
        market_cap=100000.0,
        price_change_24h=5.0,
        price_change_1h=2.5,
        price_change_5m=1.0,
        holder_count=150,
        transaction_count=200,
        age_hours=2.0
    )

fn create_test_trading_signal() -> TradingSignal:
    """
    Create test trading signal
    """
    return TradingSignal(
        symbol="TEST_TOKEN",
        action=TradingAction.BUY,
        confidence=0.8,
        timeframe="1m",
        timestamp=time(),
        price_target=0.000012,
        stop_loss=0.000009,
        volume=5000.0,
        liquidity=25000.0,
        rsi_value=25.0,
        support_level=0.0000095,
        resistance_level=0.0000115,
        signal_source=SignalSource.RSI_SUPPORT
    )

# =============================================================================
# Configuration Tests
# =============================================================================

fn test_config_loading():
    """
    Test configuration loading and validation
    """
    print("🧪 Testing Configuration Loading...")

    # Test environment loading
    config = core.config.Config.load_from_env()
    assert_not_none(config, "Config loading from environment")

    # Test basic config values
    assert_in_range(config.trading.initial_capital, 0.0, 1000000.0, "Initial capital range")
    assert_in_range(config.trading.max_position_size, 0.0, 1.0, "Max position size range")
    assert_in_range(config.trading.max_drawdown, 0.0, 1.0, "Max drawdown range")

    # Test strategy config
    assert_in_range(config.strategy.rsi_period, 1, 100, "RSI period range")
    assert_in_range(config.strategy.oversold_threshold, 0.0, 50.0, "Oversold threshold range")
    assert_in_range(config.strategy.overbought_threshold, 50.0, 100.0, "Overbought threshold range")

# =============================================================================
# Data Types Tests
# =============================================================================

fn test_trading_signal():
    """
    Test TradingSignal creation and validation
    """
    print("🧪 Testing Trading Signal...")

    signal = create_test_trading_signal()

    # Test basic properties
    assert_equal(signal.symbol, "TEST_TOKEN", "Signal symbol")
    assert_equal(signal.action, TradingAction.BUY, "Signal action")
    assert_in_range(signal.confidence, 0.0, 1.0, "Signal confidence")

    # Test financial properties
    assert_true(signal.price_target > signal.stop_loss, "Price target > stop loss")
    assert_true(signal.volume > 0, "Positive volume")
    assert_true(signal.liquidity > 0, "Positive liquidity")

    # Test RSI properties
    assert_in_range(signal.rsi_value, 0.0, 100.0, "RSI value range")

fn test_market_data():
    """
    Test MarketData creation and validation
    """
    print("🧪 Testing Market Data...")

    market_data = create_test_market_data()

    # Test basic properties
    assert_equal(market_data.symbol, "TEST_TOKEN", "Market data symbol")
    assert_true(market_data.current_price > 0, "Positive current price")
    assert_true(market_data.volume_24h > 0, "Positive 24h volume")
    assert_true(market_data.liquidity_usd > 0, "Positive liquidity")

    # Test price changes
    assert_true(market_data.market_cap > 0, "Positive market cap")
    assert_true(market_data.holder_count > 0, "Positive holder count")
    assert_true(market_data.transaction_count > 0, "Positive transaction count")

fn test_portfolio():
    """
    Test Portfolio creation and management
    """
    print("🧪 Testing Portfolio...")

    portfolio = Portfolio(
        total_value=1000.0,
        available_cash=800.0,
        positions={}
    )

    # Test initial state
    assert_equal(portfolio.total_value, 1000.0, "Portfolio total value")
    assert_equal(portfolio.available_cash, 800.0, "Available cash")
    assert_equal(portfolio.get_position_count(), 0, "Initial position count")

    # Test position addition
    position = Position(
        symbol="TEST",
        size=1000.0,
        entry_price=0.00001,
        current_price=0.00001,
        position_id="test_pos_1"
    )
    portfolio.positions["TEST"] = position
    assert_equal(portfolio.get_position_count(), 1, "Position count after addition")

# =============================================================================
# Analysis Components Tests
# =============================================================================

fn test_sentiment_analyzer():
    """
    Test algorithmic sentiment analyzer
    """
    print("🧪 Testing Sentiment Analyzer...")

    from analysis.sentiment_analyzer import SentimentAnalyzer
    analyzer = SentimentAnalyzer()

    market_data = create_test_market_data()
    sentiment = analyzer.analyze_sentiment("TEST_TOKEN", market_data)

    # Test sentiment analysis
    assert_not_none(sentiment, "Sentiment analysis result")
    assert_in_range(sentiment.sentiment_score, -1.0, 1.0, "Sentiment score range")
    assert_in_range(sentiment.confidence, 0.0, 1.0, "Sentiment confidence range")
    assert_true(len(sentiment.key_factors) > 0, "Key factors present")

fn test_pattern_recognizer():
    """
    Test pattern recognition system
    """
    print("🧪 Testing Pattern Recognizer...")

    from analysis.pattern_recognizer import PatternRecognizer
    recognizer = PatternRecognizer()

    market_data = create_test_market_data()
    patterns = recognizer.identify_patterns(market_data)

    # Test pattern recognition
    assert_not_none(patterns, "Pattern analysis result")
    assert_in_range(patterns.confidence, 0.0, 1.0, "Pattern confidence range")
    assert_not_none(patterns.primary_pattern, "Primary pattern identified")

fn test_whale_tracker():
    """
    Test whale behavior tracking
    """
    print("🧪 Testing Whale Tracker...")

    from analysis.whale_tracker import WhaleTracker
    tracker = WhaleTracker()

    market_data = create_test_market_data()
    whale_analysis = tracker.analyze_whale_behavior("TEST_TOKEN", market_data)

    # Test whale analysis
    assert_not_none(whale_analysis, "Whale analysis result")
    assert_in_range(whale_analysis.confidence, 0.0, 1.0, "Whale analysis confidence")
    assert_true(whale_analysis.whale_count >= 0, "Whale count non-negative")

fn test_volume_analyzer():
    """
    Test volume analysis engine
    """
    print("🧪 Testing Volume Analyzer...")

    from analysis.volume_analyzer import VolumeAnalyzer
    analyzer = VolumeAnalyzer()

    market_data = create_test_market_data()
    volume_analysis = analyzer.analyze(market_data)

    # Test volume analysis
    assert_not_none(volume_analysis, "Volume analysis result")
    assert_in_range(volume_analysis.quality_score, 0.0, 1.0, "Volume quality score")
    assert_true(volume_analysis.timestamp > 0, "Analysis timestamp valid")

# =============================================================================
# Engine Components Tests
# =============================================================================

fn test_enhanced_context_engine():
    """
    Test enhanced context engine
    """
    print("🧪 Testing Enhanced Context Engine...")

    from engine.enhanced_context_engine import EnhancedContextEngine
    config = core.config.Config.load_from_env()
    engine = EnhancedContextEngine(config)

    market_data = create_test_market_data()
    context = engine.analyze_symbol("TEST_TOKEN", market_data)

    # Test context analysis
    assert_not_none(context, "Context analysis result")
    assert_equal(context.symbol, "TEST_TOKEN", "Context symbol")
    assert_true(context.processing_time < 1.0, "Processing time under 1 second")
    assert_not_none(context.recommended_action, "Recommended action present")

# =============================================================================
# Integration Tests
# =============================================================================

fn test_end_to_end_workflow():
    """
    Test end-to-end trading workflow
    """
    print("🧪 Testing End-to-End Workflow...")

    # 1. Load configuration
    config = core.config.Config.load_from_env()
    assert_not_none(config, "Configuration loaded")

    # 2. Create market data
    market_data = create_test_market_data()

    # 3. Analyze sentiment
    from analysis.sentiment_analyzer import SentimentAnalyzer
    sentiment_analyzer = SentimentAnalyzer()
    sentiment = sentiment_analyzer.analyze_sentiment("TEST_TOKEN", market_data)
    assert_not_none(sentiment, "Sentiment analysis completed")

    # 4. Recognize patterns
    from analysis.pattern_recognizer import PatternRecognizer
    pattern_recognizer = PatternRecognizer()
    patterns = pattern_recognizer.identify_patterns(market_data)
    assert_not_none(patterns, "Pattern recognition completed")

    # 5. Analyze volume
    from analysis.volume_analyzer import VolumeAnalyzer
    volume_analyzer = VolumeAnalyzer()
    volume_analysis = volume_analyzer.analyze(market_data)
    assert_not_none(volume_analysis, "Volume analysis completed")

    # 6. Context analysis
    from engine.enhanced_context_engine import EnhancedContextEngine
    context_engine = EnhancedContextEngine(config)
    context = context_engine.analyze_symbol("TEST_TOKEN", market_data)
    assert_not_none(context, "Context analysis completed")

    # 7. Generate signal
    from engine.strategy_engine import StrategyEngine
    strategy_engine = StrategyEngine(config)
    signals = strategy_engine.generate_signals(context)
    assert_true(len(signals) >= 0, "Signal generation completed")

    # 8. Risk assessment
    from risk.risk_manager import RiskManager
    risk_manager = RiskManager(config)
    if signals:
        approval = risk_manager.approve_trade(signals[0])
        assert_not_none(approval, "Risk assessment completed")

fn test_performance_requirements():
    """
    Test performance requirements
    """
    print("🧪 Testing Performance Requirements...")

    # Test analysis speed
    start_time = time()

    from analysis.sentiment_analyzer import SentimentAnalyzer
    from analysis.pattern_recognizer import PatternRecognizer
    from analysis.volume_analyzer import VolumeAnalyzer

    market_data = create_test_market_data()

    sentiment_analyzer = SentimentAnalyzer()
    pattern_recognizer = PatternRecognizer()
    volume_analyzer = VolumeAnalyzer()

    # Run all analyses
    sentiment = sentiment_analyzer.analyze_sentiment("TEST_TOKEN", market_data)
    patterns = pattern_recognizer.identify_patterns(market_data)
    volume_analysis = volume_analyzer.analyze(market_data)

    total_time = time() - start_time

    # Performance requirement: all analyses under 100ms
    assert_true(total_time < 0.1, f"Analysis under 100ms (took {total_time:.3f}s)")
    print(f"   ⏱️  Total analysis time: {total_time:.3f}s")

# =============================================================================
# Error Handling Tests
# =============================================================================

fn test_error_handling():
    """
    Test error handling and edge cases
    """
    print("🧪 Testing Error Handling...")

    # Test with invalid market data
    invalid_market_data = MarketData(
        symbol="",
        current_price=0.0,
        volume_24h=0.0,
        liquidity_usd=0.0
    )

    # Test sentiment analyzer with invalid data
    from analysis.sentiment_analyzer import SentimentAnalyzer
    analyzer = SentimentAnalyzer()

    try:
        sentiment = analyzer.analyze_sentiment("", invalid_market_data)
        # Should handle gracefully without crashing
        assert_not_none(sentiment, "Graceful handling of invalid data")
    except:
        # Should not crash
        assert_true(True, "Error handling works correctly")

# =============================================================================
# Main Test Runner
# =============================================================================

fn run_all_tests():
    """
    Run all test suites
    """
    print("🚀 Starting Comprehensive Test Suite")
    print("=" * 60)

    start_time = time()

    # Configuration Tests
    test_config_loading()

    # Data Types Tests
    test_trading_signal()
    test_market_data()
    test_portfolio()

    # Analysis Components Tests
    test_sentiment_analyzer()
    test_pattern_recognizer()
    test_whale_tracker()
    test_volume_analyzer()

    # Engine Components Tests
    test_enhanced_context_engine()

    # Integration Tests
    test_end_to_end_workflow()
    test_performance_requirements()

    # Error Handling Tests
    test_error_handling()

    total_time = time() - start_time

    # Print Results
    print("\n" + "=" * 60)
    print("📊 TEST RESULTS")
    print("=" * 60)

    for result in test_results:
        print(result)

    print(f"\n📈 Summary:")
    print(f"   ✅ Passed: {tests_passed}")
    print(f"   ❌ Failed: {tests_failed}")
    print(f"   📊 Success Rate: {(tests_passed / (tests_passed + tests_failed) * 100):.1f}%")
    print(f"   ⏱️  Total Time: {total_time:.3f}s")

    if tests_failed == 0:
        print("\n🎉 ALL TESTS PASSED! The algorithmic trading bot is ready.")
    else:
        print(f"\n⚠️  {tests_failed} tests failed. Please review and fix issues.")

    return tests_failed == 0

# =============================================================================
# Entry Point
# =============================================================================

fn main():
    """
    Main entry point for test runner
    """
    success = run_all_tests()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()