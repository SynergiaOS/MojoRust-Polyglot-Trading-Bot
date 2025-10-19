"""
FastAPI Health Check API for MojoRust Trading Bot

Provides health check endpoints for monitoring and observability:
- /health - Basic health check
- /ready - Readiness check with component dependencies
- /metrics - Prometheus metrics in OpenMetrics format
"""

import os
import sys
import time
import asyncio
from typing import Dict, Any, Optional
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from prometheus_client.core import REGISTRY
from dotenv import load_dotenv

# Add src to Python path for importing Mojo modules
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

# Load environment variables
load_dotenv()

# Configuration
HEALTH_CHECK_PORT = int(os.getenv('HEALTH_CHECK_PORT', '8082'))
HEALTH_CHECK_ENABLED = os.getenv('HEALTH_CHECK_ENABLED', 'true').lower() == 'true'
METRICS_EXPORT_ENABLED = os.getenv('METRICS_EXPORT_ENABLED', 'true').lower() == 'true'

# Prometheus metrics
HTTP_REQUESTS_TOTAL = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

HTTP_REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)

HEALTH_CHECKS_TOTAL = Counter(
    'health_checks_total',
    'Total health checks',
    ['check_type', 'status']
)

READINESS_CHECKS = Gauge(
    'readiness_check_status',
    'Readiness check status',
    ['component']
)

UPTIME_GAUGE = Gauge(
    'trading_bot_uptime_seconds',
    'Application uptime in seconds'
)

# Arbitrage-specific metrics
ARBITRAGE_OPPORTUNITIES_DETECTED = Counter(
    'arbitrage_opportunities_detected_total',
    'Total arbitrage opportunities detected',
    ['type']  # triangular, cross_dex, statistical, flash_loan
)

ARBITRAGE_OPPORTUNITIES_EXECUTED = Counter(
    'arbitrage_opportunities_executed_total',
    'Total arbitrage opportunities executed',
    ['type', 'status']  # type: triangular, cross_dex, etc.; status: success, failed
)

ARBITRAGE_EXECUTION_TIME = Histogram(
    'arbitrage_execution_duration_seconds',
    'Arbitrage execution duration in seconds',
    ['type'],
    buckets=[0.1, 0.5, 1.0, 2.5, 5.0, 10.0, 20.0, 30.0, 60.0, 120.0]
)

ARBITRAGE_PROFIT = Histogram(
    'arbitrage_profit_usd',
    'Arbitrage profit in USD',
    ['type'],
    buckets=[0.01, 0.1, 0.5, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0, 100.0, 500.0]
)

# Additional counter for total profit sum (needed for alerts)
ARBITRAGE_PROFIT_TOTAL = Counter(
    'arbitrage_profit_usd_sum',
    'Total arbitrage profit in USD',
    ['type']
)

ARBITRAGE_PROFIT_ACCURACY = Histogram(
    'arbitrage_profit_accuracy_ratio',
    'Arbitrage profit prediction accuracy ratio',
    ['type'],
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99, 1.0]
)

ARBITRAGE_ACTIVE_OPPORTUNITIES = Gauge(
    'arbitrage_active_opportunities_count',
    'Current number of active arbitrage opportunities',
    ['type']
)

ARBITRAGE_GAS_COST = Histogram(
    'arbitrage_gas_cost_sol',
    'Arbitrage gas cost in SOL',
    ['type'],
    buckets=[0.001, 0.0025, 0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1.0]
)

ARBITRAGE_SLIPPAGE = Histogram(
    'arbitrage_slippage_percentage',
    'Arbitrage slippage percentage',
    ['dex'],
    buckets=[0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0, 20.0]
)

ARBITRAGE_LIQUIDITY_SCORE = Histogram(
    'arbitrage_liquidity_score',
    'Arbitrage liquidity score',
    ['type'],
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
)

ARBITRAGE_CONFIDENCE_SCORE = Histogram(
    'arbitrage_confidence_score',
    'Arbitrage confidence score',
    ['type'],
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
)

ARBITRAGE_SCAN_DURATION = Histogram(
    'arbitrage_scan_duration_seconds',
    'Duration of arbitrage opportunity scans',
    buckets=[0.1, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0, 10.0]
)

# Additional metrics for better monitoring
ARBITRAGE_OPPORTUNITY_PROFIT_THRESHOLD = Histogram(
    'arbitrage_opportunity_profit_threshold_usd',
    'Profit threshold of detected arbitrage opportunities',
    ['type'],
    buckets=[0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 25.0, 50.0]
)

ARBITRAGE_EXECUTION_GAS_USED = Histogram(
    'arbitrage_execution_gas_used',
    'Gas used for arbitrage executions',
    ['type'],
    buckets=[1000000, 2000000, 5000000, 10000000, 15000000, 20000000, 30000000, 50000000]
)

ARBITRAGE_ROUTE_COMPLEXITY = Histogram(
    'arbitrage_route_complexity_hops',
    'Number of hops in arbitrage routes',
    ['type'],
    buckets=[1, 2, 3, 4, 5, 6, 7, 8]
)

ARBITRAGE_PRICE_UPDATES = Counter(
    'arbitrage_price_updates_total',
    'Total price updates processed by arbitrage engine',
    ['dex', 'status']  # status: success, error
)

ARBITRAGE_ENGINE_STATUS = Gauge(
    'arbitrage_engine_status',
    'Arbitrage engine status (1=running, 0=stopped)',
    ['component']  # detector, scanner, executor
)

