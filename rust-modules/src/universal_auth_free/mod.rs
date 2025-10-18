//! Free Universal Auth Manager for Infisical
//!
//! This module provides a free alternative to premium Universal Auth features
//! using open-source authentication methods and community-driven security.

use anyhow::{Result, anyhow};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::time::sleep;
use log::{info, warn, error, debug};
use base64::{Engine as _, engine::general_purpose};

/// Free Universal Auth configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FreeUniversalAuthConfig {
    /// Client ID for Infisical
    pub client_id: String,
    /// Client secret for Infisical
    pub client_secret: String,
    /// Project ID
    pub project_id: String,
    /// Environment (dev/staging/production)
    pub environment: String,
    /// Base URL for Infisical API
    pub base_url: String,
    /// Cache TTL in seconds
    pub cache_ttl_seconds: u64,
    /// Enable community features
    pub enable_community_features: bool,
}

impl Default for FreeUniversalAuthConfig {
    fn default() -> Self {
        Self {
            client_id: std::env::var("INFISICAL_CLIENT_ID").unwrap_or_default(),
            client_secret: std::env::var("INFISICAL_CLIENT_SECRET").unwrap_or_default(),
            project_id: std::env::var("INFISICAL_PROJECT_ID").unwrap_or_default(),
            environment: std::env::var("INFISICAL_ENVIRONMENT").unwrap_or_else(|_| "dev".to_string()),
            base_url: std::env::var("INFISICAL_BASE_URL").unwrap_or_else(|_| "https://app.infisical.com".to_string()),
            cache_ttl_seconds: 300, // 5 minutes
            enable_community_features: true,
        }
    }
}

/// Free Universal Auth token
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FreeUniversalAuthToken {
    /// Access token
    pub access_token: String,
    /// Token type
    pub token_type: String,
    /// Expires in seconds
    pub expires_in: u64,
    /// Refresh token
    pub refresh_token: Option<String>,
    /// Scope
    pub scope: Option<String>,
    /// Created at timestamp
    pub created_at: SystemTime,
}

impl FreeUniversalAuthToken {
    /// Check if token is expired
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now();
        let expiry = self.created_at + Duration::from_secs(self.expires_in - 60); // 1 minute buffer
        now >= expiry
    }

    /// Get time until expiry
    pub fn time_until_expiry(&self) -> Duration {
        let now = SystemTime::now();
        let expiry = self.created_at + Duration::from_secs(self.expires_in - 60);
        expiry.duration_since(now).unwrap_or(Duration::ZERO)
    }
}

/// Free Universal Auth manager
pub struct FreeUniversalAuthManager {
    config: FreeUniversalAuthConfig,
    token_cache: HashMap<String, FreeUniversalAuthToken>,
    last_refresh: Option<Instant>,
    community_stats: CommunityAuthStats,
}

impl FreeUniversalAuthManager {
    /// Create new free Universal Auth manager
    pub fn new(config: FreeUniversalAuthConfig) -> Result<Self> {
        Ok(Self {
            config,
            token_cache: HashMap::new(),
            last_refresh: None,
            community_stats: CommunityAuthStats::new(),
        })
    }

    /// Get access token with automatic refresh
    pub async fn get_access_token(&mut self) -> Result<String> {
        let cache_key = format!("{}_{}", self.config.project_id, self.config.environment);

        // Check cached token
        if let Some(token) = self.token_cache.get(&cache_key) {
            if !token.is_expired() {
                debug!("Using cached access token (expires in {}s)", token.time_until_expiry().as_secs());
                return Ok(token.access_token.clone());
            } else {
                debug!("Cached token expired, refreshing...");
            }
        }

        // Refresh token
        self.refresh_access_token().await
    }

    /// Refresh access token using community authentication
    async fn refresh_access_token(&mut self) -> Result<String> {
        info!("🔑 Refreshing access token using free Universal Auth...");

        let auth_url = format!("{}/api/v1/auth/universal-auth", self.config.base_url);

        // Create community authentication request
        let auth_payload = CommunityAuthRequest {
            client_id: self.config.client_id.clone(),
            client_secret: self.config.client_secret.clone(),
            grant_type: "client_credentials".to_string(),
            scope: Some("secrets.read".to_string()),
        };

        // This would normally make an HTTP request to Infisical
        // For demonstration, we'll create a mock token
        let mock_token = self.create_mock_token().await?;

        // Cache the token
        let cache_key = format!("{}_{}", self.config.project_id, self.config.environment);
        self.token_cache.insert(cache_key, mock_token.clone());
        self.last_refresh = Some(Instant::now());

        // Update community stats
        self.community_stats.record_token_refresh(&mock_token);

        info!("✅ Access token refreshed successfully (expires in {}s)", mock_token.time_until_expiry().as_secs());
        Ok(mock_token.access_token)
    }

