# =============================================================================
# Advanced Pattern Recognition System - Algorithmic Intelligence
# =============================================================================

import core.types
import core.constants
from time import time
from collections import Dict, List
from math import abs, sqrt

# =============================================================================
# Pattern Recognition System
# =============================================================================

@value
struct PatternRecognition:
    """
    Pattern types for trading analysis
    """
    var name: String
    var confidence: Float
    var direction: TradingAction  # BUY, SELL, or HOLD
    var timeframe: String
    var strength: Float  # 0.0 to 1.0
    var metadata: Dict[String, Any]

    fn __init__(
        name: String = "",
        confidence: Float = 0.0,
        direction: TradingAction = TradingAction.HOLD,
        timeframe: String = "5m",
        strength: Float = 0.0,
        metadata: Dict[String, Any] = {}
    ):
        self.name = name
        self.confidence = max(0.0, min(1.0, confidence))
        self.direction = direction
        self.timeframe = timeframe
        self.strength = max(0.0, min(1.0, strength))
        self.metadata = metadata

@value
struct PatternAnalysis:
    """
    Complete pattern analysis result
    """
    var patterns: List[PatternRecognition]
    var confidence: Float
    var primary_pattern: String
    var overall_direction: TradingAction
    var pattern_strength: Float
    var timestamp: Float

    fn __init__(
        patterns: List[PatternRecognition] = [],
        confidence: Float = 0.0,
        primary_pattern: String = "NO_PATTERN",
        overall_direction: TradingAction = TradingAction.HOLD,
        pattern_strength: Float = 0.0,
        timestamp: Float = time()
    ):
        self.patterns = patterns
        self.confidence = max(0.0, min(1.0, confidence))
        self.primary_pattern = primary_pattern
        self.overall_direction = overall_direction
        self.pattern_strength = max(0.0, min(1.0, pattern_strength))
        self.timestamp = timestamp

# =============================================================================
# Pattern Recognizer
# =============================================================================

