//! Solana blockchain integration module
//!
//! This module provides comprehensive Solana integration including:
//! - Transaction building and signing
//! - Account management and balance queries
//! - Program interaction and instruction building
//! - RPC client with failover support
//! - WebSocket subscription handling
//! - Token and account operations

pub mod account;
pub mod client;
pub mod transaction;
pub mod token;
pub mod program;
pub mod websocket;
pub mod utils;

pub use account::{AccountManager, AccountInfo, Balance};
pub use client::{SolanaClient, RpcConfig, CommitmentLevel};
pub use transaction::{TransactionBuilder, TransactionStatus, FeeCalculator};
pub use token::{TokenManager, TokenAccount, TokenInfo, TokenOperations};
pub use program::{ProgramClient, InstructionBuilder, AccountMeta};
pub use websocket::{WebSocketClient, SubscriptionManager, AccountSubscription};
pub use utils::{SolanaUtils, AddressUtils, TransactionUtils};

use anyhow::Result;

/// Main Solana interface for the trading bot
pub struct SolanaEngine {
    client: SolanaClient,
    account_manager: AccountManager,
    token_manager: TokenManager,
    program_client: ProgramClient,
    websocket_client: Option<WebSocketClient>,
}

impl SolanaEngine {
    /// Create new Solana engine
    pub fn new(rpc_url: &str, ws_url: Option<&str>) -> Result<Self> {
        let client = SolanaClient::new(rpc_url)?;
        let account_manager = AccountManager::new(client.clone());
        let token_manager = TokenManager::new(client.clone());
        let program_client = ProgramClient::new(client.clone());

        let mut engine = Self {
            client,
            account_manager,
            token_manager,
            program_client,
            websocket_client: None,
        };

        // Initialize WebSocket if URL provided
        if let Some(ws_url) = ws_url {
            engine.websocket_client = Some(WebSocketClient::new(ws_url)?);
        }

        Ok(engine)
    }

    /// Get RPC client
    pub fn client(&self) -> &SolanaClient {
        &self.client
    }

    /// Get account manager
    pub fn account_manager(&self) -> &AccountManager {
        &self.account_manager
    }

    /// Get token manager
    pub fn token_manager(&self) -> &TokenManager {
        &self.token_manager
    }

    /// Get program client
    pub fn program_client(&self) -> &ProgramClient {
        &self.program_client
    }

    /// Get WebSocket client
    pub fn websocket_client(&self) -> Option<&WebSocketClient> {
        self.websocket_client.as_ref()
    }

    /// Initialize engine with configuration
    pub fn initialize(&mut self, config: SolanaConfig) -> Result<()> {
        // Configure client
        self.client.set_commitment(config.commitment_level);
        self.client.set_preflight_commitment(config.preflight_commitment);

        // Initialize WebSocket if available
        if let Some(ws_client) = &mut self.websocket_client {
            ws_client.connect()?;
        }

        Ok(())
    }

    /// Build a simple transfer transaction
    pub fn build_transfer_transaction(
        &self,
        from_pubkey: &str,
        to_pubkey: &str,
        lamports: u64,
        fee_payer: Option<&str>,
    ) -> Result<solana_sdk::transaction::Transaction> {
        let mut builder = TransactionBuilder::new();

        // Set fee payer
        if let Some(fee_payer) = fee_payer {
            builder.set_fee_payer(fee_payer);
        }

        // Add transfer instruction
        builder.transfer_sol(from_pubkey, to_pubkey, lamports)?;

        builder.build(&self.client)
    }

    /// Build a token transfer transaction
    pub fn build_token_transfer_transaction(
        &self,
        from_token_account: &str,
        to_token_account: &str,
        token_mint: &str,
        owner: &str,
        amount: u64,
        fee_payer: Option<&str>,
    ) -> Result<solana_sdk::transaction::Transaction> {
        let mut builder = TransactionBuilder::new();

        // Set fee payer
        if let Some(fee_payer) = fee_payer {
            builder.set_fee_payer(fee_payer);
        }

        // Add token transfer instruction
        builder.transfer_token(
            from_token_account,
            to_token_account,
            token_mint,
            owner,
            amount,
        )?;

        builder.build(&self.client)
    }

