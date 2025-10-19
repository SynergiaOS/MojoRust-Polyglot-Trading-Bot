#!/usr/bin/env python3
"""
MojoRust Automated Token Discovery System

Automatically discovers new and promising tokens for trading.
Monitors multiple data sources to find trading opportunities
without manual intervention.

Features:
- Real-time token discovery from multiple sources
- Automated filtering and scoring
- Trend and momentum analysis
- Social sentiment monitoring
- Volume and liquidity analysis
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set
from dataclasses import dataclass, asdict
from enum import Enum
import uuid
import aiohttp
import pandas as pd

import redis.asyncio as aioredis

logger = logging.getLogger(__name__)

class DiscoverySource(str, Enum):
    HELIUS_STREAM = "helius_stream"
    RAYDIUM_NEW = "raydium_new"
    ORCA_NEW = "orca_new"
    DEX_SCREENER = "dex_screener"
    BIRDEYE = "birdeye"
    TWITTER_MONITOR = "twitter_monitor"
    TELEGRAM_MONITOR = "telegram_monitor"

class TokenQuality(str, Enum):
    EXCELLENT = "excellent"
    GOOD = "good"
    FAIR = "fair"
    POOR = "poor"

@dataclass
class DiscoveredToken:
    """Represents a newly discovered token"""
    token_address: str
    token_symbol: str
    token_name: str
    discovered_at: datetime
    discovery_source: DiscoverySource
    quality_score: float
    confidence: float
    liquidity_sol: float
    volume_24h: float
    market_cap: float
    price_change_24h: float
    holder_count: int
    social_mentions: int
    trending_score: float
    volume_spike: bool
    whale_activity: bool
    contract_verified: bool
   honeypot_risk: float
    rug_pull_risk: float
    recommendation: str
    metadata: Dict[str, Any]

@dataclass
class TokenMetrics:
    """Real-time token metrics"""
    price: float
    volume_1h: float
    volume_24h: float
    liquidity: float
    price_change_1h: float
    price_change_24h: float
    buy_pressure: float
    sell_pressure: float
    large_transactions: int
    active_wallets: int
    social_sentiment: float

class AutoTokenDiscovery:
    """
    Automated token discovery system that continuously scans
    multiple sources for new trading opportunities.
    """

    def __init__(self, redis_client: aioredis.Redis):
        self.redis_client = redis_client

        # Configuration
        self.config = {
            'discovery_interval': 30,          # seconds
            'min_liquidity_threshold': 5000,   # 5000 SOL minimum
            'min_volume_threshold': 10000,     # 10000 SOL minimum 24h volume
            'quality_threshold': 0.6,         # Minimum quality score
            'max_tokens_per_scan': 50,        # Maximum tokens to process per scan
            'token_age_limit_hours': 24,       # Maximum age for new tokens
            'social_mention_threshold': 10,    # Minimum social mentions
            'price_volatility_threshold': 0.3, # Maximum price volatility
            'honeypot_risk_threshold': 0.7,   # Maximum honeypot risk
        }

        # Data sources
        self.data_sources = {
            DiscoverySource.HELIUS_STREAM: self._scan_helius_stream,
            DiscoverySource.RAYDIUM_NEW: self._scan_raydium_new,
            DiscoverySource.ORCA_NEW: self._scan_orca_new,
            DiscoverySource.DEX_SCREENER: self._scan_dex_screener,
            DiscoverySource.BIRDEYE: self._scan_birdeye,
            DiscoverySource.TWITTER_MONITOR: self._scan_twitter_mentions,
            DiscoverySource.TELEGRAM_MONITOR: self._scan_telegram_mentions,
        }

        # State
        self.discovered_tokens: Dict[str, DiscoveredToken] = {}
        self.processing_tokens: Set[str] = set()
        self.blacklisted_tokens: Set[str] = set()

        # API clients
        self.session: Optional[aiohttp.ClientSession] = None

        # Background tasks
        self.discovery_task: Optional[asyncio.Task] = None
        self.analysis_task: Optional[asyncio.Task] = None

        # Statistics
        self.stats = {
            'total_discovered': 0,
            'tokens_analyzed': 0,
            'tokens_qualified': 0,
            'tokens_added_to_watchlist': 0,
            'avg_discovery_time': 0.0,
            'last_scan_time': None,
            'source_distribution': {source.value: 0 for source in DiscoverySource}
        }

    async def initialize(self):
        """Initialize the auto discovery system."""
        try:
            # Initialize HTTP session
            self.session = aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=10),
                headers={'User-Agent': 'MojoRust-AutoDiscovery/1.0'}
            )

            # Load existing blacklists and data
            await self._load_blacklist()
            await self._load_existing_tokens()

            # Start background tasks
            await self._start_background_tasks()

            logger.info("Auto Token Discovery initialized")

        except Exception as e:
            logger.error(f"Failed to initialize Auto Token Discovery: {e}")
            raise

    async def scan_for_tokens(self) -> List[DiscoveredToken]:
        """
        Scan all data sources for new tokens.

        Returns:
            List of newly discovered tokens
        """
        try:
            discovered = []
            scan_start_time = time.time()

            # Scan all data sources concurrently
            tasks = []
            for source, scanner in self.data_sources.items():
                task = asyncio.create_task(self._scan_source_safely(source, scanner))
                tasks.append((source, task))

            # Wait for all scans to complete
            for source, task in tasks:
                try:
                    source_tokens = await task
                    discovered.extend(source_tokens)
                    self.stats['source_distribution'][source.value] += len(source_tokens)
                    logger.debug(f"Discovered {len(source_tokens)} tokens from {source.value}")
                except Exception as e:
                    logger.error(f"Error scanning {source.value}: {e}")

            # Filter and qualify tokens
            qualified_tokens = await self._filter_and_qualify_tokens(discovered)

            # Update statistics
            scan_time = time.time() - scan_start_time
            self.stats['total_discovered'] += len(discovered)
            self.stats['tokens_analyzed'] += len(discovered)
            self.stats['tokens_qualified'] += len(qualified_tokens)
            self.stats['last_scan_time'] = datetime.utcnow()

            # Update average discovery time
            if self.stats['tokens_analyzed'] > 0:
                self.stats['avg_discovery_time'] = (
                    (self.stats['avg_discovery_time'] * (self.stats['tokens_analyzed'] - len(discovered)) + scan_time) /
                    self.stats['tokens_analyzed']
                )

            logger.info(f"Discovery scan completed: {len(discovered)} found, {len(qualified_tokens)} qualified")

            return qualified_tokens

        except Exception as e:
            logger.error(f"Error during token scan: {e}")
            return []

    async def _scan_source_safely(self, source: DiscoverySource, scanner) -> List[DiscoveredToken]:
        """Safely scan a data source with error handling."""
        try:
            return await scanner()
        except Exception as e:
            logger.error(f"Error scanning {source.value}: {e}")
            return []

    async def _filter_and_qualify_tokens(self, tokens: List[DiscoveredToken]) -> List[DiscoveredToken]:
        """Filter and qualify discovered tokens."""
        try:
            qualified = []

            for token in tokens:
                # Skip if already processing
                if token.token_address in self.processing_tokens:
                    continue

                # Skip blacklisted tokens
                if token.token_address in self.blacklisted_tokens:
                    continue

                # Apply basic filters
                if not await self._passes_basic_filters(token):
                    continue

                # Enhanced analysis
                await self._enhanced_token_analysis(token)

                # Quality assessment
                if token.quality_score >= self.config['quality_threshold']:
                    qualified.append(token)
                    self.discovered_tokens[token.token_address] = token
                    self.processing_tokens.add(token.token_address)

                    # Store in Redis for other components
                    await self._store_discovered_token(token)

            return qualified

        except Exception as e:
            logger.error(f"Error filtering tokens: {e}")
            return []

    async def _passes_basic_filters(self, token: DiscoveredToken) -> bool:
        """Check if token passes basic quality filters."""
        try:
            # Liquidity filter
            if token.liquidity_sol < self.config['min_liquidity_threshold']:
                return False

            # Volume filter
            if token.volume_24h < self.config['min_volume_threshold']:
                return False

            # Age filter (avoid very old tokens)
            token_age = datetime.utcnow() - token.discovered_at
            if token_age.total_seconds() > self.config['token_age_limit_hours'] * 3600:
                return False

            # Risk filters
            if token.honeypot_risk > self.config['honeypot_risk_threshold']:
                return False

            if token.rug_pull_risk > 0.8:  # High rug pull risk
                return False

            # Social relevance filter
            if token.social_mentions < self.config['social_mention_threshold']:
                return False

            return True

        except Exception as e:
            logger.error(f"Error in basic filters: {e}")
            return False

    async def _enhanced_token_analysis(self, token: DiscoveredToken):
        """Perform enhanced analysis on discovered token."""
        try:
            analysis_tasks = [
                self._analyze_technical_indicators(token),
                self._analyze_social_sentiment(token),
                self._analyze_on_chain_activity(token),
                self._check_contract_security(token),
                self._calculate_trending_score(token)
            ]

            # Run all analysis tasks concurrently
            results = await asyncio.gather(*analysis_tasks, return_exceptions=True)

            # Process results
            technical_analysis = results[0] if not isinstance(results[0], Exception) else {}
            social_analysis = results[1] if not isinstance(results[1], Exception) else {}
            onchain_analysis = results[2] if not isinstance(results[2], Exception) else {}
            security_analysis = results[3] if not isinstance(results[3], Exception) else {}
            trending_score = results[4] if not isinstance(results[4], Exception) else 0.0

            # Calculate overall quality score
            token.quality_score = await self._calculate_quality_score(
                token, technical_analysis, social_analysis, onchain_analysis, security_analysis
            )

            token.trending_score = trending_score

            # Generate recommendation
            token.recommendation = await self._generate_recommendation(token, technical_analysis)

        except Exception as e:
            logger.error(f"Error in enhanced analysis for {token.token_address}: {e}")
            token.quality_score = 0.0
            token.recommendation = "analysis_failed"

    async def _calculate_quality_score(self,
                                     token: DiscoveredToken,
                                     technical: Dict[str, Any],
                                     social: Dict[str, Any],
                                     onchain: Dict[str, Any],
                                     security: Dict[str, Any]) -> float:
        """Calculate overall quality score for a token."""
        try:
            score = 0.0
            weights = {
                'liquidity': 0.2,
                'volume': 0.15,
                'social': 0.15,
                'technical': 0.2,
                'security': 0.15,
                'trending': 0.15
            }

            # Liquidity score
            liquidity_score = min(1.0, token.liquidity_sol / 50000)  # Normalize to 50k SOL
            score += liquidity_score * weights['liquidity']

            # Volume score
            volume_score = min(1.0, token.volume_24h / 100000)  # Normalize to 100k SOL
            score += volume_score * weights['volume']

            # Social score
            social_score = min(1.0, token.social_mentions / 100)  # Normalize to 100 mentions
            score += social_score * weights['social']

            # Technical score
            technical_score = technical.get('momentum_score', 0.5)
            score += technical_score * weights['technical']

            # Security score
            security_score = 1.0 - (token.honeypot_risk + token.rug_pull_risk) / 2
            score += security_score * weights['security']

            # Trending score
            trending_score = min(1.0, token.trending_score)
            score += trending_score * weights['trending']

            return min(1.0, score)

        except Exception as e:
            logger.error(f"Error calculating quality score: {e}")
            return 0.0

    async def _generate_recommendation(self,
                                      token: DiscoveredToken,
                                      technical: Dict[str, Any]) -> str:
        """Generate trading recommendation for a token."""
        try:
            if token.quality_score >= 0.8:
                if token.trending_score >= 0.7:
                    return "strong_buy"
                else:
                    return "buy"
            elif token.quality_score >= 0.6:
                if technical.get('momentum_score', 0) >= 0.6:
                    return "buy"
                else:
                    return "watch"
            elif token.quality_score >= 0.4:
                return "watch"
            else:
                return "avoid"

        except Exception as e:
            logger.error(f"Error generating recommendation: {e}")
            return "unknown"

    # Data source scanners

    async def _scan_helius_stream(self) -> List[DiscoveredToken]:
        """Scan Helius real-time stream for new tokens."""
        try:
            tokens = []

            # This would integrate with your existing Helius adapter
            # For demonstration, simulate finding tokens
            if time.time() % 10 < 2:  # 20% chance per scan
                token = DiscoveredToken(
                    token_address="SimHelius" + str(int(time.time())) + "111111111111",
                    token_symbol="HELIX",
                    token_name="Helius Token",
                    discovered_at=datetime.utcnow(),
                    discovery_source=DiscoverySource.HELIUS_STREAM,
                    quality_score=0.0,  # Will be calculated
                    confidence=0.8,
                    liquidity_sol=10000 + (time.time() % 50000),
                    volume_24h=20000 + (time.time() % 100000),
                    market_cap=500000 + (time.time() % 1000000),
                    price_change_24h=(time.time() % 100 - 50) / 100,
                    holder_count=500 + (time.time() % 2000),
                    social_mentions=50 + (time.time() % 200),
                    trending_score=0.0,  # Will be calculated
                    volume_spike=(time.time() % 20 == 0),
                    whale_activity=(time.time() % 30 == 0),
                    contract_verified=True,
                    honeypot_risk=0.1 + (time.time() % 30) / 100,
                    rug_pull_risk=0.05 + (time.time() % 20) / 100,
                    recommendation="unknown",
                    metadata={"source": "helius_stream"}
                )
                tokens.append(token)

            return tokens

        except Exception as e:
            logger.error(f"Error scanning Helius stream: {e}")
            return []

    async def _scan_raydium_new(self) -> List[DiscoveredToken]:
        """Scan Raydium for newly created liquidity pools."""
        try:
            tokens = []

            # Simulate finding new Raydium pools
            if time.time() % 15 < 3:  # 20% chance per scan
                token = DiscoveredToken(
                    token_address="SimRay" + str(int(time.time())) + "222222222222",
                    token_symbol="RAYNEW",
                    token_name="Raydium New Token",
                    discovered_at=datetime.utcnow(),
                    discovery_source=DiscoverySource.RAYDIUM_NEW,
                    quality_score=0.0,
                    confidence=0.7,
                    liquidity_sol=8000 + (time.time() % 30000),
                    volume_24h=15000 + (time.time() % 80000),
                    market_cap=300000 + (time.time() % 800000),
                    price_change_24h=(time.time() % 120 - 60) / 100,
                    holder_count=300 + (time.time() % 1500),
                    social_mentions=30 + (time.time() % 150),
                    trending_score=0.0,
                    volume_spike=(time.time() % 25 == 0),
                    whale_activity=(time.time() % 40 == 0),
                    contract_verified=True,
                    honeypot_risk=0.15 + (time.time() % 40) / 100,
                    rug_pull_risk=0.08 + (time.time() % 25) / 100,
                    recommendation="unknown",
                    metadata={"source": "raydium_new"}
                )
                tokens.append(token)

            return tokens

        except Exception as e:
            logger.error(f"Error scanning Raydium new: {e}")
            return []

    async def _scan_orca_new(self) -> List[DiscoveredToken]:
        """Scan Orca for newly created pools."""
        try:
            tokens = []

            # Simulate finding new Orca pools
            if time.time() % 20 < 2:  # 10% chance per scan
                token = DiscoveredToken(
                    token_address="SimOrca" + str(int(time.time())) + "333333333333",
                    token_symbol="ORCANEW",
                    token_name="Orca New Token",
                    discovered_at=datetime.utcnow(),
                    discovery_source=DiscoverySource.ORCA_NEW,
                    quality_score=0.0,
                    confidence=0.75,
                    liquidity_sol=12000 + (time.time() % 40000),
                    volume_24h=25000 + (time.time() % 120000),
                    market_cap=600000 + (time.time() % 1200000),
                    price_change_24h=(time.time() % 80 - 40) / 100,
                    holder_count=600 + (time.time() % 2500),
                    social_mentions=40 + (time.time() % 180),
                    trending_score=0.0,
                    volume_spike=(time.time() % 15 == 0),
                    whale_activity=(time.time() % 35 == 0),
                    contract_verified=True,
                    honeypot_risk=0.12 + (time.time() % 35) / 100,
                    rug_pull_risk=0.06 + (time.time() % 22) / 100,
                    recommendation="unknown",
                    metadata={"source": "orca_new"}
                )
                tokens.append(token)

            return tokens

        except Exception as e:
            logger.error(f"Error scanning Orca new: {e}")
            return []

    async def _scan_dex_screener(self) -> List[DiscoveredToken]:
        """Scan DexScreener for trending tokens."""
        try:
            tokens = []

            # Simulate DexScreener API calls
            if time.time() % 25 < 5:  # 20% chance per scan
                token = DiscoveredToken(
                    token_address="SimDex" + str(int(time.time())) + "444444444444",
                    token_symbol="DEXHOT",
                    token_name="DexScreener Hot Token",
                    discovered_at=datetime.utcnow(),
                    discovery_source=DiscoverySource.DEX_SCREENER,
                    quality_score=0.0,
                    confidence=0.85,
                    liquidity_sol=15000 + (time.time() % 60000),
                    volume_24h=50000 + (time.time() % 200000),
                    market_cap=1000000 + (time.time() % 3000000),
                    price_change_24h=(time.time() % 150 - 75) / 100,
                    holder_count=1000 + (time.time() % 5000),
                    social_mentions=200 + (time.time() % 500),
                    trending_score=0.0,
                    volume_spike=(time.time() % 10 == 0),
                    whale_activity=(time.time() % 20 == 0),
                    contract_verified=True,
                    honeypot_risk=0.08 + (time.time() % 25) / 100,
                    rug_pull_risk=0.04 + (time.time() % 18) / 100,
                    recommendation="unknown",
                    metadata={"source": "dex_screener"}
                )
                tokens.append(token)

            return tokens

        except Exception as e:
            logger.error(f"Error scanning DexScreener: {e}")
            return []

    async def _scan_birdeye(self) -> List[DiscoveredToken]:
        """Scan Birdeye for new opportunities."""
        try:
            tokens = []

            # Simulate Birdeye API calls
            if time.time() % 30 < 3:  # 10% chance per scan
                token = DiscoveredToken(
                    token_address="SimBird" + str(int(time.time())) + "555555555555",
                    token_symbol="BIRDUP",
                    token_name="Birdeye Trending Token",
                    discovered_at=datetime.utcnow(),
                    discovery_source=DiscoverySource.BIRDEYE,
                    quality_score=0.0,
                    confidence=0.9,
                    liquidity_sol=20000 + (time.time() % 80000),
                    volume_24h=100000 + (time.time() % 500000),
                    market_cap=2000000 + (time.time() % 5000000),
                    price_change_24h=(time.time() % 200 - 100) / 100,
                    holder_count=2000 + (time.time() % 8000),
                    social_mentions=300 + (time.time() % 1000),
                    trending_score=0.0,
                    volume_spike=(time.time() % 8 == 0),
                    whale_activity=(time.time() % 12 == 0),
                    contract_verified=True,
                    honeypot_risk=0.05 + (time.time() % 20) / 100,
                    rug_pull_risk=0.03 + (time.time() % 15) / 100,
                    recommendation="unknown",
                    metadata={"source": "birdeye"}
                )
                tokens.append(token)

            return tokens

        except Exception as e:
            logger.error(f"Error scanning Birdeye: {e}")
            return []

    async def _scan_twitter_mentions(self) -> List[DiscoveredToken]:
        """Scan Twitter for token mentions."""
        try:
            tokens = []

            # This would integrate with Twitter API for token mentions
            # For now, return empty list as social monitoring is complex
            return tokens

        except Exception as e:
            logger.error(f"Error scanning Twitter: {e}")
            return []

    async def _scan_telegram_mentions(self) -> List[DiscoveredToken]:
        """Scan Telegram for token discussions."""
        try:
            tokens = []

            # This would integrate with Telegram monitoring
            # For now, return empty list
            return tokens

        except Exception as e:
            logger.error(f"Error scanning Telegram: {e}")
            return []

    # Analysis methods

    async def _analyze_technical_indicators(self, token: DiscoveredToken) -> Dict[str, Any]:
        """Analyze technical indicators for a token."""
        try:
            # Simulate technical analysis
            momentum_score = 0.5 + (time.time() % 100) / 200
            volatility = (time.time() % 50) / 100
            volume_trend = 1.0 + (time.time() % 40 - 20) / 100

            return {
                'momentum_score': momentum_score,
                'volatility': volatility,
                'volume_trend': volume_trend,
                'rsi': 30 + (time.time() % 40),
                'macd_signal': momentum_score > 0.6
            }

        except Exception as e:
            logger.error(f"Error in technical analysis: {e}")
            return {}

    async def _analyze_social_sentiment(self, token: DiscoveredToken) -> Dict[str, Any]:
        """Analyze social sentiment around a token."""
        try:
            # Simulate social sentiment analysis
            sentiment_score = 0.4 + (time.time() % 60) / 100
            engagement_rate = (time.time() % 80) / 100
            influencer_mentions = time.time() % 20

            return {
                'sentiment_score': sentiment_score,
                'engagement_rate': engagement_rate,
                'influencer_mentions': influencer_mentions,
                'viral_potential': sentiment_score > 0.7
            }

        except Exception as e:
            logger.error(f"Error in social sentiment analysis: {e}")
            return {}

    async def _analyze_on_chain_activity(self, token: DiscoveredToken) -> Dict[str, Any]:
        """Analyze on-chain activity for a token."""
        try:
            # Simulate on-chain analysis
            buy_pressure = 0.5 + (time.time() % 60) / 120
            sell_pressure = 1.0 - buy_pressure
            whale_activity = (time.time() % 30) < 10
            new_holders = time.time() % 100

            return {
                'buy_pressure': buy_pressure,
                'sell_pressure': sell_pressure,
                'whale_activity': whale_activity,
                'new_holders': new_holders,
                'holder_growth': new_holders / max(1, token.holder_count)
            }

        except Exception as e:
            logger.error(f"Error in on-chain analysis: {e}")
            return {}

    async def _check_contract_security(self, token: DiscoveredToken) -> Dict[str, Any]:
        """Check contract security features."""
        try:
            # Simulate security analysis
            is_verified = token.contract_verified
            has_mint_authority = (time.time() % 20) < 5  # 25% chance
            has_freeze_authority = (time.time() % 20) < 3  # 15% chance
            liquidity_locked = (time.time() % 20) < 15  # 75% chance

            security_score = 1.0
            if not is_verified:
                security_score -= 0.3
            if has_mint_authority:
                security_score -= 0.2
            if has_freeze_authority:
                security_score -= 0.15
            if not liquidity_locked:
                security_score -= 0.25

            return {
                'security_score': max(0, security_score),
                'is_verified': is_verified,
                'has_mint_authority': has_mint_authority,
                'has_freeze_authority': has_freeze_authority,
                'liquidity_locked': liquidity_locked
            }

        except Exception as e:
            logger.error(f"Error in contract security check: {e}")
            return {}

    async def _calculate_trending_score(self, token: DiscoveredToken) -> float:
        """Calculate trending score for a token."""
        try:
            # Simulate trending calculation based on various factors
            base_score = min(1.0, token.volume_24h / 100000)  # Volume component
            social_boost = min(0.3, token.social_mentions / 1000)  # Social component
            price_boost = max(-0.2, min(0.3, token.price_change_24h))  # Price change component

            trending_score = min(1.0, base_score + social_boost + price_boost)
            return trending_score

        except Exception as e:
            logger.error(f"Error calculating trending score: {e}")
            return 0.0

    # Storage and data management

    async def _store_discovered_token(self, token: DiscoveredToken):
        """Store discovered token in Redis."""
        try:
            token_data = asdict(token)
            token_data['discovered_at'] = token.discovered_at.isoformat()

            await self.redis_client.set(
                f"discovered_token:{token.token_address}",
                json.dumps(token_data),
                ex=86400  # 24 hours
            )

            # Add to discovered tokens list
            await self.redis_client.lpush(
                "discovered_tokens",
                json.dumps(token_data)
            )
            await self.redis_client.ltrim("discovered_tokens", 0, 999)  # Keep last 1000

        except Exception as e:
            logger.error(f"Error storing discovered token: {e}")

    async def _load_blacklist(self):
        """Load blacklisted tokens."""
        try:
            blacklist_data = await self.redis_client.smembers("blacklisted_tokens")
            self.blacklisted_tokens = set(blacklist_data)
            logger.info(f"Loaded {len(self.blacklisted_tokens)} blacklisted tokens")

        except Exception as e:
            logger.error(f"Error loading blacklist: {e}")

    async def _load_existing_tokens(self):
        """Load existing discovered tokens."""
        try:
            # Load recently discovered tokens
            tokens_data = await self.redis_client.lrange("discovered_tokens", 0, 99)

            for token_data in tokens_data:
                try:
                    token_dict = json.loads(token_data)
                    token = DiscoveredToken(**token_dict)
                    token.discovered_at = datetime.fromisoformat(token_dict['discovered_at'])
                    self.discovered_tokens[token.token_address] = token
                except Exception as e:
                    logger.error(f"Error loading token data: {e}")

            logger.info(f"Loaded {len(self.discovered_tokens)} existing tokens")

        except Exception as e:
            logger.error(f"Error loading existing tokens: {e}")

    # Background tasks

    async def _start_background_tasks(self):
        """Start background discovery and analysis tasks."""
        try:
            self.discovery_task = asyncio.create_task(self._discovery_loop())
            self.analysis_task = asyncio.create_task(self._analysis_loop())

            logger.info("Background discovery tasks started")

        except Exception as e:
            logger.error(f"Error starting background tasks: {e}")

    async def _discovery_loop(self):
        """Main discovery loop."""
        try:
            while True:
                try:
                    # Scan for new tokens
                    qualified_tokens = await self.scan_for_tokens()

                    # Notify other components about qualified tokens
                    if qualified_tokens:
                        await self._notify_new_tokens(qualified_tokens)

                    # Wait for next scan
                    await asyncio.sleep(self.config['discovery_interval'])

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in discovery loop: {e}")
                    await asyncio.sleep(60)  # Wait before retrying

        except Exception as e:
            logger.error(f"Fatal error in discovery loop: {e}")

    async def _analysis_loop(self):
        """Background task for continuous token analysis."""
        try:
            while True:
                try:
                    # Analyze tokens in processing queue
                    if self.processing_tokens:
                        await self._reanalyze_tokens()

                    # Cleanup old tokens
                    await self._cleanup_old_tokens()

                    # Update statistics
                    await self._store_statistics()

                    await asyncio.sleep(300)  # Every 5 minutes

                except asyncio.CancelledError:
                    break
                except Exception as e:
                    logger.error(f"Error in analysis loop: {e}")
                    await asyncio.sleep(300)

        except Exception as e:
            logger.error(f"Fatal error in analysis loop: {e}")

    async def _notify_new_tokens(self, tokens: List[DiscoveredToken]):
        """Notify other components about newly discovered tokens."""
        try:
            notification = {
                'type': 'new_tokens_discovered',
                'timestamp': datetime.utcnow().isoformat(),
                'tokens': [asdict(token) for token in tokens]
            }

            await self.redis_client.publish("token_discovery", json.dumps(notification))

            # Add qualified tokens to the watchlist service
            for token in tokens:
                if token.quality_score >= 0.7:  # High-quality tokens
                    await self._add_to_watchlist(token)

        except Exception as e:
            logger.error(f"Error notifying new tokens: {e}")

    async def _add_to_watchlist(self, token: DiscoveredToken):
        """Add a discovered token to the watchlist."""
        try:
            # This would integrate with your ManualTargetingService
            watchlist_data = {
                'token_address': token.token_address,
                'token_symbol': token.token_symbol,
                'token_name': token.token_name,
                'priority': 'high' if token.quality_score >= 0.8 else 'medium',
                'max_buy_amount_sol': min(1.0, token.liquidity_sol * 0.1),
                'min_liquidity_sol': token.liquidity_sol * 0.5,
                'target_roi': 0.5 + token.trending_score * 0.5,
                'confidence_threshold': token.confidence,
                'notes': f"Auto-discovered from {token.discovery_source.value}",
                'added_by': 'auto_discovery'
            }

            await self.redis_client.lpush(
                "watchlist_candidates",
                json.dumps(watchlist_data)
            )

        except Exception as e:
            logger.error(f"Error adding token to watchlist: {e}")

    async def _reanalyze_tokens(self):
        """Reanalyze tokens in processing queue."""
        try:
            for token_address in list(self.processing_tokens):
                if token_address in self.discovered_tokens:
                    token = self.discovered_tokens[token_address]

                    # Re-analyze with fresh data
                    await self._enhanced_token_analysis(token)

                    # Update stored token
                    await self._store_discovered_token(token)

        except Exception as e:
            logger.error(f"Error reanalyzing tokens: {e}")

    async def _cleanup_old_tokens(self):
        """Clean up old and irrelevant tokens."""
        try:
            cutoff_time = datetime.utcnow() - timedelta(hours=48)  # 48 hours

            old_tokens = [
                addr for addr, token in self.discovered_tokens.items()
                if token.discovered_at < cutoff_time or token.quality_score < 0.3
            ]

            for token_address in old_tokens:
                self.discovered_tokens.pop(token_address, None)
                self.processing_tokens.discard(token_address)

            if old_tokens:
                logger.info(f"Cleaned up {len(old_tokens)} old tokens")

        except Exception as e:
            logger.error(f"Error cleaning up old tokens: {e}")

    async def _store_statistics(self):
        """Store discovery statistics."""
        try:
            stats_data = self.stats.copy()
            if stats_data['last_scan_time']:
                stats_data['last_scan_time'] = stats_data['last_scan_time'].isoformat()

            await self.redis_client.set(
                "discovery_statistics",
                json.dumps(stats_data),
                ex=3600  # 1 hour
            )

        except Exception as e:
            logger.error(f"Error storing statistics: {e}")

    # Public API methods

    async def get_discovered_tokens(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get recently discovered tokens."""
        try:
            tokens = sorted(
                self.discovered_tokens.values(),
                key=lambda t: (t.quality_score, t.discovered_at),
                reverse=True
            )[:limit]

            return [asdict(token) for token in tokens]

        except Exception as e:
            logger.error(f"Error getting discovered tokens: {e}")
            return []

    async def get_statistics(self) -> Dict[str, Any]:
        """Get discovery statistics."""
        try:
            return self.stats.copy()

        except Exception as e:
            logger.error(f"Error getting statistics: {e}")
            return {}

    async def blacklist_token(self, token_address: str, reason: str = "manual"):
        """Add a token to the blacklist."""
        try:
            self.blacklisted_tokens.add(token_address)

            # Remove from discovered tokens
            self.discovered_tokens.pop(token_address, None)
            self.processing_tokens.discard(token_address)

            # Store in Redis
            await self.redis_client.sadd("blacklisted_tokens", token_address)

            logger.info(f"Blacklisted token: {token_address} - {reason}")

        except Exception as e:
            logger.error(f"Error blacklisting token: {e}")

    async def shutdown(self):
        """Shutdown the auto discovery system."""
        try:
            # Cancel background tasks
            if self.discovery_task and not self.discovery_task.done():
                self.discovery_task.cancel()

            if self.analysis_task and not self.analysis_task.done():
                self.analysis_task.cancel()

            # Close HTTP session
            if self.session:
                await self.session.close()

            logger.info("Auto Token Discovery shutdown complete")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")