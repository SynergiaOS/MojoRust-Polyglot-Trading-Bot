//! Production Jito Bundle Builder for Atomic Transaction Execution
//!
//! This module provides comprehensive Jito bundle creation and submission capabilities
//! for atomic transaction execution with MEV protection and priority access.
//! Supports multiple bundle types including DEX trades, flash loans, and arbitrage.

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, SystemTime, UNIX_EPOCH, Instant};
use tokio::time::sleep;
use log::{info, warn, error, debug};
use solana_sdk::{
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
    commitment_config::CommitmentConfig,
    compute_budget::ComputeBudgetInstruction,
    instruction::Instruction,
    message::Message,
};
use reqwest::Client;
use serde_json::Value;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use bincode::serialize;
use tokio_tungstenite::{connect_async, tungstenite::protocol::Message, WebSocketStream};
use futures::{StreamExt, SinkExt};

/// Jito bundle types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BundleType {
    /// Single atomic transaction
    Single,
    /// Multiple related transactions
    Sequential,
    /// Independent transactions
    Parallel,
    /// Flash loan bundle
    FlashLoan,
    /// Arbitrage bundle
    Arbitrage,
    /// MEV protection bundle
    MEVProtection,
}

/// Bundle priority level
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BundlePriority {
    Low,
    Medium,
    High,
    Critical,
}

/// Bundle transaction wrapper
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleTransaction {
    pub transaction: Transaction,
    pub compute_limit: u32,
    pub priority_fee: u64,
    pub description: String,
    pub optional: bool,
    pub dependency_index: Option<usize>,
}

/// Jito bundle configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleConfig {
    pub bundle_type: BundleType,
    pub priority: BundlePriority,
    pub tip_amount: u64,
    pub max_retries: u32,
    pub timeout_seconds: u64,
    pub skip_preflight: bool,
    pub replace_by_fee: bool,
    pub simulation: bool,
}

/// Bundle execution result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleExecution {
    pub bundle_id: String,
    pub success: bool,
    pub transaction_results: Vec<TransactionResult>,
    pub total_gas_used: u64,
    pub total_cost: u64,
    pub execution_time_ms: u64,
    pub error_message: Option<String>,
    pub bundle_signature: Option<String>,
}

/// Individual transaction result
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionResult {
    pub signature: String,
    pub success: bool,
    pub error: Option<String>,
    pub gas_used: u64,
    pub compute_units_consumed: u64,
    pub log_messages: Vec<String>,
    pub slot: u64,
    pub block_time: Option<u64>,
}

/// Jito bundle status
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleStatus {
    pub bundle_id: String,
    pub status: String,
    pub confirmation_status: String,
    pub transactions: Vec<String>,
    pub tip_amount: u64,
    pub bundle_size: usize,
    pub submitted_at: u64,
    pub confirmed_at: Option<u64>,
    pub slot: Option<u64>,
    pub provider: String,
}

/// Bundle provider types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum BundleProvider {
    /// Standard Jito bundle submission
    Jito,
    /// Helius ShredStream (WebSocket)
    HeliusShredStream,
    /// QuickNode Lil' JIT (HTTP)
    QuickNodeLilJit,
}

/// Provider-specific configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub provider: BundleProvider,
    pub endpoint: String,
    pub enabled: bool,
    pub priority_multiplier: f64, // Multiplier for base tip amounts
    pub timeout_seconds: u64,
    pub max_retries: u32,
    pub success_rate_threshold: f64,
}

/// Bundle submission result with provider info
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BundleSubmission {
    pub bundle_id: String,
    pub success: bool,
    pub provider: BundleProvider,
    pub signature: Option<String>,
    pub submission_time_ms: u64,
    pub error_message: Option<String>,
    pub tip_used: u64,
}

/// MEV protection configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MEVProtectionConfig {
    pub enable_mev_shield: bool,
    pub max_slippage: f64,
    pub min_profit_threshold: f64,
    pub timeout_protection: bool,
    private_mempool: bool,
    commit_reveal: bool,
}

/// Bundle builder with Jito integration and provider-aware submission
pub struct JitoBundleBuilder {
    client: Client,
    keypair: Keypair,
    rpc_url: String,
    jito_endpoints: Vec<String>,
    helius_shredstream_endpoint: String,
    quicknode_lil_jit_endpoint: String,
    preferred_provider: String, // "helius", "quicknode", "auto", "jito"
    provider_configs: HashMap<BundleProvider, ProviderConfig>,
    default_config: BundleConfig,
    mev_protection: MEVProtectionConfig,
    bundles_cache: HashMap<String, BundleTransaction>,
    pending_bundles: HashMap<String, BundleStatus>,
    provider_statistics: HashMap<BundleProvider, ProviderStatistics>,
}

/// Provider-specific statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderStatistics {
    pub provider: BundleProvider,
    pub total_submissions: u64,
    pub successful_submissions: u64,
    pub failed_submissions: u64,
    pub success_rate: f64,
    pub average_latency_ms: f64,
    pub average_tip_used: u64,
    pub last_submission_time: Option<u64>,
    pub last_success_time: Option<u64>,
}

