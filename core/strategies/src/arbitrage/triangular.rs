//! Triangular Arbitrage Detection with Advanced Cycle Analysis
//!
//! This module provides sophisticated triangular arbitrage detection capabilities
//! for finding profitable trading cycles A -> B -> C -> A across different pools
//! on Solana DEXes. It features real-time price monitoring, path optimization,
//! and risk assessment for multi-hop arbitrage strategies.

use crate::arbitrage::{ArbitrageOpportunity, ArbitrageConfig};
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::time::sleep;
use log::{info, warn, error, debug};
use solana_sdk::{
    pubkey::Pubkey,
    commitment_config::CommitmentConfig,
    rpc_client::RpcClient,
};
use reqwest::Client;

/// Token pair representation for triangular arbitrage
#[derive(Debug, Clone, Hash, Eq, PartialEq)]
pub struct TokenPair {
    pub token_a: String,
    pub token_b: String,
}

impl TokenPair {
    pub fn new(token_a: String, token_b: String) -> Self {
        Self {
            token_a: token_a.min(token_b.clone()),
            token_b: token_a.max(token_b),
        }
    }
}

/// Liquidity pool for triangular arbitrage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriangularPool {
    pub address: String,
    pub dex_name: String,
    pub token_a: String,
    pub token_b: String,
    pub reserve_a: f64,
    pub reserve_b: f64,
    pub fee_rate: f64,
    pub volume_24h: f64,
    pub tvl: f64,
    pub last_updated: u64,
    pub price_impact_model: String,
}

/// Trading step in triangular arbitrage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriangularStep {
    pub from_token: String,
    pub to_token: String,
    pub pool_address: String,
    pub dex_name: String,
    pub input_amount: f64,
    pub expected_output: f64,
    pub price: f64,
    pub price_impact: f64,
    pub fees: f64,
    pub slippage: f64,
}

/// Complete triangular arbitrage cycle
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriangularCycle {
    pub id: String,
    pub tokens: Vec<String>, // A, B, C
    pub steps: Vec<TriangularStep>, // A->B, B->C, C->A
    pub start_amount: f64,
    pub end_amount: f64,
    pub gross_profit: f64,
    pub net_profit: f64,
    pub profit_percentage: f64,
    pub total_fees: f64,
    pub total_gas_estimate: f64,
    pub cycle_price: f64,
    pub execution_time_ms: u64,
    pub risk_score: f64,
    pub confidence_score: f64,
    pub max_slippage: f64,
    pub liquidity_score: f64,
    pub created_at: u64,
    expires_at: u64,
}

/// Enhanced triangular arbitrage opportunity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriangularOpportunity {
    pub id: String,
    pub cycle: TriangularCycle,
    pub arbitrage_type: String,
    pub best_route: Vec<String>,
    pub alternative_routes: Vec<Vec<String>>,
    pub execution_plan: Vec<ExecutionInstruction>,
    pub risk_assessment: RiskAssessment,
    pub profitability_analysis: ProfitabilityAnalysis,
}

/// Risk assessment for triangular arbitrage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RiskAssessment {
    pub liquidity_risk: f64,
    pub execution_risk: f64,
    pub slippage_risk: f64,
    pub sandwich_risk: f64,
    pub temporal_risk: f64,
    pub overall_risk: f64,
    pub risk_factors: Vec<String>,
}

/// Profitability analysis
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProfitabilityAnalysis {
    pub gross_profit: f64,
    pub net_profit: f64,
    pub profit_percentage: f64,
    pub break_even_price: f64,
    pub margin_of_safety: f64,
    pub expected_duration: u64,
    pub confidence_interval: (f64, f64),
}

