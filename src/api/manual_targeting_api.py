#!/usr/bin/env python3
"""
MojoRust Manual Targeting API

REST API endpoints for manual token targeting functionality.
Integrates with the ManualTargetingService to provide web interface
for adding and managing token targets.

Endpoints:
- POST /api/targeting/add - Add token to watchlist
- DELETE /api/targeting/remove/{token_address} - Remove token from watchlist
- GET /api/targeting/watchlist - Get current watchlist
- POST /api/targeting/update/{token_address} - Update token parameters
- POST /api/targeting/execute - Execute manual trade
- GET /api/targeting/analysis/{token_address} - Get token analysis
"""

import asyncio
import logging
from datetime import datetime
from typing import Dict, List, Optional, Any

from fastapi import APIRouter, HTTPException, BackgroundTasks, Query
from pydantic import BaseModel, Field

from ..control.manual_targeting_service import ManualTargetingService, TokenPriority

logger = logging.getLogger(__name__)

# Create router
router = APIRouter(prefix="/api/targeting", tags=["targeting"])

# Pydantic models
class AddTokenRequest(BaseModel):
    token_address: str = Field(..., description="Token contract address")
    token_symbol: Optional[str] = Field(None, description="Token symbol")
    token_name: Optional[str] = Field(None, description="Token name")
    priority: TokenPriority = Field(TokenPriority.MEDIUM, description="Monitoring priority")
    max_buy_amount_sol: Optional[float] = Field(None, ge=0.001, le=10, description="Max buy amount in SOL")
    min_liquidity_sol: Optional[float] = Field(None, ge=1.0, le=1000, description="Minimum liquidity in SOL")
    target_roi: Optional[float] = Field(None, ge=0.01, le=5.0, description="Target ROI (e.g., 0.5 for 50%)")
    stop_loss_percentage: Optional[float] = Field(None, ge=0.01, le=0.5, description="Stop loss percentage")
    take_profit_percentage: Optional[float] = Field(None, ge=0.01, le=2.0, description="Take profit percentage")
    confidence_threshold: Optional[float] = Field(None, ge=0.1, le=1.0, description="Minimum confidence for trading")
    expires_hours: Optional[int] = Field(None, ge=1, le=168, description="Hours until target expires")
    notes: Optional[str] = Field(None, max_length=500, description="User notes about the token")
    added_by: str = Field("user", description="Who added the token")

class UpdateTokenRequest(BaseModel):
    priority: Optional[TokenPriority] = Field(None, description="New priority level")
    max_buy_amount_sol: Optional[float] = Field(None, ge=0.001, le=10)
    min_liquidity_sol: Optional[float] = Field(None, ge=1.0, le=1000)
    target_roi: Optional[float] = Field(None, ge=0.01, le=5.0)
    stop_loss_percentage: Optional[float] = Field(None, ge=0.01, le=0.5)
    take_profit_percentage: Optional[float] = Field(None, ge=0.01, le=2.0)
    confidence_threshold: Optional[float] = Field(None, ge=0.1, le=1.0)
    expires_hours: Optional[int] = Field(None, ge=1, le=168)
    notes: Optional[str] = Field(None, max_length=500)

class ExecuteManualTradeRequest(BaseModel):
    token_address: str = Field(..., description="Token address to trade")
    action: str = Field(..., regex="^(buy|sell)$", description="Trade action: buy or sell")
    amount_sol: Optional[float] = Field(None, ge=0.001, le=10, description="Amount in SOL")
    force_execution: bool = Field(False, description="Force execution even if criteria not met")

# Global service instance (will be injected during app startup)
targeting_service: Optional[ManualTargetingService] = None

def set_targeting_service(service: ManualTargetingService):
    """Inject the targeting service instance."""
    global targeting_service
    targeting_service = service

