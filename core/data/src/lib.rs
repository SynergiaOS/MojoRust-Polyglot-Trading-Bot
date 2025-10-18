//! MojoRust HFT Data Pipeline
//!
//! High-performance data pipeline for real-time market data processing
//! in high-frequency trading applications.

#![warn(missing_docs)]
#![warn(clippy::all)]
#![allow(dead_code)]

pub mod feeds;
pub mod processors;
pub mod storage;
pub mod cache;

// Core data structures
pub mod types;
pub mod market_data;
pub mod tick_data;
pub mod order_book;

// Utilities
pub mod utils;
pub mod metrics;

use anyhow::Result;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn, error};

/// Main data pipeline manager
pub struct DataPipeline {
    config: Arc<RwLock<PipelineConfig>>,
    feeds: Arc<FeedManager>,
    processors: Arc<ProcessorManager>,
    storage: Arc<StorageManager>,
    cache: Arc<CacheManager>,
    metrics: Arc<MetricsCollector>,
}

/// Pipeline configuration
#[derive(Debug, Clone)]
pub struct PipelineConfig {
    /// Number of processing threads
    pub processing_threads: usize,
    /// Buffer size for data channels
    pub buffer_size: usize,
    /// Enable persistence
    pub enable_persistence: bool,
    /// Cache TTL in seconds
    pub cache_ttl_seconds: u64,
    /// Maximum memory usage in MB
    pub max_memory_mb: usize,
}

impl Default for PipelineConfig {
    fn default() -> Self {
        Self {
            processing_threads: num_cpus::get(),
            buffer_size: 10000,
            enable_persistence: true,
            cache_ttl_seconds: 300,
            max_memory_mb: 4096, // 4GB
        }
    }
}

impl DataPipeline {
    /// Create new data pipeline
    pub async fn new(config: PipelineConfig) -> Result<Self> {
        info!("Initializing MojoRust HFT Data Pipeline");

        let config = Arc::new(RwLock::new(config));
        let metrics = Arc::new(MetricsCollector::new());

        let feeds = Arc::new(FeedManager::new(
            config.clone(),
            metrics.clone(),
        ).await?);

        let processors = Arc::new(ProcessorManager::new(
            config.clone(),
            metrics.clone(),
        ).await?);

        let storage = Arc::new(StorageManager::new(
            config.clone(),
            metrics.clone(),
        ).await?);

        let cache = Arc::new(CacheManager::new(
            config.clone(),
            metrics.clone(),
        ).await?);

        Ok(Self {
            config,
            feeds,
            processors,
            storage,
            cache,
            metrics,
        })
    }

    /// Start the data pipeline
    pub async fn start(&self) -> Result<()> {
        info!("Starting data pipeline");

        // Start storage layer first
        self.storage.start().await?;

        // Start cache layer
        self.cache.start().await?;

        // Start processors
        self.processors.start().await?;

        // Start feeds last
        self.feeds.start().await?;

        info!("Data pipeline started successfully");
        Ok(())
    }

    /// Stop the data pipeline
    pub async fn stop(&self) -> Result<()> {
        info!("Stopping data pipeline");

        // Stop in reverse order
        self.feeds.stop().await?;
        self.processors.stop().await?;
        self.cache.stop().await?;
        self.storage.stop().await?;

        info!("Data pipeline stopped successfully");
        Ok(())
    }

    /// Get pipeline metrics
    pub fn get_metrics(&self) -> PipelineMetrics {
        PipelineMetrics {
            feeds_active: self.feeds.active_feeds(),
            processing_rate: self.processors.processing_rate(),
            storage_health: self.storage.health_status(),
            cache_hit_rate: self.cache.hit_rate(),
            memory_usage_mb: self.metrics.memory_usage_mb(),
            uptime_seconds: self.metrics.uptime_seconds(),
        }
    }

    /// Update configuration
    pub async fn update_config(&self, new_config: PipelineConfig) -> Result<()> {
        info!("Updating pipeline configuration");
        *self.config.write().await = new_config;
        Ok(())
    }

