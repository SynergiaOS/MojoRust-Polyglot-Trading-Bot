# =============================================================================
# Advanced Volume Analysis Engine - Algorithmic Intelligence
# =============================================================================

from time import time
from collections import Dict, List, Any
from math import min, max, clamp, sqrt
from core.types import MarketData, Config
from core.constants import MIN_VOLUME_USD, MIN_LIQUIDITY_USD

# =============================================================================
# Volume Analysis Types
# =============================================================================

@value
struct VolumeSpike:
    """
    Represents a detected volume spike
    """
    var timestamp: Float
    var volume: Float
    var expected_volume: Float
    var spike_ratio: Float
    var price_change: Float
    var significance: Float  # 0.0 to 1.0

    fn __init__(
        timestamp: Float = time(),
        volume: Float = 0.0,
        expected_volume: Float = 0.0,
        spike_ratio: Float = 1.0,
        price_change: Float = 0.0,
        significance: Float = 0.0
    ):
        self.timestamp = timestamp
        self.volume = volume
        self.expected_volume = expected_volume
        self.spike_ratio = max(1.0, spike_ratio)
        self.price_change = price_change
        self.significance = max(0.0, min(1.0, significance))

@value
struct VolumePattern:
    """
    Represents a detected volume pattern
    """
    var pattern_type: String
    var confidence: Float
    var direction: String  # BULLISH, BEARISH, NEUTRAL
    var strength: Float
    var duration_hours: Float
    var metadata: Dict[String, Any]

    fn __init__(
        pattern_type: String = "",
        confidence: Float = 0.0,
        direction: String = "NEUTRAL",
        strength: Float = 0.0,
        duration_hours: Float = 0.0,
        metadata: Dict[String, Any] = {}
    ):
        self.pattern_type = pattern_type
        self.confidence = max(0.0, min(1.0, confidence))
        self.direction = direction
        self.strength = max(0.0, min(1.0, strength))
        self.duration_hours = max(0.0, duration_hours)
        self.metadata = metadata

@value
struct VolumeAnomaly:
    """
    Represents a detected volume anomaly
    """
    var anomaly_type: String
    var severity: Float  # 0.0 to 1.0
    var description: String
    var timestamp: Float
    var confidence: Float

    fn __init__(
        anomaly_type: String = "",
        severity: Float = 0.0,
        description: String = "",
        timestamp: Float = time(),
        confidence: Float = 0.0
    ):
        self.anomaly_type = anomaly_type
        self.severity = max(0.0, min(1.0, severity))
        self.description = description
        self.timestamp = timestamp
        self.confidence = max(0.0, min(1.0, confidence))

@value
struct VolumeAnalysis:
    """
    Complete volume analysis result
    """
    var volume_spikes: List[VolumeSpike]
    var volume_patterns: List[VolumePattern]
    var anomalies: List[VolumeAnomaly]
    var quality_score: Float  # 0.0 to 1.0
    var is_organic: Bool
    var trend_direction: String
    var volatility_score: Float
    var momentum_score: Float
    var timestamp: Float

    fn __init__(
        volume_spikes: List[VolumeSpike] = [],
        volume_patterns: List[VolumePattern] = [],
        anomalies: List[VolumeAnomaly] = [],
        quality_score: Float = 0.5,
        is_organic: Bool = True,
        trend_direction: String = "NEUTRAL",
        volatility_score: Float = 0.0,
        momentum_score: Float = 0.0,
        timestamp: Float = time()
    ):
        self.volume_spikes = volume_spikes
        self.volume_patterns = volume_patterns
        self.anomalies = anomalies
        self.quality_score = max(0.0, min(1.0, quality_score))
        self.is_organic = is_organic
        self.trend_direction = trend_direction
        self.volatility_score = max(0.0, min(1.0, volatility_score))
        self.momentum_score = max(0.0, min(1.0, momentum_score))
        self.timestamp = timestamp

# =============================================================================
# Volume Analysis Engine
# =============================================================================

