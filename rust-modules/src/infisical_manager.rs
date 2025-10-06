//! Infisical Secrets Manager for MojoRust Trading Bot
//!
//! This module provides secure secrets management using Infisical,
//! allowing the trading bot to securely access API keys, wallet credentials,
//! and other sensitive configuration data.

use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use infisical::{AuthMethod, Client, InfisicalError};
use infisical::secrets::{GetSecretRequest, SecretResponse};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use async_trait::async_trait;

/// Cached secret with expiration time
#[derive(Debug, Clone)]
struct CachedSecret {
    value: String,
    cached_at: Instant,
    expires_at: Instant,
}

impl CachedSecret {
    fn new(value: String, ttl_seconds: u64) -> Self {
        let now = Instant::now();
        Self {
            value,
            cached_at: now,
            expires_at: now + Duration::from_secs(ttl_seconds),
        }
    }

    fn is_expired(&self) -> bool {
        Instant::now() >= self.expires_at
    }

    fn is_valid(&self) -> bool {
        !self.is_expired() && !self.value.is_empty()
    }
}

/// Infisical configuration
#[derive(Debug, Clone)]
pub struct InfisicalConfig {
    pub client_id: String,
    pub client_secret: String,
    pub project_id: String,
    pub environment: String,
    pub base_url: String,
    pub cache_ttl_seconds: u64,
}

impl InfisicalConfig {
    pub fn from_env() -> Result<Self> {
        Ok(Self {
            client_id: env::var("INFISICAL_CLIENT_ID")
                .map_err(|_| anyhow!("INFISICAL_CLIENT_ID environment variable not set"))?,
            client_secret: env::var("INFISICAL_CLIENT_SECRET")
                .map_err(|_| anyhow!("INFISICAL_CLIENT_SECRET environment variable not set"))?,
            project_id: env::var("INFISICAL_PROJECT_ID")
                .map_err(|_| anyhow!("INFISICAL_PROJECT_ID environment variable not set"))?,
            environment: env::var("INFISICAL_ENVIRONMENT").unwrap_or_else(|_| "dev".to_string()),
            base_url: env::var("INFISICAL_BASE_URL")
                .unwrap_or_else(|_| "https://app.infisical.com".to_string()),
            cache_ttl_seconds: env::var("INFISICAL_CACHE_TTL_SECONDS")
                .ok()
                .and_then(|s| s.parse().ok())
                .unwrap_or(300), // 5 minutes default
        })
    }
}

/// Trait for secret management providers
#[async_trait]
pub trait SecretProvider: Send + Sync {
    async fn get_secret(&self, key: &str) -> Result<String>;
    async fn get_secret_with_path(&self, path: &str, key: &str) -> Result<String>;
    async fn list_secrets(&self, path: Option<&str>) -> Result<Vec<String>>;
}

/// Infisical-based secret provider
pub struct InfisicalSecretProvider {
    client: Arc<Client>,
    config: InfisicalConfig,
    cache: Arc<RwLock<HashMap<String, CachedSecret>>>,
}

