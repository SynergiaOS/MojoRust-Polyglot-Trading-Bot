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
from core.logger import get_execution_logger

@value
struct ExecutionEngine:
    """
    High-performance trade execution engine
    """
    var quicknode_client  # We'll add the type later
    var jupiter_client  # We'll add the type later
    var helius_client  # We'll add the type later
    var config  # We'll add the type later
    var execution_count: Int
    var successful_executions: Int
    var total_slippage: Float
    var total_execution_time: Float
    var logger

    fn __init__(quicknode_client, jupiter_client, helius_client, config):
        self.quicknode_client = quicknode_client
        self.jupiter_client = jupiter_client
        self.helius_client = helius_client
        self.config = config
        self.execution_count = 0
        self.successful_executions = 0
        self.total_slippage = 0.0
        self.total_execution_time = 0.0
        self.logger = get_execution_logger()

    fn execute_trade(self, signal: TradingSignal, approval: RiskApproval) -> ExecutionResult:
        """
        Execute a trading signal
        """
        execution_start = time()
        self.execution_count += 1

        try:
            # Check if this is a sniper trade and use specialized execution
            if signal.metadata.get('is_sniper_trade', False):
                self.logger.debug("detected_sniper_trade",
                                symbol=signal.symbol,
                                action=signal.action,
                                using_specialized_execution=True)
                return self.execute_sniper_trade_with_tp_sl(signal, approval)

            # Regular trade execution flow
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

            if result.success:
                # Update execution metrics (only once)
                self._update_execution_metrics(result, execution_time)

                self.logger.info(f"Trade executed successfully: {signal.symbol}",
                           symbol=signal.symbol,
                           execution_time_ms=execution_time,
                           slippage_percentage=result.slippage_percentage,
                           gas_cost_sol=result.gas_cost)

            return result

        except e as e:
            self.logger.error(f"Trade execution failed: {e}",
                             symbol=signal.symbol,
                             error=str(e))
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

            if potential_loss <= 0 or potential_profit / potential_loss < self.config.risk.min_risk_reward_ratio:
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

                # For SELL, position_size is in token units, need to adjust for token decimals
                try:
                    token_metadata = self.helius_client.get_token_metadata(signal.symbol)
                    decimals = token_metadata.decimals
                    if decimals <= 0:
                        decimals = self.config.execution.default_decimals  # Configurable default decimals
                except e:
                    print(f"⚠️  Error getting token metadata for {signal.symbol}, using default decimals")
                    decimals = self.config.execution.default_decimals  # Configurable default decimals

                # Convert token units to base units (smallest possible units)
                if approval.position_size <= 0:
                    print(f"⚠️  Invalid position size for SELL: {approval.position_size}")
                    return SwapQuote()  # Return empty quote

                base_units = int(approval.position_size * (10 ** decimals))
                if base_units <= 0:
                    print(f"⚠️  Invalid base units after conversion: {base_units}")
                    return SwapQuote()  # Return empty quote

                input_amount = base_units

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
            slippage_factor = self.config.execution.base_slippage + (quote.price_impact / 100.0)  # Configurable base slippage + price impact

            if signal.action == TradingAction.BUY:
                executed_price = base_price * (1 + slippage_factor)
            else:  # SELL
                executed_price = base_price * (1 - slippage_factor)

            slippage_percentage = abs(executed_price - base_price) / base_price * 100

            # Simulate gas cost
            gas_cost = self.config.execution.gas_cost  # Configurable gas cost

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

        performance_healthy = success_rate >= self.config.execution.min_success_rate  # Configurable success rate minimum

        return jupiter_healthy and quicknode_healthy and performance_healthy

    def reset_metrics(self):
        """
        Reset execution metrics
        """
        self.execution_count = 0
        self.successful_executions = 0
        self.total_slippage = 0.0
        self.total_execution_time = 0.0

    # =============================================================================
    # Sniper TP/SL Methods
    # =============================================================================

    fn calculate_sniper_tp_sl(self, signal: TradingSignal, entry_price: Float) -> Dict[String, Any]:
        """
        Calculate custom Take Profit and Stop Loss for sniper trades
        Uses sniper-specific TP/SL thresholds from config
        """
        try:
            # Get sniper TP/SL thresholds from config
            tp_threshold = self.config.sniper_filters.tp_threshold  # 1.5 (50% profit)
            sl_threshold = self.config.sniper_filters.sl_threshold  # 0.8 (20% loss)

            # Calculate TP and SL prices
            if signal.action == TradingAction.BUY:
                # For BUY orders: TP is higher, SL is lower
                take_profit_price = entry_price * tp_threshold
                stop_loss_price = entry_price * sl_threshold
            else:  # SELL order
                # For SELL orders: TP is lower, SL is higher
                take_profit_price = entry_price * sl_threshold
                stop_loss_price = entry_price * tp_threshold

            # Calculate potential profit/loss percentages
            potential_profit_pct = abs(take_profit_price - entry_price) / entry_price * 100
            potential_loss_pct = abs(entry_price - stop_loss_price) / entry_price * 100

            # Calculate risk-reward ratio
            risk_reward_ratio = potential_profit_pct / potential_loss_pct if potential_loss_pct > 0 else 0

            tp_sl_result = {
                "entry_price": entry_price,
                "take_profit_price": take_profit_price,
                "stop_loss_price": stop_loss_price,
                "potential_profit_pct": potential_profit_pct,
                "potential_loss_pct": potential_loss_pct,
                "risk_reward_ratio": risk_reward_ratio,
                "tp_threshold": tp_threshold,
                "sl_threshold": sl_threshold,
                "action": signal.action,
                "symbol": signal.symbol,
                "calculation_timestamp": time()
            }

            self.logger.info("sniper_tp_sl_calculated",
                           symbol=signal.symbol,
                           entry_price=entry_price,
                           tp_price=take_profit_price,
                           sl_price=stop_loss_price,
                           profit_pct=potential_profit_pct,
                           loss_pct=potential_loss_pct,
                           risk_reward=risk_reward_ratio)

            return tp_sl_result

        except e:
            self.logger.error("Error calculating sniper TP/SL",
                            symbol=signal.symbol,
                            entry_price=entry_price,
                            error=str(e))
            return {
                "entry_price": entry_price,
                "take_profit_price": 0.0,
                "stop_loss_price": 0.0,
                "error": str(e)
            }

    fn execute_sniper_trade_with_tp_sl(self, signal: TradingSignal, approval: RiskApproval) -> ExecutionResult:
        """
        Execute sniper trade with custom TP/SL logic
        This method handles the complete sniper trade execution with specific profit/loss targets
        """
        execution_start = time()
        self.execution_count += 1

        try:
            # Execute the entry trade using internal methods to avoid recursion
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
            entry_result = self._execute_swap(signal, approval, quote)

            if not entry_result.success:
                return entry_result

            # Get entry price from execution result
            entry_price = entry_result.executed_price

            if entry_price <= 0:
                self.logger.error("Invalid entry price for sniper trade",
                                symbol=signal.symbol,
                                entry_price=entry_price)
                return ExecutionResult(
                    success=False,
                    error_message="Invalid entry price"
                )

            # Calculate sniper-specific TP/SL
            tp_sl_calculations = self.calculate_sniper_tp_sl(signal, entry_price)

            if "error" in tp_sl_calculations:
                return ExecutionResult(
                    success=False,
                    error_message=f"TP/SL calculation failed: {tp_sl_calculations['error']}"
                )

            # Store TP/SL information for monitoring
            self._store_sniper_position_info(signal, entry_result, tp_sl_calculations)

            # In a real implementation, we would set up automatic TP/SL orders here
            # For now, we'll log the information and return the entry result

            self.logger.info("sniper_trade_executed",
                           symbol=signal.symbol,
                           entry_price=entry_price,
                           tp_price=tp_sl_calculations["take_profit_price"],
                           sl_price=tp_sl_calculations["stop_loss_price"],
                           tx_hash=entry_result.tx_hash)

            # Return enhanced execution result with TP/SL info
            enhanced_result = ExecutionResult(
                success=entry_result.success,
                tx_hash=entry_result.tx_hash,
                executed_price=entry_result.executed_price,
                requested_price=entry_result.requested_price,
                slippage_percentage=entry_result.slippage_percentage,
                gas_cost=entry_result.gas_cost,
                execution_time_ms=entry_result.execution_time_ms
            )

            # Add TP/SL metadata to the result
            enhanced_result.metadata = {
                "sniper_trade": True,
                "tp_price": tp_sl_calculations["take_profit_price"],
                "sl_price": tp_sl_calculations["stop_loss_price"],
                "potential_profit_pct": tp_sl_calculations["potential_profit_pct"],
                "potential_loss_pct": tp_sl_calculations["potential_loss_pct"],
                "risk_reward_ratio": tp_sl_calculations["risk_reward_ratio"],
                "tp_threshold": self.config.sniper_filters.tp_threshold,
                "sl_threshold": self.config.sniper_filters.sl_threshold
            }

            return enhanced_result

        except e:
            self.logger.error("Error executing sniper trade with TP/SL",
                            symbol=signal.symbol,
                            error=str(e))
            return ExecutionResult(
                success=False,
                error_message=str(e),
                execution_time_ms=(time() - execution_start) * 1000
            )

    fn _store_sniper_position_info(self, signal: TradingSignal, execution_result: ExecutionResult, tp_sl_calculations: Dict[String, Any]):
        """
        Store sniper position information for monitoring and TP/SL execution
        """
        try:
            # This would typically store in a database or memory cache
            # For now, we'll just log the information

            position_info = {
                "symbol": signal.symbol,
                "action": signal.action,
                "entry_price": execution_result.executed_price,
                "entry_time": execution_result.execution_time_ms or time(),
                "tp_price": tp_sl_calculations["take_profit_price"],
                "sl_price": tp_sl_calculations["stop_loss_price"],
                "position_size": signal.position_size or 0.0,
                "tx_hash": execution_result.tx_hash,
                "status": "active",
                "created_at": time()
            }

            self.logger.info("sniper_position_stored",
                           symbol=signal.symbol,
                           entry_price=position_info["entry_price"],
                           tp_price=position_info["tp_price"],
                           sl_price=position_info["sl_price"],
                           position_size=position_info["position_size"])

        except e:
            self.logger.error("Error storing sniper position info",
                            symbol=signal.symbol,
                            error=str(e))

    def check_sniper_tp_sl_conditions(self, current_price: Float, position_info: Dict[String, Any]) -> Dict[String, Any]:
        """
        Check if current price triggers TP or SL conditions for a sniper position
        """
        try:
            tp_price = position_info.get("tp_price", 0.0)
            sl_price = position_info.get("sl_price", 0.0)
            action = position_info.get("action", TradingAction.BUY)
            entry_price = position_info.get("entry_price", 0.0)

            if tp_price <= 0 or sl_price <= 0 or entry_price <= 0:
                return {"triggered": False, "reason": "Invalid prices"}

            triggered = False
            trigger_type = None
            exit_price = current_price

            if action == TradingAction.BUY:
                # For BUY positions: TP when price goes up, SL when price goes down
                if current_price >= tp_price:
                    triggered = True
                    trigger_type = "take_profit"
                    exit_price = tp_price
                elif current_price <= sl_price:
                    triggered = True
                    trigger_type = "stop_loss"
                    exit_price = sl_price
            else:  # SELL position
                # For SELL positions: TP when price goes down, SL when price goes up
                if current_price <= tp_price:
                    triggered = True
                    trigger_type = "take_profit"
                    exit_price = tp_price
                elif current_price >= sl_price:
                    triggered = True
                    trigger_type = "stop_loss"
                    exit_price = sl_price

            # Calculate profit/loss
            if triggered:
                if action == TradingAction.BUY:
                    profit_loss_pct = (exit_price - entry_price) / entry_price * 100
                else:  # SELL
                    profit_loss_pct = (entry_price - exit_price) / entry_price * 100

                return {
                    "triggered": True,
                    "trigger_type": trigger_type,
                    "exit_price": exit_price,
                    "profit_loss_pct": profit_loss_pct,
                    "is_profit": profit_loss_pct > 0,
                    "symbol": position_info.get("symbol", ""),
                    "check_timestamp": time()
                }
            else:
                return {
                    "triggered": False,
                    "current_price": current_price,
                    "tp_distance_pct": abs(current_price - tp_price) / entry_price * 100,
                    "sl_distance_pct": abs(current_price - sl_price) / entry_price * 100,
                    "symbol": position_info.get("symbol", ""),
                    "check_timestamp": time()
                }

        except e:
            self.logger.error("Error checking sniper TP/SL conditions",
                            position_info=position_info,
                            current_price=current_price,
                            error=str(e))
            return {"triggered": False, "error": str(e)}

    def get_sniper_performance_stats(self) -> Dict[String, Any]:
        """
        Get sniper-specific performance statistics
        """
        try:
            # In a real implementation, this would query a database for sniper trades
            # For now, we'll return mock statistics

            mock_stats = {
                "total_sniper_trades": 0,
                "winning_sniper_trades": 0,
                "losing_sniper_trades": 0,
                "sniper_win_rate": 0.0,
                "average_sniper_profit_pct": 0.0,
                "average_sniper_loss_pct": 0.0,
                "total_sniper_profit_pct": 0.0,
                "best_sniper_trade_pct": 0.0,
                "worst_sniper_trade_pct": 0.0,
                "tp_hits": 0,
                "sl_hits": 0,
                "tp_hit_rate": 0.0,
                "average_hold_time_minutes": 0.0,
                "current_active_positions": 0,
                "last_updated": time()
            }

            return mock_stats

        except e:
            self.logger.error("Error getting sniper performance stats",
                            error=str(e))
            return {
                "error": str(e),
                "last_updated": time()
            }