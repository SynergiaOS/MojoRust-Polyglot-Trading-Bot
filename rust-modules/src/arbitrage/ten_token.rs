//! 10-Token Arbitrage Scanner
//!
//! This module implements a high-performance arbitrage scanner that monitors
//! 10 specific tokens across multiple DEXes for price discrepancies and
//! calculates flash loan arbitrage opportunities.
//!
//! ## Features:
//! - Multi-DEX price monitoring (Raydium, Orca, Jupiter, Meteora)
//! - Real-time slippage calculation
//! - Flash loan profitability analysis
//! - DragonflyDB integration for opportunity publishing
//! - Adaptive fee calculation

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use deadpool_redis::{Config, Pool, Runtime};
use redis::AsyncCommands;
use serde::{Deserialize, Serialize};
use solana_sdk::pubkey::Pubkey;
use tokio::sync::RwLock;
use tokio::time::sleep;
use tracing::{debug, error, info, warn};

use crate::dex_clients::{JupiterDexClient, DexClientConfig};

/// Configuration for 10-token arbitrage scanner
#[derive(Debug, Clone)]
pub struct TenTokenConfig {
    pub enabled: bool,
    pub monitored_tokens: Vec<String>,
    pub monitored_dexes: Vec<String>,
    pub scan_interval_ms: u64,
    pub min_profit_threshold_sol: f64,
    pub use_flash_loan: bool,
    pub max_flash_loan_amount_sol: f64,
    pub slippage_tolerance_bps: u32,
    pub max_slippage_scan_amount_sol: f64,
    pub opportunity_ttl_seconds: u64,
    pub use_real_dex_clients: bool,
    pub dex_client_config: DexClientConfig,
}

impl Default for TenTokenConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            monitored_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // SOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263".to_string(), // BONK
                "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN".to_string(), // JUP
                "EKpQGSJtjMFqKv9KELdc4xf8WouxiyU4uAXPch3HdK7q".to_string(), // WIF
                "CPz731XDgEQGpiuSwT2k3g2VHcB3nKWKV4dN9RqcnHrN".to_string(), // PYTH
                "jupoAsG4cAbk3RYE8d53kVnJJ9TZRkNUBgzU1U2iAqL".to_string(), // JTO
                "orcaEKTdK7LKzNvaCvpjnwUv3jRuVxYDZPkMqP3hFyDS".to_string(), // ORCA
                "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R".to_string(), // RAY
            ],
            monitored_dexes: vec![
                "raydium".to_string(),
                "orca".to_string(),
                "jupiter".to_string(),
                "meteora".to_string(),
            ],
            scan_interval_ms: 500,
            min_profit_threshold_sol: 0.05,
            use_flash_loan: true,
            max_flash_loan_amount_sol: 100.0,
            slippage_tolerance_bps: 300,
            max_slippage_scan_amount_sol: 10.0,
            opportunity_ttl_seconds: 15,
            use_real_dex_clients: false, // Default to false for safety
            dex_client_config: DexClientConfig::default(),
        }
    }
}

/// Arbitrage opportunity representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ArbitrageOpportunity {
    pub token_pair: (String, String), // (base_token, quote_token)
    pub buy_dex: String,
    pub sell_dex: String,
    pub buy_price: f64,
    pub sell_price: f64,
    pub spread_percentage: f64,
    pub estimated_profit_sol: f64,
    pub required_capital_sol: f64,
    pub flash_loan_amount_sol: f64,
    pub confidence_score: f64,
    pub timestamp: u64,
    pub metadata: HashMap<String, String>,
}

/// DEX client trait for price fetching
#[async_trait::async_trait]
pub trait DexClient: Send + Sync {
    async fn get_token_price(&self, token_mint: &str) -> Result<Option<f64>>;
    async fn simulate_swap(&self, input_token: &str, output_token: &str, amount: f64) -> Result<Option<f64>>;
    async fn get_pool_liquidity(&self, token_mint: &str) -> Result<Option<f64>>;
}

/// Adapter for real Jupiter DEX client
pub struct RealJupiterAdapter {
    jupiter_client: JupiterDexClient,
    dex_name: String,
}

impl RealJupiterAdapter {
    pub fn new(jupiter_client: JupiterDexClient, dex_name: String) -> Self {
        Self { jupiter_client, dex_name }
    }
}

#[async_trait::async_trait]
impl DexClient for RealJupiterAdapter {
    async fn get_token_price(&self, token_mint: &str) -> Result<Option<f64>> {
        self.jupiter_client.get_token_price(token_mint).await
    }

