//! Solend Flash Loan Integration
//! Minimal implementation for Solend protocol flash loans

use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use solana_sdk::{
    instruction::{AccountMeta, Instruction},
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
};
use serde_json::{json, Value};
use std::time::{Duration, Instant};
use tokio::time::timeout;

// Solend Program Constants
const SOLEND_PROGRAM_ID: Pubkey = solana_program::pubkey!("So1endDq2YkqhipRh3WViPa8hdiSpxWy6z3Z6tMCpAo");
const WSOL_MINT: Pubkey = solana_program::pubkey!("So11111111111111111111111111111111111111112");

#[derive(Debug, Clone)]
pub struct SolendFlashLoanConfig {
    pub program_id: Pubkey,
    lending_market: Pubkey,
    reserve: Pubkey,
    max_loan_amount: u64,
    fee_bps: u64, // 0.05% = 5 bps
    slippage_bps: u64,
}

impl Default for SolendFlashLoanConfig {
    fn default() -> Self {
        Self {
            program_id: SOLEND_PROGRAM_ID,
            lending_market: Pubkey::default(), // Set from Vault or Solend API
            reserve: Pubkey::default(),     // Set from Vault or Solend API
            max_loan_amount: 5_000_000_000, // 5 SOL
            fee_bps: 5,                   // 0.05%
            slippage_bps: 50,
        }
    }
}

pub struct SolendFlashLoanEngine {
    config: SolendFlashLoanConfig,
    http_client: reqwest::Client,
    rpc_client: std::sync::Arc<crate::execution::rpc_client::RpcClient>,
}

impl SolendFlashLoanEngine {
    pub fn new(config: SolendFlashLoanConfig, rpc_client: std::sync::Arc<crate::execution::rpc_client::RpcClient>) -> Self {
        Self {
            config,
            http_client: reqwest::Client::builder()
                .timeout(Duration::from_secs(5))
                .build()
                .expect("Failed to create HTTP client"),
            rpc_client,
        }
    }

    /// Get dynamic priority fee from Jito API
    async fn get_dynamic_priority_fee(&self) -> Result<u64, Box<dyn std::error::Error>> {
        let response = self.http_client
            .get("https://api.mainnet-beta.solana.com")
            .header("Authorization", std::env::var("JITO_API_KEY").unwrap_or_default())
            .send()
            .await?;

        let json: Value = response.json().await?;
        Ok(json["priorityFee"].as_u64().unwrap_or(10000))
    }

    /// Get Jupiter swap quote
    async fn get_jupiter_quote(
        &self,
        input_mint: &Pubkey,
        output_mint: &Pubkey,
        amount: u64,
        slippage_bps: u64,
    ) -> Result<Value, Box<dyn std::error::Error>> {
        let quote_params = json!({
            "inputMint": input_mint.to_string(),
            "outputMint": output_mint.to_string(),
            "amount": amount.to_string(),
            "slippageBps": slippage_bps,
            "onlyDirectRoutes": true,
            "asLegacyTransaction": false
        });

        let response = self.http_client
            .post("https://quote-api.jup.ag/v6/quote")
            .header("Content-Type", "application/json")
            .json(&quote_params)
            .send()
            .await?;

        Ok(response.json().await?)
    }

    /// Get Jupiter swap instruction
    async fn get_jupiter_swap_instruction(
        &self,
        quote: &Value,
        user_public_key: &Pubkey,
    ) -> Result<Instruction, Box<dyn std::error::Error>> {
        let swap_request = json!({
            "quoteResponse": quote,
            "userPublicKey": user_public_key.to_string(),
            "wrapAndUnwrapSol": true,
            "useSharedAccounts": true,
            "feeAccount": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
        });

        let response = self.http_client
            .post("https://quote-api.jup.ag/v6/swap")
            .header("Content-Type", "application/json")
            .json(&swap_request)
            .send()
            .await?;

        let swap_data = response.json().await?;
        let swap_transaction = swap_data["swapTransaction"].as_str()
            .ok_or("Invalid swap transaction")?;

        let decoded = base64::decode(swap_transaction)
            .map_err(|e| format!("Failed to decode swap transaction: {}", e))?;

        Ok(Instruction::new_with_bytes(
            swap_data["routePlan"]["swapInfo"]["ammId"].as_str()
                .and_then(|s| s.parse().ok())
                .unwrap_or_default(),
            &decoded,
            vec![],
        ))
    }

