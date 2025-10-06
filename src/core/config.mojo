# =============================================================================
# Configuration Management Module
# =============================================================================

from os import getenv, environ
from json import loads
from sys import exit

# =============================================================================
# API Configuration
# =============================================================================

@value
struct APIConfig:
    """
    Configuration for external APIs
    """
    var helius_api_key: String
    var helius_base_url: String
    var helius_rpc_url: String
    var quicknode_rpcs: QuickNodeRPCs
    var dexscreener_base_url: String
    var jupiter_base_url: String
    var jupiter_quote_api: String
    var timeout_seconds: Float

@value
struct QuickNodeRPCs:
    """
    QuickNode RPC endpoints
    """
    var primary: String
    var secondary: String
    var archive: String

    fn __init__(primary: String, secondary: String = "", archive: String = ""):
        self.primary = primary
        self.secondary = secondary if secondary else primary
        self.archive = archive if archive else primary

# =============================================================================
# Trading Configuration
# =============================================================================

@value
struct TradingConfig:
    """
    Core trading parameters
    """
    var initial_capital: Float
    var max_position_size: Float
    var min_position_size: Float
    var max_drawdown: Float
    var daily_trade_limit: Int
    var kelly_fraction: Float
    var max_portfolio_risk: Float
    var execution_mode: String
    var cycle_interval: Float

# =============================================================================
# Strategy Configuration
# =============================================================================

@value
struct StrategyConfig:
    """
    Strategy-specific parameters
    """
    var rsi_period: Int
    var oversold_threshold: Float
    var overbought_threshold: Float
    var min_confluence_strength: Float
    var enable_arbitrage: Bool
    var enable_momentum: Bool
    var enable_mean_reversion: Bool
    var support_distance: Float
    var atr_multiplier: Float

# =============================================================================
# Risk Configuration
# =============================================================================

@value
struct RiskConfig:
    """
    Risk management parameters
    """
    var max_correlation: Float
    var diversification_target: Int
    var circuit_breaker_threshold: Float
    var stop_loss_method: String
    var min_liquidity: Float
    var min_volume: Float
    var max_volatility: Float

# =============================================================================
# Execution Configuration
# =============================================================================

@value
struct ExecutionConfig:
    """
    Trade execution parameters
    """
    var max_slippage: Float
    var max_priority_fee: Float
    var transaction_timeout: Int
    var retry_attempts: Int
    var confirmation_timeout: Int
    var gas_optimization: Bool

# =============================================================================
# Database Configuration
# =============================================================================

@value
struct DatabaseConfig:
    """
    Database connection parameters
    """
    var timescale_url: String
    var redis_url: String
    var connection_pool_size: Int
    var query_timeout: Int
    var data_retention_days: Int
    var metrics_retention_days: Int
    var timescale_enabled: Bool
    var redis_enabled: Bool

# =============================================================================
# Monitoring Configuration
# =============================================================================

@value
struct MonitoringConfig:
    """
    Monitoring and logging parameters
    """
    var prometheus_port: Int
    var log_level: String
    var log_format: String
    var metrics_interval: Int
    var enable_alerts: Bool
    var alert_webhook_url: String

# =============================================================================
# Main Configuration Class
# =============================================================================

