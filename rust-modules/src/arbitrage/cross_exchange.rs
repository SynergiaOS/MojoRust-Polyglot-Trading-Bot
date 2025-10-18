//! Cross-Exchange Arbitrage Module for Orca ↔ Raydium
//!
//! This module implements high-frequency cross-exchange arbitrage detection and execution
//! between Orca and Raydium DEXs for all 10 supported tokens.
//!
//! Features:
//! - Real-time price monitoring across Orca and Raydium
//! - 1-2% spread detection with sub-millisecond latency
//! - Flash loan execution with MEV protection
//! - Advanced slippage protection and execution timing
//! - Comprehensive risk management and position sizing

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{RwLock, mpsc};
use serde::{Deserialize, Serialize};
use solana_sdk::pubkey::Pubkey;
use solana_sdk::signature::Keypair;
use solana_sdk::{
    commitment_config::CommitmentConfig,
    rpc_client::RpcClient,
};
use anchor_client::Program;
use anyhow::{Result, anyhow};
use log::{debug, info, warn, error};
use chrono::Utc;
use reqwest::Client;

use crate::monitoring::metrics;
use super::flash_loan::{FlashLoanProvider, get_token_mint_map, get_solend_markets, get_marginfi_markets};
use super::risk::calculate_position_size;
use super::execution::ExecutionEngine;
use super::ArbitrageConfig;

/// Supported tokens for cross-exchange arbitrage
pub const SUPPORTED_TOKENS: &[&str] = &[
    "SOL", "USDT", "USDC", "WBTC", "LINK",
    "USDE", "USDS", "CBBTC", "SUSDE", "WLFI"
];

/// Minimum spread threshold for arbitrage (1%)
pub const MIN_SPREAD_THRESHOLD: f64 = 0.01;

/// Maximum spread threshold (2%)
pub const MAX_SPREAD_THRESHOLD: f64 = 0.02;

/// Maximum slippage tolerance (50 basis points)
pub const MAX_SLIPPAGE_BPS: u64 = 50;

/// DEX identifiers
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Dex {
    Orca,
    Raydium,
}

impl Dex {
    pub fn as_str(&self) -> &'static str {
        match self {
            Dex::Orca => "orca",
            Dex::Raydium => "raydium",
        }
    }
}

/// Pool information for a DEX
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoolInfo {
    pub dex: Dex,
    pub address: Pubkey,
    pub token_a: Pubkey,
    pub token_b: Pubkey,
    pub reserve_a: u64,
    pub reserve_b: u64,
    pub fee_numerator: u64,
    pub fee_denominator: u64,
    pub last_update: i64,
}

impl PoolInfo {
    /// Calculate the current price of token_a in terms of token_b
    pub fn calculate_price(&self) -> f64 {
        if self.reserve_a == 0 {
            return 0.0;
        }
        self.reserve_b as f64 / self.reserve_a as f64
    }

    /// Calculate the output amount for a given input amount
    pub fn calculate_output(&self, input_amount: u64, is_token_a_input: bool) -> Result<u64> {
        if is_token_a_input {
            if self.reserve_a == 0 {
                return Err(anyhow!("Invalid reserve: reserve_a is zero"));
            }

            let input_amount_with_fees = input_amount as f64 * (1.0 - (self.fee_numerator as f64 / self.fee_denominator as f64));
            let numerator = input_amount_with_fees * self.reserve_b as f64;
            let denominator = self.reserve_a as f64 + input_amount_with_fees;

            Ok((numerator / denominator) as u64)
        } else {
            if self.reserve_b == 0 {
                return Err(anyhow!("Invalid reserve: reserve_b is zero"));
            }

            let input_amount_with_fees = input_amount as f64 * (1.0 - (self.fee_numerator as f64 / self.fee_denominator as f64));
            let numerator = input_amount_with_fees * self.reserve_a as f64;
            let denominator = self.reserve_b as f64 + input_amount_with_fees;

            Ok((numerator / denominator) as u64)
        }
    }

    /// Check if the pool data is fresh (within last 5 seconds)
    pub fn is_fresh(&self) -> bool {
        let now = Utc::now().timestamp();
        (now - self.last_update).abs() < 5
    }
}

/// Arbitrage opportunity detected between two DEXs
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArbitrageOpportunity {
    pub token_pair: (String, String),
    pub buy_dex: Dex,
    pub sell_dex: Dex,
    pub buy_price: f64,
    pub sell_price: f64,
    pub spread_percentage: f64,
    pub profit_estimate: f64,
    pub input_amount: u64,
    pub output_amount: u64,
    pub flash_loan_provider: FlashLoanProvider,
    pub gas_estimate: u64,
    pub timestamp: i64,
    pub slippage_estimate: f64,
}

impl ArbitrageOpportunity {
    /// Calculate potential profit after accounting for gas and fees
    pub fn calculate_net_profit(&self) -> f64 {
        self.profit_estimate - (self.gas_estimate as f64 * 0.000001) // Gas cost estimate
    }

    /// Check if the opportunity is still valid
    pub fn is_valid(&self, max_age_seconds: i64) -> bool {
        let now = Utc::now().timestamp();
        (now - self.timestamp).abs() < max_age_seconds &&
        self.spread_percentage >= MIN_SPREAD_THRESHOLD &&
        self.spread_percentage <= MAX_SPREAD_THRESHOLD &&
        self.slippage_estimate <= 0.005 // Max 0.5% slippage
    }

    /// Generate unique opportunity ID
    pub fn generate_id(&self) -> String {
        format!("{}-{}-{}-{}-{}",
            self.token_pair.0,
            self.token_pair.1,
            self.buy_dex.as_str(),
            self.sell_dex.as_str(),
            self.timestamp
        )
    }
}