@router.post("/add", response_model=Dict[str, Any])
async def add_token_target(request: AddTokenRequest, background_tasks: BackgroundTasks):
    """
    Add a new token target to the watchlist.

    This endpoint allows users to manually add token addresses that they want
    the trading bot to monitor and potentially trade.
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        # Add token to watchlist
        target_id = await targeting_service.add_token_target(
            token_address=request.token_address,
            token_symbol=request.token_symbol,
            token_name=request.token_name,
            priority=request.priority,
            max_buy_amount_sol=request.max_buy_amount_sol,
            min_liquidity_sol=request.min_liquidity_sol,
            target_roi=request.target_roi,
            stop_loss_percentage=request.stop_loss_percentage,
            take_profit_percentage=request.take_profit_percentage,
            confidence_threshold=request.confidence_threshold,
            expires_hours=request.expires_hours,
            notes=request.notes,
            added_by=request.added_by
        )

        # Start background analysis (async)
        background_tasks.add_task(targeting_service._analyze_and_store, request.token_address)

        return {
            "success": True,
            "message": "Token added to watchlist successfully",
            "target_id": target_id,
            "token_address": request.token_address,
            "token_symbol": request.token_symbol,
            "priority": request.priority.value
        }

    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.error(f"Error adding token target: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.delete("/remove/{token_address}", response_model=Dict[str, Any])
async def remove_token_target(token_address: str, reason: str = "user_removed"):
    """
    Remove a token target from the watchlist.

    Args:
        token_address: Token address to remove
        reason: Reason for removal (optional)
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        success = await targeting_service.remove_token_target(token_address, reason)

        if success:
            return {
                "success": True,
                "message": f"Token {token_address} removed from watchlist",
                "token_address": token_address,
                "reason": reason
            }
        else:
            raise HTTPException(status_code=404, detail="Token not found in watchlist")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error removing token target: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/watchlist", response_model=Dict[str, Any])
async def get_watchlist(
    status_filter: Optional[str] = Query(None, description="Filter by status"),
    priority_filter: Optional[str] = Query(None, description="Filter by priority"),
    limit: Optional[int] = Query(None, ge=1, le=1000, description="Maximum results to return")
):
    """
    Get the current token watchlist.

    Args:
        status_filter: Optional filter by token status
        priority_filter: Optional filter by priority level
        limit: Maximum number of results to return
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        # Convert string filters to enums
        status_enum = None
        if status_filter:
            try:
                from ..control.manual_targeting_service import TokenStatus
                status_enum = TokenStatus(status_filter)
            except ValueError:
                raise HTTPException(status_code=400, detail=f"Invalid status filter: {status_filter}")

        priority_enum = None
        if priority_filter:
            try:
                priority_enum = TokenPriority(priority_filter)
            except ValueError:
                raise HTTPException(status_code=400, detail=f"Invalid priority filter: {priority_filter}")

        # Get watchlist
        watchlist = await targeting_service.get_watchlist(
            status_filter=status_enum,
            priority_filter=priority_enum,
            limit=limit
        )

        return {
            "success": True,
            "watchlist": watchlist,
            "total_count": len(watchlist),
            "filters_applied": {
                "status": status_filter,
                "priority": priority_filter,
                "limit": limit
            }
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting watchlist: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.put("/update/{token_address}", response_model=Dict[str, Any])
async def update_token_target(token_address: str, request: UpdateTokenRequest):
    """
    Update parameters for an existing token target.

    Args:
        token_address: Token address to update
        request: Updated parameters
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        # Convert request to dict and filter None values
        update_data = {k: v for k, v in request.dict().items() if v is not None}

        success = await targeting_service.update_target_parameters(token_address, **update_data)

        if success:
            return {
                "success": True,
                "message": f"Token {token_address} updated successfully",
                "token_address": token_address,
                "updated_fields": list(update_data.keys())
            }
        else:
            raise HTTPException(status_code=404, detail="Token not found in watchlist")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error updating token target: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/execute", response_model=Dict[str, Any])
async def execute_manual_trade(request: ExecuteManualTradeRequest):
    """
    Execute a manual trade for a watched token.

    This allows users to manually trigger trades for tokens in their watchlist,
    bypassing some of the automated criteria if force_execution is True.
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        # Execute manual trade
        result = await targeting_service.execute_manual_trade(
            token_address=request.token_address,
            action=request.action,
            amount_sol=request.amount_sol,
            force_execution=request.force_execution
        )

        if result["success"]:
            return {
                "success": True,
                "message": f"Manual {request.action} trade executed successfully",
                "trade_details": result
            }
        else:
            return {
                "success": False,
                "message": f"Manual trade failed: {result.get('error', 'Unknown error')}",
                "error": result.get('error')
            }

    except Exception as e:
        logger.error(f"Error executing manual trade: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/analysis/{token_address}", response_model=Dict[str, Any])
async def get_token_analysis(token_address: str):
    """
    Get detailed analysis for a specific token.

    Returns real-time analysis data including price, liquidity,
    confidence scores, and trading recommendations.
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        analysis = await targeting_service.get_token_analysis(token_address)

        if analysis:
            return {
                "success": True,
                "token_address": token_address,
                "analysis": analysis
            }
        else:
            raise HTTPException(status_code=404, detail="Token not found in watchlist")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting token analysis: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/statistics", response_model=Dict[str, Any])
