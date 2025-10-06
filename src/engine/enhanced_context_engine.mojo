# =============================================================================
# Enhanced Context Engine - Algorithmic Intelligence without External AI
# =============================================================================

import core.config
import core.types
import core.constants
import analysis.sentiment_analyzer
import analysis.pattern_recognizer
import analysis.whale_tracker
from time import time
from collections import Dict, List
from math import sqrt

# =============================================================================
# Enhanced Context Engine
# =============================================================================

@value
struct EnhancedContextEngine:
    """
    Enhanced context engine using algorithmic intelligence instead of external AI
    """
    var config: Config
    var sentiment_analyzer: SentimentAnalyzer
    var pattern_recognizer: PatternRecognizer
    var whale_tracker: WhaleTracker
    var confluence_detector: ConfluenceDetector
    var regime_detector: RegimeDetector
    var risk_assessor: RiskAssessor

    fn __init__(config: Config):
        self.config = config
        self.sentiment_analyzer = SentimentAnalyzer()
        self.pattern_recognizer = PatternRecognizer()
        self.whale_tracker = WhaleTracker()
        self.confluence_detector = ConfluenceDetector(config)
        self.regime_detector = RegimeDetector()
        self.risk_assessor = RiskAssessor(config)

    fn analyze_symbol(self, symbol: String, market_data: MarketData) -> TradingContext:
        """
        Comprehensive analysis using algorithmic intelligence only
        """
        analysis_start = time()

        # 1. Core Confluence Analysis (RSI + Support/Resistance)
        var confluence = self.confluence_detector.analyze(symbol, market_data)

        # 2. Market Regime Detection
        var regime = self.regime_detector.detect(market_data)

        # 3. Algorithmic Sentiment Analysis (NO AI API!)
        var sentiment = self.sentiment_analyzer.analyze_sentiment(symbol, market_data)

        # 4. Pattern Recognition
        var patterns = self.pattern_recognizer.identify_patterns(market_data)

        # 5. Whale Behavior Analysis
        var whale_analysis = self.whale_tracker.analyze_whale_behavior(symbol, market_data)

        # 6. Enhanced Risk Assessment
        var risk = self.risk_assessor.assess(
            confluence=confluence,
            regime=regime,
            sentiment=sentiment,
            patterns=patterns,
            whale_analysis=whale_analysis
        )

        # 7. Generate Recommended Action
        var recommended_action = self._determine_action(
            confluence, regime, sentiment, patterns, whale_analysis, risk
        )

        processing_time = time() - analysis_start

        return TradingContext(
            symbol=symbol,
            confluence_analysis=confluence,
            market_regime=regime,
            sentiment_analysis=sentiment,
            risk_assessment=risk,
            processing_time=processing_time,
            timestamp=time(),
            recommended_action=recommended_action
        )

    fn _determine_action(
        self,
        confluence: ConfluenceAnalysis,
        regime: MarketRegime,
        sentiment: SentimentAnalysis,
        patterns: PatternAnalysis,
        whale_analysis: WhaleAnalysis,
        risk: RiskAnalysis
    ) -> TradingAction:
        """
        Determine recommended action based on all analysis components
        """
        var buy_score = 0.0
        var sell_score = 0.0

        # 1. Confluence contribution (40% weight)
        if confluence.is_oversold and confluence.distance_to_support < 0.1:
            buy_score += 0.4 * confluence.confluence_strength
        elif confluence.is_overbought and confluence.distance_to_resistance < 0.1:
            sell_score += 0.4 * confluence.confluence_strength

        # 2. Sentiment contribution (25% weight)
        buy_score += 0.25 * max(0.0, sentiment.sentiment_score)
        sell_score += 0.25 * max(0.0, -sentiment.sentiment_score)

        # 3. Pattern contribution (20% weight)
        if patterns.primary_pattern == "SUPPORT_BOUNCE":
            buy_score += 0.2 * patterns.confidence
        elif patterns.primary_pattern == "RESISTANCE_BREAK":
            sell_score += 0.2 * patterns.confidence
        elif patterns.primary_pattern == "WHALE_ACCUMULATION":
            buy_score += 0.15 * patterns.confidence
        elif patterns.primary_pattern == "WHALE_DISTRIBUTION":
            sell_score += 0.15 * patterns.confidence

        # 4. Whale Analysis contribution (10% weight)
        if whale_analysis.behavior == "ACCUMULATING":
            buy_score += 0.1 * whale_analysis.confidence
        elif whale_analysis.behavior == "DISTRIBUTING":
            sell_score += 0.1 * whale_analysis.confidence

        # 5. Market Regime consideration (5% weight)
        if regime == MarketRegime.TRENDING_UP:
            buy_score += 0.05
        elif regime == MarketRegime.TRENDING_DOWN:
            sell_score += 0.05

        # 6. Risk adjustment
        if risk.risk_level == RiskLevel.CRITICAL:
            buy_score *= 0.2
            sell_score *= 0.2
        elif risk.risk_level == RiskLevel.HIGH:
            buy_score *= 0.5
            sell_score *= 0.5

        # Decision
        if buy_score > sell_score and buy_score > 0.3:
            return TradingAction.BUY
        elif sell_score > buy_score and sell_score > 0.3:
            return TradingAction.SELL
        else:
            return TradingAction.HOLD

