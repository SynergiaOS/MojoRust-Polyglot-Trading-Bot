//! RPC Router with Dynamic Priority Fee Management
//!
//! This module provides intelligent RPC routing with dynamic priority fee calculation,
//! load balancing, and connection pooling for optimal transaction execution on Solana.
//! It integrates with multiple RPC providers and automatically selects the best endpoint
//! based on latency, success rate, and cost considerations.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::sync::{RwLock, mpsc, Semaphore};
use serde::{Deserialize, Serialize};
use anyhow::{Result, anyhow};
use log::{info, warn, error, debug};
use solana_sdk::{
    pubkey::Pubkey,
    transaction::Transaction,
    commitment_config::CommitmentConfig,
    signature::Keypair,
};
use solana_client::rpc_client::RpcClient;
use solana_client::rpc_request::RpcRequest;
use solana_client::rpc_response::RpcResult;
use reqwest::Client;
use tokio::time::timeout;

use crate::monitoring::metrics;
use super::priority_fees::{PriorityFeeCalculator, UrgencyLevel};

/// RPC endpoint configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RpcEndpoint {
    pub name: String,
    pub url: String,
    pub endpoint_type: EndpointType,
    pub priority: u8,
    pub rate_limit_per_second: u32,
    pub max_concurrent_requests: usize,
    pub timeout_ms: u64,
    pub dedicated_for: Option<Vec<RequestType>>,
    pub supports_priority_fees: bool,
    pub supports_websockets: bool,
    pub supports_gossip: bool,
}

/// RPC endpoint type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum EndpointType {
    /// Standard public RPC
    Public,
    /// Premium RPC with enhanced features
    Premium,
    /// Dedicated endpoint for transactions
    Transaction,
    /// Dedicated endpoint for data queries
    Data,
    /// WebSocket endpoint for real-time data
    WebSocket,
    /// Local full node
    Local,
}

/// Request type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RequestType {
    Transaction,
    AccountInfo,
    ProgramAccount,
    TokenAccount,
    SignatureStatus,
    SlotInfo,
    BlockInfo,
    GetBalance,
    GetTokenSupply,
    GetTokenLargestAccounts,
    Custom,
}

/// RPC routing strategy
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RoutingStrategy {
    /// Round-robin load balancing
    RoundRobin,
    /// Weighted random based on performance
    WeightedRandom,
    /// Always use best performing endpoint
    BestPerforming,
    /// Use dedicated endpoints when available
    DedicatedFirst,
    /// Intelligent routing based on request type
    Intelligent,
}

/// RPC endpoint health metrics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EndpointMetrics {
    pub name: String,
    pub total_requests: u64,
    pub successful_requests: u64,
    pub failed_requests: u64,
    pub average_latency_ms: f64,
    pub last_success_time: Option<SystemTime>,
    pub last_failure_time: Option<SystemTime>,
    pub consecutive_failures: u32,
    pub current_load: usize,
    pub max_concurrent_reached: usize,
    pub success_rate: f64,
    pub endpoint_score: f64,
    pub uptime_percentage: f64,
}

impl Default for EndpointMetrics {
    fn default() -> Self {
        Self {
            name: "".to_string(),
            total_requests: 0,
            successful_requests: 0,
            failed_requests: 0,
            average_latency_ms: 0.0,
            last_success_time: None,
            last_failure_time: None,
            consecutive_failures: 0,
            current_load: 0,
            max_concurrent_reached: 0,
            success_rate: 1.0,
            endpoint_score: 1.0,
            uptime_percentage: 100.0,
        }
    }
}

/// RPC request with metadata
#[derive(Debug, Clone)]
pub struct RpcRequestWrapper {
    pub request: RpcRequest,
    pub params: serde_json::Value,
    pub request_type: RequestType,
    pub urgency: UrgencyLevel,
    pub max_retries: u32,
    pub timeout_ms: u64,
    pub created_at: Instant,
    pub request_id: String,
}

/// RPC response with metadata
#[derive(Debug, Clone)]
pub struct RpcResponseWrapper {
    pub response: RpcResult<serde_json::Value>,
    pub endpoint_used: String,
    pub latency_ms: u64,
    pub attempt_number: u32,
    pub success: bool,
    pub error_message: Option<String>,
}