    /// Send and confirm transaction
    pub fn send_and_confirm_transaction(
        &self,
        transaction: &solana_sdk::transaction::Transaction,
        keypair: &crate::crypto::keypair::SecureKeypair,
    ) -> Result<TransactionStatus> {
        // Sign transaction
        let signed_tx = self.client.sign_transaction(transaction, keypair)?;

        // Send transaction
        let signature = self.client.send_transaction(&signed_tx)?;

        // Wait for confirmation
        self.client.confirm_transaction(&signature)
    }

    /// Get SOL balance
    pub fn get_sol_balance(&self, pubkey: &str) -> Result<u64> {
        self.account_manager.get_balance(pubkey)
    }

    /// Get token balance
    pub fn get_token_balance(&self, token_account: &str) -> Result<u64> {
        self.token_manager.get_token_balance(token_account)
    }

    /// Get token accounts by owner
    pub fn get_token_accounts(&self, owner: &str, mint: Option<&str>) -> Result<Vec<TokenAccount>> {
        self.token_manager.get_token_accounts(owner, mint)
    }

    /// Get account info
    pub fn get_account_info(&self, pubkey: &str) -> Result<AccountInfo> {
        self.account_manager.get_account_info(pubkey)
    }

    /// Get multiple account infos
    pub fn get_multiple_account_infos(&self, pubkeys: &[&str]) -> Result<Vec<Option<AccountInfo>>> {
        self.account_manager.get_multiple_account_infos(pubkeys)
    }

    /// Subscribe to account changes
    pub fn subscribe_to_account(&self, pubkey: &str) -> Result<AccountSubscription> {
        let ws_client = self.websocket_client.as_ref()
            .ok_or_else(|| anyhow::anyhow!("WebSocket client not available"))?;

        ws_client.subscribe_account(pubkey)
    }

    /// Get recent blockhash
    pub fn get_recent_blockhash(&self) -> Result<solana_sdk::hash::Hash> {
        self.client.get_latest_blockhash()
    }

    /// Calculate transaction fees
    pub fn calculate_transaction_fees(&self, transaction: &solana_sdk::transaction::Transaction) -> Result<u64> {
        self.client.calculate_fees(transaction)
    }

    /// Simulate transaction
    pub fn simulate_transaction(
        &self,
        transaction: &solana_sdk::transaction::Transaction,
    ) -> Result<TransactionSimulation> {
        self.client.simulate_transaction(transaction)
    }

    /// Get token supply
    pub fn get_token_supply(&self, mint: &str) -> Result<u64> {
        self.token_manager.get_token_supply(mint)
    }

    /// Get token info
    pub fn get_token_info(&self, mint: &str) -> Result<TokenInfo> {
        self.token_manager.get_token_info(mint)
    }

    /// Create token account
    pub fn create_token_account(
        &self,
        owner: &str,
        mint: &str,
        keypair: &crate::crypto::keypair::SecureKeypair,
    ) -> Result<String> {
        self.token_manager.create_token_account(owner, mint, keypair)
    }

    /// Close token account
    pub fn close_token_account(
        &self,
        token_account: &str,
        owner: &str,
        keypair: &crate::crypto::keypair::SecureKeypair,
    ) -> Result<solana_sdk::transaction::Transaction> {
        self.token_manager.close_token_account(token_account, owner, keypair)
    }

    /// Get program accounts
    pub fn get_program_accounts(&self, program_id: &str) -> Result<Vec<(String, AccountInfo)>> {
        self.program_client.get_program_accounts(program_id)
    }

    /// Execute program instruction
    pub fn execute_program_instruction(
        &self,
        instruction: &solana_sdk::instruction::Instruction,
        fee_payer: &str,
        signers: &[&crate::crypto::keypair::SecureKeypair],
    ) -> Result<TransactionStatus> {
        let mut builder = TransactionBuilder::new();
        builder.set_fee_payer(fee_payer);
        builder.add_instruction(instruction.clone());

        let transaction = builder.build(&self.client)?;
        let signed_tx = self.client.sign_transaction_with_signers(&transaction, signers)?;

        let signature = self.client.send_transaction(&signed_tx)?;
        self.client.confirm_transaction(&signature)
    }

