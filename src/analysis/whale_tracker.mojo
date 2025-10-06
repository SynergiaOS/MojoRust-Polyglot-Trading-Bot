# =============================================================================
# Whale Behavior Tracking System - Algorithmic Intelligence
# =============================================================================

import core.types
import core.constants
from time import time
from collections import Dict, List
from math import min, max, clamp

# =============================================================================
# Whale Analysis Types
# =============================================================================

@value
struct WhaleAnalysis:
    """
    Complete whale behavior analysis
    """
    var behavior: String
    var confidence: Float
    var whale_count: Int
    var activity_level: Float  # 0.0 to 1.0
    var manipulation_risk: Float  # 0.0 to 1.0
    var accumulation_score: Float  # 0.0 to 1.0
    var distribution_score: Float  # 0.0 to 1.0
    var timestamp: Float
    var metadata: Dict[String, Any]

    fn __init__(
        behavior: String = "NEUTRAL",
        confidence: Float = 0.5,
        whale_count: Int = 0,
        activity_level: Float = 0.0,
        manipulation_risk: Float = 0.0,
        accumulation_score: Float = 0.0,
        distribution_score: Float = 0.0,
        timestamp: Float = time(),
        metadata: Dict[String, Any] = {}
    ):
        self.behavior = behavior
        self.confidence = max(0.0, min(1.0, confidence))
        self.whale_count = whale_count
        self.activity_level = max(0.0, min(1.0, activity_level))
        self.manipulation_risk = max(0.0, min(1.0, manipulation_risk))
        self.accumulation_score = max(0.0, min(1.0, accumulation_score))
        self.distribution_score = max(0.0, min(1.0, distribution_score))
        self.timestamp = timestamp
        self.metadata = metadata

@value
struct WhaleTransaction:
    """
    Individual whale transaction for tracking
    """
    var wallet_address: String
    var amount: Float
    var timestamp: Float
    var transaction_type: String  # BUY, SELL
    var price_at_transaction: Float
    var is_suspicious: Bool

    fn __init__(
        wallet_address: String = "",
        amount: Float = 0.0,
        timestamp: Float = time(),
        transaction_type: String = "UNKNOWN",
        price_at_transaction: Float = 0.0,
        is_suspicious: Bool = False
    ):
        self.wallet_address = wallet_address
        self.amount = amount
        self.timestamp = timestamp
        self.transaction_type = transaction_type
        self.price_at_transaction = price_at_transaction
        self.is_suspicious = is_suspicious

# =============================================================================
# Whale Tracker
# =============================================================================

