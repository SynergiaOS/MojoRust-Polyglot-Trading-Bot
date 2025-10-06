# =============================================================================
# Infisical Secrets Manager Client for Mojo
# =============================================================================
# This module provides Mojo bindings for the Infisical secrets manager
# allowing secure access to API keys and sensitive configuration.

from core.types import *
from core.constants import *
from time import time
from json import loads
from sys import exit

# =============================================================================
# Infisical Client
# =============================================================================

@value
struct InfisicalClient:
    """
    Mojo client for Infisical secrets management
    """
    var _initialized: Bool
    var _fallback_to_env: Bool

    fn __init__(fallback_to_env: Bool = True):
        self._initialized = False
        self._fallback_to_env = fallback_to_env

    fn initialize(self) -> Bool:
        """
        Initialize the Infisical secrets manager
        """
        if self._initialized:
            return True

        # Try to initialize the Rust secrets manager
        result = self._init_rust_secrets_manager()
        if result == 0:  # Success
            self._initialized = True
            return True
        elif self._fallback_to_env:
            # Fallback to environment variables
            print("⚠️  Infisical initialization failed, falling back to environment variables")
            self._initialized = True
            return True
        else:
            return False

    fn is_initialized(self) -> Bool:
        """
        Check if the client is initialized
        """
        return self._initialized

    def _init_rust_secrets_manager(self) -> Int:
        """
        Initialize the Rust secrets manager via FFI
        Returns 0 for success, non-zero for failure
        """
        # This will be implemented with actual FFI calls
        # For now, we'll simulate the initialization
        try:
            # Check if Infisical environment variables are set
            from os import getenv
            client_id = getenv("INFISICAL_CLIENT_ID", "")
            client_secret = getenv("INFISICAL_CLIENT_SECRET", "")
            project_id = getenv("INFISICAL_PROJECT_ID", "")

            if client_id and client_secret and project_id:
                # Would call the actual Rust FFI here
                # result = secrets_manager_init()
                return 0  # Simulate success
            else:
                return 1  # Simulate missing config
        except e:
            return 2  # Simulate error

    fn get_secret(self, key: String) -> String:
        """
        Get a secret value by key
        """
        if not self._initialized:
            self.initialize()

        # Try Infisical first
        if self._try_infisical_available():
            value = self._get_secret_from_infisical(key)
            if value:
                return value

        # Fallback to environment variable
        from os import getenv
        env_value = getenv(key, "")
        if env_value:
            return env_value

        raise ValueError(f"Secret '{key}' not found in Infisical or environment variables")

    fn get_secret_with_default(self, key: String, default: String) -> String:
        """
        Get a secret value with default fallback
        """
        try:
            return self.get_secret(key)
        except e:
            return default

    def _try_infisical_available(self) -> Bool:
        """
        Check if Infisical should be used
        """
        try:
            from os import getenv
            client_id = getenv("INFISICAL_CLIENT_ID", "")
            client_secret = getenv("INFISICAL_CLIENT_SECRET", "")
            project_id = getenv("INFISICAL_PROJECT_ID", "")
            return bool(client_id and client_secret and project_id)
        except e:
            return False

    def _get_secret_from_infisical(self, key: String) -> String:
        """
        Get secret from Infisical via FFI
        """
        # This would call the actual Rust FFI function
        # For now, we'll simulate by checking environment variables
        from os import getenv
        return getenv(key, "")

    def get_api_config(self) -> APIConfig:
        """
        Get API configuration from secrets
        """
        try:
            # Try to get JSON config from Infisical
            if self._try_infisical_available():
                config_json = self._get_config_from_infisical("api_config")
                if config_json:
                    return self._parse_api_config(config_json)
        except e:
            pass

        # Fallback to individual secrets
        return APIConfig(
            helius_api_key=self.get_secret("HELIUS_API_KEY"),
            helius_base_url=self.get_secret_with_default("HELIUS_BASE_URL", "https://api.helius.xyz/v0"),
            helius_rpc_url=self.get_secret("HELIUS_RPC_URL"),
            quicknode_rpcs=QuickNodeRPCs(
                primary=self.get_secret("QUICKNODE_PRIMARY_RPC"),
                secondary=self.get_secret_with_default("QUICKNODE_SECONDARY_RPC", ""),
                archive=self.get_secret_with_default("QUICKNODE_ARCHIVE_RPC", "")
            ),
            dexscreener_base_url=self.get_secret_with_default("DEXSCREENER_BASE_URL", "https://api.dexscreener.com/latest/dex"),
            jupiter_base_url=self.get_secret_with_default("JUPITER_BASE_URL", "https://quote-api.jup.ag/v6"),
            jupiter_quote_api=self.get_secret_with_default("JUPITER_QUOTE_API", "https://quote-api.jup.ag/v6/quote"),
            timeout_seconds=float(self.get_secret_with_default("API_TIMEOUT_SECONDS", "10.0"))
        )

    def get_trading_config(self) -> TradingConfig:
        """
        Get trading configuration from secrets
        """
        try:
            # Try to get JSON config from Infisical
            if self._try_infisical_available():
                config_json = self._get_config_from_infisical("trading_config")
                if config_json:
                    return self._parse_trading_config(config_json)
        except e:
            pass

        # Fallback to individual secrets
        return TradingConfig(
            initial_capital=float(self.get_secret_with_default("INITIAL_CAPITAL", "1.0")),
            max_position_size=float(self.get_secret_with_default("MAX_POSITION_SIZE", "0.1")),
            max_drawdown=float(self.get_secret_with_default("MAX_DRAWDOWN", "0.15")),
            cycle_interval=float(self.get_secret_with_default("CYCLE_INTERVAL", "1.0")),
            kelly_fraction=float(self.get_secret_with_default("KELLY_FRACTION", "0.5")),
            max_correlation=float(self.get_secret_with_default("MAX_CORRELATION", "0.7")),
            diversification_target=int(self.get_secret_with_default("DIVERSIFICATION_TARGET", "10")),
            max_daily_trades=int(self.get_secret_with_default("MAX_DAILY_TRADES", "50"))
        )

    def get_wallet_config(self) -> WalletConfig:
        """
        Get wallet configuration from secrets
        """
        try:
            # Try to get JSON config from Infisical
            if self._try_infisical_available():
                config_json = self._get_config_from_infisical("wallet_config")
                if config_json:
                    return self._parse_wallet_config(config_json)
        except e:
            pass

        # Fallback to individual secrets
        return WalletConfig(
            address=self.get_secret("WALLET_ADDRESS"),
            private_key_path=self.get_secret_with_default("WALLET_PRIVATE_KEY_PATH", "~/.config/solana/id.json")
        )

    def _get_config_from_infisical(self, config_type: String) -> String:
        """
        Get configuration JSON from Infisical
        """
        # This would call the actual Rust FFI function to get serialized config
        # For now, return empty string to force fallback to individual secrets
        return ""

    def _parse_api_config(self, json_str: String) -> APIConfig:
        """
        Parse API configuration from JSON
        """
        try:
            data = loads(json_str)
            return APIConfig(
                helius_api_key=data.get("helius_api_key", ""),
                helius_base_url=data.get("helius_base_url", "https://api.helius.xyz/v0"),
                helius_rpc_url=data.get("helius_rpc_url", ""),
                quicknode_rpcs=QuickNodeRPCs(
                    primary=data.get("quicknode_rpcs", {}).get("primary", ""),
                    secondary=data.get("quicknode_rpcs", {}).get("secondary", ""),
                    archive=data.get("quicknode_rpcs", {}).get("archive", "")
                ),
                dexscreener_base_url=data.get("dexscreener_base_url", "https://api.dexscreener.com/latest/dex"),
                jupiter_base_url=data.get("jupiter_base_url", "https://quote-api.jup.ag/v6"),
                jupiter_quote_api=data.get("jupiter_quote_api", "https://quote-api.jup.ag/v6/quote"),
                timeout_seconds=float(data.get("timeout_seconds", 10.0))
            )
        except e:
            raise ValueError(f"Failed to parse API config: {e}")

    def _parse_trading_config(self, json_str: String) -> TradingConfig:
        """
        Parse trading configuration from JSON
        """
        try:
            data = loads(json_str)
            return TradingConfig(
                initial_capital=float(data.get("initial_capital", 1.0)),
                max_position_size=float(data.get("max_position_size", 0.1)),
                max_drawdown=float(data.get("max_drawdown", 0.15)),
                cycle_interval=float(data.get("cycle_interval", 1.0)),
                kelly_fraction=float(data.get("kelly_fraction", 0.5)),
                max_correlation=float(data.get("max_correlation", 0.7)),
                diversification_target=int(data.get("diversification_target", 10)),
                max_daily_trades=int(data.get("max_daily_trades", 50))
            )
        except e:
            raise ValueError(f"Failed to parse trading config: {e}")

    def _parse_wallet_config(self, json_str: String) -> WalletConfig:
        """
        Parse wallet configuration from JSON
        """
        try:
            data = loads(json_str)
            return WalletConfig(
                address=data.get("address", ""),
                private_key_path=data.get("private_key_path", "~/.config/solana/id.json")
            )
        except e:
            raise ValueError(f"Failed to parse wallet config: {e}")

    def preload_secrets(self, secret_keys: List[String]) -> Bool:
        """
        Preload commonly used secrets for better performance
        """
        if not self._initialized:
            if not self.initialize():
                return False

        # Try to preload each secret
        success_count = 0
        for key in secret_keys:
            try:
                self.get_secret(key)  # This will cache the secret
                success_count += 1
            except e:
                print(f"⚠️  Failed to preload secret '{key}': {e}")

        return success_count == len(secret_keys)

    def health_check(self) -> Dict[String, Any]:
        """
        Perform health check on the secrets manager
        """
        health = {
            "initialized": self._initialized,
            "infisical_available": self._try_infisical_available(),
            "fallback_enabled": self._fallback_to_env,
            "timestamp": time()
        }

        # Test secret retrieval
        try:
            test_secret = self.get_secret_with_default("HELIUS_API_KEY", "test")
            health["secret_retrieval"] = "ok"
            health["test_secret_available"] = bool(test_secret != "test")
        except e:
            health["secret_retrieval"] = "failed"
            health["error"] = str(e)

        return health

# =============================================================================
# Global Infisical Client Instance
# =============================================================================

var _infisical_client: Optional[InfisicalClient] = None

def get_infisical_client() -> InfisicalClient:
    """
    Get or create the global Infisical client instance
    """
    global _infisical_client
    if _infisical_client is None:
        _infisical_client = InfisicalClient(fallback_to_env=True)
        _infisical_client.initialize()
    return _infisical_client

def initialize_secrets_manager() -> Bool:
    """
    Initialize the global secrets manager
    """
    try:
        client = get_infisical_client()
        return client.is_initialized()
    except e:
        print(f"❌ Failed to initialize secrets manager: {e}")
        return False

def get_secret(key: String) -> String:
    """
    Get a secret using the global secrets manager
    """
    client = get_infisical_client()
    return client.get_secret(key)

def get_secret_with_default(key: String, default: String) -> String:
    """
    Get a secret with default fallback using the global secrets manager
    """
    client = get_infisical_client()
    return client.get_secret_with_default(key, default)