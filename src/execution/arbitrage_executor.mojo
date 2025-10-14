"""
Arbitrage Execution Engine for MojoRust Trading Bot

Specialized execution engine for arbitrage opportunities with support for:
- Triangular arbitrage (A → B → C → A)
- Cross-DEX arbitrage (same token on different DEXes)
- Statistical arbitrage (mean reversion)
- Flash loan arbitrage (atomic execution)
"""

from time import time
from collections import Dict, List
from core.types import (
    TradingSignal, ExecutionResult, RiskApproval, TradingAction,
    ArbitrageType, ArbitrageStatus, TriangularArbitrageOpportunity,
    CrossDexArbitrageOpportunity, StatisticalArbitrageOpportunity,
    ArbitrageExecution, ArbitrageResult, SwapQuote
)
from core.constants import (
    MAX_SLIPPAGE, MAX_EXECUTION_TIME_MS, DEFAULT_TIMEOUT_SECONDS,
    LAMPORTS_PER_SOL, SOL_DECIMALS
)
from core.logger import get_execution_logger
from python import Python
from asyncio import sleep

@value
struct ArbitrageExecutor:
    """
    Specialized executor for arbitrage opportunities
    """
    var execution_engine  # Base execution engine
    var jupiter_client      # Jupiter API client
    var quicknode_client   # QuickNode RPC client
    var config             # Configuration
    var active_executions: Dict[String, ArbitrageExecution]  # Currently executing arbitrage
    var execution_history: List[ArbitrageResult]            # Past execution results
    var logger

    var total_arbitrage_executions: Int
    var successful_arbitrage_executions: Int
    var total_arbitrage_profit: Float64
    var total_arbitrage_gas_cost: Float64
    var max_concurrent_executions: Int

    fn __init__(execution_engine, jupiter_client, quicknode_client, config):
        self.execution_engine = execution_engine
        self.jupiter_client = jupiter_client
        self.quicknode_client = quicknode_client
        self.config = config
        self.active_executions = {}
        self.execution_history = []
        self.logger = get_execution_logger()

        self.total_arbitrage_executions = 0
        self.successful_arbitrage_executions = 0
        self.total_arbitrage_profit = 0.0
        self.total_arbitrage_gas_cost = 0.0
        self.max_concurrent_executions = config.get_int("arbitrage.max_concurrent_trades", 3)

    fn execute_triangular_arbitrage(self, opportunity: TriangularArbitrageOpportunity) -> ArbitrageResult:
        """
        Execute triangular arbitrage opportunity
        """
        execution_id = f"tri_{int(time() * 1000)}"
        start_time = time()

        self.logger.info(f"Executing triangular arbitrage: {opportunity.get_description()}",
                        execution_id=execution_id,
                        profit_percentage=opportunity.profit_percentage,
                        confidence_score=opportunity.confidence_score)

        try:
            # Check if we can execute this arbitrage
            if not self._can_execute_arbitrage(opportunity.profit_percentage, opportunity.estimated_gas_cost):
                return ArbitrageResult(
                    execution_id=execution_id,
                    opportunity_id=opportunity.opportunity_id,
                    arbitrage_type=ArbitrageType.TRIANGULAR,
                    success=False,
                    actual_profit=0.0,
                    expected_profit=opportunity.profit_percentage,
                    total_gas_cost=0.0,
                    execution_time_ms=0.0,
                    start_timestamp=start_time,
                    end_timestamp=time(),
                    error_message="Cannot execute: insufficient profit or gas too high"
                )

            # Generate execution plan
            execution_plan = self._create_triangular_execution_plan(opportunity, execution_id)

            # Execute the triangular arbitrage
            result = self._execute_triangular_plan(execution_plan, start_time)

            # Record execution
            self._record_arbitrage_execution(result)

            # Log result
            if result.success:
                self.logger.info(f"Triangular arbitrage executed successfully",
                                execution_id=execution_id,
                                profit_usd=result.actual_profit,
                                gas_cost_sol=result.total_gas_cost,
                                execution_time_ms=result.execution_time_ms)
            else:
                self.logger.error(f"Triangular arbitrage failed: {result.error_message}",
                                 execution_id=execution_id,
                                 error_message=result.error_message)

            return result

        except e as e:
            self.logger.error(f"Triangular arbitrage execution error: {e}",
                             execution_id=execution_id,
                             error=str(e))
            return ArbitrageResult(
                execution_id=execution_id,
                opportunity_id=opportunity.opportunity_id,
                arbitrage_type=ArbitrageType.TRIANGULAR,
                success=False,
                actual_profit=0.0,
                expected_profit=opportunity.profit_percentage,
                total_gas_cost=0.0,
                execution_time_ms=(time() - start_time) * 1000,
                start_timestamp=start_time,
                end_timestamp=time(),
                error_message=str(e)
            )

    fn execute_cross_dex_arbitrage(self, opportunity: CrossDexArbitrageOpportunity) -> ArbitrageResult:
        """
        Execute cross-DEX arbitrage opportunity
        """
        execution_id = f"cross_{int(time() * 1000)}"
        start_time = time()

        self.logger.info(f"Executing cross-DEX arbitrage: {opportunity.get_description()}",
                        execution_id=execution_id,
                        buy_dex=opportunity.buy_dex,
                        sell_dex=opportunity.sell_dex,
                        spread_percentage=opportunity.spread_percentage)

        try:
            # Check if we can execute this arbitrage
            if not self._can_execute_arbitrage(opportunity.profit_after_gas, opportunity.estimated_gas_cost):
                return ArbitrageResult(
                    execution_id=execution_id,
                    opportunity_id=opportunity.opportunity_id,
                    arbitrage_type=ArbitrageType.CROSS_DEX,
                    success=False,
                    actual_profit=0.0,
                    expected_profit=opportunity.profit_after_gas,
                    total_gas_cost=0.0,
                    execution_time_ms=0.0,
                    start_timestamp=start_time,
                    end_timestamp=time(),
                    error_message="Cannot execute: insufficient profit or gas too high"
                )

            # Generate execution plan
            execution_plan = self._create_cross_dex_execution_plan(opportunity, execution_id)

            # Execute the cross-DEX arbitrage
            result = self._execute_cross_dex_plan(execution_plan, start_time)

            # Record execution
            self._record_arbitrage_execution(result)

            # Log result
            if result.success:
                self.logger.info(f"Cross-DEX arbitrage executed successfully",
                                execution_id=execution_id,
                                profit_usd=result.actual_profit,
                                gas_cost_sol=result.total_gas_cost,
                                buy_dex=opportunity.buy_dex,
                                sell_dex=opportunity.sell_dex)
            else:
                self.logger.error(f"Cross-DEX arbitrage failed: {result.error_message}",
                                 execution_id=execution_id,
                                 error_message=result.error_message)

            return result

        except e as e:
            self.logger.error(f"Cross-DEX arbitrage execution error: {e}",
                             execution_id=execution_id,
                             error=str(e))
            return ArbitrageResult(
                execution_id=execution_id,
                opportunity_id=opportunity.opportunity_id,
                arbitrage_type=ArbitrageType.CROSS_DEX,
                success=False,
                actual_profit=0.0,
                expected_profit=opportunity.profit_after_gas,
                total_gas_cost=0.0,
                execution_time_ms=(time() - start_time) * 1000,
                start_timestamp=start_time,
                end_timestamp=time(),
                error_message=str(e)
            )

    fn execute_statistical_arbitrage(self, opportunity: StatisticalArbitrageOpportunity) -> ArbitrageResult:
        """
        Execute statistical arbitrage opportunity
        """
        execution_id = f"stat_{int(time() * 1000)}"
        start_time = time()

        direction = "Long" if opportunity.z_score < -2.0 else "Short"
        self.logger.info(f"Executing statistical arbitrage: {direction} {opportunity.symbol}",
                        execution_id=execution_id,
                        symbol=opportunity.symbol,
                        z_score=opportunity.z_score,
                        expected_return=opportunity.expected_return)

        try:
            # Check if we can execute this arbitrage
            if not self._can_execute_arbitrage(opportunity.expected_return, 0.005):  # Lower gas cost for statistical
                return ArbitrageResult(
                    execution_id=execution_id,
                    opportunity_id=opportunity.opportunity_id,
                    arbitrage_type=ArbitrageType.STATISTICAL,
                    success=False,
                    actual_profit=0.0,
                    expected_profit=opportunity.expected_return,
                    total_gas_cost=0.0,
                    execution_time_ms=0.0,
                    start_timestamp=start_time,
                    end_timestamp=time(),
                    error_message="Cannot execute: insufficient expected return"
                )

            # Generate execution plan
            execution_plan = self._create_statistical_execution_plan(opportunity, execution_id)

            # Execute the statistical arbitrage
            result = self._execute_statistical_plan(execution_plan, start_time)

            # Record execution
            self._record_arbitrage_execution(result)

            # Log result
            if result.success:
                self.logger.info(f"Statistical arbitrage executed successfully",
                                execution_id=execution_id,
                                profit_usd=result.actual_profit,
                                symbol=opportunity.symbol,
                                direction=direction)
            else:
                self.logger.error(f"Statistical arbitrage failed: {result.error_message}",
                                 execution_id=execution_id,
                                 error_message=result.error_message)

            return result

        except e as e:
            self.logger.error(f"Statistical arbitrage execution error: {e}",
                             execution_id=execution_id,
                             error=str(e))
            return ArbitrageResult(
                execution_id=execution_id,
                opportunity_id=opportunity.opportunity_id,
                arbitrage_type=ArbitrageType.STATISTICAL,
                success=False,
                actual_profit=0.0,
                expected_profit=opportunity.expected_return,
                total_gas_cost=0.0,
                execution_time_ms=(time() - start_time) * 1000,
                start_timestamp=start_time,
                end_timestamp=time(),
                error_message=str(e)
            )

    fn _can_execute_arbitrage(self, profit_percentage: Float64, gas_cost: Float64) -> Bool:
        """
        Check if arbitrage can be executed based on profit and gas costs
        """
        # Check minimum profit threshold
        min_profit = self.config.get_float("arbitrage.min_profit_threshold", 0.5)
        if profit_percentage < min_profit:
            return False

        # Check maximum gas cost
        max_gas = self.config.get_float("arbitrage.max_gas_price", 0.01)
        if gas_cost > max_gas:
            return False

        # Check concurrent execution limit
        if len(self.active_executions) >= self.max_concurrent_executions:
            return False

        return True

    fn _create_triangular_execution_plan(self, opportunity: TriangularArbitrageOpportunity, execution_id: String) -> ArbitrageExecution:
        """
        Create execution plan for triangular arbitrage
        """
        var trades = List[TradingSignal]()

        # Create three trading signals for the triangular path
        # A → B (first edge)
        trades.append(TradingSignal(
            symbol=opportunity.symbols[0],
            action=TradingAction.SELL,  # Start with base token
            confidence=Float32(opportunity.confidence_score),
            timeframe="arbitrage",
            entry_price=0.0,  # Will be filled by quote
            position_size=0.1,  # Configurable position size
            reasoning=f"Triangular arbitrage step 1: {opportunity.symbols[0]} → {opportunity.symbols[1]} on {opportunity.dexes[0]}"
            priority=5,
            signal_source="triangular_arbitrage",
            metadata={
                "execution_id": execution_id,
                "dex": opportunity.dexes[0],
                "step": 1,
                "cycle": opportunity.cycle
            }
        ))

        # B → C (second edge)
        trades.append(TradingSignal(
            symbol=opportunity.symbols[1],
            action=TradingAction.SELL,
            confidence=Float32(opportunity.confidence_score),
            timeframe="arbitrage",
            entry_price=0.0,
            position_size=0.1,
            reasoning=f"Triangular arbitrage step 2: {opportunity.symbols[1]} → {opportunity.symbols[2]} on {opportunity.dexes[1]}"
            priority=5,
            signal_source="triangular_arbitrage",
            metadata={
                "execution_id": execution_id,
                "dex": opportunity.dexes[1],
                "step": 2,
                "cycle": opportunity.cycle
            }
        ))

        # C → A (third edge)
        trades.append(TradingSignal(
            symbol=opportunity.symbols[2],
            action=TradingAction.SELL,
            confidence=Float32(opportunity.confidence_score),
            timeframe="arbitrage",
            entry_price=0.0,
            position_size=0.1,
            reasoning=f"Triangular arbitrage step 3: {opportunity.symbols[2]} → {opportunity.symbols[0]} on {opportunity.dexes[2]}"
            priority=5,
            signal_source="triangular_arbitrage",
            metadata={
                "execution_id": execution_id,
                "dex": opportunity.dexes[2],
                "step": 3,
                "cycle": opportunity.cycle
            }
        ))

        return ArbitrageExecution(
            opportunity_id=opportunity.opportunity_id,
            arbitrage_type=ArbitrageType.TRIANGULAR,
            trades=trades,
            total_expected_profit=opportunity.profit_percentage,
            total_gas_cost=opportunity.estimated_gas_cost,
            execution_strategy="simultaneous",  # Execute all trades simultaneously
            max_slippage=opportunity.slippage_estimate,
            timeout_seconds=30.0,
            created_timestamp=time(),
            status=ArbitrageStatus.APPROVED
        )

    fn _create_cross_dex_execution_plan(self, opportunity: CrossDexArbitrageOpportunity, execution_id: String) -> ArbitrageExecution:
        """
        Create execution plan for cross-DEX arbitrage
        """
        var trades = List[TradingSignal]()

        # Buy on cheaper DEX
        trades.append(TradingSignal(
            symbol=opportunity.symbol,
            action=TradingAction.BUY,
            confidence=Float32(min(opportunity.spread_percentage / 10.0, 0.9)),
            timeframe="arbitrage",
            entry_price=opportunity.buy_price,
            position_size=0.1,  # Configurable position size
            reasoning=f"Cross-DEX arbitrage buy: {opportunity.symbol} on {opportunity.buy_dex} at {opportunity.buy_price}",
            priority=5,
            signal_source="cross_dex_arbitrage",
            metadata={
                "execution_id": execution_id,
                "dex": opportunity.buy_dex,
                "trade_type": "buy",
                "target_dex": opportunity.sell_dex
            }
        ))

        # Sell on more expensive DEX
        trades.append(TradingSignal(
            symbol=opportunity.symbol,
            action=TradingAction.SELL,
            confidence=Float32(min(opportunity.spread_percentage / 10.0, 0.9)),
            timeframe="arbitrage",
            entry_price=opportunity.sell_price,
            position_size=0.1,
            reasoning=f"Cross-DEX arbitrage sell: {opportunity.symbol} on {opportunity.sell_dex} at {opportunity.sell_price}",
            priority=5,
            signal_source="cross_dex_arbitrage",
            metadata={
                "execution_id": execution_id,
                "dex": opportunity.sell_dex,
                "trade_type": "sell",
                "source_dex": opportunity.buy_dex
            }
        ))

        return ArbitrageExecution(
            opportunity_id=opportunity.opportunity_id,
            arbitrage_type=ArbitrageType.CROSS_DEX,
            trades=trades,
            total_expected_profit=opportunity.profit_after_gas,
            total_gas_cost=opportunity.estimated_gas_cost,
            execution_strategy="sequential",  # Execute buy then sell
            max_slippage=2.0,
            timeout_seconds=30.0,
            created_timestamp=time(),
            status=ArbitrageStatus.APPROVED
        )

    fn _create_statistical_execution_plan(self, opportunity: StatisticalArbitrageOpportunity, execution_id: String) -> ArbitrageExecution:
        """
        Create execution plan for statistical arbitrage
        """
        direction = TradingAction.BUY if opportunity.z_score < -2.0 else TradingAction.SELL
        reasoning = f"Statistical arbitrage {direction}: {opportunity.symbol} (Z-score: {opportunity.z_score:.2f})"

        trades.append(TradingSignal(
            symbol=opportunity.symbol,
            action=direction,
            confidence=Float32(opportunity.confidence),
            timeframe="statistical",
            entry_price=opportunity.current_price,
            position_size=0.05,  # Smaller position size for statistical arbitrage
            reasoning=reasoning,
            priority=4,  # Lower priority than pure arbitrage
            signal_source="statistical_arbitrage",
            metadata={
                "execution_id": execution_id,
                "z_score": opportunity.z_score,
                "mean_price": opportunity.mean_price,
                "std_deviation": opportunity.std_deviation,
                "holding_period_ms": opportunity.holding_period_secs * 1000
            }
        ))

        return ArbitrageExecution(
            opportunity_id=opportunity.opportunity_id,
            arbitrage_type=ArbitrageType.STATISTICAL,
            trades=trades,
            total_expected_profit=opportunity.expected_return,
            total_gas_cost=0.005,  # Lower gas cost for single trade
            execution_strategy="single",
            max_slippage=1.0,
            timeout_seconds=float(opportunity.holding_period_secs),
            created_timestamp=time(),
            status=ArbitrageStatus.APPROVED
        )

    fn _execute_triangular_plan(self, execution_plan: ArbitrageExecution, start_time: Float64) -> ArbitrageResult:
        """
        Execute triangular arbitrage plan
        """
        try:
            # For now, simulate triangular arbitrage execution
            # In production, this would involve atomic execution or flash loans

            # Simulate execution time
            sleep(0.1)  # 100ms simulation

            # Calculate actual profit (with some randomness to simulate market movement)
            actual_profit = execution_plan.total_expected_profit * (0.8 + Python.random().random() * 0.4)

            # Simulate gas costs
            total_gas_cost = execution_plan.total_gas_cost * (0.9 + Python.random().random() * 0.2)

            # Generate mock transaction hash
            tx_hash = f"tri_arb_{int(time() * 1000)}"

            # Create execution results for each trade
            trade_results = []
            for trade in execution_plan.trades:
                trade_results.append(ExecutionResult(
                    success=True,
                    tx_hash=f"{tx_hash}_{trade.symbol}",
                    executed_price=trade.entry_price * (0.99 + Python.random().random() * 0.02),
                    requested_price=trade.entry_price,
                    slippage_percentage=Python.random().random() * 1.0,
                    gas_cost=total_gas_cost / len(execution_plan.trades),
                    execution_time_ms=50.0 + Python.random().random() * 100.0
                ))

            return ArbitrageResult(
                execution_id=execution_plan.trades[0].metadata["execution_id"],
                opportunity_id=execution_plan.opportunity_id,
                arbitrage_type=execution_plan.arbitrage_type,
                success=True,
                actual_profit=actual_profit,
                expected_profit=execution_plan.total_expected_profit,
                total_gas_cost=total_gas_cost,
                execution_time_ms=(time() - start_time) * 1000,
                trade_results=trade_results,
                start_timestamp=start_time,
                end_timestamp=time()
            )

        except e as e:
            return ArbitrageResult(
                execution_id=execution_plan.trades[0].metadata["execution_id"],
                opportunity_id=execution_plan.opportunity_id,
                arbitrage_type=execution_plan.arbitrage_type,
                success=False,
                actual_profit=0.0,
                expected_profit=execution_plan.total_expected_profit,
                total_gas_cost=0.0,
                execution_time_ms=(time() - start_time) * 1000,
                trade_results=[],
                start_timestamp=start_time,
                end_timestamp=time(),
                error_message=str(e)
            )

    fn _execute_cross_dex_plan(self, execution_plan: ArbitrageExecution, start_time: Float64) -> ArbitrageResult:
        """
        Execute cross-DEX arbitrage plan
        """
        try:
            # Simulate execution time (longer for cross-DEX)
            sleep(0.2)  # 200ms simulation

            # Calculate actual profit
            actual_profit = execution_plan.total_expected_profit * (0.7 + Python.random().random() * 0.5)

            # Simulate gas costs
            total_gas_cost = execution_plan.total_gas_cost * (0.9 + Python.random().random() * 0.2)

            # Generate mock transaction hash
            tx_hash = f"cross_arb_{int(time() * 1000)}"

            # Create execution results
            trade_results = []
            for trade in execution_plan.trades:
                trade_results.append(ExecutionResult(
                    success=True,
                    tx_hash=f"{tx_hash}_{trade.metadata['dex']}",
                    executed_price=trade.entry_price * (0.98 + Python.random().random() * 0.03),
                    requested_price=trade.entry_price,
                    slippage_percentage=Python.random().random() * 1.5,
                    gas_cost=total_gas_cost / len(execution_plan.trades),
                    execution_time_ms=75.0 + Python.random().random() * 150.0
                ))

            return ArbitrageResult(
                execution_id=execution_plan.trades[0].metadata["execution_id"],
                opportunity_id=execution_plan.opportunity_id,
                arbitrage_type=execution_plan.arbitrage_type,
                success=True,
                actual_profit=actual_profit,
                expected_profit=execution_plan.total_expected_profit,
                total_gas_cost=total_gas_cost,
                execution_time_ms=(time() - start_time) * 1000,
                trade_results=trade_results,
                start_timestamp=start_time,
                end_timestamp=time()
            )

        except e as e:
            return ArbitrageResult(
                execution_id=execution_plan.trades[0].metadata["execution_id"],
                opportunity_id=execution_plan.opportunity_id,
                arbitrage_type=execution_plan.arbitrage_type,
                success=False,
                actual_profit=0.0,
                expected_profit=execution_plan.total_expected_profit,
                total_gas_cost=0.0,
                execution_time_ms=(time() - start_time) * 1000,
                trade_results=[],
                start_timestamp=start_time,
                end_timestamp=time(),
                error_message=str(e)
            )

    fn _execute_statistical_plan(self, execution_plan: ArbitrageExecution, start_time: Float64) -> ArbitrageResult:
        """
        Execute statistical arbitrage plan
        """
        try:
            # Simulate execution time
            sleep(0.05)  # 50ms simulation

            # Calculate actual profit (can be negative for statistical arbitrage)
            profit_variance = Python.random().random() - 0.5  # -0.5 to 0.5
            actual_profit = execution_plan.total_expected_profit + profit_variance

            # Simulate gas costs
            total_gas_cost = execution_plan.total_gas_cost * (0.8 + Python.random().random() * 0.3)

            # Generate mock transaction hash
            tx_hash = f"stat_arb_{int(time() * 1000)}"

            # Create execution result
            trade_results = [ExecutionResult(
                success=True,
                tx_hash=tx_hash,
                executed_price=execution_plan.trades[0].entry_price * (0.98 + Python.random().random() * 0.03),
                requested_price=execution_plan.trades[0].entry_price,
                slippage_percentage=Python.random().random() * 1.0,
                gas_cost=total_gas_cost,
                execution_time_ms=25.0 + Python.random().random() * 50.0
            )]

            return ArbitrageResult(
                execution_id=execution_plan.trades[0].metadata["execution_id"],
                opportunity_id=execution_plan.opportunity_id,
                arbitrage_type=execution_plan.arbitrage_type,
                success=True,
                actual_profit=actual_profit,
                expected_profit=execution_plan.total_expected_profit,
                total_gas_cost=total_gas_cost,
                execution_time_ms=(time() - start_time) * 1000,
                trade_results=trade_results,
                start_timestamp=start_time,
                end_timestamp=time()
            )

        except e as e:
            return ArbitrageResult(
                execution_id=execution_plan.trades[0].metadata["execution_id"],
                opportunity_id=execution_plan.opportunity_id,
                arbitrage_type=execution_plan.arbitrage_type,
                success=False,
                actual_profit=0.0,
                expected_profit=execution_plan.total_expected_profit,
                total_gas_cost=0.0,
                execution_time_ms=(time() - start_time) * 1000,
                trade_results=[],
                start_timestamp=start_time,
                end_timestamp=time(),
                error_message=str(e)
            )

    fn _record_arbitrage_execution(self, result: ArbitrageResult):
        """
        Record arbitrage execution results and update metrics
        """
        self.total_arbitrage_executions += 1

        if result.success:
            self.successful_arbitrage_executions += 1
            self.total_arbitrage_profit += result.actual_profit

        self.total_arbitrage_gas_cost += result.total_gas_cost

        # Add to history (keep last 1000 executions)
        self.execution_history.append(result)
        if len(self.execution_history) > 1000:
            self.execution_history = self.execution_history[-1000:]

    def get_arbitrage_stats(self) -> Dict[str, Any]:
        """
        Get arbitrage execution statistics
        """
        success_rate = 0.0
        if self.total_arbitrage_executions > 0:
            success_rate = self.successful_arbitrage_executions / self.total_arbitrage_executions

        avg_profit = 0.0
        if self.successful_arbitrage_executions > 0:
            avg_profit = self.total_arbitrage_profit / self.successful_arbitrage_executions

        avg_gas_cost = 0.0
        if self.total_arbitrage_executions > 0:
            avg_gas_cost = self.total_arbitrage_gas_cost / self.total_arbitrage_executions

        # Calculate profit accuracy from recent executions
        recent_executions = self.execution_history[-50:] if len(self.execution_history) > 0 else []
        profit_accuracy = 0.0
        if len(recent_executions) > 0:
            total_accuracy = 0.0
            valid_count = 0
            for result in recent_executions:
                if result.expected_profit != 0:
                    accuracy = result.actual_profit / result.expected_profit
                    total_accuracy += accuracy
                    valid_count += 1

            if valid_count > 0:
                profit_accuracy = total_accuracy / valid_count

        return {
            "total_executions": self.total_arbitrage_executions,
            "successful_executions": self.successful_arbitrage_executions,
            "success_rate": success_rate,
            "total_profit_usd": self.total_arbitrage_profit,
            "average_profit_usd": avg_profit,
            "total_gas_cost_sol": self.total_arbitrage_gas_cost,
            "average_gas_cost_sol": avg_gas_cost,
            "profit_accuracy": profit_accuracy,
            "net_profit_usd": self.total_arbitrage_profit - (self.total_arbitrage_gas_cost * 150.0),  # Assuming $150/SOL
            "active_executions": len(self.active_executions),
            "max_concurrent_executions": self.max_concurrent_executions
        }

    def get_recent_executions(self, limit: Int = 10) -> List[ArbitrageResult]:
        """
        Get recent arbitrage execution results
        """
        return self.execution_history[-limit:] if len(self.execution_history) >= limit else self.execution_history

    def reset_metrics(self):
        """
        Reset arbitrage execution metrics
        """
        self.total_arbitrage_executions = 0
        self.successful_arbitrage_executions = 0
        self.total_arbitrage_profit = 0.0
        self.total_arbitrage_gas_cost = 0.0
        self.execution_history = []

    def health_check(self) -> Bool:
        """
        Check if arbitrage executor is healthy
        """
        # Check success rate
        if self.total_arbitrage_executions > 10:
            success_rate = self.successful_arbitrage_executions / self.total_arbitrage_executions
            if success_rate < 0.6:  # Less than 60% success rate
                return False

        # Check average profit
        if self.successful_arbitrage_executions > 5:
            avg_profit = self.total_arbitrage_profit / self.successful_arbitrage_executions
            if avg_profit < 0.1:  # Less than $0.10 average profit
                return False

        return True