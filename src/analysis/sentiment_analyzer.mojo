# =============================================================================
# Algorithmic Sentiment Analyzer - No External AI Required
# =============================================================================

import core.types
import core.constants
from time import time
from collections import Dict, List
from math import min, max, clamp

# =============================================================================
# Sentiment Analyzer
# =============================================================================

@value
struct SentimentAnalyzer:
    """
    Algorithmic sentiment analysis using market data and patterns
    NO EXTERNAL AI API REQUIRED!
    """
    var social_calculator: SocialMetricsCalculator
    var volume_analyzer: VolumePatternAnalyzer
    var price_momentum_analyzer: PriceMomentumAnalyzer
    var liquidity_analyzer: LiquiditySentimentAnalyzer

    fn __init__():
        self.social_calculator = SocialMetricsCalculator()
        self.volume_analyzer = VolumePatternAnalyzer()
        self.price_momentum_analyzer = PriceMomentumAnalyzer()
        self.liquidity_analyzer = LiquiditySentimentAnalyzer()

    fn analyze_sentiment(self, symbol: String, market_data: MarketData) -> SentimentAnalysis:
        """
        Analyze market sentiment using pure algorithmic methods
        """
        var start_time = time()

        # 1. Social Metrics Analysis (from DexScreener data)
        var social_score = self.social_calculator.calculate(symbol, market_data)

        # 2. Volume Pattern Analysis
        var volume_sentiment = self.volume_analyzer.analyze_patterns(market_data)

        # 3. Price Momentum Analysis
        var price_sentiment = self.price_momentum_analyzer.analyze_momentum(market_data)

        # 4. Liquidity Analysis
        var liquidity_sentiment = self.liquidity_analyzer.analyze_liquidity_sentiment(market_data)

        # 5. Aggregate all components with weights
        var final_sentiment = (
            social_score * 0.30 +      # 30% weight to social metrics
            volume_sentiment * 0.30 +  # 30% weight to volume patterns
            price_sentiment * 0.25 +   # 25% weight to price momentum
            liquidity_sentiment * 0.15 # 15% weight to liquidity
        )

        # Clamp to valid range [-1.0, 1.0]
        final_sentiment = clamp(final_sentiment, -1.0, 1.0)

        # Determine recommendation
        var recommendation = TradingAction.HOLD
        if final_sentiment > 0.3:
            recommendation = TradingAction.BUY
        elif final_sentiment < -0.3:
            recommendation = TradingAction.SELL

        # Calculate confidence based on data quality
        var confidence = self._calculate_confidence(market_data)

        # Generate key factors
        var key_factors = self._generate_key_factors(
            social_score, volume_sentiment, price_sentiment, liquidity_sentiment
        )

        processing_time = time() - start_time

        return SentimentAnalysis(
            sentiment_score=final_sentiment,
            confidence=confidence,
            key_factors=key_factors,
            recommendation=recommendation,
            social_volume=market_data.social_metrics.social_volume,
            social_sentiment=market_data.social_metrics.social_sentiment
        )

    fn _calculate_confidence(self, market_data: MarketData) -> Float:
        """
        Calculate confidence in sentiment analysis based on data quality
        """
        var confidence = 0.5  # Base confidence

        # Volume quality
        if market_data.volume_24h > MIN_VOLUME_USD:
            confidence += 0.15

        # Liquidity quality
        if market_data.liquidity_usd > MIN_LIQUIDITY_USD:
            confidence += 0.15

        # Data freshness (recent transactions)
        if market_data.transaction_count > 10:
            confidence += 0.1

        # Price stability (not extremely volatile)
        if abs(market_data.price_change_5m) < 0.1:  # Less than 10% change in 5m
            confidence += 0.1

        return min(confidence, 0.95)  # Cap at 95%

    fn _generate_key_factors(
        self,
        social_score: Float,
        volume_sentiment: Float,
        price_sentiment: Float,
        liquidity_sentiment: Float
    ) -> List[String]:
        """
        Generate key factors explaining the sentiment
        """
        var factors: List[String] = []

        if social_score > 0.5:
            factors.append("Strong social metrics")
        elif social_score < -0.5:
            factors.append("Weak social metrics")

        if volume_sentiment > 0.5:
            factors.append("High volume growth")
        elif volume_sentiment < -0.5:
            factors.append("Volume decline")

        if price_sentiment > 0.5:
            factors.append("Positive price momentum")
        elif price_sentiment < -0.5:
            factors.append("Negative price momentum")

        if liquidity_sentiment > 0.5:
            factors.append("Growing liquidity")
        elif liquidity_sentiment < -0.5:
            factors.append("Liquidity concerns")

        if not factors:
            factors.append("Neutral market conditions")

        return factors

# =============================================================================
# Social Metrics Calculator
# =============================================================================

