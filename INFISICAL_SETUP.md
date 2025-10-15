# Infisical Setup Guide

This guide provides step-by-step instructions for setting up Infisical account and obtaining the required credentials for the MojoRust Trading Bot.

## 1. Create Infisical Account

1. Navigate to https://app.infisical.com
2. Sign up with email or GitHub/Google OAuth
3. Verify email address
4. Complete account setup

## 2. Create New Project

1. Click "New Project" in Infisical dashboard
2. Name: "MojoRust Trading Bot" or similar
3. Select organization (or create new one)
4. Note the Project ID (will be used as `INFISICAL_PROJECT_ID`)

## 3. Configure Environments

1. Infisical projects have multiple environments (dev, staging, production)
2. Ensure "production" environment exists
3. This matches `INFISICAL_ENVIRONMENT=production` in `.env`

## 4. Create Machine Identity (Service Token)

1. Navigate to Project Settings → Machine Identities
2. Click "Create Machine Identity"
3. Name: "Trading Bot Production"
4. Select "Universal Auth" method
5. Set permissions: Read access to production environment
6. Copy the generated credentials:
   - **Client ID** → `INFISICAL_CLIENT_ID`
   - **Client Secret** → `INFISICAL_CLIENT_SECRET` (shown only once!)

## 5. Add Secrets to Infisical

Optionally store sensitive values in Infisical instead of `.env`:
1. Navigate to Secrets → production environment
2. Add secrets:
   - `HELIUS_API_KEY`
   - `QUICKNODE_RPC_URL`
   - `QUICKNODE_API_KEY`
   - `SOLANA_PRIVATE_KEY` (if storing in Infisical)
   - `TIMESCALEDB_PASSWORD`
   - `REDIS_PASSWORD`
   - `JWT_SECRET_KEY`

## 6. Test Connection

Install Infisical CLI and test:
```bash
npm install -g infisical
infisical login
infisical secrets list --projectId <PROJECT_ID> --env production
```

## 7. Update .env File

Add the credentials to `.env`:
```bash
INFISICAL_CLIENT_ID=<your_client_id>
INFISICAL_CLIENT_SECRET=<your_client_secret>
INFISICAL_PROJECT_ID=<your_project_id>
INFISICAL_ENVIRONMENT=production
```

## Integration Details

The bot's Infisical integration works as follows:
- **Rust Implementation**: `rust-modules/src/infisical_manager.rs` provides `SecretsManager` class with `InfisicalSecretProvider` and `EnvSecretProvider` fallback
- **Mojo Implementation**: `src/core/infisical_client.mojo` provides `InfisicalClient` struct with similar fallback mechanism
- **Caching**: Secrets are cached for 300 seconds (5 minutes) by default to reduce API calls
- **Fallback**: If Infisical is unavailable, automatically falls back to environment variables from `.env`

## Security Best Practices

- Never commit Client Secret to version control
- Rotate credentials regularly (every 90 days)
- Use separate machine identities for dev/staging/production
- Enable audit logging in Infisical dashboard
- Set up secret rotation policies
- Monitor access logs for unauthorized attempts

## Troubleshooting

- If connection fails, check firewall allows HTTPS to app.infisical.com
- Verify Client ID and Secret are correct (no extra spaces)
- Ensure Project ID matches the actual project
- Check environment name is exactly "production" (case-sensitive)
- Review Infisical CLI logs: `infisical --debug secrets list`

Refer to `scripts/validate_config.sh` (lines 296-342) for automated Infisical connectivity testing.