/// Advanced RPC Router with intelligent routing
pub struct RpcRouter {
    /// Available RPC endpoints
    endpoints: Vec<RpcEndpoint>,
    /// Current metrics for each endpoint
    endpoint_metrics: Arc<RwLock<HashMap<String, EndpointMetrics>>>,
    /// Routing strategy
    routing_strategy: RoutingStrategy,
    /// Connection pool for each endpoint
    connection_pool: Arc<RwLock<HashMap<String, Arc<RpcClient>>>>,
    /// HTTP client for direct requests
    http_client: Client,
    /// Semaphore for concurrent request limiting
    request_semaphore: Arc<Semaphore>,
    /// Priority fee calculator
    priority_fee_calculator: Arc<PriorityFeeCalculator>,
    /// Request queue for batch processing
    request_queue: Arc<RwLock<VecDeque<RpcRequestWrapper>>>,
    /// Response channel for async processing
    response_tx: mpsc::UnboundedSender<RpcResponseWrapper>,
    /// Metrics collection
    router_metrics: Arc<RwLock<RouterMetrics>>,
}

/// Router-level metrics
#[derive(Debug, Default)]
pub struct RouterMetrics {
    pub total_requests_routed: u64,
    pub requests_by_type: HashMap<RequestType, u64>,
    pub requests_by_urgency: HashMap<UrgencyLevel, u64>,
    pub average_routing_latency_ms: f64,
    pub cache_hit_rate: f64,
    pub load_balancing_efficiency: f64,
    pub fallback_usage: u64,
    pub priority_fee_calculations: u64,
}

impl RpcRouter {
    /// Create new RPC router with intelligent routing
    pub fn new(
        endpoints: Vec<RpcEndpoint>,
        routing_strategy: RoutingStrategy,
        max_concurrent_requests: usize,
    ) -> Result<Self> {
        let endpoint_metrics = Arc::new(RwLock::new(HashMap::new()));
        let connection_pool = Arc::new(RwLock::new(HashMap::new()));
        let request_semaphore = Arc::new(Semaphore::new(max_concurrent_requests));
        let priority_fee_calculator = Arc::new(PriorityFeeCalculator::new());
        let request_queue = Arc::new(RwLock::new(VecDeque::new()));
        let (response_tx, _) = mpsc::unbounded_channel();
        let router_metrics = Arc::new(RwLock::new(RouterMetrics::default()));

        // Initialize metrics for each endpoint
        {
            let mut metrics = endpoint_metrics.write().unwrap();
            for endpoint in &endpoints {
                metrics.insert(endpoint.name.clone(), EndpointMetrics {
                    name: endpoint.name.clone(),
                    endpoint_score: endpoint.priority as f64,
                    ..Default::default()
                });
            }
        }

        Ok(Self {
            endpoints,
            endpoint_metrics,
            connection_pool,
            http_client: Client::builder()
                .timeout(Duration::from_secs(30))
                .build()?,
            request_semaphore,
            priority_fee_calculator,
            request_queue,
            response_tx,
            router_metrics,
        })
    }

