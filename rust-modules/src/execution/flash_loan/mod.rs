//! Flash Loan Protocol Integration Module
//! Supports Save, Solend, and Mango V4 flash loans for high-frequency trading

pub mod save_flash_loan;
pub mod flash_loan_router;

pub use save_flash_loan::*;
pub use flash_loan_router::*;

use anyhow::Result;
use solana_sdk::pubkey::Pubkey;
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlashLoanProtocol {
    Save,
    Solend,
    MangoV4,
}

impl FlashLoanProtocol {
    pub fn program_id(&self) -> Pubkey {
        match self {
            FlashLoanProtocol::Save => solana_program::pubkey!("SAVe7x8r3PUUyL6pzT6s3nr1T9b4wxxA2pYFnzFvLaV"),
            FlashLoanProtocol::Solend => solana_program::pubkey!("So1endDq2YkqhipRh3WViPa8hdiSpxWy6z3Z6tMCpAo"),
            FlashLoanProtocol::MangoV4 => solana_program::pubkey!("mangoSo11111111111111111111111111111111111"),
        }
    }

    pub fn fee_bps(&self) -> u64 {
        match self {
            FlashLoanProtocol::Save => 3,      // 0.03%
            FlashLoanProtocol::Solend => 5,    // 0.05%
            FlashLoanProtocol::MangoV4 => 8,    // 0.08%
        }
    }

    pub fn max_latency_ms(&self) -> u64 {
        match self {
            FlashLoanProtocol::Save => 20,     // Fastest
            FlashLoanProtocol::Solend => 30,    // Medium
            FlashLoanProtocol::MangoV4 => 40,    // Slowest
        }
    }
}

#[derive(Debug, Clone)]
pub struct FlashLoanMetrics {
    pub protocol: FlashLoanProtocol,
    pub total_loans: u64,
    pub successful_loans: u64,
    pub average_execution_time_ms: f64,
    pub total_fees_paid: u64,
    pub total_profit: u64,
}

impl Default for FlashLoanMetrics {
    fn default() -> Self {
        Self {
            protocol: FlashLoanProtocol::Save,
            total_loans: 0,
            successful_loans: 0,
            average_execution_time_ms: 0.0,
            total_fees_paid: 0,
            total_profit: 0,
        }
    }
}

pub struct FlashLoanManager {
    metrics: HashMap<FlashLoanProtocol, FlashLoanMetrics>,
}

impl FlashLoanManager {
    pub fn new() -> Self {
        let mut metrics = HashMap::new();
        metrics.insert(FlashLoanProtocol::Save, FlashLoanMetrics::default());
        metrics.insert(FlashLoanProtocol::Solend, FlashLoanMetrics::default());
        metrics.insert(FlashLoanProtocol::MangoV4, FlashLoanMetrics::default());

        Self { metrics }
    }

    pub fn get_best_protocol(&self, available_amount: u64) -> FlashLoanProtocol {
        // Choose protocol based on amount and performance requirements
        if available_amount <= 5_000_000_000 {
            // For small amounts (<5 SOL), use Save (lowest fees, fastest)
            FlashLoanProtocol::Save
        } else if available_amount <= 50_000_000_000 {
            // For medium amounts, use Solend (balanced)
            FlashLoanProtocol::Solend
        } else {
            // For large amounts, use Mango V4 (highest liquidity)
            FlashLoanProtocol::MangoV4
        }
    }

    pub fn update_metrics(&mut self, protocol: FlashLoanProtocol, success: bool, execution_time_ms: u64, fees_paid: u64, profit: u64) {
        let metrics = self.metrics.entry(protocol).or_insert_with(FlashLoanMetrics::default);

        metrics.total_loans += 1;
        if success {
            metrics.successful_loans += 1;
        }

        // Update rolling average execution time
        metrics.average_execution_time_ms = (metrics.average_execution_time_ms * (metrics.total_loans - 1) as f64 + execution_time_ms as f64) / metrics.total_loans as f64;

        metrics.total_fees_paid += fees_paid;
        metrics.total_profit += profit;
    }

    pub fn get_metrics(&self, protocol: &FlashLoanProtocol) -> Option<&FlashLoanMetrics> {
        self.metrics.get(protocol)
    }

    pub fn get_success_rate(&self, protocol: &FlashLoanProtocol) -> f64 {
        if let Some(metrics) = self.get_metrics(protocol) {
            if metrics.total_loans > 0 {
                metrics.successful_loans as f64 / metrics.total_loans as f64
            } else {
                0.0
            }
        } else {
            0.0
        }
    }
}