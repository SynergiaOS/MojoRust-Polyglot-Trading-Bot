#!/usr/bin/env python3
"""
SandwichManager - Multi-Token Arbitrage Orchestration and Metrics System

This module provides comprehensive orchestration and monitoring capabilities
for the multi-token arbitrage system. It handles performance tracking, alert
generation, real-time metrics collection, and coordinates arbitrage execution
across Rust FFI backend and Mojo execution layer.

Features:
- Multi-token arbitrage orchestration
- Real-time metrics and monitoring
- Prometheus integration
- Rust FFI coordination
- Cross-system health monitoring
- Performance analytics and alerting
"""

import time
import logging
import asyncio
import json
import threading
import uuid
from typing import Dict, Any, List, Optional, Tuple, Callable
from dataclasses import dataclass, asdict, field
from datetime import datetime, timedelta
from collections import defaultdict, deque
from enum import Enum

# Prometheus metrics library
try:
    from prometheus_client import Counter, Histogram, Gauge, CollectorRegistry, generate_latest, CONTENT_TYPE_LATEST
    from prometheus_client.exposition import MetricsHandler
    from aiohttp import web
    PROMETHEUS_AVAILABLE = True
except ImportError:
    PROMETHEUS_AVAILABLE = False
    logging.warning("Prometheus client not available. Using mock metrics.")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@dataclass
class BacktestMetrics:
    """Individual backtest session metrics"""
    session_id: str
    token_address: str
    token_name: str
    token_symbol: str
    start_time: datetime
    end_time: Optional[datetime] = None
    status: str = "running"  # running, completed, failed

    # Performance metrics
    final_score: float = 0.0
    recommendation: str = ""
    simulated_profit_loss: float = 0.0
    max_drawdown: float = 0.0
    trade_count: int = 0
    win_rate: float = 0.0
    execution_time_ms: float = 0.0

    # Filter results
    honeypot_score: float = 0.0
    liquidity_score: float = 0.0
    security_score: float = 0.0
    social_score: float = 0.0
    volatility_score: float = 0.0

    # System metrics
    api_calls_count: int = 0
    cache_hits: int = 0
    cache_misses: int = 0
    errors_count: int = 0

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        # Convert datetime objects to ISO strings
        if self.start_time:
            data['start_time'] = self.start_time.isoformat()
        if self.end_time:
            data['end_time'] = self.end_time.isoformat()
        return data


@dataclass
class AggregatedMetrics:
    """Aggregated metrics across all backtest sessions"""
    total_sessions: int = 0
    successful_sessions: int = 0
    failed_sessions: int = 0
    running_sessions: int = 0

    total_profit_loss: float = 0.0
    avg_profit_loss: float = 0.0
    max_profit_loss: float = float('-inf')
    min_profit_loss: float = float('inf')

    avg_score: float = 0.0
    avg_execution_time_ms: float = 0.0

    # Recommendation distribution
    strong_buy_count: int = 0
    buy_count: int = 0
    hold_count: int = 0
    avoid_count: int = 0

    # Performance percentiles
    profit_75th_percentile: float = 0.0
    profit_90th_percentile: float = 0.0

    last_updated: datetime = None

    def __post_init__(self):
        if self.last_updated is None:
            self.last_updated = datetime.now()


# Arbitrage Orchestration Components

class ArbitrageType(Enum):
    """Arbitrage opportunity types"""
    TRIANGULAR = "triangular"
    CROSS_EXCHANGE = "cross_exchange"
    FLASH_LOAN = "flash_loan"
    STATISTICAL = "statistical"


class ArbitrageStatus(Enum):
    """Arbitrage execution status"""
    DETECTED = "detected"
    VALIDATING = "validating"
    QUEUED = "queued"
    EXECUTING = "executing"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


@dataclass
class ArbitrageOpportunity:
    """Arbitrage opportunity detected by the system"""
    id: str
    arbitrage_type: ArbitrageType
    input_token: str
    output_token: str
    input_amount: float
    expected_output: float
    profit_estimate: float
    confidence_score: float
    urgency_score: float
    dex_name: str
    detected_at: datetime
    expires_at: datetime
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        data['arbitrage_type'] = self.arbitrage_type.value
        data['detected_at'] = self.detected_at.isoformat()
        data['expires_at'] = self.expires_at.isoformat()
        return data


@dataclass
class ArbitrageExecution:
    """Arbitrage execution tracking"""
    id: str
    opportunity_id: str
    arbitrage_type: ArbitrageType
    status: ArbitrageStatus
    started_at: datetime
    completed_at: Optional[datetime] = None
    execution_engine: str = "unknown"  # rust_ffi, mojocore, simulation
    provider_used: Optional[str] = None
    input_amount: float = 0.0
    actual_output: float = 0.0
    profit_realized: float = 0.0
    gas_cost_usd: float = 0.0
    priority_fee_sol: float = 0.0
    tip_amount_sol: float = 0.0
    execution_time_ms: float = 0.0
    transaction_hash: Optional[str] = None
    bundle_hash: Optional[str] = None
    error_message: Optional[str] = None
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        data['arbitrage_type'] = self.arbitrage_type.value
        data['status'] = self.status.value
        data['started_at'] = self.started_at.isoformat()
        if self.completed_at:
            data['completed_at'] = self.completed_at.isoformat()
        return data


@dataclass
class ArbitrageMetrics:
    """Arbitrage-specific metrics"""
    total_opportunities: int = 0
    executed_opportunities: int = 0
    successful_executions: int = 0
    failed_executions: int = 0

    # By type
    triangular_detected: int = 0
    triangular_executed: int = 0
    cross_exchange_detected: int = 0
    cross_exchange_executed: int = 0
    flash_loan_detected: int = 0
    flash_loan_executed: int = 0

    # Performance
    total_profit_usd: float = 0.0
    total_gas_cost_usd: float = 0.0
    avg_execution_time_ms: float = 0.0
    avg_profit_usd: float = 0.0

    # Provider stats
    rust_ffi_executions: int = 0
    rust_ffi_success_rate: float = 0.0
    mojocore_executions: int = 0
    mojocore_success_rate: float = 0.0

    last_updated: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        data = asdict(self)
        data['last_updated'] = self.last_updated.isoformat()
        return data


