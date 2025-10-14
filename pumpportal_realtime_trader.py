#!/usr/bin/env python3
"""
PumpPortal Real-Time Trader
WebSocket-based real-time trading for PumpFun tokens with advanced sniper filters
"""

import asyncio
import websockets
import json
import time
import logging
import os
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, asdict
import aiohttp
import hashlib

# Import TradingSignal for Mojo pipeline integration
try:
    from core.types import TradingSignal
except ImportError:
    # Fallback definition if Mojo types aren't available
    class TradingSignal:
        def __init__(self, symbol: str, signal_type: str, confidence: float,
                     timestamp: float, price: float, volume_5m: float, metadata: Dict):
            self.symbol = symbol
            self.signal_type = signal_type
            self.confidence = confidence
            self.timestamp = timestamp
            self.price = price
            self.volume_5m = volume_5m
            self.metadata = metadata

# Add project root to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

@dataclass
class PumpToken:
    """PumpFun token data structure"""
    address: str
    symbol: str
    name: str
    bonding_curve: str
    associated_bonding_curve: str
    creator: str
    created_timestamp: int
    description: str
    image_uri: str
    metadata_uri: str
    twitter: Optional[str]
    telegram: Optional[str]
    website: Optional[str]
    show_name: bool
    king_of_the_hill: bool
    market_cap: float
    usd_market_cap: float
    reply_count: int
    last_reply_timestamp: int
    complete: bool
    virtual_sol_reserves: float
    virtual_token_reserves: float
    real_sol_reserves: float
    real_token_reserves: float
    token_supply: float
    holder_count: int

@dataclass
class SniperAnalysis:
    """Sniper filter analysis results"""
    token_address: str
    symbol: str
    lp_burn_rate: float
    authorities_revoked: bool
    holder_distribution_safe: bool
    social_mentions: int
    social_sentiment: float
    honeypot_safe: bool
    overall_score: float
    recommendation: str
    analysis_timestamp: float

@dataclass
class TradePosition:
    """Trading position data structure"""
    token_address: str
    symbol: str
    entry_price: float
    entry_time: float
    position_size: float
    take_profit: float
    stop_loss: float
    status: str  # 'active', 'closed_tp', 'closed_sl', 'closed_manual'
    pnl: float = 0.0
    exit_price: Optional[float] = None
    exit_time: Optional[float] = None
    exit_reason: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

