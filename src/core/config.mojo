# =============================================================================
# Configuration Management Module
# =============================================================================

from os import getenv, environ
from json import loads
from sys import exit
from infisical_client import get_infisical_client
try:
    from tomllib import loads as toml_loads
except ImportError:
    from tomli import loads as toml_loads

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

# =============================================================================
# Wallet Configuration
# =============================================================================

@value
struct WalletConfig:
    """
    Wallet configuration parameters
    """
    var address: String
    var private_key_path: String

    fn __init__(address: String = "", private_key_path: String = ""):
        self.address = address
        self.private_key_path = private_key_path

# =============================================================================
# QuickNode RPC endpoints
# =============================================================================

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
    var gas_cost: Float           # Gas cost in SOL
    var base_slippage: Float       # Base slippage factor
    var default_decimals: Int      # Default token decimals
    var min_success_rate: Float    # Minimum success rate

# =============================================================================
# Database Configuration
# =============================================================================

# =============================================================================
# Circuit Breakers Configuration
# =============================================================================

@value
struct CircuitBreakersConfig:
    """
    Circuit breaker safety parameters
    """
    var max_drawdown: Float
    var max_consecutive_losses: Int
    var max_daily_loss_percentage: Float
    var max_position_concentration: Float
    var min_trade_interval_seconds: Int
    var rapid_drawdown_threshold: Float

    fn __init__(
        max_drawdown: Float = 0.15,
        max_consecutive_losses: Int = 5,
        max_daily_loss_percentage: Float = 0.10,
        max_position_concentration: Float = 0.30,
        min_trade_interval_seconds: Int = 60,
        rapid_drawdown_threshold: Float = 0.05
    ):
        self.max_drawdown = max_drawdown
        self.max_consecutive_losses = max_consecutive_losses
        self.max_daily_loss_percentage = max_daily_loss_percentage
        self.max_position_concentration = max_position_concentration
        self.min_trade_interval_seconds = min_trade_interval_seconds
        self.rapid_drawdown_threshold = rapid_drawdown_threshold

# =============================================================================
# Database Configuration
# =============================================================================

@value
struct DatabaseConfig:
    """
    Database connection parameters
    """
    var enabled: Bool
    var host: String
    var port: Int
    var database: String
    var user: String
    var password_env: String
    var max_connections: Int
    var batch_size: Int
    var auto_flush_interval_seconds: Int

    fn __init__(
        enabled: Bool = False,
        host: String = "localhost",
        port: Int = 5432,
        database: String = "trading_bot",
        user: String = "trader",
        password_env: String = "DB_PASSWORD",
        max_connections: Int = 10,
        batch_size: Int = 100,
        auto_flush_interval_seconds: Int = 60
    ):
        self.enabled = enabled
        self.host = host
        self.port = port
        self.database = database
        self.user = user
        self.password_env = password_env
        self.max_connections = max_connections
        self.batch_size = batch_size
        self.auto_flush_interval_seconds = auto_flush_interval_seconds

# =============================================================================
# Alert System Configuration
# =============================================================================

@value
struct AlertsConfig:
    """
    Alert system parameters
    """
    var enabled: Bool
    var channels: List[String]
    var webhook_url_env: String
    var telegram_bot_token_env: String
    var telegram_chat_id_env: String
    var error_alert_cooldown: Int
    var performance_alert_cooldown: Int
    var trade_alert_cooldown: Int
    var performance_alert_threshold: Float

    fn __init__(
        enabled: Bool = True,
        channels: List[String] = ["console"],
        webhook_url_env: String = "DISCORD_WEBHOOK_URL",
        telegram_bot_token_env: String = "TELEGRAM_BOT_TOKEN",
        telegram_chat_id_env: String = "TELEGRAM_CHAT_ID",
        error_alert_cooldown: Int = 60,
        performance_alert_cooldown: Int = 300,
        trade_alert_cooldown: Int = 0,
        performance_alert_threshold: Float = 0.05
    ):
        self.enabled = enabled
        self.channels = channels
        self.webhook_url_env = webhook_url_env
        self.telegram_bot_token_env = telegram_bot_token_env
        self.telegram_chat_id_env = telegram_chat_id_env
        self.error_alert_cooldown = error_alert_cooldown
        self.performance_alert_cooldown = performance_alert_cooldown
        self.trade_alert_cooldown = trade_alert_cooldown
        self.performance_alert_threshold = performance_alert_threshold

# =============================================================================
# Filter Configuration
# =============================================================================

@value
struct FilterConfig:
    """
    Configuration for all spam filters and signal validation
    """
    # Instant Spam Detector (ultra-fast <10ms checks)
    var instant_min_volume_usd: Float
    var instant_min_liquidity_usd: Float
    var instant_min_confidence: Float
    var instant_extreme_rsi_low: Float
    var instant_extreme_rsi_high: Float

    # Spam Filter (aggressive 90%+ rejection)
    var spam_min_volume_usd: Float
    var spam_min_liquidity_usd: Float
    var spam_min_confidence: Float
    var spam_cooldown_seconds: Float
    var spam_max_signals_per_symbol: Int
    var spam_volume_quality_threshold: Float
    var spam_avg_tx_size_threshold: Float
    var spam_volume_consistency_threshold: Float
    var spam_volume_to_liquidity_ratio: Float
    var spam_wash_trading_threshold: Float
    var spam_high_frequency_threshold: Float
    var spam_large_tx_count: Int
    var spam_large_tx_liquidity: Float
    var spam_extreme_rsi_threshold: Float
    var spam_rapid_price_change: Float
    var spam_high_confidence_new_token: Float
    var spam_new_token_age_hours: Float
    var spam_careful_token_age_hours: Float
    var spam_expected_return_limit: Float
    var spam_min_stop_loss_distance: Float
    var spam_round_number_confidence: Float

    # Micro Timeframe Filter (ultra-strict for 1s-15s)
    var micro_min_volume_usd: Float
    var micro_min_confidence: Float
    var micro_cooldown_seconds: Float
    var micro_min_price_stability: Float
    var micro_max_price_change_5min: Float
    var micro_extreme_price_spike: Float
    var micro_volume_spike_ratio: Float
    var micro_extreme_price_change: Float
    var micro_max_holder_concentration: Float
    var micro_min_liquidity_ratio: Float
    var micro_min_rsi: Float
    var micro_max_rsi: Float
    var micro_volume_consistency: Float
    var micro_liquidity_multiplier: Float
    var micro_min_tx_size_ratio: Float
    var micro_max_tx_size_ratio: Float
    var micro_required_checks_percentage: Float

    fn __init__(
        # Instant Spam Detector
        instant_min_volume_usd: Float = 1000.0,
        instant_min_liquidity_usd: Float = 5000.0,
        instant_min_confidence: Float = 0.30,
        instant_extreme_rsi_low: Float = 5.0,
        instant_extreme_rsi_high: Float = 95.0,

        # Spam Filter
        spam_min_volume_usd: Float = 10000.0,
        spam_min_liquidity_usd: Float = 20000.0,
        spam_min_confidence: Float = 0.70,
        spam_cooldown_seconds: Float = 30.0,
        spam_max_signals_per_symbol: Int = 5,
        spam_volume_quality_threshold: Float = 0.6,
        spam_avg_tx_size_threshold: Float = 10.0,
        spam_volume_consistency_threshold: Float = 0.3,
        spam_volume_to_liquidity_ratio: Float = 10.0,
        spam_wash_trading_threshold: Float = 0.7,
        spam_high_frequency_threshold: Float = 100.0,
        spam_large_tx_count: Int = 10,
        spam_large_tx_liquidity: Float = 25000.0,
        spam_extreme_rsi_threshold: Float = 80.0,
        spam_rapid_price_change: Float = 50.0,
        spam_high_confidence_new_token: Float = 0.8,
        spam_new_token_age_hours: Float = 0.5,
        spam_careful_token_age_hours: Float = 2.0,
        spam_expected_return_limit: Float = 10.0,
        spam_min_stop_loss_distance: Float = 0.05,
        spam_round_number_confidence: Float = 0.85,

        # Micro Timeframe Filter
        micro_min_volume_usd: Float = 15000.0,
        micro_min_confidence: Float = 0.75,
        micro_cooldown_seconds: Float = 60.0,
        micro_min_price_stability: Float = 0.80,
        micro_max_price_change_5min: Float = 0.30,
        micro_extreme_price_spike: Float = 0.50,
        micro_volume_spike_ratio: Float = 3.0,
        micro_extreme_price_change: Float = 0.20,
        micro_max_holder_concentration: Float = 0.80,
        micro_min_liquidity_ratio: Float = 0.5,
        micro_min_rsi: Float = 20.0,
        micro_max_rsi: Float = 80.0,
        micro_volume_consistency: Float = 0.6,
        micro_liquidity_multiplier: Float = 1.5,
        micro_min_tx_size_ratio: Float = 0.001,
        micro_max_tx_size_ratio: Float = 0.10,
        micro_required_checks_percentage: Float = 0.75
    ):
        # Instant Spam Detector
        self.instant_min_volume_usd = instant_min_volume_usd
        self.instant_min_liquidity_usd = instant_min_liquidity_usd
        self.instant_min_confidence = instant_min_confidence
        self.instant_extreme_rsi_low = instant_extreme_rsi_low
        self.instant_extreme_rsi_high = instant_extreme_rsi_high

        # Spam Filter
        self.spam_min_volume_usd = spam_min_volume_usd
        self.spam_min_liquidity_usd = spam_min_liquidity_usd
        self.spam_min_confidence = spam_min_confidence
        self.spam_cooldown_seconds = spam_cooldown_seconds
        self.spam_max_signals_per_symbol = spam_max_signals_per_symbol
        self.spam_volume_quality_threshold = spam_volume_quality_threshold
        self.spam_avg_tx_size_threshold = spam_avg_tx_size_threshold
        self.spam_volume_consistency_threshold = spam_volume_consistency_threshold
        self.spam_volume_to_liquidity_ratio = spam_volume_to_liquidity_ratio
        self.spam_wash_trading_threshold = spam_wash_trading_threshold
        self.spam_high_frequency_threshold = spam_high_frequency_threshold
        self.spam_large_tx_count = spam_large_tx_count
        self.spam_large_tx_liquidity = spam_large_tx_liquidity
        self.spam_extreme_rsi_threshold = spam_extreme_rsi_threshold
        self.spam_rapid_price_change = spam_rapid_price_change
        self.spam_high_confidence_new_token = spam_high_confidence_new_token
        self.spam_new_token_age_hours = spam_new_token_age_hours
        self.spam_careful_token_age_hours = spam_careful_token_age_hours
        self.spam_expected_return_limit = spam_expected_return_limit
        self.spam_min_stop_loss_distance = spam_min_stop_loss_distance
        self.spam_round_number_confidence = spam_round_number_confidence

        # Micro Timeframe Filter
        self.micro_min_volume_usd = micro_min_volume_usd
        self.micro_min_confidence = micro_min_confidence
        self.micro_cooldown_seconds = micro_cooldown_seconds
        self.micro_min_price_stability = micro_min_price_stability
        self.micro_max_price_change_5min = micro_max_price_change_5min
        self.micro_extreme_price_spike = micro_extreme_price_spike
        self.micro_volume_spike_ratio = micro_volume_spike_ratio
        self.micro_extreme_price_change = micro_extreme_price_change
        self.micro_max_holder_concentration = micro_max_holder_concentration
        self.micro_min_liquidity_ratio = micro_min_liquidity_ratio
        self.micro_min_rsi = micro_min_rsi
        self.micro_max_rsi = micro_max_rsi
        self.micro_volume_consistency = micro_volume_consistency
        self.micro_liquidity_multiplier = micro_liquidity_multiplier
        self.micro_min_tx_size_ratio = micro_min_tx_size_ratio
        self.micro_max_tx_size_ratio = micro_max_tx_size_ratio
        self.micro_required_checks_percentage = micro_required_checks_percentage

