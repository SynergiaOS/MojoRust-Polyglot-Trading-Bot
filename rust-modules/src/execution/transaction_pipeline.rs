use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use solana_client::nonblocking::rpc_client::RpcClient;
use solana_sdk::compute_budget::ComputeBudgetInstruction;
use solana_sdk::instruction::Instruction;
use solana_sdk::message::Message;
use solana_sdk::transaction::{Transaction, VersionedTransaction};
use solana_sdk::{commitment_config::CommitmentConfig, pubkey::Pubkey, signature::Keypair};
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{mpsc, RwLock, Semaphore};
use tokio::time::timeout;
use serde::{Deserialize, Serialize};

use crate::data_consumer::PriorityLevel;
use crate::execution::rpc_router::{RpcRouter, RpcRequest, UrgencyLevel, TransactionRequest, PriorityFeeCalculator};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionPipelineConfig {
    pub max_queue_size: usize,
    pub max_concurrent_senders: usize,
    pub batch_size: usize,
    pub batch_timeout: Duration,
    pub retry_attempts: u8,
    pub retry_delay: Duration,
    pub confirmation_timeout: Duration,
    pub simulation_timeout: Duration,
    pub priority_fee_multipliers: HashMap<UrgencyLevel, f64>,
}

impl Default for TransactionPipelineConfig {
    fn default() -> Self {
        let mut priority_fee_multipliers = HashMap::new();
        priority_fee_multipliers.insert(UrgencyLevel::Critical, 10.0);
        priority_fee_multipliers.insert(UrgencyLevel::High, 5.0);
        priority_fee_multipliers.insert(UrgencyLevel::Normal, 2.0);
        priority_fee_multipliers.insert(UrgencyLevel::Low, 1.0);

        Self {
            max_queue_size: 1000,
            max_concurrent_senders: 5,
            batch_size: 10,
            batch_timeout: Duration::from_millis(50),
            retry_attempts: 3,
            retry_delay: Duration::from_millis(100),
            confirmation_timeout: Duration::from_secs(30),
            simulation_timeout: Duration::from_secs(5),
            priority_fee_multipliers,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueuedTransaction {
    pub id: String,
    pub instructions: Vec<Instruction>,
    pub urgency: UrgencyLevel,
    pub compute_limit: Option<u32>,
    pub priority_fee: Option<u64>,
    pub skip_preflight: bool,
    pub created_at: Instant,
    pub retry_count: u8,
    pub max_retries: u8,
    pub callback: mpsc::Sender<TransactionResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionResult {
    pub transaction_id: String,
    pub signature: String,
    pub success: bool,
    pub error: Option<String>,
    pub slot: u64,
    pub gas_used: u64,
    pub gas_cost: f64,
    pub priority_fee_paid: u64,
    pub execution_time: Duration,
    pub confirmation_time: Duration,
    pub total_time: Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineMetrics {
    pub total_queued: u64,
    pub total_sent: u64,
    pub total_confirmed: u64,
    pub total_failed: u64,
    pub queue_depth: usize,
    pub average_queue_time: Duration,
    pub average_send_time: Duration,
    pub average_confirmation_time: Duration,
    pub success_rate: f64,
    pub priority_fee_stats: PriorityFeeStats,
    pub urgency_distribution: HashMap<UrgencyLevel, u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriorityFeeStats {
    pub total_priority_fees_paid: u64,
    pub average_priority_fee: u64,
    pub max_priority_fee: u64,
    pub min_priority_fee: u64,
    pub priority_fee_by_urgency: HashMap<UrgencyLevel, u64>,
}

impl Default for PipelineMetrics {
    fn default() -> Self {
        Self {
            total_queued: 0,
            total_sent: 0,
            total_confirmed: 0,
            total_failed: 0,
            queue_depth: 0,
            average_queue_time: Duration::from_secs(0),
            average_send_time: Duration::from_secs(0),
            average_confirmation_time: Duration::from_secs(0),
            success_rate: 0.0,
            priority_fee_stats: PriorityFeeStats::default(),
            urgency_distribution: HashMap::new(),
        }
    }
}

impl Default for PriorityFeeStats {
    fn default() -> Self {
        Self {
            total_priority_fees_paid: 0,
            average_priority_fee: 0,
            max_priority_fee: 0,
            min_priority_fee: u64::MAX,
            priority_fee_by_urgency: HashMap::new(),
        }
    }
}

pub struct TransactionPipeline {
    config: TransactionPipelineConfig,
    rpc_router: Arc<RpcRouter>,
    keypair: Arc<Keypair>,

    // Transaction management
    transaction_queue: Arc<RwLock<VecDeque<QueuedTransaction>>>,
    pending_transactions: Arc<RwLock<HashMap<String, QueuedTransaction>>>,
    transaction_semaphore: Arc<Semaphore>,

    // Metrics and monitoring
    metrics: Arc<RwLock<PipelineMetrics>>,
    priority_fee_calculator: Arc<PriorityFeeCalculator>,

    // Performance tracking
    queue_times: Arc<RwLock<VecDeque<Duration>>>,
    send_times: Arc<RwLock<VecDeque<Duration>>>,
    confirmation_times: Arc<RwLock<VecDeque<Duration>>>,

    // Communication channels
    transaction_sender: mpsc::UnboundedSender<QueuedTransaction>,
    transaction_receiver: Option<mpsc::UnboundedReceiver<QueuedTransaction>>,
    result_sender: mpsc::UnboundedSender<TransactionResult>,
}

impl TransactionPipeline {
    pub fn new(
        config: TransactionPipelineConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
        priority_fee_calculator: Arc<PriorityFeeCalculator>,
    ) -> Self {
        let (tx, rx) = mpsc::unbounded_channel();
        let (result_tx, _) = mpsc::unbounded_channel();

        Self {
            config,
            rpc_router,
            keypair,
            transaction_queue: Arc::new(RwLock::new(VecDeque::new())),
            pending_transactions: Arc::new(RwLock::new(HashMap::new())),
            transaction_semaphore: Arc::new(Semaphore::new(config.max_concurrent_senders)),
            metrics: Arc::new(RwLock::new(PipelineMetrics::default())),
            priority_fee_calculator,
            queue_times: Arc::new(RwLock::new(VecDeque::new())),
            send_times: Arc::new(RwLock::new(VecDeque::new())),
            confirmation_times: Arc::new(RwLock::new(VecDeque::new())),
            transaction_sender: tx,
            transaction_receiver: Some(rx),
            result_sender: result_tx,
        }
    }

    pub fn get_sender(&self) -> mpsc::UnboundedSender<QueuedTransaction> {
        self.transaction_sender.clone()
    }

    pub fn get_result_receiver(&self) -> mpsc::UnboundedReceiver<TransactionResult> {
        self.result_sender.subscribe()
    }

    pub async fn start(&mut self) -> Result<()> {
        info!("Starting TransactionPipeline with RPCRouter integration");

        let mut handles = vec![];

        // Transaction processor
        let processor_handle = self.start_transaction_processor().await?;
        handles.push(processor_handle);

        // Batch processor
        let batch_handle = self.start_batch_processor().await?;
        handles.push(batch_handle);

        // Confirmation monitor
        let confirmation_handle = self.start_confirmation_monitor().await?;
        handles.push(confirmation_handle);

        // Metrics collector
        let metrics_handle = self.start_metrics_collector().await?;
        handles.push(metrics_handle);

        info!("TransactionPipeline started with {} processors", handles.len());

        // Wait for all tasks
        for handle in handles {
            handle.await??;
        }

        Ok(())
    }

    pub async fn queue_transaction(
        &self,
        instructions: Vec<Instruction>,
        urgency: UrgencyLevel,
        compute_limit: Option<u32>,
        skip_preflight: bool,
        callback: mpsc::Sender<TransactionResult>,
    ) -> Result<String> {
        let transaction_id = format!("tx_{}", SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos());

        let queued_tx = QueuedTransaction {
            id: transaction_id.clone(),
            instructions,
            urgency,
            compute_limit,
            priority_fee: None, // Will be calculated during processing
            skip_preflight,
            created_at: Instant::now(),
            retry_count: 0,
            max_retries: self.config.retry_attempts,
            callback,
        };

        // Check queue size limit
        {
            let mut queue = self.transaction_queue.write().await;
            if queue.len() >= self.config.max_queue_size {
                return Err(anyhow!("Transaction queue is full"));
            }
            queue.push_back(queued_tx);
        }

        // Update metrics
        {
            let mut metrics = self.metrics.write().await;
            metrics.total_queued += 1;
            metrics.queue_depth = metrics.queue_depth.saturating_add(1);

            *metrics.urgency_distribution.entry(urgency).or_insert(0) += 1;
        }

        debug!("Transaction {} queued with urgency {:?}", transaction_id, urgency);

        Ok(transaction_id)
    }

    async fn start_transaction_processor(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let queue = self.transaction_queue.clone();
        let pending = self.pending_transactions.clone();
        let semaphore = self.transaction_semaphore.clone();
        let config = self.config.clone();
        let rpc_router = self.rpc_router.clone();
        let keypair = self.keypair.clone();
        let metrics = self.metrics.clone();
        let priority_fee_calculator = self.priority_fee_calculator.clone();
        let queue_times = self.queue_times.clone();
        let send_times = self.send_times.clone();

        let mut receiver = self.transaction_receiver.take()
            .ok_or_else(|| anyhow!("Transaction receiver already taken"))?;

        let handle = tokio::spawn(async move {
            loop {
                // Get transaction from queue
                let mut queued_tx = {
                    let mut queue_guard = queue.write().await;
                    queue_guard.pop_front()
                };

                if let Some(ref mut tx) = queued_tx {
                    // Calculate priority fee based on urgency
                    tx.priority_fee = priority_fee_calculator.calculate_priority_fee(
                        &tx.urgency,
                        tx.compute_limit.unwrap_or(1_000_000),
                    ).await;

                    // Update queue time
                    let queue_time = tx.created_at.elapsed();
                    {
                        let mut times = queue_times.write().await;
                        times.push_back(queue_time);
                        if times.len() > 1000 {
                            times.pop_front();
                        }
                    }

                    // Add to pending
                    {
                        let mut pending_guard = pending.write().await;
                        pending_guard.insert(tx.id.clone(), tx.clone());
                    }

                    // Acquire semaphore for concurrent sending
                    let _permit = semaphore.acquire().await?;

                    // Process transaction
                    let process_start = Instant::now();
                    let result = Self::process_transaction(
                        tx.clone(),
                        config.clone(),
                        rpc_router.clone(),
                        keypair.clone(),
                    ).await;
                    let send_time = process_start.elapsed();

                    // Update send time
                    {
                        let mut times = send_times.write().await;
                        times.push_back(send_time);
                        if times.len() > 1000 {
                            times.pop_front();
                        }
                    }

                    // Handle result
                    match result {
                        Ok(signature) => {
                            info!("Transaction {} sent: {}", tx.id, signature);

                            // Update metrics
                            {
                                let mut metrics_guard = metrics.write().await;
                                metrics_guard.total_sent += 1;
                                metrics_guard.queue_depth = metrics_guard.queue_depth.saturating_sub(1);
                            }
                        }
                        Err(e) => {
                            error!("Transaction {} failed to send: {}", tx.id, e);

                            // Handle retry logic
                            if tx.retry_count < tx.max_retries {
                                // Add back to queue for retry
                                let mut retry_tx = tx.clone();
                                retry_tx.retry_count += 1;
                                retry_tx.created_at = Instant::now();

                                tokio::time::sleep(config.retry_delay).await;

                                {
                                    let mut queue_guard = queue.write().await;
                                    queue_guard.push_front(retry_tx);
                                }

                                warn!("Transaction {} queued for retry ({}/{})",
                                      tx.id, tx.retry_count + 1, tx.max_retries);
                            } else {
                                // Max retries exceeded
                                error!("Transaction {} failed after {} retries", tx.id, tx.max_retries);

                                let result = TransactionResult {
                                    transaction_id: tx.id.clone(),
                                    signature: String::new(),
                                    success: false,
                                    error: Some(format!("Max retries exceeded: {}", e)),
                                    slot: 0,
                                    gas_used: 0,
                                    gas_cost: 0.0,
                                    priority_fee_paid: 0,
                                    execution_time: send_time,
                                    confirmation_time: Duration::from_secs(0),
                                    total_time: send_time,
                                };

                                // Send result to callback
                                if let Err(_) = tx.callback.send(result).await {
                                    warn!("Failed to send transaction result to callback");
                                }

                                // Update metrics
                                {
                                    let mut metrics_guard = metrics.write().await;
                                    metrics_guard.total_failed += 1;
                                    metrics_guard.queue_depth = metrics_guard.queue_depth.saturating_sub(1);
                                }
                            }
                        }
                    }
                } else {
                    // Queue is empty, wait a bit
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            }
        });

        Ok(handle)
    }

    async fn start_batch_processor(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let queue = self.transaction_queue.clone();
        let config = self.config.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(config.batch_timeout);

            loop {
                interval.tick().await;

                // Check if batching is beneficial
                let queue_size = {
                    let queue_guard = queue.read().await;
                    queue_guard.len()
                };

                if queue_size >= config.batch_size {
                    debug!("Batch processing: {} transactions in queue", queue_size);
                    // Batch processing logic would go here
                    // For now, individual transactions are processed
                }
            }
        });

        Ok(handle)
    }

    async fn start_confirmation_monitor(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let pending = self.pending_transactions.clone();
        let rpc_router = self.rpc_router.clone();
        let config = self.config.clone();
        let metrics = self.metrics.clone();
        let confirmation_times = self.confirmation_times.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_millis(100));

            loop {
                interval.tick().await;

                let pending_transactions = {
                    let pending_guard = pending.read().await;
                    pending_guard.clone()
                };

                for (tx_id, queued_tx) in pending_transactions {
                    // Check transaction status
                    match rpc_router.get_signature_status(&tx_id).await {
                        Ok(Some(status)) => {
                            if status.err.is_none() {
                                // Transaction confirmed
                                let confirmation_time = queued_tx.created_at.elapsed();

                                // Update confirmation time
                                {
                                    let mut times = confirmation_times.write().await;
                                    times.push_back(confirmation_time);
                                    if times.len() > 1000 {
                                        times.pop_front();
                                    }
                                }

                                let result = TransactionResult {
                                    transaction_id: tx_id.clone(),
                                    signature: tx_id.clone(),
                                    success: true,
                                    error: None,
                                    slot: status.slot.unwrap_or(0),
                                    gas_used: status.confirmations.as_ref()
                                        .and_then(|c| c.compute_units_consumed)
                                        .unwrap_or(0),
                                    gas_cost: status.confirmations.as_ref()
                                        .and_then(|c| c.total_fee)
                                        .map(|f| f as f64 / 1_000_000_000.0)
                                        .unwrap_or(0.0),
                                    priority_fee_paid: queued_tx.priority_fee.unwrap_or(0),
                                    execution_time: Duration::from_secs(0), // Would be tracked during send
                                    confirmation_time,
                                    total_time: confirmation_time,
                                };

                                // Send result to callback
                                if let Err(_) = queued_tx.callback.send(result).await {
                                    warn!("Failed to send transaction result to callback for {}", tx_id);
                                }

                                // Remove from pending
                                {
                                    let mut pending_guard = pending.write().await;
                                    pending_guard.remove(&tx_id);
                                }

                                // Update metrics
                                {
                                    let mut metrics_guard = metrics.write().await;
                                    metrics_guard.total_confirmed += 1;
                                }

                                debug!("Transaction {} confirmed in slot {}", tx_id, status.slot.unwrap_or(0));
                            } else {
                                // Transaction failed
                                error!("Transaction {} failed: {:?}", tx_id, status.err);

                                // Remove from pending and handle as failure
                                {
                                    let mut pending_guard = pending.write().await;
                                    pending_guard.remove(&tx_id);
                                }

                                {
                                    let mut metrics_guard = metrics.write().await;
                                    metrics_guard.total_failed += 1;
                                }
                            }
                        }
                        Ok(None) => {
                            // Transaction not yet confirmed, check timeout
                            if queued_tx.created_at.elapsed() > config.confirmation_timeout {
                                warn!("Transaction {} confirmation timeout", tx_id);

                                // Remove from pending
                                {
                                    let mut pending_guard = pending.write().await;
                                    pending_guard.remove(&tx_id);
                                }

                                {
                                    let mut metrics_guard = metrics.write().await;
                                    metrics_guard.total_failed += 1;
                                }
                            }
                        }
                        Err(e) => {
                            error!("Error checking transaction {} status: {}", tx_id, e);
                        }
                    }
                }
            }
        });

        Ok(handle)
    }

    async fn start_metrics_collector(&self) -> Result<tokio::task::JoinHandle<Result<()>>> {
        let metrics = self.metrics.clone();
        let queue_times = self.queue_times.clone();
        let send_times = self.send_times.clone();
        let confirmation_times = self.confirmation_times.clone();

        let handle = tokio::spawn(async move {
            let mut interval = tokio::time::interval(Duration::from_secs(10));

            loop {
                interval.tick().await;

                // Calculate averages
                let (avg_queue_time, avg_send_time, avg_confirmation_time) = {
                    let queue_guard = queue_times.read().await;
                    let send_guard = send_times.read().await;
                    let conf_guard = confirmation_times.read().await;

                    let avg_queue = if !queue_guard.is_empty() {
                        queue_guard.iter().sum::<Duration>() / queue_guard.len() as u32
                    } else { Duration::from_secs(0) };

                    let avg_send = if !send_guard.is_empty() {
                        send_guard.iter().sum::<Duration>() / send_guard.len() as u32
                    } else { Duration::from_secs(0) };

                    let avg_conf = if !conf_guard.is_empty() {
                        conf_guard.iter().sum::<Duration>() / conf_guard.len() as u32
                    } else { Duration::from_secs(0) };

                    (avg_queue, avg_send, avg_conf)
                };

                // Update metrics
                {
                    let mut metrics_guard = metrics.write().await;
                    metrics_guard.average_queue_time = avg_queue_time;
                    metrics_guard.average_send_time = avg_send_time;
                    metrics_guard.average_confirmation_time = avg_confirmation_time;

                    let total_processed = metrics_guard.total_confirmed + metrics_guard.total_failed;
                    if total_processed > 0 {
                        metrics_guard.success_rate = (metrics_guard.total_confirmed as f64 / total_processed as f64) * 100.0;
                    }
                }

                // Log metrics
                {
                    let metrics_guard = metrics.read().await;
                    info!(
                        "Pipeline Metrics: queue_depth={}, success_rate={:.2}%, \
                         avg_times={:?}/{:?}/{:?}, total_sent={}",
                        metrics_guard.queue_depth,
                        metrics_guard.success_rate,
                        metrics_guard.average_queue_time,
                        metrics_guard.average_send_time,
                        metrics_guard.average_confirmation_time,
                        metrics_guard.total_sent
                    );
                }
            }
        });

        Ok(handle)
    }

    async fn process_transaction(
        queued_tx: QueuedTransaction,
        config: TransactionPipelineConfig,
        rpc_router: Arc<RpcRouter>,
        keypair: Arc<Keypair>,
    ) -> Result<String> {
        // Get recent blockhash
        let recent_blockhash = rpc_router.get_latest_blockhash().await?;

        // Add compute budget instructions if needed
        let mut instructions = queued_tx.instructions;

        if let Some(compute_limit) = queued_tx.compute_limit {
            instructions.insert(0, ComputeBudgetInstruction::set_compute_unit_limit(compute_limit));
        }

        if let Some(priority_fee) = queued_tx.priority_fee {
            instructions.insert(0, ComputeBudgetInstruction::set_compute_unit_price(priority_fee));
        }

        // Create transaction
        let message = Message::new(&instructions, Some(&keypair.pubkey()));
        let mut transaction = Transaction::new_unsigned(&message);
        transaction.partial_sign(&[&*keypair], recent_blockhash);

        // Create transaction request
        let tx_request = TransactionRequest {
            transaction,
            urgency: queued_tx.urgency,
            skip_preflight: queued_tx.skip_preflight,
            max_retries: config.retry_attempts,
            confirmation_level: CommitmentConfig::confirmed(),
        };

        // Send through RPCRouter
        let signature = rpc_router.send_transaction(tx_request).await?;

        Ok(signature)
    }

    pub async fn get_metrics(&self) -> PipelineMetrics {
        self.metrics.read().await.clone()
    }

    pub async fn get_queue_depth(&self) -> usize {
        self.transaction_queue.read().await.len()
    }

    pub async fn get_pending_count(&self) -> usize {
        self.pending_transactions.read().await.len()
    }
}