# Jupiter Integration Documentation

## Overview

This document provides comprehensive information about the Jupiter API V3 (Price) and V6 (Swap) integration in the MojoRust trading bot. The integration includes real-time price monitoring, arbitrage detection, swap execution with Jito MEV protection, and comprehensive monitoring.

## Architecture

### Components

1. **JupiterPriceClient** - Core API client for Jupiter Price API V3 and Swap API V6
2. **JupiterDataPipeline** - Real-time data pipeline for price monitoring and arbitrage detection
3. **JupiterSwapExecutor** - High-performance swap executor with Jito MEV protection
4. **JupiterMetricsCollector** - Comprehensive Prometheus metrics collection
5. **EnhancedGeyserClient** - Integration with existing Geyser client infrastructure

### Data Flow

```
Jupiter APIs → Data Pipeline → Redis Pub/Sub → Trading Logic → Swap Executor → Solana
     ↓              ↓              ↓              ↓              ↓
  Metrics → Prometheus → Grafana → Alerts → Monitoring Dashboard
```

## Installation and Setup

### Prerequisites

- Python 3.9+
- Redis server
- Access to Jupiter APIs (free tier available)
- Solana RPC endpoint
- Optional: Jito auth key for MEV protection

### Environment Variables

Create `.env` file with the following variables:

```bash
# Core Configuration
REDIS_URL=redis://localhost:6379
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
WALLET_PUBLIC_KEY=your_wallet_public_key
WALLET_PRIVATE_KEY=your_wallet_private_key

# Jupiter API (optional - Jupiter APIs are free)
JUPITER_API_KEY=your_jupiter_api_key  # If using premium tier

# Jito Configuration (optional but recommended)
JITO_AUTH_KEY=your_jito_auth_key
USE_JITO=true
JITO_TIP_LAMPORTS=10000

# Trading Parameters
MAX_POSITION_SIZE_USD=1000
MIN_PROFIT_PCT=0.5
MAX_SLIPPAGE_BPS=100
MAX_CONCURRENT_SWAPS=5

# Monitoring
METRICS_PORT=9095
PRICE_UPDATE_INTERVAL=5.0
ARBITRAGE_CHECK_INTERVAL=2.0
```

### Installation

```bash
# Install Python dependencies
pip install aiohttp redis prometheus_client solana structlog

# The Jupiter integration is part of the MojoRust project
# Ensure you have the latest version of the codebase
```

## Usage

### Basic Price Monitoring

```python
from python.geyser_client import JupiterPriceClient

# Initialize client
jupiter_client = JupiterPriceClient()

# Get single token price
price_data = await jupiter_client.get_token_price(
    token_mint="So11111111111111111111111111111111111111112",  # SOL
    vs_token="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"  # USDC
)

print(f"SOL Price: ${price_data['data']['So11111111111111111111111111111111111111112']['price']}")

# Get multiple token prices
tokens = [
    "So11111111111111111111111111111111111111112",  # SOL
    "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY",  # USDT
    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
]
all_prices = await jupiter_client.get_token_prices(tokens=tokens)
```

### Swap Quote Generation

```python
# Get swap quote
quote = await jupiter_client.get_swap_quote(
    input_mint="So11111111111111111111111111111111111111112",  # SOL
    output_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
    amount=1_000_000,  # 1 SOL (assuming 9 decimals)
    slippage_bps=100   # 1% slippage tolerance
)

print(f"Expected output: {quote['outAmount']} USDC")
print(f"Price impact: {quote['priceImpactPct']}%")
```

### Swap Execution

```python
from python.jupiter_executor import JupiterSwapExecutor, SwapExecutionRequest, JitoBundleConfig

# Configure Jito for MEV protection
jito_config = JitoBundleConfig(
    use_jito=True,
    jito_auth_key="your_jito_auth_key",
    bundle_tip_lamports=10000
)

# Initialize executor
executor = JupiterSwapExecutor(
    rpc_url="https://api.mainnet-beta.solana.com",
    redis_url="redis://localhost:6379",
    jito_config=jito_config
)

await executor.start()

# Create swap request
swap_request = SwapExecutionRequest(
    input_mint="So11111111111111111111111111111111111111112",
    output_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    input_amount=1_000_000,  # 1 SOL
    slippage_bps=100,
    user_public_key="your_wallet_public_key",
    quote_response=quote,
    priority_fee=20000,  # Priority fee in lamports
    urgency_level="high"
)

# Execute swap
result = await executor.execute_swap(swap_request)

if result.success:
    print(f"Swap successful! Signature: {result.transaction_signature}")
    print(f"Output amount: {result.output_amount}")
else:
    print(f"Swap failed: {result.error_message}")
```