    /// Health check
    pub async fn health_check(&self) -> HealthStatus {
        let feeds_health = self.feeds.health_check().await;
        let processors_health = self.processors.health_check().await;
        let storage_health = self.storage.health_check().await;
        let cache_health = self.cache.health_check().await;

        let overall_healthy = feeds_health.is_healthy
            && processors_health.is_healthy
            && storage_health.is_healthy
            && cache_health.is_healthy;

        HealthStatus {
            overall_healthy,
            feeds_health,
            processors_health,
            storage_health,
            cache_health,
            timestamp: chrono::Utc::now(),
        }
    }
}

/// Pipeline metrics
#[derive(Debug, Clone)]
pub struct PipelineMetrics {
    pub feeds_active: usize,
    pub processing_rate: f64,
    pub storage_health: StorageHealth,
    pub cache_hit_rate: f64,
    pub memory_usage_mb: usize,
    pub uptime_seconds: u64,
}

/// Health status
#[derive(Debug, Clone)]
pub struct HealthStatus {
    pub overall_healthy: bool,
    pub feeds_health: ComponentHealth,
    pub processors_health: ComponentHealth,
    pub storage_health: ComponentHealth,
    pub cache_health: ComponentHealth,
    pub timestamp: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
pub struct ComponentHealth {
    pub is_healthy: bool,
    pub message: String,
    pub last_check: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone)]
pub struct StorageHealth {
    pub is_connected: bool,
    pub disk_usage_percent: f64,
    pub write_rate: f64,
}

// Placeholder types for managers
pub struct FeedManager {
    // Implementation in feeds/mod.rs
}

impl FeedManager {
    async fn new(_config: Arc<RwLock<PipelineConfig>>, _metrics: Arc<MetricsCollector>) -> Result<Self> {
        Ok(Self {})
    }

    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    fn active_feeds(&self) -> usize { 0 }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct ProcessorManager {
    // Implementation in processors/mod.rs
}

impl ProcessorManager {
    async fn new(_config: Arc<RwLock<PipelineConfig>>, _metrics: Arc<MetricsCollector>) -> Result<Self> {
        Ok(Self {})
    }

    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    fn processing_rate(&self) -> f64 { 0.0 }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct StorageManager {
    // Implementation in storage/mod.rs
}

impl StorageManager {
    async fn new(_config: Arc<RwLock<PipelineConfig>>, _metrics: Arc<MetricsCollector>) -> Result<Self> {
        Ok(Self {})
    }

    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    fn health_status(&self) -> StorageHealth {
        StorageHealth {
            is_connected: true,
            disk_usage_percent: 0.0,
            write_rate: 0.0,
        }
    }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct CacheManager {
    // Implementation in cache/mod.rs
}

impl CacheManager {
    async fn new(_config: Arc<RwLock<PipelineConfig>>, _metrics: Arc<MetricsCollector>) -> Result<Self> {
        Ok(Self {})
    }

    async fn start(&self) -> Result<()> { Ok(()) }
    async fn stop(&self) -> Result<()> { Ok(()) }
    fn hit_rate(&self) -> f64 { 0.0 }
    async fn health_check(&self) -> ComponentHealth {
        ComponentHealth {
            is_healthy: true,
            message: "OK".to_string(),
            last_check: chrono::Utc::now(),
        }
    }
}

pub struct MetricsCollector {
    // Implementation in metrics/mod.rs
}

impl MetricsCollector {
    fn new() -> Self {
        Self {}
    }

    fn memory_usage_mb(&self) -> usize { 0 }
    fn uptime_seconds(&self) -> u64 { 0 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_data_pipeline_creation() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await;
        assert!(pipeline.is_ok());
    }

    #[tokio::test]
    async fn test_pipeline_lifecycle() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        // Start pipeline
        assert!(pipeline.start().await.is_ok());

        // Check health
        let health = pipeline.health_check().await;
        assert!(health.overall_healthy);

        // Stop pipeline
        assert!(pipeline.stop().await.is_ok());
    }

    #[test]
    fn test_pipeline_config() {
        let config = PipelineConfig::default();
        assert!(config.processing_threads > 0);
        assert!(config.buffer_size > 0);
        assert!(config.enable_persistence);
    }
}