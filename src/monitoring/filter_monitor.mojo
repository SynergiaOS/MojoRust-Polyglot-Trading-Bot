# =============================================================================
# Filter Performance Monitoring System
# =============================================================================
# Production monitoring for filter performance, spam detection, and health alerts

from time import time
from collections import Dict, List, Any
from core.logger import get_main_logger
from os import getenv

@value
struct FilterMonitor:
    """Monitor filter performance in production"""
    var logger
    var rejection_rate_history: List[Float]  # Last N rejection rates
    var history_size: Int  # Keep last N data points
    var alert_cooldown: Float  # Seconds between alerts
    var last_alert_time: Float  # Last alert timestamp
    var total_signals_processed: Int
    var total_signals_rejected: Int
    var session_start_time: Float

    # Health thresholds
    var min_healthy_rejection: Float  # Below this = too lenient
    var max_healthy_rejection: Float  # Above this = too aggressive
    var spam_spike_multiplier: Float  # Multiplier for spike detection

    # Performance tracking
    var instant_filter_rejections: Int
    var aggressive_filter_rejections: Int
    var micro_filter_rejections: Int
    var cooldown_rejections: Int
    var volume_quality_rejections: Int

    fn __init__(inout self):
        """Initialize filter monitor with configuration"""
        self.logger = get_main_logger()
        self.rejection_rate_history = List[Float]()
        self.history_size = int(getenv("FILTER_MONITOR_HISTORY_SIZE", "100"))
        self.alert_cooldown = float(getenv("FILTER_ALERT_COOLDOWN", "300.0"))  # 5 minutes
        self.last_alert_time = 0.0
        self.total_signals_processed = 0
        self.total_signals_rejected = 0
        self.session_start_time = time()

        # Health thresholds
        self.min_healthy_rejection = float(getenv("MIN_HEALTHY_REJECTION", "85.0"))  # 85%
        self.max_healthy_rejection = float(getenv("MAX_HEALTHY_REJECTION", "97.0"))  # 97%
        self.spam_spike_multiplier = float(getenv("SPAM_SPIKE_MULTIPLIER", "1.5"))  # 50% spike

        # Performance tracking
        self.instant_filter_rejections = 0
        self.aggressive_filter_rejections = 0
        self.micro_filter_rejections = 0
        self.cooldown_rejections = 0
        self.volume_quality_rejections = 0

        self.logger.info("filter_monitor_initialized", {
            "history_size": self.history_size,
            "min_rejection": self.min_healthy_rejection,
            "max_rejection": self.max_healthy_rejection
        })

    fn log_filter_performance(inout self, stats: Dict[String, Any]):
        """Log current filter statistics and update monitoring"""
        # Extract statistics
        let rejection_rate = float(stats.get("rejection_rate", 0.0))
        let total_processed = int(stats.get("total_processed", 0))
        let total_rejected = int(stats.get("total_rejected", 0))

        # Update counters
        self.total_signals_processed += total_processed
        self.total_signals_rejected += total_rejected

        # Update rejection rate history
        self._add_to_history(rejection_rate)

        # Extract detailed rejection counts if available
        if "instant_rejections" in stats:
            self.instant_filter_rejections += int(stats["instant_rejections"])
        if "aggressive_rejections" in stats:
            self.aggressive_filter_rejections += int(stats["aggressive_rejections"])
        if "micro_rejections" in stats:
            self.micro_filter_rejections += int(stats["micro_rejections"])
        if "cooldown_rejections" in stats:
            self.cooldown_rejections += int(stats["cooldown_rejections"])
        if "volume_quality_rejections" in stats:
            self.volume_quality_rejections += int(stats["volume_quality_rejections"])

        # Print formatted performance stats
        print("🛡️  Filter Performance: {:.1f}% rejection rate ({} signals processed)"\
            .format(rejection_rate, total_processed))

        # Log to structured logger
        self.logger.info("filter_performance", {
            "rejection_rate": rejection_rate,
            "total_processed": total_processed,
            "total_rejected": total_rejected,
            "session_total_processed": self.total_signals_processed,
            "session_total_rejected": self.total_signals_rejected
        })

        # Check filter health
        self.check_filter_health(rejection_rate)

        # Check for spam spikes
        self.alert_on_spam_spike(rejection_rate)

    fn _add_to_history(inout self, rejection_rate: Float):
        """Add rejection rate to history with size limit"""
        self.rejection_rate_history.append(rejection_rate)

        # Maintain history size limit
        while len(self.rejection_rate_history) > self.history_size:
            self.rejection_rate_history.pop(0)

    fn check_filter_health(inout self, rejection_rate: Float):
        """Validate filter health and alert if needed"""
        if rejection_rate < self.min_healthy_rejection:
            # Filter too lenient
            let message = "⚠️  WARNING: Filter rejection rate below {:.1f}% - check for spam!"\
                .format(self.min_healthy_rejection)
            print(message)
            self.logger.warning("filter_too_lenient", {
                "rejection_rate": rejection_rate,
                "threshold": self.min_healthy_rejection
            })

        elif rejection_rate > self.max_healthy_rejection:
            # Filter too aggressive
            let message = "⚠️  WARNING: Filter rejection rate above {:.1f}% - may be too aggressive!"\
                .format(self.max_healthy_rejection)
            print(message)
            self.logger.warning("filter_too_aggressive", {
                "rejection_rate": rejection_rate,
                "threshold": self.max_healthy_rejection
            })

        else:
            # Healthy range
            let message = "✅ Filter health: {:.1f}% rejection rate (optimal)".format(rejection_rate)
            print(message)
            self.logger.info("filter_healthy", {"rejection_rate": rejection_rate})

    fn alert_on_spam_spike(inout self, current_rate: Float):
        """Detect and alert on spam spikes"""
        if len(self.rejection_rate_history) < 10:
            return  # Not enough data for comparison

        let average_rate = self.calculate_average_rejection_rate()
        let spike_threshold = average_rate * self.spam_spike_multiplier

        if current_rate > spike_threshold:
            let current_time = time()

            # Check alert cooldown
            if current_time - self.last_alert_time >= self.alert_cooldown:
                let message = "🚨 SPAM SPIKE DETECTED: {:.1f}% vs average {:.1f}%"\
                    .format(current_rate, average_rate)
                print(message)
                self.logger.error("spam_spike", {
                    "current_rate": current_rate,
                    "average_rate": average_rate,
                    "spike_multiplier": self.spam_spike_multiplier
                })

                self.last_alert_time = current_time

    fn calculate_average_rejection_rate(self) -> Float:
        """Calculate average rejection rate from history"""
        if len(self.rejection_rate_history) == 0:
            return 0.0

        let total = 0.0
        for rate in self.rejection_rate_history:
            total += rate

        return total / Float(len(self.rejection_rate_history))

    fn get_filter_statistics(self) -> Dict[String, Float]:
        """Return comprehensive filter statistics"""
        let current_rate = 0.0
        if len(self.rejection_rate_history) > 0:
            current_rate = self.rejection_rate_history[-1]

        let average_rate = self.calculate_average_rejection_rate()

        # Calculate min/max from history
        let min_rate = current_rate
        let max_rate = current_rate
        for rate in self.rejection_rate_history:
            if rate < min_rate:
                min_rate = rate
            if rate > max_rate:
                max_rate = rate

        # Determine health status
        let health_status = 1.0  # Healthy
        if current_rate < self.min_healthy_rejection or current_rate > self.max_healthy_rejection:
            health_status = 0.0  # Unhealthy

        return {
            "current_rejection_rate": current_rate,
            "average_rejection_rate": average_rate,
            "min_rejection_rate": min_rate,
            "max_rejection_rate": max_rate,
            "health_status": health_status,
            "total_signals_processed": Float(self.total_signals_processed),
            "total_signals_rejected": Float(self.total_signals_rejected),
            "session_duration_seconds": time() - self.session_start_time,
            "instant_filter_rejections": Float(self.instant_filter_rejections),
            "aggressive_filter_rejections": Float(self.aggressive_filter_rejections),
            "micro_filter_rejections": Float(self.micro_filter_rejections),
            "cooldown_rejections": Float(self.cooldown_rejections),
            "volume_quality_rejections": Float(self.volume_quality_rejections)
        }

    fn print_hourly_summary(self):
        """Print detailed hourly summary of filter performance"""
        let stats = self.get_filter_statistics()
        let session_duration = stats["session_duration_seconds"]
        let hours = session_duration / 3600.0

        print("")
        print("📊 FILTER PERFORMANCE SUMMARY (Session: {:.1f} hours)".format(hours))
        print("=" * 65)
        print("Rejection Rates:")
        print("   Current:    {:.1f}%".format(stats["current_rejection_rate"]))
        print("   Average:    {:.1f}%".format(stats["average_rejection_rate"]))
        print("   Min/Max:    {:.1f}% / {:.1f}%".format(stats["min_rejection_rate"], stats["max_rejection_rate"]))
        print("")
        print("Signal Processing:")
        print("   Total Processed: {:,}".format(int(stats["total_signals_processed"])))
        print("   Total Rejected:  {:,}".format(int(stats["total_signals_rejected"])))
        print("   Overall Rate:    {:.1f}%".format(
            (stats["total_signals_rejected"] / stats["total_signals_processed"]) * 100.0 \
            if stats["total_signals_processed"] > 0 else 0.0
        ))
        print("")
        print("Rejection Breakdown:")
        print("   Instant Filter:    {:,}".format(int(stats["instant_filter_rejections"])))
        print("   Aggressive Filter: {:,}".format(int(stats["aggressive_filter_rejections"])))
        print("   Micro Filter:      {:,}".format(int(stats["micro_filter_rejections"])))
        print("   Cooldown:          {:,}".format(int(stats["cooldown_rejections"])))
        print("   Volume Quality:    {:,}".format(int(stats["volume_quality_rejections"])))
        print("")

        # Health status
        if stats["health_status"] == 1.0:
            print("Health Status: ✅ HEALTHY")
        else:
            print("Health Status: ⚠️  WARNING - Check filter parameters")
        print("=" * 65)

        # Log summary
        self.logger.info("hourly_summary", stats)

    fn export_metrics_for_prometheus(self) -> String:
        """Export metrics in Prometheus format"""
        let stats = self.get_filter_statistics()
        let environment = getenv("APP_ENV", "development")

        let metrics = [] # List[String]

        # Rejection rate metrics
        metrics.append("# HELP filter_rejection_rate Current filter rejection rate")
        metrics.append("# TYPE filter_rejection_rate gauge")
        metrics.append('filter_rejection_rate{{environment="{}"}} {:.2f}'\
            .format(environment, stats["current_rejection_rate"]))

        # Average rejection rate
        metrics.append("# HELP filter_rejection_rate_average Average filter rejection rate")
        metrics.append("# TYPE filter_rejection_rate_average gauge")
        metrics.append('filter_rejection_rate_average{{environment="{}"}} {:.2f}'\
            .format(environment, stats["average_rejection_rate"]))

        # Signals processed
        metrics.append("# HELP filter_signals_processed Total signals processed")
        metrics.append("# TYPE filter_signals_processed counter")
        metrics.append('filter_signals_processed{{environment="{}"}} {:.0f}'\
            .format(environment, stats["total_signals_processed"]))

        # Signals rejected
        metrics.append("# HELP filter_signals_rejected Total signals rejected")
        metrics.append("# TYPE filter_signals_rejected counter")
        metrics.append('filter_signals_rejected{{environment="{}"}} {:.0f}'\
            .format(environment, stats["total_signals_rejected"]))

        # Health status
        metrics.append("# HELP filter_health_status Filter health status (1=healthy, 0=unhealthy)")
        metrics.append("# TYPE filter_health_status gauge")
        metrics.append('filter_health_status{{environment="{}"}} {:.0f}'\
            .format(environment, stats["health_status"]))

        # Rejection breakdown
        metrics.append("# HELP filter_instant_rejections Total instant filter rejections")
        metrics.append("# TYPE filter_instant_rejections counter")
        metrics.append('filter_instant_rejections{{environment="{}"}} {:.0f}'\
            .format(environment, stats["instant_filter_rejections"]))

        metrics.append("# HELP filter_aggressive_rejections Total aggressive filter rejections")
        metrics.append("# TYPE filter_aggressive_rejections counter")
        metrics.append('filter_aggressive_rejections{{environment="{}"}} {:.0f}'\
            .format(environment, stats["aggressive_filter_rejections"]))

        metrics.append("# HELP filter_micro_rejections Total micro filter rejections")
        metrics.append("# TYPE filter_micro_rejections counter")
        metrics.append('filter_micro_rejections{{environment="{}"}} {:.0f}'\
            .format(environment, stats["micro_filter_rejections"]))

        return "\n".join(metrics)

    fn reset_counters(inout self):
        """Reset session counters (useful for testing or daily reset)"""
        self.total_signals_processed = 0
        self.total_signals_rejected = 0
        self.session_start_time = time()
        self.instant_filter_rejections = 0
        self.aggressive_filter_rejections = 0
        self.micro_filter_rejections = 0
        self.cooldown_rejections = 0
        self.volume_quality_rejections = 0
        self.rejection_rate_history.clear()

        self.logger.info("FilterMonitor counters reset")

# Global filter monitor instance
var _filter_monitor: FilterMonitor? = None

def get_filter_monitor() -> FilterMonitor:
    """Get or create the global filter monitor instance"""
    global _filter_monitor
    if _filter_monitor is None:
        _filter_monitor = FilterMonitor()
    return _filter_monitor.value()

def log_filter_performance(stats: Dict[String, Any]):
    """Log filter performance using the global monitor"""
    monitor = get_filter_monitor()
    monitor.log_filter_performance(stats)

def print_hourly_summary():
    """Print hourly summary using the global monitor"""
    monitor = get_filter_monitor()
    monitor.print_hourly_summary()

def export_prometheus_metrics() -> String:
    """Export Prometheus metrics using the global monitor"""
    monitor = get_filter_monitor()
    return monitor.export_metrics_for_prometheus()