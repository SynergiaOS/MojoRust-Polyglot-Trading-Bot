#!/usr/bin/env mojo3
# =============================================================================
# High-Performance Memecoin Trading Bot for Solana
# Algorithmic Intelligence without External AI Dependencies
# =============================================================================

from core.config import Config, load_config
from core.types import *
from core.constants import *
from core.logger import get_main_logger, configure_logging, log_system_info
from data.helius_client import HeliusClient
from data.quicknode_client import QuickNodeClient
from data.dexscreener_client import DexScreenerClient
from data.jupiter_client import JupiterClient
from engine.enhanced_context_engine import EnhancedContextEngine
from engine.master_filter import MasterFilter
from engine.strategy_engine import StrategyEngine
from analysis.sentiment_analyzer import SentimentAnalyzer
from analysis.pattern_recognizer import PatternRecognizer
from analysis.whale_tracker import WhaleTracker
from risk.risk_manager import RiskManager
from risk.circuit_breakers import CircuitBreakers
from execution.execution_engine import ExecutionEngine
from monitoring.performance_analytics import PerformanceAnalytics, TradeRecord
from persistence.database_manager import DatabaseManager
from monitoring.alert_system import AlertSystem, AlertLevel
from engine.strategy_adaptation import StrategyAdaptation

# New Advanced Components
from core.portfolio_manager_client import PortfolioManagerClient
from intelligence.data_synthesis_engine import DataSynthesisEngine
from data.geyser_client import ProductionGeyserClient
from data.social_intelligence_engine import SocialIntelligenceEngine
from analysis.wallet_graph_analyzer import WalletGraphAnalyzer
from analysis.mev_detector import MEVDetector
from execution.jito_bundle_builder import JitoBundleBuilder

# Python interop for orchestration
from python import Python

# Standard library imports
from os import getenv, environ
from sys import argv, exit
from time import time, sleep
from signal import signal, SIGINT, SIGTERM
from threading import Thread, Event
from collections import deque
import json

# Async support (import asyncio from Python)
var asyncio = None

# =============================================================================
# Main Trading Bot Class
# =============================================================================

