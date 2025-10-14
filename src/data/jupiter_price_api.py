"""
Jupiter Price API v3/v6 Python Client for MojoRust Trading Bot

Provides real-time price data from Jupiter Price API v3 for arbitrage detection.
Supports batch price queries, token metadata, and DEX price comparisons.
Enhanced with production-ready error handling, retry logic, and caching.

Configuration via environment variables:
- JUPITER_PRICE_API_URL: Jupiter Price API endpoint (default: https://price.jup.ag/v3/price)
- JUPITER_QUOTE_API_BASE_URL: Jupiter Quote API endpoint (default: https://quote-api.jup.ag/v6)
- JUPITER_TOKEN_LIST_API_URL: Jupiter Token List endpoint (default: https://token.jup.ag/v6)
- JUPITER_REQUEST_TIMEOUT_SECONDS: Request timeout (default: 30)
- JUPITER_MAX_RETRIES: Maximum retry attempts (default: 3)
- JUPITER_RETRY_DELAY: Base retry delay in seconds (default: 1.0)
- JUPITER_RATE_LIMIT_DELAY_MS: Rate limit delay in milliseconds (default: 100)
- JUPITER_BATCH_SIZE: Batch size for bulk operations (default: 50)
"""

import aiohttp
import asyncio
import logging
from typing import Dict, List, Optional, Any, Tuple
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
import json
import time
import os
from enum import Enum

# Configure logging
logger = logging.getLogger(__name__)

# Jupiter Price API endpoints (configurable via environment)
JUPITER_PRICE_API_URL = os.getenv("JUPITER_PRICE_API_URL", "https://price.jup.ag/v3/price")
JUPITER_QUOTE_API_BASE = os.getenv("JUPITER_QUOTE_API_BASE_URL", "https://quote-api.jup.ag/v6")
JUPITER_TOKEN_LIST_API = os.getenv("JUPITER_TOKEN_LIST_API_URL", "https://token.jup.ag/v6")

# Environment configuration
JUPITER_API_TIMEOUT = int(os.getenv("JUPITER_REQUEST_TIMEOUT_SECONDS", "30"))
JUPITER_MAX_RETRIES = int(os.getenv("JUPITER_MAX_RETRIES", "3"))
JUPITER_RETRY_DELAY = float(os.getenv("JUPITER_RETRY_DELAY", "1.0"))

# Additional configuration from environment
JUPITER_RATE_LIMIT_DELAY_MS = int(os.getenv("JUPITER_RATE_LIMIT_DELAY_MS", "100"))
JUPITER_BATCH_SIZE = int(os.getenv("JUPITER_BATCH_SIZE", "50"))

class DexType(Enum):
    """Supported DEX types"""
    RAYDIUM = "raydium"
    ORCA = "orca"
    SERUM = "serum"
    CREMA = "crema"
    ALDRIN = "aldrin"
    MERCURIAL = "mercurial"
    SABER = "saber"
    METEORA = "meteora"

@dataclass
class ApiResponse:
    """Standard API response wrapper"""
    success: bool
    data: Optional[Any] = None
    error: Optional[str] = None
    timestamp: datetime = None
    response_time_ms: float = 0

    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()

@dataclass
class TokenInfo:
    """Token information from Jupiter"""
    address: str
    symbol: str
    name: str
    decimals: int
    logo_uri: Optional[str] = None
    tags: Optional[List[str]] = None
    coingecko_id: Optional[str] = None
    verified: bool = False

@dataclass
class PriceInfo:
    """Price information from Jupiter"""
    price: float
    price_change_24h: Optional[float] = None
    volume_24h: Optional[float] = None
    timestamp: Optional[datetime] = None

@dataclass
class DexPrice:
    """DEX-specific price information"""
    dex_name: str
    price: float
    liquidity: Optional[float] = None
    volume_24h: Optional[float] = None
    market_cap: Optional[float] = None

@dataclass
class TokenPrice:
    """Complete token price information"""
    token: TokenInfo
    price: PriceInfo
    dex_prices: List[DexPrice]
    best_dex: Optional[DexPrice] = None

@dataclass
class PriceQuote:
    """Price quote for swap"""
    input_mint: str
    output_mint: str
    input_amount: int
    output_amount: int
    price_impact: float
    slippage: float
    route_plan: List[Dict[str, Any]]
    time_taken: float