# Initialize FastAPI app
app = FastAPI(
    title="Trading Bot Health API",
    description="Health check endpoints for MojoRust Trading Bot",
    version="1.0.0",
    docs_url="/docs" if HEALTH_CHECK_ENABLED else None,
    redoc_url="/redoc" if HEALTH_CHECK_ENABLED else None
)

# Add middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware)

# Global variables for Mojo integration
ultimate_monitor = None
rate_limiter = None
sentry_client = None
start_time = time.time()

# Global registry for custom metrics to avoid duplicates
custom_metrics_registry = {}

async def initialize_monitoring():
    """Initialize monitoring components"""
    global ultimate_monitor, rate_limiter, sentry_client

    try:
        # Import Mojo modules
        sys.path.insert(0, 'src')
        sys.path.insert(0, 'src/monitoring')

        # Initialize UltimateMonitor
        try:
            # Try to import Mojo module using Python's Mojo interop
            import python
            python.add_import_path('src/monitoring')
            from python import ultimate_monitor_mojo
            ultimate_monitor = ultimate_monitor_mojo.UltimateMonitor()
            print("✅ UltimateMonitor initialized (Mojo)")
        except Exception as e:
            try:
                # Fallback to Python implementation
                from .ultimate_monitor import UltimateMonitor
                ultimate_monitor = UltimateMonitor()
                print("✅ UltimateMonitor initialized (Python fallback)")
            except ImportError as e2:
                print(f"⚠️  Could not import UltimateMonitor: {e2}")
                print("   This is expected if running in development without monitoring modules")

        # Initialize RateLimiter
        try:
            import python
            python.add_import_path('src/monitoring')
            from python import rate_limiter_mojo
            rate_limiter = rate_limiter_mojo.RateLimiter()
            print("✅ RateLimiter initialized (Mojo)")
        except Exception as e:
            try:
                # Fallback to Python implementation
                from .rate_limiter import RateLimiter
                rate_limiter = RateLimiter()
                print("✅ RateLimiter initialized (Python fallback)")
            except ImportError as e2:
                print(f"⚠️  Could not import RateLimiter: {e2}")

        # Initialize SentryClient
        try:
            import python
            python.add_import_path('src/monitoring')
            from python import sentry_client_mojo
            sentry_client = sentry_client_mojo.SentryClient()
            print("✅ SentryClient initialized (Mojo)")
        except Exception as e:
            try:
                # Fallback to Python implementation
                from .sentry_client import SentryClient
                sentry_client = SentryClient()
                print("✅ SentryClient initialized (Python fallback)")
            except ImportError as e2:
                print(f"⚠️  Could not import SentryClient: {e2}")

    except Exception as e:
        print(f"❌ Failed to initialize monitoring: {e}")

@app.middleware("http")
async def monitoring_middleware(request: Request, call_next):
    """Add monitoring to all requests"""
    start_time_req = time.time()

    # Rate limiting
    if rate_limiter:
        client_ip = request.client.host if request.client else "unknown"
        try:
            result = rate_limiter.check_rate_limit(client_ip, request.url.path)
            # Handle result as object with attributes (from Mojo) or dict (from Python fallback)
            allowed = getattr(result, 'allowed', result.get('allowed', True) if hasattr(result, 'get') else True)
            if not allowed:
                HTTP_REQUESTS_TOTAL.labels(
                    method=request.method,
                    endpoint=request.url.path,
                    status='429'
                ).inc()
                return JSONResponse(
                    status_code=429,
                    content={"detail": "Rate limit exceeded"}
                )
        except Exception as e:
            print(f"Rate limiting error: {e}")

    # Continue with request
    response = await call_next(request)

    # Record metrics
    duration = time.time() - start_time_req
    HTTP_REQUEST_DURATION.labels(
        method=request.method,
        endpoint=request.url.path
    ).observe(duration)

    HTTP_REQUESTS_TOTAL.labels(
        method=request.method,
        endpoint=request.url.path,
        status=str(response.status_code)
    ).inc()

    return response

@app.on_event("startup")
async def startup_event():
    """Initialize monitoring on startup"""
    await initialize_monitoring()

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    global ultimate_monitor, rate_limiter, sentry_client

    if sentry_client:
        try:
            sentry_client.flush(timeout=5.0)
        except:
            pass

@app.get("/health")
async def health_check():
    """Basic health check endpoint"""
    if not HEALTH_CHECK_ENABLED:
        raise HTTPException(status_code=503, detail="Health checks disabled")

    try:
        status = "healthy"
        message = "Service is healthy"
        uptime = time.time() - start_time

        # Check UltimateMonitor if available
        if ultimate_monitor:
            try:
                health_status = ultimate_monitor.get_health_status()
                status = health_status.get('status', status)
                message = health_status.get('message', message)
            except Exception as e:
                status = "degraded"
                message = f"Monitor error: {e}"

        # Record health check
        HEALTH_CHECKS_TOTAL.labels(check_type="health", status="success").inc()

        return {
            "status": status,
            "timestamp": int(time.time()),
            "uptime": int(uptime),
            "message": message
        }

    except Exception as e:
        HEALTH_CHECKS_TOTAL.labels(check_type="health", status="error").inc()
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/health"})
            except:
                pass
        raise HTTPException(status_code=503, detail=f"Health check failed: {e}")

