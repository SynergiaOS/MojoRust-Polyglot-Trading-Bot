#!/usr/bin/env python3
"""
Webhook Manager for Real-time Trading Alerts

This module provides a Flask-based webhook management system for receiving
real-time alerts from Helius and QuickNode, processing them, and sending
notifications to Telegram and other channels.
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime
from typing import Dict, Any, List, Optional

import redis.asyncio as redis
from flask import Flask, request, jsonify
from quart import Quart, websocket
import aiohttp
import telegram
from telegram.ext import Application

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class WebhookManager:
    """
    Manages webhooks for real-time trading alerts and notifications.

    Handles incoming webhook data from various providers (Helius, QuickNode),
    processes the data, and sends notifications to configured channels.
    """

    def __init__(self):
        self.app = Quart(__name__)
        self.redis_client = None
        self.telegram_bot = None
        self.telegram_chat_id = None
        self.webhook_stats = {
            'total_received': 0,
            'helius_received': 0,
            'quicknode_received': 0,
            'processed': 0,
            'errors': 0,
            'telegram_sent': 0,
            'start_time': time.time()
        }

        # Setup routes
        self._setup_routes()

    async def initialize(self):
        """Initialize async components (Redis, Telegram)"""
        try:
            # Initialize Redis connection
            redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
            self.redis_client = redis.from_url(redis_url)
            await self.redis_client.ping()
            logger.info(f"Connected to Redis: {redis_url}")

            # Initialize Telegram bot
            telegram_token = os.getenv('TELEGRAM_BOT_TOKEN')
            self.telegram_chat_id = os.getenv('TELEGRAM_CHAT_ID')

            if telegram_token and self.telegram_chat_id:
                self.telegram_bot = telegram.Bot(token=telegram_token)
                await self.telegram_bot.get_me()
                logger.info("Telegram bot initialized successfully")
            else:
                logger.warning("Telegram bot not configured - missing TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID")

        except Exception as e:
            logger.error(f"Failed to initialize WebhookManager: {e}")
            raise

    def _setup_routes(self):
        """Setup Flask/Quart routes"""

        @self.app.route('/health', methods=['GET'])
        async def health_check():
            """Health check endpoint"""
            return jsonify({
                'status': 'healthy',
                'timestamp': datetime.utcnow().isoformat(),
                'stats': self.webhook_stats
            })

        @self.app.route('/metrics', methods=['GET'])
        async def metrics():
            """Prometheus metrics endpoint"""
            uptime = time.time() - self.webhook_stats['start_time']
            metrics_text = f"""
# HELP webhook_received_total Total number of webhooks received
# TYPE webhook_received_total counter
webhook_received_total {self.webhook_stats['total_received']}

# HELP webhook_processed_total Total number of webhooks processed
# TYPE webhook_processed_total counter
webhook_processed_total {self.webhook_stats['processed']}

# HELP webhook_errors_total Total number of webhook processing errors
# TYPE webhook_errors_total counter
webhook_errors_total {self.webhook_stats['errors']}

# HELP telegram_notifications_sent_total Total Telegram notifications sent
# TYPE telegram_notifications_sent_total counter
telegram_notifications_sent_total {self.webhook_stats['telegram_sent']}

