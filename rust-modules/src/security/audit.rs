//! Audit module for Mojo Trading Bot
//!
//! Provides audit logging, security event tracking,
//! and compliance monitoring for trading operations.

use std::collections::VecDeque;
use std::time::{SystemTime, UNIX_EPOCH};
use serde::{Deserialize, Serialize};

/// Audit event types
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuditEventType {
    UserLogin,
    UserLogout,
    TradePlaced,
    TradeCancelled,
    ConfigurationChange,
    SecurityViolation,
    SystemError,
    ApiAccess,
}

/// Audit event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuditEvent {
    pub timestamp: u64,
    pub event_type: AuditEventType,
    pub user_id: Option<String>,
    pub details: String,
    pub ip_address: Option<String>,
    pub user_agent: Option<String>,
}

/// Audit logger
pub struct AuditLogger {
    events: VecDeque<AuditEvent>,
    max_events: usize,
}

impl AuditLogger {
    /// Create new audit logger
    pub fn new(max_events: usize) -> Self {
        Self {
            events: VecDeque::with_capacity(max_events),
            max_events,
        }
    }

    /// Log audit event
    pub fn log_event(&mut self, event: AuditEvent) {
        if self.events.len() >= self.max_events {
            self.events.pop_front();
        }
        self.events.push_back(event);
    }

    /// Get recent events
    pub fn get_recent_events(&self, limit: Option<usize>) -> Vec<&AuditEvent> {
        let limit = limit.unwrap_or(self.events.len());
        self.events.iter().rev().take(limit).collect()
    }

    /// Clear all events
    pub fn clear(&mut self) {
        self.events.clear();
    }
}

impl Default for AuditLogger {
    fn default() -> Self {
        Self::new(10000)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_audit_logging() {
        let mut logger = AuditLogger::new(5);

        let event = AuditEvent {
            timestamp: SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs(),
            event_type: AuditEventType::UserLogin,
            user_id: Some("test_user".to_string()),
            details: "User logged in successfully".to_string(),
            ip_address: Some("127.0.0.1".to_string()),
            user_agent: Some("Mozilla/5.0".to_string()),
        };

        logger.log_event(event);
        assert_eq!(logger.get_recent_events(None).len(), 1);
    }
}