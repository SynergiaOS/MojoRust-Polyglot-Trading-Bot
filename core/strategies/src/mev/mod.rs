//! MEV (Maximum Extractable Value) Strategies Module
//!
//! This module provides comprehensive MEV extraction strategies for Solana DEXes,
//! including sandwich attacks, arbitrage, and other advanced MEV techniques.

pub mod sandwich;
pub mod front_running;
pub mod back_running;
pub mod liquidation;
pub mod arbitrage;

pub use sandwich::*;
pub use front_running::*;
pub use back_running::*;
pub use liquidation::*;
pub use arbitrage::*;

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant};

/// MEV strategy engine
pub struct MEVEngine {
    strategies: HashMap<String, Box<dyn MEVStrategy>>,
    config: MEVConfig,
    performance_metrics: MEVMetrics,
}

/// MEV configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MEVConfig {
    /// Enable MEV extraction
    pub enable_mev: bool,
    /// Maximum gas price in lamports
    pub max_gas_price: u64,
    /// Minimum profit threshold in lamports
    pub min_profit_threshold: u64,
    /// Risk tolerance level (0.0 - 1.0)
    pub risk_tolerance: f64,
    /// Maximum concurrent MEV operations
    pub max_concurrent_operations: usize,
    /// Strategy priorities
    pub strategy_priorities: HashMap<String, u8>,
}

/// MEV performance metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MEVMetrics {
    pub total_opportunities: u64,
    pub successful_extractions: u64,
    pub total_profit: u64,
    pub total_gas_cost: u64,
    pub average_execution_time_ms: f64,
    pub success_rate: f64,
    pub strategy_performance: HashMap<String, StrategyMetrics>,
}

/// Strategy-specific metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StrategyMetrics {
    pub opportunities_found: u64,
    pub successful_extractions: u64,
    pub total_profit: u64,
    pub average_profit: f64,
    pub success_rate: f64,
}

/// Trait for MEV strategies
pub trait MEVStrategy: Send + Sync {
    /// Get strategy name
    fn name(&self) -> &str;

    /// Get strategy priority
    fn priority(&self) -> u8;

    /// Execute the strategy
    async fn execute(&mut self, opportunity: &MEVOpportunity) -> Result<MEVResult>;

    /// Get strategy configuration
    fn config(&self) -> &StrategyConfig;

    /// Check if strategy is enabled
    fn is_enabled(&self) -> bool;

    /// Get performance metrics
    fn get_metrics(&self) -> StrategyMetrics;
}

/// MEV opportunity
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MEVOpportunity {
    pub id: String,
    pub strategy_type: String,
    pub profit_potential: u64,
    pub gas_estimate: u64,
    pub urgency_level: f64,
    pub deadline: Instant,
    pub data: serde_json::Value,
}

/// MEV execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MEVResult {
    pub success: bool,
    pub actual_profit: u64,
    pub gas_cost: u64,
    pub net_profit: u64,
    pub execution_time_ms: u64,
    pub error_message: Option<String>,
    pub transaction_hash: Option<String>,
}

/// Strategy configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StrategyConfig {
    pub enabled: bool,
    pub priority: u8,
    pub min_profit_threshold: u64,
    pub max_gas_cost: u64,
    pub custom_params: HashMap<String, serde_json::Value>,
}

impl MEVEngine {
    /// Create new MEV engine
    pub fn new(config: MEVConfig) -> Self {
        Self {
            strategies: HashMap::new(),
            config,
            performance_metrics: MEVMetrics::default(),
        }
    }

    /// Add MEV strategy
    pub fn add_strategy(&mut self, strategy: Box<dyn MEVStrategy>) {
        let name = strategy.name().to_string();
        self.strategies.insert(name, strategy);
    }

