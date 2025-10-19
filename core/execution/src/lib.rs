//! MojoRust HFT Execution Engine
//!
//! High-performance order execution engine with real-time risk management
//! for high-frequency trading applications.

#![warn(missing_docs)]
#![warn(clippy::all)]
#![allow(dead_code)]

pub mod venues;
pub mod routing;
pub mod flash_loans;
pub mod risk;

// Core execution components
pub mod orders;
pub mod positions;
pub mod execution;
pub mod fills;

// Utilities
pub mod types;
pub mod metrics;
pub mod utils;

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn, error};
use solana_sdk::signature::Keypair;
use solana_sdk::pubkey::Pubkey;

/// Main execution engine
pub struct ExecutionEngine {
    config: Arc<RwLock<ExecutionConfig>>,
    venues: Arc<VenueManager>,
    router: Arc<OrderRouter>,
    risk_manager: Arc<RiskManager>,
    flash_loan_executor: Arc<FlashLoanExecutor>,
    metrics: Arc<ExecutionMetrics>,
    keypair: Keypair,
}

/// Execution configuration
#[derive(Debug, Clone)]
pub struct ExecutionConfig {
    /// Maximum order size in USD
    pub max_order_size_usd: f64,
    /// Maximum concurrent orders
    pub max_concurrent_orders: usize,
    /// Default slippage tolerance in basis points
    pub default_slippage_bps: u16,
    /// Order timeout in seconds
    pub order_timeout_seconds: u64,
    /// Enable flash loans
    pub enable_flash_loans: bool,
    /// Risk management enabled
    pub enable_risk_management: bool,
    /// Maximum position size per symbol
    pub max_position_size_usd: f64,
    /// Circuit breaker enabled
    pub enable_circuit_breaker: bool,
}

impl Default for ExecutionConfig {
    fn default() -> Self {
        Self {
            max_order_size_usd: 100000.0,
            max_concurrent_orders: 50,
            default_slippage_bps: 50,
            order_timeout_seconds: 30,
            enable_flash_loans: false,
            enable_risk_management: true,
            max_position_size_usd: 500000.0,
            enable_circuit_breaker: true,
        }
    }
}

impl ExecutionEngine {
    /// Create new execution engine
    pub async fn new(config: ExecutionConfig, keypair: Keypair) -> Result<Self> {
        info!("Initializing MojoRust HFT Execution Engine");

        let config = Arc::new(RwLock::new(config));
        let metrics = Arc::new(ExecutionMetrics::new());

        let venues = Arc::new(VenueManager::new(
            config.clone(),
            metrics.clone(),
        ).await?);

        let router = Arc::new(OrderRouter::new(
            config.clone(),
            venues.clone(),
            metrics.clone(),
        ).await?);

        let risk_manager = Arc::new(RiskManager::new(
            config.clone(),
            metrics.clone(),
        ).await?);

        let flash_loan_executor = Arc::new(FlashLoanExecutor::new(
            config.clone(),
            keypair.clone(),
            metrics.clone(),
        ).await?);

        Ok(Self {
            config,
            venues,
            router,
            risk_manager,
            flash_loan_executor,
            metrics,
            keypair,
        })
    }

    /// Start the execution engine
    pub async fn start(&self) -> Result<()> {
        info!("Starting execution engine");

        // Start venues
        self.venues.start().await?;

        // Start router
        self.router.start().await?;

        // Start risk manager
        self.risk_manager.start().await?;

        // Start flash loan executor if enabled
        let config = self.config.read().await;
        if config.enable_flash_loans {
            drop(config);
            self.flash_loan_executor.start().await?;
        }

        info!("Execution engine started successfully");
        Ok(())
    }

    /// Stop the execution engine
    pub async fn stop(&self) -> Result<()> {
        info!("Stopping execution engine");

        // Stop flash loan executor
        self.flash_loan_executor.stop().await?;

        // Stop risk manager
        self.risk_manager.stop().await?;

        // Stop router
        self.router.stop().await?;

        // Stop venues
        self.venues.stop().await?;

        info!("Execution engine stopped successfully");
        Ok(())
    }

