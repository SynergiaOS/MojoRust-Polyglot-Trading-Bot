//! Solana utilities module for Mojo Trading Bot
//!
//! Provides utility functions for Solana operations.

use anyhow::Result;
use std::str::FromStr;

/// Solana address utilities
pub struct AddressUtils;

impl AddressUtils {
    /// Validate Solana address format
    pub fn is_valid_address(address: &str) -> bool {
        // Basic validation - Solana addresses are base58 encoded, 32-44 characters
        address.len() >= 32 && address.len() <= 44 && 
        address.chars().all(|c| c.is_ascii_alphanumeric() || c == "1" || c == "2" || c == "3")
    }

    /// Create a new random address (placeholder)
    pub fn generate_random_address() -> String {
        "11111111111111111111111111111111".to_string()
    }

    /// Convert address to bytes (placeholder)
    pub fn address_to_bytes(address: &str) -> Result<[u8; 32]> {
        if !Self::is_valid_address(address) {
            return Err(anyhow::anyhow!("Invalid address format"));
        }
        Ok([0u8; 32]) // Placeholder
    }
}

/// Utility functions for Solana operations
pub struct SolanaUtils;

impl SolanaUtils {
    /// Convert lamports to SOL
    pub fn lamports_to_sol(lamports: u64) -> f64 {
        lamports as f64 / 1_000_000_000.0
    }

    /// Convert SOL to lamports
    pub fn sol_to_lamports(sol: f64) -> u64 {
        (sol * 1_000_000_000.0) as u64
    }

    /// Calculate transaction fee (placeholder)
    pub fn calculate_transaction_fee(instructions: usize) -> u64 {
        5000 // Base fee in lamports
    }
}
