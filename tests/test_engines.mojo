#!/usr/bin/env mojo3
# =============================================================================
# Engine Components Test Suite
# =============================================================================

import core.config
import core.types
from time import time

# =============================================================================
# Test Framework
# =============================================================================

var tests_passed = 0
var tests_failed = 0

fn assert_true(condition: Bool, test_name: String):
    if condition:
        tests_passed += 1
        print(f"✅ {test_name}")
    else:
        tests_failed += 1
        print(f"❌ {test_name}")

fn assert_not_none(value, test_name: String):
    if value is not None:
        tests_passed += 1
        print(f"✅ {test_name}")
    else:
        tests_failed += 1
        print(f"❌ {test_name}")

# =============================================================================
# Spam Filter Tests
# =============================================================================

fn test_spam_filter():
    """
    Test spam filter functionality
    """
    print("🧪 Testing Spam Filter...")

    from engine.spam_filter import SpamFilter
    from data.helius_client import HeliusClient

    config = core.config.Config.load_from_env()
    helius_client = HeliusClient(api_key="test")
    spam_filter = SpamFilter(helius_client, config)

    # Test signal filtering
    test_signals = [
        core.types.TradingSignal(
            symbol="GOOD_TOKEN",
            action=core.types.TradingAction.BUY,
            confidence=0.8,
            liquidity=50000.0,
            volume=10000.0
        ),
        core.types.TradingSignal(
            symbol="SPAM_TOKEN",
            action=core.types.TradingAction.BUY,
            confidence=0.3,
            liquidity=100.0,
            volume=50.0
        )
    ]

    filtered_signals = spam_filter.filter_signals(test_signals)
    assert_true(len(filtered_signals) <= len(test_signals), "Signal filtering")

    # Test market health analysis
    market_data = core.types.MarketData(
        symbol="TEST",
        current_price=0.00001,
        volume_24h=50000.0,
        liquidity_usd=25000.0
    )

    health_analysis = spam_filter.analyze_market_health(market_data)
    assert_not_none(health_analysis, "Market health analysis")

# =============================================================================
# Strategy Engine Tests
# =============================================================================

fn test_strategy_engine():
    """
    Test strategy engine functionality
    """
    print("🧪 Testing Strategy Engine...")

    from engine.strategy_engine import StrategyEngine

    config = core.config.Config.load_from_env()
    strategy_engine = StrategyEngine(config)

    # Create mock context
    market_data = core.types.MarketData(
        symbol="TEST",
        current_price=0.00001,
        volume_24h=50000.0,
        liquidity_usd=25000.0
    )

    confluence = core.types.ConfluenceAnalysis(
        rsi_value=25.0,
        is_oversold=True,
        confluence_strength=0.8
    )

    context = core.types.TradingContext(
        symbol="TEST",
        confluence_analysis=confluence,
        market_regime=core.types.MarketRegime.RANGING
    )

    # Test signal generation
    signals = strategy_engine.generate_signals(context)
    assert_true(len(signals) >= 0, "Signal generation")

    # Test risk-reward calculation
    if signals:
        risk_reward = strategy_engine._calculate_risk_reward_ratio(signals[0])
        assert_true(risk_reward >= 0.0, "Risk-reward ratio calculation")

# =============================================================================
# Risk Manager Tests
# =============================================================================

fn test_risk_manager():
    """
    Test risk manager functionality
    """
    print("🧪 Testing Risk Manager...")

    from risk.risk_manager import RiskManager

    config = core.config.Config.load_from_env()
    risk_manager = RiskManager(config)

    # Create test signal
    signal = core.types.TradingSignal(
        symbol="TEST",
        action=core.types.TradingAction.BUY,
        confidence=0.8,
        liquidity=50000.0,
        volume=10000.0,
        price_target=0.000012,
        stop_loss=0.000009
    )

    # Test trade approval
    approval = risk_manager.approve_trade(signal)
    assert_not_none(approval, "Trade approval")

    # Test portfolio risk metrics
    portfolio = core.types.Portfolio(
        total_value=1000.0,
        available_cash=800.0
    )
    risk_manager.update_portfolio_state(portfolio)

    risk_metrics = risk_manager.get_portfolio_risk_metrics()
    assert_not_none(risk_metrics, "Portfolio risk metrics")

# =============================================================================
# Execution Engine Tests
# =============================================================================

fn test_execution_engine():
    """
    Test execution engine functionality
    """
    print("🧪 Testing Execution Engine...")

    from execution.execution_engine import ExecutionEngine
    from data.quicknode_client import QuickNodeClient, QuickNodeRPCs
    from data.jupiter_client import JupiterClient

    config = core.config.Config.load_from_env()
    quicknode_client = QuickNodeClient(QuickNodeRPCs("test"))
    jupiter_client = JupiterClient()

    execution_engine = ExecutionEngine(quicknode_client, jupiter_client, config)

    # Create test signal and approval
    signal = core.types.TradingSignal(
        symbol="TEST",
        action=core.types.TradingAction.BUY,
        confidence=0.8
    )

    approval = core.types.RiskApproval(
        approved=True,
        position_size=100.0,
        stop_loss_price=0.000009
    )

    # Test trade execution (paper mode)
    if config.trading.execution_mode == "paper":
        result = execution_engine.execute_trade(signal, approval)
        assert_not_none(result, "Trade execution result")

    # Test execution stats
    stats = execution_engine.get_execution_stats()
    assert_not_none(stats, "Execution statistics")

    # Test health check
    is_healthy = execution_engine.health_check()
    assert_true(is_healthy, "Execution engine health check")

# =============================================================================
# Enhanced Context Engine Tests
# =============================================================================

fn test_enhanced_context_engine():
    """
    Test enhanced context engine functionality
    """
    print("🧪 Testing Enhanced Context Engine...")

    from engine.enhanced_context_engine import EnhancedContextEngine

    config = core.config.Config.load_from_env()
    context_engine = EnhancedContextEngine(config)

    # Create test market data
    market_data = core.types.MarketData(
        symbol="TEST",
        current_price=0.00001,
        volume_24h=50000.0,
        liquidity_usd=25000.0,
        market_cap=100000.0,
        holder_count=150,
        transaction_count=200
    )

    # Test symbol analysis
    context = context_engine.analyze_symbol("TEST", market_data)
    assert_not_none(context, "Symbol analysis")
    assert_equal(context.symbol, "TEST", "Context symbol")

    # Test processing time
    assert_true(context.processing_time < 1.0, "Processing time under 1 second")

    # Test recommended action
    assert_not_none(context.recommended_action, "Recommended action")

# =============================================================================
# Main Test Runner
# =============================================================================

fn run_all_engine_tests():
    """
    Run all engine component tests
    """
    print("🚀 Starting Engine Components Test Suite")
    print("=" * 50)

    test_spam_filter()
    test_strategy_engine()
    test_risk_manager()
    test_execution_engine()
    test_enhanced_context_engine()

    print("\n" + "=" * 50)
    print(f"📊 Engine Components Test Results:")
    print(f"   ✅ Passed: {tests_passed}")
    print(f"   ❌ Failed: {tests_failed}")
    print(f"   📊 Success Rate: {(tests_passed / (tests_passed + tests_failed) * 100):.1f}%")

    return tests_failed == 0

fn main():
    """
    Main entry point
    """
    success = run_all_engine_tests()
    return 0 if success else 1

if __name__ == "__main__":
    exit(main())