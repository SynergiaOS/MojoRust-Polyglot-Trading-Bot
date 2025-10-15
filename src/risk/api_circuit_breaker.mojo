# src/risk/api_circuit_breaker.mojo

from time import time
from collections import Dict
from core.logger import get_logger

@value
struct APICircuitBreaker:
    """
    API-level circuit breaker for external service protection.
    Prevents cascading failures from external API outages.
    """
    var failure_counts: Dict[String, Int]
    var last_failure_time: Dict[String, Float]
    var circuit_state: Dict[String, String]
    var failure_threshold: Int
    var timeout_seconds: Float
    var half_open_max_requests: Int
    var half_open_requests: Dict[String, Int]
    var logger: PythonObject

    fn __init__(inout self, failure_threshold: Int = 5, timeout_seconds: Float = 60.0, half_open_max_requests: Int = 3):
        """
        Initializes the circuit breaker with configurable thresholds.
        """
        self.failure_counts = {}
        self.last_failure_time = {}
        self.circuit_state = {}
        self.failure_threshold = failure_threshold
        self.timeout_seconds = timeout_seconds
        self.half_open_max_requests = half_open_max_requests
        self.half_open_requests = {}
        self.logger = get_logger("APICircuitBreaker")

    fn is_available(inout self, service_name: String) -> Bool:
        """
        Checks if a service is available for requests.
        """
        let state = self.get_state(service_name)
        if state == "OPEN":
            if time() - self.last_failure_time.get(service_name, 0.0) > self.timeout_seconds:
                self.circuit_state[service_name] = "HALF_OPEN"
                self.half_open_requests[service_name] = 0
                self.logger.warn("Circuit breaker for " + service_name + " is now HALF_OPEN.")
                return True
            return False
        elif state == "HALF_OPEN":
            # Increment request count for HALF_OPEN state
            self.half_open_requests[service_name] = self.half_open_requests.get(service_name, 0) + 1
            return self.half_open_requests.get(service_name, 0) <= self.half_open_max_requests
        return True

    fn record_result(inout self, service_name: String, success: Bool):
        """
        Records the result of an API call.
        """
        let state = self.get_state(service_name)
        if success:
            if state == "HALF_OPEN":
                self.half_open_requests[service_name] = self.half_open_requests.get(service_name, 0) + 1
                if self.half_open_requests.get(service_name, 0) >= self.half_open_max_requests:
                    self.reset(service_name)
                    self.logger.info("Circuit breaker for " + service_name + " is now CLOSED.")
            else:
                self.reset(service_name)
        else:
            self.failure_counts[service_name] = self.failure_counts.get(service_name, 0) + 1
            self.last_failure_time[service_name] = time()
            if state == "HALF_OPEN" or self.failure_counts.get(service_name, 0) >= self.failure_threshold:
                if state != "OPEN":
                    self.circuit_state[service_name] = "OPEN"
                    self.logger.error("Circuit breaker for " + service_name + " is now OPEN.")

    fn get_state(self, service_name: String) -> String:
        """
        Returns the current circuit state for a service.
        """
        return self.circuit_state.get(service_name, "CLOSED")

    fn reset(inout self, service_name: String):
        """
        Manually resets the circuit breaker for a service.
        """
        self.failure_counts[service_name] = 0
        self.last_failure_time[service_name] = 0.0
        self.circuit_state[service_name] = "CLOSED"
        self.half_open_requests[service_name] = 0

    fn get_statistics(self) -> Dict[String, Any]:
        """
        Returns circuit breaker statistics for all services.
        """
        let stats = Dict[String, Any]()
        for service_name in self.circuit_state.keys():
            let state = self.get_state(service_name)
            let time_in_state = time() - self.last_failure_time.get(service_name, 0.0) if state != "CLOSED" else 0.0
            stats[service_name] = {
                "state": state,
                "failure_count": self.failure_counts.get(service_name, 0),
                "last_failure_time": self.last_failure_time.get(service_name, 0.0),
                "time_in_current_state": time_in_state,
            }
        return stats
