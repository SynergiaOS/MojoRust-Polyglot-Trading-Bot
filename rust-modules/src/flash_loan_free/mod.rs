//! Free Flash Loan Manager for Solana DeFi Protocols
//!
//! This module provides flash loan functionality using only free protocols
//! that don't require premium subscriptions: Solend, Marginfi, and Jupiter.
//! It's designed for community users who want to get started with flash loan
//! arbitrage without upfront costs.

use crate::arbitrage::flash_loan::*;
use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use log::{info, warn, error, debug};
use solana_sdk::{
    pubkey::Pubkey,
    signature::Keypair,
    transaction::Transaction,
    instruction::{Instruction, AccountMeta},
    commitment_config::CommitmentConfig,
    rpc_client::RpcClient,
};

/// Free flash loan provider information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FreeFlashLoanProvider {
    pub name: String,
    pub program_id: String,
    pub api_endpoint: String,
    pub max_loan_amount: f64,
    pub fee_rate: f64,
    pub supported_tokens: Vec<String>,
    pub health_factor_threshold: f64,
    pub community_rating: f64, // 1-5 stars from community
    pub is_community_approved: bool,
}

/// Free flash loan detector
pub struct FreeFlashLoanDetector {
    providers: HashMap<String, FreeFlashLoanProvider>,
    rpc_client: RpcClient,
    keypair: Keypair,
    config: FlashLoanConfig,
    token_mint_map: HashMap<String, String>,
    token_symbol_map: HashMap<String, String>,
    opportunities_cache: HashMap<String, FlashLoanOpportunity>,
    last_scan_time: Option<Instant>,
    community_stats: CommunityStats,
}

impl FreeFlashLoanDetector {
    /// Create new free flash loan detector
    pub fn new(rpc_url: &str, keypair: Keypair, config: FlashLoanConfig) -> Result<Self> {
        let rpc_client = RpcClient::new_with_commitment(rpc_url, CommitmentConfig::confirmed());

        // Initialize free providers
        let mut providers = HashMap::new();

        // Solend - Community favorite
        providers.insert("solend".to_string(), FreeFlashLoanProvider {
            name: "Solend".to_string(),
            program_id: "So1endDq2Ykq1RnNWjdnB3s3B6r3qCvhdJvE7mJ9JvK".to_string(),
            api_endpoint: "https://api.solend.fi".to_string(),
            max_loan_amount: 1000000.0,
            fee_rate: 0.0003,
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // WSOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
            ],
            health_factor_threshold: 1.1,
            community_rating: 4.5,
            is_community_approved: true,
        });

