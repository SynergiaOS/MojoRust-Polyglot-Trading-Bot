//! Encryption and decryption utilities for secure data storage
//!
//! Provides AES-GCM encryption for sensitive data like private keys,
//! API keys, and other configuration that needs to be stored securely.

use anyhow::{anyhow, Result};
use aes_gcm::{aead::Aead, AeadCore, Aes256Gcm, KeyInit, Nonce};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

/// Encryption utilities for secure data handling
pub struct DataEncryptor {
    cipher: Option<Aes256Gcm>,
}

impl DataEncryptor {
    /// Create a new encryptor
    pub fn new() -> Result<Self> {
        Ok(Self {
            cipher: None,
        })
    }

    /// Initialize encryptor with a key
    pub fn with_key(&self, key: &[u8]) -> Result<Self> {
        if key.len() != 32 {
            return Err(anyhow!("Key must be exactly 32 bytes for AES-256"));
        }

        let key_array: [u8; 32] = key.try_into()
            .map_err(|_| anyhow!("Failed to create key array"))?;

        let cipher = Aes256Gcm::new(&key_array.into());

        Ok(Self {
            cipher: Some(cipher),
        })
    }

    /// Generate a new encryption key
    pub fn generate_key(&self) -> Vec<u8> {
        use crate::crypto::random::SecureRandom;
        let mut rng = SecureRandom::new();
        rng.bytes(32)
    }

    /// Derive key from password using PBKDF2
    pub fn derive_key_from_password(&self, password: &str, salt: &[u8], iterations: u32) -> Vec<u8> {
        use pbkdf2::pbkdf2_hmac;
        use sha2::Sha256;

        let mut key = [0u8; 32];
        pbkdf2_hmac::<Sha256>(password.as_bytes(), salt, iterations, &mut key);
        key.to_vec()
    }

    /// Encrypt data
    pub fn encrypt(&self, data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        let cipher = self.cipher.as_ref()
            .ok_or_else(|| anyhow!("Encryptor not initialized with key"))?;

        // Generate random nonce
        let nonce = Aes256Gcm::generate_nonce(&mut rand::thread_rng());

        // Encrypt the data
        let ciphertext = cipher.encrypt(&nonce, data)
            .map_err(|e| anyhow!("Encryption failed: {}", e))?;

        // Combine nonce and ciphertext
        let mut result = nonce.to_vec();
        result.extend_from_slice(&ciphertext);

        Ok(result)
    }

    /// Decrypt data
    pub fn decrypt(&self, encrypted_data: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        let cipher = self.cipher.as_ref()
            .ok_or_else(|| anyhow!("Encryptor not initialized with key"))?;

        if encrypted_data.len() < 12 {
            return Err(anyhow!("Invalid encrypted data: too short"));
        }

        // Extract nonce and ciphertext
        let nonce = Nonce::from_slice(&encrypted_data[..12]);
        let ciphertext = &encrypted_data[12..];

        // Decrypt the data
        let plaintext = cipher.decrypt(nonce, ciphertext)
            .map_err(|e| anyhow!("Decryption failed: {}", e))?;

        Ok(plaintext)
    }

    /// Encrypt with additional authenticated data (AAD)
    pub fn encrypt_with_aad(&self, data: &[u8], aad: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        let cipher = self.cipher.as_ref()
            .ok_or_else(|| anyhow!("Encryptor not initialized with key"))?;

        let nonce = Aes256Gcm::generate_nonce(&mut rand::thread_rng());

        let ciphertext = cipher.encrypt(&nonce, aes_gcm::aead::Payload { msg: data, aad })
            .map_err(|e| anyhow!("Encryption with AAD failed: {}", e))?;

        let mut result = nonce.to_vec();
        result.extend_from_slice(&ciphertext);

        Ok(result)
    }

