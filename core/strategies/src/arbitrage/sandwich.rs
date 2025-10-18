//! Sandwich Attack Detection and Execution
//!
//! This module provides sophisticated sandwich attack detection and execution capabilities
//! for MEV extraction on Solana DEXes. It includes real-time transaction monitoring,
//! attack opportunity identification, and profitable sandwich execution.

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::time::sleep;
use log::{info, warn, error, debug};
use solana_sdk::{
    pubkey::Pubkey,
    signature::Signature,
    transaction::VersionedTransaction,
    commitment_config::CommitmentConfig,
    rpc_client::RpcClient,
};
use reqwest::Client;

/// Sandwich attack opportunity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SandwichOpportunity {
    pub id: String,
    pub target_transaction: String,
    pub victim_swap: VictimSwap,
    pub front_run: FrontRunPlan,
    pub back_run: BackRunPlan,
    pub estimated_profit: f64,
    pub gas_cost: f64,
    pub net_profit: f64,
    pub profit_margin: f64,
    pub risk_score: f64,
    pub confidence_score: f64,
    pub urgency_level: f64,
    pub execution_deadline: u64,
    pub created_at: u64,
}

/// Information about the victim's swap transaction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VictimSwap {
    pub transaction_signature: String,
    pub token_in: String,
    pub token_out: String,
    pub amount_in: f64,
    pub expected_amount_out: f64,
    pub dex: String,
    pub pool: String,
    pub slippage_tolerance: f64,
    pub max_priority_fee: u64,
    pub timestamp: u64,
    pub position_in_mempool: u32,
}

/// Front-run attack plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FrontRunPlan {
    pub action: "buy" | "sell",
    pub token: String,
    pub amount: f64,
    pub price_impact: f64,
    pub estimated_price: f64,
    pub min_output: f64,
    pub dex: String,
    pub pool: String,
    pub priority_fee: u64,
    pub compute_units: u32,
}

/// Back-run attack plan
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackRunPlan {
    pub action: "sell" | "buy",
    pub token: String,
    pub amount: f64,
    pub estimated_price: f64,
    pub min_output: f64,
    pub dex: String,
    pub pool: String,
    pub priority_fee: u64,
    pub compute_units: u32,
}

/// MEV transaction data from mempool monitoring
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MempoolTransaction {
    pub signature: String,
    pub sender: String,
    pub instructions: Vec<TransactionInstruction>,
    pub priority_fee: u64,
    pub compute_limit: u32,
    pub timestamp: u64,
    pub position_in_block: Option<u64>,
    pub is_confirmed: bool,
}

/// DEX transaction instruction
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionInstruction {
    pub program_id: String,
    pub accounts: Vec<String>,
    pub data: Vec<u8>,
    pub instruction_type: String, // "swap", "add_liquidity", "remove_liquidity"
    pub token_in: Option<String>,
    pub token_out: Option<String>,
    pub amount: Option<f64>,
    pub slippage: Option<f64>,
}

/// Sandwich attack detector and executor
pub struct SandwichDetector {
    config: SandwichConfig,
    rpc_client: RpcClient,
    http_client: Client,
    mempool_monitor: MempoolMonitor,
    price_feeds: HashMap<String, PriceFeed>,
    supported_dexes: HashMap<String, DexConfig>,
    active_opportunities: Vec<SandwichOpportunity>,
    execution_history: VecDeque<SandwichResult>,
}

/// Sandwich attack configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SandwichConfig {
    /// Minimum profit threshold in USD
    pub min_profit_threshold: f64,
    /// Maximum risk tolerance (0.0 - 1.0)
    pub max_risk_tolerance: f64,
    /// Maximum gas cost in SOL
    pub max_gas_cost_sol: f64,
    /// Minimum confidence score (0.0 - 1.0)
    pub min_confidence_score: f64,
    /// Maximum slippage tolerance
    pub max_slippage_tolerance: f64,
    /// Minimum victim trade size in USD
    pub min_victim_trade_size: f64,
    /// Maximum victim trade size in USD (avoid whales)
    pub max_victim_trade_size: f64,
    /// Priority fee multiplier for front-running
    pub priority_fee_multiplier: f64,
    /// Maximum execution delay in milliseconds
    pub max_execution_delay_ms: u64,
    /// Enable sandwich attacks
    pub enable_sandwich_attacks: bool,
    /// Monitor mempool depth
    pub mempool_depth: usize,
}