class MockPrometheusMetrics:
    """Mock Prometheus metrics when prometheus_client is not available"""

    def __init__(self):
        self.counters = defaultdict(int)
        self.gauges = defaultdict(float)
        self.histograms = defaultdict(list)

    def inc(self, name: str, labels: Dict[str, str] = None, value: float = 1):
        """Increment counter"""
        key = self._make_key(name, labels)
        self.counters[key] += value

    def set(self, name: str, labels: Dict[str, str] = None, value: float = 0):
        """Set gauge value"""
        key = self._make_key(name, labels)
        self.gauges[key] = value

    def observe(self, name: str, labels: Dict[str, str] = None, value: float = 0):
        """Observe histogram value"""
        key = self._make_key(name, labels)
        self.histograms[key].append(value)
        # Keep only last 1000 observations per key
        if len(self.histograms[key]) > 1000:
            self.histograms[key] = self.histograms[key][-1000:]

    def _make_key(self, name: str, labels: Dict[str, str] = None) -> str:
        """Create key from name and labels"""
        if not labels:
            return name
        label_str = ",".join(f"{k}={v}" for k, v in sorted(labels.items()))
        return f"{name}[{label_str}]"

    def generate_latest(self) -> str:
        """Generate text format metrics"""
        output = []

        # Output counters
        for key, value in self.counters.items():
            output.append(f"# TYPE {key} counter")
            output.append(f"{key} {value}")

        # Output gauges
        for key, value in self.gauges.items():
            output.append(f"# TYPE {key} gauge")
            output.append(f"{key} {value}")

        # Output histograms
        for key, values in self.histograms.items():
            if values:
                output.append(f"# TYPE {key} histogram")
                count = len(values)
                total = sum(values)
                avg = total / count if count > 0 else 0
                output.append(f"{key}_count {count}")
                output.append(f"{key}_sum {total}")
                output.append(f"{key}_avg {avg}")

        return "\n".join(output) + "\n"


