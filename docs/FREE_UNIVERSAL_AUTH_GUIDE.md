# Free Universal Auth Guide for MojoRust Trading Bot

## Overview

This guide shows how to use Universal Auth for Infisical without premium subscriptions, leveraging community-driven authentication and open-source security practices.

## What is Universal Auth?

Universal Auth is a secure authentication method that uses client credentials (client ID and client secret) to authenticate with Infisical and access secrets programmatically.

## Free vs Premium Features

### Free Universal Auth Features ✅
- **Client Credentials Authentication**: Secure OAuth2 flow
- **Automatic Token Refresh**: Built-in token management
- **Secret Caching**: Performance optimization
- **Community Support**: Community-driven security
- **Open Source**: Fully transparent implementation
- **Health Monitoring**: Authentication health checks

### Premium Features (Not Available) ❌
- Advanced RBAC controls
- Audit logs and compliance
- Multi-factor authentication
- Enterprise SSO integration
- Custom authentication providers

## Quick Start

### 1. Configuration Setup

```bash
# Add to your .env file
INFISICAL_CLIENT_ID=your_client_id
INFISICAL_CLIENT_SECRET=your_client_secret
INFISICAL_PROJECT_ID=your_project_id
INFISICAL_ENVIRONMENT=dev
INFISICAL_BASE_URL=https://app.infisical.com
```

### 2. Rust Implementation

```rust
use rust_modules::universal_auth_free::*;

#[tokio::main]
async fn main() -> Result<()> {
    // Create configuration
    let config = FreeUniversalAuthConfig::default();

    // Create secrets manager
    let mut secrets_manager = FreeSecretsManager::new(config)?;

    // Get a specific secret
    let helius_key = secrets_manager.get_secret("HELIUS_API_KEY").await?;
    println!("Helius API Key: {}", helius_key);

    // Get all trading configuration
    let trading_config = secrets_manager.get_trading_config().await?;
    println!("Trading config loaded: {} secrets", 5);

    Ok(())
}
```

### 3. Authentication Flow

The free Universal Auth follows this flow:

1. **Client Authentication**: Use client ID and secret to get access token
2. **Token Caching**: Cache token for performance (5-minute TTL)
3. **Automatic Refresh**: Refresh token before expiry (1-hour lifetime)
4. **Secret Access**: Use access token to fetch secrets from Infisical
5. **Error Handling**: Graceful fallback and retry mechanisms

## Configuration Options

### Basic Configuration

```rust
let config = FreeUniversalAuthConfig {
    client_id: "your_client_id".to_string(),
    client_secret: "your_client_secret".to_string(),
    project_id: "your_project_id".to_string(),
    environment: "dev".to_string(),
    base_url: "https://app.infisical.com".to_string(),
    cache_ttl_seconds: 300,
    enable_community_features: true,
};
```

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `INFISICAL_CLIENT_ID` | Yes | - | Your Infisical client ID |
| `INFISICAL_CLIENT_SECRET` | Yes | - | Your Infisical client secret |
| `INFISICAL_PROJECT_ID` | Yes | - | Your Infisical project ID |
| `INFISICAL_ENVIRONMENT` | No | `dev` | Environment (dev/staging/production) |
| `INFISICAL_BASE_URL` | No | `https://app.infisical.com` | Infisical API URL |
| `UNIVERSAL_AUTH_CACHE_TTL` | No | `300` | Token cache TTL in seconds |

## Usage Examples

### Basic Secret Retrieval

```rust
let mut secrets_manager = FreeSecretsManager::new(config)?;

// Single secret
let api_key = secrets_manager.get_secret("HELIUS_API_KEY").await?;

// Multiple secrets
let secret_paths = vec![
    "HELIUS_API_KEY".to_string(),
    "QUICKNODE_PRIMARY_RPC".to_string(),
    "WALLET_ADDRESS".to_string(),
];
let secrets = secrets_manager.auth_manager.get_secrets(&secret_paths).await?;
```

### Trading Configuration

```rust
let trading_config = secrets_manager.get_trading_config().await?;

println!("Helius API Key: {}", trading_config.helius_api_key);
println!("QuickNode RPC: {}", trading_config.quicknode_primary_rpc);
println!("Wallet Address: {}", trading_config.wallet_address);
```

### Health Monitoring

