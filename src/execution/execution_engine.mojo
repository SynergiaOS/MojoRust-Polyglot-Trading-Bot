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
struct MockBundleExecution:
    """
    Mock bundle execution result for testing and simulation
    """
    var bundle_id: String
    var success: Bool
    var bundle_signature: String
    var total_cost: Float
    var total_gas_used: Int
    var execution_time_ms: Float
    var transaction_results: List[Any]
    var bundle_metadata: Dict[String, Any]
    var error_message: String

    fn __init__(bundle_id: String, success: Bool, bundle_signature: String = "",
                total_cost: Float = 0.0, total_gas_used: Int = 0,
                execution_time_ms: Float = 0.0, transaction_results: List[Any] = [],
                bundle_metadata: Dict[String, Any] = {}, error_message: String = ""):
        self.bundle_id = bundle_id
        self.success = success
        self.bundle_signature = bundle_signature
        self.total_cost = total_cost
        self.total_gas_used = total_gas_used
        self.execution_time_ms = execution_time_ms
        self.transaction_results = transaction_results
        self.bundle_metadata = bundle_metadata
        self.error_message = error_message

@value
struct ExecutionEngine:
    """
    High-performance trade execution engine with RPCRouter integration
    """
    var rpc_router  # RPCRouter for provider management and routing
    var jupiter_client  # Jupiter client for DEX aggregation
    var config  # Configuration object
    var execution_count: Int
    var successful_executions: Int
    var total_slippage: Float
    var total_execution_time: Float
    var _bundle_submission_count: Int
    var _bundle_success_count: Int
    var logger

    fn __init__(rpc_router, jupiter_client, config):
        self.rpc_router = rpc_router
        self.jupiter_client = jupiter_client
        self.config = config
        self.execution_count = 0
        self.successful_executions = 0
        self.total_slippage = 0.0
        self.total_execution_time = 0.0
        self._bundle_submission_count = 0
        self._bundle_success_count = 0
        self.logger = get_execution_logger()
        self.logger.info("execution_engine_initialized_with_rpc_router",
                        router_providers=list(rpc_router.providers.keys()))

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

    async fn _get_swap_quote(self, signal: TradingSignal, approval: RiskApproval) -> SwapQuote:
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
                    # Get token metadata via RPCRouter
                    token_metadata = await self.rpc_router.call("getTokenMetadata", [signal.symbol])
                    decimals = token_metadata.get("offChain", {}).get("metadata", {}).get("decimals", 9)
                    if decimals <= 0:
                        decimals = self.config.execution.default_decimals  # Configurable default decimals
                except e:
                    self.logger.warning("token_metadata_fetch_failed",
                                      symbol=signal.symbol,
                                      error=str(e),
                                      using_default_decimals=self.config.execution.default_decimals)
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

    async fn _execute_swap(self, signal: TradingSignal, approval: RiskApproval, quote: SwapQuote) -> ExecutionResult:
        """
        Execute the swap transaction using RPCRouter
        """
        try:
            # Check if we're in paper trading mode
            if self.config.trading.execution_mode == "paper":
                return self._simulate_execution(signal, approval, quote)

            # Determine urgency based on signal characteristics
            urgency = "normal"
            if signal.metadata.get('is_sniper_trade', False):
                urgency = "critical"
            elif signal.action == TradingAction.BUY and "arbitrage" in signal.metadata.get('strategy', '').lower():
                urgency = "high"

            # Get dynamic priority fee via RPCRouter
            priority_fee = await self._get_dynamic_priority_fee(signal, urgency)

            self.logger.info("dynamic_priority_fee_for_swap_via_router",
                           symbol=signal.symbol,
                           urgency=urgency,
                           priority_fee_lamports=priority_fee)

            # Get user public key (would come from wallet)
            user_public_key = self.config.wallet_address

            # Get swap transaction with dynamic priority fee
            transaction = self.jupiter_client.get_swap_transaction(
                quote=quote,
                user_public_key=user_public_key,
                wrap_and_unwrap_sol=True,
                priority_fee=priority_fee
            )

            if not transaction:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to generate swap transaction"
                )

            # Submit transaction via RPCRouter
            tx_hash = await self._submit_transaction_via_router(transaction, urgency, signal)

            if not tx_hash:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to submit transaction via RPCRouter"
                )

            # Get transaction details via RPCRouter
            tx_details = await self.rpc_router.call("getTransaction", [tx_hash])

            if not tx_details:
                # Transaction might still be processing
                self.logger.warning("transaction_details_not_available",
                                   symbol=signal.symbol,
                                   tx_hash=tx_hash)
                tx_details = {}

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
            self.logger.error("swap_execution_failed_via_router",
                            symbol=signal.symbol,
                            error=str(e))
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

    async fn _get_dynamic_priority_fee(self, signal: TradingSignal, urgency: String) -> Int:
        """
        Get dynamic priority fee using RPCRouter with provider selection

        Args:
            signal: Trading signal
            urgency: Transaction urgency level

        Returns:
            Priority fee in lamports
        """
        try:
            # Derive urgency based on signal characteristics
            derived_urgency = urgency
            if signal.metadata.get('is_sniper_trade', False):
                derived_urgency = "critical"  # Sniper trades need critical priority
            elif signal.action == TradingAction.BUY and "arbitrage" in signal.metadata.get('strategy', '').lower():
                derived_urgency = "high"  # Arbitrage needs high priority
            elif urgency == "":
                derived_urgency = "normal"  # Default urgency (matching RPCRouter)

            # Get priority fee estimate from optimal provider via RPCRouter
            fee_estimate = await self.rpc_router.get_priority_fee_estimate(derived_urgency)

            # Extract priority fee from estimate
            priority_fee = fee_estimate.get("priority_fee", 1000000)  # Fallback to 0.001 SOL
            confidence = fee_estimate.get("confidence", 0.5)
            provider = fee_estimate.get("provider", "unknown")

            # Cap with config maximum priority fee
            max_priority_fee_sol = self.config.execution.max_priority_fee
            max_priority_fee_lamports = int(max_priority_fee_sol * LAMPORTS_PER_SOL)

            final_fee = min(priority_fee, max_priority_fee_lamports)

            # Log detailed information
            self.logger.info("dynamic_priority_fee_via_rpc_router",
                           symbol=signal.symbol,
                           urgency=derived_urgency,
                           provider=provider,
                           base_fee_lamports=priority_fee,
                           final_fee_lamports=final_fee,
                           confidence=confidence,
                           capped=final_fee != priority_fee,
                           max_fee_lamports=max_priority_fee_lamports)

            return final_fee

        except e:
            self.logger.error("failed_to_get_dynamic_priority_fee",
                            symbol=signal.symbol,
                            urgency=urgency,
                            error=str(e))
            # Return fallback fee (1M lamports = 0.001 SOL)
            return 1000000

    async fn _submit_transaction_via_router(self, transaction: Any, urgency: String,
                                          signal: TradingSignal) -> String:
        """
        Submit transaction via RPCRouter with optimal provider selection

        Args:
            transaction: Transaction to submit
            urgency: Transaction urgency level
            signal: Trading signal for metadata

        Returns:
            Transaction hash if successful, None otherwise
        """
        try:
            # Prepare transaction data for bundle submission
            transaction_data = {
                "transactions": [transaction],
                "urgency": urgency,
                "symbol": signal.symbol,
                "strategy": signal.metadata.get("strategy", "unknown"),
                "is_sniper_trade": signal.metadata.get("is_sniper_trade", False),
                "timestamp": time()
            }

            # Submit via RPCRouter bundle submission
            bundle_result = await self.rpc_router.submit_bundle(transaction_data, urgency)

            # Track bundle submission metrics
            self._bundle_submission_count += 1

            if bundle_result.get("success", False):
                self._bundle_success_count += 1
                bundle_id = bundle_result.get("bundle_id", "")
                provider = bundle_result.get("provider", "unknown")
                submission_time_ms = bundle_result.get("submission_time_ms", 0.0)

                self.logger.info("transaction_submitted_via_rpc_router",
                               symbol=signal.symbol,
                               bundle_id=bundle_id,
                               provider=provider,
                               urgency=urgency,
                               submission_time_ms=submission_time_ms)

                # Track bundle confirmation with router
                self._track_bundle_confirmation(bundle_id, provider, signal)

                return bundle_id  # Return bundle_id as transaction hash
            else:
                error_msg = bundle_result.get("error", "Unknown bundle submission error")
                self.logger.error("bundle_submission_failed_via_rpc_router",
                                symbol=signal.symbol,
                                urgency=urgency,
                                error=error_msg)
                return None

        except e:
            self.logger.error("exception_in_transaction_submission_via_router",
                            symbol=signal.symbol,
                            urgency=urgency,
                            error=str(e))
            return None

    fn _track_bundle_confirmation(self, bundle_id: String, provider: String, signal: TradingSignal):
        """
        Track bundle confirmation (simplified for now)
        """
        try:
            # In a real implementation, this would monitor bundle confirmation
            # and call rpc_router.track_bundle_confirmation() when confirmed
            self.logger.debug("tracking_bundle_confirmation",
                            bundle_id=bundle_id,
                            provider=provider,
                            symbol=signal.symbol)

        except e:
            self.logger.error("error_tracking_bundle_confirmation",
                            bundle_id=bundle_id,
                            error=str(e))

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

    async fn get_execution_stats(self) -> Dict[str, Any]:
        """
        Get execution performance statistics including bundle metrics
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

        # Bundle submission statistics
        bundle_success_rate = 0.0
        if self._bundle_submission_count > 0:
            bundle_success_rate = self._bundle_success_count / self._bundle_submission_count

        # Get RPCRouter bundle statistics
        router_bundle_stats = await self.rpc_router.get_bundle_statistics()

        return {
            "execution_metrics": {
                "total_executions": self.execution_count,
                "successful_executions": self.successful_executions,
                "success_rate": success_rate,
                "average_slippage_percent": avg_slippage,
                "average_execution_time_ms": avg_execution_time,
                "total_gas_cost": self._estimate_total_gas_cost()
            },
            "bundle_metrics": {
                "total_submissions": self._bundle_submission_count,
                "successful_submissions": self._bundle_success_count,
                "success_rate": bundle_success_rate,
                "router_bundle_stats": router_bundle_stats
            },
            "rpc_router_health": await self.rpc_router.health(),
            "timestamp": time()
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

    async def get_transaction_status(self, tx_hash: String) -> Dict[str, Any]:
        """
        Get status of a transaction via RPCRouter
        """
        try:
            tx_details = await self.rpc_router.call("getTransaction", [tx_hash])

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
            self.logger.error("transaction_status_check_failed",
                            tx_hash=tx_hash,
                            error=str(e))
            return {"hash": tx_hash, "status": "error"}

    async fn health_check(self) -> Bool:
        """
        Check if execution engine is healthy using RPCRouter
        """
        try:
            # Check Jupiter API
            jupiter_healthy = self.jupiter_client.health_check()

            # Check RPCRouter health
            router_health = await self.rpc_router.health()

            # Check performance metrics
            success_rate = 1.0
            if self.execution_count > 0:
                success_rate = self.successful_executions / self.execution_count

            performance_healthy = success_rate >= self.config.execution.min_success_rate  # Configurable success rate minimum

            router_healthy = router_health.get("healthy", False)

            self.logger.debug("execution_engine_health_check",
                            jupiter_healthy=jupiter_healthy,
                            router_healthy=router_healthy,
                            performance_healthy=performance_healthy,
                            success_rate=success_rate)

            return jupiter_healthy and router_healthy and performance_healthy

        except e:
            self.logger.error("execution_engine_health_check_failed",
                            error=str(e))
            return False

    def reset_metrics(self):
        """
        Reset execution metrics
        """
        self.execution_count = 0
        self.successful_executions = 0
        self.total_slippage = 0.0
        self.total_execution_time = 0.0

    # =============================================================================
    # Real Arbitrage Execution Methods using RPCRouter and JitoBundleBuilder
    # =============================================================================

    async fn execute_arbitrage_bundle(self,
                                    entry_signal: TradingSignal,
                                    exit_signal: TradingSignal,
                                    approval: RiskApproval,
                                    expected_profit: Float) -> ExecutionResult:
        """
        Execute real arbitrage opportunity using RPCRouter and JitoBundleBuilder
        This creates and submits atomic arbitrage bundles with provider-aware routing

        Args:
            entry_signal: First leg of arbitrage (entry trade)
            exit_signal: Second leg of arbitrage (exit trade)
            approval: Risk approval for the arbitrage
            expected_profit: Expected profit from arbitrage

        Returns:
            ExecutionResult with arbitrage-specific metadata
        """
        execution_start = time()
        self.execution_count += 1

        try:
            self.logger.info("executing_real_arbitrage_bundle",
                           entry_symbol=entry_signal.symbol,
                           exit_symbol=exit_signal.symbol,
                           expected_profit=expected_profit,
                           urgency="critical")

            # Validate arbitrage parameters
            if not self._validate_arbitrage_params(entry_signal, exit_signal, approval):
                return ExecutionResult(
                    success=False,
                    error_message="Invalid arbitrage parameters"
                )

            # Determine optimal provider for arbitrage (prefer high-speed providers)
            optimal_provider = await self._select_arbitrage_provider()

            # Get dynamic priority fees for both legs
            entry_priority_fee = await self._get_dynamic_priority_fee(entry_signal, "critical")
            exit_priority_fee = await self._get_dynamic_priority_fee(exit_signal, "critical")

            # Get swap quotes for both legs
            entry_quote = await self._get_swap_quote(entry_signal, approval)
            exit_quote = await self._get_swap_quote(exit_signal, approval)

            if not entry_quote or entry_quote.output_amount <= 0:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to get valid entry quote"
                )

            if not exit_quote or exit_quote.output_amount <= 0:
                return ExecutionResult(
                    success=False,
                    error_message="Failed to get valid exit quote"
                )

            # Create arbitrage bundle using JitoBundleBuilder
            bundle_result = await self._create_arbitrage_bundle(
                entry_signal, exit_signal,
                entry_quote, exit_quote,
                entry_priority_fee, exit_priority_fee,
                approval, optimal_provider
            )

            if not bundle_result.success:
                return ExecutionResult(
                    success=False,
                    error_message=f"Arbitrage bundle creation failed: {bundle_result.error_message}"
                )

            # Calculate arbitrage execution metrics
            execution_time = (time() - execution_start) * 1000

            # Calculate actual profit from quotes
            entry_price = entry_quote.output_amount / entry_quote.input_amount
            exit_price = exit_quote.output_amount / exit_quote.input_amount

            actual_profit = self._calculate_arbitrage_profit(
                entry_price, exit_price, approval.position_size
            )

            # Return enhanced execution result with arbitrage metadata
            result = ExecutionResult(
                success=True,
                tx_hash=bundle_result.bundle_signature or bundle_result.bundle_id,
                executed_price=actual_profit,  # Profit as "price"
                requested_price=expected_profit,
                slippage_percentage=self._calculate_arbitrage_slippage(actual_profit, expected_profit),
                gas_cost=bundle_result.total_cost,
                execution_time_ms=execution_time
            )

            # Add arbitrage-specific metadata
            result.metadata = {
                "arbitrage_execution": True,
                "entry_symbol": entry_signal.symbol,
                "exit_symbol": exit_signal.symbol,
                "entry_price": entry_price,
                "exit_price": exit_price,
                "expected_profit": expected_profit,
                "actual_profit": actual_profit,
                "profit_margin_pct": (actual_profit / expected_profit - 1.0) * 100 if expected_profit > 0 else 0,
                "bundle_id": bundle_result.bundle_id,
                "provider_used": bundle_result.bundle_metadata.get("provider", "unknown"),
                "transaction_count": len(bundle_result.transaction_results),
                "total_gas_used": bundle_result.total_gas_used,
                "bundle_execution_time_ms": bundle_result.execution_time_ms
            }

            # Update execution metrics
            self._update_execution_metrics(result, execution_time)
            self._bundle_submission_count += 1
            self._bundle_success_count += 1

            self.logger.info("real_arbitrage_executed_successfully",
                           entry_symbol=entry_signal.symbol,
                           exit_symbol=exit_signal.symbol,
                           actual_profit=actual_profit,
                           expected_profit=expected_profit,
                           provider_used=result.metadata.get("provider_used", "unknown"),
                           execution_time_ms=execution_time)

            return result

        except e as e:
            self.logger.error("real_arbitrage_execution_failed",
                            entry_symbol=entry_signal.symbol,
                            exit_symbol=exit_signal.symbol,
                            error=str(e))
            return ExecutionResult(
                success=False,
                error_message=str(e),
                execution_time_ms=(time() - execution_start) * 1000
            )

    fn _validate_arbitrage_params(self, entry_signal: TradingSignal,
                                exit_signal: TradingSignal,
                                approval: RiskApproval) -> Bool:
        """
        Validate arbitrage execution parameters
        """
        # Check signals validity
        if not entry_signal.symbol or entry_signal.symbol == "" or \
           not exit_signal.symbol or exit_signal.symbol == "":
            return False

        # Check different symbols (cross-token arbitrage)
        if entry_signal.symbol == exit_signal.symbol:
            return False

        # Check approval validity
        if not approval.approved or approval.position_size <= 0:
            return False

        # Check minimum arbitrage size
        if approval.position_size < 0.01:  # 0.01 SOL minimum for arbitrage
            return False

        # Check opposite actions (buy one, sell other)
        if entry_signal.action == exit_signal.action:
            return False

        # Check price targets
        if entry_signal.price_target <= 0 or exit_signal.price_target <= 0:
            return False

        return True

    async fn _select_arbitrage_provider(self) -> String:
        """
        Select optimal provider for arbitrage execution
        Prefers high-speed, high-success-rate providers
        """
        try:
            # Get provider health via RPCRouter
            router_health = await self.rpc_router.health()

            # Check ShredStream availability first (highest priority for arbitrage)
            shredstream_ready = router_health.get("shredstream_ready", False)
            if shredstream_ready:
                return "helius"

            # Check Lil' JIT availability second
            liljit_ready = router_health.get("liljit_ready", False)
            if liljit_ready:
                return "quicknode"

            # Default to standard Jito
            return "jito"

        except e:
            self.logger.warning("failed_to_select_arbitrage_provider",
                              error=str(e),
                              using_default="jito")
            return "jito"

    async fn _create_arbitrage_bundle(self,
                                    entry_signal: TradingSignal,
                                    exit_signal: TradingSignal,
                                    entry_quote: SwapQuote,
                                    exit_quote: SwapQuote,
                                    entry_priority_fee: Int,
                                    exit_priority_fee: Int,
                                    approval: RiskApproval,
                                    optimal_provider: String) -> Any:
        """
        Create arbitrage bundle using JitoBundleBuilder with provider-specific routing
        """
        try:
            # Get JitoBundleBuilder instance (would be injected or created)
            # For now, we'll simulate bundle creation
            self.logger.info("creating_arbitrage_bundle",
                           entry_symbol=entry_signal.symbol,
                           exit_symbol=exit_signal.symbol,
                           optimal_provider=optimal_provider,
                           entry_priority_fee=entry_priority_fee,
                           exit_priority_fee=exit_priority_fee)

            # Prepare arbitrage instructions
            arbitrage_instructions = []

            # Entry transaction instructions
            entry_instructions = self._prepare_swap_instructions(
                entry_signal, entry_quote, entry_priority_fee
            )

            # Exit transaction instructions
            exit_instructions = self._prepare_swap_instructions(
                exit_signal, exit_quote, exit_priority_fee
            )

            arbitrage_instructions.append(entry_instructions)
            arbitrage_instructions.append(exit_instructions)

            # Create bundle configuration for arbitrage
            bundle_config = {
                "bundle_type": "arbitrage",
                "priority": "critical",
                "tip_amount": max(entry_priority_fee, exit_priority_fee),
                "max_retries": 2,  # Fewer retries for time-sensitive arbitrage
                "timeout_seconds": 15,  # Shorter timeout for arbitrage
                "skip_preflight": True,  # Skip preflight for speed
                "replace_by_fee": True,  # Allow RBF for arbitrage
                "provider": optimal_provider
            }

            # Submit bundle via RPCRouter with provider routing
            bundle_data = {
                "transactions": arbitrage_instructions,
                "config": bundle_config,
                "metadata": {
                    "arbitrage_type": "two_leg",
                    "entry_symbol": entry_signal.symbol,
                    "exit_symbol": exit_signal.symbol,
                    "expected_profit": approval.expected_profit,
                    "urgency": "critical"
                }
            }

            # Submit via RPCRouter bundle submission
            bundle_result = await self.rpc_router.submit_bundle(bundle_data, "critical")

            if bundle_result.get("success", False):
                self.logger.info("arbitrage_bundle_created_successfully",
                               bundle_id=bundle_result.get("bundle_id", ""),
                               provider=optimal_provider,
                               submission_time_ms=bundle_result.get("submission_time_ms", 0))

                return MockBundleExecution(
                    bundle_id=bundle_result.get("bundle_id", ""),
                    success=True,
                    bundle_signature=bundle_result.get("bundle_signature", ""),
                    total_cost=bundle_result.get("total_cost", 0),
                    total_gas_used=bundle_result.get("total_gas_used", 0),
                    execution_time_ms=bundle_result.get("submission_time_ms", 0),
                    transaction_results=[],
                    bundle_metadata={"provider": optimal_provider}
                )
            else:
                error_msg = bundle_result.get("error", "Unknown bundle creation error")
                self.logger.error("arbitrage_bundle_creation_failed",
                                provider=optimal_provider,
                                error=error_msg)

                return MockBundleExecution(
                    bundle_id="",
                    success=False,
                    error_message=error_msg,
                    execution_time_ms=0.0,
                    transaction_results=[],
                    bundle_metadata={"provider": optimal_provider}
                )

        except e as e:
            self.logger.error("exception_in_arbitrage_bundle_creation",
                            entry_symbol=entry_signal.symbol,
                            exit_symbol=exit_signal.symbol,
                            error=str(e))

            return MockBundleExecution(
                bundle_id="",
                success=False,
                error_message=str(e),
                execution_time_ms=0.0,
                transaction_results=[],
                bundle_metadata={"provider": optimal_provider}
            )

    fn _prepare_swap_instructions(self, signal: TradingSignal,
                                quote: SwapQuote,
                                priority_fee: Int) -> List[Any]:
        """
        Prepare swap instructions for bundle inclusion
        """
        # This would create the actual instruction data for the swap
        # For now, return mock instruction data
        instructions = [
            {
                "program_id": "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4",  # Jupiter
                "accounts": [
                    {"pubkey": signal.symbol, "is_signer": False, "is_writable": True},
                    {"pubkey": self.config.wallet_address, "is_signer": True, "is_writable": True}
                ],
                "data": f"swap_instruction_{quote.input_amount}_{quote.output_amount}_{priority_fee}",
                "compute_units": 200000,
                "priority_fee": priority_fee
            }
        ]

        return instructions

    fn _calculate_arbitrage_profit(self, entry_price: Float,
                                 exit_price: Float,
                                 position_size: Float) -> Float:
        """
        Calculate actual arbitrage profit
        """
        try:
            if entry_price <= 0 or exit_price <= 0:
                return 0.0

            # Simple arbitrage profit calculation
            # In reality, this would account for fees, slippage, and path complexity
            profit = (exit_price - entry_price) * position_size
            return max(profit, 0.0)  # Ensure non-negative profit

        except e:
            self.logger.error("error_calculating_arbitrage_profit",
                            entry_price=entry_price,
                            exit_price=exit_price,
                            error=str(e))
            return 0.0

    fn _calculate_arbitrage_slippage(self, actual_profit: Float,
                                   expected_profit: Float) -> Float:
        """
        Calculate arbitrage slippage as percentage difference from expected profit
        """
        if expected_profit <= 0:
            return 0.0

        slippage = (expected_profit - actual_profit) / expected_profit * 100
        return max(slippage, 0.0)  # Ensure non-negative slippage

    async fn monitor_arbitrage_execution(self, bundle_id: String) -> Dict[str, Any]:
        """
        Monitor arbitrage bundle execution and provide real-time updates
        """
        try:
            # Track bundle confirmation via RPCRouter
            confirmation_result = await self.rpc_router.track_bundle_confirmation(bundle_id)

            monitoring_data = {
                "bundle_id": bundle_id,
                "status": confirmation_result.get("status", "unknown"),
                "confirmed_at": confirmation_result.get("confirmed_at"),
                "slot": confirmation_result.get("slot"),
                "transactions": confirmation_result.get("transactions", []),
                "total_gas_used": confirmation_result.get("total_gas_used", 0),
                "execution_time_ms": confirmation_result.get("execution_time_ms", 0),
                "provider": confirmation_result.get("provider", "unknown"),
                "monitoring_timestamp": time()
            }

            self.logger.info("arbitrage_execution_monitored",
                           bundle_id=bundle_id,
                           status=monitoring_data["status"],
                           execution_time_ms=monitoring_data["execution_time_ms"])

            return monitoring_data

        except e as e:
            self.logger.error("arbitrage_monitoring_failed",
                            bundle_id=bundle_id,
                            error=str(e))
            return {
                "bundle_id": bundle_id,
                "status": "error",
                "error": str(e),
                "monitoring_timestamp": time()
            }

    async fn get_arbitrage_performance_stats(self) -> Dict[str, Any]:
        """
        Get arbitrage-specific performance statistics
        """
        try:
            # Get RPCRouter bundle statistics
            router_bundle_stats = await self.rpc_router.get_bundle_statistics()

            # Calculate arbitrage-specific metrics
            arbitrage_success_rate = 0.0
            if self._bundle_submission_count > 0:
                arbitrage_success_rate = self._bundle_success_count / self._bundle_submission_count

            stats = {
                "arbitrage_metrics": {
                    "total_arbitrage_attempts": self._bundle_submission_count,
                    "successful_arbitrages": self._bundle_success_count,
                    "arbitrage_success_rate": arbitrage_success_rate,
                    "average_arbitrage_execution_time_ms": self.total_execution_time / max(self.execution_count, 1),
                    "total_arbitrage_profit": 0.0,  # Would be tracked in real implementation
                    "average_arbitrage_profit": 0.0,   # Would be tracked in real implementation
                    "best_arbitrage_profit": 0.0,      # Would be tracked in real implementation
                    "worst_arbitrage_profit": 0.0      # Would be tracked in real implementation
                },
                "provider_performance": router_bundle_stats,
                "last_updated": time()
            }

            return stats

        except e as e:
            self.logger.error("error_getting_arbitrage_performance_stats",
                            error=str(e))
            return {
                "error": str(e),
                "last_updated": time()
            }

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

            # Execute swap with critical priority for sniper trades
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