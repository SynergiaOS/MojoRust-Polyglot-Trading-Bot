# =============================================================================
# Application Constants
# =============================================================================

from tensor import Tensor
from os import getenv

# =============================================================================
# Psychological Market Cap Levels (USD)
# These are key support/resistance levels in memecoin markets
# =============================================================================

let PSYCHOLOGICAL_LEVELS = Tensor[
    1000.0,    # $1k - Entry level
    5000.0,    # $5k - Early stage
    10000.0,   # $10k - Small cap
    25000.0,   # $25k - Micro cap
    50000.0,   # $50k - Small project
    75000.0,   # $75k - Growing project
    100000.0,  # $100k - Milestone
    250000.0,  # $250k - Established project
    500000.0,  # $500k - Significant project
    750000.0,  # $750k - Large project
    1000000.0, # $1M - Major milestone
    1500000.0, # $1.5M - Strong project
    2000000.0, # $2M - Very strong project
    5000000.0, # $5M - Premium project
    10000000.0 # $10M - Elite project
]

# =============================================================================
# RSI Timeframe Mapping Based on Token Age
# =============================================================================

let RSI_TIMEFRAME_MAPPING = {
    "seconds_old": "1s",      # < 1 minute old
    "minutes_old": "5s",      # < 1 hour old
    "hours_old": "15s",       # < 24 hours old
    "days_old": "1m",         # < 7 days old
    "established": "5m"       # >= 7 days old
}

# =============================================================================
# Default Trading Constants (DEPRECATED - Use config instead)
# =============================================================================

# ⚠️ DEPRECATED: These constants are replaced by configuration system
# Use config.filters.*, config.risk_thresholds.*, config.strategy_thresholds.*
# Kept for backward compatibility - will be removed in v2.0

let DEFAULT_RSI_PERIOD = 14            # DEPRECATED: Use config.strategy.rsi_period
let OVERSOLD_THRESHOLD = 25.0           # DEPRECATED: Use config.strategy.oversold_threshold
let OVERBOUGHT_THRESHOLD = 75.0         # DEPRECATED: Use config.strategy.overbought_threshold
let MIN_CONFLUENCE_STRENGTH = 0.7        # DEPRECATED: Use config.strategy.min_confluence_strength
let MAX_SLIPPAGE = 0.02                  # DEPRECATED: Use config.execution.max_slippage
let MIN_LIQUIDITY_USD = 10000.0          # DEPRECATED: Use config.filters.spam_min_liquidity_usd
let MIN_VOLUME_USD = 5000.0              # DEPRECATED: Use config.filters.spam_min_volume_usd

# =============================================================================
# Micro Timeframe Filter Constants (DEPRECATED - Use config instead)
# =============================================================================

# ⚠️ DEPRECATED: These constants are replaced by configuration system
# Use config.filters.micro_* instead of these constants
# Kept for backward compatibility - will be removed in v2.0

# Ultra-strict thresholds for high-risk micro timeframes (1s, 5s, 15s)
let MICRO_MIN_VOLUME_USD = 15000.0          # DEPRECATED: Use config.filters.micro_min_volume_usd
let MICRO_MIN_CONFIDENCE = 0.75             # DEPRECATED: Use config.filters.micro_min_confidence
let MICRO_COOLDOWN_SECONDS = 60.0           # DEPRECATED: Use config.filters.micro_cooldown_seconds
let MICRO_MIN_PRICE_STABILITY = 0.80        # DEPRECATED: Use config.filters.micro_min_price_stability
let MICRO_MAX_PRICE_CHANGE_5MIN = 0.30      # DEPRECATED: Use config.filters.micro_max_price_change_5min
let MICRO_EXTREME_PRICE_SPIKE = 0.50        # DEPRECATED: Use config.filters.micro_extreme_price_spike

# Micro timeframe targets
let MICRO_TARGET_TIMEFRAMES = ["1s", "5s", "15s"]  # DEPRECATED: Use config in MicroTimeframeFilter