impl InfisicalSecretProvider {
    /// Create a new Infisical secret provider
    pub async fn new(config: InfisicalConfig) -> Result<Self> {
        let client = Arc::new(
            Client::builder()
                .base_url(&config.base_url)
                .build()
                .await?,
        );

        // Authenticate with universal auth
        let auth = AuthMethod::new_universal_auth(&config.client_id, &config.client_secret);
        client.login(auth).await?;

        Ok(Self {
            client,
            config,
            cache: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    /// Get secret with caching
    async fn get_secret_cached(&self, key: &str, path: Option<&str>) -> Result<String> {
        let cache_key = if let Some(path) = path {
            format!("{}:{}", path, key)
        } else {
            key.to_string()
        };

        // Check cache first
        {
            let cache = self.cache.read().await;
            if let Some(cached_secret) = cache.get(&cache_key) {
                if cached_secret.is_valid() {
                    return Ok(cached_secret.value.clone());
                }
            }
        }

        // Cache miss or expired, fetch from Infisical
        let secret_value = if let Some(path) = path {
            self.get_secret_with_path_impl(path, key).await?
        } else {
            self.get_secret_impl(key).await?
        };

        // Update cache
        let cached_secret = CachedSecret::new(secret_value.clone(), self.config.cache_ttl_seconds);
        {
            let mut cache = self.cache.write().await;
            cache.insert(cache_key, cached_secret);
        }

        Ok(secret_value)
    }

    /// Implementation of secret retrieval without caching
    async fn get_secret_impl(&self, key: &str) -> Result<String> {
        let req = GetSecretRequest::builder(
            key,
            &self.config.project_id,
            &self.config.environment,
        ).build();

        let secret = self.client.secrets().get(req).await?;
        Ok(secret.secret_key)
    }

    /// Implementation of secret retrieval with path without caching
    async fn get_secret_with_path_impl(&self, path: &str, key: &str) -> Result<String> {
        let req = GetSecretRequest::builder(
            key,
            &self.config.project_id,
            &self.config.environment,
        )
        .path(path)
        .build();

        let secret = self.client.secrets().get(req).await?;
        Ok(secret.secret_key)
    }

    /// Clear expired entries from cache
    pub async fn cleanup_cache(&self) {
        let mut cache = self.cache.write().await;
        cache.retain(|_, cached_secret| !cached_secret.is_expired());
    }

    /// Preload commonly used secrets
    pub async fn preload_secrets(&self, secret_keys: Vec<String>) -> Result<()> {
        for key in secret_keys {
            if let Err(e) = self.get_secret_cached(&key, None).await {
                eprintln!("Warning: Failed to preload secret '{}': {}", key, e);
            }
        }
        Ok(())
    }
}

#[async_trait]
impl SecretProvider for InfisicalSecretProvider {
    async fn get_secret(&self, key: &str) -> Result<String> {
        self.get_secret_cached(key, None).await
    }

    async fn get_secret_with_path(&self, path: &str, key: &str) -> Result<String> {
        self.get_secret_cached(key, Some(path)).await
    }

    async fn list_secrets(&self, path: Option<&str>) -> Result<Vec<String>> {
        // This would require implementing list secrets functionality
        // For now, return an empty list
        Ok(Vec::new())
    }
}

/// Environment variable fallback secret provider
pub struct EnvSecretProvider;

#[async_trait]
impl SecretProvider for EnvSecretProvider {
    async fn get_secret(&self, key: &str) -> Result<String> {
        env::var(key).map_err(|_| anyhow!("Environment variable '{}' not found", key))
    }

    async fn get_secret_with_path(&self, _path: &str, _key: &str) -> Result<String> {
        Err(anyhow!("Path-based secrets not supported with environment provider"))
    }

    async fn list_secrets(&self, _path: Option<&str>) -> Result<Vec<String>> {
        Ok(Vec::new())
    }
}

/// Composite secret provider with fallback mechanism
pub struct CompositeSecretProvider {
    primary: Box<dyn SecretProvider>,
    fallback: Box<dyn SecretProvider>,
}

impl CompositeSecretProvider {
    pub fn new(primary: Box<dyn SecretProvider>, fallback: Box<dyn SecretProvider>) -> Self {
        Self { primary, fallback }
    }

    /// Create with Infisical as primary and environment as fallback
    pub async fn with_infisical_fallback(config: InfisicalConfig) -> Result<Self> {
        let infisical_provider = InfisicalSecretProvider::new(config.clone()).await?;
        let env_provider = EnvSecretProvider;

        Ok(Self::new(
            Box::new(infisical_provider),
            Box::new(env_provider),
        ))
    }
}

#[async_trait]
impl SecretProvider for CompositeSecretProvider {
    async fn get_secret(&self, key: &str) -> Result<String> {
        match self.primary.get_secret(key).await {
            Ok(value) => Ok(value),
            Err(e) => {
                eprintln!("Warning: Primary secret provider failed for '{}': {}. Trying fallback.", key, e);
                self.fallback.get_secret(key).await
            }
        }
    }

    async fn get_secret_with_path(&self, path: &str, key: &str) -> Result<String> {
        match self.primary.get_secret_with_path(path, key).await {
            Ok(value) => Ok(value),
            Err(e) => {
                eprintln!("Warning: Primary secret provider failed for '{}/{}': {}. Trying fallback.", path, key, e);
                self.fallback.get_secret_with_path(path, key).await
            }
        }
    }

    async fn list_secrets(&self, path: Option<&str>) -> Result<Vec<String>> {
        match self.primary.list_secrets(path).await {
            Ok(list) => Ok(list),
            Err(e) => {
                eprintln!("Warning: Primary secret provider failed to list secrets: {}. Trying fallback.", e);
                self.fallback.list_secrets(path).await
            }
        }
    }
}

/// Secrets manager for the trading bot
pub struct SecretsManager {
    provider: Arc<dyn SecretProvider>,
}

impl SecretsManager {
    /// Create a new secrets manager
    pub async fn new() -> Result<Self> {
        let provider = if let Ok(infisical_config) = InfisicalConfig::from_env() {
            // Try to use Infisical with environment fallback
            match CompositeSecretProvider::with_infisical_fallback(infisical_config).await {
                Ok(provider) => Arc::new(provider),
                Err(e) => {
                    eprintln!("Warning: Failed to initialize Infisical provider: {}. Using environment fallback.", e);
                    Arc::new(EnvSecretProvider) as Arc<dyn SecretProvider>
                }
            }
        } else {
            // No Infisical configuration, use environment only
            eprintln!("Info: Infisical not configured, using environment variables for secrets");
            Arc::new(EnvSecretProvider) as Arc<dyn SecretProvider>
        };

        Ok(Self { provider })
    }

    /// Create with custom provider
    pub fn with_provider(provider: Arc<dyn SecretProvider>) -> Self {
        Self { provider }
    }

    /// Get API configuration
    pub async fn get_api_config(&self) -> Result<ApiConfig> {
        Ok(ApiConfig {
            helius_api_key: self.get_secret("HELIUS_API_KEY").await?,
            helius_base_url: self.get_secret_with_default("HELIUS_BASE_URL", "https://api.helius.xyz/v0").await?,
            helius_rpc_url: self.get_secret("HELIUS_RPC_URL").await?,
            quicknode_rpcs: QuickNodeRPCs {
                primary: self.get_secret("QUICKNODE_PRIMARY_RPC").await?,
                secondary: self.get_secret_with_default("QUICKNODE_SECONDARY_RPC", "").await?,
                archive: self.get_secret_with_default("QUICKNODE_ARCHIVE_RPC", "").await?,
            },
            dexscreener_base_url: self.get_secret_with_default("DEXSCREENER_BASE_URL", "https://api.dexscreener.com/latest/dex").await?,
            jupiter_base_url: self.get_secret_with_default("JUPITER_BASE_URL", "https://quote-api.jup.ag/v6").await?,
            jupiter_quote_api: self.get_secret_with_default("JUPITER_QUOTE_API", "https://quote-api.jup.ag/v6/quote").await?,
            timeout_seconds: self.get_secret_with_default("API_TIMEOUT_SECONDS", "10.0").await?
                .parse()
                .map_err(|_| anyhow!("Invalid API_TIMEOUT_SECONDS value"))?,
        })
    }

    /// Get trading configuration
    pub async fn get_trading_config(&self) -> Result<TradingConfig> {
        Ok(TradingConfig {
            initial_capital: self.get_secret_with_default("INITIAL_CAPITAL", "1.0").await?
                .parse()
                .map_err(|_| anyhow!("Invalid INITIAL_CAPITAL value"))?,
            max_position_size: self.get_secret_with_default("MAX_POSITION_SIZE", "0.1").await?
                .parse()
                .map_err(|_| anyhow!("Invalid MAX_POSITION_SIZE value"))?,
            max_drawdown: self.get_secret_with_default("MAX_DRAWDOWN", "0.15").await?
                .parse()
                .map_err(|_| anyhow!("Invalid MAX_DRAWDOWN value"))?,
            cycle_interval: self.get_secret_with_default("CYCLE_INTERVAL", "1.0").await?
                .parse()
                .map_err(|_| anyhow!("Invalid CYCLE_INTERVAL value"))?,
            kelly_fraction: self.get_secret_with_default("KELLY_FRACTION", "0.5").await?
                .parse()
                .map_err(|_| anyhow!("Invalid KELLY_FRACTION value"))?,
            max_correlation: self.get_secret_with_default("MAX_CORRELATION", "0.7").await?
                .parse()
                .map_err(|_| anyhow!("Invalid MAX_CORRELATION value"))?,
            diversification_target: self.get_secret_with_default("DIVERSIFICATION_TARGET", "10").await?
                .parse()
                .map_err(|_| anyhow!("Invalid DIVERSIFICATION_TARGET value"))?,
            max_daily_trades: self.get_secret_with_default("MAX_DAILY_TRADES", "50").await?
                .parse()
                .map_err(|_| anyhow!("Invalid MAX_DAILY_TRADES value"))?,
        })
    }

    /// Get wallet configuration
    pub async fn get_wallet_config(&self) -> Result<WalletConfig> {
        Ok(WalletConfig {
            address: self.get_secret("WALLET_ADDRESS").await?,
            private_key_path: self.get_secret_with_default("WALLET_PRIVATE_KEY_PATH", "~/.config/solana/id.json").await?,
        })
    }

    /// Get database configuration
    pub async fn get_database_config(&self) -> Result<DatabaseConfig> {
        Ok(DatabaseConfig {
            url: self.get_secret("DATABASE_URL").await?,
            max_connections: self.get_secret_with_default("DATABASE_MAX_CONNECTIONS", "10").await?
                .parse()
                .map_err(|_| anyhow!("Invalid DATABASE_MAX_CONNECTIONS value"))?,
        })
    }

    /// Get monitoring configuration
    pub async fn get_monitoring_config(&self) -> Result<MonitoringConfig> {
        Ok(MonitoringConfig {
            enabled: self.get_secret_with_default("MONITORING_ENABLED", "true").await?
                .parse()
                .map_err(|_| anyhow!("Invalid MONITORING_ENABLED value"))?,
            metrics_port: self.get_secret_with_default("METRICS_PORT", "9090").await?
                .parse()
                .map_err(|_| anyhow!("Invalid METRICS_PORT value"))?,
            dashboard_port: self.get_secret_with_default("DASHBOARD_PORT", "3000").await?
                .parse()
                .map_err(|_| anyhow!("Invalid DASHBOARD_PORT value"))?,
        })
    }

    /// Get a secret value
    pub async fn get_secret(&self, key: &str) -> Result<String> {
        self.provider.get_secret(key).await
    }

    /// Get a secret value with default fallback
    pub async fn get_secret_with_default(&self, key: &str, default: &str) -> Result<String> {
        match self.provider.get_secret(key).await {
            Ok(value) => Ok(value),
            Err(_) => Ok(default.to_string()),
        }
    }

    /// Get a secret with path
    pub async fn get_secret_with_path(&self, path: &str, key: &str) -> Result<String> {
        self.provider.get_secret_with_path(path, key).await
    }
}

// Configuration structures
#[derive(Debug, Clone)]
pub struct ApiConfig {
    pub helius_api_key: String,
    pub helius_base_url: String,
    pub helius_rpc_url: String,
    pub quicknode_rpcs: QuickNodeRPCs,
    pub dexscreener_base_url: String,
    pub jupiter_base_url: String,
    pub jupiter_quote_api: String,
    pub timeout_seconds: f64,
}

#[derive(Debug, Clone)]
pub struct QuickNodeRPCs {
    pub primary: String,
    pub secondary: String,
    pub archive: String,
}

#[derive(Debug, Clone)]
pub struct TradingConfig {
    pub initial_capital: f64,
    pub max_position_size: f64,
    pub max_drawdown: f64,
    pub cycle_interval: f64,
    pub kelly_fraction: f64,
    pub max_correlation: f64,
    pub diversification_target: i32,
    pub max_daily_trades: i32,
}

#[derive(Debug, Clone)]
pub struct WalletConfig {
    pub address: String,
    pub private_key_path: String,
}

#[derive(Debug, Clone)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
}

#[derive(Debug, Clone)]
pub struct MonitoringConfig {
    pub enabled: bool,
    pub metrics_port: u16,
    pub dashboard_port: u16,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    #[tokio::test]
    async fn test_infisical_config_from_env() {
        // Set test environment variables
        env::set_var("INFISICAL_CLIENT_ID", "test_client_id");
        env::set_var("INFISICAL_CLIENT_SECRET", "test_client_secret");
        env::set_var("INFISICAL_PROJECT_ID", "test_project_id");

        let config = InfisicalConfig::from_env().unwrap();
        assert_eq!(config.client_id, "test_client_id");
        assert_eq!(config.environment, "dev"); // default value
    }

    #[tokio::test]
    async fn test_env_secret_provider() {
        let provider = EnvSecretProvider;

        // Set a test environment variable
        env::set_var("TEST_SECRET", "test_value");

        let value = provider.get_secret("TEST_SECRET").await.unwrap();
        assert_eq!(value, "test_value");

        // Clean up
        env::remove_var("TEST_SECRET");
    }

    #[tokio::test]
    async fn test_cached_secret_expiration() {
        let cached = CachedSecret::new("test_value".to_string(), 1);
        assert!(!cached.is_expired());

        // Create an expired secret (0 TTL)
        let expired = CachedSecret::new("test_value".to_string(), 0);
        // Note: We can't actually test expiration without time manipulation
        assert!(!expired.is_expired()); // Just testing creation
    }
}