# =============================================================================
# Sniper Filters Configuration
# =============================================================================

@value
struct SniperFilterConfig:
    """
    Configuration for PumpFun memecoin sniper filters
    """
    # LP Burn Requirements
    var min_lp_burn_rate: Float

    # Authority Requirements
    var revoke_authority_required: Bool

    # Custom TP/SL for Sniper Trades
    var tp_threshold: Float
    var sl_threshold: Float

    # Holder Distribution
    var max_top_holders_share: Float

    # Volume Requirements
    var min_active_volume: Float

    # Social Mentions Check
    var min_social_mentions: Int
    var social_check_enabled: Bool
    var social_check_window_minutes: Int

    # Honeypot Detection
    var honeypot_check: Bool

    fn __init__(
        # LP Burn Requirements
        min_lp_burn_rate: Float = 90.0,

        # Authority Requirements
        revoke_authority_required: Bool = True,

        # Custom TP/SL for Sniper Trades
        tp_threshold: Float = 1.5,
        sl_threshold: Float = 0.8,

        # Holder Distribution
        max_top_holders_share: Float = 30.0,

        # Volume Requirements
        min_active_volume: Float = 5000.0,

        # Social Mentions Check
        min_social_mentions: Int = 10,
        social_check_enabled: Bool = True,
        social_check_window_minutes: Int = 10,

        # Honeypot Detection
        honeypot_check: Bool = True
    ):
        # LP Burn Requirements
        self.min_lp_burn_rate = min_lp_burn_rate

        # Authority Requirements
        self.revoke_authority_required = revoke_authority_required

        # Custom TP/SL for Sniper Trades
        self.tp_threshold = tp_threshold
        self.sl_threshold = sl_threshold

        # Holder Distribution
        self.max_top_holders_share = max_top_holders_share

        # Volume Requirements
        self.min_active_volume = min_active_volume

        # Social Mentions Check
        self.min_social_mentions = min_social_mentions
        self.social_check_enabled = social_check_enabled
        self.social_check_window_minutes = social_check_window_minutes

        # Honeypot Detection
        self.honeypot_check = honeypot_check

# =============================================================================
# Risk Thresholds Configuration
# =============================================================================

@value
struct RiskThresholdsConfig:
    """
    Configuration for risk management thresholds and scoring
    """
    # RSI-based risk thresholds
    var rsi_extreme_overbought: Float
    var rsi_very_overbought: Float
    var rsi_extreme_oversold: Float
    var rsi_very_oversold: Float
    var risk_score_extreme_overbought: Float
    var risk_score_very_overbought: Float
    var risk_score_extreme_oversold: Float
    var risk_score_very_oversold: Float

    # Volume and liquidity risk
    var risk_score_low_volume: Float
    var risk_score_low_liquidity: Float
    var liquidity_risk_low_volume: Float
    var liquidity_risk_low_liquidity: Float

    # Price movement risk
    var price_movement_extreme: Float
    var price_movement_high: Float
    var risk_score_extreme_movement: Float
    var risk_score_high_movement: Float
    var volatility_extreme_movement: Float
    var volatility_high_movement: Float

    # Confidence and wash trading
    var confidence_threshold: Float
    var risk_score_low_confidence: Float
    var wash_trading_volume_threshold: Float
    var wash_trading_liquidity_threshold: Float
    var risk_score_wash_trading: Float
    var wash_trading_score: Float

    # Risk level thresholds
    var risk_level_critical: Float
    var risk_level_high: Float
    var risk_level_medium: Float

    # Position sizing multipliers
    var position_size_high_risk_multiplier: Float
    var position_size_medium_risk_multiplier: Float
    var liquidity_risk_multiplier: Float
    var volatility_risk_multiplier: Float
    var volatility_threshold: Float
    var liquidity_risk_threshold: Float

    # Liquidity checks
    var min_liquidity_check: Float
    var volume_to_liquidity_suspicious: Float

    # Portfolio risk
    var correlation_risk_divisor: Float
    var concentration_risk_threshold: Float
    var liquidity_risk_portfolio_multiplier: Float
    var total_risk_critical: Float
    var total_risk_high: Float
    var total_risk_medium: Float
    var daily_trades_warning_percentage: Float

    fn __init__(
        # RSI-based risk thresholds
        rsi_extreme_overbought: Float = 90.0,
        rsi_very_overbought: Float = 80.0,
        rsi_extreme_oversold: Float = 10.0,
        rsi_very_oversold: Float = 20.0,
        risk_score_extreme_overbought: Float = 0.3,
        risk_score_very_overbought: Float = 0.2,
        risk_score_extreme_oversold: Float = 0.2,
        risk_score_very_oversold: Float = 0.1,

        # Volume and liquidity risk
        risk_score_low_volume: Float = 0.3,
        risk_score_low_liquidity: Float = 0.4,
        liquidity_risk_low_volume: Float = 0.2,
        liquidity_risk_low_liquidity: Float = 0.3,

        # Price movement risk
        price_movement_extreme: Float = 0.2,
        price_movement_high: Float = 0.1,
        risk_score_extreme_movement: Float = 0.3,
        risk_score_high_movement: Float = 0.2,
        volatility_extreme_movement: Float = 0.3,
        volatility_high_movement: Float = 0.2,

        # Confidence and wash trading
        confidence_threshold: Float = 0.6,
        risk_score_low_confidence: Float = 0.2,
        wash_trading_volume_threshold: Float = 1000000.0,
        wash_trading_liquidity_threshold: Float = 10000.0,
        risk_score_wash_trading: Float = 0.4,
        wash_trading_score: Float = 0.8,

        # Risk level thresholds
        risk_level_critical: Float = 0.7,
        risk_level_high: Float = 0.5,
        risk_level_medium: Float = 0.3,

        # Position sizing multipliers
        position_size_high_risk_multiplier: Float = 0.5,
        position_size_medium_risk_multiplier: Float = 0.75,
        liquidity_risk_multiplier: Float = 0.7,
        volatility_risk_multiplier: Float = 0.8,
        volatility_threshold: Float = 0.3,
        liquidity_risk_threshold: Float = 0.5,

        # Liquidity checks
        min_liquidity_check: Float = 5000.0,
        volume_to_liquidity_suspicious: Float = 20.0,

        # Portfolio risk
        correlation_risk_divisor: Float = 10.0,
        concentration_risk_threshold: Float = 0.3,
        liquidity_risk_portfolio_multiplier: Float = 0.1,
        total_risk_critical: Float = 0.7,
        total_risk_high: Float = 0.5,
        total_risk_medium: Float = 0.3,
        daily_trades_warning_percentage: Float = 0.8
    ):
        # RSI-based risk thresholds
        self.rsi_extreme_overbought = rsi_extreme_overbought
        self.rsi_very_overbought = rsi_very_overbought
        self.rsi_extreme_oversold = rsi_extreme_oversold
        self.rsi_very_oversold = rsi_very_oversold
        self.risk_score_extreme_overbought = risk_score_extreme_overbought
        self.risk_score_very_overbought = risk_score_very_overbought
        self.risk_score_extreme_oversold = risk_score_extreme_oversold
        self.risk_score_very_oversold = risk_score_very_oversold

        # Volume and liquidity risk
        self.risk_score_low_volume = risk_score_low_volume
        self.risk_score_low_liquidity = risk_score_low_liquidity
        self.liquidity_risk_low_volume = liquidity_risk_low_volume
        self.liquidity_risk_low_liquidity = liquidity_risk_low_liquidity

        # Price movement risk
        self.price_movement_extreme = price_movement_extreme
        self.price_movement_high = price_movement_high
        self.risk_score_extreme_movement = risk_score_extreme_movement
        self.risk_score_high_movement = risk_score_high_movement
        self.volatility_extreme_movement = volatility_extreme_movement
        self.volatility_high_movement = volatility_high_movement

        # Confidence and wash trading
        self.confidence_threshold = confidence_threshold
        self.risk_score_low_confidence = risk_score_low_confidence
        self.wash_trading_volume_threshold = wash_trading_volume_threshold
        self.wash_trading_liquidity_threshold = wash_trading_liquidity_threshold
        self.risk_score_wash_trading = risk_score_wash_trading
        self.wash_trading_score = wash_trading_score

        # Risk level thresholds
        self.risk_level_critical = risk_level_critical
        self.risk_level_high = risk_level_high
        self.risk_level_medium = risk_level_medium

        # Position sizing multipliers
        self.position_size_high_risk_multiplier = position_size_high_risk_multiplier
        self.position_size_medium_risk_multiplier = position_size_medium_risk_multiplier
        self.liquidity_risk_multiplier = liquidity_risk_multiplier
        self.volatility_risk_multiplier = volatility_risk_multiplier
        self.volatility_threshold = volatility_threshold
        self.liquidity_risk_threshold = liquidity_risk_threshold

        # Liquidity checks
        self.min_liquidity_check = min_liquidity_check
        self.volume_to_liquidity_suspicious = volume_to_liquidity_suspicious

        # Portfolio risk
        self.correlation_risk_divisor = correlation_risk_divisor
        self.concentration_risk_threshold = concentration_risk_threshold
        self.liquidity_risk_portfolio_multiplier = liquidity_risk_portfolio_multiplier
        self.total_risk_critical = total_risk_critical
        self.total_risk_high = total_risk_high
        self.total_risk_medium = total_risk_medium
        self.daily_trades_warning_percentage = daily_trades_warning_percentage

# =============================================================================
# Strategy Thresholds Configuration
# =============================================================================