# Pump & Dump detection thresholds
let MICRO_VOLUME_SPIKE_THRESHOLD = 3.0      # DEPRECATED: Use config.filters.micro_volume_spike_ratio
let MICRO_EXTREME_PRICE_CHANGE = 0.20       # DEPRECATED: Use config.filters.micro_extreme_price_change
let MICRO_MAX_HOLDER_CONCENTRATION = 0.80   # DEPRECATED: Use config.filters.micro_max_holder_concentration
let MICRO_MIN_LIQUIDITY_RATIO = 0.5         # DEPRECATED: Use config.filters.micro_min_liquidity_ratio
let MICRO_MIN_TX_SIZE_RATIO = 0.001         # DEPRECATED: Use config.filters.micro_min_tx_size_ratio
let MICRO_MAX_TX_SIZE_RATIO = 0.10         # DEPRECATED: Use config.filters.micro_max_tx_size_ratio
let MICRO_MIN_VOLUME_CONSISTENCY = 0.6     # DEPRECATED: Use config.filters.micro_volume_consistency
let MICRO_MIN_LIQUIDITY_MULTIPLIER = 1.5    # DEPRECATED: Use config.filters.micro_liquidity_multiplier

# =============================================================================
# Performance Targets
# =============================================================================

let MAX_LATENCY_MS = 100.0
let TARGET_CYCLE_TIME_MS = 1000.0
let MAX_API_TIMEOUT_MS = 5000.0
let MAX_EXECUTION_TIME_MS = 100.0

# =============================================================================
# Solana Constants
# =============================================================================

let SOL_DECIMALS = 9
let LAMPORTS_PER_SOL = 1000000000
let TOKEN_PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
let SYSTEM_PROGRAM_ID = "11111111111111111111111111111111"

# =============================================================================
# API Endpoints
# =============================================================================

let HELIUS_BASE_URL = "https://api.helius.xyz/v0"
let DEXSCREENER_BASE_URL = "https://api.dexscreener.com/latest"
let JUPITER_QUOTE_API = "https://quote-api.jup.ag/v6"
let JUPITER_SWAP_API = "https://quote-api.jup.ag/v6/swap"

# =============================================================================
# Error Codes
# =============================================================================

enum TradingErrorCode:
    SUCCESS = 0
    API_ERROR = 1001
    VALIDATION_ERROR = 1002
    EXECUTION_ERROR = 1003
    RISK_REJECTED = 1004
    INSUFFICIENT_FUNDS = 1005
    NETWORK_ERROR = 1006
    TIMEOUT_ERROR = 1007
    WASH_TRADING_DETECTED = 1008
    PUMP_DUMP_DETECTED = 1009
    LIQUIDITY_INSUFFICIENT = 1010
    POSITION_TOO_LARGE = 1011
    MAX_DRAWDOWN_BREACHED = 1012
    DAILY_LIMIT_REACHED = 1013
    CORRELATION_TOO_HIGH = 1014
    SLIPPAGE_TOO_HIGH = 1015
    GAS_TOO_HIGH = 1016
    TRANSACTION_FAILED = 1017
    WALLET_ERROR = 1018
    CONFIG_ERROR = 1019
    DATABASE_ERROR = 1020
    UNKNOWN_ERROR = 9999

# =============================================================================
# Trading Action Codes
# =============================================================================

enum TradingActionCode:
    BUY = 1
    SELL = 2
    HOLD = 3
    CLOSE_POSITION = 4
    EMERGENCY_EXIT = 5

# =============================================================================
# Market Regime Detection Thresholds
# =============================================================================

let TREND_UP_THRESHOLD = 0.03    # 3% price increase
let TREND_DOWN_THRESHOLD = -0.03  # -3% price decrease
let VOLATILITY_THRESHOLD = 0.05   # 5% price movement
let MOMENTUM_THRESHOLD = 0.02     # 2% momentum

