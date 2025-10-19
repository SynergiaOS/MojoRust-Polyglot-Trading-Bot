use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use solana_client::nonblocking::rpc_client::RpcClient;
use solana_sdk::compute_budget::ComputeBudgetInstruction;
use solana_sdk::instruction::Instruction;
use solana_sdk::message::Message;
use solana_sdk::transaction::{Transaction, VersionedTransaction};
use solana_sdk::{commitment_config::CommitmentConfig, pubkey::Pubkey, signature::Keypair};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, RwLock};
use tokio::time::timeout;
use serde::{Deserialize, Serialize};

use crate::arbitrage::cross_exchange::{ArbitrageOpportunity, CrossExchangeArbitrage};
use crate::arbitrage::flash_loan::{FlashLoanExecutor, FlashLoanProvider, FlashLoanRequest};
use crate::arbitrage::triangular::TriangularArbitrage;
use crate::data_consumer::PriorityLevel;
use crate::execution::rpc_router::{RpcRouter, RpcRequest, UrgencyLevel, TransactionRequest};
use crate::execution::solend_flash_loan::SolendFlashLoanEngine;
use crate::execution::flash_loan::{FlashLoanRouter, FlashLoanProtocol, FlashLoanManager};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionConfig {
    pub max_concurrent_transactions: usize,
    pub max_retries: usize,
    pub retry_delay: Duration,
    pub timeout_duration: Duration,
    pub profit_threshold: f64,
    pub max_slippage: f64,
    pub gas_limit_multiplier: f64,
    pub simulation_before_execution: bool,
}

