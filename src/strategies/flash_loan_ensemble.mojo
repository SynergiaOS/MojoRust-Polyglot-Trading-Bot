# Unified Flash Loan Ensemble Strategy
# 🚀 All strategies running on single protocol (Save) with coordination

from data.enhanced_data_pipeline import EnhancedMarketData
from analysis.comprehensive_analyzer import ComprehensiveAnalysis, AnalysisSignal
from analysis.stat_arb import StatArbEngine, StatArbSignal
from utils.config_manager import ConfigManager
from monitoring.telegram_notifier import TelegramNotifier
from python import Python
from tensor import Tensor
from random import random
from math import sqrt, exp, log, fabs, sin, cos
from algorithm import vectorize, parallelize
from time import now
from collections import Dict

@value
struct FlashLoanSignal:
    var strategy_name: String
    var token_mint: String
    var amount: Int
    var action: String  # "FLASH_LOAN", "REGULAR", "HOLD"
    var confidence: Float32
    var urgency_level: String  # "critical", "high", "medium", "low"
    var risk_score: Float32
    var liquidity_score: Float32
    var social_score: Float32
    var expected_profit: Float32
    var slippage_bps: Int
    var preferred_provider: String
    var execution_deadline: Int
    var reasoning: String
    var market_data: Dict[String, Float32]

@value
struct FlashLoanEnsembleDecision:
    var final_action: String
    var selected_strategy: String
    var unified_confidence: Float32
    var consensus_strength: FlashLoanConsensus
    var contributing_strategies: List[String]
    var weighted_amount: Int
    var optimal_provider: String
    var risk_adjusted_amount: Int
    var expected_profit: Float32
    var execution_plan: FlashLoanExecutionPlan
    var safety_checks: FlashLoanSafetyChecks

@value
struct FlashLoanConsensus:
    var buy_votes: Float32
    var hold_votes: Float32
    var total_weight: Float32
    var buy_consensus: Float32
    var hold_consensus: Float32
    var conflict_level: Float32
    var strongest_signal: Float32
    var weakest_signal: Float32

@value
struct FlashLoanExecutionPlan:
    var execution_order: List[String]
    var parallel_execution: Bool
    batch_size: Int
    timeout_ms: Int
    fallback_strategy: String
    retry_attempts: Int
    monitoring_enabled: Bool

@value
struct FlashLoanSafetyChecks:
    var market_stability: Bool
    var liquidity_sufficient: Bool
    var risk_acceptable: Bool
    var capital_available: Bool
    var rate_limits_ok: Bool
    var circuit_breaker_active: Bool
    var warnings: List[String]