@app.get("/ready")
async def readiness_check():
    """Readiness check endpoint"""
    if not HEALTH_CHECK_ENABLED:
        raise HTTPException(status_code=503, detail="Health checks disabled")

    try:
        checks = {}
        ready = True
        message = "Service is ready"

        # Check database (mock for now)
        try:
            # TODO: Implement actual database health check
            checks["database"] = True
            READINESS_CHECKS.labels(component="database").set(1)
        except Exception:
            checks["database"] = False
            ready = False
            READINESS_CHECKS.labels(component="database").set(0)

        # Check Redis (mock for now)
        try:
            # TODO: Implement actual Redis health check
            checks["redis"] = True
            READINESS_CHECKS.labels(component="redis").set(1)
        except Exception:
            checks["redis"] = False
            ready = False
            READINESS_CHECKS.labels(component="redis").set(0)

        # Check APIs (mock for now)
        try:
            # TODO: Implement actual API health checks
            checks["apis"] = True
            READINESS_CHECKS.labels(component="apis").set(1)
        except Exception:
            checks["apis"] = False
            ready = False
            READINESS_CHECKS.labels(component="apis").set(0)

        # Check UltimateMonitor readiness
        if ultimate_monitor:
            try:
                readiness_status = ultimate_monitor.get_readiness_status()
                if not readiness_status.get('ready', True):
                    ready = False
                    message = readiness_status.get('message', 'Service not ready')
                # Update component checks
                for component, status in readiness_status.get('checks', {}).items():
                    checks[component] = status
                    READINESS_CHECKS.labels(component=component).set(1 if status else 0)
            except Exception as e:
                ready = False
                message = f"Readiness check error: {e}"

        # Record readiness check
        status_code = 200 if ready else 503
        HEALTH_CHECKS_TOTAL.labels(check_type="ready", status="success" if ready else "error").inc()

        if ready:
            return {
                "ready": True,
                "checks": checks,
                "message": message,
                "timestamp": int(time.time())
            }
        else:
            raise HTTPException(
                status_code=503,
                content={
                    "ready": False,
                    "checks": checks,
                    "message": message,
                    "timestamp": int(time.time())
                }
            )

    except HTTPException:
        raise
    except Exception as e:
        HEALTH_CHECKS_TOTAL.labels(check_type="ready", status="error").inc()
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/ready"})
            except:
                pass
        raise HTTPException(status_code=503, detail=f"Readiness check failed: {e}")

@app.get("/metrics")
async def metrics():
    """Prometheus metrics endpoint"""
    if not METRICS_EXPORT_ENABLED:
        raise HTTPException(status_code=503, detail="Metrics export disabled")

    try:
        # Get custom metrics from UltimateMonitor
        custom_metrics = {}
        if ultimate_monitor:
            try:
                custom_metrics = ultimate_monitor.get_prometheus_metrics()

                # Add custom metrics using registry to avoid duplicates
                for metric_name, metric_value in custom_metrics.items():
                    try:
                        if metric_name not in custom_metrics_registry:
                            # Create new gauge and register it
                            gauge = Gauge(metric_name, f"Custom metric: {metric_name}")
                            custom_metrics_registry[metric_name] = gauge
                        else:
                            # Use existing gauge
                            gauge = custom_metrics_registry[metric_name]

                        gauge.set(metric_value)
                    except Exception:
                        pass  # Skip invalid metrics

            except Exception as e:
                print(f"Error getting custom metrics: {e}")

        # Update application uptime metric
        UPTIME_GAUGE.set(time.time() - start_time)

        # Generate metrics
        metrics_data = generate_latest()
        return PlainTextResponse(
            content=metrics_data.decode('utf-8'),
            media_type=CONTENT_TYPE_LATEST
        )

    except Exception as e:
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/metrics"})
            except:
                pass
        raise HTTPException(status_code=503, detail=f"Metrics generation failed: {e}")

@app.post("/api/alerts/telegram")
async def telegram_alert_webhook(request: Request):
    """Receive alerts from AlertManager and forward to Telegram"""
    try:
        # TODO: Implement Telegram alert forwarding
        # This would integrate with the existing Telegram bot

        alert_data = await request.json()
        print(f"Received alert: {alert_data}")

        # For now, just acknowledge receipt
        return {"status": "received", "alerts_count": len(alert_data.get('alerts', []))}

    except Exception as e:
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/api/alerts/telegram"})
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Alert processing failed: {e}")

@app.post("/api/alerts/telegram/critical")
async def telegram_critical_alert_webhook(request: Request):
    """Receive critical alerts and forward to Telegram with priority"""
    try:
        # TODO: Implement priority alert handling
        alert_data = await request.json()
        print(f"Received CRITICAL alert: {alert_data}")

        # For now, just acknowledge receipt
        return {"status": "received", "priority": "critical", "alerts_count": len(alert_data.get('alerts', []))}

    except Exception as e:
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/api/alerts/telegram/critical"})
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Critical alert processing failed: {e}")

@app.post("/api/alerts/telegram/trading")
async def telegram_trading_alert_webhook(request: Request):
    """Receive trading alerts and forward to Telegram"""
    try:
        # TODO: Implement trading alert handling
        alert_data = await request.json()
        print(f"Received trading alert: {alert_data}")

        # For now, just acknowledge receipt
        return {"status": "received", "type": "trading", "alerts_count": len(alert_data.get('alerts', []))}

    except Exception as e:
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/api/alerts/telegram/trading"})
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Trading alert processing failed: {e}")