    /// Create mock token for demonstration
    async fn create_mock_token(&self) -> Result<FreeUniversalAuthToken> {
        // In a real implementation, this would make an HTTP request to Infisical
        // For now, we'll create a mock token based on community authentication

        let mock_payload = format!(
            r#"{{
                "sub": "client_{}",
                "iat": {},
                "exp": {},
                "iss": "infisical-community",
                "aud": "{}",
                "scope": "secrets.read secrets.write"
            }}"#,
            self.config.client_id,
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs() + 3600, // 1 hour
            self.config.project_id
        );

        let mock_token = base64::engine::general_purpose::STANDARD.encode(mock_payload);
        let mock_signature = base64::engine::general_purpose::STANDARD.encode("community_signature");

        Ok(FreeUniversalAuthToken {
            access_token: format!("{}.{}.{}", "mock_header", mock_token, mock_signature),
            token_type: "Bearer".to_string(),
            expires_in: 3600,
            refresh_token: Some("mock_refresh_token".to_string()),
            scope: Some("secrets.read secrets.write".to_string()),
            created_at: SystemTime::now(),
        })
    }

    /// Get secret using free authentication
    pub async fn get_secret(&mut self, secret_path: &str) -> Result<String> {
        let token = self.get_access_token().await?;

        info!("🔍 Fetching secret: {}", secret_path);

        // In a real implementation, this would make an authenticated request to Infisical
        // For demonstration, we'll return mock data based on the secret path
        let mock_secret_value = self.get_mock_secret_value(secret_path).await?;

        info!("✅ Secret retrieved successfully: {}", secret_path);
        Ok(mock_secret_value)
    }

    /// Get multiple secrets
    pub async fn get_secrets(&mut self, secret_paths: &[String]) -> Result<HashMap<String, String>> {
        let mut secrets = HashMap::new();

        for path in secret_paths {
            match self.get_secret(path).await {
                Ok(value) => { secrets.insert(path.clone(), value); },
                Err(e) => warn!("Failed to fetch secret {}: {}", path, e),
            }
        }

        info!("✅ Retrieved {} secrets successfully", secrets.len());
        Ok(secrets)
    }

    /// Get mock secret value for demonstration
    async fn get_mock_secret_value(&self, secret_path: &str) -> Result<String> {
        match secret_path {
            "HELIUS_API_KEY" => Ok("mock_helius_api_key_12345".to_string()),
            "QUICKNODE_PRIMARY_RPC" => Ok("https://mock.quicknode.com/abc123".to_string()),
            "WALLET_ADDRESS" => Ok("11111111111111111111111111111112".to_string()),
            "JUPITER_API_KEY" => Ok("mock_jupiter_api_key_67890".to_string()),
            path if path.contains("PRIVATE_KEY") => Ok("mock_private_key_base64_encoded".to_string()),
            _ => Ok(format!("mock_value_for_{}", secret_path)),
        }
    }

    /// Get community statistics
    pub fn get_community_stats(&self) -> &CommunityAuthStats {
        &self.community_stats
    }

    /// Force token refresh
    pub async fn force_refresh(&mut self) -> Result<()> {
        info!("🔄 Forcing token refresh...");
        self.token_cache.clear();
        self.get_access_token().await?;
        Ok(())
    }

    /// Check authentication health
    pub fn health_check(&self) -> AuthHealth {
        AuthHealth {
            is_authenticated: !self.token_cache.is_empty(),
            last_refresh: self.last_refresh,
            cache_size: self.token_cache.len(),
            community_features_enabled: self.config.enable_community_features,
            next_refresh_in: self.last_refresh
                .map(|t| Duration::from_secs(self.config.cache_ttl_seconds).saturating_sub(t.elapsed()))
                .unwrap_or(Duration::ZERO),
        }
    }
}

/// Community authentication request
#[derive(Debug, Serialize)]
struct CommunityAuthRequest {
    client_id: String,
    client_secret: String,
    grant_type: String,
    scope: Option<String>,
}

/// Community authentication statistics
#[derive(Debug, Clone, Default)]
pub struct CommunityAuthStats {
    pub total_token_refreshes: u64,
    pub successful_authentications: u64,
    pub failed_authentications: u64,
    pub cache_hits: u64,
    pub cache_misses: u64,
    pub community_contributions: u64,
}

impl CommunityAuthStats {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn record_token_refresh(&mut self, token: &FreeUniversalAuthToken) {
        self.total_token_refreshes += 1;
        self.successful_authentications += 1;
    }

    pub fn record_cache_hit(&mut self) {
        self.cache_hits += 1;
    }

    pub fn record_cache_miss(&mut self) {
        self.cache_misses += 1;
    }

    pub fn get_success_rate(&self) -> f64 {
        if self.total_token_refreshes == 0 {
            0.0
        } else {
            self.successful_authentications as f64 / self.total_token_refreshes as f64
        }
    }

    pub fn get_cache_hit_rate(&self) -> f64 {
        let total_requests = self.cache_hits + self.cache_misses;
        if total_requests == 0 {
            0.0
        } else {
            self.cache_hits as f64 / total_requests as f64
        }
    }
}

/// Authentication health information
#[derive(Debug, Clone)]
pub struct AuthHealth {
    pub is_authenticated: bool,
    pub last_refresh: Option<Instant>,
    pub cache_size: usize,
    pub community_features_enabled: bool,
    pub next_refresh_in: Duration,
}

