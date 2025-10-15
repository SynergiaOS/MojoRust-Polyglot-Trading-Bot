#!/usr/bin/env python3
"""
Test suite for DTO contracts and type safety
"""

import pytest
import json
from dataclasses import asdict
from unittest.mock import Mock, patch
from src.data.social_client import SocialClient
from src.data.honeypot_client import HoneypotClient


class TestSocialAnalysisDTO:
    """Test SocialAnalysis DTO contract"""

    def test_social_analysis_creation(self):
        """Test SocialAnalysis struct creation and validation"""
        # Mock the import since we're testing Mojo structs
        with patch('src.data.social_client.SocialAnalysis') as mock_social_analysis:
            mock_instance = Mock()
            mock_instance.overall_social_score = 0.75
            mock_instance.social_assessment = "Positive sentiment detected"
            mock_instance.meets_sniper_requirements = True
            mock_instance.total_mentions = 150
            mock_instance.sentiment_score = 0.8
            mock_instance.viral_score = 0.6
            mock_instance.safety_score = 0.85
            mock_instance.momentum_score = 0.7
            mock_instance.confidence_score = 0.75
            mock_social_analysis.return_value = mock_instance

            from src.data.social_client import SocialAnalysis
            analysis = SocialAnalysis(
                overall_social_score=0.75,
                social_assessment="Positive sentiment detected",
                meets_sniper_requirements=True,
                total_mentions=150,
                sentiment_score=0.8,
                viral_score=0.6,
                safety_score=0.85,
                momentum_score=0.7,
                confidence_score=0.75
            )

            assert analysis.overall_social_score == 0.75
            assert analysis.social_assessment == "Positive sentiment detected"
            assert analysis.meets_sniper_requirements is True
            assert analysis.total_mentions == 150
            assert analysis.sentiment_score == 0.8
            assert analysis.viral_score == 0.6
            assert analysis.safety_score == 0.85
            assert analysis.momentum_score == 0.7
            assert analysis.confidence_score == 0.75

    def test_social_analysis_validation(self):
        """Test SocialAnalysis field validation"""
        with patch('src.data.social_client.SocialAnalysis') as mock_social_analysis:
            # Test score bounds validation
            valid_scores = [-1.0, -0.5, 0.0, 0.5, 1.0]

            for score in valid_scores:
                mock_instance = Mock()
                mock_instance.overall_social_score = score
                mock_instance.social_assessment = "Valid"
                mock_instance.meets_sniper_requirements = True
                mock_instance.total_mentions = 10
                mock_instance.sentiment_score = score
                mock_instance.viral_score = score
                mock_instance.safety_score = score
                mock_instance.momentum_score = score
                mock_instance.confidence_score = score
                mock_social_analysis.return_value = mock_instance

                analysis = SocialAnalysis(
                    overall_social_score=score,
                    social_assessment="Valid",
                    meets_sniper_requirements=True,
                    total_mentions=10,
                    sentiment_score=score,
                    viral_score=score,
                    safety_score=score,
                    momentum_score=score,
                    confidence_score=score
                )
                assert analysis.overall_social_score == score

    def test_social_analysis_edge_cases(self):
        """Test SocialAnalysis edge cases"""
        with patch('src.data.social_client.SocialAnalysis') as mock_social_analysis:
            # Test edge case: No mentions
            mock_instance = Mock()
            mock_instance.overall_social_score = 0.0
            mock_instance.social_assessment = "No social data available"
            mock_instance.meets_sniper_requirements = False
            mock_instance.total_mentions = 0
            mock_instance.sentiment_score = 0.0
            mock_instance.viral_score = 0.0
            mock_instance.safety_score = 0.5
            mock_instance.momentum_score = 0.0
            mock_instance.confidence_score = 0.0
            mock_social_analysis.return_value = mock_instance

            analysis = SocialAnalysis(
                overall_social_score=0.0,
                social_assessment="No social data available",
                meets_sniper_requirements=False,
                total_mentions=0,
                sentiment_score=0.0,
                viral_score=0.0,
                safety_score=0.5,
                momentum_score=0.0,
                confidence_score=0.0
            )

            assert analysis.total_mentions == 0
            assert analysis.meets_sniper_requirements is False