    /// Create Solend flash loan instruction
    fn create_flash_loan_instruction(
        &self,
        loan_amount: u64,
        lending_market: &Pubkey,
        reserve: &Pubkey,
        user_key: &Pubkey,
        is_repayment: bool,
    ) -> Result<Instruction, Box<dyn std::error::Error>> {
        // Solend flash loan instruction layout
        // First byte: 0 for borrow, 1 for repayment
        let mut instruction_data = vec![if is_repayment { 1 } else { 0 }];
        instruction_data.extend_from_slice(&loan_amount.to_le_bytes());

        let accounts = vec![
            AccountMeta::new(lending_market, false),  // Lending market
            AccountMeta::new(reserve, false),          // Reserve
            AccountMeta::new(user_key, true),             // User wallet
            AccountMeta::new(solana_program::sysvar::clock::id(), false),
        ];

        Ok(Instruction::new_with_bytes(self.config.program_id, &instruction_data, accounts))
    }

    /// Execute Solend flash loan trade
    pub async fn execute_flash_loan_snipe(
        &self,
        keypair: &Keypair,
        token_mint: &Pubkey,
        amount: u64,
        slippage_bps: u64,
    ) -> Result<crate::execution::flash_loan::FlashLoanResult, Box<dyn std::error::Error>> {
        let start_time = Instant::now();

        // Validate amount
        if amount > self.config.max_loan_amount {
            return Ok(crate::execution::flash_loan::FlashLoanResult {
                success: false,
                transaction_id: String::new(),
                execution_time_ms: start_time.elapsed().as_millis(),
                actual_amount_out: 0,
                fees_paid: 0,
                error_message: Some("Amount exceeds maximum flash loan limit".to_string()),
            });
        }

        info!("Executing Solend flash loan: {} lamports for token {}", amount, token_mint);

        // Get Jupiter quote
        let quote = timeout(
            Duration::from_millis(100),
            self.get_jupiter_quote(&WSOL_MINT, token_mint, amount, slippage_bps),
        )
        .await
        .map_err(|_| anyhow!("Jupiter quote timeout"))??;

        debug!("Jupiter quote received: {:?}", quote);

        // Get dynamic priority fee
        let priority_fee = self.get_dynamic_priority_fee().await.unwrap_or(10000);

        // Create flash loan instructions
        let mut instructions = Vec::with_capacity(4);

        // Flash loan borrow
        instructions.push(self.create_flash_loan_instruction(
            amount,
            &self.config.lending_market,
            &self.config.reserve,
            &keypair.pubkey(),
            false, // Not repayment
        )?);

        // Jupiter swap
        let swap_instruction = self.get_jupiter_swap_instruction(&quote, &keypair.pubkey()).await?;
        instructions.push(swap_instruction);

        // Flash loan repayment
        let repayment_amount = amount + (amount * self.config.fee_bps / 10000);
        instructions.push(self.create_flash_loan_instruction(
            repayment_amount,
            &self.config.lending_market,
            &self.config.reserve,
            &keypair.pubkey(),
            true, // This is repayment
        )?);

        // Add compute budget instruction for priority fee
        instructions.insert(
            0,
            solana_sdk::compute_budget::ComputeBudgetInstruction::set_compute_unit_price(priority_fee),
        );

        // Get recent blockhash
        let recent_blockhash = self.rpc_client
            .get_latest_blockhash_with_commitment(solana_sdk::commitment_config::CommitmentConfig::confirmed())
            .await?;

        // Create transaction
        let transaction = Transaction::new_signed_with_payer(
            &instructions,
            Some(&keypair.pubkey()),
            vec![keypair],
            recent_blockhash.value.blockhash,
        );

        // Serialize and send transaction
        let transaction_signature = self.rpc_client
            .send_and_confirm_transaction_with_spinner(
                &transaction,
                &recent_blockhash.value.blockhash,
                solana_sdk::commitment_config::CommitmentConfig::confirmed(),
            )
            .await
            .map_err(|e| anyhow!("Failed to send transaction: {}", e))?;

        let execution_time = start_time.elapsed().as_millis();

        // Calculate fees
        let jito_fee = priority_fee * transaction.message().instructions().len() as u64;
        let solend_fee = amount * self.config.fee_bps / 10000;
        let total_fees = jito_fee + solend_fee;

        info!("Solend flash loan executed successfully: signature={}, time={}ms",
              transaction_signature, execution_time);

        // Publish event to Redis
        if let Ok(redis_client) = self.get_redis_client() {
            let event = json!({
                "action": "solend_flash_loan_snipe",
                "token": token_mint.to_string(),
                "amount": amount,
                "signature": transaction_signature.to_string(),
                "execution_time_ms": execution_time,
                "fees_paid": total_fees,
                "protocol": "solend"
            });

            if let Err(e) = redis_client
                .publish("sniper_events", serde_json::to_string(&event)?)
                .await
            {
                warn!("Failed to publish event to Redis: {}", e);
            }
        }

        Ok(crate::execution::flash_loan::FlashLoanResult {
            success: true,
            transaction_id: transaction_signature.to_string(),
            execution_time_ms: execution_time,
            actual_amount_out: quote["outAmount"].as_u64().unwrap_or(0),
            fees_paid: total_fees,
            error_message: None,
        })
    }

