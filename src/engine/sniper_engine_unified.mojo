# =============================================================================
# Unified Sniper Engine (Memecoin)
# =============================================================================
#
# This module consolidates all sniper implementations into a unified engine
# that analyzes new tokens and generates flash loan-based sniping opportunities.
# It integrates security filters, profitability analysis, and flash loan simulation.
#
# Features:
# - Real-time token analysis from pool creation events
# - Security filters (LP burn, mint authority, holder distribution)
# - Flash loan profitability calculation
# - DragonflyDB integration for opportunity publishing
# - Dynamic blacklist management
# - Comprehensive metrics tracking

from time import now
from collections import Dict, List, Set
from math import min, max
from core.types import (
    TradingSignal, MarketData, TradingAction,
    SignalSource, Config, NewTokenEvent
)
from core.logger import get_main_logger
from data.jupiter_client import JupiterClient
from data.solana_client import SolanaClient
from strategies.flash_loan_ensemble import FlashLoanPatternSignal

# Struct for sniper analysis results
@value
struct SnipingDecision:
    approved: Bool
    confidence: Float
    reasoning: String
    filters_passed: List[String]
    filters_failed: List[String]
    risk_score: Float
    estimated_profit_sol: Float
    metadata: Dict[String, String]

# Struct for flash loan snipe opportunity
@value
struct FlashLoanSnipeOpportunity:
    token_mint: String
    pool_id: String
    creator: String
    initial_liquidity_sol: Float
    flash_loan_amount_sol: Float
    estimated_profit_sol: Float
    risk_score: Float
    confidence_score: Float
    timestamp: Int
    strategy_weights: Dict[String, Float]
    execution_plan: Dict[String, String]

# Metrics tracking for sniper engine
@value
struct SniperMetrics:
    total_analyzed: Int
    total_approved: Int
    total_rejected: Int
    average_analysis_time_ms: Float
    average_profit_sol: Float
    success_rate: Float
    last_update_time: Int