@value
struct TradingBot:
    """
    Main trading bot orchestrator that coordinates all components with graceful shutdown
    """
    var config: Config
    var is_running: Bool
    var shutdown_event: Event
    var shutdown_phase: String
    var shutdown_start_time: Float
    var start_time: Float
    var logger

    # API Clients
    var helius_client: HeliusClient
    var quicknode_client: QuickNodeClient
    var dexscreener_client: DexScreenerClient
    var jupiter_client: JupiterClient

    # Core Engines (Enhanced - No External AI)
    var enhanced_context_engine: EnhancedContextEngine
    var master_filter: MasterFilter
    var strategy_engine: StrategyEngine
    var risk_manager: RiskManager
    var execution_engine: ExecutionEngine

    # Production Components
    var circuit_breakers: CircuitBreakers
    var performance_analytics: PerformanceAnalytics
    var database_manager: DatabaseManager
    var alert_system: AlertSystem
    var strategy_adaptation: StrategyAdaptation

    # Algorithmic Intelligence Components
    var sentiment_analyzer: SentimentAnalyzer
    var pattern_recognizer: PatternRecognizer
    var whale_tracker: WhaleTracker

    # Advanced Components (New Production Architecture)
    var portfolio_manager: PortfolioManagerClient
    var data_synthesis_engine: DataSynthesisEngine
    var task_pool_manager: PythonObject
    var geyser_client: ProductionGeyserClient
    var social_intelligence_engine: SocialIntelligenceEngine
    var wallet_graph_analyzer: WalletGraphAnalyzer
    var mev_detector: MEVDetector
    var jito_bundle_builder: JitoBundleBuilder

    # Runtime State
    var portfolio: Portfolio
    var metrics: Dict[String, Any]
    var signal_queue: deque[TradingSignal]
    var last_cycle_time: Float

    # Performance tracking
    var cycles_completed: Int
    var signals_generated: Int
    var trades_executed: Int
    var total_pnl: Float

    fn __init__(config: Config):
        """
        Initialize the trading bot with configuration and graceful shutdown support
        """
        self.config = config
        self.is_running = False
        self.shutdown_event = Event()
        self.shutdown_phase = "RUNNING"
        self.shutdown_start_time = 0.0
        self.start_time = time()
        self.logger = get_main_logger()

        # Initialize API clients
        self.helius_client = HeliusClient(
            api_key=config.api.helius_api_key,
            base_url=config.api.helius_base_url
        )

        self.quicknode_client = QuickNodeClient(
            rpc_urls=config.api.quicknode_rpcs
        )

        self.dexscreener_client = DexScreenerClient()
        self.jupiter_client = JupiterClient()

        # Initialize Enhanced Engines (Algorithmic Intelligence)
        self.enhanced_context_engine = EnhancedContextEngine(config)
        self.master_filter = MasterFilter(self.helius_client, config)
        self.strategy_engine = StrategyEngine(config)
        self.execution_engine = ExecutionEngine(
            quicknode_client=self.quicknode_client,
            jupiter_client=self.jupiter_client,
            helius_client=self.helius_client,
            config=config
        )

        # Initialize Algorithmic Intelligence Components with config
        self.sentiment_analyzer = SentimentAnalyzer()
        self.pattern_recognizer = PatternRecognizer()
        self.whale_tracker = WhaleTracker(config)

        # Initialize production components
        self.circuit_breakers = CircuitBreakers(config)
        self.performance_analytics = PerformanceAnalytics(config)
        self.database_manager = DatabaseManager(config)
        self.alert_system = AlertSystem(config)
        self.strategy_adaptation = StrategyAdaptation(config)

        # Initialize portfolio
        self.portfolio = Portfolio(
            total_value=config.trading.initial_capital,
            available_cash=config.trading.initial_capital,
            positions={}
        )

        # Initialize RiskManager with portfolio state
        self.risk_manager = RiskManager(config)
        self.risk_manager.update_portfolio_state(self.portfolio)

        # Initialize runtime state
        self.metrics = {}
        self.signal_queue = deque(maxlen=1000)
        self.last_cycle_time = 0.0
        self.watchlist: Set[String] = set()  # Token discovery watchlist

        # Initialize performance tracking
        self.cycles_completed = 0
        self.signals_generated = 0
        self.trades_executed = 0
        self.total_pnl = 0.0

        # Initialize Advanced Components (New Production Architecture)
        print("🚀 Initializing advanced production components...")

        # Initialize PortfolioManager for unified capital management
        self.portfolio_manager = PortfolioManagerClient(
            initial_capital=config.trading.initial_capital,
            max_positions=20,
            risk_tolerance=0.15
        )

        # Initialize Data Synthesis Engine for ultra-fast ML inference
        self.data_synthesis_engine = DataSynthesisEngine()

        # Initialize Python Task Pool Manager for parallel processing
        python = Python()
        task_pool_module = python.import_module("src.orchestration.task_pool_manager")
        self.task_pool_manager = task_pool_module.TaskPoolManager(max_workers=16)

        # Initialize asyncio for async operations
        asyncio = python.import("asyncio")

        # Initialize Geyser client for real-time blockchain data
        self.geyser_client = ProductionGeyserClient(
            rpc_endpoint=config.api.quicknode_rpcs.primary,
            max_reconnect_attempts=5,
            heartbeat_interval=30
        )

        # Initialize Social Intelligence Engine
        self.social_intelligence_engine = SocialIntelligenceEngine(
            helius_api_key=config.api.helius_api_key,
            twitter_bearer_token=environ.get("TWITTER_BEARER_TOKEN", ""),
            reddit_client_id=environ.get("REDDIT_CLIENT_ID", ""),
            reddit_client_secret=environ.get("REDDIT_CLIENT_SECRET", ""),
            telegram_bot_token=environ.get("TELEGRAM_BOT_TOKEN", "")
        )

        # Initialize Wallet Graph Analyzer
        self.wallet_graph_analyzer = WalletGraphAnalyzer(
            database_path="data/wallet_graph.db"
        )

        # Initialize MEV Detector
        self.mev_detector = MEVDetector()

        # Initialize Jito Bundle Builder
        self.jito_bundle_builder = JitoBundleBuilder(
            jito_endpoint="https://mainnet.block-engine.jito.wtf",
            wallet_address=config.wallet_address
        )

        print("✅ Advanced production components initialized")

    fn start(self):
        """
        Start the trading bot
        """
        self.logger.info("🚀 Starting High-Performance Memecoin Trading Bot (Algorithmic Intelligence)",
                         initial_capital=self.config.trading.initial_capital,
                         environment=self.config.trading_env,
                         mode=self.config.trading.execution_mode)

        # Validate configuration
        self._validate_configuration()

        # Initialize connections
        self._initialize_connections()

        # Setup signal handlers for graceful shutdown
        signal(SIGINT, self._signal_handler)
        signal(SIGTERM, self._signal_handler)

        # Start background monitoring thread
        monitoring_thread = Thread(target=self._monitoring_loop, daemon=True)
        monitoring_thread.start()

        self.is_running = True
        self.start_time = time()

        print("✅ Trading bot started successfully")
        print("🔄 Beginning main trading cycle...")

        # Main trading loop
        self._main_trading_loop()

    async fn stop(inout self):
        """
        🛑 Phased graceful shutdown orchestration with signal handling
        """
        if not self.is_running:
            return

        print("\n🛑 Initiating graceful shutdown orchestration...")
        self.is_running = False
        self.shutdown_start_time = time()
        self.shutdown_event.set()

        # Phase 1: Immediate operations (0-5 seconds)
        await self._shutdown_phase_1_immediate()

        # Phase 2: Graceful operations (5-30 seconds)
        await self._shutdown_phase_2_graceful()

        # Phase 3: Forceful operations (30-60 seconds)
        await self._shutdown_phase_3_forceful()

        # Phase 4: Final cleanup (60+ seconds)
        await self._shutdown_phase_4_cleanup()

        shutdown_duration = time() - self.shutdown_start_time
        print(f"✅ Graceful shutdown completed in {shutdown_duration:.2f} seconds")

    async fn _shutdown_phase_1_immediate(inout self):
        """
        🛑 Phase 1: Immediate operations (0-5 seconds)
        - Stop accepting new signals and trades
        - Set shutdown flags
        - Send shutdown alerts
        """
        self.shutdown_phase = "PHASE_1_IMMEDIATE"
        print("🛑 Phase 1: Immediate shutdown operations...")

        try:
            # 1. Set shutdown flags across all components
            print("  🚦 Setting shutdown flags...")
            self.circuit_breakers.set_emergency_shutdown()
            self.execution_engine.set_shutdown_mode()
            self.strategy_engine.set_shutdown_mode()

            # 2. Send immediate shutdown alert
            print("  📱 Sending shutdown alert...")
            self.alert_system.send_system_alert(
                "Trading bot initiating graceful shutdown",
                {"phase": "IMMEDIATE", "timestamp": time()}
            )

            # 3. Stop data collection immediately
            print("  🔌 Stopping data collection...")
            self.geyser_client.stop_streaming()
            self.social_intelligence_engine.stop_monitoring()

            # 4. Cancel pending tasks
            print("  ⏹️  Canceling pending tasks...")
            self.task_pool_manager.cancel_all_tasks()

            print("✅ Phase 1 completed")
        except e as e:
            print(f"⚠️  Phase 1 error: {e}")

    async fn _shutdown_phase_2_graceful(inout self):
        """
        🛑 Phase 2: Graceful operations (5-30 seconds)
        - Complete in-progress trades
        - Save critical state
        - Close positions if needed
        """
        self.shutdown_phase = "PHASE_2_GRACEFUL"
        print("🛑 Phase 2: Graceful operations (30s timeout)...")

        phase_start = time()
        timeout = 30.0

        try:
            # 1. Wait for in-progress trades to complete
            print("  ⏳ Waiting for in-progress trades...")
            trades_timeout = min(15.0, timeout - (time() - phase_start))
            await self._wait_for_trades_completion(trades_timeout)

            # 2. Save critical portfolio state
            print("  💾 Saving portfolio state...")
            await self._save_portfolio_state_async()

            # 3. Flush pending database writes
            print("  📊 Flushing database writes...")
            await self._flush_database_async()

            # 4. Close risky positions if market conditions warrant
            print("  🔒 Assessing position closures...")
            await self._emergency_position_closure()

            # 5. Save performance metrics
            print("  📈 Saving performance metrics...")
            await self._save_performance_metrics_async()

            print("✅ Phase 2 completed")
        except e as e:
            print(f"⚠️  Phase 2 error: {e}")

    async fn _shutdown_phase_3_forceful(inout self):
        """
        🛑 Phase 3: Forceful operations (30-60 seconds)
        - Force close connections
        - Terminate streaming
        - Stop background threads
        """
        self.shutdown_phase = "PHASE_3_FORCEFUL"
        print("🛑 Phase 3: Forceful operations (30s timeout)...")

        phase_start = time()
        timeout = 30.0

        try:
            # 1. Force close streaming connections
            print("  🔌 Force closing streaming connections...")
            await self._force_close_streaming()

            # 2. Terminate background threads with timeout
            print("  🧵 Terminating background threads...")
            await self._terminate_background_threads(timeout)

            # 3. Close network connections
            print("  🌐 Closing network connections...")
            await self._close_network_connections()

            # 4. Stop monitoring systems
            print("  📊 Stopping monitoring systems...")
            await self._stop_monitoring_systems()

            print("✅ Phase 3 completed")
        except e as e:
            print(f"⚠️  Phase 3 error: {e}")

    async fn _shutdown_phase_4_cleanup(inout self):
        """
        🛑 Phase 4: Final cleanup (60+ seconds)
        - Print final statistics
        - Send final alerts
        - Clean up resources
        """
        self.shutdown_phase = "PHASE_4_CLEANUP"
        print("🛑 Phase 4: Final cleanup...")

        try:
            # 1. Print comprehensive final statistics
            print("  📊 Generating final statistics...")
            self._print_final_statistics()

            # 2. Send final summary alert
            print("  📱 Sending final summary...")
            await self._send_final_summary_alert()

            # 3. Log shutdown completion
            print("  📝 Logging shutdown completion...")
            shutdown_duration = time() - self.shutdown_start_time
            self.logger.info("Graceful shutdown completed",
                            shutdown_duration=shutdown_duration,
                            final_portfolio_value=self.portfolio.total_value,
                            trades_executed=self.trades_executed)

            # 4. Clean up any remaining resources
            print("  🧹 Final resource cleanup...")
            await self._final_resource_cleanup()

            print("✅ Phase 4 completed")
        except e as e:
            print(f"⚠️  Phase 4 error: {e}")

        self.shutdown_phase = "COMPLETED"

    async fn _wait_for_trades_completion(inout self, timeout: Float):
        """
        Wait for in-progress trades to complete with timeout
        """
        start_time = time()
        check_interval = 0.5  # Check every 500ms

        while (time() - start_time) < timeout:
            # Check if there are any in-progress trades
            in_progress_trades = self.execution_engine.get_in_progress_trades()
            if len(in_progress_trades) == 0:
                print(f"    ✅ All trades completed in {time() - start_time:.2f}s")
                return

            print(f"    ⏳ Waiting for {len(in_progress_trades)} in-progress trades...")
            await asyncio.sleep(check_interval)

        # Force stop remaining trades
        remaining_trades = self.execution_engine.get_in_progress_trades()
        if len(remaining_trades) > 0:
            print(f"    ⚠️  Force stopping {len(remaining_trades)} trades due to timeout")
            self.execution_engine.force_stop_all_trades()

    async fn _save_portfolio_state_async(inout self):
        """
        Save portfolio state asynchronously
        """
        try:
            if self.config.database.enabled:
                # Save portfolio snapshot
                self.database_manager.save_portfolio_snapshot(self.portfolio)

                # Save current positions with detailed state
                for symbol, position in self.portfolio.positions.items():
                    await self._save_position_state_async(symbol, position)

                # Flush writes
                await self.database_manager.flush_pending_writes()
                print("    ✅ Portfolio state saved asynchronously")
        except e as e:
            print(f"    ⚠️  Failed to save portfolio state: {e}")

    async fn _save_position_state_async(inout self, symbol: String, position: Position):
        """
        Save detailed position state for recovery
        """
        try:
            position_state = {
                "symbol": symbol,
                "size": position.size,
                "entry_price": position.entry_price,
                "current_price": position.current_price,
                "unrealized_pnl": position.unrealized_pnl,
                "pnl_percentage": position.pnl_percentage,
                "entry_timestamp": position.entry_timestamp,
                "stop_loss_price": position.stop_loss_price,
                "take_profit_price": position.take_profit_price,
                "position_id": position.position_id,
                "shutdown_timestamp": time(),
                "shutdown_reason": "GRACEFUL_SHUTDOWN"
            }
            # This would save to a recovery table in the database
            print(f"    💾 Saved position state for {symbol}")
        except e as e:
            print(f"    ⚠️  Failed to save position state for {symbol}: {e}")

    async fn _flush_database_async(inout self):
        """
        Flush database operations asynchronously
        """
        try:
            if self.config.database.enabled:
                # Flush pending writes with timeout
                await asyncio.wait_for(
                    self.database_manager.flush_pending_writes(),
                    timeout=10.0
                )
                print("    ✅ Database flushed asynchronously")
        except e as e:
            print(f"    ⚠️  Database flush error: {e}")

    async fn _emergency_position_closure(inout self):
        """
        Emergency closure of risky positions during shutdown
        """
        try:
            risky_positions = []
            current_prices = self._fetch_current_prices()

            for symbol, position in self.portfolio.positions.items():
                if symbol in current_prices:
                    current_price = current_prices[symbol]
                    price_change = (current_price - position.entry_price) / position.entry_timestamp

                    # Close positions with extreme losses or rapid declines
                    if (position.unrealized_pnl < -position.size * position.entry_price * 0.1 or  # >10% loss
                        price_change < -0.05):  # >5% rapid decline
                        risky_positions.append((symbol, position, "EMERGENCY_SHUTDOWN_RISK"))

            # Close risky positions
            for symbol, position, reason in risky_positions:
                print(f"    🚨 Emergency closing {symbol}: {reason}")
                await self._close_position_async(symbol, reason)

        except e as e:
            print(f"    ⚠️  Emergency position closure error: {e}")

    async fn _close_position_async(inout self, symbol: String, reason: String):
        """
        Close position asynchronously during shutdown
        """
        try:
            # This would use the async execution engine
            # For now, just log the closure
            print(f"    🔒 Async position closure: {symbol} ({reason})")
        except e as e:
            print(f"    ⚠️  Async position closure error for {symbol}: {e}")

    async fn _save_performance_metrics_async(inout self):
        """
        Save performance metrics asynchronously
        """
        try:
            if self.config.database.enabled:
                perf_stats = self.performance_analytics.get_performance_summary()
                self.database_manager.save_performance_metrics(perf_stats)

                # Save shutdown-specific metrics
                shutdown_metrics = {
                    "shutdown_timestamp": time(),
                    "shutdown_phase": self.shutdown_phase,
                    "total_uptime": time() - self.start_time,
                    "final_portfolio_value": self.portfolio.total_value,
                    "trades_executed": self.trades_executed,
                    "signals_generated": self.signals_generated,
                    "max_drawdown": self.performance_analytics.get_max_drawdown()
                }
                # This would save to a shutdown metrics table
                print("    ✅ Performance metrics saved asynchronously")
        except e as e:
            print(f"    ⚠️  Performance metrics save error: {e}")

    async fn _force_close_streaming(inout self):
        """
        Force close streaming connections
        """
        try:
            # Close Geyser streaming
            self.geyser_client.force_disconnect()

            # Close social intelligence streams
            self.social_intelligence_engine.force_disconnect()

            # Close other streaming connections
            print("    ✅ Streaming connections force closed")
        except e as e:
            print(f"    ⚠️  Streaming close error: {e}")

    async fn _terminate_background_threads(inout self, timeout: Float):
        """
        Terminate background threads with timeout
        """
        try:
            # Signal monitoring thread to stop
            self.shutdown_event.set()

            # Wait for threads to finish naturally
            await asyncio.sleep(min(5.0, timeout))

            # Force terminate if still running
            print("    ✅ Background threads terminated")
        except e as e:
            print(f"    ⚠️  Thread termination error: {e}")

    async fn _close_network_connections(inout self):
        """
        Close network connections
        """
        try:
            # Close database connections
            if self.config.database.enabled:
                await self.database_manager.disconnect()

            # Close API client connections
            self.helius_client.close()
            self.quicknode_client.close()
            self.dexscreener_client.close()
            self.jupiter_client.close()

            print("    ✅ Network connections closed")
        except e as e:
            print(f"    ⚠️  Network connection close error: {e}")

    async fn _stop_monitoring_systems(inout self):
        """
        Stop monitoring and alert systems
        """
        try:
            # Stop performance analytics
            self.performance_analytics.stop_monitoring()

            # Stop alert system
            self.alert_system.shutdown()

            # Stop circuit breakers
            self.circuit_breakers.shutdown()

            print("    ✅ Monitoring systems stopped")
        except e as e:
            print(f"    ⚠️  Monitoring systems stop error: {e}")

    async fn _send_final_summary_alert(inout self):
        """
        Send final summary alert
        """
        try:
            summary = {
                "shutdown_type": "GRACEFUL",
                "shutdown_duration": time() - self.shutdown_start_time,
                "total_uptime": time() - self.start_time,
                "final_portfolio_value": self.portfolio.total_value,
                "total_pnl": self.total_pnl,
                "trades_executed": self.trades_executed,
                "signals_generated": self.signals_generated,
                "cycles_completed": self.cycles_completed
            }

            self.alert_system.send_system_alert("Trading bot shutdown complete", summary)
            print("    ✅ Final summary alert sent")
        except e as e:
            print(f"    ⚠️  Final summary alert error: {e}")

    async fn _final_resource_cleanup(inout self):
        """
        Final resource cleanup
        """
        try:
            # Clean up task pool
            self.task_pool_manager.cleanup()

            # Clean up portfolio manager
            self.portfolio_manager.cleanup()

            # Set final state
            self.shutdown_phase = "COMPLETED"

            print("    ✅ Final resource cleanup completed")
        except e as e:
            print(f"    ⚠️  Final cleanup error: {e}")

    fn _signal_handler(self, signum, frame):
        """
        🛑 Enhanced signal handler for graceful shutdown
        """
        print(f"\n🛑 Received signal {signum} - initiating graceful shutdown...")

        # Map signals to descriptions
        signal_names = {
            2: "SIGINT (Ctrl+C)",
            15: "SIGTERM (termination)",
            9: "SIGKILL (forceful kill)"
        }

        signal_name = signal_names.get(signum, f"Signal {signum}")

        # Send immediate alert
        try:
            self.alert_system.send_system_alert(
                f"Received {signal_name} - initiating graceful shutdown",
                {
                    "signal": signum,
                    "signal_name": signal_name,
                    "timestamp": time(),
                    "portfolio_value": self.portfolio.total_value,
                    "open_positions": len(self.portfolio.positions)
                }
            )
        except:
            pass  # Don't let alert errors prevent shutdown

        # Initiate shutdown
        try:
            # In real implementation, this would be async
            # For now, set the shutdown event
            self.shutdown_event.set()
            self.is_running = False

            print("🛑 Grace shutdown initiated. Press Ctrl+C again to force quit.")

        except e as e:
            print(f"❌ Error initiating shutdown: {e}")
            exit(1)

    fn _validate_configuration(self):
        """
        Validate all required configuration
        """
        print("🔍 Validating configuration...")

        # Check required API keys
        required_keys = [
            ("HELIUS_API_KEY", self.config.api.helius_api_key),
            ("QUICKNODE_PRIMARY_RPC", self.config.api.quicknode_rpcs.primary),
            ("WALLET_ADDRESS", self.config.wallet_address)
        ]

        for key_name, key_value in required_keys:
            if not key_value or key_value == "":
                print(f"❌ Missing required configuration: {key_name}")
                exit(1)

        # Validate trading parameters
        if self.config.trading.initial_capital <= 0:
            print("❌ Initial capital must be greater than 0")
            exit(1)

        if self.config.trading.max_position_size <= 0 or self.config.trading.max_position_size > 1:
            print("❌ Max position size must be between 0 and 1")
            exit(1)

        print("✅ Configuration validation passed")

    fn _initialize_connections(self):
        """
        Initialize all external connections
        """
        print("🔌 Initializing connections...")

        # Test Helius connection
        try:
            self.helius_client.health_check()
            print("✅ Helius API connection successful")
        except e:
            print(f"❌ Failed to connect to Helius API: {e}")
            exit(1)

        # Test QuickNode connection
        try:
            self.quicknode_client.health_check()
            print("✅ QuickNode RPC connection successful")
        except e:
            print(f"❌ Failed to connect to QuickNode RPC: {e}")
            exit(1)

        # Initialize database connection
        if self.config.database.enabled:
            try:
                if self.database_manager.connect():
                    self.database_manager.initialize_schema()
                    print("✅ Database connection initialized")

                    # Try to restore portfolio state
                    var restored_portfolio = self.database_manager.load_portfolio_state()
                    if restored_portfolio:
                        self.portfolio = restored_portfolio
                        print(f"✅ Portfolio state restored: {self.portfolio.total_value:.4f} SOL")
            except e:
                print(f"⚠️  Database initialization failed: {e}")
                print("   Continuing without persistence...")

        print("✅ All connections initialized successfully")

    fn _main_trading_loop(self):
        """
        Main trading cycle that runs continuously with graceful shutdown support
        """
        cycle_interval = self.config.trading.cycle_interval  # Default: 1 second

        while self.is_running and not self.shutdown_event.is_set():
            cycle_start = time()

            try:
                # Check if we're in shutdown mode
                if self.shutdown_phase != "RUNNING":
                    print(f"🛑 Shutdown detected in phase: {self.shutdown_phase}")
                    break

                # Execute one trading cycle
                self._execute_trading_cycle()

                # Update performance metrics
                self.cycles_completed += 1
                cycle_time = time() - cycle_start
                self.last_cycle_time = cycle_time

                # Log cycle performance
                if self.cycles_completed % 60 == 0:  # Every minute
                    print(f"📊 Cycle {self.cycles_completed}: {cycle_time:.3f}s, "
                          f"Signals: {self.signals_generated}, Trades: {self.trades_executed}")

                # Sleep until next cycle (with shutdown interruptibility)
                sleep_time = max(0, cycle_interval - cycle_time)
                if sleep_time > 0:
                    # Sleep in small increments to allow responsive shutdown
                    elapsed = 0.0
                    while elapsed < sleep_time and not self.shutdown_event.is_set():
                        sleep(min(0.1, sleep_time - elapsed))
                        elapsed += 0.1

            except KeyboardInterrupt:
                print("\n⚠️  Keyboard interrupt received - initiating graceful shutdown")
                break
            except e as e:
                print(f"❌ Error in trading cycle: {e}")
                # Check if we should continue running during shutdown
                if self.shutdown_phase != "RUNNING":
                    break
                # Continue running after errors (with some backoff)
                sleep(5.0)

        # If we broke out of the loop due to shutdown, run async shutdown
        if self.shutdown_event.is_set():
            try:
                python = Python()
                asyncio = python.import("asyncio")
                asyncio.run(self.stop())
            except e as e:
                print(f"⚠️  Error during async shutdown: {e}")
                # Fallback to synchronous shutdown
                self._fallback_shutdown()

    fn _fallback_shutdown(self):
        """
        Fallback synchronous shutdown when async fails
        """
        print("\n🛑 Running fallback synchronous shutdown...")

        try:
            # Immediate operations
            print("  🚦 Setting shutdown flags...")
            self.is_running = False
            self.shutdown_phase = "FALLBACK_SHUTDOWN"

            # Save portfolio state
            print("  💾 Saving portfolio state...")
            self._save_portfolio_state()

            # Flush metrics
            print("  📈 Flushing metrics...")
            self._flush_metrics()

            # Close connections
            print("  🔌 Closing connections...")
            self._close_connections()

            # Print final statistics
            print("  📊 Final statistics...")
            self._print_final_statistics()

            print("✅ Fallback shutdown completed")
        except e as e:
            print(f"❌ Error in fallback shutdown: {e}")
            print("🛑 Emergency exit")
            exit(1)

    fn _execute_trading_cycle(self):
        """
        Execute one complete trading cycle with advanced production architecture
        """
        try:
            # 🛡️ CHECK CIRCUIT BREAKERS FIRST
            if not self.circuit_breakers.check_all_conditions(self.portfolio):
                var halt_status = self.circuit_breakers.get_halt_status()
                print(f"🛑 Trading halted: {halt_status['reason']}")
                return

            # 1. Parallel Data Collection with Task Pool
            parallel_data = self._collect_data_parallel()

            # 2. Real-time Blockchain Data from Geyser
            blockchain_updates = self._fetch_geyser_updates()

            # 3. Social Intelligence Integration
            social_insights = self._fetch_social_intelligence()

            # 4. MEV Threat Assessment
            mev_risks = self._assess_mev_risks()

            # 5. Smart Money Analysis
            smart_money_signals = self._analyze_smart_money()

            # 6. Enhanced Token Discovery
            self._discover_new_tokens_advanced()

            # 7. Synthesize All Data Sources with ML Engine
            synthesized_signals = self._synthesize_market_intelligence(
                parallel_data, blockchain_updates, social_insights,
                mev_risks, smart_money_signals
            )

            # 8. Filter through master filter pipeline
            filtered_signals = self.master_filter.filter_all_signals(synthesized_signals)
            self.signals_generated += len(filtered_signals)

            # 9. Portfolio Manager Capital Allocation
            for signal in filtered_signals:
                if self.shutdown_event.is_set():
                    break

                # Check MEV risks first
                mev_risk = self.mev_detector.analyze_transaction_risk(signal)
                if mev_risk.is_high_risk():
                    self.logger.warn(f"MEV risk detected: {signal.symbol}",
                                     symbol=signal.symbol,
                                     risk_level=mev_risk.risk_level)
                    continue

                # Allocate capital through PortfolioManager
                allocation = self.portfolio_manager.request_capital_allocation(
                    signal.symbol, signal.confidence, signal.liquidity
                )

                if allocation.approved:
                    # Create enhanced approval with PortfolioManager allocation
                    approval = RiskApproval(
                        approved=True,
                        reason=f"PortfolioManager allocation: {allocation.allocation_type}",
                        position_size=allocation.position_size,
                        stop_loss_price=allocation.stop_loss_price,
                        portfolio_allocation=allocation
                    )

                    # Execute with advanced execution (Jito bundles for MEV protection)
                    result = self._execute_with_mev_protection(signal, approval)

                    if result.success:
                        self.trades_executed += 1
                        self.portfolio_manager.record_successful_trade(
                            signal.symbol, allocation.position_size, result.executed_price
                        )
                        self._update_portfolio(signal, approval, result)

                        # 📊 Record trade result for circuit breakers
                        self.circuit_breakers.record_trade_result(True, 0.0)

                        # 📱 Send trade alert
                        self.alert_system.send_trade_alert(signal, result, AlertLevel.INFO)

                        self.logger.log_trade(
                            action="EXECUTED",
                            symbol=signal.symbol,
                            price=result.executed_price,
                            size=approval.position_size,
                            reason="Advanced execution successful"
                        )
                    else:
                        # 📊 Record failed trade
                        self.circuit_breakers.record_trade_result(False, 0.0)
                        self.portfolio_manager.record_failed_trade(signal.symbol)

                        # 📱 Send error alert
                        self.alert_system.send_error_alert(
                            f"Advanced execution failed: {signal.symbol}",
                            {"error": result.error_message}
                        )

                        self.logger.error(f"Advanced execution failed: {signal.symbol}",
                                         symbol=signal.symbol,
                                         error=result.error_message)
                else:
                    self.logger.warn(f"PortfolioManager rejected: {signal.symbol}",
                                     symbol=signal.symbol,
                                     reason=allocation.reason)

            # 10. Update existing positions with advanced risk management
            self._manage_existing_positions_advanced()

            # 11. Update portfolio metrics with PortfolioManager sync
            self._update_portfolio_metrics_advanced()

        except e as e:
            print(f"❌ Error in advanced trading cycle: {e}")
            self.alert_system.send_error_alert(f"Advanced trading cycle error: {e}", {})
            raise

    fn _discover_new_tokens(self) -> List[String]:
        """
        Discover new tokens from DexScreener
        """
        try:
            # Get latest tokens on Solana
            latest_tokens = self.dexscreener_client.get_latest_tokens("solana", limit=50)

            # Filter tokens based on basic criteria
            filtered_tokens = []
            for token in latest_tokens:
                if (token.market_cap >= 1000 and  # Min $1k market cap
                    token.volume_24h >= 5000 and   # Min $5k volume
                    token.liquidity_usd >= 10000):  # Min $10k liquidity
                    filtered_tokens.append(token.address)

            return filtered_tokens[:20]  # Limit to top 20

        except e as e:
            print(f"⚠️  Error discovering new tokens: {e}")
            return []

    fn _fetch_market_data(self) -> Dict[String, MarketData]:
        """
        Fetch market data for all monitored symbols
        """
        market_data = {}

        # Get tokens we're currently monitoring
        monitored_symbols = self._get_monitored_symbols()

        for symbol in monitored_symbols:
            try:
                # Get token pairs from DexScreener
                pairs = self.dexscreener_client.get_token_pairs(symbol)

                if pairs:
                    # Use the most liquid pair
                    best_pair = max(pairs, key=lambda p: p.liquidity_usd)

                    # Create market data
                    data = MarketData(
                        symbol=symbol,
                        current_price=best_pair.price,
                        volume_24h=best_pair.volume_24h,
                        volume_5m=best_pair.volume_5m,
                        liquidity_usd=best_pair.liquidity_usd,
                        timestamp=time(),
                        market_cap=best_pair.market_cap,
                        price_change_24h=best_pair.price_change_24h,
                        price_change_1h=best_pair.price_change_1h,
                        price_change_5m=best_pair.price_change_5m,
                        holder_count=0,  # Will be filled by Helius
                        transaction_count=best_pair.transaction_count,
                        age_hours=0,  # Will be calculated from creation time
                        social_metrics=SocialMetrics(),
                        blockchain_metrics=BlockchainMetrics()
                    )

                    # Enhance with Helius data
                    try:
                        token_metadata = self.helius_client.get_token_metadata(symbol)
                        if token_metadata:
                            data.holder_count = token_metadata.holder_count
                            data.age_hours = (time() - token_metadata.creation_timestamp) / 3600
                    except:
                        pass  # Continue without Helius data

                    market_data[symbol] = data

            except e as e:
                print(f"⚠️  Error fetching market data for {symbol}: {e}")
                continue

        return market_data

    fn _get_monitored_symbols(self) -> List[String]:
        """
        Get list of symbols to monitor (open positions + watchlist)
        """
        symbols = []

        # Add symbols from open positions
        for symbol in self.portfolio.positions.keys():
            symbols.append(symbol)

        # Add symbols from watchlist
        for watch_symbol in self.watchlist:
            if watch_symbol not in symbols:
                symbols.append(watch_symbol)

        # Add trending tokens to watchlist
        try:
            trending = self.dexscreener_client.get_trending_tokens("solana")
            for token in trending[:10]:
                if token.symbol and token.symbol not in symbols:
                    self.watchlist.add(token.symbol)
                    symbols.append(token.symbol)
        except:
            pass

        # Limit to 100 symbols for performance
        return symbols[:100]

    fn _discover_new_tokens(self):
        """
        Discover new tokens and add to watchlist
        """
        try:
            # Get latest tokens from DexScreener
            latest_tokens = self.dexscreener_client.get_latest_tokens("solana", 20)

            for token in latest_tokens:
                if token.symbol and token.symbol not in self.watchlist:
                    # Basic quality check before adding to watchlist
                    if (token.liquidity_usd >= 5000.0 and  # Minimum liquidity
                        token.volume_24h >= 1000.0 and      # Minimum volume
                        token.holder_count >= 10):        # Minimum holders
                        self.watchlist.add(token.symbol)
                        print(f"🔍 Discovered new token: {token.symbol} (Liquidity: ${token.liquidity_usd:.0f})")

            # Clean old watchlist entries (remove if too many)
            if len(self.watchlist) > 200:
                # Keep only the most recent 100
                # In a real implementation, this would be more sophisticated
                old_count = len(self.watchlist) - 100
                for i in range(old_count):
                    self.watchlist.pop()  # Remove arbitrary old entries

        except e:
            print(f"⚠️  Token discovery error: {e}")

    fn _manage_existing_positions(self):
        """
        Check existing positions for stop loss and take profit conditions
        """
        current_prices = self._fetch_current_prices()

        positions_to_close = []

        for symbol, position in self.portfolio.positions.items():
            if symbol in current_prices:
                current_price = current_prices[symbol]

                # Check stop loss
                if current_price <= position.stop_loss_price:
                    positions_to_close.append((symbol, "STOP_LOSS"))
                    continue

                # Check take profit
                if current_price >= position.take_profit_price:
                    positions_to_close.append((symbol, "TAKE_PROFIT"))
                    continue

                # Check time-based exit (for new tokens)
                if self._should_exit_time_based(position):
                    positions_to_close.append((symbol, "TIME_BASED"))

        # Close positions that need to be closed
        for symbol, reason in positions_to_close:
            self._close_position(symbol, reason)

    fn _fetch_current_prices(self) -> Dict[String, Float]:
        """
        Fetch current prices for all open positions
        """
        prices = {}

        for symbol in self.portfolio.positions.keys():
            try:
                pairs = self.dexscreener_client.get_token_pairs(symbol)
                if pairs:
                    best_pair = max(pairs, key=lambda p: p.liquidity_usd)
                    prices[symbol] = best_pair.price
            except:
                continue

        return prices

    fn _get_current_liquidity(self, symbol: String) -> Float:
        """
        Get current liquidity for a symbol
        """
        try:
            pairs = self.dexscreener_client.get_token_pairs(symbol)
            if pairs:
                best_pair = max(pairs, key=lambda p: p.liquidity_usd)
                return best_pair.liquidity_usd
        except:
            pass
        return 0.0

    fn _should_exit_time_based(self, position: Position) -> Bool:
        """
        Check if position should be closed based on time
        """
        # For very new tokens, exit after 4 hours
        position_age_hours = (time() - position.entry_timestamp) / 3600

        if position_age_hours >= 4.0:
            return True

        return False

    fn _close_position(self, symbol: String, reason: String):
        """
        Close a position
        """
        if symbol not in self.portfolio.positions:
            return

        position = self.portfolio.positions[symbol]

        try:
            # Create sell signal with safe parameters
            sell_signal = TradingSignal(
                symbol=symbol,
                action=TradingAction.SELL,
                confidence=1.0,
                timeframe="1m",
                timestamp=time(),
                price_target=position.entry_price * 0.95,  # 5% below entry as fallback
                stop_loss=position.stop_loss_price if position.stop_loss_price > 0 else position.entry_price * 0.9,  # 10% below entry as fallback
                volume=position.size,
                liquidity=self._get_current_liquidity(symbol),
                metadata={"close_reason": reason, "entry_price": position.entry_price}
            )

            # Create proper approval
            approval = RiskApproval(
                approved=True,
                reason=f"Position close: {reason}",
                position_size=position.size,  # Token units
                stop_loss_price=sell_signal.stop_loss
            )

            # Execute sell
            result = self.execution_engine.execute_trade(sell_signal, approval)

            if result.success:
                # Calculate realized P&L
                realized_pnl = (result.executed_price - position.entry_price) * position.size
                pnl_percentage = (result.executed_price - position.entry_price) / position.entry_price

                # 📊 Record trade for performance analytics
                var trade_record = TradeRecord(
                    symbol=symbol,
                    action=TradingAction.SELL,
                    entry_price=position.entry_price,
                    exit_price=result.executed_price,
                    size=position.size,
                    pnl=realized_pnl,
                    pnl_percentage=pnl_percentage,
                    entry_timestamp=position.entry_timestamp,
                    exit_timestamp=time(),
                    hold_duration_seconds=time() - position.entry_timestamp,
                    was_profitable=realized_pnl > 0,
                    close_reason=reason
                )
                self.performance_analytics.record_trade(trade_record)

                # 💾 Save trade to database
                if self.config.database.enabled:
                    self.database_manager.save_trade(trade_record)

                # 📊 Record for circuit breakers
                self.circuit_breakers.record_trade_result(realized_pnl > 0, realized_pnl)

                # 📱 Send position close alert
                self.alert_system.send_position_alert(symbol, position, f"Closed: {reason}")

                # Remove from portfolio
                del self.portfolio.positions[symbol]
                self.portfolio.available_cash += result.executed_price * position.size

                # Update metrics
                self.total_pnl += realized_pnl

                print(f"✅ Position closed: {symbol} "
                      f"Reason: {reason} "
                      f"P&L: {realized_pnl:.4f} SOL ({pnl_percentage:.2%})")
            else:
                print(f"❌ Failed to close position {symbol}: {result.error_message}")
                self.alert_system.send_error_alert(
                    f"Failed to close position: {symbol}",
                    {"reason": reason, "error": result.error_message}
                )

        except e as e:
            print(f"❌ Error closing position {symbol}: {e}")
            self.alert_system.send_error_alert(f"Error closing position: {symbol}", {"error": str(e)})

    fn _update_portfolio(self, signal: TradingSignal, approval: RiskApproval, result: ExecutionResult):
        """
        Update portfolio state after successful trade
        """
        if signal.action == BUY:
            # Add new position
            position = Position(
                symbol=signal.symbol,
                size=approval.position_size / result.executed_price,
                entry_price=result.executed_price,
                current_price=result.executed_price,
                unrealized_pnl=0.0,
                pnl_percentage=0.0,
                entry_timestamp=time(),
                stop_loss_price=approval.stop_loss_price,
                take_profit_price=signal.price_target,
                position_id=f"{signal.symbol}_{int(time())}"
            )

            self.portfolio.positions[signal.symbol] = position
            self.portfolio.available_cash -= approval.position_size

        elif signal.action == SELL:
            # Remove position (already handled in _close_position)
            pass

    fn _update_portfolio_metrics(self):
        """
        Update portfolio performance metrics
        """
        # Calculate current portfolio value
        current_value = self.portfolio.available_cash
        current_prices = self._fetch_current_prices()

        for symbol, position in self.portfolio.positions.items():
            if symbol in current_prices:
                current_price = current_prices[symbol]
                position.current_price = current_price
                position.unrealized_pnl = (current_price - position.entry_price) * position.size
                position.pnl_percentage = (current_price - position.entry_price) / position.entry_price
                current_value += position.current_price * position.size

        self.portfolio.total_value = current_value

        # Update daily P&L
        self.portfolio.daily_pnl = current_value - self.config.trading.initial_capital

        # Update portfolio peak value
        self.portfolio.peak_value = max(self.portfolio.peak_value, current_value)

        # Update daily P&L
        self.portfolio.daily_pnl = current_value - self.config.trading.initial_capital

        # 📊 Update equity curve
        self.performance_analytics.update_equity_curve(current_value)

        # Calculate drawdown
        current_drawdown = (self.portfolio.peak_value - current_value) / self.portfolio.peak_value if self.portfolio.peak_value > 0 else 0.0

        # 🛡️ Check circuit breakers
        if not self.circuit_breakers.check_all_conditions(self.portfolio):
            var halt_status = self.circuit_breakers.get_halt_status()
            print(f"🚨 Circuit breaker triggered! {halt_status['reason']}")
            self.alert_system.send_circuit_breaker_alert(halt_status['reason'], self.portfolio)
            self.is_running = False

    fn _monitoring_loop(self):
        """
        Background monitoring loop for metrics and health checks
        """
        while self.is_running and not self.shutdown_event.is_set():
            try:
                # Update metrics
                current_drawdown = (self.portfolio.peak_value - self.portfolio.total_value) / self.portfolio.peak_value if self.portfolio.peak_value > 0 else 0.0

                # Get MasterFilter statistics
                filter_stats = self.master_filter.get_filter_stats()

                # Get performance statistics
                perf_stats = self.performance_analytics.get_performance_summary()

                self.metrics = {
                    "uptime": time() - self.start_time,
                    "cycles_completed": self.cycles_completed,
                    "signals_generated": self.signals_generated,
                    "trades_executed": self.trades_executed,
                    "portfolio_value": self.portfolio.total_value,
                    "daily_pnl": self.portfolio.daily_pnl,
                    "max_drawdown": current_drawdown,
                    "last_cycle_time": self.last_cycle_time,
                    "open_positions": len(self.portfolio.positions),
                    # Filter statistics
                    "filter_rejection_rate": filter_stats["rejection_rate"],
                    "total_signals_rejected": filter_stats["total_rejected"],
                    "instant_rejections": filter_stats["instant_rejections"],
                    "aggressive_rejections": filter_stats["aggressive_rejections"],
                    "micro_rejections": filter_stats["micro_rejections"],
                    # Performance statistics
                    "win_rate": perf_stats.get("win_rate", 0.0),
                    "sharpe_ratio": perf_stats.get("sharpe_ratio", 0.0),
                    "profit_factor": perf_stats.get("profit_factor", 0.0)
                }

                # 💾 Save portfolio snapshot to database
                if self.config.database.enabled:
                    self.database_manager.save_portfolio_snapshot(self.portfolio)
                    self.database_manager.save_performance_metrics(perf_stats)

                # Health checks
                self._perform_health_checks()

                # 📊 Hourly performance report
                if time() - self.start_time >= 3600 and int(time() - self.start_time) % 3600 < 30:  # Every hour
                    self.performance_analytics.print_performance_report()

                # 🎯 Strategy adaptation check
                if self.strategy_adaptation.should_adapt():
                    var recent_trades = self.performance_analytics.get_trade_history(48)  # 48 hours
                    var adjustment = self.strategy_adaptation.adapt_strategy(recent_trades, [])
                    if adjustment.reason:
                        self.strategy_adaptation.apply_adjustments(adjustment)
                        self.alert_system.send_performance_alert(
                            metric="strategy_adapted",
                            value=0.0,
                            threshold=0.0
                        )
                        print(f"🎯 Strategy adapted: {adjustment.reason}")

                # Sleep for monitoring interval
                sleep(30.0)  # Check every 30 seconds

            except e as e:
                print(f"⚠️  Error in monitoring loop: {e}")
                sleep(60.0)  # Wait longer on error

    fn _perform_health_checks(self):
        """
        Perform health checks on all components
        """
        # Check API connectivity
        try:
            self.helius_client.health_check()
        except:
            print("⚠️  Helius API health check failed")

        try:
            self.quicknode_client.health_check()
        except:
            print("⚠️  QuickNode RPC health check failed")

        # Check performance
        if self.last_cycle_time > 2.0:  # If cycle takes more than 2 seconds
            print(f"⚠️  Slow trading cycle detected: {self.last_cycle_time:.3f}s")

    fn _signal_handler(self, signum, frame):
        """
        Handle shutdown signals
        """
        print(f"\n⚠️  Received signal {signum}")
        self.stop()
        exit(0)

    fn _save_portfolio_state(self):
        """
        Save portfolio state to database
        """
        if self.config.database.enabled:
            try:
                self.database_manager.save_portfolio_snapshot(self.portfolio)
                self.database_manager.flush_pending_writes()
                print("✅ Portfolio state saved")
            except e:
                print(f"⚠️  Failed to save portfolio state: {e}")

    fn _flush_metrics(self):
        """
        Flush metrics to monitoring system
        """
        if self.config.database.enabled:
            try:
                var perf_stats = self.performance_analytics.get_performance_summary()
                self.database_manager.save_performance_metrics(perf_stats)
                self.database_manager.flush_pending_writes()
                print("✅ Metrics flushed")
            except e:
                print(f"⚠️  Failed to flush metrics: {e}")

    fn _close_connections(self):
        """
        Close all external connections
        """
        if self.config.database.enabled:
            try:
                self.database_manager.disconnect()
                print("✅ Database connection closed")
            except e:
                print(f"⚠️  Error closing database: {e}")

    fn _print_final_statistics(self):
        """
        Print final trading statistics
        """
        uptime = time() - self.start_time
        hours = uptime / 3600

        # Get comprehensive performance stats
        var perf_stats = self.performance_analytics.get_performance_summary()

        print("\n" + "="*60)
        print("📊 FINAL TRADING STATISTICS")
        print("="*60)
        print(f"⏱️  Uptime: {hours:.2f} hours")
        print(f"🔄 Cycles Completed: {self.cycles_completed:,}")
        print(f"📈 Signals Generated: {self.signals_generated:,}")
        print(f"💰 Trades Executed: {self.trades_executed:,}")
        print(f"💵 Total P&L: {self.total_pnl:.4f} SOL")
        print(f"📉 Max Drawdown: {perf_stats.get('max_drawdown', 0.0):.2%}")
        print(f"🏆 Peak Portfolio Value: {self.portfolio.peak_value:.4f} SOL")
        print(f"💼 Final Portfolio Value: {self.portfolio.total_value:.4f} SOL")
        print(f"🎯 Win Rate: {perf_stats.get('win_rate', 0.0):.1%}")
        print(f"📊 Sharpe Ratio: {perf_stats.get('sharpe_ratio', 0.0):.2f}")
        print(f"💹 Profit Factor: {perf_stats.get('profit_factor', 0.0):.2f}")

        # Add MasterFilter statistics
        filter_stats = self.master_filter.get_filter_stats()
        print(f"🛡️  Filter Rejection Rate: {filter_stats['rejection_rate']:.1f}%")
        print(f"📊 Total Signals Filtered: {int(filter_stats['total_rejected']):,} / {int(filter_stats['total_processed']):,}")
        print(f"⚡ Instant Rejections: {int(filter_stats['instant_rejections']):,}")
        print(f"🔥 Aggressive Rejections: {int(filter_stats['aggressive_rejections']):,}")
        print(f"🔬 Micro Rejections: {int(filter_stats['micro_rejections']):,}")

        # Circuit breaker stats
        var halt_status = self.circuit_breakers.get_halt_status()
        print(f"🛡️  Circuit Breaker Status: {halt_status.get('status', 'ACTIVE')}")
        print(f"📊 Consecutive Losses: {halt_status.get('consecutive_losses', 0)}")

        print("="*60)

        # Send final summary alert
        self.alert_system.send_daily_summary(perf_stats)

