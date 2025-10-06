//! Integration tests for Mojo Trading Bot Rust modules
//!
//! These tests verify the integration between different modules and ensure
//! the entire system works correctly together.

use mojo_trading_bot::*;
use std::time::Duration;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_full_integration() {
        // Initialize the library
        initialize().expect("Failed to initialize library");

        // Create configuration
        let config = TradingBotConfig {
            security_level: SecurityLevel::High,
            enable_logging: true,
            enable_audit: true,
            enable_monitoring: true,
            rpc_url: "https://api.mainnet-beta.solana.com".to_string(),
            ws_url: None,
            max_concurrent_requests: 5,
            request_timeout_ms: 10_000,
        };

        // Note: This test requires network access and may be flaky in CI
        // let bot = TradingBot::new(config);
        // assert!(bot.is_ok());

        cleanup();
    }

    #[test]
    fn test_crypto_security_integration() {
        initialize().expect("Failed to initialize library");

        // Create engines
        let crypto_engine = CryptoEngine::new().expect("Failed to create crypto engine");
        let security_engine = SecurityEngine::new().expect("Failed to create security engine");

        // Generate keypair
        let keypair = crypto_engine.generate_keypair().expect("Failed to generate keypair");

        // Sign a message
        let message = b"test message for integration";
        let signature = crypto_engine.sign_message(message).expect("Failed to sign message");

        // Verify signature
        let is_valid = crypto_engine
            .verify_signature(message, &signature, &keypair.public_key())
            .expect("Failed to verify signature");
        assert!(is_valid);

        // Test security validation
        let result = security_engine.check_request(
            "test_client",
            "/api/verify",
            message,
        );
        assert!(result.is_ok());

        cleanup();
    }

    #[test]
    fn test_encryption_decryption_cycle() {
        let encryptor = crypto::encryption::DataEncryptor::new().expect("Failed to create encryptor");
        let key = encryptor.generate_key();
        let initialized = encryptor.with_key(&key).expect("Failed to initialize encryptor");

        let data = b"sensitive trading data that needs encryption";

        // Encrypt data
        let encrypted = initialized.encrypt(data, &key).expect("Failed to encrypt data");

        // Ensure encrypted data is different from original
        assert_ne!(encrypted, data.to_vec());

        // Decrypt data
        let decrypted = initialized.decrypt(&encrypted, &key).expect("Failed to decrypt data");

        // Ensure decrypted data matches original
        assert_eq!(decrypted, data.to_vec());
    }

    #[test]
    fn test_rate_limiting() {
        let mut rate_limiter = security::rate_limiting::RateLimiter::new().expect("Failed to create rate limiter");

        // Add a rate limit: 5 requests per second
        rate_limiter.add_limit(
            "test_endpoint",
            security::rate_limiting::RateLimitStrategy::TokenBucket,
            5,
            Duration::from_secs(1),
        );

        // Should allow first 5 requests
        for i in 0..5 {
            assert!(
                rate_limiter.check_limit("test_endpoint", &format!("client_{}", i)).unwrap(),
                "Request {} should be allowed",
                i
            );
        }

        // 6th request should be rate limited
        assert!(
            !rate_limiter
                .check_limit("test_endpoint", "client_6")
                .unwrap(),
            "6th request should be rate limited"
        );
    }

    #[test]
    fn test_input_validation() {
        let mut validator = security::input_validation::InputValidator::new();

        // Add validation rules
        validator.add_rules("trading_endpoint", vec![
            security::input_validation::ValidationRule::NoEmpty,
            security::input_validation::ValidationRule::MinLength(3),
            security::input_validation::ValidationRule::MaxLength(100),
            security::input_validation::ValidationRule::NoSqlInjection,
            security::input_validation::ValidationRule::NoXss,
        ]);

        // Valid input should pass
        let valid_input = b"valid trading signal data";
        assert!(validator.validate(valid_input, "trading_endpoint").is_ok());

        // Invalid inputs should fail
        let empty_input = b"";
        assert!(validator.validate(empty_input, "trading_endpoint").is_err());

        let sql_injection = b"'; DROP TABLE users; --";
        assert!(validator.validate(sql_injection, "trading_endpoint").is_err());

        let xss_attack = b"<script>alert('xss')</script>";
        assert!(validator.validate(xss_attack, "trading_endpoint").is_err());
    }

    #[test]
    fn test_merkle_tree_verification() {
        let data_items = vec![
            b"transaction_1".to_vec(),
            b"transaction_2".to_vec(),
            b"transaction_3".to_vec(),
            b"transaction_4".to_vec(),
        ];

        // Create Merkle tree
        let tree = crypto::hash::MerkleTree::build(&data_items);

        // Generate proof for first item
        let proof = tree.generate_proof(0).expect("Failed to generate proof");

        // Verify proof
        assert!(tree.verify_proof(&proof));

        // Verify proof with different data should fail
        let mut fake_data = data_items[0].clone();
        fake_data[0] = fake_data[0].wrapping_add(1); // Modify one byte
        let fake_tree = crypto::hash::MerkleTree::build(&vec![fake_data]);

        let fake_proof = fake_tree.generate_proof(0).expect("Failed to generate fake proof");
        assert!(!tree.verify_proof(&fake_proof));
    }

    #[test]
    fn test_keypair_serialization() {
        let mut manager = crypto::keypair::KeypairManager::new().expect("Failed to create keypair manager");

        // Generate keypair
        let keypair = manager.generate().expect("Failed to generate keypair");

        // Serialize to bytes
        let bytes = keypair.to_bytes();
        assert_eq!(bytes.len(), 64);

        // Deserialize from bytes
        let restored = crypto::keypair::SecureKeypair::from_bytes(&bytes).expect("Failed to restore keypair");

        // Verify they're the same
        assert_eq!(keypair.public_key(), restored.public_key());
        assert_eq!(keypair.private_key(), restored.private_key());

        // Test signing works the same
        let message = b"test message";
        let sig1 = keypair.sign(message);
        let sig2 = restored.sign(message);

        assert_eq!(sig1, sig2);
    }

    #[test]
    fn test_random_generation_quality() {
        use crypto::random::{SecureRandom, EntropyCalculator};

        let mut rng = SecureRandom::new();

        // Generate random data
        let data1 = rng.bytes(1024);
        let data2 = rng.bytes(1024);

        // Ensure they're different
        assert_ne!(data1, data2);

        // Check entropy quality
        let entropy1 = EntropyCalculator::shannon_entropy(&data1);
        let entropy2 = EntropyCalculator::shannon_entropy(&data2);

        // Should have high entropy (close to 8.0 for random data)
        assert!(entropy1 > 7.0, "Low entropy detected: {}", entropy1);
        assert!(entropy2 > 7.0, "Low entropy detected: {}", entropy2);

        // Check for patterns
        let patterns1 = EntropyCalculator::detect_patterns(&data1);
        let patterns2 = EntropyCalculator::detect_patterns(&data2);

        assert!(patterns1.is_empty(), "Patterns detected in random data: {:?}", patterns1);
        assert!(patterns2.is_empty(), "Patterns detected in random data: {:?}", patterns2);
    }

    #[test]
    fn test_memory_safety() {
        use crypto::keypair::SecureKeypair;

        // Test that sensitive data is properly handled
        let keypair = SecureKeypair::generate().expect("Failed to generate keypair");

        // Clone keypair (should create independent copy)
        let keypair_clone = keypair.clone();

        // Verify they have the same keys
        assert_eq!(keypair.public_key(), keypair_clone.public_key());
        assert_eq!(keypair.private_key(), keypair_clone.private_key());

        // Drop original
        drop(keypair);

        // Clone should still be valid
        let message = b"test message after drop";
        let signature = keypair_clone.sign(message);
        assert_eq!(signature.len(), 64);
    }

    #[test]
    fn test_error_handling() {
        // Test various error conditions are handled properly

        // Invalid keypair bytes
        let result = crypto::keypair::SecureKeypair::from_bytes(&[0u8; 10]);
        assert!(result.is_err());

        // Invalid signature verification
        let encryptor = crypto::encryption::DataEncryptor::new().unwrap();
        let result = encryptor.encrypt(b"data", b"short_key");
        assert!(result.is_err());

        // Invalid input validation
        let validator = security::input_validation::InputValidator::new();
        let result = validator.validate(b"", "nonexistent_endpoint");
        assert!(result.is_err());

        // Invalid Solana address
        assert!(!solana::utils::SolanaUtils::is_valid_address("invalid_address"));
        assert!(!solana::utils::SolanaUtils::is_valid_address(""));
    }

    #[test]
    fn test_concurrent_access() {
        use std::sync::Arc;
        use std::thread;

        let crypto_engine = Arc::new(CryptoEngine::new().expect("Failed to create crypto engine"));
        let security_engine = Arc::new(SecurityEngine::new().expect("Failed to create security engine"));

        let mut handles = vec![];

        // Spawn multiple threads to test concurrent access
        for i in 0..10 {
            let crypto = crypto_engine.clone();
            let security = security_engine.clone();

            let handle = thread::spawn(move || {
                // Generate keypair in thread
                let keypair = crypto.generate_keypair().expect("Failed to generate keypair");

                // Sign message
                let message = format!("test message from thread {}", i);
                let signature = crypto
                    .sign_message(message.as_bytes())
                    .expect("Failed to sign message");

                // Verify signature
                let is_valid = crypto
                    .verify_signature(message.as_bytes(), &signature, &keypair.public_key())
                    .expect("Failed to verify signature");
                assert!(is_valid);

                // Test security check
                let result = security.check_request(
                    &format!("client_{}", i),
                    "/api/test",
                    message.as_bytes(),
                );
                assert!(result.is_ok());
            });

            handles.push(handle);
        }

        // Wait for all threads to complete
        for handle in handles {
            handle.join().expect("Thread panicked");
        }
    }

    #[test]
    fn test_performance_benchmarks() {
        use std::time::Instant;

        let crypto_engine = CryptoEngine::new().expect("Failed to create crypto engine");

        // Benchmark keypair generation
        let start = Instant::now();
        for _ in 0..100 {
            crypto_engine.generate_keypair().expect("Failed to generate keypair");
        }
        let keypair_duration = start.elapsed();

        println!("Generated 100 keypairs in {:?}", keypair_duration);
        assert!(keypair_duration.as_millis() < 1000, "Keypair generation too slow");

        // Benchmark message signing
        let keypair = crypto_engine.generate_keypair().expect("Failed to generate keypair");
        let message = b"benchmark message for signing performance test";

        let start = Instant::now();
        for _ in 0..1000 {
            crypto_engine
                .sign_message(message)
                .expect("Failed to sign message");
        }
        let signing_duration = start.elapsed();

        println!("Signed 1000 messages in {:?}", signing_duration);
        assert!(signing_duration.as_millis() < 500, "Message signing too slow");

        // Benchmark signature verification
        let signature = crypto_engine
            .sign_message(message)
            .expect("Failed to sign message");

        let start = Instant::now();
        for _ in 0..1000 {
            crypto_engine
                .verify_signature(message, &signature, &keypair.public_key())
                .expect("Failed to verify signature");
        }
        let verification_duration = start.elapsed();

        println!("Verified 1000 signatures in {:?}", verification_duration);
        assert!(verification_duration.as_millis() < 200, "Signature verification too slow");
    }
}