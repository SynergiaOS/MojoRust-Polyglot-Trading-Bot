#!/usr/bin/env python3
"""
Flash Loan Integration Pipeline
Bridges Mojo sniper signals with Rust flash loan execution
"""

import asyncio
import json
import logging
import time
from typing import Dict, Any, Optional, List
from dataclasses import dataclass, asdict
from decimal import Decimal

import redis.asyncio as redis
from .jupiter_executor import JupiterExecutor
from .solend_executor import SolendExecutor
from .save_executor import SaveExecutor

logger = logging.getLogger(__name__)

@dataclass
class FlashLoanSignal:
    """Flash loan signal from Mojo sniper engine"""
    action: str  # "buy", "sell", "hold", "flash_loan"
    amount: int  # Amount in lamports
    token: str  # Token symbol
    token_mint: str  # Solana token mint address
    confidence: float  # 0.0 - 1.0
    expected_profit: float  # Expected profit percentage
    execution_deadline: int  # Unix timestamp
    preferred_provider: str  # "save", "solend", "mango_v4"
    slippage_bps: int  # Slippage tolerance in basis points
    urgency_level: str  # "high", "medium", "low"
    risk_score: float  # 0.0 - 1.0
    liquidity_score: float  # 0.0 - 1.0
    social_score: float  # 0.0 - 1.0
    quote: Dict[str, Any]  # Jupiter quote data
    market_data: Dict[str, Any]  # Additional market data

@dataclass
class FlashLoanRequest:
    """Flash loan request for Rust execution"""
    provider: str
    token_mint: str
    amount: int
    slippage_bps: int
    urgency_level: str
    expected_profit: float
    confidence: float
    risk_score: float
    market_data: Dict[str, Any]

@dataclass
class FlashLoanResult:
    """Flash loan execution result from Rust"""
    success: bool
    transaction_id: str
    execution_time_ms: int
    actual_amount_out: int
    fees_paid: int
    error_message: Optional[str] = None

