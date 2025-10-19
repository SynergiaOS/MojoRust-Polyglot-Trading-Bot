# =============================================================================
# Strategic Orchestrator (CEO Brain)
# =============================================================================
#
# This module implements the central algorithmic orchestrator that acts as the
# "CEO brain" of the trading system. It coordinates multiple strategies,
# manages capital allocation, and makes intelligent execution decisions.
#
# Features:
# - Opportunity queue management with scoring
# - Dynamic capital allocation
# - Risk management integration
# - Adaptive learning and weight adjustment
# - Consensus-based decision making
# - Performance tracking and feedback

from time import time, sleep
from collections import Dict, List, PriorityQueue, NamedTuple
from math import min, max, sqrt
from core.types import Config, TradingSignal, TradingAction
from core.logger import get_main_logger
from risk.risk_manager import RiskManager
from strategies.flash_loan_ensemble import FlashLoanPatternSignal

# Opportunity representation for the orchestrator
@value
struct Opportunity:
    id: String
    strategy_type: String  # arbitrage, sniper_momentum, etc.
    token: String
    confidence: Float
    expected_return: Float
    risk_score: Float
    required_capital: Float
    flash_loan_amount: Float
    timestamp: Int
    ttl_seconds: Int
    metadata: Dict[String, String]

    # Comparison for priority queue (higher score = higher priority)
    fn __lt__(self, other: Opportunity) -> Bool:
        return self.calculate_score() > other.calculate_score()

    fn calculate_score(self) -> Float:
        """Calculate composite score for opportunity prioritization"""
        return self.confidence * 100.0 * (1.0 - self.risk_score) + self.expected_return * 1000.0

# Portfolio state tracking
@value
struct PortfolioState:
    total_capital: Float
    available_capital: Float
    allocated_capital: Float
    flash_loan_used: Float
    flash_loan_limit: Float
    open_positions: Int
    max_positions: Int
    leverage_ratio: Float
    last_update: Int

    fn get_available_for_opportunity(self, required_capital: Float, flash_loan: Float) -> Float:
        """Check if portfolio has enough capital for opportunity"""
        total_needed = required_capital
        available = self.available_capital + (self.flash_loan_limit - self.flash_loan_used)
        return min(total_needed, available)

# Strategy performance metrics
@value
struct StrategyMetrics:
    strategy_name: String
    total_opportunities: Int
    successful_opportunities: Int
    failed_opportunities: Int
    total_profit: Float
    total_loss: Float
    average_execution_time_ms: Float
    win_rate: Float
    profit_factor: Float
    last_updated: Int

    fn update_performance(self, success: Bool, profit: Float, execution_time: Float):
        """Update metrics with new execution result"""
        new_total = self.total_opportunities + 1
        new_successful = self.successful_opportunities + (1 if success else 0)
        new_failed = self.failed_opportunities + (0 if success else 1)
        new_total_profit = self.total_profit + (profit if profit > 0 else 0)
        new_total_loss = self.total_loss + (abs(profit) if profit < 0 else 0)
        new_win_rate = new_successful as Float / new_total as Float
        new_profit_factor = new_total_profit / max(0.01, new_total_loss)

        # Update average execution time
        new_avg_time = (
            self.average_execution_time_ms * self.total_opportunities + execution_time
        ) / new_total

        return StrategyMetrics(
            strategy_name=self.strategy_name,
            total_opportunities=new_total,
            successful_opportunities=new_successful,
            failed_opportunities=new_failed,
            total_profit=new_total_profit,
            total_loss=new_total_loss,
            average_execution_time_ms=new_avg_time,
            win_rate=new_win_rate,
            profit_factor=new_profit_factor,
            last_updated=int(time())
        )

