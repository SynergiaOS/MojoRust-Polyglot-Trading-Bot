#!/usr/bin/env python3
"""
Enhanced PumpFun API orchestration module with Multi-Token Arbitrage Support

This module provides comprehensive Python coordination layer for PumpFun token data fetching,
enabling Mojo kernels to access token metadata, price history, and analytics through
async Python APIs with FFI bridges for sync Mojo interop. Enhanced with multi-token
arbitrage opportunity detection and orchestration capabilities.

Features:
- Token metadata and price history analysis
- Comprehensive filter checks (9 filters)
- Multi-token arbitrage opportunity detection
- Cross-DEX arbitrage opportunity identification
- Real-time opportunity submission to SandwichManager
- Synchronous FFI bridge for Mojo integration
- Batch processing capabilities
"""

import asyncio
import logging
import time
import hashlib
import json
import uuid
from typing import Dict, Any, List, Optional, Tuple, Union, Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum

# Import Jupiter API for price history
from jupiter_price_api import JupiterPriceAPI

# Try to import SandwichManager for arbitrage orchestration
try:
    from sandwich_manager import SandwichManager, ArbitrageType, ArbitrageOpportunity
    SANDWICH_MANAGER_AVAILABLE = True
except ImportError:
    SANDWICH_MANAGER_AVAILABLE = False
    logging.warning("SandwichManager not available. Arbitrage orchestration disabled.")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class TokenMetadata:
    """Token metadata for PumpFun analysis"""
    address: str
    name: str
    symbol: str
    decimals: int
    supply: float
    creator: str
    description: str
    image_url: str
    created_at: datetime
    initial_market_cap: float = 0.0
    bonding_curve: str = ""
    social_links: List[str] = None

    def __post_init__(self):
        if self.social_links is None:
            self.social_links = []


@dataclass
class FilterCheck:
    """Individual filter check result"""
    check_name: str
    passed: bool
    score: float
    reason: str
    metadata: Dict[str, Any] = None

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}


@dataclass
class BacktestResult:
    """Complete backtest result for a token"""
    token_address: str
    token_metadata: TokenMetadata
    filter_checks: List[FilterCheck]
    final_score: float
    recommendation: str
    simulated_profit_loss: float = 0.0
    max_drawdown: float = 0.0
    trade_count: int = 0
    win_rate: float = 0.0
    backtest_duration_hours: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            'token_address': self.token_address,
            'token_metadata': {
                'address': self.token_metadata.address,
                'name': self.token_metadata.name,
                'symbol': self.token_metadata.symbol,
                'decimals': self.token_metadata.decimals,
                'supply': self.token_metadata.supply,
                'creator': self.token_metadata.creator,
                'description': self.token_metadata.description,
                'image_url': self.token_metadata.image_url,
                'created_at': self.token_metadata.created_at.isoformat(),
                'initial_market_cap': self.token_metadata.initial_market_cap,
                'bonding_curve': self.token_metadata.bonding_curve,
                'social_links': self.token_metadata.social_links
            },
            'filter_checks': [
                {
                    'check_name': check.check_name,
                    'passed': check.passed,
                    'score': check.score,
                    'reason': check.reason,
                    'metadata': check.metadata
                } for check in self.filter_checks
            ],
            'final_score': self.final_score,
            'recommendation': self.recommendation,
            'simulated_profit_loss': self.simulated_profit_loss,
            'max_drawdown': self.max_drawdown,
            'trade_count': self.trade_count,
            'win_rate': self.win_rate,
            'backtest_duration_hours': self.backtest_duration_hours
        }


# Multi-Token Arbitrage Data Structures

@dataclass
class TokenPair:
    """Token pair for arbitrage analysis"""
    token_a: str
    token_b: str
    symbol_a: str
    symbol_b: str
    decimals_a: int
    decimals_b: int
    current_price: float = 0.0
    inverse_price: float = 0.0
    last_updated: datetime = field(default_factory=datetime.now)


@dataclass
class DEXPrice:
    """Price information from a specific DEX"""
    dex_name: str
    token_pair: TokenPair
    price: float
    liquidity: float
    volume_24h: float
    timestamp: datetime = field(default_factory=datetime.now)
    confidence_score: float = 1.0


@dataclass
class ArbitrageOpportunity:
    """Multi-token arbitrage opportunity"""
    id: str
    arbitrage_type: str  # triangular, cross_dex, flash_loan
    token_a: str
    token_b: str
    token_c: Optional[str]  # For triangular arbitrage
    dex_a: str
    dex_b: str
    dex_c: Optional[str]   # For triangular arbitrage

    # Financial data
    input_amount: float
    expected_output: float
    profit_estimate: float
    profit_percentage: float

    # Confidence metrics
    confidence_score: float
    urgency_score: float
    risk_score: float

    # Metadata
    detected_at: datetime = field(default_factory=datetime.now)
    expires_at: datetime = field(default_factory=lambda: datetime.now() + timedelta(minutes=5))
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        data = {
            'id': self.id,
            'arbitrage_type': self.arbitrage_type,
            'token_a': self.token_a,
            'token_b': self.token_b,
            'token_c': self.token_c,
            'dex_a': self.dex_a,
            'dex_b': self.dex_b,
            'dex_c': self.dex_c,
            'input_amount': self.input_amount,
            'expected_output': self.expected_output,
            'profit_estimate': self.profit_estimate,
            'profit_percentage': self.profit_percentage,
            'confidence_score': self.confidence_score,
            'urgency_score': self.urgency_score,
            'risk_score': self.risk_score,
            'detected_at': self.detected_at.isoformat(),
            'expires_at': self.expires_at.isoformat(),
            'metadata': self.metadata
        }
        return data


@dataclass
class ArbitrageAnalysis:
    """Complete arbitrage analysis for multiple tokens"""
    analyzed_tokens: List[str]
    token_pairs: List[TokenPair]
    detected_opportunities: List[ArbitrageOpportunity]
    total_potential_profit: float
    analysis_duration_ms: float
    timestamp: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        return {
            'analyzed_tokens': self.analyzed_tokens,
            'token_pairs': [
                {
                    'token_a': pair.token_a,
                    'token_b': pair.token_b,
                    'symbol_a': pair.symbol_a,
                    'symbol_b': pair.symbol_b,
                    'current_price': pair.current_price,
                    'last_updated': pair.last_updated.isoformat()
                } for pair in self.token_pairs
            ],
            'detected_opportunities': [opp.to_dict() for opp in self.detected_opportunities],
            'total_potential_profit': self.total_potential_profit,
            'analysis_duration_ms': self.analysis_duration_ms,
            'timestamp': self.timestamp.isoformat()
        }


