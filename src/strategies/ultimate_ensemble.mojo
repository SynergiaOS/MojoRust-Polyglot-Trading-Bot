# Ultimate Ensemble Strategy System
# 🚀 Ultimate Trading Bot - Advanced Ensemble Strategies

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

# Ultimate Strategy Components
@value
struct StrategySignal:
    var strategy_name: String
    var signal_type: String  # "BUY", "SELL", "HOLD"
    var confidence: Float32
    var strength: Float32
    var timeframe: String
    var entry_price: Float64
    var take_profit: Float64
    var stop_loss: Float64
    var position_size: Float32
    var reasoning: String
    var priority: Int
    var timestamp: Float64

@value
struct EnsembleDecision:
    var final_signal: String
    var aggregated_confidence: Float32
    var consensus_strength: Float32
    var contributing_strategies: List[String]
    var weighted_signals: Dict[String, Float32]
    var risk_adjusted_size: Float32
    var optimal_entry: Float64
    var optimal_exit: Float64
    var stop_loss_distance: Float64
    var expected_return: Float32
    var time_horizon: String
    var market_regime: String
    var execution_urgency: String

# Ultimate Ensemble Engine
struct UltimateEnsembleEngine:
    var config: ConfigManager
    var notifier: TelegramNotifier
    var strategy_weights: Dict[String, Float32]
    var market_regime: String
    var performance_history: List[StrategySignal]
    var adaptive_weights: Bool
    var consensus_threshold: Float32
    var min_strategies: Int
    var max_position_size: Float32
    var statistical_arbitrage_engine: StatArbEngine

    fn __init__(inout self, config: ConfigManager, notifier: TelegramNotifier) raises:
        self.config = config
        self.notifier = notifier
        self.strategy_weights = self._initialize_strategy_weights()
        self.market_regime = "NEUTRAL"
        self.performance_history = List[StrategySignal]()
        self.adaptive_weights = config.get_bool("ensemble.adaptive_weights", True)
        self.consensus_threshold = config.get_float("ensemble.consensus_threshold", 0.65)
        self.min_strategies = config.get_int("ensemble.min_strategies", 3)
        self.max_position_size = config.get_float("ensemble.max_position_size", 0.95)

        # Initialize advanced statistical arbitrage engine
        self.statistical_arbitrage_engine = StatArbEngine()

        print("🎯 Ultimate Ensemble Engine initialized")
        print(f"   Adaptive Weights: {self.adaptive_weights}")
        print(f"   Consensus Threshold: {self.consensus_threshold}")
        print(f"   Min Strategies: {self.min_strategies}")
        print("🧮 Advanced Statistical Arbitrage Engine integrated")

    fn _initialize_strategy_weights(inout self) -> Dict[String, Float32]:
        var weights = Dict[String, Float32]()

        # Initialize 8 Ultimate Strategies with weights
        weights["momentum_breakthrough"] = 0.15
        weights["mean_reversion"] = 0.12
        weights["trend_following"] = 0.14
        weights["volatility_breakout"] = 0.13
        weights["whale_tracking"] = 0.16
        weights["sentiment_momentum"] = 0.11
        weights["pattern_recognition"] = 0.10
        weights["statistical_arbitrage"] = 0.09

        return weights

    fn generate_ensemble_decision(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> EnsembleDecision raises:
        print("🎯 Generating Ultimate Ensemble Decision...")

        # Update market regime
        self._update_market_regime(data, analysis)

        # Generate signals from all strategies
        var all_signals = List[StrategySignal]()

        # PARALLEL STRATEGY EXECUTION
        @parallelize
        for i in range(8):
            var signal: StrategySignal

            if i == 0:
                signal = self._momentum_breakthrough_strategy(data, analysis)
            elif i == 1:
                signal = self._mean_reversion_strategy(data, analysis)
            elif i == 2:
                signal = self._trend_following_strategy(data, analysis)
            elif i == 3:
                signal = self._volatility_breakout_strategy(data, analysis)
            elif i == 4:
                signal = self._whale_tracking_strategy(data, analysis)
            elif i == 5:
                signal = self._sentiment_momentum_strategy(data, analysis)
            elif i == 6:
                signal = self._pattern_recognition_strategy(data, analysis)
            else:
                signal = self._statistical_arbitrage_strategy(data, analysis)

            all_signals.append(signal)

        # Filter and weight signals
        var filtered_signals = self._filter_signals(all_signals)
        var weighted_signals = self._apply_strategy_weights(filtered_signals)

        # Calculate consensus
        var decision = self._calculate_consensus(weighted_signals, data)

        # Apply risk adjustments
        decision = self._apply_risk_adjustments(decision, analysis)

        # Send ensemble alert
        await self.notifier.send_ensemble_alert(decision, filtered_signals)

        # Store for learning
        self._update_performance_history(decision, filtered_signals)

        # Adapt weights if enabled
        if self.adaptive_weights:
            self._adapt_strategy_weights(filtered_signals)

        print(f"🎯 Ensemble Decision: {decision.final_signal} (Confidence: {decision.aggregated_confidence:.3f})")

        return decision

    # 1. MOMENTUM BREAKTHROUGH STRATEGY
    fn _momentum_breakthrough_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="momentum_breakthrough",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="5m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=1,
            timestamp=now()
        )

        # Multi-timeframe momentum analysis
        var momentum_5m = analysis.technical.momentum_5m
        var momentum_15m = analysis.technical.momentum_15m
        var momentum_1h = analysis.technical.momentum_1h

        # RSI momentum
        var rsi_momentum = (analysis.technical.rsi_5m - 50.0) / 50.0
        var rsi_trend = rsi_momentum > 0.3

        # Price momentum
        var price_momentum_5m = (data.prices.current_price - data.prices.price_5m_ago) / data.prices.price_5m_ago
        var price_momentum_15m = (data.prices.current_price - data.prices.price_15m_ago) / data.prices.price_15m_ago

        # Volume momentum
        var volume_momentum = data.prices.current_volume / data.prices.avg_volume_5m

        # Breakthrough conditions
        var momentum_strength = (momentum_5m + momentum_15m) / 2.0
        var breakout_potential = momentum_strength > 0.7 and volume_momentum > 1.5

        if breakout_potential and rsi_trend:
            signal.signal_type = "BUY"
            signal.confidence = min_float(momentum_strength + (volume_momentum - 1.0) * 0.2, 0.95)
            signal.strength = momentum_strength
            signal.position_size = 0.3 + signal.confidence * 0.4

            # Calculate targets
            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price + atr * 2.5
            signal.stop_loss = data.prices.current_price - atr * 1.2
            signal.reasoning = f"Strong momentum breakthrough: {momentum_strength:.3f} with volume {volume_momentum:.2f}x"
            signal.priority = 3

        elif momentum_strength < -0.6 and volume_momentum > 1.8:
            signal.signal_type = "SELL"
            signal.confidence = min_float(abs_float(momentum_strength) + (volume_momentum - 1.0) * 0.15, 0.90)
            signal.strength = abs_float(momentum_strength)
            signal.position_size = 0.25 + signal.confidence * 0.35

            signal.take_profit = data.prices.current_price - atr * 2.0
            signal.stop_loss = data.prices.current_price + atr * 1.5
            signal.reasoning = f"Strong downside momentum: {momentum_strength:.3f} with high volume"
            signal.priority = 2

        return signal

    # 2. MEAN REVERSION STRATEGY
    fn _mean_reversion_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="mean_reversion",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="15m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=2,
            timestamp=now()
        )

        # Bollinger Band analysis
        var bb_position = (data.prices.current_price - analysis.technical.bb_lower) / (analysis.technical.bb_upper - analysis.technical.bb_lower)
        var bb_width = analysis.technical.bb_upper - analysis.technical.bb_lower

        # RSI extreme levels
        var rsi_oversold = analysis.technical.rsi_15m < 25.0
        var rsi_overbought = analysis.technical.rsi_15m > 75.0

        # Price deviation from mean
        var price_deviation = abs_float(data.prices.current_price - analysis.technical.sma_20) / analysis.technical.sma_20
        var deviation_threshold = 0.03  # 3% deviation

        # Mean reversion conditions
        if (bb_position < 0.05 or rsi_oversold) and price_deviation > deviation_threshold:
            signal.signal_type = "BUY"
            signal.confidence = min_float((0.3 - bb_position) * 2.0 + (25.0 - analysis.technical.rsi_15m) / 25.0 * 0.3, 0.85)
            signal.strength = (0.3 - bb_position) + (price_deviation - deviation_threshold) * 10.0
            signal.position_size = 0.2 + signal.confidence * 0.3

            var reversion_target = analysis.technical.sma_20
            signal.take_profit = reversion_target
            signal.stop_loss = data.prices.current_price * 0.97
            signal.reasoning = f"Oversold mean reversion: BB position {bb_position:.3f}, RSI {analysis.technical.rsi_15m:.1f}"
            signal.priority = 2

        elif (bb_position > 0.95 or rsi_overbought) and price_deviation > deviation_threshold:
            signal.signal_type = "SELL"
            signal.confidence = min_float((bb_position - 0.7) * 2.0 + (analysis.technical.rsi_15m - 75.0) / 25.0 * 0.3, 0.80)
            signal.strength = (bb_position - 0.7) + (price_deviation - deviation_threshold) * 8.0
            signal.position_size = 0.15 + signal.confidence * 0.25

            signal.take_profit = analysis.technical.sma_20
            signal.stop_loss = data.prices.current_price * 1.03
            signal.reasoning = f"Overbought mean reversion: BB position {bb_position:.3f}, RSI {analysis.technical.rsi_15m:.1f}"
            signal.priority = 1

        return signal

    # 3. TREND FOLLOWING STRATEGY
    fn _trend_following_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="trend_following",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="1h",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=2,
            timestamp=now()
        )

        # Moving average trend analysis
        var sma_trend = analysis.technical.sma_20 > analysis.technical.sma_50 and analysis.technical.sma_50 > analysis.technical.sma_200
        var ema_trend = analysis.technical.ema_12 > analysis.technical.ema_26

        # ADX trend strength
        var trend_strength = analysis.technical.adx > 25.0
        var strong_trend = analysis.technical.adx > 40.0

        # MACD trend confirmation
        var macd_bullish = analysis.technical.macd > analysis.technical.macd_signal and analysis.technical.macd_histogram > 0
        var macd_bearish = analysis.technical.macd < analysis.technical.macd_signal and analysis.technical.macd_histogram < 0

        # Price position relative to moving averages
        var price_above_sma = data.prices.current_price > analysis.technical.sma_20
        var price_above_ema = data.prices.current_price > analysis.technical.ema_12

        # Trend following conditions
        if sma_trend and ema_trend and trend_strength and macd_bullish and price_above_sma:
            signal.signal_type = "BUY"
            signal.confidence = min_float((analysis.technical.adx - 25.0) / 30.0 * 0.6 + 0.35, 0.90)
            signal.strength = analysis.technical.adx / 50.0

            if strong_trend:
                signal.position_size = 0.4 + signal.confidence * 0.3
                signal.timeframe = "4h"
            else:
                signal.position_size = 0.25 + signal.confidence * 0.25

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price + atr * 3.0
            signal.stop_loss = analysis.technical.sma_50 - atr * 0.5
            signal.reasoning = f"Strong uptrend: ADX {analysis.technical.adx:.1f}, MACD bullish"
            signal.priority = 3

        elif not sma_trend and not ema_trend and trend_strength and macd_bearish and not price_above_sma:
            signal.signal_type = "SELL"
            signal.confidence = min_float((analysis.technical.adx - 25.0) / 35.0 * 0.5 + 0.30, 0.85)
            signal.strength = analysis.technical.adx / 50.0

            signal.position_size = 0.2 + signal.confidence * 0.2

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price - atr * 2.5
            signal.stop_loss = analysis.technical.sma_50 + atr * 0.8
            signal.reasoning = f"Downtrend: ADX {analysis.technical.adx:.1f}, MACD bearish"
            signal.priority = 2

        return signal

    # 4. VOLATILITY BREAKOUT STRATEGY
    fn _volatility_breakout_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="volatility_breakout",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="5m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=2,
            timestamp=now()
        )

        # Volatility analysis
        var current_volatility = analysis.technical.volatility
        var avg_volatility = analysis.technical.avg_volatility
        var volatility_ratio = current_volatility / avg_volatility

        # Bollinger Band squeeze and breakout
        var bb_width = analysis.technical.bb_upper - analysis.technical.bb_lower
        var bb_squeeze = bb_width < analysis.technical.atr * 1.5
        var bb_breakout_up = data.prices.current_price > analysis.technical.bb_upper
        var bb_breakout_down = data.prices.current_price < analysis.technical.bb_lower

        # Volume confirmation
        var volume_surge = data.prices.current_volume > data.prices.avg_volume_5m * 2.0

        # Volatility breakout conditions
        if volatility_ratio > 1.8 and (bb_breakout_up or bb_squeeze) and volume_surge:
            signal.signal_type = "BUY"
            signal.confidence = min_float(volatility_ratio / 3.0 * 0.7 + 0.25, 0.85)
            signal.strength = volatility_ratio / 2.5
            signal.position_size = 0.35 + signal.confidence * 0.3

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price + atr * 2.0
            signal.stop_loss = data.prices.current_price - atr * 1.0
            signal.reasoning = f"Volatility breakout: Ratio {volatility_ratio:.2f}, BB squeeze {bb_squeeze}"
            signal.priority = 3

        elif volatility_ratio > 2.0 and bb_breakout_down and volume_surge:
            signal.signal_type = "SELL"
            signal.confidence = min_float(volatility_ratio / 3.5 * 0.6 + 0.20, 0.80)
            signal.strength = volatility_ratio / 3.0
            signal.position_size = 0.25 + signal.confidence * 0.25

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price - atr * 1.8
            signal.stop_loss = data.prices.current_price + atr * 1.2
            signal.reasoning = f"Downside volatility breakout: Ratio {volatility_ratio:.2f}"
            signal.priority = 2

        return signal

    # 5. WHALE TRACKING STRATEGY
    fn _whale_tracking_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="whale_tracking",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="1m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=4,
            timestamp=now()
        )

        # Whale activity analysis
        var large_buys = data.whale_activity.large_buys_5m
        var large_sells = data.whale_activity.large_sells_5m
        var net_whale_flow = data.whale_activity.net_whale_flow_5m

        # Whale wallet tracking
        var active_whales = data.whale_activity.active_whale_count
        var whale_accumulation = data.whale_activity.whale_accumulation_score

        # On-chain metrics
        var exchange_inflow = data.blockchain_metrics.exchange_inflow
        var exchange_outflow = data.blockchain_metrics.exchange_outflow
        var net_exchange_flow = exchange_outflow - exchange_inflow

        # Whale tracking conditions
        if (large_buys > large_sells * 1.5 or net_whale_flow > 100000) and whale_accumulation > 0.7:
            signal.signal_type = "BUY"
            signal.confidence = min_float(whale_accumulation * 0.7 + net_exchange_flow / 200000 * 0.3, 0.90)
            signal.strength = whale_accumulation
            signal.position_size = 0.4 + signal.confidence * 0.4

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price + atr * 2.5
            signal.stop_loss = data.prices.current_price - atr * 1.5
            signal.reasoning = f"Whale accumulation: Score {whale_accumulation:.3f}, Net flow ${net_whale_flow:,.0f}"
            signal.priority = 4

        elif (large_sells > large_buys * 1.5 or net_whale_flow < -100000) and whale_accumulation < 0.3:
            signal.signal_type = "SELL"
            signal.confidence = min_float((1.0 - whale_accumulation) * 0.6 + abs_float(net_exchange_flow) / 250000 * 0.4, 0.85)
            signal.strength = 1.0 - whale_accumulation
            signal.position_size = 0.3 + signal.confidence * 0.3

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price - atr * 2.0
            signal.stop_loss = data.prices.current_price + atr * 1.8
            signal.reasoning = f"Whale distribution: Score {whale_accumulation:.3f}, Net flow ${net_whale_flow:,.0f}"
            signal.priority = 3

        return signal

    # 6. SENTIMENT MOMENTUM STRATEGY
    fn _sentiment_momentum_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="sentiment_momentum",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="15m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=2,
            timestamp=now()
        )

        # Sentiment analysis
        var overall_sentiment = analysis.sentiment.overall_sentiment
        var sentiment_momentum = analysis.sentiment.sentiment_momentum
        var social_volume = analysis.sentiment.social_volume_score

        # News impact
        var news_sentiment = analysis.sentiment.news_sentiment_score
        var breaking_news = analysis.sentiment.breaking_news_count

        # Fear & Greed analysis
        var fear_greed = analysis.sentiment.fear_greed_index

        # Sentiment momentum conditions
        if overall_sentiment > 0.7 and sentiment_momentum > 0.3 and social_volume > 0.6:
            signal.signal_type = "BUY"
            signal.confidence = min_float(overall_sentiment * 0.5 + sentiment_momentum * 0.3 + social_volume * 0.2, 0.85)
            signal.strength = overall_sentiment

            # Boost confidence for breaking news
            if breaking_news > 0 and news_sentiment > 0.8:
                signal.confidence = min_float(signal.confidence + 0.1, 0.90)
                signal.priority = 3
            else:
                signal.priority = 2

            signal.position_size = 0.25 + signal.confidence * 0.25

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price + atr * 2.0
            signal.stop_loss = data.prices.current_price - atr * 1.3
            signal.reasoning = f"Bullish sentiment: {overall_sentiment:.3f}, Momentum {sentiment_momentum:.3f}"

        elif overall_sentiment < 0.3 and sentiment_momentum < -0.3 and social_volume > 0.5:
            signal.signal_type = "SELL"
            signal.confidence = min_float((1.0 - overall_sentiment) * 0.5 + abs_float(sentiment_momentum) * 0.3 + social_volume * 0.2, 0.80)
            signal.strength = 1.0 - overall_sentiment
            signal.position_size = 0.2 + signal.confidence * 0.2

            var atr = analysis.technical.atr
            signal.take_profit = data.prices.current_price - atr * 1.8
            signal.stop_loss = data.prices.current_price + atr * 1.5
            signal.reasoning = f"Bearish sentiment: {overall_sentiment:.3f}, Momentum {sentiment_momentum:.3f}"
            signal.priority = 2

        return signal

    # 7. PATTERN RECOGNITION STRATEGY
    fn _pattern_recognition_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="pattern_recognition",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="30m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=2,
            timestamp=now()
        )

        # Chart pattern analysis
        var bullish_patterns = analysis.patterns.bullish_patterns
        var bearish_patterns = analysis.patterns.bearish_patterns
        var pattern_strength = analysis.patterns.pattern_strength

        # Candlestick patterns
        var hammer = analysis.patterns.hammer_pattern
        var doji = analysis.patterns.doji_pattern
        var engulfing = analysis.patterns.engulfing_pattern

        # Support/Resistance levels
        var support_distance = (data.prices.current_price - analysis.patterns.nearest_support) / data.prices.current_price
        var resistance_distance = (analysis.patterns.nearest_resistance - data.prices.current_price) / data.prices.current_price

        # Pattern recognition conditions
        if bullish_patterns > 0 and pattern_strength > 0.6:
            signal.signal_type = "BUY"
            signal.confidence = min_float(pattern_strength * 0.7 + bullish_patterns * 0.1, 0.85)
            signal.strength = pattern_strength

            # Boost for strong candlestick patterns
            if hammer or engulfing:
                signal.confidence = min_float(signal.confidence + 0.08, 0.90)
                signal.priority = 3

            signal.position_size = 0.2 + signal.confidence * 0.3

            signal.take_profit = analysis.patterns.nearest_resistance * 0.98
            signal.stop_loss = analysis.patterns.nearest_support * 1.02
            signal.reasoning = f"Bullish patterns: {bullish_patterns}, Strength {pattern_strength:.3f}"

        elif bearish_patterns > 0 and pattern_strength > 0.6:
            signal.signal_type = "SELL"
            signal.confidence = min_float(pattern_strength * 0.7 + bearish_patterns * 0.1, 0.80)
            signal.strength = pattern_strength
            signal.position_size = 0.15 + signal.confidence * 0.25

            signal.take_profit = analysis.patterns.nearest_support * 1.02
            signal.stop_loss = analysis.patterns.nearest_resistance * 0.98
            signal.reasoning = f"Bearish patterns: {bearish_patterns}, Strength {pattern_strength:.3f}"
            signal.priority = 2

        return signal

    # 8. ADVANCED STATISTICAL ARBITRAGE STRATEGY
    fn _statistical_arbitrage_strategy(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis) -> StrategySignal:
        var signal = StrategySignal(
            strategy_name="statistical_arbitrage",
            signal_type="HOLD",
            confidence=0.0,
            strength=0.0,
            timeframe="5m",
            entry_price=data.prices.current_price,
            take_profit=0.0,
            stop_loss=0.0,
            position_size=0.0,
            reasoning="",
            priority=2,  # Higher priority for advanced statistical arbitrage
            timestamp=now()
        )

        # Check if we have sufficient price history for statistical arbitrage
        if data.prices.price_history.size() < self.statistical_arbitrage_engine.min_history_points:
            signal.reasoning = f"Insufficient price history: {data.prices.price_history.size()} < {self.statistical_arbitrage_engine.min_history_points}"
            return signal

        # Update pair histories and generate signals for configured pairs
        var current_time = now()
        var current_price = data.prices.current_price

        # Get external prices for pairs trading
        var btc_price = self._get_external_price("BTC")
        var eth_price = self._get_external_price("ETH")

        # Update BTC-ETH pair if both prices are available
        if btc_price > 0.0 and eth_price > 0.0:
            self.statistical_arbitrage_engine.update_pair_history("BTC", "ETH", current_time, btc_price, eth_price)

            # Generate signal for BTC-ETH pair
            var stat_signal = self.statistical_arbitrage_engine.generate_signal("BTC", "ETH")

            if stat_signal.should_trade():
                # Convert StatArbSignal to StrategySignal
                if stat_signal.signal_type == "LONG_SPREAD":
                    signal.signal_type = "BUY"
                    signal.reasoning = f"BTC-ETH Long Spread: Z={stat_signal.z_score:.2f}, H={stat_signal.hurst_exponent:.3f}"
                elif stat_signal.signal_type == "SHORT_SPREAD":
                    signal.signal_type = "SELL"
                    signal.reasoning = f"BTC-ETH Short Spread: Z={stat_signal.z_score:.2f}, H={stat_signal.hurst_exponent:.3f}"
                else:
                    signal.reasoning = f"BTC-ETH Signal: {stat_signal.signal_type}"
                    return signal  # Non-entry signals don't generate trades

                signal.confidence = stat_signal.confidence * 0.9  # Slightly conservative
                signal.strength = abs(stat_signal.z_score) / 3.0
                signal.position_size = 0.1 + signal.confidence * 0.2

                # Set risk management based on spread characteristics
                var atr = analysis.technical.atr
                var half_life_factor = min(2.0, stat_signal.half_life / 10.0)  # Adjust for mean reversion timing

                if signal.signal_type == "BUY":
                    signal.take_profit = current_price + atr * half_life_factor * 1.5
                    signal.stop_loss = current_price - atr * 0.8
                else:
                    signal.take_profit = current_price - atr * half_life_factor * 1.5
                    signal.stop_loss = current_price + atr * 0.8

                return signal

        # Fallback: Single-asset statistical analysis using enhanced z-score
        var z_score = analysis.predictive.price_z_score
        var mean_reversion_prob = analysis.predictive.mean_reversion_probability
        var trend_momentum = analysis.predictive.trend_momentum_score

        # Enhanced statistical conditions with Hurst exponent consideration
        var hurst_indicator = self._estimate_hurst_exponent(data.prices.price_history)
        var is_mean_reverting = hurst_indicator < 0.5

        if is_mean_reverting and abs_float(z_score) > self.statistical_arbitrage_engine.z_score_entry and mean_reversion_prob > 0.7:
            if z_score > 0:
                signal.signal_type = "SELL"
                signal.reasoning = f"Overextended mean-reverting: Z={z_score:.2f}, H={hurst_indicator:.3f}"
            else:
                signal.signal_type = "BUY"
                signal.reasoning = f"Oversold mean-reverting: Z={z_score:.2f}, H={hurst_indicator:.3f}"

            signal.confidence = min_float(abs_float(z_score) / 4.0 * 0.7 + mean_reversion_prob * 0.3, 0.85)
            signal.strength = abs_float(z_score) / 3.0
            signal.position_size = 0.12 + signal.confidence * 0.18

            # Dynamic risk management based on mean reversion strength
            var atr = analysis.technical.atr
            var reversion_strength = (0.5 - hurst_indicator) * 2.0  # Stronger for lower Hurst

            if signal.signal_type == "BUY":
                signal.take_profit = data.prices.current_price + atr * (1.0 + reversion_strength)
                signal.stop_loss = data.prices.current_price - atr * (0.6 + reversion_strength * 0.4)
            else:
                signal.take_profit = data.prices.current_price - atr * (1.0 + reversion_strength)
                signal.stop_loss = data.prices.current_price + atr * (0.6 + reversion_strength * 0.4)

        # Cross-exchange arbitrage (enhanced)
        else:
            var price_diff_birdeye = abs_float(data.prices.dexscreener_price - data.prices.birdeye_price) / data.prices.dexscreener_price
            var price_diff_jupiter = abs_float(data.prices.dexscreener_price - data.prices.jupiter_price) / data.prices.dexscreener_price
            var max_price_diff = max_float(price_diff_birdeye, price_diff_jupiter)

            if max_price_diff > 0.004:  # 0.4% threshold (slightly lower for more opportunities)
                signal.signal_type = "BUY"
                signal.confidence = min_float(max_price_diff * 100 * 0.9, 0.90)
                signal.strength = max_price_diff * 60
                signal.position_size = 0.08 + signal.confidence * 0.12

                signal.take_profit = data.prices.current_price * 1.0025  # 0.25% profit target
                signal.stop_loss = data.prices.current_price * 0.9975   # 0.25% stop loss
                signal.reasoning = f"Cross-exchange arbitrage: {max_price_diff*100:.2f}% price difference"
                signal.priority = 1

        return signal

    # Helper methods for advanced statistical arbitrage
    fn _get_external_price_history(self, asset: String, min_length: Int) -> Tensor[DType.float64]:
        """Get external asset price history for pairs trading analysis"""
        # In a real implementation, this would fetch from external APIs
        # For now, return synthetic correlated data for demonstration
        if asset == "BTC":
            # Generate synthetic BTC prices (highly correlated with major memecoins)
            var prices = Tensor[DType.float64](min_length)
            var base_price = 65000.0
            for i in range(min_length):
                var random_factor = 1.0 + (random() - 0.5) * 0.02  # 2% daily volatility
                var trend_factor = 1.0 + DType.float64(i) * 0.0001  # Slight upward trend
                prices[i] = base_price * random_factor * trend_factor
            return prices
        elif asset == "ETH":
            # Generate synthetic ETH prices (correlated with BTC)
            var prices = Tensor[DType.float64](min_length)
            var base_price = 3500.0
            for i in range(min_length):
                var random_factor = 1.0 + (random() - 0.5) * 0.025  # 2.5% daily volatility
                var trend_factor = 1.0 + DType.float64(i) * 0.00015  # Slight upward trend
                prices[i] = base_price * random_factor * trend_factor
            return prices
        else:
            return Tensor[DType.float64]()

    fn _estimate_hurst_exponent(self, prices: Tensor[DType.float64]) -> Float32:
        """Quick Hurst exponent estimation for mean reversion analysis"""
        if prices.size() < 20:
            return 0.5  # Random walk assumption

        # Simplified R/S calculation for speed
        var n = prices.size()
        var mean = 0.0
        for i in range(n):
            mean += prices[i]
        mean /= DType.float64(n)

        # Calculate cumulative deviations
        var cumulative_dev = Tensor[DType.float64](n)
        cumulative_dev[0] = prices[0] - mean
        for i in range(1, n):
            cumulative_dev[i] = cumulative_dev[i-1] + (prices[i] - mean)

        # Calculate range
        var max_dev = cumulative_dev[0]
        var min_dev = cumulative_dev[0]
        for i in range(n):
            max_dev = max(max_dev, cumulative_dev[i])
            min_dev = min(min_dev, cumulative_dev[i])
        var range = max_dev - min_dev

        # Calculate standard deviation
        var variance = 0.0
        for i in range(n):
            variance += pow(prices[i] - mean, 2)
        variance /= DType.float64(n)
        var std_dev = sqrt(variance)

        if std_dev == 0.0:
            return 0.5

        # Simplified Hurst estimation
        var rs = range / std_dev
        var hurst = log(rs) / log(DType.float64(n))

        # Bound between 0 and 1
        return max(0.0, min(1.0, hurst))

    def _get_external_price(self, asset: String) -> DType.float64:
        """Get current external price for an asset (simplified implementation)"""
        # In a real implementation, this would fetch from external APIs
        # For now, return mock prices for testing
        if asset == "BTC":
            return 65000.0 + (random() - 0.5) * 1000.0  # BTC around $65k with volatility
        elif asset == "ETH":
            return 3500.0 + (random() - 0.5) * 100.0    # ETH around $3.5k with volatility
        elif asset == "SOL":
            return 150.0 + (random() - 0.5) * 10.0       # SOL around $150 with volatility
        else:
            return 0.0

    # Helper Methods
    fn _update_market_regime(inout self, data: EnhancedMarketData, analysis: ComprehensiveAnalysis):
        var volatility_ratio = analysis.technical.volatility / analysis.technical.avg_volatility
        var trend_strength = analysis.technical.adx
        var sentiment = analysis.sentiment.overall_sentiment

        if volatility_ratio > 2.0:
            self.market_regime = "HIGH_VOLATILITY"
        elif trend_strength > 40.0 and sentiment > 0.6:
            self.market_regime = "BULL_TREND"
        elif trend_strength > 40.0 and sentiment < 0.4:
            self.market_regime = "BEAR_TREND"
        elif volatility_ratio < 0.7:
            self.market_regime = "LOW_VOLATILITY"
        else:
            self.market_regime = "NEUTRAL"

    fn _filter_signals(inout self, signals: List[StrategySignal]) -> List[StrategySignal]:
        var filtered = List[StrategySignal]()

        for signal in signals:
            if signal.confidence > 0.3 and signal.strength > 0.2:
                filtered.append(signal)

        return filtered

    fn _apply_strategy_weights(inout self, signals: List[StrategySignal]) -> Dict[String, Float32]:
        var weighted = Dict[String, Float32]()

        for signal in signals:
            var weight = self.strategy_weights[signal.strategy_name]
            var weighted_confidence = signal.confidence * weight

            weighted[signal.signal_type] = weighted.get(signal.signal_type, 0.0) + weighted_confidence

        return weighted

    fn _calculate_consensus(inout self, weighted_signals: Dict[String, Float32], data: EnhancedMarketData) -> EnsembleDecision:
        var decision = EnsembleDecision(
            final_signal="HOLD",
            aggregated_confidence=0.0,
            consensus_strength=0.0,
            contributing_strategies=List[String](),
            weighted_signals=weighted_signals,
            risk_adjusted_size=0.0,
            optimal_entry=data.prices.current_price,
            optimal_exit=0.0,
            stop_loss_distance=0.0,
            expected_return=0.0,
            time_horizon="15m",
            market_regime=self.market_regime,
            execution_urgency="NORMAL"
        )

        var buy_weight = weighted_signals.get("BUY", 0.0)
        var sell_weight = weighted_signals.get("SELL", 0.0)
        var total_weight = buy_weight + sell_weight

        if total_weight > 0:
            var buy_ratio = buy_weight / total_weight

            if buy_ratio > self.consensus_threshold:
                decision.final_signal = "BUY"
                decision.aggregated_confidence = buy_weight
                decision.consensus_strength = buy_ratio
                decision.execution_urgency = "HIGH" if buy_ratio > 0.8 else "NORMAL"

            elif (1.0 - buy_ratio) > self.consensus_threshold:
                decision.final_signal = "SELL"
                decision.aggregated_confidence = sell_weight
                decision.consensus_strength = 1.0 - buy_ratio
                decision.execution_urgency = "HIGH" if (1.0 - buy_ratio) > 0.8 else "NORMAL"

            # Calculate position size based on consensus
            decision.risk_adjusted_size = min_float(decision.aggregated_confidence * 0.8, self.max_position_size)

        return decision

    fn _apply_risk_adjustments(inout self, decision: EnsembleDecision, analysis: ComprehensiveAnalysis) -> EnsembleDecision:
        # Adjust position size based on volatility
        var volatility_adjustment = 1.0
        if analysis.technical.volatility > analysis.technical.avg_volatility * 2.0:
            volatility_adjustment = 0.7
        elif analysis.technical.volatility < analysis.technical.avg_volatility * 0.5:
            volatility_adjustment = 1.2

        decision.risk_adjusted_size *= volatility_adjustment

        # Adjust expected return based on market regime
        if self.market_regime == "HIGH_VOLATILITY":
            decision.expected_return *= 0.8
        elif self.market_regime == "BULL_TREND":
            decision.expected_return *= 1.2

        return decision

    fn _update_performance_history(inout self, decision: EnsembleDecision, signals: List[StrategySignal]):
        # Store performance for adaptive weight learning
        for signal in signals:
            self.performance_history.append(signal)

        # Keep history manageable
        if len(self.performance_history) > 1000:
            self.performance_history = self.performance_history[-500:]

    fn _adapt_strategy_weights(inout self, signals: List[StrategySignal]):
        # Simple adaptive weight adjustment based on recent performance
        if len(self.performance_history) < 50:
            return

        var recent_performance = self.performance_history[-20:]
        var strategy_performance = Dict[String, Float32]()
        var strategy_counts = Dict[String, Int]()

        for signal in recent_performance:
            var current_performance = signal.confidence * (1.0 if signal.signal_type in ["BUY", "SELL"] else 0.0)
            strategy_performance[signal.strategy_name] = strategy_performance.get(signal.strategy_name, 0.0) + current_performance
            strategy_counts[signal.strategy_name] = strategy_counts.get(signal.strategy_name, 0) + 1

        # Adjust weights based on performance
        for strategy in strategy_performance.keys():
            if strategy_counts[strategy] > 0:
                var avg_performance = strategy_performance[strategy] / strategy_counts[strategy]
                if avg_performance > 0.6:
                    self.strategy_weights[strategy] = min_float(self.strategy_weights[strategy] * 1.05, 0.25)
                elif avg_performance < 0.3:
                    self.strategy_weights[strategy] = max_float(self.strategy_weights[strategy] * 0.95, 0.05)

        # Normalize weights
        var total_weight = 0.0
        for weight in self.strategy_weights.values():
            total_weight += weight

        if total_weight > 0:
            for strategy in self.strategy_weights.keys():
                self.strategy_weights[strategy] = self.strategy_weights[strategy] / total_weight