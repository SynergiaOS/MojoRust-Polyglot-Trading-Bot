"""
Rate Limiter for MojoRust Trading Bot

Wraps the Rust SecurityEngine FFI for rate limiting functionality.
Supports multiple strategies: token_bucket, sliding_window, fixed_window, leaky_bucket.
"""

from memory.unsafe import Pointer
from python import Python
from sys import Error

# Import FFI functions from Rust modules
# These are defined in rust-modules/src/ffi/mod.rs

# External FFI function declarations
# Note: These need to be implemented in the Rust FFI module
fn security_engine_new() raises Error = external
fn security_engine_rate_limit(
    engine: Pointer[None],
    client_id: String,
    endpoint: String,
    out_allowed: Pointer[Bool],
    out_remaining: Pointer[Int],
    out_reset_time: Pointer[Float64],
    out_retry_after: Pointer[Int]
) -> None raises = external
fn security_engine_destroy(engine: Pointer[None]) = external

# Configuration structure
@value
struct RateLimiterConfig:
    var enabled: Bool
    var strategy: String
    var max_requests_per_minute: Int
    var max_requests_per_hour: Int
    var burst_size: Int

    fn __init__(enabled: Bool = True, strategy: String = "token_bucket",
                max_requests_per_minute: Int = 100, max_requests_per_hour: Int = 1000,
                burst_size: Int = 20):
        self.enabled = enabled
        self.strategy = strategy
        self.max_requests_per_minute = max_requests_per_minute
        self.max_requests_per_hour = max_requests_per_hour
        self.burst_size = burst_size

# Rate limit result structure
@value
struct RateLimitResult:
    var allowed: Bool
    var remaining: Int
    var reset_time: Float64
    var retry_after: Int
    var message: String

    fn __init__(allowed: Bool = True, remaining: Int = 0, reset_time: Float64 = 0.0,
                retry_after: Int = 0, message: String = ""):
        self.allowed = allowed
        self.remaining = remaining
        self.reset_time = reset_time
        self.retry_after = retry_after
        self.message = message

# Rate limit statistics structure
@value
struct RateLimitStats:
    var client_id: String
    var endpoint: String
    var requests_this_minute: Int
    var requests_this_hour: Int
    var remaining_minute: Int
    var remaining_hour: Int
    var reset_time_minute: Float64
    var reset_time_hour: Float64

    fn __init__(client_id: String = "", endpoint: String = "", requests_this_minute: Int = 0,
                requests_this_hour: Int = 0, remaining_minute: Int = 0, remaining_hour: Int = 0,
                reset_time_minute: Float64 = 0.0, reset_time_hour: Float64 = 0.0):
        self.client_id = client_id
        self.endpoint = endpoint
        self.requests_this_minute = requests_this_minute
        self.requests_this_hour = requests_this_hour
        self.remaining_minute = remaining_minute
        self.remaining_hour = remaining_hour
        self.reset_time_minute = reset_time_minute
        self.reset_time_hour = reset_time_hour

