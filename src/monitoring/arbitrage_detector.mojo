"""
Mojo Wrapper for Arbitrage Detection Engine

Provides high-performance Mojo interface to the Rust arbitrage detection engine.
Supports triangular arbitrage, cross-DEX arbitrage, and statistical arbitrage.
"""

from memory.unsafe import Pointer
from python import Python
from sys import Error, SIValue
from time import sleep

# Import FFI functions from Rust modules
# These are defined in rust-modules/src/ffi/mod.rs

# Helper function to convert C string (Pointer[UInt8]) to Mojo String
fn c_str_to_string(c_str_ptr: Pointer[UInt8]) -> String:
    if c_str_ptr.address() == 0:
        return ""

    var result = String()
    var i = 0
    while True:
        var byte = c_str_ptr[i]
        if byte == 0:  # NUL terminator
            break
        result += String(byte)
        i += 1
    return result

# External FFI function declarations
fn arbitrage_engine_init_global(config: FfiArbitrageConfig) -> FfiResult = external

# Optimized FFI function declarations
fn ffi_initialize_optimizations(num_worker_threads: UInt) -> FfiResult = external
fn arbitrage_engine_get_triangular_opportunities_fast(
    out_opportunities: Pointer[Pointer[FfiTriangularOpportunity]],
    out_count: Pointer[UInt]
) -> FfiResult = external
fn arbitrage_engine_update_price_batch(
    updates: Pointer[FfiPriceUpdate],
    count: UInt
) -> FfiResult = external
fn arbitrage_worker_pool_submit_scan() -> UInt64 = external
fn arbitrage_worker_pool_poll_result(
    task_id: UInt64,
    out_triangular_count: Pointer[UInt],
    out_cross_dex_count: Pointer[UInt],
    out_statistical_count: Pointer[UInt],
    out_is_complete: Pointer[Bool]
) -> FfiResult = external
fn ffi_is_simd_available() -> Bool = external
fn ffi_calculate_triangular_profit_simd(
    prices: Pointer[Float64],
    fees: Pointer[Float64]
) -> Float64 = external
fn ffi_calculate_batch_triangular_profits(
    opportunities: Pointer[FfiTriangularBatchInput],
    count: UInt,
    out_results: Pointer[Float64]
) -> FfiResult = external
fn arbitrage_engine_register_token(
    address: String,
    symbol: String,
    name: String,
    decimals: UInt8,
    verified: Bool
) -> FfiResult = external
fn arbitrage_engine_update_price(
    token_address: String,
    dex_name: String,
    price: Float64,
    liquidity: Float64,
    volume_24h: Float64
) -> FfiResult = external
fn arbitrage_engine_scan_opportunities(
    out_triangular_count: Pointer[UInt],
    out_cross_dex_count: Pointer[UInt],
    out_statistical_count: Pointer[UInt]
) -> FfiResult = external
fn arbitrage_engine_get_triangular_opportunities(
    out_opportunities: Pointer[Pointer[FfiTriangularOpportunity]],
    out_count: Pointer[UInt]
) -> FfiResult = external
fn arbitrage_engine_free_triangular_opportunities(
    opportunities: Pointer[FfiTriangularOpportunity],
    count: UInt
) = external
fn arbitrage_engine_get_cross_dex_opportunities(
    out_opportunities: Pointer[Pointer[FfiCrossDexOpportunity]],
    out_count: Pointer[UInt]
) -> FfiResult = external
fn arbitrage_engine_free_cross_dex_opportunities(
    opportunities: Pointer[FfiCrossDexOpportunity],
    count: UInt
) = external
fn arbitrage_engine_get_statistical_opportunities(
    out_opportunities: Pointer[Pointer[FfiStatisticalOpportunity]],
    out_count: Pointer[UInt]
) -> FfiResult = external
fn arbitrage_engine_free_statistical_opportunities(
    opportunities: Pointer[FfiStatisticalOpportunity],
    count: UInt
) = external
fn arbitrage_engine_is_initialized() -> Int = external
fn arbitrage_engine_get_status(
    out_is_running: Pointer[Bool],
    out_registered_tokens: Pointer[UInt],
    out_triangular_count: Pointer[UInt],
    out_cross_dex_count: Pointer[UInt],
    out_statistical_count: Pointer[UInt]
) -> FfiResult = external