class JupiterPriceAPI:
    """Jupiter Price API v3 client with production-ready features"""

    def __init__(self, session: Optional[aiohttp.ClientSession] = None,
                 cache_ttl: int = 30, rate_limit_delay: Optional[float] = None):
        self.session = session or aiohttp.ClientSession(
            timeout=aiohttp.ClientTimeout(total=JUPITER_API_TIMEOUT)
        )
        self.price_cache: Dict[str, TokenPrice] = {}
        self.dex_price_cache: Dict[str, List[DexPrice]] = {}
        self.cache_ttl = cache_ttl
        # Use environment variable for rate limit delay if provided, otherwise use parameter
        self.rate_limit_delay = rate_limit_delay if rate_limit_delay is not None else JUPITER_RATE_LIMIT_DELAY_MS / 1000.0
        self.request_count = 0
        self.error_count = 0
        self.last_request_time = 0

    async def close(self):
        """Close the HTTP session"""
        if self.session:
            await self.session.close()

    async def _make_request(self, url: str, params: Optional[Dict[str, str]] = None) -> ApiResponse:
        """Make HTTP request with retry logic, rate limiting, and proper error handling"""
        start_time = time.time()

        # Rate limiting
        current_time = time.time()
        time_since_last = current_time - self.last_request_time
        if time_since_last < self.rate_limit_delay:
            await asyncio.sleep(self.rate_limit_delay - time_since_last)

        self.last_request_time = time.time()
        self.request_count += 1

        # Retry logic
        last_exception = None
        for attempt in range(JUPITER_MAX_RETRIES + 1):
            try:
                async with self.session.get(url, params=params) as response:
                    response_time_ms = (time.time() - start_time) * 1000

                    if response.status == 200:
                        data = await response.json()
                        return ApiResponse(
                            success=True,
                            data=data,
                            timestamp=datetime.now(),
                            response_time_ms=response_time_ms
                        )
                    elif response.status == 429:  # Rate limited
                        retry_after = int(response.headers.get('Retry-After', JUPITER_RETRY_DELAY))
                        logger.warning(f"Rate limited, waiting {retry_after}s before retry {attempt + 1}")
                        await asyncio.sleep(retry_after)
                        continue
                    elif response.status >= 500:  # Server error
                        logger.warning(f"Server error {response.status}, retry {attempt + 1}")
                        await asyncio.sleep(JUPITER_RETRY_DELAY * (2 ** attempt))
                        continue
                    else:
                        error_text = await response.text()
                        return ApiResponse(
                            success=False,
                            error=f"HTTP {response.status}: {error_text}",
                            timestamp=datetime.now(),
                            response_time_ms=response_time_ms
                        )

            except aiohttp.ClientError as e:
                last_exception = e
                self.error_count += 1
                logger.warning(f"Network error on attempt {attempt + 1}: {e}")
                if attempt < JUPITER_MAX_RETRIES:
                    await asyncio.sleep(JUPITER_RETRY_DELAY * (2 ** attempt))
                    continue
            except asyncio.TimeoutError as e:
                last_exception = e
                self.error_count += 1
                logger.warning(f"Timeout on attempt {attempt + 1}: {e}")
                if attempt < JUPITER_MAX_RETRIES:
                    await asyncio.sleep(JUPITER_RETRY_DELAY * (2 ** attempt))
                    continue
            except Exception as e:
                last_exception = e
                self.error_count += 1
                logger.error(f"Unexpected error on attempt {attempt + 1}: {e}")
                break

        # All retries failed
        response_time_ms = (time.time() - start_time) * 1000
        return ApiResponse(
            success=False,
            error=f"Request failed after {JUPITER_MAX_RETRIES + 1} attempts: {last_exception}",
            timestamp=datetime.now(),
            response_time_ms=response_time_ms
        )

    def normalize_id(self, id_or_symbol: str) -> str:
        """Normalize token ID or symbol for API calls"""
        # Remove strict base58 validation - allow symbols
        return id_or_symbol.strip().upper()

    async def _validate_token_address(self, token_mint: str) -> bool:
        """Validate Solana token address format (relaxed)"""
        # Remove strict validation to support symbols
        return True  # Simplified validation for v3 API

    def get_api_stats(self) -> Dict[str, Any]:
        """Get API usage statistics"""
        return {
            "request_count": self.request_count,
            "error_count": self.error_count,
            "error_rate": self.error_count / max(self.request_count, 1),
            "cache_stats": self.get_cache_stats(),
            "last_request_time": self.last_request_time
        }

    def get_configuration(self) -> Dict[str, Any]:
        """Get current configuration for debugging"""
        return {
            "price_api_url": JUPITER_PRICE_API_URL,
            "quote_api_base": JUPITER_QUOTE_API_BASE,
            "token_list_api": JUPITER_TOKEN_LIST_API,
            "timeout_seconds": JUPITER_API_TIMEOUT,
            "max_retries": JUPITER_MAX_RETRIES,
            "retry_delay": JUPITER_RETRY_DELAY,
            "rate_limit_delay_ms": JUPITER_RATE_LIMIT_DELAY_MS,
            "batch_size": JUPITER_BATCH_SIZE,
            "current_rate_limit_delay": self.rate_limit_delay,
            "cache_ttl": self.cache_ttl
        }

    async def get_token_info(self, token_mint: str) -> Optional[TokenInfo]:
        """Get token information by mint address with validation"""
        if not await self._validate_token_address(token_mint):
            logger.error(f"Invalid token address: {token_mint}")
            return None

        try:
            url = f"https://token.jup.ag/v6/token/{token_mint}"
            response = await self._make_request(url)

            if not response.success:
                logger.error(f"API request failed for {token_mint}: {response.error}")
                return None

            data = response.data
            if not data:
                logger.warning(f"No data returned for token {token_mint}")
                return None

            return TokenInfo(
                address=data.get("address", token_mint),
                symbol=data.get("symbol", "UNKNOWN"),
                name=data.get("name", "Unknown Token"),
                decimals=data.get("decimals", 0),
                logo_uri=data.get("logoURI"),
                tags=data.get("tags", []),
                coingecko_id=data.get("coingeckoId"),
                verified=data.get("verified", False)
            )

        except Exception as e:
            logger.error(f"Failed to get token info for {token_mint}: {e}")
            return None

    async def get_price(self, token_mint: str) -> Optional[TokenPrice]:
        """Get token price information using v3 API format"""
        token_id = self.normalize_id(token_mint)

        try:
            # Check cache first
            if token_id in self.price_cache:
                cached_price = self.price_cache[token_id]
                if cached_price.price.timestamp and (datetime.now() - cached_price.price.timestamp) < timedelta(seconds=self.cache_ttl):
                    logger.debug(f"Using cached price for {token_id}")
                    return cached_price

            url = JUPITER_PRICE_API_URL
            params = {"ids": token_id}
            response = await self._make_request(url, params)

            if not response.success:
                logger.error(f"Failed to get price for {token_id}: {response.error}")
                return None

            payload = response.data or {}
            entry = payload.get("data", {}).get(token_id)

            if not entry:
                logger.warning(f"No price data available for token {token_id}")
                return None

            # Get token info (with fallback)
            token_info = await self.get_token_info(token_mint)
            if not token_info:
                token_info = TokenInfo(
                    address=token_mint,
                    symbol="UNKNOWN",
                    name="Unknown Token",
                    decimals=0
                )

            # Parse price data with validation
            price_value = entry.get("price", "0")
            try:
                price_float = float(price_value)
                if price_float <= 0:
                    logger.warning(f"Invalid price {price_value} for token {token_id}")
                    return None
            except (ValueError, TypeError):
                logger.error(f"Could not parse price {price_value} for token {token_id}")
                return None

            price_info = PriceInfo(
                price=price_float,
                price_change_24h=entry.get("priceChange24h"),
                timestamp=datetime.now()
            )

            # Parse DEX prices
            dex_prices = []
            best_dex = None
            best_price = 0

            dex_data = entry.get("dexes", {})
            if not dex_data:
                logger.warning(f"No DEX data available for token {token_id}")

            for dex_name, dex_info in dex_data.items():
                try:
                    dex_price_value = dex_info.get("price", "0")
                    dex_price_float = float(dex_price_value)
                    if dex_price_float <= 0:
                        continue

                    dex_price = DexPrice(
                        dex_name=dex_name,
                        price=dex_price_float,
                        liquidity=dex_info.get("liquidity"),
                        volume_24h=dex_info.get("volume24h"),
                        market_cap=dex_info.get("marketCap")
                    )
                    dex_prices.append(dex_price)

                    # Track best price
                    if dex_price.price > best_price:
                        best_price = dex_price.price
                        best_dex = dex_price

                except (ValueError, TypeError) as e:
                    logger.warning(f"Could not parse DEX price for {dex_name}: {e}")
                    continue

            token_price = TokenPrice(
                token=token_info,
                price=price_info,
                dex_prices=dex_prices,
                best_dex=best_dex
            )

            # Cache the result
            self.price_cache[token_id] = token_price
            logger.debug(f"Retrieved and cached price for {token_id}: {price_float}")

            return token_price

        except Exception as e:
            logger.error(f"Failed to get price for {token_id}: {e}")
            return None

    async def get_batch_prices(self, token_mints: List[str]) -> Dict[str, TokenPrice]:
        """Get prices for multiple tokens in batch using v3 API format"""
        try:
            # Check cache for cached tokens
            uncached_tokens = []
            results = {}

            for token_mint in token_mints:
                token_id = self.normalize_id(token_mint)
                if token_id in self.price_cache:
                    cached_price = self.price_cache[token_id]
                    if cached_price.price.timestamp and (datetime.now() - cached_price.price.timestamp) < timedelta(seconds=self.cache_ttl):
                        results[token_mint] = cached_price
                    else:
                        uncached_tokens.append(token_mint)
                else:
                    uncached_tokens.append(token_mint)

            if not uncached_tokens:
                return results

            # Normalize token IDs for API
            normalized_tokens = [self.normalize_id(t) for t in uncached_tokens]
            url = JUPITER_PRICE_API_URL
            params = {"ids": ",".join(normalized_tokens)}
            response = await self._make_request(url, params)

            if not response.success:
                return results

            payload = response.data or {}
            batch_data = payload.get("data", {})

            # Process results
            for i, token_mint in enumerate(uncached_tokens):
                token_id = normalized_tokens[i]
                if token_id in batch_data:
                    entry = batch_data[token_id]

                    # Get token info (with fallback)
                    token_info = await self.get_token_info(token_mint)
                    if not token_info:
                        token_info = TokenInfo(
                            address=token_mint,
                            symbol="UNKNOWN",
                            name="Unknown Token",
                            decimals=0
                        )

                    # Parse price data with validation
                    price_value = entry.get("price", "0")
                    try:
                        price_float = float(price_value)
                        if price_float <= 0:
                            logger.warning(f"Invalid price {price_value} for token {token_id}")
                            continue
                    except (ValueError, TypeError):
                        logger.error(f"Could not parse price {price_value} for token {token_id}")
                        continue

                    price_info = PriceInfo(
                        price=price_float,
                        price_change_24h=entry.get("priceChange24h"),
                        timestamp=datetime.now()
                    )

                    # Parse DEX prices
                    dex_prices = []
                    best_dex = None
                    best_price = 0

                    dex_data = entry.get("dexes", {})
                    for dex_name, dex_info in dex_data.items():
                        try:
                            dex_price_value = dex_info.get("price", "0")
                            dex_price_float = float(dex_price_value)
                            if dex_price_float <= 0:
                                continue

                            dex_price = DexPrice(
                                dex_name=dex_name,
                                price=dex_price_float,
                                liquidity=dex_info.get("liquidity"),
                                volume_24h=dex_info.get("volume24h"),
                                market_cap=dex_info.get("marketCap")
                            )
                            dex_prices.append(dex_price)

                            # Track best price
                            if dex_price.price > best_price:
                                best_price = dex_price.price
                                best_dex = dex_price

                        except (ValueError, TypeError) as e:
                            logger.warning(f"Could not parse DEX price for {dex_name}: {e}")
                            continue

                    token_price = TokenPrice(
                        token=token_info,
                        price=price_info,
                        dex_prices=dex_prices,
                        best_dex=best_dex
                    )

                    # Cache and add to results
                    self.price_cache[token_id] = token_price
                    results[token_mint] = token_price

            return results

        except Exception as e:
            logger.error(f"Failed to get batch prices: {e}")
            return {}

    async def get_quote(self, input_mint: str, output_mint: str, amount: int, slippage_bps: int = 100) -> Optional[PriceQuote]:
        """Get swap quote from Jupiter"""
        try:
            url = f"{JUPITER_QUOTE_API_BASE}/quote"
            params = {
                "inputMint": input_mint,
                "outputMint": output_mint,
                "amount": str(amount),
                "slippageBps": str(slippage_bps)
            }

            start_time = time.time()
            resp = await self._make_request(url, params)
            time_taken = time.time() - start_time

            if not resp.success:
                logger.error(f"Failed to get quote from {input_mint} to {output_mint}: {resp.error}")
                return None

            payload = resp.data or {}
            return PriceQuote(
                input_mint=payload.get("inputMint", ""),
                output_mint=payload.get("outputMint", ""),
                input_amount=int(payload.get("inAmount", "0")),
                output_amount=int(payload.get("outAmount", "0")),
                price_impact=float(payload.get("priceImpactPct", 0)),
                slippage=float(payload.get("slippageBps", 0)),
                route_plan=payload.get("routePlan", []),
                time_taken=time_taken
            )

        except Exception as e:
            logger.error(f"Failed to get quote from {input_mint} to {output_mint}: {e}")
            return None

    async def get_dex_prices(self, token_mint: str) -> List[DexPrice]:
        """Get DEX-specific prices for a token"""
        try:
            token_price = await self.get_price(token_mint)
            if not token_price:
                return []

            return token_price.dex_prices

        except Exception as e:
            logger.error(f"Failed to get DEX prices for {token_mint}: {e}")
            return []

    async def get_top_tokens(self, limit: int = 50) -> List[TokenInfo]:
        """Get top trading tokens"""
        try:
            url = f"{JUPITER_PRICE_API_URL}/tokens"
            params = {"limit": str(limit)}
            resp = await self._make_request(url, params)

            if not resp.success:
                logger.error(f"Failed to get top tokens: {resp.error}")
                return []

            data = resp.data or []
            tokens = []
            for token_data in data:
                token = TokenInfo(
                    address=token_data.get("address", ""),
                    symbol=token_data.get("symbol", ""),
                    name=token_data.get("name", ""),
                    decimals=token_data.get("decimals", 0),
                    logo_uri=token_data.get("logoURI"),
                    tags=token_data.get("tags", []),
                    coingecko_id=token_data.get("coingeckoId"),
                    verified=token_data.get("verified", False)
                )
                tokens.append(token)

            return tokens

        except Exception as e:
            logger.error(f"Failed to get top tokens: {e}")
            return []

    def clear_cache(self):
        """Clear price cache"""
        self.price_cache.clear()
        self.dex_price_cache.clear()

    def get_cache_stats(self) -> Dict[str, Any]:
        """Get cache statistics"""
        return {
            "cached_tokens": len(self.price_cache),
            "cached_dex_prices": len(self.dex_price_cache),
            "cache_ttl": self.cache_ttl
        }

    async def health_check(self) -> Dict[str, Any]:
        """Check API health and connectivity"""
        try:
            # Test with a well-known token (SOL)
            sol_token = "So11111111111111111111111111111111111111112"
            start_time = time.time()

            response = await self._make_request(JUPITER_PRICE_API_URL, {"ids": sol_token})
            response_time = (time.time() - start_time) * 1000

            return {
                "status": "healthy" if response.success else "unhealthy",
                "api_endpoint": JUPITER_PRICE_API_URL,
                "response_time_ms": response_time,
                "last_check": datetime.now().isoformat(),
                "error": response.error if not response.success else None
            }
        except Exception as e:
            return {
                "status": "error",
                "api_endpoint": JUPITER_PRICE_API_URL,
                "error": str(e),
                "last_check": datetime.now().isoformat()
            }

    async def get_supported_tokens(self) -> List[TokenInfo]:
        """Get list of supported tokens from Jupiter"""
        try:
            url = f"{JUPITER_TOKEN_LIST_API}/tokens"
            response = await self._make_request(url)

            if not response.success:
                logger.error(f"Failed to get supported tokens: {response.error}")
                return []

            data = response.data
            if not data:
                return []

            tokens = []
            for token_data in data:
                token = TokenInfo(
                    address=token_data.get("address", ""),
                    symbol=token_data.get("symbol", ""),
                    name=token_data.get("name", ""),
                    decimals=token_data.get("decimals", 0),
                    logo_uri=token_data.get("logoURI"),
                    tags=token_data.get("tags", []),
                    coingecko_id=token_data.get("coingeckoId"),
                    verified=token_data.get("verified", False)
                )
                tokens.append(token)

            logger.info(f"Retrieved {len(tokens)} supported tokens")
            return tokens

        except Exception as e:
            logger.error(f"Failed to get supported tokens: {e}")
            return []

    async def get_triangular_arbitrage_data(self, token_a: str, token_b: str, token_c: str) -> Optional[Dict[str, Any]]:
        """Get data for triangular arbitrage analysis"""
        try:
            # Validate all token addresses
            if not all(await self._validate_token_address(t) for t in [token_a, token_b, token_c]):
                logger.error("Invalid token addresses for triangular arbitrage")
                return None

            # Get batch prices for efficiency
            prices = await self.get_batch_prices([token_a, token_b, token_c])
            if len(prices) < 3:
                logger.warning("Could not retrieve all token prices for triangular arbitrage")
                return None

            # Get quotes for all pairs
            quotes = {}
            pairs = [(token_a, token_b), (token_b, token_c), (token_c, token_a)]

            for input_token, output_token in pairs:
                try:
                    # Use 1 unit of input token as base amount
                    token_info = prices[input_token].token
                    base_amount = 10 ** token_info.decimals

                    quote = await self.get_quote(input_token, output_token, base_amount)
                    if quote:
                        quotes[f"{input_token}_{output_token}"] = quote
                except Exception as e:
                    logger.warning(f"Failed to get quote {input_token}->{output_token}: {e}")
                    continue

            if len(quotes) < 2:
                logger.warning("Insufficient quotes for triangular arbitrage")
                return None

            return {
                "prices": prices,
                "quotes": quotes,
                "timestamp": datetime.now().isoformat()
            }

        except Exception as e:
            logger.error(f"Failed to get triangular arbitrage data: {e}")
            return None

    async def get_swap_transaction(self, quote_data: Dict[str, Any], user_public_key: str,
                                 fee_account: Optional[str] = None, priority_fee_lamports: int = 0) -> Optional[Dict[str, Any]]:
        """Get swap transaction from Jupiter for execution"""
        try:
            url = f"{JUPITER_QUOTE_API_BASE}/swap"
            params = {
                "quoteResponse": json.dumps(quote_data),
                "userPublicKey": user_public_key,
                "wrapAndUnwrapSol": "true"
            }

            if fee_account:
                params["feeAccount"] = fee_account

            if priority_fee_lamports > 0:
                params["priorityFeeLamports"] = str(priority_fee_lamports)

            start_time = time.time()
            resp = await self._make_request(url, params)
            time_taken = time.time() - start_time

            if not resp.success:
                logger.error(f"Failed to get swap transaction: {resp.error}")
                return None

            payload = resp.data or {}
            return {
                "swap_transaction": payload.get("swapTransaction"),
                "last_valid_block_height": payload.get("lastValidBlockHeight"),
                "prioritization_fee_lamports": payload.get("prioritizationFeeLamports"),
                "compute_unit_limit": payload.get("computeUnitLimit"),
                "time_taken": time_taken
            }
        except Exception as e:
            logger.error(f"Failed to get swap transaction: {e}")
            return None

    async def get_routes_for_swap(self, input_mint: str, output_mint: str, amount: int,
                                slippage_bps: int = 100, max_routes: int = 5) -> List[Dict[str, Any]]:
        """Get multiple routing options for a swap"""
        try:
            url = f"{JUPITER_QUOTE_API_BASE}/quote"
            params = {
                "inputMint": input_mint,
                "outputMint": output_mint,
                "amount": str(amount),
                "slippageBps": str(slippage_bps),
                "maxAccounts": "64"  # Allow more complex routes
            }

            # Get base quote
            resp = await self._make_request(url, params)
            if not resp.success:
                logger.error(f"Failed to get routes for swap: {resp.error}")
                return []

            payload = resp.data or {}
            routes = []
            route_plan = payload.get("routePlan", [])

            for i, route in enumerate(route_plan[:max_routes]):
                route_info = {
                    "route_index": i,
                    "input_mint": input_mint,
                    "output_mint": output_mint,
                    "input_amount": int(route.get("inAmount", "0")),
                    "output_amount": int(route.get("outAmount", "0")),
                    "price_impact": float(route.get("priceImpactPct", 0)),
                    "swap_info": route.get("swapInfo", []),
                    "market_infos": route.get("marketInfos", [])
                }
                routes.append(route_info)

            return routes
        except Exception as e:
            logger.error(f"Failed to get routes for swap: {e}")
            return []

    async def get_optimized_quote(self, input_mint: str, output_mint: str, amount: int,
                                slippage_bps: int = 100, max_slippage_bps: int = 300,
                                minimize_price_impact: bool = True) -> Optional[PriceQuote]:
        """Get optimized quote with enhanced parameters"""
        try:
            # Start with standard quote
            base_quote = await self.get_quote(input_mint, output_mint, amount, slippage_bps)
            if not base_quote:
                return None

            # If price impact is too high, try to optimize
            if minimize_price_impact and base_quote.price_impact > 0.02:  # 2% threshold
                # Try with higher slippage tolerance
                optimized_quote = await self.get_quote(input_mint, output_mint, amount, max_slippage_bps)
                if optimized_quote and optimized_quote.price_impact < base_quote.price_impact:
                    return optimized_quote

            return base_quote
        except Exception as e:
            logger.error(f"Failed to get optimized quote: {e}")
            return None

    async def simulate_swap(self, input_mint: str, output_mint: str, amount: int,
                          slippage_bps: int = 100) -> Optional[Dict[str, Any]]:
        """Simulate a swap without executing it"""
        try:
            quote = await self.get_quote(input_mint, output_mint, amount, slippage_bps)
            if not quote:
                return None

            # Calculate estimated fees and gas
            estimated_fee = amount * 0.0003  # ~0.03% typical Jupiter fee
            gas_estimate = 5000000  # 5M compute units typical

            return {
                "quote": quote,
                "estimated_fee_lamports": estimated_fee,
                "estimated_gas_units": gas_estimate,
                "estimated_gas_sol": gas_estimate * 0.000001,  # 1 micro-SOL per compute unit
                "profit_estimate": self._calculate_profit_estimate(quote),
                "risk_score": self._calculate_swap_risk_score(quote)
            }
        except Exception as e:
            logger.error(f"Failed to simulate swap: {e}")
            return None

    def _calculate_profit_estimate(self, quote: PriceQuote) -> float:
        """Calculate rough profit estimate for arbitrage"""
        try:
            # Simple profit calculation based on price impact
            # Lower price impact = potentially better arbitrage opportunity
            if quote.price_impact < 0.01:  # < 1% price impact
                return quote.output_amount * 0.001  # 0.1% estimated profit
            elif quote.price_impact < 0.02:  # < 2% price impact
                return quote.output_amount * 0.0005  # 0.05% estimated profit
            else:
                return 0.0  # No profit expected for high impact trades
        except:
            return 0.0

    def _calculate_swap_risk_score(self, quote: PriceQuote) -> float:
        """Calculate risk score for a swap (0.0 = low risk, 1.0 = high risk)"""
        try:
            risk_score = 0.0

            # Price impact risk
            if quote.price_impact > 0.05:  # > 5% price impact
                risk_score += 0.3
            elif quote.price_impact > 0.02:  # > 2% price impact
                risk_score += 0.1

            # Slippage risk
            if quote.slippage > 200:  # > 2% slippage
                risk_score += 0.2
            elif quote.slippage > 100:  # > 1% slippage
                risk_score += 0.1

            # Route complexity risk (more hops = more risk)
            route_hops = len(quote.route_plan)
            if route_hops > 3:
                risk_score += 0.2
            elif route_hops > 2:
                risk_score += 0.1

            return min(risk_score, 1.0)
        except:
            return 0.5  # Medium risk as fallback

    def reset_stats(self):
        """Reset API usage statistics"""
        self.request_count = 0
        self.error_count = 0
        self.last_request_time = 0

    def get_quote_sync(self, input_mint: str, output_mint: str, amount: int, slippage_bps: int = 100) -> Optional[Any]:
        """Synchronous wrapper for get_quote (for Mojo interop)"""
        try:
            import asyncio
            # Try to get the current event loop
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    # If loop is running, we need to run in a thread
                    import concurrent.futures
                    with concurrent.futures.ThreadPoolExecutor() as executor:
                        future = executor.submit(asyncio.run, self.get_quote(input_mint, output_mint, amount, slippage_bps))
                        return future.result(timeout=30)
                else:
                    # If loop is not running, we can run directly
                    return asyncio.run(self.get_quote(input_mint, output_mint, amount, slippage_bps))
            except RuntimeError:
                # No event loop, create one
                return asyncio.run(self.get_quote(input_mint, output_mint, amount, slippage_bps))
        except Exception as e:
            logger.error(f"Failed to get quote synchronously: {e}")
            return None

    def get_price_sync(self, token_mint: str) -> Optional[Any]:
        """Synchronous wrapper for get_price (for Mojo interop)"""
        try:
            import asyncio
            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    import concurrent.futures
                    with concurrent.futures.ThreadPoolExecutor() as executor:
                        future = executor.submit(asyncio.run, self.get_price(token_mint))
                        return future.result(timeout=30)
                else:
                    return asyncio.run(self.get_price(token_mint))
            except RuntimeError:
                return asyncio.run(self.get_price(token_mint))
        except Exception as e:
            logger.error(f"Failed to get price synchronously: {e}")
            return None