/// Execution instruction for triangular arbitrage
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionInstruction {
    pub step_number: u32,
    pub action: String, // "swap", "add_liquidity", "remove_liquidity"
    pub dex_name: String,
    pub pool_address: String,
    pub input_token: String,
    pub output_token: String,
    pub input_amount: f64,
    pub min_output_amount: f64,
    pub slippage_tolerance: f64,
    pub deadline: u64,
    pub program_id: String,
    pub accounts: Vec<String>,
}

/// Triangular arbitrage detector with advanced cycle detection
pub struct TriangularDetector {
    config: ArbitrageConfig,
    rpc_client: RpcClient,
    http_client: Client,
    pools: HashMap<String, Vec<TriangularPool>>, // dex_name -> pools
    token_graph: HashMap<String, HashMap<String, f64>>, // token -> (token -> price)
    supported_tokens: HashSet<String>,
    last_scan_time: Option<Instant>,
    cache_ttl: Duration,
    opportunities_cache: Vec<TriangularOpportunity>,
    cycle_detector: CycleDetectionEngine,
    route_optimizer: RouteOptimizer,
}

/// Advanced cycle detection engine
pub struct CycleDetectionEngine {
    max_cycle_length: usize,
    min_profit_threshold: f64,
    max_slippage: f64,
    liquidity_threshold: f64,
}

/// Route optimization engine
pub struct RouteOptimizer {
    fee_models: HashMap<String, f64>,
    liquidity_models: HashMap<String, String>,
    dex_priorities: HashMap<String, u8>,
}