@value
struct StrategyThresholdsConfig:
    """
    Configuration for strategy thresholds and multipliers
    """
    # Stop loss multipliers
    var stop_loss_below_support: Float
    var stop_loss_above_resistance: Float
    var stop_loss_momentum_buy: Float
    var stop_loss_momentum_sell: Float

    # Price targets
    var price_target_momentum_buy: Float
    var price_target_momentum_sell: Float

    # Mean reversion
    var mean_reversion_upper_band: Float
    var mean_reversion_lower_band: Float
    var mean_reversion_buy_threshold: Float
    var mean_reversion_sell_threshold: Float
    var mean_reversion_stop_loss_buy: Float
    var mean_reversion_stop_loss_sell: Float
    var mean_reversion_confidence: Float

    # Momentum
    var momentum_threshold: Float
    var momentum_confidence_multiplier: Float
    var momentum_max_confidence: Float

    # Confidence calculation
    var base_confidence: Float
    var confluence_boost_multiplier: Float
    var rsi_boost_multiplier: Float
    var distance_boost_max: Float
    var distance_boost_divisor: Float

    # Signal scoring
    var volume_bonus_divisor: Float
    var volume_bonus_max: Float
    var liquidity_bonus_divisor: Float
    var liquidity_bonus_max: Float
    var risk_reward_bonus_max: Float
    var risk_reward_bonus_divisor: Float

    # Exit conditions
    var position_age_exit_hours: Float
    var exit_urgency_stop_loss: Float
    var exit_urgency_take_profit: Float
    var exit_urgency_time_based: Float
    var exit_confidence_stop_loss: Float
    var exit_confidence_take_profit: Float
    var exit_confidence_time_based: Float

    # Sentiment adjustments
    var sentiment_positive_threshold: Float
    var sentiment_negative_threshold: Float
    var sentiment_very_negative: Float
    var sentiment_confidence_boost: Float
    var sentiment_confidence_penalty: Float

    fn __init__(
        # Stop loss multipliers
        stop_loss_below_support: Float = 0.95,
        stop_loss_above_resistance: Float = 1.05,
        stop_loss_momentum_buy: Float = 0.93,
        stop_loss_momentum_sell: Float = 1.07,

        # Price targets
        price_target_momentum_buy: Float = 1.1,
        price_target_momentum_sell: Float = 0.9,

        # Mean reversion
        mean_reversion_upper_band: Float = 1.1,
        mean_reversion_lower_band: Float = 0.9,
        mean_reversion_buy_threshold: Float = 1.02,
        mean_reversion_sell_threshold: Float = 0.98,
        mean_reversion_stop_loss_buy: Float = 0.95,
        mean_reversion_stop_loss_sell: Float = 1.05,
        mean_reversion_confidence: Float = 0.7,

        # Momentum
        momentum_threshold: Float = 0.02,
        momentum_confidence_multiplier: Float = 10.0,
        momentum_max_confidence: Float = 0.8,

        # Confidence calculation
        base_confidence: Float = 0.5,
        confluence_boost_multiplier: Float = 0.3,
        rsi_boost_multiplier: Float = 0.2,
        distance_boost_max: Float = 0.1,
        distance_boost_divisor: Float = 0.1,

        # Signal scoring
        volume_bonus_divisor: Float = 100000.0,
        volume_bonus_max: Float = 0.1,
        liquidity_bonus_divisor: Float = 50000.0,
        liquidity_bonus_max: Float = 0.1,
        risk_reward_bonus_max: Float = 0.2,
        risk_reward_bonus_divisor: Float = 10.0,

        # Exit conditions
        position_age_exit_hours: Float = 4.0,
        exit_urgency_stop_loss: Float = 1.0,
        exit_urgency_take_profit: Float = 0.8,
        exit_urgency_time_based: Float = 0.6,
        exit_confidence_stop_loss: Float = 1.0,
        exit_confidence_take_profit: Float = 0.9,
        exit_confidence_time_based: Float = 0.7,

        # Sentiment adjustments
        sentiment_positive_threshold: Float = 0.3,
        sentiment_negative_threshold: Float = -0.3,
        sentiment_very_negative: Float = -0.5,
        sentiment_confidence_boost: Float = 0.1,
        sentiment_confidence_penalty: Float = 0.2
    ):
        # Stop loss multipliers
        self.stop_loss_below_support = stop_loss_below_support
        self.stop_loss_above_resistance = stop_loss_above_resistance
        self.stop_loss_momentum_buy = stop_loss_momentum_buy
        self.stop_loss_momentum_sell = stop_loss_momentum_sell

        # Price targets
        self.price_target_momentum_buy = price_target_momentum_buy
        self.price_target_momentum_sell = price_target_momentum_sell

        # Mean reversion
        self.mean_reversion_upper_band = mean_reversion_upper_band
        self.mean_reversion_lower_band = mean_reversion_lower_band
        self.mean_reversion_buy_threshold = mean_reversion_buy_threshold
        self.mean_reversion_sell_threshold = mean_reversion_sell_threshold
        self.mean_reversion_stop_loss_buy = mean_reversion_stop_loss_buy
        self.mean_reversion_stop_loss_sell = mean_reversion_stop_loss_sell
        self.mean_reversion_confidence = mean_reversion_confidence

        # Momentum
        self.momentum_threshold = momentum_threshold
        self.momentum_confidence_multiplier = momentum_confidence_multiplier
        self.momentum_max_confidence = momentum_max_confidence

        # Confidence calculation
        self.base_confidence = base_confidence
        self.confluence_boost_multiplier = confluence_boost_multiplier
        self.rsi_boost_multiplier = rsi_boost_multiplier
        self.distance_boost_max = distance_boost_max
        self.distance_boost_divisor = distance_boost_divisor

        # Signal scoring
        self.volume_bonus_divisor = volume_bonus_divisor
        self.volume_bonus_max = volume_bonus_max
        self.liquidity_bonus_divisor = liquidity_bonus_divisor
        self.liquidity_bonus_max = liquidity_bonus_max
        self.risk_reward_bonus_max = risk_reward_bonus_max
        self.risk_reward_bonus_divisor = risk_reward_bonus_divisor

        # Exit conditions
        self.position_age_exit_hours = position_age_exit_hours
        self.exit_urgency_stop_loss = exit_urgency_stop_loss
        self.exit_urgency_take_profit = exit_urgency_take_profit
        self.exit_urgency_time_based = exit_urgency_time_based
        self.exit_confidence_stop_loss = exit_confidence_stop_loss
        self.exit_confidence_take_profit = exit_confidence_take_profit
        self.exit_confidence_time_based = exit_confidence_time_based

        # Sentiment adjustments
        self.sentiment_positive_threshold = sentiment_positive_threshold
        self.sentiment_negative_threshold = sentiment_negative_threshold
        self.sentiment_very_negative = sentiment_very_negative
        self.sentiment_confidence_boost = sentiment_confidence_boost
        self.sentiment_confidence_penalty = sentiment_confidence_penalty

# =============================================================================
# Volume Configuration
# =============================================================================

@value
struct VolumeConfig:
    """
    Configuration for volume analysis
    """
    var trend_threshold: Float
    var hours_per_day: Float
    var volatility_tx_threshold: Float
    var volatility_price_threshold: Float
    var momentum_volume_multiplier: Float
    var momentum_price_threshold: Float
    var spike_multiplier: Float
    var significance_divisor: Float
    var high_tx_threshold: Int
    var normal_tx_multiplier: Float
    var tx_spike_significance: Float
    var market_cap_percentage: Float
    var liquidity_reference: Float
    var max_liquidity_multiplier: Float
    var holder_reference: Float
    var max_holder_multiplier: Float

    fn __init__(
        trend_threshold: Float = 0.02,
        hours_per_day: Float = 24.0,
        volatility_tx_threshold: Float = 50.0,
        volatility_price_threshold: Float = 0.1,
        momentum_volume_multiplier: Float = 10.0,
        momentum_price_threshold: Float = 0.1,
        spike_multiplier: Float = 2.0,
        significance_divisor: Float = 10.0,
        high_tx_threshold: Int = 100,
        normal_tx_multiplier: Float = 3.0,
        tx_spike_significance: Float = 0.7,
        market_cap_percentage: Float = 0.05,
        liquidity_reference: Float = 50000.0,
        max_liquidity_multiplier: Float = 2.0,
        holder_reference: Float = 100.0,
        max_holder_multiplier: Float = 2.0
    ):
        self.trend_threshold = trend_threshold
        self.hours_per_day = hours_per_day
        self.volatility_tx_threshold = volatility_tx_threshold
        self.volatility_price_threshold = volatility_price_threshold
        self.momentum_volume_multiplier = momentum_volume_multiplier
        self.momentum_price_threshold = momentum_price_threshold
        self.spike_multiplier = spike_multiplier
        self.significance_divisor = significance_divisor
        self.high_tx_threshold = high_tx_threshold
        self.normal_tx_multiplier = normal_tx_multiplier
        self.tx_spike_significance = tx_spike_significance
        self.market_cap_percentage = market_cap_percentage
        self.liquidity_reference = liquidity_reference
        self.max_liquidity_multiplier = max_liquidity_multiplier
        self.holder_reference = holder_reference
        self.max_holder_multiplier = max_holder_multiplier

# =============================================================================
# Whale Configuration
# =============================================================================

@value
struct WhaleConfig:
    """
    Configuration for whale tracking
    """
    var max_holder_reference: Float

    fn __init__(
        max_holder_reference: Float = 100.0
    ):
        self.max_holder_reference = max_holder_reference

# =============================================================================
# Feature Flags Configuration
# =============================================================================

@value
struct FeaturesConfig:
    """
    Configuration for feature flags to enable/disable components
    """
    var enable_social_analysis: Bool
    var enable_honeypot_analysis: Bool
    var enable_rpc_router: Bool
    var enable_rust_data_consumer: Bool
    var enable_connection_pool_monitoring: Bool
    var enable_operational_reliability_monitor: Bool

    fn __init__(
        enable_social_analysis: Bool = True,
        enable_honeypot_analysis: Bool = True,
        enable_rpc_router: Bool = True,
        enable_rust_data_consumer: Bool = False,
        enable_connection_pool_monitoring: Bool = True,
        enable_operational_reliability_monitor: Bool = True
    ):
        self.enable_social_analysis = enable_social_analysis
        self.enable_honeypot_analysis = enable_honeypot_analysis
        self.enable_rpc_router = enable_rpc_router
        self.enable_rust_data_consumer = enable_rust_data_consumer
        self.enable_connection_pool_monitoring = enable_connection_pool_monitoring
        self.enable_operational_reliability_monitor = enable_operational_reliability_monitor

# =============================================================================
# Strategy Adaptation Configuration
# =============================================================================

@value
struct StrategyAdaptationConfig:
    """
    Strategy adaptation parameters
    """
    var enabled: Bool
    var adaptation_interval_hours: Int
    var performance_window_hours: Int
    var min_trades_for_adaptation: Int
    var baseline_confidence_threshold: Float
    var baseline_position_size: Float
    var baseline_stop_loss_percentage: Float
    var baseline_take_profit_percentage: Float
    var baseline_max_positions: Int
    var max_confidence_threshold: Float
    var min_confidence_threshold: Float
    var max_position_size_multiplier: Float
    var min_position_size_multiplier: Float

    fn __init__(
        enabled: Bool = True,
        adaptation_interval_hours: Int = 24,
        performance_window_hours: Int = 48,
        min_trades_for_adaptation: Int = 20,
        baseline_confidence_threshold: Float = 0.70,
        baseline_position_size: Float = 0.05,
        baseline_stop_loss_percentage: Float = 0.10,
        baseline_take_profit_percentage: Float = 0.20,
        baseline_max_positions: Int = 5,
        max_confidence_threshold: Float = 0.90,
        min_confidence_threshold: Float = 0.50,
        max_position_size_multiplier: Float = 1.5,
        min_position_size_multiplier: Float = 0.5
    ):
        self.enabled = enabled
        self.adaptation_interval_hours = adaptation_interval_hours
        self.performance_window_hours = performance_window_hours
        self.min_trades_for_adaptation = min_trades_for_adaptation
        self.baseline_confidence_threshold = baseline_confidence_threshold
        self.baseline_position_size = baseline_position_size
        self.baseline_stop_loss_percentage = baseline_stop_loss_percentage
        self.baseline_take_profit_percentage = baseline_take_profit_percentage
        self.baseline_max_positions = baseline_max_positions
        self.max_confidence_threshold = max_confidence_threshold
        self.min_confidence_threshold = min_confidence_threshold
        self.max_position_size_multiplier = max_position_size_multiplier
        self.min_position_size_multiplier = min_position_size_multiplier

