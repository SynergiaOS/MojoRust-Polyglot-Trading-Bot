# =============================================================================
# Advanced Spam Filter Module
# =============================================================================

from time import time
from collections import Dict, List, Set
from core.types import TradingSignal, MarketData, RiskAnalysis, RiskLevel
from core.constants import (
    WASH_TRADING_SCORE_THRESHOLD,
    PUMP_DUMP_RISK_THRESHOLD,
    MIN_UNIQUE_TRADERS,
    MAX_TOP_HOLDER_CONCENTRATION,
    MIN_LIQUIDITY_LOCK_RATIO
)

@value
struct SpamFilter:
    """
    Advanced spam filter for detecting wash trading, pump & dump, and other manipulation
    """
    var helius_client  # We'll add the type later
    var config  # We'll add the type later

    fn __init__(helius_client, config):
        self.helius_client = helius_client
        self.config = config

    fn filter_signals(self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Filter out spam and low-quality signals
        """
        filtered_signals = []

        for signal in signals:
            if self._is_legitimate_signal(signal):
                filtered_signals.append(signal)
            else:
                print(f"🚫 Filtered spam signal: {signal.symbol} - {self._get_spam_reason(signal)}")

        return filtered_signals

    fn _is_legitimate_signal(self, signal: TradingSignal) -> Bool:
        """
        Check if a signal is legitimate
        """
        # Basic validation
        if not self._basic_validation(signal):
            return False

        # Liquidity check
        if not self._liquidity_check(signal):
            return False

        # Volume check
        if not self._volume_check(signal):
            return False

        # Holder distribution check
        if not self._holder_distribution_check(signal):
            return False

        # Wash trading check
        if not self._wash_trading_check(signal):
            return False

        # Pump & dump pattern check
        if not self._pump_dump_check(signal):
            return False

        # Age check (avoid very new tokens)
        if not self._age_check(signal):
            return False

        # Price manipulation check
        if not self._price_manipulation_check(signal):
            return False

        return True

    fn _basic_validation(self, signal: TradingSignal) -> Bool:
        """
        Basic signal validation
        """
        if not signal.symbol or signal.symbol == "":
            return False

        if signal.confidence < 0.5:  # Low confidence signals
            return False

        if signal.liquidity < self.config.risk.min_liquidity:
            return False

        if signal.volume < self.config.risk.min_volume:
            return False

        return True

    fn _liquidity_check(self, signal: TradingSignal) -> Bool:
        """
        Check liquidity sufficiency
        """
        # Check minimum liquidity
        if signal.liquidity < self.config.risk.min_liquidity:
            return False

        # Check liquidity depth (ratio of volume to liquidity)
        liquidity_depth = signal.volume / signal.liquidity
        if liquidity_depth > 10.0:  # Volume > 10x liquidity might be wash trading
            return False

        return True

    fn _volume_check(self, signal: TradingSignal) -> Bool:
        """
        Check volume patterns
        """
        # Check minimum volume
        if signal.volume < self.config.risk.min_volume:
            return False

        # Check for suspicious volume spikes
        # In a real implementation, we'd compare with historical volume
        # For now, we'll use basic heuristics
        if signal.volume > 1000000.0 and signal.liquidity < 50000.0:
            # Very high volume with low liquidity is suspicious
            return False

        return True

    fn _holder_distribution_check(self, signal: TradingSignal) -> Bool:
        """
        Check holder distribution for concentration
        """
        try:
            # Get top holders from Helius
            top_holders = self.helius_client.get_top_holders(signal.symbol, 10)

            if len(top_holders) == 0:
                return True  # Skip if data unavailable

            # Calculate concentration
            total_percentage = 0.0
            for holder in top_holders[:5]:  # Top 5 holders
                total_percentage += holder.get("percentage", 0.0)

            # Check if too concentrated
            if total_percentage > MAX_TOP_HOLDER_CONCENTRATION:
                return False

            # Check minimum unique holders
            unique_holders = len(top_holders)
            if unique_holders < MIN_UNIQUE_TRADERS:
                return False

            return True
        except e:
            print(f"⚠️  Error checking holder distribution: {e}")
            return True  # Allow if check fails

    fn _wash_trading_check(self, signal: TradingSignal) -> Bool:
        """
        Check for wash trading patterns
        """
        try:
            # Get transaction history from Helius
            tx_history = self.helius_client.get_transaction_history(signal.symbol)

            # Check wash trading score
            if tx_history.wash_trading_score > WASH_TRADING_SCORE_THRESHOLD:
                return False

            # Check transaction frequency
            if tx_history.transaction_frequency > 100.0:  # Very high frequency
                return False

            # Check large transactions
            if tx_history.large_transactions > 10 and signal.liquidity < 25000.0:
                # Many large transactions with low liquidity
                return False

            return True
        except e:
            print(f"⚠️  Error checking wash trading: {e}")
            return True  # Allow if check fails

    fn _pump_dump_check(self, signal: TradingSignal) -> Bool:
        """
        Check for pump & dump patterns
        """
        # Check for rapid price increases
        if signal.rsi_value > 80.0:  # Extremely overbought
            return False

        # Check if price increase is too rapid
        if signal.price_change_5m > 50.0:  # 50% in 5 minutes
            return False

        # Check if there's no real support level
        if signal.support_level <= 0 and signal.resistance_level > 0:
            # Has resistance but no support - might be artificial
            return False

        # Check liquidity lock ratio
        try:
            liquidity_info = self.helius_client.check_liquidity_locks(signal.symbol)
            if not liquidity_info.get("is_locked", False):
                return False

            lock_ratio = liquidity_info.get("percentage_locked", 0.0)
            if lock_ratio < MIN_LIQUIDITY_LOCK_RATIO:
                return False
        except e:
            print(f"⚠️  Error checking liquidity locks: {e}")

        return True

    fn _age_check(self, signal: TradingSignal) -> Bool:
        """
        Check token age to avoid very new tokens
        """
        try:
            # Get token age from Helius
            age_hours = self.helius_client.analyze_token_age(signal.symbol)

            # Skip very new tokens (less than 30 minutes)
            if age_hours < 0.5:
                return False

            # Be more careful with very new tokens (less than 2 hours)
            if age_hours < 2.0:
                # Require higher confidence for new tokens
                return signal.confidence > 0.8

            return True
        except e:
            print(f"⚠️  Error checking token age: {e}")
            return True  # Allow if check fails

    fn _price_manipulation_check(self, signal: TradingSignal) -> Bool:
        """
        Check for price manipulation patterns
        """
        # Check for unrealistic price targets
        if signal.price_target > 0:
            expected_return = (signal.price_target - signal.stop_loss) / signal.stop_loss
            if expected_return > 10.0:  # More than 1000% expected return
                return False

        # Check stop loss placement
        if signal.stop_loss <= 0:
            return False

        # Check if stop loss is too tight
        current_price_estimate = signal.price_target if signal.price_target > 0 else signal.stop_loss * 1.5
        stop_loss_distance = abs(current_price_estimate - signal.stop_loss) / current_price_estimate
        if stop_loss_distance < 0.05:  # Less than 5% stop loss
            return False

        # Check for round number targets (might be psychological manipulation)
        if signal.price_target > 0:
            if self._is_round_number(signal.price_target):
                # Reduce confidence for round number targets
                return signal.confidence > 0.85

        return True

    fn _is_round_number(self, price: Float) -> Bool:
        """
        Check if a price is a round number
        """
        # Check if price has few significant digits
        price_str = f"{price:.10f}".rstrip('0').rstrip('.')
        significant_digits = len(price_str.replace('.', ''))

        return significant_digits <= 3  # 3 or fewer significant digits

    fn _get_spam_reason(self, signal: TradingSignal) -> String:
        """
        Get the reason why a signal was marked as spam
        """
        if signal.confidence < 0.5:
            return "Low confidence"

        if signal.liquidity < self.config.risk.min_liquidity:
            return "Insufficient liquidity"

        if signal.volume < self.config.risk.min_volume:
            return "Insufficient volume"

        if signal.rsi_value > 80.0:
            return "Extremely overbought"

        if signal.price_change_5m > 50.0:
            return "Suspicious price movement"

        return "Multiple spam factors detected"

    def analyze_market_health(self, market_data: MarketData) -> Dict[String, Any]:
        """
        Analyze overall market health for a token
        """
        health_score = 1.0
        risk_factors = []

        # Check holder distribution
        try:
            top_holders = self.helius_client.get_top_holders(market_data.symbol, 10)
            if len(top_holders) > 0:
                concentration = sum(h.get("percentage", 0.0) for h in top_holders[:5])
                if concentration > MAX_TOP_HOLDER_CONCENTRATION:
                    health_score -= 0.3
                    risk_factors.append("High holder concentration")
        except:
            pass

        # Check transaction history
        try:
            tx_history = self.helius_client.get_transaction_history(market_data.symbol)
            if tx_history.wash_trading_score > WASH_TRADING_SCORE_THRESHOLD:
                health_score -= 0.4
                risk_factors.append("High wash trading score")

            if tx_history.unique_traders < MIN_UNIQUE_TRADERS:
                health_score -= 0.2
                risk_factors.append("Low unique trader count")
        except:
            pass

        # Check liquidity locks
        try:
            liquidity_info = self.helius_client.check_liquidity_locks(market_data.symbol)
            if not liquidity_info.get("is_locked", False):
                health_score -= 0.3
                risk_factors.append("Liquidity not locked")
        except:
            pass

        # Check volume patterns
        if market_data.volume_24h > 0 and market_data.liquidity_usd > 0:
            volume_to_liquidity = market_data.volume_24h / market_data.liquidity_usd
            if volume_to_liquidity > 20.0:
                health_score -= 0.2
                risk_factors.append("Unusual volume patterns")

        return {
            "health_score": max(0.0, health_score),
            "risk_factors": risk_factors,
            "is_healthy": health_score > 0.6,
            "recommendation": "AVOID" if health_score < 0.4 else ("CAUTION" if health_score < 0.7 else "PROCEED")
        }

    def get_market_quality_score(self, market_data: MarketData) -> Float:
        """
        Get overall market quality score (0.0 to 1.0)
        """
        health_analysis = self.analyze_market_health(market_data)
        return health_analysis["health_score"]