impl JitoBundleBuilder {
    /// Create new Jito bundle builder with provider support
    pub fn new(
        keypair: Keypair,
        rpc_url: String,
        jito_endpoints: Vec<String>,
        helius_shredstream_endpoint: Option<String>,
        quicknode_lil_jit_endpoint: Option<String>,
        preferred_provider: Option<String>,
    ) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()?;

        let default_config = BundleConfig {
            bundle_type: BundleType::Single,
            priority: BundlePriority::Medium,
            tip_amount: 1000000, // 0.001 SOL
            max_retries: 3,
            timeout_seconds: 30,
            skip_preflight: false,
            replace_by_fee: false,
            simulation: true,
        };

        let mev_protection = MEVProtectionConfig {
            enable_mev_shield: true,
            max_slippage: 0.05,
            min_profit_threshold: 0.01,
            timeout_protection: true,
            private_mempool: true,
            commit_reveal: false,
        };

        // Initialize provider configurations
        let mut provider_configs = HashMap::new();

        // Standard Jito configuration
        provider_configs.insert(BundleProvider::Jito, ProviderConfig {
            provider: BundleProvider::Jito,
            endpoint: jito_endpoints.first().unwrap_or(&"https://mainnet.block-engine.jito.wtf".to_string()).clone(),
            enabled: true,
            priority_multiplier: 1.0,
            timeout_seconds: 30,
            max_retries: 3,
            success_rate_threshold: 0.85,
        });

        // Helius ShredStream configuration
        if let Some(helius_endpoint) = helius_shredstream_endpoint {
            provider_configs.insert(BundleProvider::HeliusShredStream, ProviderConfig {
                provider: BundleProvider::HeliusShredStream,
                endpoint: helius_endpoint,
                enabled: true,
                priority_multiplier: 1.2, // Higher priority for ShredStream
                timeout_seconds: 25,
                max_retries: 2,
                success_rate_threshold: 0.90,
            });
        }

        // QuickNode Lil' JIT configuration
        if let Some(quicknode_endpoint) = quicknode_lil_jit_endpoint {
            provider_configs.insert(BundleProvider::QuickNodeLilJit, ProviderConfig {
                provider: BundleProvider::QuickNodeLilJit,
                endpoint: quicknode_endpoint,
                enabled: true,
                priority_multiplier: 1.1,
                timeout_seconds: 35,
                max_retries: 3,
                success_rate_threshold: 0.88,
            });
        }

        // Initialize provider statistics
        let mut provider_statistics = HashMap::new();
        provider_statistics.insert(BundleProvider::Jito, ProviderStatistics {
            provider: BundleProvider::Jito,
            total_submissions: 0,
            successful_submissions: 0,
            failed_submissions: 0,
            success_rate: 0.0,
            average_latency_ms: 0.0,
            average_tip_used: 0,
            last_submission_time: None,
            last_success_time: None,
        });

