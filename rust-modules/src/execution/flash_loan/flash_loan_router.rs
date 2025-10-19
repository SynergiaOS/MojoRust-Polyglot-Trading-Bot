//! Flash Loan Router - Routes flash loan requests to optimal protocol
//! Automatically selects Save, Solend, or Mango V4 based on conditions

use anyhow::{anyhow, Result};
use log::{debug, info, warn};
use solana_sdk::pubkey::Pubkey;
use std::sync::Arc;
use tokio::time::{timeout, Duration};

use super::{FlashLoanProtocol, FlashLoanManager, FlashLoanRequest, FlashLoanResult};
use crate::execution::rpc_client::RpcClient;
use super::save_flash_loan::SaveFlashLoanEngine;

pub struct FlashLoanRouter {
    manager: Arc<FlashLoanManager>,
    save_engine: SaveFlashLoanEngine,
    rpc_client: Arc<RpcClient>,
}

impl FlashLoanRouter {
    pub fn new(rpc_client: Arc<RpcClient>) -> Self {
        let manager = Arc::new(FlashLoanManager::new());
        let save_engine = SaveFlashLoanEngine::new(
            super::save_flash_loan::SaveFlashLoanConfig::default(),
            rpc_client.clone(),
        );

        Self {
            manager,
            save_engine,
            rpc_client,
        }
    }

    /// Route flash loan request to optimal protocol
    pub async fn route_flash_loan(
        &self,
        keypair: &solana_sdk::signature::Keypair,
        request: FlashLoanRequest,
    ) -> Result<FlashLoanResult, Box<dyn std::error::Error>> {
        let protocol = self.manager.get_best_protocol(request.amount);
        info!("Routing flash loan to {:?} protocol", protocol);

        match protocol {
            FlashLoanProtocol::Save => {
                self.execute_save_flash_loan(keypair, request).await
            }
            FlashLoanProtocol::Solend => {
                warn!("Solend flash loan not yet implemented");
                Ok(FlashLoanResult {
                    success: false,
                    transaction_id: String::new(),
                    execution_time_ms: 0,
                    actual_amount_out: 0,
                    fees_paid: 0,
                    error_message: Some("Solend flash loan not yet implemented".to_string()),
                })
            }
            FlashLoanProtocol::MangoV4 => {
                warn!("Mango V4 flash loan not yet implemented");
                Ok(FlashLoanResult {
                    success: false,
                    transaction_id: String::new(),
                    execution_time_ms: 0,
                    actual_amount_out: 0,
                    fees_paid: 0,
                    error_message: Some("Mango V4 flash loan not yet implemented".to_string()),
                })
            }
        }
    }

    /// Execute Save flash loan with timeout and error handling
    async fn execute_save_flash_loan(
        &self,
        keypair: &solana_sdk::signature::Keypair,
        request: FlashLoanRequest,
    ) -> Result<FlashLoanResult, Box<dyn std::error::Error>> {
        // Set timeout based on protocol requirements
        let timeout_duration = Duration::from_millis(FlashLoanProtocol::Save.max_latency_ms());

        match timeout(timeout_duration, self.save_engine.execute_flash_loan_snipe(keypair, request)).await {
            Ok(result) => {
                self.manager.update_metrics(
                    FlashLoanProtocol::Save,
                    result.success,
                    result.execution_time_ms,
                    result.fees_paid,
                    result.actual_amount_out.saturating_sub(request.amount),
                );

                if result.success {
                    info!("Save flash loan executed successfully: {} SOL in {}ms",
                          request.amount / 1_000_000_000, result.execution_time_ms);
                } else {
                    warn!("Save flash loan failed: {:?}", result.error_message);
                }

                Ok(result)
            }
            Err(_) => {
                let error_msg = format!("Save flash loan timeout after {}ms", timeout_duration.as_millis());
                warn!("{}", error_msg);

                self.manager.update_metrics(
                    FlashLoanProtocol::Save,
                    false,
                    timeout_duration.as_millis(),
                    0,
                    0,
                );

                Ok(FlashLoanResult {
                    success: false,
                    transaction_id: String::new(),
                    execution_time_ms: timeout_duration.as_millis(),
                    actual_amount_out: 0,
                    fees_paid: 0,
                    error_message: Some(error_msg),
                })
            }
        }
    }