impl TriangularDetector {
    /// Create new triangular arbitrage detector
    pub fn new(config: ArbitrageConfig, rpc_url: &str) -> Result<Self> {
        let rpc_client = RpcClient::new_with_commitment(rpc_url, CommitmentConfig::confirmed());
        let http_client = Client::builder()
            .timeout(Duration::from_secs(15))
            .build()?;

        // Initialize supported tokens
        let mut supported_tokens = HashSet::new();
        supported_tokens.insert("So11111111111111111111111111111111111111112".to_string()); // SOL
        supported_tokens.insert("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string()); // USDC
        supported_tokens.insert("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string()); // USDT
        supported_tokens.insert("3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string()); // WBTC
        supported_tokens.insert("Cwe8jPTkAirWEuiSHDgr7EBsl5S71TB3B9Dhnrx7cwnA".to_string()); // LINK
        supported_tokens.insert("5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5".to_string()); // USDE

        // Initialize cycle detection engine
        let cycle_detector = CycleDetectionEngine {
            max_cycle_length: 3,
            min_profit_threshold: config.min_profit_threshold,
            max_slippage: config.max_slippage,
            liquidity_threshold: config.min_liquidity,
        };

        // Initialize route optimizer
        let mut fee_models = HashMap::new();
        fee_models.insert("Orca".to_string(), 0.003);
        fee_models.insert("Raydium".to_string(), 0.0025);
        fee_models.insert("Serum".to_string(), 0.0022);
        fee_models.insert("Jupiter".to_string(), 0.0025);

        let mut liquidity_models = HashMap::new();
        liquidity_models.insert("Orca".to_string(), "constant_product".to_string());
        liquidity_models.insert("Raydium".to_string(), "constant_product".to_string());
        liquidity_models.insert("Serum".to_string(), "order_book".to_string());
        liquidity_models.insert("Jupiter".to_string(), "aggregated".to_string());

        let mut dex_priorities = HashMap::new();
        dex_priorities.insert("Jupiter".to_string(), 1);
        dex_priorities.insert("Orca".to_string(), 2);
        dex_priorities.insert("Raydium".to_string(), 3);
        dex_priorities.insert("Serum".to_string(), 4);

        let route_optimizer = RouteOptimizer {
            fee_models,
            liquidity_models,
            dex_priorities,
        };

        Ok(Self {
            config,
            rpc_client,
            http_client,
            pools: HashMap::new(),
            token_graph: HashMap::new(),
            supported_tokens,
            last_scan_time: None,
            cache_ttl: Duration::from_secs(60), // 1 minute cache
            opportunities_cache: Vec::new(),
            cycle_detector,
            route_optimizer,
        })
    }

    /// Detect triangular arbitrage opportunities with cycle detection
    pub async fn detect_opportunities(&mut self) -> Result<Vec<TriangularOpportunity>> {
        info!("Starting triangular arbitrage detection with cycle analysis");

        // Check cache validity
        let now = Instant::now();
        if let Some(last_scan) = self.last_scan_time {
            if now.duration_since(last_scan) < self.cache_ttl {
                info!("Using cached triangular opportunities ({} found)", self.opportunities_cache.len());
                return Ok(self.opportunities_cache.clone());
            }
        }

        // Fetch current pool data
        self.update_pool_data().await?;
        self.build_token_graph().await?;

        // Detect cycles
        let cycles = self.detect_cycles().await?;
        info!("Detected {} potential triangular cycles", cycles.len());

        // Convert cycles to opportunities
        let mut opportunities = Vec::new();
        for cycle in cycles {
            match self.convert_cycle_to_opportunity(cycle).await {
                Some(opportunity) => {
                    if self.is_opportunity_viable(&opportunity) {
                        opportunities.push(opportunity);
                    }
                }
                None => {}
            }
        }

        // Rank opportunities by profitability and risk
        opportunities.sort_by(|a, b| {
            let score_a = a.cycle.net_profit * (1.0 - a.risk_assessment.overall_risk) * a.cycle.confidence_score;
            let score_b = b.cycle.net_profit * (1.0 - b.risk_assessment.overall_risk) * b.cycle.confidence_score;
            score_b.partial_cmp(&score_a).unwrap_or(std::cmp::Ordering::Equal)
        });

        // Update cache
        self.opportunities_cache = opportunities.clone();
        self.last_scan_time = Some(now);

        info!("Triangular arbitrage detection completed. Found {} opportunities", opportunities.len());
        Ok(opportunities)
    }

    /// Update pool data from all supported DEXes
    async fn update_pool_data(&mut self) -> Result<()> {
        info!("Updating pool data from DEXes");

        // Orca pools
        match self.fetch_orca_pools().await {
            Ok(pools) => {
                self.pools.insert("Orca".to_string(), pools);
                info!("Fetched {} Orca pools", pools.len());
            }
            Err(e) => {
                warn!("Failed to fetch Orca pools: {}", e);
            }
        }

        // Raydium pools
        match self.fetch_raydium_pools().await {
            Ok(pools) => {
                self.pools.insert("Raydium".to_string(), pools);
                info!("Fetched {} Raydium pools", pools.len());
            }
            Err(e) => {
                warn!("Failed to fetch Raydium pools: {}", e);
            }
        }

        // Serum pools
        match self.fetch_serum_pools().await {
            Ok(pools) => {
                self.pools.insert("Serum".to_string(), pools);
                info!("Fetched {} Serum pools", pools.len());
            }
            Err(e) => {
                warn!("Failed to fetch Serum pools: {}", e);
            }
        }

        // Jupiter aggregated pools
        match self.fetch_jupiter_pools().await {
            Ok(pools) => {
                self.pools.insert("Jupiter".to_string(), pools);
                info!("Fetched {} Jupiter pools", pools.len());
            }
            Err(e) => {
                warn!("Failed to fetch Jupiter pools: {}", e);
            }
        }

        Ok(())
    }

    /// Build token price graph from pool data
    async fn build_token_graph(&mut self) -> Result<()> {
        info!("Building token price graph from {} pools",
              self.pools.values().map(|p| p.len()).sum::<usize>());

        self.token_graph.clear();

        for (dex_name, pools) in &self.pools {
            for pool in pools {
                // Skip pools with insufficient liquidity
                if pool.reserve_a < self.config.min_liquidity || pool.reserve_b < self.config.min_liquidity {
                    continue;
                }

                // Only include supported tokens
                if !self.supported_tokens.contains(&pool.token_a) || !self.supported_tokens.contains(&pool.token_b) {
                    continue;
                }

                // Calculate prices
                let price_a_to_b = pool.reserve_b / pool.reserve_a;
                let price_b_to_a = pool.reserve_a / pool.reserve_b;

                // Add to graph
                self.token_graph
                    .entry(pool.token_a.clone())
                    .or_insert_with(HashMap::new)
                    .insert(pool.token_b.clone(), price_a_to_b);

                self.token_graph
                    .entry(pool.token_b.clone())
                    .or_insert_with(HashMap::new)
                    .insert(pool.token_a.clone(), price_b_to_a);
            }
        }

        info!("Built token graph with {} tokens and {} edges",
              self.token_graph.len(),
              self.token_graph.values().map(|m| m.len()).sum::<usize>());

        Ok(())
    }

    /// Detect triangular cycles using DFS
    async fn detect_cycles(&self) -> Result<Vec<TriangularCycle>> {
        let mut cycles = Vec::new();
        let tokens: Vec<String> = self.supported_tokens.iter().cloned().collect();

        for start_token in &tokens {
            let mut visited = HashSet::new();
            let mut current_path = vec![start_token.clone()];
            self.find_triangular_cycles(start_token, &mut visited, &mut current_path, &tokens, &mut cycles)?;
        }

        // Filter and rank cycles
        cycles.retain(|cycle| {
            cycle.profit_percentage > self.config.min_profit_threshold &&
            cycle.risk_score < self.config.max_risk_tolerance &&
            cycle.max_slippage <= self.config.max_slippage
        });

        Ok(cycles)
    }

    /// Find triangular cycles using recursive DFS
    fn find_triangular_cycles(
        &self,
        current_token: &str,
        visited: &mut HashSet<String>,
        current_path: &mut Vec<String>,
        all_tokens: &[String],
        cycles: &mut Vec<TriangularCycle>,
    ) -> Result<()> {
        if current_path.len() == 3 {
            // Check if we can return to start
            let start_token = &current_path[0];
            if let Some(final_price) = self.token_graph.get(current_token).and_then(|m| m.get(start_token)) {
                let cycle = self.create_cycle_from_path(current_path, final_price)?;
                cycles.push(cycle);
            }
            return Ok(());
        }

        if current_path.len() >= 3 {
            return Ok(());
        }

        // Explore neighbors
        if let Some(neighbors) = self.token_graph.get(current_token) {
            for (next_token, _price) in neighbors {
                if !visited.contains(next_token) {
                    visited.insert(next_token.clone());
                    current_path.push(next_token.clone());

                    self.find_triangular_cycles(next_token, visited, current_path, all_tokens, cycles)?;

                    current_path.pop();
                    visited.remove(next_token);
                }
            }
        }

        Ok(())
    }

    /// Create cycle from path
    fn create_cycle_from_path(&self, path: &[String], final_price: f64) -> Result<TriangularCycle> {
        if path.len() != 3 {
            return Err(anyhow!("Invalid path length for triangular cycle"));
        }

        let start_amount = 1000.0; // Start with 1000 units of first token
        let mut current_amount = start_amount;
        let mut steps = Vec::new();
        let mut total_fees = 0.0;

        // Create steps for each trade
        for i in 0..3 {
            let from_token = &path[i];
            let to_token = &path[(i + 1) % 3];

            let price = if i == 2 {
                final_price
            } else {
                self.token_graph
                    .get(from_token)
                    .and_then(|m| m.get(to_token))
                    .ok_or_else(|| anyhow!("No price found for {} -> {}", from_token, to_token))?
            };

            // Find the best pool for this trade
            let pool = self.find_best_pool_for_pair(from_token, to_token)?;
            let fee_rate = self.route_optimizer.fee_models.get(&pool.dex_name).unwrap_or(&0.003);
            let fees = current_amount * fee_rate;
            total_fees += fees;

            let expected_output = current_amount * price * (1.0 - fee_rate);
            let price_impact = self.calculate_price_impact(current_amount, &pool);

            steps.push(TriangularStep {
                from_token: from_token.clone(),
                to_token: to_token.clone(),
                pool_address: pool.address.clone(),
                dex_name: pool.dex_name.clone(),
                input_amount: current_amount,
                expected_output,
                price,
                price_impact,
                fees,
                slippage: price_impact * 0.5, // Conservative slippage estimate
            });

            current_amount = expected_output;
        }

        let gross_profit = current_amount - start_amount;
        let net_profit = gross_profit - total_fees;
        let profit_percentage = net_profit / start_amount;

        // Calculate risk metrics
        let liquidity_score = self.calculate_liquidity_score(&steps);
        let risk_score = self.calculate_risk_score(&steps, profit_percentage);
        let confidence_score = self.calculate_confidence_score(&steps);

        let cycle_id = format!("triangular_{}_{}_{}_{}",
            path[0][..8].to_string(),
            path[1][..8].to_string(),
            path[2][..8].to_string(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs()
        );

        Ok(TriangularCycle {
            id: cycle_id,
            tokens: path.to_vec(),
            steps,
            start_amount,
            end_amount: current_amount,
            gross_profit,
            net_profit,
            profit_percentage,
            total_fees,
            total_gas_estimate: steps.len() as f64 * 0.001, // 0.001 SOL per swap
            cycle_price: start_amount,
            execution_time_ms: 1000, // Estimated 1 second
            risk_score,
            confidence_score,
            max_slippage: steps.iter().map(|s| s.slippage).fold(0.0, f64::max),
            liquidity_score,
            created_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            expires_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() + 120, // 2 minutes
        })
    }

    /// Find best pool for token pair
    fn find_best_pool_for_pair(&self, token_a: &str, token_b: &str) -> Result<&TriangularPool> {
        let mut best_pool = None;
        let mut best_score = 0.0;

        for pools in self.pools.values() {
            for pool in pools {
                if (pool.token_a == token_a && pool.token_b == token_b) ||
                   (pool.token_a == token_b && pool.token_b == token_a) {

                    // Score based on liquidity, volume, and DEX priority
                    let dex_priority = self.route_optimizer.dex_priorities.get(&pool.dex_name).unwrap_or(&10);
                    let liquidity_score = (pool.reserve_a + pool.reserve_b).log10();
                    let volume_score = pool.volume_24h.log10();

                    let score = liquidity_score + volume_score + (10.0 - *dex_priority as f64);

                    if score > best_score {
                        best_score = score;
                        best_pool = Some(pool);
                    }
                }
            }
        }

        best_pool.ok_or_else(|| anyhow!("No pool found for {} -> {}", token_a, token_b))
    }

    /// Convert cycle to opportunity
    async fn convert_cycle_to_opportunity(&self, cycle: TriangularCycle) -> Option<TriangularOpportunity> {
        let execution_plan = self.create_execution_plan(&cycle).await?;
        let risk_assessment = self.assess_risk(&cycle);
        let profitability_analysis = self.analyze_profitability(&cycle);

        Some(TriangularOpportunity {
            id: cycle.id.clone(),
            cycle,
            arbitrage_type: "triangular".to_string(),
            best_route: vec!["direct".to_string()],
            alternative_routes: vec![],
            execution_plan,
            risk_assessment,
            profitability_analysis,
        })
    }

    /// Create execution plan for cycle
    async fn create_execution_plan(&self, cycle: &TriangularCycle) -> Result<Vec<ExecutionInstruction>> {
        let mut plan = Vec::new();
        let deadline = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() + 120;

        for (i, step) in cycle.steps.iter().enumerate() {
            let program_id = self.get_program_id_for_dex(&step.dex_name);

            plan.push(ExecutionInstruction {
                step_number: i as u32,
                action: "swap".to_string(),
                dex_name: step.dex_name.clone(),
                pool_address: step.pool_address.clone(),
                input_token: step.from_token.clone(),
                output_token: step.to_token.clone(),
                input_amount: step.input_amount,
                min_output_amount: step.expected_output * (1.0 - step.slippage),
                slippage_tolerance: step.slippage,
                deadline,
                program_id,
                accounts: vec![], // Would be populated with actual accounts
            });
        }

        Ok(plan)
    }

    /// Assess risk for cycle
    fn assess_risk(&self, cycle: &TriangularCycle) -> RiskAssessment {
        let liquidity_risk = (1.0 - cycle.liquidity_score) * 0.4;
        let execution_risk = (cycle.steps.len() as f64) * 0.1;
        let slippage_risk = cycle.max_slippage * 0.3;
        let sandwich_risk = 0.05; // Fixed estimate for sandwich attacks
        let temporal_risk = if cycle.expires_at - SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs() < 60 {
            0.1
        } else {
            0.05
        };

        let overall_risk = (liquidity_risk + execution_risk + slippage_risk + sandwich_risk + temporal_risk) / 5.0;

        let mut risk_factors = Vec::new();
        if liquidity_risk > 0.2 { risk_factors.push("High liquidity risk".to_string()); }
        if slippage_risk > 0.1 { risk_factors.push("High slippage risk".to_string()); }
        if temporal_risk > 0.08 { risk_factors.push("Time pressure".to_string()); }

        RiskAssessment {
            liquidity_risk,
            execution_risk,
            slippage_risk,
            sandwich_risk,
            temporal_risk,
            overall_risk,
            risk_factors,
        }
    }

    /// Analyze profitability
    fn analyze_profitability(&self, cycle: &TriangularCycle) -> ProfitabilityAnalysis {
        let break_even_price = cycle.start_amount;
        let margin_of_safety = (cycle.end_amount - cycle.start_amount) / cycle.start_amount;
        let confidence_interval = (
            cycle.net_profit * 0.8, // Conservative estimate
            cycle.net_profit * 1.2,  // Optimistic estimate
        );

        ProfitabilityAnalysis {
            gross_profit: cycle.gross_profit,
            net_profit: cycle.net_profit,
            profit_percentage: cycle.profit_percentage,
            break_even_price,
            margin_of_safety,
            expected_duration: cycle.execution_time_ms,
            confidence_interval,
        }
    }

    // Helper methods
    fn calculate_price_impact(&self, amount: f64, pool: &TriangularPool) -> f64 {
        let total_liquidity = pool.reserve_a + pool.reserve_b;
        (amount / total_liquidity).min(0.05) // Cap at 5%
    }

    fn calculate_liquidity_score(&self, steps: &[TriangularStep]) -> f64 {
        let total_liquidity: f64 = steps.iter()
            .map(|step| step.input_amount)
            .sum();
        (total_liquidity / 1000.0).log10().min(1.0)
    }

    fn calculate_risk_score(&self, steps: &[TriangularStep], profit_percentage: f64) -> f64 {
        let liquidity_risk = steps.iter().map(|s| s.price_impact).sum::<f64>() / steps.len() as f64;
        let execution_risk = steps.len() as f64 * 0.1;
        let profit_risk = if profit_percentage < 0.01 { 0.3 } else if profit_percentage < 0.05 { 0.1 } else { 0.05 };

        (liquidity_risk + execution_risk + profit_risk) / 3.0
    }

    fn calculate_confidence_score(&self, steps: &[TriangularStep]) -> f64 {
        let avg_liquidity = steps.iter().map(|s| s.input_amount).sum::<f64>() / steps.len() as f64;
        let liquidity_factor = (avg_liquidity / 10000.0).min(1.0);
        let step_factor = 1.0 - (steps.len() as f64 - 3.0) * 0.1; // Penalty for extra steps

        liquidity_factor * step_factor
    }

    fn is_opportunity_viable(&self, opportunity: &TriangularOpportunity) -> bool {
        opportunity.cycle.net_profit > self.config.min_profit_threshold &&
        opportunity.risk_assessment.overall_risk < self.config.max_risk_tolerance &&
        opportunity.cycle.max_slippage <= self.config.max_slippage &&
        opportunity.cycle.liquidity_score > 0.3
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

    // Mock pool fetching methods (would be replaced with real API calls)
    async fn fetch_orca_pools(&self) -> Result<Vec<TriangularPool>> {
        Ok(vec![
            TriangularPool {
                address: "orca_sol_usdc".to_string(),
                dex_name: "Orca".to_string(),
                token_a: "So11111111111111111111111111111111111111112".to_string(),
                token_b: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(),
                reserve_a: 1000.0,
                reserve_b: 100000.0,
                fee_rate: 0.003,
                volume_24h: 500000.0,
                tvl: 100000.0,
                last_updated: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
                price_impact_model: "constant_product".to_string(),
            },
            // Add more pools as needed
        ])
    }

    async fn fetch_raydium_pools(&self) -> Result<Vec<TriangularPool>> {
        // Similar mock implementation for Raydium
        Ok(vec![])
    }

    async fn fetch_serum_pools(&self) -> Result<Vec<TriangularPool>> {
        // Similar mock implementation for Serum
        Ok(vec![])
    }

    async fn fetch_jupiter_pools(&self) -> Result<Vec<TriangularPool>> {
        // Similar mock implementation for Jupiter
        Ok(vec![])
    }

    /// Get supported tokens
    pub fn get_supported_tokens(&self) -> Vec<String> {
        self.supported_tokens.iter().cloned().collect()
    }

    /// Update supported tokens
    pub fn update_supported_tokens(&mut self, tokens: Vec<String>) {
        self.supported_tokens = tokens.into_iter().collect();
    }

    /// Get current pool statistics
    pub fn get_pool_statistics(&self) -> HashMap<String, usize> {
        let mut stats = HashMap::new();
        for (dex_name, pools) in &self.pools {
            stats.insert(dex_name.clone(), pools.len());
        }
        stats
    }

    /// Get token graph statistics
    pub fn get_graph_statistics(&self) -> (usize, usize) {
        let nodes = self.token_graph.len();
        let edges = self.token_graph.values().map(|m| m.len()).sum();
        (nodes, edges)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::signature::Keypair;

    #[tokio::test]
    async fn test_triangular_detector_creation() {
        let config = ArbitrageConfig::default();
        let detector = TriangularDetector::new(
            config,
            "https://api.mainnet-beta.solana.com",
        );

        assert!(detector.is_ok());
        let detector = detector.unwrap();
        assert!(!detector.supported_tokens.is_empty());
        assert_eq!(detector.supported_tokens.len(), 6); // SOL, USDC, USDT, WBTC, LINK, USDE
    }

    #[tokio::test]
    async fn test_opportunity_detection() {
        let config = ArbitrageConfig::default();
        let mut detector = TriangularDetector::new(
            config,
            "https://api.mainnet-beta.solana.com",
        ).unwrap();

        let opportunities = detector.detect_opportunities().await;
        assert!(opportunities.is_ok());
    }

    #[test]
    fn test_token_pair_creation() {
        let pair1 = TokenPair::new("tokenA".to_string(), "tokenB".to_string());
        let pair2 = TokenPair::new("tokenB".to_string(), "tokenA".to_string());

        assert_eq!(pair1.token_a, "tokenA");
        assert_eq!(pair1.token_b, "tokenB");
        assert_eq!(pair2.token_a, "tokenA");
        assert_eq!(pair2.token_b, "tokenB");
        assert_eq!(pair1, pair2);
    }
}