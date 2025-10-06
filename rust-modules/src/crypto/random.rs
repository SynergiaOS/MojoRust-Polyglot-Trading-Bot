//! Secure random number generation
//!
//! Provides cryptographically secure random number generation
//! for key generation, nonce creation, and other security-critical operations.

use anyhow::{anyhow, Result};
use ed25519_dalek::rand::{rngs::OsRng, CryptoRng, RngCore};
use rand::{thread_rng, Rng};
use std::collections::HashMap;

/// Secure random number generator
pub struct SecureRandom {
    rng: OsRng,
}

impl SecureRandom {
    /// Create a new secure random generator
    pub fn new() -> Self {
        Self {
            rng: OsRng,
        }
    }

    /// Generate random bytes
    pub fn bytes(&mut self, len: usize) -> Vec<u8> {
        let mut bytes = vec![0u8; len];
        self.rng.fill_bytes(&mut bytes);
        bytes
    }

    /// Generate random u32
    pub fn u32(&mut self) -> u32 {
        self.rng.next_u32()
    }

    /// Generate random u64
    pub fn u64(&mut self) -> u64 {
        self.rng.next_u64()
    }

    /// Generate random number in range
    pub fn range(&mut self, min: u64, max: u64) -> Result<u64> {
        if min >= max {
            return Err(anyhow!("Invalid range: min must be less than max"));
        }
        Ok(min + (self.u64() % (max - min)))
    }

    /// Generate random f32 between 0.0 and 1.0
    pub fn f32(&mut self) -> f32 {
        thread_rng().gen::<f32>()
    }

    /// Generate random f64 between 0.0 and 1.0
    pub fn f64(&mut self) -> f64 {
        thread_rng().gen::<f64>()
    }

    /// Generate random boolean
    pub fn bool(&mut self) -> bool {
        self.u32() % 2 == 1
    }

