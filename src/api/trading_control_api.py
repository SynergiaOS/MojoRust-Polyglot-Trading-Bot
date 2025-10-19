#!/usr/bin/env python3
"""
MojoRust Trading Control API

Comprehensive trading control system providing real-time management
of the algorithmic trading bot with REST API and WebSocket support.

Features:
- Start/Stop/Pause/Resume trading operations
- Real-time status monitoring via WebSocket
- Strategy switching and parameter adjustment
- Risk management controls
- Manual trading capabilities
- Emergency stop functionality
"""

import asyncio
import json
import logging
import os
import time
import uuid
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Union
from dataclasses import dataclass, asdict
from enum import Enum
import signal
import sys

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
import redis.asyncio as aioredis
import toml
from prometheus_client import Counter, Gauge, Histogram

# Add src to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

from src.orchestration.task_pool_manager import TaskPoolManager
from src.control.trading_controller import TradingController
from src.control.strategy_manager import StrategyManager
from src.control.risk_controller import RiskController

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Enums
class TradingStatus(str, Enum):
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    PAUSING = "pausing"
    PAUSED = "paused"
    STOPPING = "stopping"
    EMERGENCY_STOPPED = "emergency_stopped"

class ExecutionMode(str, Enum):
    PAPER = "paper"
    LIVE = "live"

class TradingStrategy(str, Enum):
    ENHANCED_RSI = "enhanced_rsi"
    MEAN_REVERSION = "mean_reversion"
    MOMENTUM = "momentum"
    ARBITRAGE = "arbitrage"
    FLASH_LOAN = "flash_loan"

# Pydantic Models
@dataclass
class TradingConfig:
    mode: ExecutionMode
    strategy: TradingStrategy
    initial_capital: float
    max_position_size: float
    max_drawdown: float
    cycle_interval: float

    def to_dict(self):
        return asdict(self)

class StartTradingRequest(BaseModel):
    mode: ExecutionMode = ExecutionMode.PAPER
    strategy: TradingStrategy = TradingStrategy.ENHANCED_RSI
    capital: float = Field(default=1.0, gt=0, le=1000)
    max_position_size: float = Field(default=0.1, gt=0, le=1.0)
    max_drawdown: float = Field(default=0.15, gt=0, le=0.5)
    cycle_interval: float = Field(default=1.0, gt=0.1, le=60.0)

class UpdateParamsRequest(BaseModel):
    max_position_size: Optional[float] = Field(None, gt=0, le=1.0)
    max_drawdown: Optional[float] = Field(None, gt=0, le=0.5)
    cycle_interval: Optional[float] = Field(None, gt=0.1, le=60.0)
    kelly_fraction: Optional[float] = Field(None, gt=0, le=1.0)

class ManualTradeRequest(BaseModel):
    token_address: str
    action: str = Field(..., regex="^(buy|sell)$")
    amount_sol: float = Field(..., gt=0)
    max_slippage: float = Field(default=0.05, gt=0, le=0.2)

class RiskLimitsRequest(BaseModel):
    max_daily_loss: Optional[float] = Field(None, gt=0)
    max_position_risk: Optional[float] = Field(None, gt=0, le=0.1)
    stop_loss_percentage: Optional[float] = Field(None, gt=0, le=0.5)
    emergency_stop_enabled: Optional[bool] = None