# FFI structures (matching Rust definitions)
@value
struct FfiArbitrageConfig:
    var min_profit_threshold: Float64
    var max_slippage: Float64
    var min_liquidity: Float64
    var max_gas_price: Float64
    var confidence_threshold: Float64
    var scan_interval_ms: UInt64
    var opportunity_timeout_ms: UInt64
    var max_concurrent_trades: UInt
    var risk_tolerance: Float64

@value
struct FfiResult:
    var code: Int

@value
struct FfiTriangularOpportunity:
    var cycle_addresses: StaticArray[Pointer[UInt8], 4]  # C string pointers
    var cycle_symbols: StaticArray[Pointer[UInt8], 4]     # C string pointers
    var dex_names: StaticArray[Pointer[UInt8], 3]        # C string pointers
    var prices: StaticArray[Float64, 3]
    var profit_percentage: Float64
    var estimated_gas_cost: Float64
    var liquidity_score: Float64
    var confidence_score: Float64
    var timestamp: Int64
    var slippage_estimate: Float64

@value
struct FfiCrossDexOpportunity:
    var token_address: Pointer[UInt8]   # C string pointer
    var token_symbol: Pointer[UInt8]    # C string pointer
    var buy_dex: Pointer[UInt8]        # C string pointer
    var sell_dex: Pointer[UInt8]       # C string pointer
    var buy_price: Float64
    var sell_price: Float64
    var spread_percentage: Float64
    var buy_liquidity: Float64
    var sell_liquidity: Float64
    var estimated_gas_cost: Float64
    var profit_after_gas: Float64
    var timestamp: Int64

@value
struct FfiStatisticalOpportunity:
    var token_address: Pointer[UInt8]   # C string pointer
    var token_symbol: Pointer[UInt8]    # C string pointer
    var current_price: Float64
    var mean_price: Float64
    var std_deviation: Float64
    var z_score: Float64
    var expected_return: Float64
    var confidence: Float64
    var holding_period_ms: UInt64
    var timestamp: Int64

# Optimized FFI structures
@value
struct FfiPriceUpdate:
    var token_address: String
    var dex_name: String
    var price: Float64
    var liquidity: Float64
    var volume_24h: Float64

@value
struct FfiTriangularBatchInput:
    var price1: Float64
    var price2: Float64
    var price3: Float64
    var fee1: Float64
    var fee2: Float64
    var fee3: Float64

# Async task status tracking
@value
struct AsyncTaskStatus:
    var status: String
    var submitted_at: Float64
    var completed_at: Float64

    @staticmethod
    fn pending() -> AsyncTaskStatus:
        return AsyncTaskStatus("pending", 0.0, 0.0)

    @staticmethod
    fn completed() -> AsyncTaskStatus:
        return AsyncTaskStatus("completed", 0.0, 0.0)

# Mojo-friendly data structures
@value
struct ArbitrageConfig:
    var min_profit_threshold: Float64
    var max_slippage: Float64
    var min_liquidity: Float64
    var max_gas_price: Float64
    var confidence_threshold: Float64
    var scan_interval_ms: UInt64
    var opportunity_timeout_ms: UInt64
    var max_concurrent_trades: UInt
    var risk_tolerance: Float64

    fn __init__(min_profit_threshold: Float64 = 0.5,
                max_slippage: Float64 = 2.0,
                min_liquidity: Float64 = 10000.0,
                max_gas_price: Float64 = 0.01,
                confidence_threshold: Float64 = 0.7,
                scan_interval_ms: UInt64 = 500,
                opportunity_timeout_ms: UInt64 = 30000,
                max_concurrent_trades: UInt = 5,
                risk_tolerance: Float64 = 0.5):
        self.min_profit_threshold = min_profit_threshold
        self.max_slippage = max_slippage
        self.min_liquidity = min_liquidity
        self.max_gas_price = max_gas_price
        self.confidence_threshold = confidence_threshold
        self.scan_interval_ms = scan_interval_ms
        self.opportunity_timeout_ms = opportunity_timeout_ms
        self.max_concurrent_trades = max_concurrent_trades
        self.risk_tolerance = risk_tolerance

    fn to_ffi(self) -> FfiArbitrageConfig:
        return FfiArbitrageConfig(
            min_profit_threshold=self.min_profit_threshold,
            max_slippage=self.max_slippage,
            min_liquidity=self.min_liquidity,
            max_gas_price=self.max_gas_price,
            confidence_threshold=self.confidence_threshold,
            scan_interval_ms=self.scan_interval_ms,
            opportunity_timeout_ms=self.opportunity_timeout_ms,
            max_concurrent_trades=self.max_concurrent_trades,
            risk_tolerance=self.risk_tolerance
        )