@value
struct VolumeAnalyzer:
    """
    Advanced volume analysis engine for algorithmic trading
    """
    var spike_detector: VolumeSpikeDetector
    var pattern_analyzer: VolumePatternAnalyzer
    var anomaly_detector: VolumeAnomalyDetector
    var quality_assessor: VolumeQualityAssessor
    var config: Config

    fn __init__(config: Config):
        self.config = config
        self.spike_detector = VolumeSpikeDetector(config)
        self.pattern_analyzer = VolumePatternAnalyzer(config)
        self.anomaly_detector = VolumeAnomalyDetector(config)
        self.quality_assessor = VolumeQualityAssessor(config)

    fn analyze(self, market_data: MarketData) -> VolumeAnalysis:
        """
        Perform comprehensive volume analysis
        """
        var start_time = time()

        # 1. Detect volume spikes
        var volume_spikes = self.spike_detector.detect_spikes(market_data)

        # 2. Analyze volume patterns
        var volume_patterns = self.pattern_analyzer.analyze_patterns(market_data)

        # 3. Detect anomalies
        var anomalies = self.anomaly_detector.detect_anomalies(market_data)

        # 4. Assess volume quality
        var quality_score = self.quality_assessor.assess_quality(
            market_data, volume_spikes, volume_patterns, anomalies
        )

        # 5. Determine if volume is organic
        var is_organic = self.quality_assessor.is_organic_volume(
            market_data, volume_spikes, anomalies
        )

        # 6. Calculate trend and momentum
        var trend_direction = self._determine_volume_trend(market_data)
        var volatility_score = self._calculate_volume_volatility(market_data)
        var momentum_score = self._calculate_volume_momentum(market_data)

        return VolumeAnalysis(
            volume_spikes=volume_spikes,
            volume_patterns=volume_patterns,
            anomalies=anomalies,
            quality_score=quality_score,
            is_organic=is_organic,
            trend_direction=trend_direction,
            volatility_score=volatility_score,
            momentum_score=momentum_score,
            timestamp=start_time
        )

    fn _determine_volume_trend(self, market_data: MarketData) -> String:
        """
        Determine volume trend direction
        """
        # Use price changes as proxy for volume trend
        if market_data.price_change_5m > self.config.volume.trend_threshold:
            return "BULLISH"
        elif market_data.price_change_5m < -self.config.volume.trend_threshold:
            return "BEARISH"
        else:
            return "NEUTRAL"

    fn _calculate_volume_volatility(self, market_data: MarketData) -> Float:
        """
        Calculate volume volatility score
        """
        # Use transaction count variability as proxy
        transaction_density = market_data.transaction_count / self.config.volume.hours_per_day  # Per hour
        price_volatility = abs(market_data.price_change_5m)

        # Combine transaction density with price volatility
        volatility_score = min((transaction_density / self.config.volume.volatility_tx_threshold + price_volatility / self.config.volume.volatility_price_threshold) / 2.0, 1.0)
        return volatility_score

    fn _calculate_volume_momentum(self, market_data: MarketData) -> Float:
        """
        Calculate volume momentum score
        """
        # Combine volume and price momentum
        volume_momentum = market_data.volume_24h / MIN_VOLUME_USD
        price_momentum = abs(market_data.price_change_1h)

        momentum_score = min((volume_momentum / self.config.volume.momentum_volume_multiplier + price_momentum / self.config.volume.momentum_price_threshold) / 2.0, 1.0)
        return momentum_score

# =============================================================================
# Volume Spike Detector
# =============================================================================

@value
struct VolumeSpikeDetector:
    """
    Detects abnormal volume spikes
    """
    var config: Config

    fn __init__(config: Config):
        self.config = config

    fn detect_spikes(self, market_data: MarketData) -> List[VolumeSpike]:
        """
        Detect volume spikes in market data
        """
        var spikes: List[VolumeSpike] = []

        # Calculate expected volume based on market cap and liquidity
        var expected_volume = self._calculate_expected_volume(market_data)
        var current_volume = market_data.volume_24h

        if current_volume > expected_volume * self.config.volume.spike_multiplier:  # Configurable spike multiplier
            var spike_ratio = current_volume / expected_volume
            var significance = min(spike_ratio / self.config.volume.significance_divisor, 1.0)  # Normalize significance

            spikes.append(VolumeSpike(
                timestamp=time(),
                volume=current_volume,
                expected_volume=expected_volume,
                spike_ratio=spike_ratio,
                price_change=market_data.price_change_24h,
                significance=significance
            ))

        # Check for 5-minute volume spikes (using transaction count as proxy)
        if market_data.transaction_count > self.config.volume.high_tx_threshold:  # Configurable high transaction count
            spikes.append(VolumeSpike(
                timestamp=time(),
                volume=market_data.volume_5m,
                expected_volume=market_data.volume_5m / self.config.volume.normal_tx_multiplier,  # Configurable normal multiplier
                spike_ratio=self.config.volume.normal_tx_multiplier,
                price_change=market_data.price_change_5m,
                significance=self.config.volume.tx_spike_significance
            ))

        return spikes

    fn _calculate_expected_volume(self, market_data: MarketData) -> Float:
        """
        Calculate expected volume based on market characteristics
        """
        # Base expected volume on market cap
        var base_volume = market_data.market_cap * self.config.volume.market_cap_percentage  # Configurable % of market cap daily

        # Adjust for liquidity
        if market_data.liquidity_usd > 0:
            var liquidity_multiplier = min(market_data.liquidity_usd / self.config.volume.liquidity_reference, self.config.volume.max_liquidity_multiplier)
            base_volume *= liquidity_multiplier

        # Adjust for holder count
        if market_data.holder_count > 0:
            var holder_multiplier = min(market_data.holder_count / self.config.volume.holder_reference, self.config.volume.max_holder_multiplier)
            base_volume *= holder_multiplier

        return max(base_volume, MIN_VOLUME_USD)

