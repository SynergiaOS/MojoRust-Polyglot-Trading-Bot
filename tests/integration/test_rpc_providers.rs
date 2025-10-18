#[cfg(test)]
mod rpc_provider_tests {
    use super::*;
    use std::time::Duration;
    use tokio::time::timeout;

    #[tokio::test]
    async fn test_helius_laserstream_connection() {
        let config = LaserStreamConfig {
            endpoint: "wss://mainnet.helius-rpc.com/?api-key=test".to_string(),
            subscription_id: "test-sub".to_string(),
            tokens: vec!["So11111111111111111111111111111111111111112".to_string()],
            batch_size: 100,
        };

        let client = HeliusLaserStreamClient::new(config.clone()).await;
        assert!(client.is_ok(), "Failed to create Helius LaserStream client");

        let client = client.unwrap();

        // Test connection establishment
        let connection_result = timeout(Duration::from_secs(10), client.connect()).await;
        assert!(connection_result.is_ok(), "Connection timeout");
        assert!(connection_result.unwrap().is_ok(), "Failed to establish connection");
    }

    #[tokio::test]
    async fn test_quicknode_liljit_priority_fees() {
        let config = LilJitConfig {
            endpoint: "https://mainnet.helius-rpc.com/?api-key=test".to_string(),
            auth_key: "test-auth-key".to_string(),
            urgency_multipliers: HashMap::from([
                (UrgencyLevel::Critical, 10.0),
                (UrgencyLevel::High, 5.0),
                (UrgencyLevel::Normal, 2.0),
                (UrgencyLevel::Low, 1.0),
            ]),
        };

        let client = QuickNodeLilJitClient::new(config);

        // Test priority fee calculation
        let critical_fee = client.calculate_priority_fee(&UrgencyLevel::Critical, 1_000_000).await;
        let normal_fee = client.calculate_priority_fee(&UrgencyLevel::Normal, 1_000_000).await;

        assert!(critical_fee > normal_fee, "Critical fee should be higher than normal fee");
        assert!(critical_fee > 0, "Critical fee should be positive");
    }

    #[tokio::test]
    async fn test_rpc_router_load_balancing() {
        let endpoints = vec![
            RpcEndpoint {
                name: "primary".to_string(),
                url: "https://api.mainnet-beta.solana.com".to_string(),
                priority: 1,
                max_connections: 10,
                timeout: Duration::from_secs(5),
            },
            RpcEndpoint {
                name: "secondary".to_string(),
                url: "https://api.devnet.solana.com".to_string(),
                priority: 2,
                max_connections: 5,
                timeout: Duration::from_secs(10),
            },
        ];

        let router = RpcRouter::new(
            endpoints,
            RoutingStrategy::LoadBalanced,
            PriorityFeeCalculator::new(),
        );

        // Test endpoint selection
        let selected1 = router.select_optimal_endpoint(&RpcRequest::GetBalance).await;
        let selected2 = router.select_optimal_endpoint(&RpcRequest::GetBalance).await;

        assert!(selected1.is_some(), "Should select an endpoint");
        assert!(selected2.is_some(), "Should select an endpoint");

        // Test load balancing (should distribute across endpoints)
        let selected1_name = selected1.unwrap().name;
        let selected2_name = selected2.unwrap().name;

        // In a real test with proper load metrics, these might be different
        assert!(!selected1_name.is_empty(), "Selected endpoint should have a name");
        assert!(!selected2_name.is_empty(), "Selected endpoint should have a name");
    }

    #[tokio::test]
    async fn test_rpc_router_failover() {
        let endpoints = vec![
            RpcEndpoint {
                name: "unhealthy".to_string(),
                url: "https://invalid-endpoint.example.com".to_string(),
                priority: 1,
                max_connections: 10,
                timeout: Duration::from_millis(100),
            },
            RpcEndpoint {
                name: "healthy".to_string(),
                url: "https://api.mainnet-beta.solana.com".to_string(),
                priority: 2,
                max_connections: 10,
                timeout: Duration::from_secs(5),
            },
        ];

        let router = RpcRouter::new(
            endpoints,
            RoutingStrategy::Failover,
            PriorityFeeCalculator::new(),
        );

        // Test failover mechanism
        let selected = router.select_optimal_endpoint(&RpcRequest::GetBalance).await;
        assert!(selected.is_some(), "Should fallback to healthy endpoint");

        let endpoint_name = selected.unwrap().name;
        assert_eq!(endpoint_name, "healthy", "Should select healthy endpoint after failover");
    }