@app.post("/api/alerts/telegram/system")
async def telegram_system_alert_webhook(request: Request):
    """Receive system alerts and forward to Telegram"""
    try:
        # TODO: Implement system alert handling
        alert_data = await request.json()
        print(f"Received system alert: {alert_data}")

        # For now, just acknowledge receipt
        return {"status": "received", "type": "system", "alerts_count": len(alert_data.get('alerts', []))}

    except Exception as e:
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/api/alerts/telegram/system"})
            except:
                pass
        raise HTTPException(status_code=500, detail=f"System alert processing failed: {e}")

@app.get("/arbitrage/status")
async def get_arbitrage_status():
    """Get arbitrage engine status"""
    try:
        if ultimate_monitor and hasattr(ultimate_monitor, 'get_arbitrage_status'):
            status = ultimate_monitor.get_arbitrage_status()
            return JSONResponse(content=status)
        else:
            # Return default arbitrage status
            return JSONResponse(content={
                "is_running": ARBITRAGE_ENGINE_STATUS.labels(component="detector")._value.get() > 0,
                "registered_tokens": 0,
                "triangular_opportunities": int(ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type="triangular")._value.get()),
                "cross_dex_opportunities": int(ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type="cross_dex")._value.get()),
                "statistical_opportunities": int(ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type="statistical")._value.get()),
                "last_scan_timestamp": 0
            })
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting arbitrage status: {str(e)}")

@app.get("/arbitrage/metrics")
async def get_arbitrage_metrics():
    """Get detailed arbitrage metrics"""
    try:
        # Collect current metric values
        triangular_active = ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type="triangular")._value.get()
        cross_dex_active = ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type="cross_dex")._value.get()
        statistical_active = ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type="statistical")._value.get()

        # Try to get metrics from ultimate monitor if available
        if ultimate_monitor and hasattr(ultimate_monitor, 'get_arbitrage_metrics'):
            metrics = ultimate_monitor.get_arbitrage_metrics()
            return JSONResponse(content=metrics)

        # Return default metrics
        return JSONResponse(content={
            "total_opportunities_detected": 0,
            "total_opportunities_executed": 0,
            "successful_executions": 0,
            "failed_executions": 0,
            "total_profit": 0.0,
            "total_gas_cost": 0.0,
            "average_execution_time_ms": 0.0,
            "average_profit_per_trade": 0.0,
            "success_rate": 0.0,
            "last_scan_timestamp": 0,
            "last_execution_timestamp": 0,
            "current_active_opportunities": {
                "triangular": triangular_active,
                "cross_dex": cross_dex_active,
                "statistical": statistical_active
            }
        })
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error getting arbitrage metrics: {str(e)}")

