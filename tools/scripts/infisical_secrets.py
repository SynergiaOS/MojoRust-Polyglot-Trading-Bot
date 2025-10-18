#!/usr/bin/env python3
"""
Infisical Secrets Management Integration for MojoRust Trading Bot

This script manages secrets from Infisical, providing secure configuration
for the trading bot in production environments.

Usage:
    python scripts/infisical_secrets.py [--init|--update|--env]

Environment Variables Required:
    INFISICAL_CLIENT_ID
    INFISICAL_CLIENT_SECRET
    INFISICAL_PROJECT_ID
    INFISICAL_ENVIRONMENT
"""

import os
import sys
import json
import argparse
import logging
from typing import Dict, Any, Optional
from pathlib import Path

# Try to import infisical
try:
    from infisical import Client, InfisicalOptions
    INFISICAL_AVAILABLE = True
except ImportError:
    INFISICAL_AVAILABLE = False
    print("Warning: infisical package not installed. Install with: pip install infisical")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class InfisicalSecretsManager:
    """Manages secrets from Infisical for the trading bot"""

    def __init__(self, client_id: Optional[str] = None, client_secret: Optional[str] = None,
                 project_id: Optional[str] = None, environment: str = "dev"):
        """
        Initialize Infisical client

        Args:
            client_id: Infisical client ID
            client_secret: Infisical client secret
            project_id: Infisical project ID
            environment: Environment (dev, staging, production)
        """
        self.client_id = client_id or os.getenv('INFISICAL_CLIENT_ID')
        self.client_secret = client_secret or os.getenv('INFISICAL_CLIENT_SECRET')
        self.project_id = project_id or os.getenv('INFISICAL_PROJECT_ID')
        self.environment = environment

        if not all([self.client_id, self.client_secret, self.project_id]):
            logger.warning("Missing Infisical credentials. Using fallback environment variables.")

        self.client = None
        if INFISICAL_AVAILABLE and all([self.client_id, self.client_secret, self.project_id]):
            try:
                self.client = Client(
                    client_id=self.client_id,
                    client_secret=self.client_secret,
                    project_id=self.project_id,
                    environment=self.environment
                )
                logger.info(f"Connected to Infisical for project {self.project_id} in {self.environment}")
            except Exception as e:
                logger.error(f"Failed to connect to Infisical: {e}")

    def get_all_secrets(self) -> Dict[str, str]:
        """
        Retrieve all secrets from Infisical

        Returns:
            Dictionary of secret key-value pairs
        """
        if not self.client:
            logger.warning("Infisical client not available. Using environment variables.")
            return self._get_fallback_secrets()

        try:
            secrets = self.client.get_all_secrets()
            return {secret.secret_key: secret.secret_value for secret in secrets}
        except Exception as e:
            logger.error(f"Failed to fetch secrets from Infisical: {e}")
            return self._get_fallback_secrets()

    def get_secret(self, key: str) -> Optional[str]:
        """
        Get a specific secret from Infisical

        Args:
            key: Secret key name

        Returns:
            Secret value or None if not found
        """
        if not self.client:
            return os.getenv(key)

        try:
            secret = self.client.get_secret(key)
            return secret.secret_value if secret else os.getenv(key)
        except Exception as e:
            logger.error(f"Failed to fetch secret {key} from Infisical: {e}")
            return os.getenv(key)

    def _get_fallback_secrets(self) -> Dict[str, str]:
        """
        Fallback to environment variables when Infisical is not available

        Returns:
            Dictionary of environment variables
        """
        # List of expected environment variables for the trading bot
        expected_vars = [
            'HELIUS_API_KEY',
            'QUICKNODE_RPC_URL',
            'WALLET_ADDRESS',
            'WALLET_PRIVATE_KEY_PATH',
            'SNIPER_WALLET_PRIVATE_KEY',
            'PUMPPORTAL_API_KEY',
            'HONEYPOT_API_KEY',
            'TWITTER_API_KEY',
            'TWITTER_API_SECRET',
            'TWITTER_ACCESS_TOKEN',
            'TWITTER_ACCESS_TOKEN_SECRET',
            'TWITTER_BEARER_TOKEN',
            'JITO_AUTH_KEY',
            'REDIS_URL',
            'TIMESCALEDB_URL',
            'CLAUDE_API_KEY',
            'GEYSER_ENDPOINT',
            'GEYSER_TOKEN',
            'JWT_SECRET',
            'ALERT_WEBHOOK_URL',
            'GRAFANA_ADMIN_PASSWORD',
            'PGADMIN_PASSWORD',
            'TRADING_ENV',
            'EXECUTION_MODE',
            'INITIAL_CAPITAL',
            'MAX_POSITION_SIZE',
            'MAX_DRAWDOWN',
            'MIN_PROFIT_THRESHOLD',
            'ARBITRAGE_ENABLED',
            'RUST_FFI_ENABLED'
        ]

        secrets = {}
        for var in expected_vars:
            value = os.getenv(var)
            if value:
                secrets[var] = value

        return secrets

    def create_env_file(self, output_path: str = '.env', secrets: Optional[Dict[str, str]] = None):
        """
        Create .env file from secrets

        Args:
            output_path: Path to write .env file
            secrets: Dictionary of secrets (if None, fetches from Infisical)
        """
        if secrets is None:
            secrets = self.get_all_secrets()

        # Add some default values for required variables
        defaults = {
            'TRADING_ENV': 'production',
            'EXECUTION_MODE': 'paper',
            'LOG_LEVEL': 'INFO',
            'ARBITRAGE_ENABLED': 'true',
            'RUST_FFI_ENABLED': 'true',
            'ENABLE_RUST_CONSUMER': 'true',
            'MOCK_APIS': 'false',
            'TIMESCALEDB_PORT': '5434'
        }

        # Merge secrets with defaults
        final_secrets = {**defaults, **secrets}

        # Write .env file
        env_path = Path(output_path)
        with open(env_path, 'w') as f:
            f.write("# Auto-generated by Infisical Secrets Manager\n")
            f.write("# DO NOT commit this file to version control\n")
            f.write("# ================================================\n\n")

            for key, value in sorted(final_secrets.items()):
                f.write(f"{key}={value}\n")

        logger.info(f"Created .env file at {env_path}")
        return env_path

    def create_docker_env_file(self, output_path: str = '.env.docker', secrets: Optional[Dict[str, str]] = None):
        """
        Create Docker-specific environment file

        Args:
            output_path: Path to write .env.docker file
            secrets: Dictionary of secrets
        """
        if secrets is None:
            secrets = self.get_all_secrets()

        # Docker-specific environment variables
        docker_secrets = {}

        # Include all secrets but filter out sensitive ones for logs
        sensitive_keys = ['PRIVATE_KEY', 'SECRET', 'PASSWORD', 'TOKEN']

        for key, value in secrets.items():
            if any(sensitive in key.upper() for sensitive in sensitive_keys):
                docker_secrets[key] = value
            else:
                docker_secrets[key] = value

        # Add Docker-specific defaults
        docker_defaults = {
            'BUILD_TARGET': 'production',
            'COMPOSE_PROJECT_NAME': 'mojorust',
            'DOCKER_BUILDKIT': '1'
        }

        final_secrets = {**docker_defaults, **docker_secrets}

        # Write .env.docker file
        docker_env_path = Path(output_path)
        with open(docker_env_path, 'w') as f:
            f.write("# Auto-generated by Infisical Secrets Manager for Docker\n")
            f.write("# DO NOT commit this file to version control\n")
            f.write("# ======================================================\n\n")

            for key, value in sorted(final_secrets.items()):
                f.write(f"{key}={value}\n")

        logger.info(f"Created .env.docker file at {docker_env_path}")
        return docker_env_path