    async fn simulate_swap(&self, input_token: &str, output_token: &str, amount: f64) -> Result<Option<f64>> {
        self.jupiter_client.simulate_swap(input_token, output_token, amount).await
    }

    async fn get_pool_liquidity(&self, token_mint: &str) -> Result<Option<f64>> {
        self.jupiter_client.get_pool_liquidity(token_mint).await
    }
}

/// Mock DEX client implementation (fallback)
pub struct MockDexClient {
    dex_name: String,
}

#[async_trait::async_trait]
impl DexClient for MockDexClient {
    async fn get_token_price(&self, token_mint: &str) -> Result<Option<f64>> {
        // Mock implementation - generate realistic prices with small variations
        let base_prices = HashMap::from([
            ("So11111111111111111111111111111111111111112", 150.0), // SOL
            ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1.0),   // USDC
            ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", 1.0),   // USDT
            ("DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", 0.00003), // BONK
            ("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", 0.85),    // JUP
            ("EKpQGSJtjMFqKv9KELdc4xf8WouxiyU4uAXPch3HdK7q", 1.2),    // WIF
            ("CPz731XDgEQGpiuSwT2k3g2VHcB3nKWKV4dN9RqcnHrN", 0.35),   // PYTH
            ("jupoAsG4cAbk3RYE8d53kVnJJ9TZRkNUBgzU1U2iAqL", 2.1),    // JTO
            ("orcaEKTdK7LKzNvaCvpjnwUv3jRuVxYDZPkMqP3hFyDS", 4.5),   // ORCA
            ("4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R", 2.8),    // RAY
        ]);

        let base_price = base_prices.get(token_mint).unwrap_or(&1.0);
        let variation = (fastrand::f64() - 0.5) * 0.02; // ±1% variation
        let price = base_price * (1.0 + variation);

        // Add DEX-specific variation
        let dex_variation = match self.dex_name.as_str() {
            "raydium" => 1.0 + (fastrand::f64() - 0.5) * 0.005, // ±0.25%
            "orca" => 1.0 + (fastrand::f64() - 0.5) * 0.003,  // ±0.15%
            "jupiter" => 1.0 + (fastrand::f64() - 0.5) * 0.002, // ±0.1%
            "meteora" => 1.0 + (fastrand::f64() - 0.5) * 0.004, // ±0.2%
            _ => 1.0,
        };

        Ok(Some(price * dex_variation))
    }

    async fn simulate_swap(&self, input_token: &str, output_token: &str, amount: f64) -> Result<Option<f64>> {
        let input_price = self.get_token_price(input_token).await?.unwrap_or(1.0);
        let output_price = self.get_token_price(output_token).await?.unwrap_or(1.0);

        // Add small slippage
        let slippage = 0.001 + fastrand::f64() * 0.002; // 0.1% - 0.3%
        let output_amount = (amount * input_price / output_price) * (1.0 - slippage);

        Ok(Some(output_amount))
    }

    async fn get_pool_liquidity(&self, token_mint: &str) -> Result<Option<f64>> {
        // Mock liquidity values
        let base_liquidities = HashMap::from([
            ("So11111111111111111111111111111111111111112", 500000.0), // SOL
            ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", 1000000.0), // USDC
            ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", 800000.0),   // USDT
        ]);

        let base_liquidity = base_liquidities.get(token_mint).unwrap_or(&100000.0);
        let variation = (fastrand::f64() - 0.5) * 0.2; // ±10% variation

        Ok(Some(base_liquidity * (1.0 + variation)))
    }
}

/// 10-Token Arbitrage Scanner
pub struct TenTokenArbitrageScanner {
    config: TenTokenConfig,
    token_prices: Arc<RwLock<HashMap<String, f64>>>,
    dex_clients: HashMap<String, Box<dyn DexClient>>,
    dragonfly_client: Pool,
    slippage_maps: Arc<RwLock<HashMap<String, f64>>>,
}

impl TenTokenArbitrageScanner {
    /// Creates a new arbitrage scanner
    pub fn new(config: TenTokenConfig, redis_url: &str) -> Result<Self> {
        let token_prices = Arc::new(RwLock::new(HashMap::new()));
        let slippage_maps = Arc::new(RwLock::new(HashMap::new()));

        // Initialize DEX clients
        let mut dex_clients: HashMap<String, Box<dyn DexClient>> = HashMap::new();
        for dex_name in &config.monitored_dexes {
            let client: Box<dyn DexClient> = if config.use_real_dex_clients && dex_name == "jupiter" {
                // Use real Jupiter client when enabled
                let jupiter_client = JupiterDexClient::new(config.dex_client_config.clone());
                Box::new(RealJupiterAdapter::new(jupiter_client, dex_name.clone()))
            } else {
                // Use mock clients for other DEXes or when real clients are disabled
                Box::new(MockDexClient { dex_name: dex_name.clone() })
            };
            dex_clients.insert(dex_name.clone(), client);
        }

        // Initialize DragonflyDB connection
        let cfg = Config::from_url(redis_url);
        let dragonfly_client = cfg.create_pool(Some(Runtime::Tokio1))?;

        Ok(Self {
            config,
            token_prices,
            dex_clients,
            dragonfly_client,
            slippage_maps,
        })
    }

