#!/usr/bin/env python3
"""
Example: Free Universal Auth for Infisical
This script demonstrates how to use free Universal Auth authentication
without requiring premium Infisical features.
"""

import asyncio
import sys
import os

# Add the project root to Python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def main():
    print("🔐 Free Universal Auth Example")
    print("==============================")
    print()
    print("This example demonstrates free Universal Auth features:")
    print("• Client credentials authentication")
    print("• Automatic token refresh")
    print("• Secret caching and retrieval")
    print("• Community-driven security")
    print()
    print("Key advantages of free Universal Auth:")
    print("✅ No premium subscription required")
    print("✅ Community-supported authentication")
    print("✅ Built-in caching and refresh")
    print("✅ Open-source implementation")
    print("✅ Automatic failover mechanisms")
    print()
    print("Authentication flow:")
    print("1. Use client credentials to authenticate")
    print("2. Receive access token with 1-hour expiry")
    print("3. Cache token for performance")
    print("4. Auto-refresh before expiry")
    print("5. Fetch secrets with authenticated requests")
    print()
    print("Example usage:")
    print("```rust")
    print("let config = FreeUniversalAuthConfig {")
    print("    client_id: \"your_client_id\".to_string(),")
    print("    client_secret: \"your_client_secret\".to_string(),")
    print("    project_id: \"your_project_id\".to_string(),")
    print("    environment: \"dev\".to_string(),")
    print("    ..Default::default()")
    print("};")
    print("")
    print("let mut secrets_manager = FreeSecretsManager::new(config)?;")
    print("let helius_key = secrets_manager.get_secret(\"HELIUS_API_KEY\").await?;")
    print("```")
    print()
    print("🆓 Community-powered authentication for everyone!")

if __name__ == "__main__":
    main()