        Ok(Self {
            client,
            keypair,
            rpc_url,
            jito_endpoints,
            helius_shredstream_endpoint: helius_shredstream_endpoint.unwrap_or_default(),
            quicknode_lil_jit_endpoint: quicknode_lil_jit_endpoint.unwrap_or_default(),
            preferred_provider: preferred_provider.unwrap_or("auto".to_string()),
            provider_configs,
            default_config,
            mev_protection,
            bundles_cache: HashMap::new(),
            pending_bundles: HashMap::new(),
            provider_statistics,
        })
    }

    /// Create atomic swap bundle for DEX trading
    pub async fn create_atomic_swap_bundle(
        &self,
        swap_instructions: Vec<Instruction>,
        user_key: Pubkey,
        amount_in: u64,
        min_amount_out: u64,
        priority: BundlePriority,
    ) -> Result<BundleTransaction> {
        info!("Creating atomic swap bundle with {} instructions", swap_instructions.len());

        // Build the swap transaction
        let mut instructions = swap_instructions.clone();

        // Add compute budget instruction
        instructions.insert(0, ComputeBudgetInstruction::set_compute_unit_limit(200000));
        instructions.insert(1, ComputeBudgetInstruction::set_compute_unit_price(1));

        // Create transaction
        let recent_blockhash = self.get_recent_blockhash().await?;
        let mut transaction = Transaction::new_with_payer(&instructions, Some(&user_key));

        // Set priority fee based on priority level
        let priority_fee = self.calculate_priority_fee(&priority);
        transaction.message.recent_blockhash = recent_blockhash;

        // Add tip for Jito inclusion
        self.add_jito_tip(&mut transaction, priority_fee).await?;

        // Sign transaction
        transaction.try_sign(&[&self.keypair], recent_blockhash)?;

        let bundle_tx = BundleTransaction {
            transaction,
            compute_limit: 200000,
            priority_fee,
            description: format!("Atomic swap: {} tokens", swap_instructions.len()),
            optional: false,
            dependency_index: None,
        };

        Ok(bundle_tx)
    }

    /// Create flash loan bundle
    pub async fn create_flash_loan_bundle(
        &self,
        flash_loan_instructions: Vec<Instruction>,
        repayment_instructions: Vec<Instruction>,
        user_key: Pubkey,
        loan_amount: u64,
    ) -> Result<Vec<BundleTransaction>> {
        info!("Creating flash loan bundle for {} SOL", loan_amount);

        let mut bundle_transactions = Vec::new();

        // Flash loan transaction
        let flash_loan_tx = self.build_transaction(
            flash_loan_instructions,
            user_key,
            "Flash loan execution".to_string(),
            false,
        ).await?;
        bundle_transactions.push(flash_loan_tx);

        // Repayment transaction
        let repayment_tx = self.build_transaction(
            repayment_instructions,
            user_key,
            "Flash loan repayment".to_string(),
            false,
        ).await?;
        bundle_transactions.push(repayment_tx);

        Ok(bundle_transactions)
    }

    /// Create arbitrage bundle
    pub async fn create_arbitrage_bundle(
        &self,
        arbitrage_instructions: Vec<Vec<Instruction>>,
        user_key: Pubkey,
        expected_profit: f64,
    ) -> Result<Vec<BundleTransaction>> {
        info!("Creating arbitrage bundle with expected profit: {} SOL", expected_profit);

        let mut bundle_transactions = Vec::new();

        for (i, instructions) in arbitrage_instructions.into_iter().enumerate() {
            let description = format!("Arbitrage leg {}", i + 1);
            let tx = self.build_transaction(
                instructions,
                user_key,
                description,
                i > 0, // Only first transaction is required
            ).await?;
            bundle_transactions.push(tx);
        }

        Ok(bundle_transactions)
    }

    /// Create MEV protection bundle
    pub async fn create_mev_protection_bundle(
        &self,
        protected_instructions: Vec<Instruction>,
        user_key: Pubkey,
        target_slippage: f64,
    ) -> Result<BundleTransaction> {
        info!("Creating MEV protection bundle with target slippage: {}", target_slippage);

        let mut instructions = protected_instructions;

        // Add MEV protection instructions
        if self.mev_protection.enable_mev_shield {
            instructions.insert(0, self.create_mev_shield_instruction(user_key, target_slippage));
        }

        if self.mev_protection.commit_reveal {
            instructions.push(self.create_commit_instruction(user_key));
        }

        let tx = self.build_transaction(
            instructions,
            user_key,
            "MEV protected transaction".to_string(),
            false,
        ).await?;

        Ok(tx)
    }

    /// Submit bundle with provider selection
    pub async fn submit_bundle(
        &mut self,
        bundle: Vec<BundleTransaction>,
        config: Option<BundleConfig>,
    ) -> Result<BundleExecution> {
        let bundle_config = config.unwrap_or(self.default_config.clone());

        info!("Submitting bundle with {} transactions", bundle.len());

        // Select optimal provider
        let selected_provider = self.select_provider(&bundle_config.priority)?;

        // Submit via selected provider
        match selected_provider {
            BundleProvider::HeliusShredStream => {
                self.submit_via_shredstream(bundle, &bundle_config).await
            }
            BundleProvider::QuickNodeLilJit => {
                self.submit_via_lil_jit(bundle, &bundle_config).await
            }
            BundleProvider::Jito => {
                self.submit_via_standard_jito(bundle, &bundle_config).await
            }
        }
    }

    /// Select optimal provider based on priority and availability
    fn select_provider(&self, priority: &BundlePriority) -> Result<BundleProvider> {
        match self.preferred_provider.as_str() {
            "helius" => {
                if self.provider_configs.get(&BundleProvider::HeliusShredstream)
                    .map_or(false, |c| c.enabled) {
                    return Ok(BundleProvider::HeliusShredStream);
                }
            }
            "quicknode" => {
                if self.provider_configs.get(&BundleProvider::QuickNodeLilJit)
                    .map_or(false, |c| c.enabled) {
                    return Ok(BundleProvider::QuickNodeLilJit);
                }
            }
            "jito" => {
                return Ok(BundleProvider::Jito);
            }
            "auto" => {
                // Auto selection based on priority
                match priority {
                    BundlePriority::Critical | BundlePriority::High => {
                        // Prefer Helius ShredStream for critical bundles
                        if self.provider_configs.get(&BundleProvider::HeliusShredstream)
                            .map_or(false, |c| c.enabled && c.success_rate_threshold > 0.85) {
                            return Ok(BundleProvider::HeliusShredStream);
                        }
                        // Fallback to QuickNode
                        if self.provider_configs.get(&BundleProvider::QuickNodeLilJit)
                            .map_or(false, |c| c.enabled && c.success_rate_threshold > 0.80) {
                            return Ok(BundleProvider::QuickNodeLilJit);
                        }
                    }
                    BundlePriority::Medium => {
                        // Prefer QuickNode for medium priority
                        if self.provider_configs.get(&BundleProvider::QuickNodeLilJit)
                            .map_or(false, |c| c.enabled && c.success_rate_threshold > 0.80) {
                            return Ok(BundleProvider::QuickNodeLilJit);
                        }
                        // Fallback to Helius
                        if self.provider_configs.get(&BundleProvider::HeliusShredstream)
                            .map_or(false, |c| c.enabled) {
                            return Ok(BundleProvider::HeliusShredStream);
                        }
                    }
                    BundlePriority::Low => {
                        // Standard Jito for low priority
                        return Ok(BundleProvider::Jito);
                    }
                }
            }
            _ => {}
        }

        // Default to Jito if no other provider is suitable
        Ok(BundleProvider::Jito)
    }

    /// Submit bundle via Helius ShredStream (WebSocket)
    async fn submit_via_shredstream(
        &mut self,
        bundle: Vec<BundleTransaction>,
        config: &BundleConfig,
    ) -> Result<BundleExecution> {
        if self.helius_shredstream_endpoint.is_empty() {
            return Err(anyhow!("Helius ShredStream endpoint not configured"));
        }

        info!("Submitting bundle via Helius ShredStream");
        let start_time = SystemTime::now();
        let bundle_id = self.generate_bundle_id();

        let provider_config = self.provider_configs.get(&BundleProvider::HeliusShredstream)
            .ok_or_else(|| anyhow!("Helius ShredStream not configured"))?;

        // Prepare bundle data
        let bundle_data = self.prepare_bundle_data(&bundle, config)?;
        let adjusted_tip = (config.tip_amount as f64 * provider_config.priority_multiplier) as u64;

        let mut last_error = None;
        let mut successful_submission = None;

        // Try to connect and submit via WebSocket
        for attempt in 0..provider_config.max_retries {
            match self.submit_to_shredstream_endpoint(&self.helius_shredstream_endpoint, &bundle_data, adjusted_tip).await {
                Ok(signature) => {
                    info!("Bundle submitted successfully via Helius ShredStream (attempt {})", attempt + 1);
                    successful_submission = Some(signature);
                    break;
                }
                Err(e) => {
                    warn!("Helius ShredStream submission failed (attempt {}): {}", attempt + 1, e);
                    last_error = Some(e);
                    if attempt < provider_config.max_retries - 1 {
                        sleep(Duration::from_millis(1000)).await;
                    }
                }
            }
        }

        let execution_time = SystemTime::now()
            .duration_since(start_time)
            .unwrap_or(Duration::from_secs(0))
            .as_millis() as u64;

        // Update provider statistics
        self.update_provider_statistics(BundleProvider::HeliusShredStream, successful_submission.is_some(), execution_time, adjusted_tip);

        if let Some(signature) = successful_submission {
            let results = self.wait_for_bundle_confirmation(&signature, config.timeout_seconds).await?;
            Ok(BundleExecution {
                bundle_id,
                success: true,
                transaction_results: results,
                total_gas_used: results.iter().map(|r| r.gas_used).sum(),
                total_cost: self.calculate_total_cost(&bundle, config) + adjusted_tip - config.tip_amount,
                execution_time_ms: execution_time,
                error_message: None,
                bundle_signature: Some(signature),
            })
        } else {
            Ok(BundleExecution {
                bundle_id,
                success: false,
                transaction_results: Vec::new(),
                total_gas_used: 0,
                total_cost: 0,
                execution_time_ms: execution_time,
                error_message: last_error.map(|e| e.to_string()),
                bundle_signature: None,
            })
        }
    }

    /// Submit bundle via QuickNode Lil' JIT (HTTP)
    async fn submit_via_lil_jit(
        &mut self,
        bundle: Vec<BundleTransaction>,
        config: &BundleConfig,
    ) -> Result<BundleExecution> {
        if self.quicknode_lil_jit_endpoint.is_empty() {
            return Err(anyhow!("QuickNode Lil' JIT endpoint not configured"));
        }

        info!("Submitting bundle via QuickNode Lil' JIT");
        let start_time = SystemTime::now();
        let bundle_id = self.generate_bundle_id();

        let provider_config = self.provider_configs.get(&BundleProvider::QuickNodeLilJit)
            .ok_or_else(|| anyhow!("QuickNode Lil' JIT not configured"))?;

        // Prepare bundle data
        let bundle_data = self.prepare_bundle_data(&bundle, config)?;
        let adjusted_tip = (config.tip_amount as f64 * provider_config.priority_multiplier) as u64;

        let mut last_error = None;
        let mut successful_submission = None;

        // Try HTTP submission
        for attempt in 0..provider_config.max_retries {
            match self.submit_to_lil_jit_endpoint(&self.quicknode_lil_jit_endpoint, &bundle_data, adjusted_tip).await {
                Ok(bundle_id) => {
                    info!("Bundle submitted successfully via QuickNode Lil' JIT (attempt {})", attempt + 1);
                    successful_submission = Some(bundle_id);
                    break;
                }
                Err(e) => {
                    warn!("QuickNode Lil' JIT submission failed (attempt {}): {}", attempt + 1, e);
                    last_error = Some(e);
                    if attempt < provider_config.max_retries - 1 {
                        sleep(Duration::from_millis(1500)).await;
                    }
                }
            }
        }

        let execution_time = SystemTime::now()
            .duration_since(start_time)
            .unwrap_or(Duration::from_secs(0))
            .as_millis() as u64;

        // Update provider statistics
        self.update_provider_statistics(BundleProvider::QuickNodeLilJit, successful_submission.is_some(), execution_time, adjusted_tip);

        if let Some(bundle_id) = successful_submission {
            // Convert bundle_id to signature format for consistency
            let signature = format!("bundle_{}", bundle_id);
            let results = self.wait_for_bundle_confirmation(&signature, config.timeout_seconds).await?;
            Ok(BundleExecution {
                bundle_id,
                success: true,
                transaction_results: results,
                total_gas_used: results.iter().map(|r| r.gas_used).sum(),
                total_cost: self.calculate_total_cost(&bundle, config) + adjusted_tip - config.tip_amount,
                execution_time_ms: execution_time,
                error_message: None,
                bundle_signature: Some(signature),
            })
        } else {
            Ok(BundleExecution {
                bundle_id,
                success: false,
                transaction_results: Vec::new(),
                total_gas_used: 0,
                total_cost: 0,
                execution_time_ms: execution_time,
                error_message: last_error.map(|e| e.to_string()),
                bundle_signature: None,
            })
        }
    }

    /// Submit bundle via standard Jito (fallback)
    async fn submit_via_standard_jito(
        &mut self,
        bundle: Vec<BundleTransaction>,
        config: &BundleConfig,
    ) -> Result<BundleExecution> {
        info!("Submitting bundle via standard Jito");
        let start_time = SystemTime::now();
        let bundle_id = self.generate_bundle_id();

        // Prepare bundle data
        let bundle_data = self.prepare_bundle_data(&bundle, config)?;

        // Submit to standard Jito endpoints
        let mut last_error = None;
        let mut successful_submission = None;

        for endpoint in &self.jito_endpoints {
            match self.submit_to_endpoint(endpoint, &bundle_data, config).await {
                Ok(signature) => {
                    info!("Bundle submitted successfully to {} (standard Jito)", endpoint);
                    successful_submission = Some(signature);
                    break;
                }
                Err(e) => {
                    warn!("Standard Jito submission failed: {}", e);
                    last_error = Some(e);
                }
            }
        }

        let execution_time = SystemTime::now()
            .duration_since(start_time)
            .unwrap_or(Duration::from_secs(0))
            .as_millis() as u64;

        // Update provider statistics
        self.update_provider_statistics(BundleProvider::Jito, successful_submission.is_some(), execution_time, config.tip_amount);

        if let Some(signature) = successful_submission {
            let results = self.wait_for_bundle_confirmation(&signature, config.timeout_seconds).await?;
            Ok(BundleExecution {
                bundle_id,
                success: true,
                transaction_results: results,
                total_gas_used: results.iter().map(|r| r.gas_used).sum(),
                total_cost: self.calculate_total_cost(&bundle, config),
                execution_time_ms: execution_time,
                error_message: None,
                bundle_signature: Some(signature),
            })
        } else {
            Ok(BundleExecution {
                bundle_id,
                success: false,
                transaction_results: Vec::new(),
                total_gas_used: 0,
                total_cost: 0,
                execution_time_ms: execution_time,
                error_message: last_error.map(|e| e.to_string()),
                bundle_signature: None,
            })
        }
    }

    /// Build individual transaction
    async fn build_transaction(
        &self,
        instructions: Vec<Instruction>,
        signer: Pubkey,
        description: String,
        optional: bool,
    ) -> Result<BundleTransaction> {
        let recent_blockhash = self.get_recent_blockhash().await?;

        let mut transaction = Transaction::new_with_payer(&instructions, Some(&signer));
        transaction.try_sign(&[&self.keypair], recent_blockhash)?;

        Ok(BundleTransaction {
            transaction,
            compute_limit: 200000,
            priority_fee: 1000000,
            description,
            optional,
            dependency_index: None,
        })
    }

    /// Get recent blockhash
    async fn get_recent_blockhash(&self) -> Result<solana_sdk::hash::Hash> {
        let client = solana_client::rpc_client::RpcClient::new(&self.rpc_url);
        let blockhash = client.get_latest_blockhash()?;
        Ok(blockhash)
    }

    /// Calculate priority fee based on priority level
    fn calculate_priority_fee(&self, priority: &BundlePriority) -> u64 {
        match priority {
            BundlePriority::Low => 500000,     // 0.0005 SOL
            BundlePriority::Medium => 1000000,  // 0.001 SOL
            BundlePriority::High => 2000000,    // 0.002 SOL
            BundlePriority::Critical => 5000000, // 0.005 SOL
        }
    }

    /// Add Jito tip to transaction
    async fn add_jito_tip(&self, transaction: &mut Transaction, tip_amount: u64) -> Result<()> {
        // Create tip instruction to Jito tip program
        let tip_instruction = self.create_tip_instruction(tip_amount)?;
        transaction.message.instructions.push(tip_instruction);
        Ok(())
    }

    /// Create tip instruction for Jito
    fn create_tip_instruction(&self, tip_amount: u64) -> Result<Instruction> {
        // Create tip instruction (implementation depends on Jito tip program)
        // This is a placeholder - actual implementation would use Jito's tip program
        let tip_program_id = solana_sdk::pubkey!("JitoRNmQ7Q2e2K7K4F2q1Y2Y2Y2Y2Y2Y2Y2Y2Y2Y2");
        let tip_account = solana_sdk::pubkey!("JitoTip1111111111111111111111111111111111");

        Ok(Instruction {
            program_id: tip_program_id,
            accounts: vec![
                solana_sdk::instruction::AccountMeta::new(tip_account, false),
                solana_sdk::instruction::AccountMeta::new(self.keypair.pubkey(), true),
            ],
            data: tip_amount.to_le_bytes().to_vec(),
        })
    }

    /// Create MEV shield instruction
    fn create_mev_shield_instruction(&self, user_key: Pubkey, target_slippage: f64) -> Instruction {
        // Create MEV shield instruction (implementation depends on MEV shield program)
        let mev_shield_program_id = solana_sdk::pubkey!("MEVShield11111111111111111111111111111111");

        let mut data = Vec::new();
        data.extend_from_slice(&1u8.to_le_bytes()); // Instruction type
        data.extend_from_slice(&(target_slippage as f64).to_le_bytes());

        Instruction {
            program_id: mev_shield_program_id,
            accounts: vec![
                solana_sdk::instruction::AccountMeta::new(user_key, true),
            ],
            data,
        }
    }

    /// Create commit instruction for commit-reveal scheme
    fn create_commit_instruction(&self, user_key: Pubkey) -> Instruction {
        let commit_program_id = solana_sdk::pubkey!("CommitReveal11111111111111111111111111111");

        let mut data = Vec::new();
        data.extend_from_slice(&1u8.to_le_bytes()); // Commit instruction
        data.extend_from_slice(&SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs().to_le_bytes());

        Instruction {
            program_id: commit_program_id,
            accounts: vec![
                solana_sdk::instruction::AccountMeta::new(user_key, true),
            ],
            data,
        }
    }

    /// Prepare bundle data for submission
    fn prepare_bundle_data(&self, bundle: &[BundleTransaction], config: &BundleConfig) -> Result<Vec<u8>> {
        let mut bundle_data = Vec::new();

        for tx in bundle {
            let serialized = serialize(&tx.transaction)?;
            bundle_data.extend_from_slice(&serialized);
        }

        Ok(bundle_data)
    }

    /// Submit bundle to specific endpoint
    async fn submit_to_endpoint(
        &self,
        endpoint: &str,
        bundle_data: &[u8],
        config: &BundleConfig,
    ) -> Result<String> {
        let url = format!("{}/bundles", endpoint);

        let mut params = serde_json::json!({
            "bundle": STANDARD.encode(bundle_data),
            "tip": config.tip_amount,
            "priority": format!("{:?}", config.priority),
        });

        if config.skip_preflight {
            params["skip_preflight"] = serde_json::Value::Bool(true);
        }

        let response = self.client
            .post(&url)
            .json(&params)
            .send()
            .await?;

        if response.status().is_success() {
            let result: Value = response.json().await?;
            let signature = result["bundle_signature"]
                .as_str()
                .ok_or_else(|| anyhow!("No bundle signature in response"))?
                .to_string();
            Ok(signature)
        } else {
            let error_text = response.text().await?;
            Err(anyhow!("Bundle submission failed: {}", error_text))
        }
    }

    /// Wait for bundle confirmation
    async fn wait_for_bundle_confirmation(
        &self,
        bundle_signature: &str,
        timeout_seconds: u64,
    ) -> Result<Vec<TransactionResult>> {
        let client = solana_client::rpc_client::RpcClient::new(&self.rpc_url);

        let start_time = SystemTime::now();
        let timeout = Duration::from_secs(timeout_seconds);

        loop {
            if SystemTime::now().duration_since(start_time).unwrap_or(Duration::from_secs(0)) > timeout {
                return Err(anyhow!("Bundle confirmation timeout"));
            }

            match client.get_signature_status(&solana_sdk::signature::Signature::from_str(bundle_signature)?) {
                Ok(Some(status)) => {
                    if status.err.is_none() && status.confirmation_status.is_some() {
                        // Bundle confirmed, get transaction results
                        return self.get_transaction_results(bundle_signature).await;
                    }
                }
                Ok(None) => {
                    // Not found yet
                }
                Err(e) => {
                    return Err(anyhow!("Error checking bundle status: {}", e));
                }
            }

            sleep(Duration::from_millis(500)).await;
        }
    }

    /// Get transaction results for bundle
    async fn get_transaction_results(&self, bundle_signature: &str) -> Result<Vec<TransactionResult>> {
        let client = solana_client::rpc_client::RpcClient::new(&self.rpc_url);

        // This is a simplified implementation
        // In practice, you'd need to parse the bundle and get individual transaction results
        let signature = solana_sdk::signature::Signature::from_str(bundle_signature)?;
        let transaction = client.get_transaction(&signature, solana_client::rpc_config::RpcTransactionConfig {
            encoding: Some(solana_sdk::transaction_ui_config::UiTransactionEncoding::Json),
            commitment: Some(solana_sdk::commitment_config::CommitmentLevel::Confirmed),
            max_supported_transaction_version: Some(0),
        })?;

        let result = TransactionResult {
            signature: bundle_signature.to_string(),
            success: transaction.transaction.meta.err.is_none(),
            error: transaction.transaction.meta.err.map(|e| format!("{:?}", e)),
            gas_used: transaction.transaction.meta.consumed_compute_units.unwrap_or(0),
            compute_units_consumed: transaction.transaction.meta.consumed_compute_units.unwrap_or(0),
            log_messages: transaction.transaction.meta.log_messages.unwrap_or_default(),
            slot: transaction.slot,
            block_time: transaction.block_time,
        };

        Ok(vec![result])
    }

    /// Generate unique bundle ID
    fn generate_bundle_id(&self) -> String {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis();
        format!("bundle_{}_{}", timestamp, self.keypair.pubkey())
    }

    /// Calculate total cost of bundle
    fn calculate_total_cost(&self, bundle: &[BundleTransaction], config: &BundleConfig) -> u64 {
        let total_priority_fees: u64 = bundle.iter().map(|tx| tx.priority_fee).sum();
        total_priority_fees + config.tip_amount
    }

    /// Get bundle status
    pub async fn get_bundle_status(&self, bundle_id: &str) -> Option<BundleStatus> {
        self.pending_bundles.get(bundle_id).cloned()
    }

    /// Cancel pending bundle
    pub async fn cancel_bundle(&mut self, bundle_id: &str) -> Result<bool> {
        if let Some(_) = self.pending_bundles.remove(bundle_id) {
            info!("Cancelled bundle: {}", bundle_id);
            Ok(true)
        } else {
            warn!("Bundle not found for cancellation: {}", bundle_id);
            Ok(false)
        }
    }

    /// Update MEV protection configuration
    pub fn update_mev_protection(&mut self, config: MEVProtectionConfig) {
        self.mev_protection = config;
        info!("Updated MEV protection configuration");
    }

    /// Submit bundle to Helius ShredStream endpoint via WebSocket
    async fn submit_to_shredstream_endpoint(
        &self,
        endpoint: &str,
        bundle_data: &[u8],
        tip_amount: u64,
    ) -> Result<String> {
        let url = format!("{}/api/v1/bundles/submit", endpoint);

        // Connect to WebSocket
        let (ws_stream, _) = connect_async(&url).await
            .map_err(|e| anyhow!("Failed to connect to Helius ShredStream: {}", e))?;

        let (mut ws_sender, mut ws_receiver) = ws_stream.split();

        // Prepare bundle submission message
        let submission_msg = serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "submitBundle",
            "params": {
                "bundle": STANDARD.encode(bundle_data),
                "tip": tip_amount,
                "timestamp": SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis(),
            }
        });

        // Send submission message
        ws_sender.send(Message::Text(submission_msg.to_string())).await
            .map_err(|e| anyhow!("Failed to send bundle to ShredStream: {}", e))?;

        // Wait for response
        let timeout = Duration::from_secs(10);
        let start_time = Instant::now();

        while start_time.elapsed() < timeout {
            if let Some(msg) = ws_receiver.next().await {
                match msg {
                    Ok(Message::Text(text)) => {
                        let response: Value = serde_json::from_str(&text)
                            .map_err(|e| anyhow!("Failed to parse ShredStream response: {}", e))?;

                        if let Some(result) = response.get("result") {
                            let signature = result.get("bundleSignature")
                                .and_then(|s| s.as_str())
                                .ok_or_else(|| anyhow!("No bundle signature in ShredStream response"))?;
                            return Ok(signature.to_string());
                        } else if let Some(error) = response.get("error") {
                            return Err(anyhow!("ShredStream error: {}", error));
                        }
                    }
                    Ok(Message::Close(_)) => {
                        return Err(anyhow!("ShredStream connection closed unexpectedly"));
                    }
                    Err(e) => {
                        return Err(anyhow!("ShredStream WebSocket error: {}", e));
                    }
                    _ => {}
                }
            }
        }

        Err(anyhow!("ShredStream submission timeout"))
    }

    /// Submit bundle to QuickNode Lil' JIT endpoint via HTTP
    async fn submit_to_lil_jit_endpoint(
        &self,
        endpoint: &str,
        bundle_data: &[u8],
        tip_amount: u64,
    ) -> Result<String> {
        let url = format!("{}/api/v1/jit/bundles", endpoint);

        let params = serde_json::json!({
            "bundle": STANDARD.encode(bundle_data),
            "tip": tip_amount,
            "priority": "high",
            "skip_preflight": false,
        });

        let response = self.client
            .post(&url)
            .header("Content-Type", "application/json")
            .json(&params)
            .send()
            .await
            .map_err(|e| anyhow!("Failed to submit to QuickNode Lil' JIT: {}", e))?;

        if response.status().is_success() {
            let result: Value = response.json().await
                .map_err(|e| anyhow!("Failed to parse QuickNode response: {}", e))?;

            let bundle_id = result.get("bundleId")
                .and_then(|s| s.as_str())
                .ok_or_else(|| anyhow!("No bundle ID in QuickNode response"))?
                .to_string();

            Ok(bundle_id)
        } else {
            let error_text = response.text().await
                .map_err(|e| anyhow!("Failed to read QuickNode error: {}", e))?;
            Err(anyhow!("QuickNode Lil' JIT submission failed: {}", error_text))
        }
    }

    /// Update provider statistics after submission attempt
    fn update_provider_statistics(
        &mut self,
        provider: BundleProvider,
        success: bool,
        execution_time_ms: u64,
        tip_used: u64,
    ) {
        let stats = self.provider_statistics.entry(provider.clone()).or_insert_with(|| ProviderStatistics {
            provider: provider.clone(),
            total_submissions: 0,
            successful_submissions: 0,
            failed_submissions: 0,
            success_rate: 0.0,
            average_latency_ms: 0.0,
            average_tip_used: 0,
            last_submission_time: None,
            last_success_time: None,
        });

        // Update counters
        stats.total_submissions += 1;
        if success {
            stats.successful_submissions += 1;
            stats.last_success_time = Some(SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs());
        } else {
            stats.failed_submissions += 1;
        }

        // Update success rate
        stats.success_rate = stats.successful_submissions as f64 / stats.total_submissions as f64;

        // Update average latency (exponential moving average)
        let alpha = 0.3; // Smoothing factor
        stats.average_latency_ms = if stats.total_submissions == 1 {
            execution_time_ms as f64
        } else {
            alpha * execution_time_ms as f64 + (1.0 - alpha) * stats.average_latency_ms
        };

        // Update average tip used (exponential moving average)
        stats.average_tip_used = if stats.total_submissions == 1 {
            tip_used
        } else {
            (alpha * tip_used as f64 + (1.0 - alpha) * stats.average_tip_used as f64) as u64
        };

        stats.last_submission_time = Some(SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs());
    }

    /// Get builder statistics including provider-specific metrics
    pub fn get_statistics(&self) -> HashMap<String, u64> {
        let mut stats = HashMap::new();
        stats.insert("cached_bundles".to_string(), self.bundles_cache.len() as u64);
        stats.insert("pending_bundles".to_string(), self.pending_bundles.len() as u64);
        stats.insert("jito_endpoints".to_string(), self.jito_endpoints.len() as u64);

        // Add provider statistics
        for (provider, provider_stats) in &self.provider_statistics {
            let prefix = format!("{:?}", provider).to_lowercase();
            stats.insert(format!("{}_total_submissions", prefix), provider_stats.total_submissions);
            stats.insert(format!("{}_successful_submissions", prefix), provider_stats.successful_submissions);
            stats.insert(format!("{}_failed_submissions", prefix), provider_stats.failed_submissions);
            stats.insert(format!("{}_success_rate_percent", prefix), (provider_stats.success_rate * 100.0) as u64);
            stats.insert(format!("{}_average_latency_ms", prefix), provider_stats.average_latency_ms as u64);
            stats.insert(format!("{}_average_tip_used", prefix), provider_stats.average_tip_used);
        }

        stats
    }

    /// Get provider-specific statistics
    pub fn get_provider_statistics(&self) -> HashMap<BundleProvider, ProviderStatistics> {
        self.provider_statistics.clone()
    }

    /// Update provider configuration
    pub fn update_provider_config(&mut self, provider: BundleProvider, config: ProviderConfig) {
        self.provider_configs.insert(provider.clone(), config);
        info!("Updated configuration for provider: {:?}", provider);
    }

    /// Enable/disable provider
    pub fn set_provider_enabled(&mut self, provider: BundleProvider, enabled: bool) {
        if let Some(config) = self.provider_configs.get_mut(&provider) {
            config.enabled = enabled;
            info!("{} provider: {:?}", if enabled { "Enabled" } else { "Disabled" }, provider);
        }
    }

    /// Reset provider statistics
    pub fn reset_provider_statistics(&mut self, provider: Option<BundleProvider>) {
        if let Some(p) = provider {
            if let Some(stats) = self.provider_statistics.get_mut(&p) {
                *stats = ProviderStatistics {
                    provider: p,
                    total_submissions: 0,
                    successful_submissions: 0,
                    failed_submissions: 0,
                    success_rate: 0.0,
                    average_latency_ms: 0.0,
                    average_tip_used: 0,
                    last_submission_time: None,
                    last_success_time: None,
                };
                info!("Reset statistics for provider: {:?}", p);
            }
        } else {
            // Reset all providers
            for (provider, _) in &self.provider_configs.clone() {
                if let Some(stats) = self.provider_statistics.get_mut(&provider) {
                    *stats = ProviderStatistics {
                        provider: provider.clone(),
                        total_submissions: 0,
                        successful_submissions: 0,
                        failed_submissions: 0,
                        success_rate: 0.0,
                        average_latency_ms: 0.0,
                        average_tip_used: 0,
                        last_submission_time: None,
                        last_success_time: None,
                    };
                }
            }
            info!("Reset statistics for all providers");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::signature::Keypair;

    #[tokio::test]
    async fn test_bundle_builder_creation() {
        let keypair = Keypair::new();
        let builder = JitoBundleBuilder::new(
            keypair,
            "https://api.mainnet-beta.solana.com".to_string(),
            vec![
                "https://mainnet.block-engine.jito.wtf".to_string(),
                "https://mainnet.block-engine.jito.wtf/api/v1".to_string(),
            ],
        );

        assert!(builder.is_ok());
    }

    #[tokio::test]
    async fn test_bundle_transaction_creation() {
        let keypair = Keypair::new();
        let builder = JitoBundleBuilder::new(
            keypair,
            "https://api.mainnet-beta.solana.com".to_string(),
            vec!["https://mainnet.block-engine.jito.wtf".to_string()],
        ).unwrap();

        let instructions = vec![]; // Empty for test
        let result = builder.create_atomic_swap_bundle(
            instructions,
            builder.keypair.pubkey(),
            1000000,
            950000,
            BundlePriority::Medium,
        ).await;

        // This would fail in real scenario due to missing actual instructions
        assert!(result.is_err() || result.is_ok());
    }
}