@value
struct WhaleTracker:
    """
    Advanced whale behavior tracking without external APIs
    """
    var transaction_analyzer: WhaleTransactionAnalyzer
    var behavior_detector: WhaleBehaviorDetector
    var manipulation_detector: WhaleManipulationDetector
    var accumulation_tracker: WhaleAccumulationTracker

    fn __init__():
        self.transaction_analyzer = WhaleTransactionAnalyzer()
        self.behavior_detector = WhaleBehaviorDetector()
        self.manipulation_detector = WhaleManipulationDetector()
        self.accumulation_tracker = WhaleAccumulationTracker()

    fn analyze_whale_behavior(self, symbol: String, market_data: MarketData) -> WhaleAnalysis:
        """
        Complete whale behavior analysis
        """
        var start_time = time()

        # 1. Analyze transaction patterns
        var transaction_analysis = self.transaction_analyzer.analyze_transactions(market_data)

        # 2. Detect whale behavior patterns
        var behavior_patterns = self.behavior_detector.detect_behavior(market_data)

        # 3. Check for manipulation
        var manipulation_analysis = self.manipulation_detector.detect_manipulation(market_data)

        # 4. Track accumulation/distribution
        var accumulation_analysis = self.accumulation_tracker.track_accumulation(market_data)

        # 5. Synthesize final analysis
        var final_analysis = self._synthesize_analysis(
            transaction_analysis,
            behavior_patterns,
            manipulation_analysis,
            accumulation_analysis
        )

        final_analysis.timestamp = start_time

        return final_analysis

    fn _synthesize_analysis(
        self,
        transaction_analysis: Dict[str, Any],
        behavior_patterns: Dict[str, Any],
        manipulation_analysis: Dict[str, Any],
        accumulation_analysis: Dict[str, Any]
    ) -> WhaleAnalysis:
        """
        Synthesize all whale analysis components
        """
        # Determine primary behavior
        var behavior = self._determine_primary_behavior(
            behavior_patterns, manipulation_analysis, accumulation_analysis
        )

        # Calculate overall confidence
        var confidence = self._calculate_whale_confidence(
            transaction_analysis, behavior_patterns, manipulation_analysis
        )

        # Calculate activity level
        var activity_level = transaction_analysis.get("activity_level", 0.0)

        # Calculate manipulation risk
        var manipulation_risk = manipulation_analysis.get("risk_score", 0.0)

        # Calculate accumulation/distribution scores
        var accumulation_score = accumulation_analysis.get("accumulation_score", 0.0)
        var distribution_score = accumulation_analysis.get("distribution_score", 0.0)

        # Estimate whale count
        var whale_count = transaction_analysis.get("whale_count", 0)

        return WhaleAnalysis(
            behavior=behavior,
            confidence=confidence,
            whale_count=whale_count,
            activity_level=activity_level,
            manipulation_risk=manipulation_risk,
            accumulation_score=accumulation_score,
            distribution_score=distribution_score,
            metadata={
                "transaction_analysis": transaction_analysis,
                "behavior_patterns": behavior_patterns,
                "manipulation_analysis": manipulation_analysis,
                "accumulation_analysis": accumulation_analysis
            }
        )

    fn _determine_primary_behavior(
        self,
        behavior_patterns: Dict[str, Any],
        manipulation_analysis: Dict[str, Any],
        accumulation_analysis: Dict[str, Any]
    ) -> String:
        """
        Determine the primary whale behavior
        """
        # High manipulation risk takes priority
        if manipulation_analysis.get("risk_score", 0.0) > 0.7:
            return "MANIPULATION"

        # Check accumulation/distribution
        var accumulation_score = accumulation_analysis.get("accumulation_score", 0.0)
        var distribution_score = accumulation_analysis.get("distribution_score", 0.0)

        if accumulation_score > 0.7 and distribution_score < 0.3:
            return "ACCUMULATING"
        elif distribution_score > 0.7 and accumulation_score < 0.3:
            return "DISTRIBUTING"
        elif accumulation_score > 0.5 and distribution_score > 0.5:
            return "CHURNING"
        else:
            return "NEUTRAL"

    fn _calculate_whale_confidence(
        self,
        transaction_analysis: Dict[str, Any],
        behavior_patterns: Dict[str, Any],
        manipulation_analysis: Dict[str, Any]
    ) -> Float:
        """
        Calculate confidence in whale analysis
        """
        var transaction_confidence = transaction_analysis.get("confidence", 0.0)
        var behavior_confidence = behavior_patterns.get("confidence", 0.0)
        var manipulation_confidence = manipulation_analysis.get("confidence", 0.0)

        return (transaction_confidence + behavior_confidence + manipulation_confidence) / 3.0

# =============================================================================
# Whale Transaction Analyzer
# =============================================================================