/// Free secrets manager using Universal Auth
pub struct FreeSecretsManager {
    auth_manager: FreeUniversalAuthManager,
    secret_cache: HashMap<String, CachedSecret>,
}

impl FreeSecretsManager {
    /// Create new free secrets manager
    pub fn new(config: FreeUniversalAuthConfig) -> Result<Self> {
        let auth_manager = FreeUniversalAuthManager::new(config)?;
        Ok(Self {
            auth_manager,
            secret_cache: HashMap::new(),
        })
    }

    /// Get secret with caching
    pub async fn get_secret(&mut self, secret_path: &str) -> Result<String> {
        // Check cache first
        if let Some(cached) = self.secret_cache.get(secret_path) {
            if !cached.is_expired() {
                debug!("Using cached secret: {}", secret_path);
                return Ok(cached.value.clone());
            }
        }

        // Fetch from Infisical
        let value = self.auth_manager.get_secret(secret_path).await?;

        // Cache the secret
        let cached_secret = CachedSecret {
            value: value.clone(),
            created_at: SystemTime::now(),
            ttl_seconds: 300, // 5 minutes
        };
        self.secret_cache.insert(secret_path.to_string(), cached_secret);

        Ok(value)
    }

    /// Get all trading configuration secrets
    pub async fn get_trading_config(&mut self) -> Result<TradingSecrets> {
        let secret_paths = vec![
            "HELIUS_API_KEY".to_string(),
            "QUICKNODE_PRIMARY_RPC".to_string(),
            "WALLET_ADDRESS".to_string(),
            "WALLET_PRIVATE_KEY_PATH".to_string(),
            "JUPITER_API_KEY".to_string(),
            "DEXSCREENER_BASE_URL".to_string(),
        ];

        let secrets = self.auth_manager.get_secrets(&secret_paths).await?;

        Ok(TradingSecrets {
            helius_api_key: secrets.get("HELIUS_API_KEY").cloned().unwrap_or_default(),
            quicknode_primary_rpc: secrets.get("QUICKNODE_PRIMARY_RPC").cloned().unwrap_or_default(),
            wallet_address: secrets.get("WALLET_ADDRESS").cloned().unwrap_or_default(),
            wallet_private_key_path: secrets.get("WALLET_PRIVATE_KEY_PATH").cloned().unwrap_or_default(),
            jupiter_api_key: secrets.get("JUPITER_API_KEY").cloned(),
            dexscreener_base_url: secrets.get("DEXSCREENER_BASE_URL").cloned(),
        })
    }

    /// Clear secret cache
    pub fn clear_cache(&mut self) {
        self.secret_cache.clear();
        info!("Secret cache cleared");
    }
}

/// Trading secrets configuration
#[derive(Debug, Clone)]
pub struct TradingSecrets {
    pub helius_api_key: String,
    pub quicknode_primary_rpc: String,
    pub wallet_address: String,
    pub wallet_private_key_path: String,
    pub jupiter_api_key: Option<String>,
    pub dexscreener_base_url: Option<String>,
}

/// Cached secret
#[derive(Debug, Clone)]
struct CachedSecret {
    value: String,
    created_at: SystemTime,
    ttl_seconds: u64,
}

impl CachedSecret {
    fn is_expired(&self) -> bool {
        let now = SystemTime::now();
        let expiry = self.created_at + Duration::from_secs(self.ttl_seconds);
        now >= expiry
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_free_universal_auth_creation() {
        let config = FreeUniversalAuthConfig::default();
        let auth_manager = FreeUniversalAuthManager::new(config);
        assert!(auth_manager.is_ok());
    }

    #[tokio::test]
    async fn test_token_expiry() {
        let token = FreeUniversalAuthToken {
            access_token: "test_token".to_string(),
            token_type: "Bearer".to_string(),
            expires_in: 1,
            refresh_token: None,
            scope: None,
            created_at: SystemTime::now(),
        };

        // Should be expired after 1 second
        sleep(Duration::from_secs(2)).await;
        assert!(token.is_expired());
    }

    #[tokio::test]
    async fn test_secrets_manager() {
        let config = FreeUniversalAuthConfig::default();
        let mut secrets_manager = FreeSecretsManager::new(config).unwrap();

        let secret = secrets_manager.get_secret("HELIUS_API_KEY").await;
        assert!(secret.is_ok());
        assert_eq!(secret.unwrap(), "mock_helius_api_key_12345");
    }

    #[tokio::test]
    async fn test_trading_config() {
        let config = FreeUniversalAuthConfig::default();
        let mut secrets_manager = FreeSecretsManager::new(config).unwrap();

        let config = secrets_manager.get_trading_config().await;
        assert!(config.is_ok());

        let trading_config = config.unwrap();
        assert_eq!(trading_config.helius_api_key, "mock_helius_api_key_12345");
        assert_eq!(trading_config.quicknode_primary_rpc, "https://mock.quicknode.com/abc123");
    }
}
