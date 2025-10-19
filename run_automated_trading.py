#!/usr/bin/env python3
"""
MojoRust Automated Trading System Launcher

Main entry point for the fully automated trading system.
This script starts all components and begins automated trading
without requiring manual intervention.

Usage:
    python run_automated_trading.py [--mode MODE] [--config CONFIG_FILE]

Modes:
    fully_automatic - Complete automation with no manual intervention
    semi_automatic - Automation with manual oversight
    monitoring_only - Monitor without trading
"""

import asyncio
import argparse
import json
import logging
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

import redis.asyncio as aioredis
from dotenv import load_dotenv

# Add src to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from src.automation.automated_trading_orchestrator import (
    AutomatedTradingOrchestrator,
    AutomationMode,
    SystemStatus
)
from src.automation.auto_token_discovery import AutoTokenDiscovery
from src.automation.auto_strategy_executor import AutoStrategyExecutor
from src.control.strategy_manager import StrategyManager
from src.control.risk_controller import RiskController
from src.control.trading_controller import TradingController
from src.api.trading_control_api import TradingControlAPI, TradingStrategy

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('logs/automated_trading.log', mode='a')
    ]
)

logger = logging.getLogger(__name__)

class AutomatedTradingLauncher:
    """Main launcher for the automated trading system."""

    def __init__(self, config_file: Optional[str] = None):
        self.config_file = config_file
        self.config = self._load_configuration()
        self.redis_client: Optional[aioredio.Redis] = None
        self.orchestrator: Optional[AutomatedTradingOrchestrator] = None

    def _load_configuration(self) -> Dict[str, Any]:
        """Load configuration from file or defaults."""
        try:
            # Load environment variables
            load_dotenv()

            # Default configuration
            default_config = {
                "redis_url": os.getenv('REDIS_URL', 'redis://localhost:6379'),
                "automation_mode": "fully_automatic",
                "trading_enabled": True,
                "discovery_enabled": True,
                "risk_management_enabled": True,
                "auto_recovery": True,
                "emergency_stop_enabled": True,
                "max_daily_trades": 100,
                "daily_loss_limit": 0.1,
                "initial_capital": 1.0,
                "execution_mode": "paper",
                "default_strategy": "enhanced_rsi",
                "log_level": "INFO",
                "health_check_port": 8084,
                "monitoring_enabled": True,
                "maintenance_windows": [],
                "component_health_checks": True
            }

            # Load from file if provided
            if self.config_file and Path(self.config_file).exists():
                with open(self.config_file, 'r') as f:
                    file_config = json.load(f)
                    default_config.update(file_config)
                logger.info(f"Loaded configuration from {self.config_file}")
            else:
                logger.info("Using default configuration")

            return default_config

        except Exception as e:
            logger.error(f"Error loading configuration: {e}")
            return {}

    async def initialize(self):
        """Initialize the automated trading system."""
        try:
            logger.info("Initializing Automated Trading System...")

            # Setup logging level
            logging.getLogger().setLevel(getattr(logging, self.config.get('log_level', 'INFO')))

            # Ensure logs directory exists
            Path('logs').mkdir(exist_ok=True)

            # Initialize Redis connection
            self.redis_client = aioredis.from_url(self.config['redis_url'])
            await self.redis_client.ping()
            logger.info("Connected to Redis")

            # Initialize orchestrator
            self.orchestrator = AutomatedTradingOrchestrator(self.redis_client)
            await self.orchestrator.initialize()

            # Update orchestrator configuration
            await self.orchestrator.update_configuration({
                'mode': AutomationMode(self.config['automation_mode']),
                'trading_enabled': self.config['trading_enabled'],
                'discovery_enabled': self.config['discovery_enabled'],
                'risk_management_enabled': self.config['risk_management_enabled'],
                'auto_recovery': self.config['auto_recovery'],
                'emergency_stop_enabled': self.config['emergency_stop_enabled'],
                'max_daily_trades': self.config['max_daily_trades'],
                'daily_loss_limit': self.config['daily_loss_limit'],
                'maintenance_windows': self.config.get('maintenance_windows', [])
            })

            logger.info("Automated Trading System initialized successfully")

        except Exception as e:
            logger.error(f"Failed to initialize Automated Trading System: {e}")
            raise

    async def start_trading(self):
        """Start the automated trading system."""
        try:
            logger.info("Starting Automated Trading...")

            # Start in specified mode
            mode = AutomationMode(self.config['automation_mode'])
            await self.orchestrator.start_automated_trading(mode)

            # Log startup information
            await self._log_startup_info()

            logger.info(f"Automated Trading started in {mode.value} mode")

        except Exception as e:
            logger.error(f"Failed to start Automated Trading: {e}")
            raise

    async def run(self):
        """Run the automated trading system."""
        try:
            # Initialize
            await self.initialize()

            # Start trading
            await self.start_trading()

            # Keep the system running
            logger.info("Automated Trading System is now running...")
            logger.info("Press Ctrl+C to stop the system")

            # Main loop - handle graceful shutdown
            while True:
                try:
                    # Get system status
                    status = await self.orchestrator.get_system_status()

                    # Log periodic status updates
                    if status.get('system_status') == 'running':
                        logger.info(f"System running - Uptime: {status.get('uptime_seconds', 0):.0f}s, "
                                   f"Trades: {status.get('automation_metrics', {}).get('trades_executed', 0)}, "
                                   f"PnL: {status.get('automation_metrics', {}).get('total_pnl', 0.0):.4f} SOL")

                    # Wait for next status check
                    await asyncio.sleep(300)  # 5 minutes

                except KeyboardInterrupt:
                    logger.info("Received keyboard interrupt, initiating shutdown...")
                    break
                except Exception as e:
                    logger.error(f"Error in main loop: {e}")
                    await asyncio.sleep(60)  # Wait before retrying

        except KeyboardInterrupt:
            logger.info("Received keyboard interrupt")
        except Exception as e:
            logger.error(f"Fatal error in run loop: {e}")
        finally:
            await self.shutdown()

    async def shutdown(self):
        """Gracefully shutdown the system."""
        try:
            logger.info("Shutting down Automated Trading System...")

            if self.orchestrator:
                await self.orchestrator.shutdown()

            if self.redis_client:
                await self.redis_client.close()

            logger.info("Automated Trading System shutdown complete")

        except Exception as e:
            logger.error(f"Error during shutdown: {e}")

    async def _log_startup_info(self):
        """Log detailed startup information."""
        try:
            logger.info("=" * 60)
            logger.info("🚀 MojoRust Automated Trading System")
            logger.info("=" * 60)
            logger.info(f"Mode: {self.config['automation_mode']}")
            logger.info(f"Trading Enabled: {self.config['trading_enabled']}")
            logger.info(f"Discovery Enabled: {self.config['discovery_enabled']}")
            logger.info(f"Risk Management: {self.config['risk_management_enabled']}")
            logger.info(f"Execution Mode: {self.config['execution_mode']}")
            logger.info(f"Initial Capital: {self.config['initial_capital']} SOL")
            logger.info(f"Default Strategy: {self.config['default_strategy']}")
            logger.info(f"Max Daily Trades: {self.config['max_daily_trades']}")
            logger.info(f"Daily Loss Limit: {self.config['daily_loss_limit'] * 100:.1f}%")
            logger.info(f"Redis URL: {self.config['redis_url']}")
            logger.info("=" * 60)

        except Exception as e:
            logger.error(f"Error logging startup info: {e}")

    def create_sample_config(self):
        """Create a sample configuration file."""
        try:
            sample_config = {
                "redis_url": "redis://localhost:6379",
                "automation_mode": "fully_automatic",
                "trading_enabled": True,
                "discovery_enabled": True,
                "risk_management_enabled": True,
                "auto_recovery": True,
                "emergency_stop_enabled": True,
                "max_daily_trades": 100,
                "daily_loss_limit": 0.1,
                "initial_capital": 1.0,
                "execution_mode": "paper",
                "default_strategy": "enhanced_rsi",
                "log_level": "INFO",
                "health_check_port": 8084,
                "monitoring_enabled": True,
                "maintenance_windows": [
                    {
                        "start_hour": 2,
                        "end_hour": 3,
                        "description": "Daily maintenance window"
                    }
                ]
            }

            config_file = Path("automated_trading_config.json")
            with open(config_file, 'w') as f:
                json.dump(sample_config, f, indent=2)

            print(f"Sample configuration created: {config_file}")
            print("Edit this file to customize your trading parameters.")

        except Exception as e:
            print(f"Error creating sample configuration: {e}")