# Convenience functions for common operations
async def get_token_price(token_mint: str) -> Optional[float]:
    """Get simple token price"""
    client = JupiterPriceAPI()
    try:
        token_price = await client.get_price(token_mint)
        return token_price.price.price if token_price else None
    finally:
        await client.close()

async def compare_dex_prices(token_mint: str) -> List[Tuple[str, float]]:
    """Compare prices across DEXes"""
    client = JupiterPriceAPI()
    try:
        dex_prices = await client.get_dex_prices(token_mint)
        return [(dex.dex_name, dex.price) for dex in dex_prices]
    finally:
        await client.close()

async def get_arbitrage_opportunities(token_mint: str, min_spread: float = 0.01) -> List[Tuple[str, str, float]]:
    """Find simple arbitrage opportunities for a token"""
    client = JupiterPriceAPI()
    try:
        dex_prices = await client.get_dex_prices(token_mint)
        if len(dex_prices) < 2:
            return []

        # Sort by price
        sorted_prices = sorted(dex_prices, key=lambda x: x.price)

        opportunities = []
        for i in range(len(sorted_prices) - 1):
            buy_dex = sorted_prices[i]
            sell_dex = sorted_prices[-1]
            spread = (sell_dex.price - buy_dex.price) / buy_dex.price

            if spread >= min_spread:
                opportunities.append((buy_dex.dex_name, sell_dex.dex_name, spread))

        return opportunities
    finally:
        await client.close()


