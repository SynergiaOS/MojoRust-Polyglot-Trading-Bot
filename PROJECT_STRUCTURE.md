# MojoRust Trading Bot - Project Structure

This document outlines the organized project structure for the MojoRust trading bot.

## Directory Structure

```
MojoRust/
├── src/                          # Main source code
│   ├── core/                    # Core functionality (Mojo)
│   │   ├── config.mojo          # Configuration management
│   │   ├── types.mojo           # Type definitions
│   │   ├── constants.mojo       # Constants
│   │   ├── logger.mojo          # Logging utilities
│   │   └── ...                  # Other core modules
│   │
│   ├── data/                    # Data layer (Mix of Mojo & Python)
│   │   ├── helius_client.mojo  # Helius API client (Mojo)
│   │   ├── quicknode_client.mojo # QuickNode client (Mojo)
│   │   ├── dexscreener_client.mojo # DexScreener client (Mojo)
│   │   ├── jupiter_client.mojo  # Jupiter client (Mojo)
│   │   ├── social_client.mojo   # Social analysis (Mojo with typed DTOs)
│   │   ├── honeypot_client.mojo # Honeypot detection (Mojo with typed DTOs)
│   │   ├── rpc_router.py        # RPC routing (Python)
│   │   └── ...                  # Other data modules
│   │
│   ├── engine/                  # Trading engines (Mojo)
│   │   ├── strategy_engine.mojo
│   │   ├── master_filter.mojo
│   │   ├── enhanced_context_engine.mojo
│   │   └── ...                  # Other engine modules
│   │
│   ├── risk/                    # Risk management (Mojo)
│   │   ├── risk_manager.mojo
│   │   ├── circuit_breakers.mojo
│   │   └── ...                  # Other risk modules
│   │
│   ├── monitoring/              # Monitoring & alerting (Mix)
│   │   ├── performance_analytics.mojo
│   │   ├── alert_system.mojo
│   │   ├── connection_pool_monitor.mojo
│   │   └── ...                  # Other monitoring modules
│   │
│   ├── orchestration/           # Task orchestration (Python)
│   │   └── task_pool_manager.py
│   │
│   ├── analysis/                # Analysis modules (Mojo)
│   │   ├── sentiment_analyzer.mojo
│   │   ├── pattern_recognizer.mojo
│   │   └── ...                  # Other analysis modules
│   │
│   ├── execution/               # Trade execution (Mojo)
│   │   └── execution_engine.mojo
│   │
│   ├── persistence/             # Data persistence (Mojo)
│   │   └── database_manager.mojo
│   │
│   ├── intelligence/            # AI/ML modules (Mojo)
│   │   └── data_synthesis_engine.mojo
│   │
│   └── main.mojo                # Main application entry point
│
├── python/                       # Pure Python modules
│   ├── social_intelligence_engine.py
│   ├── geyser_client.py
│   ├── jupiter_price_api.py
│   └── ...                      # Other Python-only modules
│
├── rust-modules/                 # Rust modules
│   ├── src/
│   │   ├── data_consumer/
│   │   └── lib.rs
│   ├── Cargo.toml
│   └── ...                      # Rust build files
│
├── tests/                        # Test suite
│   ├── test_rpc_router.py        # RPC router tests
│   ├── test_dto_contracts.py     # DTO contract tests
│   ├── test_task_pool_manager.py # TaskPoolManager tests
│   ├── conftest.py               # Pytest configuration
│   └── ...                      # Other test files
│
├── config/                       # Configuration files
│   ├── trading.toml              # Main configuration
│   ├── trading_production.toml   # Production configuration
│   ├── prometheus.yml            # Prometheus config
│   └── grafana/                  # Grafana dashboards
│       └── ...
│
├── scripts/                      # Utility scripts
│   ├── start_bot.sh
│   ├── deploy.sh
│   └── ...                      # Other scripts
│
├── docs/                         # Documentation
│   ├── FREE_DATA_SOURCES_GUIDE.md
│   ├── IMPLEMENTATION_ROADMAP.md
│   └── ...                      # Other documentation
│
├── systemd/                      # Systemd service files
│   └── ...
│
├── tests/                        # Test directory (moved from root)
│   └── ...                      # Test files
│
├── docker-compose.yml            # Docker Compose configuration
├── Dockerfile                    # Docker image
├── Makefile                      # Build automation
├── pytest.ini                   # Pytest configuration
├── run_tests.py                  # Test runner script
├── requirements.txt              # Python dependencies
├── .env.example                  # Environment variables template
├── .gitignore                    # Git ignore file
└── README.md                     # Project documentation
```

## Technology Organization

### Mojo Language (High-Performance Components)
- **Core**: Configuration, types, logging, constants
- **Data**: API clients, RPC routing, DTOs
- **Engine**: Trading strategies, filtering, context
- **Risk**: Risk management, circuit breakers
- **Analysis**: Sentiment, pattern recognition
- **Execution**: Trade execution logic
- **Monitoring**: Performance analytics, alerts
- **Intelligence**: ML synthesis engine

### Python (Orchestration & Integration)
- **Orchestration**: Task pool management
- **Integration**: External services, web APIs
- **Data Processing**: Social intelligence, blockchain data
- **Utilities**: Helper functions, data transformation

### Rust (Ultra-Performance Components)
- **Data Consumer**: High-throughput blockchain data
- **Performance-Critical**: CPU-intensive operations
- **System Integration**: FFI bindings, low-level optimization

## File Naming Conventions

### Mojo Files
- Use snake_case with `.mojo` extension
- Core modules: `{module_name}.mojo`
- Client modules: `{service}_client.mojo`
- Engine modules: `{purpose}_engine.mojo`

### Python Files
- Use snake_case with `.py` extension
- Orchestration: `{purpose}_manager.py`
- Integration: `{service}_integration.py`
- Utilities: `{purpose}_utils.py`

### Rust Files
- Use snake_case with `.rs` extension
- Follow Rust conventions for modules
- Use lib.rs for library interface

## Configuration Management

### Environment-Based Configuration
- **Development**: `config/trading.toml`
- **Production**: `config/trading_production.toml`
- **Testing**: Configurable via environment variables

### Feature Flags
- Enable/disable experimental features
- Control component initialization
- Environment-specific behavior

## Testing Strategy

### Unit Tests
- Test individual components in isolation
- Mock external dependencies
- Focus on business logic

### Integration Tests
- Test component interactions
- Use real configuration
- End-to-end workflows

### Performance Tests
- Benchmark critical paths
- Load testing for data pipelines
- Memory usage validation

## Deployment Architecture

### Container-based Deployment
- Multi-stage Docker builds
- Docker Compose for local development
- Kubernetes for production (optional)

### Service Architecture
- Microservices for scalability
- Health checks and monitoring
- Graceful shutdown handling

## Development Workflow

### Code Organization
1. **New Features**: Start in appropriate directory
2. **Refactoring**: Maintain existing structure
3. **Testing**: Add tests for new functionality
4. **Documentation**: Update relevant docs

### Quality Assurance
1. **Linting**: Code style enforcement
2. **Type Checking**: Static analysis
3. **Testing**: Comprehensive test coverage
4. **Review**: Peer review process

## Monitoring & Observability

### Metrics Collection
- Prometheus-compatible metrics
- Performance analytics
- Error tracking

### Logging
- Structured logging with JSON format
- Multiple log levels
- Centralized log aggregation

### Health Checks
- Component health monitoring
- Dependency health checks
- Automated alerting