    /// Process MEV opportunity
    pub async fn process_opportunity(&mut self, opportunity: MEVOpportunity) -> Result<MEVResult> {
        if !self.config.enable_mev {
            return Ok(MEVResult {
                success: false,
                actual_profit: 0,
                gas_cost: 0,
                net_profit: 0,
                execution_time_ms: 0,
                error_message: Some("MEV extraction is disabled".to_string()),
                transaction_hash: None,
            });
        }

        // Get strategy for this opportunity type
        let strategy = self.strategies.get_mut(&opportunity.strategy_type)
            .ok_or_else(|| anyhow!("No strategy found for type: {}", opportunity.strategy_type))?;

        if !strategy.is_enabled() {
            return Ok(MEVResult {
                success: false,
                actual_profit: 0,
                gas_cost: 0,
                net_profit: 0,
                execution_time_ms: 0,
                error_message: Some("Strategy is disabled".to_string()),
                transaction_hash: None,
            });
        }

        // Check if opportunity meets criteria
        if opportunity.profit_potential < self.config.min_profit_threshold {
            return Ok(MEVResult {
                success: false,
                actual_profit: 0,
                gas_cost: 0,
                net_profit: 0,
                execution_time_ms: 0,
                error_message: Some("Profit below threshold".to_string()),
                transaction_hash: None,
            });
        }

        // Execute strategy
        let result = strategy.execute(&opportunity).await?;

        // Update metrics
        self.update_metrics(&opportunity.strategy_type, &result);

        Ok(result)
    }

    /// Update performance metrics
    fn update_metrics(&mut self, strategy_name: &str, result: &MEVResult) {
        self.performance_metrics.total_opportunities += 1;

        if result.success {
            self.performance_metrics.successful_extractions += 1;
            self.performance_metrics.total_profit += result.net_profit;
        }

        self.performance_metrics.total_gas_cost += result.gas_cost;

        // Update strategy-specific metrics
        let strategy_metrics = self.performance_metrics.strategy_performance
            .entry(strategy_name.to_string())
            .or_insert_with(|| StrategyMetrics {
                opportunities_found: 0,
                successful_extractions: 0,
                total_profit: 0,
                average_profit: 0.0,
                success_rate: 0.0,
            });

        strategy_metrics.opportunities_found += 1;

        if result.success {
            strategy_metrics.successful_extractions += 1;
            strategy_metrics.total_profit += result.net_profit;
        }

        // Calculate success rates
        self.performance_metrics.success_rate =
            self.performance_metrics.successful_extractions as f64 /
            self.performance_metrics.total_opportunities as f64;

        if strategy_metrics.opportunities_found > 0 {
            strategy_metrics.success_rate =
                strategy_metrics.successful_extractions as f64 /
                strategy_metrics.opportunities_found as f64;

            strategy_metrics.average_profit =
                strategy_metrics.total_profit as f64 /
                strategy_metrics.successful_extractions as f64;
        }
    }

    /// Get performance metrics
    pub fn get_metrics(&self) -> &MEVMetrics {
        &self.performance_metrics
    }

    /// Get strategy list
    pub fn get_strategies(&self) -> Vec<&str> {
        self.strategies.keys().map(|s| s.as_str()).collect()
    }
}

impl Default for MEVConfig {
    fn default() -> Self {
        let mut strategy_priorities = HashMap::new();
        strategy_priorities.insert("sandwich".to_string(), 1);
        strategy_priorities.insert("arbitrage".to_string(), 2);
        strategy_priorities.insert("front_running".to_string(), 3);
        strategy_priorities.insert("liquidation".to_string(), 4);

        Self {
            enable_mev: false, // Disabled by default for safety
            max_gas_price: 1_000_000, // 0.001 SOL
            min_profit_threshold: 10_000_000, // 0.01 SOL
            risk_tolerance: 0.3,
            max_concurrent_operations: 3,
            strategy_priorities,
        }
    }
}

impl Default for MEVMetrics {
    fn default() -> Self {
        Self {
            total_opportunities: 0,
            successful_extractions: 0,
            total_profit: 0,
            total_gas_cost: 0,
            average_execution_time_ms: 0.0,
            success_rate: 0.0,
            strategy_performance: HashMap::new(),
        }
    }
}