use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use solana_sdk::instruction::Instruction;
use solana_sdk::pubkey::Pubkey;
use solana_sdk::signature::{Keypair, Signer};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, RwLock};
use tokio::time::timeout;
use serde::{Deserialize, Serialize};

use crate::arbitrage::flash_loan::{FlashLoanExecutor, FlashLoanProvider, FlashLoanRequest, FlashLoanResult};
use crate::arbitrage::ten_token::ArbitrageOpportunity;
use crate::execution::rpc_router::{RpcRouter, UrgencyLevel, PriorityFeeCalculator};
use crate::execution::flash_loan::save_flash_loan::{SaveFlashLoanEngine, SaveFlashLoanConfig, FlashLoanRequest as SaveFlashLoanRequest, FlashLoanResult as SaveFlashLoanResult};
use crate::data_consumer::PriorityLevel;
use deadpool_redis;
use std::str::FromStr;
use std::env;
use anyhow::Context;
use chrono;

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
    redis_client: deadpool_redis::Pool,

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
    ) -> Result<(Self, mpsc::UnboundedSender<FlashLoanOpportunity>)> {
        let (tx, rx) = mpsc::unbounded_channel();

        // Initialize Redis client
        let redis_url = env::var("REDIS_URL")
            .unwrap_or_else(|_| "redis://localhost:6379".to_string());

        let redis_pool = deadpool_redis::Config::from_url(redis_url)
            .create_pool(Some(deadpool_redis::Runtime::Tokio1))
            .context("Failed to create Redis pool")?;

        let coordinator = Self {
            config,
            rpc_router,
            priority_fee_calculator,
            flash_loan_executors,
            redis_client: redis_pool,
            opportunity_queue: rx,
            active_loans: Arc::new(RwLock::new(HashMap::new())),
            provider_health: Arc::new(RwLock::new(HashMap::new())),
            metrics: Arc::new(RwLock::new(CoordinatorMetrics::default())),
            start_time: Instant::now(),
            recent_profits: Arc::new(RwLock::new(Vec::new())),
            provider_selection_index: Arc::new(RwLock::new(0)),
            provider_load_balancer: Arc::new(RwLock::new(HashMap::new())),
        };

        Ok((coordinator, tx))
    }

    pub async fn start(&mut self) -> Result<()> {
        info!("Starting Enhanced FlashLoanCoordinator with {} providers", self.flash_loan_executors.len());

        // Initialize provider health
        self.initialize_provider_health().await?;

        let mut handles = vec![];

        // Main opportunity processor
        let processor_handle = self.start_opportunity_processor().await?;
        handles.push(processor_handle);

        // DragonflyDB subscription for orchestrator commands
        let dragonfly_handle = self.start_dragonfly_subscriber().await?;
        handles.push(dragonfly_handle);

        // Health monitor
        let health_handle = self.start_health_monitor().await?;
        handles.push(health_handle);

        // Metrics collector
        let metrics_handle = self.start_metrics_collector().await?;
        handles.push(metrics_handle);

        info!("Enhanced FlashLoanCoordinator started successfully");

        // Wait for all tasks
        for handle in handles {
            if let Err(e) = handle.await {
                error!("Task failed: {}", e);
            }
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
            FlashLoanProvider::Save => Pubkey::from_str("SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV").unwrap(),
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

    /// Execute arbitrage flash loan from opportunity
    pub async fn execute_arbitrage_flash_loan(
        &self,
        opportunity: &ArbitrageOpportunity,
        keypair: &solana_sdk::signature::Keypair,
    ) -> Result<FlashLoanResult> {
        info!("🔄 Executing arbitrage flash loan for {:?}", opportunity.token_pair);

        // Create opportunity from arbitrage opportunity
        let flash_opportunity = FlashLoanOpportunity::new(
            solana_sdk::pubkey::Pubkey::from_str(&opportunity.token_pair.0)
                .map_err(|e| anyhow!("Invalid token mint: {}", e))?,
            (opportunity.flash_loan_amount_sol * 1_000_000_000.0) as u64, // Convert SOL to lamports
            opportunity.estimated_profit_sol,
            vec![
                opportunity.buy_dex.clone(),
                opportunity.sell_dex.clone()
            ],
            match opportunity.confidence_score {
                x if x >= 0.8 => UrgencyLevel::Critical,
                x if x >= 0.6 => UrgencyLevel::High,
                x if x >= 0.4 => UrgencyLevel::Medium,
                _ => UrgencyLevel::Low,
            },
            30, // 30 seconds TTL
        );

        // Add to queue
        let tx = std::mem::replace(&mut self.opportunity_queue, mpsc::unbounded_channel().1);
        if let Err(_) = tx.send(flash_opportunity) {
            warn!("Failed to queue arbitrage opportunity");
        }

        // Wait for result (in production, this would be handled via callback)
        // For now, return a mock result
        Ok(FlashLoanResult {
            id: opportunity.token_pair.0.clone(),
            provider: FlashLoanProvider::Solend, // Default to Solend
            success: true,
            actual_profit: opportunity.estimated_profit_sol,
            execution_time: Duration::from_millis(250),
            gas_used: 2_500_000,
            error_message: None,
            transaction_signature: Some("mock_signature".to_string()),
            block_height: Some(123456),
        })
    }

    /// Execute snipe flash loan for new token
    pub async fn execute_snipe_flash_loan(
        &self,
        token_mint: &str,
        amount_sol: f64,
        keypair: &solana_sdk::signature::Keypair,
        slippage_bps: Option<u32>,
    ) -> Result<FlashLoanResult> {
        info!("🎯 Executing snipe flash loan for {}", token_mint);

        // Create opportunity for sniping
        let flash_opportunity = FlashLoanOpportunity::new(
            solana_sdk::pubkey::Pubkey::from_str(token_mint)
                .map_err(|e| anyhow!("Invalid token mint: {}", e))?,
            (amount_sol * 1_000_000_000.0) as u64, // Convert SOL to lamports
            0.01, // Expected profit (would be calculated)
            vec!["snipe".to_string()],
            UrgencyLevel::High, // Sniping is high urgency
            15, // 15 seconds TTL
        );

        // Add to queue
        let tx = std::mem::replace(&mut self.opportunity_queue, mpsc::unbounded_channel().1);
        if let Err(_) = tx.send(flash_opportunity) {
            warn!("Failed to queue snipe opportunity");
        }

        // Wait for result (in production, this would be handled via callback)
        // For now, return a mock result
        Ok(FlashLoanResult {
            id: token_mint.to_string(),
            provider: FlashLoanProvider::Save, // Use Save protocol
            success: true,
            actual_profit: 0.02,
            execution_time: Duration::from_millis(180),
            gas_used: 1_800_000,
            error_message: None,
            transaction_signature: Some("mock_snipe_signature".to_string()),
            block_height: Some(123457),
        })
    }

    /// Execute Save flash loan with enhanced integration
    pub async fn execute_save_flash_loan(
        &self,
        token_mint: &str,
        amount_sol: f64,
        keypair: &solana_sdk::signature::Keypair,
        urgency_level: &str,
        slippage_bps: u32,
    ) -> Result<SaveFlashLoanResult> {
        info!("⚡ Executing Save flash loan for {} amount={}", token_mint, amount_sol);

        // Create Save flash loan request
        let save_request = SaveFlashLoanRequest {
            token_mint: solana_sdk::pubkey::Pubkey::from_str(token_mint)
                .map_err(|e| anyhow!("Invalid token mint: {}", e))?,
            amount: (amount_sol * 1_000_000_000.0) as u64, // Convert SOL to lamports
            target_amount: 0, // Will be calculated by Save engine
            slippage_bps: slippage_bps as u64,
            urgency_level: urgency_level.to_string(),
        };

        // Create Save flash loan engine
        let save_config = SaveFlashLoanConfig::default();
        let rpc_client = Arc::new(solana_client::rpc_client::RpcClient::new(
            std::env::var("SOLANA_RPC_URL")
                .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string())
        ));

        let save_engine = SaveFlashLoanEngine::new(save_config, rpc_client);

        // Execute Save flash loan
        let start_time = Instant::now();
        let result = save_engine.execute_flash_loan_snipe(keypair, save_request).await
            .map_err(|e| anyhow!("Save flash loan execution failed: {}", e))?;

        let execution_time = start_time.elapsed();

        info!("✅ Save flash loan completed: success={}, time={}ms, profit={}",
              result.success, execution_time.as_millis(), result.fees_paid);

        // Update coordinator metrics
        {
            let mut metrics = self.metrics.write().await;
            if result.success {
                metrics.successful_loans += 1;
                metrics.total_profit += (result.fees_paid as f64) / 1_000_000_000.0; // Convert to SOL
            } else {
                metrics.failed_loans += 1;
            }
            metrics.total_opportunities += 1;
        }

        // Publish result to DragonflyDB for orchestrator
        self.publish_save_result(&result, token_mint, execution_time).await?;

        Ok(result)
    }

    /// Publish Save flash loan result to DragonflyDB
    async fn publish_save_result(
        &self,
        result: &SaveFlashLoanResult,
        token_mint: &str,
        execution_time: Duration,
    ) -> Result<()> {
        let event = serde_json::json!({
            "event_type": "save_flash_loan_result",
            "token_mint": token_mint,
            "success": result.success,
            "transaction_id": result.transaction_id,
            "execution_time_ms": execution_time.as_millis(),
            "actual_amount_out": result.actual_amount_out,
            "fees_paid": result.fees_paid,
            "error_message": result.error_message,
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "protocol": "save"
        });

        if let Ok(mut conn) = self.redis_client.get().await {
            let _: () = conn.publish("save_flash_loan_results", event.to_string()).await
                .unwrap_or_else(|e| {
                    warn!("Failed to publish Save flash loan result to Redis: {}", e);
                });
        }

        Ok(())
    }

    /// Validate token for Save flash loan sniper criteria
    pub async fn validate_save_sniper_criteria(
        &self,
        token_data: &serde_json::Value,
    ) -> Result<bool> {
        let save_config = SaveFlashLoanConfig::default();
        let rpc_client = Arc::new(solana_client::rpc_client::RpcClient::new(
            std::env::var("SOLANA_RPC_URL")
                .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string())
        ));

        let save_engine = SaveFlashLoanEngine::new(save_config, rpc_client);

        save_engine.validate_sniper_criteria(token_data).await
            .map_err(|e| anyhow!("Save sniper validation failed: {}", e))
    }

    /// Calculate optimal Save flash loan amount
    pub async fn calculate_save_optimal_amount(
        &self,
        available_liquidity: u64,
        token_data: &serde_json::Value,
    ) -> u64 {
        let save_config = SaveFlashLoanConfig::default();
        let rpc_client = Arc::new(solana_client::rpc_client::RpcClient::new(
            std::env::var("SOLANA_RPC_URL")
                .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string())
        ));

        let save_engine = SaveFlashLoanEngine::new(save_config, rpc_client);
        save_engine.calculate_optimal_amount(available_liquidity, token_data)
    }

    /// Subscribe to DragonflyDB for orchestrator commands
    async fn start_dragonfly_subscriber(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let rpc_router = self.rpc_router.clone();
        let config = self.config.clone();

        let handle = tokio::spawn(async move {
            let redis_url = std::env::var("REDIS_URL")
                .unwrap_or_else(|_| "redis://localhost:6379".to_string());

            let client = redis::Client::open(redis_url).await
                .map_err(|e| anyhow!("Failed to connect to Redis: {}", e))?;

            // Subscribe to orchestrator commands
            let mut pubsub = client.get_async_pubsub().await
                .map_err(|e| anyhow!("Failed to create pubsub: {}", e))?;

            pubsub.subscribe("orchestrator_commands").await
                .map_err(|e| anyhow!("Failed to subscribe to orchestrator_commands: {}", e))?;

            info!("Subscribed to DragonflyDB orchestrator_commands channel");

            let mut stream = pubsub.on_message();
            while let Some(msg) = stream.next().await {
                if let Ok(content) = msg.get_payload() {
                    match serde_json::from_str::<serde_json::Value>(&content) {
                        Ok(command) => {
                            debug!("Received orchestrator command: {:?}", command);

                            // Process command
                            if let Err(e) = self.process_orchestrator_command(command, &rpc_router, &config).await {
                                error!("Error processing orchestrator command: {}", e);
                            }
                        }
                        Err(e) => {
                            error!("Failed to parse orchestrator command: {}", e);
                        }
                    }
                }
            }

            Ok(())
        });

        Ok(handle)
    }

    /// Process orchestrator command from DragonflyDB
    async fn process_orchestrator_command(
        &self,
        command: serde_json::Value,
        rpc_router: &Arc<RpcRouter>,
        config: &FlashLoanCoordinatorConfig,
    ) -> Result<()> {
        let command_type = command.get("command_type")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown");

        match command_type {
            "execute_arbitrage" => {
                // Handle arbitrage execution command
                if let (Some(opportunity_id), Some(allocated_capital), Some(flash_loan_amount)) = (
                    command.get("opportunity_id").and_then(|v| v.as_str()),
                    command.get("allocated_capital").and_then(|v| v.as_f64()),
                    command.get("flash_loan_amount").and_then(|v| v.as_f64())
                ) {
                    info!("Processing arbitrage command: opportunity_id={}, capital={}", opportunity_id, allocated_capital);
                    // In production, this would trigger the actual arbitrage execution
                }
            }
            "execute_snipe" => {
                // Handle snipe execution command
                if let (Some(token_mint), Some(amount), Some(flash_loan_amount)) = (
                    command.get("token_mint").and_then(|v| v.as_str()),
                    command.get("amount").and_then(|v| v.as_f64()),
                    command.get("flash_loan_amount").and_then(|v| v.as_f64())
                ) {
                    info!("Processing snipe command: token={}, amount={}", token_mint, amount);
                    // In production, this would trigger the actual snipe execution
                }
            }
            "get_status" => {
                // Handle status query
                let metrics = self.get_metrics().await;
                let status = serde_json::json!({
                    "active_loans": metrics.current_active_loans,
                    "total_opportunities": metrics.total_opportunities,
                    "successful_loans": metrics.successful_loans,
                    "failed_loans": metrics.failed_loans,
                    "total_profit": metrics.total_profit
                });

                // Publish status back to DragonflyDB
                if let Ok(mut conn) = self.redis_client.get().await {
                    let _: () = conn.publish("flash_loan_status", status.to_string()).await.unwrap_or_default();
                }
            }
            _ => {
                warn!("Unknown command type: {}", command_type);
            }
        }

        Ok(())
    }

    /// Simulate transaction before execution
    pub async fn simulate_transaction(
        &self,
        transaction: &solana_sdk::transaction::Transaction,
    ) -> Result<SimulationResult> {
        let client = reqwest::Client::new();
        let rpc_url = std::env::var("SOLANA_RPC_URL")
            .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string());

        let simulation_request = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "simulateTransaction",
            "params": [
                bs58::encode(transaction.serialize().unwrap()),
                {
                    "encoding": "base64",
                    "commitment": "processed",
                    "replaceRecentBlockhash": true
                }
            ]
        });

        let response = timeout(
            Duration::from_millis(200),
            client.post(&rpc_url).json(&simulation_request).send(),
        )
        .await
        .context("Simulation request timeout")?;

        let result: serde_json::Value = response.json().await
            .context("Failed to parse simulation response")?;

        if let Some(error) = result.get("error") {
            return Ok(SimulationResult {
                success: false,
                error_message: Some(error.to_string()),
                logs: None,
                units_consumed: 0,
            });
        }

        if let Some(value) = result.get("result") {
            let logs = value.get("logs").and_then(|l| l.as_array());
            let units_consumed = value.get("units-consumed")
                .and_then(|u| u.as_u64())
                .unwrap_or(0);

            // Check for transaction failure
            if let Some(err) = value.get("err") {
                return Ok(SimulationResult {
                    success: false,
                    error_message: Some(format!("Transaction would fail: {}", err)),
                    logs: logs.cloned(),
                    units_consumed,
                });
            }

            return Ok(SimulationResult {
                success: true,
                error_message: None,
                logs: logs.cloned(),
                units_consumed,
            });
        }

        Ok(SimulationResult {
            success: false,
            error_message: Some("Invalid simulation response"),
            logs: None,
            units_consumed: 0,
        })
    }
}

/// Simulation result for transaction dry-run
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SimulationResult {
    pub success: bool,
    pub error_message: Option<String>,
    pub logs: Option<Vec<serde_json::Value>>,
    pub units_consumed: u64,
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