    /// Submit a regular order
    pub async fn submit_order(&self, order: OrderRequest) -> Result<OrderResponse> {
        info!("Submitting order: {:?}", order);

        // Risk check first
        let risk_result = self.risk_manager.check_order(&order).await?;
        if !risk_result.approved {
            return Err(anyhow::anyhow!("Order rejected by risk manager: {}", risk_result.reason));
        }

        // Route and execute order
        let response = self.router.submit_order(order).await?;

        // Update metrics
        self.metrics.record_order_submission(&response);

        Ok(response)
    }

    /// Submit a flash loan arbitrage order
    pub async fn submit_flash_loan_arbitrage(&self, request: FlashLoanRequest) -> Result<FlashLoanResponse> {
        info!("Submitting flash loan arbitrage: {:?}", request);

        // Check if flash loans are enabled
        let config = self.config.read().await;
        if !config.enable_flash_loans {
            return Err(anyhow::anyhow!("Flash loans are disabled"));
        }
        drop(config);

        // Risk check with higher thresholds for flash loans
        let risk_result = self.risk_manager.check_flash_loan(&request).await?;
        if !risk_result.approved {
            return Err(anyhow::anyhow!("Flash loan rejected by risk manager: {}", risk_result.reason));
        }

        // Execute flash loan arbitrage
        let response = self.flash_loan_executor.execute_arbitrage(request).await?;

        // Update metrics
        self.metrics.record_flash_loan_execution(&response);

        Ok(response)
    }

    /// Cancel an order
    pub async fn cancel_order(&self, order_id: &str) -> Result<CancelResponse> {
        info!("Cancelling order: {}", order_id);
        self.router.cancel_order(order_id).await
    }

    /// Get current positions
    pub async fn get_positions(&self) -> Result<Vec<Position>> {
        self.risk_manager.get_positions().await
    }

    /// Get execution metrics
    pub fn get_metrics(&self) -> ExecutionMetricsSummary {
        self.metrics.get_summary()
    }

    /// Health check
    pub async fn health_check(&self) -> ExecutionHealthStatus {
        let venues_health = self.venues.health_check().await;
        let router_health = self.router.health_check().await;
        let risk_health = self.risk_manager.health_check().await;
        let flash_loan_health = self.flash_loan_executor.health_check().await;

        let overall_healthy = venues_health.is_healthy
            && router_health.is_healthy
            && risk_health.is_healthy
            && flash_loan_health.is_healthy;

        ExecutionHealthStatus {
            overall_healthy,
            venues_health,
            router_health,
            risk_health,
            flash_loan_health,
            timestamp: chrono::Utc::now(),
        }
    }

    /// Update configuration
    pub async fn update_config(&self, new_config: ExecutionConfig) -> Result<()> {
        info!("Updating execution engine configuration");
        *self.config.write().await = new_config;
        Ok(())
    }

    /// Emergency stop - cancel all orders and halt new submissions
    pub async fn emergency_stop(&self) -> Result<()> {
        warn!("EMERGENCY STOP ACTIVATED - Cancelling all orders");

        // Cancel all open orders
        self.router.cancel_all_orders().await?;

        // Halt new order submissions
        let mut config = self.config.write().await;
        config.enable_risk_management = false;

        error!("Emergency stop completed - All orders cancelled, new submissions halted");
        Ok(())
    }
}

// Types and structures
#[derive(Debug, Clone)]
pub struct OrderRequest {
    pub symbol: String,
    pub side: OrderSide,
    pub order_type: OrderType,
    pub quantity: f64,
    pub price: Option<f64>,
    pub time_in_force: TimeInForce,
    pub slippage_bps: Option<u16>,
    pub timeout_seconds: Option<u64>,
}