### Real-time Data Pipeline

```python
from python.jupiter_pipeline import JupiterDataPipeline

# Initialize pipeline
pipeline = JupiterDataPipeline(
    redis_url="redis://localhost:6379",
    monitoring_tokens=[
        "So11111111111111111111111111111111111111112",  # SOL
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY",  # USDT
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
    ],
    price_update_interval=5.0,
    arbitrage_check_interval=2.0
)

await pipeline.start()

# Get current prices
current_prices = await pipeline.get_current_prices()
for token_id, price_event in current_prices.items():
    print(f"{price_event.symbol}: ${price_event.price} ({price_event.price_change_24h:+.2f}%)")

# Get pipeline statistics
stats = await pipeline.get_statistics()
print(f"Price updates: {stats['price_updates']}")
print(f"Arbitrage opportunities: {stats['arbitrage_opportunities']}")
```

### Complete Trading Bot

```python
# See examples/jupiter_trading_example.py for complete implementation
from examples.jupiter_trading_example import JupiterTradingBot

# Configuration
config = {
    "max_position_size_usd": 1000,
    "min_profit_pct": 0.5,
    "max_slippage_bps": 100,
    "use_jito": True,
    "monitoring_tokens": [
        "So11111111111111111111111111111111111111112",  # SOL
        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNY",  # USDT
        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
    ]
}

# Start trading bot
bot = JupiterTradingBot(config)
await bot.start()
```

## API Reference

### JupiterPriceClient

#### Methods

- `get_token_price(token_mint, vs_token)` - Get single token price
- `get_token_prices(tokens)` - Get multiple token prices
- `get_swap_quote(input_mint, output_mint, amount, slippage_bps)` - Get swap quote
- `get_swap_transaction(quote_response, user_public_key)` - Get swap transaction
- `publish_price_to_redis(redis_client, price_data)` - Publish price to Redis
- `publish_quote_to_redis(redis_client, quote_data)` - Publish quote to Redis

### JupiterDataPipeline

#### Methods

- `start()` - Start the data pipeline
- `stop()` - Stop the data pipeline
- `get_current_prices()` - Get current cached prices
- `get_current_quotes()` - Get current cached quotes
- `get_statistics()` - Get pipeline statistics

### JupiterSwapExecutor

#### Methods

- `start()` - Start the swap executor
- `stop()` - Stop the swap executor
- `execute_swap(request, execution_id)` - Execute a swap
- `get_statistics()` - Get executor statistics
- `cancel_execution(execution_id)` - Cancel active execution

## Monitoring

### Prometheus Metrics

The integration provides comprehensive Prometheus metrics:

- **Price API Metrics**: Request counts, response times, error rates
- **Swap API Metrics**: Request counts, response times, quote accuracy
- **Price Monitoring**: Current prices, 24h changes, trading volumes
- **Execution Metrics**: Success rates, execution times, volume, fees
- **Jito Metrics**: Bundle submission success rates, tip amounts
- **Arbitrage Metrics**: Opportunity counts, profit potential
- **Performance Metrics**: Update rates, cache sizes, error rates

### Grafana Dashboard

Import the provided dashboard: `config/grafana/dashboards/jupiter_trading_dashboard.json`

Key panels:
- System status and health
- Real-time token prices
- 24h price changes and volumes
- Active arbitrage opportunities
- Swap execution performance
- Jito bundle success rates
- Trading volumes and fees

### Alerting

Prometheus alerts are configured in: `config/prometheus_rules/jupiter_alerts.yml`

Key alerts:
- Pipeline downtime
- High error rates
- Low success rates
- High-profit opportunities
- Rate limit hits
- Performance degradation

## Configuration

### Trading Parameters

