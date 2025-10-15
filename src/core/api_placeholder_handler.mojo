# =============================================================================
# API Placeholder Handling Strategy
# =============================================================================
# Unified approach for graceful API fallback handling across all clients

from collections import Dict, List, Any
from time import time
from sys import Error
from core.logger import get_api_logger

@value
struct APIFallbackConfig:
    """
    Configuration for API fallback behavior
    """
    var use_real_api: Bool
    var fallback_to_mock: Bool
    var mock_data_consistency: Bool  # Generate consistent mock data based on input
    var log_failures: Bool
    var log_fallbacks: Bool
    var fallback_timeout_ms: Int
    var max_retry_attempts: Int

    fn __init__(use_real_api: Bool = True, fallback_to_mock: Bool = True,
                mock_data_consistency: Bool = True, log_failures: Bool = True,
                log_fallbacks: Bool = True, fallback_timeout_ms: Int = 5000,
                max_retry_attempts: Int = 3):
        self.use_real_api = use_real_api
        self.fallback_to_mock = fallback_to_mock
        self.mock_data_consistency = mock_data_consistency
        self.log_failures = log_failures
        self.log_fallbacks = log_fallbacks
        self.fallback_timeout_ms = fallback_timeout_ms
        self.max_retry_attempts = max_retry_attempts

@value
struct APIResponse:
    """
    Standard API response structure with fallback metadata
    """
    var data: Any
    var success: Bool
    var is_fallback: Bool
    var fallback_reason: String
    var response_time_ms: Float
    var api_source: String
    var error_message: String
    var metadata: Dict[String, Any]

    fn __init__(data: Any = None, success: Bool = False, is_fallback: Bool = False,
                fallback_reason: String = "", response_time_ms: Float = 0.0,
                api_source: String = "unknown", error_message: String = "",
                metadata: Dict[String, Any] = Dict[String, Any]()):
        self.data = data
        self.success = success
        self.is_fallback = is_fallback
        self.fallback_reason = fallback_reason
        self.response_time_ms = response_time_ms
        self.api_source = api_source
        self.error_message = error_message
        self.metadata = metadata

