# Free Data Sources Guide

This guide provides comprehensive instructions for enabling and configuring the Rust data consumer to access free Solana data sources. The Rust consumer replaces expensive API calls with high-performance Geyser streaming and reduces costs by over 90%.

## Overview

The MojoRust trading bot includes a Rust-based data consumer that:

- **Streams real-time Solana data** via Geyser gRPC (free)
- **Filters events** to reduce volume by >99%
- **Publishes to Redis** for consumption by Python components
- **Exposes metrics** via Prometheus endpoint
- **Supports backpressure** and rate limiting

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Solana        │    │   Rust Data      │    │   Redis Pub/Sub │
│   Geyser gRPC   │───▶│   Consumer       │───▶│   Channels       │
│   (Free)        │    │   (data_consumer) │    │   (localhost)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                       │
                       ┌─────────────────────────────┘
                       │
                       ▼
              ┌─────────────────┐    ┌─────────────────┐
              │   TaskPool      │    │   Trading Bot   │
              │   Manager       │───▶│   Python        │
              │   (Consumer)    │    │   Components    │
              └─────────────────┘    └─────────────────┘
```

## Prerequisites

### System Requirements

- **Rust 1.70+** for building the data consumer
- **Redis 6.0+** for pub/sub messaging
- **Docker** (optional) for containerized deployment
- **Systemd** (Linux) for service management

### Solana Network Access

- Public Geyser endpoints (free tier available)
- WebSocket connection for real-time streaming
- No API keys required for basic usage

## Quick Start

### 1. Build the Rust Data Consumer

```bash
cd /home/marcin/Projects/MojoRust/rust-modules

# Build using the provided script
./build_data_consumer.sh

# Or build manually
cargo build --bin data_consumer --release
```

### 2. Start Redis

```bash
# Using Docker
docker run -d --name redis -p 6379:6379 redis:7-alpine

# Or using system package
sudo systemctl start redis-server
```

### 3. Configure Environment Variables

Create `.env` file:

```bash
# Geyser endpoint (public free endpoint)
GEYSER_ENDPOINT="https://api.mainnet-beta.solana.com:443"

# Redis connection
REDIS_URL="redis://localhost:6379"

# Metrics server
METRICS_ADDR="0.0.0.0:9191"

# Enable Rust consumer in Python
ENABLE_RUST_CONSUMER="true"

# Logging
RUST_LOG="info"
```

### 4. Start the Data Consumer

```bash
# Direct execution
./target/release/data_consumer

# Or using Docker
docker build -f Dockerfile.data-consumer -t data-consumer .
docker run -d --name data-consumer -p 9191:9191 data-consumer
```

### 5. Enable in Trading Bot

```python
# In your main bot configuration
import os
os.environ["ENABLE_RUST_CONSUMER"] = "true"

# The TaskPoolManager will automatically connect to Redis
```

## Configuration

### Event Filters

The data consumer filters events to reduce volume. Configure filters in `src/data_consumer.rs`:

```rust
// Update these filters in the data consumer binary
let filters = EventFilters {
    program_ids: HashSet::from([
        // Raydium AMM
        Pubkey::from_str("675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8").unwrap(),
        // Orca AMM
        Pubkey::from_str("9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP").unwrap(),
        // Add more program IDs as needed
    ]),
    min_transaction_amount: 1_000_000_000, // 1 SOL minimum
    token_whitelist: HashSet::new(),        // Add specific tokens if needed
    wallet_watchlist: HashSet::new(),       # Add whale addresses to monitor
};
```

### Rate Limiting

Configure per-event-type rate limiting in `src/orchestration/task_pool_manager.py`:

```python
# Rate limits in events per second
self.event_rate_limiters = {
    'NewTokenMint': TokenBucketRateLimiter(capacity=10, refill_rate=1.0),      # 10 burst, 1/sec
    'LargeTransaction': TokenBucketRateLimiter(capacity=50, refill_rate=10.0),   # 50 burst, 10/sec
    'WhaleActivity': TokenBucketRateLimiter(capacity=20, refill_rate=5.0),       # 20 burst, 5/sec
    'LiquidityChange': TokenBucketRateLimiter(capacity=30, refill_rate=8.0),     # 30 burst, 8/sec
    'PriceUpdate': TokenBucketRateLimiter(capacity=100, refill_rate=20.0),      # 100 burst, 20/sec
}
```

## Free Data Sources

### 1. Solana Geyser (Primary)

**Cost**: Free (public endpoints)
**Data**: Real-time account and transaction updates
**Latency**: <100ms
**Usage**: Primary data source for all blockchain events

```rust
// Public Geyser endpoints
const GEYSER_ENDPOINTS = [
    "https://api.mainnet-beta.solana.com:443",
    "https://solana-api.projectserum.com:443",
    "https://rpc.ankr.com/solana:443"
];
```

### 2. Jupiter Price API (Fallback)

**Cost**: Free
**Data**: Token prices and swap quotes
**Usage**: Price validation and arbitrage opportunities

### 3. Helius Metadata API (Complementary)

**Cost**: Free tier available
**Data**: Token metadata and NFT information
**Usage**: Enriching token mint events

## Event Types

The Rust consumer processes these event types:

| Event Type | Description | Frequency | Use Case |
|------------|-------------|-----------|----------|
| `NewTokenMint` | New token creation | Low | New token discovery |
| `LargeTransaction` | High-value transactions | Medium | Whale watching |
| `WhaleActivity` | Large wallet movements | Low | Whale analysis |
| `LiquidityChange` | DEX liquidity updates | Medium | Arbitrage detection |
| `PriceUpdate` | Price changes | High | Trading signals |

## Performance Metrics

Access metrics at `http://localhost:9191/metrics`:

```
# Events processed by type
rust_events_processed_total{event_type="NewTokenMint"} 1234

# Rate limiting status
rate_limit_tokens_available{event_type="LargeTransaction"} 45

# Task drops due to backpressure
task_drops_total{reason="queue_full"} 0

# Redis Pub/Sub lag
redis_pubsub_lag_ms 12.5
```

## Troubleshooting

### Common Issues

#### 1. Geyser Connection Failed

```
Error: Failed to connect to Geyser
```

**Solution**:
- Check Geyser endpoint availability
- Verify network connectivity
- Try different public endpoints

#### 2. Redis Connection Refused

```
Error: Could not connect to Redis
```

**Solution**:
- Ensure Redis is running: `redis-cli ping`
- Check Redis configuration
- Verify firewall settings

#### 3. Rate Limiting Too Aggressive

```
Warning: Rate limited LargeTransaction event
```

**Solution**:
- Adjust rate limits in `task_pool_manager.py`
- Increase token bucket capacity
- Monitor metrics for optimal settings

#### 4. High Memory Usage

**Solution**:
- Adjust event filter criteria
- Reduce batch size
- Monitor Redis memory usage

### Debug Mode

Enable debug logging:

```bash
export RUST_LOG=debug
./target/release/data_consumer
```

### Health Check

Check service health:

```bash
# Health endpoint
curl http://localhost:9191/health

# Metrics
curl http://localhost:9191/metrics

# Redis connection
redis-cli ping
```

## Deployment

### Systemd Service

Create `/etc/systemd/system/data-consumer.service`:

```ini
[Unit]
Description=MojoRust Data Consumer
After=network.target redis.service

[Service]
Type=simple
User=trading
WorkingDirectory=/opt/mojorust/rust-modules
Environment=GEYSER_ENDPOINT=https://api.mainnet-beta.solana.com:443
Environment=REDIS_URL=redis://localhost:6379
Environment=METRICS_ADDR=0.0.0.0:9191
Environment=RUST_LOG=info
ExecStart=/opt/mojorust/rust-modules/target/release/data_consumer
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable data-consumer
sudo systemctl start data-consumer
```

### Docker Deployment

Build and run:

```bash
# Build
docker build -f rust-modules/Dockerfile.data-consumer -t data-consumer .

# Run
docker run -d \
  --name data-consumer \
  -p 9191:9191 \
  -e GEYSER_ENDPOINT=https://api.mainnet-beta.solana.com:443 \
  -e REDIS_URL=redis://redis:6379 \
  data-consumer
```

### Docker Compose

```yaml
version: '3.8'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  data-consumer:
    build:
      context: .
      dockerfile: rust-modules/Dockerfile.data-consumer
    ports:
      - "9191:9191"
    environment:
      - GEYSER_ENDPOINT=https://api.mainnet-beta.solana.com:443
      - REDIS_URL=redis://redis:6379
      - METRICS_ADDR=0.0.0.0:9191
    depends_on:
      - redis
    restart: unless-stopped
```

## Cost Comparison

| Data Source | Traditional Cost | Free Tier Usage | Savings |
|-------------|------------------|-----------------|---------|
| RPC Calls | $500/month | $0 | 100% |
| WebSocket APIs | $200/month | $0 | 100% |
| Market Data | $300/month | $0 | 100% |
| **Total** | **$1,000/month** | **$0** | **100%** |

## Best Practices

1. **Monitor Rate Limits**: Adjust rate limits based on your trading volume
2. **Filter Events**: Use precise filtering to reduce noise
3. **Batch Processing**: Leverage event batching for better performance
4. **Metrics Monitoring**: Track performance via Prometheus
5. **Error Handling**: Implement proper error handling and reconnection logic
6. **Resource Management**: Monitor memory and CPU usage
7. **Security**: Use SSL/TLS for Redis connections in production

## Integration Examples

### Custom Event Handler

```python
async def custom_event_handler(event_data):
    """Custom handler for specific events"""
    event_type = event_data.get('event_type')

    if event_type == 'NewTokenMint':
        token_mint = event_data.get('token_mint')
        # Perform custom analysis
        await analyze_new_token(token_mint)

    elif event_type == 'WhaleActivity':
        wallet = event_data.get('wallet')
        # Track whale movements
        await track_whale(wallet)
```

### Metrics Integration

```python
from prometheus_client import start_http_server, Counter

# Custom metrics
custom_events_total = Counter('custom_events_total', 'Total custom events', ['type'])

async def process_with_metrics(event_data):
    event_type = event_data.get('event_type')
    custom_events_total.labels(type=event_type).inc()
    # Process event
```

## Support

- **Documentation**: `/docs` directory
- **Issues**: GitHub issues
- **Community**: Discord server
- **Monitoring**: Grafana dashboards available

## Updates

- **v1.0**: Initial release with Geyser integration
- **v1.1**: Added rate limiting and batching
- **v1.2**: Enhanced metrics and monitoring
- **v1.3**: Improved error handling and reconnection

---

*For technical support or questions, refer to the main documentation or create an issue in the repository.*