    /// Starts the arbitrage scanning loop
    pub async fn start_scanning(&self) -> Result<()> {
        info!("Starting 10-token arbitrage scanner");
        info!("Monitoring {} tokens across {} DEXes",
              self.config.monitored_tokens.len(),
              self.config.monitored_dexes.len());

        let mut slippage_update_counter = 0;

        loop {
            let scan_start = Instant::now();

            // Update slippage maps periodically (every 10 scans)
            if slippage_update_counter % 10 == 0 {
                if let Err(e) = self.update_slippage_maps().await {
                    warn!("Failed to update slippage maps: {}", e);
                }
            }
            slippage_update_counter += 1;

            // Scan for arbitrage opportunities
            match self.scan_opportunities().await {
                Ok(opportunities) => {
                    if !opportunities.is_empty() {
                        info!("Found {} arbitrage opportunities", opportunities.len());

                        // Publish opportunities to DragonflyDB
                        if let Err(e) = self.publish_opportunities(opportunities).await {
                            error!("Failed to publish opportunities: {}", e);
                        }
                    }
                }
                Err(e) => {
                    error!("Error scanning opportunities: {}", e);
                }
            }

            // Sleep for the configured interval
            let elapsed = scan_start.elapsed();
            let sleep_duration = Duration::from_millis(self.config.scan_interval_ms);

            if elapsed < sleep_duration {
                sleep(sleep_duration - elapsed).await;
            }
        }
    }

    /// Scans for arbitrage opportunities across all monitored tokens and DEXes
    async fn scan_opportunities(&self) -> Result<Vec<ArbitrageOpportunity>> {
        let mut opportunities = Vec::new();

        // Fetch current prices from all DEXes
        let mut prices_by_dex: HashMap<String, HashMap<String, f64>> = HashMap::new();

        for dex_name in &self.config.monitored_dexes {
            if let Some(client) = self.dex_clients.get(dex_name) {
                let mut dex_prices = HashMap::new();

                for token_mint in &self.config.monitored_tokens {
                    if let Ok(Some(price)) = client.get_token_price(token_mint).await {
                        dex_prices.insert(token_mint.clone(), price);
                    }
                }

                prices_by_dex.insert(dex_name.clone(), dex_prices);
            }
        }

        // Compare prices across DEXes for each token
        for token_mint in &self.config.monitored_tokens {
            let mut best_buy = None;
            let mut best_sell = None;
            let mut best_buy_price = 0.0;
            let mut best_sell_price = 0.0;

            // Find best buy and sell prices
            for (dex_name, dex_prices) in &prices_by_dex {
                if let Some(&price) = dex_prices.get(token_mint) {
                    // Normalize to SOL equivalent for comparison
                    let sol_equivalent = if token_mint == "So11111111111111111111111111111111111111112" {
                        price // Already in SOL
                    } else {
                        // Convert to SOL equivalent (mock conversion)
                        price / 150.0
                    };

                    if best_buy.is_none() || sol_equivalent < best_buy_price {
                        best_buy = Some(dex_name.clone());
                        best_buy_price = sol_equivalent;
                    }

                    if best_sell.is_none() || sol_equivalent > best_sell_price {
                        best_sell = Some(dex_name.clone());
                        best_sell_price = sol_equivalent;
                    }
                }
            }

            // Calculate spread and check if it's profitable
            if let (Some(buy_dex), Some(sell_dex)) = (best_buy, best_sell) {
                if buy_dex != sell_dex {
                    let spread_percentage = ((best_sell_price - best_buy_price) / best_buy_price) * 100.0;

                    // Only consider opportunities with meaningful spread
                    if spread_percentage > 0.1 {
                        let opportunity = self.calculate_flash_loan_arbitrage(
                            token_mint,
                            &buy_dex,
                            &sell_dex,
                            best_buy_price,
                            best_sell_price,
                            spread_percentage,
                        ).await?;

                        if opportunity.estimated_profit_sol >= self.config.min_profit_threshold_sol {
                            opportunities.push(opportunity);
                        }
                    }
                }
            }
        }

        Ok(opportunities)
    }

