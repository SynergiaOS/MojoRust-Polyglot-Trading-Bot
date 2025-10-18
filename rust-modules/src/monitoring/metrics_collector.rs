use anyhow::Result;
use log::{debug, error, info, warn};
use prometheus::{Counter, Gauge, Histogram, IntCounter, IntGauge, Registry, Opts, HistogramOpts};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use serde::{Deserialize, Serialize};

use crate::arbitrage::cross_exchange::{CrossExchangeArbitrage, ArbitrageOpportunity};
use crate::execution::execution_engine::{ExecutionEngine, ExecutionMetrics};
use crate::execution::flash_loan_coordinator::{FlashLoanCoordinator, CoordinatorMetrics};
use crate::execution::rpc_router::{RpcRouter, EndpointMetrics};
use crate::execution::transaction_pipeline::{TransactionPipeline, PipelineMetrics};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetricsConfig {
    pub collection_interval: Duration,
    pub retention_period: Duration,
    pub enable_detailed_metrics: bool,
    pub enable_performance_profiling: bool,
    pub metrics_port: u16,
}

impl Default for MetricsConfig {
    fn default() -> Self {
        Self {
            collection_interval: Duration::from_secs(5),
            retention_period: Duration::from_secs(3600), // 1 hour
            enable_detailed_metrics: true,
            enable_performance_profiling: true,
            metrics_port: 8080,
        }
    }
}

pub struct TradingMetrics {
    // Execution Metrics
    pub total_transactions: IntCounter,
    pub successful_transactions: IntCounter,
    pub failed_transactions: IntCounter,
    pub transaction_execution_time: Histogram,
    pub transaction_gas_cost: Histogram,
    pub transaction_profit: Histogram,
    pub active_transactions: IntGauge,
    pub transaction_queue_depth: IntGauge,
    pub success_rate: Gauge,
    pub profit_per_second: Gauge,
    pub gas_cost_per_second: Gauge,

    // Arbitrage Metrics
    pub arbitrage_opportunities_detected: IntCounter,
    pub arbitrage_opportunities_executed: IntCounter,
    pub arbitrage_success_rate: Gauge,
    pub arbitrage_profit: Histogram,
    pub arbitrage_slippage: Histogram,
    pub cross_exchange_opportunities: IntCounter,
    pub triangular_opportunities: IntCounter,
    pub flash_loan_opportunities: IntCounter,

    // Flash Loan Metrics
    pub flash_loans_executed: IntCounter,
    pub flash_loan_success_rate: Gauge,
    pub flash_loan_profit: Histogram,
    pub flash_loan_execution_time: Histogram,
    pub active_flash_loans: IntGauge,
    pub flash_loan_provider_usage: HashMap<String, IntCounter>,
    pub flash_loan_provider_health: HashMap<String, Gauge>,

    // RPC Router Metrics
    pub rpc_requests_total: IntCounter,
    pub rpc_request_duration: Histogram,
    pub rpc_success_rate: Gauge,
    pub active_connections: IntGauge,
    pub endpoint_request_counts: HashMap<String, IntCounter>,
    pub endpoint_response_times: HashMap<String, Histogram>,
    pub priority_fee_average: Gauge,
    pub priority_fee_total: Counter,

    // Data Pipeline Metrics
    pub events_processed: IntCounter,
    pub events_filtered: IntCounter,
    pub event_processing_rate: Gauge,
    pub filter_efficiency: Gauge,
    pub redis_lag: Gauge,
    pub data_consumer_uptime: Gauge,

    // System Metrics
    pub memory_usage: Gauge,
    pub cpu_usage: Gauge,
    pub disk_io: Histogram,
    pub network_io: Histogram,
    pub open_files: IntGauge,
    pub threads: IntGauge,

    // Performance Metrics
    pub opportunity_detection_latency: Histogram,
    pub order_execution_latency: Histogram,
    pub end_to_end_latency: Histogram,
    pub throughput: Gauge,
    pub latency_p50: Gauge,
    pub latency_p95: Gauge,
    pub latency_p99: Gauge,

    // Risk Metrics
    pub portfolio_value: Gauge,
    pub drawdown: Gauge,
    pub position_size: Gauge,
    pub leverage_ratio: Gauge,
    pub risk_score: Gauge,
    pub circuit_breaker_trips: IntCounter,
    pub stop_loss_activations: IntCounter,

