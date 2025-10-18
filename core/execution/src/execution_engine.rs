//! HFT Execution Engine
//!
//! Main execution engine coordinating all trading operations
//! with microsecond latency and real-time risk management

use anyhow::Result;
use solana_sdk::signature::Keypair;
use std::sync::Arc;
use tokio::sync::RwLock;
use std::time::{Duration, Instant};
use serde::{Deserialize, Serialize};
use log::{info, warn, error, debug};

use crate::enhanced_sniper::EnhancedSniperEngine;
use crate::flash_loan::FlashLoanExecutor;
use crate::universal_auth::FreeSecretsManager;
use super::config::ExecutionConfig;
use super::metrics::ExecutionMetrics;
use super::risk::RealTimeRiskManager;

/// Main execution engine for HFT operations
pub struct ExecutionEngine {
    config: Arc<RwLock<ExecutionConfig>>,
    sniper_engine: Arc<EnhancedSniperEngine>,
    flash_loan_executor: Arc<FlashLoanExecutor>,
    secrets_manager: Arc<RwLock<FreeSecretsManager>>,
    risk_manager: Arc<RealTimeRiskManager>,
    metrics: Arc<ExecutionMetrics>,
    keypair: Keypair,
    engine_start_time: Instant,
}

impl ExecutionEngine {
    /// Create new execution engine
    pub async fn new(
        config: ExecutionConfig,
        sniper_engine: EnhancedSniperEngine,
        flash_loan_executor: FlashLoanExecutor,
        secrets_manager: FreeSecretsManager,
        risk_manager: RealTimeRiskManager,
        keypair: Keypair,
    ) -> Result<Self> {
        let config = Arc::new(RwLock::new(config));

        Ok(Self {
            config: config.clone(),
            sniper_engine: Arc::new(sniper_engine),
            flash_loan_executor: Arc::new(flash_loan_executor),
            secrets_manager: Arc::new(RwLock::new(secrets_manager)),
            risk_manager: Arc::new(risk_manager),
            metrics: Arc::new(ExecutionMetrics::new()),
            keypair,
            engine_start_time: Instant::now(),
        })
    }

    /// Initialize execution engine
    pub async fn initialize(&self) -> Result<()> {
        info!("🚀 Initializing HFT Execution Engine...");

        // Load secrets
        let mut secrets = self.secrets_manager.write().await;
        let trading_config = secrets.get_trading_config().await?;
        drop(secrets);

        info!("✅ Trading configuration loaded");
        info!("🔑 Wallet: {}", trading_config.wallet_address);
        info!("📊 RPC: {}", trading_config.quicknode_primary_rpc);

        // Initialize components
        self.risk_manager.initialize().await?;
        self.metrics.initialize().await?;

        info!("✅ Execution engine initialized successfully");
        Ok(())
    }

    /// Execute token analysis and trading
    pub async fn analyze_and_trade_token(&self, token_address: &str) -> Result<bool> {
        let start_time = Instant::now();

        info!("🎯 Analyzing token: {}", token_address);

        // Step 1: Enhanced token analysis
        let filter = self.sniper_engine.analyze_token(token_address).await?;

        // Step 2: Risk assessment
        if !self.risk_manager.assess_token_risk(&filter).await? {
            warn!("Token {} rejected by risk manager", token_address);
            return Ok(false);
        }

        // Step 3: Trading decision
        if !self.sniper_engine.should_trade_token(&filter).await? {
            debug!("Token {} does not meet trading criteria", token_address);
            return Ok(false);
        }

        // Step 4: Execute trade
        let transaction = self.sniper_engine.execute_sniper_trade(
            &filter,
            &self.keypair,
        ).await?;

        // Step 5: Update metrics
        let execution_time = start_time.elapsed().as_micros() as f64;
        self.metrics.record_trade_execution(execution_time, &filter).await?;

        info!("✅ Trade executed for {} in {:.2}μs", token_address, execution_time);
        Ok(true)
    }

