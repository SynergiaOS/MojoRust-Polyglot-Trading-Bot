# API Keys Setup Guide

This guide provides step-by-step instructions for obtaining and configuring all required API keys for the MojoRust Trading Bot.

## 1. Helius API Setup

**Purpose**: Primary Solana RPC provider with enhanced features (ShredStream, organic score, webhooks)

**Steps:**
1. Navigate to https://helius.dev
2. Sign up for an account (free tier available)
3. Create a new API key from dashboard
4. Select plan based on needs:
   - Free: 100 requests/second
   - Premium: 1,000+ requests/second (recommended for production)
5. Copy API key → `HELIUS_API_KEY` in `.env`
6. Construct RPC URL: `https://mainnet.helius-rpc.com/?api-key=YOUR_KEY`
7. Set in `.env`: `HELIUS_RPC_URL=https://mainnet.helius-rpc.com/?api-key=YOUR_KEY`

**Optional Features** (see `.env.example` lines 51-56):
- Enable ShredStream for ultra-low latency: `HELIUS_SHREDSTREAM_ENABLED=true`
- Enable organic score filtering: `HELIUS_ORGANIC_SCORE_ENABLED=true`
- Configure webhooks for real-time notifications

**Integration**: Used by `src/data/helius_client.mojo` for transaction data, token metadata, and enhanced Solana RPC calls.

---

## 2. QuickNode RPC Setup

**Purpose**: High-performance Solana RPC endpoints with archive node support

**Steps:**
1. Navigate to https://www.quicknode.com
2. Sign up and create account
3. Click "Create Endpoint"
4. Select:
   - Chain: Solana
   - Network: Mainnet Beta
   - Plan: Based on requests/day needs
5. Copy endpoint URL → `QUICKNODE_PRIMARY_RPC` in `.env`
6. Optional: Create backup endpoint → `QUICKNODE_SECONDARY_RPC`
7. Optional: Create archive endpoint → `QUICKNODE_ARCHIVE_RPC`

**Configuration in .env** (see `.env.example` lines 93-96):
```bash
QUICKNODE_PRIMARY_RPC=https://your-endpoint.solana-mainnet.quiknode.pro/
QUICKNODE_SECONDARY_RPC=https://backup-endpoint.solana-mainnet.quiknode.pro/
QUICKNODE_ARCHIVE_RPC=https://archive-endpoint.solana-mainnet.quiknode.pro/
```

**Integration**: Used by `src/data/quicknode_client.mojo` for RPC routing with automatic failover between primary/secondary endpoints.

---

## 3. Jupiter API (No Key Required)

**Purpose**: DEX aggregator for optimal swap routing and pricing

**Configuration** (see `.env.example` lines 49-51):
```bash
JUPITER_API_URL=https://quote-api.jup.ag/v6
JUPITER_SWAP_URL=https://swap.jup.ag
```

**No API key needed** - Jupiter API is public and rate-limited by IP.

**Integration**: Used by `src/data/jupiter_client.mojo` for price quotes, swap routing, and DEX aggregation.

---

## 4. DexScreener API (No Key Required)

**Purpose**: Real-time DEX trading data and token analytics

**Configuration** (see `.env.example` line 54):
```bash
DEXSCREENER_API_URL=https://api.dexscreener.com/latest/dex
```

**No API key needed** - Public API with rate limits (300 requests/minute default).

**Integration**: Used by `src/data/dexscreener_client.mojo` for token pair data, volume analysis, and market metrics.

---

## 5. Optional: Geyser Plugin (Advanced)

**Purpose**: Real-time Solana account updates via gRPC streaming

**Configuration** (see `.env.example` lines 61-66):
```bash
GEYSER_ENABLED=false  # Set to true when ready
GEYSER_ENDPOINT=grpc.solana.mainnet.rpc.helius.xyz:443
GEYSER_TOKEN=your_geyser_auth_token
```

**Setup**: Contact Helius or other Geyser providers for access. The Rust data consumer (`rust-modules/src/data_consumer.rs`) handles Geyser streaming.

---

## 6. Optional: Social Intelligence APIs

**Twitter/X API** (see `.env.example` lines 78-83):
1. Navigate to https://developer.twitter.com
2. Create developer account and app
3. Generate API keys and bearer token
4. Used by `src/data/social_client.mojo` for social sentiment analysis

**PumpPortal API** (see `.env.example` lines 86-88):
1. Navigate to https://pumpportal.fun
2. Sign up and get API key
3. Used for pump.fun token monitoring

---

## API Rate Limits Configuration

Set rate limits in `.env` to prevent exceeding quotas (see `.env.example` lines 341-351):
```bash
HELIUS_RATE_LIMIT=1000  # requests per minute
QUICKNODE_RATE_LIMIT=100  # requests per second
DEXSCREENER_RATE_LIMIT=300  # requests per minute
JUPITER_RATE_LIMIT=100  # requests per minute
```

**Integration**: Rate limiting is handled by `src/monitoring/rate_limiter.mojo` with token bucket algorithm.

---

## Testing API Keys

After configuration, test each API:

```bash
# Test Helius
curl -H "Authorization: Bearer $HELIUS_API_KEY" \
     https://api.helius.xyz/v0/addresses/tokens

# Test QuickNode
curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
     $QUICKNODE_PRIMARY_RPC

# Test Jupiter
curl https://quote-api.jup.ag/v6/quote?inputMint=So11111111111111111111111111111111111111112&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&amount=1000000

# Test DexScreener
curl https://api.dexscreener.com/latest/dex/tokens/So11111111111111111111111111111111111111112
```

**Validation**: Run `scripts/validate_config.sh` which checks API key formats and connectivity (lines 268-292).

---

## Security Best Practices

- Store production API keys in Infisical, not `.env` file
- Use separate API keys for dev/staging/production
- Rotate API keys every 90 days
- Monitor API usage in provider dashboards
- Set up billing alerts to prevent unexpected charges
- Never commit API keys to version control
- Use environment-specific rate limits

## Cost Optimization

- Start with free tiers for testing
- Monitor actual usage before upgrading plans
- Use caching to reduce API calls (see `src/monitoring/rate_limiter.mojo`)
- Implement request batching where possible
- Use DragonflyDB caching (configured in `.env.example` line 301) to cache API responses

Refer to `docs/RPC_PROVIDER_STRATEGY.md` for detailed RPC provider selection and failover strategies.