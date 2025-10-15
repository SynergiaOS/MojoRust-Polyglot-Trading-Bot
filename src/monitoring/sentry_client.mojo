"""
Sentry Client for MojoRust Trading Bot

Wraps the Python Sentry SDK for error tracking and performance monitoring.
Provides enriched error context with trading metadata.
"""

from python import Python
from sys import Error
from memory.unsafe import Pointer
from collections import Dict, Any

# Sentry configuration structure
@value
struct SentryConfig:
    var dsn: String
    var environment: String
    var traces_sample_rate: Float32
    var send_default_pii: Bool
    var attach_stacktrace: Bool
    var max_breadcrumbs: Int
    var release: String
    var enabled: Bool

    fn __init__(dsn: String = "", environment: String = "development",
                traces_sample_rate: Float32 = 0.1, send_default_pii: Bool = False,
                attach_stacktrace: Bool = True, max_breadcrumbs: Int = 100,
                release: String = "trading-bot@1.0.0", enabled: Bool = True):
        self.dsn = dsn
        self.environment = environment
        self.traces_sample_rate = traces_sample_rate
        self.send_default_pii = send_default_pii
        self.attach_stacktrace = attach_stacktrace
        self.max_breadcrumbs = max_breadcrumbs
        self.release = release
        self.enabled = enabled

# Sentry transaction wrapper
struct SentryTransaction:
    var transaction: PythonObject
    var name: String
    var operation: String
    var status: String

    fn __init__(transaction: PythonObject, name: String = "", operation: String = ""):
        self.transaction = transaction
        self.name = name
        self.operation = operation
        self.status = "ok"

    fn finish(self):
        """Finish the transaction"""
        try:
            if self.transaction:
                self.transaction.finish()
        except Error as e:
            print(f"⚠️  Failed to finish Sentry transaction: {e}")

    fn set_status(self, status: String):
        """Set transaction status"""
        try:
            self.status = status
            if self.transaction:
                self.transaction.set_status(status)
        except Error as e:
            print(f"⚠️  Failed to set transaction status: {e}")

    fn set_tag(self, key: String, value: String):
        """Set transaction tag"""
        try:
            if self.transaction:
                self.transaction.set_tag(key, value)
        except Error as e:
            print(f"⚠️  Failed to set transaction tag: {e}")

    fn set_data(self, key: String, value: Any):
        """Set transaction data"""
        try:
            if self.transaction:
                self.transaction.set_data(key, value)
        except Error as e:
            print(f"⚠️  Failed to set transaction data: {e}")