impl Default for SandwichConfig {
    fn default() -> Self {
        Self {
            min_profit_threshold: 25.0,
            max_risk_tolerance: 0.3,
            max_gas_cost_sol: 0.01,
            min_confidence_score: 0.7,
            max_slippage_tolerance: 0.05,
            min_victim_trade_size: 1000.0,
            max_victim_trade_size: 50000.0,
            priority_fee_multiplier: 1.2,
            max_execution_delay_ms: 500,
            enable_sandwich_attacks: false, // Disabled by default for safety
            mempool_depth: 100,
        }
    }
}

/// Mempool transaction monitor
pub struct MempoolMonitor {
    pending_transactions: HashMap<String, MempoolTransaction>,
    monitoring_active: bool,
    last_update: Instant,
    update_interval: Duration,
}

/// Price feed data
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriceFeed {
    pub token: String,
    pub price: f64,
    pub liquidity: f64,
    pub volume_24h: f64,
    pub timestamp: u64,
    pub confidence: f64,
}

/// DEX configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DexConfig {
    pub name: String,
    pub program_id: String,
    pub fee_rate: f64,
    pub min_liquidity: f64,
    pub slippage_model: String,
    pub priority: u8,
}

/// Sandwich attack execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SandwichResult {
    pub opportunity_id: String,
    pub success: bool,
    pub front_run_tx: Option<String>,
    pub victim_tx: String,
    pub back_run_tx: Option<String>,
    pub actual_profit: f64,
    pub gas_cost: f64,
    pub net_profit: f64,
    pub execution_time_ms: u64,
    pub error_message: Option<String>,
    pub timestamp: u64,
}

impl SandwichDetector {
    /// Create new sandwich attack detector
    pub fn new(config: SandwichConfig, rpc_url: &str) -> Result<Self> {
        let rpc_client = RpcClient::new_with_commitment(rpc_url, CommitmentConfig::confirmed());
        let http_client = Client::builder()
            .timeout(Duration::from_secs(5))
            .build()?;

        // Initialize supported DEXes
        let mut supported_dexes = HashMap::new();

        supported_dexes.insert("orca".to_string(), DexConfig {
            name: "Orca".to_string(),
            program_id: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP".to_string(),
            fee_rate: 0.003,
            min_liquidity: 10000.0,
            slippage_model: "constant_product".to_string(),
            priority: 1,
        });

        supported_dexes.insert("raydium".to_string(), DexConfig {
            name: "Raydium".to_string(),
            program_id: "9KEPZsX3uphrDhuQCkDUBNpkPPNpygHjkEGt6eDZdvce".to_string(),
            fee_rate: 0.0025,
            min_liquidity: 10000.0,
            slippage_model: "constant_product".to_string(),
            priority: 2,
        });

        supported_dexes.insert("jupiter".to_string(), DexConfig {
            name: "Jupiter".to_string(),
            program_id: "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4".to_string(),
            fee_rate: 0.0025,
            min_liquidity: 20000.0,
            slippage_model: "aggregated".to_string(),
            priority: 1,
        });

        let mempool_monitor = MempoolMonitor {
            pending_transactions: HashMap::new(),
            monitoring_active: false,
            last_update: Instant::now(),
            update_interval: Duration::from_millis(100),
        };

        Ok(Self {
            config,
            rpc_client,
            http_client,
            mempool_monitor,
            price_feeds: HashMap::new(),
            supported_dexes,
            active_opportunities: Vec::new(),
            execution_history: VecDeque::new(),
        })
    }