    /// Calculates flash loan arbitrage opportunity details
    async fn calculate_flash_loan_arbitrage(
        &self,
        token_mint: &str,
        buy_dex: &str,
        sell_dex: &str,
        buy_price: f64,
        sell_price: f64,
        spread_percentage: f64,
    ) -> Result<ArbitrageOpportunity> {
        // Determine optimal flash loan amount
        let liquidity = self.get_dex_liquidity(buy_dex, token_mint).await.unwrap_or(10000.0);
        let optimal_amount = (liquidity * 0.1).min(self.config.max_flash_loan_amount_sol);

        // Flash loan fee (Save protocol: 0.03%)
        let flash_loan_fee = optimal_amount * 0.0003;

        // DEX fees (estimated)
        let dex_fees = optimal_amount * 0.003; // 0.3% total DEX fees

        // Slippage estimation using slippage maps
        let slippage_loss = self.get_slippage_estimate(buy_dex, token_mint, optimal_amount).await
            .unwrap_or(optimal_amount * (self.config.slippage_tolerance_bps as f64 / 10000.0));

        // Calculate gross profit
        let gross_profit = optimal_amount * (spread_percentage / 100.0);

        // Calculate net profit
        let net_profit = gross_profit - flash_loan_fee - dex_fees - slippage_loss;

        // Calculate confidence score based on spread and liquidity
        let confidence_score = (spread_percentage / 5.0).min(1.0) * (liquidity / 100000.0).min(1.0);

        let mut metadata = HashMap::new();
        metadata.insert("liquidity_usd".to_string(), liquidity.to_string());
        metadata.insert("flash_loan_fee_sol".to_string(), flash_loan_fee.to_string());
        metadata.insert("dex_fees_sol".to_string(), dex_fees.to_string());
        metadata.insert("slippage_loss_sol".to_string(), slippage_loss.to_string());

        Ok(ArbitrageOpportunity {
            token_pair: (token_mint.to_string(), "So11111111111111111111111111111111111111112".to_string()),
            buy_dex: buy_dex.to_string(),
            sell_dex: sell_dex.to_string(),
            buy_price,
            sell_price,
            spread_percentage,
            estimated_profit_sol: net_profit,
            required_capital_sol: optimal_amount + flash_loan_fee,
            flash_loan_amount_sol: optimal_amount,
            confidence_score,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            metadata,
        })
    }

    /// Gets liquidity for a token on a specific DEX
    async fn get_dex_liquidity(&self, dex_name: &str, token_mint: &str) -> Option<f64> {
        if let Some(client) = self.dex_clients.get(dex_name) {
            client.get_pool_liquidity(token_mint).await.ok().flatten()
        } else {
            None
        }
    }

    /// Gets slippage estimate from DragonflyDB slippage maps
    async fn get_slippage_estimate(&self, dex_name: &str, token_mint: &str, amount: f64) -> Option<f64> {
        let mut conn = self.dragonfly_client.get().await.ok()?;

        // Try to find exact match or closest larger amount
        let test_amounts = vec![amount, amount * 1.2, amount * 1.5, amount * 2.0];

        for test_amount in test_amounts {
            let slippage_key = format!("slippage:{}:{}:{}", dex_name, token_mint, test_amount);

            if let Ok(Some(slippage_value_str)) = redis::cmd("GET")
                .arg(&slippage_key)
                .query_async::<_, Option<String>>(&mut *conn)
                .await
            {
                if let Ok(slippage_value) = slippage_value_str.parse::<f64>() {
                    // Calculate slippage loss: (1 - slippage_value) * amount
                    let slippage_loss = (1.0 - slippage_value) * amount;
                    debug!("Found slippage estimate for {} {}: {:.6} loss per {} SOL",
                           dex_name, token_mint, slippage_loss, amount);
                    return Some(slippage_loss);
                }
            }
        }

        debug!("No slippage estimate found for {} {} with amount {}", dex_name, token_mint, amount);
        None
    }

