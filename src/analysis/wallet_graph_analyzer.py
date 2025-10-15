"""
Production Wallet Graph Analyzer for Smart Money Detection

This module provides comprehensive wallet graph analysis and smart money detection
capabilities for identifying profitable trading patterns and influential wallets
in the Solana ecosystem.

Features:
- Multi-level wallet relationship analysis
- Transaction pattern recognition
- Smart money scoring and ranking
- Early investment detection
- Wallet clustering and group analysis
- Real-time graph updates and monitoring
- Social network analysis integration
- Profitability and performance tracking
"""

import asyncio
import aiohttp
import asyncpg
import aioredis
import json
import time
import logging
import numpy as np
import pandas as pd
import networkx as nx
from typing import Dict, List, Any, Optional, Set, Tuple, Union
from dataclasses import dataclass, asdict
from enum import Enum
from datetime import datetime, timezone, timedelta
from collections import defaultdict, deque
import plotly.graph_objects as go
import plotly.express as px
from sklearn.cluster import DBSCAN
from sklearn.preprocessing import StandardScaler
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.decomposition import PCA
import requests

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ============================================================================
# Data Models and Enums
# ============================================================================

class WalletType(Enum):
    """Types of wallets based on behavior"""
    WHALE = "whale"
    SMART_MONEY = "smart_money"
    EARLY_ADOPTER = "early_adopter"
    ARBITRAGE = "arbitrage"
    MARKET_MAKER = "market_maker"
    RETAIL = "retail"
    BOT = "bot"
    INSTITUTIONAL = "institutional"

class TransactionPattern(Enum):
    """Transaction pattern types"""
    EARLY_BUY = "early_buy"
    PUMP_DUMP = "pump_dump"
    LIQUIDITY_REMOVAL = "liquidity_remoVAL"
    SNIPE = "snipe"
    ACCUMULATION = "accumulation"
    DISTRIBUTION = "distribution"
    ARBITRAGE_FLASH = "arbitrage_flash"
    WASH_TRADE = "wash_trade"

class RelationshipType(Enum):
    """Types of relationships between wallets"""
    DIRECT_TRANSFER = "direct_transfer"
    SHARED_INVESTMENT = "shared_investment"
    SEQUENTIAL_TRADING = "sequential_trading"
    COORDINATED_ACTION = "coordinated_action"
    MARKET_MAKING = "market_making"
    SYBIL_CLUSTER = "sybil_cluster"

@dataclass
class WalletProfile:
    """Comprehensive wallet profile"""
    address: str
    wallet_type: WalletType
    influence_score: float
    profitability_score: float
    early_investment_count: int
    total_transactions: int
    success_rate: float
    avg_profit_per_trade: float
    net_worth_estimate: float
    first_seen: datetime
    last_active: datetime
    active_days: int
    transaction_frequency: float
    cluster_id: Optional[str] = None
    tags: List[str] = None
    associated_addresses: List[str] = None

@dataclass
class TransactionEdge:
    """Edge representing a transaction between wallets"""
    from_wallet: str
    to_wallet: str
    amount: float
    token_address: str
    timestamp: datetime
    transaction_type: str
    relationship_strength: float
    is_profitable: bool
    profit_amount: Optional[float] = None

@dataclass
class WalletCluster:
    """Cluster of related wallets"""
    cluster_id: str
    members: List[str]
    cluster_type: WalletType
    total_value: float
    avg_profitability: float
    coordination_score: float
    risk_level: str
    created_at: datetime

@dataclass
class SmartMoneySignal:
    """Smart money trading signal"""
    signal_type: str
    wallet_address: str
    token_address: str
    action: str  # buy/sell
    confidence: float
    expected_impact: float
    supporting_evidence: List[str]
    timestamp: datetime
    expires_at: datetime

@dataclass
class GraphMetrics:
    """Graph analysis metrics"""
    total_wallets: int
    total_edges: int
    network_density: float
    avg_clustering_coefficient: float
    number_of_clusters: int
    smart_money_ratio: float
    whale_ratio: float
    bot_ratio: float
    centrality_scores: Dict[str, float]
    graph_diameter: int

# ============================================================================
# Production Wallet Graph Analyzer
# ============================================================================