@value
struct PatternRecognizer:
    """
    Advanced pattern recognition without external AI
    """
    var micro_patterns: MicroPatternLibrary
    var whale_patterns: WhalePatternLibrary
    var manipulation_patterns: ManipulationPatternLibrary
    var technical_patterns: TechnicalPatternLibrary

    fn __init__():
        self.micro_patterns = MicroPatternLibrary()
        self.whale_patterns = WhalePatternLibrary()
        self.manipulation_patterns = ManipulationPatternLibrary()
        self.technical_patterns = TechnicalPatternLibrary()

    fn identify_patterns(self, market_data: MarketData) -> PatternAnalysis:
        """
        Identify all relevant patterns in market data
        """
        var start_time = time()

        var all_patterns: List[PatternRecognition] = []

        # 1. Micro-patterns (5s-15s timeframe)
        var micro_results = self.micro_patterns.analyze(market_data)
        all_patterns.extend(micro_results)

        # 2. Whale behavior patterns
        var whale_results = self.whale_patterns.analyze(market_data)
        all_patterns.extend(whale_results)

        # 3. Manipulation detection patterns
        var manipulation_results = self.manipulation_patterns.analyze(market_data)
        all_patterns.extend(manipulation_results)

        # 4. Technical patterns
        var technical_results = self.technical_patterns.analyze(market_data)
        all_patterns.extend(technical_results)

        # 5. Aggregate results
        var analysis = self._aggregate_patterns(all_patterns)
        analysis.timestamp = start_time

        return analysis

    fn _aggregate_patterns(self, patterns: List[PatternRecognition]) -> PatternAnalysis:
        """
        Aggregate multiple patterns into coherent analysis
        """
        if not patterns:
            return PatternAnalysis(
                confidence=0.0,
                primary_pattern="NO_CLEAR_PATTERN",
                overall_direction=TradingAction.HOLD,
                pattern_strength=0.0
            )

        # Calculate overall confidence
        var total_confidence = sum(p.confidence for p in patterns)
        var overall_confidence = min(total_confidence / len(patterns), 1.0)

        # Determine primary pattern by priority and confidence
        var primary_pattern = self._identify_primary_pattern(patterns)
        var overall_direction = self._determine_overall_direction(patterns)
        var pattern_strength = self._calculate_overall_strength(patterns)

        return PatternAnalysis(
            patterns=patterns,
            confidence=overall_confidence,
            primary_pattern=primary_pattern,
            overall_direction=overall_direction,
            pattern_strength=pattern_strength
        )

    fn _identify_primary_pattern(self, patterns: List[PatternRecognition]) -> String:
        """
        Identify the most important pattern
        """
        # Priority order for patterns
        var priority_patterns = [
            "WHALE_ACCUMULATION",
            "WHALE_DISTRIBUTION",
            "PUMP_AND_DUMP",
            "LIQUIDITY_DRAIN",
            "SUPPORT_BOUNCE",
            "RESISTANCE_BREAK",
            "VOLUME_SPIKE",
            "RSI_DIVERGENCE",
            "MOMENTUM_SHIFT"
        ]

        for priority in priority_patterns:
            for pattern in patterns:
                if pattern.name == priority and pattern.confidence > 0.6:
                    return priority

        return patterns[0].name if patterns else "NO_CLEAR_PATTERN"

    fn _determine_overall_direction(self, patterns: List[PatternRecognition]) -> TradingAction:
        """
        Determine overall trading direction from all patterns
        """
        var buy_score = 0.0
        var sell_score = 0.0

        for pattern in patterns:
            if pattern.direction == TradingAction.BUY:
                buy_score += pattern.confidence * pattern.strength
            elif pattern.direction == TradingAction.SELL:
                sell_score += pattern.confidence * pattern.strength

        if buy_score > sell_score and buy_score > 0.3:
            return TradingAction.BUY
        elif sell_score > buy_score and sell_score > 0.3:
            return TradingAction.SELL
        else:
            return TradingAction.HOLD

    fn _calculate_overall_strength(self, patterns: List[PatternRecognition]) -> Float:
        """
        Calculate overall pattern strength
        """
        if not patterns:
            return 0.0

        var total_strength = sum(p.strength for p in patterns)
        return min(total_strength / len(patterns), 1.0)

# =============================================================================
# Micro Pattern Library
# =============================================================================

@value
struct MicroPatternLibrary:
    """
    Library for micro-patterns (5s-15s timeframes)
    """
    fn analyze(self, market_data: MarketData) -> List[PatternRecognition]:
        """
        Analyze micro-patterns in market data
        """
        var patterns: List[PatternRecognition] = []

        # 1. Support Bounce Pattern
        if self._detect_support_bounce(market_data):
            patterns.append(PatternRecognition(
                name="SUPPORT_BOUNCE",
                confidence=0.8,
                direction=TradingAction.BUY,
                timeframe="5m",
                strength=0.75
            ))

        # 2. Volume Spike Pattern
        if self._detect_volume_spike(market_data):
            patterns.append(PatternRecognition(
                name="VOLUME_SPIKE",
                confidence=0.7,
                direction=self._determine_volume_direction(market_data),
                timeframe="5m",
                strength=0.6
            ))

        # 3. Momentum Shift Pattern
        if self._detect_momentum_shift(market_data):
            patterns.append(PatternRecognition(
                name="MOMENTUM_SHIFT",
                confidence=0.75,
                direction=self._determine_momentum_direction(market_data),
                timeframe="1m",
                strength=0.65
            ))

        return patterns

    fn _detect_support_bounce(self, market_data: MarketData) -> Bool:
        """
        Detect support bounce pattern
        """
        # Price dropped but is recovering
        var price_change_5m = market_data.price_change_5m
        var price_change_1h = market_data.price_change_1h

        # Support bounce: Negative 1h change but positive 5m change
        return price_change_1h < -0.02 and price_change_5m > 0.01

    fn _detect_volume_spike(self, market_data: MarketData) -> Bool:
        """
        Detect abnormal volume spike
        """
        # High transaction count indicates volume spike
        return market_data.transaction_count > 50

    fn _determine_volume_direction(self, market_data: MarketData) -> TradingAction:
        """
        Determine if volume spike is bullish or bearish
        """
        # Volume spike + price increase = bullish
        if market_data.price_change_5m > 0.02:
            return TradingAction.BUY
        # Volume spike + price decrease = bearish
        elif market_data.price_change_5m < -0.02:
            return TradingAction.SELL
        else:
            return TradingAction.HOLD

    fn _detect_momentum_shift(self, market_data: MarketData) -> Bool:
        """
        Detect momentum shift
        """
        var change_5m = market_data.price_change_5m
        var change_1h = market_data.price_change_1h

        # Momentum shift: Different direction between 5m and 1h
        return (change_5m > 0.01 and change_1h < -0.01) or (change_5m < -0.01 and change_1h > 0.01)

    fn _determine_momentum_direction(self, market_data: MarketData) -> TradingAction:
        """
        Determine momentum shift direction
        """
        # Follow the 5-minute trend (most recent)
        if market_data.price_change_5m > 0:
            return TradingAction.BUY
        else:
            return TradingAction.SELL