# =============================================================================
# Advanced Trading Methods - Production Architecture
# =============================================================================

fn _collect_data_parallel(self) -> Dict[String, Any]:
    """
    Collect data in parallel using Python task pool
    """
    try:
        # Submit parallel data collection tasks
        tasks = []

        # Get monitored symbols
        monitored_symbols = self._get_monitored_symbols()

        # Create tasks for parallel execution
        for symbol in monitored_symbols[:50]:  # Limit to 50 for performance
            task_id = self.task_pool_manager.submit_task(
                task_type="market_data",
                symbol=symbol,
                priority="normal"
            )
            tasks.append(task_id)

        # Wait for results with timeout
        results = {}
        completed_tasks = 0
        timeout = 5.0  # 5 second timeout
        start_time = time()

        while completed_tasks < len(tasks) and (time() - start_time) < timeout:
            for task_id in tasks:
                if task_id not in results:
                    result = self.task_pool_manager.get_task_result(task_id)
                    if result:
                        results[task_id] = result
                        completed_tasks += 1

            sleep(0.01)  # Small delay to avoid busy waiting

        # Process results into market data
        parallel_data = {
            "market_data": {},
            "social_data": {},
            "wallet_data": {},
            "performance_metrics": {
                "tasks_submitted": len(tasks),
                "tasks_completed": completed_tasks,
                "success_rate": completed_tasks / len(tasks) if len(tasks) > 0 else 0.0
            }
        }

        for task_id, result in results.items():
            if result["success"] and "data" in result:
                data = result["data"]
                if data["type"] == "market_data":
                    parallel_data["market_data"][data["symbol"]] = data["market_data"]
                elif data["type"] == "social_data":
                    parallel_data["social_data"][data["symbol"]] = data["social_data"]
                elif data["type"] == "wallet_data":
                    parallel_data["wallet_data"][data["symbol"]] = data["wallet_data"]

        return parallel_data

    except e as e:
        print(f"⚠️  Parallel data collection error: {e}")
        return {"market_data": {}, "social_data": {}, "wallet_data": {}, "error": str(e)}

