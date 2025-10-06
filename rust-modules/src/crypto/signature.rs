//! Digital signature utilities for secure transaction signing
//!
//! Provides comprehensive signature operations for Solana transactions
//! and message authentication with ed25519 cryptography.

use crate::crypto::keypair::SecureKeypair;
use anyhow::{anyhow, Result};
use ed25519_dalek::{PublicKey, Signature, Signer, Verifier};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Transaction signature with metadata
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransactionSignature {
    pub signature: Vec<u8>,
    pub public_key: Vec<u8>,
    pub message_hash: Vec<u8>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub metadata: SignatureMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignatureMetadata {
    pub purpose: SignaturePurpose,
    pub network: String,
    pub fee_paid: Option<u64>,
    pub slot: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SignaturePurpose {
    Transaction,
    Message,
    Authentication,
    DataAttestation,
}

/// Signature verification engine
pub struct SignatureVerifier {
    trusted_keys: HashMap<String, PublicKey>,
}

impl SignatureVerifier {
    /// Create a new signature verifier
    pub fn new() -> Result<Self> {
        Ok(Self {
            trusted_keys: HashMap::new(),
        })
    }

    /// Add a trusted public key
    pub fn add_trusted_key(&mut self, address: &str, public_key: Vec<u8>) -> Result<()> {
        let pubkey = PublicKey::from_bytes(&public_key)?;
        self.trusted_keys.insert(address.to_string(), pubkey);
        Ok(())
    }

    /// Remove a trusted key
    pub fn remove_trusted_key(&mut self, address: &str) {
        self.trusted_keys.remove(address);
    }

    /// Sign a message with a keypair
    pub fn sign(&self, message: &[u8], keypair: &SecureKeypair) -> Result<Vec<u8>> {
        let signature = keypair.sign(message);
        Ok(signature)
    }

    /// Verify a signature
    pub fn verify(&self, message: &[u8], signature: &[u8], public_key: &[u8]) -> Result<bool> {
        if signature.len() != 64 {
            return Err(anyhow!("Invalid signature length: expected 64, got {}", signature.len()));
        }

        if public_key.len() != 32 {
            return Err(anyhow!("Invalid public key length: expected 32, got {}", public_key.len()));
        }

        let signature = Signature::from_bytes(signature)?;
        let public_key = PublicKey::from_bytes(public_key)?;

        Ok(public_key.verify(message, &signature).is_ok())
    }

    /// Verify signature from trusted key
    pub fn verify_trusted(&self, message: &[u8], signature: &[u8], address: &str) -> Result<bool> {
        let public_key = self.trusted_keys.get(address)
            .ok_or_else(|| anyhow!("Address {} not in trusted keys", address))?;

        if signature.len() != 64 {
            return Err(anyhow!("Invalid signature length"));
        }

        let signature = Signature::from_bytes(signature)?;
        Ok(public_key.verify(message, &signature).is_ok())
    }

    /// Batch verify multiple signatures
    pub fn batch_verify(&self, messages: &[&[u8]], signatures: &[&[u8]], public_keys: &[&[u8]]) -> Result<Vec<bool>> {
        if messages.len() != signatures.len() || signatures.len() != public_keys.len() {
            return Err(anyhow!("Mismatched array lengths for batch verification"));
        }

        let mut results = Vec::with_capacity(messages.len());

        for (i, (message, signature)) in messages.iter().zip(signatures.iter()).enumerate() {
            let public_key = public_keys[i];
            let result = self.verify(message, signature, public_key)?;
            results.push(result);
        }

        Ok(results)
    }

    /// Create a transaction signature
    pub fn create_transaction_signature(
        &self,
        message: &[u8],
        keypair: &SecureKeypair,
        metadata: SignatureMetadata,
    ) -> Result<TransactionSignature> {
        use sha2::{Digest, Sha256};

        // Hash the message for storage
        let mut hasher = Sha256::new();
        hasher.update(message);
        let message_hash = hasher.finalize().to_vec();

        let signature = self.sign(message, keypair)?;

        Ok(TransactionSignature {
            signature,
            public_key: keypair.public_key(),
            message_hash,
            timestamp: chrono::Utc::now(),
            metadata,
        })
    }

    /// Verify transaction signature
    pub fn verify_transaction_signature(&self, tx_sig: &TransactionSignature, message: &[u8]) -> Result<bool> {
        self.verify(message, &tx_sig.signature, &tx_sig.public_key)
    }

    /// Create message signature for authentication
    pub fn sign_message(
        &self,
        message: &str,
        keypair: &SecureKeypair,
        timestamp: Option<chrono::DateTime<chrono::Utc>>,
    ) -> Result<Vec<u8>> {
        let ts = timestamp.unwrap_or_else(chrono::Utc::now);
        let formatted_message = format!("{}:{}", message, ts.timestamp());
        self.sign(formatted_message.as_bytes(), keypair)
    }

    /// Verify message signature with timestamp
    pub fn verify_message_signature(
        &self,
        message: &str,
        signature: &[u8],
        public_key: &[u8],
        timestamp: chrono::DateTime<chrono::Utc>,
        max_age_seconds: u64,
    ) -> Result<bool> {
        // Check timestamp freshness
        let now = chrono::Utc::now();
        let age = now.signed_duration_since(timestamp);

        if age.num_seconds() > max_age_seconds as i64 {
            return Ok(false); // Signature too old
        }

        // Verify the signature
        let formatted_message = format!("{}:{}", message, timestamp.timestamp());
        self.verify(formatted_message.as_bytes(), signature, public_key)
    }

    /// Get signature info as string
    pub fn signature_info(&self, signature: &[u8]) -> String {
        if signature.len() == 64 {
            // Base58 encode for display
            bs58::encode(signature).into_string()
        } else {
            format!("Invalid signature ({} bytes)", signature.len())
        }
    }

    /// Check if signature is in valid format
    pub fn is_valid_signature_format(&self, signature: &[u8]) -> bool {
        signature.len() == 64
    }

    /// Get public key info as string
    pub fn public_key_info(&self, public_key: &[u8]) -> Result<String> {
        if public_key.len() == 32 {
            let pubkey = PublicKey::from_bytes(public_key)?;
            Ok(bs58::encode(pubkey.as_bytes()).into_string())
        } else {
            Err(anyhow!("Invalid public key length"))
        }
    }

    /// Verify Solana transaction signature
    pub fn verify_solana_transaction(&self, transaction: &[u8], signature: &[u8]) -> Result<bool> {
        // Parse Solana transaction and verify signature
        // This is a simplified version - in production, you'd use Solana SDK

        if signature.len() != 64 {
            return Ok(false);
        }

        // Extract message from transaction (simplified)
        // In reality, you'd deserialize the transaction properly
        let message_start = 1; // Skip signature length byte
        let message_end = transaction.len().saturating_sub(64);

        if message_end <= message_start {
            return Ok(false);
        }

        let message = &transaction[message_start..message_end];

        // Extract public key from transaction (simplified)
        // In reality, you'd extract the first signer's public key
        if message.len() < 32 {
            return Ok(false);
        }

        let public_key = &message[..32];

        self.verify(message, signature, public_key)
    }
}

/// Message signer for creating signed messages
pub struct MessageSigner {
    verifier: SignatureVerifier,
}

impl MessageSigner {
    /// Create a new message signer
    pub fn new() -> Result<Self> {
        Ok(Self {
            verifier: SignatureVerifier::new()?,
        })
    }

    /// Sign a simple message
    pub fn sign_message(&self, message: &str, keypair: &SecureKeypair) -> Result<SignedMessage> {
        let signature = self.verifier.sign(message.as_bytes(), keypair)?;
        let timestamp = chrono::Utc::now();

        Ok(SignedMessage {
            message: message.to_string(),
            signature,
            public_key: keypair.public_key(),
            timestamp,
            purpose: MessagePurpose::General,
        })
    }

    /// Sign a structured message
    pub fn sign_structured<T: Serialize>(
        &self,
        data: &T,
        keypair: &SecureKeypair,
        purpose: MessagePurpose,
    ) -> Result<SignedMessage> {
        let message = serde_json::to_string(data)?;
        let signature = self.verifier.sign(message.as_bytes(), keypair)?;
        let timestamp = chrono::Utc::now();

        Ok(SignedMessage {
            message,
            signature,
            public_key: keypair.public_key(),
            timestamp,
            purpose,
        })
    }

    /// Verify a signed message
    pub fn verify_message(&self, signed_msg: &SignedMessage) -> Result<bool> {
        self.verifier.verify(
            signed_msg.message.as_bytes(),
            &signed_msg.signature,
            &signed_msg.public_key,
        )
    }
}

/// Signed message structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedMessage {
    pub message: String,
    pub signature: Vec<u8>,
    pub public_key: Vec<u8>,
    pub timestamp: chrono::DateTime<chrono::Utc>,
    pub purpose: MessagePurpose,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessagePurpose {
    General,
    Authentication,
    DataAttestation,
    TradeConfirmation,
    RiskAssessment,
}

impl Default for SignatureVerifier {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

impl Default for MessageSigner {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::keypair::SecureKeypair;

    #[test]
    fn test_signature_creation_and_verification() {
        let verifier = SignatureVerifier::new().unwrap();
        let keypair = SecureKeypair::generate().unwrap();
        let message = b"test message";

        let signature = verifier.sign(message, &keypair).unwrap();
        let is_valid = verifier.verify(message, &signature, &keypair.public_key()).unwrap();

        assert!(is_valid);
    }

    #[test]
    fn test_message_signing_with_timestamp() {
        let verifier = SignatureVerifier::new().unwrap();
        let keypair = SecureKeypair::generate().unwrap();
        let timestamp = chrono::Utc::now();

        let signature = verifier.sign_message("test message", &keypair, Some(timestamp)).unwrap();
        let is_valid = verifier.verify_message_signature(
            "test message",
            &signature,
            &keypair.public_key(),
            timestamp,
            300, // 5 minutes
        ).unwrap();

        assert!(is_valid);
    }

    #[test]
    fn test_expired_signature() {
        let verifier = SignatureVerifier::new().unwrap();
        let keypair = SecureKeypair::generate().unwrap();
        let old_timestamp = chrono::Utc::now() - chrono::Duration::seconds(3600); // 1 hour ago

        let signature = verifier.sign_message("test message", &keypair, Some(old_timestamp)).unwrap();
        let is_valid = verifier.verify_message_signature(
            "test message",
            &signature,
            &keypair.public_key(),
            old_timestamp,
            300, // 5 minutes max age
        ).unwrap();

        assert!(!is_valid); // Should be invalid due to age
    }

    #[test]
    fn test_batch_verification() {
        let verifier = SignatureVerifier::new().unwrap();
        let keypair = SecureKeypair::generate().unwrap();

        let messages = vec![
            b"message1".as_slice(),
            b"message2".as_slice(),
            b"message3".as_slice(),
        ];

        let signatures: Vec<Vec<u8>> = messages.iter()
            .map(|msg| verifier.sign(msg, &keypair).unwrap())
            .collect();

        let public_keys: Vec<&[u8]> = vec![&keypair.public_key(); 3];

        let results = verifier.batch_verify(
            &messages.iter().map(|msg| msg.as_slice()).collect::<Vec<_>>(),
            &signatures.iter().map(|sig| sig.as_slice()).collect::<Vec<_>>(),
            &public_keys,
        ).unwrap();

        assert!(results.iter().all(|&valid| valid));
    }

    #[test]
    fn test_transaction_signature() {
        let verifier = SignatureVerifier::new().unwrap();
        let keypair = SecureKeypair::generate().unwrap();
        let message = b"transaction data";

        let metadata = SignatureMetadata {
            purpose: SignaturePurpose::Transaction,
            network: "mainnet".to_string(),
            fee_paid: Some(5000),
            slot: Some(123456),
        };

        let tx_sig = verifier.create_transaction_signature(message, &keypair, metadata).unwrap();

        assert_eq!(tx_sig.signature.len(), 64);
        assert_eq!(tx_sig.public_key, keypair.public_key());
        assert!(verifier.verify_transaction_signature(&tx_sig, message).unwrap());
    }

    #[test]
    fn test_message_signer() {
        let signer = MessageSigner::new().unwrap();
        let keypair = SecureKeypair::generate().unwrap();

        let signed = signer.sign_message("test message", &keypair).unwrap();
        let is_valid = signer.verify_message(&signed).unwrap();

        assert!(is_valid);
    }
}