async def main():
    """Main entry point."""
    try:
        # Parse command line arguments
        parser = argparse.ArgumentParser(description="MojoRust Automated Trading System")
        parser.add_argument(
            "--mode",
            choices=["fully_automatic", "semi_automatic", "monitoring_only"],
            default="fully_automatic",
            help="Automation mode"
        )
        parser.add_argument(
            "--config",
            type=str,
            help="Configuration file path"
        )
        parser.add_argument(
            "--create-config",
            action="store_true",
            help="Create sample configuration file"
        )
        parser.add_argument(
            "--paper",
            action="store_true",
            help="Force paper trading mode"
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Dry run mode (no actual trades)"
        )

        args = parser.parse_args()

        # Create sample configuration if requested
        if args.create_config:
            launcher = AutomatedTradingLauncher()
            launcher.create_sample_config()
            return

        # Create launcher
        launcher = AutomatedTradingLauncher(args.config)

        # Override mode if specified
        if args.mode:
            launcher.config['automation_mode'] = args.mode

        # Force paper trading if requested
        if args.paper:
            launcher.config['execution_mode'] = 'paper'
            logger.info("Paper trading mode enforced")

        # Dry run mode
        if args.dry_run:
            launcher.config['trading_enabled'] = False
            launcher.config['automation_mode'] = 'monitoring_only'
            logger.info("Dry run mode - no actual trades will be executed")

        # Run the system
        await launcher.run()

    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    # Run the automated trading system
    asyncio.run(main())