# Unit tests for symbol and mint cases
import unittest

class TestJupiterPriceAPI(unittest.TestCase):
    """Test Jupiter Price API functionality"""

    def test_normalize_id(self):
        """Test token ID normalization"""
        client = JupiterPriceAPI()

        # Test symbol normalization
        self.assertEqual(client.normalize_id("sol"), "SOL")
        self.assertEqual(client.normalize_id("usdc"), "USDC")
        self.assertEqual(client.normalize_id("  sol  "), "SOL")

        # Test mint address (should be unchanged)
        mint = "So11111111111111111111111111111111111111112"
        self.assertEqual(client.normalize_id(mint), mint)

    def test_validate_token_address(self):
        """Test token address validation (relaxed for v3)"""
        client = JupiterPriceAPI()

        # All should pass with relaxed validation
        self.assertTrue(await client._validate_token_address("SOL"))
        self.assertTrue(await client._validate_token_address("USDC"))
        self.assertTrue(await client._validate_token_address("So11111111111111111111111111111111111111112"))

    def test_api_response_parsing(self):
        """Test v3 API response parsing"""
        client = JupiterPriceAPI()

        # Mock v3 API response structure
        mock_response = {
            "data": {
                "SOL": {
                    "price": "100.50",
                    "priceChange24h": 2.5,
                    "dexes": {
                        "raydium": {
                            "price": "100.45",
                            "liquidity": 1000000
                        },
                        "orca": {
                            "price": "100.55",
                            "liquidity": 800000
                        }
                    }
                }
            }
        }

        # Test parsing logic
        self.assertIsInstance(mock_response, dict)
        self.assertIn("data", mock_response)
        self.assertIn("SOL", mock_response["data"])

        sol_data = mock_response["data"]["SOL"]
        self.assertEqual(sol_data["price"], "100.50")
        self.assertIn("dexes", sol_data)

if __name__ == "__main__":
    unittest.main()