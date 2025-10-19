//! Instruction Parsers for Enhanced Geyser Event Detection
//!
//! This module provides specialized parsers for different DEX instruction formats,
//! improving pool detection and event classification accuracy.

use std::collections::HashMap;
use solana_sdk::pubkey::Pubkey;
use solana_sdk::instruction::{Instruction, AccountMeta};
use anyhow::{Result, anyhow};

/// Parsed instruction information
#[derive(Debug, Clone)]
pub struct ParsedInstruction {
    pub program_id: String,
    pub instruction_type: String,
    pub accounts: Vec<String>,
    pub data: Vec<u8>,
    pub metadata: HashMap<String, String>,
}

/// Parser for different DEX instruction types
pub struct DexInstructionParser;

impl DexInstructionParser {
    /// Parse a Solana instruction and extract DEX-specific information
    pub fn parse_instruction(
        program_id: &Pubkey,
        accounts: &[AccountMeta],
        data: &[u8]
    ) -> Result<ParsedInstruction> {
        let program_id_str = program_id.to_string();

        match program_id_str.as_str() {
            // Raydium AMM
            "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8" => {
                Self::parse_raydium_instruction(accounts, data)
            },

            // Orca V1
            "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP" => {
                Self::parse_orca_v1_instruction(accounts, data)
            },

            // Orca Whirlpool
            "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc" => {
                Self::parse_orca_whirlpool_instruction(accounts, data)
            },

            // Pump.fun
            "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P" => {
                Self::parse_pump_fun_instruction(accounts, data)
            },

            // Raydium CLMM
            "TSLvdd1pWpHVjahSpsvCXUbgwsL3JAcvokwaKt1eokM" => {
                Self::parse_raydium_clmm_instruction(accounts, data)
            },

            _ => {
                // Unknown program - return generic parsing
                Ok(ParsedInstruction {
                    program_id: program_id_str,
                    instruction_type: "unknown".to_string(),
                    accounts: accounts.iter().map(|acc| acc.pubkey.to_string()).collect(),
                    data: data.to_vec(),
                    metadata: HashMap::new(),
                })
            }
        }
    }

    /// Parse Raydium AMM instructions
    fn parse_raydium_instruction(accounts: &[AccountMeta], data: &[u8]) -> Result<ParsedInstruction> {
        let instruction_type = if data.len() >= 8 {
            match data[0] {
                0 => "initialize_pool".to_string(),
                1 => "deposit".to_string(),
                2 => "withdraw".to_string(),
                3 => "swap".to_string(),
                _ => "raydium_unknown".to_string(),
            }
        } else {
            "raydium_invalid".to_string()
        };

        let mut metadata = HashMap::new();

        // Extract pool-related accounts
        if accounts.len() >= 4 {
            metadata.insert("authority".to_string(), accounts[0].pubkey.to_string());
            metadata.insert("amm_authority".to_string(), accounts[1].pubkey.to_string());
            metadata.insert("amm_open_orders".to_string(), accounts[2].pubkey.to_string());
            metadata.insert("amm_target_orders".to_string(), accounts[3].pubkey.to_string());
        }

        // Extract token accounts if available
        if accounts.len() >= 8 {
            metadata.insert("token_account_a".to_string(), accounts[6].pubkey.to_string());
            metadata.insert("token_account_b".to_string(), accounts[7].pubkey.to_string());
        }

        Ok(ParsedInstruction {
            program_id: "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8".to_string(),
            instruction_type,
            accounts: accounts.iter().map(|acc| acc.pubkey.to_string()).collect(),
            data: data.to_vec(),
            metadata,
        })
    }

    /// Parse Orca V1 instructions
    fn parse_orca_v1_instruction(accounts: &[AccountMeta], data: &[u8]) -> Result<ParsedInstruction> {
        let instruction_type = if data.len() >= 8 {
            match data[0] {
                0 => "initialize_swap".to_string(),
                1 => "swap".to_string(),
                2 => "deposit_all_token_types".to_string(),
                3 => "withdraw_all_token_types".to_string(),
                _ => "orca_v1_unknown".to_string(),
            }
        } else {
            "orca_v1_invalid".to_string()
        };

        let mut metadata = HashMap::new();

        if accounts.len() >= 8 {
            metadata.insert("swap_authority".to_string(), accounts[0].pubkey.to_string());
            metadata.insert("token_program".to_string(), accounts[1].pubkey.to_string());
            metadata.insert("swap".to_string(), accounts[2].pubkey.to_string());
            metadata.insert("swap_authority".to_string(), accounts[3].pubkey.to_string());
            metadata.insert("user_transfer_authority".to_string(), accounts[4].pubkey.to_string());
            metadata.insert("source".to_string(), accounts[5].pubkey.to_string());
            metadata.insert("destination".to_string(), accounts[6].pubkey.to_string());
            metadata.insert("user_source".to_string(), accounts[7].pubkey.to_string());
        }

        Ok(ParsedInstruction {
            program_id: "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP".to_string(),
            instruction_type,
            accounts: accounts.iter().map(|acc| acc.pubkey.to_string()).collect(),
            data: data.to_vec(),
            metadata,
        })
    }