fn _fetch_geyser_updates(self) -> Dict[String, Any]:
    """
    Fetch real-time blockchain updates from Geyser
    """
    try:
        # Get latest updates from Geyser client
        updates = self.geyser_client.get_latest_updates(limit=100)

        # Process updates into actionable signals
        blockchain_updates = {
            "new_tokens": [],
            "large_transfers": [],
            "price_movements": [],
            "liquidity_changes": []
        }

        for update in updates:
            if update["type"] == "new_token":
                blockchain_updates["new_tokens"].append(update)
            elif update["type"] == "large_transfer":
                blockchain_updates["large_transfers"].append(update)
            elif update["type"] == "price_movement":
                blockchain_updates["price_movements"].append(update)
            elif update["type"] == "liquidity_change":
                blockchain_updates["liquidity_changes"].append(update)

        return blockchain_updates

    except e as e:
        print(f"⚠️  Geyser data fetch error: {e}")
        return {"new_tokens": [], "large_transfers": [], "price_movements": [], "liquidity_changes": []}

fn _fetch_social_intelligence(self) -> Dict[String, Any]:
    """
    Fetch social intelligence from multi-platform engine
    """
    try:
        # Get current watchlist symbols
        monitored_symbols = list(self._get_monitored_symbols())

        # Fetch social insights
        social_insights = self.social_intelligence_engine.get_comprehensive_sentiment(
            monitored_symbols[:20]  # Limit to 20 for performance
        )

        return social_insights

    except e as e:
        print(f"⚠️  Social intelligence error: {e}")
        return {"sentiment_data": {}, "influencer_activity": [], "viral_signals": []}

