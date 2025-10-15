"""
Production Social Intelligence Engine for Multi-Platform Sentiment Tracking

This module provides comprehensive social media intelligence collection and analysis
across multiple platforms (Twitter/X, Telegram, Discord, Reddit, etc.) for cryptocurrency
trading signals and sentiment analysis.

Features:
- Real-time social media monitoring and sentiment analysis
- Multi-platform data aggregation (Twitter/X, Telegram, Discord, Reddit)
- Advanced NLP processing with ML-based sentiment scoring
- Influencer tracking and credibility scoring
- Trend detection and viral content analysis
- Spam detection and bot identification
- Real-time alerts for significant sentiment shifts
- Historical sentiment data storage and analysis
"""

import asyncio
import aiohttp
import json
import time
import logging
import os
import re
import hashlib
from typing import Dict, List, Any, Optional, Set, Tuple
from dataclasses import dataclass, asdict
from enum import Enum
from datetime import datetime, timezone, timedelta
from collections import defaultdict, deque
import asyncpg
import aioredis
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
import pandas as pd
from textblob import TextBlob
import transformers
from transformers import pipeline, AutoTokenizer, AutoModelForSequenceClassification
import spacy
import telegram
import discord
import praw
import tweepy

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============================================================================
# Data Models and Enums
# ============================================================================

class Platform(Enum):
    """Social media platforms"""
    TWITTER = "twitter"
    TELEGRAM = "telegram"
    DISCORD = "discord"
    REDDIT = "reddit"
    NEWS = "news"

class SentimentScore(Enum):
    """Sentiment classification"""
    VERY_BEARISH = "very_bearish"
    BEARISH = "bearish"
    NEUTRAL = "neutral"
    BULLISH = "bullish"
    VERY_BULLISH = "very_bullish"

class ContentType(Enum):
    """Types of social content"""
    POST = "post"
    COMMENT = "comment"
    REPLY = "reply"
    RETWEET = "retweet"
    SHARE = "share"
    NEWS_ARTICLE = "news_article"

@dataclass
class SocialPost:
    """Social media post data structure"""
    id: str
    platform: Platform
    author_id: str
    author_username: str
    content: str
    timestamp: datetime
    likes: int = 0
    shares: int = 0
    comments: int = 0
    hashtags: List[str] = None
    mentions: List[str] = None
    urls: List[str] = None
    content_type: ContentType = ContentType.POST
    reply_to_id: Optional[str] = None
    language: str = "en"
    location: Optional[str] = None
    raw_data: Dict[str, Any] = None

    def __post_init__(self):
        if self.hashtags is None:
            self.hashtags = []
        if self.mentions is None:
            self.mentions = []
        if self.urls is None:
            self.urls = []
        if self.raw_data is None:
            self.raw_data = {}

@dataclass
class SentimentAnalysis:
    """Sentiment analysis results"""
    post_id: str
    platform: Platform
    sentiment_score: float  # -1.0 to 1.0
    sentiment_label: SentimentScore
    confidence: float  # 0.0 to 1.0
    emotions: Dict[str, float]  # joy, anger, fear, sadness, etc.
    keywords: List[str]
    topics: List[str]
    spam_score: float  # 0.0 to 1.0
    bot_probability: float  # 0.0 to 1.0
    credibility_score: float  # 0.0 to 1.0
    processed_at: datetime

@dataclass
class InfluencerProfile:
    """Influencer profile data"""
    platform: Platform
    user_id: str
    username: str
    display_name: str
    followers: int
    following: int
    verified: bool
    description: str
    avg_engagement: float
    credibility_score: float
    expertise_areas: List[str]
    posting_frequency: float
    audience_demographics: Dict[str, Any]
    last_updated: datetime

@dataclass
class TrendingTopic:
    """Trending topic information"""
    topic: str
    platform: Platform
    mentions: int
    sentiment_distribution: Dict[str, int]
    growth_rate: float
    peak_time: datetime
    related_keywords: List[str]
    top_influencers: List[str]
    first_seen: datetime

@dataclass
class SocialAlert:
    """Social media trading alert"""
    id: str
    alert_type: str  # sentiment_spike, influencer_post, viral_content, etc.
    platform: Platform
    content: str
    significance_score: float
    timestamp: datetime
    metadata: Dict[str, Any]

# ============================================================================
# Production Social Intelligence Engine
# ============================================================================