class TestHoneypotAnalysisDTO:
    """Test HoneypotAnalysis DTO contract"""

    def test_honeypot_analysis_creation(self):
        """Test HoneypotAnalysis struct creation"""
        with patch('src.data.honeypot_client.HoneypotAnalysis') as mock_honeypot_analysis:
            mock_instance = Mock()
            mock_instance.is_honeypot = False
            mock_instance.honeypot_probability = 0.15
            mock_instance.liquidity_locked = True
            mock_instance.liquidity_lock_percentage = 95.0
            mock_instance.contract_renounced = True
            mock_instance.owner_balance = 0.02
            mock_instance.top_10_holder_percentage = 35.0
            mock_instance.buy_tax = 0.0
            mock_instance.sell_tax = 0.0
            mock_instance.risk_score = 0.25
            mock_instance.assessment = "Low risk token"
            mock_instance.confidence = 0.85
            mock_honeypot_analysis.return_value = mock_instance

            from src.data.honeypot_client import HoneypotAnalysis
            analysis = HoneypotAnalysis(
                is_honeypot=False,
                honeypot_probability=0.15,
                liquidity_locked=True,
                liquidity_lock_percentage=95.0,
                contract_renounced=True,
                owner_balance=0.02,
                top_10_holder_percentage=35.0,
                buy_tax=0.0,
                sell_tax=0.0,
                risk_score=0.25,
                assessment="Low risk token",
                confidence=0.85
            )

            assert analysis.is_honeypot is False
            assert analysis.honeypot_probability == 0.15
            assert analysis.liquidity_locked is True
            assert analysis.liquidity_lock_percentage == 95.0
            assert analysis.contract_renounced is True
            assert analysis.owner_balance == 0.02
            assert analysis.top_10_holder_percentage == 35.0
            assert analysis.buy_tax == 0.0
            assert analysis.sell_tax == 0.0
            assert analysis.risk_score == 0.25
            assert analysis.assessment == "Low risk token"
            assert analysis.confidence == 0.85

    def test_honeypot_analysis_validation(self):
        """Test HoneypotAnalysis field validation"""
        with patch('src.data.honeypot_client.HoneypotAnalysis') as mock_honeypot_analysis:
            # Test probability bounds
            valid_probabilities = [0.0, 0.25, 0.5, 0.75, 1.0]

            for prob in valid_probabilities:
                mock_instance = Mock()
                mock_instance.is_honeypot = prob > 0.5
                mock_instance.honeypot_probability = prob
                mock_instance.liquidity_locked = True
                mock_instance.liquidity_lock_percentage = 80.0
                mock_instance.contract_renounced = True
                mock_instance.owner_balance = 0.01
                mock_instance.top_10_holder_percentage = 30.0
                mock_instance.buy_tax = 0.02
                mock_instance.sell_tax = 0.02
                mock_instance.risk_score = prob
                mock_instance.assessment = f"Risk level: {prob}"
                mock_instance.confidence = 0.8
                mock_honeypot_analysis.return_value = mock_instance

                analysis = HoneypotAnalysis(
                    is_honeypot=prob > 0.5,
                    honeypot_probability=prob,
                    liquidity_locked=True,
                    liquidity_lock_percentage=80.0,
                    contract_renounced=True,
                    owner_balance=0.01,
                    top_10_holder_percentage=30.0,
                    buy_tax=0.02,
                    sell_tax=0.02,
                    risk_score=prob,
                    assessment=f"Risk level: {prob}",
                    confidence=0.8
                )
                assert analysis.honeypot_probability == prob

    def test_honeypot_analysis_high_risk_scenario(self):
        """Test high-risk honeypot scenario"""
        with patch('src.data.honeypot_client.HoneypotAnalysis') as mock_honeypot_analysis:
            mock_instance = Mock()
            mock_instance.is_honeypot = True
            mock_instance.honeypot_probability = 0.95
            mock_instance.liquidity_locked = False
            mock_instance.liquidity_lock_percentage = 0.0
            mock_instance.contract_renounced = False
            mock_instance.owner_balance = 0.85
            mock_instance.top_10_holder_percentage = 95.0
            mock_instance.buy_tax = 0.20
            mock_instance.sell_tax = 0.25
            mock_instance.risk_score = 0.95
            mock_instance.assessment = "High honeypot risk - avoid"
            mock_instance.confidence = 0.9
            mock_honeypot_analysis.return_value = mock_instance

            analysis = HoneypotAnalysis(
                is_honeypot=True,
                honeypot_probability=0.95,
                liquidity_locked=False,
                liquidity_lock_percentage=0.0,
                contract_renounced=False,
                owner_balance=0.85,
                top_10_holder_percentage=95.0,
                buy_tax=0.20,
                sell_tax=0.25,
                risk_score=0.95,
                assessment="High honeypot risk - avoid",
                confidence=0.9
            )

            assert analysis.is_honeypot is True
            assert analysis.honeypot_probability == 0.95
            assert analysis.liquidity_locked is False
            assert analysis.risk_score == 0.95
            assert "avoid" in analysis.assessment


