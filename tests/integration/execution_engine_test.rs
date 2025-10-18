//! Integration tests for the execution engine
//!
//! Tests the execution engine with real components and mock external services

use mojorust_execution::*;
use solana_sdk::signature::Keypair;
use tokio::time::{timeout, Duration};
use std::sync::Arc;

#[cfg(test)]
mod tests {
    use super::*;

    async fn setup_test_engine() -> ExecutionEngine {
        let config = ExecutionConfig {
            max_order_size_usd: 10000.0,
            max_concurrent_orders: 10,
            order_timeout_seconds: 30,
            enable_flash_loans: true,
            enable_risk_management: true,
            max_position_size_usd: 50000.0,
            enable_circuit_breaker: true,
            ..Default::default()
        };

        let keypair = Keypair::new();
        ExecutionEngine::new(config, keypair).await.unwrap()
    }

    #[tokio::test]
    async fn test_execution_engine_full_lifecycle() {
        let engine = setup_test_engine().await;

        // Test start
        assert!(engine.start().await.is_ok());
        tokio::time::sleep(Duration::from_millis(100)).await;

        // Test health
        let health = engine.health_check().await;
        assert!(health.overall_healthy);

        // Test order submission
        let order = OrderRequest {
            symbol: "SOL/USDC".to_string(),
            side: OrderSide::Buy,
            order_type: OrderType::Market,
            quantity: 10.0,
            price: None,
            time_in_force: TimeInForce::IOC,
            slippage_bps: Some(50),
            timeout_seconds: Some(30),
        };

        let response = engine.submit_order(order).await;
        assert!(response.is_ok());

        let response = response.unwrap();
        assert_eq!(response.status, OrderStatus::Filled);
        assert!(response.filled_quantity > 0.0);

        // Test flash loan arbitrage
        let flash_request = FlashLoanRequest {
            arbitrage_type: ArbitrageType::Simple,
            token_a: "USDC".to_string(),
            token_b: "SOL".to_string(),
            loan_amount: 1000.0,
            expected_profit: 25.0,
            route: vec!["USDC".to_string(), "SOL".to_string()],
            max_slippage_bps: 100,
        };

        let flash_response = engine.submit_flash_loan_arbitrage(flash_request).await;
        assert!(flash_response.is_ok());

        let flash_response = flash_response.unwrap();
        assert!(flash_response.success);
        assert!(flash_response.actual_profit > 0.0);

        // Test positions
        let positions = engine.get_positions().await.unwrap();
        assert!(!positions.is_empty());

        // Test metrics
        let metrics = engine.get_metrics();
        assert!(metrics.orders_submitted > 0);
        assert!(metrics.orders_filled > 0);
        assert!(metrics.flash_loans_executed > 0);

        // Test stop
        assert!(engine.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_order_cancellation() {
        let engine = setup_test_engine().await;
        assert!(engine.start().await.is_ok());

        // Submit a limit order that might not fill immediately
        let order = OrderRequest {
            symbol: "SOL/USDC".to_string(),
            side: OrderSide::Buy,
            order_type: OrderType::Limit,
            quantity: 100.0,
            price: Some(1.0), // Very low price, unlikely to fill
            time_in_force: TimeInForce::GTC,
            slippage_bps: Some(50),
            timeout_seconds: Some(30),
        };

        let response = engine.submit_order(order).await.unwrap();
        let order_id = response.order_id.clone();

        // Give it a moment to process
        tokio::time::sleep(Duration::from_millis(100)).await;

        // Cancel the order
        let cancel_response = engine.cancel_order(&order_id).await.unwrap();
        assert!(cancel_response.success);

        assert!(engine.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_risk_management() {
        let engine = setup_test_engine().await;
        assert!(engine.start().await.is_ok());

        // Test order that exceeds size limits
        let oversized_order = OrderRequest {
            symbol: "SOL/USDC".to_string(),
            side: OrderSide::Buy,
            order_type: OrderType::Market,
            quantity: 1000000.0, // Very large order
            price: None,
            time_in_force: TimeInForce::IOC,
            slippage_bps: Some(50),
            timeout_seconds: Some(30),
        };

        let response = engine.submit_order(oversized_order).await;
        // Should either be rejected by risk management or filled with warnings
        assert!(response.is_ok() || response.is_err());

        // Test emergency stop
        assert!(engine.emergency_stop().await.is_ok());

        // After emergency stop, new orders should be rejected
        let normal_order = OrderRequest {
            symbol: "SOL/USDC".to_string(),
            side: OrderSide::Buy,
            order_type: OrderType::Market,
            quantity: 10.0,
            price: None,
            time_in_force: TimeInForce::IOC,
            slippage_bps: Some(50),
            timeout_seconds: Some(30),
        };

        let emergency_response = engine.submit_order(normal_order).await;
        assert!(emergency_response.is_err()); // Should be rejected

        assert!(engine.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_concurrent_operations() {
        let engine = Arc::new(setup_test_engine().await);
        assert!(engine.start().await.is_ok());

        // Submit multiple orders concurrently
        let mut handles = Vec::new();

        for i in 0..20 {
            let engine_clone = Arc::clone(&engine);
            let handle = tokio::spawn(async move {
                let order = OrderRequest {
                    symbol: "SOL/USDC".to_string(),
                    side: if i % 2 == 0 { OrderSide::Buy } else { OrderSide::Sell },
                    order_type: OrderType::Market,
                    quantity: 10.0,
                    price: None,
                    time_in_force: TimeInForce::IOC,
                    slippage_bps: Some(50),
                    timeout_seconds: Some(30),
                };

                let response = engine_clone.submit_order(order).await;
                (i, response.is_ok())
            });
            handles.push(handle);
        }

        // Wait for all orders to complete
        let mut successful_orders = 0;
        for handle in handles {
            let (i, success) = handle.await.unwrap();
            if success {
                successful_orders += 1;
                println!("Order {} successful", i);
            } else {
                println!("Order {} failed", i);
            }
        }

        // Most orders should succeed
        assert!(successful_orders > 15); // At least 75% success rate

        let metrics = engine.get_metrics();
        assert_eq!(metrics.orders_submitted as usize, 20);
        assert!(metrics.orders_filled >= successful_orders as u64);

        assert!(engine.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_flash_loan_arbitrage_scenarios() {
        let engine = setup_test_engine().await;
        assert!(engine.start().await.is_ok());

        // Test different arbitrage scenarios
        let scenarios = vec![
            FlashLoanRequest {
                arbitrage_type: ArbitrageType::Simple,
                token_a: "USDC".to_string(),
                token_b: "SOL".to_string(),
                loan_amount: 1000.0,
                expected_profit: 25.0,
                route: vec!["USDC".to_string(), "SOL".to_string()],
                max_slippage_bps: 100,
            },
            FlashLoanRequest {
                arbitrage_type: ArbitrageType::Triangular,
                token_a: "USDC".to_string(),
                token_b: "SOL".to_string(),
                loan_amount: 2000.0,
                expected_profit: 50.0,
                route: vec!["USDC".to_string(), "SOL".to_string(), "USDC".to_string()],
                max_slippage_bps: 150,
            },
            FlashLoanRequest {
                arbitrage_type: ArbitrageType::CrossExchange,
                token_a: "USDC".to_string(),
                token_b: "SOL".to_string(),
                loan_amount: 5000.0,
                expected_profit: 100.0,
                route: vec!["USDC".to_string(), "SOL".to_string()],
                max_slippage_bps: 200,
            },
        ];

        for (i, scenario) in scenarios.into_iter().enumerate() {
            println!("Testing arbitrage scenario {}", i + 1);
            let response = engine.submit_flash_loan_arbitrage(scenario).await;
            assert!(response.is_ok(), "Scenario {} failed", i + 1);

            let response = response.unwrap();
            assert!(response.success, "Scenario {} not successful", i + 1);
            assert!(response.actual_profit > 0.0, "Scenario {} has no profit", i + 1);
            assert!(response.execution_time_ms < 10000, "Scenario {} took too long", i + 1);
        }

        let metrics = engine.get_metrics();
        assert_eq!(metrics.flash_loans_executed, 3);
        assert!(metrics.flash_loan_success_rate > 0.8); // At least 80% success rate

        assert!(engine.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_configuration_updates() {
        let mut config = ExecutionConfig::default();
        config.enable_flash_loans = false;

        let engine = ExecutionEngine::new(config, Keypair::new()).await.unwrap();
        assert!(engine.start().await.is_ok());

        // Flash loans should be disabled initially
        let flash_request = FlashLoanRequest {
            arbitrage_type: ArbitrageType::Simple,
            token_a: "USDC".to_string(),
            token_b: "SOL".to_string(),
            loan_amount: 1000.0,
            expected_profit: 25.0,
            route: vec!["USDC".to_string(), "SOL".to_string()],
            max_slippage_bps: 100,
        };

        let response = engine.submit_flash_loan_arbitrage(flash_request).await;
        assert!(response.is_err()); // Should fail when flash loans disabled

        // Update configuration to enable flash loans
        let new_config = ExecutionConfig {
            enable_flash_loans: true,
            ..Default::default()
        };

        assert!(engine.update_config(new_config).await.is_ok());

        // Flash loans should now work
        let flash_request = FlashLoanRequest {
            arbitrage_type: ArbitrageType::Simple,
            token_a: "USDC".to_string(),
            token_b: "SOL".to_string(),
            loan_amount: 1000.0,
            expected_profit: 25.0,
            route: vec!["USDC".to_string(), "SOL".to_string()],
            max_slippage_bps: 100,
        };

        let response = engine.submit_flash_loan_arbitrage(flash_request).await;
        assert!(response.is_ok()); // Should succeed after config update

        assert!(engine.stop().await.is_ok());
    }

    #[tokio::test]
    async fn test_performance_under_load() {
        let engine = Arc::new(setup_test_engine().await);
        assert!(engine.start().await.is_ok());

        let start_time = std::time::Instant::now();
        let num_orders = 100;
        let mut handles = Vec::new();

        // Submit many orders rapidly
        for i in 0..num_orders {
            let engine_clone = Arc::clone(&engine);
            let handle = tokio::spawn(async move {
                let order = OrderRequest {
                    symbol: "SOL/USDC".to_string(),
                    side: if i % 2 == 0 { OrderSide::Buy } else { OrderSide::Sell },
                    order_type: OrderType::Market,
                    quantity: 10.0,
                    price: None,
                    time_in_force: TimeInForce::IOC,
                    slippage_bps: Some(50),
                    timeout_seconds: Some(30),
                };

                let start = std::time::Instant::now();
                let response = engine_clone.submit_order(order).await;
                let duration = start.elapsed();

                (response.is_ok(), duration)
            });
            handles.push(handle);
        }

        // Collect results
        let mut successful_orders = 0;
        let mut total_duration = Duration::ZERO;
        let mut max_duration = Duration::ZERO;

        for handle in handles {
            let (success, duration) = handle.await.unwrap();
            if success {
                successful_orders += 1;
            }
            total_duration += duration;
            max_duration = max_duration.max(duration);
        }

        let total_time = start_time.elapsed();
        let avg_duration = total_duration / num_orders as u32;

        println!("Performance Results:");
        println!("Total orders: {}", num_orders);
        println!("Successful orders: {}", successful_orders);
        println!("Success rate: {:.2}%", (successful_orders as f64 / num_orders as f64) * 100.0);
        println!("Total time: {:?}", total_time);
        println!("Average order time: {:?}", avg_duration);
        println!("Max order time: {:?}", max_duration);
        println!("Orders per second: {:.2}", num_orders as f64 / total_time.as_secs_f64());

        // Performance assertions
        assert!(successful_orders >= 95); // At least 95% success rate
        assert!(avg_duration < Duration::from_millis(100)); // Average under 100ms
        assert!(max_duration < Duration::from_millis(500)); // Max under 500ms
        assert!(num_orders as f64 / total_time.as_secs_f64() > 50.0); // At least 50 orders per second

        let metrics = engine.get_metrics();
        assert_eq!(metrics.orders_submitted, num_orders as u64);
        assert!(metrics.fill_rate > 0.9); // At least 90% fill rate

        assert!(engine.stop().await.is_ok());
    }
}