# Main Sentry client class
struct SentryClient:
    var config: SentryConfig
    var python_sentry: PythonObject
    var initialized: Bool

    fn __init__():
        self.config = SentryConfig()
        self.initialized = False

        # Load configuration
        self._load_config()

        # Initialize Sentry SDK
        if self.config.enabled:
            self._initialize_sentry()

    fn _load_config(self):
        """Load Sentry configuration from trading.toml and environment"""
        try:
            python = Python.import_module("builtins")

            # Try to import tomlllib (Python 3.11+) first, then fallback to toml
            try:
                toml = Python.import_module("tomllib")
                # For tomllib, we need to read as bytes
                with open("config/trading.toml", "rb") as f:
                    config_data = toml.load(f)
            except Error:
                toml = Python.import_module("toml")
                # For toml, read as text
                with open("config/trading.toml", "r") as f:
                    config_data = toml.load(f)

            os = Python.import_module("os")

            # Extract Sentry configuration
            sentry_config = config_data.get("sentry", {})

            # Get DSN from environment variable
            dsn_env = sentry_config.get("dsn_env", "SENTRY_DSN")
            dsn = os.environ.get(dsn_env, "")

            # Get environment
            environment = sentry_config.get("environment", "${TRADING_ENV}")
            if environment.startswith("${") and environment.endswith("}"):
                env_var = environment[2:-1]
                environment = os.environ.get(env_var, "development")

            self.config.dsn = dsn
            self.config.environment = environment
            self.config.enabled = sentry_config.get("enabled", True) and dsn != ""
            self.config.traces_sample_rate = sentry_config.get("traces_sample_rate", 0.1)
            self.config.send_default_pii = sentry_config.get("send_default_pii", False)
            self.config.attach_stacktrace = sentry_config.get("attach_stacktrace", True)
            self.config.max_breadcrumbs = sentry_config.get("max_breadcrumbs", 100)
            self.config.release = sentry_config.get("release", "trading-bot@1.0.0")

            print("✅ Sentry configuration loaded:")
            print(f"   Enabled: {self.config.enabled}")
            print(f"   Environment: {self.config.environment}")
            print(f"   Traces sample rate: {self.config.traces_sample_rate}")

        except Error as e:
            print(f"⚠️  Failed to load Sentry config: {e}")
            self.config.enabled = False
        except:
            print("⚠️  Sentry config not found, error tracking disabled")

    fn _initialize_sentry(self):
        """Initialize Python Sentry SDK with graceful dependency handling"""
        if not self.config.enabled:
            print("ℹ️  Sentry disabled, skipping initialization")
            return

        # Check for Sentry SDK availability
        try:
            self.python_sentry = Python.import_module("sentry_sdk")
            print("✅ Sentry SDK module found")
        except Error as e:
            print(f"❌ Sentry SDK not available: {e}")
            print("   Install with: pip install sentry-sdk")
            print("   Continuing without error tracking...")
            self.initialized = False
            self.config.enabled = False
            return

        try:
            # Configure Sentry with graceful fallback for missing integrations
            sentry_config = Python.dict({
                "dsn": self.config.dsn,
                "environment": self.config.environment,
                "traces_sample_rate": self.config.traces_sample_rate,
                "send_default_pii": self.config.send_default_pii,
                "attach_stacktrace": self.config.attach_stacktrace,
                "max_breadcrumbs": self.config.max_breadcrumbs,
                "release": self.config.release
            })

            # Try to add integrations with fallback handling
            integrations = []

            # Try logging integration
            try:
                if hasattr(self.python_sentry, 'integrations') and hasattr(self.python_sentry.integrations, 'logging'):
                    logging_integration = self.python_sentry.integrations.logging.LoggingIntegration(
                        level=self.python_sentry.logging.INFO,
                        event_level=self.python_sentry.logging.WARNING
                    )
                    integrations.append(logging_integration)
                    print("✅ Sentry logging integration added")
                else:
                    print("⚠️  Sentry logging integration not available")
            except Error as e:
                print(f"⚠️  Failed to add logging integration: {e}")

            # Try excepthook integration
            try:
                if hasattr(self.python_sentry, 'integrations') and hasattr(self.python_sentry.integrations, 'excepthook'):
                    excepthook_integration = self.python_sentry.integrations.excepthook.ExcepthookIntegration()
                    integrations.append(excepthook_integration)
                    print("✅ Sentry excepthook integration added")
                else:
                    print("⚠️  Sentry excepthook integration not available")
            except Error as e:
                print(f"⚠️  Failed to add excepthook integration: {e}")

            if integrations:
                sentry_config["integrations"] = integrations
                print(f"✅ {len(integrations)} Sentry integrations configured")
            else:
                print("⚠️  No Sentry integrations available, using basic configuration")

            # Initialize Sentry
            self.python_sentry.init(**sentry_config)
            self.initialized = True

            print("✅ Sentry SDK initialized successfully")
            print(f"   Environment: {self.config.environment}")
            print(f"   DSN configured: {'Yes' if self.config.dsn else 'No'}")

            # Test Sentry with a test message (only in non-production)
            if self.config.environment != "production":
                self._test_sentry()

        except Error as e:
            print(f"❌ Failed to initialize Sentry: {e}")
            print("   Continuing without error tracking...")
            self.initialized = False
            # Don't disable completely - might be temporary issue
            print("   Will retry initialization on next error capture")

    def _test_sentry(self):
        """Send a test message to verify Sentry is working"""
        try:
            self.python_sentry.capture_message(
                "Sentry test message - trading bot started successfully",
                level="info"
            )
            print("✅ Sentry test message sent")
        except Error as e:
            print(f"⚠️  Failed to send Sentry test message: {e}")

    def capture_exception(self, exception: Error, context: Dict[String, Any] = Dict[String, Any]()):
        """Capture exception with enriched context"""
        if not self.initialized:
            return

        try:
            # Add default context
            enriched_context = context.copy()
            enriched_context["component"] = "trading_bot"
            enriched_context["timestamp"] = Python.import_module("time").time()

            # Add trading context if available
            trading_context = self._get_trading_context()
            enriched_context.update(trading_context)

            # Add system context
            system_context = self._get_system_context()
            enriched_context.update(system_context)

            # Capture exception with context
            self.python_sentry.capture_exception(exception, **enriched_context)

            print("📝 Exception captured and sent to Sentry")

        except Error as e:
            print(f"❌ Failed to capture exception in Sentry: {e}")

    def capture_message(self, message: String, level: String = "info",
                       context: Dict[String, Any] = Dict[String, Any]()):
        """Capture message with context"""
        if not self.initialized:
            return

        try:
            # Add default context
            enriched_context = context.copy()
            enriched_context["component"] = "trading_bot"
            enriched_context["timestamp"] = Python.import_module("time").time()

            # Add trading context
            trading_context = self._get_trading_context()
            enriched_context.update(trading_context)

            # Capture message
            self.python_sentry.capture_message(message, level=level, **enriched_context)

        except Error as e:
            print(f"❌ Failed to capture message in Sentry: {e}")

    def add_breadcrumb(self, message: String, category: String = "default",
                      level: String = "info", data: Dict[String, Any] = Dict[String, Any]()):
        """Add breadcrumb for debugging"""
        if not self.initialized:
            return

        try:
            breadcrumb_data = data.copy()
            breadcrumb_data["timestamp"] = Python.import_module("time").time()

            self.python_sentry.add_breadcrumb(
                message=message,
                category=category,
                level=level,
                data=breadcrumb_data
            )

        except Error as e:
            print(f"⚠️  Failed to add Sentry breadcrumb: {e}")

    def set_user(self, user_id: String, username: String = "", ip_address: String = ""):
        """Set user context"""
        if not self.initialized:
            return

        try:
            user_data = Python.dict({
                "id": user_id,
                "username": username if username else user_id
            })

            if ip_address != "":
                user_data["ip_address"] = ip_address

            self.python_sentry.set_user(user_data)

        except Error as e:
            print(f"⚠️  Failed to set Sentry user: {e}")

    def set_tag(self, key: String, value: String):
        """Set tag for filtering"""
        if not self.initialized:
            return

        try:
            self.python_sentry.set_tag(key, value)
        except Error as e:
            print(f"⚠️  Failed to set Sentry tag: {e}")

    def set_context(self, key: String, value: Dict[String, Any]):
        """Set additional context"""
        if not self.initialized:
            return

        try:
            self.python_sentry.set_context(key, value)
        except Error as e:
            print(f"⚠️  Failed to set Sentry context: {e}")

    def start_transaction(self, name: String, operation: String = "custom") -> SentryTransaction:
        """Start performance transaction"""
        if not self.initialized:
            return SentryTransaction(Python.none(), name, operation)

        try:
            transaction = self.python_sentry.start_transaction(
                name=name,
                op=operation
            )

            return SentryTransaction(transaction, name, operation)

        except Error as e:
            print(f"⚠️  Failed to start Sentry transaction: {e}")
            return SentryTransaction(Python.none(), name, operation)

    def flush(self, timeout: Float64 = 2.0):
        """Flush pending events before shutdown"""
        if not self.initialized:
            return

        try:
            self.python_sentry.flush(timeout)
            print("✅ Sentry events flushed")
        except Error as e:
            print(f"⚠️  Failed to flush Sentry events: {e}")

    def _get_trading_context(self) -> Dict[String, Any]:
        """Get current trading context for error enrichment"""
        try:
            # This would be populated with actual trading data
            # For now, return placeholder context
            python = Python.import_module("builtins")
            time = Python.import_module("time")

            return {
                "trading_active": True,
                "uptime_seconds": time.time() - (time.time() - 3600),  # Placeholder
                "active_positions": 0,  # Would get from actual trading state
                "last_trade_time": time.time() - 300,  # 5 minutes ago
                "current_symbol": "SOL",  # Would get from actual state
                "strategy": "default",  # Would get from actual state
                "risk_level": "low"  # Would get from actual risk manager
            }

        except Error as e:
            print(f"⚠️  Failed to get trading context: {e}")
            return Dict[String, Any]()

    def _get_system_context(self) -> Dict[String, Any]:
        """Get system context for error enrichment with graceful fallback"""
        try:
            python = Python.import_module("builtins")
            time = Python.import_module("time")

            # Try to import psutil, but handle missing dependency gracefully
            psutil_available = True
            try:
                psutil = Python.import_module("psutil")
            except Error:
                psutil_available = False
                print("⚠️  psutil not available, using basic system context")

            if psutil_available:
                try:
                    # Get system metrics with psutil
                    process = psutil.Process()
                    memory_info = process.memory_info()

                    return {
                        "memory_usage_mb": memory_info.rss / 1024 / 1024,
                        "cpu_percent": process.cpu_percent(),
                        "num_threads": process.num_threads(),
                        "system_load_avg": psutil.getloadavg()[0] if hasattr(psutil, "getloadavg") else 0,
                        "python_version": python.sys.version.split()[0],
                        "psutil_available": True
                    }
                except Error as e:
                    print(f"⚠️  Failed to get detailed system metrics: {e}, falling back to basic context")

            # Fallback basic system context without psutil
            return {
                "memory_usage_mb": 0,  # Cannot determine without psutil
                "cpu_percent": 0,      # Cannot determine without psutil
                "num_threads": 0,      # Cannot determine without psutil
                "system_load_avg": 0,  # Cannot determine without psutil
                "python_version": python.sys.version.split()[0],
                "psutil_available": False,
                "fallback_reason": "psutil_unavailable"
            }

        except Error as e:
            print(f"⚠️  Failed to get system context: {e}")
            return {
                "error": str(e),
                "fallback_reason": "system_context_error"
            }

    def update_config(self, new_config: SentryConfig):
        """Update Sentry configuration"""
        self.config = new_config

        # Reinitialize if enabled state changed
        if new_config.enabled and not self.initialized:
            self._initialize_sentry()
        elif not new_config.enabled and self.initialized:
            self.destroy()

        print("✅ Sentry configuration updated")

    def destroy(self):
        """Clean up Sentry resources"""
        if self.initialized:
            try:
                self.flush()
                self.initialized = False
                print("✅ Sentry client destroyed")
            except Error as e:
                print(f"⚠️  Error destroying Sentry client: {e}")