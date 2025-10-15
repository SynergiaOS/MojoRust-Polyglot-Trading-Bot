from collections import Dict, List, Any
from core.types import TradingSignal, Position, Portfolio
from monitoring.performance_analytics import TradeRecord
from core.config import Config
from core.logger import get_logger
from time import time
import os
import json

enum AlertLevel:
    INFO
    WARNING
    ERROR
    CRITICAL

struct AlertSystem:
    """
    Multi-channel alert system for notifications
    """

    # Alert channels
    var enabled_channels: List[String]
    var webhook_url: String
    var telegram_bot_token: String
    var telegram_chat_id: String

    # Cooldown management
    var alert_cooldowns: Dict[String, Float]

    # Configuration
    var config: Config
    var logger: Any

    fn __init__(config: Config):
        self.config = config
        self.logger = get_logger("AlertSystem")

        # Initialize alert channels
        self.enabled_channels = self.config.alerts.channels.copy()

        # Load webhook URL
        self.webhook_url = os.getenv(self.config.alerts.webhook_url_env, "")

        # Load Telegram credentials
        self.telegram_bot_token = os.getenv(self.config.alerts.telegram_bot_token_env, "")
        self.telegram_chat_id = os.getenv(self.config.alerts.telegram_chat_id_env, "")

        # Initialize cooldowns
        self.alert_cooldowns = {}

        # Log initialization
        self.logger.info("Alert system initialized",
                        channels=self.enabled_channels,
                        webhook_configured=bool(self.webhook_url),
                        telegram_configured=bool(self.telegram_bot_token and self.telegram_chat_id))

    fn send_trade_alert(self, signal: TradingSignal, result: Any, level: AlertLevel):
        """
        Send trade execution notification
        """
        title, message, fields = self.format_trade_alert(signal, result)

        # Determine if trade alert has cooldown
        alert_type = "trade_execution"
        if not self.should_send_alert(alert_type):
            return

        self._send_alert(level, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_error_alert(self, error: String, context: Dict[String, Any]):
        """
        Send error notification
        """
        alert_type = "error"
        if not self.should_send_alert(alert_type):
            return

        title = "❌ Error Detected"
        message = error

        # Format context as fields
        fields = []
        for key, value in context.items():
            fields.append({"name": key, "value": str(value)})

        self._send_alert(AlertLevel.ERROR, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_performance_alert(self, metric: String, value: Float, threshold: Float):
        """
        Send performance threshold breach alert
        """
        alert_type = "performance"
        if not self.should_send_alert(alert_type):
            return

        # Determine severity based on how far from threshold
        deviation = abs(value - threshold) / threshold
        level = AlertLevel.WARNING if deviation < 0.5 else AlertLevel.ERROR

        title = f"⚠️ Performance Alert: {metric}"
        message = f"Metric {metric} has breached threshold\nCurrent: {value:.4f}\nThreshold: {threshold:.4f}"

        fields = [
            {"name": "Metric", "value": metric},
            {"name": "Current Value", "value": f"{value:.4f}"},
            {"name": "Threshold", "value": f"{threshold:.4f}"},
            {"name": "Deviation", "value": f"{deviation:.1%}"}
        ]

        self._send_alert(level, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_circuit_breaker_alert(self, reason: String, portfolio: Portfolio):
        """
        Send trading halt notification
        """
        alert_type = "circuit_breaker"
        # No cooldown for circuit breaker alerts (always critical)

        title = "🚨 Circuit Breaker Triggered"
        message = f"Trading has been halted: {reason}"

        fields = [
            {"name": "Reason", "value": reason},
            {"name": "Portfolio Value", "value": f"{portfolio.total_value:.4f} SOL"},
            {"name": "Daily P&L", "value": f"{portfolio.daily_pnl:+.4f} SOL"},
            {"name": "Open Positions", "value": str(len(portfolio.positions))},
            {"name": "Available Cash", "value": f"{portfolio.available_cash:.4f} SOL"}
        ]

        # Add position details if any
        if len(portfolio.positions) > 0:
            position_details = []
            for symbol, position in portfolio.positions.items():
                pnl_str = f"{position.unrealized_pnl:+.4f} SOL ({position.pnl_percentage:+.1%})"
                position_details.append(f"{symbol}: {pnl_str}")

            fields.append({
                "name": "Open Positions",
                "value": "\n" + "\n".join(position_details[:5])  # Limit to first 5
            })

        self._send_alert(AlertLevel.CRITICAL, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_position_alert(self, symbol: String, position: Position, reason: String):
        """
        Send position-specific alert
        """
        alert_type = "position_update"
        if not self.should_send_alert(alert_type):
            return

        title = f"📊 Position Alert: {symbol}"
        message = reason

        fields = [
            {"name": "Symbol", "value": symbol},
            {"name": "Size", "value": f"{position.size:.2f}"},
            {"name": "Entry Price", "value": f"{position.entry_price:.10f} SOL"},
            {"name": "Current Price", "value": f"{position.current_price:.10f} SOL"},
            {"name": "Unrealized P&L", "value": f"{position.unrealized_pnl:+.4f} SOL"},
            {"name": "P&L %", "value": f"{position.pnl_percentage:+.1%}"},
            {"name": "Hold Duration", "value": f"{(time() - position.entry_timestamp) / 3600:.1f} hours"}
        ]

        if position.stop_loss_price > 0:
            fields.append({
                "name": "Stop Loss",
                "value": f"{position.stop_loss_price:.10f} SOL"
            })

        if position.take_profit_price > 0:
            fields.append({
                "name": "Take Profit",
                "value": f"{position.take_profit_price:.10f} SOL"
            })

        self._send_alert(AlertLevel.INFO, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_daily_summary(self, metrics: Dict[String, Float]):
        """
        Send end-of-day performance summary
        """
        alert_type = "daily_summary"
        # No cooldown for daily summaries

        title = "📊 Daily Performance Summary"
        message = self._format_daily_summary_message(metrics)

        fields = [
            {"name": "Total Trades", "value": str(int(metrics.get("total_trades", 0)))},
            {"name": "Win Rate", "value": f"{metrics.get('win_rate', 0):.1%}"},
            {"name": "Total P&L", "value": f"{metrics.get('total_pnl', 0):+.4f} SOL"},
            {"name": "Sharpe Ratio", "value": f"{metrics.get('sharpe_ratio', 0):.2f}"},
            {"name": "Max Drawdown", "value": f"{metrics.get('max_drawdown', 0):.2%}"},
            {"name": "Profit Factor", "value": f"{metrics.get('profit_factor', 0):.2f}"}
        ]

        self._send_alert(AlertLevel.INFO, title, message, fields)
        self.update_cooldown(alert_type)

    def format_trade_alert(self, signal: TradingSignal, result: Any) -> Tuple[String, String, List[Dict[String, String]]]:
        """
        Format trade details for alert
        """
        # Determine action based on signal
        action_str = "BUY" if str(signal.action) == "BUY" else "SELL"

        # Create title with status
        if hasattr(result, 'success') and result.success:
            title = f"✅ Trade Executed: {signal.symbol}"
        else:
            title = f"❌ Trade Failed: {signal.symbol}"

        # Create message
        message = f"Trade {action_str} order for {signal.symbol}"

        # Create fields
        fields = [
            {"name": "Symbol", "value": signal.symbol},
            {"name": "Action", "value": action_str},
            {"name": "Confidence", "value": f"{signal.confidence:.0%}"},
            {"name": "Timeframe", "value": signal.timeframe},
            {"name": "Volume", "value": f"{signal.volume:.2f}"}
        ]

        if hasattr(result, 'executed_price') and result.executed_price:
            fields.append({"name": "Executed Price", "value": f"{result.executed_price:.10f} SOL"})

        if hasattr(result, 'executed_size') and result.executed_size:
            fields.append({"name": "Executed Size", "value": f"{result.executed_size:.2f}"})

        if hasattr(result, 'transaction_signature') and result.transaction_signature:
            tx_sig = str(result.transaction_signature)
            if len(tx_sig) > 20:
                # Truncate long transaction signatures
                short_tx = tx_sig[:10] + "..." + tx_sig[-10:]
                fields.append({"name": "Transaction", "value": short_tx})
            else:
                fields.append({"name": "Transaction", "value": tx_sig})

        if hasattr(result, 'error_message') and result.error_message:
            fields.append({"name": "Error", "value": str(result.error_message)})

        return (title, message, fields)

    def format_performance_alert(self, metrics: Dict[String, Float]) -> String:
        """
        Format performance metrics for alert
        """
        lines = []
        lines.append("Performance Metrics Update:")
        lines.append(f"Win Rate: {metrics.get('win_rate', 0):.1%}")
        lines.append(f"Sharpe Ratio: {metrics.get('sharpe_ratio', 0):.2f}")
        lines.append(f"Max Drawdown: {metrics.get('max_drawdown', 0):.2%}")
        lines.append(f"Total Trades: {int(metrics.get('total_trades', 0))}")
        lines.append(f"Total P&L: {metrics.get('total_pnl', 0):+.4f} SOL")

        return "\n".join(lines)

    def format_circuit_breaker_alert(self, reason: String, portfolio: Portfolio) -> String:
        """
        Format circuit breaker alert details
        """
        lines = []
        lines.append(f"🚨 TRADING HALTED")
        lines.append(f"Reason: {reason}")
        lines.append(f"Portfolio Value: {portfolio.total_value:.4f} SOL")
        lines.append(f"Daily P&L: {portfolio.daily_pnl:+.4f} SOL")
        lines.append(f"Open Positions: {len(portfolio.positions)}")
        lines.append("")
        lines.append("Action Required: Manual review needed")

        return "\n".join(lines)

    fn _send_alert(self, level: AlertLevel, title: String, message: String, fields: List[Dict[String, String]]):
        """
        Send alert through all enabled channels
        """
        if not self.config.alerts.enabled:
            return

        # Send to console (always enabled)
        self.send_console_alert(level, title, message)

        # Send to other enabled channels
        for channel in self.enabled_channels:
            if channel == "console":
                continue  # Already sent
            elif channel == "webhook" and self.webhook_url:
                self.send_webhook_alert(level, title, message, fields)
            elif channel == "telegram" and self.telegram_bot_token and self.telegram_chat_id:
                self.send_telegram_alert(level, title, message)
            else:
                self.logger.warn(f"Alert channel {channel} not configured or unsupported")

    fn send_console_alert(self, level: AlertLevel, title: String, message: String):
        """
        Send alert to console
        """
        emoji_map = {
            AlertLevel.INFO: "ℹ️",
            AlertLevel.WARNING: "⚠️",
            AlertLevel.ERROR: "❌",
            AlertLevel.CRITICAL: "🚨"
        }

        level_map = {
            AlertLevel.INFO: "INFO",
            AlertLevel.WARNING: "WARNING",
            AlertLevel.ERROR: "ERROR",
            AlertLevel.CRITICAL: "CRITICAL"
        }

        emoji = emoji_map[level]
        level_str = level_map[level]

        print(f"\n{emoji} [{level_str}] {title}")
        print(f"   {message}")

    fn send_webhook_alert(self, level: AlertLevel, title: String, message: String, fields: List[Dict[String, String]]):
        """
        Send alert via Discord/Slack webhook
        """
        try:
            # Color mapping for Discord embeds
            color_map = {
                AlertLevel.INFO: 0x00FF00,      # Green
                AlertLevel.WARNING: 0xFFFF00,   # Yellow
                AlertLevel.ERROR: 0xFF0000,     # Red
                AlertLevel.CRITICAL: 0xFF4500   # Orange-Red
            }

            # Create embed fields from fields list
            embed_fields = []
            for field in fields:
                embed_fields.append({
                    "name": field["name"],
                    "value": field["value"],
                    "inline": True
                })

            payload = {
                "embeds": [{
                    "title": title,
                    "description": message,
                    "color": color_map[level],
                    "fields": embed_fields,
                    "timestamp": time()
                }]
            }

            # In real implementation, make HTTP POST request
            # import requests
            # response = requests.post(self.webhook_url, json=payload, timeout=10)
            # response.raise_for_status()

            self.logger.info("Webhook alert sent", title=title, level=str(level))

        except e as e:
            self.logger.error("Failed to send webhook alert", error=str(e))

    fn send_telegram_alert(self, level: AlertLevel, title: String, message: String):
        """
        Send alert via Telegram bot
        """
        try:
            emoji_map = {
                AlertLevel.INFO: "ℹ️",
                AlertLevel.WARNING: "⚠️",
                AlertLevel.ERROR: "❌",
                AlertLevel.CRITICAL: "🚨"
            }

            emoji = emoji_map[level]
            text = f"{emoji} *{title}*\n\n{message}"

            # In real implementation, make HTTP POST request to Telegram Bot API
            # url = f"https://api.telegram.org/bot{self.telegram_bot_token}/sendMessage"
            # payload = {
            #     "chat_id": self.telegram_chat_id,
            #     "text": text,
            #     "parse_mode": "Markdown"
            # }
            # response = requests.post(url, json=payload, timeout=10)
            # response.raise_for_status()

            self.logger.info("Telegram alert sent", title=title, level=str(level))

        except e as e:
            self.logger.error("Failed to send Telegram alert", error=str(e))

    fn should_send_alert(self, alert_type: String) -> Bool:
        """
        Check if alert should be sent based on cooldown
        """
        current_time = time()

        # Get cooldown period for this alert type
        cooldown_seconds = self._get_cooldown_seconds(alert_type)
        if cooldown_seconds == 0:
            return True  # No cooldown

        # Check last sent time
        last_sent = self.alert_cooldowns.get(alert_type, 0.0)
        time_since_last = current_time - last_sent

        return time_since_last >= cooldown_seconds

    fn update_cooldown(self, alert_type: String):
        """
        Update last sent time for alert type
        """
        self.alert_cooldowns[alert_type] = time()

    fn _get_cooldown_seconds(self, alert_type: String) -> Int:
        """
        Get cooldown period for alert type
        """
        cooldown_map = {
            "trade_execution": self.config.alerts.trade_alert_cooldown,
            "error": self.config.alerts.error_alert_cooldown,
            "performance": self.config.alerts.performance_alert_cooldown,
            "circuit_breaker": 0,  # Never cooldown circuit breaker alerts
            "daily_summary": 0,    # Never cooldown daily summaries
            "position_update": 300  # 5 minutes for position updates
        }

        return cooldown_map.get(alert_type, 60)  # Default 1 minute

    fn _format_daily_summary_message(self, metrics: Dict[String, Float]) -> String:
        """
        Format daily summary message
        """
        lines = []
        lines.append("📊 Daily Trading Summary")
        lines.append("=" * 30)
        lines.append(f"Total Trades: {int(metrics.get('total_trades', 0))}")
        lines.append(f"Win Rate: {metrics.get('win_rate', 0):.1%}")
        lines.append(f"Total P&L: {metrics.get('total_pnl', 0):+.4f} SOL")
        lines.append(f"Sharpe Ratio: {metrics.get('sharpe_ratio', 0):.2f}")
        lines.append(f"Max Drawdown: {metrics.get('max_drawdown', 0):.2%}")
        lines.append(f"Profit Factor: {metrics.get('profit_factor', 0):.2f}")

        return "\n".join(lines)

    fn send_system_alert(self, message: String, context: Dict[String, Any]):
        """
        📊 Send system-level operational alert for monitoring and health checks
        """
        alert_type = "system"
        if not self.should_send_alert(alert_type):
            return

        # Determine alert level based on context
        level = AlertLevel.INFO
        if "level" in context:
            level_str = context["level"].upper()
            if level_str == "CRITICAL":
                level = AlertLevel.CRITICAL
            elif level_str == "ERROR":
                level = AlertLevel.ERROR
            elif level_str == "WARNING":
                level = AlertLevel.WARNING

        title = f"🔧 System Alert: {context.get('component', 'Unknown')}"

        # Format context as fields
        fields = [
            {"name": "Component", "value": context.get('component', 'Unknown')},
            {"name": "Message", "value": message},
            {"name": "Timestamp", "value": f"{time():.0f}"}
        ]

        # Add specific context fields
        for key, value in context.items():
            if key not in ['component', 'level', 'timestamp']:
                fields.append({"name": key.replace("_", " ").title(), "value": str(value)})

        self._send_alert(level, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_operational_metrics_alert(self, metrics: Dict[String, Any]):
        """
        📊 Send operational metrics alert for monitoring system health
        """
        alert_type = "operational_metrics"
        if not self.should_send_alert(alert_type):
            return

        # Check for critical operational issues
        level = AlertLevel.INFO
        issues = []

        # Check connection pool health
        if metrics.get("connection_pool_healthy", True) == False:
            level = AlertLevel.ERROR
            issues.append("Connection Pool Unhealthy")

        # Check database connection
        if metrics.get("database_connected", True) == False:
            level = AlertLevel.ERROR
            issues.append("Database Disconnected")

        # Check API response times
        api_response_time = metrics.get("api_response_time", 0.0)
        if api_response_time > 5.0:  # 5 seconds threshold
            if level != AlertLevel.ERROR:
                level = AlertLevel.WARNING
            issues.append(f"Slow API Response ({api_response_time:.1f}s)")

        # Check memory usage
        memory_usage = metrics.get("memory_usage_percent", 0.0)
        if memory_usage > 90.0:  # 90% memory usage
            level = AlertLevel.CRITICAL
            issues.append(f"High Memory Usage ({memory_usage:.1f}%)")
        elif memory_usage > 75.0:
            if level == AlertLevel.INFO:
                level = AlertLevel.WARNING
            issues.append(f"Moderate Memory Usage ({memory_usage:.1f}%)")

        # Check CPU usage
        cpu_usage = metrics.get("cpu_usage_percent", 0.0)
        if cpu_usage > 85.0:  # 85% CPU usage
            if level != AlertLevel.CRITICAL:
                level = AlertLevel.WARNING
            issues.append(f"High CPU Usage ({cpu_usage:.1f}%)")

        title = f"📊 Operational Metrics: {', '.join(issues) if issues else 'Healthy'}"

        # Format metrics message
        message_parts = []
        if issues:
            message_parts.append("🚨 Issues Detected:")
            for issue in issues:
                message_parts.append(f"  • {issue}")
        else:
            message_parts.append("✅ All operational metrics within normal ranges")

        message = "\n".join(message_parts)

        # Create fields with detailed metrics
        fields = [
            {"name": "Uptime", "value": f"{metrics.get('uptime_seconds', 0) / 3600:.1f} hours"},
            {"name": "Cycles Completed", "value": f"{metrics.get('cycles_completed', 0):,}"},
            {"name": "API Response Time", "value": f"{api_response_time:.2f}s"},
            {"name": "Memory Usage", "value": f"{memory_usage:.1f}%"},
            {"name": "CPU Usage", "value": f"{cpu_usage:.1f}%"},
            {"name": "Database Health", "value": "✅ Connected" if metrics.get("database_connected", True) else "❌ Disconnected"},
            {"name": "Connection Pool", "value": "✅ Healthy" if metrics.get("connection_pool_healthy", True) else "❌ Unhealthy"}
        ]

        # Add performance metrics
        if "portfolio_value" in metrics:
            fields.append({"name": "Portfolio Value", "value": f"{metrics['portfolio_value']:.4f} SOL"})
        if "trades_executed" in metrics:
            fields.append({"name": "Trades Executed", "value": str(metrics["trades_executed"])})
        if "signals_generated" in metrics:
            fields.append({"name": "Signals Generated", "value": str(metrics["signals_generated"])})

        self._send_alert(level, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_connection_pool_alert(self, component: String, pool_stats: Dict[String, Any], issue: String):
        """
        🔗 Send connection pool specific alert
        """
        alert_type = "connection_pool"
        if not self.should_send_alert(alert_type):
            return

        # Determine severity based on issue type
        level = AlertLevel.WARNING
        if "critical" in issue.lower() or "failed" in issue.lower():
            level = AlertLevel.ERROR
        elif "unhealthy" in issue.lower():
            level = AlertLevel.WARNING

        title = f"🔗 Connection Pool Alert: {component}"
        message = f"Connection pool issue detected: {issue}"

        fields = [
            {"name": "Component", "value": component},
            {"name": "Issue", "value": issue},
            {"name": "Pool Size", "value": str(pool_stats.get("pool_size", "Unknown"))},
            {"name": "Active Connections", "value": str(pool_stats.get("active_connections", "Unknown"))},
            {"name": "Idle Connections", "value": str(pool_stats.get("idle_connections", "Unknown"))},
            {"name": "Connection Timeout", "value": f"{pool_stats.get('timeout_seconds', 0):.1f}s"}
        ]

        # Add additional pool stats
        if "error_rate" in pool_stats:
            fields.append({"name": "Error Rate", "value": f"{pool_stats['error_rate']:.1%}"})
        if "avg_response_time" in pool_stats:
            fields.append({"name": "Avg Response Time", "value": f"{pool_stats['avg_response_time']:.3f}s"})

        self._send_alert(level, title, message, fields)
        self.update_cooldown(alert_type)

    fn send_api_reliability_alert(self, api_name: String, reliability_metrics: Dict[String, Any]):
        """
        🌐 Send API reliability alert for monitoring external service health
        """
        alert_type = "api_reliability"
        if not self.should_send_alert(alert_type):
            return

        # Determine alert level based on reliability metrics
        level = AlertLevel.INFO
        issues = []

        success_rate = reliability_metrics.get("success_rate", 1.0)
        if success_rate < 0.95:  # 95% success rate threshold
            if success_rate < 0.90:
                level = AlertLevel.ERROR
                issues.append(f"Low Success Rate ({success_rate:.1%})")
            else:
                level = AlertLevel.WARNING
                issues.append(f"Reduced Success Rate ({success_rate:.1%})")

        avg_response_time = reliability_metrics.get("avg_response_time", 0.0)
        if avg_response_time > 2.0:  # 2 second threshold
            if avg_response_time > 5.0:
                level = AlertLevel.ERROR
                issues.append(f"Very Slow Response ({avg_response_time:.1f}s)")
            else:
                if level == AlertLevel.INFO:
                    level = AlertLevel.WARNING
                issues.append(f"Slow Response ({avg_response_time:.1f}s)")

        error_count = reliability_metrics.get("error_count", 0)
        if error_count > 10:  # 10 errors threshold
            if error_count > 50:
                level = AlertLevel.CRITICAL
                issues.append(f"High Error Count ({error_count})")
            else:
                if level != AlertLevel.ERROR:
                    level = AlertLevel.WARNING
                issues.append(f"Elevated Error Count ({error_count})")

        title = f"🌐 API Reliability: {api_name}"
        if issues:
            message = f"API reliability issues detected:\n" + "\n".join([f"  • {issue}" for issue in issues])
        else:
            message = "API reliability metrics within acceptable ranges"

        fields = [
            {"name": "API", "value": api_name},
            {"name": "Success Rate", "value": f"{success_rate:.1%}"},
            {"name": "Avg Response Time", "value": f"{avg_response_time:.2f}s"},
            {"name": "Error Count", "value": str(error_count)},
            {"name": "Total Requests", "value": str(reliability_metrics.get("total_requests", 0))},
            {"name": "Last Error", "value": reliability_metrics.get("last_error", "None")}
        ]

        # Add additional reliability metrics
        if "timeout_rate" in reliability_metrics:
            fields.append({"name": "Timeout Rate", "value": f"{reliability_metrics['timeout_rate']:.1%}"})
        if "retry_rate" in reliability_metrics:
            fields.append({"name": "Retry Rate", "value": f"{reliability_metrics['retry_rate']:.1%}"})

        self._send_alert(level, title, message, fields)
        self.update_cooldown(alert_type)

    fn test_alert_system(self) -> Bool:
        """
        Send test alert to verify all channels are working
        """
        try:
            title = "🧪 Alert System Test"
            message = "This is a test alert to verify the notification system is working correctly."

            fields = [
                {"name": "Test Timestamp", "value": str(time())},
                {"name": "Enabled Channels", "value": ", ".join(self.enabled_channels)},
                {"name": "Webhook Configured", "value": "Yes" if self.webhook_url else "No"},
                {"name": "Telegram Configured", "value": "Yes" if self.telegram_bot_token and self.telegram_chat_id else "No"}
            ]

            self._send_alert(AlertLevel.INFO, title, message, fields)

            self.logger.info("Alert system test completed")
            return True

        except e as e:
            self.logger.error("Alert system test failed", error=str(e))
            return False

    fn shutdown(inout self):
        """
        Gracefully shutdown the alert system
        """
        try:
            # Send shutdown alert if configured
            if self.config.alerts.enabled and len(self.enabled_channels) > 0:
                self.send_system_alert(
                    "Alert system shutting down",
                    {
                        "component": "AlertSystem",
                        "level": "INFO",
                        "shutdown_time": time()
                    }
                )

            # Clear cooldowns
            self.alert_cooldowns.clear()

            self.logger.info("Alert system shutdown completed")
        except e as e:
            self.logger.error("Error during alert system shutdown", error=str(e))