# =============================================================================
# Trade Execution Engine Module
# =============================================================================

from time import time
from collections import Dict, List
from core.types import (
    TradingSignal, ExecutionResult, RiskApproval, TradingAction,
    SwapQuote
)
from core.constants import (
    MAX_SLIPPAGE,
    MAX_EXECUTION_TIME_MS,
    DEFAULT_TIMEOUT_SECONDS,
    LAMPORTS_PER_SOL,
    SOL_DECIMALS
)

@value
struct ExecutionEngine:
    """
    High-performance trade execution engine
    """
    var quicknode_client  # We'll add the type later
    var jupiter_client  # We'll add the type later
    var config  # We'll add the type later
    var execution_count: Int
    var successful_executions: Int
    var total_slippage: Float
    var total_execution_time: Float

    fn __init__(quicknode_client, jupiter_client, config):
        self.quicknode_client = quicknode_client
        self.jupiter_client = jupiter_client
        self.config = config
        self.execution_count = 0
        self.successful_executions = 0
        self.total_slippage = 0.0
        self.total_execution_time = 0.0

    fn execute_trade(self, signal: TradingSignal, approval: RiskApproval) -> ExecutionResult:
        """
        Execute a trading signal
        """
        execution_start = time()
        self.execution_count += 1

        try:
            # Validate execution parameters
            if not self._validate_execution_params(signal, approval):
                return ExecutionResult(
                    success=False,
                    error_message="Invalid execution parameters"
                )

            # Get swap quote
            quote = self._get_swap_quote(signal, approval)
            if not quote or quote.output_amount <= 0:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to get valid swap quote"
                )

            # Execute swap
            result = self._execute_swap(signal, approval, quote)

            # Calculate execution time
            execution_time = (time() - execution_start) * 1000  # Convert to milliseconds
            self.total_execution_time += execution_time

            if result.success:
                self.successful_executions += 1
                self.total_slippage += result.slippage_percentage

                # Update execution metrics
                self._update_execution_metrics(result, execution_time)

                print(f"✅ Trade executed successfully: {signal.symbol}")
                print(f"   Execution time: {execution_time:.2f}ms")
                print(f"   Slippage: {result.slippage_percentage:.3f}%")
                print(f"   Gas cost: {result.gas_cost:.6f} SOL")

            return result

        except e as e:
            print(f"❌ Trade execution failed: {e}")
            return ExecutionResult(
                success=False,
                error_message=str(e),
                execution_time_ms=(time() - execution_start) * 1000
            )

    fn _validate_execution_params(self, signal: TradingSignal, approval: RiskApproval) -> Bool:
        """
        Validate execution parameters
        """
        # Check signal validity
        if not signal.symbol or signal.symbol == "":
            return False

        if not approval.approved or approval.position_size <= 0:
            return False

        # Check if we're in paper trading mode
        if self.config.trading.execution_mode == "paper":
            return True  # Skip validation for paper trading

        # Check minimum position size
        if approval.position_size < 0.001:  # 0.001 SOL minimum
            return False

        # Check stop loss
        if signal.stop_loss <= 0:
            return False

        # Check price target
        if signal.price_target > 0:
            # Validate risk-reward ratio
            if signal.action == TradingAction.BUY:
                potential_profit = signal.price_target - signal.stop_loss
                potential_loss = signal.stop_loss
            else:  # Sell signal
                potential_profit = signal.stop_loss - signal.price_target
                potential_loss = signal.price_target

            if potential_loss <= 0 or potential_profit / potential_loss < 2.0:
                return False

        return True

    fn _get_swap_quote(self, signal: TradingSignal, approval: RiskApproval) -> SwapQuote:
        """
        Get swap quote from Jupiter
        """
        try:
            # Determine input/output mints based on action
            if signal.action == TradingAction.BUY:
                input_mint = "So11111111111111111111111111111111111111112"  # SOL
                output_mint = signal.symbol  # Token address
                input_amount = approval.position_size * LAMPORTS_PER_SOL  # SOL amount
            else:  # SELL
                input_mint = signal.symbol  # Token address
                output_mint = "So11111111111111111111111111111111111111112"  # SOL
                # For SELL, position_size is in token units
                input_amount = approval.position_size * LAMPORTS_PER_SOL  # Token amount (adjusted for decimals)

            # Get quote from Jupiter
            quote = self.jupiter_client.get_quote(
                input_mint=input_mint,
                output_mint=output_mint,
                input_amount=input_amount,
                slippage_bps=int(self.config.execution.max_slippage * 10_000)  # 0.02 -> 200 bps
            )

            return quote

        except e as e:
            print(f"⚠️  Error getting swap quote: {e}")
            return SwapQuote()

    fn _execute_swap(self, signal: TradingSignal, approval: RiskApproval, quote: SwapQuote) -> ExecutionResult:
        """
        Execute the swap transaction
        """
        try:
            # Check if we're in paper trading mode
            if self.config.trading.execution_mode == "paper":
                return self._simulate_execution(signal, approval, quote)

            # Get user public key (would come from wallet)
            user_public_key = self.config.wallet_address

            # Get swap transaction
            transaction = self.jupiter_client.get_swap_transaction(
                quote=quote,
                user_public_key=user_public_key,
                wrap_and_unwrap_sol=True
            )

            if not transaction:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to generate swap transaction"
                )

            # Sign and send transaction
            tx_hash = self.quicknode_client.send_transaction(transaction)

            if not tx_hash:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to send transaction"
                )

            # Wait for confirmation
            confirmed = self.quicknode_client.confirm_transaction(tx_hash)

            if not confirmed:
                return ExecutionResult(
                    success=False,
                    error_message="Transaction not confirmed"
                )

            # Get transaction details for execution price
            tx_details = self.quicknode_client.get_transaction(tx_hash)

            # Calculate execution metrics
            executed_price = self._calculate_execution_price(tx_details, signal.action)
            requested_price = quote.output_amount / quote.input_amount
            slippage = self._calculate_slippage(executed_price, requested_price)
            gas_cost = self._calculate_gas_cost(tx_details)

            return ExecutionResult(
                success=True,
                tx_hash=tx_hash,
                executed_price=executed_price,
                requested_price=requested_price,
                slippage_percentage=slippage,
                gas_cost=gas_cost,
                execution_time_ms=0.0  # Will be set by caller
            )

        except e as e:
            return ExecutionResult(
                success=False,
                error_message=str(e)
            )

    fn _simulate_execution(self, signal: TradingSignal, approval: RiskApproval, quote: SwapQuote) -> ExecutionResult:
        """
        Simulate execution for paper trading
        """
        try:
            # Simulate execution with realistic slippage
            if quote.input_amount <= 0:
                # Guard against division by zero
                return ExecutionResult(
                    success=False,
                    error_message="Invalid input amount (zero or negative)"
                )

            base_price = quote.output_amount / quote.input_amount
            slippage_factor = 0.001 + (quote.price_impact / 100)  # Base slippage + price impact

            if signal.action == TradingAction.BUY:
                executed_price = base_price * (1 + slippage_factor)
            else:  # SELL
                executed_price = base_price * (1 - slippage_factor)

            slippage_percentage = abs(executed_price - base_price) / base_price * 100

            # Simulate gas cost
            gas_cost = 0.000005  # 0.000005 SOL typical gas cost

            # Generate mock transaction hash
            mock_tx_hash = f"paper_tx_{int(time() * 1000)}"

            return ExecutionResult(
                success=True,
                tx_hash=mock_tx_hash,
                executed_price=executed_price,
                requested_price=base_price,
                slippage_percentage=slippage_percentage,
                gas_cost=gas_cost,
                execution_time_ms=50.0  # Simulated execution time
            )

        except e as e:
            return ExecutionResult(
                success=False,
                error_message=f"Simulation error: {e}"
            )

    fn _calculate_execution_price(self, tx_details: Dict, action: TradingAction) -> Float:
        """
        Calculate actual execution price from transaction details
        """
        try:
            # Extract input/output amounts from transaction
            if "meta" in tx_details and "postBalances" in tx_details["meta"]:
                post_balances = tx_details["meta"]["postBalances"]
                pre_balances = tx_details["meta"]["preBalances"]

                if len(post_balances) >= 2 and len(pre_balances) >= 2:
                    # Calculate executed amounts
                    if action == TradingAction.BUY:
                        input_change = pre_balances[0] - post_balances[0]  # SOL spent
                        output_change = post_balances[1] - pre_balances[1]  # Tokens received
                    else:  # SELL
                        input_change = pre_balances[1] - post_balances[1]  # Tokens spent
                        output_change = post_balances[0] - pre_balances[0]  # SOL received

                    if input_change > 0 and output_change > 0:
                        return output_change / input_change

            return 0.0

        except e:
            print(f"⚠️  Error calculating execution price: {e}")
            return 0.0

    fn _calculate_slippage(self, executed_price: Float, requested_price: Float) -> Float:
        """
        Calculate slippage percentage
        """
        if requested_price <= 0:
            return 0.0

        return abs(executed_price - requested_price) / requested_price * 100

    fn _calculate_gas_cost(self, tx_details: Dict) -> Float:
        """
        Calculate gas cost from transaction details
        """
        try:
            if "meta" in tx_details and "fee" in tx_details["meta"]:
                fee_lamports = tx_details["meta"]["fee"]
                return fee_lamports / LAMPORTS_PER_SOL
            return 0.0
        except e:
            print(f"⚠️  Error calculating gas cost: {e}")
            return 0.0

    fn _update_execution_metrics(self, result: ExecutionResult, execution_time: Float):
        """
        Update execution performance metrics
        """
        # Update counters (execution_count is already updated in execute_trade)
        if result.success:
            self.successful_executions += 1
            self.total_slippage += result.slippage_percentage

        self.total_execution_time += execution_time

        # Log performance warnings
        if execution_time > MAX_EXECUTION_TIME_MS:
            print(f"⚠️  Slow execution detected: {execution_time:.2f}ms")

        if result.slippage_percentage > self.config.execution.max_slippage * 100:
            print(f"⚠️  High slippage detected: {result.slippage_percentage:.3f}%")

    def get_execution_stats(self) -> Dict[str, Any]:
        """
        Get execution performance statistics
        """
        success_rate = 0.0
        if self.execution_count > 0:
            success_rate = self.successful_executions / self.execution_count

        avg_slippage = 0.0
        if self.successful_executions > 0:
            avg_slippage = self.total_slippage / self.successful_executions

        avg_execution_time = 0.0
        if self.execution_count > 0:
            avg_execution_time = self.total_execution_time / self.execution_count

        return {
            "total_executions": self.execution_count,
            "successful_executions": self.successful_executions,
            "success_rate": success_rate,
            "average_slippage_percent": avg_slippage,
            "average_execution_time_ms": avg_execution_time,
            "total_gas_cost": self._estimate_total_gas_cost()
        }

    def _estimate_total_gas_cost(self) -> Float:
        """
        Estimate total gas cost spent
        """
        # Rough estimate: 0.000005 SOL per successful transaction
        return self.successful_executions * 0.000005

    def cancel_transaction(self, tx_hash: String) -> Bool:
        """
        Cancel a pending transaction (if possible)
        """
        try:
            # In Solana, transactions can't be directly cancelled
            # But we can monitor and handle timeouts
            print(f"⚠️  Transaction cancellation requested for {tx_hash}")
            print("   Note: Solana transactions cannot be directly cancelled")
            return True
        except e:
            print(f"❌ Error handling transaction cancellation: {e}")
            return False

    def get_transaction_status(self, tx_hash: String) -> Dict[str, Any]:
        """
        Get status of a transaction
        """
        try:
            tx_details = self.quicknode_client.get_transaction(tx_hash)

            if tx_details:
                return {
                    "hash": tx_hash,
                    "status": "confirmed" if tx_details else "pending",
                    "slot": tx_details.get("slot", 0),
                    "block_time": tx_details.get("blockTime", 0),
                    "fee": tx_details.get("meta", {}).get("fee", 0)
                }
            else:
                return {
                    "hash": tx_hash,
                    "status": "not_found"
                }
        except e:
            print(f"⚠️  Error getting transaction status: {e}")
            return {"hash": tx_hash, "status": "error"}

    def health_check(self) -> Bool:
        """
        Check if execution engine is healthy
        """
        # Check Jupiter API
        jupiter_healthy = self.jupiter_client.health_check()

        # Check QuickNode RPC
        quicknode_healthy = self.quicknode_client.health_check()

        # Check performance metrics
        success_rate = 1.0
        if self.execution_count > 0:
            success_rate = self.successful_executions / self.execution_count

        performance_healthy = success_rate >= 0.9  # 90% success rate minimum

        return jupiter_healthy and quicknode_healthy and performance_healthy

    def reset_metrics(self):
        """
        Reset execution metrics
        """
        self.execution_count = 0
        self.successful_executions = 0
        self.total_slippage = 0.0
        self.total_execution_time = 0.0