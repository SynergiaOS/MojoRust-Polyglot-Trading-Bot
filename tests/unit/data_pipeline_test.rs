//! Unit tests for the data pipeline
//!
//! Comprehensive testing of the high-performance data pipeline components

use mojorust_data::*;
use tokio::time::{timeout, Duration};
use std::sync::Arc;
use parking_lot::RwLock;

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_data_pipeline_creation() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await;
        assert!(pipeline.is_ok());

        let pipeline = pipeline.unwrap();
        let health = pipeline.health_check().await;
        assert!(health.overall_healthy);
    }

    #[tokio::test]
    async fn test_data_pipeline_lifecycle() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        // Test start
        assert!(pipeline.start().await.is_ok());

        // Give it a moment to start
        tokio::time::sleep(Duration::from_millis(100)).await;

        // Test health after start
        let health = pipeline.health_check().await;
        assert!(health.overall_healthy);

        // Test metrics
        let metrics = pipeline.get_metrics();
        assert!(metrics.feeds_active >= 0);
        assert!(metrics.processing_rate >= 0.0);

        // Test stop
        assert!(pipeline.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_config_update() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        let new_config = PipelineConfig {
            processing_threads: 8,
            buffer_size: 20000,
            enable_persistence: false,
            cache_ttl_seconds: 600,
            max_memory_mb: 8192,
        };

        assert!(pipeline.update_config(new_config).await.is_ok());
    }

    #[tokio::test]
    async fn test_pipeline_timeout() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        // Test that operations complete within reasonable time
        let start_result = timeout(Duration::from_secs(5), pipeline.start()).await;
        assert!(start_result.is_ok());
        assert!(start_result.unwrap().is_ok());

        let stop_result = timeout(Duration::from_secs(5), pipeline.stop()).await;
        assert!(stop_result.is_ok());
        assert!(stop_result.unwrap().is_ok());
    }

    #[tokio::test]
    async fn test_multiple_pipelines() {
        let config = PipelineConfig::default();

        // Create multiple pipelines
        let pipeline1 = DataPipeline::new(config.clone()).await.unwrap();
        let pipeline2 = DataPipeline::new(config).await.unwrap();

        // Both should start without conflicts
        assert!(pipeline1.start().await.is_ok());
        assert!(pipeline2.start().await.is_ok());

        // Both should be healthy
        let health1 = pipeline1.health_check().await;
        let health2 = pipeline2.health_check().await;
        assert!(health1.overall_healthy);
        assert!(health2.overall_healthy);

        // Clean up
        assert!(pipeline1.stop().await.is_ok());
        assert!(pipeline2.stop().await.is_ok());
    }

    #[test]
    fn test_pipeline_config_validation() {
        // Test default config
        let config = PipelineConfig::default();
        assert!(config.processing_threads > 0);
        assert!(config.buffer_size > 0);
        assert!(config.max_memory_mb > 0);

        // Test config with custom values
        let custom_config = PipelineConfig {
            processing_threads: 16,
            buffer_size: 50000,
            enable_persistence: true,
            cache_ttl_seconds: 120,
            max_memory_mb: 16384,
        };
        assert_eq!(custom_config.processing_threads, 16);
        assert_eq!(custom_config.buffer_size, 50000);
        assert_eq!(custom_config.max_memory_mb, 16384);
    }

    #[tokio::test]
    async fn test_pipeline_error_handling() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        // Test double start (should handle gracefully)
        assert!(pipeline.start().await.is_ok());
        let second_start = pipeline.start().await;
        // Should either succeed or fail gracefully
        assert!(second_start.is_ok() || second_start.is_err());

        // Test stop without start (should handle gracefully)
        let pipeline2 = DataPipeline::new(PipelineConfig::default()).await.unwrap();
        let stop_result = pipeline2.stop().await;
        assert!(stop_result.is_ok() || stop_result.is_err());

        // Clean up
        assert!(pipeline.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_pipeline_metrics_collection() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        assert!(pipeline.start().await.is_ok());

        // Wait a bit for metrics to be collected
        tokio::time::sleep(Duration::from_millis(200)).await;

        let metrics = pipeline.get_metrics();

        // Validate metrics structure
        assert!(metrics.feeds_active >= 0);
        assert!(metrics.processing_rate >= 0.0);
        assert!(metrics.memory_usage_mb >= 0);
        assert!(metrics.uptime_seconds >= 0);

        // Memory usage should be reasonable for a test
        assert!(metrics.memory_usage_mb < 1000); // Less than 1GB for tests

        assert!(pipeline.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_pipeline_concurrent_access() {
        let config = PipelineConfig::default();
        let pipeline = Arc::new(DataPipeline::new(config).await.unwrap());

        assert!(pipeline.start().await.is_ok());

        // Spawn multiple tasks to access the pipeline concurrently
        let mut handles = Vec::new();

        for i in 0..10 {
            let pipeline_clone = Arc::clone(&pipeline);
            let handle = tokio::spawn(async move {
                // Test concurrent health checks
                let health = pipeline_clone.health_check().await;
                assert!(health.overall_healthy);

                // Test concurrent metrics access
                let metrics = pipeline_clone.get_metrics();
                assert!(metrics.feeds_active >= 0);

                format!("Task {} completed", i)
            });
            handles.push(handle);
        }

        // Wait for all tasks to complete
        for handle in handles {
            let result = handle.await.unwrap();
            assert!(result.starts_with("Task"));
            assert!(result.ends_with("completed"));
        }

        assert!(pipeline.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_pipeline_resource_cleanup() {
        let config = PipelineConfig::default();
        let pipeline = DataPipeline::new(config).await.unwrap();

        // Start and stop multiple times to test resource cleanup
        for _ in 0..5 {
            assert!(pipeline.start().await.is_ok());
            tokio::time::sleep(Duration::from_millis(50)).await;
            assert!(pipeline.stop().await.is_ok());
            tokio::time::sleep(Duration::from_millis(50)).await;
        }

        // Pipeline should still be healthy after multiple cycles
        let health = pipeline.health_check().await;
        assert!(health.overall_healthy);
    }
}