@value
struct FlashLoanEnsembleEngine:
    var config: ConfigManager
    var notifier: TelegramNotifier
    var save_flash_loan_enabled: Bool
    var stat_arb_engine: StatArbEngine
    var strategy_weights: Dict[String, Float32]
    var consensus_threshold: Float32
    var max_concurrent_flash_loans: Int
    var total_portfolio_value: Float64
    var active_flash_loans: Dict[String, Int]
    var performance_metrics: Dict[String, Float32]
    var market_regime: String

    fn __init__(inout self, config: ConfigManager, notifier: TelegramNotifier) raises:
        self.config = config
        self.notifier = notifier
        self.save_flash_loan_enabled = config.get_bool("flash_loan.save_enabled", True)
        self.stat_arb_engine = StatArbEngine()
        self.strategy_weights = self._initialize_unified_weights()
        self.consensus_threshold = config.get_float("flash_loan.consensus_threshold", 0.65)
        self.max_concurrent_flash_loans = config.get_int("flash_loan.max_concurrent", 3)
        self.total_portfolio_value = 1.0
        self.active_flash_loans = Dict[String, Int]()
        self.performance_metrics = Dict[String, Float32]()
        self.market_regime = "NEUTRAL"

        print("🔥 Flash Loan Ensemble Engine initialized")
        print(f"   Save Flash Loans: {self.save_flash_loan_enabled}")
        print(f"   Max Concurrent: {self.max_concurrent_flash_loans}")
        print(f"   Consensus Threshold: {self.consensus_threshold}")
        print("🎯 Unified approach - all strategies on Save protocol")

    fn _initialize_unified_weights(inout self) -> Dict[String, Float32]:
        var weights = Dict[String, Float32]()

        # All strategies now focused on Save Flash Loans with different angles
        weights["sniper_momentum"] = 0.25      # Quick memecoin detection
        weights["statistical_arbitrage"] = 0.20    # Cointegration analysis
        weights["liquidity_mining"] = 0.18        # Pool depth analysis
        weights["social_sentiment"] = 0.15        # Social media signals
        weights["technical_patterns"] = 0.12       # Chart patterns
        weights["whale_tracking"] = 0.10          # Large holder movements

        return weights

    async fn process_market_data(
        inout self,
        data: EnhancedMarketData,
        analysis: ComprehensiveAnalysis
    ) -> FlashLoanEnsembleDecision raises:
        print("🔥 Processing market data with Flash Loan Ensemble...")

        # Update market regime
        self._update_market_regime(data, analysis)

        # Generate all Flash Loan signals
        var all_signals = List[FlashLoanSignal]()

        # PARALLEL STRATEGY EXECUTION
        @parallelize
        for i in range(6):
            var signal: FlashLoanSignal

            if i == 0:
                signal = self._sniper_momentum_flash_loan(data, analysis)
            elif i == 1:
                signal = self._statistical_arbitrage_flash_loan(data, analysis)
            elif i == 2:
                signal = self._liquidity_mining_flash_loan(data, analysis)
            elif i == 3:
                signal = self._social_sentiment_flash_loan(data, analysis)
            elif i == 4:
                signal = self._technical_patterns_flash_loan(data, analysis)
            else:
                signal = self._whale_tracking_flash_loan(data, analysis)

            all_signals.append(signal)

        # Filter for Save protocol compatibility
        var filtered_signals = self._filter_save_compatible_signals(all_signals)

        # Apply Save-specific weighting
        var weighted_signals = self._apply_save_weights(filtered_signals)

        # Calculate unified consensus
        var consensus = self._calculate_flash_loan_consensus(weighted_signals, data)

        # Generate unified execution plan
        var decision = self._generate_unified_decision(consensus, weighted_signals, data)

        # Apply Save-specific safety checks
        decision = self._apply_save_safety_checks(decision, data)

        # Send unified alert
        await self.notifier.send_flash_loan_ensemble_alert(decision, filtered_signals)

        # Update performance metrics
        self._update_performance_metrics(decision, filtered_signals)

        return decision

    fn _sniper_momentum_flash_loan(self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> FlashLoanSignal:
        print("🎯 Generating Sniper Momentum Flash Loan Signal...")

        var token_mint = data.token_mint
        var token_symbol = data.token_symbol

        # Check for memecoin characteristics
        var lp_burned = data.get_metric("lp_burned", 0.0)
        var volume_24h = data.get_metric("volume_24h", 0.0)
        var social_mentions = data.get_metric("social_mentions", 0.0)
        var holder_count = data.get_metric("holder_count", 0.0)
        var age_minutes = data.get_metric("age_minutes", 0.0)

        # Calculate flash loan suitability
        var flash_suitability = 0.0
        if lp_burned >= 90.0:
            flash_suitability += 0.4
        if volume_24h >= 5000.0:
            flash_suitability += 0.3
        if social_mentions >= 10:
            flash_suitability += 0.2
        if age_minutes <= 30:
            flash_suitability += 0.1

        var confidence = flash_suitability
        var urgency_level = "high"
        var risk_score = max(0.0, 1.0 - flash_suitability)

        # Calculate optimal amount for Save
        var max_save_amount = 5_000_000_000  # 5 SOL
        var available_liquidity = data.get_metric("available_liquidity", 0.0)
        var optimal_amount = min(
            Int(min(available_liquidity / 10, max_save_amount)),
            max_save_amount
        )

        if confidence >= 0.8 and optimal_amount >= 100_000_000:
            return FlashLoanSignal(
                strategy_name="sniper_momentum",
                token_mint=token_mint,
                amount=optimal_amount,
                action="FLASH_LOAN",
                confidence=confidence,
                urgency_level=urgency_level,
                risk_score=risk_score,
                liquidity_score=min(volume_24h / 10000.0, 1.0),
                social_score=min(social_mentions / 100.0, 1.0),
                expected_profit=confidence * 5.0,  # 5% expected profit
                slippage_bps=50,
                preferred_provider="save",
                execution_deadline=now() + 20000,  # 20 seconds
                reasoning=f"High-confidence memecoin opportunity detected - {token_symbol}",
                market_data=data.to_dict()
            )
        else:
            return FlashLoanSignal(
                strategy_name="sniper_momentum",
                token_mint=token_mint,
                amount=0,
                action="HOLD",
                confidence=confidence,
                urgency_level="low",
                risk_score=1.0,
                liquidity_score=0.0,
                social_score=0.0,
                expected_profit=0.0,
                slippage_bps=50,
                preferred_provider="save",
                execution_deadline=0,
                reasoning=f"Insufficient confidence for flash loan - {token_symbol}",
                market_data=data.to_dict()
            )

    fn _statistical_arbitrage_flash_loan(self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> FlashLoanSignal:
        print("📊 Generating Statistical Arbitrage Flash Loan Signal...")

        # Use integrated statistical arbitrage engine
        var stat_arb_signal = self.stat_arb_engine.generate_signal(data, analysis)

        if stat_arb_signal.action == "BUY" and stat_arb_signal.confidence >= 0.7:
            # Convert statistical signal to flash loan
            var max_save_amount = 5_000_000_000
            var flash_amount = min(stat_arb_signal.amount, max_save_amount)

            # Adjust for flash loan fees (Save 0.03% + Jito)
            var total_fees = flash_amount * 3 // 10000  # Save fee
            total_fees += 150_000_000  # Jito tip

            if stat_arb_signal.expected_profit > total_fees:
                return FlashLoanSignal(
                    strategy_name="statistical_arbitrage",
                    token_mint=data.token_mint,
                    amount=flash_amount,
                    action="FLASH_LOAN",
                    confidence=stat_arb_signal.confidence,
                    urgency_level="medium",
                    risk_score=stat_arb_signal.risk_score,
                    liquidity_score=stat_arb_signal.liquidity_score,
                    social_score=stat_arb_signal.social_score,
                    expected_profit=(stat_arb_signal.expected_profit - total_fees) / 1_000_000_000,
                    slippage_bps=50,
                    preferred_provider="save",
                    execution_deadline=now() + 30000,  # 30 seconds
                    reasoning=f"Statistical arbitrage opportunity detected - {data.token_symbol}",
                    market_data=data.to_dict()
                )

        return FlashLoanSignal(
            strategy_name="statistical_arbitrage",
            token_mint=data.token_mint,
            amount=0,
            action="HOLD",
            confidence=stat_arb_signal.confidence,
            urgency_level="low",
            risk_score=stat_arb_signal.risk_score,
            liquidity_score=stat_arb_signal.liquidity_score,
            social_score=stat_arb_signal.social_score,
            expected_profit=0.0,
            slippage_bps=50,
            preferred_provider="save",
            execution_deadline=0,
            reasoning=f"Statistical analysis does not support flash loan",
            market_data=data.to_dict()
        )

    fn _liquidity_mining_flash_loan(self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> FlashLoanSignal:
        print("💧 Generating Liquidity Mining Flash Loan Signal...")

        # Analyze pool depth and liquidity opportunities
        var pool_depth = data.get_metric("pool_depth", 0.0)
        var liquidity_score = data.get_metric("liquidity_score", 0.0)
        var volume_imbalance = data.get_metric("volume_imbalance", 0.0)
        var price_impact = data.get_metric("price_impact", 0.0)

        # Calculate flash loan opportunity based on liquidity
        var liquidity_opportunity = 0.0
        if liquidity_score >= 0.8:
            liquidity_opportunity += 0.3
        if volume_imbalance > 0.02:  # 2% volume imbalance
            liquidity_opportunity += 0.2
        if price_impact < 0.01:  # Low price impact
            liquidity_opportunity += 0.3
        if pool_depth > 100_000:  # Significant pool depth
            liquidity_opportunity += 0.2

        var confidence = liquidity_opportunity
        var risk_score = 1.0 - liquidity_score

        # Calculate amount for liquidity mining
        var max_save_amount = 5_000_000_000
        var optimal_amount = min(
            Int(pool_depth * 0.1),  # 10% of pool depth
            max_save_amount
        )

        if confidence >= 0.75 and optimal_amount >= 500_000_000:
            return FlashLoanSignal(
                strategy_name="liquidity_mining",
                token_mint=data.token_mint,
                amount=optimal_amount,
                action="FLASH_LOAN",
                confidence=confidence,
                urgency_level="medium",
                risk_score=risk_score,
                liquidity_score=liquidity_score,
                social_score=0.5,  # Less important for liquidity
                expected_profit=confidence * 2.0,  # 2% expected profit
                slippage_bps=75,  # Higher slippage for liquidity mining
                preferred_provider="save",
                execution_deadline=now() + 25000,  # 25 seconds
                reasoning=f"Liquidity mining opportunity detected - {data.token_symbol}",
                market_data=data.to_dict()
            )
        else:
            return FlashLoanSignal(
                strategy_name="liquidity_mining",
                token_mint=data.token_mint,
                amount=0,
                action="HOLD",
                confidence=confidence,
                urgency_level="low",
                risk_score=risk_score,
                liquidity_score=liquidity_score,
                social_score=0.0,
                expected_profit=0.0,
                slippage_bps=50,
                preferred_provider="save",
                execution_deadline=0,
                reasoning=f"Liquidity insufficient for flash loan mining - {data.token_symbol}",
                market_data=data.to_dict()
            )

    fn _social_sentiment_flash_loan(self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> FlashLoanSignal:
        print("📱 Generating Social Sentiment Flash Loan Signal...")

        # Analyze social media sentiment
        var sentiment_score = data.get_metric("sentiment_score", 0.0)
        var social_volume = data.get_metric("social_volume", 0.0)
        var influencer_mentions = data.get_metric("influencer_mentions", 0.0)
        var trending_score = data.get_metric("trending_score", 0.0)

        # Calculate social opportunity
        var social_opportunity = 0.0
        if sentiment_score >= 0.7:
            social_opportunity += 0.4
        if social_volume >= 10000:
            social_opportunity += 0.2
        if influencer_mentions >= 5:
            social_opportunity += 0.3
        if trending_score >= 0.8:
            social_opportunity += 0.1

        var confidence = social_opportunity
        var risk_score = max(0.0, 1.0 - sentiment_score)
        var social_score = min(social_volume / 50000.0, 1.0)

        # Calculate amount based on social signals
        var max_save_amount = 5_000_000_000
        var social_amount = min(
            Int(social_volume * 0.01),  # 1% of social volume
            max_save_amount
        )

        if confidence >= 0.8 and social_amount >= 1_000_000_000:
            return FlashLoanSignal(
                strategy_name="social_sentiment",
                token_mint=data.token_mint,
                amount=social_amount,
                action="FLASH_LOAN",
                confidence=confidence,
                urgency_level="high",
                risk_score=risk_score,
                liquidity_score=0.6,  # Less important for social
                social_score=social_score,
                expected_profit=confidence * 3.5,  # 3.5% expected profit
                slippage_bps=60,
                preferred_provider="save",
                execution_deadline=now() + 15000,  # 15 seconds - social moves fast
                reasoning=f"Social sentiment surge detected - {data.token_symbol}",
                market_data=data.to_dict()
            )
        else:
            return FlashLoanSignal(
                strategy_name="social_sentiment",
                token_mint=data.token_mint,
                amount=0,
                action="HOLD",
                confidence=confidence,
                urgency_level="low",
                risk_score=risk_score,
                liquidity_score=0.5,
                social_score=social_score,
                expected_profit=0.0,
                slippage_bps=50,
                preferred_provider="save",
                execution_deadline=0,
                reasoning=f"Social signals insufficient for flash loan - {data.token_symbol}",
                market_data=data.to_dict()
            )

    fn _technical_patterns_flash_loan(self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> FlashLoanPatternSignal:
        print("📈 Generating Technical Patterns Flash Loan Signal...")

        # Analyze technical patterns
        var pattern_score = data.get_metric("pattern_score", 0.0)
        var breakout_probability = data.get_metric("breakout_probability", 0.0)
        var support_resistance_strength = data.get_metric("support_resistance_strength", 0.0)
        var momentum_indicator = data.get_metric("momentum_indicator", 0.0)

        # Calculate technical opportunity
        var technical_opportunity = 0.0
        if pattern_score >= 0.7:
            technical_opportunity += 0.3
        if breakout_probability >= 0.6:
            technical_opportunity += 0.4
        if momentum_indicator >= 0.8:
            technical_opportunity += 0.3

        var confidence = technical_opportunity
        var risk_score = max(0.0, 1.0 - pattern_score)
        var liquidity_score = 0.7  # Standard for technical analysis

        # Calculate amount based on technical signals
        var max_save_amount = 5_000_000_000
        var technical_amount = min(
            Int(pattern_score * 3_000_000_000),  # Scale with pattern score
            max_save_amount
        )

        if confidence >= 0.75 and technical_amount >= 500_000_000:
            return FlashLoanPatternSignal(
                strategy_name="technical_patterns",
                token_mint=data.token_mint,
                amount=technical_amount,
                action="FLASH_LOAN",
                confidence=confidence,
                urgency_level="medium",
                risk_score=risk_score,
                liquidity_score=liquidity_score,
                social_score=0.3,
                expected_profit=confidence * 2.5,  # 2.5% expected profit
                slippage_bps=55,
                preferred_provider="save",
                execution_deadline=now() + 30000,  # 30 seconds for technical
                reasoning=f"Technical breakout pattern detected - {data.token_symbol}",
                market_data=data.to_dict()
            )
        else:
            return FlashLoanPatternSignal(
                strategy_name="technical_patterns",
                token_mint=data.token_mint,
                amount=0,
                action="HOLD",
                confidence=confidence,
                urgency_level="low",
                risk_score=risk_score,
                liquidity_score=liquidity_score,
                social_score=0.0,
                expected_profit=0.0,
                slippage_bps=50,
                preferred_provider="save",
                execution_deadline=0,
                reasoning=f"Technical patterns do not support flash loan - {data.token_symbol}",
                market_data=data.to_dict()
            )

    fn _whale_tracking_flash_loan(self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> FlashLoanSignal:
        print("🐋 Generating Whale Tracking Flash Loan Signal...")

        # Track whale movements
        var whale_activity = data.get_metric("whale_activity", 0.0)
        var large_transactions = data.get_metric("large_transactions", 0.0)
        var whale_sentiment = data.get_metric("whale_sentiment", 0.0)
        var price_impact = data.get_metric("whale_price_impact", 0.0)

        # Calculate whale opportunity
        var whale_opportunity = 0.0
        if whale_activity >= 0.7:
            whale_opportunity += 0.4
        if large_transactions >= 10:
            whale_opportunity += 0.3
        if whale_sentiment > 0:
            whale_opportunity += 0.3

        var confidence = whale_opportunity
        var risk_score = max(0.0, 1.0 - whale_activity)
        var liquidity_score = 0.8  # Usually high liquidity for whale moves

        # Calculate amount for whale following
        var max_save_amount = 5_000_000_000
        var whale_amount = min(
            Int(large_transactions * 2_000_000_000),  # Scale with transaction size
            max_save_amount
        )

        if confidence >= 0.8 and whale_amount >= 2_000_000_000:
            return FlashLoanSignal(
                strategy_name="whale_tracking",
                token_mint=data.token_mint,
                amount=whale_amount,
                action="FLASH_LOAN",
                confidence=confidence,
                urgency_level="high",
                risk_score=risk_score,
                liquidity_score=liquidity_score,
                social_score=0.6,
                expected_profit=confidence * 4.0,  # 4% expected profit
                slippage_bps=40,
                preferred_provider="save",
                execution_deadline=now() + 12000,  # 12 seconds - whales move fast
                reasoning=f"Whale activity detected - {data.token_symbol}",
                market_data=data.to_dict()
            )
        else:
            return FlashLoanSignal(
                strategy_name="whale_tracking",
                token_mint=data.token_mint,
                amount=0,
                action="HOLD",
                confidence=confidence,
                urgency_level="low",
                risk_score=risk_score,
                liquidity_score=liquidity_score,
                social_score=0.0,
                expected_profit=0.0,
                slippage_bps=50,
                preferred_provider="save",
                execution_deadline=0,
                reasoning=f"No significant whale activity - {data.token_symbol}",
                market_data=data.to_dict()
            )

    # Filter signals for Save protocol compatibility
    fn _filter_save_compatible_signals(inout self, signals: List[FlashLoanSignal]) -> List[FlashLoanSignal]:
        return [signal for signal in signals if self._is_save_compatible(signal)]

    fn _is_save_compatible(self, signal: FlashLoanSignal) -> Bool:
        var max_save_amount = 5_000_000_000  # 5 SOL limit
        return signal.amount > 0 and signal.amount <= max_save_amount

    # Apply Save-specific weighting
    fn _apply_save_weights(inout self, signals: List[FlashLoanSignal]) -> Dict[String, Float32]:
        var weighted_signals = Dict[String, Float32]()

        for signal in signals:
            var strategy_weight = self.strategy_weights.get(signal.strategy_name, 0.1)

            # Boost weights for Save protocol
            var save_bonus = 1.2  # 20% bonus for Save compatibility
            var final_weight = strategy_weight * save_bonus

            weighted_signals[signal.strategy_name] = final_weight

        return weighted_signals

    # Calculate unified consensus for Flash Loans
    fn _calculate_flash_loan_consensus(
        inout self,
        weighted_signals: Dict[String, Float32],
        data: EnhancedMarketData
    ) -> FlashLoanConsensus:
        var buy_weight = 0.0
        var hold_weight = 0.0
        var total_weight = 0.0
        var buy_signals = List[Float32]()
        var hold_signals = List[Float32]()

        for strategy_name, weight in weighted_signals:
            # Find corresponding signal
            for signal in self.active_flash_loans:
                if signal.strategy_name == strategy_name and signal.action == "FLASH_LOAN":
                    buy_weight += weight
                    buy_signals.append(weight)
                elif signal.action == "HOLD":
                    hold_weight += weight
                    hold_signals.append(weight)

            total_weight += weight

        if total_weight > 0:
            var buy_consensus = buy_weight / total_weight
            var hold_consensus = hold_weight / total_weight

            return FlashLoanConsensus(
                buy_votes=buy_weight,
                hold_votes=hold_weight,
                total_weight=total_weight,
                buy_consensus=buy_consensus,
                hold_consensus=hold_consensus,
                conflict_level=1.0 - abs(buy_consensus - hold_consensus),
                strongest_signal=max(buy_signals) if buy_signals else 0.0,
                weakest_signal=min(buy_signals) if hold_signals else 0.0
            )
        else:
            return FlashLoanConsensus(
                buy_votes=0.0,
                hold_votes=0.0,
                total_weight=0.0,
                buy_consensus=0.0,
                hold_consensus=0.0,
                conflict_level=0.0,
                strongest_signal=0.0,
                weakest_signal=0.0
            )

    # Generate unified execution plan
    fn _generate_unified_decision(
        inout self,
        consensus: FlashLoanConsensus,
        weighted_signals: Dict[String, Float32],
        data: EnhancedMarketData
    ) -> FlashLoanEnsembleDecision:
        if consensus.buy_consensus >= self.consensus_threshold:
            # Select best signal
            var best_strategy = max(
                weighted_signals.items(),
                key=lambda item: item[1]
            )[0]

            # Find corresponding signal
            var selected_signal: FlashLoanSignal
            for signal in self.active_flash_loans:
                if signal.strategy_name == best_strategy and signal.action == "FLASH_LOAN":
                    selected_signal = signal
                    break

            # Create unified execution plan
            var execution_plan = self._create_execution_plan(selected_signal, weighted_signals)

            return FlashLoanEnsembleDecision(
                final_action="FLASH_LOAN",
                selected_strategy=best_strategy,
                unified_confidence=consensus.buy_consensus,
                consensus_strength=consensus,
                contributing_strategies=list(weighted_signals.keys()),
                weighted_amount=selected_signal.amount,
                optimal_provider="save",
                risk_adjusted_amount=selected_signal.amount,
                expected_profit=selected_signal.expected_profit,
                execution_plan=execution_plan,
                safety_checks=self._create_safety_checks(selected_signal, data)
            )
        else:
            return FlashLoanEnsembleDecision(
                final_action="HOLD",
                selected_strategy="ensemble",
                unified_confidence=consensus.hold_consensus,
                consensus_strength=consensus,
                contributing_strategies=list(weighted_signals.keys()),
                weighted_amount=0,
                optimal_provider="save",
                risk_adjusted_amount=0,
                expected_profit=0.0,
                execution_plan=FlashLoanExecutionPlan(
                    execution_order=[],
                    parallel_execution=False,
                    batch_size=0,
                    timeout_ms=0,
                    fallback_strategy="none",
                    retry_attempts=0,
                    monitoring_enabled=True
                ),
                safety_checks=self._create_default_safety_checks()
            )

    # Apply Save-specific safety checks
    fn _apply_save_safety_checks(
        inout self,
        decision: FlashLoanEnsembleDecision,
        data: EnhancedMarketData
    ) -> FlashLoanEnsembleDecision:
        decision.safety_checks = self._create_safety_checks(decision.risk_adjusted_amount, data)

        # Check Save protocol specific constraints
        var max_concurrent = self.active_flash_loans.get("save", 0)
        if max_concurrent >= self.max_concurrent_flash_loans:
            decision.final_action = "HOLD"
            decision.safety_checks.warnings.append("Save protocol max concurrency reached")

        return decision

    # Helper functions for creating safety checks and execution plans
    fn _create_safety_checks(self, amount: Int, data: EnhancedMarketData) -> FlashLoanSafetyChecks:
        var market_stability = data.get_metric("market_stability", 1.0) > 0.7
        var liquidity_sufficient = data.get_metric("available_liquidity", 0.0) >= amount
        var risk_acceptable = data.get_metric("overall_risk", 0.5) < 0.3
        var capital_available = self.total_portfolio_value >= (amount / 1_000_000_000)
        var rate_limits_ok = self._check_rate_limits()

        return FlashLoanSafetyChecks(
            market_stability=market_stability,
            liquidity_sufficient=liquidity_sufficient,
            risk_acceptable=risk_acceptable,
            capital_available=capital_available,
            rate_limits_ok=rate_limits_ok,
            circuit_breaker_active=self.market_regime == "HIGH_VOLATILITY",
            warnings=List[String]()
        )

    fn _create_default_safety_checks() -> FlashLoanSafetyChecks:
        return FlashLoanSafetyChecks(
            market_stability=True,
            liquidity_sufficient=True,
            risk_acceptable=True,
            capital_available=True,
            rate_limits_ok=True,
            circuit_breaker_active=False,
            warnings=List[String]()
        )

    fn _create_execution_plan(self, signal: FlashLoanSignal, weighted_signals: Dict[String, Float32]) -> FlashLoanExecutionPlan:
        return FlashLoanExecutionPlan(
            execution_order=["jupiter_quote", "save_flash_loan_begin", "jupiter_swap", "save_flash_loan_end"],
            parallel_execution=False,
            batch_size=1,
            timeout_ms=signal.execution_deadline - now(),
            fallback_strategy="regular_trade",
            retry_attempts=2,
            monitoring_enabled=True
        )

    # Update performance metrics
    fn _update_performance_metrics(inout self, decision: FlashLoanEnsembleDecision, signals: List[FlashLoanSignal]):
        self.performance_metrics["last_execution_time"] = now()
        self.performance_metrics["consensus_strength"] = decision.consensus_strength.consensus_strength
        self.performance_metrics["active_strategies"] = len(signals)

        if decision.final_action == "FLASH_LOAN":
            self.performance_metrics["flash_loan_count"] = self.performance_metrics.get("flash_loan_count", 0.0) + 1.0

# Add the missing FlashLoanPatternSignal struct
@value
struct FlashLoanPatternSignal:
    var strategy_name: String
    var token_mint: String
    var amount: Int
    var action: String
    var confidence: Float32
    var urgency_level: String
    var risk_score: Float32
    var liquidity_score: Float32
    var social_score: Float32
    var expected_profit: Float32
    var slippage_bps: Int
    var preferred_provider: String
    var execution_deadline: Int
    var reasoning: String
    var market_data: Dict[String, Float32]