    /// Parse Orca Whirlpool instructions
    fn parse_orca_whirlpool_instruction(accounts: &[AccountMeta], data: &[u8]) -> Result<ParsedInstruction> {
        let instruction_type = if data.len() >= 8 {
            match data[0] {
                0 => "initialize_pool".to_string(),
                1 => "swap".to_string(),
                2 => "deposit".to_string(),
                3 => "withdraw".to_string(),
                _ => "orca_whirlpool_unknown".to_string(),
            }
        } else {
            "orca_whirlpool_invalid".to_string()
        };

        let mut metadata = HashMap::new();

        if accounts.len() >= 10 {
            metadata.insert("whirlpool".to_string(), accounts[0].pubkey.to_string());
            metadata.insert("token_authority".to_string(), accounts[1].pubkey.to_string());
            metadata.insert("oracle".to_string(), accounts[2].pubkey.to_string());
            metadata.insert("tick_array".to_string(), accounts[3].pubkey.to_string());
            metadata.insert("source_token".to_string(), accounts[7].pubkey.to_string());
            metadata.insert("destination_token".to_string(), accounts[8].pubkey.to_string());
        }

        Ok(ParsedInstruction {
            program_id: "whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc".to_string(),
            instruction_type,
            accounts: accounts.iter().map(|acc| acc.pubkey.to_string()).collect(),
            data: data.to_vec(),
            metadata,
        })
    }

    /// Parse Pump.fun instructions
    fn parse_pump_fun_instruction(accounts: &[AccountMeta], data: &[u8]) -> Result<ParsedInstruction> {
        let instruction_type = if data.len() >= 8 {
            match data[0] {
                0 => "create".to_string(),
                1 => "buy".to_string(),
                2 => "sell".to_string(),
                3 => "withdraw".to_string(),
                _ => "pump_fun_unknown".to_string(),
            }
        } else {
            "pump_fun_invalid".to_string()
        };

        let mut metadata = HashMap::new();

        // Pump.fun usually has specific account structure
        if accounts.len() >= 6 {
            metadata.insert("mint".to_string(), accounts[0].pubkey.to_string());
            metadata.insert("bonding_curve".to_string(), accounts[1].pubkey.to_string());
            metadata.insert("associated_bonding_curve".to_string(), accounts[2].pubkey.to_string());
            metadata.insert("user".to_string(), accounts[4].pubkey.to_string());
            metadata.insert("system_program".to_string(), accounts[5].pubkey.to_string());
        }

        Ok(ParsedInstruction {
            program_id: "6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P".to_string(),
            instruction_type,
            accounts: accounts.iter().map(|acc| acc.pubkey.to_string()).collect(),
            data: data.to_vec(),
            metadata,
        })
    }

    /// Parse Raydium CLMM instructions
    fn parse_raydium_clmm_instruction(accounts: &[AccountMeta], data: &[u8]) -> Result<ParsedInstruction> {
        let instruction_type = if data.len() >= 8 {
            match data[0] {
                0 => "initialize_position".to_string(),
                1 => "increase_liquidity".to_string(),
                2 => "decrease_liquidity".to_string(),
                3 => "swap".to_string(),
                _ => "raydium_clmm_unknown".to_string(),
            }
        } else {
            "raydium_clmm_invalid".to_string()
        };

        let mut metadata = HashMap::new();

        if accounts.len() >= 12 {
            metadata.insert("pool".to_string(), accounts[0].pubkey.to_string());
            metadata.insert("authority".to_string(), accounts[1].pubkey.to_string());
            metadata.insert("token_vault_a".to_string(), accounts[7].pubkey.to_string());
            metadata.insert("token_vault_b".to_string(), accounts[8].pubkey.to_string());
            metadata.insert("user_token_a".to_string(), accounts[9].pubkey.to_string());
            metadata.insert("user_token_b".to_string(), accounts[10].pubkey.to_string());
        }

        Ok(ParsedInstruction {
            program_id: "TSLvdd1pWpHVjahSpsvCXUbgwsL3JAcvokwaKt1eokM".to_string(),
            instruction_type,
            accounts: accounts.iter().map(|acc| acc.pubkey.to_string()).collect(),
            data: data.to_vec(),
            metadata,
        })
    }

