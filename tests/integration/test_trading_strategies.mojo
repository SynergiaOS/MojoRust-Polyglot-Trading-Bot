#!/usr/bin/env mojo3

# =============================================================================
# Trading Strategies Integration Tests
# =============================================================================
# End-to-end tests for strategy engines, risk management, and execution
# =============================================================================

import sys
from time import time
from collections import Dict, List

# Add source path
sys.path.append("../../src")

# Import core types and test utilities
from core.types import (
    MarketData, TradingSignal, SignalSource, TradingAction,
    Portfolio, RiskApproval, SocialMetrics, BlockchainMetrics,
    TradeRecord, SentimentAnalysis, RiskAnalysis
)
from core.config import Config

# Import mock loader for market scenarios
from tests.mocks.mock_loader import load_market_scenario

# =============================================================================
# Test Framework
# =============================================================================

var test_count = 0
var passed_tests = 0
var failed_tests = 0

fn assert_equal(actual, expected, test_name: String):
    test_count += 1
    if actual == expected:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: {expected}, Got: {actual}")

fn assert_true(condition: Bool, test_name: String):
    test_count += 1
    if condition:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: True, Got: False")

fn assert_false(condition: Bool, test_name: String):
    test_count += 1
    if not condition:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: False, Got: True")

fn assert_close(actual: Float, expected: Float, tolerance: Float, test_name: String):
    test_count += 1
    if abs(actual - expected) <= tolerance:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected: {expected} ± {tolerance}, Got: {actual}")

fn assert_in_range(value: Float, min_val: Float, max_val: Float, test_name: String):
    test_count += 1
    if value >= min_val and value <= max_val:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected range: [{min_val}, {max_val}], Got: {value}")

fn assert_not_none(value, test_name: String):
    test_count += 1
    if value is not None:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected non-None value")

fn assert_dict_contains(dict_obj: Dict[String, Any], key: String, test_name: String):
    test_count += 1
    if key in dict_obj:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Dictionary missing key: {key}")

fn assert_list_not_empty(list_obj: List[Any], test_name: String):
    test_count += 1
    if len(list_obj) > 0:
        passed_tests += 1
        print(f"✅ PASS: {test_name}")
    else:
        failed_tests += 1
        print(f"❌ FAIL: {test_name}")
        print(f"   Expected non-empty list")

# =============================================================================
# Mock Strategy Engine
# =============================================================================

@value
struct MockStrategyEngine:
    """
    Mock strategy engine for testing
    Simulates signal generation and analysis
    """
    var confidence_threshold: Float

    fn __init__(confidence_threshold: Float = 0.7):
        self.confidence_threshold = confidence_threshold

    fn generate_signal(self, market_data: MarketData) -> TradingSignal:
        """Generate trading signal based on market data"""
        start_time = time()

        # Simple signal generation logic based on market conditions
        confidence = 0.0
        action = TradingAction.HOLD
        reasoning = ""

        # Price momentum signal
        if market_data.price_change_1h > 0.05 and market_data.price_change_5m > 0.02:
            confidence += 0.3
            action = TradingAction.BUY
            reasoning += "Strong upward momentum; "

        elif market_data.price_change_1h < -0.05 and market_data.price_change_5m < -0.02:
            confidence += 0.3
            action = TradingAction.SELL
            reasoning += "Strong downward momentum; "

        # Volume confirmation
        if market_data.volume_24h > 100000:
            confidence += 0.2
            reasoning += "High volume support; "

        # Liquidity check
        if market_data.liquidity_usd > 50000:
            confidence += 0.2
            reasoning += "Good liquidity; "

        # Social sentiment
        if market_data.social_metrics.twitter_mentions > 100:
            confidence += 0.1
            reasoning += "Social activity; "

        # Risk adjustments
        if market_data.blockchain_metrics.wash_trading_score > 0.5:
            confidence *= 0.5
            reasoning += "High wash trading risk; "

        if market_data.holder_count < 50:
            confidence *= 0.7
            reasoning += "Low holder count; "

        # Clamp confidence to [0, 1]
        confidence = max(0.0, min(1.0, confidence))

        # Generate price targets
        price_target = market_data.current_price * 1.1 if action == TradingAction.BUY else market_data.current_price * 0.9
        stop_loss = market_data.current_price * 0.9 if action == TradingAction.BUY else market_data.current_price * 1.1

        signal = TradingSignal(
            symbol=market_data.symbol,
            action=action,
            confidence=confidence,
            timeframe="1m",
            timestamp=start_time,
            price_target=price_target,
            stop_loss=stop_loss,
            volume=market_data.volume_24h / (24 * 12),  # Approximate 5m volume
            liquidity=market_data.liquidity_usd,
            rsi_value=self._calculate_rsi(market_data),
            support_level=market_data.current_price * 0.95,
            resistance_level=market_data.current_price * 1.05,
            signal_source=SignalSource.AI_SENTIMENT,
            metadata={
                "price_change_5m": market_data.price_change_5m,
                "volume_5m": market_data.volume_24h / (24 * 12),
                "holder_count": market_data.holder_count,
                "age_hours": market_data.age_hours,
                "reasoning": reasoning
            }
        )

        processing_time = time() - start_time
        signal.metadata["processing_time_ms"] = processing_time * 1000

        return signal

    fn _calculate_rsi(self, market_data: MarketData) -> Float:
        """Mock RSI calculation"""
        # Simple mock RSI based on price changes
        rsi = 50.0 + market_data.price_change_1h * 100
        return max(0.0, min(100.0, rsi))