    // Error Metrics
    pub error_count: IntCounter,
    pub error_rate: Gauge,
    pub timeout_count: IntCounter,
    pub retry_count: IntCounter,
    pub circuit_breaker_active: IntGauge,
}

impl TradingMetrics {
    pub fn new() -> Self {
        Self {
            // Execution Metrics
            total_transactions: IntCounter::new("trading_total_transactions", "Total number of trading transactions").unwrap(),
            successful_transactions: IntCounter::new("trading_successful_transactions", "Number of successful transactions").unwrap(),
            failed_transactions: IntCounter::new("trading_failed_transactions", "Number of failed transactions").unwrap(),
            transaction_execution_time: Histogram::with_opts(
                HistogramOpts::new("trading_transaction_execution_time_seconds", "Transaction execution time in seconds")
                    .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0])
            ).unwrap(),
            transaction_gas_cost: Histogram::with_opts(
                HistogramOpts::new("trading_transaction_gas_cost_lamports", "Transaction gas cost in lamports")
                    .buckets(vec![1000, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000])
            ).unwrap(),
            transaction_profit: Histogram::with_opts(
                HistogramOpts::new("trading_transaction_profit_lamports", "Transaction profit in lamports")
                    .buckets(vec![-1000000, -500000, -250000, -100000, -50000, -25000, 0, 25000, 50000, 100000, 250000, 500000, 1000000])
            ).unwrap(),
            active_transactions: IntGauge::new("trading_active_transactions", "Number of currently active transactions").unwrap(),
            transaction_queue_depth: IntGauge::new("trading_transaction_queue_depth", "Number of transactions in queue").unwrap(),
            success_rate: Gauge::new("trading_success_rate", "Overall trading success rate").unwrap(),
            profit_per_second: Gauge::new("trading_profit_per_second_lamports", "Profit generated per second").unwrap(),
            gas_cost_per_second: Gauge::new("trading_gas_cost_per_second_lamports", "Gas cost incurred per second").unwrap(),