# =============================================================================
# Volume Pattern Analyzer
# =============================================================================

@value
struct VolumePatternAnalyzer:
    """
    Analyzes volume patterns for trading insights
    """
    var config: Config

    fn __init__(config: Config):
        self.config = config

    fn analyze_patterns(self, market_data: MarketData) -> List[VolumePattern]:
        """
        Analyze volume patterns in market data
        """
        var patterns: List[VolumePattern] = []

        # 1. Accumulation Pattern
        if self._detect_accumulation_pattern(market_data):
            patterns.append(VolumePattern(
                pattern_type="ACCUMULATION",
                confidence=0.8,
                direction="BULLISH",
                strength=0.7,
                duration_hours=2.0,
                metadata={"volume_stability": "high"}
            ))

        # 2. Distribution Pattern
        if self._detect_distribution_pattern(market_data):
            patterns.append(VolumePattern(
                pattern_type="DISTRIBUTION",
                confidence=0.8,
                direction="BEARISH",
                strength=0.7,
                duration_hours=1.5,
                metadata={"volume_pressure": "high"}
            ))

        # 3. Breakout Pattern
        if self._detect_breakout_pattern(market_data):
            patterns.append(VolumePattern(
                pattern_type="BREAKOUT",
                confidence=0.75,
                direction=self._determine_breakout_direction(market_data),
                strength=0.8,
                duration_hours=0.5,
                metadata={"breakout_strength": "strong"}
            ))

        # 4. Churning Pattern (wash trading indicator)
        if self._detect_churning_pattern(market_data):
            patterns.append(VolumePattern(
                pattern_type="CHURNING",
                confidence=0.9,
                direction="NEUTRAL",
                strength=0.6,
                duration_hours=4.0,
                metadata={"manipulation_risk": "high"}
            ))

        return patterns

    fn _detect_accumulation_pattern(self, market_data: MarketData) -> Bool:
        """
        Detect volume accumulation pattern
        """
        return (
            market_data.volume_24h > MIN_VOLUME_USD * 2 and
            market_data.price_change_1h > -0.02 and
            market_data.price_change_5m > 0.0 and
            market_data.liquidity_usd > MIN_LIQUIDITY_USD
        )

    fn _detect_distribution_pattern(self, market_data: MarketData) -> Bool:
        """
        Detect volume distribution pattern
        """
        return (
            market_data.volume_24h > MIN_VOLUME_USD * 2 and
            market_data.price_change_1h < -0.02 and
            abs(market_data.price_change_5m) > 0.03
        )

    fn _detect_breakout_pattern(self, market_data: MarketData) -> Bool:
        """
        Detect volume breakout pattern
        """
        return (
            market_data.transaction_count > 50 and
            abs(market_data.price_change_5m) > 0.04 and
            market_data.volume_24h > MIN_VOLUME_USD * 3
        )

    fn _determine_breakout_direction(self, market_data: MarketData) -> String:
        """
        Determine breakout direction
        """
        return "BULLISH" if market_data.price_change_5m > 0 else "BEARISH"

    fn _detect_churning_pattern(self, market_data: MarketData) -> Bool:
        """
        Detect churning (high volume with minimal price movement)
        """
        return (
            market_data.volume_24h > MIN_VOLUME_USD * 5 and
            abs(market_data.price_change_1h) < 0.01 and
            market_data.holder_count < 15
        )

# =============================================================================
# Volume Anomaly Detector
# =============================================================================