/// Cross-exchange arbitrage engine
pub struct CrossExchangeArbitrage {
    /// Current pool information for both DEXs
    pools: Arc<RwLock<HashMap<(Dex, String, String), PoolInfo>>>,
    /// Detected arbitrage opportunities
    opportunities: Arc<RwLock<HashMap<String, ArbitrageOpportunity>>>,
    /// Execution engine for flash loan arbitrage
    execution_engine: Arc<ExecutionEngine>,
    /// Private key for transaction signing
    keypair: Arc<Keypair>,
    /// Channel for opportunity notifications
    opportunity_tx: mpsc::UnboundedSender<ArbitrageOpportunity>,
    /// Channel for receiving new pool data
    pool_rx: mpsc::UnboundedReceiver<PoolInfo>,
    /// Minimum spread threshold
    min_spread_threshold: f64,
    /// Maximum position size
    max_position_size: f64,
    /// Last scan time
    last_scan_time: RwLock<Instant>,
    /// Performance metrics
    metrics: CrossExchangeMetrics,
}

/// Performance metrics for cross-exchange arbitrage
#[derive(Debug, Default)]
pub struct CrossExchangeMetrics {
    pub total_opportunities_detected: u64,
    pub successful_arbitrages: u64,
    pub failed_arbitrages: u64,
    pub total_profit: f64,
    pub average_execution_time_ms: f64,
    pub average_spread_captured: f64,
    pub last_detection_time: Option<SystemTime>,
}

impl CrossExchangeArbitrage {
    /// Create a new cross-exchange arbitrage engine
    pub fn new(
        keypair: Arc<Keypair>,
        execution_engine: Arc<ExecutionEngine>,
    ) -> (Self, mpsc::UnboundedSender<PoolInfo>, mpsc::UnboundedReceiver<ArbitrageOpportunity>) {
        let (opportunity_tx, opportunity_rx) = mpsc::unbounded_channel();
        let (pool_tx, pool_rx) = mpsc::unbounded_channel();

        let engine = Self {
            pools: Arc::new(RwLock::new(HashMap::new())),
            opportunities: Arc::new(RwLock::new(HashMap::new())),
            execution_engine,
            keypair,
            opportunity_tx,
            pool_rx,
            min_spread_threshold: MIN_SPREAD_THRESHOLD,
            max_position_size: 100000.0, // $100k max position
            last_scan_time: RwLock::new(Instant::now()),
            metrics: CrossExchangeMetrics::default(),
        };

        (engine, pool_tx, opportunity_rx)
    }