            // Arbitrage Metrics
            arbitrage_opportunities_detected: IntCounter::new("arbitrage_opportunities_detected_total", "Total arbitrage opportunities detected").unwrap(),
            arbitrage_opportunities_executed: IntCounter::new("arbitrage_opportunities_executed_total", "Total arbitrage opportunities executed").unwrap(),
            arbitrage_success_rate: Gauge::new("arbitrage_success_rate", "Arbitrage execution success rate").unwrap(),
            arbitrage_profit: Histogram::with_opts(
                HistogramOpts::new("arbitrage_profit_lamports", "Arbitrage profit in lamports")
                    .buckets(vec![10000, 25000, 50000, 100000, 250000, 500000, 1000000, 2500000, 5000000])
            ).unwrap(),
            arbitrage_slippage: Histogram::with_opts(
                HistogramOpts::new("arbitrage_slippage_percentage", "Arbitrage slippage percentage")
                    .buckets(vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0])
            ).unwrap(),
            cross_exchange_opportunities: IntCounter::new("arbitrage_cross_exchange_opportunities_total", "Cross-exchange arbitrage opportunities").unwrap(),
            triangular_opportunities: IntCounter::new("arbitrage_triangular_opportunities_total", "Triangular arbitrage opportunities").unwrap(),
            flash_loan_opportunities: IntCounter::new("arbitrage_flash_loan_opportunities_total", "Flash loan arbitrage opportunities").unwrap(),

            // Flash Loan Metrics
            flash_loans_executed: IntCounter::new("flash_loans_executed_total", "Total flash loans executed").unwrap(),
            flash_loan_success_rate: Gauge::new("flash_loan_success_rate", "Flash loan success rate").unwrap(),
            flash_loan_profit: Histogram::with_opts(
                HistogramOpts::new("flash_loan_profit_lamports", "Flash loan profit in lamports")
                    .buckets(vec![50000, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000])
            ).unwrap(),
            flash_loan_execution_time: Histogram::with_opts(
                HistogramOpts::new("flash_loan_execution_time_seconds", "Flash loan execution time in seconds")
                    .buckets(vec![1.0, 2.5, 5.0, 10.0, 15.0, 30.0, 60.0])
            ).unwrap(),
            active_flash_loans: IntGauge::new("flash_loan_active_count", "Number of active flash loans").unwrap(),
            flash_loan_provider_usage: HashMap::new(),
            flash_loan_provider_health: HashMap::new(),

            // RPC Router Metrics
            rpc_requests_total: IntCounter::new("rpc_requests_total", "Total RPC requests").unwrap(),
            rpc_request_duration: Histogram::with_opts(
                HistogramOpts::new("rpc_request_duration_seconds", "RPC request duration in seconds")
                    .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5])
            ).unwrap(),
            rpc_success_rate: Gauge::new("rpc_success_rate", "RPC request success rate").unwrap(),
            active_connections: IntGauge::new("rpc_active_connections", "Number of active RPC connections").unwrap(),
            endpoint_request_counts: HashMap::new(),
            endpoint_response_times: HashMap::new(),
            priority_fee_average: Gauge::new("rpc_priority_fee_average_lamports", "Average priority fee in lamports").unwrap(),
            priority_fee_total: Counter::new("rpc_priority_fee_total_lamports", "Total priority fees paid").unwrap(),

            // Data Pipeline Metrics
            events_processed: IntCounter::new("data_events_processed_total", "Total events processed").unwrap(),
            events_filtered: IntCounter::new("data_events_filtered_total", "Total events filtered out").unwrap(),
            event_processing_rate: Gauge::new("data_event_processing_rate", "Events processed per second").unwrap(),
            filter_efficiency: Gauge::new("data_filter_efficiency", "Filter efficiency percentage").unwrap(),
            redis_lag: Gauge::new("data_redis_lag_seconds", "Redis message lag in seconds").unwrap(),
            data_consumer_uptime: Gauge::new("data_consumer_uptime_seconds", "Data consumer uptime in seconds").unwrap(),

            // System Metrics
            memory_usage: Gauge::new("system_memory_usage_bytes", "Memory usage in bytes").unwrap(),
            cpu_usage: Gauge::new("system_cpu_usage_percentage", "CPU usage percentage").unwrap(),
            disk_io: Histogram::with_opts(
                HistogramOpts::new("system_disk_io_bytes", "Disk I/O in bytes")
                    .buckets(vec![1024, 4096, 16384, 65536, 262144, 1048576, 4194304, 16777216])
            ).unwrap(),
            network_io: Histogram::with_opts(
                HistogramOpts::new("system_network_io_bytes", "Network I/O in bytes")
                    .buckets(vec![1024, 4096, 16384, 65536, 262144, 1048576, 4194304, 16777216])
            ).unwrap(),
            open_files: IntGauge::new("system_open_files", "Number of open files").unwrap(),
            threads: IntGauge::new("system_threads", "Number of threads").unwrap(),

            // Performance Metrics
            opportunity_detection_latency: Histogram::with_opts(
                HistogramOpts::new("performance_opportunity_detection_latency_seconds", "Opportunity detection latency")
                    .buckets(vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25])
            ).unwrap(),
            order_execution_latency: Histogram::with_opts(
                HistogramOpts::new("performance_order_execution_latency_seconds", "Order execution latency")
                    .buckets(vec![0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5])
            ).unwrap(),
            end_to_end_latency: Histogram::with_opts(
                HistogramOpts::new("performance_end_to_end_latency_seconds", "End-to-end latency")
                    .buckets(vec![0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0])
            ).unwrap(),
            throughput: Gauge::new("performance_throughput_transactions_per_second", "Transactions per second").unwrap(),
            latency_p50: Gauge::new("performance_latency_p50_seconds", "50th percentile latency").unwrap(),
            latency_p95: Gauge::new("performance_latency_p95_seconds", "95th percentile latency").unwrap(),
            latency_p99: Gauge::new("performance_latency_p99_seconds", "99th percentile latency").unwrap(),

            // Risk Metrics
            portfolio_value: Gauge::new("risk_portfolio_value_lamports", "Portfolio value in lamports").unwrap(),
            drawdown: Gauge::new("risk_drawdown_percentage", "Drawdown percentage").unwrap(),
            position_size: Gauge::new("risk_position_size_lamports", "Position size in lamports").unwrap(),
            leverage_ratio: Gauge::new("risk_leverage_ratio", "Leverage ratio").unwrap(),
            risk_score: Gauge::new("risk_score", "Risk score").unwrap(),
            circuit_breaker_trips: IntCounter::new("risk_circuit_breaker_trips_total", "Circuit breaker trips").unwrap(),
            stop_loss_activations: IntCounter::new("risk_stop_loss_activations_total", "Stop loss activations").unwrap(),

            // Error Metrics
            error_count: IntCounter::new("error_count_total", "Total error count").unwrap(),
            error_rate: Gauge::new("error_rate", "Error rate").unwrap(),
            timeout_count: IntCounter::new("timeout_count_total", "Total timeout count").unwrap(),
            retry_count: IntCounter::new("retry_count_total", "Total retry count").unwrap(),
            circuit_breaker_active: IntGauge::new("circuit_breaker_active", "Number of active circuit breakers").unwrap(),
        }
    }

    pub fn register_with_registry(&self, registry: &Registry) -> Result<()> {
        // Register all metrics
        registry.register(Box::new(self.total_transactions.clone()))?;
        registry.register(Box::new(self.successful_transactions.clone()))?;
        registry.register(Box::new(self.failed_transactions.clone()))?;
        registry.register(Box::new(self.transaction_execution_time.clone()))?;
        registry.register(Box::new(self.transaction_gas_cost.clone()))?;
        registry.register(Box::new(self.transaction_profit.clone()))?;
        registry.register(Box::new(self.active_transactions.clone()))?;
        registry.register(Box::new(self.transaction_queue_depth.clone()))?;
        registry.register(Box::new(self.success_rate.clone()))?;
        registry.register(Box::new(self.profit_per_second.clone()))?;
        registry.register(Box::new(self.gas_cost_per_second.clone()))?;

        registry.register(Box::new(self.arbitrage_opportunities_detected.clone()))?;
        registry.register(Box::new(self.arbitrage_opportunities_executed.clone()))?;
        registry.register(Box::new(self.arbitrage_success_rate.clone()))?;
        registry.register(Box::new(self.arbitrage_profit.clone()))?;
        registry.register(Box::new(self.arbitrage_slippage.clone()))?;
        registry.register(Box::new(self.cross_exchange_opportunities.clone()))?;
        registry.register(Box::new(self.triangular_opportunities.clone()))?;
        registry.register(Box::new(self.flash_loan_opportunities.clone()))?;

        registry.register(Box::new(self.flash_loans_executed.clone()))?;
        registry.register(Box::new(self.flash_loan_success_rate.clone()))?;
        registry.register(Box::new(self.flash_loan_profit.clone()))?;
        registry.register(Box::new(self.flash_loan_execution_time.clone()))?;
        registry.register(Box::new(self.active_flash_loans.clone()))?;

        registry.register(Box::new(self.rpc_requests_total.clone()))?;
        registry.register(Box::new(self.rpc_request_duration.clone()))?;
        registry.register(Box::new(self.rpc_success_rate.clone()))?;
        registry.register(Box::new(self.active_connections.clone()))?;
        registry.register(Box::new(self.priority_fee_average.clone()))?;
        registry.register(Box::new(self.priority_fee_total.clone()))?;

        registry.register(Box::new(self.events_processed.clone()))?;
        registry.register(Box::new(self.events_filtered.clone()))?;
        registry.register(Box::new(self.event_processing_rate.clone()))?;
        registry.register(Box::new(self.filter_efficiency.clone()))?;
        registry.register(Box::new(self.redis_lag.clone()))?;
        registry.register(Box::new(self.data_consumer_uptime.clone()))?;

        registry.register(Box::new(self.memory_usage.clone()))?;
        registry.register(Box::new(self.cpu_usage.clone()))?;
        registry.register(Box::new(self.disk_io.clone()))?;
        registry.register(Box::new(self.network_io.clone()))?;
        registry.register(Box::new(self.open_files.clone()))?;
        registry.register(Box::new(self.threads.clone()))?;

        registry.register(Box::new(self.opportunity_detection_latency.clone()))?;
        registry.register(Box::new(self.order_execution_latency.clone()))?;
        registry.register(Box::new(self.end_to_end_latency.clone()))?;
        registry.register(Box::new(self.throughput.clone()))?;
        registry.register(Box::new(self.latency_p50.clone()))?;
        registry.register(Box::new(self.latency_p95.clone()))?;
        registry.register(Box::new(self.latency_p99.clone()))?;

        registry.register(Box::new(self.portfolio_value.clone()))?;
        registry.register(Box::new(self.drawdown.clone()))?;
        registry.register(Box::new(self.position_size.clone()))?;
        registry.register(Box::new(self.leverage_ratio.clone()))?;
        registry.register(Box::new(self.risk_score.clone()))?;
        registry.register(Box::new(self.circuit_breaker_trips.clone()))?;
        registry.register(Box::new(self.stop_loss_activations.clone()))?;

        registry.register(Box::new(self.error_count.clone()))?;
        registry.register(Box::new(self.error_rate.clone()))?;
        registry.register(Box::new(self.timeout_count.clone()))?;
        registry.register(Box::new(self.retry_count.clone()))?;
        registry.register(Box::new(self.circuit_breaker_active.clone()))?;

        Ok(())
    }
}