    /// Decrypt with additional authenticated data (AAD)
    pub fn decrypt_with_aad(&self, encrypted_data: &[u8], aad: &[u8], key: &[u8]) -> Result<Vec<u8>> {
        let cipher = self.cipher.as_ref()
            .ok_or_else(|| anyhow!("Encryptor not initialized with key"))?;

        if encrypted_data.len() < 12 {
            return Err(anyhow!("Invalid encrypted data: too short"));
        }

        let nonce = Nonce::from_slice(&encrypted_data[..12]);
        let ciphertext = &encrypted_data[12..];

        let plaintext = cipher.decrypt(nonce, aes_gcm::aead::Payload { msg: ciphertext, aad })
            .map_err(|e| anyhow!("Decryption with AAD failed: {}", e))?;

        Ok(plaintext)
    }

    /// Encrypt string
    pub fn encrypt_string(&self, plaintext: &str, key: &[u8]) -> Result<String> {
        let encrypted = self.encrypt(plaintext.as_bytes(), key)?;
        Ok(base64::encode(encrypted))
    }

    /// Decrypt string
    pub fn decrypt_string(&self, ciphertext: &str, key: &[u8]) -> Result<String> {
        let encrypted = base64::decode(ciphertext)?;
        let decrypted = self.decrypt(&encrypted, key)?;
        Ok(String::from_utf8(decrypted)?)
    }

    /// Encrypt JSON serializable data
    pub fn encrypt_json<T: Serialize>(&self, data: &T, key: &[u8]) -> Result<Vec<u8>> {
        let json = serde_json::to_vec(data)?;
        self.encrypt(&json, key)
    }

    /// Decrypt JSON data
    pub fn decrypt_json<T: for<'de> Deserialize<'de>>(&self, encrypted_data: &[u8], key: &[u8]) -> Result<T> {
        let json = self.decrypt(encrypted_data, key)?;
        let data: T = serde_json::from_slice(&json)?;
        Ok(data)
    }
}

impl Default for DataEncryptor {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

/// Secure storage for encrypted data
pub struct SecureStorage {
    encryptor: DataEncryptor,
    storage_path: Option<String>,
}

impl SecureStorage {
    /// Create new secure storage
    pub fn new() -> Result<Self> {
        Ok(Self {
            encryptor: DataEncryptor::new()?,
            storage_path: None,
        })
    }

    /// Set storage path
    pub fn set_storage_path<P: AsRef<Path>>(&mut self, path: P) {
        self.storage_path = Some(path.as_ref().to_string_lossy().to_string());
    }

    /// Initialize with password
    pub fn initialize_with_password(&mut self, password: &str, salt: Option<&[u8]>) -> Result<Vec<u8>> {
        let salt = salt.unwrap_or(b"default_salt_for_trading_bot");
        let key = self.encryptor.derive_key_from_password(password, salt, 100_000);
        self.encryptor = self.encryptor.with_key(&key)?;
        Ok(key)
    }

    /// Initialize with key
    pub fn initialize_with_key(&mut self, key: &[u8]) -> Result<()> {
        self.encryptor = self.encryptor.with_key(key)?;
        Ok(())
    }

    /// Store encrypted data
    pub fn store(&self, key: &str, data: &[u8]) -> Result<()> {
        let storage_path = self.storage_path.as_ref()
            .ok_or_else(|| anyhow!("Storage path not set"))?;

        // Create directory if it doesn't exist
        if let Some(parent) = Path::new(storage_path).parent() {
            fs::create_dir_all(parent)?;
        }

        let storage = EncryptedStorage::new(data);
        let encrypted = self.encryptor.encrypt_json(&storage, &self.get_key()?)?;
        fs::write(storage_path, encrypted)?;
        Ok(())
    }

    /// Retrieve encrypted data
    pub fn retrieve(&self, key: &str) -> Result<Vec<u8>> {
        let storage_path = self.storage_path.as_ref()
            .ok_or_else(|| anyhow!("Storage path not set"))?;

        if !Path::new(storage_path).exists() {
            return Err(anyhow!("Storage file not found"));
        }

        let encrypted = fs::read(storage_path)?;
        let storage: EncryptedStorage = self.encryptor.decrypt_json(&encrypted, &self.get_key()?)?;
        Ok(storage.data)
    }