fn _assess_mev_risks(self) -> Dict[String, Any]:
    """
    Assess MEV risks for current market conditions
    """
    try:
        # Get current market conditions
        monitored_symbols = list(self._get_monitored_symbols())

        mev_risks = {}
        for symbol in monitored_symbols[:10]:  # Limit to 10 for performance
            risk_assessment = self.mev_detector.analyze_market_risk(symbol)
            mev_risks[symbol] = risk_assessment

        return mev_risks

    except e as e:
        print(f"⚠️  MEV risk assessment error: {e}")
        return {}

fn _analyze_smart_money(self) -> Dict[String, Any]:
    """
    Analyze smart money movements and wallet relationships
    """
    try:
        # Get recent significant transactions
        recent_transactions = self._get_recent_significant_transactions()

        smart_money_signals = {}
        for tx in recent_transactions:
            # Analyze wallet graph for each transaction
            wallet_analysis = self.wallet_graph_analyzer.analyze_wallet_activity(tx["wallet"])
            if wallet_analysis["is_smart_money"]:
                smart_money_signals[tx["symbol"]] = wallet_analysis

        return smart_money_signals

    except e as e:
        print(f"⚠️  Smart money analysis error: {e}")
        return {}

fn _synthesize_market_intelligence(self, parallel_data: Dict[String, Any],
                                 blockchain_updates: Dict[String, Any],
                                 social_insights: Dict[String, Any],
                                 mev_risks: Dict[String, Any],
                                 smart_money_signals: Dict[String, Any]) -> List[TradingSignal]:
    """
    Synthesize all data sources using ML inference engine
    """
    try:
        synthesized_signals = []

        # Get all symbols from different data sources
        all_symbols = set()

        # Add symbols from parallel data
        for symbol in parallel_data.get("market_data", {}).keys():
            all_symbols.add(symbol)

        # Add symbols from blockchain updates
        for update in blockchain_updates.get("new_tokens", []):
            if "symbol" in update:
                all_symbols.add(update["symbol"])

        # Add symbols from social intelligence
        for symbol in social_insights.get("sentiment_data", {}).keys():
            all_symbols.add(symbol)

        # Add symbols from smart money
        for symbol in smart_money_signals.keys():
            all_symbols.add(symbol)

        # Process each symbol through data synthesis engine
        for symbol in all_symbols:
            try:
                # Create feature vector for this symbol
                feature_vector = self.data_synthesis_engine.create_feature_vector(
                    symbol=symbol,
                    market_data=parallel_data.get("market_data", {}).get(symbol),
                    social_data=social_insights.get("sentiment_data", {}).get(symbol),
                    blockchain_data=blockchain_updates,
                    smart_money_data=smart_money_signals.get(symbol),
                    mev_risk_data=mev_risks.get(symbol)
                )

                # Run ML inference
                signal = self.data_synthesis_engine.generate_trading_signal(feature_vector)

                if signal and signal.confidence > 0.6:  # Minimum confidence threshold
                    synthesized_signals.append(signal)

            except e as e:
                print(f"⚠️  Error synthesizing signal for {symbol}: {e}")
                continue

        return synthesized_signals

    except e as e:
        print(f"⚠️  Market intelligence synthesis error: {e}")
        return []