@value
struct VolumeAnomalyDetector:
    """
    Detects volume anomalies and irregularities
    """
    fn detect_anomalies(self, market_data: MarketData) -> List[VolumeAnomaly]:
        """
        Detect volume anomalies
        """
        var anomalies: List[VolumeAnomaly] = []

        # 1. Suspicious High Volume
        if self._detect_suspicious_high_volume(market_data):
            anomalies.append(VolumeAnomaly(
                anomaly_type="SUSPICIOUS_HIGH_VOLUME",
                severity=0.8,
                description="Extremely high volume relative to market characteristics",
                confidence=0.9
            ))

        # 2. Volume Dry-up
        if self._detect_volume_dry_up(market_data):
            anomalies.append(VolumeAnomaly(
                anomaly_type="VOLUME_DRY_UP",
                severity=0.6,
                description="Unusually low volume activity",
                confidence=0.8
            ))

        # 3. Volume-Price Divergence
        if self._detect_volume_price_divergence(market_data):
            anomalies.append(VolumeAnomaly(
                anomaly_type="VOLUME_PRICE_DIVERGENCE",
                severity=0.7,
                description="Volume and price movement are not correlated",
                confidence=0.85
            ))

        # 4. Wash Trading Indicator
        if self._detect_wash_trading_indicator(market_data):
            anomalies.append(VolumeAnomaly(
                anomaly_type="WASH_TRADING_INDICATOR",
                severity=0.9,
                description="Potential wash trading activity detected",
                confidence=0.95
            ))

        return anomalies

    fn _detect_suspicious_high_volume(self, market_data: MarketData) -> Bool:
        """
        Detect suspiciously high volume
        """
        return (
            market_data.volume_24h > market_data.market_cap * 0.5 and
            market_data.holder_count < 20
        )

    fn _detect_volume_dry_up(self, market_data: MarketData) -> Bool:
        """
        Detect unusually low volume
        """
        return (
            market_data.volume_24h < MIN_VOLUME_USD * 0.1 and
            market_data.liquidity_usd > MIN_LIQUIDITY_USD
        )

    fn _detect_volume_price_divergence(self, market_data: MarketData) -> Bool:
        """
        Detect volume-price divergence
        """
        high_volume = market_data.volume_24h > MIN_VOLUME_USD * 3
        low_price_movement = abs(market_data.price_change_1h) < 0.005
        return high_volume and low_price_movement

    fn _detect_wash_trading_indicator(self, market_data: MarketData) -> Bool:
        """
        Detect wash trading indicators
        """
        return (
            market_data.volume_24h > MIN_VOLUME_USD * 10 and
            abs(market_data.price_change_1h) < 0.005 and
            market_data.holder_count < 10
        )

# =============================================================================
# Volume Quality Assessor
# =============================================================================

@value
struct VolumeQualityAssessor:
    """
    Assesses the quality and legitimacy of volume data
    """
    fn assess_quality(
        self,
        market_data: MarketData,
        volume_spikes: List[VolumeSpike],
        volume_patterns: List[VolumePattern],
        anomalies: List[VolumeAnomaly]
    ) -> Float:
        """
        Assess overall volume quality (0.0 to 1.0)
        """
        var score = 1.0  # Start with perfect score

        # Penalize for volume spikes
        if len(volume_spikes) > 3:
            score -= 0.3
        elif len(volume_spikes) > 1:
            score -= 0.1

        # Penalize for anomalies
        score -= len(anomalies) * 0.2

        # Reward for healthy patterns
        healthy_patterns = [p for p in volume_patterns if p.pattern_type != "CHURNING"]
        score += len(healthy_patterns) * 0.1

        # Adjust for market data quality
        if market_data.volume_24h > MIN_VOLUME_USD:
            score += 0.1
        if market_data.liquidity_usd > MIN_LIQUIDITY_USD:
            score += 0.1

        return max(0.0, min(1.0, score))

    fn is_organic_volume(
        self,
        market_data: MarketData,
        volume_spikes: List[VolumeSpike],
        anomalies: List[VolumeAnomaly]
    ) -> Bool:
        """
        Determine if volume appears to be organic
        """
        # Check for manipulation indicators
        if len(anomalies) > 2:
            return False

        # Check for excessive volume spikes
        if len(volume_spikes) > 3:
            return False

        # Check volume-to-transaction ratio
        if market_data.transaction_count > 0:
            var avg_transaction_size = market_data.volume_24h / market_data.transaction_count
            if avg_transaction_size < 10.0:  # Very small average transactions
                return False

        # Check liquidity ratio
        if market_data.liquidity_usd > 0:
            var volume_to_liquidity = market_data.volume_24h / market_data.liquidity_usd
            if volume_to_liquidity > 20.0:  # Very high volume relative to liquidity
                return False

        return True