impl Default for ExecutionConfig {
    fn default() -> Self {
        Self {
            max_concurrent_transactions: 10,
            max_retries: 3,
            retry_delay: Duration::from_millis(100),
            timeout_duration: Duration::from_secs(30),
            profit_threshold: 0.001, // 0.1%
            max_slippage: 0.05,      // 5%
            gas_limit_multiplier: 1.2,
            simulation_before_execution: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionMetrics {
    pub total_executed: u64,
    pub successful_executions: u64,
    pub failed_executions: u64,
    pub total_profit: f64,
    pub total_gas_used: u64,
    pub average_execution_time: Duration,
    pub total_gas_cost: f64,
    pub retry_rate: f64,
    pub slippage_average: f64,
}

impl Default for ExecutionMetrics {
    fn default() -> Self {
        Self {
            total_executed: 0,
            successful_executions: 0,
            failed_executions: 0,
            total_profit: 0.0,
            total_gas_used: 0,
            average_execution_time: Duration::from_secs(0),
            total_gas_cost: 0.0,
            retry_rate: 0.0,
            slippage_average: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionResult {
    pub transaction_id: String,
    pub signature: String,
    pub success: bool,
    pub profit: f64,
    pub gas_used: u64,
    pub gas_cost: f64,
    pub execution_time: Duration,
    pub slippage: f64,
    pub error: Option<String>,
    pub slot: u64,
    pub confirmation_time: Duration,
}

#[derive(Debug, Clone)]
pub enum ExecutionRequest {
    Arbitrage {
        opportunity: ArbitrageOpportunity,
        urgency: UrgencyLevel,
        callback: mpsc::Sender<ExecutionResult>,
    },
    FlashLoanArbitrage {
        request: FlashLoanRequest,
        urgency: UrgencyLevel,
        callback: mpsc::Sender<ExecutionResult>,
    },
    TriangularArbitrage {
        cycle: Vec<String>,
        profit: f64,
        urgency: UrgencyLevel,
        callback: mpsc::Sender<ExecutionResult>,
    },
}

pub struct ExecutionEngine {
    config: ExecutionConfig,
    rpc_router: Arc<RpcRouter>,
    keypair: Arc<Keypair>,
    metrics: Arc<RwLock<ExecutionMetrics>>,

    // Arbitrage components
    cross_exchange: Arc<CrossExchangeArbitrage>,
    flash_loan_executor: Arc<FlashLoanExecutor>,
    triangular_arbitrage: Arc<TriangularArbitrage>,

    // Flash loan components
    solend_flash_loan: Arc<SolendFlashLoanEngine>,
    flash_loan_router: Arc<FlashLoanRouter>,

    // Execution management
    execution_queue: mpsc::UnboundedReceiver<ExecutionRequest>,
    active_executions: Arc<RwLock<HashMap<String, Instant>>>,
    pending_confirmations: Arc<RwLock<HashMap<String, ExecutionRequest>>>,

    // Performance tracking
    start_time: Instant,
    recent_profits: Arc<RwLock<Vec<f64>>>,
    recent_errors: Arc<RwLock<Vec<String>>>,
}

impl ExecutionEngine {
    pub fn new(
        config: ExecutionConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        cross_exchange: Arc<CrossExchangeArbitrage>,
        flash_loan_executor: Arc<FlashLoanExecutor>,
        triangular_arbitrage: Arc<TriangularArbitrage>,
        solend_flash_loan: Option<Arc<SolendFlashLoanEngine>>,
    ) -> (Self, mpsc::UnboundedSender<ExecutionRequest>) {
        let (tx, rx) = mpsc::unbounded_channel();

        // Initialize flash loan router
        let flash_loan_router = Arc::new(FlashLoanRouter::new(rpc_router.clone()));

        // Initialize Solend flash loan if provided
        let solend_engine = solend_flash_loan.unwrap_or_else(|| {
            Arc::new(SolendFlashLoanEngine::new(
                crate::execution::solend_flash_loan::SolendFlashLoanConfig::default(),
                rpc_router.clone(),
            ))
        });

        let engine = Self {
            config,
            rpc_router,
            keypair,
            metrics: Arc::new(RwLock::new(ExecutionMetrics::default())),
            cross_exchange,
            flash_loan_executor,
            triangular_arbitrage,
            solend_flash_loan: solend_engine,
            flash_loan_router,
            execution_queue: rx,
            active_executions: Arc::new(RwLock::new(HashMap::new())),
            pending_confirmations: Arc::new(RwLock::new(HashMap::new())),
            start_time: Instant::now(),
            recent_profits: Arc::new(RwLock::new(Vec::new())),
            recent_errors: Arc::new(RwLock::new(Vec::new())),
        };

        (engine, tx)
    }

    pub async fn start(&mut self) -> Result<()> {
        info!("Starting ExecutionEngine with RPCRouter integration");

        // Start the main execution loop
        let mut handles = vec![];

        // Main execution processor
        let engine_handle = {
            let metrics = self.metrics.clone();
            let rpc_router = self.rpc_router.clone();
            let cross_exchange = self.cross_exchange.clone();
            let flash_loan_executor = self.flash_loan_executor.clone();
            let triangular_arbitrage = self.triangular_arbitrage.clone();
            let active_executions = self.active_executions.clone();
            let pending_confirmations = self.pending_confirmations.clone();
            let recent_profits = self.recent_profits.clone();
            let recent_errors = self.recent_errors.clone();
            let config = self.config.clone();
            let keypair = self.keypair.clone();

            let mut execution_queue = std::mem::replace(&mut self.execution_queue, mpsc::unbounded_channel().1);

            tokio::spawn(async move {
                Self::execution_loop(
                    execution_queue,
                    config,
                    rpc_router,
                    keypair,
                    metrics,
                    cross_exchange,
                    flash_loan_executor,
                    triangular_arbitrage,
                    active_executions,
                    pending_confirmations,
                    recent_profits,
                    recent_errors,
                ).await
            })
        };

        handles.push(engine_handle);

        // Metrics collector
        let metrics_handle = self.start_metrics_collection().await?;
        handles.push(metrics_handle);

        // Transaction confirmation monitor
        let confirmation_handle = self.start_confirmation_monitor().await?;
        handles.push(confirmation_handle);

        info!("ExecutionEngine started with {} concurrent processors", handles.len());

        // Wait for all tasks
        for handle in handles {
            handle.await??;
        }

        Ok(())
    }

    async fn execution_loop(
        mut queue: mpsc::UnboundedReceiver<ExecutionRequest>,
        config: ExecutionConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        metrics: Arc<RwLock<ExecutionMetrics>>,
        cross_exchange: Arc<CrossExchangeArbitrage>,
        flash_loan_executor: Arc<FlashLoanExecutor>,
        triangular_arbitrage: Arc<TriangularArbitrage>,
        active_executions: Arc<RwLock<HashMap<String, Instant>>>,
        pending_confirmations: Arc<RwLock<HashMap<String, ExecutionRequest>>>,
        recent_profits: Arc<RwLock<Vec<f64>>>,
        recent_errors: Arc<RwLock<Vec<String>>>,
    ) -> Result<()> {
        let mut current_executions = 0;

        while let Some(request) = queue.recv().await {
            // Check execution limit
            if current_executions >= config.max_concurrent_transactions {
                debug!("Execution queue full, skipping request");
                continue;
            }

            // Generate unique transaction ID
            let transaction_id = format!("exec_{}", SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos());

            // Track active execution
            {
                let mut active = active_executions.write().await;
                active.insert(transaction_id.clone(), Instant::now());
            }
            current_executions += 1;

            let request_type = match &request {
                ExecutionRequest::Arbitrage { .. } => "Arbitrage",
                ExecutionRequest::FlashLoanArbitrage { .. } => "FlashLoanArbitrage",
                ExecutionRequest::TriangularArbitrage { .. } => "TriangularArbitrage",
            };

            debug!("Processing {} execution: {}", request_type, transaction_id);

            // Spawn execution task
            let result = Self::execute_request(
                request,
                transaction_id.clone(),
                config.clone(),
                rpc_router.clone(),
                keypair.clone(),
                metrics.clone(),
                cross_exchange.clone(),
                flash_loan_executor.clone(),
                triangular_arbitrage.clone(),
                pending_confirmations.clone(),
                recent_profits.clone(),
                recent_errors.clone(),
            );

            tokio::spawn(async move {
                match result.await {
                    Ok(result) => {
                        debug!("Execution {} completed: {}", transaction_id, result.signature);
                    }
                    Err(e) => {
                        error!("Execution {} failed: {}", transaction_id, e);
                    }
                }

                // Remove from active executions
                {
                    let mut active = active_executions.write().await;
                    active.remove(&transaction_id);
                }
            });
        }

        Ok(())
    }

    async fn execute_request(
        request: ExecutionRequest,
        transaction_id: String,
        config: ExecutionConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        metrics: Arc<RwLock<ExecutionMetrics>>,
        cross_exchange: Arc<CrossExchangeArbitrage>,
        flash_loan_executor: Arc<FlashLoanExecutor>,
        triangular_arbitrage: Arc<TriangularArbitrage>,
        pending_confirmations: Arc<RwLock<HashMap<String, ExecutionRequest>>>,
        recent_profits: Arc<RwLock<Vec<f64>>>,
        recent_errors: Arc<RwLock<Vec<String>>>,
    ) -> Result<ExecutionResult> {
        let start_time = Instant::now();

        let result = match request {
            ExecutionRequest::Arbitrage { opportunity, urgency, callback } => {
                Self::execute_arbitrage(
                    opportunity,
                    urgency,
                    transaction_id.clone(),
                    config,
                    rpc_router,
                    keypair,
                    metrics,
                    cross_exchange,
                    callback,
                ).await
            }
            ExecutionRequest::FlashLoanArbitrage { request, urgency, callback } => {
                Self::execute_flash_loan_arbitrage(
                    request,
                    urgency,
                    transaction_id.clone(),
                    config,
                    rpc_router,
                    keypair,
                    metrics,
                    flash_loan_executor,
                    callback,
                ).await
            }
            ExecutionRequest::TriangularArbitrage { cycle, profit, urgency, callback } => {
                Self::execute_triangular_arbitrage(
                    cycle,
                    profit,
                    urgency,
                    transaction_id.clone(),
                    config,
                    rpc_router,
                    keypair,
                    metrics,
                    triangular_arbitrage,
                    callback,
                ).await
            }
        };

        let execution_time = start_time.elapsed();

        match result {
            Ok(mut exec_result) => {
                exec_result.execution_time = execution_time;

                // Update metrics
                {
                    let mut metrics_guard = metrics.write().await;
                    metrics_guard.total_executed += 1;
                    metrics_guard.successful_executions += 1;
                    metrics_guard.total_profit += exec_result.profit;
                    metrics_guard.total_gas_used += exec_result.gas_used;
                    metrics_guard.total_gas_cost += exec_result.gas_cost;

                    // Update average execution time
                    let total_time = metrics_guard.average_execution_time * (metrics_guard.total_executed - 1) as u32 + execution_time;
                    metrics_guard.average_execution_time = total_time / metrics_guard.total_executed as u32;
                }

                // Track recent profits
                {
                    let mut profits = recent_profits.write().await;
                    profits.push(exec_result.profit);
                    if profits.len() > 100 {
                        profits.remove(0);
                    }
                }

                info!("Execution {} succeeded: profit={}, gas={}",
                      transaction_id, exec_result.profit, exec_result.gas_used);

                Ok(exec_result)
            }
            Err(e) => {
                let error_msg = e.to_string();

                // Update metrics
                {
                    let mut metrics_guard = metrics.write().await;
                    metrics_guard.total_executed += 1;
                    metrics_guard.failed_executions += 1;
                }

                // Track recent errors
                {
                    let mut errors = recent_errors.write().await;
                    errors.push(error_msg.clone());
                    if errors.len() > 100 {
                        errors.remove(0);
                    }
                }

                error!("Execution {} failed: {}", transaction_id, error_msg);

                Ok(ExecutionResult {
                    transaction_id,
                    signature: String::new(),
                    success: false,
                    profit: 0.0,
                    gas_used: 0,
                    gas_cost: 0.0,
                    execution_time,
                    slippage: 0.0,
                    error: Some(error_msg),
                    slot: 0,
                    confirmation_time: Duration::from_secs(0),
                })
            }
        }
    }

    async fn execute_arbitrage(
        opportunity: ArbitrageOpportunity,
        urgency: UrgencyLevel,
        transaction_id: String,
        config: ExecutionConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        metrics: Arc<RwLock<ExecutionMetrics>>,
        cross_exchange: Arc<CrossExchangeArbitrage>,
        callback: mpsc::Sender<ExecutionResult>,
    ) -> Result<ExecutionResult> {
        debug!("Executing arbitrage opportunity: profit={}", opportunity.profit);

        // Validate profit threshold
        if opportunity.profit < config.profit_threshold {
            return Err(anyhow!("Profit {} below threshold {}", opportunity.profit, config.profit_threshold));
        }

        // Build transaction instructions
        let instructions = cross_exchange.build_arbitrage_instructions(&opportunity).await?;

        // Create and send transaction through RPCRouter
        let signature = Self::send_transaction_via_router(
            instructions,
            urgency,
            transaction_id.clone(),
            rpc_router,
            keypair,
            config.clone(),
        ).await?;

        // Wait for confirmation
        let confirmation_result = Self::wait_for_confirmation(
            &signature,
            config.timeout_duration,
            rpc_router.clone(),
        ).await?;

        let result = ExecutionResult {
            transaction_id,
            signature,
            success: true,
            profit: opportunity.profit,
            gas_used: confirmation_result.gas_used,
            gas_cost: confirmation_result.gas_cost,
            execution_time: Duration::from_secs(0), // Will be set by caller
            slippage: opportunity.slippage,
            error: None,
            slot: confirmation_result.slot,
            confirmation_time: confirmation_result.confirmation_time,
        };

        // Send result to callback
        if let Err(_) = callback.send(result.clone()).await {
            warn!("Failed to send arbitrage result to callback");
        }

        Ok(result)
    }

    async fn execute_flash_loan_arbitrage(
        request: FlashLoanRequest,
        urgency: UrgencyLevel,
        transaction_id: String,
        config: ExecutionConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        metrics: Arc<RwLock<ExecutionMetrics>>,
        flash_loan_executor: Arc<FlashLoanExecutor>,
        callback: mpsc::Sender<ExecutionResult>,
    ) -> Result<ExecutionResult> {
        debug!("Executing flash loan arbitrage: amount={}", request.amount);

        // Execute flash loan
        let signature = flash_loan_executor.execute_flash_loan(request.clone(), keypair.clone()).await?;

        // Wait for confirmation
        let confirmation_result = Self::wait_for_confirmation(
            &signature,
            config.timeout_duration,
            rpc_router.clone(),
        ).await?;

        // Calculate actual profit (would be returned from flash loan execution)
        let actual_profit = request.expected_profit; // Simplified

        let result = ExecutionResult {
            transaction_id,
            signature,
            success: true,
            profit: actual_profit,
            gas_used: confirmation_result.gas_used,
            gas_cost: confirmation_result.gas_cost,
            execution_time: Duration::from_secs(0), // Will be set by caller
            slippage: 0.0, // Flash loans have no slippage
            error: None,
            slot: confirmation_result.slot,
            confirmation_time: confirmation_result.confirmation_time,
        };

        // Send result to callback
        if let Err(_) = callback.send(result.clone()).await {
            warn!("Failed to send flash loan result to callback");
        }

        Ok(result)
    }

    async fn execute_triangular_arbitrage(
        cycle: Vec<String>,
        profit: f64,
        urgency: UrgencyLevel,
        transaction_id: String,
        config: ExecutionConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        metrics: Arc<RwLock<ExecutionMetrics>>,
        triangular_arbitrage: Arc<TriangularArbitrage>,
        callback: mpsc::Sender<ExecutionResult>,
    ) -> Result<ExecutionResult> {
        debug!("Executing triangular arbitrage: cycle={:?}, profit={}", cycle, profit);

        // Validate profit threshold
        if profit < config.profit_threshold {
            return Err(anyhow!("Profit {} below threshold {}", profit, config.profit_threshold));
        }

        // Build transaction instructions
        let instructions = triangular_arbitrage.build_triangular_instructions(&cycle).await?;

        // Create and send transaction through RPCRouter
        let signature = Self::send_transaction_via_router(
            instructions,
            urgency,
            transaction_id.clone(),
            rpc_router,
            keypair,
            config.clone(),
        ).await?;

        // Wait for confirmation
        let confirmation_result = Self::wait_for_confirmation(
            &signature,
            config.timeout_duration,
            rpc_router.clone(),
        ).await?;

        let result = ExecutionResult {
            transaction_id,
            signature,
            success: true,
            profit,
            gas_used: confirmation_result.gas_used,
            gas_cost: confirmation_result.gas_cost,
            execution_time: Duration::from_secs(0), // Will be set by caller
            slippage: 0.02, // Estimated triangular arbitrage slippage
            error: None,
            slot: confirmation_result.slot,
            confirmation_time: confirmation_result.confirmation_time,
        };

        // Send result to callback
        if let Err(_) = callback.send(result.clone()).await {
            warn!("Failed to send triangular arbitrage result to callback");
        }

        Ok(result)
    }

    async fn send_transaction_via_router(
        instructions: Vec<Instruction>,
        urgency: UrgencyLevel,
        transaction_id: String,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        config: ExecutionConfig,
    ) -> Result<String> {
        // Create transaction
        let recent_blockhash = rpc_router.get_latest_blockhash().await?;
        let message = Message::new(&instructions, Some(&keypair.pubkey()));
        let mut transaction = Transaction::new_unsigned(&message);
        transaction.partial_sign(&[&*keypair], recent_blockhash);

        // Create transaction request
        let tx_request = TransactionRequest {
            transaction: transaction.clone(),
            urgency,
            skip_preflight: false,
            max_retries: config.max_retries as u8,
            confirmation_level: CommitmentConfig::confirmed(),
        };

        // Send through RPCRouter
        let signature = rpc_router.send_transaction(tx_request).await?;

        Ok(signature)
    }

    async fn wait_for_confirmation(
        signature: &str,
        timeout_duration: Duration,
        rpc_router: Arc<RpcRouter>,
    ) -> Result<ConfirmationResult> {
        let start_time = Instant::now();

        let confirmation = timeout(timeout_duration, async {
            loop {
                match rpc_router.get_signature_status(signature).await? {
                    Some(status) => {
                        if status.err.is_none() {
                            return Ok(ConfirmationResult {
                                slot: status.slot.unwrap_or(0),
                                gas_used: status.confirmations.as_ref()
                                    .and_then(|c| c.compute_units_consumed)
                                    .unwrap_or(0),
                                gas_cost: status.confirmations.as_ref()
                                    .and_then(|c| c.total_fee)
                                    .map(|f| f as f64 / 1_000_000_000.0) // Convert lamports to SOL
                                    .unwrap_or(0.0),
                                confirmation_time: start_time.elapsed(),
                            });
                        } else {
                            return Err(anyhow!("Transaction failed: {:?}", status.err));
                        }
                    }
                    None => {
                        tokio::time::sleep(Duration::from_millis(100)).await;
                    }
                }
            }
        }).await??;

        Ok(confirmation)
    }

    async fn start_metrics_collection(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let metrics = self.metrics.clone();
        let recent_profits = self.recent_profits.clone();
        let recent_errors = self.recent_errors.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(10));

            loop {
                interval.tick().await;

                let metrics_guard = metrics.read().await;
                let profits_guard = recent_profits.read().await;
                let errors_guard = recent_errors.read().await;

                info!(
                    "Execution Metrics: total={}, success_rate={:.2}%, avg_profit={:.6}, avg_exec_time={:?}",
                    metrics_guard.total_executed,
                    if metrics_guard.total_executed > 0 {
                        (metrics_guard.successful_executions as f64 / metrics_guard.total_executed as f64) * 100.0
                    } else { 0.0 },
                    if !profits_guard.is_empty() {
                        profits_guard.iter().sum::<f64>() / profits_guard.len() as f64
                    } else { 0.0 },
                    metrics_guard.average_execution_time
                );

                // Log recent errors if any
                if !errors_guard.is_empty() {
                    let recent_errors: Vec<_> = errors_guard.iter().rev().take(5).cloned().collect();
                    for error in recent_errors {
                        warn!("Recent execution error: {}", error);
                    }
                }
            }
        });

        Ok(handle)
    }

    async fn start_confirmation_monitor(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let pending_confirmations = self.pending_confirmations.clone();
        let active_executions = self.active_executions.clone();
        let rpc_router = self.rpc_router.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(5));

            loop {
                interval.tick().await;

                // Clean up old executions
                {
                    let mut active = active_executions.write().await;
                    let now = Instant::now();
                    active.retain(|_, start_time| now.duration_since(*start_time) < Duration::from_secs(60));
                }

                // Process pending confirmations
                {
                    let mut pending = pending_confirmations.write().await;
                    // In a real implementation, this would check for stuck transactions
                    if pending.len() > 100 {
                        warn!("High number of pending confirmations: {}", pending.len());
                    }
                }
            }
        });

        Ok(handle)
    }