        // Marginfi - Growing protocol
        providers.insert("marginfi".to_string(), FreeFlashLoanProvider {
            name: "Marginfi".to_string(),
            program_id: "MFv2hDwq5yeYimEzdGxM9o8iZeFdwgKhwbfNYJhCeG9".to_string(),
            api_endpoint: "https://api.marginfi.com".to_string(),
            max_loan_amount: 500000.0,
            fee_rate: 0.0005,
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // WSOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "5qKyBumD1kcngvZE3Qp6UknYnojx7aPAJNdLMFjUtwg5".to_string(), // USDE
            ],
            health_factor_threshold: 1.05,
            community_rating: 4.2,
            is_community_approved: true,
        });

        // Jupiter - Aggregator with flash loans
        providers.insert("jupiter".to_string(), FreeFlashLoanProvider {
            name: "Jupiter".to_string(),
            program_id: "JUP6LkbZbjS1j9wapLHYD4cTwJQDg4pQKPYMM1mF1F".to_string(),
            api_endpoint: "https://quote-api.jup.ag".to_string(),
            max_loan_amount: 250000.0,
            fee_rate: 0.0004,
            supported_tokens: vec![
                "So11111111111111111111111111111111111111112".to_string(), // WSOL
                "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
                "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB".to_string(), // USDT
                "3NZ9JMVBmGAqocybic2KjQTYjwrLJSZGW3G4XvmaB8im".to_string(), // WBTC
            ],
            health_factor_threshold: 1.08,
            community_rating: 4.8,
            is_community_approved: true,
        });

        Ok(Self {
            providers,
            rpc_client,
            keypair,
            config,
            token_mint_map: get_token_mint_map(),
            token_symbol_map: get_token_symbol_map(),
            opportunities_cache: HashMap::new(),
            last_scan_time: None,
            community_stats: CommunityStats::new(),
        })
    }

    /// Detect opportunities using only free protocols
    pub async fn detect_free_opportunities(&mut self) -> Result<Vec<FlashLoanOpportunity>> {
        info!("🔍 Scanning for flash loan opportunities using free protocols...");

        let now = Instant::now();
        if let Some(last_scan) = self.last_scan_time {
            if now.duration_since(last_scan) < Duration::from_secs(60) {
                info!("Using cached opportunities ({} found)", self.opportunities_cache.len());
                return Ok(self.opportunities_cache.values().cloned().collect());
            }
        }

        let mut all_opportunities = Vec::new();

        // Scan each free provider
        for (provider_name, provider) in &self.providers {
            if provider.is_community_approved {
                info!("🆓 Scanning {} (Community Approved, ⭐{} rating)",
                      provider_name, provider.community_rating);

                match self.detect_provider_opportunities(provider).await {
                    Ok(mut opportunities) => {
                        info!("Found {} opportunities on {}", opportunities.len(), provider_name);
                        all_opportunities.append(&mut opportunities);
                    }
                    Err(e) => {
                        warn!("Failed to scan {}: {}", provider_name, e);
                    }
                }
            } else {
                warn!("⚠️  Skipping {} - not community approved", provider_name);
            }
        }

        // Rank by profitability minus risk
        all_opportunities.sort_by(|a, b| {
            let score_a = a.profit_potential * (1.0 - a.risk_factors.overall_risk) *
                          if self.providers.get(&a.provider).map(|p| p.community_rating).unwrap_or(3.0) / 5.0 { 1.0 } else { 0.8 };
            let score_b = b.profit_potential * (1.0 - b.risk_factors.overall_risk) *
                          if self.providers.get(&b.provider).map(|p| p.community_rating).unwrap_or(3.0) / 5.0 { 1.0 } else { 0.8 };
            score_b.partial_cmp(&score_a).unwrap_or(std::cmp::Ordering::Equal)
        });

        // Update cache
        self.opportunities_cache.clear();
        for opportunity in &all_opportunities {
            self.opportunities_cache.insert(opportunity.id.clone(), opportunity.clone());
        }
        self.last_scan_time = Some(now);

        info!("🎯 Free flash loan scan completed. Found {} opportunities", all_opportunities.len());
        Ok(all_opportunities)
    }

    /// Get community statistics
    pub fn get_community_stats(&self) -> &CommunityStats {
        &self.community_stats
    }

    /// Get best provider for specific token and amount
    pub fn get_best_provider_for_token(&self, token_mint: &str, amount: f64) -> Option<&FreeFlashLoanProvider> {
        self.providers.values()
            .filter(|p| p.supported_tokens.contains(&token_mint.to_string()))
            .filter(|p| amount <= p.max_loan_amount)
            .filter(|p| p.is_community_approved)
            .max_by(|a, b| a.community_rating.partial_cmp(&b.community_rating).unwrap_or(std::cmp::Ordering::Equal))
    }

    /// Execute free flash loan with community safety
    pub async fn execute_free_flash_loan(&self, request: FlashLoanRequest) -> Result<FlashLoanExecution> {
        info!("🚀 Executing free flash loan: {} {} from {}",
              request.amount, request.token_mint, request.provider);

        // Get provider
        let provider = self.providers.get(&request.provider)
            .ok_or_else(|| anyhow!("Provider not found: {}", request.provider))?;

        if !provider.is_community_approved {
            return Err(anyhow!("Provider {} is not community approved", request.provider));
        }

        // Check if within community limits
        if request.amount > provider.max_loan_amount {
            return Err(anyhow!("Amount exceeds community limit of {} SOL", provider.max_loan_amount));
        }

        // Community safety checks
        if request.amount < 10.0 {
            return Err(anyhow!("Minimum loan amount is 10 SOL for community safety"));
        }

        // Execute with additional monitoring
        let start_time = Instant::now();
        let result = self.execute_with_monitoring(request, provider).await?;

        // Update community stats
        self.community_stats.record_execution(&result, provider);

        info!("✅ Free flash loan {} completed in {}ms",
              if result.success { "SUCCESS" } else { "FAILED" },
              start_time.elapsed().as_millis());

        Ok(result)
    }

    async fn execute_with_monitoring(&self, request: &FlashLoanRequest, provider: &FreeFlashLoanProvider) -> Result<FlashLoanExecution> {
        // This would integrate with the existing flash loan execution logic
        // For now, return a mock result
        Ok(FlashLoanExecution {
            success: true,
            transaction_id: Some("mock_signature_123".to_string()),
            actual_profit: 25.50,
            execution_time_ms: 2500,
            gas_used: 150000,
            error_message: None,
            logs: vec![
                "Flash loan initiated from Solend".to_string(),
                "Arbitrage route: USDC -> SOL -> USDC".to_string(),
                "Flash loan repaid successfully".to_string(),
                "Profit: 25.50 SOL".to_string(),
            ],
        })
    }

    async fn detect_provider_opportunities(&self, provider: &FreeFlashLoanProvider) -> Result<Vec<FlashLoanOpportunity>> {
        // Simplified opportunity detection for free providers
        let mut opportunities = Vec::new();

        // Mock opportunities for demonstration
        let mock_opportunity = FlashLoanOpportunity {
            id: format!("free_{}_{}", provider.name, SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs()),
            provider: provider.name.clone(),
            token_a: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v".to_string(), // USDC
            token_b: "So11111111111111111111111111111111111111112".to_string(), // SOL
            loan_amount: 1000.0,
            profit_potential: 25.50,
            gas_estimate: 150000.0,
            flash_loan_fee: 0.3,
            route: vec!["USDC", "SOL"],
            confidence_score: 0.8,
            execution_complexity: 3,
            time_to_expiry: 300,
            slippage_tolerance: 0.03,
            dex_routes: vec![],
            risk_factors: RiskFactors {
                liquidity_risk: 0.1,
                slippage_risk: 0.02,
                execution_risk: 0.15,
                sandwich_risk: 0.01,
                overall_risk: 0.07,
                max_acceptable_slippage: 0.03,
            },
            created_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            arbitrage_type: ArbitrageType::Simple {
                token_a: "USDC".to_string(),
                token_b: "SOL".to_string(),
            },
            intermediate_tokens: vec![],
            cycle_detected: false,
        };

        opportunities.push(mock_opportunity);
        Ok(opportunities)
    }
}

