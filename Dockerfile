# =============================================================================
# Multi-stage Dockerfile for AI-Powered Memecoin Trading Bot
# =============================================================================
# IMPORTANT: Mojo Binary Build Required
# =============================================================================
# Mojo requires Modular authentication and cannot be built in Docker without credentials.
# Build the Mojo binary locally first:
#   mojo build src/main.mojo -o trading-bot
# Then build Docker image:
#   docker build -t trading-bot:latest .
# =============================================================================
# Build stages:
# 1. rust-builder - Compile Rust security modules (works without auth)
# 2. runtime - Minimal runtime image with compiled binaries (uses pre-built Mojo)

# =============================================================================
# Stage 1: Rust Builder
# =============================================================================
FROM rust:1.75-slim as rust-builder

# Set working directory
WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    pkg-config \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy Rust workspace configuration
COPY Cargo.toml Cargo.lock ./
COPY rust-modules/ ./rust-modules/

# Build Rust dependencies first (for layer caching)
RUN cargo build --workspace --release

# Copy Rust source code
COPY rust-modules/src/ ./rust-modules/src/

# Build Rust modules with optimizations
RUN cargo build --workspace --release

# =============================================================================
# Stage 2: Mojo Builder - DISABLED
# =============================================================================
# Mojo installation requires Modular authentication
# Build Mojo components locally and copy binaries instead
# FROM ubuntu:22.04 as mojo-builder
# ... (entire mojo-builder stage commented out due to auth requirements)

# =============================================================================
# Stage 2: Runtime
# =============================================================================
FROM ubuntu:22.04 as runtime

# Set labels for metadata
LABEL maintainer="Trading Bot Team"
LABEL description="AI-powered memecoin trading bot for Solana"
LABEL version="0.1.0"

# Set working directory
WORKDIR /app

# Install only runtime dependencies
RUN apt-get update && apt-get install -y \
    libssl3 \
    ca-certificates \
    curl \
    wget \
    python3-minimal \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Create non-root user for security
RUN groupadd -r trading && useradd -r -g trading trading

# Create necessary directories
RUN mkdir -p \
    /app/logs \
    /app/secrets \
    /app/cache \
    /app/data \
    && chown -R trading:trading /app

# Copy pre-built Mojo binary (built locally with Modular auth)
COPY ./trading-bot /app/trading-bot
# Ensure correct ownership and execute permissions for non-root runtime user
RUN chown trading:trading /app/trading-bot && chmod 0755 /app/trading-bot

# Copy compiled Rust libraries from builder
COPY --from=rust-builder /build/rust-modules/target/release/*.so /app/lib/

# Copy configuration files
COPY config/ ./config/
# Do NOT embed example env into runtime image; runtime env should be supplied by Compose or env files

# Set library path
ENV LD_LIBRARY_PATH=/app/lib:$LD_LIBRARY_PATH

# Set environment variables
ENV RUST_LOG=info
ENV LOG_LEVEL=info
ENV TRADING_ENV=production

# Expose monitoring ports
EXPOSE 9091 8082

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8082/health || exit 1

# Copy startup script
COPY scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Switch to non-root user
USER trading

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command: expand environment variables at container runtime; default to paper
# Using shell form so ${EXECUTION_MODE} is expanded at container start
CMD ./trading-bot --mode "${EXECUTION_MODE:-paper}" --capital "${INITIAL_CAPITAL:-1.0}"

# =============================================================================
# Development Target
# =============================================================================
FROM runtime as development

# Switch back to root for development setup
USER root

# Install development tools
RUN apt-get update && apt-get install -y \
    vim \
    htop \
    strace \
    lsof \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Install additional debugging tools
RUN apt-get update && apt-get install -y \
    gdb \
    valgrind \
    && rm -rf /var/lib/apt/lists/*

# Copy source code for development (read-only)
COPY --chown=trading:trading src/ /app/src/
COPY --chown=trading:trading rust-modules/ /app/rust-modules/
COPY --chown=trading:trading tests/ /app/tests/
COPY --chown=trading:trading scripts/ /app/scripts/

# Override environment for development
ENV LOG_LEVEL=debug
ENV TRADING_ENV=development
ENV MOCK_APIS=true
ENV VERBOSE_LOGGING=true

# Switch back to trading user
USER trading

# Development command (watch mode)
CMD ["./trading-bot", "--mode", "paper", "--capital", "1.0", "--watch"]

# =============================================================================
# Test Target
# =============================================================================
FROM development as test

# Install test dependencies
USER root
RUN apt-get update && apt-get install -y \
    python3-pytest \
    && rm -rf /var/lib/apt/lists/*

USER trading

# Test command
CMD ["./trading-bot", "--mode", "test", "--run-all-tests"]

# =============================================================================
# Build Targets Summary
# =============================================================================
#
# Prerequisites for building:
#   1. Install Mojo locally: https://docs.modular.com/mojo/get-started
#   2. Build Mojo binary: mojo build src/main.mojo -o trading-bot
#   3. Build Docker image: docker build -t trading-bot:latest .
#
# Development build:
#   docker build --target development -t trading-bot:dev .
#
# Production build:
#   docker build --target runtime -t trading-bot:latest .
#
# Test build:
#   docker build --target test -t trading-bot:test .
#
# Run commands:
#   Development: docker run -p 9091:9090 -p 8082:8082 trading-bot:dev
#   Production:  docker run -p 9091:9090 -p 8082:8082 trading-bot:latest
#   Tests:       docker run trading-bot:test
#
# Build with BuildKit for parallel builds:
#   DOCKER_BUILDKIT=1 docker build --target runtime -t trading-bot:latest .