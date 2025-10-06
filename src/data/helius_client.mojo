# =============================================================================
# Helius API Client Module
# =============================================================================

from json import loads, dumps
from time import time
from sys import exit
from collections import Dict, List
from core.types import TokenMetadata, SocialMetrics, BlockchainMetrics
from core.constants import HELIUS_BASE_URL, DEFAULT_TIMEOUT_SECONDS

@value
struct HeliusClient:
    """
    Helius API client for token metadata and on-chain data
    """
    var api_key: String
    var base_url: String
    var timeout_seconds: Float

    fn __init__(api_key: String, base_url: String = HELIUS_BASE_URL, timeout_seconds: Float = DEFAULT_TIMEOUT_SECONDS):
        self.api_key = api_key
        self.base_url = base_url
        self.timeout_seconds = timeout_seconds

    fn get_token_metadata(self, token_address: String) -> TokenMetadata:
        """
        Get token metadata from Helius API
        """
        if not token_address or token_address == "":
            return TokenMetadata()

        try:
            # Construct API URL
            url = f"{self.base_url}/tokens/metadata?api_key={self.api_key}&tokenAddress={token_address}"

            # Mock implementation for now - in real scenario, make HTTP request
            # For testing purposes, return mock data
            mock_data = self._get_mock_token_metadata(token_address)
            return mock_data

        except e:
            print(f"⚠️  Error fetching token metadata from Helius: {e}")
            return TokenMetadata(address=token_address)

    def _get_mock_token_metadata(self, token_address: String) -> TokenMetadata:
        """
        Mock token metadata for testing
        """
        return TokenMetadata(
            address=token_address,
            name="Mock Token",
            symbol="MOCK",
            decimals=9,
            supply=1000000000.0,
            holder_count=150,
            creation_timestamp=time() - 86400.0,  # 1 day ago
            creator="11111111111111111111111111111111",
            image_url="https://example.com/token.png",
            description="Mock token for testing"
        )

    fn get_holder_data(self, token_address: String) -> SocialMetrics:
        """
        Get holder distribution data
        """
        try:
            # Mock implementation
            return SocialMetrics(
                twitter_mentions=50,
                telegram_members=200,
                discord_members=150,
                reddit_posts=25,
                social_volume=1000.0,
                social_sentiment=0.3
            )
        except e:
            print(f"⚠️  Error fetching holder data: {e}")
            return SocialMetrics()

    def get_transaction_history(self, token_address: String, limit: Int = 100) -> BlockchainMetrics:
        """
        Get transaction history for wash trading detection
        """
        try:
            # Mock implementation
            return BlockchainMetrics(
                unique_traders=45,
                wash_trading_score=0.2,  # Low wash trading score
                holder_distribution_score=0.7,  # Well distributed
                transaction_frequency=2.5,
                large_transactions=3,
                liquidity_lock_ratio=0.8  # 80% liquidity locked
            )
        except e:
            print(f"⚠️  Error fetching transaction history: {e}")
            return BlockchainMetrics()

    fn health_check(self) -> Bool:
        """
        Check if Helius API is accessible
        """
        try:
            # Simple health check - try to fetch SOL token metadata
            sol_token = "So11111111111111111111111111111111111111112"
            result = self.get_token_metadata(sol_token)
            return result.address == sol_token
        except e:
            print(f"❌ Helius health check failed: {e}")
            return False

    fn get_multiple_token_metadata(self, token_addresses: List[String]) -> List[TokenMetadata]:
        """
        Get metadata for multiple tokens in batch
        """
        results = []
        for address in token_addresses:
            metadata = self.get_token_metadata(address)
            results.append(metadata)
        return results

    def analyze_token_age(self, token_address: String) -> Float:
        """
        Analyze token age in hours
        """
        metadata = self.get_token_metadata(token_address)
        if metadata.creation_timestamp > 0:
            age_seconds = time() - metadata.creation_timestamp
            return age_seconds / 3600.0  # Convert to hours
        return 0.0

    def get_top_holders(self, token_address: String, limit: Int = 10) -> List[Dict[String, Any]]:
        """
        Get top token holders for concentration analysis
        """
        try:
            # Mock implementation - return mock holder data
            mock_holders = []
            for i in range(limit):
                holder = {
                    "address": f"holder_{i}_address",
                    "amount": 1000000.0 / (i + 1),  # Decreasing amounts
                    "percentage": 0.1 / (i + 1)     # Decreasing percentages
                }
                mock_holders.append(holder)
            return mock_holders
        except e:
            print(f"⚠️  Error fetching top holders: {e}")
            return []

    def check_liquidity_locks(self, token_address: String) -> Dict[String, Any]:
        """
        Check if liquidity is locked
        """
        try:
            # Mock implementation
            return {
                "is_locked": True,
                "lock_amount": 50000.0,
                "lock_duration_days": 365,
                "lock_contract": "lock_contract_address",
                "percentage_locked": 0.85
            }
        except e:
            print(f"⚠️  Error checking liquidity locks: {e}")
            return {"is_locked": False}

    def get_creation_info(self, token_address: String) -> Dict[String, Any]:
        """
        Get token creation information
        """
        try:
            metadata = self.get_token_metadata(token_address)
            return {
                "creator": metadata.creator,
                "creation_timestamp": metadata.creation_timestamp,
                "initial_supply": metadata.supply,
                "mint_authority": "mint_authority_address",
                "freeze_authority": "freeze_authority_address"
            }
        except e:
            print(f"⚠️  Error fetching creation info: {e}")
            return {}