    pub async fn get_metrics(&self) -> ExecutionMetrics {
        self.metrics.read().await.clone()
    }

    pub async fn get_recent_performance(&self) -> (Vec<f64>, Vec<String>) {
        let profits = self.recent_profits.read().await.clone();
        let errors = self.recent_errors.read().await.clone();
        (profits, errors)
    }

    pub async fn get_active_executions(&self) -> usize {
        self.active_executions.read().await.len()
    }

    /// Execute Solend flash loan sniper trade
    pub async fn execute_solend_flash_loan_snipe(
        &self,
        token_mint: &Pubkey,
        amount: u64,
        slippage_bps: u64,
    ) -> Result<crate::execution::flash_loan::FlashLoanResult> {
        info!("Executing Solend flash loan snipe: {} lamports for token {}", amount, token_mint);

        let result = self.solend_flash_loan.execute_flash_loan_snipe(
            &self.keypair,
            token_mint,
            amount,
            slippage_bps,
        ).await;

        match &result {
            Ok(flash_result) => {
                if flash_result.success {
                    info!("Solend flash loan snipe succeeded: {}", flash_result.transaction_id);
                } else {
                    warn!("Solend flash loan snipe failed: {:?}", flash_result.error_message);
                }
            }
            Err(e) => {
                error!("Solend flash loan snipe error: {}", e);
            }
        }

        result
    }