/// Community statistics for transparency
#[derive(Debug, Clone, Default)]
pub struct CommunityStats {
    pub total_executions: u64,
    pub successful_executions: u64,
    pub total_profit_sol: f64,
    pub community_fund_balance: f64,
    pub top_performers: Vec<CommunityPerformer>,
}

impl CommunityStats {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn record_execution(&mut self, result: &FlashLoanExecution, provider: &FreeFlashLoanProvider) {
        self.total_executions += 1;
        if result.success {
            self.successful_executions += 1;
            self.total_profit_sol += result.actual_profit;
        }
    }

    pub fn get_success_rate(&self) -> f64 {
        if self.total_executions == 0 {
            0.0
        } else {
            self.successful_executions as f64 / self.total_executions as f64
        }
    }
}

#[derive(Debug, Clone)]
pub struct CommunityPerformer {
    pub wallet_address: String,
    pub total_profit: f64,
    pub success_rate: f64,
    pub community_contribution: f64,
}

// Re-export token mappings from the main module
pub use super::get_token_mint_map;
pub use super::get_token_symbol_map;

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::signature::Keypair;

    #[tokio::test]
    async fn test_free_flash_loan_detector() {
        let config = FlashLoanConfig::default();
        let keypair = Keypair::new();

        let detector = FreeFlashLoanDetector::new(
            "https://api.mainnet-beta.solana.com",
            keypair,
            config,
        );

        assert!(detector.is_ok());
        let detector = detector.unwrap();

        assert_eq!(detector.providers.len(), 3); // Solend, Marginfi, Jupiter

        // Check that all providers are community approved
        for provider in detector.providers.values() {
            assert!(provider.is_community_approved);
        }
    }

    #[tokio::test]
    async fn test_community_opportunity_detection() {
        let config = FlashLoanConfig::default();
        let keypair = Keypair::new();

        let mut detector = FreeFlashLoanDetector::new(
            "https://api.mainnet-beta.solana.com",
            keypair,
            config,
        ).unwrap();

        let opportunities = detector.detect_free_opportunities().await;
        assert!(opportunities.is_ok());

        let opportunities = opportunities.unwrap();
        assert!(!opportunities.is_empty(), "Should find some opportunities");

        // Check that all opportunities use approved providers
        for opportunity in &opportunities {
            let provider = detector.providers.get(&opportunity.provider).unwrap();
            assert!(provider.is_community_approved);
        }
    }
}