# Main RateLimiter class
struct RateLimiter:
    var security_engine: Pointer[None]
    var config: RateLimiterConfig
    var python_config: PythonObject
    var initialized: Bool

    fn __init__():
        self.security_engine = Pointer[None]()
        self.config = RateLimiterConfig()
        self.initialized = False

        # Load configuration from config file
        self._load_config()

        # Initialize security engine
        if self.config.enabled:
            self._initialize_security_engine()

    fn _load_config(self):
        """Load configuration from trading.toml"""
        try:
            python = Python.import_module("builtins")
            toml = Python.import_module("toml")

            # Read config file
            with open("config/trading.toml", "r") as f:
                config_data = toml.load(f)

            # Extract rate limiting configuration
            rate_limit_config = config_data.get("rate_limiting", {})

            self.config.enabled = rate_limit_config.get("enabled", True)
            self.config.strategy = rate_limit_config.get("strategy", "token_bucket")
            self.config.max_requests_per_minute = rate_limit_config.get("max_requests_per_minute", 100)
            self.config.max_requests_per_hour = rate_limit_config.get("max_requests_per_hour", 1000)
            self.config.burst_size = rate_limit_config.get("burst_size", 20)

            print("✅ Rate limiter configuration loaded:")
            print(f"   Enabled: {self.config.enabled}")
            print(f"   Strategy: {self.config.strategy}")
            print(f"   Max per minute: {self.config.max_requests_per_minute}")
            print(f"   Max per hour: {self.config.max_requests_per_hour}")
            print(f"   Burst size: {self.config.burst_size}")

        except Error as e:
            print(f"⚠️  Failed to load rate limiter config, using defaults: {e}")
            # Keep default values
        except:
            print("⚠️  Config file not found, using rate limiter defaults")

    fn _initialize_security_engine(self):
        """Initialize the Rust SecurityEngine via FFI"""
        try:
            self.security_engine = security_engine_new()
            self.initialized = True
            print("✅ SecurityEngine initialized for rate limiting")
        except Error as e:
            print(f"❌ Failed to initialize SecurityEngine: {e}")
            self.initialized = False
            # Fallback to basic Python implementation
            self._initialize_python_fallback()

    fn _initialize_python_fallback(self):
        """Initialize Python fallback implementation"""
        try:
            python = Python.import_module("builtins")

            # Create Python-based rate limiter
            self.python_config = python.dict()
            self.python_config["enabled"] = self.config.enabled
            self.python_config["strategy"] = self.config.strategy
            self.python_config["max_per_minute"] = self.config.max_requests_per_minute
            self.python_config["max_per_hour"] = self.config.max_requests_per_hour
            self.python_config["burst_size"] = self.config.burst_size
            self.python_config["clients"] = python.dict()  # Store client state

            print("✅ Python fallback rate limiter initialized")

        except Error as e:
            print(f"❌ Failed to initialize Python fallback: {e}")

    fn check_rate_limit(self, client_id: String, endpoint: String) -> RateLimitResult:
        """Check if a request is allowed based on rate limits"""

        if not self.config.enabled:
            return RateLimitResult(allowed=True, remaining=999999, reset_time=0.0, retry_after=0, message="Rate limiting disabled")

        if self.initialized and self.security_engine:
            return self._check_rate_limit_ffi(client_id, endpoint)
        else:
            return self._check_rate_limit_python(client_id, endpoint)

    fn _check_rate_limit_ffi(self, client_id: String, endpoint: String) -> RateLimitResult:
        """Check rate limit using Rust FFI"""
        try:
            # Allocate output variables
            var allowed = False
            var remaining = 0
            var reset_time = 0.0
            var retry_after = 0

            # Call Rust SecurityEngine with out parameters
            security_engine_rate_limit(
                self.security_engine, client_id, endpoint,
                Pointer.addressof(allowed),
                Pointer.addressof(remaining),
                Pointer.addressof(reset_time),
                Pointer.addressof(retry_after)
            )

            return RateLimitResult(
                allowed=allowed,
                remaining=remaining,
                reset_time=reset_time,
                retry_after=retry_after,
                message="Rate limit checked via FFI"
            )

        except Error as e:
            print(f"❌ FFI rate limit check failed: {e}")
            # Fall back to Python implementation
            return self._check_rate_limit_python(client_id, endpoint)

    fn _check_rate_limit_python(self, client_id: String, endpoint: String) -> RateLimitResult:
        """Check rate limit using Python fallback implementation"""
        try:
            python = Python.import_module("builtins")
            time = Python.import_module("time")

            # Get current time
            current_time = time.time()

            # Get or create client state
            client_key = f"{client_id}:{endpoint}"
            if client_key not in self.python_config["clients"]:
                self.python_config["clients"][client_key] = python.dict({
                    "requests_minute": [],
                    "requests_hour": [],
                    "last_minute_reset": current_time,
                    "last_hour_reset": current_time
                })

            client_state = self.python_config["clients"][client_key]

            # Clean old requests (simple implementation)
            self._cleanup_old_requests(client_state, current_time)

            # Check minute limits
            minute_requests = len(client_state["requests_minute"])
            if minute_requests >= self.config.max_requests_per_minute:
                reset_time = client_state["last_minute_reset"] + 60.0
                retry_after = int(max(0, reset_time - current_time))
                return RateLimitResult(
                    allowed=False,
                    remaining=0,
                    reset_time=reset_time,
                    retry_after=retry_after,
                    message="Minute rate limit exceeded"
                )

            # Check hour limits
            hour_requests = len(client_state["requests_hour"])
            if hour_requests >= self.config.max_requests_per_hour:
                reset_time = client_state["last_hour_reset"] + 3600.0
                retry_after = int(max(0, reset_time - current_time))
                return RateLimitResult(
                    allowed=False,
                    remaining=0,
                    reset_time=reset_time,
                    retry_after=retry_after,
                    message="Hour rate limit exceeded"
                )

            # Record this request
            client_state["requests_minute"].append(current_time)
            client_state["requests_hour"].append(current_time)

            # Calculate remaining requests
            remaining_minute = self.config.max_requests_per_minute - len(client_state["requests_minute"])
            remaining_hour = self.config.max_requests_per_hour - len(client_state["requests_hour"])
            remaining_total = min(remaining_minute, remaining_hour)

            return RateLimitResult(
                allowed=True,
                remaining=remaining_total,
                reset_time=current_time + 60.0,
                retry_after=0,
                message="Request allowed"
            )

        except Error as e:
            print(f"❌ Python rate limit check failed: {e}")
            # Allow request by default if rate limiting fails
            return RateLimitResult(allowed=True, remaining=1, reset_time=0.0, retry_after=0, message="Rate limit check failed, allowing request")

    fn _cleanup_old_requests(self, client_state: PythonObject, current_time: Float64):
        """Clean up old request timestamps"""
        try:
            python = Python.import_module("builtins")

            # Clean minute requests (keep only last 60 seconds)
            minute_cutoff = current_time - 60.0
            client_state["requests_minute"] = [
                req_time for req_time in client_state["requests_minute"]
                if req_time > minute_cutoff
            ]

            # Clean hour requests (keep only last 3600 seconds)
            hour_cutoff = current_time - 3600.0
            client_state["requests_hour"] = [
                req_time for req_time in client_state["requests_hour"]
                if req_time > hour_cutoff
            ]

            # Update reset times
            if len(client_state["requests_minute"]) == 0:
                client_state["last_minute_reset"] = current_time

            if len(client_state["requests_hour"]) == 0:
                client_state["last_hour_reset"] = current_time

        except Error as e:
            print(f"⚠️  Failed to cleanup old requests: {e}")

    fn get_rate_limit_stats(self, client_id: String, endpoint: String) -> RateLimitStats:
        """Get current rate limit statistics for a client"""
        try:
            python = Python.import_module("builtins")
            time = Python.import_module("time")

            current_time = time.time()
            client_key = f"{client_id}:{endpoint}"

            if self.initialized and self.security_engine:
                # TODO: Implement FFI stats retrieval
                pass

            # Use Python fallback
            if client_key not in self.python_config["clients"]:
                return RateLimitStats(client_id=client_id, endpoint=endpoint)

            client_state = self.python_config["clients"][client_key]
            self._cleanup_old_requests(client_state, current_time)

            requests_this_minute = len(client_state["requests_minute"])
            requests_this_hour = len(client_state["requests_hour"])
            remaining_minute = self.config.max_requests_per_minute - requests_this_minute
            remaining_hour = self.config.max_requests_per_hour - requests_this_hour
            reset_time_minute = client_state["last_minute_reset"] + 60.0
            reset_time_hour = client_state["last_hour_reset"] + 3600.0

            return RateLimitStats(
                client_id=client_id,
                endpoint=endpoint,
                requests_this_minute=requests_this_minute,
                requests_this_hour=requests_this_hour,
                remaining_minute=remaining_minute,
                remaining_hour=remaining_hour,
                reset_time_minute=reset_time_minute,
                reset_time_hour=reset_time_hour
            )

        except Error as e:
            print(f"❌ Failed to get rate limit stats: {e}")
            return RateLimitStats(client_id=client_id, endpoint=endpoint)

    fn reset_rate_limit(self, client_id: String, endpoint: String) -> Bool:
        """Reset rate limit for a specific client (admin function)"""
        try:
            client_key = f"{client_id}:{endpoint}"

            if self.initialized and self.security_engine:
                # TODO: Implement FFI reset
                pass

            # Reset Python state
            if client_key in self.python_config["clients"]:
                python = Python.import_module("builtins")
                time = Python.import_module("time")
                current_time = time.time()
                self.python_config["clients"][client_key] = {
                    "requests_minute": [],
                    "requests_hour": [],
                    "last_minute_reset": current_time,
                    "last_hour_reset": current_time
                }
                return True

            return False

        except Error as e:
            print(f"❌ Failed to reset rate limit: {e}")
            return False

    fn update_config(self, new_config: RateLimiterConfig):
        """Update rate limiter configuration"""
        self.config = new_config

        # Reinitialize if needed
        if new_config.enabled and not self.initialized:
            self._initialize_security_engine()
        elif not new_config.enabled and self.initialized:
            self.destroy()

        print("✅ Rate limiter configuration updated")

    fn destroy(self):
        """Clean up resources"""
        if self.initialized and self.security_engine:
            try:
                security_engine_destroy(self.security_engine)
                self.initialized = False
                print("✅ SecurityEngine destroyed")
            except Error as e:
                print(f"⚠️  Error destroying SecurityEngine: {e}")

        self.security_engine = Pointer[None]()