async def get_targeting_statistics():
    """
    Get statistics about the manual targeting service.

    Returns performance metrics, watchlist statistics, and success rates.
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        stats = await targeting_service.get_statistics()

        return {
            "success": True,
            "statistics": stats,
            "timestamp": datetime.utcnow().isoformat()
        }

    except Exception as e:
        logger.error(f"Error getting targeting statistics: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.post("/batch-add", response_model=Dict[str, Any])
async def batch_add_tokens(requests: List[AddTokenRequest], background_tasks: BackgroundTasks):
    """
    Add multiple tokens to the watchlist in a single request.

    Useful for bulk importing token lists.
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        if len(requests) > 100:
            raise HTTPException(status_code=400, detail="Maximum 100 tokens per batch request")

        results = []
        errors = []

        for i, token_request in enumerate(requests):
            try:
                target_id = await targeting_service.add_token_target(
                    token_address=token_request.token_address,
                    token_symbol=token_request.token_symbol,
                    token_name=token_request.token_name,
                    priority=token_request.priority,
                    max_buy_amount_sol=token_request.max_buy_amount_sol,
                    min_liquidity_sol=token_request.min_liquidity_sol,
                    target_roi=token_request.target_roi,
                    stop_loss_percentage=token_request.stop_loss_percentage,
                    take_profit_percentage=token_request.take_profit_percentage,
                    confidence_threshold=token_request.confidence_threshold,
                    expires_hours=token_request.expires_hours,
                    notes=token_request.notes,
                    added_by=token_request.added_by
                )

                # Start background analysis
                background_tasks.add_task(targeting_service._analyze_and_store, token_request.token_address)

                results.append({
                    "index": i,
                    "token_address": token_request.token_address,
                    "target_id": target_id,
                    "success": True
                })

            except Exception as e:
                errors.append({
                    "index": i,
                    "token_address": token_request.token_address,
                    "error": str(e),
                    "success": False
                })

        return {
            "success": True,
            "message": f"Processed {len(requests)} token requests",
            "summary": {
                "total_requests": len(requests),
                "successful": len(results),
                "failed": len(errors)
            },
            "results": results,
            "errors": errors
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error in batch add tokens: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@router.get("/search/{token_address}", response_model=Dict[str, Any])
async def search_token(token_address: str):
    """
    Search for a token in the watchlist by address.

    Returns detailed information about the token if found.
    """
    try:
        if not targeting_service:
            raise HTTPException(status_code=503, detail="Targeting service not available")

        watchlist = await targeting_service.get_watchlist()

        # Search for token
        found_tokens = [token for token in watchlist if token["token_address"] == token_address]

        if found_tokens:
            return {
                "success": True,
                "found": True,
                "token": found_tokens[0]
            }
        else:
            return {
                "success": True,
                "found": False,
                "message": f"Token {token_address} not found in watchlist"
            }

    except Exception as e:
        logger.error(f"Error searching for token: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

# WebSocket endpoint for real-time updates (would be added to main API)
async def setup_targeting_websocket_routes(app):
    """Setup WebSocket routes for targeting updates."""
    from fastapi import WebSocket, WebSocketDisconnect

    @app.websocket("/ws/targeting")
    async def targeting_websocket_endpoint(websocket: WebSocket):
        await websocket.accept()
        targeting_service.active_connections.append(websocket)

        try:
            while True:
                # Handle incoming messages
                data = await websocket.receive_text()
                message = json.loads(data)

                if message.get("type") == "get_watchlist":
                    watchlist = await targeting_service.get_watchlist()
                    await websocket.send_text(json.dumps({
                        "type": "watchlist_update",
                        "data": watchlist
                    }))
                elif message.get("type") == "ping":
                    await websocket.send_text(json.dumps({"type": "pong"}))

        except WebSocketDisconnect:
            targeting_service.active_connections.remove(websocket)
        except Exception as e:
            logger.error(f"WebSocket error: {e}")
            if websocket in targeting_service.active_connections:
                targeting_service.active_connections.remove(websocket)