# =============================================================================
# Mock Risk Manager
# =============================================================================

@value
struct MockRiskManager:
    """
    Mock risk manager for testing
    Simulates risk assessment and approval
    """
    var max_drawdown: Float
    var max_position_size: Float

    fn __init__(max_drawdown: Float = 0.15, max_position_size: Float = 0.1):
        self.max_drawdown = max_drawdown
        self.max_position_size = max_position_size

    fn evaluate_risk(self, signal: TradingSignal, portfolio: Portfolio) -> RiskApproval:
        """Evaluate risk for a trading signal"""
        start_time = time()

        # Check circuit breaker (drawdown)
        if portfolio.peak_value > 0:
            drawdown = (portfolio.peak_value - portfolio.total_value) / portfolio.peak_value
            if drawdown > self.max_drawdown:
                return RiskApproval(
                    approved=False,
                    reason=f"Circuit breaker triggered - drawdown {drawdown:.2%} exceeds limit {self.max_drawdown:.2%}"
                )

        # Check position size
        position_value = signal.price_target * signal.volume
        if position_value > portfolio.total_value * self.max_position_size:
            return RiskApproval(
                approved=False,
                reason=f"Position size {position_value:.4f} exceeds limit {portfolio.total_value * self.max_position_size:.4f}"
            )

        # Check signal confidence
        if signal.confidence < 0.6:
            return RiskApproval(
                approved=False,
                reason=f"Signal confidence {signal.confidence:.2f} below threshold 0.6"
            )

        # Check liquidity
        if signal.liquidity < 10000:
            return RiskApproval(
                approved=False,
                reason=f"Insufficient liquidity: {signal.liquidity:.2f}"
            )

        # Calculate risk/reward ratio
        risk_reward_ratio = self._calculate_risk_reward_ratio(signal)
        if risk_reward_ratio < 1.5:
            return RiskApproval(
                approved=False,
                reason=f"Risk/reward ratio {risk_reward_ratio:.2f} below threshold 1.5"
            )

        # Calculate position size
        approved_size = min(
            portfolio.total_value * 0.05,  # 5% max per trade
            portfolio.available_cash * 0.8,  # 80% of available cash
            signal.liquidity * 0.01  # 1% of liquidity
        )

        processing_time = time() - start_time

        return RiskApproval(
            approved=True,
            reason="Risk check passed",
            position_size=approved_size,
            stop_loss_price=signal.stop_loss,
            max_position_size=portfolio.total_value * self.max_position_size,
            expected_risk_reward_ratio=risk_reward_ratio
        )

    fn _calculate_risk_reward_ratio(self, signal: TradingSignal) -> Float:
        """Calculate risk/reward ratio"""
        if signal.action == TradingAction.BUY:
            potential_profit = signal.price_target - signal.current_price if hasattr(signal, 'current_price') else signal.price_target - signal.price_target * 0.95
            potential_loss = signal.price_target - signal.stop_loss
        else:
            potential_profit = signal.stop_loss - signal.price_target if hasattr(signal, 'current_price') else signal.stop_loss - signal.price_target * 1.05
            potential_loss = signal.stop_loss - signal.price_target

        return potential_profit / potential_loss if potential_loss > 0 else 0.0