# =============================================================================
# Whale Pattern Library
# =============================================================================

@value
struct WhalePatternLibrary:
    """
    Library for whale behavior patterns
    """
    fn analyze(self, market_data: MarketData) -> List[PatternRecognition]:
        """
        Analyze whale behavior patterns
        """
        var patterns: List[PatternRecognition] = []

        # 1. Whale Accumulation Pattern
        if self._detect_whale_accumulation(market_data):
            patterns.append(PatternRecognition(
                name="WHALE_ACCUMULATION",
                confidence=0.8,
                direction=TradingAction.BUY,
                timeframe="1h",
                strength=0.7,
                metadata={"whale_confidence": 0.8}
            ))

        # 2. Whale Distribution Pattern
        if self._detect_whale_distribution(market_data):
            patterns.append(PatternRecognition(
                name="WHALE_DISTRIBUTION",
                confidence=0.8,
                direction=TradingAction.SELL,
                timeframe="1h",
                strength=0.7,
                metadata={"whale_confidence": 0.8}
            ))

        # 3. Whale Manipulation Pattern
        if self._detect_whale_manipulation(market_data):
            patterns.append(PatternRecognition(
                name="WHALE_MANIPULATION",
                confidence=0.9,
                direction=TradingAction.SELL,
                timeframe="5m",
                strength=0.9,
                metadata={"manipulation_type": "wash_trading"}
            ))

        return patterns

    fn _detect_whale_accumulation(self, market_data: MarketData) -> Bool:
        """
        Detect whale accumulation pattern
        """
        # Whale accumulation signs:
        # 1. High volume with moderate price increase
        # 2. Growing liquidity
        # 3. Increasing holder count

        return (
            market_data.volume_24h > MIN_VOLUME_USD * 2 and
            market_data.price_change_1h > 0.01 and market_data.price_change_1h < 0.05 and
            market_data.liquidity_usd > MIN_LIQUIDITY_USD and
            market_data.holder_count > 10
        )

    fn _detect_whale_distribution(self, market_data: MarketData) -> Bool:
        """
        Detect whale distribution pattern
        """
        # Whale distribution signs:
        # 1. High volume with price decrease
        # 2. Decreasing holder count
        # 3. Price volatility

        return (
            market_data.volume_24h > MIN_VOLUME_USD * 2 and
            market_data.price_change_1h < -0.02 and
            abs(market_data.price_change_5m) > 0.03
        )

    fn _detect_whale_manipulation(self, market_data: MarketData) -> Bool:
        """
        Detect whale manipulation patterns
        """
        # Manipulation signs:
        # 1. Extreme price volatility
        # 2. High volume but small holder count
        # 3. Suspicious transaction patterns

        return (
            abs(market_data.price_change_5m) > 0.1 and
            market_data.volume_24h > MIN_VOLUME_USD and
            market_data.holder_count < 20
        )