struct APIFallbackHandler:
    """
    Unified API fallback handler for graceful degradation
    """
    var config: APIFallbackConfig
    var logger
    var fallback_stats: Dict[String, Any]

    fn __init__(config: APIFallbackConfig = APIFallbackConfig()):
        self.config = config
        self.logger = get_api_logger()
        self.fallback_stats = {
            "total_requests": 0,
            "successful_requests": 0,
            "fallback_requests": 0,
            "failed_requests": 0,
            "avg_response_time": 0.0
        }

    fn execute_with_fallback[T](self,
                               api_name: String,
                               real_api_call: fn() -> T,
                               mock_fallback: fn() -> T,
                               context: Dict[String, Any] = Dict[String, Any]()) -> APIResponse:
        """
        Execute API call with graceful fallback to mock data
        """
        start_time = time()
        self.fallback_stats["total_requests"] += 1

        response = APIResponse(
            data=None,
            success=False,
            is_fallback=False,
            api_source=api_name,
            metadata=context.copy()
        )

        # Try real API first if enabled
        if self.config.use_real_api:
            for attempt in range(self.config.max_retry_attempts):
                try:
                    result = real_api_call()
                    response_time = (time() - start_time) * 1000.0

                    response.data = result
                    response.success = True
                    response.response_time_ms = response_time
                    response.api_source = f"{api_name}_real"

                    self.fallback_stats["successful_requests"] += 1
                    self._update_avg_response_time(response_time)

                    if self.config.log_fallbacks and attempt > 0:
                        self.logger.info(f"API {api_name} succeeded on attempt {attempt + 1}",
                                       api_name=api_name, attempt=attempt + 1,
                                       response_time_ms=response_time)

                    return response

                except Error as e:
                    if attempt < self.config.max_retry_attempts - 1:
                        if self.config.log_failures:
                            self.logger.warning(f"API {api_name} attempt {attempt + 1} failed, retrying",
                                              api_name=api_name, attempt=attempt + 1,
                                              error=str(e))
                        continue
                    else:
                        if self.config.log_failures:
                            self.logger.error(f"API {api_name} failed after {self.config.max_retry_attempts} attempts",
                                            api_name=api_name, error=str(e))
                        response.error_message = str(e)

        # Fall back to mock data if enabled
        if self.config.fallback_to_mock:
            try:
                mock_result = mock_fallback()
                response_time = (time() - start_time) * 1000.0

                response.data = mock_result
                response.success = True
                response.is_fallback = True
                response.fallback_reason = "api_failure"
                response.response_time_ms = response_time
                response.api_source = f"{api_name}_mock"

                # Add mock metadata
                if self.config.mock_data_consistency:
                    response.metadata["mock_consistent"] = True
                    response.metadata["mock_seed"] = self._generate_seed(context)

                self.fallback_stats["fallback_requests"] += 1
                self._update_avg_response_time(response_time)

                if self.config.log_fallbacks:
                    self.logger.warning(f"API {api_name} fell back to mock data",
                                      api_name=api_name, fallback_reason="api_failure",
                                      response_time_ms=response_time)

                return response

            except Error as e:
                if self.config.log_failures:
                    self.logger.error(f"Mock fallback for {api_name} also failed",
                                    api_name=api_name, error=str(e))
                response.error_message = f"Real API failed, mock fallback also failed: {str(e)}"

        # All attempts failed
        response_time = (time() - start_time) * 1000.0
        response.response_time_ms = response_time
        self.fallback_stats["failed_requests"] += 1

        if self.config.log_failures:
            self.logger.error(f"API {api_name} completely failed",
                            api_name=api_name, total_time_ms=response_time,
                            error=response.error_message)

        return response

    fn _generate_seed(self, context: Dict[String, Any]) -> Int:
        """
        Generate consistent seed for mock data based on context
        """
        seed = 12345  # Base seed

        # Use context to create consistent but varied seed
        for key, value in context.items():
            if isinstance(value, String):
                seed += hash(value)
            elif isinstance(value, Int):
                seed += value
            elif isinstance(value, Float):
                seed += int(value * 1000)

        return abs(seed) % 1000000

    fn _update_avg_response_time(self, response_time: Float):
        """
        Update running average response time
        """
        total = self.fallback_stats["total_requests"]
        current_avg = self.fallback_stats["avg_response_time"]
        self.fallback_stats["avg_response_time"] = (current_avg * (total - 1) + response_time) / total

    fn get_fallback_stats(self) -> Dict[String, Any]:
        """
        Get current fallback statistics
        """
        stats = self.fallback_stats.copy()
        total = stats["total_requests"]

        if total > 0:
            stats["success_rate"] = stats["successful_requests"] / total
            stats["fallback_rate"] = stats["fallback_requests"] / total
            stats["failure_rate"] = stats["failed_requests"] / total
        else:
            stats["success_rate"] = 0.0
            stats["fallback_rate"] = 0.0
            stats["failure_rate"] = 0.0

        return stats

    fn reset_stats(self):
        """
        Reset fallback statistics
        """
        self.fallback_stats = {
            "total_requests": 0,
            "successful_requests": 0,
            "fallback_requests": 0,
            "failed_requests": 0,
            "avg_response_time": 0.0
        }

# Utility functions for common mock data patterns
fn generate_consistent_float(seed: Int, min_val: Float, max_val: Float) -> Float:
    """
    Generate consistent float value within range based on seed
    """
    normalized = (seed % 10000) / 10000.0
    return min_val + (normalized * (max_val - min_val))

fn generate_consistent_int(seed: Int, min_val: Int, max_val: Int) -> Int:
    """
    Generate consistent integer value within range based on seed
    """
    range_size = max_val - min_val + 1
    return min_val + (seed % range_size)

fn generate_consistent_string(seed: Int, prefix: String, suffix: String = "") -> String:
    """
    Generate consistent string with seed-based variation
    """
    return f"{prefix}_{abs(seed)}{suffix}"

fn is_healthy_response(response: APIResponse) -> Bool:
    """
    Check if API response indicates healthy service
    """
    return response.success and not response.is_fallback

fn get_response_health_score(response: APIResponse) -> Float:
    """
    Get health score for API response (0.0-1.0)
    """
    if not response.success:
        return 0.0
    elif response.is_fallback:
        return 0.5  # Partial credit for successful fallback
    else:
        return 1.0  # Full credit for successful real API call