# =============================================================================
# Confluence Detector
# =============================================================================

@value
struct ConfluenceDetector:
    """
    Detects confluence between RSI and support/resistance levels
    """
    var config: Config
    var rsi_calculator: RSICalculator

    fn __init__(config: Config):
        self.config = config
        self.rsi_calculator = RSICalculator()

    fn analyze(self, symbol: String, market_data: MarketData) -> ConfluenceAnalysis:
        """
        Analyze RSI + Support/Resistance confluence
        """
        # 1. Determine optimal RSI timeframe
        var rsi_timeframe = get_optimal_rsi_timeframe(market_data.age_hours)

        # 2. Calculate RSI
        var rsi_value = self.rsi_calculator.calculate_rsi(symbol, rsi_timeframe, self.config.strategy.rsi_period)

        # 3. Find nearest support and resistance levels
        var nearest_support = find_nearest_psychological_level(market_data.market_cap, above=False)
        var nearest_resistance = find_nearest_psychological_level(market_data.market_cap, above=True)

        # 4. Calculate distances
        var distance_to_support = calculate_distance_to_level(market_data.market_cap, nearest_support)
        var distance_to_resistance = calculate_distance_to_level(market_data.market_cap, nearest_resistance)

        # 5. Determine overbought/oversold
        var is_oversold = rsi_value < self.config.strategy.oversold_threshold
        var is_overbought = rsi_value > self.config.strategy.overbought_threshold

        # 6. Calculate confluence strength
        var confluence_strength = self._calculate_confluence_strength(
            rsi_value, distance_to_support, distance_to_resistance, market_data.volume_24h
        )

        return ConfluenceAnalysis(
            rsi_value=rsi_value,
            rsi_timeframe=rsi_timeframe,
            nearest_support=nearest_support,
            nearest_resistance=nearest_resistance,
            confluence_strength=confluence_strength,
            is_oversold=is_oversold,
            is_overbought=is_overbought,
            distance_to_support=distance_to_support,
            distance_to_resistance=distance_to_resistance
        )

    fn _calculate_confluence_strength(
        self,
        rsi_value: Float,
        distance_to_support: Float,
        distance_to_resistance: Float,
        volume_24h: Float
    ) -> Float:
        """
        Calculate confluence strength score (0.0 to 1.0)
        """
        var score = 0.0

        # Strong confluence: RSI oversold + near support
        if rsi_value < 25.0 and distance_to_support < 0.05:
            score = 0.9
        # Moderate confluence: RSI oversold + moderate support distance
        elif rsi_value < 30.0 and distance_to_support < 0.03:
            score = 0.7
        # Weak confluence: RSI oversold + far support
        elif rsi_value < 25.0 and distance_to_support < 0.10:
            score = 0.6
        # No signal
        else:
            score = 0.3

        # Volume boost
        if volume_24h > MIN_VOLUME_USD * 2:
            score = min(1.0, score + 0.1)

        return score

# =============================================================================
# Regime Detector
# =============================================================================

@value
struct RegimeDetector:
    """
    Detects current market regime
    """
    fn detect(self, market_data: MarketData) -> MarketRegime:
        """
        Detect market regime based on price action and volume
        """
        var price_change_5m = market_data.price_change_5m
        var price_change_1h = market_data.price_change_1h
        var price_change_24h = market_data.price_change_24h

        # Trending Up
        if (price_change_5m > 0.01 and price_change_1h > 0.02 and price_change_24h > 0.05):
            return MarketRegime.TRENDING_UP

        # Trending Down
        elif (price_change_5m < -0.01 and price_change_1h < -0.02 and price_change_24h < -0.05):
            return MarketRegime.TRENDING_DOWN

        # Volatile (large swings)
        elif abs(price_change_5m) > 0.05 or abs(price_change_1h) > 0.1:
            return MarketRegime.VOLATILE

        # Ranging (default)
        else:
            return MarketRegime.RANGING

# =============================================================================
# Risk Assessor
# =============================================================================