    /// Store sensitive string
    pub fn store_string(&self, key: &str, value: &str) -> Result<()> {
        self.store(key, value.as_bytes())
    }

    /// Retrieve sensitive string
    pub fn retrieve_string(&self, key: &str) -> Result<String> {
        let data = self.retrieve(key)?;
        Ok(String::from_utf8(data)?)
    }

    /// Check if key exists
    pub fn contains(&self, key: &str) -> bool {
        let storage_path = match &self.storage_path {
            Some(path) => path,
            None => return false,
        };

        Path::new(storage_path).exists()
    }

    /// Delete stored data
    pub fn delete(&self, key: &str) -> Result<()> {
        let storage_path = self.storage_path.as_ref()
            .ok_or_else(|| anyhow!("Storage path not set"))?;

        if Path::new(storage_path).exists() {
            fs::remove_file(storage_path)?;
        }
        Ok(())
    }

    /// Clear all stored data
    pub fn clear(&self) -> Result<()> {
        if let Some(storage_path) = &self.storage_path {
            if Path::new(storage_path).exists() {
                fs::remove_file(storage_path)?;
            }
        }
        Ok(())
    }

    fn get_key(&self) -> Result<Vec<u8>> {
        // This should return the current encryption key
        // In a real implementation, you'd store this securely
        Err(anyhow!("Key management not implemented"))
    }
}

/// Encrypted storage format
#[derive(Debug, Clone, Serialize, Deserialize)]
struct EncryptedStorage {
    version: u8,
    created_at: chrono::DateTime<chrono::Utc>,
    data: Vec<u8>,
    metadata: StorageMetadata,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StorageMetadata {
    purpose: String,
    encrypted: bool,
    compression: bool,
}

impl EncryptedStorage {
    fn new(data: &[u8]) -> Self {
        Self {
            version: 1,
            created_at: chrono::Utc::now(),
            data: data.to_vec(),
            metadata: StorageMetadata {
                purpose: "secure_storage".to_string(),
                encrypted: true,
                compression: false,
            },
        }
    }
}

impl Default for SecureStorage {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

/// Key rotation manager
pub struct KeyRotationManager {
    current_key: Vec<u8>,
    previous_keys: Vec<(Vec<u8>, chrono::DateTime<chrono::Utc>)>,
    max_previous_keys: usize,
}

impl KeyRotationManager {
    /// Create new key rotation manager
    pub fn new(initial_key: Vec<u8>) -> Self {
        Self {
            current_key: initial_key,
            previous_keys: Vec::new(),
            max_previous_keys: 5,
        }
    }

    /// Rotate to a new key
    pub fn rotate_key(&mut self, new_key: Vec<u8>) {
        // Move current key to previous keys
        self.previous_keys.push((self.current_key.clone(), chrono::Utc::now()));

        // Keep only the most recent previous keys
        if self.previous_keys.len() > self.max_previous_keys {
            self.previous_keys.remove(0);
        }

        self.current_key = new_key;
    }

    /// Get current key
    pub fn current_key(&self) -> &[u8] {
        &self.current_key
    }

    /// Get key for decryption (tries current then previous)
    pub fn get_decryption_key(&self, timestamp: chrono::DateTime<chrono::Utc>) -> Option<&[u8]> {
        // If timestamp is recent, try current key first
        let recent_threshold = chrono::Utc::now() - chrono::Duration::hours(1);

        if timestamp > recent_threshold {
            return Some(&self.current_key);
        }

        // Try previous keys in reverse order (most recent first)
        for (key, key_timestamp) in self.previous_keys.iter().rev() {
            if timestamp > *key_timestamp {
                return Some(key);
            }
        }

        // Fallback to current key
        Some(&self.current_key)
    }

    /// Remove old keys
    pub fn cleanup_old_keys(&mut self, max_age_days: i64) {
        let cutoff = chrono::Utc::now() - chrono::Duration::days(max_age_days);
        self.previous_keys.retain(|(_, timestamp)| *timestamp > cutoff);
    }