# =============================================================================
# RPC Providers Configuration (2025 Features)
# =============================================================================

@value
struct RPCProvidersConfig:
    """
    Configuration for RPC provider features and routing
    """
    # Helius configuration
    var helius_enable_shredstream: Bool
    var helius_shredstream_endpoint: String
    var helius_enable_priority_fee_api: Bool
    var helius_enable_webhooks: Bool
    var helius_webhook_types: List[String]
    var helius_organic_score_enabled: Bool
    var helius_tier: String

    # QuickNode configuration
    var quicknode_enable_lil_jit: Bool
    var quicknode_lil_jit_endpoint: String
    var quicknode_enable_priority_fee_api: Bool

    # Routing configuration
    var routing_policy: String
    var routing_latency_threshold_ms: Int
    var routing_bundle_success_rate_threshold: Float
    var routing_track_bundle_metrics: Bool
    var routing_prefer_shredstream_for_mev: Bool

    fn __init__(
        # Helius defaults
        helius_enable_shredstream: Bool = True,
        helius_shredstream_endpoint: String = "",
        helius_enable_priority_fee_api: Bool = True,
        helius_enable_webhooks: Bool = True,
        helius_webhook_types: List[String] = ["token_transfers", "new_mints", "large_transactions"],
        helius_organic_score_enabled: Bool = True,
        helius_tier: String = "developer",

        # QuickNode defaults
        quicknode_enable_lil_jit: Bool = True,
        quicknode_lil_jit_endpoint: String = "",
        quicknode_enable_priority_fee_api: Bool = True,

        # Routing defaults
        routing_policy: String = "health_first",
        routing_latency_threshold_ms: Int = 100,
        routing_bundle_success_rate_threshold: Float = 0.90,
        routing_track_bundle_metrics: Bool = True,
        routing_prefer_shredstream_for_mev: Bool = True
    ):
        self.helius_enable_shredstream = helius_enable_shredstream
        self.helius_shredstream_endpoint = helius_shredstream_endpoint
        self.helius_enable_priority_fee_api = helius_enable_priority_fee_api
        self.helius_enable_webhooks = helius_enable_webhooks
        self.helius_webhook_types = helius_webhook_types
        self.helius_organic_score_enabled = helius_organic_score_enabled
        self.helius_tier = helius_tier

        self.quicknode_enable_lil_jit = quicknode_enable_lil_jit
        self.quicknode_lil_jit_endpoint = quicknode_lil_jit_endpoint
        self.quicknode_enable_priority_fee_api = quicknode_enable_priority_fee_api

        self.routing_policy = routing_policy
        self.routing_latency_threshold_ms = routing_latency_threshold_ms
        self.routing_bundle_success_rate_threshold = routing_bundle_success_rate_threshold
        self.routing_track_bundle_metrics = routing_track_bundle_metrics
        self.routing_prefer_shredstream_for_mev = routing_prefer_shredstream_for_mev

# =============================================================================
# MEV Configuration (2025 Features)
# =============================================================================

@value
struct MEVConfig:
    """
    Configuration for Maximal Extractable Value features
    """
    var prefer_helius_shredstream: Bool
    var bundle_submission_provider: String
    var track_bundle_success_by_provider: Bool

    # Jito configuration
    var jito_enabled: Bool
    var jito_endpoint: String
    var jito_tip_lamports: Int
    var jito_max_tip_lamports: Int
    var min_profit_threshold_sol: Float

    fn __init__(
        prefer_helius_shredstream: Bool = True,
        bundle_submission_provider: String = "auto",
        track_bundle_success_by_provider: Bool = True,

        # Jito defaults
        jito_enabled: Bool = True,
        jito_endpoint: String = "",
        jito_tip_lamports: Int = 1000000,     # 0.001 SOL
        jito_max_tip_lamports: Int = 10000000, # 0.01 SOL
        min_profit_threshold_sol: Float = 0.01
    ):
        self.prefer_helius_shredstream = prefer_helius_shredstream
        self.bundle_submission_provider = bundle_submission_provider
        self.track_bundle_success_by_provider = track_bundle_success_by_provider

        self.jito_enabled = jito_enabled
        self.jito_endpoint = jito_endpoint
        self.jito_tip_lamports = jito_tip_lamports
        self.jito_max_tip_lamports = jito_max_tip_lamports
        self.min_profit_threshold_sol = min_profit_threshold_sol

# =============================================================================
# Legacy Monitoring Configuration (for compatibility)
# =============================================================================

