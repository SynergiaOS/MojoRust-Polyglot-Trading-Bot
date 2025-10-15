# =============================================================================
# Connection Pool Monitoring Module
# =============================================================================

from collections import Dict, List, Any
from core.config import Config
from core.logger import get_logger
from time import time
from monitoring.alert_system import AlertSystem

@value
struct ConnectionPoolStats:
    """
    Connection pool statistics for monitoring
    """
    var component: String
    var pool_size: Int
    var active_connections: Int
    var idle_connections: Int
    var total_requests: Int
    var successful_requests: Int
    var failed_requests: Int
    var timeout_requests: Int
    var avg_response_time: Float
    var min_response_time: Float
    var max_response_time: Float
    var last_updated: Float
    var error_rate: Float
    var success_rate: Float

    fn __init__(component: String):
        self.component = component
        self.pool_size = 0
        self.active_connections = 0
        self.idle_connections = 0
        self.total_requests = 0
        self.successful_requests = 0
        self.failed_requests = 0
        self.timeout_requests = 0
        self.avg_response_time = 0.0
        self.min_response_time = float('inf')
        self.max_response_time = 0.0
        self.last_updated = time()
        self.error_rate = 0.0
        self.success_rate = 1.0

struct ConnectionPoolMonitor:
    """
    Centralized connection pool monitoring system
    """

    # Monitoring state
    var pool_stats: Dict[String, ConnectionPoolStats]
    var alert_system: AlertSystem
    var config: Config
    var logger: Any

    # Thresholds
    var error_rate_threshold: Float
    var response_time_threshold: Float
    var success_rate_threshold: Float
    var connection_utilization_threshold: Float

    # Alert cooldowns
    var last_alert_time: Dict[String, Float]
    var alert_cooldown_seconds: Float

    fn __init__(config: Config, alert_system: AlertSystem):
        """
        Initialize connection pool monitor
        """
        self.config = config
        self.alert_system = alert_system
        self.logger = get_logger("ConnectionPoolMonitor")
        self.pool_stats = {}
        self.last_alert_time = {}

        # Set monitoring thresholds
        self.error_rate_threshold = 0.05  # 5% error rate threshold
        self.response_time_threshold = 2.0  # 2 second response time threshold
        self.success_rate_threshold = 0.95  # 95% success rate threshold
        self.connection_utilization_threshold = 0.8  # 80% connection utilization threshold
        self.alert_cooldown_seconds = 300.0  # 5 minutes alert cooldown

        self.logger.info("Connection pool monitor initialized",
                        error_rate_threshold=self.error_rate_threshold,
                        response_time_threshold=self.response_time_threshold,
                        success_rate_threshold=self.success_rate_threshold)

    fn register_pool(self, component: String, pool_size: Int):
        """
        Register a connection pool for monitoring
        """
        if component not in self.pool_stats:
            self.pool_stats[component] = ConnectionPoolStats(component)
            self.pool_stats[component].pool_size = pool_size

            self.logger.info("Connection pool registered for monitoring",
                            component=component, pool_size=pool_size)
        else:
            # Update pool size if it changed
            self.pool_stats[component].pool_size = pool_size

    fn update_pool_stats(self, component: String, stats_update: Dict[String, Any]):
        """
        Update connection pool statistics
        """
        if component not in self.pool_stats:
            self.register_pool(component, stats_update.get("pool_size", 0))

        var pool_stat = self.pool_stats[component]
        current_time = time()

        # Update connection counts
        if "active_connections" in stats_update:
            pool_stat.active_connections = stats_update["active_connections"]
        if "idle_connections" in stats_update:
            pool_stat.idle_connections = stats_update["idle_connections"]

        # Update request statistics
        if "request_success" in stats_update:
            pool_stat.total_requests += 1
            pool_stat.successful_requests += 1

            # Update response time
            if "response_time" in stats_update:
                response_time = stats_update["response_time"]
                pool_stat.min_response_time = min(pool_stat.min_response_time, response_time)
                pool_stat.max_response_time = max(pool_stat.max_response_time, response_time)

                # Calculate rolling average
                if pool_stat.total_requests == 1:
                    pool_stat.avg_response_time = response_time
                else:
                    alpha = 0.1  # Smoothing factor
                    pool_stat.avg_response_time = (alpha * response_time +
                                                 (1 - alpha) * pool_stat.avg_response_time)

        elif "request_failure" in stats_update:
            pool_stat.total_requests += 1
            pool_stat.failed_requests += 1

        elif "request_timeout" in stats_update:
            pool_stat.total_requests += 1
            pool_stat.timeout_requests += 1

        # Update rates
        if pool_stat.total_requests > 0:
            pool_stat.success_rate = pool_stat.successful_requests / pool_stat.total_requests
            pool_stat.error_rate = (pool_stat.failed_requests + pool_stat.timeout_requests) / pool_stat.total_requests

        pool_stat.last_updated = current_time

        # Check for alert conditions
        self._check_alert_conditions(component, pool_stat)

    def _check_alert_conditions(self, component: String, pool_stat: ConnectionPoolStats):
        """
        Check if pool statistics exceed alert thresholds
        """
        current_time = time()

        # Check alert cooldown
        last_alert = self.last_alert_time.get(component, 0.0)
        if current_time - last_alert < self.alert_cooldown_seconds:
            return

        issues = []
        alert_level = "WARNING"

        # Check error rate
        if pool_stat.error_rate > self.error_rate_threshold:
            issues.append(f"High error rate ({pool_stat.error_rate:.1%})")
            if pool_stat.error_rate > self.error_rate_threshold * 2:
                alert_level = "CRITICAL"

        # Check success rate
        if pool_stat.success_rate < self.success_rate_threshold:
            issues.append(f"Low success rate ({pool_stat.success_rate:.1%})")
            if pool_stat.success_rate < self.success_rate_threshold * 0.8:
                alert_level = "CRITICAL"

        # Check response time
        if pool_stat.avg_response_time > self.response_time_threshold:
            issues.append(f"Slow response time ({pool_stat.avg_response_time:.2f}s)")
            if pool_stat.avg_response_time > self.response_time_threshold * 2:
                alert_level = "CRITICAL"

        # Check connection utilization
        if pool_stat.pool_size > 0:
            utilization = pool_stat.active_connections / pool_stat.pool_size
            if utilization > self.connection_utilization_threshold:
                issues.append(f"High connection utilization ({utilization:.1%})")
                if utilization > 0.95:
                    alert_level = "CRITICAL"

        # Send alert if issues detected
        if len(issues) > 0:
            self._send_pool_alert(component, pool_stat, issues, alert_level)
            self.last_alert_time[component] = current_time

    def _send_pool_alert(self, component: String, pool_stat: ConnectionPoolStats, issues: List[String], level: String):
        """
        Send connection pool alert
        """
        pool_stats_dict = {
            "component": component,
            "pool_size": pool_stat.pool_size,
            "active_connections": pool_stat.active_connections,
            "idle_connections": pool_stat.idle_connections,
            "total_requests": pool_stat.total_requests,
            "success_rate": pool_stat.success_rate,
            "error_rate": pool_stat.error_rate,
            "avg_response_time": pool_stat.avg_response_time,
            "min_response_time": pool_stat.min_response_time,
            "max_response_time": pool_stat.max_response_time,
            "last_updated": pool_stat.last_updated
        }

        issue_summary = ", ".join(issues)
        self.alert_system.send_connection_pool_alert(component, pool_stats_dict, issue_summary)

        self.logger.warn("Connection pool alert sent",
                        component=component,
                        level=level,
                        issues=issues,
                        error_rate=pool_stat.error_rate,
                        success_rate=pool_stat.success_rate,
                        avg_response_time=pool_stat.avg_response_time)

    fn get_pool_stats(self, component: String) -> Dict[String, Any]:
        """
        Get current statistics for a specific pool
        """
        if component not in self.pool_stats:
            return {"error": f"Pool {component} not found"}

        pool_stat = self.pool_stats[component]

        # Calculate utilization
        utilization = 0.0
        if pool_stat.pool_size > 0:
            utilization = pool_stat.active_connections / pool_stat.pool_size

        return {
            "component": pool_stat.component,
            "pool_size": pool_stat.pool_size,
            "active_connections": pool_stat.active_connections,
            "idle_connections": pool_stat.idle_connections,
            "total_requests": pool_stat.total_requests,
            "successful_requests": pool_stat.successful_requests,
            "failed_requests": pool_stat.failed_requests,
            "timeout_requests": pool_stat.timeout_requests,
            "success_rate": pool_stat.success_rate,
            "error_rate": pool_stat.error_rate,
            "avg_response_time": pool_stat.avg_response_time,
            "min_response_time": pool_stat.min_response_time,
            "max_response_time": pool_stat.max_response_time,
            "utilization": utilization,
            "last_updated": pool_stat.last_updated
        }

    fn get_all_pool_stats(self) -> Dict[String, Dict[String, Any]]:
        """
        Get statistics for all monitored pools
        """
        all_stats = {}
        for component in self.pool_stats.keys():
            all_stats[component] = self.get_pool_stats(component)
        return all_stats

    fn get_health_summary(self) -> Dict[String, Any]:
        """
        Get overall health summary of all connection pools
        """
        total_pools = len(self.pool_stats)
        healthy_pools = 0
        warning_pools = 0
        critical_pools = 0
        total_requests = 0
        total_errors = 0

        for component, pool_stat in self.pool_stats.items():
            total_requests += pool_stat.total_requests
            total_errors += pool_stat.failed_requests + pool_stat.timeout_requests

            # Determine pool health status
            if (pool_stat.error_rate > self.error_rate_threshold * 2 or
                pool_stat.success_rate < self.success_rate_threshold * 0.8 or
                pool_stat.avg_response_time > self.response_time_threshold * 2):
                critical_pools += 1
            elif (pool_stat.error_rate > self.error_rate_threshold or
                  pool_stat.success_rate < self.success_rate_threshold or
                  pool_stat.avg_response_time > self.response_time_threshold):
                warning_pools += 1
            else:
                healthy_pools += 1

        overall_error_rate = total_errors / total_requests if total_requests > 0 else 0.0

        return {
            "total_pools": total_pools,
            "healthy_pools": healthy_pools,
            "warning_pools": warning_pools,
            "critical_pools": critical_pools,
            "overall_error_rate": overall_error_rate,
            "total_requests": total_requests,
            "total_errors": total_errors,
            "health_score": healthy_pools / total_pools if total_pools > 0 else 1.0
        }

    def log_periodic_summary(self):
        """
        Log periodic summary of connection pool health
        """
        health_summary = self.get_health_summary()

        self.logger.info("Connection pool health summary",
                        total_pools=health_summary["total_pools"],
                        healthy_pools=health_summary["healthy_pools"],
                        warning_pools=health_summary["warning_pools"],
                        critical_pools=health_summary["critical_pools"],
                        overall_error_rate=f"{health_summary['overall_error_rate']:.2%}",
                        health_score=f"{health_summary['health_score']:.2%}",
                        total_requests=health_summary["total_requests"])

    fn reset_stats(self, component: String):
        """
        Reset statistics for a specific pool
        """
        if component in self.pool_stats:
            pool_stat = self.pool_stats[component]
            pool_size = pool_stat.pool_size  # Preserve pool size

            # Reset the pool stats
            self.pool_stats[component] = ConnectionPoolStats(component)
            self.pool_stats[component].pool_size = pool_size

            self.logger.info("Connection pool statistics reset", component=component)

    def shutdown(self):
        """
        Shutdown the connection pool monitor
        """
        self.logger.info("Connection pool monitor shutting down",
                        total_pools=len(self.pool_stats))

        # Log final summary
        self.log_periodic_summary()

        # Clear all stats
        self.pool_stats.clear()
        self.last_alert_time.clear()