    /// Get number of keys being managed
    pub fn key_count(&self) -> usize {
        1 + self.previous_keys.len()
    }
}

/// Password strength validator
pub struct PasswordValidator;

impl PasswordValidator {
    /// Validate password strength
    pub fn validate_strength(password: &str) -> PasswordStrength {
        let mut score = 0;
        let mut issues = Vec::new();

        // Length check
        if password.len() < 8 {
            issues.push("Password too short (minimum 8 characters)".to_string());
        } else if password.len() >= 12 {
            score += 2;
        } else {
            score += 1;
        }

        // Character variety checks
        if password.chars().any(|c| c.is_uppercase()) {
            score += 1;
        } else {
            issues.push("No uppercase letters".to_string());
        }

        if password.chars().any(|c| c.is_lowercase()) {
            score += 1;
        } else {
            issues.push("No lowercase letters".to_string());
        }

        if password.chars().any(|c| c.is_numeric()) {
            score += 1;
        } else {
            issues.push("No numbers".to_string());
        }

        if password.chars().any(|c| !c.is_alphanumeric()) {
            score += 1;
        } else {
            issues.push("No special characters".to_string());
        }

        // Common patterns check
        if Self::has_common_patterns(password) {
            score -= 2;
            issues.push("Contains common patterns".to_string());
        }

        let strength = match score {
            0..=2 => PasswordStrength::Weak,
            3..=4 => PasswordStrength::Medium,
            5..=6 => PasswordStrength::Strong,
            _ => PasswordStrength::VeryStrong,
        };

        PasswordStrength {
            strength,
            score,
            issues,
        }
    }

    fn has_common_patterns(password: &str) -> bool {
        let common_patterns = vec![
            "123456", "password", "qwerty", "abc123", "letmein",
            "admin", "welcome", "monkey", "dragon", "master",
        ];

        let lowercase = password.to_lowercase();
        common_patterns.iter().any(|pattern| lowercase.contains(pattern))
    }