# HELP webhook_uptime_seconds Webhook manager uptime in seconds
# TYPE webhook_uptime_seconds gauge
webhook_uptime_seconds {uptime:.2f}
            """.strip()

            return metrics_text, 200, {'Content-Type': 'text/plain; charset=utf-8'}

        @self.app.route('/webhook/helius', methods=['POST'])
        async def helius_webhook():
            """Handle Helius webhooks"""
            try:
                data = await request.get_json()
                self.webhook_stats['helius_received'] += 1
                self.webhook_stats['total_received'] += 1

                logger.info(f"Received Helius webhook: {data.get('event_type', 'unknown')}")

                # Process webhook data
                processed_data = await self._process_helius_webhook(data)

                # Publish to Redis for other services
                await self._publish_to_redis('helius_webhooks', processed_data)

                # Send Telegram notification
                await self._send_telegram_notification(processed_data, 'helius')

                self.webhook_stats['processed'] += 1
                return jsonify({'status': 'ok', 'processed': True}), 200

            except Exception as e:
                self.webhook_stats['errors'] += 1
                logger.error(f"Error processing Helius webhook: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 500

        @self.app.route('/webhook/quicknode', methods=['POST'])
        async def quicknode_webhook():
            """Handle QuickNode webhooks"""
            try:
                data = await request.get_json()
                self.webhook_stats['quicknode_received'] += 1
                self.webhook_stats['total_received'] += 1

                logger.info(f"Received QuickNode webhook: {data.get('type', 'unknown')}")

                # Process webhook data
                processed_data = await self._process_quicknode_webhook(data)

                # Publish to Redis for other services
                await self._publish_to_redis('quicknode_webhooks', processed_data)

                # Send Telegram notification
                await self._send_telegram_notification(processed_data, 'quicknode')

                self.webhook_stats['processed'] += 1
                return jsonify({'status': 'ok', 'processed': True}), 200

            except Exception as e:
                self.webhook_stats['errors'] += 1
                logger.error(f"Error processing QuickNode webhook: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 500

        @self.app.route('/webhook/test', methods=['POST'])
        async def test_webhook():
            """Test webhook endpoint for development"""
            try:
                data = await request.get_json()
                logger.info(f"Received test webhook: {data}")

                # Create test notification
                test_data = {
                    'type': 'test',
                    'message': data.get('message', 'Test webhook received'),
                    'timestamp': datetime.utcnow().isoformat(),
                    'source': 'webhook_manager'
                }

                await self._send_telegram_notification(test_data, 'test')

                return jsonify({
                    'status': 'ok',
                    'message': 'Test webhook processed successfully',
                    'data': test_data
                }), 200

            except Exception as e:
                logger.error(f"Error processing test webhook: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 500

    async def _process_helius_webhook(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Process Helius webhook data"""
        try:
            event_type = data.get('event_type', 'unknown')

            processed_data = {
                'provider': 'helius',
                'event_type': event_type,
                'timestamp': datetime.utcnow().isoformat(),
                'raw_data': data,
                'processed': True
            }

            # Handle different event types
            if event_type == 'token_launch':
                processed_data.update({
                    'title': '🚀 New Token Launch',
                    'token_address': data.get('token_address', 'unknown'),
                    'token_symbol': data.get('token_symbol', 'unknown'),
                    'lp_burned': data.get('lp_burned', 0),
                    'initial_liquidity': data.get('initial_liquidity', 0),
                    'urgency': 'high'
                })

            elif event_type == 'large_transaction':
                processed_data.update({
                    'title': '💰 Large Transaction',
                    'amount': data.get('amount', 0),
                    'token': data.get('token', 'unknown'),
                    'from_address': data.get('from_address', 'unknown'),
                    'to_address': data.get('to_address', 'unknown'),
                    'urgency': 'medium'
                })

            elif event_type == 'whale_movement':
                processed_data.update({
                    'title': '🐋 Whale Movement Detected',
                    'wallet': data.get('wallet', 'unknown'),
                    'amount': data.get('amount', 0),
                    'token': data.get('token', 'unknown'),
                    'action': data.get('action', 'unknown'),
                    'urgency': 'high'
                })

            else:
                processed_data.update({
                    'title': f'📡 Helius Event: {event_type}',
                    'urgency': 'low'
                })

            return processed_data

        except Exception as e:
            logger.error(f"Error processing Helius webhook: {e}")
            return {
                'provider': 'helius',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'processed': False
            }

    async def _process_quicknode_webhook(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Process QuickNode webhook data"""
        try:
            event_type = data.get('type', 'unknown')

            processed_data = {
                'provider': 'quicknode',
                'event_type': event_type,
                'timestamp': datetime.utcnow().isoformat(),
                'raw_data': data,
                'processed': True
            }

            # Handle different event types
            if event_type == 'bundle_submitted':
                processed_data.update({
                    'title': '📦 Jito Bundle Submitted',
                    'bundle_id': data.get('bundle_id', 'unknown'),
                    'transactions_count': data.get('transactions_count', 0),
                    'priority_fee': data.get('priority_fee', 0),
                    'urgency': 'high'
                })

            elif event_type == 'bundle_confirmed':
                processed_data.update({
                    'title': '✅ Jito Bundle Confirmed',
                    'bundle_id': data.get('bundle_id', 'unknown'),
                    'slot': data.get('slot', 0),
                    'profit': data.get('profit', 0),
                    'urgency': 'high'
                })

            elif event_type == 'nft_mint':
                processed_data.update({
                    'title': '🎨 NFT Mint Detected',
                    'collection': data.get('collection', 'unknown'),
                    'mint_address': data.get('mint_address', 'unknown'),
                    'price': data.get('price', 0),
                    'urgency': 'medium'
                })

            else:
                processed_data.update({
                    'title': f'📡 QuickNode Event: {event_type}',
                    'urgency': 'low'
                })

            return processed_data

        except Exception as e:
            logger.error(f"Error processing QuickNode webhook: {e}")
            return {
                'provider': 'quicknode',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat(),
                'processed': False
            }

    async def _publish_to_redis(self, channel: str, data: Dict[str, Any]):
        """Publish processed data to Redis for other services"""
        try:
            if self.redis_client:
                message = json.dumps(data)
                await self.redis_client.publish(f'webhook_events:{channel}', message)
                await self.redis_client.publish('webhook_events:all', message)
                logger.debug(f"Published webhook data to Redis channel: {channel}")
            else:
                logger.warning("Redis client not available - skipping Redis publish")

        except Exception as e:
            logger.error(f"Error publishing to Redis: {e}")

    async def _send_telegram_notification(self, data: Dict[str, Any], source: str):
        """Send notification to Telegram"""
        try:
            if not self.telegram_bot or not self.telegram_chat_id:
                logger.debug("Telegram not configured - skipping notification")
                return

            # Format message
            title = data.get('title', 'Webhook Event')
            urgency_emoji = {
                'high': '🔴',
                'medium': '🟡',
                'low': '🟢'
            }.get(data.get('urgency', 'low'), '🔵')

            message = f"{urgency_emoji} *{title}*\n\n"
            message += f"📡 Source: {source.title()}\n"
            message += f"⏰ Time: {data.get('timestamp', 'unknown')}\n"

            # Add specific details based on event type
            if 'token_address' in data:
                message += f"🪙 Token: `{data['token_address']}`\n"
            if 'token_symbol' in data:
                message += f"📈 Symbol: {data['token_symbol']}\n"
            if 'lp_burned' in data:
                message += f"🔥 LP Burned: {data['lp_burned']}%\n"
            if 'amount' in data:
                message += f"💰 Amount: {data['amount']:,}\n"
            if 'bundle_id' in data:
                message += f"📦 Bundle ID: `{data['bundle_id']}`\n"
            if 'error' in data:
                message += f"❌ Error: {data['error']}\n"

            message += f"\n📊 Processed by WebhookManager"

            # Send message
            await self.telegram_bot.send_message(
                chat_id=self.telegram_chat_id,
                text=message,
                parse_mode='Markdown'
            )

            self.webhook_stats['telegram_sent'] += 1
            logger.info(f"Telegram notification sent for {source} event")

        except Exception as e:
            logger.error(f"Error sending Telegram notification: {e}")

    async def get_stats(self) -> Dict[str, Any]:
        """Get webhook statistics"""
        uptime = time.time() - self.webhook_stats['start_time']

        return {
            **self.webhook_stats,
            'uptime_seconds': uptime,
            'uptime_formatted': f"{uptime/3600:.1f}h",
            'processing_rate': self.webhook_stats['processed'] / max(uptime, 1),
            'error_rate': self.webhook_stats['errors'] / max(self.webhook_stats['total_received'], 1) * 100
        }

# Global webhook manager instance
webhook_manager = WebhookManager()

async def create_app():
    """Create and initialize Quart app"""
    await webhook_manager.initialize()
    return webhook_manager.app

# Flask compatibility wrapper
def create_flask_app():
    """Create Flask app for compatibility"""
    flask_app = Flask(__name__)

    @flask_app.route('/health', methods=['GET'])
    def health_check():
        return jsonify({'status': 'healthy'})

    @flask_app.route('/webhook/helius', methods=['POST'])
    def helius_webhook():
        data = request.get_json()
        logger.info(f"Flask received Helius webhook: {data.get('event_type', 'unknown')}")
        return jsonify({'status': 'ok'})

    @flask_app.route('/webhook/quicknode', methods=['POST'])
    def quicknode_webhook():
        data = request.get_json()
        logger.info(f"Flask received QuickNode webhook: {data.get('type', 'unknown')}")
        return jsonify({'status': 'ok'})

    return flask_app

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description='Webhook Manager for Trading Alerts')
    parser.add_argument('--host', default='0.0.0.0', help='Host to bind to')
    parser.add_argument('--port', type=int, default=8082, help='Port to bind to')
    parser.add_argument('--flask', action='store_true', help='Use Flask instead of Quart')
    args = parser.parse_args()

    if args.flask:
        # Use Flask (synchronous)
        app = create_flask_app()
        logger.info(f"Starting Flask webhook manager on {args.host}:{args.port}")
        app.run(host=args.host, port=args.port, debug=False)
    else:
        # Use Quart (asynchronous)
        async def main():
            app = await create_app()
            logger.info(f"Starting Quart webhook manager on {args.host}:{args.port}")
            await app.run_task(host=args.host, port=args.port)

        asyncio.run(main())