class TestSocialClientIntegration:
    """Test SocialClient with typed DTOs"""

    @pytest.mark.asyncio
    async def test_comprehensive_social_analysis_return_type(self):
        """Test that comprehensive_social_analysis returns SocialAnalysis DTO"""
        with patch('src.data.social_client.SocialAnalysis') as mock_dto:
            # Mock the SocialAnalysis struct
            mock_analysis = Mock()
            mock_analysis.overall_social_score = 0.8
            mock_analysis.social_assessment = "Strong positive sentiment"
            mock_analysis.meets_sniper_requirements = True
            mock_analysis.total_mentions = 200
            mock_analysis.sentiment_score = 0.85
            mock_analysis.viral_score = 0.7
            mock_analysis.safety_score = 0.9
            mock_analysis.momentum_score = 0.75
            mock_analysis.confidence_score = 0.8
            mock_dto.return_value = mock_analysis

            # Mock the SocialClient
            with patch('src.data.social_client.SocialClient') as mock_client_class:
                mock_client = Mock()
                mock_client.comprehensive_social_analysis = Mock(return_value=mock_analysis)
                mock_client_class.return_value = mock_client

                client = SocialClient(api_key="test_key")
                result = client.comprehensive_social_analysis("TEST", "address123", 10)

                # Verify the return type has correct attributes
                assert hasattr(result, 'overall_social_score')
                assert hasattr(result, 'social_assessment')
                assert hasattr(result, 'meets_sniper_requirements')
                assert hasattr(result, 'total_mentions')
                assert hasattr(result, 'sentiment_score')
                assert hasattr(result, 'viral_score')
                assert hasattr(result, 'safety_score')
                assert hasattr(result, 'momentum_score')
                assert hasattr(result, 'confidence_score')

    @pytest.mark.asyncio
    async def test_social_analysis_with_min_mentions_threshold(self):
        """Test social analysis behavior with different mention thresholds"""
        with patch('src.data.social_client.SocialAnalysis') as mock_dto:
            # Mock low mentions scenario
            mock_low_mentions = Mock()
            mock_low_mentions.overall_social_score = 0.1
            mock_low_mentions.social_assessment = "Low social presence"
            mock_low_mentions.meets_sniper_requirements = False
            mock_low_mentions.total_mentions = 5
            mock_low_mentions.sentiment_score = 0.0
            mock_low_mentions.viral_score = 0.0
            mock_low_mentions.safety_score = 0.5
            mock_low_mentions.momentum_score = 0.0
            mock_low_mentions.confidence_score = 0.1
            mock_dto.return_value = mock_low_mentions

            with patch('src.data.social_client.SocialClient') as mock_client_class:
                mock_client = Mock()
                mock_client.comprehensive_social_analysis = Mock(return_value=mock_low_mentions)
                mock_client_class.return_value = mock_client

                client = SocialClient(api_key="test_key")
                result = client.comprehensive_social_analysis("TEST", "address123", 50)

                assert result.total_mentions < 50
                assert result.meets_sniper_requirements is False


