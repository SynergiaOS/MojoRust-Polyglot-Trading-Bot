# =============================================================================
# Strategy Engine Module
# =============================================================================

from time import time
from collections import Dict, List
from math import sqrt, abs
from core.types import (
    TradingSignal, MarketData, ConfluenceAnalysis, TradingAction,
    SignalSource, MarketRegime, SentimentAnalysis
)
from core.constants import (
    DEFAULT_RSI_PERIOD,
    OVERSOLD_THRESHOLD,
    OVERBOUGHT_THRESHOLD,
    MIN_CONFLUENCE_STRENGTH,
    TREND_UP_THRESHOLD,
    TREND_DOWN_THRESHOLD,
    MIN_RISK_REWARD_RATIO,
    DEFAULT_STOP_LOSS_PERCENTAGE
)
from analysis.sentiment_analyzer import SentimentAnalyzer

@value
struct StrategyEngine:
    """
    Core strategy engine for generating trading signals
    """
    var config  # We'll add the type later
    var sentiment_analyzer: SentimentAnalyzer

    fn __init__(config):
        self.config = config
        self.sentiment_analyzer = SentimentAnalyzer()

    fn generate_signals(self, context) -> List[TradingSignal]:
        """
        Generate trading signals from market context
        """
        signals = []

        # RSI + Support/Resistance Strategy (Primary)
        rsi_signals = self._rsi_support_resistance_strategy(context)
        signals.extend(rsi_signals)

        # Mean Reversion Strategy
        if self.config.strategy.enable_mean_reversion:
            mean_reversion_signals = self._mean_reversion_strategy(context)
            signals.extend(mean_reversion_signals)

        # Momentum Strategy
        if self.config.strategy.enable_momentum:
            momentum_signals = self._momentum_strategy(context)
            signals.extend(momentum_signals)

        # Arbitrage Strategy
        if self.config.strategy.enable_arbitrage:
            arbitrage_signals = self._arbitrage_strategy(context)
            signals.extend(arbitrage_signals)

        # Rank and filter signals
        ranked_signals = self._rank_signals(signals)
        return ranked_signals[:5]  # Return top 5 signals

    fn _rsi_support_resistance_strategy(self, context) -> List[TradingSignal]:
        """
        RSI + Support/Resistance confluence strategy
        """
        signals = []
        confluence = context.confluence_analysis

        # Check for buy signal (RSI oversold + near support)
        if (confluence.is_oversold and
            confluence.confluence_strength >= self.config.strategy.min_confluence_strength and
            confluence.distance_to_support <= self.config.strategy.support_distance):

            confidence = self._calculate_rsi_confidence(confluence)
            price_target = confluence.nearest_resistance
            stop_loss = confluence.nearest_support * 0.95  # 5% below support

            signal = TradingSignal(
                symbol=context.symbol,
                action=TradingAction.BUY,
                confidence=confidence,
                timeframe="1m",
                timestamp=time(),
                price_target=price_target,
                stop_loss=stop_loss,
                volume=context.market_data.volume_5m,
                liquidity=context.market_data.liquidity_usd,
                rsi_value=confluence.rsi_value,
                support_level=confluence.nearest_support,
                resistance_level=confluence.nearest_resistance,
                signal_source=SignalSource.RSI_SUPPORT
            )

            signals.append(signal)

        # Check for sell signal (RSI overbought + near resistance)
        elif (confluence.is_overbought and
              confluence.distance_to_resistance <= self.config.strategy.support_distance):

            confidence = self._calculate_rsi_confidence(confluence)
            price_target = confluence.nearest_support
            stop_loss = confluence.nearest_resistance * 1.05  # 5% above resistance

            signal = TradingSignal(
                symbol=context.symbol,
                action=TradingAction.SELL,
                confidence=confidence,
                timeframe="1m",
                timestamp=time(),
                price_target=price_target,
                stop_loss=stop_loss,
                volume=context.market_data.volume_5m,
                liquidity=context.market_data.liquidity_usd,
                rsi_value=confluence.rsi_value,
                support_level=confluence.nearest_support,
                resistance_level=confluence.nearest_resistance,
                signal_source=SignalSource.RSI_SUPPORT
            )

            signals.append(signal)

        return signals

    fn _mean_reversion_strategy(self, context) -> List[TradingSignal]:
        """
        Mean reversion strategy for range-bound markets
        """
        signals = []
        market_data = context.market_data

        # Check if market is ranging
        if context.market_regime == MarketRegime.RANGING:
            # Calculate Bollinger Bands-like levels
            recent_high = market_data.current_price * 1.1
            recent_low = market_data.current_price * 0.9
            middle_band = (recent_high + recent_low) / 2

            # Buy signal: Price near lower band
            if market_data.current_price <= recent_low * 1.02:
                confidence = 0.7
                price_target = middle_band
                stop_loss = recent_low * 0.95

                signal = TradingSignal(
                    symbol=context.symbol,
                    action=TradingAction.BUY,
                    confidence=confidence,
                    timeframe="5m",
                    timestamp=time(),
                    price_target=price_target,
                    stop_loss=stop_loss,
                    volume=market_data.volume_5m,
                    liquidity=market_data.liquidity_usd,
                    signal_source=SignalSource.MEAN_REVERSION
                )
                signals.append(signal)

            # Sell signal: Price near upper band
            elif market_data.current_price >= recent_high * 0.98:
                confidence = 0.7
                price_target = middle_band
                stop_loss = recent_high * 1.05

                signal = TradingSignal(
                    symbol=context.symbol,
                    action=TradingAction.SELL,
                    confidence=confidence,
                    timeframe="5m",
                    timestamp=time(),
                    price_target=price_target,
                    stop_loss=stop_loss,
                    volume=market_data.volume_5m,
                    liquidity=market_data.liquidity_usd,
                    signal_source=SignalSource.MEAN_REVERSION
                )
                signals.append(signal)

        return signals

    fn _momentum_strategy(self, context) -> List[TradingSignal]:
        """
        Momentum strategy for trending markets
        """
        signals = []
        market_data = context.market_data

        # Check for strong momentum
        if abs(market_data.price_change_5m) > 0.02:  # 2% change in 5 minutes
            if (market_data.price_change_5m > 0 and
                context.market_regime == MarketRegime.TRENDING_UP):

                # Buy signal: Strong upward momentum
                confidence = min(0.8, abs(market_data.price_change_5m) * 10)
                price_target = market_data.current_price * 1.1  # 10% target
                stop_loss = market_data.current_price * 0.93   # 7% stop loss

                signal = TradingSignal(
                    symbol=context.symbol,
                    action=TradingAction.BUY,
                    confidence=confidence,
                    timeframe="1m",
                    timestamp=time(),
                    price_target=price_target,
                    stop_loss=stop_loss,
                    volume=market_data.volume_5m,
                    liquidity=market_data.liquidity_usd,
                    signal_source=SignalSource.MOMENTUM
                )
                signals.append(signal)

            elif (market_data.price_change_5m < 0 and
                  context.market_regime == MarketRegime.TRENDING_DOWN):

                # Sell signal: Strong downward momentum
                confidence = min(0.8, abs(market_data.price_change_5m) * 10)
                price_target = market_data.current_price * 0.9   # 10% target
                stop_loss = market_data.current_price * 1.07   # 7% stop loss

                signal = TradingSignal(
                    symbol=context.symbol,
                    action=TradingAction.SELL,
                    confidence=confidence,
                    timeframe="1m",
                    timestamp=time(),
                    price_target=price_target,
                    stop_loss=stop_loss,
                    volume=market_data.volume_5m,
                    liquidity=market_data.liquidity_usd,
                    signal_source=SignalSource.MOMENTUM
                )
                signals.append(signal)

        return signals

    fn _arbitrage_strategy(self, context) -> List[TradingSignal]:
        """
        Arbitrage strategy (simplified implementation)
        """
        signals = []

        # This would be implemented with multiple DEX data sources
        # For now, return empty as we don't have multi-DEX data
        return signals

    fn _calculate_rsi_confidence(self, confluence: ConfluenceAnalysis) -> Float:
        """
        Calculate confidence score for RSI-based signals
        """
        base_confidence = 0.5

        # Boost confidence based on confluence strength
        confluence_boost = confluence.confluence_strength * 0.3

        # Boost confidence based on RSI extremity
        rsi_boost = 0.0
        if confluence.is_oversold:
            rsi_boost = (OVERSOLD_THRESHOLD - confluence.rsi_value) / OVERSOLD_THRESHOLD * 0.2
        elif confluence.is_overbought:
            rsi_boost = (confluence.rsi_value - OVERBOUGHT_THRESHOLD) / (100 - OVERBOUGHT_THRESHOLD) * 0.2

        # Distance to level boost
        distance_boost = 0.0
        if confluence.distance_to_support > 0:
            distance_boost = min(0.1, confluence.distance_to_support / 0.1)
        elif confluence.distance_to_resistance > 0:
            distance_boost = min(0.1, confluence.distance_to_resistance / 0.1)

        total_confidence = base_confidence + confluence_boost + rsi_boost + distance_boost
        return min(1.0, total_confidence)

    fn _rank_signals(self, signals: List[TradingSignal]) -> List[TradingSignal]:
        """
        Rank signals by confidence and other factors
        """
        # Calculate composite score for each signal
        scored_signals = []
        for signal in signals:
            score = self._calculate_signal_score(signal)
            scored_signals.append((score, signal))

        # Sort by score (descending)
        scored_signals.sort(key=lambda x: x[0], reverse=True)

        # Return only signals
        return [signal for _, signal in scored_signals]

    fn _calculate_signal_score(self, signal: TradingSignal) -> Float:
        """
        Calculate composite score for a signal
        """
        base_score = signal.confidence

        # Volume bonus
        volume_bonus = min(0.1, signal.volume / 100000.0)

        # Liquidity bonus
        liquidity_bonus = min(0.1, signal.liquidity / 50000.0)

        # Risk-reward bonus
        risk_reward_bonus = 0.0
        if signal.price_target > 0 and signal.stop_loss > 0:
            risk_reward_ratio = abs(signal.price_target - signal.stop_loss) / signal.stop_loss
            if risk_reward_ratio >= MIN_RISK_REWARD_RATIO:
                risk_reward_bonus = min(0.2, risk_reward_ratio / 10.0)

        total_score = base_score + volume_bonus + liquidity_bonus + risk_reward_bonus
        return min(1.0, total_score)

    def should_exit_position(self, current_price: Float, position) -> Dict[str, Any]:
        """
        Determine if a position should be exited
        """
        exit_signals = []

        # Stop loss check
        if current_price <= position.stop_loss_price:
            exit_signals.append({
                "reason": "STOP_LOSS",
                "urgency": 1.0,
                "confidence": 1.0
            })

        # Take profit check
        if current_price >= position.take_profit_price:
            exit_signals.append({
                "reason": "TAKE_PROFIT",
                "urgency": 0.8,
                "confidence": 0.9
            })

        # Time-based exit
        position_age_hours = (time() - position.entry_timestamp) / 3600
        if position_age_hours >= 4.0:  # 4 hour time limit
            exit_signals.append({
                "reason": "TIME_BASED",
                "urgency": 0.6,
                "confidence": 0.7
            })

        # If multiple exit signals, take the most urgent
        if exit_signals:
            exit_signals.sort(key=lambda x: x["urgency"], reverse=True)
            return exit_signals[0]

        return {"should_exit": False}

    def update_signal_with_sentiment(self, signal: TradingSignal, market_data: MarketData) -> TradingSignal:
        """
        Update signal with sentiment analysis
        """
        try:
            sentiment = self.sentiment_analyzer.analyze_sentiment(signal.symbol, market_data)
            signal.sentiment_score = sentiment.sentiment_score
            signal.ai_analysis = sentiment

            # Adjust confidence based on sentiment
            if sentiment.sentiment_score > 0.3 and signal.action == TradingAction.BUY:
                signal.confidence = min(1.0, signal.confidence + 0.1)
            elif sentiment.sentiment_score < -0.3 and signal.action == TradingAction.SELL:
                signal.confidence = min(1.0, signal.confidence + 0.1)
            elif sentiment.sentiment_score < -0.5 and signal.action == TradingAction.BUY:
                signal.confidence = max(0.0, signal.confidence - 0.2)

        except e:
            print(f"⚠️  Error updating signal with sentiment: {e}")

        return signal

    def get_strategy_performance(self) -> Dict[str, Any]:
        """
        Get strategy performance metrics
        """
        # This would be implemented with actual performance tracking
        return {
            "total_signals": 0,
            "successful_signals": 0,
            "success_rate": 0.0,
            "average_return": 0.0,
            "sharpe_ratio": 0.0,
            "max_drawdown": 0.0,
            "strategies": {
                "RSI_SUPPORT": {"signals": 0, "success_rate": 0.0},
                "MOMENTUM": {"signals": 0, "success_rate": 0.0},
                "MEAN_REVERSION": {"signals": 0, "success_rate": 0.0},
                "ARBITRAGE": {"signals": 0, "success_rate": 0.0}
            }
        }