# =============================================================================
# Risk Management Constants
# =============================================================================

let MIN_RISK_REWARD_RATIO = 2.0     # Minimum 2:1 reward/risk
let DEFAULT_STOP_LOSS_PERCENTAGE = 0.15  # 15% stop loss
let MAX_CORRELATION_THRESHOLD = 0.7     # 70% max correlation
let MIN_DIVERSIFICATION_SCORE = 0.5     # Minimum diversification score
let MAX_POSITION_PERCENTAGE = 0.10      # 10% max position size
let CIRCUIT_BREAKER_THRESHOLD = 0.10    # 10% drawdown triggers halt

# =============================================================================
# Spam Filter Thresholds
# =============================================================================

let WASH_TRADING_SCORE_THRESHOLD = 0.7    # 70% wash trading score = reject
let PUMP_DUMP_RISK_THRESHOLD = 0.6       # 60% pump/dump risk = reject
let MIN_UNIQUE_TRADERS = 10               # Minimum unique traders
let MAX_TOP_HOLDER_CONCENTRATION = 0.8    # 80% top 10 holders = reject
let MIN_LIQUIDITY_LOCK_RATIO = 0.5        # 50% liquidity must be locked

# =============================================================================
# Time Constants (in seconds)
# =============================================================================

let SECOND = 1.0
let MINUTE = 60.0
let HOUR = 3600.0
let DAY = 86400.0
let WEEK = 604800.0

# Token age thresholds
let NEW_TOKEN_THRESHOLD = HOUR              # 1 hour
let ESTABLISHED_TOKEN_THRESHOLD = WEEK * 1  # 7 days

# Time-based exits
let MAX_HOLD_TIME_HOURS = 4.0
let MIN_HOLD_TIME_MINUTES = 5.0

# API timeouts
let DEFAULT_TIMEOUT_SECONDS = 5.0
let LONG_TIMEOUT_SECONDS = 30.0
def QUICK_TIMEOUT_SECONDS = 1.0

# =============================================================================
# Cache TTL Constants (in seconds)
# =============================================================================

let TOKEN_METADATA_TTL = 300.0      # 5 minutes
let MARKET_DATA_TTL = 10.0          # 10 seconds
let QUOTE_TTL = 5.0                 # 5 seconds
let RSI_CACHE_TTL = 60.0            # 1 minute
let SENTIMENT_TTL = 300.0           # 5 minutes
let RISK_ANALYSIS_TTL = 120.0       # 2 minutes

# =============================================================================
# Database Query Limits
# =============================================================================

let MAX_QUERY_RESULTS = 1000
let DEFAULT_BATCH_SIZE = 100
let MAX_BATCH_SIZE = 500

# =============================================================================
# Monitoring Constants
# =============================================================================

let METRICS_COLLECTION_INTERVAL = 60.0   # 1 minute
let HEALTH_CHECK_INTERVAL = 30.0         # 30 seconds
let ALERT_COOLDOWN_PERIOD = 300.0        # 5 minutes

# Performance alert thresholds
let SLOW_CYCLE_THRESHOLD = 2.0          # 2 seconds
let HIGH_LATENCY_THRESHOLD = 500.0       # 500ms
let ERROR_RATE_THRESHOLD = 0.05          # 5% error rate

# =============================================================================
# Debugging Constants
# =============================================================================

let DEBUG_MODE = getenv("DEBUG_MODE", "false").lower() == "true"
let VERBOSE_LOGGING = getenv("VERBOSE_LOGGING", "false").lower() == "true"
let MOCK_APIS = getenv("MOCK_APIS", "false").lower() == "true"

# =============================================================================
# Utility Functions
# =============================================================================