class FlashLoanPipeline:
    """
    Integration pipeline for flash loan execution
    Processes Mojo signals and routes to optimal Rust flash loan providers
    """

    def __init__(self, redis_url: str = "redis://localhost:6379"):
        self.redis_url = redis_url
        self.redis_client: Optional[redis.Redis] = None

        # Initialize executors
        self.jupiter_executor = JupiterExecutor()
        self.save_executor = SaveExecutor()
        self.solend_executor = SolendExecutor()

        # Performance tracking
        self.signals_processed = 0
        self.flash_loans_executed = 0
        self.successful_executions = 0
        self.total_profit = 0.0

    async def start(self):
        """Start the flash loan pipeline"""
        logger.info("Starting Flash Loan Integration Pipeline")

        # Connect to Redis
        try:
            self.redis_client = redis.from_url(self.redis_url)
            await self.redis_client.ping()
            logger.info("Connected to Redis")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise

        # Start signal processing
        await self._start_signal_processor()

    async def stop(self):
        """Stop the flash loan pipeline"""
        logger.info("Stopping Flash Loan Integration Pipeline")

        if self.redis_client:
            await self.redis_client.close()

        logger.info(f"Pipeline stats: {self.signals_processed} signals processed, "
                   f"{self.flash_loans_executed} flash loans executed, "
                   f"{self.successful_executions} successful, "
                   f"total profit: ${self.total_profit:.2f}")

    async def _start_signal_processor(self):
        """Process signals from Mojo sniper engine"""
        logger.info("Starting signal processor")

        while True:
            try:
                # Get signal from Redis queue
                signal_data = await self.redis_client.blpop("mojo_sniper_signals", timeout=5)

                if signal_data:
                    _, signal_json = signal_data
                    signal = FlashLoanSignal(**json.loads(signal_json))

                    await self._process_signal(signal)
                    self.signals_processed += 1

            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"Error processing signal: {e}")
                await asyncio.sleep(1)

    async def _process_signal(self, signal: FlashLoanSignal):
        """Process individual sniper signal"""
        logger.info(f"Processing signal: {signal.action} for {signal.token} "
                   f"(confidence: {signal.confidence:.3f}, profit: {signal.expected_profit:.2f}%)")

        # Only process flash loan or buy signals with high confidence
        if signal.action not in ["flash_loan", "buy"]:
            logger.debug(f"Ignoring signal action: {signal.action}")
            return

        if signal.confidence < 0.7:
            logger.debug(f"Ignoring low confidence signal: {signal.confidence}")
            return

        # Check deadline
        if time.time() > signal.execution_deadline / 1000:
            logger.warning(f"Signal expired: {time.time()} > {signal.execution_deadline / 1000}")
            return

        # Determine if we should use flash loans
        use_flash_loan = (
            signal.action == "flash_loan" or
            (signal.confidence >= 0.85 and signal.expected_profit >= 2.0)
        )

        if use_flash_loan:
            await self._execute_flash_loan(signal)
        else:
            await self._execute_regular_trade(signal)

    async def _execute_flash_loan(self, signal: FlashLoanSignal):
        """Execute flash loan trade"""
        logger.info(f"Executing flash loan for {signal.token} using {signal.preferred_provider}")

        try:
            # Create flash loan request
            request = FlashLoanRequest(
                provider=signal.preferred_provider,
                token_mint=signal.token_mint,
                amount=signal.amount,
                slippage_bps=signal.slippage_bps,
                urgency_level=signal.urgency_level,
                expected_profit=signal.expected_profit,
                confidence=signal.confidence,
                risk_score=signal.risk_score,
                market_data=signal.market_data
            )

            # Route to appropriate provider
            result = await self._route_flash_loan(request)

            if result.success:
                self.flash_loans_executed += 1
                self.successful_executions += 1
                self.total_profit += signal.expected_profit

                logger.info(f"Flash loan successful: {result.transaction_id} "
                           f"(profit: ${signal.expected_profit:.2f}, time: {result.execution_time_ms}ms)")
            else:
                logger.error(f"Flash loan failed: {result.error_message}")

            # Publish result
            await self._publish_result("flash_loan", signal, result)

        except Exception as e:
            logger.error(f"Error executing flash loan: {e}")

            # Publish error result
            error_result = FlashLoanResult(
                success=False,
                transaction_id="",
                execution_time_ms=0,
                actual_amount_out=0,
                fees_paid=0,
                error_message=str(e)
            )
            await self._publish_result("flash_loan", signal, error_result)

    async def _execute_regular_trade(self, signal: FlashLoanSignal):
        """Execute regular trade without flash loans"""
        logger.info(f"Executing regular trade for {signal.token}")

        try:
            # Execute Jupiter swap
            result = await self.jupiter_executor.execute_swap(
                input_mint="So11111111111111111111111111111111111111112",  # WSOL
                output_mint=signal.token_mint,
                amount=signal.amount,
                slippage_bps=signal.slippage_bps
            )

            if result.get("success", False):
                logger.info(f"Regular trade successful: {result.get('signature', 'unknown')}")
            else:
                logger.error(f"Regular trade failed: {result.get('error', 'unknown')}")

            # Publish result
            await self._publish_result("regular_trade", signal,
                                      FlashLoanResult(
                                          success=result.get("success", False),
                                          transaction_id=result.get("signature", ""),
                                          execution_time_ms=result.get("execution_time_ms", 0),
                                          actual_amount_out=result.get("out_amount", 0),
                                          fees_paid=result.get("fees", 0),
                                          error_message=result.get("error")
                                      ))

        except Exception as e:
            logger.error(f"Error executing regular trade: {e}")

    async def _route_flash_loan(self, request: FlashLoanRequest) -> FlashLoanResult:
        """Route flash loan request to optimal provider"""

        # Select provider based on amount and preference
        if request.amount <= 5_000_000_000:  # <= 5 SOL
            preferred_provider = "save"
        elif request.amount <= 50_000_000_000:  # <= 50 SOL
            preferred_provider = "solend"
        else:
            preferred_provider = "mango_v4"

        # Use requested provider if it can handle the amount
        if request.provider in ["save", "solend", "mango_v4"]:
            preferred_provider = request.provider

        # Execute with selected provider
        if preferred_provider == "save":
            return await self.save_executor.execute_flash_loan(request)
        elif preferred_provider == "solend":
            return await self.solend_executor.execute_flash_loan(request)
        elif preferred_provider == "mango_v4":
            # Mango V4 not implemented yet, fallback to Solend
            logger.warning("Mango V4 not implemented, using Solend as fallback")
            return await self.solend_executor.execute_flash_loan(request)
        else:
            raise ValueError(f"Unknown provider: {preferred_provider}")

    async def _publish_result(self, trade_type: str, signal: FlashLoanSignal, result: FlashLoanResult):
        """Publish execution result to Redis"""
        try:
            result_data = {
                "trade_type": trade_type,
                "signal": asdict(signal),
                "result": asdict(result),
                "timestamp": int(time.time() * 1000)
            }

            await self.redis_client.lpush("flash_loan_results", json.dumps(result_data))
            await self.redis_client.publish("flash_loan_events", json.dumps(result_data))

        except Exception as e:
            logger.error(f"Error publishing result: {e}")

    async def get_pipeline_stats(self) -> Dict[str, Any]:
        """Get pipeline performance statistics"""
        success_rate = (
            self.successful_executions / self.flash_loans_executed
            if self.flash_loans_executed > 0 else 0.0
        )

        return {
            "signals_processed": self.signals_processed,
            "flash_loans_executed": self.flash_loans_executed,
            "successful_executions": self.successful_executions,
            "success_rate": success_rate,
            "total_profit": self.total_profit,
            "average_profit_per_trade": (
                self.total_profit / self.successful_executions
                if self.successful_executions > 0 else 0.0
            )
        }

# Utility functions for integration with Mojo
def create_flash_loan_signal(mojo_signal: Dict[str, Any]) -> FlashLoanSignal:
    """Create FlashLoanSignal from Mojo signal data"""
    return FlashLoanSignal(
        action=mojo_signal.get("action", "hold"),
        amount=mojo_signal.get("amount", 0),
        token=mojo_signal.get("token", ""),
        token_mint=mojo_signal.get("token_mint", ""),
        confidence=mojo_signal.get("confidence", 0.0),
        expected_profit=mojo_signal.get("expected_profit", 0.0),
        execution_deadline=mojo_signal.get("execution_deadline", 0),
        preferred_provider=mojo_signal.get("preferred_provider", "save"),
        slippage_bps=mojo_signal.get("slippage_bps", 50),
        urgency_level=mojo_signal.get("urgency_level", "medium"),
        risk_score=mojo_signal.get("risk_score", 0.0),
        liquidity_score=mojo_signal.get("liquidity_score", 0.0),
        social_score=mojo_signal.get("social_score", 0.0),
        quote=mojo_signal.get("quote", {}),
        market_data=mojo_signal.get("market_data", {})
    )

async def publish_mojo_signal(redis_client: redis.Redis, signal: FlashLoanSignal):
    """Publish Mojo signal to Redis for processing"""
    signal_json = json.dumps(asdict(signal))
    await redis_client.lpush("mojo_sniper_signals", signal_json)
    await redis_client.publish("mojo_signals", signal_json)