    /// Create default RPC endpoints configuration
    pub fn create_default_endpoints() -> Vec<RpcEndpoint> {
        vec![
            // Primary Helius endpoint
            RpcEndpoint {
                name: "helius_primary".to_string(),
                url: "https://rpc.helius.xyz/?api-key={api_key}".to_string(),
                endpoint_type: EndpointType::Premium,
                priority: 1,
                rate_limit_per_second: 100,
                max_concurrent_requests: 50,
                timeout_ms: 5000,
                dedicated_for: None,
                supports_priority_fees: true,
                supports_websockets: true,
                supports_gossip: true,
            },
            // Backup Helius endpoint
            RpcEndpoint {
                name: "helius_backup".to_string(),
                url: "https://rpc.helius.xyz/?api-key={api_key}".to_string(),
                endpoint_type: EndpointType::Premium,
                priority: 2,
                rate_limit_per_second: 50,
                max_concurrent_requests: 25,
                timeout_ms: 8000,
                dedicated_for: None,
                supports_priority_fees: true,
                supports_websockets: true,
                supports_gossip: false,
            },
            // QuickNode primary
            RpcEndpoint {
                name: "quicknode_primary".to_string(),
                url: "https://{endpoint}.solana-mainnet.quiknode.pro/{api_key}".to_string(),
                endpoint_type: EndpointType::Premium,
                priority: 3,
                rate_limit_per_second: 80,
                max_concurrent_requests: 40,
                timeout_ms: 6000,
                dedicated_for: None,
                supports_priority_fees: true,
                supports_websockets: true,
                supports_gossip: true,
            },
            // Public fallback
            RpcEndpoint {
                name: "public_fallback".to_string(),
                url: "https://api.mainnet-beta.solana.com".to_string(),
                endpoint_type: EndpointType::Public,
                priority: 10,
                rate_limit_per_second: 20,
                max_concurrent_requests: 10,
                timeout_ms: 10000,
                dedicated_for: Some(vec![RequestType::AccountInfo, RequestType::SignatureStatus]),
                supports_priority_fees: false,
                supports_websockets: false,
                supports_gossip: false,
            },
        ]
    }

    /// Route and execute RPC request
    pub async fn execute_request(&self, request: RpcRequestWrapper) -> Result<RpcResponseWrapper> {
        let start_time = Instant::now();

        // Update routing metrics
        {
            let mut metrics = self.router_metrics.write().unwrap();
            metrics.total_requests_routed += 1;
            *metrics.requests_by_type.entry(request.request_type).or_insert(0) += 1;
            *metrics.requests_by_urgency.entry(request.urgency).or_insert(0) += 1;
        }

        // Select optimal endpoint
        let endpoint_name = self.select_endpoint(&request).await?;

        // Acquire semaphore permit
        let _permit = self.request_semaphore.acquire().await
            .map_err(|_| anyhow!("Request semaphore closed"))?;

        // Execute request with retry logic
        let response = self.execute_with_retry(&request, &endpoint_name).await?;

        // Update routing metrics
        let routing_latency = start_time.elapsed().as_millis() as f64;
        {
            let mut metrics = self.router_metrics.write().unwrap();
            metrics.average_routing_latency_ms =
                (metrics.average_routing_latency_ms + routing_latency) / 2.0;
        }

        metrics::increment_counter("rpc_requests_routed_total", &[
            ("endpoint", &endpoint_name),
            ("request_type", format!("{:?}", request.request_type).as_str()),
            ("success", &response.success.to_string()),
        ]);

        Ok(response)
    }

    /// Send transaction with optimal routing and priority fees
    pub async fn send_transaction(
        &self,
        transaction: &Transaction,
        urgency: UrgencyLevel,
        keypair: &Keypair,
    ) -> Result<String> {
        info!("Sending transaction with urgency: {:?}", urgency);

        // Calculate optimal priority fees
        let priority_fees = self.priority_fee_calculator
            .calculate_priority_fees(transaction, urgency).await?;

        // Create transaction request
        let request = RpcRequestWrapper {
            request: RpcRequest::SendTransaction,
            params: serde_json::json!([
                bs58::encode(bincode::serialize(&transaction)?).into_string(),
                serde_json::json!({
                    "skipPreflight": false,
                    "preflightCommitment": "confirmed",
                    "maxRetries": 3,
                    "priorityFeeLimit": priority_fees.compute_unit_price,
                })
            ]),
            request_type: RequestType::Transaction,
            urgency,
            max_retries: 3,
            timeout_ms: match urgency {
                UrgencyLevel::Flash => 2000,
                UrgencyLevel::High => 5000,
                UrgencyLevel::Medium => 8000,
                UrgencyLevel::Low => 12000,
            },
            created_at: Instant::now(),
            request_id: uuid::Uuid::new_v4().to_string(),
        };

        // Execute request
        let response = self.execute_request(request).await?;

        if response.success {
            if let Some(signature) = response.response.unwrap().as_str() {
                info!("Transaction sent successfully: {}", signature);
                metrics::increment_counter("transactions_sent_total", &[
                    ("urgency", format!("{:?}", urgency).as_str()),
                ]);
                return Ok(signature.to_string());
            }
        }

        Err(anyhow!("Failed to send transaction: {:?}", response.error_message))
    }