    /// Publishes opportunities to DragonflyDB
    async fn publish_opportunities(&self, opportunities: Vec<ArbitrageOpportunity>) -> Result<()> {
        let mut conn = self.dragonfly_client.get().await
            .context("Failed to get DragonflyDB connection")?;

        for opportunity in opportunities {
            // Publish to arbitrage_opportunities channel (legacy)
            let payload = serde_json::to_string(&opportunity)
                .context("Failed to serialize opportunity")?;

            redis::cmd("PUBLISH")
                .arg("arbitrage_opportunities")
                .arg(&payload)
                .query_async(&mut *conn)
                .await
                .context("Failed to publish opportunity to arbitrage channel")?;

            // Add to orchestrator opportunity_queue
            let orchestrator_opportunity = serde_json::json!({
                "id": format!("arb_{}_{}_{}",
                    opportunity.token_pair.0.split_at(8).0,
                    opportunity.buy_dex,
                    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs()
                ),
                "strategy_type": "statistical_arbitrage",
                "token": opportunity.token_pair.0.clone(),
                "confidence": opportunity.confidence_score,
                "expected_return": opportunity.estimated_profit_sol,
                "risk_score": 0.2, // Low risk for arbitrage
                "required_capital": opportunity.required_capital_sol,
                "flash_loan_amount": opportunity.flash_loan_amount_sol,
                "timestamp": opportunity.timestamp,
                "ttl_seconds": self.config.opportunity_ttl_seconds,
                "metadata": {
                    "buy_dex": opportunity.buy_dex,
                    "sell_dex": opportunity.sell_dex,
                    "buy_price": opportunity.buy_price,
                    "sell_price": opportunity.sell_price,
                    "spread_percentage": opportunity.spread_percentage,
                    "token_pair": opportunity.token_pair,
                    "opportunity_type": "cross_dex_arbitrage"
                }
            });

            let orchestrator_payload = serde_json::to_string(&orchestrator_opportunity)
                .context("Failed to serialize orchestrator opportunity")?;

            // Add to opportunity_queue sorted set with score based on profit
            let score = opportunity.estimated_profit_sol * 1000.0 + opportunity.confidence_score * 100.0;
            redis::cmd("ZADD")
                .arg("opportunity_queue")
                .arg(score)
                .arg(&orchestrator_payload)
                .query_async(&mut *conn)
                .await
                .context("Failed to add opportunity to orchestrator queue")?;

            debug!("Published arbitrage opportunity to orchestrator: {} -> {}, profit: {} SOL, score: {:.2}",
                   opportunity.buy_dex, opportunity.sell_dex, opportunity.estimated_profit_sol, score);
        }

        Ok(())
    }

    /// Updates slippage maps by simulating trades of various sizes
    async fn update_slippage_maps(&self) -> Result<()> {
        debug!("Updating slippage maps...");

        for dex_name in &self.config.monitored_dexes {
            if let Some(client) = self.dex_clients.get(dex_name) {
                for token_mint in &self.config.monitored_tokens {
                    // Test different trade sizes
                    let test_amounts = vec![1.0, 5.0, 10.0, 25.0, 50.0];

                    for amount in test_amounts {
                        if amount <= self.config.max_slippage_scan_amount_sol {
                            if let Ok(Some(output_amount)) = client.simulate_swap(
                                token_mint,
                                "So11111111111111111111111111111111111111112",
                                amount
                            ).await {
                                let slippage_key = format!("slippage:{}:{}:{}", dex_name, token_mint, amount);
                                let slippage_value = output_amount / amount;

                                // Store in DragonflyDB with TTL
                                if let Ok(mut conn) = self.dragonfly_client.get().await {
                                    let _: () = redis::cmd("SETEX")
                                        .arg(&slippage_key)
                                        .arg(300) // 5 minutes TTL
                                        .arg(slippage_value.to_string())
                                        .query_async(&mut *conn)
                                        .await.unwrap_or_default();
                                }
                            }
                        }
                    }
                }
            }
        }

        debug!("Slippage maps updated");
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_ten_token_scanner_creation() {
        let config = TenTokenConfig::default();
        let scanner = TenTokenArbitrageScanner::new(config, "redis://localhost:6379");
        assert!(scanner.is_ok());
    }

    #[tokio::test]
    async fn test_mock_dex_client() {
        let client = MockDexClient { dex_name: "raydium".to_string() };

        let price = client.get_token_price("So11111111111111111111111111111111111111112").await.unwrap();
        assert!(price.is_some());
        assert!(price.unwrap() > 0.0);
    }

    #[test]
    fn test_arbitrage_opportunity_serialization() {
        let opportunity = ArbitrageOpportunity {
            token_pair: ("So11111111111111111111111111111111111111112".to_string(),
                        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string()),
            buy_dex: "raydium".to_string(),
            sell_dex: "orca".to_string(),
            buy_price: 150.0,
            sell_price: 151.5,
            spread_percentage: 1.0,
            estimated_profit_sol: 0.05,
            required_capital_sol: 100.0,
            flash_loan_amount_sol: 100.0,
            confidence_score: 0.8,
            timestamp: 1678886400,
            metadata: HashMap::new(),
        };

        let serialized = serde_json::to_string(&opportunity);
        assert!(serialized.is_ok());
    }
}