pub struct MetricsCollector {
    config: MetricsConfig,
    metrics: TradingMetrics,
    registry: Registry,

    // Component references for data collection
    execution_engine: Option<Arc<ExecutionEngine>>,
    flash_loan_coordinator: Option<Arc<FlashLoanCoordinator>>,
    rpc_router: Option<Arc<RpcRouter>>,
    transaction_pipeline: Option<Arc<TransactionPipeline>>,
    cross_exchange_arbitrage: Option<Arc<CrossExchangeArbitrage>>,

    // Collection state
    start_time: Instant,
    last_collection: Arc<RwLock<Instant>>,
    collection_stats: Arc<RwLock<CollectionStats>>,
}

#[derive(Debug, Clone, Default)]
struct CollectionStats {
    total_collections: u64,
    successful_collections: u64,
    failed_collections: u64,
    average_collection_time: Duration,
    last_error: Option<String>,
}

impl MetricsCollector {
    pub fn new(config: MetricsConfig) -> Result<Self> {
        let metrics = TradingMetrics::new();
        let registry = Registry::new();

        // Register metrics with registry
        metrics.register_with_registry(&registry)?;

        Ok(Self {
            config,
            metrics,
            registry,
            execution_engine: None,
            flash_loan_coordinator: None,
            rpc_router: None,
            transaction_pipeline: None,
            cross_exchange_arbitrage: None,
            start_time: Instant::now(),
            last_collection: Arc::new(RwLock::new(Instant::now())),
            collection_stats: Arc::new(RwLock::new(CollectionStats::default())),
        })
    }

