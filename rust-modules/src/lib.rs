//! Mojo Trading Bot Rust Security Modules
//!
//! This crate provides comprehensive security and cryptographic utilities
//! for the high-performance algorithmic trading bot.
//!
//! ## Features
//!
//! - **Cryptography**: Keypair management, digital signatures, encryption
//! - **Security**: Rate limiting, input validation, audit logging
//! - **Solana Integration**: Transaction building, account management
//! - **FFI Interface**: Safe bindings for Mojo integration
//!
//! ## Architecture
//!
//! The module is organized into several key components:
//!
//! - [`crypto`]: Core cryptographic utilities
//! - [`security`]: Security protection and monitoring
//! - [`solana`]: Solana blockchain integration
//! - [`ffi`]: Foreign Function Interface for Mojo

#![warn(missing_docs)]
#![warn(clippy::all)]
#![allow(dead_code)] // TODO: Remove when all features are implemented

pub mod crypto;
pub mod security;
pub mod solana;
pub mod ffi;
pub mod infisical_manager;

// Re-export main interfaces for convenience
pub use crypto::CryptoEngine;
pub use security::SecurityEngine;
pub use solana::SolanaEngine;
pub use infisical_manager::{SecretsManager, ApiConfig, TradingConfig, WalletConfig, DatabaseConfig, MonitoringConfig};

use anyhow::Result;

/// Library version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Library initialization
pub fn initialize() -> Result<()> {
    // Initialize logging
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    // Initialize security subsystems
    ffi::ffi_initialize();

    log::info!("Mojo Trading Bot Rust Security Modules v{} initialized", VERSION);
    Ok(())
}

/// Library cleanup
pub fn cleanup() {
    ffi::ffi_cleanup();
    log::info!("Mojo Trading Bot Rust Security Modules cleaned up");
}

/// Get library information
pub fn get_library_info() -> LibraryInfo {
    LibraryInfo {
        name: "mojo-trading-bot".to_string(),
        version: VERSION.to_string(),
        description: "High-performance algorithmic trading bot security modules".to_string(),
        author: "MojoRust Team".to_string(),
        build_date: env!("VERGEN_BUILD_DATE").to_string(),
        git_hash: env!("VERGEN_GIT_SHA").to_string(),
    }
}

/// Library information
#[derive(Debug, Clone)]
pub struct LibraryInfo {
    pub name: String,
    pub version: String,
    pub description: String,
    pub author: String,
    pub build_date: String,
    pub git_hash: String,
}

/// Security level configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SecurityLevel {
    Low,
    Medium,
    High,
    Maximum,
}

impl SecurityLevel {
    /// Get security level from string
    pub fn from_str(level: &str) -> Self {
        match level.to_lowercase().as_str() {
            "low" => SecurityLevel::Low,
            "medium" => SecurityLevel::Medium,
            "high" => SecurityLevel::High,
            "maximum" => SecurityLevel::Maximum,
            _ => SecurityLevel::Medium,
        }
    }

    /// Get security level as string
    pub fn as_str(&self) -> &'static str {
        match self {
            SecurityLevel::Low => "low",
            SecurityLevel::Medium => "medium",
            SecurityLevel::High => "high",
            SecurityLevel::Maximum => "maximum",
        }
    }

    /// Get numeric security score
    pub fn score(&self) -> u8 {
        match self {
            SecurityLevel::Low => 25,
            SecurityLevel::Medium => 50,
            SecurityLevel::High => 75,
            SecurityLevel::Maximum => 100,
        }
    }
}

/// Configuration for the trading bot security modules
#[derive(Debug, Clone)]
pub struct TradingBotConfig {
    pub security_level: SecurityLevel,
    pub enable_logging: bool,
    pub enable_audit: bool,
    pub enable_monitoring: bool,
    pub rpc_url: String,
    pub ws_url: Option<String>,
    pub max_concurrent_requests: u32,
    pub request_timeout_ms: u64,
}

impl Default for TradingBotConfig {
    fn default() -> Self {
        Self {
            security_level: SecurityLevel::Medium,
            enable_logging: true,
            enable_audit: true,
            enable_monitoring: true,
            rpc_url: "https://api.mainnet-beta.solana.com".to_string(),
            ws_url: None,
            max_concurrent_requests: 10,
            request_timeout_ms: 30_000,
        }
    }
}

/// Main trading bot interface
pub struct TradingBot {
    config: TradingBotConfig,
    crypto_engine: CryptoEngine,
    security_engine: SecurityEngine,
    solana_engine: SolanaEngine,
}

