use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use solana_sdk::instruction::Instruction;
use solana_sdk::pubkey::Pubkey;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, RwLock};
use serde::{Deserialize, Serialize};

use crate::arbitrage::flash_loan::{FlashLoanExecutor, FlashLoanProvider, FlashLoanRequest, FlashLoanResult};
use crate::execution::rpc_router::{RpcRouter, UrgencyLevel, PriorityFeeCalculator};
use crate::data_consumer::PriorityLevel;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlashLoanCoordinatorConfig {
    pub max_concurrent_loans: usize,
    pub loan_timeout: Duration,
    pub profit_threshold: f64,
    pub max_slippage: f64,
    pub retry_attempts: u8,
    pub retry_delay: Duration,
    pub health_check_interval: Duration,
    pub provider_selection_strategy: ProviderSelectionStrategy,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ProviderSelectionStrategy {
    BestRate,
    FastestExecution,
    HighestLiquidity,
    RoundRobin,
    LoadBalanced,
}

impl Default for FlashLoanCoordinatorConfig {
    fn default() -> Self {
        Self {
            max_concurrent_loans: 5,
            loan_timeout: Duration::from_secs(30),
            profit_threshold: 0.002, // 0.2%
            max_slippage: 0.03,      // 3%
            retry_attempts: 3,
            retry_delay: Duration::from_millis(500),
            health_check_interval: Duration::from_secs(10),
            provider_selection_strategy: ProviderSelectionStrategy::BestRate,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FlashLoanOpportunity {
    pub id: String,
    pub token_mint: Pubkey,
    pub amount: u64,
    pub expected_profit: f64,
    pub arbitrage_path: Vec<String>,
    pub urgency: UrgencyLevel,
    pub created_at: Instant,
    pub expires_at: Instant,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoordinatedFlashLoan {
    pub opportunity: FlashLoanOpportunity,
    pub selected_provider: FlashLoanProvider,
    pub provider_address: Pubkey,
    pub priority_fee: u64,
    pub estimated_gas_cost: u64,
    pub execution_time: Duration,
    pub callback: mpsc::Sender<FlashLoanResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CoordinatorMetrics {
    pub total_opportunities: u64,
    pub successful_loans: u64,
    pub failed_loans: u64,
    pub total_profit: f64,
    pub average_execution_time: Duration,
    pub provider_usage: HashMap<FlashLoanProvider, u64>,
    pub success_rate_by_provider: HashMap<FlashLoanProvider, f64>,
    pub profit_by_provider: HashMap<FlashLoanProvider, f64>,
    pub current_active_loans: usize,
    pub average_priority_fee: u64,
}

impl Default for CoordinatorMetrics {
    fn default() -> Self {
        Self {
            total_opportunities: 0,
            successful_loans: 0,
            failed_loans: 0,
            total_profit: 0.0,
            average_execution_time: Duration::from_secs(0),
            provider_usage: HashMap::new(),
            success_rate_by_provider: HashMap::new(),
            profit_by_provider: HashMap::new(),
            current_active_loans: 0,
            average_priority_fee: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderHealth {
    pub provider: FlashLoanProvider,
    pub is_healthy: bool,
    pub last_check: Instant,
    pub response_time: Duration,
    pub available_liquidity: u64,
    pub success_rate: f64,
    pub error_count: u64,
}

pub struct FlashLoanCoordinator {
    config: FlashLoanCoordinatorConfig,
    rpc_router: Arc<RpcRouter>,
    priority_fee_calculator: Arc<PriorityFeeCalculator>,
    flash_loan_executors: HashMap<FlashLoanProvider, Arc<FlashLoanExecutor>>,

    // Opportunity management
    opportunity_queue: mpsc::UnboundedReceiver<FlashLoanOpportunity>,
    active_loans: Arc<RwLock<HashMap<String, CoordinatedFlashLoan>>>,
    provider_health: Arc<RwLock<HashMap<FlashLoanProvider, ProviderHealth>>>,

    // Metrics and monitoring
    metrics: Arc<RwLock<CoordinatorMetrics>>,
    start_time: Instant,
    recent_profits: Arc<RwLock<Vec<f64>>>,

    // Provider selection
    provider_selection_index: Arc<RwLock<usize>>,
    provider_load_balancer: Arc<RwLock<HashMap<FlashLoanProvider, usize>>>,
}

impl FlashLoanCoordinator {
    pub fn new(
        config: FlashLoanCoordinatorConfig,
        rpc_router: Arc<RpcRouter>,
        priority_fee_calculator: Arc<PriorityFeeCalculator>,
        flash_loan_executors: HashMap<FlashLoanProvider, Arc<FlashLoanExecutor>>,
    ) -> (Self, mpsc::UnboundedSender<FlashLoanOpportunity>) {
        let (tx, rx) = mpsc::unbounded_channel();

        let coordinator = Self {
            config,
            rpc_router,
            priority_fee_calculator,
            flash_loan_executors,
            opportunity_queue: rx,
            active_loans: Arc::new(RwLock::new(HashMap::new())),
            provider_health: Arc::new(RwLock::new(HashMap::new())),
            metrics: Arc::new(RwLock::new(CoordinatorMetrics::default())),
            start_time: Instant::now(),
            recent_profits: Arc::new(RwLock::new(Vec::new())),
            provider_selection_index: Arc::new(RwLock::new(0)),
            provider_load_balancer: Arc::new(RwLock::new(HashMap::new())),
        };

        (coordinator, tx)
    }

    pub async fn start(&mut self) -> Result<()> {
        info!("Starting FlashLoanCoordinator with {} providers", self.flash_loan_executors.len());

        // Initialize provider health
        self.initialize_provider_health().await?;

        let mut handles = vec![];

        // Main opportunity processor
        let processor_handle = self.start_opportunity_processor().await?;
        handles.push(processor_handle);

        // Health monitor
        let health_handle = self.start_health_monitor().await?;
        handles.push(health_handle);

        // Metrics collector
        let metrics_handle = self.start_metrics_collector().await?;
        handles.push(metrics_handle);

        info!("FlashLoanCoordinator started successfully");

        // Wait for all tasks
        for handle in handles {
            handle.await??;
        }

        Ok(())
    }

    async fn initialize_provider_health(&self) -> Result<()> {
        let mut health_map = self.provider_health.write().await;

        for provider in self.flash_loan_executors.keys() {
            let health = ProviderHealth {
                provider: provider.clone(),
                is_healthy: true,
                last_check: Instant::now(),
                response_time: Duration::from_millis(100),
                available_liquidity: 1_000_000, // 1M tokens default
                success_rate: 1.0,
                error_count: 0,
            };
            health_map.insert(provider.clone(), health);
        }

        Ok(())
    }

    async fn start_opportunity_processor(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let mut queue = std::mem::replace(&mut self.opportunity_queue, mpsc::unbounded_channel().1);
        let active_loans = self.active_loans.clone();
        let provider_health = self.provider_health.clone();
        let metrics = self.metrics.clone();
        let recent_profits = self.recent_profits.clone();
        let config = self.config.clone();
        let rpc_router = self.rpc_router.clone();
        let priority_fee_calculator = self.priority_fee_calculator.clone();
        let flash_loan_executors = self.flash_loan_executors.clone();
        let provider_selection_index = self.provider_selection_index.clone();
        let provider_load_balancer = self.provider_load_balancer.clone();

        let handle = tokio::spawn(async move {
            loop {
                // Check for new opportunities
                if let Some(opportunity) = queue.recv().await {
                    // Validate opportunity
                    if opportunity.expires_at < Instant::now() {
                        debug!("Skipping expired opportunity: {}", opportunity.id);
                        continue;
                    }

                    if opportunity.expected_profit < config.profit_threshold {
                        debug!("Skipping low-profit opportunity: {} (profit: {})",
                               opportunity.id, opportunity.expected_profit);
                        continue;
                    }

                    // Check concurrent loan limit
                    let active_count = active_loans.read().await.len();
                    if active_count >= config.max_concurrent_loans {
                        debug!("Skipping opportunity due to concurrent loan limit: {}", opportunity.id);
                        continue;
                    }

                    // Select best provider
                    let selected_provider = match Self::select_provider(
                        &opportunity,
                        &provider_health,
                        &config.provider_selection_strategy,
                        &provider_selection_index,
                        &provider_load_balancer,
                    ).await {
                        Some(provider) => provider,
                        None => {
                            warn!("No healthy provider available for opportunity: {}", opportunity.id);
                            continue;
                        }
                    };

                    // Calculate priority fee
                    let priority_fee = priority_fee_calculator.calculate_priority_fee(
                        &opportunity.urgency,
                        1_000_000, // Estimated compute units
                    ).await.unwrap_or(0);

                    // Estimate gas cost
                    let estimated_gas_cost = Self::estimate_gas_cost(&opportunity, priority_fee).await;

                    // Create coordinated flash loan
                    let coordinated_loan = CoordinatedFlashLoan {
                        opportunity: opportunity.clone(),
                        selected_provider: selected_provider.clone(),
                        provider_address: Self::get_provider_address(&selected_provider),
                        priority_fee,
                        estimated_gas_cost,
                        execution_time: Duration::from_secs(0), // Will be updated during execution
                        callback: opportunity.callback, // This would need to be passed in opportunity
                    };

                    // Add to active loans
                    {
                        let mut active = active_loans.write().await;
                        active.insert(opportunity.id.clone(), coordinated_loan.clone());
                    }

                    // Update metrics
                    {
                        let mut metrics_guard = metrics.write().await;
                        metrics_guard.total_opportunities += 1;
                        *metrics_guard.provider_usage.entry(selected_provider.clone()).or_insert(0) += 1;
                    }

                    // Execute flash loan
                    let executor = flash_loan_executors.get(&selected_provider)
                        .ok_or_else(|| anyhow!("Flash loan executor not found for provider: {:?}", selected_provider))?;

                    let execution_start = Instant::now();
                    let result = Self::execute_coordinated_loan(
                        coordinated_loan.clone(),
                        executor.clone(),
                        rpc_router.clone(),
                        config.clone(),
                    ).await;
                    let execution_time = execution_start.elapsed();

                    // Handle result
                    match result {
                        Ok(flash_result) => {
                            info!("Flash loan {} completed successfully: profit={}, time={}",
                                  opportunity.id, flash_result.actual_profit, execution_time);

                            // Update metrics
                            {
                                let mut metrics_guard = metrics.write().await;
                                metrics_guard.successful_loans += 1;
                                metrics_guard.total_profit += flash_result.actual_profit;

                                let total_time = metrics_guard.average_execution_time *
                                    (metrics_guard.successful_loans - 1) as u32 + execution_time;
                                metrics_guard.average_execution_time = total_time / metrics_guard.successful_loans as u32;

                                *metrics_guard.profit_by_provider.entry(selected_provider.clone()).or_insert(0.0)
                                    += flash_result.actual_profit;
                            }

                            // Track recent profits
                            {
                                let mut profits = recent_profits.write().await;
                                profits.push(flash_result.actual_profit);
                                if profits.len() > 100 {
                                    profits.remove(0);
                                }
                            }
                        }
                        Err(e) => {
                            error!("Flash loan {} failed: {}", opportunity.id, e);

                            // Update metrics
                            {
                                let mut metrics_guard = metrics.write().await;
                                metrics_guard.failed_loans += 1;
                            }
                        }
                    }

                    // Remove from active loans
                    {
                        let mut active = active_loans.write().await;
                        active.remove(&opportunity.id);
                    }
                } else {
                    // No opportunities, wait a bit
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            }
        });

        Ok(handle)
    }

    async fn select_provider(
        opportunity: &FlashLoanOpportunity,
        provider_health: &Arc<RwLock<HashMap<FlashLoanProvider, ProviderHealth>>>,
        strategy: &ProviderSelectionStrategy,
        selection_index: &Arc<RwLock<usize>>,
        load_balancer: &Arc<RwLock<HashMap<FlashLoanProvider, usize>>>,
    ) -> Option<FlashLoanProvider> {
        let health_guard = provider_health.read().await;

        // Filter healthy providers
        let healthy_providers: Vec<_> = health_guard.iter()
            .filter(|(_, health)| health.is_healthy)
            .map(|(provider, _)| provider.clone())
            .collect();

        if healthy_providers.is_empty() {
            return None;
        }

        match strategy {
            ProviderSelectionStrategy::BestRate => {
                // Select provider with best rates (simplified - would need real rate data)
                healthy_providers.first().cloned()
            }
            ProviderSelectionStrategy::FastestExecution => {
                // Select provider with fastest response time
                health_guard.iter()
                    .filter(|(provider, _)| healthy_providers.contains(provider))
                    .min_by_key(|(_, health)| health.response_time)
                    .map(|(provider, _)| provider.clone())
            }
            ProviderSelectionStrategy::HighestLiquidity => {
                // Select provider with most liquidity
                health_guard.iter()
                    .filter(|(provider, _)| healthy_providers.contains(provider))
                    .max_by_key(|(_, health)| health.available_liquidity)
                    .map(|(provider, _)| provider.clone())
            }
            ProviderSelectionStrategy::RoundRobin => {
                // Round-robin selection
                let mut index = selection_index.write().await;
                let provider = healthy_providers[*index % healthy_providers.len()].clone();
                *index = (*index + 1) % healthy_providers.len();
                Some(provider)
            }
            ProviderSelectionStrategy::LoadBalanced => {
                // Select provider with least current load
                let mut load_guard = load_balancer.write().await;
                let provider = healthy_providers.iter()
                    .min_by_key(|provider| load_guard.get(*provider).unwrap_or(&0))
                    .cloned()?;

                // Increment load
                *load_guard.entry(provider.clone()).or_insert(0) += 1;
                Some(provider)
            }
        }
    }

    async fn execute_coordinated_loan(
        coordinated_loan: CoordinatedFlashLoan,
        executor: Arc<FlashLoanExecutor>,
        rpc_router: Arc<RpcRouter>,
        config: FlashLoanCoordinatorConfig,
    ) -> Result<FlashLoanResult> {
        let opportunity = coordinated_loan.opportunity;

        // Create flash loan request
        let flash_request = FlashLoanRequest {
            id: opportunity.id.clone(),
            provider: coordinated_loan.selected_provider,
            token_mint: opportunity.token_mint,
            amount: opportunity.amount,
            arbitrage_instructions: vec![], // Would be built based on arbitrage path
            expected_profit: opportunity.expected_profit,
            max_slippage: config.max_slippage,
            urgency: opportunity.urgency,
            priority_fee: coordinated_loan.priority_fee,
            created_at: opportunity.created_at,
        };

        // Execute flash loan with timeout
        let result = tokio::time::timeout(
            config.loan_timeout,
            executor.execute_flash_loan_with_timeout(flash_request, config.loan_timeout)
        ).await??;

        Ok(result)
    }

    async fn get_provider_address(provider: &FlashLoanProvider) -> Pubkey {
        // Return the actual program address for each provider
        match provider {
            FlashLoanProvider::Solend => Pubkey::from_str("So1endDq2YkqhipR3E1PsjBsLvd6dAoj5tyUQgX3Zt").unwrap(),
            FlashLoanProvider::Marginfi => Pubkey::from_str("MFv2hWf31Z9kbPo1Ms5sxLh6tqF3bDDeJCMKJCBVnR").unwrap(),
            FlashLoanProvider::Mango => Pubkey::from_str("MANGOkCCV7or5J5r2k6gSSYcM4qYapoWEtdM4LsNrbN").unwrap(),
        }
    }

    async fn estimate_gas_cost(opportunity: &FlashLoanOpportunity, priority_fee: u64) -> u64 {
        // Simplified gas cost estimation
        let base_gas = 1_000_000; // Base compute units for flash loan
        let arbitrage_gas = 500_000; // Additional compute for arbitrage
        let total_compute_units = base_gas + arbitrage_gas;

        // Convert priority fee (micro-lamports per compute unit) to total lamports
        total_compute_units * priority_fee
    }

    async fn start_health_monitor(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let provider_health = self.provider_health.clone();
        let flash_loan_executors = self.flash_loan_executors.clone();
        let config = self.config.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(config.health_check_interval);

            loop {
                interval.tick().await;

                for (provider, executor) in &flash_loan_executors {
                    let health_start = Instant::now();

                    // Check provider health
                    let is_healthy = match executor.health_check().await {
                        Ok(_) => true,
                        Err(e) => {
                            error!("Health check failed for provider {:?}: {}", provider, e);
                            false
                        }
                    };

                    let response_time = health_start.elapsed();

                    // Update health status
                    {
                        let mut health_map = provider_health.write().await;
                        if let Some(health) = health_map.get_mut(provider) {
                            health.is_healthy = is_healthy;
                            health.last_check = Instant::now();
                            health.response_time = response_time;

                            if !is_healthy {
                                health.error_count += 1;
                            }
                        }
                    }

                    debug!("Provider {:?} health check: healthy={}, response_time={:?}",
                           provider, is_healthy, response_time);
                }
            }
        });

        Ok(handle)
    }

    async fn start_metrics_collector(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let metrics = self.metrics.clone();
        let provider_health = self.provider_health.clone();
        let recent_profits = self.recent_profits.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(30));

            loop {
                interval.tick().await;

                let metrics_guard = metrics.read().await;
                let health_guard = provider_health.read().await;
                let profits_guard = recent_profits.read().await;

                let total_loans = metrics_guard.successful_loans + metrics_guard.failed_loans;
                let success_rate = if total_loans > 0 {
                    (metrics_guard.successful_loans as f64 / total_loans as f64) * 100.0
                } else { 0.0 };

                let avg_profit = if !profits_guard.is_empty() {
                    profits_guard.iter().sum::<f64>() / profits_guard.len() as f64
                } else { 0.0 };

                info!(
                    "Flash Loan Coordinator Metrics: opportunities={}, success_rate={:.2}%, \
                     total_profit={:.6}, avg_profit={:.6}, active_loans={}",
                    metrics_guard.total_opportunities,
                    success_rate,
                    metrics_guard.total_profit,
                    avg_profit,
                    metrics_guard.current_active_loans
                );

                // Log provider-specific metrics
                for (provider, usage) in &metrics_guard.provider_usage {
                    let profit = metrics_guard.profit_by_provider.get(provider).unwrap_or(&0.0);
                    let health = health_guard.get(provider);
                    let health_status = health.map(|h| if h.is_healthy { "healthy" } else { "unhealthy" })
                        .unwrap_or("unknown");

                    debug!("Provider {:?}: usage={}, profit={}, health={}",
                            provider, usage, profit, health_status);
                }
            }
        });

        Ok(handle)
    }

    pub async fn get_metrics(&self) -> CoordinatorMetrics {
        self.metrics.read().await.clone()
    }

    pub async fn get_provider_health(&self) -> HashMap<FlashLoanProvider, ProviderHealth> {
        self.provider_health.read().await.clone()
    }

    pub async fn get_active_loans_count(&self) -> usize {
        self.active_loans.read().await.len()
    }

    pub async fn get_recent_profits(&self) -> Vec<f64> {
        self.recent_profits.read().await.clone()
    }
}

impl FlashLoanOpportunity {
    pub fn new(
        token_mint: Pubkey,
        amount: u64,
        expected_profit: f64,
        arbitrage_path: Vec<String>,
        urgency: UrgencyLevel,
        ttl_seconds: u64,
    ) -> Self {
        let now = Instant::now();
        Self {
            id: format!("fl_{}", SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos()),
            token_mint,
            amount,
            expected_profit,
            arbitrage_path,
            urgency,
            created_at: now,
            expires_at: now + Duration::from_secs(ttl_seconds),
        }
    }
}