    pub fn register_execution_engine(&mut self, execution_engine: Arc<ExecutionEngine>) {
        self.execution_engine = Some(execution_engine);
    }

    pub fn register_flash_loan_coordinator(&mut self, flash_loan_coordinator: Arc<FlashLoanCoordinator>) {
        self.flash_loan_coordinator = Some(flash_loan_coordinator);
    }

    pub fn register_rpc_router(&mut self, rpc_router: Arc<RpcRouter>) {
        self.rpc_router = Some(rpc_router);
    }

    pub fn register_transaction_pipeline(&mut self, transaction_pipeline: Arc<TransactionPipeline>) {
        self.transaction_pipeline = Some(transaction_pipeline);
    }

    pub fn register_cross_exchange_arbitrage(&mut self, cross_exchange_arbitrage: Arc<CrossExchangeArbitrage>) {
        self.cross_exchange_arbitrage = Some(cross_exchange_arbitrage);
    }

    pub fn get_registry(&self) -> &Registry {
        &self.registry
    }

    pub async fn start_collection(&self) -> Result<()> {
        info!("Starting metrics collection with interval {:?}", self.config.collection_interval);

        let metrics = &self.metrics;
        let collection_stats = self.collection_stats.clone();
        let last_collection = self.last_collection.clone();
        let execution_engine = self.execution_engine.clone();
        let flash_loan_coordinator = self.flash_loan_coordinator.clone();
        let rpc_router = self.rpc_router.clone();
        let transaction_pipeline = self.transaction_pipeline.clone();
        let cross_exchange_arbitrage = self.cross_exchange_arbitrage.clone();
        let collection_interval = self.config.collection_interval;
        let start_time = self.start_time;

        let mut interval = tokio::time::interval(collection_interval);

        loop {
            interval.tick().await;
            let collection_start = Instant::now();

            // Update uptime
            metrics.data_consumer_uptime.set(start_time.elapsed().as_secs_f64());

            // Collect execution engine metrics
            if let Some(engine) = &execution_engine {
                if let Ok(engine_metrics) = engine.get_metrics().await {
                    metrics.total_transactions.inc_by(engine_metrics.total_executed as u64);
                    metrics.successful_transactions.inc_by(engine_metrics.successful_executions as u64);
                    metrics.failed_transactions.inc_by(engine_metrics.failed_executions as u64);
                    metrics.active_transactions.set(engine.get_active_executions().await as i64);

                    let success_rate = if engine_metrics.total_executed > 0 {
                        (engine_metrics.successful_executions as f64 / engine_metrics.total_executed as f64) * 100.0
                    } else { 0.0 };
                    metrics.success_rate.set(success_rate);

                    // Update profit and gas cost rates
                    let elapsed = start_time.elapsed().as_secs_f64();
                    if elapsed > 0.0 {
                        metrics.profit_per_second.set(engine_metrics.total_profit / elapsed);
                        metrics.gas_cost_per_second.set(engine_metrics.total_gas_cost as f64 / elapsed);
                    }
                }
            }

            // Collect flash loan coordinator metrics
            if let Some(coordinator) = &flash_loan_coordinator {
                if let Ok(coordinator_metrics) = coordinator.get_metrics().await {
                    metrics.flash_loans_executed.inc_by(coordinator_metrics.successful_loans as u64);
                    metrics.active_flash_loans.set(coordinator_metrics.current_active_loans as i64);

                    let flash_success_rate = if coordinator_metrics.successful_loans + coordinator_metrics.failed_loans > 0 {
                        (coordinator_metrics.successful_loans as f64 / (coordinator_metrics.successful_loans + coordinator_metrics.failed_loans) as f64) * 100.0
                    } else { 0.0 };
                    metrics.flash_loan_success_rate.set(flash_success_rate);
                }
            }

            // Collect transaction pipeline metrics
            if let Some(pipeline) = &transaction_pipeline {
                let pipeline_metrics = pipeline.get_metrics().await;
                metrics.transaction_queue_depth.set(pipeline_metrics.queue_depth as i64);
                metrics.throughput.set(pipeline_metrics.total_sent as f64 / start_time.elapsed().as_secs_f64());
            }

            // Collect RPC router metrics
            if let Some(router) = &rpc_router {
                // Would need to implement get_metrics() on RpcRouter
                debug!("Collecting RPC router metrics");
            }

            // Collect system metrics
            Self::collect_system_metrics(metrics).await;

            // Update collection stats
            let collection_time = collection_start.elapsed();
            {
                let mut stats = collection_stats.write().await;
                stats.total_collections += 1;
                stats.successful_collections += 1;

                let total_time = stats.average_collection_time * (stats.successful_collections - 1) as u32 + collection_time;
                stats.average_collection_time = total_time / stats.successful_collections as u32;
            }
            *last_collection.write().await = Instant::now();

            debug!("Metrics collection completed in {:?}", collection_time);
        }
    }