    /// Get Redis client for event publishing
    fn get_redis_client(&self) -> Result<fred::prelude::RedisClient, Box<dyn std::error::Error>> {
        Ok(fred::prelude::RedisClient::new("redis://dragonfly:6379")?)
    }

    /// Get lending market and reserve info from Solend API
    pub async fn get_solend_market_data(&self, token_mint: &Pubkey) -> Result<(Pubkey, Pubkey), Box<dyn std::error::Error>> {
        // In production, this would fetch from Solend API
        // For now, return default values that would be configured from Vault
        info!("Using default Solend market data for token: {}", token_mint);
        Ok((self.config.lending_market, self.config.reserve))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_solend_flash_loan_config() {
        let config = SolendFlashLoanConfig::default();
        assert_eq!(config.max_loan_amount, 5_000_000_000);
        assert_eq!(config.fee_bps, 5); // 0.05%
    }

    #[tokio::test]
    async fn test_flash_loan_instruction_creation() {
        let config = SolendFlashLoanConfig::default();
        let engine = SolendFlashLoanEngine::new(
            config,
            std::sync::Arc::new(
                crate::execution::rpc_client::RpcClient::new(
                    "https://api.mainnet-beta.solana.com".to_string()
                ).unwrap()
            ),
        );

        let keypair = Keypair::new();
        let reserve = Pubkey::new_unique();
        let lending_market = Pubkey::new_unique();

        // Test borrow instruction
        let borrow_instruction = engine.create_flash_loan_instruction(
            1_000_000_000,
            &lending_market,
            &reserve,
            &keypair.pubkey(),
            false,
        );

        assert!(borrow_instruction.is_ok());

        // Test repayment instruction
        let repayment_instruction = engine.create_flash_loan_instruction(
            1_050_000_000, // 1 SOL + 0.05 SOL fee
            &lending_market,
            &reserve,
            &keypair.pubkey(),
            true,
        );

        assert!(repayment_instruction.is_ok());
    }
}