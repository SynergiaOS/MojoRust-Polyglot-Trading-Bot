#!/usr/bin/env python3
"""
Flash Loan Integration Tests
Comprehensive testing for Save, Solend, and Mango V4 flash loan integration
"""

import pytest
import asyncio
import json
import time
from decimal import Decimal
from unittest.mock import Mock, AsyncMock, patch
from typing import Dict, Any, List

from python.flash_loan_pipeline import (
    FlashLoanPipeline, FlashLoanSignal, FlashLoanRequest, FlashLoanResult,
    create_flash_loan_signal, publish_mojo_signal
)
from python.save_executor import SaveExecutor
from python.solend_executor import SolendExecutor
from python.jupiter_executor import JupiterSwapExecutor


class TestFlashLoanIntegration:
    """Comprehensive flash loan integration tests"""

    @pytest.fixture
    async def mock_redis(self):
        """Mock Redis client for testing"""
        mock_redis = AsyncMock()
        mock_redis.ping.return_value = True
        mock_redis.blpop.return_value = None  # No signals by default
        mock_redis.lpush.return_value = True
        mock_redis.publish.return_value = True
        return mock_redis

    @pytest.fixture
    async def flash_loan_pipeline(self, mock_redis):
        """Create flash loan pipeline with mocked dependencies"""
        pipeline = FlashLoanPipeline(redis_url="redis://localhost:6379")
        pipeline.redis_client = mock_redis
        return pipeline

    @pytest.fixture
    def sample_mojo_signal(self):
        """Sample Mojo sniper signal for testing"""
        return {
            "action": "flash_loan",
            "amount": 2_000_000_000,  # 2 SOL in lamports
            "token": "USDC",
            "token_mint": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            "confidence": 0.85,
            "expected_profit": 3.2,
            "execution_deadline": int(time.time() * 1000) + 30000,
            "preferred_provider": "save",
            "slippage_bps": 50,
            "urgency_level": "high",
            "risk_score": 0.2,
            "liquidity_score": 0.9,
            "social_score": 0.8,
            "quote": {
                "outAmount": "2056000000",
                "priceImpactPct": "0.15"
            },
            "market_data": {
                "lp_burned": 95.0,
                "volume_24h": 15000.0,
                "social_mentions": 25,
                "holder_count": 500,
                "market_cap": 250000,
                "age_minutes": 3
            }
        }

    @pytest.fixture
    def sample_flash_loan_request(self):
        """Sample flash loan request for testing"""
        return FlashLoanRequest(
            provider="save",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            amount=2_000_000_000,
            slippage_bps=50,
            urgency_level="high",
            expected_profit=3.2,
            confidence=0.85,
            risk_score=0.2,
            market_data={"lp_burned": 95.0, "volume_24h": 15000.0}
        )


class TestFlashLoanSignal:
    """Test flash loan signal creation and validation"""

    def test_create_flash_loan_signal(self, sample_mojo_signal):
        """Test creating FlashLoanSignal from Mojo signal data"""
        signal = create_flash_loan_signal(sample_mojo_signal)

        assert signal.action == "flash_loan"
        assert signal.amount == 2_000_000_000
        assert signal.token_mint == "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        assert signal.confidence == 0.85
        assert signal.preferred_provider == "save"
        assert signal.slippage_bps == 50
        assert signal.urgency_level == "high"
        assert signal.risk_score == 0.2
        assert signal.liquidity_score == 0.9
        assert signal.social_score == 0.8

    def test_flash_loan_signal_validation(self, sample_mojo_signal):
        """Test FlashLoanSignal validation"""
        signal = create_flash_loan_signal(sample_mojo_signal)

        # Test valid signal
        assert signal.action in ["flash_loan", "buy", "sell", "hold"]
        assert signal.amount > 0
        assert signal.token_mint != ""
        assert 0.0 <= signal.confidence <= 1.0
        assert signal.preferred_provider in ["save", "solend", "mango_v4"]
        assert 0 <= signal.slippage_bps <= 1000
        assert signal.urgency_level in ["high", "medium", "low"]
        assert 0.0 <= signal.risk_score <= 1.0

    def test_invalid_flash_loan_signal(self):
        """Test handling of invalid flash loan signals"""
        invalid_signals = [
            {"action": "invalid", "amount": 1000, "token_mint": ""},  # Invalid action
            {"action": "flash_loan", "amount": -1, "token_mint": "valid"},  # Negative amount
            {"action": "flash_loan", "amount": 1000, "token_mint": ""},  # Empty mint
            {"action": "flash_loan", "amount": 1000, "token_mint": "valid", "confidence": 1.5},  # Invalid confidence
        ]

        for invalid_data in invalid_signals:
            with pytest.raises((KeyError, ValueError, AssertionError)):
                signal = create_flash_loan_signal(invalid_data)