    async fn collect_system_metrics(metrics: &TradingMetrics) {
        // Memory usage
        if let Ok(memory_info) = Self::get_memory_usage().await {
            metrics.memory_usage.set(memory_info as f64);
        }

        // CPU usage
        if let Ok(cpu_usage) = Self::get_cpu_usage().await {
            metrics.cpu_usage.set(cpu_usage);
        }

        // Open files
        if let Ok(open_files) = Self::get_open_files_count().await {
            metrics.open_files.set(open_files as i64);
        }

        // Threads
        if let Ok(threads) = Self::get_thread_count().await {
            metrics.threads.set(threads as i64);
        }
    }

    async fn get_memory_usage() -> Result<u64> {
        // Get memory usage from /proc/self/status
        let content = tokio::fs::read_to_string("/proc/self/status").await?;
        for line in content.lines() {
            if line.starts_with("VmRSS:") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    let memory_kb: u64 = parts[1].parse()?;
                    return Ok(memory_kb * 1024); // Convert to bytes
                }
            }
        }
        Err(anyhow!("Memory usage not found"))
    }

    async fn get_cpu_usage() -> Result<f64> {
        // Simplified CPU usage calculation
        Ok(0.0) // Would need proper implementation
    }

    async fn get_open_files_count() -> Result<usize> {
        // Count entries in /proc/self/fd
        let mut entries = tokio::fs::read_dir("/proc/self/fd").await?;
        let mut count = 0;
        while let Some(_) = entries.next_entry().await? {
            count += 1;
        }
        Ok(count)
    }

    async fn get_thread_count() -> Result<usize> {
        // Count entries in /proc/self/task
        let mut entries = tokio::fs::read_dir("/proc/self/task").await?;
        let mut count = 0;
        while let Some(_) = entries.next_entry().await? {
            count += 1;
        }
        Ok(count)
    }

    pub async fn get_collection_stats(&self) -> CollectionStats {
        self.collection_stats.read().await.clone()
    }
}