# Unified Sniper Engine
@value
struct UnifiedSniperEngine:
    var config: Config
    var dragonfly_client: PythonObject
    var jupiter_client: JupiterClient
    var solana_client: SolanaClient
    var blacklist: Set[String]
    var metrics: SniperMetrics
    var logger: PythonObject

    fn __init__(self, config: Config):
        self.config = config
        self.logger = get_main_logger()

        # Initialize DragonflyDB client
        import redis
        redis_url = config.dragonflydb.url
        self.dragonfly_client = redis.from_url(redis_url)

        # Initialize API clients
        self.jupiter_client = JupiterClient(config)
        self.solana_client = SolanaClient(config)

        # Initialize blacklist
        self.blacklist = set()

        # Initialize metrics
        self.metrics = SniperMetrics(
            total_analyzed=0,
            total_approved=0,
            total_rejected=0,
            average_analysis_time_ms=0.0,
            average_profit_sol=0.0,
            success_rate=0.0,
            last_update_time=now()
        )

        self.logger.info("🎯 Unified Sniper Engine initialized")
        self.logger.info(f"   Flash loan enabled: {config.sniper.memecoin.use_flash_loan}")
        self.logger.info(f"   Max flash loan: {config.sniper.memecoin.max_flash_loan_amount_sol} SOL")
        self.logger.info(f"   Min liquidity: {config.sniper.memecoin.filters.min_initial_liquidity_sol} SOL")

    fn analyze_new_token(self, event: NewTokenEvent) -> SnipingDecision:
        """
        Analyzes a new token from pool creation event and makes sniping decision.
        Applies security filters first, then profitability analysis.
        """
        analysis_start = now()
        self.logger.info(f"🔍 Analyzing new token: {event.token_mint}")

        # Initialize analysis results
        var filters_passed = []
        var filters_failed = []
        var confidence = 0.0
        var reasoning = ""
        var risk_score = 0.5  # Start with medium risk
        var estimated_profit = 0.0

        # === SECURITY FILTERS (Fast checks) ===

        # 1. Check if creator is blacklisted
        if self.blacklist.contains(event.creator):
            filters_failed.append("Creator blacklisted")
            reasoning += "Creator is blacklisted; "
            risk_score += 0.3
        else:
            filters_passed.append("Creator not blacklisted")
            confidence += 0.1

        # 2. Check mint authority is revoked
        try:
            mint_info = self.solana_client.get_mint_info(event.token_mint)
            if mint_info.mint_authority_revoked:
                filters_passed.append("Mint authority revoked")
                confidence += 0.2
            else:
                filters_failed.append("Mint authority not revoked")
                reasoning += "Mint authority not revoked; "
                risk_score += 0.2
        except:
            filters_failed.append("Failed to check mint authority")
            reasoning += "Could not verify mint authority; "
            risk_score += 0.1

        # 3. Check LP burn threshold (90% required)
        try:
            lp_info = self.solana_client.get_lp_info(event.pool_id)
            lp_burn_percentage = lp_info.lp_burned / lp_info.total_lp * 100.0

            if lp_burn_percentage >= self.config.sniper.memecoin.filters.lp_burn_threshold_bps / 100.0:
                filters_passed.append(f"LP burn: {lp_burn_percentage:.1f}%")
                confidence += 0.15
            else:
                filters_failed.append(f"LP burn too low: {lp_burn_percentage:.1f}%")
                reasoning += f"LP burn too low ({lp_burn_percentage:.1f}%); "
                risk_score += 0.25
        except:
            filters_failed.append("Failed to check LP burn")
            reasoning += "Could not verify LP burn; "
            risk_score += 0.15

        # 4. Check holder distribution (top 5 holders < 30%)
        try:
            holders = self.solana_client.get_token_holders(event.token_mint, 5)
            top5_percentage = sum(holders) / 100.0

            if top5_percentage <= self.config.sniper.memecoin.filters.max_top5_holder_percent:
                filters_passed.append(f"Holder distribution OK: {top5_percentage:.1f}%")
                confidence += 0.1
            else:
                filters_failed.append(f"Too concentrated: {top5_percentage:.1f}%")
                reasoning += f"Too concentrated ({top5_percentage:.1f}%); "
                risk_score += 0.2
        except:
            filters_failed.append("Failed to check holders")
            reasoning += "Could not verify holders; "
            risk_score += 0.1

        # 5. Check initial liquidity
        if event.initial_liquidity_sol >= self.config.sniper.memecoin.filters.min_initial_liquidity_sol:
            filters_passed.append(f"Liquidity: {event.initial_liquidity_sol} SOL")
            confidence += min(0.1, event.initial_liquidity_sol / 50000.0)
        else:
            filters_failed.append(f"Low liquidity: {event.initial_liquidity_sol} SOL")
            reasoning += f"Low liquidity ({event.initial_liquidity_sol} SOL); "
            risk_score += 0.2

        # 6. Check token age
        token_age_seconds = now() - event.creation_time
        if (token_age_seconds >= self.config.sniper.memecoin.filters.min_token_age_seconds and
            token_age_seconds <= self.config.sniper.memecoin.filters.max_token_age_hours * 3600):
            filters_passed.append(f"Token age: {token_age_seconds:.0f}s")
        else:
            filters_failed.append(f"Invalid token age: {token_age_seconds:.0f}s")
            reasoning += f"Invalid token age ({token_age_seconds:.0f}s); "
            risk_score += 0.1

        # === PROFITABILITY ANALYSIS (If time permits) ===

        var flash_loan_feasible = False

        # Only proceed with profitability if basic security checks pass
        if len(filters_failed) <= 2:  # Allow up to 2 security failures
            try:
                # Simulate flash loan snipe
                if self.config.sniper.memecoin.use_flash_loan:
                    flash_loan_result = self.calculate_flash_loan_snipe(event)
                    if flash_loan_result.estimated_profit_sol > 0:
                        estimated_profit = flash_loan_result.estimated_profit_sol
                        flash_loan_feasible = True

                        # Boost confidence based on profit
                        profit_multiplier = estimated_profit / self.config.sniper.memecoin.target_profit_multiplier
                        confidence += min(0.2, profit_multiplier * 0.1)

                        filters_passed.append(f"Flash loan profit: {estimated_profit:.4f} SOL")

                        # Check if profit meets minimum threshold
                        min_profit = self.config.sniper.memecoin.target_profit_multiplier * 0.0003  # Save fee
                        if estimated_profit >= min_profit:
                            filters_passed.append("Profit threshold met")
                            confidence += 0.1
                        else:
                            filters_failed.append(f"Profit too low: {estimated_profit:.4f} SOL")
                            reasoning += f"Profit too low ({estimated_profit:.4f} SOL); "
                else:
                    # Regular swap simulation
                    swap_result = self.jupiter_client.simulate_swap(
                        "So11111111111111111111111111111111111111112",  # SOL
                        event.token_mint,
                        1.0  # 1 SOL test
                    )
                    if swap_result and swap_result.estimated_output > 0:
                        estimated_profit = swap_result.estimated_output - 1.0
                        if estimated_profit > 0:
                            filters_passed.append(f"Swap profit: {estimated_profit:.4f} SOL")
                            confidence += 0.05

            except:
                filters_failed.append("Profit simulation failed")
                reasoning += "Profit simulation failed; "
                risk_score += 0.1

        # === FINAL DECISION ===

        # Calculate final confidence (clamp between 0 and 1)
        confidence = max(0.0, min(1.0, confidence))

        # Calculate final risk score (clamp between 0 and 1)
        risk_score = max(0.0, min(1.0, risk_score))

        # Decision logic
        var approved = False

        # Must pass basic security requirements
        security_passed = len(filters_failed) <= 2 and "Mint authority not revoked" not in filters_failed

        # Must have positive profit if flash loan enabled
        profit_requirement = not self.config.sniper.memecoin.use_flash_loan or estimated_profit > 0

        # Minimum confidence threshold
        confidence_requirement = confidence >= 0.3

        # Maximum risk threshold
        risk_requirement = risk_score <= 0.7

        if security_passed and profit_requirement and confidence_requirement and risk_requirement:
            approved = True
            reasoning = "APPROVED: " + reasoning if reasoning else "APPROVED: All checks passed"
        else:
            reasoning = "REJECTED: " + reasoning if reasoning else "REJECTED: Security or profit requirements not met"

        # Update metrics
        self.metrics.total_analyzed += 1
        if approved:
            self.metrics.total_approved += 1
        else:
            self.metrics.total_rejected += 1

        # Update averages
        analysis_time = (now() - analysis_start) * 1000  # Convert to ms
        self.metrics.average_analysis_time_ms = (
            self.metrics.average_analysis_time_ms * (self.metrics.total_analyzed - 1) + analysis_time
        ) / self.metrics.total_analyzed

        if approved and estimated_profit > 0:
            self.metrics.average_profit_sol = (
                self.metrics.average_profit_sol * (self.metrics.total_approved - 1) + estimated_profit
            ) / self.metrics.total_approved

        self.metrics.success_rate = self.metrics.total_approved as Float / self.metrics.total_analyzed as Float
        self.metrics.last_update_time = int(time())

        # Create decision object
        decision = SnipingDecision(
            approved=approved,
            confidence=confidence,
            reasoning=reasoning,
            filters_passed=filters_passed,
            filters_failed=filters_failed,
            risk_score=risk_score,
            estimated_profit_sol=estimated_profit,
            metadata={
                "analysis_time_ms": str(analysis_time),
                "flash_loan_feasible": str(flash_loan_feasible),
                "creator": event.creator,
                "pool_id": event.pool_id,
                "initial_liquidity": str(event.initial_liquidity_sol)
            }
        )

        # Log result
        if approved:
            self.logger.info(f"✅ APPROVED {event.token_mint}: confidence={confidence:.2f}, profit={estimated_profit:.4f} SOL")
        else:
            self.logger.debug(f"❌ REJECTED {event.token_mint}: {reasoning}")

        # Publish approved opportunities to orchestrator queue
        if approved:
            self.publish_opportunity_to_orchestrator(decision, event)

        return decision

    fn calculate_flash_loan_snipe(self, event: NewTokenEvent) -> FlashLoanSnipeOpportunity:
        """
        Calculates flash loan sniping opportunity for a new token.
        Simulates: borrow SOL → buy token → immediately sell token → repay loan
        """
        # Determine optimal flash loan amount based on liquidity
        max_loan = min(
            self.config.sniper.memecoin.max_flash_loan_amount_sol,
            event.initial_liquidity_sol * 0.5  # Don't use more than 50% of liquidity
        )

        # Start with minimum profitable amount
        optimal_amount = max(0.1, max_loan * 0.1)

        # Simulate buy transaction
        buy_result = self.jupiter_client.simulate_swap(
            "So11111111111111111111111111111111111111112",  # SOL
            event.token_mint,
            optimal_amount
        )

        if not buy_result or buy_result.estimated_output <= 0:
            raise ValueError("Failed to simulate buy transaction")

        tokens_received = buy_result.estimated_output

        # Simulate sell transaction
        sell_result = self.jupiter_client.simulate_swap(
            event.token_mint,
            "So11111111111111111111111111111111111111112",  # SOL
            tokens_received
        )

        if not sell_result or sell_result.estimated_output <= 0:
            raise ValueError("Failed to simulate sell transaction")

        sol_received = sell_result.estimated_output

        # Calculate costs
        flash_loan_fee = optimal_amount * 0.0003  # Save protocol fee
        jupiter_fees_buy = buy_result.fee_amount if hasattr(buy_result, "fee_amount") else 0.0
        jupiter_fees_sell = sell_result.fee_amount if hasattr(sell_result, "fee_amount") else 0.0
        total_fees = flash_loan_fee + jupiter_fees_buy + jupiter_fees_sell

        # Calculate net profit
        gross_profit = sol_received - optimal_amount
        net_profit = gross_profit - total_fees

        # Calculate risk and confidence scores
        liquidity_score = min(1.0, event.initial_liquidity_sol / 10000.0)
        profit_score = min(1.0, net_profit / 0.1)  # Normalize to 0.1 SOL as max
        risk_score = 1.0 - liquidity_score * 0.5 - profit_score * 0.5

        confidence_score = (liquidity_score + profit_score) / 2.0

        # Strategy weights for ensemble
        strategy_weights = {
            "sniper_momentum": 0.4,
            "liquidity_mining": 0.3,
            "technical_patterns": 0.2,
            "social_sentiment": 0.1
        }

        # Execution plan
        execution_plan = {
            "flash_loan_protocol": "save",
            "borrow_amount": str(optimal_amount),
            "buy_dex": buy_result.dex_name if hasattr(buy_result, "dex_name") else "jupiter",
            "sell_dex": sell_result.dex_name if hasattr(sell_result, "dex_name") else "jupiter",
            "max_slippage": str(self.config.sniper.memecoin.simulation.max_slippage_bps),
            "use_jito_bundle": "true"
        }

        return FlashLoanSnipeOpportunity(
            token_mint=event.token_mint,
            pool_id=event.pool_id,
            creator=event.creator,
            initial_liquidity_sol=event.initial_liquidity_sol,
            flash_loan_amount_sol=optimal_amount,
            estimated_profit_sol=net_profit,
            risk_score=risk_score,
            confidence_score=confidence_score,
            timestamp=now(),
            strategy_weights=strategy_weights,
            execution_plan=execution_plan
        )

    fn create_opportunity(self, decision: SnipingDecision, event: NewTokenEvent) -> FlashLoanPatternSignal:
        """
        Creates a unified opportunity object for the orchestrator.
        """
        if not decision.approved:
            raise ValueError("Cannot create opportunity from rejected decision")

        # Calculate overall score
        profit_score = decision.estimated_profit_sol / 0.1  # Normalize to 0.1 SOL
        risk_penalty = decision.risk_score * 0.3
        confidence_bonus = decision.confidence * 0.2

        overall_score = min(100.0, max(0.0, (profit_score - risk_penalty + confidence_bonus) * 100))

        # Create pattern signal for ensemble
        return FlashLoanPatternSignal(
            token=event.token_mint,
            signal_type="flash_loan_snipe",
            confidence=decision.confidence,
            expected_return=decision.estimated_profit_sol,
            risk_score=decision.risk_score,
            timestamp=now(),
            metadata=decision.metadata
        )

    fn update_blacklist(self):
        """
        Updates the creator blacklist from DragonflyDB.
        Subscribes to blacklist updates and maintains in-memory cache.
        """
        try:
            # Get current blacklist from DragonflyDB
            blacklist_key = "blacklist:creators"
            blacklist_entries = self.dragonfly_client.smembers(blacklist_key)

            # Update in-memory blacklist
            self.blacklist = set(blacklist_entries)

            if len(blacklist_entries) > 0:
                self.logger.info(f"📋 Updated blacklist with {len(blacklist_entries)} creators")

        except Exception as e:
            self.logger.error(f"Failed to update blacklist: {e}")

    def get_metrics(self) -> SniperMetrics:
        """
        Returns current sniper metrics.
        """
        return self.metrics

    fn reset_metrics(self):
        """
        Resets all metrics to initial values.
        """
        self.metrics = SniperMetrics(
            total_analyzed=0,
            total_approved=0,
            total_rejected=0,
            average_analysis_time_ms=0.0,
            average_profit_sol=0.0,
            success_rate=0.0,
            last_update_time=now()
        )
        self.logger.info("📊 Sniper metrics reset")

    fn publish_opportunity_to_orchestrator(self, decision: SnipingDecision, event: NewTokenEvent) -> Bool:
        """
        Publishes approved sniping opportunities to the orchestrator opportunity queue.
        Returns True if successfully published, False otherwise.
        """
        if not decision.approved:
            return False

        try:
            # Create orchestrator opportunity object
            orchestrator_opportunity = {
                "id": f"snipe_{event.token_mint[:8]}_{now()}",
                "strategy_type": "sniper_momentum",
                "token": event.token_mint,
                "confidence": decision.confidence,
                "expected_return": decision.estimated_profit_sol,
                "risk_score": decision.risk_score,
                "required_capital": max(0.1, decision.estimated_profit_sol * 20),  # 5% profit expectation
                "flash_loan_amount": max(0.1, decision.estimated_profit_sol * 19),
                "timestamp": now(),
                "ttl_seconds": 30,  # Sniping opportunities expire quickly
                "metadata": {
                    "creator": event.creator,
                    "pool_id": event.pool_id,
                    "initial_liquidity": str(event.initial_liquidity_sol),
                    "filters_passed": ",".join(decision.filters_passed),
                    "filters_failed": ",".join(decision.filters_failed),
                    "reasoning": decision.reasoning,
                    "analysis_time_ms": decision.metadata.get("analysis_time_ms", "0"),
                    "flash_loan_feasible": decision.metadata.get("flash_loan_feasible", "false"),
                    "opportunity_type": "memecoin_snipe"
                }
            }

            # Calculate opportunity score for prioritization
            profit_score = decision.estimated_profit_sol * 1000.0
            confidence_bonus = decision.confidence * 100.0
            risk_penalty = decision.risk_score * 50.0
            total_score = profit_score + confidence_bonus - risk_penalty

            # Add to orchestrator opportunity_queue sorted set
            # Note: JSON serialization will be handled by the Python FFI layer
            self.dragonfly_client.zadd("opportunity_queue", {orchestrator_opportunity: total_score})

            # Also publish to sniper_opportunities channel for monitoring
            self.dragonfly_client.publish("sniper_opportunities", orchestrator_opportunity)

            self.logger.info(f"🎯 Published sniping opportunity to orchestrator: {event.token_mint[:8]}..., score: {total_score:.2f}")
            return True

        except Exception as e:
            self.logger.error(f"Failed to publish sniping opportunity to orchestrator: {e}")
            return False