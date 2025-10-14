//! Solana transaction module for Mojo Trading Bot
//!
//! Provides Solana transaction building and signing.

use anyhow::Result;

/// Solana transaction builder
pub struct TransactionBuilder {
    instructions: Vec<Instruction>,
    fee_payer: String,
    recent_blockhash: String,
}

impl TransactionBuilder {
    pub fn new(fee_payer: String, recent_blockhash: String) -> Self {
        Self {
            instructions: Vec::new(),
            fee_payer,
            recent_blockhash,
        }
    }

    pub fn add_instruction(&mut self, instruction: Instruction) {
        self.instructions.push(instruction);
    }

    pub fn build(self) -> Result<Transaction> {
        Ok(Transaction {
            instructions: self.instructions,
            fee_payer: self.fee_payer,
            recent_blockhash: self.recent_blockhash,
            signatures: Vec::new(),
        })
    }
}

/// Solana transaction
#[derive(Debug, Clone)]
pub struct Transaction {
    pub instructions: Vec<Instruction>,
    pub fee_payer: String,
    pub recent_blockhash: String,
    pub signatures: Vec<String>,
}

/// Solana instruction
#[derive(Debug, Clone)]
pub struct Instruction {
    pub program_id: String,
    pub accounts: Vec<String>,
    pub data: Vec<u8>,
}