@value
struct RiskAssessor:
    """
    Comprehensive risk assessment without external AI
    """
    var config: Config

    fn __init__(config: Config):
        self.config = config

    fn assess(
        self,
        confluence: ConfluenceAnalysis,
        regime: MarketRegime,
        sentiment: SentimentAnalysis,
        patterns: PatternAnalysis,
        whale_analysis: WhaleAnalysis
    ) -> RiskAnalysis:
        """
        Assess overall risk for trading decision
        """
        var risk_score = 0.0
        var risk_factors: List[String] = []

        # 1. Liquidity risk
        var liquidity_risk = self._assess_liquidity_risk()
        risk_score += liquidity_risk * 0.3
        if liquidity_risk > 0.6:
            risk_factors.append("LOW_LIQUIDITY")

        # 2. Volume risk
        var volume_risk = self._assess_volume_risk()
        risk_score += volume_risk * 0.2
        if volume_risk > 0.6:
            risk_factors.append("LOW_VOLUME")

        # 3. Market regime risk
        var regime_risk = self._assess_regime_risk(regime)
        risk_score += regime_risk * 0.2
        if regime_risk > 0.6:
            risk_factors.append("ADVERSE_REGIME")

        # 4. Pattern risk
        var pattern_risk = self._assess_pattern_risk(patterns)
        risk_score += pattern_risk * 0.15
        if pattern_risk > 0.6:
            risk_factors.append("RISKY_PATTERNS")

        # 5. Whale manipulation risk
        var whale_risk = self._assess_whale_risk(whale_analysis)
        risk_score += whale_risk * 0.15
        if whale_risk > 0.6:
            risk_factors.append("WHALE_MANIPULATION")

        # Determine risk level
        var risk_level = RiskLevel.MEDIUM
        if risk_score < 0.3:
            risk_level = RiskLevel.LOW
        elif risk_score > 0.7:
            risk_level = RiskLevel.HIGH
        elif risk_score > 0.85:
            risk_level = RiskLevel.CRITICAL

        return RiskAnalysis(
            risk_level=risk_level,
            confidence=0.8,  # High confidence in algorithmic assessment
            risk_factors=risk_factors,
            wash_trading_score=0.0,  # Will be filled by spam filter
            liquidity_risk_score=liquidity_risk,
            volatility_score=self._calculate_volatility_score()
        )

    fn _assess_liquidity_risk(self) -> Float:
        """
        Assess liquidity risk (0.0 = low risk, 1.0 = high risk)
        """
        # This would use actual liquidity data from market_data
        # For now, return default
        return 0.2

    fn _assess_volume_risk(self) -> Float:
        """
        Assess volume risk
        """
        return 0.1

    fn _assess_regime_risk(self, regime: MarketRegime) -> Float:
        """
        Assess risk based on market regime
        """
        if regime == MarketRegime.VOLATILE:
            return 0.7
        elif regime == MarketRegime.TRENDING_DOWN:
            return 0.5
        else:
            return 0.2

    fn _assess_pattern_risk(self, patterns: PatternAnalysis) -> Float:
        """
        Assess risk based on detected patterns
        """
        if patterns.primary_pattern == "PUMP_AND_DUMP":
            return 0.9
        elif patterns.primary_pattern == "LIQUIDITY_DRAIN":
            return 0.8
        elif patterns.primary_pattern == "WHALE_DISTRIBUTION":
            return 0.6
        else:
            return 0.2

    fn _assess_whale_risk(self, whale_analysis: WhaleAnalysis) -> Float:
        """
        Assess risk from whale behavior
        """
        if whale_analysis.behavior == "MANIPULATION":
            return 0.9
        elif whale_analysis.behavior == "DISTRIBUTING":
            return 0.5
        else:
            return 0.1

    fn _calculate_volatility_score(self) -> Float:
        """
        Calculate volatility risk score
        """
        return 0.3

# =============================================================================
# RSI Calculator
# =============================================================================

@value
struct RSICalculator:
    """
    Calculates RSI with optimal timeframes based on token age
    """
    var price_history: Dict[String, List[Float]]

    fn __init__():
        self.price_history = {}

    fn calculate_rsi(self, symbol: String, timeframe: String, period: Int) -> Float:
        """
        Calculate RSI for given symbol, timeframe, and period
        """
        # In a real implementation, this would fetch historical price data
        # For now, return a placeholder
        return 50.0

    def add_price_data(self, symbol: String, price: Float):
        """
        Add new price data to history
        """
        if symbol not in self.price_history:
            self.price_history[symbol] = List[Float]()

        self.price_history[symbol].append(price)

        # Keep only last 1000 data points
        if len(self.price_history[symbol]) > 1000:
            self.price_history[symbol] = self.price_history[symbol][-1000:]