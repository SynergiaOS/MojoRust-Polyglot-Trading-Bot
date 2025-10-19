#!/usr/bin/env python3
"""
Manual Targeting FastAPI Service
Provides REST API for manual token targeting and sniper control
"""

import asyncio
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
from enum import Enum

import aiohttp
import aiofiles
import uvicorn
from fastapi import FastAPI, HTTPException, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import redis.asyncio as redis

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class TargetType(str, Enum):
    """Targeting strategy types"""
    SNIPE = "snipe"
    SWEEP = "sweep"
    ARBITRAGE = "arbitrage"
    FLASH_LOAN = "flash_loan"

class UrgencyLevel(str, Enum):
    """Urgency levels for targeting"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

@dataclass
class ManualTarget:
    """Manual targeting request"""
    id: str
    token_mint: str
    target_type: TargetType
    urgency_level: UrgencyLevel
    amount_sol: float
    slippage_bps: int
    max_price_impact: float
    target_price: Optional[float] = None
    description: Optional[str] = None
    created_at: datetime = None
    expires_at: Optional[datetime] = None
    status: str = "pending"  # pending, executing, completed, failed, cancelled

    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.utcnow()
        if self.expires_at is None:
            # Default expiry: 30 minutes from creation
            self.expires_at = self.created_at + timedelta(minutes=30)

class TargetRequest(BaseModel):
    """Target creation request"""
    token_mint: str = Field(..., description="Token mint address to target")
    target_type: TargetType = Field(..., description="Type of targeting strategy")
    urgency_level: UrgencyLevel = Field(..., description="Urgency level")
    amount_sol: float = Field(..., gt=0, le=5.0, description="Amount in SOL (max 5.0)")
    slippage_bps: int = Field(default=500, ge=0, le=5000, description="Slippage tolerance in basis points")
    max_price_impact: float = Field(default=0.05, ge=0, le=0.5, description="Maximum price impact")
    target_price: Optional[float] = Field(None, description="Target price for limit orders")
    description: Optional[str] = Field(None, description="Description of the targeting strategy")
    expiry_minutes: int = Field(default=30, ge=1, le=1440, description="Expiry time in minutes")

@dataclass
class TargetExecution:
    """Target execution result"""
    target_id: str
    success: bool
    execution_time_ms: int
    transaction_signature: Optional[str] = None
    profit_sol: Optional[float] = None
    fees_paid_sol: Optional[float] = None
    error_message: Optional[str] = None
    executed_at: datetime = None

    def __post_init__(self):
        if self.executed_at is None:
            self.executed_at = datetime.utcnow()

class ManualTargetingService:
    """Manual targeting service"""

    def __init__(self):
        self.app = FastAPI(
            title="Manual Targeting Service",
            description="REST API for manual token targeting and sniper control",
            version="1.0.0"
        )

        # CORS middleware
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

        # State
        self.active_targets: Dict[str, ManualTarget] = {}
        self.execution_history: List[TargetExecution] = []
        self.websocket_connections: List[WebSocket] = []
        self.redis_client: Optional[redis.Redis] = None

        # Setup routes
        self._setup_routes()

        # Background tasks
        self.cleanup_task: Optional[asyncio.Task] = None

    async def initialize(self):
        """Initialize the service"""
        try:
            # Connect to Redis
            redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
            self.redis_client = redis.from_url(redis_url)

            # Test connection
            await self.redis_client.ping()
            logger.info("Connected to Redis")

            # Start cleanup task
            self.cleanup_task = asyncio.create_task(self._cleanup_expired_targets())

            logger.info("Manual Targeting Service initialized successfully")

        except Exception as e:
            logger.error(f"Failed to initialize Manual Targeting Service: {e}")
            raise

    def _setup_routes(self):
        """Setup API routes"""

        @self.app.get("/health")
        async def health_check():
            """Health check endpoint"""
            try:
                if self.redis_client:
                    await self.redis_client.ping()
                return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}
            except Exception as e:
                logger.error(f"Health check failed: {e}")
                return JSONResponse(
                    status_code=503,
                    content={"status": "unhealthy", "error": str(e)}
                )

        @self.app.get("/targets", response_model=List[Dict])
        async def list_targets(
            status: Optional[str] = None,
            target_type: Optional[TargetType] = None
        ):
            """List all targets with optional filtering"""
            targets = []
            for target in self.active_targets.values():
                if status and target.status != status:
                    continue
                if target_type and target.target_type != target_type:
                    continue
                targets.append(asdict(target))
            return targets

        @self.app.post("/targets", response_model=Dict)
        async def create_target(request: TargetRequest, background_tasks: BackgroundTasks):
            """Create a new manual target"""
            try:
                # Validate token mint format
                if not self._is_valid_solana_address(request.token_mint):
                    raise HTTPException(status_code=400, detail="Invalid token mint address")

                # Generate target ID
                target_id = f"manual_{int(datetime.utcnow().timestamp() * 1000)}"

                # Create target
                target = ManualTarget(
                    id=target_id,
                    token_mint=request.token_mint,
                    target_type=request.target_type,
                    urgency_level=request.urgency_level,
                    amount_sol=request.amount_sol,
                    slippage_bps=request.slippage_bps,
                    max_price_impact=request.max_price_impact,
                    target_price=request.target_price,
                    description=request.description,
                    expires_at=datetime.utcnow() + timedelta(minutes=request.expiry_minutes)
                )

                # Store target
                self.active_targets[target_id] = target

                # Publish to Redis for orchestrator
                await self._publish_target_to_redis(target)

                # Start execution in background
                background_tasks.add_task(self._execute_target, target_id)

                logger.info(f"Created manual target: {target_id} for token {request.token_mint}")

                return {
                    "target_id": target_id,
                    "status": "created",
                    "target": asdict(target)
                }

            except Exception as e:
                logger.error(f"Failed to create target: {e}")
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.get("/targets/{target_id}", response_model=Dict)
        async def get_target(target_id: str):
            """Get target details"""
            target = self.active_targets.get(target_id)
            if not target:
                raise HTTPException(status_code=404, detail="Target not found")
            return asdict(target)

        @self.app.delete("/targets/{target_id}")
        async def cancel_target(target_id: str):
            """Cancel a target"""
            target = self.active_targets.get(target_id)
            if not target:
                raise HTTPException(status_code=404, detail="Target not found")

            if target.status not in ["pending", "executing"]:
                raise HTTPException(status_code=400, detail=f"Cannot cancel target in {target.status} status")

            target.status = "cancelled"

            # Publish cancellation to Redis
            await self._publish_target_cancellation(target_id)

            logger.info(f"Cancelled target: {target_id}")
            return {"status": "cancelled", "target_id": target_id}

        @self.app.get("/targets/{target_id}/executions")
        async def get_target_executions(target_id: str):
            """Get execution history for a target"""
            executions = [
                asdict(execution) for execution in self.execution_history
                if execution.target_id == target_id
            ]
            return {"target_id": target_id, "executions": executions}

        @self.app.get("/executions", response_model=List[Dict])
        async def list_executions(
            limit: int = 100,
            offset: int = 0,
            success_only: bool = False
        ):
            """List execution history"""
            executions = self.execution_history
            if success_only:
                executions = [e for e in executions if e.success]

            executions = executions[offset:offset + limit]
            return [asdict(execution) for execution in executions]

        @self.app.get("/stats")
        async def get_stats():
            """Get targeting statistics"""
            total_targets = len(self.active_targets)
            pending_targets = len([t for t in self.active_targets.values() if t.status == "pending"])
            executing_targets = len([t for t in self.active_targets.values() if t.status == "executing"])

            total_executions = len(self.execution_history)
            successful_executions = len([e for e in self.execution_history if e.success])
            success_rate = (successful_executions / total_executions * 100) if total_executions > 0 else 0

            total_profit = sum(e.profit_sol or 0 for e in self.execution_history if e.success)
            avg_execution_time = sum(e.execution_time_ms for e in self.execution_history) / len(self.execution_history) if self.execution_history else 0

            return {
                "targets": {
                    "total": total_targets,
                    "pending": pending_targets,
                    "executing": executing_targets
                },
                "executions": {
                    "total": total_executions,
                    "successful": successful_executions,
                    "success_rate": round(success_rate, 2),
                    "total_profit_sol": round(total_profit, 6),
                    "avg_execution_time_ms": round(avg_execution_time, 2)
                }
            }

        @self.app.websocket("/ws")
        async def websocket_endpoint(websocket: WebSocket):
            """WebSocket endpoint for real-time updates"""
            await websocket.accept()
            self.websocket_connections.append(websocket)

            try:
                while True:
                    await websocket.receive_text()
            except WebSocketDisconnect:
                self.websocket_connections.remove(websocket)

    async def _execute_target(self, target_id: str):
        """Execute a target"""
        target = self.active_targets.get(target_id)
        if not target:
            return

        if target.status != "pending":
            return

        try:
            target.status = "executing"
            await self._broadcast_target_update(target)

            # Prepare execution command for orchestrator
            command = {
                "command_type": "execute_manual_target",
                "target_id": target_id,
                "token_mint": target.token_mint,
                "target_type": target.target_type.value,
                "urgency_level": target.urgency_level.value,
                "amount_sol": target.amount_sol,
                "slippage_bps": target.slippage_bps,
                "max_price_impact": target.max_price_impact,
                "target_price": target.target_price,
                "timestamp": datetime.utcnow().isoformat()
            }

            # Publish execution command to Redis
            if self.redis_client:
                await self.redis_client.publish("manual_target_commands", json.dumps(command))

            # Wait for execution result (in production, this would be handled via Redis pub/sub)
            # For now, simulate execution
            await asyncio.sleep(2)  # Simulate execution time

            # Create execution result
            execution = TargetExecution(
                target_id=target_id,
                success=True,
                execution_time_ms=1500 + (hash(target_id) % 1000),  # Simulate varying execution times
                transaction_signature=f"manual_tx_{target_id}",
                profit_sol=0.01 + (hash(target_id) % 100) / 10000,  # Simulate profit
                fees_paid_sol=0.0001
            )

            self.execution_history.append(execution)
            target.status = "completed"

            # Broadcast updates
            await self._broadcast_target_update(target)
            await self._broadcast_execution_result(execution)

            logger.info(f"Successfully executed target: {target_id}")

        except Exception as e:
            logger.error(f"Failed to execute target {target_id}: {e}")
            target.status = "failed"

            execution = TargetExecution(
                target_id=target_id,
                success=False,
                execution_time_ms=0,
                error_message=str(e)
            )

            self.execution_history.append(execution)
            await self._broadcast_target_update(target)
            await self._broadcast_execution_result(execution)

    async def _publish_target_to_redis(self, target: ManualTarget):
        """Publish target to Redis for orchestrator"""
        if not self.redis_client:
            return

        event = {
            "event_type": "manual_target_created",
            "target": asdict(target),
            "timestamp": datetime.utcnow().isoformat()
        }

        await self.redis_client.publish("manual_target_events", json.dumps(event))
        await self.redis_client.set(f"manual_target:{target.id}", json.dumps(asdict(target)), ex=3600)  # 1 hour expiry

    async def _publish_target_cancellation(self, target_id: str):
        """Publish target cancellation to Redis"""
        if not self.redis_client:
            return

        event = {
            "event_type": "manual_target_cancelled",
            "target_id": target_id,
            "timestamp": datetime.utcnow().isoformat()
        }

        await self.redis_client.publish("manual_target_events", json.dumps(event))
        await self.redis_client.delete(f"manual_target:{target_id}")

    async def _broadcast_target_update(self, target: ManualTarget):
        """Broadcast target update via WebSocket"""
        message = {
            "type": "target_update",
            "target": asdict(target),
            "timestamp": datetime.utcnow().isoformat()
        }

        await self._broadcast_websocket_message(message)

    async def _broadcast_execution_result(self, execution: TargetExecution):
        """Broadcast execution result via WebSocket"""
        message = {
            "type": "execution_result",
            "execution": asdict(execution),
            "timestamp": datetime.utcnow().isoformat()
        }

        await self._broadcast_websocket_message(message)

    async def _broadcast_websocket_message(self, message: Dict):
        """Broadcast message to all WebSocket connections"""
        if not self.websocket_connections:
            return

        message_str = json.dumps(message)
        disconnected = []

        for websocket in self.websocket_connections:
            try:
                await websocket.send_text(message_str)
            except Exception:
                disconnected.append(websocket)

        # Remove disconnected websockets
        for websocket in disconnected:
            if websocket in self.websocket_connections:
                self.websocket_connections.remove(websocket)

    async def _cleanup_expired_targets(self):
        """Cleanup expired targets"""
        while True:
            try:
                now = datetime.utcnow()
                expired_targets = []

                for target_id, target in self.active_targets.items():
                    if target.expires_at and target.expires_at < now:
                        if target.status in ["pending", "executing"]:
                            target.status = "expired"
                            expired_targets.append(target)
                            await self._broadcast_target_update(target)

                # Remove expired targets from active list after some time
                for target in expired_targets:
                    if datetime.utcnow() - target.expires_at > timedelta(minutes=5):
                        self.active_targets.pop(target.id, None)

                await asyncio.sleep(60)  # Check every minute

            except Exception as e:
                logger.error(f"Error in cleanup task: {e}")
                await asyncio.sleep(60)

    def _is_valid_solana_address(self, address: str) -> bool:
        """Validate Solana address format"""
        try:
            # Basic validation - should be base58 encoded and appropriate length
            import base58
            decoded = base58.b58decode(address)
            return len(decoded) == 32
        except Exception:
            return False

# Global service instance
service = ManualTargetingService()

@app.on_event("startup")
async def startup_event():
    """Startup event handler"""
    await service.initialize()

@app.on_event("shutdown")
async def shutdown_event():
    """Shutdown event handler"""
    if service.cleanup_task:
        service.cleanup_task.cancel()

    if service.redis_client:
        await service.redis_client.close()

    logger.info("Manual Targeting Service shutdown complete")

# FastAPI app instance
app = service.app

if __name__ == "__main__":
    import os

    # Configure logging
    log_level = os.getenv("LOG_LEVEL", "info").lower()
    uvicorn.run(
        "manual_targeting_service:app",
        host="0.0.0.0",
        port=int(os.getenv("MANUAL_TARGETING_PORT", 8000)),
        log_level=log_level,
        reload=os.getenv("ENVIRONMENT") == "development"
    )