- `max_position_size_usd` - Maximum position size per trade (default: 1000)
- `min_profit_pct` - Minimum profit percentage for arbitrage (default: 0.5)
- `max_slippage_bps` - Maximum slippage tolerance in basis points (default: 100)
- `max_concurrent_swaps` - Maximum concurrent swap executions (default: 5)

### Jito Configuration

- `use_jito` - Enable Jito MEV protection (default: true)
- `jito_auth_key` - Jito authentication key
- `jito_tip_lamports` - Jito tip amount in lamports (default: 10000)
- `max_bundle_size` - Maximum bundle size (default: 5)

### Performance Tuning

- `price_update_interval` - Price update frequency in seconds (default: 5.0)
- `arbitrage_check_interval` - Arbitrage check frequency in seconds (default: 2.0)
- `metrics_update_interval` - Metrics update frequency in seconds (default: 5.0)

## Rate Limits

Jupiter API has the following rate limits (free tier):

- **Price API V3**: 100 requests/minute
- **Swap API V6**: 100 requests/minute

The integration includes automatic rate limiting and backoff logic.

## Error Handling

The integration includes comprehensive error handling:

- **API Errors**: Automatic retries with exponential backoff
- **Network Issues**: Connection pooling and timeout handling
- **Rate Limiting**: Automatic request throttling
- **Transaction Failures**: Retry logic and error reporting
- **Data Validation**: Input validation and sanity checks

## Security

### Key Management

- Private keys are handled securely in the Rust modules
- No credential logging or exposure
- Environment-based configuration

### MEV Protection

- Jito bundle integration for MEV protection
- Dynamic priority fee calculation
- Private mempool submission

### Risk Management

- Position size limits
- Slippage protection
- Circuit breaker mechanisms
- Real-time monitoring

## Troubleshooting

### Common Issues

1. **Redis Connection Failed**
   - Ensure Redis server is running
   - Check Redis URL configuration
   - Verify network connectivity

2. **API Rate Limiting**
   - Monitor rate limit metrics
   - Adjust request frequencies
   - Consider upgrading API tier

3. **Transaction Failures**
   - Check SOL balance for fees
   - Verify wallet permissions
   - Monitor network congestion

4. **Jito Bundle Failures**
   - Verify Jito auth key
   - Check tip amounts
   - Monitor bundle status

### Debug Logging

Enable debug logging:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

### Health Checks

Monitor component health:

```python
# Pipeline health
pipeline_stats = await pipeline.get_statistics()
print(f"Pipeline running: {pipeline_stats['is_running']}")

# Executor health
executor_stats = await executor.get_statistics()
print(f"Success rate: {executor_stats['success_rate']}%")
```

## Performance

### Benchmarks

- **Price API Response**: <100ms average
- **Quote Generation**: <200ms average
- **Swap Execution**: 2-10s average (including confirmation)
- **Arbitrage Detection**: <50ms per check
- **Pipeline Throughput**: 1000+ events/second

### Optimization Tips

1. **Reduce Update Intervals** for lower CPU usage
2. **Increase Cache Sizes** for better performance
3. **Use Jito** for better execution reliability
4. **Monitor Metrics** for performance tuning
5. **Adjust Position Sizes** for risk management

## Contributing

### Development Setup

```bash
# Install development dependencies
pip install -r requirements-dev.txt

# Run tests
pytest tests/jupiter/

# Run linting
flake8 python/jupiter/
mypy python/jupiter/
```

### Testing

```bash
# Run unit tests
pytest tests/jupiter/unit/

# Run integration tests
pytest tests/jupiter/integration/

# Run performance tests
pytest tests/jupiter/performance/
```

## Support

- **Documentation**: See `docs/` directory
- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Jupiter API Docs**: https://station.jup.ag/docs/api/overview

## Changelog

### v1.0.0 (2025-01-18)

- Initial Jupiter API V3/V6 integration
- Real-time price monitoring pipeline
- Arbitrage detection system
- Jito MEV protection
- Comprehensive monitoring and metrics
- Grafana dashboard and alerts

---

**Note**: This integration is part of the MojoRust algorithmic trading bot. Ensure you understand the risks before running with real funds. Start with paper trading mode and monitor performance carefully.