# =============================================================================
# Mock Executor
# =============================================================================

@value
struct MockExecutor:
    """
    Mock executor for testing
    Simulates trade execution
    """
    var execution_delay_ms: Float
    var slippage_rate: Float

    fn __init__(execution_delay_ms: Float = 100.0, slippage_rate: Float = 0.1):
        self.execution_delay_ms = execution_delay_ms
        self.slippage_rate = slippage_rate

    fn execute_trade(self, signal: TradingSignal, risk_approval: RiskApproval) -> TradeRecord:
        """Execute a trade based on signal and risk approval"""
        start_time = time()

        # Simulate execution delay
        # In real implementation, this would be async

        # Calculate executed price with slippage
        slippage_amount = signal.price_target * self.slippage_rate / 100
        if signal.action == TradingAction.BUY:
            executed_price = signal.price_target + slippage_amount
        else:
            executed_price = signal.price_target - slippage_amount

        # Create trade record
        trade = TradeRecord(
            symbol=signal.symbol,
            action=str(signal.action),
            quantity=risk_approval.position_size / executed_price,
            price=signal.price_target,
            executed_price=executed_price,
            timestamp=start_time,
            tx_hash=f"mock_tx_{int(start_time * 1000)}",
            status="COMPLETED",
            gas_cost=0.000005,  # Mock gas cost
            slippage=self.slippage_rate,
            portfolio_id="test_portfolio"
        )

        processing_time = time() - start_time
        trade.timestamp = start_time + processing_time

        return trade

# =============================================================================
# Mock Sentiment Analyzer
# =============================================================================

@value
struct MockSentimentAnalyzer:
    """
    Mock sentiment analyzer for testing
    Simulates AI-powered sentiment analysis
    """
    fn analyze_sentiment(self, market_data: MarketData) -> SentimentAnalysis:
        """Analyze sentiment for market data"""
        start_time = time()

        sentiment_score = 0.0
        confidence = 0.7
        key_factors: List[String] = []

        # Social sentiment factors
        if market_data.social_metrics.twitter_mentions > 500:
            sentiment_score += 0.3
            key_factors.append("High Twitter activity")

        if market_data.social_metrics.social_sentiment > 0.5:
            sentiment_score += 0.2
            key_factors.append("Positive social sentiment")

        # Market momentum factors
        if market_data.price_change_24h > 0.1:
            sentiment_score += 0.2
            key_factors.append("Strong daily performance")

        elif market_data.price_change_24h < -0.1:
            sentiment_score -= 0.2
            key_factors.append("Poor daily performance")

        # Volume factors
        if market_data.volume_24h > 1000000:
            sentiment_score += 0.1
            key_factors.append("High trading volume")

        # Blockchain factors
        if market_data.blockchain_metrics.wash_trading_score < 0.3:
            sentiment_score += 0.1
            key_factors.append("Low wash trading risk")

        if market_data.blockchain_metrics.unique_traders > 1000:
            sentiment_score += 0.1
            key_factors.append("Diverse trader base")

        # Clamp sentiment score
        sentiment_score = max(-1.0, min(1.0, sentiment_score))

        # Determine recommendation
        if sentiment_score > 0.3:
            recommendation = TradingAction.BUY
        elif sentiment_score < -0.3:
            recommendation = TradingAction.SELL
        else:
            recommendation = TradingAction.HOLD

        processing_time = time() - start_time

        return SentimentAnalysis(
            sentiment_score=sentiment_score,
            confidence=confidence,
            key_factors=key_factors,
            recommendation=recommendation,
            social_volume=Float(market_data.social_metrics.twitter_mentions),
            social_sentiment=market_data.social_metrics.social_sentiment
        )

# =============================================================================
# End-to-End Signal Generation Tests
# =============================================================================