# =============================================================================
# Manipulation Pattern Library
# =============================================================================

@value
struct ManipulationPatternLibrary:
    """
    Library for manipulation detection patterns
    """
    fn analyze(self, market_data: MarketData) -> List[PatternRecognition]:
        """
        Analyze manipulation patterns
        """
        var patterns: List[PatternRecognition] = []

        # 1. Pump and Dump Pattern
        if self._detect_pump_and_dump(market_data):
            patterns.append(PatternRecognition(
                name="PUMP_AND_DUMP",
                confidence=0.9,
                direction=TradingAction.SELL,
                timeframe="15m",
                strength=0.85
            ))

        # 2. Liquidity Drain Pattern
        if self._detect_liquidity_drain(market_data):
            patterns.append(PatternRecognition(
                name="LIQUIDITY_DRAIN",
                confidence=0.8,
                direction=TradingAction.SELL,
                timeframe="5m",
                strength=0.75
            ))

        return patterns

    fn _detect_pump_and_dump(self, market_data: MarketData) -> Bool:
        """
        Detect pump and dump pattern
        """
        # Pump and dump signs:
        # 1. Very high 5m gain (>10%)
        # 2. High volume
        # 3. Low liquidity relative to volume

        return (
            market_data.price_change_5m > 0.10 and
            market_data.volume_24h > MIN_VOLUME_USD * 3 and
            market_data.liquidity_usd < market_data.volume_24h * 0.5
        )

    fn _detect_liquidity_drain(self, market_data: MarketData) -> Bool:
        """
        Detect liquidity drain pattern
        """
        # Liquidity drain signs:
        # 1. High volume but decreasing liquidity
        # 2. Price decline
        # 3. Low liquidity ratio

        return (
            market_data.volume_24h > MIN_VOLUME_USD * 2 and
            market_data.price_change_1h < -0.05 and
            market_data.liquidity_usd < MIN_LIQUIDITY_USD
        )

# =============================================================================
# Technical Pattern Library
# =============================================================================

@value
struct TechnicalPatternLibrary:
    """
    Library for technical analysis patterns
    """
    fn analyze(self, market_data: MarketData) -> List[PatternRecognition]:
        """
        Analyze technical patterns
        """
        var patterns: List[PatternRecognition] = []

        # 1. Support/Resistance Break Pattern
        if self._detect_support_resistance_break(market_data):
            patterns.append(PatternRecognition(
                name="RESISTANCE_BREAK",
                confidence=0.75,
                direction=TradingAction.BUY,
                timeframe="1h",
                strength=0.7
            ))

        # 2. RSI Divergence Pattern
        if self._detect_rsi_divergence(market_data):
            patterns.append(PatternRecognition(
                name="RSI_DIVERGENCE",
                confidence=0.7,
                direction=TradingAction.BUY,
                timeframe="5m",
                strength=0.65
            ))

        return patterns

    fn _detect_support_resistance_break(self, market_data: MarketData) -> Bool:
        """
        Detect support/resistance break
        """
        # Support/resistance break signs:
        # 1. Significant price movement
        # 2. High volume confirmation
        # 3. Breakthrough key psychological levels

        var price_movement = abs(market_data.price_change_1h)
        return price_movement > 0.05 and market_data.volume_24h > MIN_VOLUME_USD

    fn _detect_rsi_divergence(self, market_data: MarketData) -> Bool:
        """
        Detect RSI divergence patterns
        """
        # RSI divergence signs:
        # 1. Price making new highs/lows
        # 2. RSI not confirming
        # 3. Volume patterns

        # This would need historical RSI data
        # For now, use price patterns as proxy
        var price_strength = abs(market_data.price_change_5m)
        return 0.02 < price_strength < 0.06 and market_data.volume_24h > MIN_VOLUME_USD