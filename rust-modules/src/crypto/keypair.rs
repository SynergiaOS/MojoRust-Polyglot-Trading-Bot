//! Secure keypair management for Solana trading operations
//!
//! Provides secure generation, storage, and management of cryptographic keypairs
//! used for signing transactions and authenticating with the Solana network.

use crate::crypto::random::SecureRandom;
use anyhow::{anyhow, Result};
use ed25519_dalek::{Keypair as Ed25519Keypair, PublicKey, SecretKey, Signer, Verifier};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;
use zeroize::Zeroize;

/// Secure wrapper for ed25519 keypair with memory safety
#[derive(Clone)]
pub struct SecureKeypair {
    keypair: Ed25519Keypair,
}

impl SecureKeypair {
    /// Create a new secure keypair from raw bytes
    pub fn from_bytes(bytes: &[u8]) -> Result<Self> {
        if bytes.len() != 64 {
            return Err(anyhow!("Invalid keypair length: expected 64 bytes, got {}", bytes.len()));
        }

        let secret = SecretKey::from_bytes(&bytes[..32])?;
        let public = PublicKey::from_bytes(&bytes[32..])?;

        let keypair = Ed25519Keypair { secret, public };
        Ok(Self { keypair })
    }

    /// Generate a new random keypair
    pub fn generate() -> Result<Self> {
        let mut rng = SecureRandom::new();
        let keypair = Ed25519Keypair::generate(&mut rng);
        Ok(Self { keypair })
    }

    /// Get the public key bytes
    pub fn public_key(&self) -> Vec<u8> {
        self.keypair.public.to_bytes().to_vec()
    }

    /// Get the private key bytes (secret)
    pub fn private_key(&self) -> Vec<u8> {
        self.keypair.secret.as_bytes().to_vec()
    }

    /// Get the full keypair bytes (private + public)
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = vec![0u8; 64];
        bytes[..32].copy_from_slice(self.keypair.secret.as_bytes());
        bytes[32..].copy_from_slice(self.keypair.public.as_bytes());
        bytes
    }

    /// Get the Solana address (base58 encoded)
    pub fn to_solana_address(&self) -> String {
        // Use Solana's base58 encoding
        solana_sdk::pubkey::Pubkey::from(self.keypair.public).to_string()
    }

    /// Sign a message
    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        self.keypair.sign(message).to_bytes().to_vec()
    }

    /// Verify a signature
    pub fn verify(&self, message: &[u8], signature: &[u8]) -> Result<bool> {
        if signature.len() != 64 {
            return Err(anyhow!("Invalid signature length"));
        }

        let signature = ed25519_dalek::Signature::from_bytes(signature)?;
        Ok(self.keypair.public.verify(message, &signature).is_ok())
    }
}

impl Drop for SecureKeypair {
    fn drop(&mut self) {
        // Zero out sensitive data when dropping
        self.keypair.secret.as_bytes().zeroize();
    }
}

/// Keypair storage format for serialization
#[derive(Serialize, Deserialize)]
pub struct KeypairStorage {
    pub version: u8,
    pub encrypted: bool,
    pub keypair_data: Vec<u8>,
    pub metadata: KeypairMetadata,
}

#[derive(Serialize, Deserialize)]
pub struct KeypairMetadata {
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub last_used: Option<chrono::DateTime<chrono::Utc>>,
    pub label: Option<String>,
    pub purpose: String,
}

/// Secure keypair manager with storage and retrieval capabilities
pub struct KeypairManager {
    current_keypair: Option<SecureKeypair>,
    storage_path: Option<String>,
}

impl KeypairManager {
    /// Create a new keypair manager
    pub fn new() -> Result<Self> {
        Ok(Self {
            current_keypair: None,
            storage_path: None,
        })
    }

    /// Set the storage path for keypair persistence
    pub fn set_storage_path<P: AsRef<Path>>(&mut self, path: P) {
        self.storage_path = Some(path.as_ref().to_string_lossy().to_string());
    }

    /// Generate a new keypair
    pub fn generate(&mut self) -> Result<SecureKeypair> {
        let keypair = SecureKeypair::generate()?;
        self.current_keypair = Some(keypair.clone());
        Ok(keypair)
    }

    /// Load keypair from seed
    pub fn from_seed(&mut self, seed: &[u8]) -> Result<SecureKeypair> {
        if seed.len() < 32 {
            return Err(anyhow!("Seed must be at least 32 bytes"));
        }

        // Use first 32 bytes as seed for keypair generation
        let seed_array: [u8; 32] = seed[..32].try_into()
            .map_err(|_| anyhow!("Failed to create seed array"))?;

        let secret_key = SecretKey::from_bytes(&seed_array)?;
        let public_key = PublicKey::from(&secret_key);
        let keypair = Ed25519Keypair { secret: secret_key, public: public_key };

        let secure_keypair = SecureKeypair { keypair };
        self.current_keypair = Some(secure_keypair.clone());
        Ok(secure_keypair)
    }