fn test_end_to_end_signal_generation():
    print("\n🧪 Testing End-to-End Signal Generation...")

    # Initialize components
    strategy_engine = MockStrategyEngine()
    sentiment_analyzer = MockSentimentAnalyzer()

    # Test with different market scenarios
    scenarios = ["bull_market", "bear_market", "sideways_market", "pump_and_dump"]

    for scenario_name in scenarios:
        print(f"\n  Testing scenario: {scenario_name}")

        # Load market scenario
        scenario = load_market_scenario(scenario_name)
        assert_not_none(scenario, f"Scenario {scenario_name} loaded")

        if not scenario:
            continue

        # Create market data from scenario
        market_data = MarketData(
            symbol="TEST_TOKEN",
            current_price=scenario["market_data"]["price"],
            volume_24h=scenario["market_data"]["volume_24h"],
            liquidity_usd=scenario["market_data"]["liquidity"],
            timestamp=scenario["market_data"]["timestamp"],
            market_cap=scenario["market_data"]["market_cap"],
            price_change_24h=scenario["market_data"]["price_change_24h"],
            price_change_1h=scenario["market_data"]["price_change_1h"],
            price_change_5m=0.02,  # Mock 5m change
            holder_count=150,  # Mock holder count
            transaction_count=500,  # Mock transaction count
            age_hours=6.0,  # Mock age
            social_metrics=SocialMetrics(
                twitter_mentions=100,
                telegram_members=200,
                social_sentiment=0.5
            ),
            blockchain_metrics=BlockchainMetrics(
                unique_traders=75,
                wash_trading_score=0.2
            )
        )

        # Generate trading signal
        signal = strategy_engine.generate_signal(market_data)
        assert_not_none(signal, f"Signal generated for {scenario_name}")
        assert_in_range(signal.confidence, 0.0, 1.0, f"Signal confidence in range for {scenario_name}")
        assert_dict_contains(signal.metadata, "processing_time_ms", f"Signal has processing time for {scenario_name}")

        # Analyze sentiment
        sentiment = sentiment_analyzer.analyze_sentiment(market_data)
        assert_not_none(sentiment, f"Sentiment analysis completed for {scenario_name}")
        assert_in_range(sentiment.sentiment_score, -1.0, 1.0, f"Sentiment score in range for {scenario_name}")
        assert_in_range(sentiment.confidence, 0.0, 1.0, f"Sentiment confidence in range for {scenario_name}")
        assert_list_not_empty(sentiment.key_factors, f"Sentiment has key factors for {scenario_name}")

        # Add sentiment to signal
        signal.sentiment_score = sentiment.sentiment_score
        signal.ai_analysis = sentiment

        # Validate signal structure
        assert_true(hasattr(signal, "symbol"), f"Signal has symbol for {scenario_name}")
        assert_true(hasattr(signal, "action"), f"Signal has action for {scenario_name}")
        assert_true(hasattr(signal, "confidence"), f"Signal has confidence for {scenario_name}")
        assert_true(signal.price_target > 0, f"Signal has positive price target for {scenario_name}")
        assert_true(signal.stop_loss > 0, f"Signal has positive stop loss for {scenario_name}")

        print(f"    ✅ {scenario_name}: Action={signal.action}, Confidence={signal.confidence:.2f}")

        # Compare with expected signals
        if "expected_signals" in scenario:
            expected_signals = scenario["expected_signals"]
            if len(expected_signals) > 0:
                expected_action = expected_signals[0]["action"]
                if expected_action == "BUY" and signal.action != TradingAction.BUY:
                    print(f"    ⚠️  Expected BUY but got {signal.action}")
                elif expected_action == "SELL" and signal.action != TradingAction.SELL:
                    print(f"    ⚠️  Expected SELL but got {signal.action}")
                elif expected_action == "HOLD" and signal.action != TradingAction.HOLD:
                    print(f"    ⚠️  Expected HOLD but got {signal.action}")

    print("✅ End-to-end signal generation tests completed")

# =============================================================================
# Ensemble Consensus Tests
# =============================================================================