    /// Get account info with intelligent routing
    pub async fn get_account_info(&self, pubkey: &Pubkey, commitment: CommitmentConfig) -> Result<Option<solana_sdk::account::Account>> {
        let request = RpcRequestWrapper {
            request: RpcRequest::GetAccountInfo,
            params: serde_json::json!([
                pubkey.to_string(),
                serde_json::json!({
                    "encoding": "base64",
                    "commitment": format!("{:?}", commitment)
                })
            ]),
            request_type: RequestType::AccountInfo,
            urgency: UrgencyLevel::Medium,
            max_retries: 2,
            timeout_ms: 5000,
            created_at: Instant::now(),
            request_id: uuid::Uuid::new_v4().to_string(),
        };

        let response = self.execute_request(request).await?;

        if response.success {
            if let Some(result) = response.response.unwrap().as_object() {
                if let Some(value) = result.get("value") {
                    if !value.is_null() {
                        let account_data = value.get("data").unwrap().as_str().unwrap();
                        let lamports = value.get("lamports").unwrap().as_u64().unwrap();
                        let owner = Pubkey::from_str(value.get("owner").unwrap().as_str().unwrap())?;
                        let executable = value.get("executable").unwrap().as_bool().unwrap();
                        let rent_epoch = value.get("rentEpoch").unwrap().as_u64().unwrap();

                        let data = bs58::decode(account_data).into_vec()?;
                        let account = solana_sdk::account::Account {
                            lamports,
                            data,
                            owner,
                            executable,
                            rent_epoch,
                        };

                        return Ok(Some(account));
                    }
                }
            }
        }

        Ok(None)
    }

    /// Select optimal endpoint for request
    async fn select_endpoint(&self, request: &RpcRequestWrapper) -> Result<String> {
        let metrics = self.endpoint_metrics.read().unwrap();

        match self.routing_strategy {
            RoutingStrategy::Intelligent => self.intelligent_endpoint_selection(&metrics, request),
            RoutingStrategy::BestPerforming => self.best_performing_endpoint(&metrics, request),
            RoutingStrategy::DedicatedFirst => self.dedicated_endpoint_selection(&metrics, request),
            RoutingStrategy::WeightedRandom => self.weighted_random_selection(&metrics, request),
            RoutingStrategy::RoundRobin => self.round_robin_selection(&metrics, request),
        }
    }

    /// Intelligent endpoint selection based on request type and performance
    fn intelligent_endpoint_selection(
        &self,
        metrics: &HashMap<String, EndpointMetrics>,
        request: &RpcRequestWrapper,
    ) -> Result<String> {
        let mut candidate_endpoints = Vec::new();

        // Filter endpoints by request requirements
        for endpoint in &self.endpoints {
            // Skip endpoints that are down or have too many consecutive failures
            if let Some(endpoint_metrics) = metrics.get(&endpoint.name) {
                if endpoint_metrics.consecutive_failures > 3 {
                    continue;
                }

                // Check if endpoint supports required features
                match request.request_type {
                    RequestType::Transaction if !endpoint.supports_priority_fees => continue,
                    _ => {}
                }

                // Check dedicated endpoint requirements
                if let Some(dedicated_for) = &endpoint.dedicated_for {
                    if !dedicated_for.contains(&request.request_type) {
                        continue;
                    }
                }

                // Check rate limits
                if endpoint_metrics.current_load >= endpoint.max_concurrent_requests {
                    continue;
                }

                candidate_endpoints.push(endpoint);
            }
        }

        if candidate_endpoints.is_empty() {
            // Fall back to public endpoints
            for endpoint in &self.endpoints {
                if endpoint.endpoint_type == EndpointType::Public {
                    return Ok(endpoint.name.clone());
                }
            }
            return Err(anyhow!("No available endpoints"));
        }

        // Score endpoints based on multiple factors
        let mut scored_endpoints = Vec::new();
        for endpoint in &candidate_endpoints {
            if let Some(endpoint_metrics) = metrics.get(&endpoint.name) {
                let mut score = endpoint_metrics.endpoint_score;

                // Factor in success rate
                score *= endpoint_metrics.success_rate;

                // Factor in latency (inverse)
                score *= 1.0 / (1.0 + endpoint_metrics.average_latency_ms / 1000.0);

                // Factor in current load
                let load_ratio = endpoint_metrics.current_load as f64 / endpoint.max_concurrent_requests as f64;
                score *= (1.0 - load_ratio).max(0.1);

                // Factor in endpoint priority
                score *= (11.0 - endpoint.priority as f64) / 10.0;

                // Factor in urgency level
                match request.urgency {
                    UrgencyLevel::Flash => score *= endpoint.supports_priority_fees as u8 as f64,
                    UrgencyLevel::High => score *= 1.2,
                    UrgencyLevel::Medium => score *= 1.0,
                    UrgencyLevel::Low => score *= 0.8,
                }

                scored_endpoints.push((endpoint.name.clone(), score));
            }
        }

        // Sort by score and select the best
        scored_endpoints.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        if let Some((best_endpoint, _)) = scored_endpoints.first() {
            return Ok(best_endpoint.clone());
        }

        Err(anyhow!("No suitable endpoint found"))
    }