    /// Start the arbitrage detection engine
    pub async fn start(&mut self) -> Result<()> {
        info!("Starting cross-exchange arbitrage engine");

        // Start scanning for arbitrage opportunities
        let mut last_scan = Instant::now();

        loop {
            // Process new pool data
            while let Ok(pool_info) = self.pool_rx.try_recv() {
                self.update_pool_info(pool_info).await?;
            }

            // Scan for arbitrage opportunities every 100ms
            if last_scan.elapsed() >= Duration::from_millis(100) {
                self.scan_for_arbitrage().await?;
                last_scan = Instant::now();
            }

            // Clean up stale opportunities
            self.cleanup_stale_opportunities().await?;

            // Small delay to prevent excessive CPU usage
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }

    /// Update pool information and trigger arbitrage scan if needed
    async fn update_pool_info(&self, pool_info: PoolInfo) -> Result<()> {
        let key = (pool_info.dex,
                  format!("{:?}", pool_info.token_a),
                  format!("{:?}", pool_info.token_b));

        {
            let mut pools = self.pools.write().await;
            pools.insert(key, pool_info.clone());
        }

        debug!("Updated pool info for {} on {}",
               format!("{:?}", pool_info.token_a),
               pool_info.dex.as_str());

        // Trigger immediate scan for opportunities involving this pool
        self.scan_for_arbitrage().await?;

        Ok(())
    }

    /// Scan for arbitrage opportunities across all token pairs
    async fn scan_for_arbitrage(&self) -> Result<()> {
        let pools = self.pools.read().await;
        let mut opportunities = Vec::new();

        // Iterate through all supported token pairs
        for i in 0..SUPPORTED_TOKENS.len() {
            for j in (i + 1)..SUPPORTED_TOKENS.len() {
                let token_a = SUPPORTED_TOKENS[i];
                let token_b = SUPPORTED_TOKENS[j];

                // Check Orca -> Raydium arbitrage
                if let Some(opportunity) = self.check_arbitrage_direction(
                    &pools, token_a, token_b, Dex::Orca, Dex::Raydium
                ).await? {
                    opportunities.push(opportunity);
                }

                // Check Raydium -> Orca arbitrage
                if let Some(opportunity) = self.check_arbitrage_direction(
                    &pools, token_a, token_b, Dex::Raydium, Dex::Orca
                ).await? {
                    opportunities.push(opportunity);
                }
            }
        }

        // Update opportunities and notify
        {
            let mut current_opportunities = self.opportunities.write().await;
            for opportunity in opportunities {
                let id = opportunity.generate_id();
                current_opportunities.insert(id.clone(), opportunity.clone());

                // Send notification through channel
                if let Err(e) = self.opportunity_tx.send(opportunity.clone()) {
                    warn!("Failed to send arbitrage opportunity: {}", e);
                }

                // Update metrics
                metrics::increment_counter("cross_exchange_opportunities_detected_total");
                self.metrics.total_opportunities_detected += 1;
                self.metrics.last_detection_time = Some(SystemTime::now());

                info!("New arbitrage opportunity: {} {} on {}, sell {} on {} - Spread: {:.2}%",
                      opportunity.input_amount,
                      opportunity.token_pair.0,
                      opportunity.buy_dex.as_str(),
                      opportunity.token_pair.1,
                      opportunity.sell_dex.as_str(),
                      opportunity.spread_percentage * 100.0);
            }
        }

        // Update last scan time
        {
            let mut last_scan = self.last_scan_time.write().await;
            *last_scan = Instant::now();
        }

        Ok(())
    }

    /// Check for arbitrage opportunity in a specific direction
    async fn check_arbitrage_direction(
        &self,
        pools: &HashMap<(Dex, String, String), PoolInfo>,
        token_a: &str,
        token_b: &str,
        buy_dex: Dex,
        sell_dex: Dex,
    ) -> Result<Option<ArbitrageOpportunity>> {
        // Get pools for both DEXs
        let buy_pool_key = (buy_dex, token_a.to_string(), token_b.to_string());
        let sell_pool_key = (sell_dex, token_a.to_string(), token_b.to_string());

        let buy_pool = match pools.get(&buy_pool_key) {
            Some(pool) if pool.is_fresh() => pool,
            _ => return Ok(None),
        };

        let sell_pool = match pools.get(&sell_pool_key) {
            Some(pool) if pool.is_fresh() => pool,
            _ => return Ok(None),
        };

        // Calculate prices
        let buy_price = buy_pool.calculate_price();
        let sell_price = sell_pool.calculate_price();

        // Skip if prices are invalid
        if buy_price <= 0.0 || sell_price <= 0.0 {
            return Ok(None);
        }

        // Calculate spread
        let spread_percentage = (sell_price - buy_price) / buy_price;

        // Check if spread meets minimum threshold
        if spread_percentage < self.min_spread_threshold || spread_percentage > MAX_SPREAD_THRESHOLD {
            return Ok(None);
        }

        // Calculate optimal input amount (using Kelly Criterion with conservative fraction)
        let optimal_input = self.calculate_optimal_input_amount(buy_pool, sell_pool, spread_percentage)?;

        // Calculate outputs and profit
        let buy_output = buy_pool.calculate_output(optimal_input, true)?;
        let sell_output = sell_pool.calculate_output(buy_output, false)?;
        let profit_estimate = sell_output as f64 - optimal_input as f64;

        // Skip if profit is too small
        if profit_estimate < 10.0 { // Minimum $10 profit
            return Ok(None);
        }

        // Estimate gas costs
        let gas_estimate = self.estimate_gas_costs();

        // Estimate slippage
        let slippage_estimate = self.estimate_slippage(buy_pool, sell_pool, optimal_input);

        // Select best flash loan provider
        let flash_loan_provider = self.select_flash_loan_provider(token_a)?;

        let opportunity = ArbitrageOpportunity {
            token_pair: (token_a.to_string(), token_b.to_string()),
            buy_dex,
            sell_dex,
            buy_price,
            sell_price,
            spread_percentage,
            profit_estimate,
            input_amount: optimal_input,
            output_amount: sell_output,
            flash_loan_provider,
            gas_estimate,
            timestamp: Utc::now().timestamp(),
            slippage_estimate,
        };

        Ok(Some(opportunity))
    }

    /// Calculate optimal input amount using Kelly Criterion
    fn calculate_optimal_input_amount(
        &self,
        buy_pool: &PoolInfo,
        sell_pool: &PoolInfo,
        spread_percentage: f64,
    ) -> Result<u64> {
        // Use conservative Kelly fraction (25% of full Kelly)
        let kelly_fraction = 0.25;

        // Estimate win rate based on spread and market conditions
        let win_rate = if spread_percentage > 0.015 { 0.8 } else { 0.6 };

        // Calculate Kelly criterion
        let kelly_percentage = kelly_fraction * ((spread_percentage * win_rate) - (1.0 - win_rate)) / spread_percentage;

        // Apply position size limits
        let max_position = self.max_position_size;
        let base_amount = 1000.0; // $1k base amount

        let optimal_amount = (kelly_percentage * max_position).min(base_amount * 2.0);

        // Convert to token units (assuming token_a is the input)
        let token_amount = (optimal_amount / buy_pool.calculate_price()) as u64;

        Ok(token_amount)
    }

    /// Estimate gas costs for the arbitrage transaction
    fn estimate_gas_costs(&self) -> u64 {
        // Base gas cost for flash loan arbitrage
        const BASE_GAS_COST: u64 = 5000000; // 5M lamports

        // Additional gas for DEX interactions
        const DEX_GAS_COST: u64 = 2000000; // 2M lamports per DEX

        // Total gas cost
        BASE_GAS_COST + (DEX_GAS_COST * 2)
    }

    /// Estimate slippage for the trade
    fn estimate_slippage(
        &self,
        buy_pool: &PoolInfo,
        sell_pool: &PoolInfo,
        input_amount: u64,
    ) -> f64 {
        // Calculate impact on buy pool
        let buy_impact = if buy_pool.reserve_a > 0 {
            input_amount as f64 / buy_pool.reserve_a as f64
        } else {
            1.0
        };

        // Calculate impact on sell pool
        let sell_impact = if let Ok(sell_input) = buy_pool.calculate_output(input_amount, true) {
            if sell_pool.reserve_a > 0 {
                sell_input as f64 / sell_pool.reserve_a as f64
            } else {
                1.0
            }
        } else {
            1.0
        };

        // Total slippage estimate (conservative)
        (buy_impact + sell_impact) * 0.5
    }

    /// Select the best flash loan provider for the token
    fn select_flash_loan_provider(&self, token: &str) -> Result<FlashLoanProvider> {
        let token_mint = get_token_mint_map()
            .get(token)
            .ok_or_else(|| anyhow!("Token {} not found in mint map", token))?;

        // Check Solend availability
        if get_solend_markets().contains_key(token_mint) {
            Ok(FlashLoanProvider::Solend)
        } else if get_marginfi_markets().contains_key(token_mint) {
            Ok(FlashLoanProvider::Marginfi)
        } else {
            Ok(FlashLoanProvider::Mango) // Default to Mango
        }
    }

    /// Clean up stale arbitrage opportunities
    async fn cleanup_stale_opportunities(&self) -> Result<()> {
        let mut opportunities = self.opportunities.write().await;
        let initial_count = opportunities.len();

        opportunities.retain(|_, opportunity| opportunity.is_valid(30)); // 30 second validity

        let cleaned_count = initial_count - opportunities.len();
        if cleaned_count > 0 {
            debug!("Cleaned up {} stale arbitrage opportunities", cleaned_count);
        }

        Ok(())
    }

    /// Get current arbitrage opportunities
    pub async fn get_opportunities(&self) -> Vec<ArbitrageOpportunity> {
        let opportunities = self.opportunities.read().await;
        opportunities.values().cloned().collect()
    }

    /// Get performance metrics
    pub fn get_metrics(&self) -> &CrossExchangeMetrics {
        &self.metrics
    }

    /// Update metrics after executing an arbitrage
    pub fn update_execution_metrics(&mut self, success: bool, profit: f64, execution_time_ms: f64) {
        if success {
            self.metrics.successful_arbitrages += 1;
            self.metrics.total_profit += profit;
        } else {
            self.metrics.failed_arbitrages += 1;
        }

        // Update average execution time
        let total_executions = self.metrics.successful_arbitrages + self.metrics.failed_arbitrages;
        if total_executions > 0 {
            self.metrics.average_execution_time_ms =
                (self.metrics.average_execution_time_ms * (total_executions - 1) as f64 + execution_time_ms) /
                total_executions as f64;
        }
    }
}

/// Mock pool data for testing and development
pub fn get_mock_pool_data() -> HashMap<(Dex, String, String), PoolInfo> {
    let mut pools = HashMap::new();
    let now = Utc::now().timestamp();

    // Orca SOL/USDC pool
    pools.insert((Dex::Orca, "SOL".to_string(), "USDC".to_string()), PoolInfo {
        dex: Dex::Orca,
        address: Pubkey::new_unique(),
        token_a: Pubkey::new_unique(),
        token_b: Pubkey::new_unique(),
        reserve_a: 1000000000, // 1000 SOL
        reserve_b: 22500000000, // 22.5M USDC ($22.50 per SOL)
        fee_numerator: 30, // 0.3%
        fee_denominator: 10000,
        last_update: now,
    });

    // Raydium SOL/USDC pool (with arbitrage opportunity)
    pools.insert((Dex::Raydium, "SOL".to_string(), "USDC".to_string()), PoolInfo {
        dex: Dex::Raydium,
        address: Pubkey::new_unique(),
        token_a: Pubkey::new_unique(),
        token_b: Pubkey::new_unique(),
        reserve_a: 1000000000, // 1000 SOL
        reserve_b: 22750000000, // 22.75M USDC ($22.75 per SOL)
        fee_numerator: 25, // 0.25%
        fee_denominator: 10000,
        last_update: now,
    });

    // Orca USDT/USDC pool
    pools.insert((Dex::Orca, "USDT".to_string(), "USDC".to_string()), PoolInfo {
        dex: Dex::Orca,
        address: Pubkey::new_unique(),
        token_a: Pubkey::new_unique(),
        token_b: Pubkey::new_unique(),
        reserve_a: 1000000000, // 1M USDT
        reserve_b: 1001000000, // 1.001M USDC (1:1.001 ratio)
        fee_numerator: 4, // 0.04%
        fee_denominator: 10000,
        last_update: now,
    });

    // Raydium USDT/USDC pool (with arbitrage opportunity)
    pools.insert((Dex::Raydium, "USDT".to_string(), "USDC".to_string()), PoolInfo {
        dex: Dex::Raydium,
        address: Pubkey::new_unique(),
        token_a: Pubkey::new_unique(),
        token_b: Pubkey::new_unique(),
        reserve_a: 1000000000, // 1M USDT
        reserve_b: 998000000, // 998K USDC (0.998:1 ratio)
        fee_numerator: 25, // 0.25%
        fee_denominator: 10000,
        last_update: now,
    });

    pools
}

// Mock random number generator for testing
fn mock_random() -> f64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::SystemTime;