class PumpPortalTrader:
    """
    Real-time PumpFun token trader with advanced sniper filtering
    """

    def __init__(self):
        self.setup_logging()
        self.load_config()

        # Trading state
        self.positions: Dict[str, TradePosition] = {}
        self.wallet_balance = self.config.get('initial_sol_balance', 1.0)
        self.is_running = False

        # WebSocket connection
        self.ws_url = "wss://www.pumpportal.fun/api/data"
        self.session: Optional[aiohttp.ClientSession] = None
        self.websocket: Optional[websockets.WebSocketClientProtocol] = None

        # Rate limiting
        self.last_trade_time = 0
        self.min_trade_interval = self.config.get('min_trade_interval_seconds', 30)

        # Sniper filter settings
        self.sniper_config = self.config.get('sniper_filters', {})

        # Statistics
        self.stats = {
            'tokens_seen': 0,
            'tokens_analyzed': 0,
            'signals_generated': 0,
            'trades_executed': 0,
            'winning_trades': 0,
            'losing_trades': 0,
            'total_pnl': 0.0,
            'rejections': {
                'lp_burn': 0,
                'authority': 0,
                'distribution': 0,
                'social': 0,
                'honeypot': 0
            }
        }

        self.logger.info("PumpPortal Trader initialized")

    def setup_logging(self):
        """Setup logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('pumpportal_trader.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger('PumpPortalTrader')

    def load_config(self):
        """Load configuration from environment variables"""
        self.config = {
            # Trading parameters
            'initial_sol_balance': float(os.getenv('INITIAL_SOL_BALANCE', '1.0')),
            'max_position_size': float(os.getenv('MAX_POSITION_SIZE', '0.1')),
            'min_trade_interval_seconds': int(os.getenv('MIN_TRADE_INTERVAL_SECONDS', '30')),
            'max_open_positions': int(os.getenv('MAX_OPEN_POSITIONS', '5')),

            # API settings
            'helius_api_key': os.getenv('HELIUS_API_KEY', ''),
            'honeypot_api_key': os.getenv('HONEYPOT_API_KEY', ''),
            'twitter_api_key': os.getenv('TWITTER_API_KEY', ''),

            # Sniper filter settings
            'sniper_filters': {
                'min_lp_burn_rate': float(os.getenv('MIN_LP_BURN_RATE', '90.0')),
                'revoke_authority_required': os.getenv('REVOKE_AUTHORITY_REQUIRED', 'true').lower() == 'true',
                'max_top_holders_share': float(os.getenv('MAX_TOP_HOLDERS_SHARE', '30.0')),
                'min_social_mentions': int(os.getenv('MIN_SOCIAL_MENTIONS', '10')),
                'social_check_enabled': os.getenv('SOCIAL_CHECK_ENABLED', 'true').lower() == 'true',
                'honeypot_check': os.getenv('HONEYPOT_CHECK', 'true').lower() == 'true',
                'tp_threshold': float(os.getenv('TP_THRESHOLD', '1.5')),
                'sl_threshold': float(os.getenv('SL_THRESHOLD', '0.8')),
                'min_market_cap': float(os.getenv('MIN_MARKET_CAP', '10000.0'))
            }
        }

    async def start(self):
        """Start the real-time trader"""
        self.print_banner()

        try:
            self.session = aiohttp.ClientSession()
            self.is_running = True

            self.logger.info("Starting PumpPortal real-time trader...")

            # Start WebSocket connection
            await self.connect_websocket()

        except Exception as e:
            self.logger.error(f"Failed to start trader: {e}")
            await self.shutdown()

    async def connect_websocket(self):
        """Connect to PumpPortal WebSocket"""
        try:
            self.websocket = await websockets.connect(self.ws_url)
            self.logger.info("Connected to PumpPortal WebSocket")

            # Subscribe to new token events
            await self.subscribe_new_tokens()

            # Start listening for messages
            await self.listen_websocket()

        except Exception as e:
            self.logger.error(f"WebSocket connection failed: {e}")
            await self.shutdown()

    async def subscribe_new_tokens(self):
        """Subscribe to new token creation events"""
        try:
            subscribe_message = {
                "method": "subscribeNewToken",
                "params": {}
            }

            await self.websocket.send(json.dumps(subscribe_message))
            self.logger.info("Subscribed to new token events")

        except Exception as e:
            self.logger.error(f"Failed to subscribe to new tokens: {e}")
            raise

    async def listen_websocket(self):
        """Listen for WebSocket messages"""
        try:
            async for message in self.websocket:
                if not self.is_running:
                    break

                try:
                    data = json.loads(message)

                    # Handle different message types
                    if isinstance(data, dict):
                        if data.get("method") == "newToken":
                            # New token creation event
                            token_data = data.get("params", {})
                            await self.process_token_data(token_data)
                        elif data.get("method") == "tokenUpdate":
                            # Token update event (price/volume changes)
                            token_data = data.get("params", {})
                            await self.process_token_update(token_data)
                        elif "error" in data:
                            # Error message
                            self.logger.error(f"WebSocket error: {data['error']}")
                        else:
                            # Unknown message type
                            self.logger.debug(f"Unknown message type: {data}")
                    else:
                        # Handle legacy/flat token data format
                        await self.process_token_data(data)

                except json.JSONDecodeError:
                    self.logger.warning(f"Invalid JSON received: {message}")
                except Exception as e:
                    self.logger.error(f"Error processing message: {e}")

        except websockets.exceptions.ConnectionClosed:
            self.logger.warning("WebSocket connection closed")
            await self.reconnect_websocket()
        except Exception as e:
            self.logger.error(f"WebSocket listening error: {e}")
            await self.reconnect_websocket()

    async def reconnect_websocket(self):
        """Reconnect to WebSocket"""
        if self.is_running:
            self.logger.info("Attempting to reconnect...")
            await asyncio.sleep(5)
            await self.connect_websocket()

    async def process_token_data(self, data: Dict):
        """Process incoming token data"""
        try:
            # Parse token data
            token = self.parse_token_data(data)
            if not token:
                return

            self.stats['tokens_seen'] += 1

            # Filter tokens that meet basic criteria
            if not self.passes_basic_filters(token):
                return

            self.stats['tokens_analyzed'] += 1

            # Apply advanced sniper filters
            sniper_analysis = await self.run_sniper_analysis(token)

            if sniper_analysis.recommendation == 'proceed':
                await self.generate_trading_signal(token, sniper_analysis)
            else:
                self.track_rejection(sniper_analysis)

        except Exception as e:
            self.logger.error(f"Error processing token data: {e}")

    async def process_token_update(self, data: Dict):
        """Process token update events (price/volume changes)"""
        try:
            token_address = data.get('mint', '')
            if not token_address or token_address not in self.positions:
                return

            # Update position data with new price information
            position = self.positions[token_address]
            current_price = float(data.get('price', position.entry_price))
            volume_5m = float(data.get('volume_5m', 0.0))

            # Store volume data for sniper analysis
            position.metadata = getattr(position, 'metadata', {})
            position.metadata['volume_5m'] = volume_5m

            self.logger.debug(f"Token update: {position.symbol} @ {current_price:.8f} SOL, Volume: {volume_5m:.2f}")

        except Exception as e:
            self.logger.error(f"Error processing token update: {e}")

    def parse_token_data(self, data: Dict) -> Optional[PumpToken]:
        """Parse token data from WebSocket message"""
        try:
            return PumpToken(
                address=data.get('mint', ''),
                symbol=data.get('symbol', ''),
                name=data.get('name', ''),
                bonding_curve=data.get('bondingCurve', ''),
                associated_bonding_curve=data.get('associatedBondingCurve', ''),
                creator=data.get('creator', ''),
                created_timestamp=data.get('created_timestamp', 0),
                description=data.get('description', ''),
                image_uri=data.get('imageUri', ''),
                metadata_uri=data.get('metadataUri', ''),
                twitter=data.get('twitter'),
                telegram=data.get('telegram'),
                website=data.get('website'),
                show_name=data.get('showName', False),
                king_of_the_hill=data.get('kingOfTheHill', False),
                market_cap=float(data.get('marketCap', 0)),
                usd_market_cap=float(data.get('usdMarketCap', 0)),
                reply_count=int(data.get('replyCount', 0)),
                last_reply_timestamp=int(data.get('lastReplyTimestamp', 0)),
                complete=data.get('complete', False),
                virtual_sol_reserves=float(data.get('virtualSolReserves', 0)),
                virtual_token_reserves=float(data.get('virtualTokenReserves', 0)),
                real_sol_reserves=float(data.get('realSolReserves', 0)),
                real_token_reserves=float(data.get('realTokenReserves', 0)),
                token_supply=float(data.get('tokenSupply', 0)),
                holder_count=int(data.get('holderCount', 0))
            )
        except Exception as e:
            self.logger.error(f"Error parsing token data: {e}")
            return None

    def passes_basic_filters(self, token: PumpToken) -> bool:
        """Check if token passes basic filters"""
        # Minimum market cap filter
        if token.usd_market_cap < self.sniper_config['min_market_cap']:
            return False

        # Avoid tokens that are too old (> 1 hour)
        token_age = time.time() - token.created_timestamp
        if token_age > 3600:
            return False

        # Avoid tokens that are too new (< 1 minute)
        if token_age < 60:
            return False

        # Must have some description
        if not token.description or len(token.description) < 10:
            return False

        return True

    async def run_sniper_analysis(self, token: PumpToken) -> SniperAnalysis:
        """Run comprehensive sniper analysis on token"""
        try:
            # Import HeliusClient for real API calls
            from data.helius_client import HeliusClient

            # Initialize Helius client with real API
            helius_client = HeliusClient(
                api_key=self.config['helius_api_key'],
                enabled=self.config['helius_api_key'] != ""
            )

            # Get real LP burn rate
            lp_analysis = await helius_client.check_lp_burn_rate(token.address)
            lp_burn_rate = lp_analysis.get("lp_burn_rate", 0.0)

            # Get real authority revocation status
            authority_analysis = await helius_client.check_authority_revocation(token.address)
            authorities_revoked = authority_analysis.get("authority_revocation_complete", False)

            # Get real holder distribution analysis
            distribution_analysis = await helius_client.get_holder_distribution_analysis(token.address)
            top_holders_share = distribution_analysis.get("top_holders_share", 100.0)
            holder_distribution_safe = top_holders_share <= self.sniper_config['max_top_holders_share']

            # Check social mentions if enabled and client is available
            social_mentions = 0
            social_sentiment = 0.0
            if self.sniper_config['social_check_enabled']:
                try:
                    from data.social_client import SocialClient
                    social_client = SocialClient(
                        twitter_api_key=self.config['twitter_api_key'],
                        enabled=self.config['twitter_api_key'] != ""
                    )

                    if social_client.enabled:
                        social_analysis = social_client.comprehensive_social_analysis(
                            token.symbol,
                            token.address,
                            self.sniper_config['min_social_mentions']
                        )
                        social_mentions = social_analysis.get("total_mentions", 0)
                        social_sentiment = social_analysis.get("sentiment_details", {}).get("current_sentiment_score", 0.0)
                except Exception as e:
                    self.logger.warning(f"Social client error: {e}")

            # Check honeypot status if enabled
            honeypot_safe = True
            if self.sniper_config['honeypot_check']:
                try:
                    from data.honeypot_client import HoneypotClient
                    honeypot_client = HoneypotClient(
                        api_key=self.config['honeypot_api_key'],
                        enabled=self.config['honeypot_api_key'] != ""
                    )

                    if honeypot_client.enabled:
                        honeypot_analysis = honeypot_client.comprehensive_honeypot_analysis(token.address)
                        honeypot_safe = honeypot_analysis.get("is_safe_for_sniping", False)
                except Exception as e:
                    self.logger.warning(f"Honeypot client error: {e}")

            # Calculate overall score
            score = 0.0
            if lp_burn_rate >= self.sniper_config['min_lp_burn_rate']:
                score += 0.25
            if authorities_revoked == self.sniper_config['revoke_authority_required']:
                score += 0.25
            if holder_distribution_safe:
                score += 0.20
            if social_mentions >= self.sniper_config['min_social_mentions']:
                score += 0.15
            if honeypot_safe:
                score += 0.15

            recommendation = 'proceed' if score >= 0.7 else 'avoid' if score < 0.4 else 'caution'

            return SniperAnalysis(
                token_address=token.address,
                symbol=token.symbol,
                lp_burn_rate=lp_burn_rate,
                authorities_revoked=authorities_revoked,
                holder_distribution_safe=holder_distribution_safe,
                social_mentions=social_mentions,
                social_sentiment=social_sentiment,
                honeypot_safe=honeypot_safe,
                overall_score=score,
                recommendation=recommendation,
                analysis_timestamp=time.time(),
                analysis_details={
                    "lp_analysis": lp_analysis,
                    "authority_analysis": authority_analysis,
                    "distribution_analysis": distribution_analysis
                }
            )

        except Exception as e:
            self.logger.error(f"Error in sniper analysis: {e}")
            return SniperAnalysis(
                token_address=token.address,
                symbol=token.symbol,
                lp_burn_rate=0.0,
                authorities_revoked=False,
                holder_distribution_safe=False,
                social_mentions=0,
                social_sentiment=0.0,
                honeypot_safe=False,
                overall_score=0.0,
                recommendation='avoid',
                analysis_timestamp=time.time()
            )

    async def generate_trading_signal(self, token: PumpToken, analysis: SniperAnalysis):
        """Generate trading signal and call into Mojo pipeline"""
        try:
            # Create TradingSignal object for Mojo pipeline
            signal = TradingSignal(
                symbol=token.symbol,
                signal_type='BUY',
                confidence=analysis.overall_score,
                timestamp=time.time(),
                price=token.usd_market_cap / token.token_supply if token.token_supply > 0 else 0.00001,
                volume_5m=float(token.real_sol_reserves),  # Use real SOL reserves as volume indicator
                metadata={
                    # Required sniper candidate metadata
                    'is_sniper_candidate': True,
                    'token_address': token.address,
                    'creator': token.creator,
                    'created_timestamp': token.created_timestamp,
                    'market_cap': token.usd_market_cap,
                    'description': token.description,
                    'twitter': token.twitter,
                    'telegram': token.telegram,
                    'website': token.website,

                    # Sniper filter analysis results
                    'lp_burn_rate': analysis.lp_burn_rate,
                    'authorities_revoked': analysis.authorities_revoked,
                    'holder_distribution_safe': analysis.holder_distribution_safe,
                    'social_mentions': analysis.social_mentions,
                    'honeypot_safe': analysis.honeypot_safe,
                    'sniper_score': analysis.overall_score,
                    'recommendation': analysis.recommendation,

                    # Volume and liquidity data
                    'virtual_sol_reserves': token.virtual_sol_reserves,
                    'virtual_token_reserves': token.virtual_token_reserves,
                    'real_sol_reserves': token.real_sol_reserves,
                    'real_token_reserves': token.real_token_reserves,
                    'holder_count': token.holder_count,
                    'bonding_curve': token.bonding_curve,
                    'associated_bonding_curve': token.associated_bonding_curve,

                    # TP/SL thresholds for sniper execution
                    'tp_threshold': self.sniper_config['tp_threshold'],
                    'sl_threshold': self.sniper_config['sl_threshold']
                }
            )

            # Log signal generation
            self.logger.info(f"🎯 SNIPER SIGNAL GENERATED: {token.symbol} | "
                           f"Score: {analysis.overall_score:.3f} | "
                           f"LP Burn: {analysis.lp_burn_rate:.1f}% | "
                           f"Social: {analysis.social_mentions} | "
                           f"Market Cap: ${token.usd_market_cap:,.0f}")

            # Call into Mojo pipeline by sending signal to master filter
            await self.send_to_mojo_pipeline(signal)

            self.stats['signals_generated'] += 1

        except Exception as e:
            self.logger.error(f"Error generating trading signal: {e}")

    async def send_to_mojo_pipeline(self, signal: TradingSignal):
        """Send trading signal to Mojo pipeline via MasterFilter"""
        try:
            # Import the Mojo master filter (this would be called via FFI)
            # For now, log the signal that would be sent
            self.logger.info(f"🚀 SENDING TO MOJO PIPELINE: {signal.symbol} | "
                           f"Price: {signal.price:.8f} | "
                           f"Confidence: {signal.confidence:.3f} | "
                           f"Volume: {signal.volume_5m:.2f} | "
                           f"Sniper Candidate: {signal.metadata.get('is_sniper_candidate', False)}")

            # In the actual implementation, this would call:
            # from engine.master_filter import MasterFilter
            # master_filter = MasterFilter(helius_client, config)
            # filtered_signals = master_filter.filter_all_signals([signal])
            #
            # For each filtered signal, execute the trade:
            # for filtered_signal in filtered_signals:
            #     await self.execute_sniper_trade(filtered_signal)

            # For now, execute the trade directly
            await self.execute_sniper_trade(signal)

        except Exception as e:
            self.logger.error(f"Error sending signal to Mojo pipeline: {e}")

    async def execute_sniper_trade(self, signal: TradingSignal):
        """Execute sniper trade based on filtered signal"""
        try:
            # Check if we have too many open positions
            if len(self.positions) >= self.config['max_open_positions']:
                self.logger.info(f"Max positions reached, skipping {signal.symbol}")
                return

            # Check trade rate limiting
            current_time = time.time()
            if current_time - self.last_trade_time < self.min_trade_interval:
                self.logger.info(f"Rate limiting, skipping {signal.symbol}")
                return

            # Calculate position size
            position_size = min(
                self.wallet_balance * self.config['max_position_size'],
                self.wallet_balance * 0.2  # Max 20% per trade
            )

            if position_size < 0.001:  # Minimum position size
                self.logger.info(f"Position too small, skipping {signal.symbol}")
                return

            # Extract TP/SL thresholds from signal metadata
            tp_threshold = signal.metadata.get('tp_threshold', self.sniper_config['tp_threshold'])
            sl_threshold = signal.metadata.get('sl_threshold', self.sniper_config['sl_threshold'])

            # Calculate TP/SL based on sniper thresholds
            take_profit = signal.price * tp_threshold
            stop_loss = signal.price * sl_threshold

            # Create position
            position = TradePosition(
                token_address=signal.metadata.get('token_address', ''),
                symbol=signal.symbol,
                entry_price=signal.price,
                entry_time=current_time,
                position_size=position_size,
                take_profit=take_profit,
                stop_loss=stop_loss,
                status='active',
                metadata=signal.metadata
            )

            self.positions[signal.metadata.get('token_address', '')] = position
            self.wallet_balance -= position_size
            self.last_trade_time = current_time

            self.stats['trades_executed'] += 1

            self.logger.info(f"🚀 SNIPER BUY {signal.symbol} @ {signal.price:.8f} SOL | "
                           f"Size: {position_size:.4f} SOL | "
                           f"TP: {take_profit:.8f} | SL: {stop_loss:.8f} | "
                           f"Score: {signal.confidence:.3f}")

            # Start monitoring this position
            asyncio.create_task(self.monitor_position(position, None))

        except Exception as e:
            self.logger.error(f"Error executing sniper trade: {e}")

    def track_rejection(self, analysis: SniperAnalysis):
        """Track rejection reasons for statistics"""
        if analysis.lp_burn_rate < self.sniper_config['min_lp_burn_rate']:
            self.stats['rejections']['lp_burn'] += 1
        elif analysis.authorities_revoked != self.sniper_config['revoke_authority_required']:
            self.stats['rejections']['authority'] += 1
        elif not analysis.holder_distribution_safe:
            self.stats['rejections']['distribution'] += 1
        elif analysis.social_mentions < self.sniper_config['min_social_mentions']:
            self.stats['rejections']['social'] += 1
        elif not analysis.honeypot_safe:
            self.stats['rejections']['honeypot'] += 1

    async def monitor_position(self, position: TradePosition, token: PumpToken):
        """Monitor position for exit conditions"""
        while position.status == 'active' and self.is_running:
            try:
                # Get current price (mock price tracking)
                current_time = time.time()
                time_elapsed = current_time - position.entry_time

                # Simulate price movement (in production, get real price)
                price_change = 0.0
                if time_elapsed < 300:  # First 5 minutes: potential pump
                    price_change = (hash(token.symbol + str(int(time_elapsed))) % 200 - 100) / 10000
                else:  # After 5 minutes: more volatile
                    price_change = (hash(token.symbol + str(int(time_elapsed))) % 400 - 200) / 10000

                current_price = position.entry_price * (1 + price_change)

                # Check exit conditions
                should_exit = False
                exit_reason = None
                exit_price = current_price

                if current_price >= position.take_profit:
                    should_exit = True
                    exit_reason = 'TAKE_PROFIT'
                    exit_price = position.take_profit
                elif current_price <= position.stop_loss:
                    should_exit = True
                    exit_reason = 'STOP_LOSS'
                    exit_price = position.stop_loss
                elif time_elapsed > 1800:  # 30 minutes timeout
                    should_exit = True
                    exit_reason = 'TIMEOUT'
                elif time_elapsed > 600 and position.entry_price * 1.1 <= current_price <= position.entry_price * 1.2:
                    # Take partial profits if up 10-20% after 10 minutes
                    should_exit = True
                    exit_reason = 'PARTIAL_PROFIT'

                if should_exit:
                    await self.close_position(position, exit_price, exit_reason)
                    break

                # Check every 5 seconds
                await asyncio.sleep(5)

            except Exception as e:
                self.logger.error(f"Error monitoring position {position.symbol}: {e}")
                await asyncio.sleep(5)

    async def close_position(self, position: TradePosition, exit_price: float, reason: str):
        """Close trading position"""
        try:
            # Calculate P&L
            pnl_percentage = (exit_price - position.entry_price) / position.entry_price
            pnl = position.position_size * pnl_percentage

            # Update position
            position.exit_price = exit_price
            position.exit_time = time.time()
            position.exit_reason = reason
            position.pnl = pnl

            # Update wallet balance
            returned_amount = position.position_size * (1 + pnl_percentage)
            self.wallet_balance += returned_amount

            # Update statistics
            if pnl > 0:
                self.stats['winning_trades'] += 1
                status = 'closed_tp'
            else:
                self.stats['losing_trades'] += 1
                status = 'closed_sl'

            self.stats['total_pnl'] += pnl
            position.status = status

            # Log trade exit
            emoji = "✅" if pnl > 0 else "❌"
            self.logger.info(f"{emoji} SELL {position.symbol} @ {exit_price:.8f} SOL | "
                           f"Reason: {reason} | "
                           f"P&L: {pnl:.6f} SOL ({pnl_percentage:.2%}) | "
                           f"Duration: {(position.exit_time - position.entry_time):.1f}s")

        except Exception as e:
            self.logger.error(f"Error closing position {position.symbol}: {e}")

    def print_banner(self):
        """Print trading bot banner"""
        print("""
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║    🎯 PumpPortal Real-Time Sniper Trader 🎯                 ║
    ║                                                              ║
    ║    Advanced Filtering | Real-Time Execution | MEV Ready      ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
    """)
        print(f"🔧 Configuration:")
        print(f"   Initial Balance: {self.config['initial_sol_balance']} SOL")
        print(f"   Max Position Size: {self.config['max_position_size']:.1%}")
        print(f"   Max Open Positions: {self.config['max_open_positions']}")
        print(f"   Min Trade Interval: {self.config['min_trade_interval_seconds']}s")
        print(f"   LP Burn Threshold: {self.sniper_config['min_lp_burn_rate']:.1f}%")
        print(f"   Min Social Mentions: {self.sniper_config['min_social_mentions']}")
        print(f"   TP/SL: {self.sniper_config['tp_threshold']:.1f}x/{self.sniper_config['sl_threshold']:.1f}x")
        print(f"   Min Market Cap: ${self.sniper_config['min_market_cap']:,.0f}")
        print("")

    def print_statistics(self):
        """Print current trading statistics"""
        print("\n" + "="*80)
        print("📊 PUMPPORTAL TRADER STATISTICS")
        print("="*80)
        print(f"📈 Tokens Seen: {self.stats['tokens_seen']:,}")
        print(f"🔍 Tokens Analyzed: {self.stats['tokens_analyzed']:,}")
        print(f"📊 Signals Generated: {self.stats['signals_generated']:,}")
        print(f"💰 Trades Executed: {self.stats['trades_executed']:,}")
        print(f"🏆 Winning Trades: {self.stats['winning_trades']:,}")
        print(f"📉 Losing Trades: {self.stats['losing_trades']:,}")
        print(f"💵 Total P&L: {self.stats['total_pnl']:.6f} SOL")
        print(f"💼 Current Balance: {self.wallet_balance:.6f} SOL")
        print(f"📊 Open Positions: {len(self.positions)}")

        if self.stats['trades_executed'] > 0:
            win_rate = self.stats['winning_trades'] / self.stats['trades_executed']
            print(f"🎯 Win Rate: {win_rate:.1%}")

        print(f"\n🛡️  Rejection Breakdown:")
        total_rejections = sum(self.stats['rejections'].values())
        for reason, count in self.stats['rejections'].items():
            percentage = (count / total_rejections * 100) if total_rejections > 0 else 0
            print(f"   {reason.title()}: {count} ({percentage:.1f}%)")

        print("="*80)

    async def shutdown(self):
        """Shutdown the trader"""
        self.is_running = False
        self.logger.info("Shutting down PumpPortal trader...")

        if self.websocket:
            await self.websocket.close()
        if self.session:
            await self.session.close()

        # Close all open positions
        for position in list(self.positions.values()):
            if position.status == 'active':
                await self.close_position(position, position.entry_price, 'SHUTDOWN')

        self.print_statistics()
        self.logger.info("PumpPortal trader shutdown complete")

def main():
    """Main entry point"""
    trader = PumpPortalTrader()

    try:
        asyncio.run(trader.start())
    except KeyboardInterrupt:
        print("\n👋 Shutting down...")
        asyncio.run(trader.shutdown())
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        asyncio.run(trader.shutdown())

if __name__ == "__main__":
    main()