//! Access control module for Mojo Trading Bot
//!
//! Provides role-based access control, permissions management,
//! and authorization checks for API endpoints and operations.

use std::collections::HashMap;
use std::sync::Arc;
use anyhow::Result;

/// User roles for access control
#[derive(Debug, Clone, PartialEq)]
pub enum Role {
    Admin,
    Trader,
    Viewer,
    ReadOnly,
}

/// Permission types
#[derive(Debug, Clone, PartialEq)]
pub enum Permission {
    // Trading permissions
    PlaceTrade,
    CancelTrade,
    ViewPositions,

    // Configuration permissions
    ViewConfig,
    ModifyConfig,

    // Monitoring permissions
    ViewLogs,
    ViewMetrics,

    // System permissions
    ManageUsers,
    SystemAdmin,
}

/// Access control manager
pub struct AccessControlManager {
    user_roles: HashMap<String, Role>,
    role_permissions: HashMap<Role, Vec<Permission>>,
}

impl AccessControlManager {
    /// Create new access control manager
    pub fn new() -> Self {
        let mut manager = Self {
            user_roles: HashMap::new(),
            role_permissions: HashMap::new(),
        };

        // Initialize default permissions
        manager.setup_default_permissions();
        manager
    }

    /// Setup default role permissions
    fn setup_default_permissions(&mut self) {
        // Admin permissions
        self.role_permissions.insert(
            Role::Admin,
            vec![
                Permission::PlaceTrade,
                Permission::CancelTrade,
                Permission::ViewPositions,
                Permission::ViewConfig,
                Permission::ModifyConfig,
                Permission::ViewLogs,
                Permission::ViewMetrics,
                Permission::ManageUsers,
                Permission::SystemAdmin,
            ],
        );

        // Trader permissions
        self.role_permissions.insert(
            Role::Trader,
            vec![
                Permission::PlaceTrade,
                Permission::CancelTrade,
                Permission::ViewPositions,
                Permission::ViewConfig,
                Permission::ViewLogs,
                Permission::ViewMetrics,
            ],
        );

        // Viewer permissions
        self.role_permissions.insert(
            Role::Viewer,
            vec![
                Permission::ViewPositions,
                Permission::ViewConfig,
                Permission::ViewLogs,
                Permission::ViewMetrics,
            ],
        );

        // Read-only permissions
        self.role_permissions.insert(
            Role::ReadOnly,
            vec![
                Permission::ViewPositions,
                Permission::ViewMetrics,
            ],
        );
    }

    /// Add user with role
    pub fn add_user(&mut self, user_id: &str, role: Role) {
        self.user_roles.insert(user_id.to_string(), role);
    }

    /// Check if user has permission
    pub fn has_permission(&self, user_id: &str, permission: Permission) -> bool {
        if let Some(role) = self.user_roles.get(user_id) {
            if let Some(permissions) = self.role_permissions.get(role) {
                return permissions.contains(&permission);
            }
        }
        false
    }

    /// Get user role
    pub fn get_user_role(&self, user_id: &str) -> Option<&Role> {
        self.user_roles.get(user_id)
    }

    /// Update user role
    pub fn update_user_role(&mut self, user_id: &str, role: Role) -> Result<()> {
        if self.user_roles.contains_key(user_id) {
            self.user_roles.insert(user_id.to_string(), role);
            Ok(())
        } else {
            Err(anyhow::anyhow!("User not found: {}", user_id))
        }
    }

    /// Remove user
    pub fn remove_user(&mut self, user_id: &str) -> Result<()> {
        if self.user_roles.remove(user_id).is_some() {
            Ok(())
        } else {
            Err(anyhow::anyhow!("User not found: {}", user_id))
        }
    }
}

impl Default for AccessControlManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_access_control() {
        let mut acm = AccessControlManager::new();
        acm.add_user("admin_user", Role::Admin);
        acm.add_user("trader_user", Role::Trader);

        assert!(acm.has_permission("admin_user", Permission::SystemAdmin));
        assert!(acm.has_permission("trader_user", Permission::PlaceTrade));
        assert!(!acm.has_permission("trader_user", Permission::SystemAdmin));
        assert!(!acm.has_permission("unknown_user", Permission::ViewPositions));
    }
}