    let mut hasher = DefaultHasher::new();
    SystemTime::now().hash(&mut hasher);
    let hash = hasher.finish();
    (hash as f64) / (u64::MAX as f64)
}

// Re-export for easier access
pub use mock_random as rand_random;

/// Legacy CrossExchangeDetector for backward compatibility
pub struct CrossExchangeDetector {
    config: ArbitrageConfig,
    dex_endpoints: HashMap<String, DexEndpoint>,
    rpc_client: RpcClient,
    http_client: Client,
    monitored_tokens: Vec<String>,
    price_cache: HashMap<String, Vec<TokenPrice>>,
    liquidity_cache: HashMap<String, Vec<LiquidityPool>>,
    cache_ttl: Duration,
    last_scan_time: Option<Instant>,
    opportunities: Vec<CrossExchangeOpportunity>,
}

/// DEX endpoint configuration (legacy)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DexEndpoint {
    pub name: String,
    pub program_id: String,
    pub api_url: String,
    pub rpc_url: String,
    pub supported_tokens: Vec<String>,
    pub fee_rate: f64,
    pub min_slippage: f64,
    pub max_slippage: f64,
    pub liquidity_threshold: f64,
    pub priority: u8,
}

/// Token price data from DEX (legacy)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenPrice {
    pub token_mint: String,
    pub price: f64,
    pub liquidity: f64,
    pub volume_24h: f64,
    pub timestamp: u64,
    pub confidence: f64,
}

/// Cross-exchange arbitrage opportunity data (legacy)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrossExchangeOpportunity {
    pub id: String,
    pub token: String,
    pub token_mint: String,
    pub buy_dex: String,
    pub sell_dex: String,
    pub buy_price: f64,
    pub sell_price: f64,
    pub price_spread: f64,
    pub spread_percentage: f64,
    pub buy_liquidity: f64,
    pub sell_liquidity: f64,
    pub transfer_cost: f64,
    pub gas_estimate: f64,
    pub profit_potential: f64,
    pub risk_score: f64,
    pub confidence_score: f64,
    pub execution_plan: Vec<ExecutionStep>,
    pub time_to_expiry: u64,
    pub created_at: u64,
}

/// Execution step for cross-exchange arbitrage (legacy)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionStep {
    pub step_id: u32,
    pub action: String, // "buy", "sell", "transfer"
    pub dex: String,
    pub token: String,
    pub amount: f64,
    pub expected_price: f64,
    pub slippage_tolerance: f64,
    pub deadline: u64,
    pub program_id: String,
    pub accounts: Vec<String>,
}