    /// Load keypair from file
    pub fn from_file<P: AsRef<Path>>(&mut self, path: P) -> Result<SecureKeypair> {
        let content = fs::read_to_string(path)?;
        let storage: KeypairStorage = serde_json::from_str(&content)?;

        let keypair = if storage.encrypted {
            // Handle encrypted keypair storage
            return Err(anyhow!("Encrypted keypair storage not yet implemented"));
        } else {
            SecureKeypair::from_bytes(&storage.keypair_data)?
        };

        self.current_keypair = Some(keypair.clone());
        Ok(keypair)
    }

    /// Save current keypair to file
    pub fn save_to_file<P: AsRef<Path>>(&self, path: P, label: Option<String>) -> Result<()> {
        let keypair = self.current_keypair.as_ref()
            .ok_or_else(|| anyhow!("No keypair to save"))?;

        let storage = KeypairStorage {
            version: 1,
            encrypted: false,
            keypair_data: keypair.to_bytes(),
            metadata: KeypairMetadata {
                created_at: chrono::Utc::now(),
                last_used: None,
                label,
                purpose: "trading".to_string(),
            },
        };

        let json = serde_json::to_string_pretty(&storage)?;
        fs::write(path, json)?;
        Ok(())
    }

    /// Get the current keypair
    pub fn get_keypair(&self) -> Result<SecureKeypair> {
        self.current_keypair.clone()
            .ok_or_else(|| anyhow!("No keypair loaded"))
    }

    /// Import keypair from Solana CLI format
    pub fn import_from_solana_cli<P: AsRef<Path>>(&mut self, path: P) -> Result<SecureKeypair> {
        let content = fs::read_to_string(path)?;

        // Parse array format like [1,2,3,...]
        let content = content.trim().trim_start_matches('[').trim_end_matches(']');
        let bytes: Result<Vec<u8>, _> = content
            .split(',')
            .map(|s| s.trim().parse::<u8>())
            .collect();

        let bytes = bytes.map_err(|_| anyhow!("Failed to parse keypair file"))?;

        let keypair = SecureKeypair::from_bytes(&bytes)?;
        self.current_keypair = Some(keypair.clone());
        Ok(keypair)
    }

    /// Validate keypair integrity
    pub fn validate_keypair(&self, keypair: &SecureKeypair) -> Result<bool> {
        // Test signing and verification with a test message
        let test_message = b"validation_test_message";
        let signature = keypair.sign(test_message);
        keypair.verify(test_message, &signature)
    }

    /// Generate keypair from mnemonic phrase
    pub fn from_mnemonic(&mut self, mnemonic: &str, passphrase: Option<&str>) -> Result<SecureKeypair> {
        // This would require implementing BIP39 functionality
        // For now, use a simple hash-based derivation
        use sha2::{Digest, Sha256};

        let mut hasher = Sha256::new();
        hasher.update(mnemonic.as_bytes());
        if let Some(passphrase) = passphrase {
            hasher.update(passphrase.as_bytes());
        }
        let hash = hasher.finalize();

        self.from_seed(&hash)
    }
}

impl Default for KeypairManager {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_secure_keypair_generation() {
        let keypair = SecureKeypair::generate().unwrap();
        assert_eq!(keypair.public_key().len(), 32);
        assert_eq!(keypair.private_key().len(), 32);
    }

    #[test]
    fn test_keypair_from_bytes() {
        let keypair1 = SecureKeypair::generate().unwrap();
        let bytes = keypair1.to_bytes();
        let keypair2 = SecureKeypair::from_bytes(&bytes).unwrap();

        assert_eq!(keypair1.public_key(), keypair2.public_key());
        assert_eq!(keypair1.private_key(), keypair2.private_key());
    }

    #[test]
    fn test_message_signing() {
        let keypair = SecureKeypair::generate().unwrap();
        let message = b"test message";
        let signature = keypair.sign(message);

        assert_eq!(signature.len(), 64);
        assert!(keypair.verify(message, &signature).unwrap());
    }

    #[test]
    fn test_keypair_storage() {
        let mut manager = KeypairManager::new();
        let keypair = manager.generate().unwrap();

        let temp_dir = tempdir().unwrap();
        let file_path = temp_dir.path().join("test_keypair.json");

        manager.save_to_file(&file_path, Some("test".to_string())).unwrap();

        let mut manager2 = KeypairManager::new();
        let loaded_keypair = manager2.from_file(&file_path).unwrap();

        assert_eq!(keypair.public_key(), loaded_keypair.public_key());
    }

    #[test]
    fn test_keypair_validation() {
        let keypair = SecureKeypair::generate().unwrap();
        let mut manager = KeypairManager::new();

        assert!(manager.validate_keypair(&keypair).unwrap());
    }

    #[test]
    fn test_mnemonic_derivation() {
        let mut manager = KeypairManager::new();
        let mnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about";

        let keypair1 = manager.from_mnemonic(mnemonic, None).unwrap();
        let keypair2 = manager.from_mnemonic(mnemonic, Some("password")).unwrap();

        // Same mnemonic but different passphrase should give different keys
        assert_ne!(keypair1.public_key(), keypair2.public_key());
    }
}