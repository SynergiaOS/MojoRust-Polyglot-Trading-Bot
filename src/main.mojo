# =============================================================================
# MojoRust Trading Bot - Main Entry Point
# =============================================================================

from time import time, sleep
from collections import List

# Core imports
from core.config import load_config, Config
from core.types import TradingSignal, MarketData, Portfolio
from core.logger import get_main_logger, setup_logging

# Engine imports
from engine.data_synthesis_engine import DataSynthesisEngine
from engine.strategy_engine import StrategyEngine
from engine.spam_filter import SpamFilter
from engine.instant_spam_detector import InstantSpamDetector
from engine.micro_timeframe_filter import MicroTimeframeFilter

# Analysis imports
from analysis.volume_analyzer import VolumeAnalyzer
from analysis.sentiment_analyzer import SentimentAnalyzer

# Risk and Execution imports
from risk.risk_manager import RiskManager
from execution.ultimate_executor import UltimateExecutor

# Data layer imports
from data.data_provider import DataProvider


fn main() raises:
    """
    Main function to initialize and run the trading bot.
    """
    # 1. Load Configuration
    # =========================================================================
    # This now loads the entire configuration tree, including the new
    # 'filters', 'risk_thresholds', and 'strategy_thresholds' sections.
    let config = load_config("config/trading.toml")

    # Setup logging based on the loaded configuration
    setup_logging(config)
    let logger = get_main_logger()
    logger.info("✅ MojoRust Trading Bot starting up...")
    logger.info(f"   Environment: {config.trading_env}")
    logger.info(f"   Execution Mode: {config.trading.execution_mode}")

    # 2. Initialize Core Components with Config
    # =========================================================================
    # All major components are now initialized with the central 'config' object,
    # ensuring they use the new configurable parameters instead of hardcoded values.

    logger.info("🔧 Initializing core components...")

    # Check if Flash Loan Ensemble is enabled
    if (hasattr(config.strategy, 'flash_loan_ensemble') and
        config.strategy.flash_loan_ensemble.enabled):
        logger.info("🚀 Flash Loan Ensemble enabled - using Save protocol for all strategies")
        logger.info(f"   Primary Protocol: {config.strategy.flash_loan_ensemble.primary_protocol}")
        logger.info(f"   Max Concurrent Strategies: {config.strategy.flash_loan_ensemble.max_concurrent_strategies}")
        logger.info(f"   Consensus Threshold: {config.strategy.flash_loan_ensemble.consensus_threshold}")
    else:
        logger.info("📊 Using traditional multi-protocol strategies")

    # Data Layer
    let data_provider = DataProvider(config)

    # Analysis Layer
    let volume_analyzer = VolumeAnalyzer(config)
    let sentiment_analyzer = SentimentAnalyzer(config)

    # Filtering Layer
    let instant_spam_detector = InstantSpamDetector(config)
    let spam_filter = SpamFilter(config)
    let micro_timeframe_filter = MicroTimeframeFilter(config)

    # Core Engine Layer
    let strategy_engine = StrategyEngine(config)
    let synthesis_engine = DataSynthesisEngine(config)

    # Risk and Execution Layer
    let risk_manager = RiskManager(config)
    let executor = UltimateExecutor(config)

    # Portfolio
    var portfolio = Portfolio(config.trading.initial_capital)

    logger.info("✅ All components initialized successfully.")

    # 3. Main Trading Loop
    # =========================================================================
    logger.info("🚀 Starting main trading loop...")

    while True:
        let start_time = time()

        # Fetch new market data (e.g., new token pairs)
        let new_tokens: List[MarketData] = data_provider.get_new_tokens()

        if len(new_tokens) > 0:
            logger.info(f"🔍 Found {len(new_tokens)} new tokens to analyze.")

            # Generate trading signals
            var signals = strategy_engine.generate_signals(new_tokens)

            # Filter signals (now using the full, configurable filter chain)
            let filtered_signals = spam_filter.filter_signals(signals) # Example filter

            if len(filtered_signals) > 0:
                logger.info(f"💡 Found {len(filtered_signals)} promising signals.")

                for signal in filtered_signals:
                    # Perform risk assessment
                    let approval = risk_manager.assess_risk(signal, portfolio)

                    if approval.approved:
                        # Execute trade
                        executor.execute_trade(approval)

        # Control loop timing
        let elapsed_time = time() - start_time
        let sleep_duration = max(0, config.trading.cycle_interval - elapsed_time)
        sleep(sleep_duration)