@value
struct Config:
    """
    Centralized configuration manager
    """
    var api: APIConfig
    var trading: TradingConfig
    var strategy: StrategyConfig
    var risk: RiskConfig
    var execution: ExecutionConfig
    var database: DatabaseConfig
    var monitoring: MonitoringConfig

    # Environment-specific
    var trading_env: String
    var wallet_address: String
    var wallet_private_key_path: String

    @staticmethod
    fn load_from_env() -> Config:
        """
        Load configuration from environment variables
        """
        # Environment
        trading_env = getenv("TRADING_ENV", "development")

        # API Configuration
        helius_api_key = getenv("HELIUS_API_KEY", "")
        helius_base_url = getenv("HELIUS_BASE_URL", "https://api.helius.xyz/v0")
        helius_rpc_url = getenv("HELIUS_RPC_URL", "")

        quicknode_primary = getenv("QUICKNODE_PRIMARY_RPC", "")
        quicknode_secondary = getenv("QUICKNODE_SECONDARY_RPC", quicknode_primary)
        quicknode_archive = getenv("QUICKNODE_ARCHIVE_RPC", quicknode_primary)
        quicknode_rpcs = QuickNodeRPCs(quicknode_primary, quicknode_secondary, quicknode_archive)

        dexscreener_base_url = getenv("DEXSCREENER_BASE_URL", "https://api.dexscreener.com/latest")
        jupiter_base_url = getenv("JUPITER_BASE_URL", "https://quote-api.jup.ag")
        jupiter_quote_api = getenv("JUPITER_QUOTE_API", "https://quote-api.jup.ag/v6")

        timeout_seconds = float(getenv("API_TIMEOUT_SECONDS", "5.0"))

        api_config = APIConfig(
            helius_api_key=helius_api_key,
            helius_base_url=helius_base_url,
            helius_rpc_url=helius_rpc_url,
            quicknode_rpcs=quicknode_rpcs,
            dexscreener_base_url=dexscreener_base_url,
            jupiter_base_url=jupiter_base_url,
            jupiter_quote_api=jupiter_quote_api,
            timeout_seconds=timeout_seconds
        )

        # Trading Configuration
        initial_capital = float(getenv("INITIAL_CAPITAL", "1.0"))
        max_position_size = float(getenv("MAX_POSITION_SIZE", "0.10"))
        min_position_size = float(getenv("MIN_POSITION_SIZE", "0.005"))
        max_drawdown = float(getenv("MAX_DRAWDOWN", "0.15"))
        daily_trade_limit = int(getenv("DAILY_TRADE_LIMIT", "100"))
        kelly_fraction = float(getenv("KELLY_FRACTION", "0.5"))
        max_portfolio_risk = float(getenv("MAX_PORTFOLIO_RISK", "0.02"))
        execution_mode = getenv("EXECUTION_MODE", "paper")
        cycle_interval = float(getenv("CYCLE_INTERVAL", "1.0"))

        trading_config = TradingConfig(
            initial_capital=initial_capital,
            max_position_size=max_position_size,
            min_position_size=min_position_size,
            max_drawdown=max_drawdown,
            daily_trade_limit=daily_trade_limit,
            kelly_fraction=kelly_fraction,
            max_portfolio_risk=max_portfolio_risk,
            execution_mode=execution_mode,
            cycle_interval=cycle_interval
        )

        # Strategy Configuration
        rsi_period = int(getenv("RSI_PERIOD", "14"))
        oversold_threshold = float(getenv("OVERSOLD_THRESHOLD", "25.0"))
        overbought_threshold = float(getenv("OVERBOUGHT_THRESHOLD", "75.0"))
        min_confluence_strength = float(getenv("MIN_CONFLUENCE_STRENGTH", "0.7"))
        enable_arbitrage = getenv("ENABLE_ARBITRAGE", "true").lower() == "true"
        enable_momentum = getenv("ENABLE_MOMENTUM", "true").lower() == "true"
        enable_mean_reversion = getenv("ENABLE_MEAN_REVERSION", "false").lower() == "true"
        support_distance = float(getenv("SUPPORT_DISTANCE", "0.15"))
        atr_multiplier = float(getenv("ATR_MULTIPLIER", "1.5"))

        strategy_config = StrategyConfig(
            rsi_period=rsi_period,
            oversold_threshold=oversold_threshold,
            overbought_threshold=overbought_threshold,
            min_confluence_strength=min_confluence_strength,
            enable_arbitrage=enable_arbitrage,
            enable_momentum=enable_momentum,
            enable_mean_reversion=enable_mean_reversion,
            support_distance=support_distance,
            atr_multiplier=atr_multiplier
        )

        # Risk Configuration
        max_correlation = float(getenv("MAX_CORRELATION", "0.7"))
        diversification_target = int(getenv("DIVERSIFICATION_TARGET", "10"))
        circuit_breaker_threshold = float(getenv("CIRCUIT_BREAKER_DRAWDOWN", "0.10"))
        stop_loss_method = getenv("STOP_LOSS_METHOD", "support_based")
        min_liquidity = float(getenv("MIN_LIQUIDITY", "10000.0"))
        min_volume = float(getenv("MIN_VOLUME", "5000.0"))
        max_volatility = float(getenv("MAX_VOLATILITY", "2.0"))

        risk_config = RiskConfig(
            max_correlation=max_correlation,
            diversification_target=diversification_target,
            circuit_breaker_threshold=circuit_breaker_threshold,
            stop_loss_method=stop_loss_method,
            min_liquidity=min_liquidity,
            min_volume=min_volume,
            max_volatility=max_volatility
        )

        # Execution Configuration
        max_slippage = float(getenv("MAX_SLIPPAGE", "0.02"))
        max_priority_fee = float(getenv("MAX_PRIORITY_FEE", "0.001"))
        transaction_timeout = int(getenv("TRANSACTION_TIMEOUT", "30"))
        retry_attempts = int(getenv("RETRY_ATTEMPTS", "3"))
        confirmation_timeout = int(getenv("CONFIRMATION_TIMEOUT", "30"))
        gas_optimization = getenv("GAS_OPTIMIZATION", "true").lower() == "true"

        execution_config = ExecutionConfig(
            max_slippage=max_slippage,
            max_priority_fee=max_priority_fee,
            transaction_timeout=transaction_timeout,
            retry_attempts=retry_attempts,
            confirmation_timeout=confirmation_timeout,
            gas_optimization=gas_optimization
        )

        # Database Configuration
        timescale_url = getenv("TIMESCALEDB_URL", "postgresql://trading_user:trading_password@localhost:5432/trading_db")
        redis_url = getenv("REDIS_URL", "redis://localhost:6379")
        connection_pool_size = int(getenv("DB_POOL_SIZE", "10"))
        query_timeout = int(getenv("DB_CONNECTION_TIMEOUT", "30"))
        data_retention_days = int(getenv("DATA_RETENTION_DAYS", "90"))
        metrics_retention_days = int(getenv("METRICS_RETENTION_DAYS", "30"))
        timescale_enabled = timescale_url != ""
        redis_enabled = redis_url != ""

        database_config = DatabaseConfig(
            timescale_url=timescale_url,
            redis_url=redis_url,
            connection_pool_size=connection_pool_size,
            query_timeout=query_timeout,
            data_retention_days=data_retention_days,
            metrics_retention_days=metrics_retention_days,
            timescale_enabled=timescale_enabled,
            redis_enabled=redis_enabled
        )

        # Monitoring Configuration
        prometheus_port = int(getenv("PROMETHEUS_PORT", "9090"))
        log_level = getenv("LOG_LEVEL", "INFO")
        log_format = getenv("LOG_FORMAT", "json")
        metrics_interval = int(getenv("METRICS_INTERVAL", "60"))
        enable_alerts = getenv("ENABLE_ALERTS", "true").lower() == "true"
        alert_webhook_url = getenv("ALERT_WEBHOOK_URL", "")

        monitoring_config = MonitoringConfig(
            prometheus_port=prometheus_port,
            log_level=log_level,
            log_format=log_format,
            metrics_interval=metrics_interval,
            enable_alerts=enable_alerts,
            alert_webhook_url=alert_webhook_url
        )

        # Wallet configuration
        wallet_address = getenv("WALLET_ADDRESS", "")
        wallet_private_key_path = getenv("WALLET_PRIVATE_KEY_PATH", "")

        return Config(
            api=api_config,
            trading=trading_config,
            strategy=strategy_config,
            risk=risk_config,
            execution=execution_config,
            database=database_config,
            monitoring=monitoring_config,
            trading_env=trading_env,
            wallet_address=wallet_address,
            wallet_private_key_path=wallet_private_key_path
        )

    @staticmethod
    fn load_from_file(file_path: String) -> Config:
        """
        Load configuration from TOML/JSON file
        """
        # This would implement file-based configuration loading
        # For now, fall back to environment variables
        return Config.load_from_env()

    fn validate(self) -> Bool:
        """
        Validate configuration values
        """
        # Check required API keys
        if not self.api.helius_api_key:
            print("❌ Missing HELIUS_API_KEY")
            return False

        if not self.api.quicknode_rpcs.primary:
            print("❌ Missing QUICKNODE_PRIMARY_RPC")
            return False

    
        if not self.wallet_address:
            print("❌ Missing WALLET_ADDRESS")
            return False

        # Validate numeric ranges
        if self.trading.initial_capital <= 0:
            print("❌ Initial capital must be greater than 0")
            return False

        if not (0 < self.trading.max_position_size <= 1):
            print("❌ Max position size must be between 0 and 1")
            return False

        if not (0 < self.trading.max_drawdown <= 1):
            print("❌ Max drawdown must be between 0 and 1")
            return False

        if not (0 < self.strategy.rsi_period <= 100):
            print("❌ RSI period must be between 1 and 100")
            return False

        if not (0 < self.strategy.oversold_threshold < 100):
            print("❌ Oversold threshold must be between 0 and 100")
            return False

        if not (0 < self.strategy.overbought_threshold <= 100):
            print("❌ Overbought threshold must be between 0 and 100")
            return False

        if self.strategy.oversold_threshold >= self.strategy.overbought_threshold:
            print("❌ Oversold threshold must be less than overbought threshold")
            return False

        # Validate execution mode
        valid_modes = ["paper", "live", "test"]
        if self.trading.execution_mode not in valid_modes:
            print(f"❌ Invalid execution mode: {self.trading.execution_mode}")
            return False

        # Validate environment
        valid_envs = ["development", "staging", "production"]
        if self.trading_env not in valid_envs:
            print(f"❌ Invalid environment: {self.trading_env}")
            return False

        return True

    fn get_environment(self) -> String:
        """
        Get current environment
        """
        return self.trading_env

    fn is_production(self) -> Bool:
        """
        Check if running in production mode
        """
        return self.trading_env == "production"

    fn is_development(self) -> Bool:
        """
        Check if running in development mode
        """
        return self.trading_env == "development"

    fn is_paper_trading(self) -> Bool:
        """
        Check if running in paper trading mode
        """
        return self.trading.execution_mode == "paper"

    def print_summary(self):
        """
        Print configuration summary for debugging
        """
        print("📋 Configuration Summary:")
        print(f"   Environment: {self.trading_env}")
        print(f"   Execution Mode: {self.trading.execution_mode}")
        print(f"   Initial Capital: {self.trading.initial_capital} SOL")
        print(f"   Max Position Size: {self.trading.max_position_size:.1%}")
        print(f"   Max Drawdown: {self.trading.max_drawdown:.1%}")
        print(f"   RSI Period: {self.strategy.rsi_period}")
        print(f"   Oversold Threshold: {self.strategy.oversold_threshold}")
        print(f"   Overbought Threshold: {self.strategy.overbought_threshold}")
        print(f"   Min Confluence Strength: {self.strategy.min_confluence_strength}")
        print(f"   Database Enabled: {self.database.timescale_enabled}")
        print(f"   Redis Enabled: {self.database.redis_enabled}")
        print(f"   Alerts Enabled: {self.monitoring.enable_alerts}")

# =============================================================================
# Configuration Loading Function
# =============================================================================

def load_config(config_path: String = "") -> Config:
    """
    Load configuration from file or environment
    """
    if config_path and config_path != "":
        try:
            config = Config.load_from_file(config_path)
            print(f"✅ Configuration loaded from file: {config_path}")
        except e as e:
            print(f"⚠️  Failed to load config file: {e}")
            print("🔄 Loading from environment variables...")
            config = Config.load_from_env()
    else:
        config = Config.load_from_env()
        print("🔄 Configuration loaded from environment variables")

    # Validate configuration
    if not config.validate():
        print("❌ Configuration validation failed")
        exit(1)

    print("✅ Configuration validation passed")

    # Print summary in development mode
    if config.is_development():
        config.print_summary()

    return config