fn test_ensemble_consensus():
    print("\n🧪 Testing Ensemble Consensus...")

    # Create multiple strategy engines with different parameters
    engines = [
        MockStrategyEngine(0.6),  # Low threshold
        MockStrategyEngine(0.7),  # Medium threshold
        MockStrategyEngine(0.8),  # High threshold
    ]

    # Load test scenario
    scenario = load_market_scenario("bull_market")
    assert_not_none(scenario, "Bull market scenario loaded")

    if scenario:
        # Create market data
        market_data = MarketData(
            symbol="TEST_TOKEN",
            current_price=scenario["market_data"]["price"],
            volume_24h=scenario["market_data"]["volume_24h"],
            liquidity_usd=scenario["market_data"]["liquidity"],
            timestamp=scenario["market_data"]["timestamp"],
            market_cap=scenario["market_data"]["market_cap"],
            price_change_24h=scenario["market_data"]["price_change_24h"],
            price_change_1h=scenario["market_data"]["price_change_1h"],
            price_change_5m=0.03,
            holder_count=200,
            transaction_count=800,
            age_hours=4.0,
            social_metrics=SocialMetrics(twitter_mentions=150, telegram_members=300),
            blockchain_metrics=BlockchainMetrics(unique_traders=120, wash_trading_score=0.1)
        )

        # Generate signals from all engines
        signals: List[TradingSignal] = []
        for i, engine in enumerate(engines):
            signal = engine.generate_signal(market_data)
            signals.append(signal)
            print(f"    Engine {i+1}: {signal.action} (conf: {signal.confidence:.2f})")

        # Calculate consensus
        buy_votes = len([s for s in signals if s.action == TradingAction.BUY])
        sell_votes = len([s for s in signals if s.action == TradingAction.SELL])
        hold_votes = len([s for s in signals if s.action == TradingAction.HOLD])

        # Determine consensus action
        if buy_votes > sell_votes and buy_votes > hold_votes:
            consensus_action = TradingAction.BUY
        elif sell_votes > buy_votes and sell_votes > hold_votes:
            consensus_action = TradingAction.SELL
        else:
            consensus_action = TradingAction.HOLD

        # Calculate average confidence
        avg_confidence = sum([s.confidence for s in signals]) / len(signals)

        print(f"    Consensus: {consensus_action} (avg conf: {avg_confidence:.2f})")
        print(f"    Vote distribution: BUY={buy_votes}, SELL={sell_votes}, HOLD={hold_votes}")

        # Validate consensus
        assert_equal(len(signals), 3, "Generated signals from all engines")
        assert_true(avg_confidence >= 0.0 and avg_confidence <= 1.0, "Average confidence in range")
        assert_true(buy_votes + sell_votes + hold_votes == 3, "Vote count matches engines")

    print("✅ Ensemble consensus tests completed")

# =============================================================================
# Risk Approval Tests
# =============================================================================