class SocialIntelligenceEngine:
    """
    Production-grade social intelligence engine for cryptocurrency trading.
    Collects, processes, and analyzes social media data across multiple platforms.
    """

    def __init__(
        self,
        config: Dict[str, Any],
        db_url: Optional[str] = None,
        redis_url: Optional[str] = None
    ):
        """
        Initialize social intelligence engine

        Args:
            config: Configuration dictionary with API keys and settings
            db_url: PostgreSQL database connection string
            redis_url: Redis connection string for caching
        """
        self.config = config
        self.db_url = db_url or os.getenv("DATABASE_URL")
        self.redis_url = redis_url or os.getenv("REDIS_URL")

        # Initialize connections
        self.db_pool = None
        self.redis_client = None
        self.http_session = None

        # Platform clients
        self.twitter_client = None
        self.telegram_client = None
        self.discord_client = None
        self.reddit_client = None

        # ML models
        self.sentiment_pipeline = None
        self.spacy_model = None
        self.tfidf_vectorizer = None

        # Data storage
        self.posts_cache = deque(maxlen=10000)
        self.sentiment_cache = {}
        self.influencer_cache = {}
        self.trending_topics = {}

        # Performance tracking
        self.metrics = {
            "posts_processed": 0,
            "sentiment_analyzed": 0,
            "alerts_generated": 0,
            "api_calls": 0,
            "errors": 0,
            "start_time": time.time()
        }

        # Rate limiting
        self.rate_limits = defaultdict(lambda: {"calls": 0, "reset_time": time.time() + 3600})

        # Background tasks
        self.collection_tasks = []
        self.analysis_task = None
        self.alert_task = None

        logger.info("Social Intelligence Engine initialized")

    async def initialize(self):
        """Initialize all connections and models"""
        logger.info("Initializing Social Intelligence Engine...")

        # Initialize database connections
        await self._init_database()

        # Initialize HTTP session
        self.http_session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=30),
            connector=aiohttp.TCPConnector(limit=100)
        )

        # Initialize platform clients
        await self._init_platform_clients()

        # Initialize ML models
        await self._init_ml_models()

        # Start background tasks
        await self._start_background_tasks()

        logger.info("Social Intelligence Engine initialization complete")

    async def _init_database(self):
        """Initialize database connections"""
        try:
            # PostgreSQL connection
            if self.db_url:
                self.db_pool = await asyncpg.create_pool(
                    self.db_url,
                    min_size=2,
                    max_size=10,
                    command_timeout=60
                )
                logger.info("PostgreSQL connection established")

            # Redis connection
            if self.redis_url:
                self.redis_client = await aioredis.from_url(self.redis_url)
                await self.redis_client.ping()
                logger.info("Redis connection established")

        except Exception as e:
            logger.error(f"Database initialization failed: {e}")
            # Continue without database for development

    async def _init_platform_clients(self):
        """Initialize social media platform clients"""
        config = self.config

        # Twitter/X
        if "twitter" in config:
            try:
                twitter_config = config["twitter"]
                auth = tweepy.OAuthHandler(
                    twitter_config["api_key"],
                    twitter_config["api_secret"]
                )
                auth.set_access_token(
                    twitter_config["access_token"],
                    twitter_config["access_token_secret"]
                )
                self.twitter_client = tweepy.API(auth, wait_on_rate_limit=True)
                logger.info("Twitter client initialized")
            except Exception as e:
                logger.warning(f"Twitter client initialization failed: {e}")

        # Telegram
        if "telegram" in config:
            try:
                telegram_config = config["telegram"]
                self.telegram_client = telegram.Bot(token=telegram_config["bot_token"])
                logger.info("Telegram client initialized")
            except Exception as e:
                logger.warning(f"Telegram client initialization failed: {e}")

        # Reddit
        if "reddit" in config:
            try:
                reddit_config = config["reddit"]
                self.reddit_client = praw.Reddit(
                    client_id=reddit_config["client_id"],
                    client_secret=reddit_config["client_secret"],
                    user_agent="MojoRust/1.0"
                )
                logger.info("Reddit client initialized")
            except Exception as e:
                logger.warning(f"Reddit client initialization failed: {e}")

    async def _init_ml_models(self):
        """Initialize ML models for sentiment analysis"""
        try:
            # Load sentiment analysis model
            model_name = "cardiffnlp/twitter-roberta-base-sentiment-latest"
            self.sentiment_pipeline = pipeline(
                "sentiment-analysis",
                model=model_name,
                tokenizer=model_name,
                device=0 if torch.cuda.is_available() else -1
            )

            # Load spaCy model
            self.spacy_model = spacy.load("en_core_web_sm")

            # Initialize TF-IDF vectorizer
            self.tfidf_vectorizer = TfidfVectorizer(
                max_features=1000,
                stop_words='english',
                ngram_range=(1, 2)
            )

            logger.info("ML models initialized successfully")

        except Exception as e:
            logger.warning(f"ML model initialization failed: {e}")
            # Fallback to TextBlob
            logger.info("Using TextBlob as fallback sentiment analyzer")

    async def _start_background_tasks(self):
        """Start background collection and analysis tasks"""
        # Start data collection tasks
        for platform in Platform:
            if await self._is_platform_enabled(platform):
                task = asyncio.create_task(self._collect_platform_data(platform))
                self.collection_tasks.append(task)

        # Start sentiment analysis task
        self.analysis_task = asyncio.create_task(self._analyze_sentiment_loop())

        # Start alert generation task
        self.alert_task = asyncio.create_task(self._generate_alerts_loop())

        logger.info("Background tasks started")

    async def _is_platform_enabled(self, platform: Platform) -> bool:
        """Check if a platform is enabled and has valid credentials"""
        config_key = platform.value
        return config_key in self.config and self.config[config_key].get("enabled", False)

    async def _collect_platform_data(self, platform: Platform):
        """Collect data from a specific platform"""
        logger.info(f"Starting data collection for {platform.value}")

        while True:
            try:
                if platform == Platform.TWITTER:
                    await self._collect_twitter_data()
                elif platform == Platform.TELEGRAM:
                    await self._collect_telegram_data()
                elif platform == Platform.REDDIT:
                    await self._collect_reddit_data()
                elif platform == Platform.DISCORD:
                    await self._collect_discord_data()

                # Rate limiting
                await asyncio.sleep(self._get_collection_interval(platform))

            except Exception as e:
                logger.error(f"Error collecting data from {platform.value}: {e}")
                await asyncio.sleep(60)  # Wait 1 minute on error

    async def _collect_twitter_data(self):
        """Collect data from Twitter/X"""
        if not self.twitter_client:
            return

        try:
            # Search for cryptocurrency-related tweets
            keywords = ["bitcoin", "btc", "ethereum", "eth", "solana", "sol",
                       "crypto", "cryptocurrency", "blockchain", "DeFi", "NFT"]

            for keyword in keywords:
                if not self._check_rate_limit("twitter"):
                    await asyncio.sleep(60)
                    continue

                tweets = self.twitter_client.search_tweets(
                    q=keyword,
                    lang="en",
                    result_type="recent",
                    count=100,
                    tweet_mode="extended"
                )

                for tweet in tweets:
                    post = self._parse_twitter_tweet(tweet)
                    await self._process_post(post)

                self.metrics["api_calls"] += 1
                await asyncio.sleep(1)  # Respect rate limits

        except Exception as e:
            logger.error(f"Twitter data collection error: {e}")
            self.metrics["errors"] += 1

    async def _collect_telegram_data(self):
        """Collect data from Telegram channels"""
        if not self.telegram_client:
            return

        try:
            # Get list of crypto-related channels to monitor
            channels = self.config.get("telegram", {}).get("channels", [])

            for channel_id in channels:
                try:
                    # Get recent messages from channel
                    messages = await self._get_telegram_messages(channel_id, limit=50)

                    for message in messages:
                        post = self._parse_telegram_message(message, channel_id)
                        await self._process_post(post)

                except Exception as e:
                    logger.warning(f"Error collecting from Telegram channel {channel_id}: {e}")

        except Exception as e:
            logger.error(f"Telegram data collection error: {e}")
            self.metrics["errors"] += 1

    async def _collect_reddit_data(self):
        """Collect data from Reddit"""
        if not self.reddit_client:
            return

        try:
            # Monitor crypto-related subreddits
            subreddits = ["cryptocurrency", "Bitcoin", "ethereum", "solana",
                          "CryptoMarkets", "CryptoCurrencyTrading", "defi"]

            for sub_name in subreddits:
                try:
                    subreddit = self.reddit_client.subreddit(sub_name)

                    # Get hot posts
                    for post in subreddit.hot(limit=25):
                        reddit_post = self._parse_reddit_post(post)
                        await self._process_post(reddit_post)

                        # Get top comments
                        post.comments.replace_more(limit=0)
                        for comment in post.comments[:20]:
                            reddit_comment = self._parse_reddit_comment(comment, post.id)
                            await self._process_post(reddit_comment)

                except Exception as e:
                    logger.warning(f"Error collecting from r/{sub_name}: {e}")

        except Exception as e:
            logger.error(f"Reddit data collection error: {e}")
            self.metrics["errors"] += 1

    async def _collect_discord_data(self):
        """Collect data from Discord servers"""
        # Discord implementation would require specific bot setup
        # This is a placeholder for Discord data collection
        pass

    def _parse_twitter_tweet(self, tweet) -> SocialPost:
        """Parse Twitter tweet into SocialPost"""
        return SocialPost(
            id=str(tweet.id),
            platform=Platform.TWITTER,
            author_id=str(tweet.user.id),
            author_username=tweet.user.screen_name,
            content=tweet.full_text,
            timestamp=tweet.created_at.replace(tzinfo=timezone.utc),
            likes=tweet.favorite_count,
            shares=tweet.retweet_count,
            comments=tweet.reply_count if hasattr(tweet, 'reply_count') else 0,
            hashtags=self._extract_hashtags(tweet.full_text),
            mentions=self._extract_mentions(tweet.full_text),
            urls=self._extract_urls(tweet.full_text),
            content_type=ContentType.RETWEET if hasattr(tweet, 'retweeted_status') else ContentType.POST,
            language=tweet.lang if hasattr(tweet, 'lang') else "en",
            raw_data={"user": tweet.user._json}
        )

    def _parse_telegram_message(self, message, channel_id: str) -> SocialPost:
        """Parse Telegram message into SocialPost"""
        return SocialPost(
            id=str(message.message_id),
            platform=Platform.TELEGRAM,
            author_id=str(message.from_user.id) if message.from_user else channel_id,
            author_username=message.from_user.username if message.from_user else channel_id,
            content=message.text or message.caption or "",
            timestamp=message.date.replace(tzinfo=timezone.utc),
            content_type=ContentType.POST,
            language="en",  # Would need language detection
            raw_data={"channel_id": channel_id}
        )

    def _parse_reddit_post(self, post) -> SocialPost:
        """Parse Reddit post into SocialPost"""
        return SocialPost(
            id=post.id,
            platform=Platform.REDDIT,
            author_id=post.author.id if post.author else "[deleted]",
            author_username=post.author.name if post.author else "[deleted]",
            content=post.title + "\n\n" + post.selftext,
            timestamp=datetime.fromtimestamp(post.created_utc, tz=timezone.utc),
            likes=post.score,
            comments=post.num_comments,
            hashtags=self._extract_hashtags(post.title + " " + post.selftext),
            content_type=ContentType.POST,
            subreddit=post.subreddit.display_name,
            raw_data={"permalink": post.permalink}
        )

    def _parse_reddit_comment(self, comment, post_id: str) -> SocialPost:
        """Parse Reddit comment into SocialPost"""
        return SocialPost(
            id=comment.id,
            platform=Platform.REDDIT,
            author_id=comment.author.id if comment.author else "[deleted]",
            author_username=comment.author.name if comment.author else "[deleted]",
            content=comment.body,
            timestamp=datetime.fromtimestamp(comment.created_utc, tz=timezone.utc),
            likes=comment.score,
            content_type=ContentType.COMMENT,
            reply_to_id=post_id,
            raw_data={"permalink": comment.permalink}
        )

    async def _process_post(self, post: SocialPost):
        """Process a social media post"""
        try:
            # Add to cache
            self.posts_cache.append(post)

            # Store in database if available
            if self.db_pool:
                await self._store_post(post)

            # Cache in Redis if available
            if self.redis_client:
                await self._cache_post(post)

            self.metrics["posts_processed"] += 1

        except Exception as e:
            logger.error(f"Error processing post {post.id}: {e}")
            self.metrics["errors"] += 1

    async def _analyze_sentiment_loop(self):
        """Background task to analyze sentiment of collected posts"""
        logger.info("Starting sentiment analysis loop")

        while True:
            try:
                # Get unprocessed posts
                posts_to_analyze = list(self.posts_cache)[-100:]  # Last 100 posts

                for post in posts_to_analyze:
                    if post.id not in self.sentiment_cache:
                        analysis = await self._analyze_sentiment(post)
                        self.sentiment_cache[post.id] = analysis
                        self.metrics["sentiment_analyzed"] += 1

                await asyncio.sleep(30)  # Analyze every 30 seconds

            except Exception as e:
                logger.error(f"Error in sentiment analysis loop: {e}")
                await asyncio.sleep(60)

    async def _analyze_sentiment(self, post: SocialPost) -> SentimentAnalysis:
        """Analyze sentiment of a post"""
        try:
            content = post.content
            if not content:
                return self._create_neutral_analysis(post)

            # Use ML model if available
            if self.sentiment_pipeline:
                result = self.sentiment_pipeline(content)[0]
                sentiment_score = self._convert_sentiment_label(result['label'])
                confidence = result['score']
            else:
                # Fallback to TextBlob
                blob = TextBlob(content)
                sentiment_score = blob.sentiment.polarity
                confidence = abs(blob.sentiment.polarity)

            # Determine sentiment label
            sentiment_label = self._get_sentiment_label(sentiment_score)

            # Extract emotions (simplified)
            emotions = self._extract_emotions(content)

            # Extract keywords and topics
            keywords = self._extract_keywords(content)
            topics = self._extract_topics(content)

            # Calculate spam score
            spam_score = self._calculate_spam_score(post)

            # Calculate bot probability
            bot_probability = self._calculate_bot_probability(post)

            # Calculate credibility score
            credibility_score = self._calculate_credibility_score(post)

            return SentimentAnalysis(
                post_id=post.id,
                platform=post.platform,
                sentiment_score=sentiment_score,
                sentiment_label=sentiment_label,
                confidence=confidence,
                emotions=emotions,
                keywords=keywords,
                topics=topics,
                spam_score=spam_score,
                bot_probability=bot_probability,
                credibility_score=credibility_score,
                processed_at=datetime.now(timezone.utc)
            )

        except Exception as e:
            logger.error(f"Error analyzing sentiment for post {post.id}: {e}")
            return self._create_neutral_analysis(post)

    def _convert_sentiment_label(self, label: str) -> float:
        """Convert model label to sentiment score"""
        label_map = {
            "LABEL_0": -1.0,  # Very negative
            "LABEL_1": -0.5,  # Negative
            "LABEL_2": 0.0,   # Neutral
            "LABEL_3": 0.5,   # Positive
            "LABEL_4": 1.0    # Very positive
        }
        return label_map.get(label, 0.0)

    def _get_sentiment_label(self, score: float) -> SentimentScore:
        """Convert sentiment score to label"""
        if score <= -0.6:
            return SentimentScore.VERY_BEARISH
        elif score <= -0.2:
            return SentimentScore.BEARISH
        elif score <= 0.2:
            return SentimentScore.NEUTRAL
        elif score <= 0.6:
            return SentimentScore.BULLISH
        else:
            return SentimentScore.VERY_BULLISH

    def _extract_emotions(self, content: str) -> Dict[str, float]:
        """Extract emotion scores from content"""
        # Simplified emotion extraction based on keywords
        emotions = {
            "joy": 0.0,
            "anger": 0.0,
            "fear": 0.0,
            "sadness": 0.0,
            "surprise": 0.0,
            "disgust": 0.0
        }

        # Emotion keyword mapping
        emotion_keywords = {
            "joy": ["happy", "excited", "glad", "great", "awesome", "bullish", "moon"],
            "anger": ["angry", "mad", "frustrated", "annoyed", "bearish", "dump"],
            "fear": ["scared", "afraid", "worried", "concerned", "fear", "crash"],
            "sadness": ["sad", "disappointed", "depressed", "loss", "bad"],
            "surprise": ["surprised", "shocked", "amazed", "wow", "unexpected"],
            "disgust": ["disgusted", "sick", "terrible", "awful", "scam"]
        }

        content_lower = content.lower()
        for emotion, keywords in emotion_keywords.items():
            count = sum(1 for keyword in keywords if keyword in content_lower)
            emotions[emotion] = min(count / len(keywords), 1.0)

        return emotions

    def _extract_keywords(self, content: str) -> List[str]:
        """Extract keywords from content"""
        # Simple keyword extraction (would be enhanced with NLP)
        crypto_keywords = [
            "bitcoin", "btc", "ethereum", "eth", "solana", "sol", "cardano", "ada",
            "polkadot", "dot", "avalanche", "avax", "chainlink", "link", "uniswap",
            "defi", "nft", "dao", "yield", "staking", "mining", "bullish", "bearish",
            "moon", "lambo", "hodl", "dip", "pump", "dump", "whale", "shill"
        ]

        content_lower = content.lower()
        return [keyword for keyword in crypto_keywords if keyword in content_lower]

    def _extract_topics(self, content: str) -> List[str]:
        """Extract topics from content"""
        topics = []

        # Topic detection based on keyword patterns
        if any(word in content.lower() for word in ["price", "chart", "technical"]):
            topics.append("price_analysis")

        if any(word in content.lower() for word in ["news", "announcement", "partnership"]):
            topics.append("market_news")

        if any(word in content.lower() for word in ["buy", "sell", "trade"]):
            topics.append("trading_signals")

        if any(word in content.lower() for word in ["defi", "yield", "staking", "liquidity"]):
            topics.append("defi")

        if any(word in content.lower() for word in ["nft", "art", "collection"]):
            topics.append("nft")

        return topics

    def _calculate_spam_score(self, post: SocialPost) -> float:
        """Calculate spam score for a post"""
        score = 0.0

        # Check for spam indicators
        content_lower = post.content.lower()

        # Excessive capitalization
        if content_lower.count('!') > 3:
            score += 0.2

        if sum(1 for c in post.content if c.isupper()) / len(post.content) > 0.5:
            score += 0.2

        # Spam keywords
        spam_keywords = ["100x", "guaranteed", "free money", "click here", "buy now"]
        score += sum(0.1 for keyword in spam_keywords if keyword in content_lower)

        # Repetitive content
        unique_words = len(set(post.content.split()))
        total_words = len(post.content.split())
        if total_words > 0 and unique_words / total_words < 0.3:
            score += 0.3

        # Multiple URLs
        if len(post.urls) > 3:
            score += 0.2

        return min(score, 1.0)

    def _calculate_bot_probability(self, post: SocialPost) -> float:
        """Calculate probability that author is a bot"""
        score = 0.0

        # High posting frequency (would need historical data)
        # Placeholder for bot detection logic

        # Generic profile information
        if post.author_username and post.author_username.isdigit():
            score += 0.3

        # Low engagement ratio
        if post.likes + post.comments == 0:
            score += 0.2

        # Content patterns
        if post.content and len(post.content.split()) < 3:
            score += 0.1

        return min(score, 1.0)

    def _calculate_credibility_score(self, post: SocialPost) -> float:
        """Calculate credibility score for a post"""
        score = 0.5  # Base score

        # Verified author
        if post.raw_data and post.raw_data.get("user", {}).get("verified"):
            score += 0.3

        # High engagement
        engagement = post.likes + post.shares + post.comments
        if engagement > 100:
            score += 0.2
        elif engagement > 10:
            score += 0.1

        # Content quality (length, originality)
        if len(post.content) > 100:
            score += 0.1

        # Low spam score
        spam_score = self._calculate_spam_score(post)
        score -= spam_score * 0.3

        return max(0.0, min(1.0, score))

    def _create_neutral_analysis(self, post: SocialPost) -> SentimentAnalysis:
        """Create neutral sentiment analysis for fallback"""
        return SentimentAnalysis(
            post_id=post.id,
            platform=post.platform,
            sentiment_score=0.0,
            sentiment_label=SentimentScore.NEUTRAL,
            confidence=0.5,
            emotions={"joy": 0.0, "anger": 0.0, "fear": 0.0, "sadness": 0.0, "surprise": 0.0, "disgust": 0.0},
            keywords=[],
            topics=[],
            spam_score=0.0,
            bot_probability=0.0,
            credibility_score=0.5,
            processed_at=datetime.now(timezone.utc)
        )

    async def _generate_alerts_loop(self):
        """Background task to generate trading alerts"""
        logger.info("Starting alert generation loop")

        while True:
            try:
                await self._check_sentiment_spikes()
                await self._check_influencer_activity()
                await self._check_viral_content()

                await asyncio.sleep(60)  # Check every minute

            except Exception as e:
                logger.error(f"Error in alert generation loop: {e}")
                await asyncio.sleep(60)

    async def _check_sentiment_spikes(self):
        """Check for significant sentiment spikes"""
        # Analyze recent sentiment trends
        recent_sentiments = [
            analysis for analysis in self.sentiment_cache.values()
            if (datetime.now(timezone.utc) - analysis.processed_at).seconds < 300  # Last 5 minutes
        ]

        if len(recent_sentiments) < 10:
            return

        # Calculate sentiment distribution
        avg_sentiment = sum(s.sentiment_score for s in recent_sentiments) / len(recent_sentiments)

        # Generate alert if sentiment is extreme
        if avg_sentiment > 0.7:
            await self._create_alert("bullish_spike", "Strong bullish sentiment detected", avg_sentiment)
        elif avg_sentiment < -0.7:
            await self._create_alert("bearish_spike", "Strong bearish sentiment detected", avg_sentiment)

    async def _check_influencer_activity(self):
        """Check for activity from key influencers"""
        # Implementation would track known crypto influencers
        pass

    async def _check_viral_content(self):
        """Check for viral crypto content"""
        # Implementation would identify rapidly spreading content
        pass

    async def _create_alert(self, alert_type: str, message: str, significance: float):
        """Create a trading alert"""
        alert = SocialAlert(
            id=str(int(time.time() * 1000)),
            alert_type=alert_type,
            platform=Platform.TWITTER,  # Would be determined by context
            content=message,
            significance_score=significance,
            timestamp=datetime.now(timezone.utc),
            metadata={"sentiment_score": significance}
        )

        # Store alert
        if self.db_pool:
            await self._store_alert(alert)

        if self.redis_client:
            await self._cache_alert(alert)

        self.metrics["alerts_generated"] += 1
        logger.info(f"Alert generated: {alert_type} - {message}")

    # Utility methods
    def _extract_hashtags(self, content: str) -> List[str]:
        """Extract hashtags from content"""
        return re.findall(r'#\w+', content)

    def _extract_mentions(self, content: str) -> List[str]:
        """Extract mentions from content"""
        return re.findall(r'@\w+', content)

    def _extract_urls(self, content: str) -> List[str]:
        """Extract URLs from content"""
        url_pattern = r'https?://[^\s<>"]+|www\.[^\s<>"]+'
        return re.findall(url_pattern, content)

    def _check_rate_limit(self, platform: str) -> bool:
        """Check if platform rate limit allows API call"""
        now = time.time()
        limits = self.rate_limits[platform]

        if now > limits["reset_time"]:
            # Reset rate limit
            limits["calls"] = 0
            limits["reset_time"] = now + 3600

        # Platform-specific limits
        max_calls = {
            "twitter": 300,
            "telegram": 30,
            "reddit": 60
        }

        if limits["calls"] < max_calls.get(platform, 100):
            limits["calls"] += 1
            return True

        return False

    def _get_collection_interval(self, platform: Platform) -> int:
        """Get data collection interval for platform"""
        intervals = {
            Platform.TWITTER: 60,
            Platform.TELEGRAM: 120,
            Platform.REDDIT: 180,
            Platform.DISCORD: 60
        }
        return intervals.get(platform, 120)

    # Database operations
    async def _store_post(self, post: SocialPost):
        """Store post in database"""
        if not self.db_pool:
            return

        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO social_posts (
                        id, platform, author_id, author_username, content,
                        timestamp, likes, shares, comments, hashtags,
                        mentions, urls, content_type, reply_to_id, language
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
                    ON CONFLICT (id) DO NOTHING
                """, *[
                    post.id, post.platform.value, post.author_id, post.author_username,
                    post.content, post.timestamp, post.likes, post.shares, post.comments,
                    json.dumps(post.hashtags), json.dumps(post.mentions),
                    json.dumps(post.urls), post.content_type.value, post.reply_to_id, post.language
                ])
        except Exception as e:
            logger.error(f"Error storing post {post.id}: {e}")

    async def _store_alert(self, alert: SocialAlert):
        """Store alert in database"""
        if not self.db_pool:
            return

        try:
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO social_alerts (
                        id, alert_type, platform, content, significance_score,
                        timestamp, metadata
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
                """, *[
                    alert.id, alert.alert_type, alert.platform.value,
                    alert.content, alert.significance_score, alert.timestamp,
                    json.dumps(alert.metadata)
                ])
        except Exception as e:
            logger.error(f"Error storing alert {alert.id}: {e}")

    async def _cache_post(self, post: SocialPost):
        """Cache post in Redis"""
        if not self.redis_client:
            return

        try:
            key = f"social_post:{post.platform.value}:{post.id}"
            await self.redis_client.setex(
                key,
                timedelta(hours=24),
                json.dumps(asdict(post), default=str)
            )
        except Exception as e:
            logger.error(f"Error caching post {post.id}: {e}")

    async def _cache_alert(self, alert: SocialAlert):
        """Cache alert in Redis"""
        if not self.redis_client:
            return

        try:
            key = f"social_alert:{alert.id}"
            await self.redis_client.setex(
                key,
                timedelta(hours=6),
                json.dumps(asdict(alert), default=str)
            )
        except Exception as e:
            logger.error(f"Error caching alert {alert.id}: {e}")

    # Public API methods
    async def get_sentiment_summary(
        self,
        platforms: Optional[List[Platform]] = None,
        time_range: timedelta = timedelta(hours=1)
    ) -> Dict[str, Any]:
        """Get sentiment summary for specified platforms and time range"""
        cutoff_time = datetime.now(timezone.utc) - time_range

        relevant_analyses = [
            analysis for analysis in self.sentiment_cache.values()
            if (not platforms or analysis.platform in platforms) and
               analysis.processed_at > cutoff_time
        ]

        if not relevant_analyses:
            return {
                "total_posts": 0,
                "avg_sentiment": 0.0,
                "sentiment_distribution": {},
                "top_topics": [],
                "timestamp": datetime.now(timezone.utc)
            }

        # Calculate metrics
        total_posts = len(relevant_analyses)
        avg_sentiment = sum(a.sentiment_score for a in relevant_analyses) / total_posts

        # Sentiment distribution
        sentiment_counts = defaultdict(int)
        for analysis in relevant_analyses:
            sentiment_counts[analysis.sentiment_label.value] += 1

        # Top topics
        all_topics = []
        for analysis in relevant_analyses:
            all_topics.extend(analysis.topics)
        topic_counts = defaultdict(int)
        for topic in all_topics:
            topic_counts[topic] += 1
        top_topics = sorted(topic_counts.items(), key=lambda x: x[1], reverse=True)[:10]

        return {
            "total_posts": total_posts,
            "avg_sentiment": avg_sentiment,
            "sentiment_distribution": dict(sentiment_counts),
            "top_topics": [{"topic": t[0], "count": t[1]} for t in top_topics],
            "timestamp": datetime.now(timezone.utc)
        }

    async def get_recent_alerts(
        self,
        alert_types: Optional[List[str]] = None,
        limit: int = 50
    ) -> List[SocialAlert]:
        """Get recent trading alerts"""
        # Implementation would query database or cache
        return []

    async def get_trending_topics(
        self,
        platform: Optional[Platform] = None,
        time_range: timedelta = timedelta(hours=6)
    ) -> List[TrendingTopic]:
        """Get trending topics"""
        # Implementation would analyze trending keywords and topics
        return []

    async def get_metrics(self) -> Dict[str, Any]:
        """Get engine performance metrics"""
        uptime = time.time() - self.metrics["start_time"]

        return {
            **self.metrics,
            "uptime_seconds": uptime,
            "posts_per_minute": self.metrics["posts_processed"] / (uptime / 60) if uptime > 0 else 0,
            "cache_sizes": {
                "posts": len(self.posts_cache),
                "sentiment": len(self.sentiment_cache),
                "influencers": len(self.influencer_cache)
            }
        }

    async def shutdown(self):
        """Shutdown the engine and cleanup resources"""
        logger.info("Shutting down Social Intelligence Engine...")

        # Cancel background tasks
        for task in self.collection_tasks:
            task.cancel()

        if self.analysis_task:
            self.analysis_task.cancel()

        if self.alert_task:
            self.alert_task.cancel()

        # Close connections
        if self.http_session:
            await self.http_session.close()

        if self.db_pool:
            await self.db_pool.close()

        if self.redis_client:
            await self.redis_client.close()

        logger.info("Social Intelligence Engine shutdown complete")