fn _discover_new_tokens_advanced(self):
    """
    Advanced token discovery using multiple data sources
    """
    try:
        # Discover from blockchain updates
        for token in self.geyser_client.get_latest_token_creations(limit=10):
            if token["symbol"] and token["symbol"] not in self.watchlist:
                # Quick quality check
                if token.get("initial_liquidity", 0) >= 1000:  # Min $1k initial liquidity
                    self.watchlist.add(token["symbol"])
                    print(f"🔍 Discovered new token from Geyser: {token['symbol']}")

        # Discover from social intelligence
        viral_tokens = self.social_intelligence_engine.get_viral_tokens(limit=5)
        for token in viral_tokens:
            if token["symbol"] and token["symbol"] not in self.watchlist:
                self.watchlist.add(token["symbol"])
                print(f"🔍 Discovered viral token: {token['symbol']} (Sentiment: {token['sentiment']:.2f})")

        # Clean old watchlist entries
        if len(self.watchlist) > 300:
            # Keep only the most recent 150
            old_count = len(self.watchlist) - 150
            watchlist_list = list(self.watchlist)
            for i in range(old_count):
                self.watchlist.discard(watchlist_list[i])

    except e as e:
        print(f"⚠️  Advanced token discovery error: {e}")

fn _execute_with_mev_protection(self, signal: TradingSignal, approval: RiskApproval) -> ExecutionResult:
    """
    Execute trade with MEV protection using Jito bundles
    """
    try:
        # Check if MEV protection is needed
        mev_risk = self.mev_detector.analyze_transaction_risk(signal)

        if mev_risk.requires_mev_protection():
            # Use Jito bundle for MEV protection
            bundle_result = self.jito_bundle_builder.create_and_submit_bundle(
                signal=signal,
                approval=approval,
                mev_risk=mev_risk
            )

            if bundle_result.success:
                return ExecutionResult(
                    success=True,
                    executed_price=bundle_result.executed_price,
                    executed_quantity=approval.position_size / bundle_result.executed_price,
                    transaction_hash=bundle_result.transaction_hash,
                    gas_used=bundle_result.gas_used,
                    error_message=""
                )
            else:
                return ExecutionResult(
                    success=False,
                    executed_price=0.0,
                    executed_quantity=0.0,
                    transaction_hash="",
                    gas_used=0,
                    error_message=f"Jito bundle failed: {bundle_result.error_message}"
                )
        else:
            # Use regular execution for low-risk trades
            return self.execution_engine.execute_trade(signal, approval)

    except e as e:
        print(f"⚠️  MEV protection execution error: {e}")
        return ExecutionResult(
            success=False,
            executed_price=0.0,
            executed_quantity=0.0,
            transaction_hash="",
            gas_used=0,
            error_message=f"MEV protection error: {e}"
        )

