//! Data Consumer Binary
//!
//! This binary runs the Geyser data consumer as a standalone service.
//! It connects to a Solana Geyser gRPC stream, filters events, and
//! publishes them to Redis. It also exposes /metrics and /health endpoints.

use axum::{routing::get, Router};
use mojo_trading_bot::data_consumer::{EventFilters, GeyserDataConsumer};
use solana_sdk::pubkey::Pubkey;
use std::collections::HashSet;
use std::net::SocketAddr;
use std::str::FromStr;
use tokio::sync::watch;
use tracing::{info, error};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    info!("Starting Data Consumer service...");

    // --- Configuration ---
    let geyser_endpoint = std::env::var("GEYSER_ENDPOINT")
        .expect("GEYSER_ENDPOINT must be set");
    let redis_url = std::env::var("REDIS_URL")
        .expect("REDIS_URL must be set");
    let metrics_addr = std::env::var("METRICS_ADDR").unwrap_or_else(|_| "0.0.0.0:9191".to_string());

    // --- Filters ---
    // In a real app, load this from a config file
    let filters = EventFilters {
        program_ids: HashSet::from([
            Pubkey::from_str("675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8").unwrap(), // Raydium AMM
            Pubkey::from_str("9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP").unwrap(), // Orca V1
            Pubkey::from_str("whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc").unwrap(), // Orca Whirlpool
            Pubkey::from_str("CEeNRhHxdiUHkTBLPZVYo7LPPGQh6K7JZCfHTJvuUJ7").unwrap(), // Orca V2
            Pubkey::from_str("6EF8rrecthR5Dkzon8Nwu78hRvfCKubJ14M5uBEwF6P").unwrap(), // Pump.fun
            Pubkey::from_str("TSLvdd1pWpHVjahSpsvCXUbgwsL3JAcvokwaKt1eokM").unwrap(), // Raydium CLMM
        ]),
        min_transaction_amount: 1_000_000_000, // 1 SOL
        token_whitelist: HashSet::new(),
        wallet_watchlist: HashSet::new(),
    };

    // --- Shutdown Signal ---
    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    // --- Geyser Consumer ---
    let mut consumer = GeyserDataConsumer::new(
        geyser_endpoint,
        &redis_url,
        filters,
        shutdown_rx.clone(),
    )
    .await?;

    let metrics_registry = consumer.metrics.registry.clone();

    // --- Health & Metrics Server ---
    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/metrics", get(move || metrics_handler(metrics_registry)));

    let listener = tokio::net::TcpListener::bind(&metrics_addr).await?;
    info!("Metrics and health server listening on {}", metrics_addr);
    let server_handle = tokio::spawn(axum::serve(listener, app));

    // --- Start Consuming ---
    let consumer_handle = tokio::spawn(async move {
        if let Err(e) = consumer.start_consuming().await {
            error!("Data consumer failed: {}", e);
        }
    });

    // --- Graceful Shutdown ---
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {
            info!("Received Ctrl-C, shutting down.");
        }
        _ = consumer_handle => {
            info!("Consumer task finished.");
        }
    }

    // Signal shutdown
    shutdown_tx.send(true)?;
    server_handle.abort();

    info!("Shutdown complete.");
    Ok(())
}

async fn health_handler() -> &'static str {
    "OK"
}

async fn metrics_handler(registry: prometheus::Registry) -> String {
    use prometheus::Encoder;
    let mut buffer = vec![];
    let encoder = prometheus::TextEncoder::new();
    let metric_families = registry.gather();
    encoder.encode(&metric_families, &mut buffer).unwrap();
    String::from_utf8(buffer).unwrap()
}