@value
struct MonitoringConfig:
    """
    Legacy monitoring parameters (kept for compatibility)
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
    var circuit_breakers: CircuitBreakersConfig
    var alerts: AlertsConfig
    var strategy_adaptation: StrategyAdaptationConfig
    var filters: FilterConfig
    var risk_thresholds: RiskThresholdsConfig
    var strategy_thresholds: StrategyThresholdsConfig
    var volume: VolumeConfig
    var whale: WhaleConfig
    var sniper_filters: SniperFilterConfig
    var features: FeaturesConfig
    var rpc_providers: RPCProvidersConfig  # 2025 RPC features
    var mev: MEVConfig                      # 2025 MEV features
    var backtest: BacktestConfig           # PumpFun backtesting features

    # Environment-specific
    var trading_env: String
    var wallet_address: String
    var wallet_private_key_path: String

    @staticmethod
    fn load_from_env() -> Config:
        """
        Load configuration from Infisical secrets or environment variables
        """
        # Initialize Infisical client
        infisical = get_infisical_client()

        # Environment
        trading_env = getenv("TRADING_ENV", "development")

        # API Configuration (try Infisical first, fallback to env)
        try:
            api_config = infisical.get_api_config()
        except e:
            print(f"⚠️  Failed to load API config from Infisical: {e}")
            # Fallback to environment variables
            api_config = APIConfig(
                helius_api_key=getenv("HELIUS_API_KEY", ""),
                helius_base_url=getenv("HELIUS_BASE_URL", "https://api.helius.xyz/v0"),
                helius_rpc_url=getenv("HELIUS_RPC_URL", ""),
                quicknode_rpcs=QuickNodeRPCs(
                    primary=getenv("QUICKNODE_PRIMARY_RPC", ""),
                    secondary=getenv("QUICKNODE_SECONDARY_RPC", ""),
                    archive=getenv("QUICKNODE_ARCHIVE_RPC", "")
                ),
                dexscreener_base_url=getenv("DEXSCREENER_BASE_URL", "https://api.dexscreener.com/latest/dex"),
                jupiter_base_url=getenv("JUPITER_BASE_URL", "https://quote-api.jup.ag/v6"),
                jupiter_quote_api=getenv("JUPITER_QUOTE_API", "https://quote-api.jup.ag/v6/quote"),
                timeout_seconds=float(getenv("API_TIMEOUT_SECONDS", "10.0"))
            )

        # Trading Configuration (try Infisical first, fallback to env)
        try:
            trading_config = infisical.get_trading_config()
        except e:
            print(f"⚠️  Failed to load trading config from Infisical: {e}")
            # Fallback to environment variables
            trading_config = TradingConfig(
                initial_capital=float(getenv("INITIAL_CAPITAL", "1.0")),
                max_position_size=float(getenv("MAX_POSITION_SIZE", "0.1")),
                max_drawdown=float(getenv("MAX_DRAWDOWN", "0.15")),
                cycle_interval=float(getenv("CYCLE_INTERVAL", "1.0")),
                kelly_fraction=float(getenv("KELLY_FRACTION", "0.5")),
                max_correlation=float(getenv("MAX_CORRELATION", "0.7")),
                diversification_target=int(getenv("DIVERSIFICATION_TARGET", "10")),
                max_daily_trades=int(getenv("MAX_DAILY_TRADES", "50"))
            )

        # Wallet Configuration (try Infisical first, fallback to env)
        wallet_address = getenv("WALLET_ADDRESS", "")
        wallet_private_key_path = getenv("WALLET_PRIVATE_KEY_PATH", "~/.config/solana/id.json")

        try:
            wallet_config = infisical.get_wallet_config()
        except e:
            print(f"⚠️  Failed to load wallet config from Infisical: {e}")
            # Fallback to environment variables
            wallet_config = WalletConfig(
                address=wallet_address,
                private_key_path=wallet_private_key_path
            )

        # API config already loaded from Infisical above

        # Trading Configuration parameters
        initial_capital = float(getenv("INITIAL_CAPITAL", "1.0"))
        max_position_size = float(getenv("MAX_POSITION_SIZE", "0.1"))
        min_position_size = float(getenv("MIN_POSITION_SIZE", "0.01"))
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
        database_enabled = getenv("DATABASE_ENABLED", "false").lower() == "true"
        database_host = getenv("DATABASE_HOST", "localhost")
        database_port = int(getenv("DATABASE_PORT", "5432"))
        database_name = getenv("DATABASE_NAME", "trading_bot")
        database_user = getenv("DATABASE_USER", "trader")
        database_password_env = getenv("DATABASE_PASSWORD_ENV", "DB_PASSWORD")
        database_max_connections = int(getenv("DATABASE_MAX_CONNECTIONS", "10"))
        database_batch_size = int(getenv("DATABASE_BATCH_SIZE", "100"))
        database_auto_flush_interval = int(getenv("DATABASE_AUTO_FLUSH_INTERVAL", "60"))

        database_config = DatabaseConfig(
            enabled=database_enabled,
            host=database_host,
            port=database_port,
            database=database_name,
            user=database_user,
            password_env=database_password_env,
            max_connections=database_max_connections,
            batch_size=database_batch_size,
            auto_flush_interval_seconds=database_auto_flush_interval
        )

        # Circuit Breakers Configuration
        circuit_breakers_max_drawdown = float(getenv("CIRCUIT_BREAKERS_MAX_DRAWDOWN", "0.15"))
        circuit_breakers_max_consecutive_losses = int(getenv("CIRCUIT_BREAKERS_MAX_CONSECUTIVE_LOSSES", "5"))
        circuit_breakers_max_daily_loss_percentage = float(getenv("CIRCUIT_BREAKERS_MAX_DAILY_LOSS_PERCENTAGE", "0.10"))
        circuit_breakers_max_position_concentration = float(getenv("CIRCUIT_BREAKERS_MAX_POSITION_CONCENTRATION", "0.30"))
        circuit_breakers_min_trade_interval_seconds = int(getenv("CIRCUIT_BREAKERS_MIN_TRADE_INTERVAL_SECONDS", "60"))
        circuit_breakers_rapid_drawdown_threshold = float(getenv("CIRCUIT_BREAKERS_RAPID_DRAWDOWN_THRESHOLD", "0.05"))

        circuit_breakers_config = CircuitBreakersConfig(
            max_drawdown=circuit_breakers_max_drawdown,
            max_consecutive_losses=circuit_breakers_max_consecutive_losses,
            max_daily_loss_percentage=circuit_breakers_max_daily_loss_percentage,
            max_position_concentration=circuit_breakers_max_position_concentration,
            min_trade_interval_seconds=circuit_breakers_min_trade_interval_seconds,
            rapid_drawdown_threshold=circuit_breakers_rapid_drawdown_threshold
        )

        # Alerts Configuration
        alerts_enabled = getenv("ALERTS_ENABLED", "true").lower() == "true"
        alerts_channels = getenv("ALERTS_CHANNELS", "console").split(",")
        alerts_webhook_url_env = getenv("ALERTS_WEBHOOK_URL_ENV", "DISCORD_WEBHOOK_URL")
        alerts_telegram_bot_token_env = getenv("ALERTS_TELEGRAM_BOT_TOKEN_ENV", "TELEGRAM_BOT_TOKEN")
        alerts_telegram_chat_id_env = getenv("ALERTS_TELEGRAM_CHAT_ID_ENV", "TELEGRAM_CHAT_ID")
        alerts_error_cooldown = int(getenv("ALERTS_ERROR_COOLDOWN", "60"))
        alerts_performance_cooldown = int(getenv("ALERTS_PERFORMANCE_COOLDOWN", "300"))
        alerts_trade_cooldown = int(getenv("ALERTS_TRADE_COOLDOWN", "0"))
        alerts_performance_threshold = float(getenv("ALERTS_PERFORMANCE_THRESHOLD", "0.05"))

        alerts_config = AlertsConfig(
            enabled=alerts_enabled,
            channels=alerts_channels,
            webhook_url_env=alerts_webhook_url_env,
            telegram_bot_token_env=alerts_telegram_bot_token_env,
            telegram_chat_id_env=alerts_telegram_chat_id_env,
            error_alert_cooldown=alerts_error_cooldown,
            performance_alert_cooldown=alerts_performance_cooldown,
            trade_alert_cooldown=alerts_trade_cooldown,
            performance_alert_threshold=alerts_performance_threshold
        )

        # Strategy Adaptation Configuration
        strategy_adaptation_enabled = getenv("STRATEGY_ADAPTATION_ENABLED", "true").lower() == "true"
        strategy_adaptation_interval_hours = int(getenv("STRATEGY_ADAPTATION_INTERVAL_HOURS", "24"))
        strategy_adaptation_performance_window_hours = int(getenv("STRATEGY_ADAPTATION_PERFORMANCE_WINDOW_HOURS", "48"))
        strategy_adaptation_min_trades_for_adaptation = int(getenv("STRATEGY_ADAPTATION_MIN_TRADES_FOR_ADAPTATION", "20"))
        strategy_adaptation_baseline_confidence_threshold = float(getenv("STRATEGY_ADAPTATION_BASELINE_CONFIDENCE_THRESHOLD", "0.70"))
        strategy_adaptation_baseline_position_size = float(getenv("STRATEGY_ADAPTATION_BASELINE_POSITION_SIZE", "0.05"))
        strategy_adaptation_baseline_stop_loss_percentage = float(getenv("STRATEGY_ADAPTATION_BASELINE_STOP_LOSS_PERCENTAGE", "0.10"))
        strategy_adaptation_baseline_take_profit_percentage = float(getenv("STRATEGY_ADAPTATION_BASELINE_TAKE_PROFIT_PERCENTAGE", "0.20"))
        strategy_adaptation_baseline_max_positions = int(getenv("STRATEGY_ADAPTATION_BASELINE_MAX_POSITIONS", "5"))
        strategy_adaptation_max_confidence_threshold = float(getenv("STRATEGY_ADAPTATION_MAX_CONFIDENCE_THRESHOLD", "0.90"))
        strategy_adaptation_min_confidence_threshold = float(getenv("STRATEGY_ADAPTATION_MIN_CONFIDENCE_THRESHOLD", "0.50"))
        strategy_adaptation_max_position_size_multiplier = float(getenv("STRATEGY_ADAPTATION_MAX_POSITION_SIZE_MULTIPLIER", "1.5"))
        strategy_adaptation_min_position_size_multiplier = float(getenv("STRATEGY_ADAPTATION_MIN_POSITION_SIZE_MULTIPLIER", "0.5"))

        strategy_adaptation_config = StrategyAdaptationConfig(
            enabled=strategy_adaptation_enabled,
            adaptation_interval_hours=strategy_adaptation_interval_hours,
            performance_window_hours=strategy_adaptation_performance_window_hours,
            min_trades_for_adaptation=strategy_adaptation_min_trades_for_adaptation,
            baseline_confidence_threshold=strategy_adaptation_baseline_confidence_threshold,
            baseline_position_size=strategy_adaptation_baseline_position_size,
            baseline_stop_loss_percentage=strategy_adaptation_baseline_stop_loss_percentage,
            baseline_take_profit_percentage=strategy_adaptation_baseline_take_profit_percentage,
            baseline_max_positions=strategy_adaptation_baseline_max_positions,
            max_confidence_threshold=strategy_adaptation_max_confidence_threshold,
            min_confidence_threshold=strategy_adaptation_min_confidence_threshold,
            max_position_size_multiplier=strategy_adaptation_max_position_size_multiplier,
            min_position_size_multiplier=strategy_adaptation_min_position_size_multiplier
        )

        # Legacy Monitoring Configuration (for compatibility)
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

        # New Configuration Sections

        # Filter Configuration
        filter_config = FilterConfig()

        # Risk Thresholds Configuration
        risk_thresholds_config = RiskThresholdsConfig()

        # Strategy Thresholds Configuration
        strategy_thresholds_config = StrategyThresholdsConfig()

        # Volume Configuration
        volume_config = VolumeConfig()

        # Whale Configuration
        whale_config = WhaleConfig()

        # Sniper Filter Configuration
        sniper_filter_config = SniperFilterConfig()

        # Feature Flags Configuration
        enable_social_analysis = getenv("ENABLE_SOCIAL_ANALYSIS", "true").lower() == "true"
        enable_honeypot_analysis = getenv("ENABLE_HONEYPOT_ANALYSIS", "true").lower() == "true"
        enable_rpc_router = getenv("ENABLE_RPC_ROUTER", "true").lower() == "true"
        enable_rust_data_consumer = getenv("ENABLE_RUST_DATA_CONSUMER", "false").lower() == "true"
        enable_connection_pool_monitoring = getenv("ENABLE_CONNECTION_POOL_MONITORING", "true").lower() == "true"
        enable_operational_reliability_monitor = getenv("ENABLE_OPERATIONAL_RELIABILITY_MONITOR", "true").lower() == "true"

        features_config = FeaturesConfig(
            enable_social_analysis=enable_social_analysis,
            enable_honeypot_analysis=enable_honeypot_analysis,
            enable_rpc_router=enable_rpc_router,
            enable_rust_data_consumer=enable_rust_data_consumer,
            enable_connection_pool_monitoring=enable_connection_pool_monitoring,
            enable_operational_reliability_monitor=enable_operational_reliability_monitor
        )

        # RPC Providers Configuration (2025 features)
        rpc_providers_config = RPCProvidersConfig(
            # Helius configuration
            helius_enable_shredstream=getenv("HELIUS_ENABLE_SHREDSTREAM", "true").lower() == "true",
            helius_shredstream_endpoint=getenv("HELIUS_SHREDSTREAM_ENDPOINT", ""),
            helius_enable_priority_fee_api=getenv("HELIUS_ENABLE_PRIORITY_FEE_API", "true").lower() == "true",
            helius_enable_webhooks=getenv("HELIUS_ENABLE_WEBHOOKS", "true").lower() == "true",
            helius_webhook_types=getenv("HELIUS_WEBHOOK_TYPES", "token_transfers,new_mints,large_transactions").split(","),
            helius_organic_score_enabled=getenv("HELIUS_ORGANIC_SCORE_ENABLED", "true").lower() == "true",
            helius_tier=getenv("HELIUS_TIER", "developer"),

            # QuickNode configuration
            quicknode_enable_lil_jit=getenv("QUICKNODE_ENABLE_LIL_JIT", "true").lower() == "true",
            quicknode_lil_jit_endpoint=getenv("QUICKNODE_LIL_JIT_ENDPOINT", ""),
            quicknode_enable_priority_fee_api=getenv("QUICKNODE_ENABLE_PRIORITY_FEE_API", "true").lower() == "true",

            # Routing configuration
            routing_policy=getenv("RPC_ROUTING_POLICY", "health_first"),
            routing_latency_threshold_ms=int(getenv("RPC_LATENCY_THRESHOLD_MS", "100")),
            routing_bundle_success_rate_threshold=float(getenv("RPC_BUNDLE_SUCCESS_RATE_THRESHOLD", "0.90")),
            routing_track_bundle_metrics=getenv("RPC_TRACK_BUNDLE_METRICS", "true").lower() == "true",
            routing_prefer_shredstream_for_mev=getenv("RPC_PREFER_SHREDSTREAM_FOR_MEV", "true").lower() == "true"
        )

        # MEV Configuration (2025 features)
        mev_config = MEVConfig(
            prefer_helius_shredstream=getenv("MEV_PREFER_HELIUS_SHREDSTREAM", "true").lower() == "true",
            bundle_submission_provider=getenv("MEV_BUNDLE_SUBMISSION_PROVIDER", "auto"),
            track_bundle_success_by_provider=getenv("MEV_TRACK_BUNDLE_SUCCESS_BY_PROVIDER", "true").lower() == "true",

            # Jito configuration
            jito_enabled=getenv("JITO_ENABLED", "true").lower() == "true",
            jito_endpoint=getenv("JITO_ENDPOINT", ""),
            jito_tip_lamports=int(getenv("JITO_TIP_LAMPORTS", "1000000")),
            jito_max_tip_lamports=int(getenv("JITO_MAX_TIP_LAMPORTS", "10000000")),
            min_profit_threshold_sol=float(getenv("MIN_PROFIT_THRESHOLD_SOL", "0.01"))
        )

        # Backtest Configuration (PumpFun Sniper)
        backtest_config = BacktestConfig(
            enabled=getenv("BACKTEST_ENABLED", "true").lower() == "true",
            data_retention_days=int(getenv("BACKTEST_DATA_RETENTION_DAYS", "30")),
            max_concurrent_backtests=int(getenv("BACKTEST_MAX_CONCURRENT_BACKTESTS", "10")),
            default_initial_investment=float(getenv("BACKTEST_DEFAULT_INITIAL_INVESTMENT", "1000.0")),
            default_simulation_hours=int(getenv("BACKTEST_DEFAULT_SIMULATION_HOURS", "24")),
            default_time_interval=getenv("BACKTEST_DEFAULT_TIME_INTERVAL", "5m"),
            enable_simd_vectorization=getenv("BACKTEST_ENABLE_SIMD_VECTORIZATION", "true").lower() == "true",
            chunk_size=int(getenv("BACKTEST_CHUNK_SIZE", "1024")),
            parallel_workers=int(getenv("BACKTEST_PARALLEL_WORKERS", "4")),
            cache_price_history=getenv("BACKTEST_CACHE_PRICE_HISTORY", "true").lower() == "true",
            cache_ttl_hours=int(getenv("BACKTEST_CACHE_TTL_HOURS", "1"))
        )

        return Config(
            api=api_config,
            trading=trading_config,
            strategy=strategy_config,
            risk=risk_config,
            execution=execution_config,
            database=database_config,
            monitoring=monitoring_config,
            circuit_breakers=circuit_breakers_config,
            alerts=alerts_config,
            strategy_adaptation=strategy_adaptation_config,
            filters=filter_config,
            risk_thresholds=risk_thresholds_config,
            strategy_thresholds=strategy_thresholds_config,
            volume=volume_config,
            whale=whale_config,
            sniper_filters=sniper_filter_config,
            features=features_config,
            rpc_providers=rpc_providers_config,
            mev=mev_config,
            backtest=backtest_config,
            trading_env=trading_env,
            wallet_address=wallet_address,
            wallet_private_key_path=wallet_private_key_path
        )

    @staticmethod
    fn load_from_file(file_path: String) -> Config:
        """
        Load configuration from TOML file with environment fallbacks
        """
        try:
            with open(file_path, 'r') as f:
                if file_path.endswith('.json'):
                    config_data = loads(f.read())
                else:
                    config_data = toml_loads(f.read())

            print(f"📄 Loading configuration from file: {file_path}")

            # Parse RPC providers configuration
            rpc_providers_config = RPCProvidersConfig()
            mev_config = MEVConfig()

            # Parse [rpc_providers] section
            if 'rpc_providers' in config_data:
                rpc_section = config_data['rpc_providers']

                # Parse [rpc_providers.helius]
                if 'helius' in rpc_section:
                    helius_config = rpc_section['helius']
                    rpc_providers_config.helius_enable_shredstream = helius_config.get('enable_shredstream', getenv("HELIUS_ENABLE_SHREDSTREAM", "false").lower() == "true")
                    rpc_providers_config.helius_shredstream_endpoint = helius_config.get('shredstream_endpoint', getenv("HELIUS_SHREDSTREAM_ENDPOINT", ""))
                    rpc_providers_config.helius_enable_priority_fee_api = helius_config.get('enable_priority_fee_api', getenv("HELIUS_ENABLE_PRIORITY_FEE_API", "true").lower() == "true")
                    rpc_providers_config.helius_enable_webhooks = helius_config.get('enable_webhooks', getenv("HELIUS_ENABLE_WEBHOOKS", "false").lower() == "true")
                    rpc_providers_config.helius_webhook_types = helius_config.get('webhook_types', getenv("HELIUS_WEBHOOK_TYPES", "token_transfers,new_mints,large_transactions").split(","))
                    rpc_providers_config.helius_organic_score_enabled = helius_config.get('organic_score_enabled', getenv("HELIUS_ORGANIC_SCORE_ENABLED", "true").lower() == "true")
                    rpc_providers_config.helius_tier = helius_config.get('tier', getenv("HELIUS_TIER", "developer"))

                # Parse [rpc_providers.quicknode]
                if 'quicknode' in rpc_section:
                    quicknode_config = rpc_section['quicknode']
                    rpc_providers_config.quicknode_enable_lil_jit = quicknode_config.get('enable_lil_jit', getenv("QUICKNODE_ENABLE_LIL_JIT", "false").lower() == "true")
                    rpc_providers_config.quicknode_lil_jit_endpoint = quicknode_config.get('lil_jit_endpoint', getenv("QUICKNODE_LIL_JIT_ENDPOINT", ""))
                    rpc_providers_config.quicknode_enable_priority_fee_api = quicknode_config.get('enable_priority_fee_api', getenv("QUICKNODE_ENABLE_PRIORITY_FEE_API", "true").lower() == "true")

                # Parse [rpc_providers.routing]
                if 'routing' in rpc_section:
                    routing_config = rpc_section['routing']
                    rpc_providers_config.routing_policy = routing_config.get('policy', getenv("RPC_ROUTING_POLICY", "health_first"))
                    rpc_providers_config.routing_latency_threshold_ms = routing_config.get('latency_threshold_ms', int(getenv("RPC_LATENCY_THRESHOLD_MS", "100")))
                    rpc_providers_config.routing_bundle_success_rate_threshold = routing_config.get('bundle_success_rate_threshold', float(getenv("RPC_BUNDLE_SUCCESS_RATE_THRESHOLD", "0.90")))
                    rpc_providers_config.routing_track_bundle_metrics = routing_config.get('track_bundle_metrics', getenv("RPC_TRACK_BUNDLE_METRICS", "true").lower() == "true")
                    rpc_providers_config.routing_prefer_shredstream_for_mev = routing_config.get('prefer_shredstream_for_mev', getenv("RPC_PREFER_SHREDSTREAM_FOR_MEV", "true").lower() == "true")

            # Parse [mev] section
            if 'mev' in config_data:
                mev_section = config_data['mev']
                mev_config.prefer_helius_shredstream = mev_section.get('prefer_helius_shredstream', getenv("MEV_PREFER_HELIUS_SHREDSTREAM", "true").lower() == "true")
                mev_config.bundle_submission_provider = mev_section.get('bundle_submission_provider', getenv("MEV_BUNDLE_SUBMISSION_PROVIDER", "auto"))
                mev_config.track_bundle_success_by_provider = mev_section.get('track_bundle_success_by_provider', getenv("MEV_TRACK_BUNDLE_SUCCESS_BY_PROVIDER", "true").lower() == "true")

                # Parse Jito configuration within MEV
                if 'jito_enabled' in mev_section:
                    mev_config.jito_enabled = mev_section.get('jito_enabled', getenv("JITO_ENABLED", "true").lower() == "true")
                if 'jito_endpoint' in mev_section:
                    mev_config.jito_endpoint = mev_section.get('jito_endpoint', getenv("JITO_ENDPOINT", ""))
                if 'jito_tip_lamports' in mev_section:
                    mev_config.jito_tip_lamports = mev_section.get('jito_tip_lamports', int(getenv("JITO_TIP_LAMPORTS", "1000000")))
                if 'jito_max_tip_lamports' in mev_section:
                    mev_config.jito_max_tip_lamports = mev_section.get('jito_max_tip_lamports', int(getenv("JITO_MAX_TIP_LAMPORTS", "10000000")))
                if 'min_profit_threshold_sol' in mev_section:
                    mev_config.min_profit_threshold_sol = mev_section.get('min_profit_threshold_sol', float(getenv("MIN_PROFIT_THRESHOLD_SOL", "0.01")))

            print("✅ RPC/MEV configuration parsed from TOML")

            # Load remaining configuration from environment (as fallback)
            base_config = Config.load_from_env()

            # Update RPC and MEV configs with parsed values
            base_config.rpc_providers = rpc_providers_config
            base_config.mev = mev_config

            return base_config

        except FileNotFoundError:
            print(f"❌ Configuration file not found: {file_path}")
            print("🔄 Loading from environment variables...")
            return Config.load_from_env()
        except Exception as e:
            print(f"⚠️  Error parsing configuration file: {e}")
            print("🔄 Loading from environment variables...")
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

        # Validate filter configuration
        if not (0 <= self.filters.instant_min_confidence <= 1):
            print("❌ Instant filter confidence must be between 0 and 1")
            return False

        if not (0 <= self.filters.spam_min_confidence <= 1):
            print("❌ Spam filter confidence must be between 0 and 1")
            return False

        if not (0 <= self.filters.micro_min_confidence <= 1):
            print("❌ Micro filter confidence must be between 0 and 1")
            return False

        if self.filters.instant_min_volume_usd <= 0:
            print("❌ Instant filter minimum volume must be greater than 0")
            return False

        if self.filters.spam_min_volume_usd <= 0:
            print("❌ Spam filter minimum volume must be greater than 0")
            return False

        if self.filters.micro_min_volume_usd <= 0:
            print("❌ Micro filter minimum volume must be greater than 0")
            return False

        # Validate risk thresholds
        if not (0 <= self.risk_thresholds.risk_level_critical <= 1):
            print("❌ Risk level critical must be between 0 and 1")
            return False

        if not (0 <= self.risk_thresholds.risk_level_high <= 1):
            print("❌ Risk level high must be between 0 and 1")
            return False

        if not (0 <= self.risk_thresholds.risk_level_medium <= 1):
            print("❌ Risk level medium must be between 0 and 1")
            return False

        if not (0 < self.risk_thresholds.position_size_high_risk_multiplier <= 1):
            print("❌ Position size high risk multiplier must be between 0 and 1")
            return False

        if not (0 < self.risk_thresholds.position_size_medium_risk_multiplier <= 1):
            print("❌ Position size medium risk multiplier must be between 0 and 1")
            return False

        # Validate strategy thresholds
        if not (0 < self.strategy_thresholds.stop_loss_below_support <= 1):
            print("❌ Stop loss below support must be between 0 and 1")
            return False

        if not (1 <= self.strategy_thresholds.stop_loss_above_resistance <= 2):
            print("❌ Stop loss above resistance must be between 1 and 2")
            return False

        if not (0 < self.strategy_thresholds.position_age_exit_hours <= 24):
            print("❌ Position age exit hours must be between 0 and 24")
            return False

        if not (0 <= self.strategy_thresholds.base_confidence <= 1):
            print("❌ Base confidence must be between 0 and 1")
            return False

        # Validate RPC providers configuration
        if not self.validate_rpc_providers():
            print("❌ RPC providers validation failed")
            return False

        # Validate MEV configuration
        if not self.validate_mev_config():
            print("❌ MEV configuration validation failed")
            return False

        return True

    fn validate_rpc_providers(self) -> Bool:
        """
        Validate RPC providers configuration values
        """
        try:
            # Validate routing policy
            valid_policies = ["health_first", "latency_based", "cost_based", "environment_based", "round_robin"]
            if self.rpc_providers.routing_policy not in valid_policies:
                print(f"❌ Invalid routing policy: {self.rpc_providers.routing_policy}")
                print(f"   Valid options: {', '.join(valid_policies)}")
                return False

            # Validate routing latency threshold
            if not (0 < self.rpc_providers.routing_latency_threshold_ms <= 2000):
                print("❌ Routing latency threshold must be > 0 and ≤ 2000ms")
                return False

            # Validate bundle success rate threshold
            if not (0.0 <= self.rpc_providers.routing_bundle_success_rate_threshold <= 1.0):
                print("❌ Bundle success rate threshold must be between 0 and 1")
                return False

            # Validate Helius ShredStream configuration
            if self.rpc_providers.helius_enable_shredstream:
                if not self.rpc_providers.helius_shredstream_endpoint:
                    print("❌ ShredStream endpoint required when enabled")
                    return False
                if not (self.rpc_providers.helius_shredstream_endpoint.startswith("ws://") or
                       self.rpc_providers.helius_shredstream_endpoint.startswith("wss://")):
                    print("❌ ShredStream endpoint must start with ws:// or wss://")
                    return False

            # Validate QuickNode Li'l JIT configuration
            if self.rpc_providers.quicknode_enable_lil_jit:
                if not self.rpc_providers.quicknode_lil_jit_endpoint:
                    print("❌ Li'l JIT endpoint required when enabled")
                    return False
                if not (self.rpc_providers.quicknode_lil_jit_endpoint.startswith("https://")):
                    print("❌ Li'l JIT endpoint must be an HTTPS URL")
                    return False

            # Validate Helius tier
            valid_tiers = ["free", "developer", "pro", "enterprise"]
            if self.rpc_providers.helius_tier not in valid_tiers:
                print(f"❌ Invalid Helius tier: {self.rpc_providers.helius_tier}")
                print(f"   Valid options: {', '.join(valid_tiers)}")
                return False

            # Log successful validation
            print("✅ RPC providers configuration validation passed")
            return True

        except Exception as e:
            print(f"⚠️  Error validating RPC providers: {e}")
            return False

    fn validate_mev_config(self) -> Bool:
        """
        Validate MEV configuration values
        """
        try:
            # Validate bundle submission provider
            valid_providers = ["helius", "quicknode", "auto"]
            if self.mev.bundle_submission_provider not in valid_providers:
                print(f"❌ Invalid bundle submission provider: {self.mev.bundle_submission_provider}")
                print(f"   Valid options: {', '.join(valid_providers)}")
                return False

            # Validate Jito configuration
            if self.mev.jito_enabled:
                if self.mev.jito_tip_lamports < 0:
                    print("❌ Jito tip lamports must be >= 0")
                    return False

                if self.mev.jito_max_tip_lamports < self.mev.jito_tip_lamports:
                    print("❌ Jito max tip must be >= tip")
                    return False

                if self.mev.min_profit_threshold_sol < 0:
                    print("❌ Minimum profit threshold must be >= 0")
                    return False

            # Log successful validation
            print("✅ MEV configuration validation passed")
            return True

        except Exception as e:
            print(f"⚠️  Error validating MEV configuration: {e}")
            return False

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
        print(f"   Database Enabled: {self.database.enabled}")
        print(f"   Alerts Enabled: {self.monitoring.enable_alerts}")

        # New configuration sections
        print("   🛡️  Filter Thresholds:")
        print(f"      Instant: Vol≥${self.filters.instant_min_volume_usd:.0f}, Conf≥{self.filters.instant_min_confidence:.0%}")
        print(f"      Spam: Vol≥${self.filters.spam_min_volume_usd:.0f}, Conf≥{self.filters.spam_min_confidence:.0%}")
        print(f"      Micro: Vol≥${self.filters.micro_min_volume_usd:.0f}, Conf≥{self.filters.micro_min_confidence:.0%}")

        print("   ⚠️  Risk Thresholds:")
        print(f"      Critical: {self.risk_thresholds.risk_level_critical:.0%}")
        print(f"      High: {self.risk_thresholds.risk_level_high:.0%}")
        print(f"      Medium: {self.risk_thresholds.risk_level_medium:.0%}")
        print(f"      RSI: {self.risk_thresholds.rsi_extreme_overbought:.0f}/{self.risk_thresholds.rsi_extreme_oversold:.0f}")

        print("   📈 Strategy Thresholds:")
        print(f"      Stop Loss: {self.strategy_thresholds.stop_loss_below_support:.0%}")
        print(f"      Exit: {self.strategy_thresholds.position_age_exit_hours:.1f}h")
        print(f"      Base Confidence: {self.strategy_thresholds.base_confidence:.0%}")

# =============================================================================
# Backtesting Configuration (PumpFun Sniper)
# =============================================================================

@value
struct BacktestDataSourcesConfig:
    """
    Configuration for backtesting data sources
    """
    var jupiter_price_api_enabled: Bool
    var helius_metadata_enabled: Bool
    var quicknode_realtime_enabled: Bool
    var data_quality_threshold: Float
    var min_data_points: Int
    var max_data_gap_hours: Int

    fn __init__(
        jupiter_price_api_enabled: Bool = True,
        helius_metadata_enabled: Bool = True,
        quicknode_realtime_enabled: Bool = True,
        data_quality_threshold: Float = 0.7,
        min_data_points: Int = 50,
        max_data_gap_hours: Int = 2
    ):
        self.jupiter_price_api_enabled = jupiter_price_api_enabled
        self.helius_metadata_enabled = helius_metadata_enabled
        self.quicknode_realtime_enabled = quicknode_realtime_enabled
        self.data_quality_threshold = data_quality_threshold
        self.min_data_points = min_data_points
        self.max_data_gap_hours = max_data_gap_hours


@value
struct BacktestPumpFunFiltersConfig:
    """
    Configuration for PumpFun token analysis filters in backtesting
    """
    # Token screening thresholds
    var min_market_cap_usd: Float
    var max_market_cap_usd: Float
    var min_liquidity_usd: Float
    var min_volume_24h_usd: Float
    var max_age_hours: Int

    # Security and safety checks
    var max_holder_concentration: Float
    var min_holders: Int
    var max_creator_allocation: Float
    var honeypot_risk_threshold: Float

    # Social and community metrics
    var min_social_mentions: Int
    var min_social_sentiment: Float
    var max_social_spam_score: Float
    var min_telegram_members: Int
    var min_twitter_followers: Int

    # Technical analysis criteria
    var min_trading_volume_usd: Float
    var max_price_volatility: Float
    var min_price_stability: Float
    var trend_strength_threshold: Float
    var momentum_threshold: Float

    # Financial metrics
    var min_revenue_24h_usd: Float
    var max_supply_inflation: Float
    var burn_rate_threshold: Float

    fn __init__(
        # Token screening thresholds
        min_market_cap_usd: Float = 1000.0,
        max_market_cap_usd: Float = 100000.0,
        min_liquidity_usd: Float = 500.0,
        min_volume_24h_usd: Float = 10000.0,
        max_age_hours: Int = 168,

        # Security and safety checks
        max_holder_concentration: Float = 0.8,
        min_holders: Int = 10,
        max_creator_allocation: Float = 0.2,
        honeypot_risk_threshold: Float = 0.7,

        # Social and community metrics
        min_social_mentions: Int = 5,
        min_social_sentiment: Float = 0.3,
        max_social_spam_score: Float = 0.8,
        min_telegram_members: Int = 50,
        min_twitter_followers: Int = 100,

        # Technical analysis criteria
        min_trading_volume_usd: Float = 5000.0,
        max_price_volatility: Float = 0.5,
        min_price_stability: Float = 0.7,
        trend_strength_threshold: Float = 0.4,
        momentum_threshold: Float = 0.02,

        # Financial metrics
        min_revenue_24h_usd: Float = 0.0,
        max_supply_inflation: Float = 0.1,
        burn_rate_threshold: Float = 0.05
    ):
        self.min_market_cap_usd = min_market_cap_usd
        self.max_market_cap_usd = max_market_cap_usd
        self.min_liquidity_usd = min_liquidity_usd
        self.min_volume_24h_usd = min_volume_24h_usd
        self.max_age_hours = max_age_hours

        self.max_holder_concentration = max_holder_concentration
        self.min_holders = min_holders
        self.max_creator_allocation = max_creator_allocation
        self.honeypot_risk_threshold = honeypot_risk_threshold

        self.min_social_mentions = min_social_mentions
        self.min_social_sentiment = min_social_sentiment
        self.max_social_spam_score = max_social_spam_score
        self.min_telegram_members = min_telegram_members
        self.min_twitter_followers = min_twitter_followers

        self.min_trading_volume_usd = min_trading_volume_usd
        self.max_price_volatility = max_price_volatility
        self.min_price_stability = min_price_stability
        self.trend_strength_threshold = trend_strength_threshold
        self.momentum_threshold = momentum_threshold

        self.min_revenue_24h_usd = min_revenue_24h_usd
        self.max_supply_inflation = max_supply_inflation
        self.burn_rate_threshold = burn_rate_threshold


@value
struct BacktestRiskManagementConfig:
    """
    Risk management configuration for backtesting
    """
    var max_position_size_percent: Float
    var max_portfolio_risk: Float
    var max_drawdown_threshold: Float
    var stop_loss_percentage: Float
    var take_profit_percentage: Float
    var max_leverage: Float

    fn __init__(
        max_position_size_percent: Float = 10.0,
        max_portfolio_risk: Float = 0.02,
        max_drawdown_threshold: Float = 0.15,
        stop_loss_percentage: Float = 0.05,
        take_profit_percentage: Float = 0.10,
        max_leverage: Float = 1.0
    ):
        self.max_position_size_percent = max_position_size_percent
        self.max_portfolio_risk = max_portfolio_risk
        self.max_drawdown_threshold = max_drawdown_threshold
        self.stop_loss_percentage = stop_loss_percentage
        self.take_profit_percentage = take_profit_percentage
        self.max_leverage = max_leverage


@value
struct BacktestExecutionConfig:
    """
    Execution simulation parameters for backtesting
    """
    var slippage_model: String
    var base_slippage_percentage: Float
    var commission_rate: Float
    var max_slippage_percentage: Float
    var min_trade_size_usd: Float
    var max_trade_size_usd: Float

    # Simulation timing parameters
    var order_execution_delay_ms: Int
    var block_confirmation_delay_ms: Int
    var network_congestion_factor: Float

    fn __init__(
        slippage_model: String = "linear",
        base_slippage_percentage: Float = 0.002,
        commission_rate: Float = 0.003,
        max_slippage_percentage: Float = 0.02,
        min_trade_size_usd: Float = 10.0,
        max_trade_size_usd: Float = 10000.0,
        order_execution_delay_ms: Int = 100,
        block_confirmation_delay_ms: Int = 400,
        network_congestion_factor: Float = 1.1
    ):
        self.slippage_model = slippage_model
        self.base_slippage_percentage = base_slippage_percentage
        self.commission_rate = commission_rate
        self.max_slippage_percentage = max_slippage_percentage
        self.min_trade_size_usd = min_trade_size_usd
        self.max_trade_size_usd = max_trade_size_usd
        self.order_execution_delay_ms = order_execution_delay_ms
        self.block_confirmation_delay_ms = block_confirmation_delay_ms
        self.network_congestion_factor = network_congestion_factor


@value
struct BacktestAdvancedConfig:
    """
    Advanced backtesting features configuration
    """
    # Monte Carlo simulation
    var enable_monte_carlo: Bool
    var monte_carlo_simulations: Int
    var confidence_intervals: List[Float]

    # Stress testing
    var enable_stress_testing: Bool
    var stress_scenarios: List[String]
    var stress_test_multiplier: Float

    # Sensitivity analysis
    var enable_sensitivity_analysis: Bool
    var sensitivity_parameters: List[String]

    # Walk-forward optimization
    var enable_walk_forward: Bool
    var walk_forward_windows: List[Int]
    var optimization_metric: String

    fn __init__(
        enable_monte_carlo: Bool = True,
        monte_carlo_simulations: Int = 1000,
        confidence_intervals: List[Float] = [0.95, 0.99],
        enable_stress_testing: Bool = True,
        stress_scenarios: List[String] = ["market_crash", "liquidity_crisis", "volatility_spike", "network_congestion"],
        stress_test_multiplier: Float = 2.0,
        enable_sensitivity_analysis: Bool = True,
        sensitivity_parameters: List[String] = ["slippage", "commission", "delay", "volatility"],
        enable_walk_forward: Bool = True,
        walk_forward_windows: List[Int] = [168, 336, 720],
        optimization_metric: String = "sharpe_ratio"
    ):
        self.enable_monte_carlo = enable_monte_carlo
        self.monte_carlo_simulations = monte_carlo_simulations
        self.confidence_intervals = confidence_intervals
        self.enable_stress_testing = enable_stress_testing
        self.stress_scenarios = stress_scenarios
        self.stress_test_multiplier = stress_test_multiplier
        self.enable_sensitivity_analysis = enable_sensitivity_analysis
        self.sensitivity_parameters = sensitivity_parameters
        self.enable_walk_forward = enable_walk_forward
        self.walk_forward_windows = walk_forward_windows
        self.optimization_metric = optimization_metric


@value
struct BacktestValidationConfig:
    """
    Backtest validation and quality control configuration
    """
    var enable_cross_validation: Bool
    var cross_validation_folds: Int
    var out_of_sample_percentage: Float
    var min_backtest_period_days: Int
    var max_backtest_period_days: Int

    # Statistical significance testing
    var significance_level: Float
    var min_trades_for_significance: Int
    var bootstrap_samples: Int

    # Performance benchmarking
    var enable_benchmarking: Bool
    var benchmark_strategies: List[String]
    var risk_free_rate: Float

    fn __init__(
        enable_cross_validation: Bool = True,
        cross_validation_folds: Int = 5,
        out_of_sample_percentage: Float = 0.2,
        min_backtest_period_days: Int = 7,
        max_backtest_period_days: Int = 365,
        significance_level: Float = 0.05,
        min_trades_for_significance: Int = 30,
        bootstrap_samples: Int = 1000,
        enable_benchmarking: Bool = True,
        benchmark_strategies: List[String] = ["buy_and_hold", "random_trading", "momentum_only", "mean_reversion_only"],
        risk_free_rate: Float = 0.02
    ):
        self.enable_cross_validation = enable_cross_validation
        self.cross_validation_folds = cross_validation_folds
        self.out_of_sample_percentage = out_of_sample_percentage
        self.min_backtest_period_days = min_backtest_period_days
        self.max_backtest_period_days = max_backtest_period_days
        self.significance_level = significance_level
        self.min_trades_for_significance = min_trades_for_significance
        self.bootstrap_samples = bootstrap_samples
        self.enable_benchmarking = enable_benchmarking
        self.benchmark_strategies = benchmark_strategies
        self.risk_free_rate = risk_free_rate


@value
struct BacktestResultsConfig:
    """
    Results storage and reporting configuration
    """
    var enable_result_storage: Bool
    var result_storage_format: String
    var detailed_trade_logs: Bool
    var performance_metrics: List[String]

    # Report generation
    var generate_html_reports: Bool
    var generate_pdf_reports: Bool
    var include_charts: Bool
    var chart_resolution: String

    fn __init__(
        enable_result_storage: Bool = True,
        result_storage_format: String = "json",
        detailed_trade_logs: Bool = True,
        performance_metrics: List[String] = ["total_return", "sharpe_ratio", "max_drawdown", "win_rate", "profit_factor"],
        generate_html_reports: Bool = True,
        generate_pdf_reports: Bool = False,
        include_charts: Bool = True,
        chart_resolution: String = "high"
    ):
        self.enable_result_storage = enable_result_storage
        self.result_storage_format = result_storage_format
        self.detailed_trade_logs = detailed_trade_logs
        self.performance_metrics = performance_metrics
        self.generate_html_reports = generate_html_reports
        self.generate_pdf_reports = generate_pdf_reports
        self.include_charts = include_charts
        self.chart_resolution = chart_resolution


@value
struct BacktestAlertsConfig:
    """
    Alert thresholds for backtesting
    """
    var enable_performance_alerts: Bool
    var performance_alert_threshold: Float
    var enable_error_alerts: Bool
    var max_error_rate: Float
    var enable_timeout_alerts: Bool
    var max_timeout_rate: Float

    fn __init__(
        enable_performance_alerts: Bool = True,
        performance_alert_threshold: Float = 0.1,
        enable_error_alerts: Bool = True,
        max_error_rate: Float = 0.05,
        enable_timeout_alerts: Bool = True,
        max_timeout_rate: Float = 0.02
    ):
        self.enable_performance_alerts = enable_performance_alerts
        self.performance_alert_threshold = performance_alert_threshold
        self.enable_error_alerts = enable_error_alerts
        self.max_error_rate = max_error_rate
        self.enable_timeout_alerts = enable_timeout_alerts
        self.max_timeout_rate = max_timeout_rate


@value
struct BacktestMonitoringConfig:
    """
    Integration with monitoring systems
    """
    var prometheus_metrics_enabled: Bool
    var metrics_port: Int
    var granularity_seconds: Int
    var custom_metrics: List[String]

    # Health checks
    var health_check_interval_seconds: Int
    var health_check_timeout_seconds: Int
    var max_memory_usage_percent: Float
    var max_cpu_usage_percent: Float

    fn __init__(
        prometheus_metrics_enabled: Bool = True,
        metrics_port: Int = 8002,
        granularity_seconds: Int = 60,
        custom_metrics: List[String] = ["backtest_duration", "data_quality_score", "filter_pass_rate"],
        health_check_interval_seconds: Int = 30,
        health_check_timeout_seconds: Int = 5,
        max_memory_usage_percent: Float = 80.0,
        max_cpu_usage_percent: Float = 90.0
    ):
        self.prometheus_metrics_enabled = prometheus_metrics_enabled
        self.metrics_port = metrics_port
        self.granularity_seconds = granularity_seconds
        self.custom_metrics = custom_metrics
        self.health_check_interval_seconds = health_check_interval_seconds
        self.health_check_timeout_seconds = health_check_timeout_seconds
        self.max_memory_usage_percent = max_memory_usage_percent
        self.max_cpu_usage_percent = max_cpu_usage_percent


@value
struct BacktestHistoricalDataConfig:
    """
    Historical data management configuration
    """
    var data_sources: List[String]
    var update_interval_hours: Int
    var historical_lookback_days: Int
    var data_compression: Bool
    var compression_ratio: Float

    # Data quality metrics
    var enable_data_quality_monitoring: Bool
    var data_quality_threshold: Float
    var missing_data_tolerance: Float
    var outlier_detection_enabled: Bool
    var outlier_threshold_sigma: Float

    fn __init__(
        data_sources: List[String] = ["jupiter", "coingecko", "defillama", "dexscreener"],
        update_interval_hours: Int = 1,
        historical_lookback_days: Int = 365,
        data_compression: Bool = True,
        compression_ratio: Float = 0.1,
        enable_data_quality_monitoring: Bool = True,
        data_quality_threshold: Float = 0.8,
        missing_data_tolerance: Float = 0.05,
        outlier_detection_enabled: Bool = True,
        outlier_threshold_sigma: Float = 3.0
    ):
        self.data_sources = data_sources
        self.update_interval_hours = update_interval_hours
        self.historical_lookback_days = historical_lookback_days
        self.data_compression = data_compression
        self.compression_ratio = compression_ratio
        self.enable_data_quality_monitoring = enable_data_quality_monitoring
        self.data_quality_threshold = data_quality_threshold
        self.missing_data_tolerance = missing_data_tolerance
        self.outlier_detection_enabled = outlier_detection_enabled
        self.outlier_threshold_sigma = outlier_threshold_sigma


@value
struct BacktestSchedulingConfig:
    """
    Backtest scheduling and automation configuration
    """
    var enable_scheduled_backtests: Bool
    var schedule_timezone: String
    var run_interval_hours: Int
    var batch_size: Int
    var enable_parallel_batches: Bool
    var max_parallel_batches: Int

    # Backtest prioritization
    var prioritization_method: String
    var priority_tokens: List[String]
    var exclude_tokens: List[String]

    fn __init__(
        enable_scheduled_backtests: Bool = True,
        schedule_timezone: String = "UTC",
        run_interval_hours: Int = 6,
        batch_size: Int = 50,
        enable_parallel_batches: Bool = True,
        max_parallel_batches: Int = 4,
        prioritization_method: String = "market_cap",
        priority_tokens: List[String] = [],
        exclude_tokens: List[String] = []
    ):
        self.enable_scheduled_backtests = enable_scheduled_backtests
        self.schedule_timezone = schedule_timezone
        self.run_interval_hours = run_interval_hours
        self.batch_size = batch_size
        self.enable_parallel_batches = enable_parallel_batches
        self.max_parallel_batches = max_parallel_batches
        self.prioritization_method = prioritization_method
        self.priority_tokens = priority_tokens
        self.exclude_tokens = exclude_tokens


@value
struct BacktestDevelopmentConfig:
    """
    Development and testing configuration
    """
    var enable_debug_mode: Bool
    var debug_log_level: String
    var verbose_output: Bool
    var save_intermediate_results: Bool
    var mock_external_apis: Bool

    # Test data and scenarios
    var test_data_directory: String
    var test_scenarios_enabled: Bool
    var integration_tests_enabled: Bool
    var performance_tests_enabled: Bool

    fn __init__(
        enable_debug_mode: Bool = False,
        debug_log_level: String = "DEBUG",
        verbose_output: Bool = False,
        save_intermediate_results: Bool = False,
        mock_external_apis: Bool = False,
        test_data_directory: String = "./test_data",
        test_scenarios_enabled: Bool = True,
        integration_tests_enabled: Bool = True,
        performance_tests_enabled: Bool = False
    ):
        self.enable_debug_mode = enable_debug_mode
        self.debug_log_level = debug_log_level
        self.verbose_output = verbose_output
        self.save_intermediate_results = save_intermediate_results
        self.mock_external_apis = mock_external_apis
        self.test_data_directory = test_data_directory
        self.test_scenarios_enabled = test_scenarios_enabled
        self.integration_tests_enabled = integration_tests_enabled
        self.performance_tests_enabled = performance_tests_enabled


@value
struct BacktestConfig:
    """
    Main backtesting configuration container
    """
    # Enable/disable backtesting features
    var enabled: Bool
    var data_retention_days: Int

    # Backtest execution parameters
    var max_concurrent_backtests: Int
    var default_initial_investment: Float
    var default_simulation_hours: Int
    var default_time_interval: String

    # Performance optimization
    var enable_simd_vectorization: Bool
    var chunk_size: Int
    var parallel_workers: Int
    var cache_price_history: Bool
    var cache_ttl_hours: Int

    # Sub-configurations
    var data_sources: BacktestDataSourcesConfig
    var pumpfun_filters: BacktestPumpFunFiltersConfig
    var risk_management: BacktestRiskManagementConfig
    var execution: BacktestExecutionConfig
    var advanced: BacktestAdvancedConfig
    var validation: BacktestValidationConfig
    var results: BacktestResultsConfig
    var alerts: BacktestAlertsConfig
    var monitoring: BacktestMonitoringConfig
    var historical_data: BacktestHistoricalDataConfig
    var scheduling: BacktestSchedulingConfig
    var development: BacktestDevelopmentConfig

    fn __init__(
        enabled: Bool = True,
        data_retention_days: Int = 30,
        max_concurrent_backtests: Int = 10,
        default_initial_investment: Float = 1000.0,
        default_simulation_hours: Int = 24,
        default_time_interval: String = "5m",
        enable_simd_vectorization: Bool = True,
        chunk_size: Int = 1024,
        parallel_workers: Int = 4,
        cache_price_history: Bool = True,
        cache_ttl_hours: Int = 1
    ):
        self.enabled = enabled
        self.data_retention_days = data_retention_days
        self.max_concurrent_backtests = max_concurrent_backtests
        self.default_initial_investment = default_initial_investment
        self.default_simulation_hours = default_simulation_hours
        self.default_time_interval = default_time_interval
        self.enable_simd_vectorization = enable_simd_vectorization
        self.chunk_size = chunk_size
        self.parallel_workers = parallel_workers
        self.cache_price_history = cache_price_history
        self.cache_ttl_hours = cache_ttl_hours

        # Initialize sub-configurations with defaults
        self.data_sources = BacktestDataSourcesConfig()
        self.pumpfun_filters = BacktestPumpFunFiltersConfig()
        self.risk_management = BacktestRiskManagementConfig()
        self.execution = BacktestExecutionConfig()
        self.advanced = BacktestAdvancedConfig()
        self.validation = BacktestValidationConfig()
        self.results = BacktestResultsConfig()
        self.alerts = BacktestAlertsConfig()
        self.monitoring = BacktestMonitoringConfig()
        self.historical_data = BacktestHistoricalDataConfig()
        self.scheduling = BacktestSchedulingConfig()
        self.development = BacktestDevelopmentConfig()


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