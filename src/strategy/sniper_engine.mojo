# Mojo Sniper Engine with Save Flash Loans Integration
# High-frequency memecoin sniping with <30ms latency

from time import now
from tensor import Tensor
from python import Python
from collections import Dict
from math import min, max

@value
struct SniperSignal:
    var action: String  # "buy", "sell", "hold", "flash_loan"
    var amount: Int
    var token: String
    var token_mint: String  # Solana token mint address
    var quote: Python.Object
    var confidence: Float32
    var expected_profit: Float32
    var execution_deadline: Int
    var preferred_provider: String  # "save", "solend", "mango_v4"
    var slippage_bps: Int
    var urgency_level: String  # "high", "medium", "low"
    var risk_score: Float32
    var liquidity_score: Float32
    var social_score: Float32
    var market_data: Python.Object  # Additional market data for Rust

    fn __init__(inout self, action: String = "hold"):
        self.action = action
        self.amount = 0
        self.token = ""
        self.token_mint = ""
        self.quote = Python.dict()
        self.confidence = 0.0
        self.expected_profit = 0.0
        self.execution_deadline = now()
        self.preferred_provider = "save"  # Default to Save for speed
        self.slippage_bps = 50
        self.urgency_level = "high"
        self.risk_score = 0.0
        self.liquidity_score = 0.0
        self.social_score = 0.0
        self.market_data = Python.dict()