class PumpFunAPI:
    """
    Enhanced PumpFun API orchestration class with Multi-Token Arbitrage Support

    Provides async methods for token metadata fetching, price history analysis,
    honeypot detection, social mentions, comprehensive backtesting, and multi-token
    arbitrage opportunity detection and orchestration.
    """

    def __init__(self, helius_api_key: str = "", quicknode_rpc: str = "",
                 sandwich_manager: Optional[SandwichManager] = None,
                 enable_arbitrage: bool = True):
        """
        Initialize PumpFun API with required service connections

        Args:
            helius_api_key: Helius API key for token metadata
            quicknode_rpc: QuickNode RPC URL for additional data
            sandwich_manager: SandwichManager instance for arbitrage orchestration
            enable_arbitrage: Enable arbitrage opportunity detection
        """
        self.helius_api_key = helius_api_key
        self.quicknode_rpc = quicknode_rpc
        self.jupiter_api = JupiterPriceAPI()
        self.sandwich_manager = sandwich_manager
        self.enable_arbitrage = enable_arbitrage and SANDWICH_MANAGER_AVAILABLE
        self.logger = logging.getLogger(__name__)

        # Rate limiting configuration
        self.requests_per_second = 10
        self.last_request_time = 0
        self.request_queue = asyncio.Queue()

        # Cache for token metadata and prices
        self.metadata_cache = {}
        self.price_history_cache = {}
        self.token_pair_cache = {}
        self.dex_price_cache = {}

        # Arbitrage configuration
        self.supported_dexes = [
            "raydium", "orca", "serum", "jupiter", "meteora", "aldrin"
        ]
        self.min_profit_threshold = 5.0  # Minimum profit in USD
        self.max_opportunity_age_minutes = 5
        self.max_concurrent_analyses = 3

        # Arbitrage statistics
        self.arbitrage_stats = {
            'opportunities_detected': 0,
            'opportunities_submitted': 0,
            'total_potential_profit': 0.0,
            'last_analysis_time': None
        }

        self.logger.info(f"Enhanced PumpFun API initialized (Arbitrage: {self.enable_arbitrage})")

    async def _rate_limit(self):
        """Simple rate limiting for API calls"""
        current_time = time.time()
        time_since_last = current_time - self.last_request_time
        min_interval = 1.0 / self.requests_per_second

        if time_since_last < min_interval:
            sleep_time = min_interval - time_since_last
            await asyncio.sleep(sleep_time)

        self.last_request_time = time.time()

    async def get_token_metadata(self, token_address: str) -> Optional[TokenMetadata]:
        """
        Fetch comprehensive token metadata from Helius

        Args:
            token_address: Token mint address

        Returns:
            TokenMetadata object or None if failed
        """
        await self._rate_limit()

        try:
            # Check cache first
            if token_address in self.metadata_cache:
                cached_metadata = self.metadata_cache[token_address]
                # Cache valid for 5 minutes
                if time.time() - cached_metadata['timestamp'] < 300:
                    return cached_metadata['data']

            # Mock implementation for now - replace with real Helius API call
            self.logger.info(f"Fetching metadata for token: {token_address}")

            # Simulate API delay
            await asyncio.sleep(0.1)

            # Generate mock metadata
            address_hash = abs(hash(token_address)) if token_address else 0

            metadata = TokenMetadata(
                address=token_address,
                name=f"PumpFun Token {address_hash % 10000}",
                symbol=f"PF{address_hash % 1000}",
                decimals=9,
                supply=float(1000000000 + (address_hash % 9000000000)),
                creator=f"Creator{address_hash % 1000}",
                description=f"Mock PumpFun token #{address_hash} for backtesting",
                image_url=f"https://example.com/token_{address_hash}.png",
                created_at=datetime.now() - timedelta(hours=address_hash % 168),
                initial_market_cap=float(10000 + (address_hash % 99000)),
                bonding_curve=f"curve_{address_hash % 1000}",
                social_links=[
                    f"https://twitter.com/pumpfun_{address_hash % 1000}",
                    f"https://t.me/pumpfun_{address_hash % 1000}"
                ]
            )

            # Cache the result
            self.metadata_cache[token_address] = {
                'data': metadata,
                'timestamp': time.time()
            }

            self.logger.info(f"Successfully fetched metadata for {token_address}")
            return metadata

        except Exception as e:
            self.logger.error(f"Failed to fetch token metadata for {token_address}: {e}")
            return None

    async def get_token_price_history(
        self,
        token_address: str,
        interval: str = "1m",
        hours_back: int = 24
    ) -> List[Dict[str, Any]]:
        """
        Fetch price history using Jupiter Price API

        Args:
            token_address: Token mint address
            interval: Time interval for data points
            hours_back: Number of hours of history to fetch

        Returns:
            List of price history data points
        """
        try:
            # Calculate timestamp range
            to_timestamp = int(time.time())
            from_timestamp = to_timestamp - (hours_back * 3600)

            # Get price history from Jupiter API
            price_history = await self.jupiter_api.get_price_history(
                token_address=token_address,
                interval=interval,
                from_timestamp=from_timestamp,
                to_timestamp=to_timestamp
            )

            self.logger.info(f"Fetched {len(price_history)} price points for {token_address}")
            return price_history

        except Exception as e:
            self.logger.error(f"Failed to fetch price history for {token_address}: {e}")
            return []

    async def check_honeypot_risk(self, token_address: str) -> FilterCheck:
        """
        Perform honeypot risk assessment

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with honeypot risk score
        """
        await self._rate_limit()

        try:
            self.logger.info(f"Checking honeypot risk for: {token_address}")

            # Mock honeypot detection logic
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate various risk factors
            liquidity_score = 0.3 + (address_hash % 700) / 1000.0
            holder_distribution_score = 0.4 + (address_hash % 600) / 1000.0
            contract_risk_score = 0.2 + (address_hash % 800) / 1000.0
            sell_tax_score = 0.5 + (address_hash % 500) / 1000.0

            # Calculate overall honeypot risk score (lower is better)
            honeypot_score = (liquidity_score + holder_distribution_score +
                             contract_risk_score + sell_tax_score) / 4

            # Determine if it's a honeypot
            is_honeypot = honeypot_score > 0.7
            passed = not is_honeypot

            reason = "Low honeypot risk detected" if passed else "High honeypot risk detected"

            return FilterCheck(
                check_name="honeypot_risk",
                passed=passed,
                score=1.0 - honeypot_score,  # Convert to pass score (higher is better)
                reason=reason,
                metadata={
                    "liquidity_score": liquidity_score,
                    "holder_distribution_score": holder_distribution_score,
                    "contract_risk_score": contract_risk_score,
                    "sell_tax_score": sell_tax_score,
                    "honeypot_score": honeypot_score
                }
            )

        except Exception as e:
            self.logger.error(f"Honeypot check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="honeypot_risk",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_social_mentions(self, token_address: str) -> FilterCheck:
        """
        Analyze social media mentions and sentiment

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with social analysis score
        """
        await self._rate_limit()

        try:
            self.logger.info(f"Checking social mentions for: {token_address}")

            # Mock social sentiment analysis
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate social metrics
            twitter_mentions = 10 + (address_hash % 990)
            telegram_members = 100 + (address_hash % 4900)
            reddit_posts = 5 + (address_hash % 95)
            overall_sentiment = 0.3 + (address_hash % 700) / 1000.0

            # Calculate social score
            mention_score = min(twitter_mentions / 100, 1.0) * 0.4
            community_score = min(telegram_members / 1000, 1.0) * 0.4
            sentiment_score = overall_sentiment * 0.2

            social_score = mention_score + community_score + sentiment_score

            # Determine if social presence is strong enough
            passed = social_score > 0.5

            reason = f"Social sentiment analysis complete (score: {social_score:.2f})"

            return FilterCheck(
                check_name="social_mentions",
                passed=passed,
                score=social_score,
                reason=reason,
                metadata={
                    "twitter_mentions": twitter_mentions,
                    "telegram_members": telegram_members,
                    "reddit_posts": reddit_posts,
                    "overall_sentiment": overall_sentiment,
                    "social_score": social_score
                }
            )

        except Exception as e:
            self.logger.error(f"Social mentions check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="social_mentions",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_liquidity_depth(self, token_address: str) -> FilterCheck:
        """
        Check liquidity depth and trading volume

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with liquidity analysis
        """
        await self._rate_limit()

        try:
            self.logger.info(f"Checking liquidity depth for: {token_address}")

            # Mock liquidity analysis
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate liquidity metrics
            total_liquidity = 1000 + (address_hash % 99000)  # In USD
            daily_volume = 500 + (address_hash % 45000)      # In USD
            liquidity_utilization = (address_hash % 800) / 1000.0

            # Calculate liquidity scores
            depth_score = min(total_liquidity / 50000, 1.0) * 0.5
            volume_score = min(daily_volume / 20000, 1.0) * 0.3
            utilization_score = (1.0 - abs(0.5 - liquidity_utilization)) * 0.2

            liquidity_score = depth_score + volume_score + utilization_score

            # Determine if liquidity is sufficient
            passed = liquidity_score > 0.4 and total_liquidity > 5000

            reason = f"Liquidity analysis complete (score: {liquidity_score:.2f})"

            return FilterCheck(
                check_name="liquidity_depth",
                passed=passed,
                score=liquidity_score,
                reason=reason,
                metadata={
                    "total_liquidity": total_liquidity,
                    "daily_volume": daily_volume,
                    "liquidity_utilization": liquidity_utilization,
                    "liquidity_score": liquidity_score
                }
            )

        except Exception as e:
            self.logger.error(f"Liquidity check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="liquidity_depth",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_price_volatility(self, token_address: str) -> FilterCheck:
        """
        Analyze price volatility and patterns

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with volatility analysis
        """
        try:
            self.logger.info(f"Checking price volatility for: {token_address}")

            # Get price history for volatility analysis
            price_history = await self.get_token_price_history(
                token_address,
                interval="5m",
                hours_back=6
            )

            if len(price_history) < 10:
                return FilterCheck(
                    check_name="price_volatility",
                    passed=False,
                    score=0.0,
                    reason="Insufficient price history for volatility analysis"
                )

            # Calculate volatility metrics
            prices = [float(point.get('price', 0)) for point in price_history if point.get('price')]

            if len(prices) < 10:
                return FilterCheck(
                    check_name="price_volatility",
                    passed=False,
                    score=0.0,
                    reason="Valid price data insufficient"
                )

            # Calculate price changes
            price_changes = []
            for i in range(1, len(prices)):
                if prices[i-1] > 0:
                    change = (prices[i] - prices[i-1]) / prices[i-1]
                    price_changes.append(change)

            if not price_changes:
                return FilterCheck(
                    check_name="price_volatility",
                    passed=False,
                    score=0.0,
                    reason="Cannot calculate price changes"
                )

            # Calculate volatility (standard deviation of price changes)
            mean_change = sum(price_changes) / len(price_changes)
            variance = sum((x - mean_change) ** 2 for x in price_changes) / len(price_changes)
            volatility = variance ** 0.5

            # Score volatility (moderate volatility is good for trading)
            # Too low = boring, too high = risky
            optimal_volatility = 0.05  # 5% volatility is ideal
            volatility_score = 1.0 - abs(volatility - optimal_volatility) / optimal_volatility
            volatility_score = max(0, min(1, volatility_score))

            # Determine if volatility is acceptable
            passed = volatility_score > 0.3 and volatility < 0.2  # Less than 20% volatility

            reason = f"Price volatility analysis complete (score: {volatility_score:.2f}, volatility: {volatility:.2%})"

            return FilterCheck(
                check_name="price_volatility",
                passed=passed,
                score=volatility_score,
                reason=reason,
                metadata={
                    "volatility": volatility,
                    "mean_change": mean_change,
                    "price_points": len(prices),
                    "volatility_score": volatility_score
                }
            )

        except Exception as e:
            self.logger.error(f"Volatility check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="price_volatility",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_holder_distribution(self, token_address: str) -> FilterCheck:
        """
        Analyze token holder distribution

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with holder analysis
        """
        await self._rate_limit()

        try:
            self.logger.info(f"Checking holder distribution for: {token_address}")

            # Mock holder distribution analysis
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate holder metrics
            total_holders = 50 + (address_hash % 950)
            top_10_holders_percentage = 0.3 + (address_hash % 600) / 1000.0
            creator_holding_percentage = (address_hash % 300) / 1000.0

            # Calculate distribution scores
            holder_count_score = min(total_holders / 200, 1.0) * 0.4
            distribution_score = (1.0 - top_10_holders_percentage) * 0.4
            creator_score = (1.0 - creator_holding_percentage) * 0.2

            distribution_score_total = holder_count_score + distribution_score + creator_score

            # Determine if distribution is healthy
            passed = (distribution_score_total > 0.5 and
                     top_10_holders_percentage < 0.8 and
                     creator_holding_percentage < 0.3)

            reason = f"Holder distribution analysis complete (score: {distribution_score_total:.2f})"

            return FilterCheck(
                check_name="holder_distribution",
                passed=passed,
                score=distribution_score_total,
                reason=reason,
                metadata={
                    "total_holders": total_holders,
                    "top_10_holders_percentage": top_10_holders_percentage,
                    "creator_holding_percentage": creator_holding_percentage,
                    "distribution_score": distribution_score_total
                }
            )

        except Exception as e:
            self.logger.error(f"Holder distribution check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="holder_distribution",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_contract_security(self, token_address: str) -> FilterCheck:
        """
        Check contract security and audit status

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with security analysis
        """
        await self._rate_limit()

        try:
            self.logger.info(f"Checking contract security for: {token_address}")

            # Mock security analysis
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate security metrics
            is_verified = (address_hash % 10) != 0  # 90% are verified
            has_audit = (address_hash % 5) != 0     # 80% have audits
            vulnerability_score = (address_hash % 200) / 1000.0  # 0-0.2 range
            ownership_renounced = (address_hash % 4) == 0  # 25% have renounced ownership

            # Calculate security score
            verification_score = 1.0 if is_verified else 0.3
            audit_score = 0.8 if has_audit else 0.4
            vulnerability_score_clean = 1.0 - vulnerability_score
            ownership_score = 0.9 if ownership_renounced else 0.7

            security_score = (verification_score * 0.3 +
                            audit_score * 0.3 +
                            vulnerability_score_clean * 0.3 +
                            ownership_score * 0.1)

            # Determine if contract is secure enough
            passed = security_score > 0.6 and is_verified

            reason = f"Contract security analysis complete (score: {security_score:.2f})"

            return FilterCheck(
                check_name="contract_security",
                passed=passed,
                score=security_score,
                reason=reason,
                metadata={
                    "is_verified": is_verified,
                    "has_audit": has_audit,
                    "vulnerability_score": vulnerability_score,
                    "ownership_renounced": ownership_renounced,
                    "security_score": security_score
                }
            )

        except Exception as e:
            self.logger.error(f"Contract security check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="contract_security",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_market_cap_ranking(self, token_address: str) -> FilterCheck:
        """
        Check market cap ranking and growth potential

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with market cap analysis
        """
        try:
            self.logger.info(f"Checking market cap ranking for: {token_address}")

            # Get token metadata for market cap
            metadata = await self.get_token_metadata(token_address)
            if not metadata:
                return FilterCheck(
                    check_name="market_cap_ranking",
                    passed=False,
                    score=0.0,
                    reason="Cannot fetch token metadata"
                )

            # Mock market cap analysis
            market_cap = metadata.initial_market_cap
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate market cap ranking
            market_cap_rank = 1000 + (address_hash % 9000)
            market_cap_growth_24h = -0.1 + (address_hash % 300) / 1000.0  # -10% to +20%

            # Calculate market cap scores
            size_score = min(market_cap / 100000, 1.0) * 0.4  # Prefer reasonable size
            rank_score = max(0, 1.0 - (market_cap_rank - 1000) / 10000) * 0.3
            growth_score = max(0, market_cap_growth_24h * 5) * 0.3  # Positive growth bonus

            market_cap_score = size_score + rank_score + growth_score

            # Determine if market cap is acceptable
            passed = (market_cap_score > 0.4 and
                     1000 < market_cap < 1000000 and  # Between $1k and $1M
                     market_cap_rank < 5000)

            reason = f"Market cap analysis complete (score: {market_cap_score:.2f})"

            return FilterCheck(
                check_name="market_cap_ranking",
                passed=passed,
                score=market_cap_score,
                reason=reason,
                metadata={
                    "market_cap": market_cap,
                    "market_cap_rank": market_cap_rank,
                    "market_cap_growth_24h": market_cap_growth_24h,
                    "market_cap_score": market_cap_score
                }
            )

        except Exception as e:
            self.logger.error(f"Market cap check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="market_cap_ranking",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_trading_activity(self, token_address: str) -> FilterCheck:
        """
        Check recent trading activity and momentum

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with trading activity analysis
        """
        try:
            self.logger.info(f"Checking trading activity for: {token_address}")

            # Get price history for trading analysis
            price_history = await self.get_token_price_history(
                token_address,
                interval="1m",
                hours_back=2
            )

            if len(price_history) < 20:
                return FilterCheck(
                    check_name="trading_activity",
                    passed=False,
                    score=0.0,
                    reason="Insufficient trading history"
                )

            # Mock trading activity metrics
            address_hash = abs(hash(token_address)) if token_address else 0

            # Simulate trading metrics
            recent_trades = 50 + (address_hash % 450)
            unique_traders = 20 + (address_hash % 180)
            avg_trade_size = 100 + (address_hash % 900)
            buy_sell_ratio = 0.4 + (address_hash % 400) / 1000.0

            # Calculate activity scores
            volume_score = min(recent_trades / 200, 1.0) * 0.3
            diversity_score = min(unique_traders / 50, 1.0) * 0.2
            size_score = min(avg_trade_size / 500, 1.0) * 0.2
            momentum_score = buy_sell_ratio * 0.3

            activity_score = volume_score + diversity_score + size_score + momentum_score

            # Determine if trading activity is sufficient
            passed = (activity_score > 0.5 and
                     recent_trades > 30 and
                     unique_traders > 15)

            reason = f"Trading activity analysis complete (score: {activity_score:.2f})"

            return FilterCheck(
                check_name="trading_activity",
                passed=passed,
                score=activity_score,
                reason=reason,
                metadata={
                    "recent_trades": recent_trades,
                    "unique_traders": unique_traders,
                    "avg_trade_size": avg_trade_size,
                    "buy_sell_ratio": buy_sell_ratio,
                    "activity_score": activity_score
                }
            )

        except Exception as e:
            self.logger.error(f"Trading activity check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="trading_activity",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def check_technical_indicators(self, token_address: str) -> FilterCheck:
        """
        Analyze technical indicators for momentum and trends

        Args:
            token_address: Token mint address

        Returns:
            FilterCheck result with technical analysis
        """
        try:
            self.logger.info(f"Checking technical indicators for: {token_address}")

            # Get price history for technical analysis
            price_history = await self.get_token_price_history(
                token_address,
                interval="5m",
                hours_back=12
            )

            if len(price_history) < 30:
                return FilterCheck(
                    check_name="technical_indicators",
                    passed=False,
                    score=0.0,
                    reason="Insufficient data for technical analysis"
                )

            # Extract prices
            prices = [float(point.get('price', 0)) for point in price_history if point.get('price')]

            if len(prices) < 30:
                return FilterCheck(
                    check_name="technical_indicators",
                    passed=False,
                    score=0.0,
                    reason="Insufficient valid price data"
                )

            # Calculate simple technical indicators
            # Moving averages
            sma_short = sum(prices[-10:]) / 10  # 10-period SMA
            sma_long = sum(prices[-30:]) / 30   # 30-period SMA

            # RSI (simplified)
            gains = []
            losses = []
            for i in range(1, len(prices)):
                change = prices[i] - prices[i-1]
                if change > 0:
                    gains.append(change)
                    losses.append(0)
                else:
                    gains.append(0)
                    losses.append(abs(change))

            avg_gain = sum(gains[-14:]) / 14 if len(gains) >= 14 else 0
            avg_loss = sum(losses[-14:]) / 14 if len(losses) >= 14 else 0.001

            rsi = 100 - (100 / (1 + avg_gain / avg_loss)) if avg_loss > 0 else 50

            # Price momentum
            price_momentum = (prices[-1] - prices[-20]) / prices[-20] if len(prices) > 20 else 0

            # Calculate technical scores
            ma_score = 1.0 if sma_short > sma_long else 0.3  # Bullish MA crossover
            rsi_score = 0.8 if 30 <= rsi <= 70 else 0.4       # Not overbought/oversold
            momentum_score = min(max(price_momentum * 10, 0), 1)  # Positive momentum

            technical_score = (ma_score * 0.4 + rsi_score * 0.3 + momentum_score * 0.3)

            # Determine if technicals are favorable
            passed = technical_score > 0.5

            reason = f"Technical analysis complete (score: {technical_score:.2f})"

            return FilterCheck(
                check_name="technical_indicators",
                passed=passed,
                score=technical_score,
                reason=reason,
                metadata={
                    "sma_short": sma_short,
                    "sma_long": sma_long,
                    "rsi": rsi,
                    "price_momentum": price_momentum,
                    "technical_score": technical_score
                }
            )

        except Exception as e:
            self.logger.error(f"Technical indicators check failed for {token_address}: {e}")
            return FilterCheck(
                check_name="technical_indicators",
                passed=False,
                score=0.0,
                reason=f"Check failed: {str(e)}"
            )

    async def perform_all_checks(self, token_address: str) -> List[FilterCheck]:
        """
        Perform all 12 filter checks for a token

        Args:
            token_address: Token mint address

        Returns:
            List of all FilterCheck results
        """
        self.logger.info(f"Performing comprehensive analysis for token: {token_address}")

        # List of all check methods
        check_methods = [
            self.check_honeypot_risk,
            self.check_social_mentions,
            self.check_liquidity_depth,
            self.check_price_volatility,
            self.check_holder_distribution,
            self.check_contract_security,
            self.check_market_cap_ranking,
            self.check_trading_activity,
            self.check_technical_indicators
        ]

        # Execute all checks concurrently
        tasks = [method(token_address) for method in check_methods]
        filter_checks = await asyncio.gather(*tasks, return_exceptions=True)

        # Process results and handle exceptions
        valid_checks = []
        for i, check in enumerate(filter_checks):
            if isinstance(check, Exception):
                self.logger.error(f"Check {check_methods[i].__name__} failed: {check}")
                valid_checks.append(FilterCheck(
                    check_name=check_methods[i].__name__.replace('check_', ''),
                    passed=False,
                    score=0.0,
                    reason=f"Check failed with exception: {str(check)}"
                ))
            else:
                valid_checks.append(check)

        self.logger.info(f"Completed {len(valid_checks)} filter checks for {token_address}")
        return valid_checks

    async def run_backtest(
        self,
        token_address: str,
        initial_investment: float = 1000.0,
        simulate_hours: int = 24
    ) -> BacktestResult:
        """
        Run comprehensive backtest for a token

        Args:
            token_address: Token mint address
            initial_investment: Starting investment amount in USD
            simulate_hours: Number of hours to simulate

        Returns:
            Complete BacktestResult with all analysis
        """
        start_time = time.time()
        self.logger.info(f"Starting backtest for token: {token_address}")

        try:
            # Get token metadata
            token_metadata = await self.get_token_metadata(token_address)
            if not token_metadata:
                raise ValueError(f"Cannot fetch metadata for token: {token_address}")

            # Perform all filter checks
            filter_checks = await self.perform_all_checks(token_address)

            # Calculate overall score (weighted average)
            total_weight = 0
            weighted_score = 0

            # Weights for different check types
            weights = {
                'honeypot_risk': 0.20,        # Most important - avoid scams
                'liquidity_depth': 0.15,      # Important for trading
                'contract_security': 0.15,    # Security is critical
                'social_mentions': 0.10,      # Social proof
                'price_volatility': 0.10,     # Trading opportunities
                'holder_distribution': 0.08,  # Decentralization
                'market_cap_ranking': 0.07,   # Market position
                'trading_activity': 0.10,     # Current interest
                'technical_indicators': 0.05  # Technical momentum
            }

            for check in filter_checks:
                weight = weights.get(check.check_name, 0.05)
                total_weight += weight
                weighted_score += check.score * weight

            final_score = weighted_score / total_weight if total_weight > 0 else 0

            # Generate recommendation
            if final_score >= 0.8:
                recommendation = "STRONG_BUY"
            elif final_score >= 0.6:
                recommendation = "BUY"
            elif final_score >= 0.4:
                recommendation = "HOLD"
            else:
                recommendation = "AVOID"

            # Simulate trading performance based on filter results
            # This is a simplified simulation - real implementation would use historical price data
            base_return = 0.1  # 10% base return
            score_bonus = (final_score - 0.5) * 0.4  # Score-based adjustment
            volatility_factor = 0.1  # Random factor for volatility

            import random
            random.seed(hash(token_address) % 1000)  # Deterministic randomness
            random_factor = (random.random() - 0.5) * volatility_factor

            total_return = base_return + score_bonus + random_factor
            simulated_profit_loss = initial_investment * total_return

            # Calculate additional metrics
            max_drawdown = abs(min(0, random_factor * 0.5))  # Simulated drawdown
            trade_count = int(5 + final_score * 15)  # More trades for better scores
            win_rate = min(0.3 + final_score * 0.5, 0.9)  # Higher win rate for better scores

            backtest_duration = time.time() - start_time

            result = BacktestResult(
                token_address=token_address,
                token_metadata=token_metadata,
                filter_checks=filter_checks,
                final_score=final_score,
                recommendation=recommendation,
                simulated_profit_loss=simulated_profit_loss,
                max_drawdown=max_drawdown,
                trade_count=trade_count,
                win_rate=win_rate,
                backtest_duration_hours=backtest_duration / 3600
            )

            self.logger.info(f"Backtest completed for {token_address}: {recommendation} (score: {final_score:.2f})")
            return result

        except Exception as e:
            self.logger.error(f"Backtest failed for {token_address}: {e}")
            # Return minimal result on error
            return BacktestResult(
                token_address=token_address,
                token_metadata=TokenMetadata(
                    address=token_address,
                    name="Unknown Token",
                    symbol="UNKNOWN",
                    decimals=9,
                    supply=0,
                    creator="",
                    description="",
                    image_url="",
                    created_at=datetime.now()
                ),
                filter_checks=[],
                final_score=0.0,
                recommendation="ERROR",
                backtest_duration_hours=(time.time() - start_time) / 3600
            )

    # Synchronous wrapper methods for Mojo FFI interop

    def get_token_metadata_sync(self, token_address: str) -> Optional[Dict[str, Any]]:
        """
        Synchronous wrapper for get_token_metadata

        Args:
            token_address: Token mint address

        Returns:
            Token metadata as dictionary or None
        """
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(self.get_token_metadata(token_address))
            loop.close()

            if result:
                return result.__dict__
            return None
        except Exception as e:
            self.logger.error(f"Sync metadata fetch failed: {e}")
            return None

    def run_backtest_sync(
        self,
        token_address: str,
        initial_investment: float = 1000.0,
        simulate_hours: int = 24
    ) -> Dict[str, Any]:
        """
        Synchronous wrapper for run_backtest

        Args:
            token_address: Token mint address
            initial_investment: Starting investment amount in USD
            simulate_hours: Number of hours to simulate

        Returns:
            Backtest result as dictionary
        """
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(
                self.run_backtest(token_address, initial_investment, simulate_hours)
            )
            loop.close()

            return result.to_dict()
        except Exception as e:
            self.logger.error(f"Sync backtest failed: {e}")
            return {
                'token_address': token_address,
                'error': str(e),
                'final_score': 0.0,
                'recommendation': 'ERROR'
            }

    def batch_backtest_sync(
        self,
        token_addresses: List[str],
        initial_investment: float = 1000.0
    ) -> List[Dict[str, Any]]:
        """
        Synchronous batch backtesting for multiple tokens

        Args:
            token_addresses: List of token mint addresses
            initial_investment: Investment amount per token

        Returns:
            List of backtest results as dictionaries
        """
        results = []

        for token_address in token_addresses:
            self.logger.info(f"Processing token: {token_address}")
            result = self.run_backtest_sync(token_address, initial_investment)
            results.append(result)

            # Small delay between tokens to respect rate limits
            time.sleep(0.1)

        self.logger.info(f"Batch backtest completed for {len(token_addresses)} tokens")
        return results

    # Multi-Token Arbitrage Methods

    async def analyze_multi_token_arbitrage(
        self,
        token_addresses: List[str],
        analysis_type: str = "comprehensive"
    ) -> ArbitrageAnalysis:
        """
        Perform comprehensive multi-token arbitrage analysis

        Args:
            token_addresses: List of token addresses to analyze
            analysis_type: Type of analysis (triangular, cross_dex, comprehensive)

        Returns:
            Complete ArbitrageAnalysis with detected opportunities
        """
        start_time = time.time()
        self.logger.info(f"Starting multi-token arbitrage analysis for {len(token_addresses)} tokens")

        try:
            # Step 1: Get metadata for all tokens
            token_metadata = {}
            for token_addr in token_addresses:
                metadata = await self.get_token_metadata(token_addr)
                if metadata:
                    token_metadata[token_addr] = metadata

            if len(token_metadata) < 2:
                raise ValueError("Need at least 2 valid tokens for arbitrage analysis")

            # Step 2: Create token pairs
            token_pairs = await self._create_token_pairs(list(token_metadata.keys()))

            # Step 3: Get prices from multiple DEXes
            dex_prices = await self._get_multi_dex_prices(token_pairs)

            # Step 4: Detect arbitrage opportunities
            opportunities = []

            if analysis_type in ["triangular", "comprehensive"]:
                triangular_opps = await self._detect_triangular_arbitrage(
                    list(token_metadata.keys()), dex_prices
                )
                opportunities.extend(triangular_opps)

            if analysis_type in ["cross_dex", "comprehensive"]:
                cross_dex_opps = await self._detect_cross_dex_arbitrage(
                    token_pairs, dex_prices
                )
                opportunities.extend(cross_dex_opps)

            # Step 5: Filter and validate opportunities
            valid_opportunities = await self._filter_arbitrage_opportunities(opportunities)

            # Step 6: Submit to SandwichManager if available
            if self.enable_arbitrage and self.sandwich_manager:
                await self._submit_arbitrage_opportunities(valid_opportunities)

            # Calculate total potential profit
            total_profit = sum(opp.profit_estimate for opp in valid_opportunities)

            # Update statistics
            self.arbitrage_stats['opportunities_detected'] += len(valid_opportunities)
            self.arbitrage_stats['total_potential_profit'] += total_profit
            self.arbitrage_stats['last_analysis_time'] = datetime.now()

            analysis_duration = (time.time() - start_time) * 1000

            result = ArbitrageAnalysis(
                analyzed_tokens=token_addresses,
                token_pairs=token_pairs,
                detected_opportunities=valid_opportunities,
                total_potential_profit=total_profit,
                analysis_duration_ms=analysis_duration
            )

            self.logger.info(f"Arbitrage analysis completed: {len(valid_opportunities)} opportunities, "
                           f"${total_profit:.2f} potential profit, {analysis_duration:.0f}ms")
            return result

        except Exception as e:
            self.logger.error(f"Multi-token arbitrage analysis failed: {e}")
            return ArbitrageAnalysis(
                analyzed_tokens=token_addresses,
                token_pairs=[],
                detected_opportunities=[],
                total_potential_profit=0.0,
                analysis_duration_ms=(time.time() - start_time) * 1000
            )

    async def _create_token_pairs(self, token_addresses: List[str]) -> List[TokenPair]:
        """Create token pairs for analysis"""
        pairs = []
        tokens = list(token_addresses)

        for i in range(len(tokens)):
            for j in range(i + 1, len(tokens)):
                token_a, token_b = tokens[i], tokens[j]

                # Check cache first
                cache_key = f"{token_a}_{token_b}"
                if cache_key in self.token_pair_cache:
                    pairs.append(self.token_pair_cache[cache_key])
                    continue

                # Get metadata
                metadata_a = await self.get_token_metadata(token_a)
                metadata_b = await self.get_token_metadata(token_b)

                if metadata_a and metadata_b:
                    # Get current price from Jupiter
                    try:
                        price = await self.jupiter_api.get_token_price(token_a, token_b)
                        if price and price > 0:
                            pair = TokenPair(
                                token_a=token_a,
                                token_b=token_b,
                                symbol_a=metadata_a.symbol,
                                symbol_b=metadata_b.symbol,
                                decimals_a=metadata_a.decimals,
                                decimals_b=metadata_b.decimals,
                                current_price=price,
                                inverse_price=1.0 / price
                            )
                        else:
                            pair = TokenPair(
                                token_a=token_a,
                                token_b=token_b,
                                symbol_a=metadata_a.symbol,
                                symbol_b=metadata_b.symbol,
                                decimals_a=metadata_a.decimals,
                                decimals_b=metadata_b.decimals
                            )

                        pairs.append(pair)
                        self.token_pair_cache[cache_key] = pair

                    except Exception as e:
                        self.logger.warning(f"Failed to get price for {token_a}/{token_b}: {e}")

        return pairs

    async def _get_multi_dex_prices(self, token_pairs: List[TokenPair]) -> Dict[str, List[DEXPrice]]:
        """Get prices from multiple DEXes for all token pairs"""
        dex_prices = {}

        for pair in token_pairs:
            pair_key = f"{pair.token_a}_{pair.token_b}"
            prices = []

            for dex in self.supported_dexes:
                try:
                    # Mock DEX price data - in production, integrate with real DEX APIs
                    dex_price = await self._get_dex_price(dex, pair)
                    if dex_price:
                        prices.append(dex_price)

                except Exception as e:
                    self.logger.debug(f"Failed to get {dex} price for {pair.symbol_a}/{pair.symbol_b}: {e}")

            if prices:
                dex_prices[pair_key] = prices

        return dex_prices

    async def _get_dex_price(self, dex_name: str, token_pair: TokenPair) -> Optional[DEXPrice]:
        """Get price from a specific DEX (mock implementation)"""
        # In production, integrate with real DEX APIs
        # For now, generate realistic mock data

        address_hash = abs(hash(f"{dex_name}_{token_pair.token_a}_{token_pair.token_b}"))

        # Simulate price variation between DEXes
        base_price = token_pair.current_price if token_pair.current_price > 0 else 1.0
        price_variation = 1.0 + ((address_hash % 200) - 100) / 1000.0  # ±10% variation
        dex_price = base_price * price_variation

        # Simulate liquidity and volume
        liquidity = 10000 + (address_hash % 99000)
        volume_24h = 50000 + (address_hash % 450000)

        # Confidence based on liquidity
        confidence_score = min(liquidity / 50000, 1.0)

        return DEXPrice(
            dex_name=dex_name,
            token_pair=token_pair,
            price=dex_price,
            liquidity=liquidity,
            volume_24h=volume_24h,
            confidence_score=confidence_score
        )

    async def _detect_triangular_arbitrage(
        self,
        token_addresses: List[str],
        dex_prices: Dict[str, List[DEXPrice]]
    ) -> List[ArbitrageOpportunity]:
        """Detect triangular arbitrage opportunities"""
        opportunities = []

        # Need at least 3 tokens for triangular arbitrage
        if len(token_addresses) < 3:
            return opportunities

        # Generate all possible triangular combinations
        for i in range(len(token_addresses)):
            for j in range(len(token_addresses)):
                if j == i:
                    continue
                for k in range(len(token_addresses)):
                    if k == i or k == j:
                        continue

                    token_a, token_b, token_c = token_addresses[i], token_addresses[j], token_addresses[k]

                    # Check for triangular opportunity A -> B -> C -> A
                    opp = await self._analyze_triangular_opportunity(
                        token_a, token_b, token_c, dex_prices
                    )
                    if opp:
                        opportunities.append(opp)

        return opportunities

    async def _analyze_triangular_opportunity(
        self,
        token_a: str,
        token_b: str,
        token_c: str,
        dex_prices: Dict[str, List[DEXPrice]]
    ) -> Optional[ArbitrageOpportunity]:
        """Analyze a specific triangular arbitrage opportunity"""
        try:
            # Get best prices for each leg
            ab_prices = dex_prices.get(f"{token_a}_{token_b}", [])
            bc_prices = dex_prices.get(f"{token_b}_{token_c}", [])
            ca_prices = dex_prices.get(f"{token_c}_{token_a}", [])

            if not ab_prices or not bc_prices or not ca_prices:
                return None

            # Select best DEXes for each leg
            best_ab = max(ab_prices, key=lambda p: p.confidence_score * p.liquidity)
            best_bc = max(bc_prices, key=lambda p: p.confidence_score * p.liquidity)
            best_ca = max(ca_prices, key=lambda p: p.confidence_score * p.liquidity)

            # Calculate triangular arbitrage profit
            # Start with 1000 units of token A
            input_amount = 1000.0
            amount_b = input_amount / best_ab.price
            amount_c = amount_b / best_bc.price
            amount_a_final = amount_c / best_ca.price

            profit = amount_a_final - input_amount
            profit_percentage = (profit / input_amount) * 100

            # Minimum profit threshold
            if profit_percentage < 0.5:  # 0.5% minimum profit
                return None

            # Calculate confidence and urgency scores
            avg_confidence = (best_ab.confidence_score + best_bc.confidence_score + best_ca.confidence_score) / 3
            total_liquidity = best_ab.liquidity + best_bc.liquidity + best_ca.liquidity
            urgency_score = min(total_liquidity / 100000, 1.0)  # Higher liquidity = higher urgency

            # Calculate risk score based on price volatility (simplified)
            risk_score = 1.0 - (avg_confidence * 0.7 + urgency_score * 0.3)

            return ArbitrageOpportunity(
                id=str(uuid.uuid4()),
                arbitrage_type="triangular",
                token_a=token_a,
                token_b=token_b,
                token_c=token_c,
                dex_a=best_ab.dex_name,
                dex_b=best_bc.dex_name,
                dex_c=best_ca.dex_name,
                input_amount=input_amount,
                expected_output=amount_a_final,
                profit_estimate=profit,
                profit_percentage=profit_percentage,
                confidence_score=avg_confidence,
                urgency_score=urgency_score,
                risk_score=risk_score,
                metadata={
                    'leg_ab_price': best_ab.price,
                    'leg_bc_price': best_bc.price,
                    'leg_ca_price': best_ca.price,
                    'total_liquidity': total_liquidity,
                    'dex_names': [best_ab.dex_name, best_bc.dex_name, best_ca.dex_name]
                }
            )

        except Exception as e:
            self.logger.error(f"Triangular opportunity analysis failed: {e}")
            return None

    async def _detect_cross_dex_arbitrage(
        self,
        token_pairs: List[TokenPair],
        dex_prices: Dict[str, List[DEXPrice]]
    ) -> List[ArbitrageOpportunity]:
        """Detect cross-DEX arbitrage opportunities"""
        opportunities = []

        for pair in token_pairs:
            pair_key = f"{pair.token_a}_{pair.token_b}"
            prices = dex_prices.get(pair_key, [])

            if len(prices) < 2:
                continue

            # Sort by price
            prices.sort(key=lambda p: p.price)

            # Find best arbitrage opportunities
            for i in range(len(prices)):
                for j in range(i + 1, len(prices)):
                    low_price_dex = prices[i]
                    high_price_dex = prices[j]

                    price_diff = high_price_dex.price - low_price_dex.price
                    profit_percentage = (price_diff / low_price_dex.price) * 100

                    # Minimum profit threshold
                    if profit_percentage < 0.3:  # 0.3% minimum profit
                        continue

                    # Calculate input amount based on liquidity
                    max_trade_size = min(low_price_dex.liquidity, high_price_dex.liquidity) * 0.1  # 10% of liquidity
                    input_amount = min(max_trade_size, 10000)  # Cap at $10,000

                    expected_output = (input_amount / low_price_dex.price) * high_price_dex.price
                    profit = expected_output - input_amount

                    if profit < self.min_profit_threshold:
                        continue

                    # Calculate scores
                    avg_confidence = (low_price_dex.confidence_score + high_price_dex.confidence_score) / 2
                    total_liquidity = low_price_dex.liquidity + high_price_dex.liquidity
                    urgency_score = min(total_liquidity / 50000, 1.0)
                    risk_score = 1.0 - (avg_confidence * 0.8 + urgency_score * 0.2)

                    opportunity = ArbitrageOpportunity(
                        id=str(uuid.uuid4()),
                        arbitrage_type="cross_dex",
                        token_a=pair.token_a,
                        token_b=pair.token_b,
                        token_c=None,
                        dex_a=low_price_dex.dex_name,
                        dex_b=high_price_dex.dex_name,
                        dex_c=None,
                        input_amount=input_amount,
                        expected_output=expected_output,
                        profit_estimate=profit,
                        profit_percentage=profit_percentage,
                        confidence_score=avg_confidence,
                        urgency_score=urgency_score,
                        risk_score=risk_score,
                        metadata={
                            'buy_price': low_price_dex.price,
                            'sell_price': high_price_dex.price,
                            'price_difference': price_diff,
                            'buy_liquidity': low_price_dex.liquidity,
                            'sell_liquidity': high_price_dex.liquidity
                        }
                    )

                    opportunities.append(opportunity)

        return opportunities

    async def _filter_arbitrage_opportunities(
        self,
        opportunities: List[ArbitrageOpportunity]
    ) -> List[ArbitrageOpportunity]:
        """Filter and validate arbitrage opportunities"""
        valid_opportunities = []

        for opp in opportunities:
            # Check expiration
            if datetime.now() > opp.expires_at:
                continue

            # Check minimum profit
            if opp.profit_estimate < self.min_profit_threshold:
                continue

            # Check confidence threshold
            if opp.confidence_score < 0.3:
                continue

            # Check risk threshold
            if opp.risk_score > 0.8:
                continue

            valid_opportunities.append(opp)

        # Sort by profit descending
        valid_opportunities.sort(key=lambda x: x.profit_estimate, reverse=True)

        # Limit to top 10 opportunities
        return valid_opportunities[:10]

    async def _submit_arbitrage_opportunities(
        self,
        opportunities: List[ArbitrageOpportunity]
    ) -> int:
        """Submit arbitrage opportunities to SandwichManager"""
        if not self.enable_arbitrage or not self.sandwich_manager:
            return 0

        submitted_count = 0

        for opp in opportunities:
            try:
                # Convert to SandwichManager format
                sm_opportunity = ArbitrageOpportunity(
                    id=opp.id,
                    arbitrage_type=ArbitrageType(opp.arbitrage_type),
                    input_token=opp.token_a,
                    output_token=opp.token_b,
                    input_amount=opp.input_amount,
                    expected_output=opp.expected_output,
                    profit_amount=opp.profit_estimate,
                    confidence_score=opp.confidence_score,
                    urgency_score=opp.urgency_score,
                    dex_name=opp.dex_a,
                    detected_at=opp.detected_at,
                    expires_at=opp.expires_at,
                    metadata=opp.metadata
                )

                # Submit to SandwichManager
                success = await self.sandwich_manager.submit_arbitrage_opportunity(sm_opportunity)
                if success:
                    submitted_count += 1
                    self.arbitrage_stats['opportunities_submitted'] += 1

            except Exception as e:
                self.logger.error(f"Failed to submit opportunity {opp.id}: {e}")

        self.logger.info(f"Submitted {submitted_count}/{len(opportunities)} arbitrage opportunities")
        return submitted_count

    def get_arbitrage_statistics(self) -> Dict[str, Any]:
        """Get arbitrage analysis statistics"""
        return {
            **self.arbitrage_stats,
            'arbitrage_enabled': self.enable_arbitrage,
            'supported_dexes': self.supported_dexes,
            'min_profit_threshold': self.min_profit_threshold,
            'max_concurrent_analyses': self.max_concurrent_analyses
        }

    # Synchronous wrapper methods for multi-token arbitrage

    def analyze_multi_token_arbitrage_sync(
        self,
        token_addresses: List[str],
        analysis_type: str = "comprehensive"
    ) -> Dict[str, Any]:
        """
        Synchronous wrapper for multi-token arbitrage analysis

        Args:
            token_addresses: List of token addresses to analyze
            analysis_type: Type of analysis (triangular, cross_dex, comprehensive)

        Returns:
            Arbitrage analysis result as dictionary
        """
        try:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(
                self.analyze_multi_token_arbitrage(token_addresses, analysis_type)
            )
            loop.close()

            return result.to_dict()
        except Exception as e:
            self.logger.error(f"Sync arbitrage analysis failed: {e}")
            return {
                'error': str(e),
                'analyzed_tokens': token_addresses,
                'detected_opportunities': [],
                'total_potential_profit': 0.0
            }


# Factory function for easy initialization
def create_pumpfun_api(helius_api_key: str = "", quicknode_rpc: str = "") -> PumpFunAPI:
    """
    Create and initialize PumpFun API instance

    Args:
        helius_api_key: Helius API key
        quicknode_rpc: QuickNode RPC URL

    Returns:
        Initialized PumpFunAPI instance
    """
    return PumpFunAPI(helius_api_key, quicknode_rpc)


# Test function
async def test_pumpfun_api():
    """
    Test PumpFun API functionality
    """
    logger.info("Testing PumpFun API...")

    try:
        # Initialize API
        api = create_pumpfun_api("test_helius_key", "test_quicknode_rpc")

        # Test token metadata fetching
        test_token = "So11111111111111111111111111111111111111112"  # Wrapped SOL
        metadata = await api.get_token_metadata(test_token)
        if metadata:
            logger.info(f"✅ Token metadata fetched: {metadata.name} ({metadata.symbol})")

        # Test filter checks
        honeypot_check = await api.check_honeypot_risk(test_token)
        logger.info(f"✅ Honeypot check: {honeypot_check.passed} (score: {honeypot_check.score:.2f})")

        # Test comprehensive backtest
        backtest_result = await api.run_backtest(test_token, 1000.0, 1)
        logger.info(f"✅ Backtest completed: {backtest_result.recommendation} (score: {backtest_result.final_score:.2f})")

        logger.info("PumpFun API test completed successfully")

    except Exception as e:
        logger.error(f"PumpFun API test failed: {e}")
        raise


if __name__ == "__main__":
    # Run test
    asyncio.run(test_pumpfun_api())