    /// Best performing endpoint selection
    fn best_performing_endpoint(
        &self,
        metrics: &HashMap<String, EndpointMetrics>,
        _request: &RpcRequestWrapper,
    ) -> Result<String> {
        let mut best_endpoint = None;
        let mut best_score = 0.0;

        for (name, endpoint_metrics) in metrics {
            if endpoint_metrics.consecutive_failures < 3 {
                let score = endpoint_metrics.success_rate / (1.0 + endpoint_metrics.average_latency_ms / 1000.0);
                if score > best_score {
                    best_score = score;
                    best_endpoint = Some(name.clone());
                }
            }
        }

        best_endpoint.ok_or_else(|| anyhow!("No healthy endpoints available"))
    }

    /// Dedicated endpoint selection
    fn dedicated_endpoint_selection(
        &self,
        metrics: &HashMap<String, EndpointMetrics>,
        request: &RpcRequestWrapper,
    ) -> Result<String> {
        // First try dedicated endpoints
        for endpoint in &self.endpoints {
            if let Some(dedicated_for) = &endpoint.dedicated_for {
                if dedicated_for.contains(&request.request_type) {
                    if let Some(endpoint_metrics) = metrics.get(&endpoint.name) {
                        if endpoint_metrics.consecutive_failures < 3 {
                            return Ok(endpoint.name.clone());
                        }
                    }
                }
            }
        }

        // Fall back to intelligent selection
        self.intelligent_endpoint_selection(metrics, request)
    }

    /// Weighted random endpoint selection
    fn weighted_random_selection(
        &self,
        metrics: &HashMap<String, EndpointMetrics>,
        request: &RpcRequestWrapper,
    ) -> Result<String> {
        let mut candidates = Vec::new();
        let mut total_weight = 0.0;

        for endpoint in &self.endpoints {
            if let Some(endpoint_metrics) = metrics.get(&endpoint.name) {
                if endpoint_metrics.consecutive_failures < 3 {
                    let weight = endpoint_metrics.endpoint_score * endpoint_metrics.success_rate;
                    candidates.push((endpoint.name.clone(), weight));
                    total_weight += weight;
                }
            }
        }

        if candidates.is_empty() {
            return Err(anyhow!("No healthy endpoints available"));
        }

        // Random selection weighted by performance
        let random_value = rand::random::<f64>() * total_weight;
        let mut cumulative_weight = 0.0;

        for (name, weight) in candidates {
            cumulative_weight += weight;
            if random_value <= cumulative_weight {
                return Ok(name);
            }
        }

        // Fallback to first candidate
        Ok(candidates[0].0.clone())
    }

    /// Round-robin endpoint selection
    fn round_robin_selection(
        &self,
        metrics: &HashMap<String, EndpointMetrics>,
        _request: &RpcRequestWrapper,
    ) -> Result<String> {
        // Simple round-robin based on request count
        let mut min_requests = u64::MAX;
        let mut selected_endpoint = None;

        for (name, endpoint_metrics) in metrics {
            if endpoint_metrics.consecutive_failures < 3 && endpoint_metrics.total_requests < min_requests {
                min_requests = endpoint_metrics.total_requests;
                selected_endpoint = Some(name.clone());
            }
        }

        selected_endpoint.ok_or_else(|| anyhow!("No healthy endpoints available"))
    }