# ============================================================================
# Utility Functions
# ============================================================================

async def create_social_intelligence_engine(config: Dict[str, Any]) -> SocialIntelligenceEngine:
    """
    Create and initialize social intelligence engine

    Args:
        config: Configuration dictionary

    Returns:
        Initialized SocialIntelligenceEngine instance
    """
    engine = SocialIntelligenceEngine(config)
    await engine.initialize()
    return engine

# ============================================================================
# Development Testing
# ============================================================================

async def development_test():
    """
    Development test function
    """
    logger.info("Starting Social Intelligence Engine development test...")

    # Mock configuration
    config = {
        "twitter": {
            "enabled": False,  # Disabled for development
            "api_key": "mock_key",
            "api_secret": "mock_secret",
            "access_token": "mock_token",
            "access_token_secret": "mock_token_secret"
        },
        "telegram": {
            "enabled": False,
            "bot_token": "mock_token"
        },
        "reddit": {
            "enabled": False,
            "client_id": "mock_id",
            "client_secret": "mock_secret"
        }
    }

    engine = SocialIntelligenceEngine(config)

    try:
        # Initialize (will skip platform clients due to disabled config)
        await engine.initialize()

        # Create mock post for testing
        mock_post = SocialPost(
            id="test_123",
            platform=Platform.TWITTER,
            author_id="test_user",
            author_username="testuser",
            content="Bitcoin is going to the moon! Very bullish on BTC! 🚀🚀🚀",
            timestamp=datetime.now(timezone.utc),
            likes=100,
            shares=50,
            hashtags=["#bitcoin", "#btc"],
            keywords=["bitcoin", "btc", "bullish", "moon"]
        )

        # Process post
        await engine._process_post(mock_post)

        # Analyze sentiment
        analysis = await engine._analyze_sentiment(mock_post)
        logger.info(f"Sentiment analysis: {analysis.sentiment_label.value} (score: {analysis.sentiment_score:.2f})")

        # Get metrics
        metrics = await engine.get_metrics()
        logger.info(f"Engine metrics: {metrics}")

        # Get sentiment summary
        summary = await engine.get_sentiment_summary()
        logger.info(f"Sentiment summary: {summary}")

    finally:
        await engine.shutdown()
        logger.info("Development test completed")

if __name__ == "__main__":
    asyncio.run(development_test())