impl TradingBot {
    /// Create new trading bot instance
    pub fn new(config: TradingBotConfig) -> Result<Self> {
        initialize()?;

        let crypto_engine = CryptoEngine::new()?;
        let security_engine = SecurityEngine::new()?;
        let solana_engine = SolanaEngine::new(&config.rpc_url, config.ws_url.as_deref())?;

        let mut bot = Self {
            config,
            crypto_engine,
            security_engine,
            solana_engine,
        };

        bot.initialize()?;
        Ok(bot)
    }

    /// Initialize the trading bot
    fn initialize(&mut self) -> Result<()> {
        // Initialize security engine
        self.security_engine.initialize()?;

        // Configure Solana engine
        let solana_config = solana::SolanaConfig::default();
        // Note: This would need to be made mutable in the actual implementation
        // self.solana_engine.initialize(solana_config)?;

        log::info!("Trading bot initialized with security level: {}",
                  self.config.security_level.as_str());
        Ok(())
    }

    /// Get configuration
    pub fn config(&self) -> &TradingBotConfig {
        &self.config
    }

    /// Get crypto engine
    pub fn crypto_engine(&self) -> &CryptoEngine {
        &self.crypto_engine
    }

    /// Get security engine
    pub fn security_engine(&self) -> &SecurityEngine {
        &self.security_engine
    }

    /// Get Solana engine
    pub fn solana_engine(&self) -> &SolanaEngine {
        &self.solana_engine
    }

    /// Perform health check
    pub fn health_check(&self) -> Result<HealthStatus> {
        let crypto_healthy = self.crypto_engine.keypair_manager().get_keypair().is_ok();
        let security_healthy = self.security_engine.monitor().is_active();
        let solana_healthy = self.solana_engine.get_cluster_health()?.is_healthy;

        Ok(HealthStatus {
            overall_healthy: crypto_healthy && security_healthy && solana_healthy,
            crypto_healthy,
            security_healthy,
            solana_healthy,
            uptime: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs(),
        })
    }

    /// Update configuration
    pub fn update_config(&mut self, new_config: TradingBotConfig) -> Result<()> {
        self.config = new_config;

        // Reinitialize if necessary
        if self.config.rpc_url != self.solana_engine.client().rpc_url() {
            self.solana_engine = SolanaEngine::new(&self.config.rpc_url, self.config.ws_url.as_deref())?;
        }

        log::info!("Trading bot configuration updated");
        Ok(())
    }

    /// Get performance metrics
    pub fn get_metrics(&self) -> Metrics {
        Metrics {
            security_score: self.config.security_level.score(),
            active_rate_limits: self.security_engine.rate_limiter().get_active_limits(),
            audit_log_size: self.security_engine.auditor().get_log_size(),
            threats_detected: self.security_engine.monitor().get_threat_count(),
            last_check: std::time::SystemTime::now(),
        }
    }
}

impl Drop for TradingBot {
    fn drop(&mut self) {
        cleanup();
    }
}

/// Health status information
#[derive(Debug, Clone)]
pub struct HealthStatus {
    pub overall_healthy: bool,
    pub crypto_healthy: bool,
    pub security_healthy: bool,
    pub solana_healthy: bool,
    pub uptime: u64,
}

/// Performance metrics
#[derive(Debug, Clone)]
pub struct Metrics {
    pub security_score: u8,
    pub active_rate_limits: usize,
    pub audit_log_size: usize,
    pub threats_detected: u64,
    pub last_check: std::time::SystemTime,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_library_initialization() {
        assert!(initialize().is_ok());
        cleanup();
    }

    #[test]
    fn test_library_info() {
        let info = get_library_info();
        assert_eq!(info.name, "mojo-trading-bot");
        assert!(!info.version.is_empty());
    }

    #[test]
    fn test_security_level() {
        assert_eq!(SecurityLevel::from_str("high"), SecurityLevel::High);
        assert_eq!(SecurityLevel::Medium.as_str(), "medium");
        assert_eq!(SecurityLevel::Maximum.score(), 100);
    }

    #[test]
    fn test_trading_bot_config() {
        let config = TradingBotConfig::default();
        assert_eq!(config.security_level, SecurityLevel::Medium);
        assert!(config.enable_logging);
    }

    #[test]
    fn test_trading_bot_creation() {
        let config = TradingBotConfig::default();
        // Note: This test may fail in CI without network access
        // let bot = TradingBot::new(config);
        // assert!(bot.is_ok());
    }

    #[test]
    fn test_crypto_engine_creation() {
        let engine = CryptoEngine::new();
        assert!(engine.is_ok());
    }

    #[test]
    fn test_security_engine_creation() {
        let engine = SecurityEngine::new();
        assert!(engine.is_ok());
    }

    #[test]
    fn test_solana_engine_creation() {
        let engine = SolanaEngine::new("https://api.mainnet-beta.solana.com", None);
        assert!(engine.is_ok());
    }
}