    /// Execute request with retry logic
    async fn execute_with_retry(
        &self,
        request: &RpcRequestWrapper,
        endpoint_name: &str,
    ) -> Result<RpcResponseWrapper> {
        let mut attempt = 1;
        let mut last_error = None;

        while attempt <= request.max_retries {
            let start_time = Instant::now();

            match self.execute_single_request(request, endpoint_name).await {
                Ok(response) => {
                    if response.success {
                        // Update success metrics
                        self.update_endpoint_metrics(endpoint_name, true, start_time.elapsed().as_millis() as u64);
                        return Ok(response);
                    } else {
                        last_error = response.error_message.clone();
                        warn!("Request failed on attempt {}: {:?}", attempt, last_error);
                    }
                }
                Err(e) => {
                    last_error = Some(e.to_string());
                    warn!("Request error on attempt {}: {}", attempt, last_error.as_ref().unwrap());
                }
            }

            // Update failure metrics
            self.update_endpoint_metrics(endpoint_name, false, start_time.elapsed().as_millis() as u64);

            // Exponential backoff
            let backoff_ms = 1000 * (2_u64.pow(attempt - 1));
            tokio::time::sleep(Duration::from_millis(backoff_ms)).await;

            attempt += 1;
        }

        Err(anyhow!("Request failed after {} attempts: {}", request.max_retries, last_error.unwrap_or_default()))
    }

    /// Execute single request on specific endpoint
    async fn execute_single_request(
        &self,
        request: &RpcRequestWrapper,
        endpoint_name: &str,
    ) -> Result<RpcResponseWrapper> {
        let endpoint = self.endpoints.iter()
            .find(|e| e.name == endpoint_name)
            .ok_or_else(|| anyhow!("Endpoint not found: {}", endpoint_name))?;

        // Get or create connection
        let client = self.get_or_create_client(endpoint_name).await?;

        // Execute with timeout
        let result = timeout(
            Duration::from_millis(request.timeout_ms),
            client.send(&request.request, request.params.clone())
        ).await;

        match result {
            Ok(Ok(response)) => {
                Ok(RpcResponseWrapper {
                    response: Ok(response),
                    endpoint_used: endpoint_name.to_string(),
                    latency_ms: 0, // Would measure actual latency
                    attempt_number: 1,
                    success: true,
                    error_message: None,
                })
            }
            Ok(Err(e)) => {
                Ok(RpcResponseWrapper {
                    response: Err(e),
                    endpoint_used: endpoint_name.to_string(),
                    latency_ms: 0,
                    attempt_number: 1,
                    success: false,
                    error_message: Some("RPC error".to_string()),
                })
            }
            Err(_) => {
                Ok(RpcResponseWrapper {
                    response: Err(solana_client::client_error::Error::Reqwest(
                        reqwest::Error::from(reqwest::ErrorKind::Timeout)
                    )),
                    endpoint_used: endpoint_name.to_string(),
                    latency_ms: request.timeout_ms,
                    attempt_number: 1,
                    success: false,
                    error_message: Some("Request timeout".to_string()),
                })
            }
        }
    }

    /// Get or create RPC client for endpoint
    async fn get_or_create_client(&self, endpoint_name: &str) -> Result<Arc<RpcClient>> {
        {
            let pool = self.connection_pool.read().unwrap();
            if let Some(client) = pool.get(endpoint_name) {
                return Ok(client.clone());
            }
        }

        // Create new client
        let endpoint = self.endpoints.iter()
            .find(|e| e.name == endpoint_name)
            .ok_or_else(|| anyhow!("Endpoint not found: {}", endpoint_name))?;

        let client = Arc::new(RpcClient::new_with_commitment(
            &endpoint.url,
            CommitmentConfig::confirmed()
        ));

        // Add to pool
        {
            let mut pool = self.connection_pool.write().unwrap();
            pool.insert(endpoint_name.to_string(), client.clone());
        }

        Ok(client)
    }