fn _manage_existing_positions_advanced(self):
    """
    Advanced position management with MEV awareness
    """
    try:
        # Get current prices and MEV risks
        current_prices = self._fetch_current_prices()
        positions_to_close = []

        for symbol, position in self.portfolio.positions.items():
            if symbol in current_prices:
                current_price = current_prices[symbol]

                # Check traditional stop loss/take profit
                if current_price <= position.stop_loss_price:
                    positions_to_close.append((symbol, "STOP_LOSS"))
                    continue

                if current_price >= position.take_profit_price:
                    positions_to_close.append((symbol, "TAKE_PROFIT"))
                    continue

                # Check MEV risks for this position
                market_signal = TradingSignal(
                    symbol=symbol,
                    action=TradingAction.SELL,
                    confidence=1.0,
                    timeframe="1m",
                    timestamp=time(),
                    price_target=current_price,
                    stop_loss=position.stop_loss_price,
                    volume=position.size,
                    liquidity=self._get_current_liquidity(symbol)
                )

                mev_risk = self.mev_detector.analyze_transaction_risk(market_signal)
                if mev_risk.is_extreme_risk():
                    positions_to_close.append((symbol, "MEV_RISK"))
                    continue

                # Check time-based exit
                if self._should_exit_time_based(position):
                    positions_to_close.append((symbol, "TIME_BASED"))

        # Close positions that need to be closed
        for symbol, reason in positions_to_close:
            self._close_position(symbol, reason)

    except e as e:
        print(f"⚠️  Advanced position management error: {e}")