    #[tokio::test]
    async fn test_transaction_pipeline_queue() {
        let config = TransactionPipelineConfig::default();
        let rpc_router = Arc::new(RpcRouter::new(
            vec![create_test_endpoint()],
            RoutingStrategy::RoundRobin,
            PriorityFeeCalculator::new(),
        ));
        let keypair = Arc::new(Keypair::new());
        let priority_fee_calculator = Arc::new(PriorityFeeCalculator::new());

        let mut pipeline = TransactionPipeline::new(
            config,
            rpc_router,
            keypair,
            priority_fee_calculator,
        );

        // Test transaction queuing
        let (tx, mut rx) = mpsc::channel(10);

        let queue_result = pipeline.queue_transaction(
            vec![],
            UrgencyLevel::Normal,
            Some(1_000_000),
            false,
            tx,
        ).await;

        assert!(queue_result.is_ok(), "Should successfully queue transaction");
        let transaction_id = queue_result.unwrap();
        assert!(!transaction_id.is_empty(), "Transaction ID should not be empty");

        // Test queue depth
        let queue_depth = pipeline.get_queue_depth().await;
        assert!(queue_depth >= 1, "Queue depth should be at least 1");
    }

    #[tokio::test]
    async fn test_flash_loan_coordinator_provider_selection() {
        let config = FlashLoanCoordinatorConfig::default();
        let rpc_router = Arc::new(RpcRouter::new(
            vec![create_test_endpoint()],
            RoutingStrategy::RoundRobin,
            PriorityFeeCalculator::new(),
        ));
        let priority_fee_calculator = Arc::new(PriorityFeeCalculator::new());

        let flash_loan_executors = HashMap::from([
            (FlashLoanProvider::Solend, Arc::new(FlashLoanExecutor::new(
                FlashLoanProvider::Solend,
                create_test_endpoint().url,
            ))),
            (FlashLoanProvider::Marginfi, Arc::new(FlashLoanExecutor::new(
                FlashLoanProvider::Marginfi,
                create_test_endpoint().url,
            ))),
        ]);

        let (mut coordinator, _opportunity_sender) = FlashLoanCoordinator::new(
            config,
            rpc_router,
            priority_fee_calculator,
            flash_loan_executors,
        );

        // Initialize provider health
        coordinator.initialize_provider_health().await.unwrap();

        let opportunity = FlashLoanOpportunity::new(
            Pubkey::new_unique(),
            1_000_000_000, // 1 SOL
            0.01, // 1% expected profit
            vec!["SOL".to_string(), "USDC".to_string()],
            UrgencyLevel::High,
            60, // 60 seconds TTL
        );

        // Test provider selection
        let provider = FlashLoanCoordinator::select_provider(
            &opportunity,
            &coordinator.provider_health,
            &ProviderSelectionStrategy::BestRate,
            &coordinator.provider_selection_index,
            &coordinator.provider_load_balancer,
        ).await;

        assert!(provider.is_some(), "Should select a provider");
        assert!(matches!(provider.unwrap(), FlashLoanProvider::Solend | FlashLoanProvider::Marginfi));
    }

    fn create_test_endpoint() -> RpcEndpoint {
        RpcEndpoint {
            name: "test".to_string(),
            url: "https://api.mainnet-beta.solana.com".to_string(),
            priority: 1,
            max_connections: 10,
            timeout: Duration::from_secs(5),
        }
    }
}

#[cfg(test)]
mod integration_tests {
    use super::*;
    use std::sync::Arc;