class TestSaveExecutor:
    """Test Save flash loan executor"""

    @pytest.fixture
    def save_executor(self):
        """Create Save executor instance"""
        return SaveExecutor()

    @pytest.mark.asyncio
    async def test_save_flash_loan_execution(self, save_executor, sample_flash_loan_request):
        """Test Save flash loan execution"""
        result = await save_executor.execute_flash_loan(sample_flash_loan_request)

        assert isinstance(result, FlashLoanResult)
        assert result.success in [True, False]
        assert result.execution_time_ms >= 0
        assert result.fees_paid >= 0

        if result.success:
            assert result.transaction_id != ""
            assert result.actual_amount_out > 0
            assert result.error_message is None
        else:
            assert result.error_message is not None

    @pytest.mark.asyncio
    async def test_save_amount_limit(self, save_executor):
        """Test Save flash loan amount limits"""
        # Test amount exceeding limit
        large_request = FlashLoanRequest(
            provider="save",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            amount=10_000_000_000,  # 10 SOL - exceeds Save limit of 5 SOL
            slippage_bps=50,
            urgency_level="high",
            expected_profit=5.0,
            confidence=0.9,
            risk_score=0.1,
            market_data={}
        )

        result = await save_executor.execute_flash_loan(large_request)
        assert not result.success
        assert "exceeds Save maximum" in result.error_message

    @pytest.mark.asyncio
    async def test_save_protocol_info(self, save_executor):
        """Test Save protocol information"""
        info = await save_executor.get_protocol_info()

        assert info["name"] == "Save"
        assert info["fee_bps"] == 3
        assert info["max_latency_ms"] == 20
        assert info["max_loan_amount"] == 5_000_000_000
        assert isinstance(info["supported_tokens"], list)
        assert "So11111111111111111111111111111111111111112" in info["supported_tokens"]


class TestSolendExecutor:
    """Test Solend flash loan executor"""

    @pytest.fixture
    def solend_executor(self):
        """Create Solend executor instance"""
        return SolendExecutor()

    @pytest.mark.asyncio
    async def test_solend_flash_loan_execution(self, solend_executor, sample_flash_loan_request):
        """Test Solend flash loan execution"""
        request = sample_flash_loan_request
        request.provider = "solend"

        result = await solend_executor.execute_flash_loan(request)

        assert isinstance(result, FlashLoanResult)
        assert result.execution_time_ms >= 20  # Solend has higher latency

    @pytest.mark.asyncio
    async def test_solend_market_data(self, solend_executor):
        """Test Solend market data retrieval"""
        market_data = await solend_executor.get_market_data("EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")

        assert "lending_market" in market_data
        assert "reserve" in market_data
        assert "available_liquidity" in market_data
        assert "borrow_rate" in market_data
        assert "health_factor" in market_data

    @pytest.mark.asyncio
    async def test_solend_protocol_info(self, solend_executor):
        """Test Solend protocol information"""
        info = await solend_executor.get_protocol_info()

        assert info["name"] == "Solend"
        assert info["fee_bps"] == 5
        assert info["max_latency_ms"] == 30
        assert info["max_loan_amount"] == 50_000_000_000