@value
struct SocialMetricsCalculator:
    """
    Calculates social sentiment from market data (no external APIs needed)
    """
    fn calculate(self, symbol: String, market_data: MarketData) -> Float:
        """
        Calculate social sentiment score from available market data
        """
        var score = 0.0

        # 1. Price change velocity (social enthusiasm indicator)
        var velocity_score = self._calculate_velocity_score(market_data.price_change_5m)
        score += velocity_score * 0.4

        # 2. Volume spike intensity (community engagement)
        var volume_score = self._calculate_volume_intensity_score(market_data)
        score += volume_score * 0.3

        # 3. Liquidity growth (trust building)
        var liquidity_score = self._calculate_liquidity_growth_score(market_data)
        score += liquidity_score * 0.2

        # 4. Transaction frequency (activity level)
        var transaction_score = self._calculate_transaction_activity_score(market_data)
        score += transaction_score * 0.1

        return clamp(score, -1.0, 1.0)

    fn _calculate_velocity_score(self, price_change_5m: Float) -> Float:
        """
        Calculate price change velocity score
        """
        # Normalize 5-minute price change to [-1, 1] range
        # 10% change = maximum score
        var normalized_change = price_change_5m / 0.10
        return clamp(normalized_change, -1.0, 1.0)

    fn _calculate_volume_intensity_score(self, market_data: MarketData) -> Float:
        """
        Calculate volume intensity score based on volume changes
        """
        # Use transaction count as volume proxy
        var transaction_density = market_data.transaction_count / 100.0  # Normalize
        return clamp(transaction_density, -1.0, 1.0)

    fn _calculate_liquidity_growth_score(self, market_data: MarketData) -> Float:
        """
        Calculate liquidity growth sentiment
        """
        # Higher liquidity indicates more trust
        var liquidity_score = min(market_data.liquidity_usd / 100000.0, 1.0)  # $100k = max score
        return liquidity_score

    fn _calculate_transaction_activity_score(self, market_data: MarketData) -> Float:
        """
        Calculate transaction activity score
        """
        # More transactions = higher social activity
        var activity_score = min(market_data.transaction_count / 50.0, 1.0)  # 50 transactions = max score
        return activity_score

# =============================================================================
# Volume Pattern Analyzer
# =============================================================================

@value
struct VolumePatternAnalyzer:
    """
    Analyzes volume patterns for sentiment indicators
    """
    fn analyze_patterns(self, market_data: MarketData) -> Float:
        """
        Analyze volume patterns for sentiment
        """
        var sentiment = 0.0

        # 1. Volume growth pattern
        var volume_growth = self._detect_volume_growth(market_data)
        sentiment += volume_growth * 0.4

        # 2. Volume consistency
        var volume_consistency = self._detect_volume_consistency(market_data)
        sentiment += volume_consistency * 0.3

        # 3. Volume-to-price correlation
        var volume_price_correlation = self._detect_volume_price_correlation(market_data)
        sentiment += volume_price_correlation * 0.3

        return clamp(sentiment, -1.0, 1.0)

    fn _detect_volume_growth(self, market_data: MarketData) -> Float:
        """
        Detect volume growth patterns
        """
        # Use price change as proxy for volume activity
        # Higher price changes often correlate with higher volume
        var price_activity = abs(market_data.price_change_5m) + abs(market_data.price_change_1h)
        return min(price_activity / 0.15, 1.0)  # 15% total change = max score

    fn _detect_volume_consistency(self, market_data: MarketData) -> Float:
        """
        Detect volume consistency (steady volume is positive)
        """
        # High transaction count indicates consistent activity
        var consistency = min(market_data.transaction_count / 100.0, 1.0)
        return consistency

    fn _detect_volume_price_correlation(self, market_data: MarketData) -> Float:
        """
        Detect positive correlation between volume and price movement
        """
        # Positive price change with high volume is bullish
        if market_data.price_change_5m > 0 and market_data.transaction_count > 20:
            return 0.8
        # Negative price change with high volume is bearish
        elif market_data.price_change_5m < 0 and market_data.transaction_count > 20:
            return -0.8
        else:
            return 0.0

# =============================================================================
# Price Momentum Analyzer
# =============================================================================

@value
struct PriceMomentumAnalyzer:
    """
    Analyzes price momentum for sentiment
    """
    fn analyze_momentum(self, market_data: MarketData) -> Float:
        """
        Analyze price momentum across multiple timeframes
        """
        var momentum = 0.0

        # 1. Short-term momentum (5m)
        var short_momentum = market_data.price_change_5m / 0.05  # Normalize 5% = max
        momentum += short_momentum * 0.4

        # 2. Medium-term momentum (1h)
        var medium_momentum = market_data.price_change_1h / 0.10  # Normalize 10% = max
        momentum += medium_momentum * 0.35

        # 3. Long-term momentum (24h)
        var long_momentum = market_data.price_change_24h / 0.20  # Normalize 20% = max
        momentum += long_momentum * 0.25

        return clamp(momentum, -1.0, 1.0)

# =============================================================================
# Liquidity Sentiment Analyzer
# =============================================================================

@value
struct LiquiditySentimentAnalyzer:
    """
    Analyzes liquidity patterns for sentiment
    """
    fn analyze_liquidity_sentiment(self, market_data: MarketData) -> Float:
        """
        Analyze liquidity as a sentiment indicator
        """
        var sentiment = 0.0

        # 1. Absolute liquidity level
        var liquidity_level = min(market_data.liquidity_usd / 50000.0, 1.0)  # $50k = max score
        sentiment += liquidity_level * 0.5

        # 2. Liquidity stability (high volume + good liquidity)
        var liquidity_stability = 0.0
        if market_data.liquidity_usd > MIN_LIQUIDITY_USD and market_data.volume_24h > MIN_VOLUME_USD:
            liquidity_stability = 1.0
        sentiment += liquidity_stability * 0.3

        # 3. Liquidity growth potential (age-based)
        var growth_potential = self._calculate_growth_potential(market_data.age_hours)
        sentiment += growth_potential * 0.2

        return clamp(sentiment, -1.0, 1.0)

    fn _calculate_growth_potential(self, age_hours: Float) -> Float:
        """
        Calculate liquidity growth potential based on token age
        """
        # New tokens have higher growth potential
        if age_hours < 1.0:      # < 1 hour
            return 1.0
        elif age_hours < 24.0:   # < 1 day
            return 0.8
        elif age_hours < 168.0:  # < 7 days
            return 0.5
        else:                     # > 7 days
            return 0.2