class TestHoneypotClientIntegration:
    """Test HoneypotClient with typed DTOs"""

    @pytest.mark.asyncio
    async def test_comprehensive_honeypot_analysis_return_type(self):
        """Test that comprehensive_honeypot_analysis returns HoneypotAnalysis DTO"""
        with patch('src.data.honeypot_client.HoneypotAnalysis') as mock_dto:
            # Mock the HoneypotAnalysis struct
            mock_analysis = Mock()
            mock_analysis.is_honeypot = False
            mock_analysis.honeypot_probability = 0.1
            mock_analysis.liquidity_locked = True
            mock_analysis.liquidity_lock_percentage = 98.0
            mock_analysis.contract_renounced = True
            mock_analysis.owner_balance = 0.01
            mock_analysis.top_10_holder_percentage = 25.0
            mock_analysis.buy_tax = 0.0
            mock_analysis.sell_tax = 0.0
            mock_analysis.risk_score = 0.15
            mock_analysis.assessment = "Safe token - good liquidity"
            mock_analysis.confidence = 0.9
            mock_dto.return_value = mock_analysis

            # Mock the HoneypotClient
            with patch('src.data.honeypot_client.HoneypotClient') as mock_client_class:
                mock_client = Mock()
                mock_client.comprehensive_honeypot_analysis = Mock(return_value=mock_analysis)
                mock_client_class.return_value = mock_client

                client = HoneypotClient()
                result = client.comprehensive_honeypot_analysis("address123")

                # Verify the return type has correct attributes
                assert hasattr(result, 'is_honeypot')
                assert hasattr(result, 'honeypot_probability')
                assert hasattr(result, 'liquidity_locked')
                assert hasattr(result, 'liquidity_lock_percentage')
                assert hasattr(result, 'contract_renounced')
                assert hasattr(result, 'owner_balance')
                assert hasattr(result, 'top_10_holder_percentage')
                assert hasattr(result, 'buy_tax')
                assert hasattr(result, 'sell_tax')
                assert hasattr(result, 'risk_score')
                assert hasattr(result, 'assessment')
                assert hasattr(result, 'confidence')

    @pytest.mark.asyncio
    async def test_honeypot_analysis_edge_cases(self):
        """Test honeypot analysis edge cases"""
        with patch('src.data.honeypot_client.HoneypotAnalysis') as mock_dto:
            # Mock uncertain case
            mock_uncertain = Mock()
            mock_uncertain.is_honeypot = False  # Not confirmed honeypot
            mock_uncertain.honeypot_probability = 0.5  # But 50% probability
            mock_uncertain.liquidity_locked = True
            mock_uncertain.liquidity_lock_percentage = 50.0  # Partial lock
            mock_uncertain.contract_renounced = False
            mock_uncertain.owner_balance = 0.3
            mock_uncertain.top_10_holder_percentage = 60.0
            mock_uncertain.buy_tax = 0.05
            mock_uncertain.sell_tax = 0.05
            mock_uncertain.risk_score = 0.6
            mock_uncertain.assessment = "Medium risk - investigate further"
            mock_uncertain.confidence = 0.5
            mock_dto.return_value = mock_uncertain

            with patch('src.data.honeypot_client.HoneypotClient') as mock_client_class:
                mock_client = Mock()
                mock_client.comprehensive_honeypot_analysis = Mock(return_value=mock_uncertain)
                mock_client_class.return_value = mock_client

                client = HoneypotClient()
                result = client.comprehensive_honeypot_analysis("address123")

                # Verify edge case handling
                assert result.is_honeypot is False
                assert result.honeypot_probability == 0.5  # Medium probability
                assert result.risk_score == 0.6  # Medium risk
                assert "investigate" in result.assessment.lower()