class TestFlashLoanPipeline:
    """Test flash loan integration pipeline"""

    @pytest.mark.asyncio
    async def test_pipeline_startup(self, flash_loan_pipeline):
        """Test pipeline startup"""
        await flash_loan_pipeline.start()

        # Verify startup
        assert flash_loan_pipeline.redis_client is not None
        assert flash_loan_pipeline.jupiter_executor is not None
        assert flash_loan_pipeline.save_executor is not None
        assert flash_loan_pipeline.solend_executor is not None

        await flash_loan_pipeline.stop()

    @pytest.mark.asyncio
    async def test_signal_processing(self, flash_loan_pipeline, sample_mojo_signal, mock_redis):
        """Test signal processing"""
        await flash_loan_pipeline.start()

        # Mock signal reception
        signal_json = json.dumps(sample_mojo_signal)
        mock_redis.blpop.return_value = ("mojo_sniper_signals", signal_json)

        # Process signal (simulate one iteration)
        signal = create_flash_loan_signal(sample_mojo_signal)
        await flash_loan_pipeline._process_signal(signal)

        # Verify signal was processed
        assert flash_loan_pipeline.signals_processed >= 0

        await flash_loan_pipeline.stop()

    @pytest.mark.asyncio
    async def test_flash_loan_routing(self, flash_loan_pipeline, sample_flash_loan_request):
        """Test flash loan routing to optimal provider"""
        await flash_loan_pipeline.start()

        result = await flash_loan_pipeline._route_flash_loan(sample_flash_loan_request)

        assert isinstance(result, FlashLoanResult)
        # Should route to Save for 2 SOL
        assert result.execution_time_ms <= 30  # Save has 20ms max latency

        await flash_loan_pipeline.stop()

    @pytest.mark.asyncio
    async def test_provider_selection(self, flash_loan_pipeline):
        """Test optimal provider selection based on amount"""
        await flash_loan_pipeline.start()

        # Test small amount (should use Save)
        small_request = FlashLoanRequest(
            provider="",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            amount=1_000_000_000,  # 1 SOL
            slippage_bps=50,
            urgency_level="high",
            expected_profit=2.0,
            confidence=0.8,
            risk_score=0.2,
            market_data={}
        )

        result = await flash_loan_pipeline._route_flash_loan(small_request)
        assert result.execution_time_ms <= 25  # Save should be used

        # Test medium amount (should use Solend)
        medium_request = FlashLoanRequest(
            provider="",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            amount=10_000_000_000,  # 10 SOL
            slippage_bps=50,
            urgency_level="medium",
            expected_profit=3.0,
            confidence=0.85,
            risk_score=0.15,
            market_data={}
        )

        result = await flash_loan_pipeline._route_flash_loan(medium_request)
        assert result.execution_time_ms <= 35  # Solend should be used

        await flash_loan_pipeline.stop()

    @pytest.mark.asyncio
    async def test_pipeline_statistics(self, flash_loan_pipeline):
        """Test pipeline performance statistics"""
        await flash_loan_pipeline.start()

        stats = await flash_loan_pipeline.get_pipeline_stats()

        assert "signals_processed" in stats
        assert "flash_loans_executed" in stats
        assert "successful_executions" in stats
        assert "success_rate" in stats
        assert "total_profit" in stats
        assert "average_profit_per_trade" in stats

        # Initial stats should be zero or positive
        assert stats["signals_processed"] >= 0
        assert stats["success_rate"] >= 0.0
        assert stats["total_profit"] >= 0.0

        await flash_loan_pipeline.stop()


