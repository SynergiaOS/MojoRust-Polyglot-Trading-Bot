#!/usr/bin/env mojo3
# =============================================================================
# High-Performance Memecoin Trading Bot for Solana
# Algorithmic Intelligence without External AI Dependencies
# =============================================================================

from core.config import Config, load_config
from core.types import *
from core.constants import *
from data.helius_client import HeliusClient
from data.quicknode_client import QuickNodeClient
from data.dexscreener_client import DexScreenerClient
from data.jupiter_client import JupiterClient
from engine.enhanced_context_engine import EnhancedContextEngine
from engine.spam_filter import SpamFilter
from engine.strategy_engine import StrategyEngine
from analysis.sentiment_analyzer import SentimentAnalyzer
from analysis.pattern_recognizer import PatternRecognizer
from analysis.whale_tracker import WhaleTracker
from risk.risk_manager import RiskManager
from execution.execution_engine import ExecutionEngine

# Standard library imports
from os import getenv, environ
from sys import argv, exit
from time import time, sleep
from signal import signal, SIGINT, SIGTERM
from threading import Thread, Event
from collections import deque
import json

# =============================================================================
# Main Trading Bot Class
# =============================================================================

@value
struct TradingBot:
    """
    Main trading bot orchestrator that coordinates all components
    """
    var config: Config
    var is_running: Bool
    var shutdown_event: Event
    var start_time: Float

    # API Clients
    var helius_client: HeliusClient
    var quicknode_client: QuickNodeClient
    var dexscreener_client: DexScreenerClient
    var jupiter_client: JupiterClient

    # Core Engines (Enhanced - No External AI)
    var enhanced_context_engine: EnhancedContextEngine
    var spam_filter: SpamFilter
    var strategy_engine: StrategyEngine
    var risk_manager: RiskManager
    var execution_engine: ExecutionEngine

    # Algorithmic Intelligence Components
    var sentiment_analyzer: SentimentAnalyzer
    var pattern_recognizer: PatternRecognizer
    var whale_tracker: WhaleTracker

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
    var max_drawdown: Float
    var peak_value: Float

    fn __init__(config: Config):
        """
        Initialize the trading bot with configuration
        """
        self.config = config
        self.is_running = False
        self.shutdown_event = Event()
        self.start_time = time()

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
        self.spam_filter = SpamFilter(self.helius_client, config)
        self.strategy_engine = StrategyEngine(config)
        self.execution_engine = ExecutionEngine(
            quicknode_client=self.quicknode_client,
            jupiter_client=self.jupiter_client,
            config=config
        )

        # Initialize Algorithmic Intelligence Components
        self.sentiment_analyzer = SentimentAnalyzer()
        self.pattern_recognizer = PatternRecognizer()
        self.whale_tracker = WhaleTracker()

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
        self.max_drawdown = 0.0
        self.peak_value = config.trading.initial_capital

    fn start(self):
        """
        Start the trading bot
        """
        print("🚀 Starting High-Performance Memecoin Trading Bot (Algorithmic Intelligence)")
        print(f"📊 Initial Capital: {self.config.trading.initial_capital} SOL")
        print(f"🎯 Environment: {self.config.trading_env}")
        print(f"🔧 Mode: {self.config.trading.execution_mode}")

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

    fn stop(self):
        """
        Stop the trading bot gracefully
        """
        print("\n🛑 Shutting down trading bot...")
        self.is_running = False
        self.shutdown_event.set()

        # Stop accepting new signals
        print("📊 Saving portfolio state...")
        self._save_portfolio_state()

        # Flush metrics
        print("📈 Flushing metrics...")
        self._flush_metrics()

        # Close connections
        print("🔌 Closing connections...")
        self._close_connections()

        # Print final statistics
        self._print_final_statistics()

        print("✅ Trading bot stopped gracefully")

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

        # Initialize database connections if configured
        if self.config.database.timescale_enabled:
            try:
                self._init_database_connections()
                print("✅ Database connections initialized")
            except e:
                print(f"❌ Failed to initialize database connections: {e}")
                exit(1)

        print("✅ All connections initialized successfully")

    fn _main_trading_loop(self):
        """
        Main trading cycle that runs continuously
        """
        cycle_interval = self.config.trading.cycle_interval  # Default: 1 second

        while self.is_running and not self.shutdown_event.is_set():
            cycle_start = time()

            try:
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

                # Sleep until next cycle
                sleep_time = max(0, cycle_interval - cycle_time)
                if sleep_time > 0:
                    sleep(sleep_time)

            except KeyboardInterrupt:
                print("\n⚠️  Keyboard interrupt received")
                break
            except e as e:
                print(f"❌ Error in trading cycle: {e}")
                # Continue running after errors (with some backoff)
                sleep(5.0)

    fn _execute_trading_cycle(self):
        """
        Execute one complete trading cycle
        """
        try:
            # 1. Discover new tokens (DexScreener)
            self._discover_new_tokens()

            # 2. Fetch market data for monitored symbols
            market_data = self._fetch_market_data()

            # 3. Run context analysis on all symbols
            contexts = {}
            for symbol, data in market_data.items():
                context = self.enhanced_context_engine.analyze_symbol(symbol, data)
                contexts[symbol] = context

            # 4. Generate trading signals
            signals = []
            for symbol, context in contexts.items():
                symbol_signals = self.strategy_engine.generate_signals(context)
                signals.extend(symbol_signals)

            # 5. Filter signals through spam filter
            filtered_signals = self.spam_filter.filter_signals(signals)
            self.signals_generated += len(filtered_signals)

            # 6. Get algorithmic sentiment analysis for high-confidence signals
            enhanced_signals = []
            for signal in filtered_signals:
                # Add metadata from market data
                if signal.symbol in market_data:
                    market_data_symbol = market_data[signal.symbol]
                    signal.metadata["price_change_5m"] = market_data_symbol.price_change_5m
                    signal.metadata["volume_5m"] = market_data_symbol.volume_5m
                    signal.metadata["holder_count"] = market_data_symbol.holder_count
                    signal.metadata["age_hours"] = market_data_symbol.age_hours

                if signal.confidence > 0.8:  # Only analyze high-confidence signals
                    sentiment = self.sentiment_analyzer.analyze_sentiment(
                        signal.symbol,
                        market_data[signal.symbol]
                    )
                    signal.sentiment_score = sentiment.sentiment_score
                    signal.ai_analysis = sentiment
                enhanced_signals.append(signal)

            # 7. Process each signal through risk management and execution
            for signal in enhanced_signals:
                if self.shutdown_event.is_set():
                    break

                # Get risk approval
                approval = self.risk_manager.approve_trade(signal)

                if approval.approved:
                    # Execute trade
                    result = self.execution_engine.execute_trade(signal, approval)

                    if result.success:
                        self.trades_executed += 1
                        self._update_portfolio(signal, approval, result)
                        print(f"✅ Trade executed: {signal.symbol} "
                              f"Size: {approval.position_size:.4f} SOL "
                              f"Price: {result.executed_price:.6f}")
                    else:
                        print(f"❌ Trade failed: {signal.symbol} - {result.error_message}")
                else:
                    print(f"⚠️  Trade rejected: {signal.symbol} - {approval.reason}")

            # 8. Update existing positions (check stop losses, take profits)
            self._manage_existing_positions()

            # 9. Update portfolio metrics
            self._update_portfolio_metrics()

        except e as e:
            print(f"❌ Error in trading cycle: {e}")
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

                # Remove from portfolio
                del self.portfolio.positions[symbol]
                self.portfolio.available_cash += result.executed_price * position.size

                # Update metrics
                self.total_pnl += realized_pnl

                print(f"✅ Position closed: {symbol} "
                      f"Reason: {reason} "
                      f"P&L: {realized_pnl:.4f} SOL")
            else:
                print(f"❌ Failed to close position {symbol}: {result.error_message}")

        except e as e:
            print(f"❌ Error closing position {symbol}: {e}")

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

        # Update peak value and drawdown
        if current_value > self.peak_value:
            self.peak_value = current_value

        current_drawdown = (self.peak_value - current_value) / self.peak_value
        if current_drawdown > self.max_drawdown:
            self.max_drawdown = current_drawdown

        # Check if circuit breaker should trigger
        if current_drawdown > self.config.trading.max_drawdown:
            print(f"🚨 Circuit breaker triggered! Drawdown: {current_drawdown:.2%}")
            self.is_running = False

    fn _monitoring_loop(self):
        """
        Background monitoring loop for metrics and health checks
        """
        while self.is_running and not self.shutdown_event.is_set():
            try:
                # Update metrics
                self.metrics = {
                    "uptime": time() - self.start_time,
                    "cycles_completed": self.cycles_completed,
                    "signals_generated": self.signals_generated,
                    "trades_executed": self.trades_executed,
                    "portfolio_value": self.portfolio.total_value,
                    "daily_pnl": self.portfolio.daily_pnl,
                    "max_drawdown": self.max_drawdown,
                    "last_cycle_time": self.last_cycle_time,
                    "open_positions": len(self.portfolio.positions)
                }

                # Health checks
                self._perform_health_checks()

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
        # This would implement database persistence
        pass

    fn _flush_metrics(self):
        """
        Flush metrics to monitoring system
        """
        # This would implement metrics export to Prometheus
        pass

    fn _close_connections(self):
        """
        Close all external connections
        """
        # Close database connections, WebSocket connections, etc.
        pass

    fn _print_final_statistics(self):
        """
        Print final trading statistics
        """
        uptime = time() - self.start_time
        hours = uptime / 3600

        print("\n" + "="*60)
        print("📊 FINAL TRADING STATISTICS")
        print("="*60)
        print(f"⏱️  Uptime: {hours:.2f} hours")
        print(f"🔄 Cycles Completed: {self.cycles_completed:,}")
        print(f"📈 Signals Generated: {self.signals_generated:,}")
        print(f"💰 Trades Executed: {self.trades_executed:,}")
        print(f"💵 Total P&L: {self.total_pnl:.4f} SOL")
        print(f"📉 Max Drawdown: {self.max_drawdown:.2%}")
        print(f"🏆 Peak Portfolio Value: {self.peak_value:.4f} SOL")
        print(f"💼 Final Portfolio Value: {self.portfolio.total_value:.4f} SOL")
        print(f"🎯 Win Rate: {(self.trades_executed / max(1, self.signals_generated) * 100):.1f}%")
        print("="*60)

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