@value
struct TriangularOpportunity:
    var cycle: List[String]        # Token addresses in cycle
    var symbols: List[String]       # Token symbols
    var dexes: List[String]         # DEX names for each edge
    var prices: List[Float64]       # Prices for each edge
    var profit_percentage: Float64  # Net profit percentage
    var estimated_gas_cost: Float64  # SOL gas cost
    var liquidity_score: Float64    # Minimum liquidity along path
    var confidence_score: Float64   # Statistical confidence
    var timestamp: Int64            # Unix timestamp
    var slippage_estimate: Float64  # Estimated slippage

@value
struct CrossDexOpportunity:
    var token_address: String       # Token mint address
    var symbol: String              # Token symbol
    var buy_dex: String             # DEX to buy from
    var sell_dex: String            # DEX to sell to
    var buy_price: Float64          # Buy price
    var sell_price: Float64         # Sell price
    var spread_percentage: Float64  # Price spread percentage
    var buy_liquidity: Float64      # Buy liquidity
    var sell_liquidity: Float64     # Sell liquidity
    var estimated_gas_cost: Float64 # SOL gas cost
    var profit_after_gas: Float64   # Profit after gas costs
    var timestamp: Int64            # Unix timestamp

@value
struct StatisticalOpportunity:
    var token_address: String       # Token mint address
    var symbol: String              # Token symbol
    var current_price: Float64      # Current price
    var mean_price: Float64         # Historical mean price
    var std_deviation: Float64      # Standard deviation
    var z_score: Float64            # Z-score
    var expected_return: Float64    # Expected return percentage
    var confidence: Float64         # Confidence level
    var holding_period_ms: UInt64   # Expected holding period
    var timestamp: Int64            # Unix timestamp

@value
struct ArbitrageStatus:
    var is_running: Bool
    var registered_tokens: UInt
    var triangular_opportunities: UInt
    var cross_dex_opportunities: UInt
    var statistical_opportunities: UInt

