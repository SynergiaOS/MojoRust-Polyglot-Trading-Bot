//! Security utilities for trading bot protection
//!
//! This module provides comprehensive security features including:
//! - Rate limiting and DoS protection
//! - Input validation and sanitization
//! - Security audit and monitoring
//! - Access control and authentication
//! - Secure communication protocols

pub mod access_control;
pub mod audit;
pub mod input_validation;
pub mod monitoring;
pub mod rate_limiting;
pub mod secure_communication;

pub use access_control::{AccessController, Role, Permission};
pub use audit::{SecurityAuditor, SecurityEvent, AuditLogger};
pub use input_validation::{InputValidator, ValidationRule};
pub use monitoring::{SecurityMonitor, ThreatDetector, AlertLevel};
pub use rate_limiting::{RateLimiter, TokenBucket, SlidingWindow};
pub use secure_communication::{SecureChannel, MessageAuthenticator};

use anyhow::Result;

/// Main security interface for the trading bot
pub struct SecurityEngine {
    access_controller: AccessController,
    auditor: SecurityAuditor,
    input_validator: InputValidator,
    monitor: SecurityMonitor,
    rate_limiter: RateLimiter,
    secure_channel: SecureChannel,
}

impl SecurityEngine {
    /// Create a new security engine
    pub fn new() -> Result<Self> {
        Ok(Self {
            access_controller: AccessController::new()?,
            auditor: SecurityAuditor::new()?,
            input_validator: InputValidator::new()?,
            monitor: SecurityMonitor::new()?,
            rate_limiter: RateLimiter::new()?,
            secure_channel: SecureChannel::new()?,
        })
    }

    /// Initialize security engine with configuration
    pub fn initialize(&mut self) -> Result<()> {
        self.access_controller.setup_default_roles()?;
        self.monitor.start_monitoring()?;
        self.auditor.initialize_logging()?;
        Ok(())
    }

    /// Get access controller
    pub fn access_controller(&self) -> &AccessController {
        &self.access_controller
    }

    /// Get auditor
    pub fn auditor(&self) -> &SecurityAuditor {
        &self.auditor
    }

    /// Get input validator
    pub fn input_validator(&self) -> &InputValidator {
        &self.input_validator
    }

    /// Get security monitor
    pub fn monitor(&self) -> &SecurityMonitor {
        &self.monitor
    }

    /// Get rate limiter
    pub fn rate_limiter(&self) -> &RateLimiter {
        &self.rate_limiter
    }

    /// Get secure channel
    pub fn secure_channel(&self) -> &SecureChannel {
        &self.secure_channel
    }

    /// Perform security check on incoming request
    pub fn check_request(&self, client_id: &str, endpoint: &str, data: &[u8]) -> Result<SecurityCheckResult> {
        // Rate limiting check
        if !self.rate_limiter.check_limit(client_id, endpoint)? {
            self.auditor.log_security_event(SecurityEvent::RateLimitExceeded {
                client_id: client_id.to_string(),
                endpoint: endpoint.to_string(),
                timestamp: chrono::Utc::now(),
            })?;
            return Ok(SecurityCheckResult::RateLimited);
        }

        // Access control check
        if !self.access_controller.check_access(client_id, endpoint)? {
            self.auditor.log_security_event(SecurityEvent::AccessDenied {
                client_id: client_id.to_string(),
                endpoint: endpoint.to_string(),
                timestamp: chrono::Utc::now(),
            })?;
            return Ok(SecurityCheckResult::AccessDenied);
        }

        // Input validation
        if let Err(validation_error) = self.input_validator.validate(data, endpoint) {
            self.auditor.log_security_event(SecurityEvent::InvalidInput {
                client_id: client_id.to_string(),
                endpoint: endpoint.to_string(),
                error: validation_error.to_string(),
                timestamp: chrono::Utc::now(),
            })?;
            return Ok(SecurityCheckResult::InvalidInput);
        }

        // Threat detection
        if self.monitor.detect_threat(client_id, data)? {
            self.auditor.log_security_event(SecurityEvent::ThreatDetected {
                client_id: client_id.to_string(),
                threat_type: "Suspicious pattern".to_string(),
                timestamp: chrono::Utc::now(),
            })?;
            return Ok(SecurityCheckResult::ThreatDetected);
        }

        Ok(SecurityCheckResult::Allowed)
    }

    /// Log security event
    pub fn log_security_event(&self, event: SecurityEvent) -> Result<()> {
        self.auditor.log_security_event(event)
    }

    /// Get security status
    pub fn get_security_status(&self) -> SecurityStatus {
        SecurityStatus {
            monitoring_active: self.monitor.is_active(),
            threats_detected: self.monitor.get_threat_count(),
            audit_log_size: self.auditor.get_log_size(),
            active_rate_limits: self.rate_limiter.get_active_limits(),
            last_security_check: chrono::Utc::now(),
        }
    }

    /// Perform security audit
    pub fn perform_security_audit(&self) -> Result<SecurityAuditReport> {
        self.auditor.perform_audit()
    }
}

/// Result of security check
#[derive(Debug, Clone, PartialEq)]
pub enum SecurityCheckResult {
    Allowed,
    RateLimited,
    AccessDenied,
    InvalidInput,
    ThreatDetected,
}

/// Security status information
#[derive(Debug, Clone)]
pub struct SecurityStatus {
    pub monitoring_active: bool,
    pub threats_detected: u64,
    pub audit_log_size: usize,
    pub active_rate_limits: usize,
    pub last_security_check: chrono::DateTime<chrono::Utc>,
}

/// Security audit report
#[derive(Debug, Clone)]
pub struct SecurityAuditReport {
    pub audit_time: chrono::DateTime<chrono::Utc>,
    pub total_events: u64,
    pub security_events: Vec<SecurityEvent>,
    pub recommendations: Vec<String>,
    pub risk_score: f64,
}

impl Default for SecurityEngine {
    fn default() -> Self {
        Self::new().unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_security_engine_initialization() {
        let engine = SecurityEngine::new().unwrap();
        let status = engine.get_security_status();

        assert!(!status.monitoring_active); // Not started yet
        assert_eq!(status.threats_detected, 0);
    }

    #[test]
    fn test_security_check_allowed() {
        let engine = SecurityEngine::new().unwrap();
        let result = engine.check_request("test_client", "/api/health", b"{}");

        assert!(matches!(result, Ok(SecurityCheckResult::Allowed)));
    }

    #[test]
    fn test_security_audit() {
        let engine = SecurityEngine::new().unwrap();
        let report = engine.perform_security_audit().unwrap();

        assert!(report.audit_time <= chrono::Utc::now());
        assert!(report.risk_score >= 0.0);
    }
}