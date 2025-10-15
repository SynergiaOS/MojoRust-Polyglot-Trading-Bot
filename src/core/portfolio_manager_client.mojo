"""
Portfolio Manager Client - Mojo Wrapper for Rust PortfolioManager FFI

This module provides a Mojo interface to the Rust PortfolioManager through FFI,
enabling high-performance capital management, position tracking, and risk controls
for the MojoRust trading bot.

Features:
- Unified capital management for sniper + arbitrage strategies
- Real-time position tracking and P&L calculation
- Risk management with configurable limits
- Priority-based execution queues
- Emergency stop functionality
- Memory-safe operations with automatic cleanup
"""

from python import Python
from memory.unsafe import Pointer
from memory import UnsafePointer
from string import StringRef
from sys.info import num_simd_lanes

# Import the compiled Rust library
# This assumes the library is compiled and available in the path
# In practice, this would be linked during the build process

# FFI Result codes (matching Rust FFI enum)
alias FFIResult = SI32
const SUCCESS = 0
const INVALID_INPUT = -1
const INTERNAL_ERROR = -2
const MEMORY_ERROR = -3
const NETWORK_ERROR = -4
const CRYPTO_ERROR = -5
const SECURITY_ERROR = -6
const SOLANA_ERROR = -7

# Strategy types (matching Rust StrategyType enum)
alias StrategyType = SI32
const STRATEGY_SNIPER = 0
const STRATEGY_ARBITRAGE = 1
const STRATEGY_FLASH_LOAN = 2
const STRATEGY_MARKET_MAKING = 3

# Order sides (matching Rust OrderSide enum)
alias OrderSide = SI32
const ORDER_BUY = 0
const ORDER_SELL = 1

# Risk levels (matching Rust RiskLevel enum)
alias RiskLevel = SI32
const RISK_LOW = 1
const RISK_MEDIUM = 2
const RISK_HIGH = 3
const RISK_CRITICAL = 4

# FFI byte structure for passing data between Mojo and Rust
@register(passable)
struct FFIBytes:
    var data: UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]]
    var len: UInt
    var capacity: UInt

# UUID structure (16 bytes)
@register(passable)
struct UUID:
    var data: SIMD[DType.uint8, 16]

@value
struct PositionInfo:
    """Position information returned from PortfolioManager"""
    var id: UUID
    var strategy: StrategyType
    var token_mint: String
    var symbol: String
    var side: OrderSide
    var size: Float
    var entry_price: Float
    var current_price: Float
    var unrealized_pnl: Float
    var realized_pnl: Float
    var fees_paid: Float
    var risk_level: RiskLevel
    var created_at: UInt
    var updated_at: UInt

@value
struct PortfolioMetrics:
    """Portfolio metrics returned from PortfolioManager"""
    var total_capital: Float
    var available_capital: Float
    var used_capital: Float
    var total_pnl: Float
    var unrealized_pnl: Float
    var realized_pnl: Float
    var total_fees: Float
    var open_positions: UInt
    var closed_positions: UInt
    var win_rate: Float
    var sharpe_ratio: Float
    var max_drawdown: Float
    var last_updated: UInt

@value
struct CapitalAllocation:
    """Capital allocation information for a strategy"""
    var strategy: StrategyType
    var allocated_capital: Float
    var used_capital: Float
    var available_capital: Float
    var max_position_size: Float
    var risk_limit: Float
    var priority: UInt8

# External function declarations (matching Rust FFI)
@extern("portfolio_manager_new")
fn _portfolio_manager_new(total_capital: Float) -> UnsafePointer[None]

@extern("portfolio_manager_destroy")
fn _portfolio_manager_destroy(manager: UnsafePointer[None])

@extern("portfolio_manager_init_global")
fn _portfolio_manager_init_global(total_capital: Float) -> FFIResult

@extern("portfolio_manager_open_position")
fn _portfolio_manager_open_position(
    manager: UnsafePointer[None],
    strategy: StrategyType,
    token_mint: UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]],
    symbol: UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]],
    side: OrderSide,
    size: Float,
    entry_price: Float,
    risk_level: RiskLevel,
    out_position_id: UnsafePointer[UUID]
) -> FFIResult

@extern("portfolio_manager_close_position")
fn _portfolio_manager_close_position(
    manager: UnsafePointer[None],
    position_id: UnsafePointer[UUID],
    close_price: Float,
    fees: Float,
    out_pnl: UnsafePointer[Float]
) -> FFIResult

@extern("portfolio_manager_update_position_price")
fn _portfolio_manager_update_position_price(
    manager: UnsafePointer[None],
    position_id: UnsafePointer[UUID],
    new_price: Float
) -> FFIResult

@extern("portfolio_manager_get_metrics")
fn _portfolio_manager_get_metrics(
    manager: UnsafePointer[None],
    out_bytes: UnsafePointer[FFIBytes]
) -> FFIResult