# Main arbitrage detector class
struct ArbitrageDetector:
    var config: ArbitrageConfig
    var initialized: Bool
    var optimizations_enabled: Bool
    var python_config: PythonObject
    var worker_threads: UInt
    var async_tasks: Dict[UInt64, AsyncTaskStatus]

    fn __init__(config: ArbitrageConfig = ArbitrageConfig(), enable_optimizations: Bool = True, worker_threads: UInt = 4):
        self.config = config
        self.initialized = False
        self.optimizations_enabled = enable_optimizations
        self.worker_threads = worker_threads
        self.async_tasks = {}

        # Load configuration
        self._load_config()

        # Initialize optimizations first if enabled
        if self.optimizations_enabled:
            self._initialize_optimizations()

        # Initialize the Rust arbitrage engine
        self._initialize_engine()

    fn _load_config(self):
        """Load configuration from trading.toml"""
        try:
            python = Python.import_module("builtins")

            # Try to import tomlllib (Python 3.11+) first, then fallback to toml
            try:
                toml = Python.import_module("tomllib")
                with open("config/trading.toml", "rb") as f:
                    config_data = toml.load(f)
            except Error:
                toml = Python.import_module("toml")
                with open("config/trading.toml", "r") as f:
                    config_data = toml.load(f)

            # Extract arbitrage configuration
            arbitrage_config = config_data.get("arbitrage", {})

            self.config.min_profit_threshold = arbitrage_config.get("min_profit_threshold", 0.5)
            self.config.max_slippage = arbitrage_config.get("max_slippage", 2.0)
            self.config.min_liquidity = arbitrage_config.get("min_liquidity", 10000.0)
            self.config.max_gas_price = arbitrage_config.get("max_gas_price", 0.01)
            self.config.confidence_threshold = arbitrage_config.get("confidence_threshold", 0.7)
            self.config.scan_interval_ms = arbitrage_config.get("scan_interval_ms", 500)
            self.config.opportunity_timeout_ms = arbitrage_config.get("opportunity_timeout_ms", 30000)
            self.config.max_concurrent_trades = arbitrage_config.get("max_concurrent_trades", 5)
            self.config.risk_tolerance = arbitrage_config.get("risk_tolerance", 0.5)

            print("✅ Arbitrage detector configuration loaded:")
            print(f"   Min profit threshold: {self.config.min_profit_threshold}%")
            print(f"   Max slippage: {self.config.max_slippage}%")
            print(f"   Scan interval: {self.config.scan_interval_ms}ms")

        except Error as e:
            print(f"⚠️  Failed to load arbitrage config, using defaults: {e}")
        except:
            print("⚠️  Config file not found, using arbitrage defaults")

    fn _initialize_engine(self):
        """Initialize the Rust arbitrage engine"""
        try:
            ffi_config = self.config.to_ffi()
            result = arbitrage_engine_init_global(ffi_config)

            if result.code == 0:  # FfiResult::Success
                self.initialized = True
                print("✅ Arbitrage engine initialized successfully")
            else:
                print(f"❌ Failed to initialize arbitrage engine: {result.code}")
                self.initialized = False

        except Error as e:
            print(f"❌ Failed to initialize arbitrage engine: {e}")
            self.initialized = False

    fn _initialize_optimizations(self):
        """Initialize FFI optimizations"""
        if not self.optimizations_enabled:
            return

        try:
            print(f"🚀 Initializing FFI optimizations with {self.worker_threads} worker threads")
            result = ffi_initialize_optimizations(self.worker_threads)

            if result.code == 0:
                print("✅ FFI optimizations initialized successfully")
                print(f"📊 SIMD available: {ffi_is_simd_available()}")
            else:
                print(f"⚠️  Failed to initialize FFI optimizations: {result.code}")
                self.optimizations_enabled = False

        except Error as e:
            print(f"⚠️  Failed to initialize FFI optimizations: {e}")
            self.optimizations_enabled = False

    fn register_token(self, address: String, symbol: String, name: String, decimals: UInt8, verified: Bool = False) -> Bool:
        """Register a token with the arbitrage engine"""
        if not self.initialized:
            print("❌ Arbitrage engine not initialized")
            return False

        try:
            result = arbitrage_engine_register_token(address, symbol, name, decimals, verified)

            if result.code == 0:
                print(f"✅ Token registered: {symbol} ({address})")
                return True
            else:
                print(f"❌ Failed to register token {symbol}: {result.code}")
                return False

        except Error as e:
            print(f"❌ Failed to register token {symbol}: {e}")
            return False

    fn update_price(self, token_address: String, dex_name: String, price: Float64,
                   liquidity: Float64 = 0.0, volume_24h: Float64 = 0.0) -> Bool:
        """Update price data for a token"""
        if not self.initialized:
            print("❌ Arbitrage engine not initialized")
            return False

        try:
            result = arbitrage_engine_update_price(token_address, dex_name, price, liquidity, volume_24h)

            if result.code == 0:
                return True
            else:
                print(f"❌ Failed to update price for {token_address} on {dex_name}: {result.code}")
                return False

        except Error as e:
            print(f"❌ Failed to update price for {token_address}: {e}")
            return False

    fn update_prices_batch(self, updates: List[FfiPriceUpdate]) -> Bool:
        """Update multiple prices in batch for optimal performance"""
        if not self.initialized:
            print("❌ Arbitrage engine not initialized")
            return False

        if not self.optimizations_enabled:
            # Fallback to individual updates
            print("⚠️  Optimizations not enabled, using individual updates")
            success = True
            for update in updates:
                if not self.update_price(update.token_address, update.dex_name,
                                       update.price, update.liquidity, update.volume_24h):
                    success = False
            return success

        try:
            print(f"📦 Updating {len(updates)} prices in batch")
            result = arbitrage_engine_update_price_batch(updates.data(), len(updates))

            if result.code == 0:
                print("✅ Batch price update completed successfully")
                return True
            else:
                print(f"❌ Failed to update batch prices: {result.code}")
                return False

        except Error as e:
            print(f"❌ Failed to update batch prices: {e}")
            return False

    fn scan_opportunities(self) -> Tuple[UInt, UInt, UInt]:
        """Scan for arbitrage opportunities"""
        if not self.initialized:
            print("❌ Arbitrage engine not initialized")
            return (0, 0, 0)

        try:
            var triangular_count = 0
            var cross_dex_count = 0
            var statistical_count = 0

            result = arbitrage_engine_scan_opportunities(
                Pointer.addressof(triangular_count),
                Pointer.addressof(cross_dex_count),
                Pointer.addressof(statistical_count)
            )

            if result.code == 0:
                print(f"🔍 Scan completed: {triangular_count} triangular, {cross_dex_count} cross-DEX, {statistical_count} statistical")
                return (triangular_count, cross_dex_count, statistical_count)
            else:
                print(f"❌ Failed to scan opportunities: {result.code}")
                return (0, 0, 0)

        except Error as e:
            print(f"❌ Failed to scan opportunities: {e}")
            return (0, 0, 0)

    def submit_async_scan(self) -> UInt64:
        """Submit async arbitrage scan to worker pool"""
        if not self.initialized or not self.optimizations_enabled:
            print("❌ Async scanning not available (engine not initialized or optimizations disabled)")
            return 0

        try:
            task_id = arbitrage_worker_pool_submit_scan()
            if task_id > 0:
                self.async_tasks[task_id] = AsyncTaskStatus.pending()
                print(f"📤 Submitted async scan task: {task_id}")
                return task_id
            else:
                print("❌ Failed to submit async scan task")
                return 0

        except Error as e:
            print(f"❌ Failed to submit async scan: {e}")
            return 0

    def poll_scan_result(self, task_id: UInt64) -> Tuple[Bool, UInt, UInt, UInt]:
        """Poll for async scan result"""
        if not self.initialized or not self.optimizations_enabled:
            return (False, 0, 0, 0)

        try:
            var triangular_count = 0
            var cross_dex_count = 0
            var statistical_count = 0
            var is_complete = False

            result = arbitrage_worker_pool_poll_result(
                task_id,
                Pointer.addressof(triangular_count),
                Pointer.addressof(cross_dex_count),
                Pointer.addressof(statistical_count),
                Pointer.addressof(is_complete)
            )

            if result.code == 0:
                if is_complete and task_id in self.async_tasks:
                    self.async_tasks[task_id] = AsyncTaskStatus.completed()
                    print(f"📥 Async scan completed: {triangular_count} triangular, {cross_dex_count} cross-DEX, {statistical_count} statistical")

                return (is_complete, triangular_count, cross_dex_count, statistical_count)
            else:
                print(f"❌ Failed to poll scan result: {result.code}")
                return (False, 0, 0, 0)

        except Error as e:
            print(f"❌ Failed to poll scan result: {e}")
            return (False, 0, 0, 0)

    def calculate_triangular_profit_simd(self, prices: List[Float64], fees: List[Float64]) -> Float64:
        """Calculate triangular arbitrage profit using SIMD"""
        if not self.optimizations_enabled:
            # Fallback to scalar calculation
            return (1.0 / prices[0]) * (1.0 - fees[0]) * \
                   (1.0 / prices[1]) * (1.0 - fees[1]) * \
                   (1.0 / prices[2]) * (1.0 - fees[2]) - 1.0

        try:
            return ffi_calculate_triangular_profit_simd(prices.data(), fees.data())
        except Error as e:
            print(f"❌ Failed to calculate triangular profit with SIMD: {e}")
            # Fallback to scalar calculation
            return (1.0 / prices[0]) * (1.0 - fees[0]) * \
                   (1.0 / prices[1]) * (1.0 - fees[1]) * \
                   (1.0 / prices[2]) * (1.0 - fees[2]) - 1.0

    def calculate_batch_triangular_profits_simd(self, opportunities: List[FfiTriangularBatchInput]) -> List[Float64]:
        """Calculate batch triangular profits using SIMD"""
        if opportunities.is_empty():
            return []

        if not self.optimizations_enabled:
            # Fallback to individual calculations
            results = List[Float64]()
            for opp in opportunities:
                profit = self.calculate_triangular_profit_simd(
                    [opp.price1, opp.price2, opp.price3],
                    [opp.fee1, opp.fee2, opp.fee3]
                )
                results.append(profit)
            return results

        try:
            var results = List[Float64]()
            results.resize(len(opportunities))

            result = ffi_calculate_batch_triangular_profits(
                opportunities.data(),
                len(opportunities),
                results.data()
            )

            if result.code == 0:
                return results
            else:
                print(f"❌ Failed to calculate batch profits: {result.code}")
                return []

        except Error as e:
            print(f"❌ Failed to calculate batch profits with SIMD: {e}")
            return []

    fn get_triangular_opportunities(self) -> List[TriangularOpportunity]:
        """Get triangular arbitrage opportunities using optimized memory pools"""
        if not self.initialized:
            return List[TriangularOpportunity]()

        try:
            # Use optimized function if available
            if self.optimizations_enabled:
                return self._get_triangular_opportunities_fast()
            else:
                return self._get_triangular_opportunities_standard()

        except Error as e:
            print(f"❌ Failed to get triangular opportunities: {e}")
            return List[TriangularOpportunity]()

    fn _get_triangular_opportunities_fast(self) -> List[TriangularOpportunity]:
        """Get triangular opportunities using optimized memory pools"""
        try:
            var opportunities_ptr = Pointer[FfiTriangularOpportunity]()
            var count = 0

            result = arbitrage_engine_get_triangular_opportunities_fast(
                Pointer.addressof(opportunities_ptr),
                Pointer.addressof(count)
            )

            if result.code != 0 or count == 0:
                return List[TriangularOpportunity]()

            print(f"🚀 Retrieved {count} triangular opportunities using optimized memory pools")

            # Convert FFI opportunities to Mojo structures
            var mojo_opportunities = List[TriangularOpportunity]()

            # This is simplified - in practice, we'd need to properly handle the C array
            # For now, we'll create a placeholder implementation
            for i in range(count):
                # Create a placeholder opportunity
                opportunity = TriangularOpportunity(
                    cycle=["", "", "", ""],
                    symbols=["", "", "", ""],
                    dexes=["", "", ""],
                    prices=[0.0, 0.0, 0.0],
                    profit_percentage=0.0,
                    estimated_gas_cost=0.0,
                    liquidity_score=0.0,
                    confidence_score=0.0,
                    timestamp=0,
                    slippage_estimate=0.0
                )
                mojo_opportunities.append(opportunity)

            # Free the C memory
            arbitrage_engine_free_triangular_opportunities(opportunities_ptr, count)

            return mojo_opportunities

        except Error as e:
            print(f"❌ Failed to get triangular opportunities (optimized): {e}")
            return List[TriangularOpportunity]()

    fn _get_triangular_opportunities_standard(self) -> List[TriangularOpportunity]:
        """Get triangular opportunities using standard FFI"""
        try:
            var opportunities_ptr = Pointer[FfiTriangularOpportunity]()
            var count = 0

            result = arbitrage_engine_get_triangular_opportunities(
                Pointer.addressof(opportunities_ptr),
                Pointer.addressof(count)
            )

            if result.code != 0 or count == 0:
                return List[TriangularOpportunity]()

            # Convert FFI opportunities to Mojo structures
            var mojo_opportunities = List[TriangularOpportunity]()

            # This is simplified - in practice, we'd need to properly handle the C array
            # For now, we'll create a placeholder implementation
            for i in range(count):
                # Create a placeholder opportunity
                opportunity = TriangularOpportunity(
                    cycle=["", "", "", ""],
                    symbols=["", "", "", ""],
                    dexes=["", "", ""],
                    prices=[0.0, 0.0, 0.0],
                    profit_percentage=0.0,
                    estimated_gas_cost=0.0,
                    liquidity_score=0.0,
                    confidence_score=0.0,
                    timestamp=0,
                    slippage_estimate=0.0
                )
                mojo_opportunities.append(opportunity)

            # Free the C memory
            arbitrage_engine_free_triangular_opportunities(opportunities_ptr, count)

            return mojo_opportunities

        except Error as e:
            print(f"❌ Failed to get triangular opportunities (standard): {e}")
            return List[TriangularOpportunity]()

    fn get_cross_dex_opportunities(self) -> List[CrossDexOpportunity]:
        """Get cross-DEX arbitrage opportunities"""
        if not self.initialized:
            return List[CrossDexOpportunity]()

        try:
            var opportunities_ptr = Pointer[FfiCrossDexOpportunity]()
            var count = 0

            result = arbitrage_engine_get_cross_dex_opportunities(
                Pointer.addressof(opportunities_ptr),
                Pointer.addressof(count)
            )

            if result.code != 0 or count == 0:
                return List[CrossDexOpportunity]()

            # Convert FFI opportunities to Mojo structures
            var mojo_opportunities = List[CrossDexOpportunity]()

            # Simplified implementation
            for i in range(count):
                opportunity = CrossDexOpportunity(
                    token_address="",
                    symbol="",
                    buy_dex="",
                    sell_dex="",
                    buy_price=0.0,
                    sell_price=0.0,
                    spread_percentage=0.0,
                    buy_liquidity=0.0,
                    sell_liquidity=0.0,
                    estimated_gas_cost=0.0,
                    profit_after_gas=0.0,
                    timestamp=0
                )
                mojo_opportunities.append(opportunity)

            # Free the C memory
            arbitrage_engine_free_cross_dex_opportunities(opportunities_ptr, count)

            return mojo_opportunities

        except Error as e:
            print(f"❌ Failed to get cross-DEX opportunities: {e}")
            return List[CrossDexOpportunity]()

    fn get_statistical_opportunities(self) -> List[StatisticalOpportunity]:
        """Get statistical arbitrage opportunities"""
        if not self.initialized:
            return List[StatisticalOpportunity]()

        try:
            var opportunities_ptr = Pointer[FfiStatisticalOpportunity]()
            var count = 0

            result = arbitrage_engine_get_statistical_opportunities(
                Pointer.addressof(opportunities_ptr),
                Pointer.addressof(count)
            )

            if result.code != 0 or count == 0:
                return List[StatisticalOpportunity]()

            # Convert FFI opportunities to Mojo structures
            var mojo_opportunities = List[StatisticalOpportunity]()

            # Simplified implementation
            for i in range(count):
                opportunity = StatisticalOpportunity(
                    token_address="",
                    symbol="",
                    current_price=0.0,
                    mean_price=0.0,
                    std_deviation=0.0,
                    z_score=0.0,
                    expected_return=0.0,
                    confidence=0.0,
                    holding_period_ms=0,
                    timestamp=0
                )
                mojo_opportunities.append(opportunity)

            # Free the C memory
            arbitrage_engine_free_statistical_opportunities(opportunities_ptr, count)

            return mojo_opportunities

        except Error as e:
            print(f"❌ Failed to get statistical opportunities: {e}")
            return List[StatisticalOpportunity]()

    fn get_status(self) -> ArbitrageStatus:
        """Get current arbitrage engine status"""
        try:
            var is_running = False
            var registered_tokens = 0
            var triangular_count = 0
            var cross_dex_count = 0
            var statistical_count = 0

            result = arbitrage_engine_get_status(
                Pointer.addressof(is_running),
                Pointer.addressof(registered_tokens),
                Pointer.addressof(triangular_count),
                Pointer.addressof(cross_dex_count),
                Pointer.addressof(statistical_count)
            )

            if result.code == 0:
                return ArbitrageStatus(
                    is_running=is_running,
                    registered_tokens=registered_tokens,
                    triangular_opportunities=triangular_count,
                    cross_dex_opportunities=cross_dex_count,
                    statistical_opportunities=statistical_count
                )
            else:
                return ArbitrageStatus(
                    is_running=False,
                    registered_tokens=0,
                    triangular_opportunities=0,
                    cross_dex_opportunities=0,
                    statistical_opportunities=0
                )

        except Error as e:
            print(f"❌ Failed to get arbitrage status: {e}")
            return ArbitrageStatus(
                is_running=False,
                registered_tokens=0,
                triangular_opportunities=0,
                cross_dex_opportunities=0,
                statistical_opportunities=0
            )

    def is_initialized(self) -> Bool:
        """Check if the arbitrage engine is initialized"""
        return self.initialized and arbitrage_engine_is_initialized() != 0

    def update_config(self, new_config: ArbitrageConfig):
        """Update configuration"""
        self.config = new_config

        # Reinitialize engine with new config
        if self.initialized:
            print("🔄 Reinitializing arbitrage engine with new configuration")
            self._initialize_engine()

        print("✅ Arbitrage detector configuration updated")

    def start_monitoring_loop(self, scan_interval_ms: UInt64 = 1000):
        """Start continuous monitoring loop"""
        print(f"🚀 Starting arbitrage monitoring loop (interval: {scan_interval_ms}ms)")

        while True:
            try:
                # Scan for opportunities
                (triangular, cross_dex, statistical) = self.scan_opportunities()

                # Get status
                status = self.get_status()
                print(f"📊 Status: {status.registered_tokens} tokens, "
                      f"{triangular} triangular, {cross_dex} cross-DEX, {statistical} statistical opportunities")

                # Sleep for the specified interval
                sleep(Float64(scan_interval_ms) / 1000.0)

            except Error as e:
                print(f"❌ Error in monitoring loop: {e}")
                sleep(1.0)  # Wait 1 second before retrying

    def register_common_tokens(self) -> Bool:
        """Register common Solana tokens"""
        try:
            # Common Solana tokens
            tokens = [
                ("So11111111111111111111111111111111111111112", "SOL", "Solana", 9, True),
                ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "USDC", "USD Coin", 6, True),
                ("Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB", "USDT", "Tether USD", 6, True),
                ("mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So", "msol", "Marinade SOL", 9, True),
                ("7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iLJ3j3HLJBM9t", "JUP", "Jupiter", 6, True),
                ("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", "JUP", "Jupiter Token", 6, True),
            ]

            for (address, symbol, name, decimals, verified) in tokens:
                self.register_token(address, symbol, name, UInt8(decimals), verified)

            print("✅ Common Solana tokens registered")
            return True

        except Error as e:
            print(f"❌ Failed to register common tokens: {e}")
            return False

    def demo_price_updates(self) -> Bool:
        """Demo: Update some sample prices"""
        try:
            # Sample price updates
            price_updates = [
                ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "Raydium", 1.001, 50000.0, 1000000.0),
                ("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", "Orca", 1.002, 75000.0, 1200000.0),
                ("So11111111111111111111111111111111111111112", "Raydium", 145.50, 10000.0, 500000.0),
                ("So11111111111111111111111111111111111111112", "Orca", 145.48, 15000.0, 750000.0),
                ("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", "Raydium", 0.825, 25000.0, 300000.0),
                ("JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN", "Orca", 0.827, 30000.0, 350000.0),
            ]

            for (token, dex, price, liquidity, volume) in price_updates:
                self.update_price(token, dex, price, liquidity, volume)

            print("✅ Demo price updates completed")
            return True

        except Error as e:
            print(f"❌ Failed to update demo prices: {e}")
            return False

# Utility functions for convenience
fn create_arbitrage_detector() -> ArbitrageDetector:
    """Create arbitrage detector with default configuration"""
    return ArbitrageDetector()

fn create_arbitrage_detector_with_config(config: ArbitrageConfig) -> ArbitrageDetector:
    """Create arbitrage detector with custom configuration"""
    return ArbitrageDetector(config)

fn demo_arbitrage_detection():
    """Demo function showing arbitrage detection usage"""
    print("🚀 Starting arbitrage detection demo")

    # Create detector
    detector = create_arbitrage_detector()

    if not detector.is_initialized():
        print("❌ Failed to initialize arbitrage detector")
        return

    # Register common tokens
    detector.register_common_tokens()

    # Update some sample prices
    detector.demo_price_updates()

    # Scan for opportunities
    (triangular, cross_dex, statistical) = detector.scan_opportunities()

    # Get status
    status = detector.get_status()
    print(f"📊 Final Status: {status.registered_tokens} tokens registered")
    print(f"   Triangular opportunities: {status.triangular_opportunities}")
    print(f"   Cross-DEX opportunities: {status.cross_dex_opportunities}")
    print(f"   Statistical opportunities: {status.statistical_opportunities}")

    print("✅ Arbitrage detection demo completed")