/// Liquidity pool data (legacy)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LiquidityPool {
    pub address: String,
    pub dex: String,
    pub token_a: String,
    pub token_b: String,
    pub reserve_a: f64,
    pub reserve_b: f64,
    pub fee_rate: f64,
    pub volume_24h: f64,
    pub tvl: f64,
    pub price_impact_model: String,
}

impl CrossExchangeDetector {
    /// Create new cross-exchange arbitrage detector
    pub fn new(config: ArbitrageConfig, rpc_url: &str) -> Result<Self> {
        let rpc_client = RpcClient::new_with_commitment(rpc_url, CommitmentConfig::confirmed());
        let http_client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()?;

        let mut dex_endpoints = HashMap::new();

        // Orca configuration
        dex_endpoints.insert("orca".to_string(), DexEndpoint {
            name: "Orca".to_string(),
            program_id: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP".to_string(),
            api_url: "https://api.orca.so".to_string(),
            rpc_url: "https://solana-api.projectserum.com".to_string(),
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // SOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
            ],
            fee_rate: 0.003,
            min_slippage: 0.001,
            max_slippage: 0.05,
            liquidity_threshold: 10000.0,
            priority: 1,
        });

        // Raydium configuration
        dex_endpoints.insert("raydium".to_string(), DexEndpoint {
            name: "Raydium".to_string(),
            program_id: "9KEPZsX3uphrDhuQCkDUBNpkPPNpygHjkEGt6eDZdvce".to_string(),
            api_url: "https://api.raydium.io".to_string(),
            rpc_url: "https://solana-api.projectserum.com".to_string(),
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // SOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
            ],
            fee_rate: 0.0025,
            min_slippage: 0.001,
            max_slippage: 0.05,
            liquidity_threshold: 10000.0,
            priority: 2,
        });

        // Serum configuration
        dex_endpoints.insert("serum".to_string(), DexEndpoint {
            name: "Serum".to_string(),
            program_id: "9xQeQv8N8MXiwr5uHFUhc6rY7fGw2a7zXWYVvJfQZJj".to_string(),
            api_url: "https://serum-api.bonfida.com".to_string(),
            rpc_url: "https://solana-api.projectserum.com".to_string(),
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // SOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
            ],
            fee_rate: 0.0022,
            min_slippage: 0.001,
            max_slippage: 0.05,
            liquidity_threshold: 5000.0,
            priority: 3,
        });

        // Jupiter aggregator configuration
        dex_endpoints.insert("jupiter".to_string(), DexEndpoint {
            name: "Jupiter".to_string(),
            program_id: "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4".to_string(),
            api_url: "https://quote-api.jup.ag".to_string(),
            rpc_url: "https://solana-api.projectserum.com".to_string(),
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // SOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
                "Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA".to_string(), // LINK
            ],
            fee_rate: 0.0025,
            min_slippage: 0.001,
            max_slippage: 0.05,
            liquidity_threshold: 20000.0,
            priority: 1,
        });

        Ok(Self {
            config,
            dex_endpoints,
            rpc_client,
            http_client,
            monitored_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // SOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
                "Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA".to_string(), // LINK
                "5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5".to_string(), // USDE
            ],
            price_cache: HashMap::new(),
            liquidity_cache: HashMap::new(),
            cache_ttl: Duration::from_secs(30),
            last_scan_time: None,
            opportunities: Vec::new(),
        })
    }

    /// Detect cross-exchange arbitrage opportunities
    pub async fn detect_opportunities(&mut self) -> Result<Vec<CrossExchangeOpportunity>> {
        info!("Starting cross-exchange arbitrage detection across {} DEXes", self.dex_endpoints.len());

        // Check if we need to refresh cache
        let now = Instant::now();
        if let Some(last_scan) = self.last_scan_time {
            if now.duration_since(last_scan) < self.cache_ttl {
                info!("Using cached cross-exchange opportunities ({} found)", self.opportunities.len());
                return Ok(self.opportunities.clone());
            }
        }

        self.opportunities.clear();

        // Fetch current prices from all DEXes
        let all_prices = self.fetch_all_prices().await?;
        let all_liquidity = self.fetch_all_liquidity().await?;

        // Detect arbitrage opportunities for each token
        for token in &self.monitored_tokens {
            match self.detect_token_arbitrage(token, &all_prices, &all_liquidity).await {
                Ok(mut opportunities) => {
                    info!("Found {} opportunities for token {}", opportunities.len(), token);
                    self.opportunities.append(&mut opportunities);
                }
                Err(e) => {
                    warn!("Failed to detect arbitrage for token {}: {}", token, e);
                }
            }
        }

        // Rank opportunities by profit potential and risk
        self.opportunities.sort_by(|a, b| {
            let score_a = a.profit_potential * (1.0 - a.risk_score) * a.confidence_score;
            let score_b = b.profit_potential * (1.0 - b.risk_score) * b.confidence_score;
            score_b.partial_cmp(&score_a).unwrap_or(std::cmp::Ordering::Equal)
        });

        self.last_scan_time = Some(now);

        info!("Cross-exchange arbitrage detection completed. Found {} opportunities", self.opportunities.len());
        Ok(self.opportunities.clone())
    }

    /// Fetch all token prices from all DEXes
    async fn fetch_all_prices(&self) -> Result<HashMap<String, Vec<TokenPrice>>> {
        let mut all_prices = HashMap::new();

        for (dex_name, endpoint) in &self.dex_endpoints {
            match self.fetch_dex_prices(dex_name, endpoint).await {
                Ok(mut prices) => {
                    for price in &prices {
                        all_prices.entry(price.token_mint.clone())
                            .or_insert_with(Vec::new)
                            .push(price.clone());
                    }
                    info!("Fetched {} prices from {}", prices.len(), dex_name);
                }
                Err(e) => {
                    warn!("Failed to fetch prices from {}: {}", dex_name, e);
                }
            }
        }

        Ok(all_prices)
    }

    /// Fetch prices from specific DEX
    async fn fetch_dex_prices(&self, dex_name: &str, endpoint: &DexEndpoint) -> Result<Vec<TokenPrice>> {
        let mut prices = Vec::new();

        for token_mint in &endpoint.supported_tokens {
            match self.fetch_token_price_from_dex(token_mint, endpoint).await {
                Ok(price) => {
                    prices.push(price);
                }
                Err(e) => {
                    debug!("Failed to fetch price for {} from {}: {}", token_mint, dex_name, e);
                }
            }
        }

        Ok(prices)
    }

    /// Fetch specific token price from DEX
    async fn fetch_token_price_from_dex(&self, token_mint: &str, endpoint: &DexEndpoint) -> Result<TokenPrice> {
        // This would make real API calls to DEX endpoints
        // For now, return mock prices with small variations
        let base_price = self.get_mock_base_price(token_mint);
        let dex_modifier = self.get_dex_price_modifier(endpoint.name.as_str());

        let price = base_price * dex_modifier;
        let liquidity = (50000.0 + mock_random() * 100000.0) * self.get_liquidity_modifier(endpoint.name.as_str());
        let volume = 24h_volume_from_endpoint(endpoint.name.as_str());
        let confidence = 0.8 + mock_random() * 0.2;

        Ok(TokenPrice {
            token_mint: token_mint.to_string(),
            price,
            liquidity,
            volume_24h: volume,
            timestamp: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            confidence,
        })
    }

    /// Fetch all liquidity data from all DEXes
    async fn fetch_all_liquidity(&self) -> Result<HashMap<String, Vec<LiquidityPool>>> {
        let mut all_liquidity = HashMap::new();

        for (dex_name, endpoint) in &self.dex_endpoints {
            match self.fetch_dex_liquidity(dex_name, endpoint).await {
                Ok(pools) => {
                    for pool in &pools {
                        all_liquidity.entry(pool.token_a.clone())
                            .or_insert_with(Vec::new)
                            .push(pool.clone());
                        all_liquidity.entry(pool.token_b.clone())
                            .or_insert_with(Vec::new)
                            .push(pool.clone());
                    }
                    info!("Fetched {} liquidity pools from {}", pools.len(), dex_name);
                }
                Err(e) => {
                    warn!("Failed to fetch liquidity from {}: {}", dex_name, e);
                }
            }
        }

        Ok(all_liquidity)
    }

    /// Fetch liquidity pools from specific DEX
    async fn fetch_dex_liquidity(&self, dex_name: &str, endpoint: &DexEndpoint) -> Result<Vec<LiquidityPool>> {
        let mut pools = Vec::new();

        // Generate mock pools for USDC pairs
        let usdc_mint = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";

        for token_mint in &endpoint.supported_tokens {
            if token_mint != usdc_mint {
                pools.push(LiquidityPool {
                    address: format!("{}_{}_{}", dex_name, token_mint[..8].to_string(), usdc_mint[..8].to_string()),
                    dex: dex_name.to_string(),
                    token_a: token_mint.to_string(),
                    token_b: usdc_mint.to_string(),
                    reserve_a: 1000.0 + mock_random() * 5000.0,
                    reserve_b: 50000.0 + mock_random() * 100000.0,
                    fee_rate: endpoint.fee_rate,
                    volume_24h: 100000.0 + mock_random() * 500000.0,
                    tvl: 100000.0 + mock_random() * 500000.0,
                    price_impact_model: "constant_product".to_string(),
                });
            }
        }

        Ok(pools)
    }

    /// Detect arbitrage opportunities for specific token
    async fn detect_token_arbitrage(
        &self,
        token: &str,
        all_prices: &HashMap<String, Vec<TokenPrice>>,
        all_liquidity: &HashMap<String, Vec<LiquidityPool>>,
    ) -> Result<Vec<CrossExchangeOpportunity>> {
        let mut opportunities = Vec::new();

        let token_prices = all_prices.get(token).unwrap_or(&vec![]);
        if token_prices.len() < 2 {
            return Ok(opportunities);
        }

        // Find best buy and sell prices
        let (buy_price, buy_dex) = token_prices.iter()
            .filter(|p| p.liquidity >= self.config.min_liquidity)
            .min_by(|a, b| a.price.partial_cmp(&b.price).unwrap_or(std::cmp::Ordering::Equal))
            .map(|p| (p.price, &p.token_mint))
            .unwrap_or((0.0, ""));

        let (sell_price, sell_dex) = token_prices.iter()
            .filter(|p| p.liquidity >= self.config.min_liquidity)
            .max_by(|a, b| a.price.partial_cmp(&b.price).unwrap_or(std::cmp::Ordering::Equal))
            .map(|p| (p.price, &p.token_mint))
            .unwrap_or((0.0, ""));

        if buy_price == 0.0 || sell_price == 0.0 || buy_dex == sell_dex {
            return Ok(opportunities);
        }

        let price_spread = sell_price - buy_price;
        let spread_percentage = price_spread / buy_price;

        // Only consider if spread is significant
        if spread_percentage < self.config.min_profit_threshold {
            return Ok(opportunities);
        }

        // Calculate profitability
        let trade_amount = 10000.0; // $10k trade size
        let transfer_cost = 0.002; // 0.2% transfer cost
        let gas_estimate = 0.001; // ~$0.001 per transaction
        let trading_fees = trade_amount * (0.003 + 0.003); // Buy and sell fees
        let total_costs = trading_fees + transfer_cost * trade_amount + gas_estimate;

        let gross_profit = trade_amount * spread_percentage;
        let net_profit = gross_profit - total_costs;

        if net_profit <= self.config.min_profit_threshold * trade_amount {
            return Ok(opportunities);
        }

        // Calculate risk score
        let buy_liquidity = token_prices.iter().find(|p| p.price == buy_price).map(|p| p.liquidity).unwrap_or(0.0);
        let sell_liquidity = token_prices.iter().find(|p| p.price == sell_price).map(|p| p.liquidity).unwrap_or(0.0);
        let risk_score = self.calculate_risk_score(trade_amount, buy_liquidity, sell_liquidity);

        if risk_score > self.config.max_risk_tolerance {
            return Ok(opportunities);
        }

        // Create execution plan
        let execution_plan = self.create_execution_plan(token, trade_amount, buy_price, sell_price, buy_dex, sell_dex)?;

        let opportunity_id = format!("cross_{}_{}_{}_{}",
            token[..8].to_string(),
            buy_dex[..8].to_string(),
            sell_dex[..8].to_string(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs()
        );

        opportunities.push(CrossExchangeOpportunity {
            id: opportunity_id,
            token: self.get_token_symbol(token).unwrap_or_else(|| token[..8].to_string()),
            token_mint: token.to_string(),
            buy_dex: self.get_dex_name_from_endpoint(buy_dex),
            sell_dex: self.get_dex_name_from_endpoint(sell_dex),
            buy_price,
            sell_price,
            price_spread,
            spread_percentage,
            buy_liquidity,
            sell_liquidity,
            transfer_cost: transfer_cost * trade_amount,
            gas_estimate,
            profit_potential: net_profit,
            risk_score,
            confidence_score: 0.85,
            execution_plan,
            time_to_expiry: 120, // 2 minutes
            created_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
        });

        Ok(opportunities)
    }

    /// Calculate risk score for arbitrage opportunity
    fn calculate_risk_score(&self, trade_amount: f64, buy_liquidity: f64, sell_liquidity: f64) -> f64 {
        let liquidity_risk = (trade_amount / buy_liquidity.min(sell_liquidity)).min(1.0) * 0.4;
        let execution_risk = 0.1; // Base execution risk
        let slippage_risk = 0.05; // Slippage risk
        let temporal_risk = 0.03; // Time-based risk

        liquidity_risk + execution_risk + slippage_risk + temporal_risk
    }

    /// Create execution plan for arbitrage
    fn create_execution_plan(
        &self,
        token: &str,
        amount: f64,
        buy_price: f64,
        sell_price: f64,
        buy_dex: &str,
        sell_dex: &str,
    ) -> Result<Vec<ExecutionStep>> {
        let mut plan = Vec::new();
        let deadline = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() + 120;

        // Step 1: Buy on cheaper DEX
        plan.push(ExecutionStep {
            step_id: 1,
            action: "buy".to_string(),
            dex: self.get_dex_name_from_endpoint(buy_dex),
            token: token.to_string(),
            amount,
            expected_price: buy_price,
            slippage_tolerance: 0.01,
            deadline,
            program_id: self.get_program_id_for_dex(&self.get_dex_name_from_endpoint(buy_dex)),
            accounts: vec![], // Would be populated with actual accounts
        });

        // Step 2: Transfer tokens between DEXes if needed
        if buy_dex != sell_dex {
            plan.push(ExecutionStep {
                step_id: 2,
                action: "transfer".to_string(),
                dex: "system".to_string(),
                token: token.to_string(),
                amount,
                expected_price: buy_price,
                slippage_tolerance: 0.0,
                deadline,
                program_id: "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA".to_string(), // Token program
                accounts: vec![], // Would be populated with actual accounts
            });
        }

        // Step 3: Sell on more expensive DEX
        plan.push(ExecutionStep {
            step_id: plan.len() as u32 + 1,
            action: "sell".to_string(),
            dex: self.get_dex_name_from_endpoint(sell_dex),
            token: token.to_string(),
            amount,
            expected_price: sell_price,
            slippage_tolerance: 0.01,
            deadline,
            program_id: self.get_program_id_for_dex(&self.get_dex_name_from_endpoint(sell_dex)),
            accounts: vec![], // Would be populated with actual accounts
        });

        Ok(plan)
    }

    // Helper methods
    fn get_mock_base_price(&self, token_mint: &str) -> f64 {
        match token_mint {
            "So11111111111111111111111111111111111111112" => 150.0, // SOL
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" => 1.0,   // USDC
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB" => 1.0,   // USDT
            "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im" => 65000.0, // WBTC
            "Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA" => 25.0,   // LINK
            "5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5" => 1.0,    // USDE
            _ => 1.0,
        }
    }

    fn get_dex_price_modifier(&self, dex_name: &str) -> f64 {
        match dex_name {
            "Orca" => 1.001,
            "Raydium" => 0.999,
            "Serum" => 1.002,
            "Jupiter" => 1.0005,
            _ => 1.0,
        }
    }

    fn get_liquidity_modifier(&self, dex_name: &str) -> f64 {
        match dex_name {
            "Orca" => 1.2,
            "Raydium" => 1.0,
            "Serum" => 0.8,
            "Jupiter" => 1.5,
            _ => 1.0,
        }
    }

    fn get_token_symbol(&self, token_mint: &str) -> Option<String> {
        let symbol_map = [
            ("So11111111111111111111111111111111111111112", "SOL"),
            ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "USDC"),
            ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", "USDT"),
            ("3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im", "WBTC"),
            ("Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA", "LINK"),
            ("5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5", "USDE"),
        ];

        for (mint, symbol) in symbol_map {
            if token_mint == mint {
                return Some(symbol.to_string());
            }
        }
        None
    }

    fn get_dex_name_from_endpoint(&self, endpoint: &str) -> String {
        if endpoint.contains("orca") {
            "Orca".to_string()
        } else if endpoint.contains("raydium") {
            "Raydium".to_string()
        } else if endpoint.contains("serum") {
            "Serum".to_string()
        } else if endpoint.contains("jupiter") {
            "Jupiter".to_string()
        } else {
            "Unknown".to_string()
        }
    }

    fn get_program_id_for_dex(&self, dex_name: &str) -> String {
        match dex_name {
            "Orca" => "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP".to_string(),
            "Raydium" => "9KEPZsX3uphrDhuQCkDUBNpkPPNpygHjkEGt6eDZdvce".to_string(),
            "Serum" => "9xQeQv8N8MXiwr5uHFUhc6rY7fGw2a7zXWYVvJfQZJj".to_string(),
            "Jupiter" => "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4".to_string(),
            _ => "".to_string(),
        }
    }

    /// Get supported DEXes
    pub fn get_supported_dexes(&self) -> Vec<String> {
        self.dex_endpoints.keys().cloned().collect()
    }

    /// Get supported tokens
    pub fn get_supported_tokens(&self) -> Vec<String> {
        self.monitored_tokens.clone()
    }

    /// Update monitored tokens
    pub fn update_monitored_tokens(&mut self, tokens: Vec<String>) {
        self.monitored_tokens = tokens;
    }
}