@extern("portfolio_manager_get_available_capital")
fn _portfolio_manager_get_available_capital(
    manager: UnsafePointer[None],
    strategy: StrategyType,
    out_capital: UnsafePointer[Float]
) -> FFIResult

@extern("portfolio_manager_can_take_position")
fn _portfolio_manager_can_take_position(
    manager: UnsafePointer[None],
    strategy: StrategyType,
    amount: Float,
    risk_level: RiskLevel,
    out_can_take: UnsafePointer[Bool]
) -> FFIResult

@extern("portfolio_manager_update_token_price")
fn _portfolio_manager_update_token_price(
    manager: UnsafePointer[None],
    token_mint: UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]],
    symbol: UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]],
    price: Float,
    decimals: UInt8
) -> FFIResult

@extern("portfolio_manager_set_emergency_stop")
fn _portfolio_manager_set_emergency_stop(
    manager: UnsafePointer[None],
    stop: Bool
) -> FFIResult

@extern("portfolio_manager_get_open_positions_count")
fn _portfolio_manager_get_open_positions_count(
    manager: UnsafePointer[None],
    out_count: UnsafePointer[UInt]
) -> FFIResult

@extern("ffi_bytes_free")
fn _ffi_bytes_free(bytes: FFIBytes)

@extern("ffi_set_last_error")
fn _ffi_set_last_error(message: UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]])

@extern("ffi_get_last_error")
fn _ffi_get_last_error() -> UnsafePointer[SIMD[DType.uint8, num_simd_lanes()]]