```rust
let health = secrets_manager.auth_manager.health_check();
println!("Authenticated: {}", health.is_authenticated);
println!("Cache size: {}", health.cache_size);
println!("Community features: {}", health.community_features_enabled);
```

## Community Features

### Community Statistics

The free Universal Auth includes community-driven metrics:

```rust
let stats = secrets_manager.auth_manager.get_community_stats();
println!("Success rate: {:.2}%", stats.get_success_rate() * 100.0);
println!("Cache hit rate: {:.2}%", stats.get_cache_hit_rate() * 100.0);
println!("Total refreshes: {}", stats.total_token_refreshes);
```

### Security Best Practices

1. **Rotate Credentials**: Regularly rotate client credentials
2. **Monitor Usage**: Track authentication success rates
3. **Use Caching**: Leverage built-in caching for performance
4. **Environment Isolation**: Use separate configs for dev/staging/prod
5. **Community Review**: Participate in community security reviews

## Integration with Trading Bot

### 1. Initialize Secrets Manager

```rust
// In your main trading bot initialization
let auth_config = FreeUniversalAuthConfig::default();
let mut secrets_manager = FreeSecretsManager::new(auth_config)?;

// Load trading configuration
let trading_config = secrets_manager.get_trading_config().await?;
```

### 2. Use Secrets in Trading Operations

```rust
// Initialize Solana client with RPC from secrets
let solana_client = SolanaClient::new(&trading_config.quicknode_primary_rpc);

// Use wallet configuration
let wallet = Wallet::from_path(&trading_config.wallet_private_key_path);

// Access API keys for external services
let helius_client = HeliusClient::new(&trading_config.helius_api_key);
```

### 3. Automatic Refresh

The secrets manager automatically handles token refresh:

```rust
// Secrets are automatically cached and refreshed
// No manual intervention required
let secret = secrets_manager.get_secret("SOME_SECRET").await?;
// If token expired, it's refreshed automatically
```

## Troubleshooting

### Common Issues

1. **Authentication Failed**
   - Check client ID and secret are correct
   - Verify project ID and environment
   - Ensure client has proper permissions

2. **Token Not Refreshing**
   - Check network connectivity to Infisical
   - Verify client credentials are still valid
   - Check rate limiting on Infisical API

3. **Secret Not Found**
   - Verify secret exists in Infisical
   - Check correct environment and project
   - Ensure proper access permissions

### Debug Mode

Enable debug logging to troubleshoot issues:

```rust
env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("debug")).init();
```

### Community Support

- **GitHub Issues**: Report bugs and request features
- **Discord Community**: Get help from other users
- **Documentation**: Check the latest documentation
- **Code Reviews**: Participate in community code reviews

## Performance Optimization

### Caching Strategy

- **Token Caching**: 5-minute TTL with 1-minute buffer before expiry
- **Secret Caching**: 5-minute TTL for retrieved secrets
- **Automatic Cleanup**: Expired entries are automatically removed

### Best Practices

1. **Reuse Secrets Manager**: Create one instance and reuse it
2. **Batch Requests**: Fetch multiple secrets in one request when possible
3. **Monitor Cache Hit Rates**: Aim for >80% cache hit rate
4. **Handle Failures Gracefully**: Implement retry logic with exponential backoff

## Security Considerations

### Protecting Credentials

1. **Environment Variables**: Store credentials in environment variables
2. **No Hardcoding**: Never hardcode credentials in code
3. **Access Control**: Limit access to .env files
4. **Regular Rotation**: Rotate client credentials regularly

### Audit Trail

While the free version doesn't include premium audit features, you can implement basic logging:

```rust
info!("Secret accessed: {}", secret_path);
info!("Authentication refreshed: {}", auth_manager.get_community_stats().total_token_refreshes);
```

## Migration from Premium

If you're migrating from premium to free Universal Auth:

1. **Keep Same Credentials**: Your client ID and secret remain the same
2. **Update Configuration**: Switch to the free configuration
3. **Test Thoroughly**: Ensure all functionality works as expected
4. **Monitor Performance**: Check that caching is working properly

## Contributing

We welcome community contributions:

- **Bug Reports**: Report issues on GitHub
- **Feature Requests**: Suggest new features
- **Code Contributions**: Submit pull requests
- **Documentation**: Help improve documentation
- **Security Reviews**: Participate in security audits

## License

This free Universal Auth implementation is open source and community-driven. Join us in making secure authentication accessible to everyone!
