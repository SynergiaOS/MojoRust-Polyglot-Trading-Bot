//! Data Consumer Binary
//!
//! This binary runs the Geyser data consumer as a standalone service.
//! It connects to a Solana Geyser gRPC stream, filters events, and
//! publishes them to Redis. It also exposes /metrics and /health endpoints.

use axum::{routing::get, Router};
use mojo_trading_bot::data_consumer::{EventFilters, GeyserDataConsumer};
use mojo_trading_bot::helius_laserstream::{HeliusLaserStreamClient, LaserStreamConfig};
use solana_sdk::pubkey::Pubkey;
use std::collections::HashSet;
use std::net::SocketAddr;
use std::str::FromStr;
use tokio::sync::watch;
use tracing::{info, error, warn};
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
    let redis_url = std::env::var("REDIS_URL")
        .expect("REDIS_URL must be set");
    let metrics_addr = std::env::var("METRICS_ADDR").unwrap_or_else(|_| "0.0.0.0:9191".to_string());

    // Check if we should use Helius LaserStream or traditional Geyser
    let use_helius = std::env::var("USE_HELIUS_LASERSTREAM")
        .unwrap_or_else(|_| "false".to_string())
        .parse::<bool>()
        .unwrap_or(false);

    info!("Data source: {}", if use_helius { "Helius LaserStream" } else { "Traditional Geyser" });

    // --- Filters ---
    // In a real app, load this from a config file
    let filters = EventFilters {
        program_ids: HashSet::from([
            Pubkey::from_str("675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8").unwrap(), // Raydium
            Pubkey::from_str("9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP").unwrap(), // Orca
            Pubkey::from_str("pumpaFf22bg1d1V1S63s3vr41yB2tL3vA3b2c").unwrap(), // Pump.fun (example)
        ]),
        min_transaction_amount: 1_000_000_000, // 1 SOL
        token_whitelist: HashSet::new(),
        wallet_watchlist: HashSet::new(),
    };

    // --- Shutdown Signal ---
    let (shutdown_tx, shutdown_rx) = watch::channel(false);

    // --- Data Consumer (Geyser or Helius LaserStream) ---
    let (consumer_handle, metrics_registry) = if use_helius {
        info!("Initializing Helius LaserStream client");

        // Configure Helius LaserStream
        let helius_config = LaserStreamConfig {
            endpoint: std::env::var("HELIUS_LASERSTREAM_ENDPOINT")
                .unwrap_or_else(|_| "grpc://helius-laserstream.helius-rpc.com:443".to_string()),
            api_key: std::env::var("HELIUS_LASERSTREAM_KEY")
                .expect("HELIUS_LASERSTREAM_KEY must be set when using Helius"),
            filter_threshold: std::env::var("HELIUS_FILTER_THRESHOLD")
                .unwrap_or_else(|_| "0.99".to_string())
                .parse::<f64>()
                .unwrap_or(0.99),
            redis_url: redis_url.clone(),
            accounts: Vec::new(),
            program_ids: vec![
                "675kPX9MHTjS2zt1qfr1NYHuzeLXfQM9H24wFSUt1Mp8".to_string(), // Raydium
                "9W959DqEETiGZocYWCQPaJ6sBmUzgfxXfqGeTEdp3aQP".to_string(), // Orca
            ],
            min_transaction_amount: 1_000_000_000, // 1 SOL
            connection_timeout: 30,
            heartbeat_interval: 10,
        };

        let helius_client = HeliusLaserStreamClient::new(helius_config);

        // Create a simple metrics registry for Helius
        let registry = prometheus::Registry::new();

        let handle = tokio::spawn(async move {
            if let Err(e) = helius_client.stream_shreds().await {
                error!("Helius LaserStream failed: {}", e);
            }
        });

        (handle, registry)
    } else {
        info!("Initializing traditional Geyser consumer");

        let geyser_endpoint = std::env::var("GEYSER_ENDPOINT")
            .expect("GEYSER_ENDPOINT must be set when not using Helius");

        let mut consumer = GeyserDataConsumer::new(
            geyser_endpoint,
            &redis_url,
            filters,
            shutdown_rx.clone(),
        )
        .await?;

        let registry = consumer.metrics.registry.clone();

        let handle = tokio::spawn(async move {
            if let Err(e) = consumer.start_consuming().await {
                error!("Geyser consumer failed: {}", e);
            }
        });

        (handle, registry)
    };

    // --- Health & Metrics Server ---
    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/metrics", get(move || metrics_handler(metrics_registry)));

    let listener = tokio::net::TcpListener::bind(&metrics_addr).await?;
    info!("Metrics and health server listening on {}", metrics_addr);
    let server_handle = tokio::spawn(axum::serve(listener, app));

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