    /// Execute flash loan using optimal provider (Save/Solend/Mango V4)
    pub async fn execute_optimal_flash_loan(
        &self,
        token_mint: &Pubkey,
        amount: u64,
        slippage_bps: u64,
    ) -> Result<crate::execution::flash_loan::FlashLoanResult> {
        info!("Executing optimal flash loan: {} lamports for token {}", amount, token_mint);

        // Create flash loan request
        let request = crate::execution::flash_loan::FlashLoanRequest {
            token_mint: *token_mint,
            amount,
            target_amount: 0,
            slippage_bps,
            urgency_level: "high".to_string(),
        };

        // Route through flash loan router for optimal provider selection
        let result = self.flash_loan_router.route_flash_loan(&self.keypair, request).await;

        match &result {
            Ok(flash_result) => {
                if flash_result.success {
                    info!("Optimal flash loan succeeded: {}", flash_result.transaction_id);
                } else {
                    warn!("Optimal flash loan failed: {:?}", flash_result.error_message);
                }
            }
            Err(e) => {
                error!("Optimal flash loan error: {}", e);
            }
        }

        result
    }

    /// Get flash loan performance metrics
    pub async fn get_flash_loan_metrics(&self) -> crate::execution::flash_loan::FlashLoanMetrics {
        self.flash_loan_router.get_performance_metrics()
    }

    /// Check if flash loan is available for given amount
    pub fn is_flash_loan_available(&self, amount: u64) -> bool {
        self.flash_loan_router.is_flash_loan_available(amount)
    }

    /// Get estimated fees for flash loan
    pub async fn estimate_flash_loan_fees(&self, amount: u64, protocol: Option<FlashLoanProtocol>) -> u64 {
        self.flash_loan_router.estimate_fees(amount, protocol)
    }

    /// Get optimal flash loan protocol for given amount
    pub async fn get_optimal_flash_loan_protocol(&self, amount: u64) -> FlashLoanProtocol {
        self.flash_loan_router.get_optimal_protocol(amount)
    }

    /// Get Solend market data for token
    pub async fn get_solend_market_data(&self, token_mint: &Pubkey) -> Result<(Pubkey, Pubkey), Box<dyn std::error::Error>> {
        self.solend_flash_loan.get_solend_market_data(token_mint).await
    }
}

#[derive(Debug, Clone)]
pub struct ConfirmationResult {
    pub slot: u64,
    pub gas_used: u64,
    pub gas_cost: f64,
    pub confirmation_time: Duration,
}