    /// Extract token mint from parsed instruction
    pub fn extract_token_mint(parsed: &ParsedInstruction) -> Option<String> {
        // Try to find token mint in metadata
        if let Some(mint) = parsed.metadata.get("mint") {
            return Some(mint.clone());
        }

        // Try to find token accounts
        for key in ["token_account_a", "token_account_b", "source_token", "destination_token"] {
            if let Some(token_account) = parsed.metadata.get(key) {
                return Some(token_account.clone());
            }
        }

        // Fallback to analyzing accounts (first non-system account)
        for account in &parsed.accounts {
            if !account.starts_with("11111111111111111111111111111111") && // System program
               !account.starts_with("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA") { // Token program
                return Some(account.clone());
            }
        }

        None
    }

    /// Extract pool ID from parsed instruction
    pub fn extract_pool_id(parsed: &ParsedInstruction) -> Option<String> {
        // Look for pool-related keys in metadata
        for key in ["whirlpool", "swap", "pool", "bonding_curve"] {
            if let Some(pool_id) = parsed.metadata.get(key) {
                return Some(pool_id.clone());
            }
        }

        None
    }

    /// Extract creator/authority from parsed instruction
    pub fn extract_creator(parsed: &ParsedInstruction) -> Option<String> {
        // Look for authority/user keys
        for key in ["user", "authority", "swap_authority", "user_source"] {
            if let Some(creator) = parsed.metadata.get(key) {
                return Some(creator.clone());
            }
        }

        None
    }

    /// Determine if instruction creates a new pool/token
    pub fn is_pool_creation(parsed: &ParsedInstruction) -> bool {
        matches!(
            parsed.instruction_type.as_str(),
            "initialize_pool" | "create" | "initialize_swap" | "initialize_position"
        )
    }

    /// Determine if instruction is a swap
    pub fn is_swap(parsed: &ParsedInstruction) -> bool {
        parsed.instruction_type.contains("swap") ||
        parsed.instruction_type.contains("buy") ||
        parsed.instruction_type.contains("sell")
    }

    /// Determine if instruction involves liquidity provision
    pub fn is_liquidity_operation(parsed: &ParsedInstruction) -> bool {
        parsed.instruction_type.contains("deposit") ||
        parsed.instruction_type.contains("withdraw") ||
        parsed.instruction_type.contains("increase_liquidity") ||
        parsed.instruction_type.contains("decrease_liquidity")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use solana_sdk::instruction::AccountMeta;
    use solana_sdk::pubkey::Pubkey;

    #[test]
    fn test_raydium_pool_creation_parsing() {
        let program_id = Pubkey::from_str("675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8").unwrap();

        let accounts = vec![
            AccountMeta::new_readonly(Pubkey::new_unique(), false),
            AccountMeta::new_readonly(Pubkey::new_unique(), false),
            AccountMeta::new(Pubkey::new_unique(), false),
            AccountMeta::new(Pubkey::new_unique(), false),
        ];

        let data = vec![0]; // initialize_pool instruction

        let parsed = DexInstructionParser::parse_instruction(&program_id, &accounts, &data).unwrap();

        assert_eq!(parsed.instruction_type, "initialize_pool");
        assert!(DexInstructionParser::is_pool_creation(&parsed));
    }

    #[test]
    fn test_pump_fun_buy_parsing() {
        let program_id = Pubkey::from_str("6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P").unwrap();

        let mint_pubkey = Pubkey::new_unique();
        let user_pubkey = Pubkey::new_unique();

        let accounts = vec![
            AccountMeta::new(mint_pubkey, false),
            AccountMeta::new(Pubkey::new_unique(), false),
            AccountMeta::new(Pubkey::new_unique(), false),
            AccountMeta::new(Pubkey::new_unique(), false),
            AccountMeta::new(user_pubkey, true),
            AccountMeta::new_readonly(Pubkey::new_unique(), false),
        ];

        let data = vec![1]; // buy instruction

        let parsed = DexInstructionParser::parse_instruction(&program_id, &accounts, &data).unwrap();

        assert_eq!(parsed.instruction_type, "buy");
        assert!(DexInstructionParser::is_swap(&parsed));
        assert_eq!(DexInstructionParser::extract_token_mint(&parsed), Some(mint_pubkey.to_string()));
        assert_eq!(DexInstructionParser::extract_creator(&parsed), Some(user_pubkey.to_string()));
    }
}