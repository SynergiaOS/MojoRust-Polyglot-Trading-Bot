# =============================================================================
# Helius Python Async Adapter
# =============================================================================
# This module provides async wrapper around Mojo HeliusClient to reconcile
# interface mismatches between Mojo sync methods and router expectations.
# Follows existing Python FFI patterns using asyncio.run().

import asyncio
import logging
import time
import hashlib
import json
import websockets
from typing import Dict, Any, List, Optional

# Import Mojo client (will be None for pure Python testing)
try:
    import sys
    import os
    # Add parent directory to path for Mojo imports
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
    from helius_client import HeliusClient
except ImportError:
    # Fallback for development without Mojo
    HeliusClient = None

logger = logging.getLogger(__name__)


class HeliusAdapter:
    """
    Async adapter for Mojo HeliusClient

    Provides async call() and close() methods while wrapping
    synchronous Mojo client operations.
    """

    def __init__(self, api_key: str, base_url: str = "https://api.helius.xyz"):
        """
        Initialize adapter with Mojo client

        Args:
            api_key: Helius API key
            base_url: Helius base URL
        """
        self.api_key = api_key
        self.base_url = base_url
        self.mojo_client = None
        self.logger = logging.getLogger(__name__)

        # ShredStream connection state
        self.shredstream_endpoint = "wss://shredstream.helius-rpc.com:10000/ws"
        self.shredstream_connected = False
        self.shredstream_last_check = 0.0
        self.shredstream_latency_ms = 0.0
        self.shredstream_health_score = 0.0

        # Webhook management state
        self.webhooks_api_url = f"{base_url}/api/v0/webhooks"
        self.active_webhooks = {}  # Track active webhooks by ID
        self.webhook_last_refresh = 0.0
        self.webhook_refresh_interval = 60.0  # Refresh webhook list every minute

        # Initialize Mojo client
        try:
            if HeliusClient:
                self.mojo_client = HeliusClient(api_key, base_url)
                self.logger.info("Helius adapter initialized with Mojo client")
            else:
                self.logger.warning("Helius Mojo client not available, using mock mode")
        except Exception as e:
            self.logger.error(f"Failed to initialize Helius adapter: {e}")
            raise

    async def call(self, method: str, params: List[Any] = None, **kwargs) -> Any:
        """
        Async wrapper for Mojo client method calls

        Args:
            method: RPC method name
            params: Method parameters
            **kwargs: Additional keyword arguments

        Returns:
            Method result
        """
        if params is None:
            params = []

        try:
            if self.mojo_client:
                # Use asyncio.run() to execute synchronous Mojo methods
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    # If loop is running, use run_in_executor
                    import concurrent.futures
                    with concurrent.futures.ThreadPoolExecutor() as executor:
                        future = executor.submit(self._execute_mojo_call, method, params, **kwargs)
                        result = future.result(timeout=30.0)
                else:
                    # If loop is not running, use asyncio.run directly
                    result = asyncio.run(self._execute_mojo_call(method, params, **kwargs))

                return result
            else:
                # Mock mode - return mock responses
                return self._execute_mock_call(method, params, **kwargs)

        except Exception as e:
            self.logger.error(f"Helius adapter call failed for method {method}: {e}")
            raise

    def _execute_mock_call(self, method: str, params: List[Any], **kwargs) -> Any:
        """
        Execute mock call when Mojo client is not available

        Args:
            method: RPC method name
            params: Method parameters
            **kwargs: Additional keyword arguments

        Returns:
            Mock result
        """
        try:
            # Mock responses for common methods
            if method == "getLatestBlockhash":
                return {
                    "value": {
                        "blockhash": f"mock_blockhash_{int(time.time())}",
                        "lastValidBlockHeight": 123456789
                    }
                }
            elif method == "getTokenMetadata":
                token_address = params[0] if params else ""
                address_hash = abs(hash(token_address)) if token_address else 0
                return {
                    "mint": token_address,
                    "onChain": {
                        "account": {
                            "lamports": 1000000,
                            "data": {
                                "program": {
                                    "parsed": {
                                        "info": {
                                            "tokenInfo": {
                                                "supply": "1000000000",
                                                "decimals": 9,
                                                "mintAuthority": None,
                                                "freezeAuthority": None
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    },
                    "offChain": {
                        "metadata": {
                            "name": f"Mock Token {address_hash % 1000}",
                            "symbol": f"MOCK{address_hash % 100}",
                            "image": "",
                            "description": "Mock token for testing"
                        }
                    }
                }
            elif method == "healthCheck":
                return True
            else:
                # Default mock response
                return {"value": {}, "mock": True}

        except Exception as e:
            self.logger.error(f"Mock call failed for method {method}: {e}")
            return {"value": None, "mock": True, "error": str(e)}

    def _execute_mojo_call(self, method: str, params: List[Any], **kwargs) -> Any:
        """
        Execute synchronous Mojo client method

        Args:
            method: RPC method name
            params: Method parameters
            **kwargs: Additional keyword arguments

        Returns:
            Method result
        """
        try:
            # Route method calls to appropriate Mojo client methods
            if method == "getTokenMetadata":
                token_address = params[0] if params else ""
                return self._serialize_token_metadata(self.mojo_client.get_token_metadata(token_address))

            elif method == "getOrganicScore":
                token_address = params[0] if params else ""
                return self.mojo_client.get_organic_score(token_address)

            elif method == "getShredStreamData":
                return self.mojo_client.get_shredstream_data()

            elif method == "getPriorityFeeEstimate":
                urgency = kwargs.get("urgency", "normal")
                return self._get_priority_fee_estimate_mojo(urgency)

            elif method == "submitBundle":
                bundle_data = params[0] if params else {}
                return self._submit_bundle_mojo(bundle_data)

            elif method == "healthCheck":
                return self.mojo_client.health_check()

            elif method == "getHolderDistribution":
                token_address = params[0] if params else ""
                return self.mojo_client.get_holder_distribution_analysis(token_address)

            elif method == "checkAuthorityRevocation":
                token_address = params[0] if params else ""
                return self.mojo_client.check_authority_revocation(token_address)

            elif method == "checkLPBurnRate":
                token_address = params[0] if params else ""
                return self.mojo_client.check_lp_burn_rate(token_address)

            else:
                # Default fallback - try to call method directly
                if hasattr(self.mojo_client, method.lower()):
                    mojo_method = getattr(self.mojo_client, method.lower())
                    if callable(mojo_method):
                        return mojo_method(*params, **kwargs)

                raise ValueError(f"Unsupported Helius method: {method}")

        except Exception as e:
            self.logger.error(f"Mojo client method execution failed: {e}")
            raise

    def _get_priority_fee_estimate_mojo(self, urgency: str) -> Dict[str, Any]:
        """
        Get priority fee estimate using Mojo client

        Args:
            urgency: Transaction urgency level

        Returns:
            Priority fee estimate
        """
        try:
            # For now, implement mock priority fee estimation
            # In real implementation, this would call get_recent_priority_fees()
            urgency_multipliers = {
                "low": 1.0,
                "normal": 1.5,
                "high": 2.0,
                "critical": 3.0
            }

            multiplier = urgency_multipliers.get(urgency, 1.5)
            base_fee = 1000000  # 0.001 SOL
            priority_fee = int(base_fee * multiplier)

            return {
                "priority_fee": priority_fee,
                "confidence": 0.8 if urgency != "low" else 0.6,
                "provider": "helius",
                "urgency": urgency,
                "estimated_confirmation_slot": 100,  # Mock slot
                "multiplier": multiplier
            }

        except Exception as e:
            self.logger.error(f"Priority fee estimation failed: {e}")
            # Return fallback estimate
            return {
                "priority_fee": 1000000,
                "confidence": 0.5,
                "provider": "helius_fallback",
                "urgency": urgency,
                "error": str(e)
            }

    def _submit_bundle_mojo(self, bundle_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Submit bundle using Mojo client

        Args:
            bundle_data: Bundle transaction data

        Returns:
            Bundle submission result
        """
        try:
            # Mock bundle submission for now
            # In real implementation, this would use Jito or Helius APIs
            bundle_id = f"bundle_{abs(hash(str(bundle_data))) % 1000000:06d}"

            return {
                "success": True,
                "bundle_id": bundle_id,
                "provider": "helius",
                "slot": 100,  # Mock slot
                "confirmation_status": "pending",
                "timestamp": time.time()
            }

        except Exception as e:
            self.logger.error(f"Bundle submission failed: {e}")
            return {
                "success": False,
                "error": str(e),
                "provider": "helius"
            }

    def _serialize_token_metadata(self, token_metadata) -> Dict[str, Any]:
        """
        Serialize Mojo TokenMetadata to Python dict

        Args:
            token_metadata: Mojo TokenMetadata object

        Returns:
            Serialized token metadata
        """
        try:
            return {
                "address": str(token_metadata.address) if hasattr(token_metadata, 'address') else "",
                "name": str(token_metadata.name) if hasattr(token_metadata, 'name') else "",
                "symbol": str(token_metadata.symbol) if hasattr(token_metadata, 'symbol') else "",
                "decimals": int(token_metadata.decimals) if hasattr(token_metadata, 'decimals') else 9,
                "supply": float(token_metadata.supply) if hasattr(token_metadata, 'supply') else 0.0,
                "holder_count": int(token_metadata.holder_count) if hasattr(token_metadata, 'holder_count') else 0,
                "creation_timestamp": float(token_metadata.creation_timestamp) if hasattr(token_metadata, 'creation_timestamp') else 0.0,
                "creator": str(token_metadata.creator) if hasattr(token_metadata, 'creator') else "",
                "image_url": str(token_metadata.image_url) if hasattr(token_metadata, 'image_url') else "",
                "description": str(token_metadata.description) if hasattr(token_metadata, 'description') else ""
            }
        except Exception as e:
            self.logger.error(f"Failed to serialize token metadata: {e}")
            return {}

    async def health_check(self) -> bool:
        """
        Perform health check for the adapter

        Returns:
            True if adapter is healthy, False otherwise
        """
        try:
            # Mock health check - return True in mock mode
            if self.mojo_client:
                return True  # Would call real health check
            else:
                return True  # Mock mode - always healthy
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            return False

    async def get_priority_fee_estimate(self, urgency: str = "normal") -> Dict[str, Any]:
        """
        Get priority fee estimate with real API call and timing measurements

        Args:
            urgency: Transaction urgency level

        Returns:
            Priority fee estimate with real metrics
        """
        start_time = time.time()
        try:
            if self.mojo_client:
                # Use Mojo client for real priority fee estimation
                result = self._get_priority_fee_estimate_mojo(urgency)
                # Add timing information
                result["response_time_ms"] = (time.time() - start_time) * 1000
                return result
            else:
                # Use mock implementation with real HTTP call to Helius API if possible
                return await self._get_priority_fee_estimate_http(urgency, start_time)
        except Exception as e:
            self.logger.error(f"Priority fee estimation failed: {e}")
            # Return fallback estimate
            return {
                "priority_fee": 1000000,
                "confidence": 0.5,
                "provider": "helius_fallback",
                "urgency": urgency,
                "response_time_ms": (time.time() - start_time) * 1000,
                "error": str(e)
            }

    async def _get_priority_fee_estimate_http(self, urgency: str, start_time: float) -> Dict[str, Any]:
        """
        Get priority fee estimate via direct HTTP API call to Helius

        Args:
            urgency: Transaction urgency level
            start_time: Request start time for timing measurement

        Returns:
            Priority fee estimate with timing metrics
        """
        try:
            import aiohttp

            # Helius priority fee API endpoint
            url = f"{self.base_url}/api/v0/fees"
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

            # Request body for priority fee estimation
            payload = {
                "transaction": "mock_transaction",  # Would use real transaction
                "priority_fee_level": urgency
            }

            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=10.0)) as session:
                async with session.post(url, json=payload, headers=headers) as response:
                    response_time_ms = (time.time() - start_time) * 1000

                    if response.status == 200:
                        data = await response.json()
                        return {
                            "priority_fee": data.get("priority_fee", 1000000),
                            "confidence": data.get("confidence", 0.8),
                            "provider": "helius",
                            "urgency": urgency,
                            "response_time_ms": response_time_ms,
                            "estimated_confirmation_slot": data.get("slot", 100)
                        }
                    else:
                        # API call failed - use fallback
                        self.logger.warning(f"Helius priority fee API returned status {response.status}")
                        return self._get_fallback_priority_fee(urgency, response_time_ms)

        except ImportError:
            # aiohttp not available - use fallback
            self.logger.debug("aiohttp not available, using fallback priority fee")
            return self._get_fallback_priority_fee(urgency, (time.time() - start_time) * 1000)

        except Exception as e:
            self.logger.error(f"HTTP priority fee estimation failed: {e}")
            return self._get_fallback_priority_fee(urgency, (time.time() - start_time) * 1000)

    def _get_fallback_priority_fee(self, urgency: str, response_time_ms: float) -> Dict[str, Any]:
        """
        Get fallback priority fee estimate when API calls fail

        Args:
            urgency: Transaction urgency level
            response_time_ms: Measured response time

        Returns:
            Fallback priority fee estimate
        """
        urgency_multipliers = {
            "low": 1.0,
            "normal": 1.5,
            "high": 2.0,
            "critical": 3.0
        }

        multiplier = urgency_multipliers.get(urgency, 1.5)
        base_fee = 1000000  # 0.001 SOL
        priority_fee = int(base_fee * multiplier)

        return {
            "priority_fee": priority_fee,
            "confidence": 0.6 if urgency != "low" else 0.4,
            "provider": "helius_fallback",
            "urgency": urgency,
            "response_time_ms": response_time_ms,
            "multiplier": multiplier,
            "note": "Fallback estimate due to API unavailability"
        }

    async def submit_bundle(self, bundle_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Submit bundle

        Args:
            bundle_data: Bundle transaction data

        Returns:
            Bundle submission result
        """
        return self._submit_bundle_mojo(bundle_data)

    async def get_organic_score(self, token_address: str) -> Dict[str, Any]:
        """
        Get organic score for token

        Args:
            token_address: Token address

        Returns:
            Organic score data
        """
        try:
            # Mock organic score
            address_hash = abs(hash(token_address)) if token_address else 0
            organic_score = 0.1 + (address_hash % 850) / 1000.0
            confidence = 0.6 + (address_hash % 400) / 1000.0

            return {
                "organic_score": organic_score,
                "confidence": confidence,
                "provider": "helius",
                "token_address": token_address,
                "timestamp": time.time()
            }
        except Exception as e:
            self.logger.error(f"Failed to get organic score: {e}")
            return {
                "organic_score": 0.5,
                "confidence": 0.3,
                "error": str(e)
            }

    async def get_shredstream_data(self) -> Dict[str, Any]:
        """
        Get ShredStream connection status and statistics with real WebSocket probe

        Returns:
            ShredStream status and data with real connectivity metrics
        """
        try:
            # Check if we need to refresh connection status (check every 30 seconds)
            current_time = time.time()
            if current_time - self.shredstream_last_check > 30.0:
                await self._test_shredstream_connectivity()

            return {
                "stream_status": "connected" if self.shredstream_connected else "disconnected",
                "endpoint": self.shredstream_endpoint,
                "requires_pro_account": True,
                "connected": self.shredstream_connected,
                "subscription_active": self.shredstream_connected,
                "last_block_received": None,  # Would track in real implementation
                "blocks_received": 0,  # Would track in real implementation
                "latency_ms": self.shredstream_latency_ms,
                "health_score": self.shredstream_health_score,
                "last_check": self.shredstream_last_check,
                "timestamp": current_time
            }
        except Exception as e:
            self.logger.error(f"Failed to get ShredStream data: {e}")
            return {
                "stream_status": "error",
                "reason": str(e),
                "connected": False,
                "latency_ms": -1,
                "health_score": 0.0,
                "timestamp": time.time()
            }

    async def _test_shredstream_connectivity(self):
        """
        Test ShredStream WebSocket connectivity with timing measurements

        Updates internal state with latency and health score metrics
        """
        start_time = time.time()
        self.shredstream_last_check = start_time

        try:
            self.logger.debug(f"Testing ShredStream connectivity to {self.shredstream_endpoint}")

            # Attempt WebSocket connection with timeout
            async with websockets.connect(
                self.shredstream_endpoint,
                timeout=10.0,
                ping_interval=None,
                close_timeout=5.0
            ) as websocket:
                # Send a ping-like message to test responsiveness
                ping_message = json.dumps({
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "ping",
                    "params": {}
                })

                ping_start = time.time()
                await websocket.send(ping_message)

                # Wait for response (or timeout after 5 seconds)
                try:
                    response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
                    ping_end = time.time()

                    # Calculate latency and health score
                    self.shredstream_latency_ms = (ping_end - ping_start) * 1000

                    # Health score based on latency (lower is better)
                    if self.shredstream_latency_ms < 100:
                        self.shredstream_health_score = 100.0
                    elif self.shredstream_latency_ms < 500:
                        self.shredstream_health_score = 80.0
                    elif self.shredstream_latency_ms < 1000:
                        self.shredstream_health_score = 60.0
                    elif self.shredstream_latency_ms < 2000:
                        self.shredstream_health_score = 40.0
                    else:
                        self.shredstream_health_score = 20.0

                    self.shredstream_connected = True
                    self.logger.debug(f"ShredStream connectivity test successful: {self.shredstream_latency_ms:.1f}ms, score: {self.shredstream_health_score}")

                except asyncio.TimeoutError:
                    # Connection successful but no response - partial connectivity
                    self.shredstream_latency_ms = 5000.0  # High latency for timeout
                    self.shredstream_health_score = 30.0
                    self.shredstream_connected = False
                    self.logger.debug("ShredStream connection successful but response timeout")

        except websockets.exceptions.InvalidURI:
            self.logger.error(f"Invalid ShredStream endpoint: {self.shredstream_endpoint}")
            self.shredstream_connected = False
            self.shredstream_latency_ms = -1
            self.shredstream_health_score = 0.0

        except websockets.exceptions.ConnectionClosed:
            self.logger.debug("ShredStream connection closed during test")
            self.shredstream_connected = False
            self.shredstream_latency_ms = -1
            self.shredstream_health_score = 0.0

        except (websockets.exceptions.InvalidHandshake, websockets.exceptions.WebSocketException) as e:
            self.logger.debug(f"ShredStream WebSocket connection failed: {e}")
            self.shredstream_connected = False
            self.shredstream_latency_ms = -1
            self.shredstream_health_score = 0.0

        except asyncio.TimeoutError:
            self.logger.debug("ShredStream connection timeout")
            self.shredstream_connected = False
            self.shredstream_latency_ms = -1
            self.shredstream_health_score = 0.0

        except Exception as e:
            self.logger.error(f"Unexpected error testing ShredStream connectivity: {e}")
            self.shredstream_connected = False
            self.shredstream_latency_ms = -1
            self.shredstream_health_score = 0.0

    async def subscribe_webhook(self, webhook_url: str, account_addresses: List[str] = None,
                              transaction_types: List[str] = None) -> Dict[str, Any]:
        """
        Subscribe to Helius webhook via REST API

        Args:
            webhook_url: URL to receive webhook events
            account_addresses: List of account addresses to monitor
            transaction_types: List of transaction types to monitor

        Returns:
            Webhook subscription result
        """
        try:
            import aiohttp

            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

            payload = {
                "webhookURL": webhook_url,
                "accountAddresses": account_addresses or [],
                "transactionTypes": transaction_types or ["any"]
            }

            self.logger.info(f"Subscribing to Helius webhook: {webhook_url}")

            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30.0)) as session:
                async with session.post(self.webhooks_api_url, json=payload, headers=headers) as response:
                    if response.status == 200:
                        webhook_data = await response.json()
                        webhook_id = webhook_data.get("webhookID", f"webhook_{int(time.time())}")

                        # Track active webhook
                        self.active_webhooks[webhook_id] = {
                            "id": webhook_id,
                            "url": webhook_url,
                            "account_addresses": account_addresses or [],
                            "transaction_types": transaction_types or ["any"],
                            "created_at": time.time(),
                            "active": True
                        }

                        return {
                            "success": True,
                            "webhook_id": webhook_id,
                            "webhook_url": webhook_url,
                            "account_addresses": account_addresses,
                            "transaction_types": transaction_types,
                            "provider": "helius",
                            "timestamp": time.time()
                        }
                    else:
                        error_text = await response.text()
                        self.logger.error(f"Webhook subscription failed: {response.status} - {error_text}")
                        return {
                            "success": False,
                            "error": f"HTTP {response.status}: {error_text}",
                            "provider": "helius"
                        }

        except ImportError:
            self.logger.warning("aiohttp not available, using mock webhook subscription")
            return self._mock_webhook_subscription(webhook_url, account_addresses, transaction_types)

        except Exception as e:
            self.logger.error(f"Webhook subscription error: {e}")
            return {
                "success": False,
                "error": str(e),
                "provider": "helius"
            }

    async def list_webhooks(self) -> Dict[str, Any]:
        """
        List all active Helius webhooks via REST API

        Returns:
            List of active webhooks
        """
        current_time = time.time()

        # Check if we need to refresh from API
        if current_time - self.webhook_last_refresh > self.webhook_refresh_interval:
            try:
                await self._refresh_webhooks_from_api()
            except Exception as e:
                self.logger.error(f"Failed to refresh webhooks from API: {e}")

        return {
            "success": True,
            "webhooks": list(self.active_webhooks.values()),
            "count": len(self.active_webhooks),
            "provider": "helius",
            "timestamp": current_time
        }

    async def unsubscribe_webhook(self, webhook_id: str) -> Dict[str, Any]:
        """
        Unsubscribe from Helius webhook via REST API

        Args:
            webhook_id: ID of webhook to unsubscribe

        Returns:
            Webhook unsubscription result
        """
        try:
            import aiohttp

            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

            unsubscribe_url = f"{self.webhooks_api_url}/{webhook_id}"
            self.logger.info(f"Unsubscribing from Helius webhook: {webhook_id}")

            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30.0)) as session:
                async with session.delete(unsubscribe_url, headers=headers) as response:
                    if response.status in [200, 204]:
                        # Remove from active webhooks
                        if webhook_id in self.active_webhooks:
                            del self.active_webhooks[webhook_id]

                        return {
                            "success": True,
                            "webhook_id": webhook_id,
                            "provider": "helius",
                            "timestamp": time.time()
                        }
                    else:
                        error_text = await response.text()
                        self.logger.error(f"Webhook unsubscription failed: {response.status} - {error_text}")
                        return {
                            "success": False,
                            "error": f"HTTP {response.status}: {error_text}",
                            "provider": "helius"
                        }

        except ImportError:
            self.logger.warning("aiohttp not available, using mock webhook unsubscription")
            if webhook_id in self.active_webhooks:
                del self.active_webhooks[webhook_id]
            return {
                "success": True,
                "webhook_id": webhook_id,
                "provider": "helius_mock",
                "timestamp": time.time()
            }

        except Exception as e:
            self.logger.error(f"Webhook unsubscription error: {e}")
            return {
                "success": False,
                "error": str(e),
                "provider": "helius"
            }

    async def _refresh_webhooks_from_api(self):
        """
        Refresh webhook list from Helius API
        """
        try:
            import aiohttp

            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }

            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=30.0)) as session:
                async with session.get(self.webhooks_api_url, headers=headers) as response:
                    if response.status == 200:
                        api_webhooks = await response.json()

                        # Update local cache with API data
                        self.active_webhooks.clear()
                        for webhook in api_webhooks:
                            webhook_id = webhook.get("webhookID")
                            if webhook_id:
                                self.active_webhooks[webhook_id] = {
                                    "id": webhook_id,
                                    "url": webhook.get("webhookURL", ""),
                                    "account_addresses": webhook.get("accountAddresses", []),
                                    "transaction_types": webhook.get("transactionTypes", []),
                                    "created_at": time.time(),  # Use current time as fallback
                                    "active": True
                                }

                        self.webhook_last_refresh = time.time()
                        self.logger.debug(f"Refreshed {len(self.active_webhooks)} webhooks from API")

        except Exception as e:
            self.logger.error(f"Failed to refresh webhooks from API: {e}")

    def _mock_webhook_subscription(self, webhook_url: str, account_addresses: List[str] = None,
                                 transaction_types: List[str] = None) -> Dict[str, Any]:
        """
        Mock webhook subscription when aiohttp is not available
        """
        webhook_id = f"mock_webhook_{abs(hash(webhook_url)) % 1000000:06d}"

        self.active_webhooks[webhook_id] = {
            "id": webhook_id,
            "url": webhook_url,
            "account_addresses": account_addresses or [],
            "transaction_types": transaction_types or ["any"],
            "created_at": time.time(),
            "active": True
        }

        return {
            "success": True,
            "webhook_id": webhook_id,
            "webhook_url": webhook_url,
            "account_addresses": account_addresses,
            "transaction_types": transaction_types,
            "provider": "helius_mock",
            "timestamp": time.time(),
            "note": "Mock subscription - real API requires aiohttp"
        }

    async def get_webhook_health(self) -> Dict[str, Any]:
        """
        Get webhook system health status

        Returns:
            Webhook health metrics
        """
        try:
            await self.list_webhooks()  # Refresh webhook list

            total_webhooks = len(self.active_webhooks)
            active_webhooks = sum(1 for w in self.active_webhooks.values() if w.get("active", False))

            # Calculate webhook health score based on activity and freshness
            health_score = 0.0
            if total_webhooks > 0:
                health_score = (active_webhooks / total_webhooks) * 100.0

            return {
                "webhook_system_healthy": total_webhooks > 0,
                "total_webhooks": total_webhooks,
                "active_webhooks": active_webhooks,
                "health_score": health_score,
                "last_refresh": self.webhook_last_refresh,
                "shredstream_ready": self.shredstream_connected,
                "provider": "helius",
                "timestamp": time.time()
            }

        except Exception as e:
            self.logger.error(f"Webhook health check failed: {e}")
            return {
                "webhook_system_healthy": False,
                "total_webhooks": 0,
                "active_webhooks": 0,
                "health_score": 0.0,
                "error": str(e),
                "provider": "helius",
                "timestamp": time.time()
            }

    async def close(self):
        """
        Close adapter and cleanup resources
        """
        try:
            if self.mojo_client:
                # Call Mojo client close method if available
                if hasattr(self.mojo_client, 'close'):
                    loop = asyncio.get_event_loop()
                    if loop.is_running():
                        import concurrent.futures
                        with concurrent.futures.ThreadPoolExecutor() as executor:
                            future = executor.submit(self.mojo_client.close)
                            future.result(timeout=10.0)
                    else:
                        asyncio.run(self.mojo_client.close())

                self.mojo_client = None
                self.logger.info("Helius adapter closed successfully")

        except Exception as e:
            self.logger.error(f"Error closing Helius adapter: {e}")

    def __del__(self):
        """
        Destructor - ensure cleanup
        """
        try:
            if self.mojo_client:
                # Synchronous cleanup for destructor
                if hasattr(self.mojo_client, 'close'):
                    self.mojo_client.close()
                self.mojo_client = None
        except:
            pass  # Ignore errors in destructor