    /// Get performance metrics for all protocols
    pub fn get_performance_metrics(&self) -> super::FlashLoanMetrics {
        // Return metrics for the best performing protocol
        let mut best_protocol = FlashLoanProtocol::Save;
        let mut best_profit = 0u64;

        for protocol in [FlashLoanProtocol::Save, FlashLoanProtocol::Solend, FlashLoanProtocol::MangoV4] {
            if let Some(metrics) = self.manager.get_metrics(&protocol) {
                if metrics.total_profit > best_profit {
                    best_protocol = protocol.clone();
                    best_profit = metrics.total_profit;
                }
            }
        }

        self.manager.get_metrics(&best_protocol).cloned().unwrap_or_default()
    }

    /// Get success rate for specific protocol
    pub fn get_success_rate(&self, protocol: &FlashLoanProtocol) -> f64 {
        self.manager.get_success_rate(protocol)
    }

    /// Check if flash loan is available for given amount
    pub fn is_flash_loan_available(&self, amount: u64) -> bool {
        // Save can handle up to 5 SOL
        amount <= 5_000_000_000
    }

    /// Get estimated fees for flash loan
    pub fn estimate_fees(&self, amount: u64, protocol: Option<FlashLoanProtocol>) -> u64 {
        let protocol = protocol.unwrap_or_else(|| self.manager.get_best_protocol(amount));
        let fee_bps = protocol.fee_bps();
        amount * fee_bps / 10000
    }

    /// Get optimal protocol for given amount
    pub fn get_optimal_protocol(&self, amount: u64) -> FlashLoanProtocol {
        self.manager.get_best_protocol(amount)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[tokio::test]
    async fn test_flash_loan_routing() {
        let rpc_client = Arc::new(
            RpcClient::new("https://api.mainnet-beta.solana.com".to_string()).unwrap()
        );
        let router = FlashLoanRouter::new(rpc_client);

        // Test routing small amount (should use Save)
        let small_request = FlashLoanRequest {
            token_mint: solana_program::pubkey!("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
            amount: 1_000_000_000, // 1 SOL
            target_amount: 0,
            slippage_bps: 50,
            urgency_level: "high".to_string(),
        };

        let protocol = router.get_optimal_protocol(small_request.amount);
        assert_eq!(protocol, FlashLoanProtocol::Save);

        // Test routing large amount (should use Mango V4 when implemented)
        let large_request = FlashLoanRequest {
            token_mint: solana_program::pubkey!("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
            amount: 100_000_000_000, // 100 SOL
            target_amount: 0,
            slippage_bps: 50,
            urgency_level: "normal".to_string(),
        };

        let protocol = router.get_optimal_protocol(large_request.amount);
        // Note: Will return Save until Mango V4 is implemented
        assert_eq!(protocol, FlashLoanProtocol::Save);
    }

    #[test]
    fn test_fee_estimation() {
        let rpc_client = Arc::new(
            RpcClient::new("https://api.mainnet-beta.solana.com".to_string()).unwrap()
        );
        let router = FlashLoanRouter::new(rpc_client);

        // Test fee estimation for Save (0.03%)
        let amount = 5_000_000_000; // 5 SOL
        let fees = router.estimate_fees(amount, Some(FlashLoanProtocol::Save));
        assert_eq!(fees, 5_000_000_000 * 3 / 10000); // 0.03% of 5 SOL = 150,000 lamports = 0.00015 SOL
    }

    #[test]
    fn test_flash_loan_availability() {
        let rpc_client = Arc::new(
            RpcClient::new("https://api.mainnet-beta.solana.com".to_string()).unwrap()
        );
        let router = FlashLoanRouter::new(rpc_client);

        // Test small amount (should be available)
        assert!(router.is_flash_loan_available(1_000_000_000));

        // Test large amount (should not be available for Save)
        assert!(!router.is_flash_loan_available(10_000_000_000));
    }
}