class WalletGraphAnalyzer:
    """
    Production-grade wallet graph analyzer for smart money detection
    and comprehensive transaction pattern analysis.
    """

    def __init__(
        self,
        rpc_url: str,
        db_url: Optional[str] = None,
        redis_url: Optional[str] = None,
        config: Optional[Dict[str, Any]] = None
    ):
        """
        Initialize wallet graph analyzer

        Args:
            rpc_url: Solana RPC endpoint
            db_url: PostgreSQL connection string
            redis_url: Redis connection string for caching
            config: Configuration dictionary
        """
        self.rpc_url = rpc_url
        self.db_url = db_url
        self.redis_url = redis_url
        self.config = config or {}

        # Initialize connections
        self.db_pool = None
        self.redis_client = None
        self.http_session = None
        self.rpc_client = None

        # Graph storage
        self.wallet_graph = nx.DiGraph()
        self.wallet_profiles: Dict[str, WalletProfile] = {}
        self.wallet_clusters: Dict[str, WalletCluster] = {}
        self.transaction_history: List[TransactionEdge] = []

        # Analysis state
        self.last_analysis_time = 0
        self.analysis_interval = self.config.get("analysis_interval", 300)  # 5 minutes
        self.max_graph_size = self.config.get("max_graph_size", 100000)  # 100k wallets

        # Performance tracking
        self.metrics = {
            "wallets_analyzed": 0,
            "transactions_processed": 0,
            "clusters_identified": 0,
            "smart_money_detected": 0,
            "signals_generated": 0,
            "analysis_time_ms": 0,
            "start_time": time.time()
        }

        # Configuration parameters
        self.min_transactions_for_analysis = self.config.get("min_transactions", 10)
        self.min_profit_threshold = self.config.get("min_profit_threshold", 100.0)  # $100
        self.early_investment_window = self.config.get("early_investment_window", 3600)  # 1 hour
        self.coordination_threshold = self.config.get("coordination_threshold", 0.7)

        logger.info("Wallet Graph Analyzer initialized")

    async def initialize(self):
        """Initialize all connections and load initial data"""
        logger.info("Initializing Wallet Graph Analyzer...")

        # Initialize database connections
        await self._init_database()

        # Initialize HTTP sessions
        self.http_session = aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=30),
            connector=aiohttp.TCPConnector(limit=100)
        )

        # Initialize RPC client
        await self._init_rpc_client()

        # Load existing wallet data
        await self._load_historical_data()

        # Start background analysis tasks
        await self._start_background_tasks()

        logger.info("Wallet Graph Analyzer initialization complete")

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

    async def _init_rpc_client(self):
        """Initialize Solana RPC client"""
        try:
            # Initialize RPC client
            self.rpc_client = {
                "url": self.rpc_url,
                "session": self.http_session
            }
            logger.info(f"RPC client initialized for {self.rpc_url}")
        except Exception as e:
            logger.error(f"RPC client initialization failed: {e}")

    async def _load_historical_data(self):
        """Load historical wallet and transaction data"""
        try:
            if self.db_pool:
                async with self.db_pool.acquire() as conn:
                    # Load wallet profiles
                    profiles_query = """
                        SELECT address, wallet_type, influence_score, profitability_score,
                               early_investment_count, total_transactions, success_rate,
                               avg_profit_per_trade, net_worth_estimate, first_seen,
                               last_active, active_days, transaction_frequency, cluster_id
                        FROM wallet_profiles
                        WHERE last_active > NOW() - INTERVAL '30 days'
                    """
                    rows = await conn.fetch(profiles_query)
                    for row in rows:
                        profile = WalletProfile(
                            address=row['address'],
                            wallet_type=WalletType(row['wallet_type']),
                            influence_score=row['influence_score'],
                            profitability_score=row['profitability_score'],
                            early_investment_count=row['early_investment_count'],
                            total_transactions=row['total_transactions'],
                            success_rate=row['success_rate'],
                            avg_profit_per_trade=row['avg_profit_per_trade'],
                            net_worth_estimate=row['net_worth_estimate'],
                            first_seen=row['first_seen'],
                            last_active=row['last_active'],
                            active_days=row['active_days'],
                            transaction_frequency=row['transaction_frequency'],
                            cluster_id=row['cluster_id'],
                            tags=[],
                            associated_addresses=[]
                        )
                        self.wallet_profiles[row['address']] = profile

                    # Load recent transactions
                    transactions_query = """
                        SELECT from_wallet, to_wallet, amount, token_address, timestamp,
                               transaction_type, relationship_strength, is_profitable, profit_amount
                        FROM wallet_transactions
                        WHERE timestamp > NOW() - INTERVAL '7 days'
                        ORDER BY timestamp DESC
                        LIMIT 50000
                    """
                    rows = await conn.fetch(transactions_query)
                    for row in rows:
                        edge = TransactionEdge(
                            from_wallet=row['from_wallet'],
                            to_wallet=row['to_wallet'],
                            amount=row['amount'],
                            token_address=row['token_address'],
                            timestamp=row['timestamp'],
                            transaction_type=row['transaction_type'],
                            relationship_strength=row['relationship_strength'],
                            is_profitable=row['is_profitable'],
                            profit_amount=row['profit_amount']
                        )
                        self.transaction_history.append(edge)
                        self._add_edge_to_graph(edge)

            logger.info(f"Loaded {len(self.wallet_profiles)} wallet profiles and {len(self.transaction_history)} transactions")

        except Exception as e:
            logger.error(f"Failed to load historical data: {e}")

    async def _start_background_tasks(self):
        """Start background analysis tasks"""
        # Periodic graph analysis
        asyncio.create_task(self._periodic_analysis())

        # Smart money monitoring
        asyncio.create_task(self._smart_money_monitoring())

        # Graph cleanup and optimization
        asyncio.create_task(self._graph_maintenance())

        logger.info("Background analysis tasks started")

    async def _periodic_analysis(self):
        """Periodic graph analysis and updates"""
        while True:
            try:
                await self.analyze_wallet_graph()
                await asyncio.sleep(self.analysis_interval)
            except Exception as e:
                logger.error(f"Error in periodic analysis: {e}")
                await asyncio.sleep(60)

    async def _smart_money_monitoring(self):
        """Monitor smart money activity and generate signals"""
        while True:
            try:
                signals = await self.generate_smart_money_signals()
                for signal in signals:
                    await self._process_smart_money_signal(signal)
                await asyncio.sleep(60)  # Check every minute
            except Exception as e:
                logger.error(f"Error in smart money monitoring: {e}")
                await asyncio.sleep(60)

    async def _graph_maintenance(self):
        """Graph cleanup and optimization"""
        while True:
            try:
                await self._cleanup_old_data()
                await self._optimize_graph_structure()
                await asyncio.sleep(3600)  # Run every hour
            except Exception as e:
                logger.error(f"Error in graph maintenance: {e}")
                await asyncio.sleep(300)

    async def analyze_wallet_graph(self) -> GraphMetrics:
        """
        Perform comprehensive analysis of the wallet graph

        Returns:
            Graph analysis metrics
        """
        start_time = time.time()

        try:
            # Update transaction data
            await self._fetch_recent_transactions()

            # Analyze wallet behavior patterns
            await self._analyze_wallet_patterns()

            # Identify wallet clusters
            await self._identify_wallet_clusters()

            # Calculate centrality and influence
            await self._calculate_wallet_influence()

            # Detect smart money patterns
            await self._detect_smart_money_patterns()

            # Update graph metrics
            metrics = await self._calculate_graph_metrics()

            analysis_time = (time.time() - start_time) * 1000
            self.metrics["analysis_time_ms"] = analysis_time
            self.last_analysis_time = time.time()

            logger.info(f"Wallet graph analysis completed in {analysis_time:.2f}ms",
                       wallets=metrics.total_wallets,
                       clusters=metrics.number_of_clusters,
                       smart_money_ratio=metrics.smart_money_ratio)

            return metrics

        except Exception as e:
            logger.error(f"Error in wallet graph analysis: {e}")
            raise e

    async def _fetch_recent_transactions(self):
        """Fetch recent transactions from RPC"""
        try:
            # This would integrate with Solana RPC to fetch recent transactions
            # For now, simulate transaction fetching
            recent_transactions = await self._simulate_transaction_fetch()

            for tx_data in recent_transactions:
                edge = self._parse_transaction_edge(tx_data)
                if edge:
                    self.transaction_history.append(edge)
                    self._add_edge_to_graph(edge)

        except Exception as e:
            logger.error(f"Error fetching recent transactions: {e}")

    async def _simulate_transaction_fetch(self) -> List[Dict[str, Any]]:
        """Simulate transaction fetching for development"""
        # Mock recent transactions
        return [
            {
                "from": "wallet1_address",
                "to": "wallet2_address",
                "amount": 1000.0,
                "token": "token_address",
                "timestamp": datetime.now(timezone.utc),
                "type": "transfer"
            }
        ]

    def _parse_transaction_edge(self, tx_data: Dict[str, Any]) -> Optional[TransactionEdge]:
        """Parse transaction data into edge"""
        try:
            return TransactionEdge(
                from_wallet=tx_data["from"],
                to_wallet=tx_data["to"],
                amount=tx_data["amount"],
                token_address=tx_data["token"],
                timestamp=tx_data["timestamp"],
                transaction_type=tx_data["type"],
                relationship_strength=self._calculate_relationship_strength(tx_data),
                is_profitable=self._is_transaction_profitable(tx_data),
                profit_amount=tx_data.get("profit")
            )
        except Exception as e:
            logger.error(f"Error parsing transaction edge: {e}")
            return None

    def _calculate_relationship_strength(self, tx_data: Dict[str, Any]) -> float:
        """Calculate relationship strength based on transaction characteristics"""
        amount = tx_data.get("amount", 0)
        # Normalize amount to 0-1 scale (assuming max meaningful amount is 100k)
        return min(amount / 100000.0, 1.0)

    def _is_transaction_profitable(self, tx_data: Dict[str, Any]) -> bool:
        """Determine if transaction was profitable"""
        profit = tx_data.get("profit", 0)
        return profit > self.min_profit_threshold

    def _add_edge_to_graph(self, edge: TransactionEdge):
        """Add transaction edge to the graph"""
        self.wallet_graph.add_edge(
            edge.from_wallet,
            edge.to_wallet,
            weight=edge.relationship_strength,
            amount=edge.amount,
            token=edge.token_address,
            timestamp=edge.timestamp,
            transaction_type=edge.transaction_type,
            is_profitable=edge.is_profitable,
            profit_amount=edge.profit_amount or 0
        )

    async def _analyze_wallet_patterns(self):
        """Analyze individual wallet behavior patterns"""
        for wallet_address in self.wallet_graph.nodes():
            if wallet_address not in self.wallet_profiles:
                profile = await self._create_wallet_profile(wallet_address)
                if profile:
                    self.wallet_profiles[wallet_address] = profile
                    self.metrics["wallets_analyzed"] += 1

    async def _create_wallet_profile(self, wallet_address: str) -> Optional[WalletProfile]:
        """Create profile for a wallet based on its transaction history"""
        try:
            # Get wallet's transaction history
            transactions = self._get_wallet_transactions(wallet_address)

            if len(transactions) < self.min_transactions_for_analysis:
                return None

            # Calculate metrics
            total_transactions = len(transactions)
            profitable_tx = [tx for tx in transactions if tx.is_profitable]
            success_rate = len(profitable_tx) / total_transactions

            total_profit = sum(tx.profit_amount or 0 for tx in profitable_tx)
            avg_profit = total_profit / len(profitable_tx) if profitable_tx else 0

            # Determine wallet type
            wallet_type = self._classify_wallet_type(transactions)

            # Calculate influence score
            influence_score = self._calculate_influence_score(wallet_address, transactions)

            # Calculate profitability score
            profitability_score = min(avg_profit / 1000.0, 1.0)  # Normalize to 0-1

            # Time-based metrics
            timestamps = [tx.timestamp for tx in transactions]
            first_seen = min(timestamps)
            last_active = max(timestamps)
            active_days = (last_active - first_seen).days + 1
            transaction_frequency = total_transactions / active_days

            # Estimate net worth
            net_worth = self._estimate_net_worth(transactions)

            # Early investments
            early_investments = self._count_early_investments(transactions)

            return WalletProfile(
                address=wallet_address,
                wallet_type=wallet_type,
                influence_score=influence_score,
                profitability_score=profitability_score,
                early_investment_count=early_investments,
                total_transactions=total_transactions,
                success_rate=success_rate,
                avg_profit_per_trade=avg_profit,
                net_worth_estimate=net_worth,
                first_seen=first_seen,
                last_active=last_active,
                active_days=active_days,
                transaction_frequency=transaction_frequency,
                tags=[],
                associated_addresses=[]
            )

        except Exception as e:
            logger.error(f"Error creating wallet profile for {wallet_address}: {e}")
            return None

    def _get_wallet_transactions(self, wallet_address: str) -> List[TransactionEdge]:
        """Get all transactions involving a wallet"""
        transactions = []

        # Outgoing transactions
        for _, _, data in self.wallet_graph.out_edges(wallet_address, data=True):
            transactions.append(TransactionEdge(
                from_wallet=wallet_address,
                to_wallet=data.get("to", ""),
                amount=data.get("amount", 0),
                token_address=data.get("token", ""),
                timestamp=data.get("timestamp", datetime.now(timezone.utc)),
                transaction_type=data.get("transaction_type", ""),
                relationship_strength=data.get("weight", 0),
                is_profitable=data.get("is_profitable", False),
                profit_amount=data.get("profit_amount")
            ))

        # Incoming transactions
        for _, _, data in self.wallet_graph.in_edges(wallet_address, data=True):
            transactions.append(TransactionEdge(
                from_wallet=data.get("from", ""),
                to_wallet=wallet_address,
                amount=data.get("amount", 0),
                token_address=data.get("token", ""),
                timestamp=data.get("timestamp", datetime.now(timezone.utc)),
                transaction_type=data.get("transaction_type", ""),
                relationship_strength=data.get("weight", 0),
                is_profitable=data.get("is_profitable", False),
                profit_amount=data.get("profit_amount")
            ))

        return transactions

    def _classify_wallet_type(self, transactions: List[TransactionEdge]) -> WalletType:
        """Classify wallet type based on transaction patterns"""
        # Simple heuristic-based classification
        total_amount = sum(tx.amount for tx in transactions)
        avg_amount = total_amount / len(transactions)
        profit_rate = len([tx for tx in transactions if tx.is_profitable]) / len(transactions)

        if avg_amount > 100000:  # > $100k average
            return WalletType.WHALE
        elif profit_rate > 0.8 and len(transactions) > 100:
            return WalletType.SMART_MONEY
        elif profit_rate > 0.6:
            return WalletType.EARLY_ADOPTER
        elif len(transactions) > 1000:
            return WalletType.MARKET_MAKER
        elif len(transactions) > 100 and profit_rate > 0.4:
            return WalletType.ARBITRAGE
        else:
            return WalletType.RETAIL

    def _calculate_influence_score(self, wallet_address: str, transactions: List[TransactionEdge]) -> float:
        """Calculate influence score based on network position and transaction patterns"""
        try:
            # Network centrality
            centrality = nx.degree_centrality(self.wallet_graph).get(wallet_address, 0)

            # Transaction volume
            total_volume = sum(tx.amount for tx in transactions)
            volume_score = min(total_volume / 1000000.0, 1.0)  # Normalize to 0-1

            # Profitability
            profit_rate = len([tx for tx in transactions if tx.is_profitable]) / len(transactions)

            # Combined influence score
            influence = (centrality * 0.3) + (volume_score * 0.4) + (profit_rate * 0.3)

            return min(influence, 1.0)

        except Exception as e:
            logger.error(f"Error calculating influence score: {e}")
            return 0.5

    def _estimate_net_worth(self, transactions: List[TransactionEdge]) -> float:
        """Estimate net worth based on transaction patterns"""
        # Simple estimation based on transaction amounts
        total_amount = sum(tx.amount for tx in transactions)
        return total_amount * 0.1  # Rough estimate

    def _count_early_investments(self, transactions: List[TransactionEdge]) -> int:
        """Count early investment patterns"""
        # Simplified early investment detection
        return len([tx for tx in transactions if tx.transaction_type == "early_buy"])

    async def _identify_wallet_clusters(self):
        """Identify clusters of related wallets"""
        try:
            # Extract wallet features for clustering
            wallet_features = self._extract_wallet_features()

            if len(wallet_features) < 10:
                return  # Not enough data for clustering

            # Perform clustering
            clusters = self._perform_clustering(wallet_features)

            # Create wallet cluster objects
            for cluster_id, wallet_addresses in clusters.items():
                cluster = await self._create_wallet_cluster(cluster_id, wallet_addresses)
                if cluster:
                    self.wallet_clusters[cluster_id] = cluster
                    self.metrics["clusters_identified"] += 1

        except Exception as e:
            logger.error(f"Error identifying wallet clusters: {e}")

    def _extract_wallet_features(self) -> Dict[str, np.ndarray]:
        """Extract features for clustering"""
        features = {}

        for wallet_address, profile in self.wallet_profiles.items():
            feature_vector = np.array([
                profile.influence_score,
                profile.profitability_score,
                profile.transaction_frequency,
                profile.success_rate,
                profile.net_worth_estimate / 1000000.0,  # Normalize by 1M
                len(self._get_wallet_transactions(wallet_address))
            ])
            features[wallet_address] = feature_vector

        return features

    def _perform_clustering(self, wallet_features: Dict[str, np.ndarray]) -> Dict[int, List[str]]:
        """Perform DBSCAN clustering on wallet features"""
        try:
            # Prepare data
            addresses = list(wallet_features.keys())
            features = np.array([wallet_features[addr] for addr in addresses])

            # Standardize features
            scaler = StandardScaler()
            features_scaled = scaler.fit_transform(features)

            # Perform clustering
            clustering = DBSCAN(eps=0.5, min_samples=3).fit(features_scaled)

            # Group wallets by cluster
            clusters = defaultdict(list)
            for i, label in enumerate(clustering.labels_):
                if label != -1:  # Skip noise points
                    clusters[label].append(addresses[i])

            return dict(clusters)

        except Exception as e:
            logger.error(f"Error performing clustering: {e}")
            return {}

    async def _create_wallet_cluster(self, cluster_id: int, wallet_addresses: List[str]) -> Optional[WalletCluster]:
        """Create wallet cluster object"""
        try:
            profiles = [self.wallet_profiles[addr] for addr in wallet_addresses if addr in self.wallet_profiles]

            if not profiles:
                return None

            # Calculate cluster metrics
            total_value = sum(p.net_worth_estimate for p in profiles)
            avg_profitability = sum(p.profitability_score for p in profiles) / len(profiles)
            coordination_score = self._calculate_coordination_score(wallet_addresses)

            # Determine cluster type
            cluster_type = self._determine_cluster_type(profiles)

            # Risk assessment
            risk_level = self._assess_cluster_risk(profiles)

            return WalletCluster(
                cluster_id=f"cluster_{cluster_id}",
                members=wallet_addresses,
                cluster_type=cluster_type,
                total_value=total_value,
                avg_profitability=avg_profitability,
                coordination_score=coordination_score,
                risk_level=risk_level,
                created_at=datetime.now(timezone.utc)
            )

        except Exception as e:
            logger.error(f"Error creating wallet cluster: {e}")
            return None

    def _calculate_coordination_score(self, wallet_addresses: List[str]) -> float:
        """Calculate coordination score for wallet cluster"""
        try:
            # Measure coordination through simultaneous or sequential actions
            total_pairs = len(wallet_addresses) * (len(wallet_addresses) - 1) // 2
            coordinated_pairs = 0

            for i, addr1 in enumerate(wallet_addresses):
                for addr2 in wallet_addresses[i+1:]:
                    if self.wallet_graph.has_edge(addr1, addr2) or self.wallet_graph.has_edge(addr2, addr1):
                        coordinated_pairs += 1

            return coordinated_pairs / total_pairs if total_pairs > 0 else 0.0

        except Exception as e:
            logger.error(f"Error calculating coordination score: {e}")
            return 0.0

    def _determine_cluster_type(self, profiles: List[WalletProfile]) -> WalletType:
        """Determine cluster type based on member profiles"""
        type_counts = defaultdict(int)
        for profile in profiles:
            type_counts[profile.wallet_type] += 1

        # Return the most common type
        return max(type_counts.items(), key=lambda x: x[1])[0]

    def _assess_cluster_risk(self, profiles: List[WalletProfile]) -> str:
        """Assess risk level of wallet cluster"""
        avg_success_rate = sum(p.success_rate for p in profiles) / len(profiles)
        avg_profitability = sum(p.profitability_score for p in profiles) / len(profiles)

        if avg_success_rate > 0.8 and avg_profitability > 0.7:
            return "low"
        elif avg_success_rate > 0.6 and avg_profitability > 0.5:
            return "medium"
        else:
            return "high"

    async def _calculate_wallet_influence(self):
        """Calculate influence scores for all wallets"""
        try:
            # Calculate various centrality measures
            degree_centrality = nx.degree_centrality(self.wallet_graph)
            betweenness_centrality = nx.betweenness_centrality(self.wallet_graph)
            closeness_centrality = nx.closeness_centrality(self.wallet_graph)

            # Update influence scores in wallet profiles
            for wallet_address in self.wallet_graph.nodes():
                if wallet_address in self.wallet_profiles:
                    profile = self.wallet_profiles[wallet_address]

                    # Combined influence score
                    influence = (
                        degree_centrality.get(wallet_address, 0) * 0.4 +
                        betweenness_centrality.get(wallet_address, 0) * 0.3 +
                        closeness_centrality.get(wallet_address, 0) * 0.3
                    )

                    profile.influence_score = influence

        except Exception as e:
            logger.error(f"Error calculating wallet influence: {e}")

    async def _detect_smart_money_patterns(self):
        """Detect smart money patterns and update wallet classifications"""
        try:
            for wallet_address, profile in self.wallet_profiles.items():
                # Check for smart money indicators
                if self._is_smart_money(profile):
                    profile.wallet_type = WalletType.SMART_MONEY
                    self.metrics["smart_money_detected"] += 1

                    # Add smart money tag
                    if not profile.tags:
                        profile.tags = []
                    profile.tags.append("smart_money")

        except Exception as e:
            logger.error(f"Error detecting smart money patterns: {e}")

    def _is_smart_money(self, profile: WalletProfile) -> bool:
        """Determine if wallet exhibits smart money behavior"""
        return (
            profile.profitability_score > 0.7 and
            profile.success_rate > 0.8 and
            profile.early_investment_count > 5 and
            profile.avg_profit_per_trade > 500
        )

    async def _calculate_graph_metrics(self) -> GraphMetrics:
        """Calculate comprehensive graph metrics"""
        try:
            total_wallets = self.wallet_graph.number_of_nodes()
            total_edges = self.wallet_graph.number_of_edges()

            # Network density
            network_density = nx.density(self.wallet_graph)

            # Clustering coefficient
            clustering_coeff = nx.average_clustering(self.wallet_graph.to_undirected())

            # Wallet type ratios
            smart_money_count = len([p for p in self.wallet_profiles.values() if p.wallet_type == WalletType.SMART_MONEY])
            whale_count = len([p for p in self.wallet_profiles.values() if p.wallet_type == WalletType.WHALE])
            bot_count = len([p for p in self.wallet_profiles.values() if p.wallet_type == WalletType.BOT])

            total_classified = len(self.wallet_profiles)
            smart_money_ratio = smart_money_count / total_classified if total_classified > 0 else 0
            whale_ratio = whale_count / total_classified if total_classified > 0 else 0
            bot_ratio = bot_count / total_classified if total_classified > 0 else 0

            # Centralities
            centralities = nx.degree_centrality(self.wallet_graph)

            # Graph diameter (for connected components only)
            if nx.is_connected(self.wallet_graph.to_undirected()):
                diameter = nx.diameter(self.wallet_graph.to_undirected())
            else:
                diameter = -1  # Disconnected graph

            return GraphMetrics(
                total_wallets=total_wallets,
                total_edges=total_edges,
                network_density=network_density,
                avg_clustering_coefficient=clustering_coeff,
                number_of_clusters=len(self.wallet_clusters),
                smart_money_ratio=smart_money_ratio,
                whale_ratio=whale_ratio,
                bot_ratio=bot_ratio,
                centrality_scores=centralities,
                graph_diameter=diameter
            )

        except Exception as e:
            logger.error(f"Error calculating graph metrics: {e}")
            return GraphMetrics(0, 0, 0, 0, 0, 0, 0, 0, {}, 0)

    async def generate_smart_money_signals(self) -> List[SmartMoneySignal]:
        """Generate smart money trading signals"""
        signals = []

        try:
            for wallet_address, profile in self.wallet_profiles.items():
                if profile.wallet_type == WalletType.SMART_MONEY:
                    # Get recent transactions for this wallet
                    recent_transactions = [
                        tx for tx in self._get_wallet_transactions(wallet_address)
                        if (datetime.now(timezone.utc) - tx.timestamp).total_seconds() < 3600
                    ]

                    for tx in recent_transactions:
                        if tx.is_profitable and tx.amount > 1000:  # Significant profitable transaction
                            signal = SmartMoneySignal(
                                signal_type="smart_money_activity",
                                wallet_address=wallet_address,
                                token_address=tx.token_address,
                                action="buy" if tx.amount > 0 else "sell",
                                confidence=profile.profitability_score,
                                expected_impact=self._calculate_expected_impact(tx, profile),
                                supporting_evidence=[
                                    f"Success rate: {profile.success_rate:.2%}",
                                    f"Avg profit: ${profile.avg_profit_per_trade:.2f}",
                                    f"Influence: {profile.influence_score:.2f}"
                                ],
                                timestamp=datetime.now(timezone.utc),
                                expires_at=datetime.now(timezone.utc) + timedelta(hours=1)
                            )
                            signals.append(signal)
                            self.metrics["signals_generated"] += 1

        except Exception as e:
            logger.error(f"Error generating smart money signals: {e}")

        return signals

    def _calculate_expected_impact(self, transaction: TransactionEdge, profile: WalletProfile) -> float:
        """Calculate expected market impact of a transaction"""
        base_impact = (transaction.amount / 10000.0) * profile.influence_score
        return min(base_impact, 1.0)

    async def _process_smart_money_signal(self, signal: SmartMoneySignal):
        """Process and store smart money signal"""
        try:
            # Store in database if available
            if self.db_pool:
                async with self.db_pool.acquire() as conn:
                    await conn.execute("""
                        INSERT INTO smart_money_signals (
                            signal_type, wallet_address, token_address, action,
                            confidence, expected_impact, supporting_evidence,
                            timestamp, expires_at
                        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                    """, *[
                        signal.signal_type,
                        signal.wallet_address,
                        signal.token_address,
                        signal.action,
                        signal.confidence,
                        signal.expected_impact,
                        json.dumps(signal.supporting_evidence),
                        signal.timestamp,
                        signal.expires_at
                    ])

            # Cache in Redis
            if self.redis_client:
                signal_key = f"smart_money_signal:{signal.wallet_address}:{signal.token_address}"
                await self.redis_client.setex(
                    signal_key,
                    3600,  # 1 hour TTL
                    json.dumps(asdict(signal), default=str)
                )

            logger.info(f"Processed smart money signal: {signal.signal_type}",
                       wallet=signal.wallet_address[:8],
                       token=signal.token_address[:8],
                       confidence=signal.confidence)

        except Exception as e:
            logger.error(f"Error processing smart money signal: {e}")

    async def _cleanup_old_data(self):
        """Clean up old data to maintain performance"""
        try:
            cutoff_time = datetime.now(timezone.utc) - timedelta(days=30)

            # Remove old transactions
            self.transaction_history = [
                tx for tx in self.transaction_history
                if tx.timestamp > cutoff_time
            ]

            # Remove old wallet profiles
            self.wallet_profiles = {
                addr: profile for addr, profile in self.wallet_profiles.items()
                if profile.last_active > cutoff_time
            }

            # Update graph
            old_nodes = [
                node for node in self.wallet_graph.nodes()
                if node not in self.wallet_profiles
            ]
            self.wallet_graph.remove_nodes_from(old_nodes)

            logger.info(f"Cleaned up old data. Removed {len(old_nodes)} inactive wallets")

        except Exception as e:
            logger.error(f"Error cleaning up old data: {e}")

    async def _optimize_graph_structure(self):
        """Optimize graph structure for better performance"""
        try:
            # Remove isolated nodes
            isolated_nodes = list(nx.isolates(self.wallet_graph))
            self.wallet_graph.remove_nodes_from(isolated_nodes)

            # Limit graph size
            if self.wallet_graph.number_of_nodes() > self.max_graph_size:
                # Keep most influential nodes
                centralities = nx.degree_centrality(self.wallet_graph)
                sorted_nodes = sorted(centralities.items(), key=lambda x: x[1], reverse=True)
                nodes_to_keep = set(addr for addr, _ in sorted_nodes[:self.max_graph_size])

                nodes_to_remove = [
                    node for node in self.wallet_graph.nodes()
                    if node not in nodes_to_keep
                ]
                self.wallet_graph.remove_nodes_from(nodes_to_remove)

            logger.info(f"Graph optimized. Current size: {self.wallet_graph.number_of_nodes()} nodes")

        except Exception as e:
            logger.error(f"Error optimizing graph structure: {e}")

    # Public API methods
    async def get_wallet_profile(self, wallet_address: str) -> Optional[WalletProfile]:
        """Get profile for a specific wallet"""
        return self.wallet_profiles.get(wallet_address)

    async def get_smart_money_wallets(self, limit: int = 100) -> List[WalletProfile]:
        """Get top smart money wallets"""
        smart_money = [
            profile for profile in self.wallet_profiles.values()
            if profile.wallet_type == WalletType.SMART_MONEY
        ]
        smart_money.sort(key=lambda p: p.profitability_score, reverse=True)
        return smart_money[:limit]

    async def get_wallet_clusters(self, cluster_type: Optional[WalletType] = None) -> List[WalletCluster]:
        """Get wallet clusters, optionally filtered by type"""
        clusters = list(self.wallet_clusters.values())
        if cluster_type:
            clusters = [c for c in clusters if c.cluster_type == cluster_type]
        return clusters

    async def get_related_wallets(self, wallet_address: str, max_depth: int = 2) -> List[str]:
        """Get wallets related to a given wallet"""
        try:
            if wallet_address not in self.wallet_graph:
                return []

            # Find related wallets using BFS
            related = set()
            queue = [(wallet_address, 0)]
            visited = {wallet_address}

            while queue:
                current, depth = queue.pop(0)
                if depth >= max_depth:
                    continue

                neighbors = list(self.wallet_graph.neighbors(current))
                for neighbor in neighbors:
                    if neighbor not in visited:
                        visited.add(neighbor)
                        related.add(neighbor)
                        queue.append((neighbor, depth + 1))

            return list(related)

        except Exception as e:
            logger.error(f"Error getting related wallets: {e}")
            return []

    async def get_metrics(self) -> Dict[str, Any]:
        """Get analyzer performance metrics"""
        uptime = time.time() - self.metrics["start_time"]

        return {
            **self.metrics,
            "uptime_seconds": uptime,
            "wallet_profiles_count": len(self.wallet_profiles),
            "transaction_count": len(self.transaction_history),
            "cluster_count": len(self.wallet_clusters),
            "graph_nodes": self.wallet_graph.number_of_nodes(),
            "graph_edges": self.wallet_graph.number_of_edges(),
            "last_analysis": self.last_analysis_time
        }

    async def shutdown(self):
        """Shutdown the analyzer and cleanup resources"""
        logger.info("Shutting down Wallet Graph Analyzer...")

        # Close connections
        if self.http_session:
            await self.http_session.close()

        if self.db_pool:
            await self.db_pool.close()

        if self.redis_client:
            await self.redis_client.close()

        logger.info("Wallet Graph Analyzer shutdown complete")