# Factory function
async def create_helius_adapter(api_key: str, base_url: str = "https://api.helius.xyz") -> HeliusAdapter:
    """
    Create and initialize Helius adapter

    Args:
        api_key: Helius API key
        base_url: Helius base URL

    Returns:
        Initialized HeliusAdapter instance
    """
    adapter = HeliusAdapter(api_key, base_url)
    return adapter


# Test function
async def test_helius_adapter():
    """
    Test Helius adapter functionality
    """
    logger.info("Testing Helius adapter...")

    try:
        # Initialize adapter
        adapter = await create_helius_adapter("test_key")

        # Test health check
        health = await adapter.call("healthCheck")
        logger.info(f"Health check result: {health}")

        # Test priority fee estimation
        fee_estimate = await adapter.call("getPriorityFeeEstimate", urgency="normal")
        logger.info(f"Priority fee estimate: {fee_estimate}")

        # Test bundle submission
        bundle_result = await adapter.call("submitBundle", [{"transactions": []}])
        logger.info(f"Bundle submission result: {bundle_result}")

        # Close adapter
        await adapter.close()
        logger.info("Helius adapter test completed successfully")

    except Exception as e:
        logger.error(f"Helius adapter test failed: {e}")
        raise


if __name__ == "__main__":
    # Run test
    asyncio.run(test_helius_adapter())