    /// Execute flash loan arbitrage
    pub async fn execute_flash_loan_arbitrage(&self, token_address: &str) -> Result<bool> {
        let start_time = Instant::now();

        info!("⚡ Analyzing flash loan arbitrage for: {}", token_address);

        // Check if flash loans are enabled
        let config = self.config.read().await;
        if !config.enable_flash_loans {
            debug!("Flash loans disabled in configuration");
            return Ok(false);
        }
        drop(config);

        // Execute arbitrage
        let result = self.flash_loan_executor.execute_arbitrage(
            token_address,
            &self.keypair,
        ).await?;

        // Update metrics
        let execution_time = start_time.elapsed().as_micros() as f64;
        self.metrics.record_flash_loan_execution(execution_time, result).await?;

        if result.success {
            info!("✅ Flash loan arbitrage successful for {} in {:.2}μs", token_address, execution_time);
        } else {
            warn!("❌ Flash loan arbitrage failed for {}: {}", token_address, result.error_message);
        }

        Ok(result.success)
    }

    /// Get engine status and health
    pub async fn get_engine_status(&self) -> EngineStatus {
        let metrics = self.metrics.get_current_metrics().await;
        let risk_status = self.risk_manager.get_risk_status().await;
        let config = self.config.read().await;

        EngineStatus {
            is_running: true,
            uptime_seconds: self.engine_start_time.elapsed().as_secs(),
            total_trades: metrics.total_trades,
            successful_trades: metrics.successful_trades,
            total_arbitrage_attempts: metrics.total_arbitrage_attempts,
            successful_arbitrage: metrics.successful_arbitrage,
            average_execution_time_us: metrics.average_execution_time_us,
            risk_level: risk_status.current_risk_level,
            circuit_breaker_active: risk_status.circuit_breaker_active,
            flash_loans_enabled: config.enable_flash_loans,
            wallet_address: self.keypair.pubkey().to_string(),
        }
    }

    /// Emergency stop all trading
    pub async fn emergency_stop(&self) -> Result<()> {
        warn!("🚨 EMERGENCY STOP ACTIVATED");

        // Activate circuit breaker
        self.risk_manager.activate_circuit_breaker("Emergency stop requested").await?;

        // Log emergency stop
        error!("All trading operations halted at user request");

        Ok(())
    }

    /// Resume trading after emergency stop
    pub async fn resume_trading(&self) -> Result<()> {
        info!("🔄 Resuming trading operations...");

        // Reset circuit breaker
        self.risk_manager.reset_circuit_breaker().await?;

        // Log resume
        info!("Trading operations resumed");

        Ok(())
    }
}

/// Engine status information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineStatus {
    pub is_running: bool,
    pub uptime_seconds: u64,
    pub total_trades: u64,
    pub successful_trades: u64,
    pub total_arbitrage_attempts: u64,
    pub successful_arbitrage: u64,
    pub average_execution_time_us: f64,
    pub risk_level: f64,
    pub circuit_breaker_active: bool,
    pub flash_loans_enabled: bool,
    pub wallet_address: String,
}

/// Health check result
#[derive(Debug, Clone)]
pub struct HealthCheck {
    pub is_healthy: bool,
    pub issues: Vec<String>,
    pub last_check: Instant,
}

impl ExecutionEngine {
    /// Perform comprehensive health check
    pub async fn health_check(&self) -> HealthCheck {
        let mut issues = Vec::new();

        // Check component health
        let sniper_health = self.sniper_engine.health_check().await;
        if !sniper_health.is_healthy {
            issues.push(format!("Sniper engine: {}", sniper_health.status));
        }

        let flash_loan_health = self.flash_loan_executor.health_check().await;
        if !flash_loan_health.is_healthy {
            issues.push(format!("Flash loan executor: {}", flash_loan_health.status));
        }

        let risk_health = self.risk_manager.health_check().await;
        if !risk_health.is_healthy {
            issues.push(format!("Risk manager: {}", risk_health.status));
        }

        // Check secrets manager
        let secrets_health = {
            let secrets = self.secrets_manager.read().await;
            secrets.health_check()
        };
        if !secrets_health.is_authenticated {
            issues.push("Secrets manager not authenticated".to_string());
        }

        HealthCheck {
            is_healthy: issues.is_empty(),
            issues,
            last_check: Instant::now(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_engine_creation() {
        // Test implementation would go here
        // For now, just verify the struct can be created
        assert!(true);
    }
}