fn test_risk_approval():
    print("\n🧪 Testing Risk Approval...")

    # Initialize components
    strategy_engine = MockStrategyEngine()
    risk_manager = MockRiskManager()

    # Create test portfolio
    portfolio = Portfolio(
        total_value=10.0,
        available_cash=5.0,
        daily_pnl=0.5,
        total_pnl=1.5,
        peak_value=10.5,
        trade_count_today=3,
        last_reset_timestamp=time()
    )

    # Test different signal scenarios
    test_scenarios = [
        {
            "name": "High confidence BUY",
            "action": TradingAction.BUY,
            "confidence": 0.9,
            "liquidity": 100000,
            "expected_approval": True
        },
        {
            "name": "Low confidence signal",
            "action": TradingAction.BUY,
            "confidence": 0.4,
            "liquidity": 100000,
            "expected_approval": False
        },
        {
            "name": "Low liquidity",
            "action": TradingAction.BUY,
            "confidence": 0.8,
            "liquidity": 5000,
            "expected_approval": False
        },
        {
            "name": "High confidence SELL",
            "action": TradingAction.SELL,
            "confidence": 0.85,
            "liquidity": 100000,
            "expected_approval": True
        }
    ]

    for scenario in test_scenarios:
        print(f"\n  Testing: {scenario['name']}")

        # Create market data
        market_data = MarketData(
            symbol="TEST_TOKEN",
            current_price=1.0,
            volume_24h=50000,
            liquidity_usd=scenario["liquidity"],
            timestamp=time(),
            market_cap=1000000,
            price_change_24h=0.05,
            price_change_1h=0.02,
            price_change_5m=0.01,
            holder_count=100,
            transaction_count=300,
            age_hours=12.0,
            social_metrics=SocialMetrics(),
            blockchain_metrics=BlockchainMetrics()
        )

        # Generate signal
        signal = strategy_engine.generate_signal(market_data)
        signal.action = scenario["action"]
        signal.confidence = scenario["confidence"]
        signal.liquidity = scenario["liquidity"]

        # Evaluate risk
        risk_approval = risk_manager.evaluate_risk(signal, portfolio)
        assert_not_none(risk_approval, f"Risk evaluation completed for {scenario['name']}")
        assert_equal(risk_approval.approved, scenario["expected_approval"],
                    f"Risk approval matches expected for {scenario['name']}")

        if risk_approval.approved:
            assert_true(risk_approval.position_size > 0, f"Approved position size positive for {scenario['name']}")
            assert_true(risk_approval.expected_risk_reward_ratio > 1.0,
                       f"Risk/reward ratio acceptable for {scenario['name']}")

        print(f"    Result: {'APPROVED' if risk_approval.approved else 'REJECTED'}")
        print(f"    Reason: {risk_approval.reason}")

    # Test drawdown scenario
    print(f"\n  Testing: Maximum drawdown scenario")

    # Create portfolio with high drawdown
    drawdown_portfolio = Portfolio(
        total_value=8.5,
        available_cash=2.0,
        daily_pnl=-1.0,
        total_pnl=-0.5,
        peak_value=10.0,  # 15% drawdown
        trade_count_today=5,
        last_reset_timestamp=time()
    )

    # Create signal for drawdown test
    market_data = MarketData(
        symbol="TEST_TOKEN",
        current_price=1.0,
        volume_24h=50000,
        liquidity_usd=100000,
        timestamp=time(),
        market_cap=1000000,
        price_change_24h=0.05,
        price_change_1h=0.02,
        price_change_5m=0.01,
        holder_count=100,
        transaction_count=300,
        age_hours=12.0,
        social_metrics=SocialMetrics(),
        blockchain_metrics=BlockchainMetrics()
    )

    signal = strategy_engine.generate_signal(market_data)
    signal.confidence = 0.9  # High confidence

    # Evaluate risk with drawdown
    risk_approval = risk_manager.evaluate_risk(signal, drawdown_portfolio)
    assert_false(risk_approval.approved, "High drawdown triggers circuit breaker")
    assert_true("circuit breaker" in risk_approval.reason.lower(),
                "Drawdown reason mentions circuit breaker")

    print(f"    Result: REJECTED (circuit breaker)")
    print(f"    Reason: {risk_approval.reason}")

    print("✅ Risk approval tests completed")

# =============================================================================
# Mock Execution Tests
# =============================================================================

fn test_mock_execution():
    print("\n🧪 Testing Mock Execution...")

    # Initialize components
    strategy_engine = MockStrategyEngine()
    risk_manager = MockRiskManager()
    executor = MockExecutor()

    # Create test portfolio
    portfolio = Portfolio(
        total_value=10.0,
        available_cash=5.0,
        daily_pnl=0.2,
        total_pnl=1.0,
        peak_value=10.2,
        trade_count_today=2,
        last_reset_timestamp=time()
    )

    # Create market data for execution test
    market_data = MarketData(
        symbol="EXEC_TOKEN",
        current_price=0.5,
        volume_24h=100000,
        liquidity_usd=50000,
        timestamp=time(),
        market_cap=500000,
        price_change_24h=0.08,
        price_change_1h=0.03,
        price_change_5m=0.01,
        holder_count=150,
        transaction_count=600,
        age_hours=8.0,
        social_metrics=SocialMetrics(twitter_mentions=80, telegram_members=160),
        blockchain_metrics=BlockchainMetrics(unique_traders=100, wash_trading_score=0.15)
    )

    # Generate signal
    signal = strategy_engine.generate_signal(market_data)
    assert_not_none(signal, "Signal generated for execution test")

    # Evaluate risk
    risk_approval = risk_manager.evaluate_risk(signal, portfolio)
    assert_not_none(risk_approval, "Risk evaluation completed for execution test")

    if risk_approval.approved:
        # Execute trade
        trade = executor.execute_trade(signal, risk_approval)
        assert_not_none(trade, "Trade executed successfully")
        assert_equal(trade.symbol, signal.symbol, "Trade symbol matches signal")
        assert_equal(trade.action, str(signal.action), "Trade action matches signal")
        assert_true(trade.quantity > 0, "Trade quantity positive")
        assert_true(trade.executed_price > 0, "Executed price positive")
        assert_equal(trade.status, "COMPLETED", "Trade status completed")
        assert_true(len(trade.tx_hash) > 0, "Trade has transaction hash")
        assert_true(trade.gas_cost >= 0, "Gas cost non-negative")
        assert_true(trade.slippage >= 0, "Slippage non-negative")

        print(f"    Executed: {trade.quantity:.6f} {trade.symbol} @ {trade.executed_price:.6f}")
        print(f"    Transaction: {trade.tx_hash}")
        print(f"    Slippage: {trade.slippage:.2f}%")
        print(f"    Gas cost: {trade.gas_cost:.6f}")

        # Validate trade execution metrics
        # Check if executed price is reasonable (within expected slippage)
        expected_slippage_range = signal.price_target * (executor.slippage_rate / 100)
        price_difference = abs(trade.executed_price - signal.price_target)
        assert_true(price_difference <= expected_slippage_range * 2,
                   "Executed price within reasonable slippage range")

    else:
        print(f"    Trade not executed: {risk_approval.reason}")

    print("✅ Mock execution tests completed")