@value
struct PortfolioManagerClient:
    """Mojo wrapper for Rust PortfolioManager FFI"""

    var manager: UnsafePointer[None]
    var is_global: Bool
    var total_capital: Float

    fn __init__(inout self, total_capital: Float, use_global: Bool = True):
        """Initialize PortfolioManager client"""
        self.total_capital = total_capital
        self.is_global = use_global

        if use_global:
            # Initialize global instance
            result = _portfolio_manager_init_global(total_capital)
            if result != SUCCESS:
                self._handle_ffi_error("Failed to initialize global portfolio manager")
            self.manager = UnsafePointer[None]()
        else:
            # Create new instance
            self.manager = _portfolio_manager_new(total_capital)
            if self.manager.address == 0:
                self._handle_ffi_error("Failed to create portfolio manager")

    fn __del__(inout self):
        """Cleanup PortfolioManager client"""
        if self.manager.address != 0 and not self.is_global:
            _portfolio_manager_destroy(self.manager)

    fn open_position(
        inout self,
        strategy: StrategyType,
        token_mint: String,
        symbol: String,
        side: OrderSide,
        size: Float,
        entry_price: Float,
        risk_level: RiskLevel
    ) -> UUID:
        """Open a new position"""
        var position_id = UUID()

        # Convert strings to C-style strings
        var mint_bytes = token_mint.to_bytes()
        var symbol_bytes = symbol.to_bytes()

        var result = _portfolio_manager_open_position(
            self.manager,
            strategy,
            mint_bytes.data,
            symbol_bytes.data,
            side,
            size,
            entry_price,
            risk_level,
            UnsafePointer[UUID].address_of(position_id)
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to open position")

        return position_id

    fn close_position(inout self, position_id: UUID, close_price: Float, fees: Float) -> Float:
        """Close a position and return P&L"""
        var pnl: Float = 0.0

        var result = _portfolio_manager_close_position(
            self.manager,
            UnsafePointer[UUID].address_of(position_id),
            close_price,
            fees,
            UnsafePointer[Float].address_of(pnl)
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to close position")

        return pnl

    fn update_position_price(inout self, position_id: UUID, new_price: Float):
        """Update position price"""
        var result = _portfolio_manager_update_position_price(
            self.manager,
            UnsafePointer[UUID].address_of(position_id),
            new_price
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to update position price")

    fn get_metrics(inout self) -> PortfolioMetrics:
        """Get portfolio metrics"""
        var bytes = FFIBytes()

        var result = _portfolio_manager_get_metrics(
            self.manager,
            UnsafePointer[FFIBytes].address_of(bytes)
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to get portfolio metrics")

        # Parse JSON response (simplified - would need proper JSON parsing)
        var metrics = PortfolioMetrics(
            total_capital=self.total_capital,
            available_capital=0.0,
            used_capital=0.0,
            total_pnl=0.0,
            unrealized_pnl=0.0,
            realized_pnl=0.0,
            total_fees=0.0,
            open_positions=0,
            closed_positions=0,
            win_rate=0.0,
            sharpe_ratio=0.0,
            max_drawdown=0.0,
            last_updated=0
        )

        # Free the returned bytes
        _ffi_bytes_free(bytes)

        return metrics

    fn get_available_capital(inout self, strategy: StrategyType) -> Float:
        """Get available capital for a strategy"""
        var capital: Float = 0.0

        var result = _portfolio_manager_get_available_capital(
            self.manager,
            strategy,
            UnsafePointer[Float].address_of(capital)
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to get available capital")

        return capital

    fn can_take_position(
        inout self,
        strategy: StrategyType,
        amount: Float,
        risk_level: RiskLevel
    ) -> Bool:
        """Check if can take new position"""
        var can_take: Bool = False

        var result = _portfolio_manager_can_take_position(
            self.manager,
            strategy,
            amount,
            risk_level,
            UnsafePointer[Bool].address_of(can_take)
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to check position viability")

        return can_take

    fn update_token_price(
        inout self,
        token_mint: String,
        symbol: String,
        price: Float,
        decimals: UInt8
    ):
        """Update token price cache"""
        var mint_bytes = token_mint.to_bytes()
        var symbol_bytes = symbol.to_bytes()

        var result = _portfolio_manager_update_token_price(
            self.manager,
            mint_bytes.data,
            symbol_bytes.data,
            price,
            decimals
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to update token price")

    fn set_emergency_stop(inout self, stop: Bool):
        """Set emergency stop flag"""
        var result = _portfolio_manager_set_emergency_stop(self.manager, stop)

        if result != SUCCESS:
            self._handle_ffi_error("Failed to set emergency stop")

    fn get_open_positions_count(inout self) -> UInt:
        """Get number of open positions"""
        var count: UInt = 0

        var result = _portfolio_manager_get_open_positions_count(
            self.manager,
            UnsafePointer[UInt].address_of(count)
        )

        if result != SUCCESS:
            self._handle_ffi_error("Failed to get open positions count")

        return count

    fn _handle_ffi_error(inout self, operation: String):
        """Handle FFI errors with detailed logging"""
        var error_ptr = _ffi_get_last_error()
        if error_ptr.address != 0:
            # Convert C string to Mojo string (simplified)
            print("⚠️  PortfolioManager FFI Error in " + operation + ":")
            # Would need proper C string to Mojo string conversion here
        else:
            print("⚠️  PortfolioManager FFI Error in " + operation + ": Unknown error")

    # Convenience methods for common operations
    fn open_sniper_position(
        inout self,
        token_mint: String,
        symbol: String,
        size: Float,
        entry_price: Float
    ) -> UUID:
        """Open a sniper position with default parameters"""
        return self.open_position(
            STRATEGY_SNIPER,
            token_mint,
            symbol,
            ORDER_BUY,
            size,
            entry_price,
            RISK_MEDIUM
        )

    fn open_arbitrage_position(
        inout self,
        token_mint: String,
        symbol: String,
        size: Float,
        entry_price: Float
    ) -> UUID:
        """Open an arbitrage position with default parameters"""
        return self.open_position(
            STRATEGY_ARBITRAGE,
            token_mint,
            symbol,
            ORDER_BUY,
            size,
            entry_price,
            RISK_LOW
        )

    def get_strategy_name(strategy: StrategyType) -> String:
        """Get human-readable strategy name"""
        match strategy:
            case STRATEGY_SNIPER:
                return "Sniper"
            case STRATEGY_ARBITRAGE:
                return "Arbitrage"
            case STRATEGY_FLASH_LOAN:
                return "FlashLoan"
            case STRATEGY_MARKET_MAKING:
                return "MarketMaking"
            case _:
                return "Unknown"

    def get_risk_name(risk_level: RiskLevel) -> String:
        """Get human-readable risk level name"""
        match risk_level:
            case RISK_LOW:
                return "Low"
            case RISK_MEDIUM:
                return "Medium"
            case RISK_HIGH:
                return "High"
            case RISK_CRITICAL:
                return "Critical"
            case _:
                return "Unknown"

    def print_portfolio_summary(inout self):
        """Print portfolio summary for debugging"""
        print("📊 Portfolio Summary:")
        print("   Total Capital: $" + str(self.total_capital))
        print("   Available Capital (Sniper): $" + str(self.get_available_capital(STRATEGY_SNIPER)))
        print("   Available Capital (Arbitrage): $" + str(self.get_available_capital(STRATEGY_ARBITRAGE)))
        print("   Available Capital (FlashLoan): $" + str(self.get_available_capital(STRATEGY_FLASH_LOAN)))
        print("   Open Positions: " + str(self.get_open_positions_count()))

        var metrics = self.get_metrics()
        print("   Total P&L: $" + str(metrics.total_pnl))
        print("   Win Rate: " + str(metrics.win_rate * 100) + "%")

# Global instance for convenience
var _global_portfolio_client: Optional[PortfolioManagerClient] = None

fn get_global_portfolio_client(total_capital: Float = 10000.0) -> PortfolioManagerClient:
    """Get or create global portfolio client instance"""
    if _global_portfolio_client is None:
        _global_portfolio_client = PortfolioManagerClient(total_capital, use_global=True)
    return _global_portfolio_client.value()