    /// Start sandwich attack detection
    pub async fn start_monitoring(&mut self) -> Result<()> {
        if !self.config.enable_sandwich_attacks {
            warn!("Sandwich attacks are disabled in configuration");
            return Ok(());
        }

        info!("🥪 Starting sandwich attack detection and monitoring");
        self.mempool_monitor.monitoring_active = true;

        while self.mempool_monitor.monitoring_active {
            match self.monitor_mempool().await {
                Ok(_) => {
                    // Detect sandwich opportunities
                    match self.detect_sandwich_opportunities().await {
                        Ok(opportunities) => {
                            for opportunity in opportunities {
                                self.process_sandwich_opportunity(opportunity).await?;
                            }
                        }
                        Err(e) => {
                            warn!("Failed to detect sandwich opportunities: {}", e);
                        }
                    }
                }
                Err(e) => {
                    error!("Mempool monitoring error: {}", e);
                    sleep(Duration::from_secs(1)).await;
                }
            }

            sleep(self.mempool_monitor.update_interval).await;
        }

        Ok(())
    }

    /// Stop monitoring
    pub fn stop_monitoring(&mut self) {
        info!("Stopping sandwich attack monitoring");
        self.mempool_monitor.monitoring_active = false;
    }

    /// Monitor mempool for profitable transactions
    async fn monitor_mempool(&mut self) -> Result<()> {
        // Get pending transactions from mempool
        let pending_txs = self.get_pending_transactions().await?;

        // Update mempool monitor
        for tx in pending_txs {
            if !self.mempool_monitor.pending_transactions.contains_key(&tx.signature) {
                self.mempool_monitor.pending_transactions.insert(tx.signature.clone(), tx);
            }
        }

        // Clean up old transactions
        let now = Instant::now();
        self.mempool_monitor.pending_transactions.retain(|_, tx| {
            now.duration_since(Instant::now() - Duration::from_secs(tx.timestamp)).as_secs() < 30
        });

        self.mempool_monitor.last_update = now;
        Ok(())
    }

    /// Detect sandwich attack opportunities
    async fn detect_sandwich_opportunities(&self) -> Result<Vec<SandwichOpportunity>> {
        let mut opportunities = Vec::new();

        for (_, tx) in &self.mempool_monitor.pending_transactions {
            if tx.is_confirmed {
                continue;
            }

            // Check if this is a DEX swap transaction
            for instruction in &tx.instructions {
                if instruction.instruction_type == "swap" {
                    match self.analyze_swap_for_sandwich(instruction, tx).await {
                        Ok(Some(opportunity)) => {
                            if self.is_opportunity_profitable(&opportunity) {
                                opportunities.push(opportunity);
                            }
                        }
                        Ok(None) => {}
                        Err(e) => {
                            debug!("Failed to analyze swap for sandwich: {}", e);
                        }
                    }
                }
            }
        }

        // Rank opportunities by profit potential
        opportunities.sort_by(|a, b| b.net_profit.partial_cmp(&a.net_profit).unwrap_or(std::cmp::Ordering::Equal));

        Ok(opportunities)
    }

