//! QuickNode Lil' JIT Client Module
//!
//! This module provides a client for QuickNode's Lil' JIT service
//! enabling Jito bundle submission with dynamic priority fees
//! for MEV-protected transactions with <30ms latency.

use anyhow::{Result, Context};
use serde::{Deserialize, Serialize};
use solana_sdk::{
    compute_budget::ComputeBudgetInstruction,
    transaction::Transaction,
    pubkey::Pubkey,
    signature::Signature,
};
use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::timeout;
use tracing::{info, warn, error, debug, instrument};
use reqwest::Client;

/// Priority fee response from QuickNode API
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PriorityFeeResponse {
    pub recommended: u64,
    pub low: u64,
    pub medium: u64,
    pub high: u64,
    pub very_high: u64,
    pub last_updated: i64,
    pub confidence: f64,
}

/// Bundle submission request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleRequest {
    pub transactions: Vec<String>,
    pub priority_fee: u64,
    pub max_retries: u32,
    pub timeout_ms: u64,
}

/// Bundle submission response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleResponse {
    pub success: bool,
    pub bundle_id: String,
    pub signature: Option<String>,
    pub error: Option<String>,
    pub latency_ms: u64,
    pub slot: u64,
    pub confirmation_status: String,
}

/// Jito bundle statistics
#[derive(Debug, Clone, Default)]
pub struct LilJitStats {
    pub bundles_submitted: u64,
    pub bundles_successful: u64,
    pub bundles_failed: u64,
    pub average_latency_ms: f64,
    pub total_priority_fees: u64,
    pub success_rate: f64,
    pub last_submission_time: Option<SystemTime>,
    pub provider: String,
}

/// Configuration for QuickNode Lil' JIT client
#[derive(Debug, Clone)]
pub struct LilJitConfig {
    /// Lil' JIT endpoint URL
    pub lil_jit_endpoint: String,
    /// Priority fee API endpoint
    pub priority_fee_api: String,
    /// API key for authentication
    pub api_key: String,
    /// Minimum priority fee in lamports
    pub min_tip: u64,
    /// Maximum priority fee in lamports
    pub max_tip: u64,
    /// Connection timeout in seconds
    pub connection_timeout: u64,
    /// Request timeout in milliseconds
    pub request_timeout_ms: u64,
    /// Maximum retry attempts
    pub max_retries: u32,
    /// Urgency level for priority fees ("low", "medium", "high", "critical")
    pub urgency_level: String,
}

impl Default for LilJitConfig {
    fn default() -> Self {
        Self {
            lil_jit_endpoint: std::env::var("QUICKNODE_LIL_JIT_ENDPOINT")
                .unwrap_or_else(|_| "https://lil-jit.quicknode.com".to_string()),
            priority_fee_api: std::env::var("QUICKNODE_PRIORITY_FEE_API")
                .unwrap_or_else(|_| "https://api.quicknode.com/priority-fee".to_string()),
            api_key: std::env::var("QUICKNODE_LIL_JIT_API_KEY")
                .unwrap_or_else(|_| std::env::var("PRIORITY_FEE_API_KEY").unwrap_or_default()),
            min_tip: 1000, // 0.000001 SOL
            max_tip: 10000000, // 0.01 SOL
            connection_timeout: 30,
            request_timeout_ms: 5000,
            max_retries: 3,
            urgency_level: "medium".to_string(),
        }
    }
}

/// QuickNode Lil' JIT client for MEV-protected bundle submission
pub struct QuickNodeLilJitClient {
    config: LilJitConfig,
    http_client: Client,
    stats: LilJitStats,
    start_time: SystemTime,
}

impl QuickNodeLilJitClient {
    /// Create new Lil' JIT client with configuration
    pub fn new(config: LilJitConfig) -> Self {
        let http_client = Client::builder()
            .timeout(Duration::from_secs(config.connection_timeout))
            .user_agent("MojoRust-Trading-Bot/1.0")
            .build()
            .expect("Failed to create HTTP client");

        Self {
            config,
            http_client,
            stats: LilJitStats::default(),
            start_time: SystemTime::now(),
        }
    }