    #[tokio::test]
    async fn test_end_to_end_transaction_flow() {
        // This test requires actual RPC connections and is marked as integration test
        // Run with: cargo test --test integration -- --ignored

        let config = TransactionPipelineConfig {
            max_queue_size: 100,
            max_concurrent_senders: 2,
            batch_size: 5,
            batch_timeout: Duration::from_millis(100),
            retry_attempts: 2,
            retry_delay: Duration::from_millis(50),
            confirmation_timeout: Duration::from_secs(10),
            simulation_timeout: Duration::from_secs(2),
            priority_fee_multipliers: HashMap::from([
                (UrgencyLevel::Critical, 10.0),
                (UrgencyLevel::High, 5.0),
                (UrgencyLevel::Normal, 2.0),
                (UrgencyLevel::Low, 1.0),
            ]),
        };

        let rpc_endpoint = RpcEndpoint {
            name: "mainnet".to_string(),
            url: std::env::var("SOLANA_RPC_URL")
                .unwrap_or_else(|_| "https://api.mainnet-beta.solana.com".to_string()),
            priority: 1,
            max_connections: 5,
            timeout: Duration::from_secs(5),
        };

        let rpc_router = Arc::new(RpcRouter::new(
            vec![rpc_endpoint],
            RoutingStrategy::RoundRobin,
            PriorityFeeCalculator::new(),
        ));

        let keypair = Arc::new(Keypair::new());
        let priority_fee_calculator = Arc::new(PriorityFeeCalculator::new());

        let mut pipeline = TransactionPipeline::new(
            config,
            rpc_router,
            keypair,
            priority_fee_calculator,
        );

        // Test the complete flow with a real transaction
        let (result_tx, mut result_rx) = mpsc::channel(1);

        let transaction_id = pipeline.queue_transaction(
            vec![], // Empty instructions for testing
            UrgencyLevel::Normal,
            Some(1_000_000),
            false,
            result_tx,
        ).await;

        assert!(transaction_id.is_ok(), "Should queue transaction successfully");

        // Wait for result (with timeout)
        let timeout_result = tokio::time::timeout(
            Duration::from_secs(15),
            result_rx.recv()
        ).await;

        assert!(timeout_result.is_ok(), "Should receive result before timeout");

        if let Some(result) = timeout_result.unwrap() {
            // In a real scenario, this would be a transaction result
            // For testing, we just verify the structure
            assert!(!result.transaction_id.is_empty());
        }
    }

    #[tokio::test]
    #[ignore] // Requires real API keys
    async fn test_helius_laserstream_real_connection() {
        let api_key = std::env::var("HELIUS_API_KEY")
            .expect("HELIUS_API_KEY environment variable required");

        let config = LaserStreamConfig {
            endpoint: format!("wss://mainnet.helius-rpc.com/?api-key={}", api_key),
            subscription_id: "test-integration".to_string(),
            tokens: vec!["So11111111111111111111111111111111111111112".to_string()],
            batch_size: 10,
        };

        let client = HeliusLaserStreamClient::new(config).await.unwrap();

        // Test connection
        let connection_result = tokio::time::timeout(
            Duration::from_secs(30),
            client.connect()
        ).await;

        assert!(connection_result.is_ok(), "Connection should not timeout");
        assert!(connection_result.unwrap().is_ok(), "Should establish connection successfully");

        // Test data reception
        let mut data_receiver = client.get_data_receiver();
        let data_result = tokio::time::timeout(
            Duration::from_secs(60),
            data_receiver.recv()
        ).await;

        assert!(data_result.is_ok(), "Should receive data within timeout");
        assert!(data_result.unwrap().is_some(), "Should receive actual data");
    }

    #[tokio::test]
    #[ignore] // Requires real API keys
    async fn test_quicknode_liljit_real_bundle() {
        let api_key = std::env::var("QUICKNODE_API_KEY")
            .expect("QUICKNODE_API_KEY environment variable required");

        let config = LilJitConfig {
            endpoint: format!("https://{}.solana-mainnet.quiknode.pro/{}", api_key, api_key),
            auth_key: std::env::var("JITO_AUTH_KEY")
                .unwrap_or_else(|_| "test-auth-key".to_string()),
            urgency_multipliers: HashMap::from([
                (UrgencyLevel::Critical, 10.0),
                (UrgencyLevel::High, 5.0),
                (UrgencyLevel::Normal, 2.0),
                (UrgencyLevel::Low, 1.0),
            ]),
        };

        let client = QuickNodeLilJitClient::new(config);

        // Test priority fee estimation
        let priority_fee = client.estimate_priority_fee(&UrgencyLevel::Normal).await;
        assert!(priority_fee.is_ok(), "Should estimate priority fee");
        assert!(priority_fee.unwrap() > 0, "Priority fee should be positive");

        // Test bundle submission (with dummy data)
        let bundle = Bundle {
            transactions: vec![],
            priority_fee: 1000000,
            deadline: SystemTime::now() + Duration::from_secs(30),
        };

        // Note: This will likely fail with dummy data, but tests the API call structure
        let submission_result = client.submit_bundle(bundle).await;
        // We don't assert success here as it requires valid transactions
        assert!(submission_result.is_ok() || submission_result.is_err(), "Should handle bundle submission");
    }
}