@value
struct WhaleTransactionAnalyzer:
    """
    Analyzes whale transactions from available market data
    """
    fn analyze_transactions(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Analyze whale transaction patterns
        """
        var analysis: Dict[str, Any] = {}

        # 1. Estimate whale activity from volume patterns
        var whale_activity = self._estimate_whale_activity(market_data)
        analysis["activity_level"] = whale_activity

        # 2. Estimate number of active whales
        var whale_count = self._estimate_whale_count(market_data)
        analysis["whale_count"] = whale_count

        # 3. Analyze transaction size distribution
        var transaction_patterns = self._analyze_transaction_patterns(market_data)
        analysis["transaction_patterns"] = transaction_patterns

        # 4. Calculate confidence based on data quality
        var confidence = self._calculate_transaction_confidence(market_data)
        analysis["confidence"] = confidence

        return analysis

    fn _estimate_whale_activity(self, market_data: MarketData) -> Float:
        """
        Estimate whale activity level from market data
        """
        # High volume + low holder count = likely whale activity
        var volume_score = min(market_data.volume_24h / 100000.0, 1.0)  # $100k = max
        var holder_concentration = 1.0 - (market_data.holder_count / self.config.whale.max_holder_reference)  # Configurable holder concentration

        return min((volume_score + holder_concentration * 0.5) / 1.5, 1.0)

    fn _estimate_whale_count(self, market_data: MarketData) -> Int:
        """
        Estimate number of active whales
        """
        # Use transaction count and volume as proxies
        var transaction_density = market_data.transaction_count
        var volume_level = market_data.volume_24h / 10000.0  # $10k increments

        # Rough estimate: high volume + many transactions = many whales
        return int(min((transaction_density / 10) + (volume_level / 5), 50))

    fn _analyze_transaction_patterns(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Analyze transaction size and timing patterns
        """
        var patterns: Dict[str, Any] = {}

        # Large transaction indicator (price volatility + volume)
        var large_transaction_indicator = abs(market_data.price_change_5m) * market_data.volume_24h / 10000.0
        patterns["large_transactions"] = large_transaction_indicator > 1.0

        # Transaction timing (regular vs clustered)
        var transaction_regularity = market_data.transaction_count / 24.0  # Transactions per hour
        patterns["regularity"] = min(transaction_regularity / 100.0, 1.0)

        # Transaction size consistency
        patterns["consistency"] = 0.7  # Placeholder - would need historical data

        return patterns

    fn _calculate_transaction_confidence(self, market_data: MarketData) -> Float:
        """
        Calculate confidence in transaction analysis
        """
        var confidence = 0.5  # Base confidence

        # Higher volume = higher confidence
        if market_data.volume_24h > MIN_VOLUME_USD:
            confidence += 0.2

        # More transactions = higher confidence
        if market_data.transaction_count > 20:
            confidence += 0.2

        # Good liquidity = higher confidence
        if market_data.liquidity_usd > MIN_LIQUIDITY_USD:
            confidence += 0.1

        return min(confidence, 0.9)

# =============================================================================
# Whale Behavior Detector
# =============================================================================

@value
struct WhaleBehaviorDetector:
    """
    Detects specific whale behavior patterns
    """
    fn detect_behavior(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Detect whale behavior patterns
        """
        var detection: Dict[str, Any] = {}

        # 1. Detect accumulation behavior
        var accumulation_signals = self._detect_accumulation_signals(market_data)
        detection["accumulation_signals"] = accumulation_signals

        # 2. Detect distribution behavior
        var distribution_signals = self._detect_distribution_signals(market_data)
        detection["distribution_signals"] = distribution_signals

        # 3. Detect churning (wash trading)
        var churning_signals = self._detect_churning_signals(market_data)
        detection["churning_signals"] = churning_signals

        # 4. Overall behavior confidence
        var confidence = self._calculate_behavior_confidence(market_data)
        detection["confidence"] = confidence

        return detection

    fn _detect_accumulation_signals(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Detect signals of whale accumulation
        """
        var signals: Dict[str, Any] = {}

        # Price support on high volume
        var support_signal = (
            market_data.price_change_1h > -0.02 and
            market_data.price_change_5m > 0.0 and
            market_data.volume_24h > MIN_VOLUME_USD * 2
        )
        signals["price_support"] = support_signal

        # Increasing holder count
        signals["holder_growth"] = market_data.holder_count > 20

        # Liquidity growth
        signals["liquidity_growth"] = market_data.liquidity_usd > MIN_LIQUIDITY_USD * 1.5

        # Calculate accumulation strength
        var strength = 0.0
        if support_signal:
            strength += 0.4
        if signals["holder_growth"]:
            strength += 0.3
        if signals["liquidity_growth"]:
            strength += 0.3

        signals["strength"] = strength

        return signals

    fn _detect_distribution_signals(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Detect signals of whale distribution
        """
        var signals: Dict[str, Any] = {}

        # Price pressure on high volume
        var pressure_signal = (
            market_data.price_change_1h < -0.02 and
            market_data.volume_24h > MIN_VOLUME_USD * 2
        )
        signals["price_pressure"] = pressure_signal

        # High volatility
        signals["high_volatility"] = abs(market_data.price_change_5m) > 0.05

        # Decreasing liquidity ratio
        signals["liquidity_decline"] = market_data.liquidity_usd < MIN_LIQUIDITY_USD

        # Calculate distribution strength
        var strength = 0.0
        if pressure_signal:
            strength += 0.5
        if signals["high_volatility"]:
            strength += 0.3
        if signals["liquidity_decline"]:
            strength += 0.2

        signals["strength"] = strength

        return signals

    fn _detect_churning_signals(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Detect wash trading/churning signals
        """
        var signals: Dict[str, Any] = {}

        # High volume with minimal price movement
        var churning_signal = (
            market_data.volume_24h > MIN_VOLUME_USD * 3 and
            abs(market_data.price_change_1h) < 0.02
        )
        signals["volume_price_divergence"] = churning_signal

        # Low holder count with high volume
        signals["concentrated_volume"] = (
            market_data.holder_count < 15 and
            market_data.volume_24h > MIN_VOLUME_USD * 2
        )

        # Calculate churning strength
        var strength = 0.0
        if churning_signal:
            strength += 0.6
        if signals["concentrated_volume"]:
            strength += 0.4

        signals["strength"] = strength

        return signals

    fn _calculate_behavior_confidence(self, market_data: MarketData) -> Float:
        """
        Calculate confidence in behavior detection
        """
        var confidence = 0.5

        # Higher volume = higher confidence
        if market_data.volume_24h > MIN_VOLUME_USD * 2:
            confidence += 0.3

        # More transaction data = higher confidence
        if market_data.transaction_count > 30:
            confidence += 0.2

        return min(confidence, 0.9)

# =============================================================================
# Whale Manipulation Detector
# =============================================================================

@value
struct WhaleManipulationDetector:
    """
    Detects whale manipulation patterns
    """
    fn detect_manipulation(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Detect whale manipulation
        """
        var detection: Dict[str, Any] = {}

        # 1. Pump and dump detection
        var pump_dump_risk = self._detect_pump_dump_risk(market_data)
        detection["pump_dump_risk"] = pump_dump_risk

        # 2. Wash trading detection
        var wash_trading_risk = self._detect_wash_trading_risk(market_data)
        detection["wash_trading_risk"] = wash_trading_risk

        # 3. Liquidity manipulation
        var liquidity_manipulation = self._detect_liquidity_manipulation(market_data)
        detection["liquidity_manipulation"] = liquidity_manipulation

        # 4. Overall manipulation risk score
        var risk_score = (pump_dump_risk + wash_trading_risk + liquidity_manipulation) / 3.0
        detection["risk_score"] = risk_score

        # 5. Confidence in manipulation detection
        detection["confidence"] = 0.8  # High confidence in algorithmic detection

        return detection

    fn _detect_pump_dump_risk(self, market_data: MarketData) -> Float:
        """
        Detect pump and dump manipulation risk
        """
        var risk = 0.0

        # Extreme price spikes
        if market_data.price_change_5m > 0.15:
            risk += 0.4

        # High volume with few holders
        if market_data.volume_24h > MIN_VOLUME_USD * 3 and market_data.holder_count < 10:
            risk += 0.3

        # Low liquidity relative to volume
        if market_data.liquidity_usd < market_data.volume_24h * 0.3:
            risk += 0.3

        return min(risk, 1.0)

    fn _detect_wash_trading_risk(self, market_data: MarketData) -> Float:
        """
        Detect wash trading risk
        """
        var risk = 0.0

        # High volume with minimal price movement
        if market_data.volume_24h > MIN_VOLUME_USD * 5 and abs(market_data.price_change_1h) < 0.01:
            risk += 0.5

        # Very concentrated holder base
        if market_data.holder_count < 5:
            risk += 0.3

        # High transaction frequency
        if market_data.transaction_count > 200:
            risk += 0.2

        return min(risk, 1.0)

    fn _detect_liquidity_manipulation(self, market_data: MarketData) -> Float:
        """
        Detect liquidity manipulation
        """
        var risk = 0.0

        # Sudden liquidity changes would need historical data
        # Use low liquidity as proxy for potential manipulation
        if market_data.liquidity_usd < MIN_LIQUIDITY_USD * 0.5:
            risk += 0.4

        # High volume with low liquidity
        if market_data.volume_24h > market_data.liquidity_usd * 10:
            risk += 0.3

        # Price volatility with low liquidity
        if abs(market_data.price_change_5m) > 0.05 and market_data.liquidity_usd < MIN_LIQUIDITY_USD:
            risk += 0.3

        return min(risk, 1.0)

# =============================================================================
# Whale Accumulation Tracker
# =============================================================================

@value
struct WhaleAccumulationTracker:
    """
    Tracks whale accumulation and distribution
    """
    fn track_accumulation(self, market_data: MarketData) -> Dict[str, Any]:
        """
        Track whale accumulation/distribution patterns
        """
        var tracking: Dict[str, Any] = {}

        # 1. Accumulation score
        var accumulation_score = self._calculate_accumulation_score(market_data)
        tracking["accumulation_score"] = accumulation_score

        # 2. Distribution score
        var distribution_score = self._calculate_distribution_score(market_data)
        tracking["distribution_score"] = distribution_score

        # 3. Net flow
        var net_flow = accumulation_score - distribution_score
        tracking["net_flow"] = net_flow

        # 4. Flow trend
        var flow_trend = "NEUTRAL"
        if net_flow > 0.3:
            flow_trend = "ACCUMULATING"
        elif net_flow < -0.3:
            flow_trend = "DISTRIBUTING"
        tracking["flow_trend"] = flow_trend

        return tracking

    fn _calculate_accumulation_score(self, market_data: MarketData) -> Float:
        """
        Calculate whale accumulation score
        """
        var score = 0.0

        # Price support on volume
        if market_data.price_change_1h > -0.01 and market_data.volume_24h > MIN_VOLUME_USD:
            score += 0.3

        # Holder growth
        if market_data.holder_count > 15:
            score += 0.3

        # Liquidity building
        if market_data.liquidity_usd > MIN_LIQUIDITY_USD * 1.2:
            score += 0.2

        # Stable price with volume
        if abs(market_data.price_change_5m) < 0.02 and market_data.transaction_count > 20:
            score += 0.2

        return min(score, 1.0)

    fn _calculate_distribution_score(self, market_data: MarketData) -> Float:
        """
        Calculate whale distribution score
        """
        var score = 0.0

        # Price pressure with volume
        if market_data.price_change_1h < -0.02 and market_data.volume_24h > MIN_VOLUME_USD:
            score += 0.4

        # High volatility
        if abs(market_data.price_change_5m) > 0.05:
            score += 0.3

        # Liquidity decline
        if market_data.liquidity_usd < MIN_LIQUIDITY_USD:
            score += 0.3

        return min(score, 1.0)