# ============================================================================
# Utility Functions
# ============================================================================

async def create_wallet_graph_analyzer(
    rpc_url: str,
    db_url: Optional[str] = None,
    redis_url: Optional[str] = None,
    config: Optional[Dict[str, Any]] = None
) -> WalletGraphAnalyzer:
    """
    Create and initialize wallet graph analyzer

    Args:
        rpc_url: Solana RPC endpoint
        db_url: PostgreSQL connection string
        redis_url: Redis connection string
        config: Configuration dictionary

    Returns:
        Initialized WalletGraphAnalyzer instance
    """
    analyzer = WalletGraphAnalyzer(rpc_url, db_url, redis_url, config)
    await analyzer.initialize()
    return analyzer

# ============================================================================
# Development Testing
# ============================================================================

async def development_test():
    """
    Development test function
    """
    logger.info("Starting Wallet Graph Analyzer development test...")

    # Mock configuration
    config = {
        "analysis_interval": 60,  # 1 minute for testing
        "max_graph_size": 1000,
        "min_transactions": 5
    }

    analyzer = WalletGraphAnalyzer(
        rpc_url="https://api.mainnet-beta.solana.com",
        config=config
    )

    try:
        # Initialize analyzer
        await analyzer.initialize()

        # Analyze graph
        metrics = await analyzer.analyze_wallet_graph()
        logger.info(f"Graph metrics: {metrics}")

        # Get smart money wallets
        smart_money = await analyzer.get_smart_money_wallets(10)
        logger.info(f"Found {len(smart_money)} smart money wallets")

        # Get analyzer metrics
        analyzer_metrics = await analyzer.get_metrics()
        logger.info(f"Analyzer metrics: {analyzer_metrics}")

    finally:
        await analyzer.shutdown()
        logger.info("Development test completed")

if __name__ == "__main__":
    asyncio.run(development_test())