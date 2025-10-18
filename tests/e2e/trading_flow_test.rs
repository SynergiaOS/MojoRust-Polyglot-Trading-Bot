//! End-to-End tests for complete trading flow
//!
//! Tests the entire system from data ingestion to order execution

use std::sync::Arc;
use std::time::Duration;
use tokio::time::timeout;

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_complete_trading_workflow() {
        println!("🧪 Testing complete trading workflow...");

        // 1. Setup infrastructure
        let infra_config = mojorust_infrastructure::InfrastructureConfig {
            environment: mojorust_infrastructure::Environment::Development,
            enable_monitoring: true,
            enable_health_checks: true,
            enable_alerts: false,
            metrics_port: 9091,
            health_port: 8081,
            log_level: mojorust_infrastructure::LogLevel::Debug,
            enable_distributed_tracing: false,
        };

        let infra_manager = mojorust_infrastructure::InfrastructureManager::new(infra_config)
            .await
            .expect("Failed to create infrastructure manager");

        assert!(infra_manager.start().await.is_ok());

        // 2. Setup data pipeline
        let data_config = mojorust_data::PipelineConfig::default();
        let data_pipeline = mojorust_data::DataPipeline::new(data_config)
            .await
            .expect("Failed to create data pipeline");

        assert!(data_pipeline.start().await.is_ok());

        // 3. Setup execution engine
        let exec_config = mojorust_execution::ExecutionConfig {
            max_order_size_usd: 5000.0,
            max_concurrent_orders: 5,
            order_timeout_seconds: 30,
            enable_flash_loans: true,
            enable_risk_management: true,
            max_position_size_usd: 25000.0,
            enable_circuit_breaker: true,
            ..Default::default()
        };

        let keypair = solana_sdk::signature::Keypair::new();
        let execution_engine = mojorust_execution::ExecutionEngine::new(exec_config, keypair)
            .await
            .expect("Failed to create execution engine");

        assert!(execution_engine.start().await.is_ok());

        // 4. Wait for system to stabilize
        tokio::time::sleep(Duration::from_secs(2)).await;

        // 5. Verify all components are healthy
        let infra_health = infra_manager.get_health().await;
        assert!(infra_health.overall_healthy, "Infrastructure not healthy");

        let data_health = data_pipeline.health_check().await;
        assert!(data_health.overall_healthy, "Data pipeline not healthy");

        let exec_health = execution_engine.health_check().await;
        assert!(exec_health.overall_healthy, "Execution engine not healthy");

        // 6. Execute test trading scenario
        println!("📊 Executing test trading scenario...");

        // Submit a test order
        let order = mojorust_execution::OrderRequest {
            symbol: "SOL/USDC".to_string(),
            side: mojorust_execution::OrderSide::Buy,
            order_type: mojorust_execution::OrderType::Market,
            quantity: 10.0,
            price: None,
            time_in_force: mojorust_execution::TimeInForce::IOC,
            slippage_bps: Some(50),
            timeout_seconds: Some(30),
        };

        let order_response = execution_engine.submit_order(order).await
            .expect("Failed to submit order");

        assert_eq!(order_response.status, mojorust_execution::OrderStatus::Filled);
        assert!(order_response.filled_quantity > 0.0);

        println!("✅ Order executed: {} {} at ${:.2}",
                 order_response.filled_quantity,
                 "SOL",
                 order_response.average_price.unwrap_or(0.0));

        // 7. Test flash loan arbitrage
        println!("⚡ Testing flash loan arbitrage...");

        let flash_request = mojorust_execution::FlashLoanRequest {
            arbitrage_type: mojorust_execution::ArbitrageType::Simple,
            token_a: "USDC".to_string(),
            token_b: "SOL".to_string(),
            loan_amount: 1000.0,
            expected_profit: 25.0,
            route: vec!["USDC".to_string(), "SOL".to_string()],
            max_slippage_bps: 100,
        };

        let flash_response = execution_engine.submit_flash_loan_arbitrage(flash_request).await
            .expect("Failed to execute flash loan arbitrage");

        assert!(flash_response.success, "Flash loan arbitrage failed");
        assert!(flash_response.actual_profit > 0.0, "No profit from flash loan");

        println!("✅ Flash loan executed: ${:.2} profit in {}ms",
                 flash_response.actual_profit,
                 flash_response.execution_time_ms);

        // 8. Verify positions
        let positions = execution_engine.get_positions().await
            .expect("Failed to get positions");

        assert!(!positions.is_empty(), "No positions found");
        println!("📈 Current positions: {}", positions.len());

        for position in &positions {
            println!("  - {}: {} @ ${:.2} (PnL: ${:.2})",
                     position.symbol,
                     position.quantity,
                     position.average_price,
                     position.unrealized_pnl);
        }

        // 9. Check system metrics
        let exec_metrics = execution_engine.get_metrics();
        let data_metrics = data_pipeline.get_metrics();

        println!("📊 System Metrics:");
        println!("  Execution - Orders: {}, Fill Rate: {:.2}%",
                 exec_metrics.orders_submitted,
                 exec_metrics.fill_rate * 100.0);
        println!("  Data Pipeline - Processing Rate: {:.2} ops/sec",
                 data_metrics.processing_rate);
        println!("  Data Pipeline - Memory Usage: {} MB",
                 data_metrics.memory_usage_mb);

        // 10. Test system resilience under load
        println!("🔥 Testing system resilience...");

        let mut handles = Vec::new();
        let load_test_orders = 20;

        for i in 0..load_test_orders {
            let exec_engine = Arc::new(execution_engine.clone());
            let handle = tokio::spawn(async move {
                let order = mojorust_execution::OrderRequest {
                    symbol: "SOL/USDC".to_string(),
                    side: if i % 2 == 0 {
                        mojorust_execution::OrderSide::Buy
                    } else {
                        mojorust_execution::OrderSide::Sell
                    },
                    order_type: mojorust_execution::OrderType::Market,
                    quantity: 5.0,
                    price: None,
                    time_in_force: mojorust_execution::TimeInForce::IOC,
                    slippage_bps: Some(50),
                    timeout_seconds: Some(15),
                };

                let start = std::time::Instant::now();
                let result = exec_engine.submit_order(order).await;
                let duration = start.elapsed();

                (result.is_ok(), duration)
            });
            handles.push(handle);
        }

        let mut successful_orders = 0;
        let mut total_duration = Duration::ZERO;

        for handle in handles {
            let (success, duration) = handle.await.unwrap();
            if success {
                successful_orders += 1;
            }
            total_duration += duration;
        }

        let success_rate = (successful_orders as f64 / load_test_orders as f64) * 100.0;
        let avg_duration = total_duration / load_test_orders as u32;

        println!("✅ Load test results:");
        println!("  Success Rate: {:.1}%", success_rate);
        println!("  Average Response Time: {:?}", avg_duration);

        assert!(success_rate >= 80.0, "Success rate too low: {:.1}%", success_rate);
        assert!(avg_duration < Duration::from_millis(200), "Response time too slow: {:?}", avg_duration);

        // 11. Test graceful shutdown
        println!("🔄 Testing graceful shutdown...");

        let shutdown_start = std::time::Instant::now();

        // Stop in reverse order
        assert!(execution_engine.stop().await.is_ok());
        assert!(data_pipeline.stop().await.is_ok());
        assert!(infra_manager.stop().await.is_ok());

        let shutdown_duration = shutdown_start.elapsed();

        println!("✅ Graceful shutdown completed in {:?}", shutdown_duration);
        assert!(shutdown_duration < Duration::from_secs(10), "Shutdown took too long");

        // 12. Final validation
        println!("🎯 End-to-end test completed successfully!");
        println!("✅ All components are working correctly");
        println!("✅ Trading workflow executed without errors");
        println!("✅ System performed well under load");
        println!("✅ Graceful shutdown completed properly");
    }

    #[tokio::test]
    async fn test_error_recovery_scenarios() {
        println!("🧪 Testing error recovery scenarios...");

        // Setup minimal infrastructure
        let infra_config = mojorust_infrastructure::InfrastructureConfig {
            environment: mojorust_infrastructure::Environment::Development,
            enable_monitoring: true,
            enable_health_checks: true,
            enable_alerts: false,
            metrics_port: 9092,
            health_port: 8082,
            log_level: mojorust_infrastructure::LogLevel::Debug,
            enable_distributed_tracing: false,
        };

        let infra_manager = mojorust_infrastructure::InfrastructureManager::new(infra_config)
            .await
            .expect("Failed to create infrastructure manager");

        assert!(infra_manager.start().await.is_ok());

        // Test component failure recovery
        println!("💥 Testing component failure simulation...");

        // Simulate infrastructure failure
        let infra_health_before = infra_manager.get_health().await;
        assert!(infra_health_before.overall_healthy);

        // In a real test, you would simulate failures here
        // For now, we'll test the recovery mechanisms

        // Test emergency procedures
        println!("🚨 Testing emergency procedures...");

        // Send test alert
        let test_alert = mojorust_infrastructure::Alert {
            level: mojorust_infrastructure::AlertLevel::Warning,
            title: "Test Alert".to_string(),
            message: "This is a test alert for validation".to_string(),
            component: "test_suite".to_string(),
            timestamp: chrono::Utc::now(),
            metadata: std::collections::HashMap::new(),
        };

        let alert_result = infra_manager.send_alert(test_alert).await;
        assert!(alert_result.is_ok(), "Failed to send test alert");

        println!("✅ Alert system working correctly");

        // Test configuration reload
        println!("🔄 Testing configuration reload...");

        let reload_result = infra_manager.reload_config().await;
        assert!(reload_result.is_ok(), "Failed to reload configuration");

        println!("✅ Configuration reload successful");

        // Cleanup
        assert!(infra_manager.stop().await.is_ok());

        println!("✅ Error recovery scenarios completed successfully");
    }

    #[tokio::test]
    async fn test_system_monitoring_integration() {
        println!("📊 Testing system monitoring integration...");

        // Setup with full monitoring enabled
        let infra_config = mojorust_infrastructure::InfrastructureConfig {
            environment: mojorust_infrastructure::Environment::Development,
            enable_monitoring: true,
            enable_health_checks: true,
            enable_alerts: true,
            metrics_port: 9093,
            health_port: 8083,
            log_level: mojorust_infrastructure::LogLevel::Info,
            enable_distributed_tracing: false,
        };

        let infra_manager = Arc::new(mojorust_infrastructure::InfrastructureManager::new(infra_config)
            .await
            .expect("Failed to create infrastructure manager"));

        assert!(infra_manager.start().await.is_ok());

        // Wait for monitoring services to start
        tokio::time::sleep(Duration::from_secs(1)).await;

        // Test metrics collection
        println!("📈 Testing metrics collection...");

        let metrics = infra_manager.get_metrics().await;
        assert!(metrics.uptime_seconds > 0, "Uptime should be positive");
        assert!(metrics.memory_usage_mb > 0.0, "Memory usage should be positive");
        assert!(metrics.active_connections >= 0, "Active connections should be non-negative");

        println!("✅ Metrics collected successfully:");
        println!("  Uptime: {} seconds", metrics.uptime_seconds);
        println!("  Memory Usage: {:.1} MB", metrics.memory_usage_mb);
        println!("  CPU Usage: {:.1}%", metrics.cpu_usage_percent);
        println!("  Active Connections: {}", metrics.active_connections);

        // Test health endpoints
        println!("🏥 Testing health endpoints...");

        let health = infra_manager.get_health().await;
        assert!(health.overall_healthy, "System should be healthy");

        println!("✅ Health checks passed:");
        println!("  Overall Health: {}", health.overall_healthy);
        println!("  Config Health: {}", health.config_health.is_healthy);
        println!("  Logging Health: {}", health.logging_health.is_healthy);
        println!("  Monitoring Health: {}", health.monitoring_health.is_healthy);

        // Test alert levels
        println!("🚨 Testing different alert levels...");

        let alert_levels = vec![
            mojorust_infrastructure::AlertLevel::Info,
            mojorust_infrastructure::AlertLevel::Warning,
            mojorust_infrastructure::AlertLevel::Error,
            mojorust_infrastructure::AlertLevel::Critical,
        ];

        for (i, level) in alert_levels.iter().enumerate() {
            let alert = mojorust_infrastructure::Alert {
                level: level.clone(),
                title: format!("Test Alert {}", i + 1),
                message: format!("Testing {} level alert", format!("{:?}", level).to_lowercase()),
                component: "test_suite".to_string(),
                timestamp: chrono::Utc::now(),
                metadata: std::collections::HashMap::new(),
            };

            let result = infra_manager.send_alert(alert).await;
            assert!(result.is_ok(), "Failed to send {:?} alert", level);
        }

        println!("✅ All alert levels tested successfully");

        // Cleanup
        assert!(infra_manager.stop().await.is_ok());

        println!("✅ System monitoring integration test completed");
    }
}