    /// Get dynamic priority fee from QuickNode API
    #[instrument(skip(self))]
    pub async fn get_dynamic_priority_fee(&self) -> Result<u64> {
        info!("Fetching dynamic priority fee from QuickNode API");

        let url = format!(
            "{}/v1/solana/priority-fees?urgency={}",
            self.config.priority_fee_api,
            self.config.urgency_level
        );

        let request_start = SystemTime::now();

        let response = timeout(
            Duration::from_millis(self.config.request_timeout_ms),
            self.http_client
                .get(&url)
                .header("Authorization", format!("Bearer {}", self.config.api_key))
                .header("Content-Type", "application/json")
                .send()
        )
        .await
        .context("Priority fee API request timeout")?
        .context("Failed to send priority fee request")?;

        let latency = request_start
            .elapsed()
            .unwrap_or_default()
            .as_millis() as u64;

        if response.status().is_success() {
            let fee_response: PriorityFeeResponse = response
                .json()
                .await
                .context("Failed to parse priority fee response")?;

            let recommended_fee = self.calculate_optimal_fee(&fee_response);

            info!(
                "Dynamic priority fee: {} lamports (latency: {}ms, confidence: {:.2}%)",
                recommended_fee, latency, fee_response.confidence * 100.0
            );

            Ok(recommended_fee)
        } else {
            let error_text = response.text().await.unwrap_or_default();
            error!("Priority fee API error: {} - {}", response.status(), error_text);

            // Fallback to minimum tip
            warn!("Using fallback priority fee: {} lamports", self.config.min_tip);
            Ok(self.config.min_tip)
        }
    }

    /// Calculate optimal priority fee based on urgency and market conditions
    fn calculate_optimal_fee(&self, fee_response: &PriorityFeeResponse) -> u64 {
        let base_fee = match self.config.urgency_level.as_str() {
            "low" => fee_response.low,
            "medium" => fee_response.medium,
            "high" => fee_response.high,
            "critical" => fee_response.very_high,
            _ => fee_response.recommended,
        };

        // Apply urgency multiplier
        let urgency_multiplier = match self.config.urgency_level.as_str() {
            "low" => 0.8,
            "medium" => 1.0,
            "high" => 1.5,
            "critical" => 2.5,
            _ => 1.0,
        };

        let adjusted_fee = (base_fee as f64 * urgency_multiplier) as u64;

        // Clamp within min/max bounds
        adjusted_fee
            .max(self.config.min_tip)
            .min(self.config.max_tip)
    }

    /// Add priority fee instruction to transaction
    pub fn add_priority_fee_instruction(&self, mut transaction: Transaction, priority_fee: u64) -> Transaction {
        // Create compute budget instruction for priority fee
        let priority_fee_instruction = ComputeBudgetInstruction::set_compute_unit_price(priority_fee);

        // Insert at the beginning of instructions
        transaction.message.instructions.insert(0, priority_fee_instruction);

        transaction
    }