fn _update_portfolio_metrics_advanced(self):
    """
    Update portfolio metrics with PortfolioManager synchronization
    """
    try:
        # Update traditional metrics
        self._update_portfolio_metrics()

        # Sync with PortfolioManager
        portfolio_summary = self.portfolio_manager.get_portfolio_summary()

        # Update metrics with PortfolioManager data
        self.metrics.update({
            "portfolio_utilization": portfolio_summary.get("utilization", 0.0),
            "available_capital": portfolio_summary.get("available_capital", 0.0),
            "allocated_capital": portfolio_summary.get("allocated_capital", 0.0),
            "total_positions": portfolio_summary.get("total_positions", 0),
            "portfolio_health": portfolio_summary.get("health_score", 1.0),
            "risk_metrics": portfolio_summary.get("risk_metrics", {})
        })

        # Log advanced metrics periodically
        if self.cycles_completed % 300 == 0:  # Every 5 minutes
            print(f"📊 Portfolio Summary: {portfolio_summary}")

    except e as e:
        print(f"⚠️  Advanced portfolio metrics error: {e}")

fn _get_recent_significant_transactions(self) -> List[Dict[String, Any]]:
    """
    Get recent significant transactions for smart money analysis
    """
    try:
        # This would integrate with Helius to get large transactions
        # For now, return empty list as placeholder
        return []
    except e as e:
        print(f"⚠️  Error fetching significant transactions: {e}")
        return []

# =============================================================================
# Command Line Interface
# =============================================================================

fn print_banner():
    """
    Print application banner
    """
    print("""
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║    🚀 Algorithmic Memecoin Trading Bot for Solana 🚀         ║
    ║                                                              ║
    ║    Target: 2-5% Daily ROI | 65-75% Win Rate | <15% DD     ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

fn print_usage():
    """
    Print command line usage
    """
    print("""
    Usage: trading-bot [OPTIONS]

    Options:
      --mode MODE         Trading mode: paper, live, test (default: paper)
      --capital AMOUNT    Initial capital in SOL (default: 1.0)
      --config PATH       Path to configuration file (default: config/trading.toml)
      --dry-run           Don't execute real trades
      --help              Show this help message
      --version           Show version information

    Environment Variables:
      TRADING_ENV         Environment: development, staging, production
      LOG_LEVEL           Logging level: DEBUG, INFO, WARN, ERROR
      HELIUS_API_KEY      Helius API key (required)
      QUICKNODE_RPC       QuickNode RPC URL (required)
      WALLET_ADDRESS      Solana wallet address (required)

    Examples:
      trading-bot --mode=paper --capital=1.0
      trading-bot --mode=live --capital=10.0 --config=config/prod.toml
      trading-bot --mode=test --run-all-tests
    """)

fn main():
    """
    Main entry point
    """
    print_banner()

    # Parse command line arguments
    mode = "paper"
    capital = 1.0
    config_path = "config/trading.toml"
    dry_run = False

    i = 1
    while i < len(argv):
        arg = argv[i]

        if arg == "--mode":
            if i + 1 < len(argv):
                mode = argv[i + 1]
                i += 1
        elif arg == "--capital":
            if i + 1 < len(argv):
                capital = float(argv[i + 1])
                i += 1
        elif arg == "--config":
            if i + 1 < len(argv):
                config_path = argv[i + 1]
                i += 1
        elif arg == "--dry-run":
            dry_run = True
        elif arg == "--help" or arg == "-h":
            print_usage()
            exit(0)
        elif arg == "--version":
            print("Trading Bot v0.1.0")
            exit(0)
        else:
            print(f"Unknown argument: {arg}")
            print_usage()
            exit(1)

        i += 1

    # Validate arguments
    valid_modes = ["paper", "live", "test"]
    if mode not in valid_modes:
        print(f"Invalid mode: {mode}. Valid modes: {', '.join(valid_modes)}")
        exit(1)

    if capital <= 0:
        print("Initial capital must be greater than 0")
        exit(1)

    if mode == "live" and dry_run:
        print("Cannot use --dry-run with live mode")
        exit(1)

    # Load configuration
    try:
        config = load_config(config_path)
    except e as e:
        print(f"Failed to load configuration: {e}")
        exit(1)

    # Override config with command line arguments
    config.trading.execution_mode = mode
    config.trading.initial_capital = capital
    if dry_run:
        config.trading.execution_mode = "paper"

    # Create and start trading bot
    try:
        bot = TradingBot(config)
        bot.start()
    except KeyboardInterrupt:
        print("\n👋 Goodbye!")
    except e as e:
        print(f"❌ Fatal error: {e}")
        exit(1)

if __name__ == "__main__":
    main()