class TradingControlAPI:
    """
    Main Trading Control API providing comprehensive trading management.
    """

    def __init__(self):
        self.app = FastAPI(
            title="MojoRust Trading Control API",
            description="Comprehensive control system for algorithmic trading bot",
            version="1.0.0",
            docs_url="/docs",
            redoc_url="/redoc"
        )

        # Configuration
        self.port = int(os.getenv('TRADING_CONTROL_PORT', '8083'))
        self.redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
        self.config_path = os.getenv('TRADING_CONFIG_PATH', 'config/trading.toml')

        # State management
        self.trading_status = TradingStatus.STOPPED
        self.trading_config: Optional[TradingConfig] = None
        self.start_time: Optional[datetime] = None
        self.last_trade_time: Optional[datetime] = None

        # Controllers
        self.task_pool_manager: Optional[TaskPoolManager] = None
        self.trading_controller: Optional[TradingController] = None
        self.strategy_manager: Optional[StrategyManager] = None
        self.risk_controller: Optional[RiskController] = None

        # WebSocket connections
        self.active_connections: List[WebSocket] = []

        # Redis and monitoring
        self.redis_client: Optional[aioredis.Redis] = None

        # Prometheus metrics
        self.setup_metrics()

        # Setup middleware and routes
        self.setup_middleware()
        self.setup_routes()

        # Setup signal handlers for graceful shutdown
        self.setup_signal_handlers()

        logger.info("Trading Control API initialized")

    def setup_metrics(self):
        """Setup Prometheus metrics"""
        self.trading_control_requests = Counter(
            'trading_control_requests_total',
            'Total trading control requests',
            ['endpoint', 'method', 'status']
        )

        self.trading_status_gauge = Gauge(
            'trading_status',
            'Current trading status (0=stopped, 1=running, 2=paused, 3=emergency_stopped)'
        )

        self.portfolio_value_gauge = Gauge(
            'portfolio_value_sol',
            'Current portfolio value in SOL'
        )

        self.control_latency = Histogram(
            'control_operation_duration_seconds',
            'Control operation duration in seconds',
            ['operation']
        )

    def setup_middleware(self):
        """Setup FastAPI middleware"""
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],  # Configure appropriately for production
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        self.app.add_middleware(GZipMiddleware, minimum_size=1000)

    def setup_signal_handlers(self):
        """Setup signal handlers for graceful shutdown"""
        def signal_handler(signum, frame):
            logger.info(f"Received signal {signum}, initiating graceful shutdown...")
            asyncio.create_task(self.emergency_stop())
            asyncio.create_task(self.shutdown())

        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)

    async def initialize(self):
        """Initialize async components"""
        try:
            # Initialize Redis connection
            self.redis_client = aioredis.from_url(self.redis_url)
            await self.redis_client.ping()
            logger.info(f"Connected to Redis: {self.redis_url}")

            # Initialize controllers
            self.trading_controller = TradingController(self.redis_client)
            self.strategy_manager = StrategyManager(self.redis_client)
            self.risk_controller = RiskController(self.redis_client)

            # Load initial configuration
            await self.load_config()

            logger.info("Trading Control API initialization completed")

        except Exception as e:
            logger.error(f"Failed to initialize Trading Control API: {e}")
            raise

    async def load_config(self):
        """Load trading configuration from TOML file"""
        try:
            with open(self.config_path, 'r') as f:
                config_data = toml.load(f)

            trading_config = config_data.get('trading', {})
            strategy_config = config_data.get('strategy', {})

            # Convert to TradingConfig
            self.trading_config = TradingConfig(
                mode=ExecutionMode(config_data.get('environment', {}).get('execution_mode', 'paper')),
                strategy=TradingStrategy.ENHANCED_RSI,  # Default strategy
                initial_capital=trading_config.get('initial_capital', 1.0),
                max_position_size=trading_config.get('max_position_size', 0.1),
                max_drawdown=trading_config.get('max_drawdown', 0.15),
                cycle_interval=trading_config.get('cycle_interval', 1.0)
            )

            logger.info(f"Loaded trading configuration: {self.trading_config}")

        except Exception as e:
            logger.error(f"Failed to load configuration: {e}")
            # Use default configuration
            self.trading_config = TradingConfig(
                mode=ExecutionMode.PAPER,
                strategy=TradingStrategy.ENHANCED_RSI,
                initial_capital=1.0,
                max_position_size=0.1,
                max_drawdown=0.15,
                cycle_interval=1.0
            )

    def setup_routes(self):
        """Setup API routes"""

        @self.app.get("/api/trading/status")
        async def get_trading_status():
            """Get current trading status"""
            try:
                with self.control_latency.labels(operation='get_status').time():
                    status_data = {
                        "status": self.trading_status.value,
                        "config": self.trading_config.to_dict() if self.trading_config else None,
                        "start_time": self.start_time.isoformat() if self.start_time else None,
                        "last_trade_time": self.last_trade_time.isoformat() if self.last_trade_time else None,
                        "uptime_seconds": (datetime.utcnow() - self.start_time).total_seconds() if self.start_time else 0,
                        "metrics": await self.get_trading_metrics()
                    }

                    self.trading_control_requests.labels(
                        endpoint='/api/trading/status',
                        method='GET',
                        status='success'
                    ).inc()

                    return JSONResponse(status_data)

            except Exception as e:
                logger.error(f"Error getting trading status: {e}")
                self.trading_control_requests.labels(
                    endpoint='/api/trading/status',
                    method='GET',
                    status='error'
                ).inc()
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/trading/start")
        async def start_trading(request: StartTradingRequest, background_tasks: BackgroundTasks):
            """Start trading with specified configuration"""
            try:
                with self.control_latency.labels(operation='start_trading').time():
                    if self.trading_status in [TradingStatus.RUNNING, TradingStatus.STARTING]:
                        raise HTTPException(status_code=400, detail="Trading is already running")

                    # Update configuration
                    self.trading_config = TradingConfig(
                        mode=request.mode,
                        strategy=request.strategy,
                        initial_capital=request.capital,
                        max_position_size=request.max_position_size,
                        max_drawdown=request.max_drawdown,
                        cycle_interval=request.cycle_interval
                    )

                    # Set status to starting
                    self.trading_status = TradingStatus.STARTING
                    await self.broadcast_status_update()

                    # Start trading in background
                    background_tasks.add_task(self._start_trading_background)

                    self.trading_control_requests.labels(
                        endpoint='/api/trading/start',
                        method='POST',
                        status='success'
                    ).inc()

                    return JSONResponse({
                        "message": "Trading started successfully",
                        "status": self.trading_status.value,
                        "config": self.trading_config.to_dict()
                    })

            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"Error starting trading: {e}")
                self.trading_control_requests.labels(
                    endpoint='/api/trading/start',
                    method='POST',
                    status='error'
                ).inc()
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/trading/stop")
        async def stop_trading():
            """Stop all trading activity"""
            try:
                with self.control_latency.labels(operation='stop_trading').time():
                    if self.trading_status == TradingStatus.STOPPED:
                        raise HTTPException(status_code=400, detail="Trading is already stopped")

                    self.trading_status = TradingStatus.STOPPING
                    await self.broadcast_status_update()

                    # Stop trading controllers
                    if self.trading_controller:
                        await self.trading_controller.stop_trading()

                    if self.task_pool_manager:
                        await self.task_pool_manager.shutdown()

                    self.trading_status = TradingStatus.STOPPED
                    self.start_time = None
                    await self.broadcast_status_update()

                    # Update metrics
                    self.trading_status_gauge.set(0)

                    self.trading_control_requests.labels(
                        endpoint='/api/trading/stop',
                        method='POST',
                        status='success'
                    ).inc()

                    return JSONResponse({"message": "Trading stopped successfully"})

            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"Error stopping trading: {e}")
                self.trading_control_requests.labels(
                    endpoint='/api/trading/stop',
                    method='POST',
                    status='error'
                ).inc()
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/trading/pause")
        async def pause_trading():
            """Pause trading temporarily"""
            try:
                with self.control_latency.labels(operation='pause_trading').time():
                    if self.trading_status != TradingStatus.RUNNING:
                        raise HTTPException(status_code=400, detail="Trading is not running")

                    self.trading_status = TradingStatus.PAUSING
                    await self.broadcast_status_update()

                    if self.trading_controller:
                        await self.trading_controller.pause_trading()

                    self.trading_status = TradingStatus.PAUSED
                    await self.broadcast_status_update()

                    # Update metrics
                    self.trading_status_gauge.set(2)

                    self.trading_control_requests.labels(
                        endpoint='/api/trading/pause',
                        method='POST',
                        status='success'
                    ).inc()

                    return JSONResponse({"message": "Trading paused successfully"})

            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"Error pausing trading: {e}")
                self.trading_control_requests.labels(
                    endpoint='/api/trading/pause',
                    method='POST',
                    status='error'
                ).inc()
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/trading/resume")
        async def resume_trading():
            """Resume paused trading"""
            try:
                with self.control_latency.labels(operation='resume_trading').time():
                    if self.trading_status != TradingStatus.PAUSED:
                        raise HTTPException(status_code=400, detail="Trading is not paused")

                    if self.trading_controller:
                        await self.trading_controller.resume_trading()

                    self.trading_status = TradingStatus.RUNNING
                    await self.broadcast_status_update()

                    # Update metrics
                    self.trading_status_gauge.set(1)

                    self.trading_control_requests.labels(
                        endpoint='/api/trading/resume',
                        method='POST',
                        status='success'
                    ).inc()

                    return JSONResponse({"message": "Trading resumed successfully"})

            except HTTPException:
                raise
            except Exception as e:
                logger.error(f"Error resuming trading: {e}")
                self.trading_control_requests.labels(
                    endpoint='/api/trading/resume',
                    method='POST',
                    status='error'
                ).inc()
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.post("/api/trading/emergency/stop")
        async def emergency_stop():
            """Emergency stop all trading activity immediately"""
            try:
                with self.control_latency.labels(operation='emergency_stop').time():
                    logger.warning("EMERGENCY STOP ACTIVATED")

                    # Set status immediately
                    self.trading_status = TradingStatus.EMERGENCY_STOPPED
                    await self.broadcast_status_update()

                    # Force stop all components
                    if self.trading_controller:
                        await self.trading_controller.emergency_stop()

                    if self.task_pool_manager:
                        await self.task_pool_manager.emergency_shutdown()

                    # Update metrics
                    self.trading_status_gauge.set(3)

                    self.trading_control_requests.labels(
                        endpoint='/api/trading/emergency/stop',
                        method='POST',
                        status='success'
                    ).inc()

                    return JSONResponse({
                        "message": "Emergency stop activated - all trading halted immediately",
                        "status": self.trading_status.value
                    })

            except Exception as e:
                logger.error(f"Error during emergency stop: {e}")
                self.trading_control_requests.labels(
                    endpoint='/api/trading/emergency/stop',
                    method='POST',
                    status='error'
                ).inc()
                raise HTTPException(status_code=500, detail=str(e))

        @self.app.websocket("/ws/trading")
        async def websocket_endpoint(websocket: WebSocket):
            """WebSocket endpoint for real-time status updates"""
            await websocket.accept()
            self.active_connections.append(websocket)

            try:
                # Send initial status
                await self.send_status_update(websocket)

                # Keep connection alive and handle messages
                while True:
                    data = await websocket.receive_text()

                    # Handle WebSocket messages (e.g., ping/pong, status requests)
                    try:
                        message = json.loads(data)
                        if message.get("type") == "ping":
                            await websocket.send_text(json.dumps({"type": "pong"}))
                        elif message.get("type") == "get_status":
                            await self.send_status_update(websocket)
                    except json.JSONDecodeError:
                        pass

            except WebSocketDisconnect:
                self.active_connections.remove(websocket)
                logger.info("WebSocket client disconnected")
            except Exception as e:
                logger.error(f"WebSocket error: {e}")
                if websocket in self.active_connections:
                    self.active_connections.remove(websocket)

    async def _start_trading_background(self):
        """Background task to start trading"""
        try:
            logger.info("Starting trading in background...")

            # Initialize task pool manager
            self.task_pool_manager = TaskPoolManager(redis_client=self.redis_client)
            await self.task_pool_manager.initialize()

            # Start trading controller
            await self.trading_controller.start_trading(self.trading_config)

            # Update status
            self.trading_status = TradingStatus.RUNNING
            self.start_time = datetime.utcnow()
            await self.broadcast_status_update()

            # Update metrics
            self.trading_status_gauge.set(1)

            logger.info("Trading started successfully")

        except Exception as e:
            logger.error(f"Failed to start trading: {e}")
            self.trading_status = TradingStatus.STOPPED
            await self.broadcast_status_update()

    async def get_trading_metrics(self) -> Dict[str, Any]:
        """Get current trading metrics"""
        try:
            if not self.trading_controller:
                return {}

            metrics = await self.trading_controller.get_metrics()

            # Update portfolio value gauge
            if 'portfolio_value' in metrics:
                self.portfolio_value_gauge.set(metrics['portfolio_value'])

            return metrics

        except Exception as e:
            logger.error(f"Error getting trading metrics: {e}")
            return {}

    async def send_status_update(self, websocket: WebSocket):
        """Send status update to specific WebSocket client"""
        try:
            status_data = {
                "type": "status_update",
                "timestamp": datetime.utcnow().isoformat(),
                "status": self.trading_status.value,
                "config": self.trading_config.to_dict() if self.trading_config else None,
                "start_time": self.start_time.isoformat() if self.start_time else None,
                "last_trade_time": self.last_trade_time.isoformat() if self.last_trade_time else None,
                "uptime_seconds": (datetime.utcnow() - self.start_time).total_seconds() if self.start_time else 0,
                "metrics": await self.get_trading_metrics()
            }

            await websocket.send_text(json.dumps(status_data))

        except Exception as e:
            logger.error(f"Error sending status update: {e}")

    async def broadcast_status_update(self):
        """Broadcast status update to all connected WebSocket clients"""
        if not self.active_connections:
            return

        # Create a list of tasks to send updates to all clients
        tasks = []
        for websocket in self.active_connections.copy():
            tasks.append(self.send_status_update(websocket))

        # Execute all tasks concurrently
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def run(self):
        """Run the API server"""
        import uvicorn

        logger.info(f"Starting Trading Control API on port {self.port}")

        # Initialize before starting
        await self.initialize()

        # Run the server
        config = uvicorn.Config(
            app=self.app,
            host="0.0.0.0",
            port=self.port,
            log_level="info"
        )

        server = uvicorn.Server(config)
        await server.serve()

    async def shutdown(self):
        """Graceful shutdown"""
        logger.info("Shutting down Trading Control API...")

        # Close WebSocket connections
        for websocket in self.active_connections.copy():
            try:
                await websocket.close()
            except:
                pass
        self.active_connections.clear()

        # Stop trading
        if self.trading_status in [TradingStatus.RUNNING, TradingStatus.PAUSED]:
            await self.stop_trading()

        # Close Redis connection
        if self.redis_client:
            await self.redis_client.close()

        logger.info("Trading Control API shutdown complete")

# Main execution
if __name__ == "__main__":
    api = TradingControlAPI()

    try:
        asyncio.run(api.run())
    except KeyboardInterrupt:
        logger.info("Received keyboard interrupt")
    except Exception as e:
        logger.error(f"Fatal error: {e}")
    finally:
        asyncio.run(api.shutdown())