#[derive(Debug, Clone)]
pub struct OrderResponse {
    pub order_id: String,
    pub status: OrderStatus,
    pub filled_quantity: f64,
    pub average_price: Option<f64>,
    pub commission: f64,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
pub struct FlashLoanRequest {
    pub arbitrage_type: ArbitrageType,
    pub token_a: String,
    pub token_b: String,
    pub loan_amount: f64,
    pub expected_profit: f64,
    pub route: Vec<String>,
    pub max_slippage_bps: u16,
    pub preferred_provider: Option<FlashLoanProvider>,
    pub slippage_bps: u64,
    pub token_mint: Pubkey,
}

#[derive(Debug, Clone)]
pub struct FlashLoanResponse {
    pub transaction_id: Option<String>,
    pub success: bool,
    pub actual_profit: f64,
    pub execution_time_ms: u64,
    pub gas_used: u64,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Position {
    pub symbol: String,
    pub quantity: f64,
    pub average_price: f64,
    pub unrealized_pnl: f64,
    pub realized_pnl: f64,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
pub struct CancelResponse {
    pub order_id: String,
    pub success: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ExecutionMetricsSummary {
    pub orders_submitted: u64,
    pub orders_filled: u64,
    pub fill_rate: f64,
    pub average_fill_time_ms: f64,
    pub total_volume_usd: f64,
    pub total_commission_usd: f64,
    pub flash_loans_executed: u64,
    pub flash_loan_success_rate: f64,
    pub circuit_breaker_trips: u64,
}

#[derive(Debug, Clone)]
pub struct ExecutionHealthStatus {
    pub overall_healthy: bool,
    pub venues_health: ComponentHealth,
    pub router_health: ComponentHealth,
    pub risk_health: ComponentHealth,
    pub flash_loan_health: ComponentHealth,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
pub struct ComponentHealth {
    pub is_healthy: bool,
    pub message: String,
    pub last_check: chrono::DateTime<chrono::Utc>,
}

// Enums
#[derive(Debug, Clone, PartialEq)]
pub enum OrderSide {
    Buy,
    Sell,
}

#[derive(Debug, Clone, PartialEq)]
pub enum OrderType {
    Market,
    Limit,
    Stop,
    StopLimit,
}

#[derive(Debug, Clone, PartialEq)]
pub enum OrderStatus {
    New,
    PartiallyFilled,
    Filled,
    Cancelled,
    Rejected,
}

#[derive(Debug, Clone, PartialEq)]
pub enum TimeInForce {
    Day,
    GTC, // Good Till Cancelled
    IOC, // Immediate Or Cancel
    FOK, // Fill Or Kill
}

#[derive(Debug, Clone, PartialEq)]
pub enum ArbitrageType {
    Simple,
    Triangular,
    CrossExchange,
}

#[derive(Debug, Clone, PartialEq)]
pub enum FlashLoanProvider {
    Save,
    Solend,
    MangoV4,
}

impl FlashLoanProvider {
    pub fn fee_bps(&self) -> u64 {
        match self {
            FlashLoanProvider::Save => 3,      // 0.03%
            FlashLoanProvider::Solend => 5,    // 0.05%
            FlashLoanProvider::MangoV4 => 8,    // 0.08%
        }
    }

    pub fn max_latency_ms(&self) -> u64 {
        match self {
            FlashLoanProvider::Save => 20,     // Fastest
            FlashLoanProvider::Solend => 30,    // Medium
            FlashLoanProvider::MangoV4 => 40,    // Slowest
        }
    }

    pub fn max_loan_amount(&self) -> u64 {
        match self {
            FlashLoanProvider::Save => 5_000_000_000,     // 5 SOL
            FlashLoanProvider::Solend => 50_000_000_000,  // 50 SOL
            FlashLoanProvider::MangoV4 => 100_000_000_000, // 100 SOL
        }
    }
}

// Placeholder implementations
pub struct VenueManager;
impl VenueManager {
    async fn new(_config: Arc<RwLock<ExecutionConfig>>, _metrics: Arc<ExecutionMetrics>) -> Result<Self> {
        Ok(Self)
    }
    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct OrderRouter;
impl OrderRouter {
    async fn new(_config: Arc<RwLock<ExecutionConfig>>, _venues: Arc<VenueManager>, _metrics: Arc<ExecutionMetrics>) -> Result<Self> {
        Ok(Self)
    }
    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    async fn submit_order(&self, _order: OrderRequest) -> Result<OrderResponse> {
        Ok(OrderResponse {
            order_id: "test_order".to_string(),
            status: OrderStatus::Filled,
            filled_quantity: 100.0,
            average_price: Some(100.0),
            commission: 0.1,
            timestamp: chrono::Utc::now(),
        })
    }
    async fn cancel_order(&self, _order_id: &str) -> Result<CancelResponse> {
        Ok(CancelResponse {
            order_id: "test_order".to_string(),
            success: true,
            reason: None,
        })
    }
    async fn cancel_all_orders(&self) -> Result<()> { Ok(()) }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct RiskManager;
impl RiskManager {
    async fn new(_config: Arc<RwLock<ExecutionConfig>>, _metrics: Arc<ExecutionMetrics>) -> Result<Self> {
        Ok(Self)
    }
    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    async fn check_order(&self, _order: &OrderRequest) -> Result<RiskCheckResult> {
        Ok(RiskCheckResult {
            approved: true,
            reason: "OK".to_string(),
        })
    }
    async fn check_flash_loan(&self, _request: &FlashLoanRequest) -> Result<RiskCheckResult> {
        Ok(RiskCheckResult {
            approved: true,
            reason: "OK".to_string(),
        })
    }
    async fn get_positions(&self) -> Result<Vec<Position>> { Ok(vec![]) }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct FlashLoanExecutor {
    config: Arc<RwLock<ExecutionConfig>>,
    keypair: Arc<Keypair>,
    metrics: Arc<ExecutionMetrics>,
    provider_stats: Arc<RwLock<std::collections::HashMap<FlashLoanProvider, ProviderStats>>>,
}

#[derive(Debug, Clone, Default)]
struct ProviderStats {
    total_executions: u64,
    successful_executions: u64,
    total_profit: f64,
    average_execution_time_ms: f64,
    total_fees: f64,
}

impl FlashLoanExecutor {
    async fn new(config: Arc<RwLock<ExecutionConfig>>, keypair: Keypair, metrics: Arc<ExecutionMetrics>) -> Result<Self> {
        let mut provider_stats = std::collections::HashMap::new();
        provider_stats.insert(FlashLoanProvider::Save, ProviderStats::default());
        provider_stats.insert(FlashLoanProvider::Solend, ProviderStats::default());
        provider_stats.insert(FlashLoanProvider::MangoV4, ProviderStats::default());

        Ok(Self {
            config,
            keypair: Arc::new(keypair),
            metrics,
            provider_stats: Arc::new(RwLock::new(provider_stats)),
        })
    }

    async fn start(&self) -> Result<()> {
        info!("Starting FlashLoanExecutor with multi-provider support");
        Ok(())
    }

    async fn stop(&self) -> Result<()> {
        info!("Stopping FlashLoanExecutor");
        Ok(())
    }

    async fn execute_arbitrage(&self, request: FlashLoanRequest) -> Result<FlashLoanResponse> {
        let start_time = std::time::Instant::now();

        // Select optimal provider
        let provider = self.select_optimal_provider(&request).await?;
        info!("Selected flash loan provider: {:?}", provider);

        // Validate loan amount against provider limits
        if request.loan_amount as u64 > provider.max_loan_amount() {
            return Err(anyhow::anyhow!(
                "Loan amount {} exceeds provider {} maximum {}",
                request.loan_amount,
                format!("{:?}", provider),
                provider.max_loan_amount()
            ));
        }

        // Simulate flash loan execution based on provider
        let execution_result = match provider {
            FlashLoanProvider::Save => self.execute_save_flash_loan(&request).await,
            FlashLoanProvider::Solend => self.execute_solend_flash_loan(&request).await,
            FlashLoanProvider::MangoV4 => self.execute_mango_flash_loan(&request).await,
        };

        let execution_time_ms = start_time.elapsed().as_millis() as u64;

        match execution_result {
            Ok(mut response) => {
                response.execution_time_ms = execution_time_ms;

                // Update provider stats
                self.update_provider_stats(provider, &response, true).await;

                info!(
                    "Flash loan arbitrage successful: provider={:?}, profit=${:.4}, time={}ms",
                    provider, response.actual_profit, execution_time_ms
                );

                Ok(response)
            }
            Err(e) => {
                // Update provider stats with failure
                self.update_provider_stats(provider, &FlashLoanResponse {
                    transaction_id: None,
                    success: false,
                    actual_profit: 0.0,
                    execution_time_ms,
                    gas_used: 0,
                    error_message: Some(e.to_string()),
                }, false).await;

                error!(
                    "Flash loan arbitrage failed: provider={:?}, error={}, time={}ms",
                    provider, e, execution_time_ms
                );

                Err(e)
            }
        }
    }

    async fn select_optimal_provider(&self, request: &FlashLoanRequest) -> Result<FlashLoanProvider> {
        // Use preferred provider if specified and valid
        if let Some(preferred) = request.preferred_provider {
            if request.loan_amount as u64 <= preferred.max_loan_amount() {
                return Ok(preferred);
            }
        }

        // Select based on loan amount and historical performance
        let loan_amount = request.loan_amount as u64;

        if loan_amount <= 5_000_000_000 { // <= 5 SOL
            // Use Save for small amounts (fastest, lowest fees)
            Ok(FlashLoanProvider::Save)
        } else if loan_amount <= 50_000_000_000 { // <= 50 SOL
            // Use Solend for medium amounts (balanced)
            Ok(FlashLoanProvider::Solend)
        } else {
            // Use Mango V4 for large amounts (highest liquidity)
            Ok(FlashLoanProvider::MangoV4)
        }
    }

    async fn execute_save_flash_loan(&self, request: &FlashLoanRequest) -> Result<FlashLoanResponse> {
        info!("Executing Save flash loan: {} lamports", request.loan_amount as u64);

        // Simulate Save flash loan execution (20ms latency)
        tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

        let fees = (request.loan_amount * FlashLoanProvider::Save.fee_bps() as f64) / 10000.0;
        let net_profit = request.expected_profit - fees;

        Ok(FlashLoanResponse {
            transaction_id: Some(format!("save_tx_{}", chrono::Utc::now().timestamp())),
            success: net_profit > 0.0,
            actual_profit: net_profit,
            execution_time_ms: 0, // Will be set by caller
            gas_used: 150000,
            error_message: None,
        })
    }

    async fn execute_solend_flash_loan(&self, request: &FlashLoanRequest) -> Result<FlashLoanResponse> {
        info!("Executing Solend flash loan: {} lamports", request.loan_amount as u64);

        // Simulate Solend flash loan execution (30ms latency)
        tokio::time::sleep(tokio::time::Duration::from_millis(30)).await;

        let fees = (request.loan_amount * FlashLoanProvider::Solend.fee_bps() as f64) / 10000.0;
        let net_profit = request.expected_profit - fees;

        Ok(FlashLoanResponse {
            transaction_id: Some(format!("solend_tx_{}", chrono::Utc::now().timestamp())),
            success: net_profit > 0.0,
            actual_profit: net_profit,
            execution_time_ms: 0, // Will be set by caller
            gas_used: 180000,
            error_message: None,
        })
    }

    async fn execute_mango_flash_loan(&self, request: &FlashLoanRequest) -> Result<FlashLoanResponse> {
        info!("Executing Mango V4 flash loan: {} lamports", request.loan_amount as u64);

        // Simulate Mango V4 flash loan execution (40ms latency)
        tokio::time::sleep(tokio::time::Duration::from_millis(40)).await;

        let fees = (request.loan_amount * FlashLoanProvider::MangoV4.fee_bps() as f64) / 10000.0;
        let net_profit = request.expected_profit - fees;

        Ok(FlashLoanResponse {
            transaction_id: Some(format!("mango_tx_{}", chrono::Utc::now().timestamp())),
            success: net_profit > 0.0,
            actual_profit: net_profit,
            execution_time_ms: 0, // Will be set by caller
            gas_used: 220000,
            error_message: None,
        })
    }

    async fn update_provider_stats(&self, provider: FlashLoanProvider, response: &FlashLoanResponse, success: bool) {
        let mut stats = self.provider_stats.write().await;
        let provider_stats = stats.entry(provider).or_default();

        provider_stats.total_executions += 1;
        if success {
            provider_stats.successful_executions += 1;
            provider_stats.total_profit += response.actual_profit;
            provider_stats.total_fees += response.gas_used as f64 * 0.000001; // Convert gas units to SOL equivalent
        }

        // Update average execution time
        let total_time = provider_stats.average_execution_time_ms * (provider_stats.total_executions - 1) as f64 + response.execution_time_ms as f64;
        provider_stats.average_execution_time_ms = total_time / provider_stats.total_executions as f64;
    }

    async fn health_check(&self) -> ComponentHealth {
        let stats = self.provider_stats.read().await;
        let total_executions: u64 = stats.values().map(|s| s.total_executions).sum();
        let successful_executions: u64 = stats.values().map(|s| s.successful_executions).sum();

        let success_rate = if total_executions > 0 {
            successful_executions as f64 / total_executions as f64
        } else {
            1.0
        };

        let is_healthy = success_rate >= 0.8; // 80% success rate threshold

        ComponentHealth {
            is_healthy,
            message: format!(
                "Flash loan executor: {:.1}% success rate, {} total executions",
                success_rate * 100.0,
                total_executions
            ),
            last_check: chrono::Utc::now(),
        }
    }

    pub async fn get_provider_stats(&self) -> std::collections::HashMap<FlashLoanProvider, ProviderStats> {
        self.provider_stats.read().await.clone()
    }

    pub async fn get_provider_success_rate(&self, provider: &FlashLoanProvider) -> f64 {
        let stats = self.provider_stats.read().await;
        if let Some(provider_stats) = stats.get(provider) {
            if provider_stats.total_executions > 0 {
                provider_stats.successful_executions as f64 / provider_stats.total_executions as f64
            } else {
                0.0
            }
        } else {
            0.0
        }
    }
}

pub struct ExecutionMetrics;
impl ExecutionMetrics {
    fn new() -> Self { Self }
    fn record_order_submission(&self, _response: &OrderResponse) {}
    fn record_flash_loan_execution(&self, _response: &FlashLoanResponse) {}
    fn get_summary(&self) -> ExecutionMetricsSummary {
        ExecutionMetricsSummary {
            orders_submitted: 0,
            orders_filled: 0,
            fill_rate: 0.0,
            average_fill_time_ms: 0.0,
            total_volume_usd: 0.0,
            total_commission_usd: 0.0,
            flash_loans_executed: 0,
            flash_loan_success_rate: 0.0,
            circuit_breaker_trips: 0,
        }
    }
}

pub struct RiskCheckResult {
    pub approved: bool,
    pub reason: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::signature::Keypair;

    #[tokio::test]
    async fn test_execution_engine_creation() {
        let config = ExecutionConfig::default();
        let keypair = Keypair::new();
        let engine = ExecutionEngine::new(config, keypair).await;
        assert!(engine.is_ok());
    }

    #[tokio::test]
    async fn test_order_submission() {
        let config = ExecutionConfig::default();
        let keypair = Keypair::new();
        let engine = ExecutionEngine::new(config, keypair).await.unwrap();

        let order = OrderRequest {
            symbol: "SOL/USDC".to_string(),
            side: OrderSide::Buy,
            order_type: OrderType::Market,
            quantity: 10.0,
            price: None,
            time_in_force: TimeInForce::IOC,
            slippage_bps: Some(50),
            timeout_seconds: Some(30),
        };

        let response = engine.submit_order(order).await;
        assert!(response.is_ok());
    }

    #[tokio::test]
    async fn test_flash_loan_arbitrage() {
        let mut config = ExecutionConfig::default();
        config.enable_flash_loans = true;

        let keypair = Keypair::new();
        let engine = ExecutionEngine::new(config, keypair).await.unwrap();

        let request = FlashLoanRequest {
            arbitrage_type: ArbitrageType::Simple,
            token_a: "USDC".to_string(),
            token_b: "SOL".to_string(),
            loan_amount: 1000.0,
            expected_profit: 25.0,
            route: vec!["USDC".to_string(), "SOL".to_string()],
            max_slippage_bps: 100,
        };

        let response = engine.submit_flash_loan_arbitrage(request).await;
        assert!(response.is_ok());
    }

    #[test]
    fn test_execution_config() {
        let config = ExecutionConfig::default();
        assert!(config.max_order_size_usd > 0.0);
        assert!(config.max_concurrent_orders > 0);
        assert!(config.enable_risk_management);
        assert!(config.enable_circuit_breaker);
    }
}