@value
struct SniperEngine:
    var min_lp_burned: Float32
    var min_volume: Float32
    var min_social_mentions: Int
    var max_flash_loan_amount: Int
    var slippage_bps: Int
    var min_confidence: Float32

    fn __init__(inout self):
        self.min_lp_burned = 90.0
        self.min_volume = 5000.0
        self.min_social_mentions = 10
        self.max_flash_loan_amount = 5_000_000_000  # 5 SOL
        self.slippage_bps = 50
        self.min_confidence = 0.7

    fn evaluate_token(self, token: String, data: Dict[String, Float32]) -> SniperSignal:
        """Evaluate token for sniping opportunity"""
        var signal = SniperSignal()
        signal.token = token
        signal.token_mint = data.get("token_mint", "").to_string()  # Required for Rust integration

        # Check sniper criteria
        var lp_burned = data.get("lp_burned", 0.0)
        var volume = data.get("volume_24h", 0.0)
        var social_mentions = data.get("social_mentions", 0.0)
        var available_liquidity = data.get("available_liquidity", 0.0).to_int()

        # Calculate scores for Rust integration
        signal.liquidity_score = min(volume / 10000.0, 1.0)  # Normalize to 0-1
        signal.social_score = min(social_mentions / 100.0, 1.0)  # Normalize to 0-1
        signal.risk_score = self.calculate_risk_score(data)

        # Calculate confidence based on metrics
        var confidence = 0.0
        if lp_burned >= self.min_lp_burned:
            confidence += 0.4
        if volume >= self.min_volume:
            confidence += 0.3
        if social_mentions >= self.min_social_mentions:
            confidence += 0.3

        # Additional confidence factors
        var holder_count = data.get("holder_count", 0.0)
        if holder_count >= 100:
            confidence += 0.1

        var market_cap = data.get("market_cap", 0.0)
        if market_cap >= 100000:
            confidence += 0.1

        # Adjust confidence based on token age
        var token_age_minutes = data.get("age_minutes", 0.0)
        if token_age_minutes <= 30:  # Very new token
            confidence += 0.2
        elif token_age_minutes <= 5:  # Extremely new token
            confidence += 0.3

        confidence = min(confidence, 1.0)
        signal.confidence = confidence

        # Set urgency level based on confidence and token age
        if confidence >= 0.9 and token_age_minutes <= 5:
            signal.urgency_level = "high"
        elif confidence >= 0.8:
            signal.urgency_level = "medium"
        else:
            signal.urgency_level = "low"

        # Determine preferred flash loan provider based on amount and requirements
        var base_amount = min(available_liquidity / 10, self.max_flash_loan_amount)
        if base_amount <= 1_000_000_000:  # <= 1 SOL
            signal.preferred_provider = "save"  # Fastest for small amounts
        elif base_amount <= 10_000_000_000:  # <= 10 SOL
            signal.preferred_provider = "solend"  # Balanced for medium amounts
        else:
            signal.preferred_provider = "mango_v4"  # High liquidity for large amounts

        # Check if meets minimum confidence threshold
        if confidence < self.min_confidence:
            signal.action = "hold"
            return signal

        # Adjust amount based on confidence and provider
        var amount_multiplier = confidence * 1.2  # 20% boost for high confidence
        var provider_multiplier = 1.0
        if signal.preferred_provider == "save":
            provider_multiplier = 0.8  # More conservative with Save (lower limit)
        elif signal.preferred_provider == "mango_v4":
            provider_multiplier = 1.5  # More aggressive with Mango (higher limit)

        var optimal_amount = min(
            Int(base_amount * amount_multiplier * provider_multiplier),
            self.max_flash_loan_amount
        )

        # Set slippage based on urgency and volatility
        if signal.urgency_level == "high":
            signal.slippage_bps = 100  # Higher slippage for speed
        elif signal.urgency_level == "medium":
            signal.slippage_bps = 75
        else:
            signal.slippage_bps = 50

        signal.amount = optimal_amount

        # Populate market data for Rust integration
        var market_data = Python.dict({
            "lp_burned": lp_burned,
            "volume_24h": volume,
            "social_mentions": social_mentions,
            "holder_count": holder_count,
            "market_cap": market_cap,
            "age_minutes": token_age_minutes,
            "available_liquidity": available_liquidity,
            "confidence": confidence,
            "risk_score": signal.risk_score,
            "liquidity_score": signal.liquidity_score,
            "social_score": signal.social_score,
            "preferred_provider": signal.preferred_provider,
            "urgency_level": signal.urgency_level
        })
        signal.market_data = market_data

        # Get Jupiter quote with updated slippage
        var quotes_api = Python.import_module("requests")
        try:
            var quote = quotes_api.get(
                "https://quote-api.jup.ag/v6/quote",
                params=Python.dict({
                    "inputMint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # WSOL
                    "outputMint": signal.token_mint if signal.token_mint != "" else token,
                    "amount": str(optimal_amount),
                    "slippageBps": str(signal.slippage_bps),
                    "onlyDirectRoutes": "true",
                    "asLegacyTransaction": "false"
                })
            ).json()

            # Calculate expected profit including flash loan fees
            var out_amount = quote.get("outAmount", 0).to_int()
            var gross_profit = (out_amount - optimal_amount).to_float()
            var profit_estimate = gross_profit / optimal_amount.to_float() * 100

            # Subtract flash loan fees based on provider
            var flash_loan_fee_rate = 0.0003  # Default 0.03% (Save)
            if signal.preferred_provider == "solend":
                flash_loan_fee_rate = 0.0005  # 0.05%
            elif signal.preferred_provider == "mango_v4":
                flash_loan_fee_rate = 0.0008  # 0.08%

            var flash_loan_fee = optimal_amount.to_float() * flash_loan_fee_rate
            var net_profit = gross_profit - flash_loan_fee
            var net_profit_percentage = net_profit / optimal_amount.to_float() * 100

            # Final decision - use flash loan if high confidence and good profit
            if confidence >= 0.8 and net_profit_percentage > 1.5:  # Lower threshold for flash loans
                signal.action = "flash_loan"
                signal.amount = optimal_amount
                signal.quote = quote
                signal.expected_profit = net_profit_percentage
                signal.execution_deadline = now() + 20000  # 20 seconds deadline for flash loans

            elif net_profit_percentage > 2.0:  # Higher threshold for regular trades
                signal.action = "buy"
                signal.amount = optimal_amount
                signal.quote = quote
                signal.expected_profit = net_profit_percentage
                signal.execution_deadline = now() + 30000  # 30 seconds deadline

            else:
                signal.action = "hold"

        except:
            # Fallback if Jupiter API fails - still use flash loan if confidence is high
            if confidence >= 0.9:
                signal.action = "flash_loan"
                signal.amount = optimal_amount
                signal.expected_profit = 1.5  # Conservative estimate
                signal.execution_deadline = now() + 20000
            else:
                signal.action = "hold"
                signal.confidence = confidence * 0.5

        return signal

    def calculate_risk_score(self, data: Dict[String, Float32]) -> Float32:
        """Calculate risk score for token (0.0 = low risk, 1.0 = high risk)"""
        var risk_score = 0.0

        # High volume reduces risk
        var volume = data.get("volume_24h", 0.0)
        if volume < 1000:
            risk_score += 0.3
        elif volume > 10000:
            risk_score -= 0.2

        # High social mentions reduce risk
        var social_mentions = data.get("social_mentions", 0.0)
        if social_mentions < 5:
            risk_score += 0.2
        elif social_mentions > 50:
            risk_score -= 0.1

        # Recent token age increases risk
        var token_age_minutes = data.get("age_minutes", 0.0)
        if token_age_minutes < 1:
            risk_score += 0.3
        elif token_age_minutes > 60:
            risk_score -= 0.1

        # Holder count
        var holder_count = data.get("holder_count", 0.0)
        if holder_count < 10:
            risk_score += 0.2
        elif holder_count > 1000:
            risk_score -= 0.1

        return max(0.0, min(1.0, risk_score))

    def should_use_flash_loan(self, amount: Int, data: Dict[String, Float32]) -> Bool:
        """Determine if flash loan should be used"""
        # Use flash loan for amounts > 0.5 SOL
        if amount > 500_000_000:
            return True

        # Use flash loan if confidence is high and liquidity is sufficient
        var confidence = self.calculate_token_confidence(data)
        var available_liquidity = data.get("available_liquidity", 0.0)

        return confidence > 0.8 and available_liquidity > amount * 2

    def calculate_token_confidence(self, data: Dict[String, Float32]) -> Float32:
        """Calculate overall token confidence score"""
        var confidence = 0.0

        # LP burn percentage
        var lp_burned = data.get("lp_burned", 0.0)
        confidence += (lp_burned / 100.0) * 0.4

        # Volume score (normalized)
        var volume = data.get("volume_24h", 0.0)
        confidence += min(volume / 10000.0, 1.0) * 0.3

        # Social mentions score (normalized)
        var social_mentions = data.get("social_mentions", 0.0)
        confidence += min(social_mentions / 100.0, 1.0) * 0.3

        return min(confidence, 1.0)