def init_infisical():
    """Initialize Infisical configuration"""
    print("=== Infisical Setup ===")
    print("To set up Infisical secrets management:")
    print("1. Create account at https://app.infisical.com/")
    print("2. Create a new project")
    print("3. Get your Client ID, Client Secret, and Project ID")
    print("4. Set environment variables:")
    print("   export INFISICAL_CLIENT_ID=your_client_id")
    print("   export INFISICAL_CLIENT_SECRET=your_client_secret")
    print("   export INFISICAL_PROJECT_ID=your_project_id")
    print("   export INFISICAL_ENVIRONMENT=production")
    print("\nRequired secrets for the trading bot:")

    required_secrets = [
        ('HELIUS_API_KEY', 'Helius API key for Solana RPC access'),
        ('QUICKNODE_RPC_URL', 'QuickNode RPC endpoint URL'),
        ('WALLET_ADDRESS', 'Main trading wallet address'),
        ('WALLET_PRIVATE_KEY_PATH', 'Path to wallet private key file'),
        ('SNIPER_WALLET_PRIVATE_KEY', 'Sniper bot private key'),
        ('PUMPPORTAL_API_KEY', 'PumpPortal API key'),
        ('HONEYPOT_API_KEY', 'Honeypot detection API key'),
        ('JITO_AUTH_KEY', 'Jito authentication key'),
        ('REDIS_URL', 'Redis/DragonflyDB connection URL'),
        ('JWT_SECRET', 'JWT secret for API authentication')
    ]

    for secret, description in required_secrets:
        print(f"   {secret}: {description}")

def update_secrets():
    """Update secrets from Infisical and create environment files"""
    manager = InfisicalSecretsManager()
    secrets = manager.get_all_secrets()

    if not secrets:
        logger.error("No secrets found. Please check your Infisical configuration.")
        return False

    # Create .env file
    manager.create_env_file()

    # Create .env.docker file
    manager.create_docker_env_file()

    logger.info("Successfully updated secrets from Infisical")
    return True

def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Infisical secrets management')
    parser.add_argument('--init', action='store_true', help='Initialize Infisical setup')
    parser.add_argument('--update', action='store_true', help='Update secrets from Infisical')
    parser.add_argument('--env', action='store_true', help='Create environment files')
    parser.add_argument('--environment', default='production', help='Environment (dev/staging/production)')

    args = parser.parse_args()

    if args.init:
        init_infisical()
        return

    if args.update:
        if update_secrets():
            print("✅ Secrets updated successfully!")
        else:
            print("❌ Failed to update secrets")
            sys.exit(1)
        return

    if args.env:
        manager = InfisicalSecretsManager(environment=args.environment)
        manager.create_env_file()
        manager.create_docker_env_file()
        print("✅ Environment files created!")
        return

    # Default: show status
    manager = InfisicalSecretsManager()
    if manager.client:
        print("✅ Infisical client connected")
        secrets = manager.get_all_secrets()
        print(f"📊 Found {len(secrets)} secrets")
    else:
        print("❌ Infisical client not connected")
        print("Run with --init for setup instructions")

if __name__ == '__main__':
    main()