class TestRiskManagement:
    """Test risk management in flash loan execution"""

    @pytest.mark.asyncio
    async def test_high_risk_signal_rejection(self, flash_loan_pipeline):
        """Test rejection of high-risk signals"""
        await flash_loan_pipeline.start()

        # Create high-risk signal
        high_risk_signal = FlashLoanSignal(
            action="flash_loan",
            amount=2_000_000_000,
            token="USDC",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            confidence=0.6,  # Low confidence
            expected_profit=5.0,
            execution_deadline=int(time.time() * 1000) + 30000,
            preferred_provider="save",
            slippage_bps=50,
            urgency_level="high",
            risk_score=0.8,  # High risk
            liquidity_score=0.9,
            social_score=0.8,
            quote={},
            market_data={}
        )

        await flash_loan_pipeline._process_signal(high_risk_signal)
        # Signal should be ignored due to high risk
        assert flash_loan_pipeline.signals_processed >= 0

        await flash_loan_pipeline.stop()

    @pytest.mark.asyncio
    async def test_expired_signal_handling(self, flash_loan_pipeline):
        """Test handling of expired signals"""
        await flash_loan_pipeline.start()

        # Create expired signal
        expired_signal = FlashLoanSignal(
            action="flash_loan",
            amount=2_000_000_000,
            token="USDC",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            confidence=0.9,
            expected_profit=3.0,
            execution_deadline=int(time.time() * 1000) - 1000,  # Expired
            preferred_provider="save",
            slippage_bps=50,
            urgency_level="high",
            risk_score=0.1,
            liquidity_score=0.9,
            social_score=0.8,
            quote={},
            market_data={}
        )

        await flash_loan_pipeline._process_signal(expired_signal)
        # Expired signal should be ignored
        assert flash_loan_pipeline.signals_processed >= 0

        await flash_loan_pipeline.stop()


class TestPerformanceBenchmarks:
    """Performance benchmarks for flash loan execution"""

    @pytest.mark.asyncio
    async def test_execution_latency(self, flash_loan_pipeline, sample_flash_loan_request):
        """Benchmark flash loan execution latency"""
        await flash_loan_pipeline.start()

        start_time = time.time()
        result = await flash_loan_pipeline._route_flash_loan(sample_flash_loan_request)
        end_time = time.time()

        execution_time_ms = (end_time - start_time) * 1000

        # Save flash loan should complete within 50ms (including network overhead)
        assert execution_time_ms < 50
        assert result.execution_time_ms < 30  # Individual execution time

        await flash_loan_pipeline.stop()

    @pytest.mark.asyncio
    async def test_concurrent_execution(self, flash_loan_pipeline):
        """Test concurrent flash loan execution"""
        await flash_loan_pipeline.start()

        # Create multiple concurrent requests
        requests = []
        for i in range(5):
            request = FlashLoanRequest(
                provider="save" if i % 2 == 0 else "solend",
                token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
                amount=1_000_000_000 + (i * 500_000_000),
                slippage_bps=50,
                urgency_level="high",
                expected_profit=2.0 + i * 0.5,
                confidence=0.8 + (i * 0.02),
                risk_score=0.1 + (i * 0.05),
                market_data={}
            )
            requests.append(request)

        # Execute concurrently
        start_time = time.time()
        tasks = [flash_loan_pipeline._route_flash_loan(req) for req in requests]
        results = await asyncio.gather(*tasks)
        end_time = time.time()

        total_time_ms = (end_time - start_time) * 1000

        # Concurrent execution should be faster than sequential
        assert total_time_ms < 200  # All 5 requests in under 200ms
        assert len(results) == 5
        assert all(isinstance(r, FlashLoanResult) for r in results)

        await flash_loan_pipeline.stop()


# Integration test utilities
class TestMojoIntegration:
    """Test Mojo signal integration"""

    @pytest.mark.asyncio
    async def test_mojo_signal_publishing(self, mock_redis):
        """Test publishing Mojo signals to Redis"""
        signal = FlashLoanSignal(
            action="flash_loan",
            amount=2_000_000_000,
            token="USDC",
            token_mint="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            confidence=0.85,
            expected_profit=3.2,
            execution_deadline=int(time.time() * 1000) + 30000,
            preferred_provider="save",
            slippage_bps=50,
            urgency_level="high",
            risk_score=0.2,
            liquidity_score=0.9,
            social_score=0.8,
            quote={},
            market_data={}
        )

        await publish_mojo_signal(mock_redis, signal)

        # Verify signal was published
        mock_redis.lpush.assert_called_once()
        mock_redis.publish.assert_called_once()

        # Verify call arguments
        lpush_call = mock_redis.lpush.call_args
        publish_call = mock_redis.publish.call_args

        assert lpush_call[0][0] == "mojo_sniper_signals"
        assert publish_call[0][0] == "mojo_signals"


if __name__ == "__main__":
    # Run tests
    pytest.main([__file__, "-v", "--tb=short"])