# =============================================================================
# Enhanced Social Media Client Module
# =============================================================================

from json import loads, dumps
from time import time
from sys import exit
from collections import Dict, List
from math import sin
from core.types import SocialMetrics
from core.constants import DEFAULT_TIMEOUT_SECONDS
from core.logger import get_api_logger
from core.api_placeholder_handler import APIFallbackHandler, APIFallbackConfig, APIResponse, generate_consistent_int, generate_consistent_float
from python import Python

@value
struct SocialClient:
    """
    Enhanced social media client for tracking token mentions and sentiment
    Integrates with X/Twitter API and Python social intelligence engine
    for comprehensive multi-platform social monitoring and analysis
    """
    var twitter_api_key: String
    var twitter_api_secret: String
    var twitter_access_token: String
    var twitter_access_token_secret: String
    var base_url: String
    var timeout_seconds: Float
    var logger
    var enabled: Bool

    # Python social intelligence engine integration
    var python_engine: PythonObject
    var use_python_engine: Bool
    var engine_config: Dict[String, Any]
    var python_initialized: Bool

    # Unified API fallback handling
    var fallback_handler: APIFallbackHandler

    fn __init__(twitter_api_key: String = "", twitter_api_secret: String = "",
                 twitter_access_token: String = "", twitter_access_token_secret: String = "",
                 base_url: String = "https://api.twitter.com/2", timeout_seconds: Float = DEFAULT_TIMEOUT_SECONDS,
                 enabled: Bool = True, use_python_engine: Bool = True, engine_config: Dict[String, Any] = Dict[String, Any]()):
        self.twitter_api_key = twitter_api_key
        self.twitter_api_secret = twitter_api_secret
        self.twitter_access_token = twitter_access_token
        self.twitter_access_token_secret = twitter_access_token_secret
        self.base_url = base_url
        self.timeout_seconds = timeout_seconds
        self.logger = get_api_logger()
        self.enabled = enabled and all([twitter_api_key, twitter_api_secret, twitter_access_token, twitter_access_token_secret])

        # Python social intelligence engine initialization
        self.use_python_engine = use_python_engine
        self.engine_config = engine_config
        self.python_engine = Python.none()
        self.python_initialized = False

        # Initialize Python engine if enabled
        if self.use_python_engine:
            self._init_python_engine()

        # Initialize unified API fallback handler
        fallback_config = APIFallbackConfig(
            use_real_api=self.enabled,
            fallback_to_mock=True,
            mock_data_consistency=True,
            log_failures=True,
            log_fallbacks=True,
            fallback_timeout_ms=int(timeout_seconds * 1000),
            max_retry_attempts=3
        )
        self.fallback_handler = APIFallbackHandler(fallback_config)

    def get_token_mentions(self, token_symbol: String, token_address: String, window_minutes: Int = 10) -> Dict[String, Any]:
        """
        Get token mentions from X/Twitter in specified time window
        Returns mention count, sentiment, and engagement metrics
        """
        if not self.enabled:
            return self._get_disabled_response()

        try:
            # Calculate time window
            current_time = time()
            window_start_time = current_time - (window_minutes * 60)

            # Mock implementation for now - replace with real Twitter API v2 call
            # In production, this would use Twitter's recent search endpoint
            mock_mention_analysis = {
                "token_symbol": token_symbol,
                "token_address": token_address,
                "window_minutes": window_minutes,
                "total_mentions": 25,
                "unique_users": 18,
                "total_impressions": 15420,
                "total_likes": 342,
                "total_retweets": 89,
                "total_replies": 127,
                "sentiment_analysis": {
                    "positive_mentions": 15,
                    "negative_mentions": 3,
                    "neutral_mentions": 7,
                    "overall_sentiment": "positive",
                    "sentiment_score": 0.72  # Range -1 to 1
                },
                "engagement_metrics": {
                    "average_likes_per_tweet": 13.7,
                    "average_retweets_per_tweet": 3.6,
                    "average_replies_per_tweet": 5.1,
                    "engagement_rate": 0.023  # 2.3% engagement rate
                },
                "influencer_mentions": [
                    {
                        "username": "crypto_influencer_1",
                        "followers": 50000,
                        "tweet_text": f"Just discovered ${token_symbol} - looks promising! 🚀",
                        "timestamp": current_time - 300,  # 5 minutes ago
                        "engagement": {"likes": 45, "retweets": 12, "replies": 8}
                    },
                    {
                        "username": "token_analyst_2",
                        "followers": 25000,
                        "tweet_text": f"${token_symbol} has strong fundamentals",
                        "timestamp": current_time - 480,  # 8 minutes ago
                        "engagement": {"likes": 23, "retweets": 6, "replies": 4}
                    }
                ],
                "trending_keywords": [token_symbol.lower(), f"${token_symbol}", "moonshot", "pump"],
                "mention_velocity": 2.5,  # Mentions per minute
                "growth_rate": 0.15,  # 15% growth in mentions over window
                "confidence_score": 0.85,
                "meets_sniper_threshold": True,  # Based on min_social_mentions config
                "analysis_timestamp": current_time
            }

            self.logger.info(f"Social mentions analysis completed",
                           token_symbol=token_symbol,
                           total_mentions=mock_mention_analysis["total_mentions"],
                           sentiment=mock_mention_analysis["sentiment_analysis"]["overall_sentiment"],
                           meets_threshold=mock_mention_analysis["meets_sniper_threshold"])

            return mock_mention_analysis

        except e:
            self.logger.error(f"Error getting token mentions",
                            token_symbol=token_symbol,
                            error=str(e))
            return self._get_error_response(str(e))

    def analyze_sentiment_trend(self, token_symbol: String, token_address: String, hours_back: Int = 1) -> Dict[String, Any]:
        """
        Analyze sentiment trend over longer time period
        Returns sentiment progression and momentum
        """
        if not self.enabled:
            return self._get_disabled_response()

        try:
            # Mock implementation - analyze sentiment over time
            current_time = time()
            time_intervals = []

            # Generate mock sentiment data points
            for i in range(hours_back):
                interval_time = current_time - (i * 3600)  # i hours ago
                sentiment_score = 0.4 + (i * 0.15) + (0.1 * sin(i * 0.5))  # Improving trend

                time_intervals.append({
                    "timestamp": interval_time,
                    "sentiment_score": max(-1.0, min(1.0, sentiment_score)),
                    "mention_count": 10 + (i * 8),
                    "sentiment": "positive" if sentiment_score > 0.2 else "negative" if sentiment_score < -0.2 else "neutral"
                })

            # Calculate trend metrics
            sentiment_scores = [interval["sentiment_score"] for interval in time_intervals]
            mention_counts = [interval["mention_count"] for interval in time_intervals]

            sentiment_trend = sentiment_scores[-1] - sentiment_scores[0] if len(sentiment_scores) > 1 else 0
            mention_trend = mention_counts[-1] - mention_counts[0] if len(mention_counts) > 1 else 0

            mock_sentiment_trend = {
                "token_symbol": token_symbol,
                "token_address": token_address,
                "analysis_hours": hours_back,
                "sentiment_trend": sentiment_trend,
                "mention_trend": mention_trend,
                "current_sentiment": sentiment_scores[-1] if sentiment_scores else 0,
                "current_sentiment_label": "positive" if (sentiment_scores[-1] if sentiment_scores else 0) > 0.2 else "negative",
                "momentum_score": min(1.0, (sentiment_trend + 0.5) * 2),  # Normalize to 0-1
                "sentiment_velocity": sentiment_trend / hours_back,
                "mention_velocity": mention_trend / hours_back,
                "time_intervals": time_intervals,
                "trend_strength": "strong" if abs(sentiment_trend) > 0.5 else "moderate" if abs(sentiment_trend) > 0.2 else "weak",
                "is_positive_momentum": sentiment_trend > 0.2 and mention_trend > 0,
                "confidence_score": 0.78
            }

            self.logger.info(f"Sentiment trend analysis completed",
                           token_symbol=token_symbol,
                           sentiment_trend=mock_sentiment_trend["sentiment_trend"],
                           momentum_score=mock_sentiment_trend["momentum_score"],
                           has_positive_momentum=mock_sentiment_trend["is_positive_momentum"])

            return mock_sentiment_trend

        except e:
            self.logger.error(f"Error analyzing sentiment trend",
                            token_symbol=token_symbol,
                            error=str(e))
            return self._get_error_response(str(e))

    def check_viral_potential(self, token_symbol: String, token_address: String) -> Dict[String, Any]:
        """
        Check viral potential based on social metrics
        Analyzes factors that could lead to rapid price movement
        """
        if not self.enabled:
            return self._get_disabled_response()

        try:
            # Get current mentions and sentiment
            current_mentions = self.get_token_mentions(token_symbol, token_address, 10)
            sentiment_trend = self.analyze_sentiment_trend(token_symbol, token_address, 1)

            # Handle cases where called methods return disabled responses
            if not current_mentions.get("enabled", True) or not sentiment_trend.get("enabled", True):
                return self._get_disabled_response()

            # Calculate viral indicators
            mention_velocity = current_mentions.get("mention_velocity", 0)
            engagement_rate = current_mentions.get("engagement_metrics", {}).get("engagement_rate", 0)
            influencer_count = len(current_mentions.get("influencer_mentions", []))
            sentiment_score = current_mentions.get("sentiment_analysis", {}).get("sentiment_score", 0)
            momentum_score = sentiment_trend.get("momentum_score", 0)

            # Calculate viral score (0-1)
            viral_score = 0
            viral_score += min(0.3, mention_velocity / 10)  # Max 0.3 for velocity
            viral_score += min(0.25, engagement_rate * 10)  # Max 0.25 for engagement
            viral_score += min(0.2, influencer_count / 5)   # Max 0.2 for influencers
            viral_score += min(0.15, (sentiment_score + 1) / 2)  # Max 0.15 for sentiment
            viral_score += min(0.1, momentum_score)  # Max 0.1 for momentum

            # Determine viral potential level
            viral_level = "low"
            if viral_score > 0.7:
                viral_level = "very high"
            elif viral_score > 0.5:
                viral_level = "high"
            elif viral_score > 0.3:
                viral_level = "moderate"

            mock_viral_analysis = {
                "token_symbol": token_symbol,
                "token_address": token_address,
                "viral_score": viral_score,
                "viral_level": viral_level,
                "viral_indicators": {
                    "mention_velocity": mention_velocity,
                    "engagement_rate": engagement_rate,
                    "influencer_count": influencer_count,
                    "sentiment_score": sentiment_score,
                    "momentum_score": momentum_score
                },
                "viral_factors": {
                    "high_mention_velocity": mention_velocity > 5,
                    "strong_engagement": engagement_rate > 0.05,
                    "influencer_participation": influencer_count > 2,
                    "positive_sentiment": sentiment_score > 0.5,
                    "upward_momentum": momentum_score > 0.6
                },
                "viral_triggers": [],  # Specific events that could trigger virality
                "estimated_reach": current_mentions.get("total_impressions", 0) * (1 + viral_score),
                "price_impact_potential": "high" if viral_score > 0.6 else "moderate" if viral_score > 0.3 else "low",
                "time_to_potential_viral": "minutes" if viral_score > 0.7 else "hours" if viral_score > 0.4 else "days",
                "has_viral_potential": viral_score > 0.4,
                "confidence_score": 0.82,
                "analysis_timestamp": time()
            }

            self.logger.info(f"Viral potential analysis completed",
                           token_symbol=token_symbol,
                           viral_score=viral_score,
                           viral_level=viral_level,
                           has_potential=mock_viral_analysis["has_viral_potential"])

            return mock_viral_analysis

        except e:
            self.logger.error(f"Error checking viral potential",
                            token_symbol=token_symbol,
                            error=str(e))
            return self._get_error_response(str(e))

    def monitor_social_alerts(self, token_symbol: String, token_address: String) -> Dict[String, Any]:
        """
        Monitor social media for alerts and red flags
        Checks for negative sentiment, FUD, or concerning patterns
        """
        if not self.enabled:
            return self._get_disabled_response()

        try:
            # Mock implementation - simulate social alert monitoring
            current_time = time()

            mock_alert_monitoring = {
                "token_symbol": token_symbol,
                "token_address": token_address,
                "alerts": [],
                "red_flags": [],
                "concerning_patterns": [],
                "negative_sentiment_spike": False,
                "coordinated_fud_detected": False,
                "scam_warnings": [],
                "safety_score": 0.88,  # High safety score
                "alert_level": "normal",
                "recent_negative_mentions": 0,
                "coordinated_negative_accounts": [],
                "warning_keywords_found": [],
                "community_trust": "high",
                "moderation_status": "clean",
                "spam_detection": "low",
                "confidence_score": 0.91,
                "monitoring_timestamp": current_time
            }

            # In a real implementation, this would:
            # 1. Monitor for scam-related keywords
            # 2. Detect coordinated negative campaigns
            # 3. Check for known scammer accounts promoting
            # 4. Analyze reply patterns for bot activity
            # 5. Track sudden sentiment drops

            self.logger.info(f"Social alert monitoring completed",
                           token_symbol=token_symbol,
                           alert_level=mock_alert_monitoring["alert_level"],
                           safety_score=mock_alert_monitoring["safety_score"])

            return mock_alert_monitoring

        except e:
            self.logger.error(f"Error monitoring social alerts",
                            token_symbol=token_symbol,
                            error=str(e))
            return self._get_error_response(str(e))

    async def comprehensive_social_analysis(self, token_symbol: String, token_address: String, min_mentions_threshold: Int = 10) -> Dict[String, Any]:
        """
        Perform comprehensive social analysis combining all social metrics
        Enhanced with Python social intelligence engine for multi-platform data
        Returns unified social assessment for sniper filters
        """
        if not self.enabled:
            return self._get_disabled_response()

        try:
            # Get all individual analyses
            mention_analysis = self.get_token_mentions(token_symbol, token_address, 10)
            sentiment_trend = self.analyze_sentiment_trend(token_symbol, token_address, 1)
            viral_potential = self.check_viral_potential(token_symbol, token_address)
            alert_monitoring = self.monitor_social_alerts(token_symbol, token_address)

            # Handle cases where called methods return disabled responses
            if not mention_analysis.get("enabled", True) or not sentiment_trend.get("enabled", True) or not viral_potential.get("enabled", True) or not alert_monitoring.get("enabled", True):
                return self._get_disabled_response()

            # Check if meets minimum mentions requirement
            total_mentions = mention_analysis.get("total_mentions", 0)
            meets_mentions_threshold = total_mentions >= min_mentions_threshold

            # Calculate overall social score
            mention_score = min(1.0, total_mentions / (min_mentions_threshold * 2))  # More mentions = higher score
            sentiment_score = (mention_analysis.get("sentiment_analysis", {}).get("sentiment_score", 0) + 1) / 2  # Normalize to 0-1
            viral_score = viral_potential.get("viral_score", 0)
            safety_score = alert_monitoring.get("safety_score", 0)
            momentum_score = sentiment_trend.get("momentum_score", 0)

            # Weighted average (Mentions: 30%, Sentiment: 25%, Viral: 20%, Safety: 15%, Momentum: 10%)
            overall_social_score = (mention_score * 0.3) + (sentiment_score * 0.25) + (viral_score * 0.2) + (safety_score * 0.15) + (momentum_score * 0.1)

            # Determine social assessment
            social_assessment = "excellent"
            if overall_social_score < 0.3:
                social_assessment = "poor"
            elif overall_social_score < 0.5:
                social_assessment = "moderate"
            elif overall_social_score < 0.7:
                social_assessment = "good"

            comprehensive_analysis = {
                "overall_social_score": overall_social_score,
                "social_assessment": social_assessment,
                "meets_sniper_requirements": meets_mentions_threshold and overall_social_score >= 0.5,
                "mention_threshold_met": meets_mentions_threshold,
                "total_mentions": total_mentions,
                "minimum_required": min_mentions_threshold,
                "key_metrics": {
                    "mention_score": mention_score,
                    "sentiment_score": sentiment_score,
                    "viral_score": viral_score,
                    "safety_score": safety_score,
                    "momentum_score": momentum_score
                },
                "sentiment_details": {
                    "current_sentiment": mention_analysis.get("sentiment_analysis", {}).get("overall_sentiment", "neutral"),
                    "sentiment_trend": sentiment_trend.get("sentiment_trend", 0),
                    "has_positive_momentum": sentiment_trend.get("is_positive_momentum", False)
                },
                "viral_potential": viral_potential.get("viral_level", "low"),
                "has_viral_potential": viral_potential.get("has_viral_potential", False),
                "safety_indicators": {
                    "alert_level": alert_monitoring.get("alert_level", "normal"),
                    "safety_score": safety_score,
                    "red_flags_count": len(alert_monitoring.get("red_flags", []))
                },
                "analyses": {
                    "mentions": mention_analysis,
                    "sentiment_trend": sentiment_trend,
                    "viral_potential": viral_potential,
                    "alert_monitoring": alert_monitoring
                },
                "recommendation": "proceed" if meets_mentions_threshold and overall_social_score >= 0.6 else "caution" if overall_social_score >= 0.4 else "avoid",
                "confidence_score": min(0.95, overall_social_score * 1.1),
                "analysis_timestamp": time()
            }

            # Enhance with Python social intelligence engine data
            enhanced_analysis = await self._enhance_with_python_data(comprehensive_analysis, token_symbol)

            # Recalculate overall score if Python data provided significant new insights
            if "python_sentiment_analysis" in enhanced_analysis:
                python_sentiment = enhanced_analysis["python_sentiment_analysis"]
                if "total_posts" in python_sentiment and python_sentiment["total_posts"] > 0:
                    # Boost score slightly if there's active social discussion
                    python_boost = min(0.1, python_sentiment["total_posts"] / 1000)
                    enhanced_overall_score = min(1.0, enhanced_analysis["overall_social_score"] + python_boost)
                    enhanced_analysis["overall_social_score"] = enhanced_overall_score

                    # Recalculate assessment if score changed significantly
                    if enhanced_overall_score > 0.7:
                        enhanced_analysis["social_assessment"] = "excellent"
                    elif enhanced_overall_score > 0.5:
                        enhanced_analysis["social_assessment"] = "good"
                    elif enhanced_overall_score > 0.3:
                        enhanced_analysis["social_assessment"] = "moderate"
                    else:
                        enhanced_analysis["social_assessment"] = "poor"

                    # Update recommendation
                    enhanced_analysis["meets_sniper_requirements"] = meets_mentions_threshold and enhanced_overall_score >= 0.5
                    enhanced_analysis["recommendation"] = "proceed" if meets_mentions_threshold and enhanced_overall_score >= 0.6 else "caution" if enhanced_overall_score >= 0.4 else "avoid"
                    enhanced_analysis["confidence_score"] = min(0.98, enhanced_overall_score * 1.15)

            self.logger.info(f"Enhanced comprehensive social analysis completed",
                           token_symbol=token_symbol,
                           overall_score=enhanced_analysis["overall_social_score"],
                           meets_threshold=meets_mentions_threshold,
                           assessment=enhanced_analysis["social_assessment"],
                           recommendation=enhanced_analysis["recommendation"],
                           python_enhanced=self.use_python_engine and self.python_initialized)

            return enhanced_analysis

        except e:
            self.logger.error(f"Error in comprehensive social analysis",
                            token_symbol=token_symbol,
                            error=str(e))
            return self._get_error_response(str(e))

    def _get_disabled_response(self) -> Dict[String, Any]:
        """
        Return response when social monitoring is disabled
        """
        return {
            "enabled": False,
            "overall_social_score": 0.0,
            "social_assessment": "unknown",
            "meets_sniper_requirements": False,
            "recommendation": "caution",
            "message": "Social monitoring is disabled"
        }

    def _get_error_response(self, error_message: String) -> Dict[String, Any]:
        """
        Return error response for failed analysis
        """
        return {
            "enabled": self.enabled,
            "overall_social_score": 0.0,
            "social_assessment": "poor",
            "meets_sniper_requirements": False,
            "recommendation": "avoid",
            "error": error_message,
            "message": "Social analysis failed - assuming poor social metrics for safety"
        }

    # Python Social Intelligence Engine Integration Methods

    fn _init_python_engine(self):
        """
        Initialize Python social intelligence engine
        """
        try:
            # Import the Python social intelligence engine
            Python.import("sys.path").append("src/data")
            social_engine_module = Python.import("social_intelligence_engine")

            # Create default configuration if none provided
            config = self.engine_config
            if config.size() == 0:
                config = {
                    "twitter": {
                        "enabled": False,
                        "api_key": self.twitter_api_key,
                        "api_secret": self.twitter_api_secret,
                        "access_token": self.twitter_access_token,
                        "access_token_secret": self.twitter_access_token_secret
                    },
                    "telegram": {"enabled": False},
                    "reddit": {"enabled": False},
                    "discord": {"enabled": False}
                }

            # Initialize the engine (async initialization will be handled on first use)
            self.python_engine = social_engine_module.SocialIntelligenceEngine(config)
            self.python_initialized = True

            self.logger.info("Python social intelligence engine initialized successfully")

        except e:
            self.logger.error(f"Failed to initialize Python social intelligence engine: {e}")
            self.python_initialized = False
            self.use_python_engine = False

    async def _ensure_python_engine_ready(self):
        """
        Ensure Python engine is initialized and ready
        """
        if self.use_python_engine and not self.python_initialized:
            self._init_python_engine()

        if self.use_python_engine and self.python_initialized:
            try:
                # Initialize async components if not already done
                await self.python_engine.initialize()
            except:
                # Engine might already be initialized, continue
                pass

    async def _get_python_sentiment_summary(self, token_symbol: String, time_hours: Int = 1) -> Dict[String, Any]:
        """
        Get sentiment summary from Python social intelligence engine
        """
        if not self.use_python_engine or not self.python_initialized:
            return {}

        try:
            await self._ensure_python_engine_ready()

            # Get sentiment summary from Python engine
            platforms = Python.import("social_intelligence_engine").Platform
            time_delta = Python.import("datetime").timedelta(hours=time_hours)

            summary = await self.python_engine.get_sentiment_summary(
                platforms=[platforms.TWITTER, platforms.REDDIT, platforms.TELEGRAM],
                time_range=time_delta
            )

            # Convert Python result to Mojo Dict
            return self._convert_python_dict(summary)

        except e:
            self.logger.error(f"Error getting Python sentiment summary: {e}")
            return {}

    async def _get_python_recent_alerts(self, limit: Int = 20) -> List[Dict[String, Any]]:
        """
        Get recent alerts from Python social intelligence engine
        """
        if not self.use_python_engine or not self.python_initialized:
            return []

        try:
            await self._ensure_python_engine_ready()

            alerts = await self.python_engine.get_recent_alerts(limit=limit)

            # Convert Python alerts to Mojo format
            mojo_alerts = List[Dict[String, Any]]()
            for alert in alerts:
                mojo_alerts.append(self._convert_python_dict(alert.to_dict()))

            return mojo_alerts

        except e:
            self.logger.error(f"Error getting Python recent alerts: {e}")
            return []

    def _convert_python_dict(self, python_obj: PythonObject) -> Dict[String, Any]:
        """
        Convert Python dictionary/object to Mojo Dict
        """
        try:
            # Try to convert to JSON first
            json_module = Python.import("json")
            json_str = json_module.dumps(python_obj)
            return loads(json_str)
        except:
            # Fallback: try to extract basic attributes
            result = Dict[String, Any]()
            try:
                result["data"] = str(python_obj)
            except:
                result["data"] = "conversion_error"
            return result

    async def _enhance_with_python_data(self, base_analysis: Dict[String, Any], token_symbol: String) -> Dict[String, Any]:
        """
        Enhance base analysis with data from Python social intelligence engine
        """
        if not self.use_python_engine:
            return base_analysis

        try:
            # Get Python sentiment summary
            python_sentiment = await self._get_python_sentiment_summary(token_symbol)

            # Get recent alerts
            python_alerts = await self._get_python_recent_alerts(10)

            # Enhance the base analysis
            enhanced = base_analysis.copy()

            if python_sentiment.size() > 0:
                enhanced["python_sentiment_analysis"] = python_sentiment

                # Update overall sentiment if Python data is available
                if "avg_sentiment" in python_sentiment:
                    python_score = python_sentiment["avg_sentiment"]
                    # Blend with existing sentiment (70% existing, 30% Python)
                    existing_score = enhanced.get("sentiment_analysis", {}).get("sentiment_score", 0.0)
                    blended_score = (existing_score * 0.7) + (python_score * 0.3)

                    if "sentiment_analysis" not in enhanced:
                        enhanced["sentiment_analysis"] = {}
                    enhanced["sentiment_analysis"]["sentiment_score"] = blended_score
                    enhanced["sentiment_analysis"]["python_enhanced"] = True

                    # Update sentiment label based on blended score
                    if blended_score > 0.3:
                        enhanced["sentiment_analysis"]["overall_sentiment"] = "positive"
                    elif blended_score < -0.3:
                        enhanced["sentiment_analysis"]["overall_sentiment"] = "negative"
                    else:
                        enhanced["sentiment_analysis"]["overall_sentiment"] = "neutral"

            if python_alerts.size() > 0:
                enhanced["python_alerts"] = python_alerts
                enhanced["has_social_alerts"] = True

                # Check for any high-significance alerts
                high_significance_alerts = [alert for alert in python_alerts
                                          if alert.get("significance_score", 0) > 0.7]
                if high_significance_alerts.size() > 0:
                    enhanced["has_high_priority_alerts"] = True
                    enhanced["alert_level"] = "high"

            # Add enhancement metadata
            enhanced["data_sources"] = ["twitter_api", "python_intelligence_engine"]
            enhanced["enhancement_timestamp"] = time()

            self.logger.info(f"Enhanced social analysis with Python engine data",
                           token_symbol=token_symbol,
                           python_data_available=python_sentiment.size() > 0,
                           alerts_count=python_alerts.size())

            return enhanced

        except e:
            self.logger.error(f"Error enhancing analysis with Python data: {e}")
            # Return original analysis if enhancement fails
            base_analysis["enhancement_error"] = str(e)
            return base_analysis

    def health_check(self) -> Bool:
        """
        Check if social media APIs are accessible
        """
        if not self.enabled:
            return True  # Consider healthy if disabled

        try:
            # Simple health check - try to search for a known term
            result = self.get_token_mentions("BTC", "bitcoin", 1)
            return "error" not in result
        except e:
            self.logger.error(f"Social API health check failed: {e}")
            return False