    /// Submit transaction via Lil' JIT bundle
    #[instrument(skip(self, transaction))]
    pub async fn send_with_lil_jit(&mut self, transaction: Transaction) -> Result<String> {
        let request_start = SystemTime::now();

        // Get dynamic priority fee
        let priority_fee = self.get_dynamic_priority_fee().await
            .context("Failed to get dynamic priority fee")?;

        // Add priority fee instruction
        let transaction_with_fee = self.add_priority_fee_instruction(transaction, priority_fee);

        // Serialize transaction
        let serialized_tx = bincode::serialize(&transaction_with_fee)
            .context("Failed to serialize transaction")?;

        let tx_base64 = base64::encode(serialized_tx);

        // Create bundle request
        let bundle_request = BundleRequest {
            transactions: vec![tx_base64],
            priority_fee,
            max_retries: self.config.max_retries,
            timeout_ms: self.config.request_timeout_ms,
        };

        info!("Submitting bundle via Lil' JIT (priority fee: {} lamports)", priority_fee);

        // Submit bundle
        let response = timeout(
            Duration::from_millis(self.config.request_timeout_ms),
            self.http_client
                .post(&format!("{}/sendBundle", self.config.lil_jit_endpoint))
                .header("Authorization", format!("Bearer {}", self.config.api_key))
                .header("Content-Type", "application/json")
                .json(&bundle_request)
                .send()
        )
        .await
        .context("Lil' JIT bundle submission timeout")?
        .context("Failed to submit bundle to Lil' JIT")?;

        let latency = request_start
            .elapsed()
            .unwrap_or_default()
            .as_millis() as u64;

        if response.status().is_success() {
            let bundle_response: BundleResponse = response
                .json()
                .await
                .context("Failed to parse bundle response")?;

            self.update_stats(&bundle_response, latency, priority_fee);

            if bundle_response.success {
                info!(
                    "Bundle submitted successfully: {} (latency: {}ms, slot: {})",
                    bundle_response.bundle_id, latency, bundle_response.slot
                );
                Ok(bundle_response.bundle_id)
            } else {
                error!(
                    "Bundle submission failed: {} (error: {})",
                    bundle_response.bundle_id,
                    bundle_response.error.unwrap_or_default()
                );
                Err(anyhow::anyhow!("Bundle submission failed: {}",
                    bundle_response.error.unwrap_or_default()))
            }
        } else {
            let error_text = response.text().await.unwrap_or_default();
            error!("Lil' JIT API error: {} - {}", response.status(), error_text);
            Err(anyhow::anyhow!("Lil' JIT API error: {} - {}", response.status(), error_text))
        }
    }

    /// Submit multiple transactions as a bundle
    #[instrument(skip(self, transactions))]
    pub async fn send_bundle(&mut self, transactions: Vec<Transaction>) -> Result<String> {
        if transactions.is_empty() {
            return Err(anyhow::anyhow!("No transactions to submit"));
        }

        let request_start = SystemTime::now();

        // Get dynamic priority fee
        let priority_fee = self.get_dynamic_priority_fee().await
            .context("Failed to get dynamic priority fee")?;

        // Serialize all transactions with priority fee
        let mut serialized_txs = Vec::new();
        for transaction in transactions {
            let tx_with_fee = self.add_priority_fee_instruction(transaction, priority_fee);
            let serialized = bincode::serialize(&tx_with_fee)
                .context("Failed to serialize transaction")?;
            serialized_txs.push(base64::encode(serialized));
        }

        // Create bundle request
        let bundle_request = BundleRequest {
            transactions: serialized_txs,
            priority_fee,
            max_retries: self.config.max_retries,
            timeout_ms: self.config.request_timeout_ms,
        };

        info!("Submitting bundle with {} transactions via Lil' JIT", bundle_request.transactions.len());

        // Submit bundle
        let response = timeout(
            Duration::from_millis(self.config.request_timeout_ms),
            self.http_client
                .post(&format!("{}/sendBundle", self.config.lil_jit_endpoint))
                .header("Authorization", format!("Bearer {}", self.config.api_key))
                .header("Content-Type", "application/json")
                .json(&bundle_request)
                .send()
        )
        .await
        .context("Lil' JIT bundle submission timeout")?
        .context("Failed to submit bundle to Lil' JIT")?;

        let latency = request_start
            .elapsed()
            .unwrap_or_default()
            .as_millis() as u64;

        if response.status().is_success() {
            let bundle_response: BundleResponse = response
                .json()
                .await
                .context("Failed to parse bundle response")?;

            self.update_stats(&bundle_response, latency, priority_fee * transactions.len() as u64);

            if bundle_response.success {
                info!(
                    "Bundle submitted successfully: {} (transactions: {}, latency: {}ms, slot: {})",
                    bundle_response.bundle_id, transactions.len(), latency, bundle_response.slot
                );
                Ok(bundle_response.bundle_id)
            } else {
                error!(
                    "Bundle submission failed: {} (error: {})",
                    bundle_response.bundle_id,
                    bundle_response.error.unwrap_or_default()
                );
                Err(anyhow::anyhow!("Bundle submission failed: {}",
                    bundle_response.error.unwrap_or_default()))
            }
        } else {
            let error_text = response.text().await.unwrap_or_default();
            error!("Lil' JIT API error: {} - {}", response.status(), error_text);
            Err(anyhow::anyhow!("Lil' JIT API error: {} - {}", response.status(), error_text))
        }
    }