@app.post("/arbitrage/opportunity-detected")
async def record_arbitrage_opportunity(request: Request):
    """Record detection of an arbitrage opportunity"""
    try:
        data = await request.json()
        opportunity_type = data.get("type", "unknown")
        profit_percentage = data.get("profit_percentage", 0.0)
        confidence_score = data.get("confidence_score", 0.0)
        liquidity_score = data.get("liquidity_score", 0.0)

        # Record metrics
        ARBITRAGE_OPPORTUNITIES_DETECTED.labels(type=opportunity_type).inc()
        ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type=opportunity_type).inc()

        if confidence_score > 0:
            ARBITRAGE_CONFIDENCE_SCORE.labels(type=opportunity_type).observe(confidence_score)

        if liquidity_score > 0:
            ARBITRAGE_LIQUIDITY_SCORE.labels(type=opportunity_type).observe(liquidity_score)

        if profit_percentage > 0:
            # Convert percentage to USD estimate (simplified)
            estimated_profit_usd = profit_percentage * 100  # Rough estimate
            ARBITRAGE_OPPORTUNITY_PROFIT_THRESHOLD.labels(type=opportunity_type).observe(estimated_profit_usd)

        return JSONResponse(content={"status": "recorded"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error recording opportunity: {str(e)}")

@app.post("/arbitrage/execution-completed")
async def record_arbitrage_execution(request: Request):
    """Record completion of an arbitrage execution"""
    try:
        data = await request.json()
        opportunity_type = data.get("type", "unknown")
        status = data.get("status", "failed")  # success or failed
        profit_usd = data.get("profit_usd", 0.0)
        expected_profit_usd = data.get("expected_profit_usd", 0.0)
        gas_cost_sol = data.get("gas_cost_sol", 0.0)
        execution_time_ms = data.get("execution_time_ms", 0.0)
        slippage_percentage = data.get("slippage_percentage", 0.0)
        dex_name = data.get("dex_name", "unknown")

        # Record metrics
        ARBITRAGE_OPPORTUNITIES_EXECUTED.labels(type=opportunity_type, status=status).inc()
        ARBITRAGE_ACTIVE_OPPORTUNITIES.labels(type=opportunity_type).dec()  # Remove from active

        if execution_time_ms > 0:
            ARBITRAGE_EXECUTION_TIME.labels(type=opportunity_type).observe(execution_time_ms / 1000.0)

        if profit_usd > 0:
            ARBITRAGE_PROFIT.labels(type=opportunity_type).observe(profit_usd)
            ARBITRAGE_PROFIT_TOTAL.labels(type=opportunity_type).inc(profit_usd)

        if gas_cost_sol > 0:
            ARBITRAGE_GAS_COST.labels(type=opportunity_type).observe(gas_cost_sol)

        if slippage_percentage > 0:
            ARBITRAGE_SLIPPAGE.labels(dex=dex_name).observe(slippage_percentage)

        if expected_profit_usd > 0 and profit_usd > 0:
            accuracy = profit_usd / expected_profit_usd
            ARBITRAGE_PROFIT_ACCURACY.labels(type=opportunity_type).observe(accuracy)

        # Record additional metrics
        if data.get("gas_used", 0) > 0:
            ARBITRAGE_EXECUTION_GAS_USED.labels(type=opportunity_type).observe(data.get("gas_used"))

        if data.get("route_hops", 0) > 0:
            ARBITRAGE_ROUTE_COMPLEXITY.labels(type=opportunity_type).observe(data.get("route_hops"))

        return JSONResponse(content={"status": "recorded"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error recording execution: {str(e)}")

@app.post("/arbitrage/price-update")
async def record_arbitrage_price_update(request: Request):
    """Record price updates processed by arbitrage engine"""
    try:
        data = await request.json()
        dex_name = data.get("dex_name", "unknown")
        status = data.get("status", "success")

        ARBITRAGE_PRICE_UPDATES.labels(dex=dex_name, status=status).inc()

        return JSONResponse(content={"status": "recorded"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error recording price update: {str(e)}")

@app.post("/arbitrage/scan-completed")
async def record_arbitrage_scan(request: Request):
    """Record completion of arbitrage opportunity scan"""
    try:
        data = await request.json()
        scan_duration_seconds = data.get("scan_duration_seconds", 0.0)

        ARBITRAGE_SCAN_DURATION.observe(scan_duration_seconds)

        return JSONResponse(content={"status": "recorded"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error recording scan: {str(e)}")

@app.post("/arbitrage/engine-status")
async def update_arbitrage_engine_status(request: Request):
    """Update arbitrage engine component status"""
    try:
        data = await request.json()
        component = data.get("component", "unknown")  # detector, scanner, executor
        is_running = data.get("is_running", False)

        ARBITRAGE_ENGINE_STATUS.labels(component=component).set(1 if is_running else 0)

        return JSONResponse(content={"status": "updated"})
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error updating engine status: {str(e)}")

# ============================================================================
# Manual Targeting API Endpoints
# ============================================================================

from pydantic import BaseModel, Field
from typing import List, Optional, Union

class ManualTarget(BaseModel):
    """Manual target request for a specific token"""
    token_mint: str = Field(..., description="Token mint address")
    action: str = Field(..., regex="^(BUY|SELL|HOLD|FLASH_LOAN)$", description="Action to take")
    amount_sol: float = Field(..., ge=0.0001, le=1000.0, description="Amount in SOL")
    strategy_type: str = Field("manual", regex="^(sniper_momentum|statistical_arbitrage|liquidity_mining|social_sentiment|technical_patterns|whale_tracking|manual)$", description="Strategy type")
    confidence: float = Field(0.8, ge=0.0, le=1.0, description="Confidence level (0-1)")
    risk_score: float = Field(0.2, ge=0.0, le=1.0, description="Risk score (0-1)")
    expected_return: float = Field(0.0, description="Expected return in SOL")
    flash_loan_amount: float = Field(0.0, ge=0.0, description="Flash loan amount in SOL")
    max_slippage_bps: int = Field(300, ge=50, le=5000, description="Maximum slippage in basis points")
    ttl_seconds: int = Field(60, ge=10, le=3600, description="Time to live in seconds")
    priority: str = Field("normal", regex="^(low|normal|high|critical)$", description="Priority level")
    metadata: Optional[Dict[str, Any]] = Field(None, description="Additional metadata")

class BulkTargetRequest(BaseModel):
    """Bulk targeting request for multiple tokens"""
    targets: List[ManualTarget] = Field(..., min_items=1, max_items=50, description="List of targets")
    batch_name: Optional[str] = Field(None, description="Name for this batch")
    execution_mode: str = Field("sequential", regex="^(sequential|parallel)$", description="Execution mode")

class TargetResponse(BaseModel):
    """Response for targeting requests"""
    success: bool
    target_id: Optional[str] = None
    message: str
    timestamp: int
    estimated_execution_time: Optional[int] = None

# Redis connection for targeting
redis_client = None

async def get_redis_client():
    """Get Redis client connection"""
    global redis_client
    if redis_client is None:
        try:
            import redis
            redis_url = os.getenv('DRAGONFLYDB_URL', 'redis://localhost:6379')
            redis_client = redis.from_url(redis_url, decode_responses=True)
            # Test connection
            await redis_client.ping()
        except Exception as e:
            raise HTTPException(status_code=503, detail=f"Redis connection failed: {e}")
    return redis_client

def generate_target_id(target: ManualTarget) -> str:
    """Generate unique target ID"""
    import uuid
    import time
    strategy_short = target.strategy_type[:4].upper()
    token_short = target.token_mint[:8]
    timestamp = int(time.time())
    unique_suffix = str(uuid.uuid4())[:8]
    return f"MANUAL_{strategy_short}_{token_short}_{timestamp}_{unique_suffix}"

def calculate_opportunity_score(target: ManualTarget) -> float:
    """Calculate opportunity score for prioritization"""
    profit_score = target.expected_return * 1000.0 if target.expected_return > 0 else 0.0
    confidence_bonus = target.confidence * 100.0
    risk_penalty = target.risk_score * 50.0

    # Priority multipliers
    priority_multiplier = {
        "low": 0.5,
        "normal": 1.0,
        "high": 1.5,
        "critical": 2.0
    }.get(target.priority, 1.0)

    # Flash loan bonus
    flash_loan_bonus = 100.0 if target.flash_loan_amount > 0 else 0.0

    return (profit_score + confidence_bonus - risk_penalty + flash_loan_bonus) * priority_multiplier

@app.post("/api/targeting/manual", response_model=TargetResponse)
async def create_manual_target(target: ManualTarget):
    """Create a manual trading target"""
    try:
        # Get Redis client
        redis_conn = await get_redis_client()

        # Generate target ID
        target_id = generate_target_id(target)

        # Validate token mint format
        if not (len(target.token_mint) >= 32 and len(target.token_mint) <= 44):
            raise HTTPException(status_code=400, detail="Invalid token mint address format")

        # Validate action and required capital
        if target.action in ["BUY", "FLASH_LOAN"] and target.amount_sol < 0.001:
            raise HTTPException(status_code=400, detail="Minimum amount is 0.001 SOL for trading actions")

        # For flash loans, ensure amount matches flash_loan_amount
        if target.action == "FLASH_LOAN" and target.flash_loan_amount <= 0:
            target.flash_loan_amount = target.amount_sol * 0.95  # Use 95% flash loan by default

        # Create orchestrator opportunity object
        orchestrator_opportunity = {
            "id": target_id,
            "strategy_type": target.strategy_type,
            "token": target.token_mint,
            "confidence": target.confidence,
            "expected_return": target.expected_return,
            "risk_score": target.risk_score,
            "required_capital": target.amount_sol,
            "flash_loan_amount": target.flash_loan_amount,
            "timestamp": int(time.time()),
            "ttl_seconds": target.ttl_seconds,
            "metadata": {
                "manual_target": True,
                "action": target.action,
                "max_slippage_bps": target.max_slippage_bps,
                "priority": target.priority,
                "batch_name": target.metadata.get("batch_name", "") if target.metadata else "",
                "source": "manual_api",
                "creator": "manual_user",
                "opportunity_type": "manual_target"
            }
        }

        # Add any custom metadata
        if target.metadata:
            orchestrator_opportunity["metadata"].update(target.metadata)

        # Calculate opportunity score
        score = calculate_opportunity_score(target)

        # Add to orchestrator opportunity_queue sorted set
        opportunity_payload = json.dumps(orchestrator_opportunity)
        await redis_conn.zadd("opportunity_queue", {opportunity_payload: score})

        # Also publish to manual_targets channel for monitoring
        await redis_conn.publish("manual_targets", opportunity_payload)

        # Store target details for tracking
        target_key = f"manual_target:{target_id}"
        await redis_conn.hset(target_key, mapping={
            "target_data": opportunity_payload,
            "status": "queued",
            "created_at": str(int(time.time())),
            "score": str(score)
        })
        await redis_conn.expire(target_key, target.ttl_seconds + 300)  # Extra 5 minutes TTL

        # Estimate execution time based on priority
        priority_delay = {
            "critical": 5,
            "high": 15,
            "normal": 30,
            "low": 60
        }.get(target.priority, 30)

        # Record metrics
        HTTP_REQUESTS_TOTAL.labels(
            method="POST",
            endpoint="/api/targeting/manual",
            status="201"
        ).inc()

        return TargetResponse(
            success=True,
            target_id=target_id,
            message=f"Manual target created successfully with ID: {target_id}",
            timestamp=int(time.time()),
            estimated_execution_time=priority_delay
        )

    except HTTPException:
        raise
    except Exception as e:
        HTTP_REQUESTS_TOTAL.labels(
            method="POST",
            endpoint="/api/targeting/manual",
            status="500"
        ).inc()
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/api/targeting/manual"})
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Failed to create manual target: {str(e)}")

@app.post("/api/targeting/bulk", response_model=List[TargetResponse])
async def create_bulk_targets(bulk_request: BulkTargetRequest):
    """Create multiple manual trading targets"""
    try:
        # Get Redis client
        redis_conn = await get_redis_client()

        responses = []
        batch_start_time = int(time.time())
        batch_id = f"BULK_{batch_start_time}_{len(bulk_request.targets)}"

        for i, target in enumerate(bulk_request.targets):
            try:
                # Generate target ID with batch info
                target_id = f"BATCH_{batch_id}_{i+1:02d}_{target.token_mint[:8]}"

                # Add batch metadata
                if target.metadata is None:
                    target.metadata = {}
                target.metadata["batch_id"] = batch_id
                target.metadata["batch_name"] = bulk_request.batch_name or f"Batch_{batch_id}"
                target.metadata["batch_index"] = str(i + 1)
                target.metadata["batch_total"] = str(len(bulk_request.targets))
                target.metadata["execution_mode"] = bulk_request.execution_mode

                # Create orchestrator opportunity (similar to manual target)
                orchestrator_opportunity = {
                    "id": target_id,
                    "strategy_type": target.strategy_type,
                    "token": target.token_mint,
                    "confidence": target.confidence,
                    "expected_return": target.expected_return,
                    "risk_score": target.risk_score,
                    "required_capital": target.amount_sol,
                    "flash_loan_amount": target.flash_loan_amount,
                    "timestamp": batch_start_time,
                    "ttl_seconds": target.ttl_seconds,
                    "metadata": {
                        "manual_target": True,
                        "bulk_target": True,
                        "action": target.action,
                        "max_slippage_bps": target.max_slippage_bps,
                        "priority": target.priority,
                        "batch_name": target.metadata.get("batch_name", ""),
                        "batch_id": batch_id,
                        "execution_mode": bulk_request.execution_mode,
                        "source": "bulk_api",
                        "creator": "bulk_user",
                        "opportunity_type": "bulk_target"
                    }
                }

                # Add any custom metadata
                if target.metadata:
                    orchestrator_opportunity["metadata"].update(target.metadata)

                # Calculate opportunity score (slightly reduced for bulk to avoid spam)
                score = calculate_opportunity_score(target) * 0.95

                # Add to orchestrator opportunity_queue
                opportunity_payload = json.dumps(orchestrator_opportunity)
                await redis_conn.zadd("opportunity_queue", {opportunity_payload: score})

                # Store target details
                target_key = f"manual_target:{target_id}"
                await redis_conn.hset(target_key, mapping={
                    "target_data": opportunity_payload,
                    "status": "queued",
                    "created_at": str(batch_start_time),
                    "score": str(score)
                })
                await redis_conn.expire(target_key, target.ttl_seconds + 300)

                # Store batch information
                batch_key = f"bulk_batch:{batch_id}"
                await redis_conn.hset(batch_key, mapping={
                    "batch_name": bulk_request.batch_name or f"Batch_{batch_id}",
                    "total_targets": str(len(bulk_request.targets)),
                    "created_at": str(batch_start_time),
                    "execution_mode": bulk_request.execution_mode
                })
                await redis_conn.expire(batch_key, 3600)  # 1 hour TTL for batch info

                # Add target to batch set
                await redis_conn.sadd(f"batch_targets:{batch_id}", target_id)

                # Priority-based execution time estimation
                priority_delay = {
                    "critical": 10,
                    "high": 30,
                    "normal": 60,
                    "low": 120
                }.get(target.priority, 60)

                responses.append(TargetResponse(
                    success=True,
                    target_id=target_id,
                    message=f"Bulk target {i+1}/{len(bulk_request.targets)} created",
                    timestamp=batch_start_time,
                    estimated_execution_time=priority_delay
                ))

            except Exception as e:
                responses.append(TargetResponse(
                    success=False,
                    target_id=None,
                    message=f"Failed to create target {i+1}: {str(e)}",
                    timestamp=batch_start_time
                ))

        # Publish batch creation event
        batch_event = {
            "batch_id": batch_id,
            "batch_name": bulk_request.batch_name or f"Batch_{batch_id}",
            "total_targets": len(bulk_request.targets),
            "successful_targets": sum(1 for r in responses if r.success),
            "failed_targets": sum(1 for r in responses if not r.success),
            "execution_mode": bulk_request.execution_mode,
            "timestamp": batch_start_time
        }
        await redis_conn.publish("bulk_targets_created", json.dumps(batch_event))

        # Record metrics
        HTTP_REQUESTS_TOTAL.labels(
            method="POST",
            endpoint="/api/targeting/bulk",
            status="201"
        ).inc()

        return responses

    except Exception as e:
        HTTP_REQUESTS_TOTAL.labels(
            method="POST",
            endpoint="/api/targeting/bulk",
            status="500"
        ).inc()
        if sentry_client:
            try:
                sentry_client.capture_exception(e, {"endpoint": "/api/targeting/bulk"})
            except:
                pass
        raise HTTPException(status_code=500, detail=f"Failed to create bulk targets: {str(e)}")

@app.get("/api/targeting/status/{target_id}")
async def get_target_status(target_id: str):
    """Get status of a specific manual target"""
    try:
        redis_conn = await get_redis_client()

        # Check if target exists
        target_key = f"manual_target:{target_id}"
        target_data = await redis_conn.hgetall(target_key)

        if not target_data:
            raise HTTPException(status_code=404, detail=f"Target {target_id} not found")

        # Parse target data
        target_opportunity = json.loads(target_data.get("target_data", "{}"))

        # Check if it's been processed (removed from queue)
        queue_score = await redis_conn.zscore("opportunity_queue", json.dumps(target_opportunity))

        status = target_data.get("status", "unknown")
        if queue_score is None and status == "queued":
            status = "processed"  # Removed from queue, likely processed

        return {
            "target_id": target_id,
            "status": status,
            "created_at": int(target_data.get("created_at", 0)),
            "score": float(target_data.get("score", 0)),
            "in_queue": queue_score is not None,
            "queue_score": queue_score,
            "target_data": target_opportunity
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get target status: {str(e)}")

@app.get("/api/targeting/batch/{batch_id}")
async def get_batch_status(batch_id: str):
    """Get status of a bulk target batch"""
    try:
        redis_conn = await get_redis_client()

        # Get batch information
        batch_key = f"bulk_batch:{batch_id}"
        batch_data = await redis_conn.hgetall(batch_key)

        if not batch_data:
            raise HTTPException(status_code=404, detail=f"Batch {batch_id} not found")

        # Get all targets in batch
        target_ids = await redis_conn.smembers(f"batch_targets:{batch_id}")

        targets_status = []
        processed_count = 0
        queued_count = 0

        for target_id in target_ids:
            target_key = f"manual_target:{target_id}"
            target_data = await redis_conn.hgetall(target_key)

            if target_data:
                status = target_data.get("status", "unknown")
                target_opportunity = json.loads(target_data.get("target_data", "{}"))
                queue_score = await redis_conn.zscore("opportunity_queue", json.dumps(target_opportunity))

                if queue_score is None and status == "queued":
                    status = "processed"

                if status == "processed":
                    processed_count += 1
                elif queue_score is not None:
                    queued_count += 1

                targets_status.append({
                    "target_id": target_id,
                    "status": status,
                    "in_queue": queue_score is not None,
                    "queue_score": queue_score
                })

        return {
            "batch_id": batch_id,
            "batch_name": batch_data.get("batch_name", ""),
            "total_targets": int(batch_data.get("total_targets", 0)),
            "created_at": int(batch_data.get("created_at", 0)),
            "execution_mode": batch_data.get("execution_mode", "sequential"),
            "targets_status": targets_status,
            "summary": {
                "queued": queued_count,
                "processed": processed_count,
                "total": len(target_ids)
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get batch status: {str(e)}")

@app.delete("/api/targeting/manual/{target_id}")
async def cancel_manual_target(target_id: str):
    """Cancel a manual target"""
    try:
        redis_conn = await get_redis_client()

        # Check if target exists
        target_key = f"manual_target:{target_id}"
        target_data = await redis_conn.hgetall(target_key)

        if not target_data:
            raise HTTPException(status_code=404, detail=f"Target {target_id} not found")

        # Parse target data to remove from queue
        target_opportunity = json.loads(target_data.get("target_data", "{}"))

        # Remove from opportunity queue
        removed = await redis_conn.zrem("opportunity_queue", json.dumps(target_opportunity))

        # Update target status
        await redis_conn.hset(target_key, "status", "cancelled")
        await redis_conn.hset(target_key, "cancelled_at", str(int(time.time())))

        # Publish cancellation event
        cancellation_event = {
            "target_id": target_id,
            "status": "cancelled",
            "timestamp": int(time.time()),
            "removed_from_queue": removed > 0
        }
        await redis_conn.publish("target_cancelled", json.dumps(cancellation_event))

        return {
            "success": True,
            "message": f"Target {target_id} cancelled successfully",
            "removed_from_queue": removed > 0,
            "timestamp": int(time.time())
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to cancel target: {str(e)}")

@app.get("/api/targeting/queue")
async def get_queue_status(limit: int = 50, offset: int = 0):
    """Get current opportunity queue status"""
    try:
        redis_conn = await get_redis_client()

        # Get top opportunities from queue
        queue_data = await redis_conn.zrevrange("opportunity_queue", offset, offset + limit - 1, withscores=True)

        opportunities = []
        for i, (opportunity_json, score) in enumerate(queue_data):
            try:
                opportunity = json.loads(opportunity_json)
                opportunities.append({
                    "rank": offset + i + 1,
                    "score": float(score),
                    "opportunity": opportunity,
                    "is_manual": opportunity.get("metadata", {}).get("manual_target", False)
                })
            except json.JSONDecodeError:
                continue

        # Get queue statistics
        total_queue_size = await redis_conn.zcard("opportunity_queue")

        # Count manual targets in queue
        manual_targets = 0
        for opportunity_json, _ in queue_data:
            try:
                opportunity = json.loads(opportunity_json)
                if opportunity.get("metadata", {}).get("manual_target", False):
                    manual_targets += 1
            except:
                continue

        return {
            "total_queue_size": total_queue_size,
            "showing_range": f"{offset + 1}-{min(offset + len(opportunities), total_queue_size)}",
            "manual_targets_in_page": manual_targets,
            "opportunities": opportunities
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get queue status: {str(e)}")

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "service": "Trading Bot Health API",
        "version": "1.0.0",
        "status": "running",
        "endpoints": {
            "health": "/health",
            "ready": "/ready",
            "metrics": "/metrics",
            "arbitrage_status": "/arbitrage/status",
            "arbitrage_metrics": "/arbitrage/metrics",
            "manual_targeting": {
                "create_target": "/api/targeting/manual",
                "bulk_targets": "/api/targeting/bulk",
                "target_status": "/api/targeting/status/{target_id}",
                "batch_status": "/api/targeting/batch/{batch_id}",
                "cancel_target": "/api/targeting/manual/{target_id}",
                "queue_status": "/api/targeting/queue"
            },
            "arbitrage_endpoints": {
                "opportunity_detected": "/arbitrage/opportunity-detected",
                "execution_completed": "/arbitrage/execution-completed",
                "price_update": "/arbitrage/price-update",
                "scan_completed": "/arbitrage/scan-completed",
                "engine_status": "/arbitrage/engine-status"
            },
            "alerts": {
                "telegram": "/api/alerts/telegram",
                "telegram_critical": "/api/alerts/telegram/critical",
                "telegram_trading": "/api/alerts/telegram/trading",
                "telegram_system": "/api/alerts/telegram/system"
            },
            "docs": "/docs"
        }
    }

if __name__ == "__main__":
    import uvicorn

    print(f"🚀 Starting Health API on port {HEALTH_CHECK_PORT}")
    print(f"   Health checks enabled: {HEALTH_CHECK_ENABLED}")
    print(f"   Metrics export enabled: {METRICS_EXPORT_ENABLED}")

    uvicorn.run(
        "health_api:app",
        host="0.0.0.0",
        port=HEALTH_CHECK_PORT,
        reload=False,
        log_level="info"
    )