def get_optimal_rsi_timeframe(age_hours: Float) -> String:
    """
    Get optimal RSI timeframe based on token age
    """
    if age_hours < 1.0/60.0:          # < 1 minute
        return RSI_TIMEFRAME_MAPPING["seconds_old"]
    elif age_hours < 1.0:             # < 1 hour
        return RSI_TIMEFRAME_MAPPING["minutes_old"]
    elif age_hours < 24.0:            # < 24 hours
        return RSI_TIMEFRAME_MAPPING["hours_old"]
    elif age_hours < 168.0:           # < 7 days
        return RSI_TIMEFRAME_MAPPING["days_old"]
    else:
        return RSI_TIMEFRAME_MAPPING["established"]

def find_nearest_psychological_level(current_mcap: Float, above: Bool = True) -> Float:
    """
    Find nearest psychological support/resistance level
    """
    if above:
        # Find nearest level above current market cap
        for level in PSYCHOLOGICAL_LEVELS:
            if level > current_mcap:
                return level
    else:
        # Find nearest level below current market cap
        for level in reversed(PSYCHOLOGICAL_LEVELS):
            if level < current_mcap:
                return level

    return current_mcap  # Fallback

def calculate_distance_to_level(current_value: Float, level: Float) -> Float:
    """
    Calculate percentage distance to a level
    """
    if level == 0:
        return 0.0

    return abs(current_value - level) / level

def is_new_token(age_hours: Float) -> Bool:
    """
    Check if token is considered new
    """
    return age_hours < NEW_TOKEN_THRESHOLD / HOUR

def is_established_token(age_hours: Float) -> Bool:
    """
    Check if token is established
    """
    return age_hours >= ESTABLISHED_TOKEN_THRESHOLD / HOUR

def should_use_enhanced_analysis(confidence: Float) -> Bool:
    """
    Determine if enhanced algorithmic analysis should be used based on signal confidence
    """
    return confidence > 0.8

def calculate_position_size_multiplier(risk_score: Float) -> Float:
    """
    Calculate position size multiplier based on risk score
    """
    if risk_score <= 0.3:      # Low risk
        return 1.0
    elif risk_score <= 0.6:    # Medium risk
        return 0.7
    elif risk_score <= 0.8:    # High risk
        return 0.4
    else:                      # Critical risk
        return 0.1

def is_valid_solana_address(address: String) -> Bool:
    """
    Basic validation for Solana addresses
    """
    if len(address) not in [43, 44]:  # Solana addresses are 43-44 characters
        return False

    # Basic character check (base58)
    valid_chars = set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    return all(char in valid_chars for char in address)

def format_sol_amount(amount: Float, decimals: Int = SOL_DECIMALS) -> String:
    """
    Format SOL amount with appropriate decimal places
    """
    divisor = 10 ** decimals
    sol_amount = amount / divisor

    if sol_amount < 0.001:
        return f"{sol_amount:.8f} SOL"
    elif sol_amount < 1.0:
        return f"{sol_amount:.6f} SOL"
    else:
        return f"{sol_amount:.4f} SOL"

def calculate_percentage_change(old_value: Float, new_value: Float) -> Float:
    """
    Calculate percentage change between two values
    """
    if old_value == 0:
        return 0.0

    return (new_value - old_value) / old_value

def is_within_trading_hours() -> Bool:
    """
    Check if current time is within optimal trading hours
    """
    # Memecoins are most active during UTC 12:00 - 22:00
    from time import time, gmtime
    current_hour = gmtime(time()).tm_hour
    return 12 <= current_hour <= 22

# =============================================================================
# Constants for Different Environments
# =============================================================================

def get_max_position_size(env: String) -> Float:
    """
    Get max position size based on environment
    """
    if env == "production":
        return 0.10    # 10%
    elif env == "staging":
        return 0.05    # 5%
    else:  # development
        return 0.02    # 2%

def get_initial_capital(env: String) -> Float:
    """
    Get recommended initial capital based on environment
    """
    if env == "production":
        return 100.0   # 100 SOL
    elif env == "staging":
        return 10.0    # 10 SOL
    else:  # development
        return 1.0     # 1 SOL