    /// Analyze a swap transaction for sandwich attack potential
    async fn analyze_swap_for_sandwich(&self, instruction: &TransactionInstruction, tx: &MempoolTransaction) -> Result<Option<SandwichOpportunity>> {
        let token_in = instruction.token_in.as_ref().ok_or_else(|| anyhow!("No token_in"))?;
        let token_out = instruction.token_out.as_ref().ok_or_else(|| anyhow!("No token_out"))?;
        let amount = instruction.amount.ok_or_else(|| anyhow!("No amount"))?;
        let slippage = instruction.slippage.unwrap_or(0.01);

        // Check if trade size is within our range
        let trade_size_usd = self.calculate_trade_size_usd(token_in, amount).await?;
        if trade_size_usd < self.config.min_victim_trade_size || trade_size_usd > self.config.max_victim_trade_size {
            return Ok(None);
        }

        // Get current price and liquidity
        let current_price = self.get_current_price(token_in).await?;
        let liquidity = self.get_liquidity_depth(token_in).await?;

        // Calculate sandwich attack parameters
        let front_run_amount = trade_size_usd * 0.1; // 10% of victim trade
        let estimated_price_impact = self.calculate_price_impact(front_run_amount, liquidity);

        if estimated_price_impact > self.config.max_slippage_tolerance {
            return Ok(None);
        }

        // Estimate profit
        let gross_profit = self.estimate_sandwich_profit(
            front_run_amount,
            trade_size_usd,
            current_price,
            estimated_price_impact,
        ).await?;

        let gas_cost = self.estimate_gas_cost(3).await?; // 3 transactions (front-run, victim, back-run)
        let net_profit = gross_profit - gas_cost;

        if net_profit < self.config.min_profit_threshold {
            return Ok(None);
        }

        // Calculate risk metrics
        let risk_score = self.calculate_sandwich_risk(
            trade_size_usd,
            liquidity,
            tx.priority_fee,
            estimated_price_impact,
        ).await?;

        let confidence_score = self.calculate_sandwich_confidence(
            trade_size_usd,
            liquidity,
            tx.position_in_mempool,
            slippage,
        ).await?;

        // Create opportunity
        let opportunity_id = format!("sandwich_{}_{}",
            tx.signature[..8].to_string(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs()
        );

        let opportunity = SandwichOpportunity {
            id: opportunity_id,
            target_transaction: tx.signature.clone(),
            victim_swap: VictimSwap {
                transaction_signature: tx.signature.clone(),
                token_in: token_in.clone(),
                token_out: token_out.clone(),
                amount_in: amount,
                expected_amount_out: amount * current_price,
                dex: self.get_dex_name_from_program(&instruction.program_id),
                pool: "unknown".to_string(), // Would be determined from instruction data
                slippage_tolerance: slippage,
                max_priority_fee: tx.priority_fee,
                timestamp: tx.timestamp,
                position_in_mempool: tx.position_in_mempool.unwrap_or(0) as u32,
            },
            front_run: FrontRunPlan {
                action: "buy", // Assuming we're buying the token the victim is buying
                token: token_in.clone(),
                amount: front_run_amount,
                price_impact: estimated_price_impact,
                estimated_price: current_price * (1.0 + estimated_price_impact),
                min_output: front_run_amount * 0.95, // 5% slippage tolerance
                dex: self.get_dex_name_from_program(&instruction.program_id),
                pool: "unknown".to_string(),
                priority_fee: (tx.priority_fee as f64 * self.config.priority_fee_multiplier) as u64,
                compute_units: 200_000,
            },
            back_run: BackRunPlan {
                action: "sell",
                token: token_in.clone(),
                amount: front_run_amount,
                estimated_price: current_price * (1.0 - estimated_price_impact),
                min_output: front_run_amount * 0.95,
                dex: self.get_dex_name_from_program(&instruction.program_id),
                pool: "unknown".to_string(),
                priority_fee: (tx.priority_fee as f64 * self.config.priority_fee_multiplier) as u64,
                compute_units: 200_000,
            },
            estimated_profit: gross_profit,
            gas_cost,
            net_profit,
            profit_margin: net_profit / front_run_amount,
            risk_score,
            confidence_score,
            urgency_level: self.calculate_urgency_level(tx.position_in_mempool),
            execution_deadline: tx.timestamp + self.config.max_execution_delay_ms / 1000,
            created_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
        };

        Ok(Some(opportunity))
    }

    /// Execute sandwich attack
    async fn execute_sandwich_attack(&self, opportunity: &SandwichOpportunity) -> Result<SandwichResult> {
        info!("🥪 Executing sandwich attack: {}", opportunity.id);

        let execution_start = Instant::now();

        // Build front-run transaction
        let front_run_tx = self.build_front_run_transaction(&opportunity.front_run).await?;

        // Build back-run transaction
        let back_run_tx = self.build_back_run_transaction(&opportunity.back_run).await?;

        // Execute bundle (front-run + victim + back-run)
        let execution_result = self.execute_sandwich_bundle(
            front_run_tx,
            opportunity.victim_swap.transaction_signature.clone(),
            back_run_tx,
        ).await?;

        let execution_time = execution_start.elapsed().as_millis() as u64;

        Ok(SandwichResult {
            opportunity_id: opportunity.id.clone(),
            success: execution_result.success,
            front_run_tx: execution_result.front_run_signature,
            victim_tx: opportunity.victim_swap.transaction_signature.clone(),
            back_run_tx: execution_result.back_run_signature,
            actual_profit: execution_result.actual_profit,
            gas_cost: execution_result.gas_cost,
            net_profit: execution_result.net_profit,
            execution_time_ms: execution_time,
            error_message: execution_result.error_message,
            timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
        })
    }

    /// Process sandwich opportunity
    async fn process_sandwich_opportunity(&mut self, opportunity: SandwichOpportunity) -> Result<()> {
        info!("Processing sandwich opportunity: {} (profit: ${:.2})",
              opportunity.id, opportunity.net_profit);

        // Check urgency and deadline
        let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
        if now > opportunity.execution_deadline {
            warn!("Opportunity {} expired", opportunity.id);
            return Ok(());
        }

        // Execute attack
        match self.execute_sandwich_attack(&opportunity).await {
            Ok(result) => {
                self.execution_history.push_back(result);

                // Keep only last 100 results
                if self.execution_history.len() > 100 {
                    self.execution_history.pop_front();
                }

                info!("✅ Sandwich attack executed successfully: ${:.2} profit", result.net_profit);
            }
            Err(e) => {
                warn!("❌ Sandwich attack failed: {}", e);
            }
        }

        Ok(())
    }

    // Helper methods (implementations would go here)
    async fn get_pending_transactions(&self) -> Result<Vec<MempoolTransaction>> {
        // TODO: Implement actual mempool monitoring
        // This would connect to Jito mempool or similar service
        Ok(vec![])
    }

    async fn calculate_trade_size_usd(&self, _token: &str, amount: f64) -> Result<f64> {
        // TODO: Implement actual price calculation
        Ok(amount * 100.0) // Mock calculation
    }

    async fn get_current_price(&self, _token: &str) -> Result<f64> {
        // TODO: Implement actual price fetching
        Ok(100.0) // Mock price
    }

    async fn get_liquidity_depth(&self, _token: &str) -> Result<f64> {
        // TODO: Implement actual liquidity calculation
        Ok(100000.0) // Mock liquidity
    }

    fn calculate_price_impact(&self, amount: f64, liquidity: f64) -> f64 {
        (amount / liquidity).min(0.1) // Cap at 10%
    }

    async fn estimate_sandwich_profit(&self, front_run_amount: f64, victim_amount: f64, current_price: f64, price_impact: f64) -> Result<f64> {
        let price_increase = current_price * price_impact;
        let profit_from_victim = victim_amount * price_increase;
        let profit_from_arbitrage = front_run_amount * price_increase * 2.0; // Buy low, sell high
        Ok(profit_from_victim + profit_from_arbitrage)
    }

    async fn estimate_gas_cost(&self, num_transactions: u32) -> Result<f64> {
        // TODO: Implement actual gas cost estimation
        Ok(num_transactions as f64 * 0.001) // Mock cost
    }

    async fn calculate_sandwich_risk(&self, trade_size: f64, liquidity: f64, _priority_fee: u64, price_impact: f64) -> Result<f64> {
        let liquidity_risk = (trade_size / liquidity).min(1.0) * 0.4;
        let execution_risk = 0.2; // Base execution risk
        let price_impact_risk = price_impact * 0.3;
        let competition_risk = 0.1; // Competition risk

        Ok(liquidity_risk + execution_risk + price_impact_risk + competition_risk)
    }

    async fn calculate_sandwich_confidence(&self, trade_size: f64, liquidity: f64, position: Option<u64>, slippage: f64) -> Result<f64> {
        let size_factor = (trade_size / 10000.0).min(1.0); // Better for medium-sized trades
        let liquidity_factor = (liquidity / 100000.0).min(1.0);
        let position_factor = if position.unwrap_or(0) < 10 { 0.3 } else { 0.0 }; // Better for early position
        let slippage_factor = 1.0 - (slippage * 10.0); // Lower slippage = higher confidence

        Ok((size_factor + liquidity_factor + position_factor + slippage_factor) / 4.0)
    }

    fn calculate_urgency_level(&self, position: Option<u64>) -> f64 {
        match position {
            Some(pos) if pos < 5 => 1.0,    // Very urgent
            Some(pos) if pos < 20 => 0.8,   // Urgent
            Some(pos) if pos < 50 => 0.6,   // Moderate
            _ => 0.4,                        // Low urgency
        }
    }

    fn get_dex_name_from_program(&self, program_id: &str) -> String {
        for (_, dex_config) in &self.supported_dexes {
            if dex_config.program_id == program_id {
                return dex_config.name.clone();
            }
        }
        "Unknown".to_string()
    }

    fn is_opportunity_profitable(&self, opportunity: &SandwichOpportunity) -> bool {
        opportunity.net_profit >= self.config.min_profit_threshold &&
        opportunity.risk_score <= self.config.max_risk_tolerance &&
        opportunity.confidence_score >= self.config.min_confidence_score
    }

    async fn build_front_run_transaction(&self, _plan: &FrontRunPlan) -> Result<VersionedTransaction> {
        // TODO: Implement actual transaction building
        Err(anyhow!("Front-run transaction building not implemented"))
    }

    async fn build_back_run_transaction(&self, _plan: &BackRunPlan) -> Result<VersionedTransaction> {
        // TODO: Implement actual transaction building
        Err(anyhow!("Back-run transaction building not implemented"))
    }

    async fn execute_sandwich_bundle(&self, _front_run: VersionedTransaction, _victim: String, _back_run: VersionedTransaction) -> Result<SandwichExecutionResult> {
        // TODO: Implement actual bundle execution
        Ok(SandwichExecutionResult {
            success: true,
            front_run_signature: Some("mock_front_run".to_string()),
            back_run_signature: Some("mock_back_run".to_string()),
            actual_profit: 50.0,
            gas_cost: 0.005,
            net_profit: 45.0,
            error_message: None,
        })
    }

    /// Get execution statistics
    pub fn get_execution_stats(&self) -> SandwichStats {
        let total_attempts = self.execution_history.len();
        let successful_attacks = self.execution_history.iter().filter(|r| r.success).count();
        let total_profit = self.execution_history.iter().map(|r| r.net_profit).sum();
        let avg_execution_time = if total_attempts > 0 {
            self.execution_history.iter().map(|r| r.execution_time_ms).sum::<u64>() / total_attempts as u64
        } else {
            0
        };

        SandwichStats {
            total_attempts,
            successful_attacks,
            success_rate: if total_attempts > 0 {
                successful_attacks as f64 / total_attempts as f64
            } else {
                0.0
            },
            total_profit,
            average_execution_time_ms: avg_execution_time,
        }
    }
}

/// Sandwich execution result
#[derive(Debug, Clone)]
pub struct SandwichExecutionResult {
    pub success: bool,
    pub front_run_signature: Option<String>,
    pub back_run_signature: Option<String>,
    pub actual_profit: f64,
    pub gas_cost: f64,
    pub net_profit: f64,
    pub error_message: Option<String>,
}

/// Sandwich attack statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SandwichStats {
    pub total_attempts: usize,
    pub successful_attacks: usize,
    pub success_rate: f64,
    pub total_profit: f64,
    pub average_execution_time_ms: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sandwich_config_default() {
        let config = SandwichConfig::default();
        assert!(!config.enable_sandwich_attacks);
        assert_eq!(config.min_profit_threshold, 25.0);
        assert_eq!(config.max_risk_tolerance, 0.3);
    }

    #[test]
    fn test_price_impact_calculation() {
        let detector = SandwichDetector::new(
            SandwichConfig::default(),
            "https://api.mainnet-beta.solana.com",
        ).unwrap();

        let impact = detector.calculate_price_impact(1000.0, 100000.0);
        assert_eq!(impact, 0.01); // 1% price impact

        let impact_max = detector.calculate_price_impact(20000.0, 100000.0);
        assert_eq!(impact_max, 0.1); // Capped at 10%
    }

    #[test]
    fn test_urgency_level_calculation() {
        let detector = SandwichDetector::new(
            SandwichConfig::default(),
            "https://api.mainnet-beta.solana.com",
        ).unwrap();

        assert_eq!(detector.calculate_urgency_level(Some(3)), 1.0);
        assert_eq!(detector.calculate_urgency_level(Some(15)), 0.8);
        assert_eq!(detector.calculate_urgency_level(Some(40)), 0.6);
        assert_eq!(detector.calculate_urgency_level(Some(100)), 0.4);
        assert_eq!(detector.calculate_urgency_level(None), 0.4);
    }
}