    /// Generate strong password suggestion
    pub fn generate_strong_password(length: usize) -> String {
        use crate::crypto::random::SecureRandom;
        let mut rng = SecureRandom::new();

        const LOWERCASE: &str = "abcdefghijklmnopqrstuvwxyz";
        const UPPERCASE: &str = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const NUMBERS: &str = "0123456789";
        const SPECIAL: &str = "!@#$%^&*()_+-=[]{}|;:,.<>?";

        let all_chars = format!("{}{}{}{}", LOWERCASE, UPPERCASE, NUMBERS, SPECIAL);

        let mut password = String::new();

        // Ensure at least one character from each category
        password.push(rng.choice(LOWCASE.chars().collect::<Vec<_>>().as_slice()).unwrap());
        password.push(rng.choice(UPPERCASE.chars().collect::<Vec<_>>().as_slice()).unwrap());
        password.push(rng.choice(NUMBERS.chars().collect::<Vec<_>>().as_slice()).unwrap());
        password.push(rng.choice(SPECIAL.chars().collect::<Vec<_>>().as_slice()).unwrap());

        // Fill the rest randomly
        for _ in 4..length {
            password.push(rng.choice(all_chars.chars().collect::<Vec<_>>().as_slice()).unwrap());
        }

        // Shuffle the password
        let mut chars: Vec<char> = password.chars().collect();
        rng.shuffle(&mut chars);
        chars.into_iter().collect()
    }
}

/// Password strength result
#[derive(Debug, Clone)]
pub struct PasswordStrength {
    pub strength: StrengthLevel,
    pub score: i32,
    pub issues: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StrengthLevel {
    Weak,
    Medium,
    Strong,
    VeryStrong,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encryption_decryption() {
        let encryptor = DataEncryptor::new().unwrap();
        let key = encryptor.generate_key();
        let initialized = encryptor.with_key(&key).unwrap();

        let data = b"sensitive trading data";
        let encrypted = initialized.encrypt(data, &key).unwrap();
        let decrypted = initialized.decrypt(&encrypted, &key).unwrap();

        assert_eq!(data.to_vec(), decrypted);
        assert_ne!(encrypted, data.to_vec());
    }

    #[test]
    fn test_string_encryption() {
        let encryptor = DataEncryptor::new().unwrap();
        let key = encryptor.generate_key();
        let initialized = encryptor.with_key(&key).unwrap();

        let plaintext = "API_KEY_SECRET_123";
        let encrypted = initialized.encrypt_string(plaintext, &key).unwrap();
        let decrypted = initialized.decrypt_string(&encrypted, &key).unwrap();

        assert_eq!(plaintext, decrypted);
    }

    #[test]
    fn test_json_encryption() {
        use serde_json::json;

        let encryptor = DataEncryptor::new().unwrap();
        let key = encryptor.generate_key();
        let initialized = encryptor.with_key(&key).unwrap();

        let data = json!({
            "api_key": "test_key",
            "secret": "test_secret",
            "expires": 1234567890
        });

        let encrypted = initialized.encrypt_json(&data, &key).unwrap();
        let decrypted: serde_json::Value = initialized.decrypt_json(&encrypted, &key).unwrap();

        assert_eq!(data, decrypted);
    }

    #[test]
    fn test_key_derivation() {
        let encryptor = DataEncryptor::new().unwrap();
        let password = "strong_password_123";
        let salt = b"unique_salt_value";

        let key1 = encryptor.derive_key_from_password(password, salt, 100_000);
        let key2 = encryptor.derive_key_from_password(password, salt, 100_000);

        assert_eq!(key1, key2);

        let key3 = encryptor.derive_key_from_password(password, b"different_salt", 100_000);
        assert_ne!(key1, key3);
    }

    #[test]
    fn test_key_rotation() {
        let initial_key = vec![0u8; 32];
        let mut manager = KeyRotationManager::new(initial_key);

        let new_key = vec![1u8; 32];
        manager.rotate_key(new_key);

        assert_eq!(manager.current_key(), &[1u8; 32]);
        assert_eq!(manager.key_count(), 2);
    }

    #[test]
    fn test_password_validation() {
        let weak_password = "123";
        let strength = PasswordValidator::validate_strength(weak_password);
        assert!(matches!(strength.strength, StrengthLevel::Weak));
        assert!(!strength.issues.is_empty());

        let strong_password = PasswordValidator::generate_strong_password(16);
        let strength = PasswordValidator::validate_strength(&strong_password);
        assert!(matches!(strength.strength, StrengthLevel::Strong | StrengthLevel::VeryStrong));
        assert_eq!(strong_password.len(), 16);
    }

    #[test]
    fn test_encryption_with_aad() {
        let encryptor = DataEncryptor::new().unwrap();
        let key = encryptor.generate_key();
        let initialized = encryptor.with_key(&key).unwrap();

        let data = b"secret data";
        let aad = b"additional authenticated data";

        let encrypted = initialized.encrypt_with_aad(data, aad, &key).unwrap();
        let decrypted = initialized.decrypt_with_aad(&encrypted, aad, &key).unwrap();

        assert_eq!(data.to_vec(), decrypted);

        // Wrong AAD should fail decryption
        assert!(initialized.decrypt_with_aad(&encrypted, b"wrong aad", &key).is_err());
    }

    #[test]
    fn test_invalid_decryption() {
        let encryptor = DataEncryptor::new().unwrap();
        let key = encryptor.generate_key();
        let initialized = encryptor.with_key(&key).unwrap();

        // Try to decrypt invalid data
        let invalid_data = vec![0u8; 10];
        assert!(initialized.decrypt(&invalid_data, &key).is_err());

        // Try to decrypt with wrong key
        let data = b"test data";
        let encrypted = initialized.encrypt(data, &key).unwrap();
        let wrong_key = vec![1u8; 32];
        assert!(initialized.decrypt(&encrypted, &wrong_key).is_err());
    }
}