# =============================================================================
# Full Trading Cycle Tests
# =============================================================================

fn test_full_trading_cycle():
    print("\n🧪 Testing Full Trading Cycle...")

    # Initialize components
    strategy_engine = MockStrategyEngine()
    sentiment_analyzer = MockSentimentAnalyzer()
    risk_manager = MockRiskManager()
    executor = MockExecutor()

    # Create test portfolio
    portfolio = Portfolio(
        total_value=10.0,
        available_cash=6.0,
        positions={},
        daily_pnl=0.0,
        total_pnl=0.0,
        peak_value=10.0,
        trade_count_today=0,
        last_reset_timestamp=time()
    )

    # Test with multiple scenarios
    scenarios = ["bull_market", "arbitrage_opportunity", "new_token_launch"]

    for scenario_name in scenarios:
        print(f"\n  Running full cycle: {scenario_name}")

        # Load scenario
        scenario = load_market_scenario(scenario_name)
        if not scenario:
            continue

        # Create market data
        market_data = MarketData(
            symbol=f"CYCLE_{scenario_name.upper()}",
            current_price=scenario["market_data"]["price"],
            volume_24h=scenario["market_data"]["volume_24h"],
            liquidity_usd=scenario["market_data"]["liquidity"],
            timestamp=scenario["market_data"]["timestamp"],
            market_cap=scenario["market_data"]["market_cap"],
            price_change_24h=scenario["market_data"]["price_change_24h"],
            price_change_1h=scenario["market_data"]["price_change_1h"],
            price_change_5m=0.015,
            holder_count=200,
            transaction_count=1000,
            age_hours=scenario["market_data"].get("age_hours", 6.0),
            social_metrics=SocialMetrics(
                twitter_mentions=120,
                telegram_members=250,
                social_sentiment=0.6
            ),
            blockchain_metrics=BlockchainMetrics(
                unique_traders=150,
                wash_trading_score=0.12
            )
        )

        # Step 1: Signal Generation
        start_time = time()
        signal = strategy_engine.generate_signal(market_data)
        signal_generation_time = time() - start_time

        assert_not_none(signal, f"Signal generated for {scenario_name}")
        assert_in_range(signal.confidence, 0.0, 1.0, f"Signal confidence valid for {scenario_name}")
        assert_true(signal_generation_time < 0.1, f"Signal generation fast for {scenario_name}")

        # Step 2: Sentiment Analysis
        start_time = time()
        sentiment = sentiment_analyzer.analyze_sentiment(market_data)
        sentiment_analysis_time = time() - start_time

        signal.sentiment_score = sentiment.sentiment_score
        signal.ai_analysis = sentiment

        assert_not_none(sentiment, f"Sentiment analysis completed for {scenario_name}")
        assert_true(sentiment_analysis_time < 0.1, f"Sentiment analysis fast for {scenario_name}")

        # Step 3: Risk Evaluation
        start_time = time()
        risk_approval = risk_manager.evaluate_risk(signal, portfolio)
        risk_evaluation_time = time() - start_time

        assert_not_none(risk_approval, f"Risk evaluation completed for {scenario_name}")
        assert_true(risk_evaluation_time < 0.05, f"Risk evaluation fast for {scenario_name}")

        # Step 4: Execution (if approved)
        trade_record = None
        if risk_approval.approved:
            start_time = time()
            trade_record = executor.execute_trade(signal, risk_approval)
            execution_time = time() - start_time

            assert_not_none(trade_record, f"Trade executed for {scenario_name}")
            assert_true(execution_time < 0.01, f"Execution fast for {scenario_name}")

            # Update portfolio (mock)
            portfolio.trade_count_today += 1
            if trade_record.action == "BUY":
                portfolio.available_cash -= trade_record.executed_price * trade_record.quantity
            else:
                portfolio.available_cash += trade_record.executed_price * trade_record.quantity

        # Step 5: Performance Metrics
        total_cycle_time = signal_generation_time + sentiment_analysis_time + risk_evaluation_time
        if trade_record:
            total_cycle_time += (time() - start_time)

        # Performance assertions
        assert_true(total_cycle_time < 0.5, f"Total cycle time < 500ms for {scenario_name}")
        assert_true(signal_generation_time < 0.1, f"Signal generation < 100ms for {scenario_name}")
        assert_true(sentiment_analysis_time < 0.1, f"Sentiment analysis < 100ms for {scenario_name}")
        assert_true(risk_evaluation_time < 0.05, f"Risk evaluation < 50ms for {scenario_name}")

        # Print results
        print(f"    Signal: {signal.action} (conf: {signal.confidence:.2f})")
        print(f"    Sentiment: {sentiment.sentiment_score:.2f} (conf: {sentiment.confidence:.2f})")
        print(f"    Risk: {'APPROVED' if risk_approval.approved else 'REJECTED'}")
        if risk_approval.approved and trade_record:
            print(f"    Executed: {trade_record.quantity:.6f} @ {trade_record.executed_price:.6f}")
        print(f"    Timing: Signal={signal_generation_time*1000:.1f}ms, "
              f"Sentiment={sentiment_analysis_time*1000:.1f}ms, "
              f"Risk={risk_evaluation_time*1000:.1f}ms, "
              f"Total={total_cycle_time*1000:.1f}ms")

        # Validate expected outcomes
        if "expected_signals" in scenario:
            expected = scenario["expected_signals"][0]
            if expected["action"] == "BUY" and signal.action == TradingAction.BUY:
                assert_true(risk_approval.approved, f"Expected BUY signal approved for {scenario_name}")
            elif expected["action"] == "SELL" and signal.action == TradingAction.SELL:
                assert_true(risk_approval.approved, f"Expected SELL signal approved for {scenario_name}")
            elif expected["action"] == "REJECT":
                assert_false(risk_approval.approved, f"Expected REJECTION for {scenario_name}")

    print("✅ Full trading cycle tests completed")

# =============================================================================
# Test Runner
# =============================================================================

fn run_all_tests():
    print("🚀 Starting Trading Strategies Integration Tests")
    print("=" * 60)

    start_time = time()

    # Run all test modules
    test_end_to_end_signal_generation()
    test_ensemble_consensus()
    test_risk_approval()
    test_mock_execution()
    test_full_trading_cycle()

    end_time = time()
    duration = end_time - start_time

    # Print results
    print("\n" + "=" * 60)
    print("📊 Trading Strategies Integration Test Results Summary")
    print("=" * 60)
    print(f"Total Tests: {test_count}")
    print(f"Passed: {passed_tests} ✅")
    print(f"Failed: {failed_tests} ❌")
    print(f"Duration: {duration:.2f}s")

    if failed_tests == 0:
        print("\n🎉 All trading strategies integration tests passed!")
        return 0
    else:
        print(f"\n⚠️  {failed_tests} test(s) failed. Please check trading strategy implementations.")
        return 1

# =============================================================================
# Main Entry Point
# =============================================================================

fn main():
    result = run_all_tests()
    sys.exit(result)

if __name__ == "__main__":
    main()