    /// Check bundle status
    #[instrument(skip(self))]
    pub async fn check_bundle_status(&self, bundle_id: &str) -> Result<BundleResponse> {
        let url = format!("{}/bundle/{}", self.config.lil_jit_endpoint, bundle_id);

        let response = self.http_client
            .get(&url)
            .header("Authorization", format!("Bearer {}", self.config.api_key))
            .send()
            .await
            .context("Failed to check bundle status")?;

        if response.status().is_success() {
            let bundle_response: BundleResponse = response
                .json()
                .await
                .context("Failed to parse bundle status response")?;

            debug!("Bundle {} status: {}", bundle_id, bundle_response.confirmation_status);
            Ok(bundle_response)
        } else {
            let error_text = response.text().await.unwrap_or_default();
            Err(anyhow::anyhow!("Bundle status check failed: {} - {}", response.status(), error_text))
        }
    }

    /// Update statistics
    fn update_stats(&mut self, response: &BundleResponse, latency_ms: u64, priority_fee: u64) {
        self.stats.bundles_submitted += 1;
        self.stats.last_submission_time = Some(SystemTime::now());
        self.stats.total_priority_fees += priority_fee;

        if response.success {
            self.stats.bundles_successful += 1;
        } else {
            self.stats.bundles_failed += 1;
        }

        // Update average latency
        let total_submissions = self.stats.bundles_submitted;
        self.stats.average_latency_ms =
            (self.stats.average_latency_ms * (total_submissions - 1) as f64 + latency_ms as f64) / total_submissions as f64;

        // Update success rate
        self.stats.success_rate =
            (self.stats.bundles_successful as f64 / total_submissions as f64) * 100.0;
    }

    /// Get current statistics
    pub fn get_stats(&self) -> &LilJitStats {
        &self.stats
    }

    /// Reset statistics
    pub fn reset_stats(&mut self) {
        self.stats = LilJitStats {
            provider: "quicknode_liljit".to_string(),
            ..Default::default()
        };
    }

    /// Print performance statistics
    pub fn print_stats(&self) {
        info!("=== QuickNode Lil' JIT Performance Statistics ===");
        info!("Bundles Submitted: {}", self.stats.bundles_submitted);
        info!("Bundles Successful: {}", self.stats.bundles_successful);
        info!("Bundles Failed: {}", self.stats.bundles_failed);
        info!("Success Rate: {:.2}%", self.stats.success_rate);
        info!("Average Latency: {:.2} ms", self.stats.average_latency_ms);
        info!("Total Priority Fees: {} lamports", self.stats.total_priority_fees);
        info!("Provider: {}", self.stats.provider);
        info!("Uptime: {:.2} minutes",
              self.start_time.elapsed().unwrap_or_default().as_secs_f64() / 60.0);
        info!("===============================================");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_liljit_config_default() {
        let config = LilJitConfig::default();
        assert_eq!(config.urgency_level, "medium");
        assert_eq!(config.min_tip, 1000);
        assert_eq!(config.max_tip, 10000000);
    }

    #[test]
    fn test_calculate_optimal_fee() {
        let config = LilJitConfig::default();
        let client = QuickNodeLilJitClient::new(config);

        let fee_response = PriorityFeeResponse {
            recommended: 5000,
            low: 3000,
            medium: 5000,
            high: 8000,
            very_high: 15000,
            last_updated: chrono::Utc::now().timestamp(),
            confidence: 0.85,
        };

        // Test medium urgency
        let fee = client.calculate_optimal_fee(&fee_response);
        assert_eq!(fee, 5000);

        // Test critical urgency
        let mut config = LilJitConfig::default();
        config.urgency_level = "critical".to_string();
        let client = QuickNodeLilJitClient::new(config);
        let fee = client.calculate_optimal_fee(&fee_response);
        assert_eq!(fee, 15000);
    }
}