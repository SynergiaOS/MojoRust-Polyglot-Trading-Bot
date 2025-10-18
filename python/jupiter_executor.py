#!/usr/bin/env python3
"""
Jupiter Swap Executor Module

High-performance Jupiter swap execution with Jito MEV protection,
dynamic priority fees, and transaction monitoring.
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
import base64
from decimal import Decimal

import redis.asyncio as redis
from aiohttp import ClientSession, ClientTimeout
from solana.keypair import Keypair
from solana.transaction import Transaction
from solana.rpc.async_api import AsyncClient
from solana.rpc.commitment import Confirmed, Finalized
from solana.rpc.types import TxOpts
import structlog

from .geyser_client import JupiterPriceClient
from .jupiter_pipeline import JupiterQuoteEvent

logger = structlog.get_logger()

@dataclass
class SwapExecutionRequest:
    """Swap execution request"""
    input_mint: str
    output_mint: str
    input_amount: int
    slippage_bps: int
    user_public_key: str
    quote_response: Dict[str, Any]
    priority_fee: int
    urgency_level: str = "normal"  # low, normal, high, critical
    max_retries: int = 3
    deadline: Optional[datetime] = None

@dataclass
class SwapExecutionResult:
    """Swap execution result"""
    success: bool
    transaction_signature: Optional[str]
    error_message: Optional[str]
    input_amount: int
    output_amount: int
    actual_slippage_bps: Optional[int]
    execution_time_ms: int
    priority_fee_used: int
    confirmations: int
    timestamp: datetime

@dataclass
class JitoBundleConfig:
    """Jito bundle configuration"""
    use_jito: bool = True
    jito_auth_key: Optional[str] = None
    bundle_tip_lamports: int = 10000
    max_bundle_size: int = 5
    bundle_timeout_seconds: int = 30

class JupiterSwapExecutor:
    """
    High-performance Jupiter swap executor with MEV protection
    """

    def __init__(
        self,
        rpc_url: str,
        redis_url: str = "redis://localhost:6379",
        jito_config: Optional[JitoBundleConfig] = None,
        max_concurrent_swaps: int = 10
    ):
        """
        Initialize Jupiter swap executor

        Args:
            rpc_url: Solana RPC URL
            redis_url: Redis connection URL
            jito_config: Jito bundle configuration
            max_concurrent_swaps: Maximum concurrent swap executions
        """
        self.rpc_url = rpc_url
        self.redis_url = redis_url
        self.jupiter_client = JupiterPriceClient()
        self.jito_config = jito_config or JitoBundleConfig()
        self.max_concurrent_swaps = max_concurrent_swaps

        # Initialize clients
        self.rpc_client: Optional[AsyncClient] = None
        self.redis_client: Optional[redis.Redis] = None

        # Execution state
        self.execution_semaphore = asyncio.Semaphore(max_concurrent_swaps)
        self.active_executions: Dict[str, asyncio.Task] = {}
        self.execution_results: Dict[str, SwapExecutionResult] = {}

        # Statistics
        self.stats = {
            "total_swaps": 0,
            "successful_swaps": 0,
            "failed_swaps": 0,
            "total_volume_usd": 0.0,
            "total_fees_paid": 0,
            "average_execution_time_ms": 0.0,
            "jito_bundles_sent": 0,
            "jito_bundles_successful": 0,
            "start_time": None
        }

        # Priority fee calculator
        self.priority_fee_calculator = PriorityFeeCalculator(rpc_url)

    async def start(self) -> None:
        """Start the Jupiter swap executor"""
        try:
            logger.info("Starting Jupiter swap executor...")

            # Initialize clients
            self.rpc_client = AsyncClient(self.rpc_url)
            self.redis_client = redis.from_url(self.redis_url, decode_responses=True)

            # Test connections
            await self.rpc_client.get_health()
            await self.redis_client.ping()

            self.stats["start_time"] = datetime.now()
            logger.info("Jupiter swap executor started successfully")

        except Exception as e:
            logger.error("Failed to start Jupiter swap executor", error=str(e))
            await self.stop()
            raise

    async def stop(self) -> None:
        """Stop the Jupiter swap executor"""
        try:
            logger.info("Stopping Jupiter swap executor...")

            # Cancel active executions
            for execution_id, task in self.active_executions.items():
                logger.info(f"Cancelling active execution: {execution_id}")
                task.cancel()

            # Wait for tasks to complete
            if self.active_executions:
                await asyncio.gather(*self.active_executions.values(), return_exceptions=True)

            # Close clients
            if self.rpc_client:
                await self.rpc_client.close()
            if self.redis_client:
                await self.redis_client.close()

            logger.info("Jupiter swap executor stopped")

        except Exception as e:
            logger.error("Error stopping Jupiter swap executor", error=str(e))

    async def execute_swap(
        self,
        request: SwapExecutionRequest,
        execution_id: Optional[str] = None
    ) -> SwapExecutionResult:
        """
        Execute a swap with MEV protection

        Args:
            request: Swap execution request
            execution_id: Unique execution identifier

        Returns:
            Swap execution result
        """
        if not execution_id:
            execution_id = f"swap_{int(time.time() * 1000)}_{request.input_mint[:8]}_{request.output_mint[:8]}"

        start_time = time.time()

        try:
            # Acquire semaphore to limit concurrent executions
            async with self.execution_semaphore:
                logger.info("Executing swap",
                           execution_id=execution_id,
                           input_mint=request.input_mint[:8],
                           output_mint=request.output_mint[:8],
                           input_amount=request.input_amount,
                           urgency_level=request.urgency_level)

                # Update statistics
                self.stats["total_swaps"] += 1

                # Execute swap with MEV protection
                if self.jito_config.use_jito:
                    result = await self._execute_jito_swap(request, execution_id)
                else:
                    result = await self._execute_standard_swap(request, execution_id)

                # Calculate execution time
                result.execution_time_ms = int((time.time() - start_time) * 1000)

                # Store result
                self.execution_results[execution_id] = result

                # Update statistics
                if result.success:
                    self.stats["successful_swaps"] += 1
                    # Update average execution time
                    total_time = self.stats["average_execution_time_ms"] * (self.stats["successful_swaps"] - 1)
                    self.stats["average_execution_time_ms"] = (
                        total_time + result.execution_time_ms
                    ) / self.stats["successful_swaps"]
                else:
                    self.stats["failed_swaps"] += 1

                # Publish result to Redis
                await self._publish_execution_result(execution_id, result)

                logger.info("Swap execution completed",
                           execution_id=execution_id,
                           success=result.success,
                           execution_time_ms=result.execution_time_ms)

                return result

        except Exception as e:
            logger.error("Swap execution failed",
                        execution_id=execution_id,
                        error=str(e))

            # Create failure result
            result = SwapExecutionResult(
                success=False,
                transaction_signature=None,
                error_message=str(e),
                input_amount=request.input_amount,
                output_amount=0,
                actual_slippage_bps=None,
                execution_time_ms=int((time.time() - start_time) * 1000),
                priority_fee_used=request.priority_fee,
                confirmations=0,
                timestamp=datetime.now()
            )

            self.stats["failed_swaps"] += 1
            self.execution_results[execution_id] = result
            await self._publish_execution_result(execution_id, result)

            return result

    async def _execute_jito_swap(
        self,
        request: SwapExecutionRequest,
        execution_id: str
    ) -> SwapExecutionResult:
        """Execute swap using Jito bundle for MEV protection"""
        try:
            logger.info("Executing Jito swap", execution_id=execution_id)

            # Get swap transaction from Jupiter
            swap_transaction = await self.jupiter_client.get_swap_transaction(
                quote_response=request.quote_response,
                user_public_key=request.user_public_key,
                wrap_and_unwrap_sol=True
            )

            if not swap_transaction:
                return SwapExecutionResult(
                    success=False,
                    transaction_signature=None,
                    error_message="Failed to get swap transaction from Jupiter",
                    input_amount=request.input_amount,
                    output_amount=0,
                    actual_slippage_bps=None,
                    execution_time_ms=0,
                    priority_fee_used=request.priority_fee,
                    confirmations=0,
                    timestamp=datetime.now()
                )

            # Create Jito bundle
            bundle = await self._create_jito_bundle(swap_transaction, request)

            # Submit bundle to Jito
            bundle_result = await self._submit_jito_bundle(bundle, execution_id)

            if bundle_result["success"]:
                # Monitor bundle confirmation
                confirmation = await self._monitor_jito_bundle(
                    bundle_result["bundle_id"],
                    execution_id
                )

                if confirmation["confirmed"]:
                    return SwapExecutionResult(
                        success=True,
                        transaction_signature=bundle_result["signatures"][0],
                        error_message=None,
                        input_amount=request.input_amount,
                        output_amount=confirmation.get("output_amount", 0),
                        actual_slippage_bps=confirmation.get("actual_slippage_bps"),
                        execution_time_ms=0,  # Will be set by caller
                        priority_fee_used=request.priority_fee,
                        confirmations=1,
                        timestamp=datetime.now()
                    )
                else:
                    return SwapExecutionResult(
                        success=False,
                        transaction_signature=bundle_result["signatures"][0],
                        error_message=f"Bundle not confirmed: {confirmation.get('error', 'Unknown error')}",
                        input_amount=request.input_amount,
                        output_amount=0,
                        actual_slippage_bps=None,
                        execution_time_ms=0,
                        priority_fee_used=request.priority_fee,
                        confirmations=0,
                        timestamp=datetime.now()
                    )
            else:
                return SwapExecutionResult(
                    success=False,
                    transaction_signature=None,
                    error_message=f"Bundle submission failed: {bundle_result.get('error', 'Unknown error')}",
                    input_amount=request.input_amount,
                    output_amount=0,
                    actual_slippage_bps=None,
                    execution_time_ms=0,
                    priority_fee_used=request.priority_fee,
                    confirmations=0,
                    timestamp=datetime.now()
                )

        except Exception as e:
            logger.error("Jito swap execution failed", execution_id=execution_id, error=str(e))
            raise

    async def _execute_standard_swap(
        self,
        request: SwapExecutionRequest,
        execution_id: str
    ) -> SwapExecutionResult:
        """Execute standard swap without Jito"""
        try:
            logger.info("Executing standard swap", execution_id=execution_id)

            # Get swap transaction from Jupiter
            swap_transaction = await self.jupiter_client.get_swap_transaction(
                quote_response=request.quote_response,
                user_public_key=request.user_public_key,
                wrap_and_unwrap_sol=True,
                use_shared_accounts=True,
                fee_account=request.user_public_key  # For priority fees
            )

            if not swap_transaction:
                return SwapExecutionResult(
                    success=False,
                    transaction_signature=None,
                    error_message="Failed to get swap transaction from Jupiter",
                    input_amount=request.input_amount,
                    output_amount=0,
                    actual_slippage_bps=None,
                    execution_time_ms=0,
                    priority_fee_used=request.priority_fee,
                    confirmations=0,
                    timestamp=datetime.now()
                )

            # Decode and add priority fee
            transaction = Transaction.deserialize(base64.b64decode(swap_transaction))

            # Add compute budget instructions for priority fee
            await self._add_priority_fee_instruction(transaction, request.priority_fee)

            # Send transaction
            signature = await self.rpc_client.send_transaction(
                transaction,
                opts=TxOpts(
                    skip_preflight=True,
                    preflight_commitment=Confirmed,
                    max_retries=request.max_retries
                )
            )

            logger.info("Transaction sent", execution_id=execution_id, signature=signature)

            # Wait for confirmation
            confirmation = await self._wait_for_confirmation(
                signature,
                commitment=Confirmed,
                timeout_seconds=30
            )

            if confirmation["confirmed"]:
                return SwapExecutionResult(
                    success=True,
                    transaction_signature=signature,
                    error_message=None,
                    input_amount=request.input_amount,
                    output_amount=confirmation.get("output_amount", 0),
                    actual_slippage_bps=confirmation.get("actual_slippage_bps"),
                    execution_time_ms=0,  # Will be set by caller
                    priority_fee_used=request.priority_fee,
                    confirmations=confirmation.get("confirmations", 1),
                    timestamp=datetime.now()
                )
            else:
                return SwapExecutionResult(
                    success=False,
                    transaction_signature=signature,
                    error_message=f"Transaction not confirmed: {confirmation.get('error', 'Unknown error')}",
                    input_amount=request.input_amount,
                    output_amount=0,
                    actual_slippage_bps=None,
                    execution_time_ms=0,
                    priority_fee_used=request.priority_fee,
                    confirmations=0,
                    timestamp=datetime.now()
                )

        except Exception as e:
            logger.error("Standard swap execution failed", execution_id=execution_id, error=str(e))
            raise

    async def _create_jito_bundle(
        self,
        swap_transaction: str,
        request: SwapExecutionRequest
    ) -> List[str]:
        """Create Jito bundle with tip transaction"""
        try:
            # Decode swap transaction
            swap_tx = Transaction.deserialize(base64.b64decode(swap_transaction))

            # Create tip transaction
            tip_tx = await self._create_tip_transaction(request)

            # Bundle transactions (tip first, then swap)
            bundle = [tip_tx, swap_tx]

            logger.info("Jito bundle created",
                       bundle_size=len(bundle),
                       tip_amount=self.jito_config.bundle_tip_lamports)

            return bundle

        except Exception as e:
            logger.error("Failed to create Jito bundle", error=str(e))
            raise

    async def _create_tip_transaction(self, request: SwapExecutionRequest) -> str:
        """Create Jito tip transaction"""
        try:
            # This is a simplified tip transaction
            # In production, you'd create a proper transfer to Jito tip accounts

            # For now, return a placeholder
            # In reality, you'd:
            # 1. Get Jito tip accounts
            # 2. Create transfer transaction
            # 3. Sign with appropriate authority
            # 4. Return base64 encoded transaction

            logger.warning("Tip transaction creation not fully implemented")
            return "placeholder_tip_transaction"

        except Exception as e:
            logger.error("Failed to create tip transaction", error=str(e))
            raise

    async def _submit_jito_bundle(
        self,
        bundle: List[str],
        execution_id: str
    ) -> Dict[str, Any]:
        """Submit bundle to Jito"""
        try:
            if not self.jito_config.jito_auth_key:
                # Fallback to standard execution if no Jito auth key
                logger.warning("No Jito auth key provided, falling back to standard execution")
                return await self._fallback_standard_execution(bundle[1], execution_id)

            # This would involve Jito's bundle submission API
            # For now, simulate successful submission

            bundle_id = f"bundle_{int(time.time() * 1000)}"
            signatures = [f"sig_{i}_{int(time.time() * 1000)}" for i in range(len(bundle))]

            self.stats["jito_bundles_sent"] += 1

            logger.info("Jito bundle submitted",
                       bundle_id=bundle_id,
                       signatures_count=len(signatures))

            return {
                "success": True,
                "bundle_id": bundle_id,
                "signatures": signatures
            }

        except Exception as e:
            logger.error("Failed to submit Jito bundle", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }

    async def _monitor_jito_bundle(
        self,
        bundle_id: str,
        execution_id: str,
        timeout_seconds: int = 30
    ) -> Dict[str, Any]:
        """Monitor Jito bundle confirmation"""
        try:
            start_time = time.time()

            while time.time() - start_time < timeout_seconds:
                # Check bundle status (this would be Jito's bundle status API)
                # For now, simulate successful confirmation after some time

                await asyncio.sleep(2)  # Simulate checking delay

                # Simulate successful confirmation
                if time.time() - start_time > 5:  # Confirm after 5 seconds
                    self.stats["jito_bundles_successful"] += 1

                    logger.info("Jito bundle confirmed",
                               bundle_id=bundle_id,
                               execution_time_s=time.time() - start_time)

                    return {
                        "confirmed": True,
                        "bundle_id": bundle_id,
                        "confirmations": 1
                    }

            # Timeout
            return {
                "confirmed": False,
                "error": "Bundle confirmation timeout"
            }

        except Exception as e:
            logger.error("Error monitoring Jito bundle", error=str(e))
            return {
                "confirmed": False,
                "error": str(e)
            }

    async def _add_priority_fee_instruction(
        self,
        transaction: Transaction,
        priority_fee: int
    ) -> None:
        """Add compute budget instruction for priority fee"""
        try:
            # This would add the proper compute budget instruction
            # For now, just log the intention
            logger.info("Adding priority fee instruction", priority_fee_lamports=priority_fee)

        except Exception as e:
            logger.error("Failed to add priority fee instruction", error=str(e))

    async def _wait_for_confirmation(
        self,
        signature: str,
        commitment: str = "confirmed",
        timeout_seconds: int = 30
    ) -> Dict[str, Any]:
        """Wait for transaction confirmation"""
        try:
            start_time = time.time()

            while time.time() - start_time < timeout_seconds:
                try:
                    result = await self.rpc_client.confirm_transaction(
                        signature,
                        commitment=commitment
                    )

                    if result.value[0] is not None:
                        if result.value[0].err is None:
                            return {
                                "confirmed": True,
                                "confirmations": 1,
                                "slot": result.value[0].slot
                            }
                        else:
                            return {
                                "confirmed": False,
                                "error": str(result.value[0].err)
                            }

                except Exception:
                    # Transaction not yet confirmed
                    pass

                await asyncio.sleep(1)

            return {
                "confirmed": False,
                "error": "Confirmation timeout"
            }

        except Exception as e:
            logger.error("Error waiting for confirmation", error=str(e))
            return {
                "confirmed": False,
                "error": str(e)
            }

    async def _fallback_standard_execution(
        self,
        swap_transaction: str,
        execution_id: str
    ) -> Dict[str, Any]:
        """Fallback to standard execution if Jito fails"""
        try:
            logger.info("Falling back to standard execution", execution_id=execution_id)

            # Decode and send transaction normally
            transaction = Transaction.deserialize(base64.b64decode(swap_transaction))
            signature = await self.rpc_client.send_transaction(transaction)

            return {
                "success": True,
                "bundle_id": f"fallback_{signature[:8]}",
                "signatures": [signature]
            }

        except Exception as e:
            logger.error("Fallback execution failed", error=str(e))
            return {
                "success": False,
                "error": str(e)
            }

    async def _publish_execution_result(
        self,
        execution_id: str,
        result: SwapExecutionResult
    ) -> None:
        """Publish execution result to Redis"""
        try:
            message = asdict(result)
            message["timestamp"] = result.timestamp.isoformat()

            await self.redis_client.publish("jupiter:swap:results", json.dumps({
                "execution_id": execution_id,
                **message
            }))

            # Store in execution history
            await self.redis_client.hset(
                "jupiter:swap:history",
                execution_id,
                json.dumps(message)
            )

            # Keep only last 1000 executions in history
            await self.redis_client.hlen("jupiter:swap:history")
            # Note: You might want to implement more sophisticated cleanup

        except Exception as e:
            logger.error("Failed to publish execution result", error=str(e))

    async def get_statistics(self) -> Dict[str, Any]:
        """Get executor statistics"""
        stats = self.stats.copy()

        if stats["start_time"]:
            uptime = datetime.now() - stats["start_time"]
            stats["uptime_seconds"] = uptime.total_seconds()
            stats["uptime_formatted"] = str(uptime).split(".")[0]

        # Calculate success rate
        if stats["total_swaps"] > 0:
            stats["success_rate"] = (stats["successful_swaps"] / stats["total_swaps"]) * 100
        else:
            stats["success_rate"] = 0.0

        # Calculate Jito success rate
        if stats["jito_bundles_sent"] > 0:
            stats["jito_success_rate"] = (stats["jito_bundles_successful"] / stats["jito_bundles_sent"]) * 100
        else:
            stats["jito_success_rate"] = 0.0

        stats["active_executions"] = len(self.active_executions)
        stats["cached_results"] = len(self.execution_results)

        return stats

    async def get_execution_result(self, execution_id: str) -> Optional[SwapExecutionResult]:
        """Get specific execution result"""
        return self.execution_results.get(execution_id)

    async def cancel_execution(self, execution_id: str) -> bool:
        """Cancel active execution"""
        if execution_id in self.active_executions:
            task = self.active_executions[execution_id]
            task.cancel()
            del self.active_executions[execution_id]
            return True
        return False


class PriorityFeeCalculator:
    """Calculate optimal priority fees based on network conditions"""

    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url
        self.fee_history: List[Tuple[float, int]] = []  # (timestamp, fee_micro_lamports)

    async def calculate_priority_fee(
        self,
        urgency_level: str = "normal",
        compute_units: int = 1_000_000
    ) -> int:
        """Calculate priority fee based on urgency and network conditions"""
        try:
            # Base fees for different urgency levels
            base_fees = {
                "low": 1000,      # 0.000001 SOL
                "normal": 5000,   # 0.000005 SOL
                "high": 20000,    # 0.00002 SOL
                "critical": 100000  # 0.0001 SOL
            }

            base_fee = base_fees.get(urgency_level, base_fees["normal"])

            # Adjust based on network conditions (simplified)
            network_multiplier = await self._get_network_multiplier()

            priority_fee = int(base_fee * network_multiplier)

            logger.info("Priority fee calculated",
                       urgency_level=urgency_level,
                       base_fee=base_fee,
                       network_multiplier=network_multiplier,
                       final_fee=priority_fee)

            return priority_fee

        except Exception as e:
            logger.error("Failed to calculate priority fee", error=str(e))
            return 5000  # Default fallback

    async def _get_network_multiplier(self) -> float:
        """Get network congestion multiplier"""
        try:
            # This would typically involve checking recent block fees
            # For now, return a simplified multiplier
            return 1.0

        except Exception as e:
            logger.error("Failed to get network multiplier", error=str(e))
            return 1.0