# =============================================================================
# ShredStream Python Bridge for Helius WebSocket Connection
# =============================================================================
# This module provides a WebSocket bridge for Helius ShredStream connectivity.
# It handles async WebSocket operations and exposes a simple synchronous interface
# for Mojo integration using asyncio.run() patterns.

import asyncio
import json
import logging
import time
from typing import Optional, Dict, Any, List

# WebSocket library for ShredStream connection
try:
    import websockets
    WEBSOCKETS_AVAILABLE = True
except ImportError:
    WEBSOCKETS_AVAILABLE = False
    websockets = None

# Module-level logger
logger = logging.getLogger(__name__)

# Global connection state
_connection = None
_connection_stats = {
    "connected": False,
    "endpoint": "",
    "connection_time": None,
    "last_message_time": None,
    "messages_received": 0,
    "blocks_received": 0,
    "subscription_active": False
}


async def _connect_async(endpoint: str) -> bool:
    """
    Asynchronous WebSocket connection to ShredStream endpoint

    Args:
        endpoint: ShredStream WebSocket endpoint URL

    Returns:
        True if connection successful, False otherwise
    """
    global _connection, _connection_stats

    if not WEBSOCKETS_AVAILABLE:
        logger.error("websockets library not available")
        return False

    try:
        logger.info(f"Connecting to ShredStream endpoint: {endpoint}")

        # Connect to WebSocket with ping/pong for connection health
        _connection = await websockets.connect(
            endpoint,
            ping_interval=20,
            ping_timeout=10,
            close_timeout=10
        )

        _connection_stats.update({
            "connected": True,
            "endpoint": endpoint,
            "connection_time": time.time(),
            "messages_received": 0,
            "blocks_received": 0,
            "subscription_active": False
        })

        logger.info("ShredStream connection established successfully")
        return True

    except Exception as e:
        logger.error(f"Failed to connect to ShredStream: {e}")
        _connection_stats["connected"] = False
        return False


def connect(endpoint: str) -> bool:
    """
    Connect to ShredStream WebSocket endpoint

    Args:
        endpoint: ShredStream WebSocket endpoint URL

    Returns:
        True if connection successful, False otherwise
    """
    try:
        # Run the async connection function
        loop = asyncio.get_event_loop()
        if loop.is_running():
            # If loop is running, use run_in_executor
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(asyncio.run, _connect_async(endpoint))
                result = future.result(timeout=30.0)
        else:
            # If loop is not running, use asyncio.run directly
            result = asyncio.run(_connect_async(endpoint))

        return result

    except Exception as e:
        logger.error(f"ShredStream connection failed: {e}")
        return False


async def _subscribe_to_blocks_async() -> bool:
    """
    Subscribe to block updates via ShredStream

    Returns:
        True if subscription successful, False otherwise
    """
    global _connection, _connection_stats

    if not _connection or not _connection_stats["connected"]:
        logger.error("No active ShredStream connection")
        return False

    try:
        # Send block subscription message
        subscribe_message = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "blockSubscribe"
        }

        await _connection.send(json.dumps(subscribe_message))
        _connection_stats["subscription_active"] = True

        logger.info("Subscribed to block updates via ShredStream")
        return True

    except Exception as e:
        logger.error(f"Failed to subscribe to blocks: {e}")
        return False


def subscribe_to_blocks() -> bool:
    """
    Subscribe to block updates via ShredStream

    Returns:
        True if subscription successful, False otherwise
    """
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(asyncio.run, _subscribe_to_blocks_async())
                result = future.result(timeout=10.0)
        else:
            result = asyncio.run(_subscribe_to_blocks_async())

        return result

    except Exception as e:
        logger.error(f"Block subscription failed: {e}")
        return False


async def _disconnect_async() -> None:
    """Asynchronous disconnection from ShredStream"""
    global _connection, _connection_stats

    if _connection:
        try:
            await _connection.close()
            logger.info("ShredStream connection closed")
        except Exception as e:
            logger.error(f"Error closing ShredStream connection: {e}")
        finally:
            _connection = None
            _connection_stats["connected"] = False
            _connection_stats["subscription_active"] = False


def disconnect() -> None:
    """Disconnect from ShredStream WebSocket"""
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(asyncio.run, _disconnect_async())
                future.result(timeout=10.0)
        else:
            asyncio.run(_disconnect_async())

    except Exception as e:
        logger.error(f"Disconnection failed: {e}")


def is_connected() -> bool:
    """
    Check if ShredStream is connected

    Returns:
        True if connected, False otherwise
    """
    return _connection_stats["connected"]


def get_connection_stats() -> Dict[str, Any]:
    """
    Get current connection statistics

    Returns:
        Dictionary containing connection stats
    """
    return _connection_stats.copy()


async def _listen_for_messages_async() -> None:
    """
    Listen for incoming messages from ShredStream

    This is a background task that processes messages and updates stats.
    """
    global _connection, _connection_stats

    if not _connection:
        return

    try:
        async for message in _connection:
            _connection_stats["last_message_time"] = time.time()
            _connection_stats["messages_received"] += 1

            # Try to parse as JSON and check if it's a block message
            try:
                data = json.loads(message)
                if data.get("method") == "blockNotification":
                    _connection_stats["blocks_received"] += 1
                    logger.debug(f"Received block notification: {data}")
            except json.JSONDecodeError:
                logger.debug(f"Received non-JSON message: {message}")

    except websockets.exceptions.ConnectionClosed:
        logger.info("ShredStream connection closed")
        _connection_stats["connected"] = False
        _connection_stats["subscription_active"] = False
    except Exception as e:
        logger.error(f"Error listening for messages: {e}")
        _connection_stats["connected"] = False


def start_message_listener() -> None:
    """
    Start background message listener

    This should be called after successful connection and subscription.
    """
    try:
        loop = asyncio.get_event_loop()
        if loop.is_running():
            # Create task for message listening
            task = asyncio.create_task(_listen_for_messages_async())
            logger.info("Started ShredStream message listener task")
        else:
            logger.warning("No event loop running, cannot start message listener")

    except Exception as e:
        logger.error(f"Failed to start message listener: {e}")


# Test function for development
async def test_shredstream_bridge():
    """Test ShredStream bridge functionality"""
    logger.info("Testing ShredStream bridge...")

    # Test connection
    test_endpoint = "wss://atlas-mainnet.helius-rpc.com/shredstream"
    connected = connect(test_endpoint)

    if connected:
        logger.info("✅ Connection test successful")

        # Test subscription
        subscribed = subscribe_to_blocks()
        if subscribed:
            logger.info("✅ Subscription test successful")

            # Start listener
            start_message_listener()

            # Wait for some messages
            await asyncio.sleep(5)

            # Get stats
            stats = get_connection_stats()
            logger.info(f"Connection stats: {stats}")

        else:
            logger.error("❌ Subscription test failed")

        # Cleanup
        disconnect()
    else:
        logger.error("❌ Connection test failed")


if __name__ == "__main__":
    # Configure logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )

    # Run test
    asyncio.run(test_shredstream_bridge())