# =============================================================================
# Structured Logging System for MojoRust Trading Bot
# =============================================================================

from time import time
from os import getenv
from collections import Dict, Any

# =============================================================================
# Logger Class
# =============================================================================

@value
struct Logger:
    """
    Structured logging system with configurable log levels
    """
    var level: String
    var level_priority: Dict[String, Int]
    var component: String

    fn __init__(level: String = "info", component: String = "MojoRust"):
        self.level = level.lower()
        self.component = component
        self.level_priority = {
            "debug": 10,
            "info": 20,
            "warn": 30,
            "error": 40,
            "critical": 50
        }

    fn _should_log(self, message_level: String) -> Bool:
        """
        Check if message should be logged based on current level
        """
        message_priority = self.level_priority.get(message_level.lower(), 0)
        current_priority = self.level_priority.get(self.level, 20)
        return message_priority >= current_priority

    fn _format_message(self, level: String, message: String, extra: Dict[String, Any] = {}) -> String:
        """
        Format log message with timestamp and metadata
        """
        timestamp = time()
        level_upper = level.upper()

        # Basic format: [TIMESTAMP] [LEVEL] [COMPONENT] message
        formatted = f"[{timestamp:.3f}] [{level_upper}] [{self.component}] {message}"

        # Add extra fields if provided
        if extra:
            extra_str = " | ".join([f"{k}={v}" for k, v in extra.items()])
            formatted += f" | {extra_str}"

        return formatted

    fn debug(self, message: String, **kwargs):
        """
        Log debug message (detailed information for debugging)
        """
        if self._should_log("debug"):
            extra = Dict(kwargs)
            print(self._format_message("debug", message, extra))

    fn info(self, message: String, **kwargs):
        """
        Log info message (general information about program execution)
        """
        if self._should_log("info"):
            extra = Dict(kwargs)
            print(self._format_message("info", message, extra))

    fn warn(self, message: String, **kwargs):
        """
        Log warning message (something unexpected, but program can continue)
        """
        if self._should_log("warn"):
            extra = Dict(kwargs)
            print(self._format_message("warn", message, extra))

    fn error(self, message: String, **kwargs):
        """
        Log error message (serious problem, program may not continue)
        """
        if self._should_log("error"):
            extra = Dict(kwargs)
            print(self._format_message("error", message, extra))

    fn critical(self, message: String, **kwargs):
        """
        Log critical message (very serious error, program will likely terminate)
        """
        if self._should_log("critical"):
            extra = Dict(kwargs)
            print(self._format_message("critical", message, extra))

    fn log_trade(self, action: String, symbol: String, price: Float, size: Float, **kwargs):
        """
        Specialized logging for trading events
        """
        if self._should_log("info"):
            extra = Dict(kwargs)
            extra["action"] = action
            extra["symbol"] = symbol
            extra["price"] = price
            extra["size"] = size
            message = f"Trade {action}: {symbol}"
            print(self._format_message("info", message, extra))

    fn log_api_call(self, api: String, endpoint: String, response_time: Float, success: Bool, **kwargs):
        """
        Specialized logging for API calls
        """
        level = "debug" if success else "warn"
        if self._should_log(level):
            extra = Dict(kwargs)
            extra["api"] = api
            extra["endpoint"] = endpoint
            extra["response_time_ms"] = response_time
            extra["success"] = success
            status = "SUCCESS" if success else "FAILED"
            message = f"API {status}: {api} {endpoint}"
            print(self._format_message(level, message, extra))

    fn log_metrics(self, metrics: Dict[str, Any]):
        """
        Log performance metrics
        """
        if self._should_log("debug"):
            message = "Performance metrics"
            print(self._format_message("debug", message, metrics))

    fn log_portfolio_update(self, total_value: Float, pnl: Float, positions: Int, **kwargs):
        """
        Log portfolio state changes
        """
        if self._should_log("info"):
            extra = Dict(kwargs)
            extra["total_value"] = total_value
            extra["pnl"] = pnl
            extra["positions"] = positions
            message = f"Portfolio updated: Value={total_value:.4f} SOL, P&L={pnl:+.4f} SOL"
            print(self._format_message("info", message, extra))

    fn set_level(self, new_level: String):
        """
        Change logging level
        """
        self.level = new_level.lower()
        if self.level not in self.level_priority:
            self.warn(f"Invalid log level '{new_level}', using 'info'", current_level=self.level)
            self.level = "info"

    fn get_level(self) -> String:
        """
        Get current logging level
        """
        return self.level

# =============================================================================
# Global Logger Factory
# =============================================================================

# Global logger instances for different components
var _loggers: Dict[String, Logger] = {}

fn get_logger(component: String = "MojoRust") -> Logger:
    """
    Get or create a logger instance for a specific component
    """
    if component not in _loggers:
        # Read log level from environment or use default
        log_level = getenv("LOG_LEVEL", "info")
        _loggers[component] = Logger(log_level, component)
    return _loggers[component]

fn set_global_level(level: String):
    """
    Set log level for all existing loggers
    """
    for logger in _loggers.values():
        logger.set_level(level)

# =============================================================================
# Convenience Functions
# =============================================================================

def debug(message: String, component: String = "MojoRust", **kwargs):
    """
    Convenience function for debug logging
    """
    logger = get_logger(component)
    logger.debug(message, **kwargs)

def info(message: String, component: String = "MojoRust", **kwargs):
    """
    Convenience function for info logging
    """
    logger = get_logger(component)
    logger.info(message, **kwargs)

def warn(message: String, component: String = "MojoRust", **kwargs):
    """
    Convenience function for warning logging
    """
    logger = get_logger(component)
    logger.warn(message, **kwargs)

def error(message: String, component: String = "MojoRust", **kwargs):
    """
    Convenience function for error logging
    """
    logger = get_logger(component)
    logger.error(message, **kwargs)

def critical(message: String, component: String = "MojoRust", **kwargs):
    """
    Convenience function for critical logging
    """
    logger = get_logger(component)
    logger.critical(message, **kwargs)

# =============================================================================
# Component-Specific Loggers
# =============================================================================

def get_main_logger() -> Logger:
    """Get logger for main trading bot"""
    return get_logger("MainBot")

def get_api_logger() -> Logger:
    """Get logger for API operations"""
    return get_logger("API")

def get_execution_logger() -> Logger:
    """Get logger for trade execution"""
    return get_logger("Execution")

def get_risk_logger() -> Logger:
    """Get logger for risk management"""
    return get_logger("Risk")

def get_strategy_logger() -> Logger:
    """Get logger for strategy operations"""
    return get_logger("Strategy")

def get_analysis_logger() -> Logger:
    """Get logger for market analysis"""
    return get_logger("Analysis")

# =============================================================================
# Log Configuration Utilities
# =============================================================================

def configure_logging(level: String = "info", format_type: String = "structured"):
    """
    Configure global logging settings
    """
    set_global_level(level)
    info(f"Logging configured: level={level}, format={format_type}", component="Config")

def log_system_info():
    """
    Log system information for debugging
    """
    logger = get_logger("System")
    logger.info("System startup",
                mojo_version="24.4+",
                timestamp=time(),
                pid="N/A"  # Would need to implement process ID retrieval
                )

def log_configuration(config: Dict[String, Any]):
    """
    Log configuration (excluding sensitive data)
    """
    logger = get_logger("Config")
    safe_config = {}

    # Log non-sensitive configuration
    for key, value in config.items():
        if not ("key" in key.lower() or "secret" in key.lower() or "password" in key.lower()):
            safe_config[key] = value

    logger.info("Configuration loaded", **safe_config)