    /// Generate random choice from slice
    pub fn choice<'a, T>(&mut self, slice: &'a [T]) -> Result<&'a T> {
        if slice.is_empty() {
            return Err(anyhow!("Cannot choose from empty slice"));
        }

        let index = self.range(0, slice.len() as u64)? as usize;
        Ok(&slice[index])
    }

    /// Shuffle a slice in place
    pub fn shuffle<T>(&mut self, slice: &mut [T]) {
        use rand::seq::SliceRandom;
        slice.shuffle(&mut self.rng);
    }

    /// Generate random alphanumeric string
    pub fn alphanumeric(&mut self, len: usize) -> String {
        const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ\
                                abcdefghijklmnopqrstuvwxyz\
                                0123456789";

        let mut result = String::with_capacity(len);
        for _ in 0..len {
            let index = self.range(0, CHARSET.len() as u64)? as usize;
            result.push(CHARSET[index] as char);
        }
        result
    }

    /// Generate random hexadecimal string
    pub fn hex(&mut self, len: usize) -> String {
        const CHARSET: &[u8] = b"0123456789abcdef";

        let mut result = String::with_capacity(len);
        for _ in 0..len {
            let index = self.range(0, CHARSET.len() as u64)? as usize;
            result.push(CHARSET[index] as char);
        }
        result
    }

    /// Generate random base58 string
    pub fn base58(&mut self, len: usize) -> String {
        const CHARSET: &[u8] = b"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

        let mut result = String::with_capacity(len);
        for _ in 0..len {
            let index = self.range(0, CHARSET.len() as u64)? as usize;
            result.push(CHARSET[index] as char);
        }
        result
    }

    /// Generate random UUID
    pub fn uuid(&mut self) -> String {
        let bytes = self.bytes(16);
        format!(
            "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }

    /// Generate random nonce
    pub fn nonce(&mut self, len: usize) -> Vec<u8> {
        self.bytes(len)
    }

    /// Generate random seed for key derivation
    pub fn seed(&mut self, len: usize) -> Vec<u8> {
        self.bytes(len)
    }

    /// Generate random timestamp (recent past or near future)
    pub fn timestamp(&mut self, offset_seconds: u64) -> chrono::DateTime<chrono::Utc> {
        let now = chrono::Utc::now();
        let offset = chrono::Duration::seconds(self.range(0, offset_seconds * 2)? as i64 - offset_seconds as i64);
        now + offset
    }

    /// Generate random IP address (for testing)
    pub fn ip_address(&mut self) -> String {
        format!(
            "{}.{}.{}.{}",
            self.range(1, 255)?,
            self.range(0, 256)?,
            self.range(0, 256)?,
            self.range(1, 255)?
        )
    }

    /// Generate random port number
    pub fn port(&mut self) -> u16 {
        self.range(1024, 65535).unwrap() as u16
    }

    /// Generate random delay in milliseconds
    pub fn delay_ms(&mut self, min_ms: u64, max_ms: u64) -> std::time::Duration {
        let delay = self.range(min_ms, max_ms).unwrap();
        std::time::Duration::from_millis(delay)
    }
}

impl Default for SecureRandom {
    fn default() -> Self {
        Self::new()
    }
}

impl RngCore for SecureRandom {
    fn next_u32(&mut self) -> u32 {
        self.u32()
    }

    fn next_u64(&mut self) -> u64 {
        self.u64()
    }

    fn fill_bytes(&mut self, dest: &mut [u8]) {
        for byte in dest.iter_mut() {
            *byte = self.u32() as u8;
        }
    }

    fn try_fill_bytes(&mut self, dest: &mut [u8]) -> Result<(), rand::Error> {
        self.fill_bytes(dest);
        Ok(())
    }
}

impl CryptoRng for SecureRandom {}

/// Random string generator with different character sets
pub struct RandomStringGenerator {
    rng: SecureRandom,
}

impl RandomStringGenerator {
    /// Create new random string generator
    pub fn new() -> Self {
        Self {
            rng: SecureRandom::new(),
        }
    }

    /// Generate random string with custom character set
    pub fn generate(&mut self, len: usize, charset: &str) -> String {
        let mut result = String::with_capacity(len);
        let chars: Vec<char> = charset.chars().collect();

        for _ in 0..len {
            let index = self.rng.range(0, chars.len() as u64).unwrap() as usize;
            result.push(chars[index]);
        }
        result
    }

    /// Generate random lowercase string
    pub fn lowercase(&mut self, len: usize) -> String {
        self.generate(len, "abcdefghijklmnopqrstuvwxyz")
    }

    /// Generate random uppercase string
    pub fn uppercase(&mut self, len: usize) -> String {
        self.generate(len, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    }

    /// Generate random mixed case string
    pub fn mixed_case(&mut self, len: usize) -> String {
        self.generate(len, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    }

    /// Generate random numeric string
    pub fn numeric(&mut self, len: usize) -> String {
        self.generate(len, "0123456789")
    }

    /// Generate random alphanumeric string
    pub fn alphanumeric(&mut self, len: usize) -> String {
        self.generate(len, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    }

    /// Generate random memorable string (pronounceable)
    pub fn memorable(&mut self, syllables: usize) -> String {
        const CONSONANTS: &str = "bcdfghjklmnpqrstvwxyz";
        const VOWELS: &str = "aeiou";

        let mut result = String::new();

        for i in 0..syllables {
            if i > 0 {
                result.push('-'); // Separator between syllables
            }

            // Generate consonant-vowel-consonant pattern
            result.push(self.generate(1, CONSONANTS).chars().next().unwrap());
            result.push(self.generate(1, VOWELS).chars().next().unwrap());
            if self.rng.bool() {
                result.push(self.generate(1, CONSONANTS).chars().next().unwrap());
            }
        }

        result
    }
}

impl Default for RandomStringGenerator {
    fn default() -> Self {
        Self::new()
    }
}

/// Entropy calculator for randomness quality assessment
pub struct EntropyCalculator;

impl EntropyCalculator {
    /// Calculate Shannon entropy of data
    pub fn shannon_entropy(data: &[u8]) -> f64 {
        if data.is_empty() {
            return 0.0;
        }

        let mut frequency = HashMap::new();
        let len = data.len() as f64;

        // Count frequency of each byte
        for &byte in data {
            *frequency.entry(byte).or_insert(0) += 1;
        }

        // Calculate entropy
        let mut entropy = 0.0;
        for &count in frequency.values() {
            let probability = count as f64 / len;
            if probability > 0.0 {
                entropy -= probability * probability.log2();
            }
        }

        entropy
    }

    /// Calculate min-entropy
    pub fn min_entropy(data: &[u8]) -> f64 {
        if data.is_empty() {
            return 0.0;
        }

        let mut frequency = HashMap::new();
        let len = data.len();

        // Count frequency of each byte
        for &byte in data {
            *frequency.entry(byte).or_insert(0) += 1;
        }

        // Find maximum frequency
        let max_count = *frequency.values().max().unwrap() as f64;
        let len = len as f64;

        -(max_count / len).log2()
    }

    /// Estimate entropy bits per byte
    pub fn bits_per_byte(data: &[u8]) -> f64 {
        Self::shannon_entropy(data)
    }

    /// Test randomness quality (0.0 to 1.0, higher is better)
    pub fn randomness_quality(data: &[u8]) -> f64 {
        if data.is_empty() {
            return 0.0;
        }

        let entropy = Self::shannon_entropy(data);
        let max_entropy = 8.0; // Maximum entropy for bytes

        entropy / max_entropy
    }

    /// Detect patterns in random data
    pub fn detect_patterns(data: &[u8]) -> Vec<String> {
        let mut patterns = Vec::new();

        // Check for repeated bytes
        if Self::has_repeated_bytes(data, 10) {
            patterns.push("Repeated bytes detected".to_string());
        }

        // Check for sequences
        if Self::has_sequences(data, 5) {
            patterns.push("Sequential patterns detected".to_string());
        }

        // Check for low entropy
        let entropy = Self::shannon_entropy(data);
        if entropy < 4.0 {
            patterns.push("Low entropy detected".to_string());
        }

        patterns
    }

    fn has_repeated_bytes(data: &[u8], threshold: usize) -> bool {
        let mut count = HashMap::new();

        for &byte in data {
            *count.entry(byte).or_insert(0) += 1;
            if count[&byte] > threshold {
                return true;
            }
        }

        false
    }

    fn has_sequences(data: &[u8], length: usize) -> bool {
        if data.len() < length {
            return false;
        }

        for i in 0..=data.len() - length {
            let mut is_sequence = true;
            let mut is_reverse_sequence = true;

            for j in 1..length {
                if data[i + j] != data[i + j - 1] + 1 {
                    is_sequence = false;
                }
                if data[i + j] != data[i + j - 1] - 1 {
                    is_reverse_sequence = false;
                }
            }

            if is_sequence || is_reverse_sequence {
                return true;
            }
        }

        false
    }
}

/// Random delay generator for rate limiting and jitter
pub struct RandomDelay {
    rng: SecureRandom,
}

impl RandomDelay {
    /// Create new random delay generator
    pub fn new() -> Self {
        Self {
            rng: SecureRandom::new(),
        }
    }

    /// Generate random delay
    pub fn delay(&mut self, min_ms: u64, max_ms: u64) -> std::time::Duration {
        self.rng.delay_ms(min_ms, max_ms)
    }

    /// Generate exponential backoff delay
    pub fn exponential_backoff(&mut self, attempt: u32, base_ms: u64, max_ms: u64) -> std::time::Duration {
        let delay_ms = (base_ms * 2_u64.pow(attempt)).min(max_ms);
        let jitter_ms = self.rng.range(0, delay_ms / 4).unwrap();
        std::time::Duration::from_millis(delay_ms + jitter_ms)
    }

    /// Generate jitter for timing attacks prevention
    pub fn jitter(&mut self, base_ms: u64, jitter_percent: u8) -> std::time::Duration {
        let jitter_range = base_ms * jitter_percent as u64 / 100;
        let jitter = self.rng.range(0, jitter_range * 2).unwrap();
        let adjustment = jitter as i64 - jitter_range as i64;
        let final_delay = (base_ms as i64 + adjustment).max(0) as u64;
        std::time::Duration::from_millis(final_delay)
    }
}

impl Default for RandomDelay {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_secure_random_generation() {
        let mut rng = SecureRandom::new();

        let bytes1 = rng.bytes(32);
        let bytes2 = rng.bytes(32);

        assert_eq!(bytes1.len(), 32);
        assert_eq!(bytes2.len(), 32);
        assert_ne!(bytes1, bytes2);
    }

    #[test]
    fn test_random_range() {
        let mut rng = SecureRandom::new();

        for _ in 0..100 {
            let num = rng.range(10, 20).unwrap();
            assert!(num >= 10 && num < 20);
        }
    }

    #[test]
    fn test_random_choice() {
        let mut rng = SecureRandom::new();
        let items = vec!["a", "b", "c", "d", "e"];

        let choice = rng.choice(&items).unwrap();
        assert!(items.contains(&choice));
    }

    #[test]
    fn test_random_string_generation() {
        let mut rng = SecureRandom::new();

        let alphanumeric = rng.alphanumeric(10);
        assert_eq!(alphanumeric.len(), 10);
        assert!(alphanumeric.chars().all(|c| c.is_alphanumeric()));

        let hex_string = rng.hex(16);
        assert_eq!(hex_string.len(), 16);
        assert!(hex_string.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_uuid_generation() {
        let mut rng = SecureRandom::new();

        let uuid1 = rng.uuid();
        let uuid2 = rng.uuid();

        assert_eq!(uuid1.len(), 36); // Standard UUID format
        assert_eq!(uuid2.len(), 36);
        assert_ne!(uuid1, uuid2);
    }

    #[test]
    fn test_entropy_calculation() {
        // Perfect entropy data
        let mut rng = SecureRandom::new();
        let random_data = rng.bytes(1024);
        let entropy = EntropyCalculator::shannon_entropy(&random_data);
        assert!(entropy > 7.0); // Should be close to 8.0

        // Low entropy data
        let low_entropy_data = vec![0u8; 1024];
        let entropy = EntropyCalculator::shannon_entropy(&low_entropy_data);
        assert_eq!(entropy, 0.0);
    }

    #[test]
    fn test_pattern_detection() {
        let mut rng = SecureRandom::new();
        let random_data = rng.bytes(100);
        let patterns = EntropyCalculator::detect_patterns(&random_data);
        assert!(patterns.is_empty());

        // Data with repeated bytes
        let repeated_data = vec![42u8; 50];
        let patterns = EntropyCalculator::detect_patterns(&repeated_data);
        assert!(!patterns.is_empty());
    }

    #[test]
    fn test_random_delay() {
        let mut delay = RandomDelay::new();

        let d1 = delay.delay(100, 200);
        let d2 = delay.delay(100, 200);

        assert!(d1.as_millis() >= 100 && d1.as_millis() < 200);
        assert!(d2.as_millis() >= 100 && d2.as_millis() < 200);
    }

    #[test]
    fn test_exponential_backoff() {
        let mut delay = RandomDelay::new();

        let d1 = delay.exponential_backoff(0, 100, 1000);
        let d2 = delay.exponential_backoff(1, 100, 1000);
        let d3 = delay.exponential_backoff(2, 100, 1000);

        assert!(d2.as_millis() > d1.as_millis());
        assert!(d3.as_millis() > d2.as_millis());
    }

    #[test]
    fn test_memorable_string_generation() {
        let mut gen = RandomStringGenerator::new();

        let memorable = gen.memorable(4);
        assert!(memorable.contains('-'));
        assert!(memorable.chars().all(|c| c.is_alphabetic() || c == '-'));
    }
}