    /// Update endpoint metrics
    fn update_endpoint_metrics(&self, endpoint_name: &str, success: bool, latency_ms: u64) {
        let mut metrics = self.endpoint_metrics.write().unwrap();
        if let Some(endpoint_metrics) = metrics.get_mut(endpoint_name) {
            endpoint_metrics.total_requests += 1;

            if success {
                endpoint_metrics.successful_requests += 1;
                endpoint_metrics.last_success_time = Some(SystemTime::now());
                endpoint_metrics.consecutive_failures = 0;

                // Update average latency
                let new_latency = latency_ms as f64;
                endpoint_metrics.average_latency_ms =
                    (endpoint_metrics.average_latency_ms + new_latency) / 2.0;
            } else {
                endpoint_metrics.failed_requests += 1;
                endpoint_metrics.last_failure_time = Some(SystemTime::now());
                endpoint_metrics.consecutive_failures += 1;
            }

            // Update success rate
            endpoint_metrics.success_rate = endpoint_metrics.successful_requests as f64
                / endpoint_metrics.total_requests as f64;

            // Update endpoint score
            endpoint_metrics.endpoint_score = endpoint_metrics.success_rate *
                (1.0 / (1.0 + endpoint_metrics.average_latency_ms / 1000.0));
        }
    }

    /// Get endpoint metrics
    pub async fn get_endpoint_metrics(&self) -> HashMap<String, EndpointMetrics> {
        self.endpoint_metrics.read().unwrap().clone()
    }

    /// Get router metrics
    pub async fn get_router_metrics(&self) -> RouterMetrics {
        self.router_metrics.read().unwrap().clone()
    }

    /// Health check for all endpoints
    pub async fn health_check(&self) -> HashMap<String, bool> {
        let mut health_status = HashMap::new();

        for endpoint in &self.endpoints {
            let request = RpcRequestWrapper {
                request: RpcRequest::GetSlot,
                params: serde_json::json!({}),
                request_type: RequestType::SlotInfo,
                urgency: UrgencyLevel::Medium,
                max_retries: 1,
                timeout_ms: 5000,
                created_at: Instant::now(),
                request_id: uuid::Uuid::new_v4().to_string(),
            };

            let result = self.execute_with_retry(&request, &endpoint.name).await;
            health_status.insert(endpoint.name.clone(), result.is_ok());
        }

        health_status
    }

    /// Optimize routing based on recent performance
    pub async fn optimize_routing(&self) {
        let metrics = self.endpoint_metrics.read().unwrap();

        // Recalculate endpoint scores based on recent performance
        for endpoint_metric in metrics.values() {
            // Implement optimization logic
            debug!("Optimizing routing for endpoint: {}", endpoint_metric.name);
        }

        info!("Routing optimization completed");
    }
}

// Mock random number generator
mod rand {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::SystemTime;

    pub fn random<T>() -> T
    where
        T: From<f64>
    {
        let mut hasher = DefaultHasher::new();
        SystemTime::now().hash(&mut hasher);
        let hash = hasher.finish();
        let normalized = (hash as f64) / (u64::MAX as f64);
        T::from(normalized)
    }
}

// Re-export bs58 for encoding
pub use bs58;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_default_endpoints() {
        let endpoints = RpcRouter::create_default_endpoints();
        assert_eq!(endpoints.len(), 4);
        assert!(endpoints.iter().any(|e| e.name == "helius_primary"));
        assert!(endpoints.iter().any(|e| e.endpoint_type == EndpointType::Public));
    }

    #[test]
    fn test_endpoint_types() {
        assert_eq!(format!("{:?}", EndpointType::Premium), "Premium");
        assert_eq!(format!("{:?}", RequestType::Transaction), "Transaction");
        assert_eq!(format!("{:?}", RoutingStrategy::Intelligent), "Intelligent");
    }

    #[test]
    fn test_endpoint_metrics_default() {
        let metrics = EndpointMetrics::default();
        assert_eq!(metrics.success_rate, 1.0);
        assert_eq!(metrics.total_requests, 0);
        assert_eq!(metrics.endpoint_score, 1.0);
    }
}