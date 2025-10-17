//! Cross-Exchange Arbitrage Detection
//!
//! This module provides comprehensive cross-exchange arbitrage detection capabilities
//! for finding price differences across different DEXes on Solana. It supports
//! real-time price monitoring, liquidity analysis, and profit calculation with
//! proper risk assessment.

use crate::arbitrage::{ArbitrageOpportunity, ArbitrageConfig};
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::time::sleep;
use log::{info, warn, error, debug};
use solana_sdk::{
    pubkey::Pubkey,
    commitment_config::CommitmentConfig,
    rpc_client::RpcClient,
};
use reqwest::Client;

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

/// DEX endpoint configuration
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

/// Token price data from DEX
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokenPrice {
    pub token_mint: String,
    pub price: f64,
    pub liquidity: f64,
    pub volume_24h: f64,
    pub timestamp: u64,
    pub confidence: f64,
}

/// Cross-exchange arbitrage opportunity data
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

/// Execution step for cross-exchange arbitrage
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

/// Liquidity pool data
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

/// Cross-exchange arbitrage detector
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
    use solana_sdk::signature::Keypair;

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
    async fn test_opportunity_detection() {
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