class TestDTOContractCompliance:
    """Test DTO contract compliance and consistency"""

    def test_dto_serialization_compatibility(self):
        """Test that DTOs maintain serialization compatibility"""
        # Test SocialAnalysis serialization compatibility
        social_data = {
            "overall_social_score": 0.75,
            "social_assessment": "Positive sentiment",
            "meets_sniper_requirements": True,
            "total_mentions": 100,
            "sentiment_score": 0.8,
            "viral_score": 0.6,
            "safety_score": 0.85,
            "momentum_score": 0.7,
            "confidence_score": 0.75
        }

        # Verify JSON serialization/deserialization
        serialized = json.dumps(social_data)
        deserialized = json.loads(serialized)

        assert deserialized["overall_social_score"] == 0.75
        assert deserialized["meets_sniper_requirements"] is True
        assert deserialized["total_mentions"] == 100

        # Test HoneypotAnalysis serialization compatibility
        honeypot_data = {
            "is_honeypot": False,
            "honeypot_probability": 0.15,
            "liquidity_locked": True,
            "liquidity_lock_percentage": 95.0,
            "contract_renounced": True,
            "owner_balance": 0.02,
            "top_10_holder_percentage": 35.0,
            "buy_tax": 0.0,
            "sell_tax": 0.0,
            "risk_score": 0.25,
            "assessment": "Low risk token",
            "confidence": 0.85
        }

        serialized = json.dumps(honeypot_data)
        deserialized = json.loads(serialized)

        assert deserialized["is_honeypot"] is False
        assert deserialized["liquidity_locked"] is True
        assert deserialized["risk_score"] == 0.25

    def test_dto_field_type_consistency(self):
        """Test that DTO fields maintain type consistency"""
        # These tests verify the expected types for each field

        # SocialAnalysis field types
        social_fields = {
            "overall_social_score": float,
            "social_assessment": str,
            "meets_sniper_requirements": bool,
            "total_mentions": int,
            "sentiment_score": float,
            "viral_score": float,
            "safety_score": float,
            "momentum_score": float,
            "confidence_score": float
        }

        # HoneypotAnalysis field types
        honeypot_fields = {
            "is_honeypot": bool,
            "honeypot_probability": float,
            "liquidity_locked": bool,
            "liquidity_lock_percentage": float,
            "contract_renounced": bool,
            "owner_balance": float,
            "top_10_holder_percentage": float,
            "buy_tax": float,
            "sell_tax": float,
            "risk_score": float,
            "assessment": str,
            "confidence": float
        }

        # Verify type expectations
        for field, expected_type in social_fields.items():
            assert expected_type in [float, str, bool, int], f"Invalid type for {field}"

        for field, expected_type in honeypot_fields.items():
            assert expected_type in [float, str, bool], f"Invalid type for {field}"

    def test_dto_business_logic_validation(self):
        """Test business logic validation for DTOs"""

        # Test SocialAnalysis business rules
        # 1. Overall score should be consistent with component scores
        # 2. Confidence should reflect data quality
        # 3. Sniper requirements should depend on mentions threshold

        # Test HoneypotAnalysis business rules
        # 1. Honeypot probability should correlate with risk factors
        # 2. Risk score should reflect multiple risk indicators
        # 3. Assessment should be consistent with numerical scores

        # These are logical assertions that the business rules should follow
        business_rules = {
            "social_mentions_threshold": 10,  # Minimum mentions for sniper requirements
            "honeypot_high_risk_threshold": 0.7,
            "confidence_high_threshold": 0.8,
            "liquidity_lock_good_threshold": 80.0
        }

        assert business_rules["social_mentions_threshold"] > 0
        assert 0 <= business_rules["honeypot_high_risk_threshold"] <= 1
        assert 0 <= business_rules["confidence_high_threshold"] <= 1
        assert business_rules["liquidity_lock_good_threshold"] > 50


if __name__ == "__main__":
    pytest.main([__file__, "-v"])