# Utility functions for sniper engine
fn format_sol_amount(amount: Int) -> String:
    """Format SOL amount for display"""
    var sol_amount = amount / 1_000_000_000
    var lamports = amount % 1_000_000_000
    if lamports > 0:
        return f"{sol_amount}.{lamports // 10_000_000} SOL"
    else:
        return f"{sol_amount} SOL"

def calculate_roi(entry_price: Float64, exit_price: Float64, fees: Float64) -> Float32:
    """Calculate ROI percentage"""
    if entry_price == 0.0:
        return 0.0

    var gross_profit = (exit_price - entry_price) / entry_price * 100.0
    var net_profit = gross_profit - fees
    return net_profit

# Performance monitoring
@value
struct SniperMetrics:
    var total_evaluations: Int
    var buy_signals: Int
    var successful_trades: Int
    var average_execution_time_ms: Float32
    var total_profit: Float32
    var win_rate: Float32

    fn __init__(inout self):
        self.total_evaluations = 0
        self.buy_signals = 0
        self.successful_trades = 0
        self.average_execution_time_ms = 0.0
        self.total_profit = 0.0
        self.win_rate = 0.0

    fn record_evaluation(inout self):
        self.total_evaluations += 1

    fn record_buy_signal(inout self):
        self.buy_signals += 1

    fn record_trade_result(inout self, success: Bool, profit: Float32, execution_time_ms: Int):
        self.successful_trades += 1
        self.total_profit += profit

        # Update rolling average execution time
        self.average_execution_time_ms = (
            self.average_execution_time_ms * (self.successful_trades - 1) + execution_time_ms.to_float32()
        ) / self.successful_trades.to_float32()

        # Update win rate
        self.win_rate = self.successful_trades.to_float32() / self.buy_signals.to_float32()

    def get_sharpe_ratio(self, risk_free_rate: Float32 = 0.02) -> Float32:
        """Calculate Sharpe ratio"""
        if self.total_profit == 0.0 or self.win_rate == 0.0:
            return 0.0

        return (self.total_profit - risk_free_rate) / (self.win_rate * 0.15)  # Assuming 15% annual volatility

# Global metrics instance
var global_sniper_metrics = SniperMetrics()