class SandwichManager:
    """
    SandwichManager - Multi-Token Arbitrage Orchestration and Metrics System

    Handles collection, aggregation, orchestration, and export of arbitrage metrics
    with Prometheus integration, real-time monitoring, and cross-system coordination.
    """

    def __init__(self, metrics_port: int = 8001, enable_prometheus: bool = True,
                 enable_arbitrage_orchestration: bool = True):
        """
        Initialize SandwichManager

        Args:
            metrics_port: Port for Prometheus metrics endpoint
            enable_prometheus: Whether to enable Prometheus metrics export
            enable_arbitrage_orchestration: Whether to enable arbitrage orchestration
        """
        self.metrics_port = metrics_port
        self.enable_prometheus = enable_prometheus and PROMETHEUS_AVAILABLE
        self.enable_arbitrage_orchestration = enable_arbitrage_orchestration

        # Session tracking (backtest compatibility)
        self.active_sessions: Dict[str, BacktestMetrics] = {}
        self.completed_sessions: List[BacktestMetrics] = []
        self.max_completed_sessions = 1000  # Keep last 1000 completed sessions

        # Aggregated metrics
        self.aggregated_metrics = AggregatedMetrics()

        # Arbitrage orchestration components
        self.active_opportunities: Dict[str, ArbitrageOpportunity] = {}
        self.opportunity_queue: asyncio.Queue = asyncio.Queue(maxsize=1000)
        self.active_executions: Dict[str, ArbitrageExecution] = {}
        self.completed_executions: List[ArbitrageExecution] = []
        self.max_completed_executions = 5000  # Keep last 5000 executions

        # Arbitrage metrics
        self.arbitrage_metrics = ArbitrageMetrics()

        # Execution engine callbacks
        self.rust_ffi_executor: Optional[Callable] = None
        self.mojocore_executor: Optional[Callable] = None
        self.opportunity_detectors: List[Callable] = []

        # Prometheus metrics
        self.registry = CollectorRegistry() if self.enable_prometheus else None
        self.prometheus_metrics = self._setup_prometheus_metrics() if self.enable_prometheus else MockPrometheusMetrics()

        # Rate limiting and performance tracking
        self.request_timestamps = deque(maxlen=1000)  # Last 1000 requests
        self.performance_history = deque(maxlen=100)    # Last 100 execution times

        # Alert thresholds
        self.alert_thresholds = {
            'error_rate': 0.1,           # 10% error rate
            'avg_execution_time': 5000,   # 5 seconds
            'memory_usage': 0.8,          # 80% memory usage
            'disk_usage': 0.9,            # 90% disk usage
            'cache_hit_rate': 0.5,        # 50% cache hit rate
            'arbitrage_success_rate': 0.7, # 70% arbitrage success rate
            'opportunity_age_minutes': 5,   # 5 minutes max opportunity age
        }

        # Orchestration configuration
        self.max_concurrent_arbitrage = 3
        self.opportunity_timeout_seconds = 30
        self.execution_timeout_seconds = 60

        # Web server for metrics endpoint
        self.app = None
        self.runner = None
        self.site = None

        # Background tasks
        self.orchestration_task: Optional[asyncio.Task] = None
        self.cleanup_task: Optional[asyncio.Task] = None

        # Lock for thread safety
        self.metrics_lock = threading.RLock()

        self.logger = logging.getLogger(__name__)
        self.logger.info(f"SandwichManager initialized (Prometheus: {self.enable_prometheus}, Arbitrage: {self.enable_arbitrage_orchestration})")

    def _setup_prometheus_metrics(self):
        """Setup Prometheus metrics collectors"""
        if not self.enable_prometheus:
            return MockPrometheusMetrics()

        try:
            # Session metrics
            sessions_total = Counter(
                'backtest_sessions_total',
                'Total number of backtest sessions',
                ['status'],
                registry=self.registry
            )

            session_duration = Histogram(
                'backtest_session_duration_seconds',
                'Duration of backtest sessions',
                registry=self.registry
            )

            # Performance metrics
            execution_time = Histogram(
                'backtest_execution_time_ms',
                'Backtest execution time in milliseconds',
                buckets=[100, 500, 1000, 2000, 5000, 10000, 30000],
                registry=self.registry
            )

            profit_loss = Histogram(
                'backtest_profit_loss_usd',
                'Backtest profit/loss in USD',
                buckets=[-1000, -500, -100, -50, 0, 50, 100, 500, 1000, 5000],
                registry=self.registry
            )

            # Score metrics
            score = Histogram(
                'backtest_final_score',
                'Final backtest score',
                buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
                registry=self.registry
            )

            # Filter metrics
            filter_score = Histogram(
                'backtest_filter_score',
                'Individual filter check scores',
                ['filter_name'],
                buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
                registry=self.registry
            )

            # System metrics
            api_requests = Counter(
                'api_requests_total',
                'Total API requests made',
                ['api_type', 'status'],
                registry=self.registry
            )

            cache_operations = Counter(
                'cache_operations_total',
                'Total cache operations',
                ['operation'],
                registry=self.registry
            )

            errors = Counter(
                'backtest_errors_total',
                'Total backtest errors',
                ['error_type'],
                registry=self.registry
            )

            # Active sessions gauge
            active_sessions_gauge = Gauge(
                'backtest_active_sessions',
                'Number of currently active backtest sessions',
                registry=self.registry
            )

            # Queue metrics
            queue_size = Gauge(
                'backtest_queue_size',
                'Current queue size for pending backtests',
                registry=self.registry
            )

            return {
                'sessions_total': sessions_total,
                'session_duration': session_duration,
                'execution_time': execution_time,
                'profit_loss': profit_loss,
                'score': score,
                'filter_score': filter_score,
                'api_requests': api_requests,
                'cache_operations': cache_operations,
                'errors': errors,
                'active_sessions': active_sessions_gauge,
                'queue_size': queue_size
            }

        except Exception as e:
            self.logger.error(f"Failed to setup Prometheus metrics: {e}")
            return MockPrometheusMetrics()

    async def start_metrics_server(self):
        """Start the Prometheus metrics HTTP server and arbitrage orchestration"""
        if not self.enable_prometheus:
            self.logger.info("Prometheus server disabled")
            return

        try:
            from aiohttp import web

            # Create web application
            self.app = web.Application()

            # Add metrics endpoint
            self.app.router.add_get('/metrics', self._metrics_handler)

            # Add health check endpoint
            self.app.router.add_get('/health', self._health_handler)

            # Add detailed metrics endpoint
            self.app.router.add_get('/metrics/detailed', self._detailed_metrics_handler)

            # Add arbitrage endpoints
            if self.enable_arbitrage_orchestration:
                self.app.router.add_get('/arbitrage/opportunities', self._arbitrage_opportunities_handler)
                self.app.router.add_get('/arbitrage/executions', self._arbitrage_executions_handler)
                self.app.router.add_post('/arbitrage/opportunity', self._submit_opportunity_handler)
                self.app.router.add_get('/arbitrage/metrics', self._arbitrage_metrics_handler)

            # Start server
            self.runner = web.AppRunner(self.app)
            await self.runner.setup()

            self.site = web.TCPSite(self.runner, '0.0.0.0', self.metrics_port)
            await self.site.start()

            # Start arbitrage orchestration
            if self.enable_arbitrage_orchestration:
                await self._start_arbitrage_orchestration()

            self.logger.info(f"SandwichManager server started on port {self.metrics_port}")

        except Exception as e:
            self.logger.error(f"Failed to start SandwichManager server: {e}")
            self.enable_prometheus = False

    async def _start_arbitrage_orchestration(self):
        """Start arbitrage orchestration background tasks"""
        self.logger.info("Starting arbitrage orchestration...")

        # Start opportunity processing task
        self.orchestration_task = asyncio.create_task(self._orchestrate_arbitrage())

        # Start cleanup task
        self.cleanup_task = asyncio.create_task(self._cleanup_expired_opportunities())

        self.logger.info("Arbitrage orchestration started")

    # Arbitrage Orchestration Methods

    def register_rust_ffi_executor(self, executor: Callable):
        """Register Rust FFI arbitrage executor"""
        self.rust_ffi_executor = executor
        self.logger.info("Rust FFI executor registered")

    def register_mojocore_executor(self, executor: Callable):
        """Register MojoCore arbitrage executor"""
        self.mojocore_executor = executor
        self.logger.info("MojoCore executor registered")

    def register_opportunity_detector(self, detector: Callable):
        """Register opportunity detector callback"""
        self.opportunity_detectors.append(detector)
        self.logger.info(f"Opportunity detector registered (total: {len(self.opportunity_detectors)})")

    async def submit_arbitrage_opportunity(self, opportunity: ArbitrageOpportunity) -> bool:
        """
        Submit a new arbitrage opportunity for execution

        Args:
            opportunity: Arbitrage opportunity to execute

        Returns:
            True if successfully queued, False otherwise
        """
        try:
            # Check if opportunity already exists
            if opportunity.id in self.active_opportunities:
                self.logger.warning(f"Opportunity {opportunity.id} already active")
                return False

            # Check opportunity validity
            if not self._validate_opportunity(opportunity):
                self.logger.warning(f"Invalid opportunity {opportunity.id}")
                return False

            # Add to active opportunities
            with self.metrics_lock:
                self.active_opportunities[opportunity.id] = opportunity
                self.arbitrage_metrics.total_opportunities += 1

                # Update type-specific metrics
                if opportunity.arbitrage_type == ArbitrageType.TRIANGULAR:
                    self.arbitrage_metrics.triangular_detected += 1
                elif opportunity.arbitrage_type == ArbitrageType.CROSS_EXCHANGE:
                    self.arbitrage_metrics.cross_exchange_detected += 1
                elif opportunity.arbitrage_type == ArbitrageType.FLASH_LOAN:
                    self.arbitrage_metrics.flash_loan_detected += 1

            # Queue for execution
            await self.opportunity_queue.put(opportunity.id)

            # Update Prometheus metrics
            if self.enable_prometheus:
                self.prometheus_metrics['arbitrage_opportunities_total'].labels(
                    type=opportunity.arbitrage_type.value
                ).inc()
            else:
                self.prometheus_metrics.inc('arbitrage_opportunities_total',
                                         {'type': opportunity.arbitrage_type.value})

            self.logger.info(f"Submitted arbitrage opportunity: {opportunity.id} ({opportunity.arbitrage_type.value})")
            return True

        except Exception as e:
            self.logger.error(f"Failed to submit opportunity {opportunity.id}: {e}")
            return False

    async def _orchestrate_arbitrage(self):
        """Main arbitrage orchestration loop"""
        self.logger.info("Starting arbitrage orchestration loop")

        while True:
            try:
                # Get next opportunity from queue
                opportunity_id = await asyncio.wait_for(
                    self.opportunity_queue.get(),
                    timeout=1.0
                )

                # Check concurrent execution limit
                if len(self.active_executions) >= self.max_concurrent_arbitrage:
                    # Re-queue opportunity
                    await self.opportunity_queue.put(opportunity_id)
                    await asyncio.sleep(0.1)
                    continue

                # Get opportunity details
                with self.metrics_lock:
                    if opportunity_id not in self.active_opportunities:
                        continue  # Opportunity may have expired

                    opportunity = self.active_opportunities[opportunity_id]

                # Start execution
                asyncio.create_task(self._execute_arbitrage_opportunity(opportunity))

            except asyncio.TimeoutError:
                # No opportunities, continue loop
                continue
            except Exception as e:
                self.logger.error(f"Error in arbitrage orchestration loop: {e}")
                await asyncio.sleep(1.0)

    async def _execute_arbitrage_opportunity(self, opportunity: ArbitrageOpportunity):
        """Execute a single arbitrage opportunity"""
        execution_id = str(uuid.uuid4())
        start_time = datetime.now()

        # Create execution record
        execution = ArbitrageExecution(
            id=execution_id,
            opportunity_id=opportunity.id,
            arbitrage_type=opportunity.arbitrage_type,
            status=ArbitrageStatus.EXECUTING,
            started_at=start_time,
            input_amount=opportunity.input_amount
        )

        try:
            with self.metrics_lock:
                self.active_executions[execution_id] = execution
                self.arbitrage_metrics.executed_opportunities += 1

                # Update type-specific metrics
                if opportunity.arbitrage_type == ArbitrageType.TRIANGULAR:
                    self.arbitrage_metrics.triangular_executed += 1
                elif opportunity.arbitrage_type == ArbitrageType.CROSS_EXCHANGE:
                    self.arbitrage_metrics.cross_exchange_executed += 1
                elif opportunity.arbitrage_type == ArbitrageType.FLASH_LOAN:
                    self.arbitrage_metrics.flash_loan_executed += 1

            # Choose execution engine
            executor = self._choose_execution_engine(opportunity)
            execution.execution_engine = executor

            # Execute opportunity
            if executor == "rust_ffi" and self.rust_ffi_executor:
                result = await self._execute_with_rust_ffi(opportunity, execution)
            elif executor == "mojocore" and self.mojocore_executor:
                result = await self._execute_with_mojocore(opportunity, execution)
            else:
                result = await self._execute_with_simulation(opportunity, execution)

            # Update execution with results
            if result:
                execution.status = ArbitrageStatus.COMPLETED
                execution.completed_at = datetime.now()
                execution.execution_time_ms = (execution.completed_at - start_time).total_seconds() * 1000
                execution.actual_output = result.get('actual_output', 0.0)
                execution.profit_realized = result.get('profit_realized', 0.0)
                execution.gas_cost_usd = result.get('gas_cost_usd', 0.0)
                execution.priority_fee_sol = result.get('priority_fee_sol', 0.0)
                execution.tip_amount_sol = result.get('tip_amount_sol', 0.0)
                execution.transaction_hash = result.get('transaction_hash')
                execution.bundle_hash = result.get('bundle_hash')
                execution.provider_used = result.get('provider_used')

                # Update metrics
                with self.metrics_lock:
                    self.arbitrage_metrics.successful_executions += 1
                    self.arbitrage_metrics.total_profit_usd += execution.profit_realized
                    self.arbitrage_metrics.total_gas_cost_usd += execution.gas_cost_usd

                    # Update provider-specific metrics
                    if executor == "rust_ffi":
                        self.arbitrage_metrics.rust_ffi_executions += 1
                    elif executor == "mojocore":
                        self.arbitrage_metrics.mojocore_executions += 1

                self.logger.info(f"Arbitrage executed successfully: {execution_id} "
                               f"(profit: ${execution.profit_realized:.2f}, engine: {executor})")

            else:
                execution.status = ArbitrageStatus.FAILED
                execution.completed_at = datetime.now()
                execution.error_message = "Execution failed"

                with self.metrics_lock:
                    self.arbitrage_metrics.failed_executions += 1

                self.logger.error(f"Arbitrage execution failed: {execution_id}")

        except Exception as e:
            execution.status = ArbitrageStatus.FAILED
            execution.completed_at = datetime.now()
            execution.error_message = str(e)

            with self.metrics_lock:
                self.arbitrage_metrics.failed_executions += 1

            self.logger.error(f"Arbitrage execution error: {execution_id} - {e}")

        finally:
            # Move execution to completed
            with self.metrics_lock:
                if execution_id in self.active_executions:
                    del self.active_executions[execution_id]

                self.completed_executions.append(execution)
                if len(self.completed_executions) > self.max_completed_executions:
                    self.completed_executions = self.completed_executions[-self.max_completed_executions:]

                # Remove opportunity from active
                if opportunity.id in self.active_opportunities:
                    del self.active_opportunities[opportunity.id]

            # Update Prometheus metrics
            if self.enable_prometheus:
                self.prometheus_metrics['arbitrage_executions_total'].labels(
                    type=opportunity.arbitrage_type.value,
                    status=execution.status.value,
                    engine=execution.execution_engine
                ).inc()
                self.prometheus_metrics['arbitrage_execution_time_ms'].observe(execution.execution_time_ms)
                if execution.profit_realized > 0:
                    self.prometheus_metrics['arbitrage_profit_usd'].observe(execution.profit_realized)
            else:
                self.prometheus_metrics.inc('arbitrage_executions_total',
                                         {'type': opportunity.arbitrage_type.value,
                                          'status': execution.status.value,
                                          'engine': execution.execution_engine})
                self.prometheus_metrics.observe('arbitrage_execution_time_ms', execution.execution_time_ms)
                if execution.profit_realized > 0:
                    self.prometheus_metrics.observe('arbitrage_profit_usd', execution.profit_realized)

            # Update aggregated metrics
            self._update_arbitrage_aggregated_metrics()

    async def _cleanup_expired_opportunities(self):
        """Clean up expired opportunities"""
        while True:
            try:
                await asyncio.sleep(30)  # Check every 30 seconds

                current_time = datetime.now()
                expired_opportunities = []

                with self.metrics_lock:
                    for opp_id, opportunity in self.active_opportunities.items():
                        if current_time > opportunity.expires_at:
                            expired_opportunities.append(opp_id)

                    # Remove expired opportunities
                    for opp_id in expired_opportunities:
                        del self.active_opportunities[opp_id]
                        self.logger.info(f"Removed expired opportunity: {opp_id}")

                if expired_opportunities:
                    if self.enable_prometheus:
                        self.prometheus_metrics['arbitrage_opportunities_expired_total'].inc(len(expired_opportunities))
                    else:
                        self.prometheus_metrics.inc('arbitrage_opportunities_expired_total', value=len(expired_opportunities))

            except Exception as e:
                self.logger.error(f"Error in cleanup task: {e}")
                await asyncio.sleep(60)  # Wait longer on error

    def _validate_opportunity(self, opportunity: ArbitrageOpportunity) -> bool:
        """Validate arbitrage opportunity"""
        current_time = datetime.now()

        # Check expiration
        if current_time > opportunity.expires_at:
            return False

        # Check minimum profit
        if opportunity.profit_estimate <= 0:
            return False

        # Check confidence
        if opportunity.confidence_score < 0.1:
            return False

        # Check amounts
        if opportunity.input_amount <= 0 or opportunity.expected_output <= 0:
            return False

        return True

    def _choose_execution_engine(self, opportunity: ArbitrageOpportunity) -> str:
        """Choose optimal execution engine for opportunity"""
        # Prioritize Rust FFI for high-profit, high-urgency opportunities
        if (self.rust_ffi_executor and
            opportunity.profit_estimate > 10.0 and
            opportunity.urgency_score > 0.7):
            return "rust_ffi"

        # Use MojoCore for triangular arbitrage
        if (self.mojocore_executor and
            opportunity.arbitrage_type == ArbitrageType.TRIANGULAR):
            return "mojocore"

        # Default to simulation
        return "simulation"

    async def _execute_with_rust_ffi(self, opportunity: ArbitrageOpportunity,
                                   execution: ArbitrageExecution) -> Optional[Dict[str, Any]]:
        """Execute using Rust FFI backend"""
        try:
            if not self.rust_ffi_executor:
                return None

            # Convert opportunity to Rust format
            rust_opportunity = {
                'id': opportunity.id,
                'arbitrage_type': opportunity.arbitrage_type.value,
                'input_amount': opportunity.input_amount,
                'output_amount': opportunity.expected_output,
                'profit_amount': opportunity.profit_estimate,
                'max_slippage': 0.05,  # Default 5% slippage
                'urgency_score': opportunity.urgency_score,
                'dex_name': opportunity.dex_name,
                'metadata': opportunity.metadata
            }

            # Execute via Rust FFI
            result = await self.rust_ffi_executor(rust_opportunity)

            return result

        except Exception as e:
            self.logger.error(f"Rust FFI execution failed: {e}")
            return None

    async def _execute_with_mojocore(self, opportunity: ArbitrageOpportunity,
                                   execution: ArbitrageExecution) -> Optional[Dict[str, Any]]:
        """Execute using MojoCore backend"""
        try:
            if not self.mojocore_executor:
                return None

            # Convert opportunity to Mojo format
            mojocore_opportunity = {
                'id': opportunity.id,
                'arbitrage_type': opportunity.arbitrage_type.value,
                'input_amount': opportunity.input_amount,
                'expected_output': opportunity.expected_output,
                'profit_estimate': opportunity.profit_estimate,
                'confidence_score': opportunity.confidence_score,
                'dex_name': opportunity.dex_name,
                'metadata': opportunity.metadata
            }

            # Execute via MojoCore
            result = await self.mojocore_executor(mojocore_opportunity)

            return result

        except Exception as e:
            self.logger.error(f"MojoCore execution failed: {e}")
            return None

    async def _execute_with_simulation(self, opportunity: ArbitrageOpportunity,
                                    execution: ArbitrageExecution) -> Optional[Dict[str, Any]]:
        """Execute using simulation (fallback)"""
        try:
            # Simulate execution time
            await asyncio.sleep(0.1 + (1.0 - opportunity.urgency_score) * 0.5)

            # Simulate success rate based on confidence
            import random
            success = random.random() < opportunity.confidence_score

            if success:
                # Simulate profit with some variance
                profit_variance = (random.random() - 0.5) * 0.2  # ±10% variance
                actual_profit = opportunity.profit_estimate * (1.0 + profit_variance)

                return {
                    'actual_output': opportunity.expected_output,
                    'profit_realized': actual_profit,
                    'gas_cost_usd': 5.0,  # Simulated gas cost
                    'priority_fee_sol': 0.0001,
                    'tip_amount_sol': 0.00005,
                    'transaction_hash': f"sim_{execution.id}",
                    'provider_used': 'simulation'
                }
            else:
                return None

        except Exception as e:
            self.logger.error(f"Simulation execution failed: {e}")
            return None

    def _update_arbitrage_aggregated_metrics(self):
        """Update aggregated arbitrage metrics"""
        if not self.completed_executions:
            return

        with self.metrics_lock:
            # Calculate averages
            successful_executions = [e for e in self.completed_executions if e.status == ArbitrageStatus.COMPLETED]

            if successful_executions:
                total_profit = sum(e.profit_realized for e in successful_executions)
                total_gas = sum(e.gas_cost_usd for e in successful_executions)
                avg_time = sum(e.execution_time_ms for e in successful_executions) / len(successful_executions)

                self.arbitrage_metrics.total_profit_usd = total_profit
                self.arbitrage_metrics.total_gas_cost_usd = total_gas
                self.arbitrage_metrics.avg_execution_time_ms = avg_time
                self.arbitrage_metrics.avg_profit_usd = total_profit / len(successful_executions)

            # Calculate success rates
            if self.arbitrage_metrics.rust_ffi_executions > 0:
                rust_successful = len([e for e in successful_executions if e.execution_engine == "rust_ffi"])
                self.arbitrage_metrics.rust_ffi_success_rate = rust_successful / self.arbitrage_metrics.rust_ffi_executions

            if self.arbitrage_metrics.mojocore_executions > 0:
                mojo_successful = len([e for e in successful_executions if e.execution_engine == "mojocore"])
                self.arbitrage_metrics.mojocore_success_rate = mojo_successful / self.arbitrage_metrics.mojocore_executions

            self.arbitrage_metrics.last_updated = datetime.now()

    # HTTP Handlers for Arbitrage Endpoints

    async def _arbitrage_opportunities_handler(self, request):
        """Handle arbitrage opportunities endpoint"""
        with self.metrics_lock:
            opportunities = [
                opp.to_dict() for opp in self.active_opportunities.values()
            ]

        return web.json_response({
            'active_opportunities': len(opportunities),
            'opportunities': opportunities
        })

    async def _arbitrage_executions_handler(self, request):
        """Handle arbitrage executions endpoint"""
        limit = int(request.query.get('limit', 50))

        with self.metrics_lock:
            active_executions = [
                exec.to_dict() for exec in self.active_executions.values()
            ]

            recent_executions = [
                exec.to_dict() for exec in self.completed_executions[-limit:]
            ]

        return web.json_response({
            'active_executions': len(active_executions),
            'active': active_executions,
            'recent_completed': recent_executions
        })

    async def _submit_opportunity_handler(self, request):
        """Handle opportunity submission endpoint"""
        try:
            data = await request.json()

            # Create opportunity from request data
            opportunity = ArbitrageOpportunity(
                id=data.get('id', str(uuid.uuid4())),
                arbitrage_type=ArbitrageType(data.get('arbitrage_type', 'triangular')),
                input_token=data.get('input_token', ''),
                output_token=data.get('output_token', ''),
                input_amount=float(data.get('input_amount', 0)),
                expected_output=float(data.get('expected_output', 0)),
                profit_estimate=float(data.get('profit_estimate', 0)),
                confidence_score=float(data.get('confidence_score', 0)),
                urgency_score=float(data.get('urgency_score', 0)),
                dex_name=data.get('dex_name', ''),
                detected_at=datetime.now(),
                expires_at=datetime.now() + timedelta(seconds=int(data.get('ttl_seconds', 60))),
                metadata=data.get('metadata', {})
            )

            # Submit opportunity
            success = await self.submit_arbitrage_opportunity(opportunity)

            return web.json_response({
                'success': success,
                'opportunity_id': opportunity.id
            })

        except Exception as e:
            return web.json_response({
                'success': False,
                'error': str(e)
            }, status=400)

    async def _arbitrage_metrics_handler(self, request):
        """Handle arbitrage metrics endpoint"""
        with self.metrics_lock:
            return web.json_response(self.arbitrage_metrics.to_dict())

    async def stop_metrics_server(self):
        """Stop the Prometheus metrics HTTP server"""
        if self.orchestration_task:
            self.orchestration_task.cancel()
            try:
                await self.orchestration_task
            except asyncio.CancelledError:
                pass

        if self.cleanup_task:
            self.cleanup_task.cancel()
            try:
                await self.cleanup_task
            except asyncio.CancelledError:
                pass

        if self.runner:
            await self.runner.cleanup()
            self.logger.info("SandwichManager server stopped")

    async def _metrics_handler(self, request):
        """Handle Prometheus metrics endpoint"""
        if self.enable_prometheus:
            return web.Response(
                body=generate_latest(self.registry),
                content_type=CONTENT_TYPE_LATEST
            )
        else:
            return web.Response(
                body=self.prometheus_metrics.generate_latest(),
                content_type='text/plain'
            )

    async def _health_handler(self, request):
        """Handle health check endpoint"""
        health_status = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'active_sessions': len(self.active_sessions),
            'total_sessions': self.aggregated_metrics.total_sessions,
            'success_rate': (self.aggregated_metrics.successful_sessions /
                           max(1, self.aggregated_metrics.total_sessions))
        }

        # Check alert conditions
        error_rate = self._get_current_error_rate()
        if error_rate > self.alert_thresholds['error_rate']:
            health_status['status'] = 'degraded'
            health_status['issues'] = ['High error rate']

        return web.json_response(health_status)

    async def _detailed_metrics_handler(self, request):
        """Handle detailed metrics endpoint"""
        with self.metrics_lock:
            # Get recent sessions
            recent_sessions = [
                session.to_dict()
                for session in self.completed_sessions[-50:]
            ]

            # Get active sessions
            active_sessions = [
                session.to_dict()
                for session in self.active_sessions.values()
            ]

            detailed_metrics = {
                'timestamp': datetime.now().isoformat(),
                'aggregated': asdict(self.aggregated_metrics),
                'active_sessions': active_sessions,
                'recent_sessions': recent_sessions,
                'performance_stats': self._get_performance_stats()
            }

        return web.json_response(detailed_metrics)

    def start_backtest_session(self, session_id: str, token_address: str,
                             token_name: str = "", token_symbol: str = "") -> BacktestMetrics:
        """
        Start tracking a new backtest session

        Args:
            session_id: Unique session identifier
            token_address: Token mint address
            token_name: Token name
            token_symbol: Token symbol

        Returns:
            BacktestMetrics object for the session
        """
        with self.metrics_lock:
            # Check if session already exists
            if session_id in self.active_sessions:
                self.logger.warning(f"Session {session_id} already exists")
                return self.active_sessions[session_id]

            # Create new session metrics
            session_metrics = BacktestMetrics(
                session_id=session_id,
                token_address=token_address,
                token_name=token_name or f"Token_{token_address[:8]}",
                token_symbol=token_symbol or "UNK",
                start_time=datetime.now()
            )

            # Add to active sessions
            self.active_sessions[session_id] = session_metrics

            # Update Prometheus metrics
            if self.enable_prometheus:
                self.prometheus_metrics['sessions_total'].labels(status='started').inc()
                self.prometheus_metrics['active_sessions'].set(len(self.active_sessions))
            else:
                self.prometheus_metrics.inc('backtest_sessions_total', {'status': 'started'})
                self.prometheus_metrics.set('backtest_active_sessions', len(self.active_sessions))

            self.logger.info(f"Started backtest session: {session_id} for token {token_address}")
            return session_metrics

    def update_session_metrics(self, session_id: str, **kwargs):
        """
        Update metrics for an active backtest session

        Args:
            session_id: Session identifier
            **kwargs: Metrics to update
        """
        with self.metrics_lock:
            if session_id not in self.active_sessions:
                self.logger.warning(f"Session {session_id} not found")
                return

            session = self.active_sessions[session_id]

            # Update session metrics
            for key, value in kwargs.items():
                if hasattr(session, key):
                    setattr(session, key, value)

            # Track API calls
            if 'api_calls_count' in kwargs:
                if self.enable_prometheus:
                    self.prometheus_metrics['api_requests'].labels(
                        api_type='helius', status='success'
                    ).inc(kwargs['api_calls_count'])
                else:
                    self.prometheus_metrics.inc('api_requests_total',
                                             {'api_type': 'helius', 'status': 'success'},
                                             kwargs['api_calls_count'])

            # Track errors
            if 'errors_count' in kwargs and kwargs['errors_count'] > 0:
                if self.enable_prometheus:
                    self.prometheus_metrics['errors'].labels(
                        error_type='general'
                    ).inc(kwargs['errors_count'])
                else:
                    self.prometheus_metrics.inc('backtest_errors_total',
                                             {'error_type': 'general'},
                                             kwargs['errors_count'])

    def complete_backtest_session(self, session_id: str, status: str = "completed"):
        """
        Mark a backtest session as completed

        Args:
            session_id: Session identifier
            status: Completion status (completed, failed, cancelled)
        """
        with self.metrics_lock:
            if session_id not in self.active_sessions:
                self.logger.warning(f"Session {session_id} not found")
                return

            session = self.active_sessions[session_id]
            session.end_time = datetime.now()
            session.status = status
            session.execution_time_ms = (session.end_time - session.start_time).total_seconds() * 1000

            # Add to completed sessions
            self.completed_sessions.append(session)

            # Limit completed sessions size
            if len(self.completed_sessions) > self.max_completed_sessions:
                self.completed_sessions = self.completed_sessions[-self.max_completed_sessions:]

            # Remove from active sessions
            del self.active_sessions[session_id]

            # Update Prometheus metrics
            duration_seconds = session.execution_time_ms / 1000

            if self.enable_prometheus:
                self.prometheus_metrics['sessions_total'].labels(status=status).inc()
                self.prometheus_metrics['session_duration'].observe(duration_seconds)
                self.prometheus_metrics['execution_time'].observe(session.execution_time_ms)
                self.prometheus_metrics['profit_loss'].observe(session.simulated_profit_loss)
                self.prometheus_metrics['score'].observe(session.final_score)
                self.prometheus_metrics['active_sessions'].set(len(self.active_sessions))

                # Filter scores
                self.prometheus_metrics['filter_score'].labels(
                    filter_name='honeypot'
                ).observe(session.honeypot_score)
                self.prometheus_metrics['filter_score'].labels(
                    filter_name='liquidity'
                ).observe(session.liquidity_score)
                self.prometheus_metrics['filter_score'].labels(
                    filter_name='security'
                ).observe(session.security_score)
                self.prometheus_metrics['filter_score'].labels(
                    filter_name='social'
                ).observe(session.social_score)
                self.prometheus_metrics['filter_score'].labels(
                    filter_name='volatility'
                ).observe(session.volatility_score)
            else:
                self.prometheus_metrics.inc('backtest_sessions_total', {'status': status})
                self.prometheus_metrics.observe('backtest_session_duration_seconds', value=duration_seconds)
                self.prometheus_metrics.observe('backtest_execution_time_ms', value=session.execution_time_ms)
                self.prometheus_metrics.observe('backtest_profit_loss_usd', value=session.simulated_profit_loss)
                self.prometheus_metrics.observe('backtest_final_score', value=session.final_score)
                self.prometheus_metrics.set('backtest_active_sessions', len(self.active_sessions))

            # Update aggregated metrics
            self._update_aggregated_metrics()

            # Track performance
            self.performance_history.append(session.execution_time_ms)

            self.logger.info(f"Completed backtest session: {session_id} (status: {status}, score: {session.final_score:.2f})")

    def _update_aggregated_metrics(self):
        """Update aggregated metrics from completed sessions"""
        if not self.completed_sessions:
            return

        # Calculate statistics
        total_sessions = len(self.completed_sessions)
        successful_sessions = len([s for s in self.completed_sessions if s.status == 'completed'])
        failed_sessions = len([s for s in self.completed_sessions if s.status == 'failed'])

        # Profit/loss statistics
        profit_losses = [s.simulated_profit_loss for s in self.completed_sessions if s.status == 'completed']
        total_profit_loss = sum(profit_losses)
        avg_profit_loss = total_profit_loss / len(profit_losses) if profit_losses else 0
        max_profit_loss = max(profit_losses) if profit_losses else 0
        min_profit_loss = min(profit_losses) if profit_losses else 0

        # Score statistics
        scores = [s.final_score for s in self.completed_sessions if s.status == 'completed']
        avg_score = sum(scores) / len(scores) if scores else 0

        # Execution time statistics
        execution_times = [s.execution_time_ms for s in self.completed_sessions if s.status == 'completed']
        avg_execution_time = sum(execution_times) / len(execution_times) if execution_times else 0

        # Recommendation distribution
        recommendations = [s.recommendation for s in self.completed_sessions if s.status == 'completed']
        strong_buy_count = recommendations.count("STRONG_BUY")
        buy_count = recommendations.count("BUY")
        hold_count = recommendations.count("HOLD")
        avoid_count = recommendations.count("AVOID")

        # Profit percentiles
        if profit_losses:
            sorted_profits = sorted(profit_losses)
            profit_75th = sorted_profits[int(len(sorted_profits) * 0.75)]
            profit_90th = sorted_profits[int(len(sorted_profits) * 0.90)]
        else:
            profit_75th = profit_90th = 0

        # Update aggregated metrics
        self.aggregated_metrics = AggregatedMetrics(
            total_sessions=total_sessions,
            successful_sessions=successful_sessions,
            failed_sessions=failed_sessions,
            running_sessions=len(self.active_sessions),
            total_profit_loss=total_profit_loss,
            avg_profit_loss=avg_profit_loss,
            max_profit_loss=max_profit_loss,
            min_profit_loss=min_profit_loss,
            avg_score=avg_score,
            avg_execution_time_ms=avg_execution_time,
            strong_buy_count=strong_buy_count,
            buy_count=buy_count,
            hold_count=hold_count,
            avoid_count=avoid_count,
            profit_75th_percentile=profit_75th,
            profit_90th_percentile=profit_90th,
            last_updated=datetime.now()
        )

    def _get_performance_stats(self) -> Dict[str, Any]:
        """Get current performance statistics"""
        current_time = time.time()

        # Calculate request rate (last minute)
        recent_requests = [
            ts for ts in self.request_timestamps
            if current_time - ts < 60
        ]
        requests_per_minute = len(recent_requests)

        # Calculate average execution time (last 10 sessions)
        recent_executions = list(self.performance_history)[-10:]
        avg_execution_time = sum(recent_executions) / len(recent_executions) if recent_executions else 0

        # Calculate error rate
        error_rate = self._get_current_error_rate()

        return {
            'requests_per_minute': requests_per_minute,
            'avg_execution_time_ms': avg_execution_time,
            'error_rate': error_rate,
            'active_sessions': len(self.active_sessions),
            'cache_hit_rate': self._get_cache_hit_rate(),
            'memory_usage_mb': self._get_memory_usage(),
            'uptime_seconds': current_time - (self.completed_sessions[0].start_time.timestamp() if self.completed_sessions else current_time)
        }

    def _get_current_error_rate(self) -> float:
        """Calculate current error rate"""
        with self.metrics_lock:
            total_sessions = len(self.completed_sessions) + len(self.active_sessions)
            failed_sessions = len([s for s in self.completed_sessions if s.status == 'failed'])

            if total_sessions == 0:
                return 0.0

            return failed_sessions / total_sessions

    def _get_cache_hit_rate(self) -> float:
        """Calculate cache hit rate"""
        with self.metrics_lock:
            total_cache_ops = 0
            total_hits = 0

            for session in list(self.active_sessions.values()) + self.completed_sessions[-100:]:
                total_cache_ops += session.cache_hits + session.cache_misses
                total_hits += session.cache_hits

            return total_hits / total_cache_ops if total_cache_ops > 0 else 0.0

    def _get_memory_usage(self) -> float:
        """Get current memory usage in MB"""
        try:
            import psutil
            process = psutil.Process()
            return process.memory_info().rss / 1024 / 1024
        except ImportError:
            return 0.0

    def get_session_metrics(self, session_id: str) -> Optional[Dict[str, Any]]:
        """Get metrics for a specific session"""
        with self.metrics_lock:
            # Check active sessions
            if session_id in self.active_sessions:
                return self.active_sessions[session_id].to_dict()

            # Check completed sessions
            for session in reversed(self.completed_sessions):
                if session.session_id == session_id:
                    return session.to_dict()

            return None

    def get_top_performing_tokens(self, limit: int = 10) -> List[Dict[str, Any]]:
        """Get top performing tokens by profit/loss"""
        with self.metrics_lock:
            # Get completed sessions sorted by profit/loss
            completed = [
                session for session in self.completed_sessions
                if session.status == 'completed' and session.simulated_profit_loss != 0
            ]

            completed.sort(key=lambda x: x.simulated_profit_loss, reverse=True)

            return [
                {
                    'token_address': session.token_address,
                    'token_name': session.token_name,
                    'token_symbol': session.token_symbol,
                    'profit_loss': session.simulated_profit_loss,
                    'final_score': session.final_score,
                    'recommendation': session.recommendation,
                    'completion_time': session.end_time.isoformat() if session.end_time else None
                }
                for session in completed[:limit]
            ]

    def get_alert_status(self) -> Dict[str, Any]:
        """Get current alert status"""
        alerts = []

        # Check error rate
        error_rate = self._get_current_error_rate()
        if error_rate > self.alert_thresholds['error_rate']:
            alerts.append({
                'type': 'error_rate',
                'severity': 'warning',
                'message': f'High error rate: {error_rate:.1%} (threshold: {self.alert_thresholds["error_rate"]:.1%})'
            })

        # Check execution time
        with self.metrics_lock:
            if self.performance_history:
                avg_execution = sum(self.performance_history[-10:]) / min(10, len(self.performance_history))
                if avg_execution > self.alert_thresholds['avg_execution_time']:
                    alerts.append({
                        'type': 'execution_time',
                        'severity': 'warning',
                        'message': f'High execution time: {avg_execution:.0f}ms (threshold: {self.alert_thresholds["avg_execution_time"]}ms)'
                    })

        # Check memory usage
        memory_usage = self._get_memory_usage()
        if memory_usage > 1024:  # 1GB
            alerts.append({
                'type': 'memory_usage',
                'severity': 'warning',
                'message': f'High memory usage: {memory_usage:.0f}MB'
            })

        return {
            'alert_count': len(alerts),
            'alerts': alerts,
            'timestamp': datetime.now().isoformat()
        }

    def cleanup_old_sessions(self, hours: int = 24):
        """Clean up old session data"""
        cutoff_time = datetime.now() - timedelta(hours=hours)

        with self.metrics_lock:
            # Clean up completed sessions
            original_count = len(self.completed_sessions)
            self.completed_sessions = [
                session for session in self.completed_sessions
                if session.end_time and session.end_time > cutoff_time
            ]

            cleaned_count = original_count - len(self.completed_sessions)
            if cleaned_count > 0:
                self.logger.info(f"Cleaned up {cleaned_count} old sessions (older than {hours} hours)")

    async def __aenter__(self):
        """Async context manager entry"""
        await self.start_metrics_server()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit"""
        await self.stop_metrics_server()


# Global instance
_sandwich_manager = None


def get_sandwich_manager(metrics_port: int = 8001, enable_prometheus: bool = True) -> SandwichManager:
    """Get or create global SandwichManager instance"""
    global _sandwich_manager
    if _sandwich_manager is None:
        _sandwich_manager = SandwichManager(metrics_port, enable_prometheus)
    return _sandwich_manager


# Test function
async def test_sandwich_manager():
    """Test SandwichManager functionality"""
    logger.info("Testing SandwichManager...")

    try:
        # Create manager
        manager = SandwichManager(metrics_port=8002)

        # Start metrics server
        await manager.start_metrics_server()

        # Test session tracking
        session_id = "test_session_001"
        session = manager.start_backtest_session(
            session_id=session_id,
            token_address="So11111111111111111111111111111111111111112",
            token_name="Wrapped SOL",
            token_symbol="WSOL"
        )

        # Update session metrics
        manager.update_session_metrics(
            session_id,
            api_calls_count=15,
            cache_hits=8,
            cache_misses=7,
            final_score=0.75,
            recommendation="BUY",
            simulated_profit_loss=150.0,
            honeypot_score=0.9,
            liquidity_score=0.8,
            security_score=0.85,
            social_score=0.7,
            volatility_score=0.6
        )

        # Complete session
        await asyncio.sleep(0.1)  # Small delay
        manager.complete_backtest_session(session_id, "completed")

        # Check metrics
        session_metrics = manager.get_session_metrics(session_id)
        if session_metrics:
            logger.info(f"✅ Session metrics retrieved: {session_metrics['final_score']:.2f}")

        # Check aggregated metrics
        logger.info(f"✅ Aggregated metrics: {manager.aggregated_metrics.total_sessions} sessions")

        # Check alerts
        alert_status = manager.get_alert_status()
        logger.info(f"✅ Alert status: {alert_status['alert_count']} alerts")

        # Stop server
        await manager.stop_metrics_server()

        logger.info("SandwichManager test completed successfully")

    except Exception as e:
        logger.error(f"SandwichManager test failed: {e}")
        raise


if __name__ == "__main__":
    # Run test
    asyncio.run(test_sandwich_manager())