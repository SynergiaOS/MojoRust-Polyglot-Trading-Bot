# =============================================================================
# Strategy Engine Module
# =============================================================================

from time import time
from collections import Dict, List
from math import sqrt, abs
from core.types import (
    TradingSignal, MarketData, ConfluenceAnalysis, TradingAction,
    SignalSource, MarketRegime, SentimentAnalysis, Config
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
    var config: Config
    var sentiment_analyzer: SentimentAnalyzer

    fn __init__(config: Config):
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
        max_signals = int(self.config.trading.max_positions_per_trade) if hasattr(self.config.trading, 'max_positions_per_trade') else 5
        return ranked_signals[:max_signals]  # Return top signals from config

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
            stop_loss = confluence.nearest_support * self.config.strategy_thresholds.stop_loss_below_support  # Using config threshold

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
                signal_source=SignalSource.RSI_SUPPORT,
                metadata={
                    "price_change_5m": context.market_data.price_change_5m,
                    "volume_5m": context.market_data.volume_5m,
                    "holder_count": context.market_data.holder_count,
                    "age_hours": context.market_data.age_hours
                }
            )

            signals.append(signal)

        # Check for sell signal (RSI overbought + near resistance)
        elif (confluence.is_overbought and
              confluence.distance_to_resistance <= self.config.strategy.support_distance):

            confidence = self._calculate_rsi_confidence(confluence)
            price_target = confluence.nearest_support
            stop_loss = confluence.nearest_resistance * self.config.strategy_thresholds.stop_loss_above_resistance  # Using config threshold

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
                signal_source=SignalSource.RSI_SUPPORT,
                metadata={
                    "price_change_5m": context.market_data.price_change_5m,
                    "volume_5m": context.market_data.volume_5m,
                    "holder_count": context.market_data.holder_count,
                    "age_hours": context.market_data.age_hours
                }
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
            # Calculate Bollinger Bands-like levels (using config thresholds)
            recent_high = market_data.current_price * self.config.strategy_thresholds.mean_reversion_upper_band
            recent_low = market_data.current_price * self.config.strategy_thresholds.mean_reversion_lower_band
            middle_band = (recent_high + recent_low) / 2

            # Buy signal: Price near lower band (using config threshold)
            if market_data.current_price <= recent_low * self.config.strategy_thresholds.mean_reversion_buy_threshold:
                confidence = self.config.strategy_thresholds.mean_reversion_confidence
                price_target = middle_band
                stop_loss = recent_low * self.config.strategy_thresholds.mean_reversion_stop_loss_buy

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
                    signal_source=SignalSource.MEAN_REVERSION,
                    metadata={
                        "price_change_5m": market_data.price_change_5m,
                        "volume_5m": market_data.volume_5m,
                        "holder_count": market_data.holder_count,
                        "age_hours": market_data.age_hours
                    }
                )
                signals.append(signal)

            # Sell signal: Price near upper band (using config threshold)
            elif market_data.current_price >= recent_high * self.config.strategy_thresholds.mean_reversion_sell_threshold:
                confidence = self.config.strategy_thresholds.mean_reversion_confidence
                price_target = middle_band
                stop_loss = recent_high * self.config.strategy_thresholds.mean_reversion_stop_loss_sell

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
                    signal_source=SignalSource.MEAN_REVERSION,
                    metadata={
                        "price_change_5m": market_data.price_change_5m,
                        "volume_5m": market_data.volume_5m,
                        "holder_count": market_data.holder_count,
                        "age_hours": market_data.age_hours
                    }
                )
                signals.append(signal)

        return signals

    fn _momentum_strategy(self, context) -> List[TradingSignal]:
        """
        Momentum strategy for trending markets
        """
        signals = []
        market_data = context.market_data

        # Check for strong momentum (using config threshold)
        if abs(market_data.price_change_5m) > self.config.strategy_thresholds.momentum_threshold:
            if (market_data.price_change_5m > 0 and
                context.market_regime == MarketRegime.TRENDING_UP):

                # Buy signal: Strong upward momentum (using config thresholds)
                confidence = min(self.config.strategy_thresholds.momentum_max_confidence, abs(market_data.price_change_5m) * self.config.strategy_thresholds.momentum_confidence_multiplier)
                price_target = market_data.current_price * self.config.strategy_thresholds.price_target_momentum_buy  # Using config target
                stop_loss = market_data.current_price * self.config.strategy_thresholds.stop_loss_momentum_buy   # Using config stop loss

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
                    signal_source=SignalSource.MOMENTUM,
                    metadata={
                        "price_change_5m": market_data.price_change_5m,
                        "volume_5m": market_data.volume_5m,
                        "holder_count": market_data.holder_count,
                        "age_hours": market_data.age_hours
                    }
                )
                signals.append(signal)

            elif (market_data.price_change_5m < 0 and
                  context.market_regime == MarketRegime.TRENDING_DOWN):

                # Sell signal: Strong downward momentum (using config thresholds)
                confidence = min(self.config.strategy_thresholds.momentum_max_confidence, abs(market_data.price_change_5m) * self.config.strategy_thresholds.momentum_confidence_multiplier)
                price_target = market_data.current_price * self.config.strategy_thresholds.price_target_momentum_sell   # Using config target
                stop_loss = market_data.current_price * self.config.strategy_thresholds.stop_loss_momentum_sell   # Using config stop loss

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
                    signal_source=SignalSource.MOMENTUM,
                    metadata={
                        "price_change_5m": market_data.price_change_5m,
                        "volume_5m": market_data.volume_5m,
                        "holder_count": market_data.holder_count,
                        "age_hours": market_data.age_hours
                    }
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
        Calculate confidence score for RSI-based signals (using config thresholds)
        """
        base_confidence = self.config.strategy_thresholds.base_confidence

        # Boost confidence based on confluence strength (using config multiplier)
        confluence_boost = confluence.confluence_strength * self.config.strategy_thresholds.confluence_boost_multiplier

        # Boost confidence based on RSI extremity (using config multiplier)
        rsi_boost = 0.0
        if confluence.is_oversold:
            rsi_boost = (OVERSOLD_THRESHOLD - confluence.rsi_value) / OVERSOLD_THRESHOLD * self.config.strategy_thresholds.rsi_boost_multiplier
        elif confluence.is_overbought:
            rsi_boost = (confluence.rsi_value - OVERBOUGHT_THRESHOLD) / (100 - OVERBOUGHT_THRESHOLD) * self.config.strategy_thresholds.rsi_boost_multiplier

        # Distance to level boost (using config thresholds)
        distance_boost = 0.0
        if confluence.distance_to_support > 0:
            distance_boost = min(self.config.strategy_thresholds.distance_boost_max, confluence.distance_to_support / self.config.strategy_thresholds.distance_boost_divisor)
        elif confluence.distance_to_resistance > 0:
            distance_boost = min(self.config.strategy_thresholds.distance_boost_max, confluence.distance_to_resistance / self.config.strategy_thresholds.distance_boost_divisor)

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

        # Volume bonus (using config thresholds)
        volume_bonus = min(self.config.strategy_thresholds.volume_bonus_max, signal.volume / self.config.strategy_thresholds.volume_bonus_divisor)

        # Liquidity bonus (using config thresholds)
        liquidity_bonus = min(self.config.strategy_thresholds.liquidity_bonus_max, signal.liquidity / self.config.strategy_thresholds.liquidity_bonus_divisor)

        # Risk-reward bonus (using config thresholds)
        risk_reward_bonus = 0.0
        if signal.price_target > 0 and signal.stop_loss > 0:
            risk_reward_ratio = abs(signal.price_target - signal.stop_loss) / signal.stop_loss
            if risk_reward_ratio >= MIN_RISK_REWARD_RATIO:
                risk_reward_bonus = min(self.config.strategy_thresholds.risk_reward_bonus_max, risk_reward_ratio / self.config.strategy_thresholds.risk_reward_bonus_divisor)

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
                "urgency": self.config.strategy_thresholds.exit_urgency_take_profit,
                "confidence": self.config.strategy_thresholds.exit_confidence_take_profit
            })

        # Time-based exit (using config threshold)
        position_age_hours = (time() - position.entry_timestamp) / 3600
        if position_age_hours >= self.config.strategy_thresholds.position_age_exit_hours:  # Using config time limit
            exit_signals.append({
                "reason": "TIME_BASED",
                "urgency": self.config.strategy_thresholds.exit_urgency_time_based,
                "confidence": self.config.strategy_thresholds.exit_confidence_time_based
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

            # Adjust confidence based on sentiment (using config thresholds)
            if sentiment.sentiment_score > self.config.strategy_thresholds.sentiment_positive_threshold and signal.action == TradingAction.BUY:
                signal.confidence = min(1.0, signal.confidence + self.config.strategy_thresholds.sentiment_confidence_boost)
            elif sentiment.sentiment_score < self.config.strategy_thresholds.sentiment_negative_threshold and signal.action == TradingAction.SELL:
                signal.confidence = min(1.0, signal.confidence + self.config.strategy_thresholds.sentiment_confidence_boost)
            elif sentiment.sentiment_score < self.config.strategy_thresholds.sentiment_very_negative and signal.action == TradingAction.BUY:
                signal.confidence = max(0.0, signal.confidence - self.config.strategy_thresholds.sentiment_confidence_penalty)

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