# Strategic Orchestrator - The CEO Brain
@value
struct StrategicOrchestrator:
    var config: Config
    var opportunity_queue: PriorityQueue[Opportunity]
    var portfolio_state: PortfolioState
    var strategy_metrics: Dict[String, StrategyMetrics]
    var risk_manager: RiskManager
    var dragonfly_client: PythonObject
    var logger: PythonObject
    var scoring_weights: Dict[String, Float]
    var adaptive_learning_enabled: Bool
    var running: Bool

    fn __init__(self, config: Config):
        self.config = config
        self.logger = get_main_logger()

        # Initialize components
        self.opportunity_queue = PriorityQueue()
        self.risk_manager = RiskManager(config)

        # Initialize DragonflyDB client
        import redis
        redis_url = config.dragonflydb.url
        self.dragonfly_client = redis.from_url(redis_url)

        # Initialize portfolio state
        self.portfolio_state = PortfolioState(
            total_capital=config.trading.initial_capital,
            available_capital=config.trading.initial_capital,
            allocated_capital=0.0,
            flash_loan_used=0.0,
            flash_loan_limit=config.flash_loan.enhanced.daily_limit_sol,
            open_positions=0,
            max_positions=config.orchestrator.max_concurrent_opportunities,
            leverage_ratio=1.0,
            last_update=int(time())
        )

        # Initialize strategy metrics
        self.strategy_metrics = {}

        # Initialize scoring weights from config
        self.scoring_weights = {
            "profit": config.orchestrator.scoring_weights.profit,
            "risk": config.orchestrator.scoring_weights.risk,
            "capital_efficiency": config.orchestrator.scoring_weights.capital_efficiency,
            "strategy_bonus": config.orchestrator.scoring_weights.strategy_bonus
        }

        self.adaptive_learning_enabled = config.orchestrator.adaptive_learning_enabled
        self.running = False

        self.logger.info("🧠 Strategic Orchestrator (CEO Brain) initialized")
        self.logger.info(f"   Max concurrent opportunities: {config.orchestrator.max_concurrent_opportunities}")
        self.logger.info(f"   Scoring weights: {self.scoring_weights}")
        self.logger.info(f"   Adaptive learning: {self.adaptive_learning_enabled}")

    fn start(self):
        """Start the orchestrator control loop"""
        self.running = True
        self.logger.info("🚀 Starting Strategic Orchestrator control loop")

        while self.running:
            try:
                self.control_loop_iteration()
                sleep(self.config.orchestrator.decision_loop_interval_ms / 1000.0)
            except Exception as e:
                self.logger.error(f"Error in control loop: {e}")
                sleep(1.0)  # Brief pause on error

    fn stop(self):
        """Stop the orchestrator"""
        self.running = False
        self.logger.info("🛑 Strategic Orchestrator stopped")

    fn control_loop_iteration(self):
        """Main control loop iteration - processes one opportunity"""
        # Step 1: Fetch highest score opportunity from queue
        opportunity = self.fetch_opportunity()
        if opportunity is None:
            return  # No opportunities available

        # Step 2: Verify risk limits
        risk_check = self.verify_risk_limits(opportunity)
        if not risk_check.approved:
            self.logger.debug(f"❌ Risk rejected {opportunity.id}: {risk_check.reason}")
            return

        # Step 3: Allocate resources
        allocation_result = self.allocate_capital(opportunity)
        if not allocation_result.success:
            self.logger.debug(f"❌ Capital allocation failed for {opportunity.id}: {allocation_result.reason}")
            return

        # Step 4: Execute command
        execution_result = self.execute_opportunity(opportunity, allocation_result.allocated_capital)

        # Step 5: Update metrics and release/adjust capital
        self.handle_execution_result(opportunity, execution_result)

        # Step 6: Adaptive learning (if enabled)
        if self.adaptive_learning_enabled:
            self.adaptive_weight_adjustment()

    fn fetch_opportunity(self) -> Opportunity:
        """Fetch highest score opportunity from DragonflyDB queue"""
        try:
            # Get highest score opportunity from sorted set
            opportunity_data = self.dragonfly_client.zpopmax("opportunity_queue", 1)
            if not opportunity_data:
                return None

            # ZPOPMAX returns [(member, score), ...] - we need the member (payload)
            opportunity_json = opportunity_data[0][0]  # Get payload (member), not score
            if isinstance(opportunity_json, bytes):
                opportunity_json = opportunity_json.decode('utf-8')

            # Parse JSON properly instead of using eval
            import json
            opportunity_dict = json.loads(opportunity_json)

            # Check if opportunity is still valid (not expired)
            current_time = int(time())
            if current_time - opportunity_dict["timestamp"] > opportunity_dict["ttl_seconds"]:
                self.logger.debug(f"⏰ Opportunity {opportunity_dict['id']} expired")
                return None

            return Opportunity(
                id=opportunity_dict["id"],
                strategy_type=opportunity_dict["strategy_type"],
                token=opportunity_dict["token"],
                confidence=opportunity_dict["confidence"],
                expected_return=opportunity_dict["expected_return"],
                risk_score=opportunity_dict["risk_score"],
                required_capital=opportunity_dict["required_capital"],
                flash_loan_amount=opportunity_dict["flash_loan_amount"],
                timestamp=opportunity_dict["timestamp"],
                ttl_seconds=opportunity_dict["ttl_seconds"],
                metadata=opportunity_dict["metadata"]
            )

        except Exception as e:
            self.logger.error(f"Error fetching opportunity: {e}")
            return None

    fn verify_risk_limits(self, opportunity: Opportunity) -> NamedTuple:
        """Verify that opportunity passes all risk checks"""
        # Check available capital
        total_required = opportunity.required_capital
        available = self.portfolio_state.available_capital + (self.portfolio_state.flash_loan_limit - self.portfolio_state.flash_loan_used)

        if total_required > available:
            return NamedTuple(approved=False, reason="Insufficient capital")

        # Check flash loan daily limit
        if opportunity.flash_loan_amount > (self.portfolio_state.flash_loan_limit - self.portfolio_state.flash_loan_used):
            return NamedTuple(approved=False, reason="Flash loan daily limit exceeded")

        # Check portfolio heat
        portfolio_heat = self.portfolio_state.allocated_capital / self.portfolio_state.total_capital
        if portfolio_heat > self.config.orchestrator.portfolio_heat_limit:
            return NamedTuple(approved=False, reason=f"Portfolio heat too high: {portfolio_heat:.2f}")

        # Check position limits
        if self.portfolio_state.open_positions >= self.portfolio_state.max_positions:
            return NamedTuple(approved=False, reason="Maximum positions reached")

        # Check leverage ratio
        leverage_ratio = (self.portfolio_state.allocated_capital + opportunity.flash_loan_amount) / self.portfolio_state.total_capital
        if leverage_ratio > self.config.orchestrator.max_leverage_ratio:
            return NamedTuple(approved=False, reason=f"Leverage ratio too high: {leverage_ratio:.2f}")

        # Use risk manager for additional checks
        risk_result = self.risk_manager.evaluate_opportunity(opportunity)
        if not risk_result.approved:
            return NamedTuple(approved=False, reason=risk_result.reason)

        return NamedTuple(approved=True, reason="All risk checks passed")

    fn allocate_capital(self, opportunity: Opportunity) -> NamedTuple:
        """Allocate capital for the opportunity"""
        try:
            # Reserve capital atomically in DragonflyDB
            capital_key = f"capital_reservation:{opportunity.id}"
            reservation_data = {
                "opportunity_id": opportunity.id,
                "allocated_capital": opportunity.required_capital,
                "flash_loan_amount": opportunity.flash_loan_amount,
                "timestamp": int(time()),
                "ttl": 300  # 5 minutes reservation
            }

            # Store reservation with TTL as JSON
            import json
            self.dragonfly_client.setex(capital_key, 300, json.dumps(reservation_data))

            # Update portfolio state
            self.portfolio_state = PortfolioState(
                total_capital=self.portfolio_state.total_capital,
                available_capital=self.portfolio_state.available_capital - opportunity.required_capital,
                allocated_capital=self.portfolio_state.allocated_capital + opportunity.required_capital,
                flash_loan_used=self.portfolio_state.flash_loan_used + opportunity.flash_loan_amount,
                flash_loan_limit=self.portfolio_state.flash_loan_limit,
                open_positions=self.portfolio_state.open_positions + 1,
                max_positions=self.portfolio_state.max_positions,
                leverage_ratio=(self.portfolio_state.allocated_capital + opportunity.flash_loan_amount) / self.portfolio_state.total_capital,
                last_update=int(time())
            )

            return NamedTuple(
                success=True,
                allocated_capital=opportunity.required_capital,
                flash_loan_amount=opportunity.flash_loan_amount,
                reason="Capital allocated successfully"
            )

        except Exception as e:
            self.logger.error(f"Error allocating capital: {e}")
            return NamedTuple(success=False, allocated_capital=0.0, flash_loan_amount=0.0, reason=str(e))

    fn execute_opportunity(self, opportunity: Opportunity, allocated_capital: Float) -> NamedTuple:
        """Send execution command to execution layer"""
        try:
            execution_start = time()

            # Create execution command
            execution_command = {
                "opportunity_id": opportunity.id,
                "strategy_type": opportunity.strategy_type,
                "token": opportunity.token,
                "allocated_capital": allocated_capital,
                "flash_loan_amount": opportunity.flash_loan_amount,
                "execution_plan": opportunity.metadata,
                "timestamp": int(time())
            }

            # Publish to execution results channel (Rust will pick this up)
            import json
            self.dragonfly_client.publish("orchestrator_commands", json.dumps(execution_command))

            execution_time = (time() - execution_start) * 1000  # Convert to ms

            self.logger.info(f"🎯 Executing {opportunity.strategy_type} for {opportunity.token} with {allocated_capital:.4f} SOL")

            return NamedTuple(
                success=True,
                execution_time_ms=execution_time,
                reason="Execution command sent"
            )

        except Exception as e:
            self.logger.error(f"Error executing opportunity: {e}")
            return NamedTuple(success=False, execution_time_ms=0.0, reason=str(e))

    fn handle_execution_result(self, opportunity: Opportunity, execution_result: NamedTuple):
        """Handle execution result and update metrics"""
        try:
            # Wait for execution result (this would be handled via pub/sub in production)
            # For now, simulate a result
            import random
            success = random.random() > 0.3  # 70% success rate
            profit = opportunity.expected_return * (0.8 + random.random() * 0.4) if success else -opportunity.expected_return * 0.1

            # Update strategy metrics
            if opportunity.strategy_type not in self.strategy_metrics:
                self.strategy_metrics[opportunity.strategy_type] = StrategyMetrics(
                    strategy_name=opportunity.strategy_type,
                    total_opportunities=0,
                    successful_opportunities=0,
                    failed_opportunities=0,
                    total_profit=0.0,
                    total_loss=0.0,
                    average_execution_time_ms=0.0,
                    win_rate=0.0,
                    profit_factor=0.0,
                    last_updated=int(time())
                )

            current_metrics = self.strategy_metrics[opportunity.strategy_type]
            updated_metrics = current_metrics.update_performance(success, profit, execution_result.execution_time_ms)
            self.strategy_metrics[opportunity.strategy_type] = updated_metrics

            # Release capital
            self.release_capital(opportunity.id, success, profit)

            # Publish result for monitoring
            result_data = {
                "opportunity_id": opportunity.id,
                "strategy_type": opportunity.strategy_type,
                "success": success,
                "profit": profit,
                "execution_time_ms": execution_result.execution_time_ms,
                "timestamp": int(time())
            }

            self.dragonfly_client.publish("execution_results", json.dumps(result_data))

            # Log result
            if success:
                self.logger.info(f"✅ Success {opportunity.id}: profit={profit:.4f} SOL")
            else:
                self.logger.warning(f"❌ Failed {opportunity.id}: loss={profit:.4f} SOL")

        except Exception as e:
            self.logger.error(f"Error handling execution result: {e}")
            # Still release capital on error
            self.release_capital(opportunity.id, False, 0.0)

    fn release_capital(self, opportunity_id: String, success: Bool, profit: Float):
        """Release allocated capital back to portfolio"""
        try:
            # Get reservation data using the same key used in allocation
            capital_key = f"capital_reservation:{opportunity_id}"
            reservation_data = self.dragonfly_client.get(capital_key)

            if reservation_data:
                # Parse JSON properly instead of using eval
                import json
                if isinstance(reservation_data, bytes):
                    reservation_data = reservation_data.decode('utf-8')
                reservation = json.loads(reservation_data)

                allocated_capital = reservation["allocated_capital"]
                flash_loan_amount = reservation["flash_loan_amount"]

                # Update portfolio state
                self.portfolio_state = PortfolioState(
                    total_capital=self.portfolio_state.total_capital + profit,
                    available_capital=self.portfolio_state.available_capital + allocated_capital + profit,
                    allocated_capital=self.portfolio_state.allocated_capital - allocated_capital,
                    flash_loan_used=self.portfolio_state.flash_loan_used - flash_loan_amount,
                    flash_loan_limit=self.portfolio_state.flash_loan_limit,
                    open_positions=self.portfolio_state.open_positions - 1,
                    max_positions=self.portfolio_state.max_positions,
                    leverage_ratio=self.portfolio_state.allocated_capital / self.portfolio_state.total_capital,
                    last_update=int(time())
                )

            # Remove capital reservation
            self.dragonfly_client.delete(capital_key)

        except Exception as e:
            self.logger.error(f"Error releasing capital: {e}")

    fn calculate_opportunity_score(self, opportunity: Opportunity) -> Float:
        """Calculate composite score for opportunity"""
        # Base score from expected return
        profit_score = opportunity.expected_return * self.scoring_weights["profit"] * 1000.0

        # Risk penalty
        risk_penalty = opportunity.risk_score * self.scoring_weights["risk"] * 100.0

        # Capital efficiency bonus (higher return per capital = better)
        capital_efficiency = (opportunity.expected_return / max(0.001, opportunity.required_capital))
        efficiency_bonus = capital_efficiency * self.scoring_weights["capital_efficiency"] * 100.0

        # Strategy bonus based on historical performance
        strategy_bonus = 0.0
        if opportunity.strategy_type in self.strategy_metrics:
            metrics = self.strategy_metrics[opportunity.strategy_type]
            strategy_bonus = metrics.win_rate * metrics.profit_factor * self.scoring_weights["strategy_bonus"] * 50.0

        total_score = profit_score - risk_penalty + efficiency_bonus + strategy_bonus

        # Normalize to 0-100 range
        return max(0.0, min(100.0, total_score))

    fn adaptive_weight_adjustment(self):
        """Adjust scoring weights based on strategy performance"""
        try:
            # Analyze last 100 opportunities for each strategy
            current_time = int(time())
            analysis_window = 300  # 5 minutes

            for strategy_name, metrics in self.strategy_metrics.items():
                if metrics.total_opportunities >= 10:  # Only adjust with sufficient data
                    # Calculate performance score
                    performance_score = metrics.win_rate * metrics.profit_factor

                    # Adjust weights based on performance
                    if performance_score > 1.5:  # High performance
                        self.scoring_weights["strategy_bonus"] = min(0.3, self.scoring_weights["strategy_bonus"] * 1.1)
                        self.logger.info(f"📈 Increasing weight for {strategy_name} (performance: {performance_score:.2f})")
                    elif performance_score < 0.5:  # Low performance
                        self.scoring_weights["strategy_bonus"] = max(0.05, self.scoring_weights["strategy_bonus"] * 0.9)
                        self.logger.info(f"📉 Decreasing weight for {strategy_name} (performance: {performance_score:.2f})")

        except Exception as e:
            self.logger.error(f"Error in adaptive weight adjustment: {e}")

    fn get_portfolio_snapshot(self) -> Dict[String, Any]:
        """Get current portfolio state"""
        return {
            "total_capital": self.portfolio_state.total_capital,
            "available_capital": self.portfolio_state.available_capital,
            "allocated_capital": self.portfolio_state.allocated_capital,
            "flash_loan_used": self.portfolio_state.flash_loan_used,
            "flash_loan_limit": self.portfolio_state.flash_loan_limit,
            "open_positions": self.portfolio_state.open_positions,
            "leverage_ratio": self.portfolio_state.leverage_ratio,
            "last_update": self.portfolio_state.last_update
        }

    fn get_strategy_performance(self) -> Dict[String, StrategyMetrics]:
        """Get performance metrics for all strategies"""
        return self.strategy_metrics