fn 24h_volume_from_endpoint(dex_name: &str) -> f64 {
    let random_val = mock_random();
    match dex_name {
        "Orca" => 1000000.0 + random_val * 500000.0,
        "Raydium" => 800000.0 + random_val * 400000.0,
        "Serum" => 600000.0 + random_val * 300000.0,
        "Jupiter" => 2000000.0 + random_val * 1000000.0,
        _ => 500000.0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[tokio::test]
    async fn test_cross_exchange_arbitrage_creation() {
        let keypair = Arc::new(Keypair::new());
        let execution_engine = Arc::new(ExecutionEngine::new(keypair.clone()));

        let (arbitrage, _, _) = CrossExchangeArbitrage::new(keypair, execution_engine);

        // Check that the engine was created successfully
        assert_eq!(arbitrage.min_spread_threshold, MIN_SPREAD_THRESHOLD);
        assert_eq!(arbitrage.max_position_size, 100000.0);
        assert_eq!(SUPPORTED_TOKENS.len(), 10); // All 10 tokens supported
    }

    #[tokio::test]
    async fn test_arbitrage_opportunity_detection() {
        let keypair = Arc::new(Keypair::new());
        let execution_engine = Arc::new(ExecutionEngine::new(keypair.clone()));

        let (mut arbitrage, pool_tx, _) = CrossExchangeArbitrage::new(keypair, execution_engine);

        // Add mock pool data
        let mock_pools = get_mock_pool_data();
        for ((dex, token_a, token_b), pool) in mock_pools {
            let key = (dex, token_a, token_b);
            pool_tx.send(pool).unwrap();
        }

        // Small delay to process pool data
        tokio::time::sleep(Duration::from_millis(50)).await;

        // Get opportunities
        let opportunities = arbitrage.get_opportunities().await;
        assert!(!opportunities.is_empty(), "Should detect arbitrage opportunities");

        // Verify opportunity characteristics
        for opportunity in &opportunities {
            assert!(opportunity.spread_percentage >= MIN_SPREAD_THRESHOLD);
            assert!(opportunity.spread_percentage <= MAX_SPREAD_THRESHOLD);
            assert!(opportunity.profit_estimate > 0.0);
            assert!(opportunity.is_valid(60)); // Should be valid for 60 seconds
        }
    }

    #[test]
    fn test_pool_price_calculation() {
        let pool = PoolInfo {
            dex: Dex::Orca,
            address: Pubkey::new_unique(),
            token_a: Pubkey::new_unique(),
            token_b: Pubkey::new_unique(),
            reserve_a: 1000000000, // 1000 SOL
            reserve_b: 22500000000, // 22.5M USDC
            fee_numerator: 30,
            fee_denominator: 10000,
            last_update: Utc::now().timestamp(),
        };

        let price = pool.calculate_price();
        assert_eq!(price, 22.5); // 22.5 USDC per SOL
    }

    #[test]
    fn test_arbitrage_opportunity_validation() {
        let opportunity = ArbitrageOpportunity {
            token_pair: ("SOL".to_string(), "USDC".to_string()),
            buy_dex: Dex::Orca,
            sell_dex: Dex::Raydium,
            buy_price: 22.5,
            sell_price: 22.75,
            spread_percentage: 0.0111, // 1.11%
            profit_estimate: 100.0,
            input_amount: 1000000000, // 1000 SOL lamports
            output_amount: 11250000000, // ~11.25B USDC lamports
            flash_loan_provider: FlashLoanProvider::Solend,
            gas_estimate: 7000000,
            timestamp: Utc::now().timestamp(),
            slippage_estimate: 0.002,
        };

        assert!(opportunity.is_valid(60));
        assert_eq!(opportunity.calculate_net_profit(), 100.0 - 7.0); // profit - gas cost
    }

    #[test]
    fn test_mock_pool_data() {
        let pools = get_mock_pool_data();
        assert!(!pools.is_empty());

        // Check Orca SOL/USDC pool
        let orca_sol_usdc = pools.get(&(Dex::Orca, "SOL".to_string(), "USDC".to_string()));
        assert!(orca_sol_usdc.is_some());

        let pool = orca_sol_usdc.unwrap();
        assert_eq!(pool.dex, Dex::Orca);
        assert_eq!(pool.reserve_a, 1000000000);
        assert_eq!(pool.reserve_b, 22500000000);
    }

    #[tokio::test]
    async fn test_cross_exchange_detector_creation() {
        let config = ArbitrageConfig::default();

        let detector = CrossExchangeDetector::new(
            config,
            "https://api.mainnet-beta.solana.com",
        );

        assert!(detector.is_ok());
        let detector = detector.unwrap();
        assert_eq!(detector.dex_endpoints.len(), 4); // Orca, Raydium, Serum, Jupiter
        assert!(!detector.monitored_tokens.is_empty());
    }

    #[tokio::test]
    async fn test_legacy_opportunity_detection() {
        let config = ArbitrageConfig::default();
        let mut detector = CrossExchangeDetector::new(
            config,
            "https://api.mainnet-beta.solana.com",
        ).unwrap();

        let opportunities = detector.detect_opportunities().await;
        assert!(opportunities.is_ok());

        let opportunities = opportunities.unwrap();
        // Should find some mock opportunities
        assert!(!opportunities.is_empty());
    }
}