    /// Get cluster health status
    pub fn get_cluster_health(&self) -> Result<ClusterHealth> {
        let slot = self.client.get_slot()?;
        let health = self.client.get_health()?;
        let version = self.client.get_version()?;

        Ok(ClusterHealth {
            is_healthy: health == "ok",
            current_slot: slot,
            solana_version: version.solana_core,
            feature_set: version.feature_set,
        })
    }

    /// Estimate compute units for transaction
    pub fn estimate_compute_units(&self, transaction: &solana_sdk::transaction::Transaction) -> Result<u64> {
        self.client.estimate_compute_units(transaction)
    }

    /// Optimize transaction for lower fees
    pub fn optimize_transaction_fees(
        &self,
        mut transaction: solana_sdk::transaction::Transaction,
    ) -> Result<solana_sdk::transaction::Transaction> {
        // Set compute unit limit
        let compute_budget_ix = solana_sdk::compute_budget::ComputeBudgetInstruction::set_compute_unit_limit(1_400_000);
        transaction.message.instructions.insert(0, compute_budget_ix);

        // Set compute unit price (priority fee)
        let compute_price_ix = solana_sdk::compute_budget::ComputeBudgetInstruction::set_compute_unit_price(1);
        transaction.message.instructions.insert(1, compute_price_ix);

        Ok(transaction)
    }
}

/// Solana configuration
#[derive(Debug, Clone)]
pub struct SolanaConfig {
    pub commitment_level: CommitmentLevel,
    pub preflight_commitment: CommitmentLevel,
    pub encoding: String,
    pub max_retries: u32,
    pub retry_delay: std::time::Duration,
    pub timeout: std::time::Duration,
}

impl Default for SolanaConfig {
    fn default() -> Self {
        Self {
            commitment_level: CommitmentLevel::Confirmed,
            preflight_commitment: CommitmentLevel::Finalized,
            encoding: "base64".to_string(),
            max_retries: 3,
            retry_delay: std::time::Duration::from_millis(1000),
            timeout: std::time::Duration::from_secs(30),
        }
    }
}

/// Cluster health information
#[derive(Debug, Clone)]
pub struct ClusterHealth {
    pub is_healthy: bool,
    pub current_slot: u64,
    pub solana_version: String,
    pub feature_set: u32,
}

/// Transaction simulation result
#[derive(Debug, Clone)]
pub struct TransactionSimulation {
    pub err: Option<serde_json::Value>,
    pub logs: Vec<String>,
    pub accounts: Option<Vec<serde_json::Value>>,
    pub units_consumed: Option<u64>,
    pub return_data: Option<serde_json::Value>,
}

impl Default for SolanaEngine {
    fn default() -> Self {
        Self::new("https://api.mainnet-beta.solana.com", None).unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_solana_engine_creation() {
        let engine = SolanaEngine::new("https://api.mainnet-beta.solana.com", None);
        assert!(engine.is_ok());
    }

    #[test]
    fn test_solana_config_default() {
        let config = SolanaConfig::default();
        assert!(matches!(config.commitment_level, CommitmentLevel::Confirmed));
        assert_eq!(config.max_retries, 3);
    }

    #[test]
    fn test_address_validation() {
        // Valid Solana addresses
        assert!(SolanaUtils::is_valid_address("11111111111111111111111111111112"));
        assert!(SolanaUtils::is_valid_address("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"));

        // Invalid addresses
        assert!(!SolanaUtils::is_valid_address("invalid"));
        assert!(!SolanaUtils::is_valid_address(""));
    }

    #[test]
    fn test_lamport_conversion() {
        let sol = 1.0;
        let lamports = SolanaUtils::sol_to_lamports(sol);
        assert_eq!(lamports, 1_000_000_000);

        let back_to_sol = SolanaUtils::lamports_to_sol(lamports);
        assert_eq!(back_to_sol, sol);
    }
}