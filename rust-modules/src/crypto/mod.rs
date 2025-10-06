//! Core cryptographic utilities for secure trading operations
//!
//! This module provides essential cryptographic functions for:
//! - Key generation and management
//! - Digital signatures
//! - Hash functions
//! - Secure random number generation
//! - Encryption/decryption

pub mod keypair;
pub mod signature;
pub mod hash;
pub mod random;
pub mod encryption;

pub use keypair::{KeypairManager, SecureKeypair};
pub use signature::{SignatureVerifier, MessageSigner};
pub use hash::{HashUtils, MerkleTree};
pub use random::SecureRandom;
pub use encryption::{DataEncryptor, SecureStorage};

use anyhow::Result;

/// Main cryptographic interface for the trading bot
pub struct CryptoEngine {
    keypair_manager: KeypairManager,
    signature_verifier: SignatureVerifier,
    encryptor: DataEncryptor,
}

impl CryptoEngine {
    /// Create a new cryptographic engine
    pub fn new() -> Result<Self> {
        Ok(Self {
            keypair_manager: KeypairManager::new()?,
            signature_verifier: SignatureVerifier::new()?,
            encryptor: DataEncryptor::new()?,
        })
    }

    /// Get the keypair manager
    pub fn keypair_manager(&self) -> &KeypairManager {
        &self.keypair_manager
    }

    /// Get the signature verifier
    pub fn signature_verifier(&self) -> &SignatureVerifier {
        &self.signature_verifier
    }

    /// Get the encryptor
    pub fn encryptor(&self) -> &DataEncryptor {
        &self.encryptor
    }

    /// Initialize the cryptographic engine with a seed
    pub fn initialize_with_seed(&mut self, seed: &[u8]) -> Result<()> {
        self.keypair_manager.from_seed(seed)?;
        Ok(())
    }

    /// Generate a new keypair
    pub fn generate_keypair(&mut self) -> Result<SecureKeypair> {
        self.keypair_manager.generate()
    }

    /// Sign a message with the current keypair
    pub fn sign_message(&self, message: &[u8]) -> Result<Vec<u8>> {
        self.signature_verifier.sign(message, &self.keypair_manager.get_keypair()?)
    }

    /// Verify a signature
    pub fn verify_signature(&self, message: &[u8], signature: &[u8], public_key: &[u8]) -> Result<bool> {
        self.signature_verifier.verify(message, signature, public_key)
    }

    /// Encrypt sensitive data
    pub fn encrypt_data(&self, data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        self.encryptor.encrypt(data, key)
    }

    /// Decrypt sensitive data
    pub fn decrypt_data(&self, encrypted_data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        self.encryptor.decrypt(encrypted_data, key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_crypto_engine_initialization() {
        let engine = CryptoEngine::new().unwrap();
        assert!(engine.keypair_manager().get_keypair().is_err()); // No keypair yet
    }

    #[test]
    fn test_keypair_generation() {
        let mut engine = CryptoEngine::new().unwrap();
        let keypair = engine.generate_keypair().unwrap();
        assert!(!keypair.public_key().is_empty());
        assert!(!keypair.private_key().is_empty());
    }

    #[test]
    fn test_message_signing_and_verification() {
        let mut engine = CryptoEngine::new().unwrap();
        let keypair = engine.generate_keypair().unwrap();

        let message = b"test message for signing";
        let signature = engine.sign_message(message).unwrap();
        let public_key = keypair.public_key();

        let is_valid = engine.verify_signature(message, &signature, public_key).unwrap();
        assert!(is_valid);
    }

    #[test]
    fn test_encryption_decryption() {
        let engine = CryptoEngine::new().unwrap();
        let data = b"sensitive trading data";
        let key = b"encryption_key_32_bytes_long";

        let encrypted = engine.encrypt_data(data, key).unwrap();
        let decrypted = engine.decrypt_data(&encrypted, key).unwrap();

        assert_eq!(data.to_vec(), decrypted);
    }
}