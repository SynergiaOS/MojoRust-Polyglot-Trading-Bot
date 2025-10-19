#!/usr/bin/env python3
"""
Save Flash Loan Profitability Analysis Tests
ROI calculation and fee analysis testing with comprehensive scenarios
"""

import pytest
import asyncio
import json
import logging
from typing import Dict, List, Tuple
from dataclasses import dataclass
from decimal import Decimal, getcontext

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Set precision for decimal calculations
getcontext().prec = 10

@dataclass
class ProfitabilityScenario:
    """Profitability test scenario"""
    name: str
    loan_amount_sol: float
    roi_percentage: float
    save_fee_bps: int
    jito_tip_sol: float
    success_rate: float
    expected_win_rate: float

@dataclass
class ProfitabilityResult:
    """Profitability calculation result"""
    scenario_name: str
    loan_amount_lamports: int
    gross_profit_lamports: int
    save_fee_lamports: int
    jito_tip_lamports: int
    net_profit_lamports: int
    net_profit_sol: float
    net_profit_usd: float
    roi_net: float
    profitability_score: float
    is_profitable: bool
    risk_level: str

class SaveFlashLoanProfitability:
    """Comprehensive profitability analysis for Save Flash Loans"""

    # Market data for realistic calculations
    SOL_USD_PRICE = 150.0  # Current SOL price (example)
    SAVE_FEE_BPS = 3  # 0.03% Save protocol fee
    DEFAULT_JITO_TIP = 0.15  # SOL

    # Risk and success rate calculations
    BASE_SUCCESS_RATE = 0.85  # 85% base success rate
    RISK_PENALTY = 0.05  # 5% penalty for high-risk scenarios

    def __init__(self):
        self.sol_usd_price = self.SOL_USD_PRICE
        self.save_fee_bps = self.SAVE_FEE_BPS
        self.default_jito_tip = self.DEFAULT_JITO_TIP

    def calculate_save_fee(self, amount_lamports: int) -> int:
        """Calculate Save protocol fee (0.03%)"""
        return amount_lamports * self.save_fee_bps // 10000

    def calculate_jito_tip(self, amount_lamports: int, urgency_level: str = "high") -> int:
        """Calculate Jito tip based on amount and urgency"""
        base_tip = int(self.default_jito_tip * 1_000_000_000)  # Convert to lamports

        if urgency_level == "critical":
            return base_tip * 2  # Double tip for critical trades
        elif urgency_level == "high":
            return base_tip * 1  # Standard tip
        elif urgency_level == "medium":
            return base_tip // 2  # Half tip for medium urgency
        else:
            return base_tip // 4  # Quarter tip for low urgency

    def calculate_gross_profit(self, loan_amount_lamports: int, roi_percentage: float) -> int:
        """Calculate gross profit before fees"""
        return int(loan_amount_lamports * Decimal(str(roi_percentage / 100)))

    def calculate_net_profit(
        self,
        loan_amount_lamports: int,
        gross_profit_lamports: int,
        save_fee_lamports: int,
        jito_tip_lamports: int,
        success_rate: float
    ) -> int:
        """Calculate expected net profit accounting for success rate"""
        total_fees = save_fee_lamports + jito_tip_lamports
        gross_profit_adjusted = int(gross_profit_lamports * success_rate)
        return gross_profit_adjusted - total_fees

    def calculate_profitability_score(
        self,
        net_profit_sol: float,
        roi_net: float,
        risk_level: str,
        loan_amount_sol: float
    ) -> float:
        """Calculate profitability score (0-100)"""
        base_score = min(roi_net * 20, 50)  # ROI component (max 50 points)

        # Size component - larger amounts get bonus
        size_score = min(loan_amount_sol * 2, 25)  # Max 25 points for 5+ SOL

        # Risk adjustment
        risk_adjustment = {
            "low": 15,
            "medium": 5,
            "high": -10,
            "extreme": -20
        }.get(risk_level, 0)

        # Minimum profit threshold
        minimum_profit_bonus = 10 if net_profit_sol > 0.01 else 0

        score = base_score + size_score + risk_adjustment + minimum_profit_bonus
        return max(0, min(100, score))

    def analyze_profitability(
        self,
        scenario: ProfitabilityScenario,
        urgency_level: str = "high"
    ) -> ProfitabilityResult:
        """Comprehensive profitability analysis for a scenario"""

        # Convert to lamports
        loan_amount_lamports = int(scenario.loan_amount_sol * 1_000_000_000)

        # Calculate fees
        save_fee_lamports = self.calculate_save_fee(loan_amount_lamports)
        jito_tip_lamports = self.calculate_jito_tip(loan_amount_lamports, urgency_level)

        # Calculate profits
        gross_profit_lamports = self.calculate_gross_profit(loan_amount_lamports, scenario.roi_percentage)
        net_profit_lamports = self.calculate_net_profit(
            loan_amount_lamports,
            gross_profit_lamports,
            save_fee_lamports,
            jito_tip_lamports,
            scenario.success_rate
        )

        # Convert to SOL and USD
        net_profit_sol = net_profit_lamports / 1_000_000_000
        net_profit_usd = net_profit_sol * self.sol_usd_price
        roi_net = (net_profit_lamports / loan_amount_lamports) * 100 if loan_amount_lamports > 0 else 0

        # Determine risk level
        risk_level = self.determine_risk_level(scenario.loan_amount_sol, scenario.roi_percentage)

        # Calculate profitability score
        profitability_score = self.calculate_profitability_score(
            net_profit_sol,
            roi_net,
            risk_level,
            scenario.loan_amount_sol
        )

        # Determine if profitable
        is_profitable = net_profit_lamports > 0 and profitability_score >= 50

        return ProfitabilityResult(
            scenario_name=scenario.name,
            loan_amount_lamports=loan_amount_lamports,
            gross_profit_lamports=gross_profit_lamports,
            save_fee_lamports=save_fee_lamports,
            jito_tip_lamports=jito_tip_lamports,
            net_profit_lamports=net_profit_lamports,
            net_profit_sol=net_profit_sol,
            net_profit_usd=net_profit_usd,
            roi_net=roi_net,
            profitability_score=profitability_score,
            is_profitable=is_profitable,
            risk_level=risk_level
        )

    def determine_risk_level(self, loan_amount_sol: float, roi_percentage: float) -> str:
        """Determine risk level based on loan amount and ROI"""
        if loan_amount_sol <= 1.0 and roi_percentage <= 3.0:
            return "low"
        elif loan_amount_sol <= 3.0 and roi_percentage <= 5.0:
            return "medium"
        elif loan_amount_sol <= 5.0 and roi_percentage <= 8.0:
            return "high"
        else:
            return "extreme"

class TestSaveFlashLoanProfitability:
    """Comprehensive profitability testing"""

    def setup_method(self):
        """Setup test data"""
        self.profitability = SaveFlashLoanProfitability()

        # Define test scenarios
        self.scenarios = [
            # Low risk, small amount scenarios
            ProfitabilityScenario(
                name="Small Amount - Low ROI",
                loan_amount_sol=0.5,
                roi_percentage=2.0,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=0.90,
                expected_win_rate=0.90
            ),
            ProfitabilityScenario(
                name="Small Amount - High ROI",
                loan_amount_sol=0.5,
                roi_percentage=5.0,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=0.88,
                expected_win_rate=0.88
            ),

            # Medium risk scenarios
            ProfitabilityScenario(
                name="Medium Amount - Medium ROI",
                loan_amount_sol=2.0,
                roi_percentage=3.0,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=0.85,
                expected_win_rate=0.85
            ),
            ProfitabilityScenario(
                name="Medium Amount - High ROI",
                loan_amount_sol=2.0,
                roi_percentage=6.0,
                success_rate=0.80,
                expected_win_rate=0.80
            ),

            # High risk scenarios
            ProfitabilityScenario(
                name="Large Amount - Medium ROI",
                loan_amount_sol=5.0,
                roi_percentage=3.0,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=0.75,
                expected_win_rate=0.75
            ),
            ProfitabilityScenario(
                name="Large Amount - High ROI",
                loan_amount_sol=5.0,
                roi_percentage=7.0,
                success_rate=0.70,
                expected_win_rate=0.70
            ),

            # Edge cases
            ProfitabilityScenario(
                name="Micro Amount",
                loan_amount_sol=0.1,
                roi_percentage=10.0,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=0.95,
                expected_win_rate=0.95
            ),
            ProfitabilityScenario(
                name="Maximum Amount",
                loan_amount_sol=5.0,
                roi_percentage=1.0,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=0.82,
                expected_win_rate=0.82
            ),
        ]

    def test_save_fee_calculation(self):
        """Test Save fee calculation with various amounts"""
        test_cases = [
            (0.1, 0.00003),    # 0.1 SOL → 0.00003 SOL
            (1.0, 0.0003),     # 1 SOL → 0.0003 SOL
            (2.5, 0.00075),    # 2.5 SOL → 0.00075 SOL
            (5.0, 0.0015),     # 5 SOL → 0.0015 SOL
        ]

        for amount_sol, expected_fee in test_cases:
            amount_lamports = int(amount_sol * 1_000_000_000)
            fee_lamports = self.profitability.calculate_save_fee(amount_lamports)
            actual_fee = fee_lamports / 1_000_000_000

            assert abs(actual_fee - expected_fee) < 0.000001, \
                f"Save fee calculation failed for {amount_sol} SOL: expected {expected_fee}, got {actual_fee}"

    def test_jito_tip_calculation(self):
        """Test Jito tip calculation with different urgency levels"""
        amount_sol = 2.0
        amount_lamports = int(amount_sol * 1_000_000_000)

        test_cases = [
            ("low", 0.0375),      # Quarter of default tip
            ("medium", 0.075),    # Half of default tip
            ("high", 0.15),       # Default tip
            ("critical", 0.30),    # Double tip
        ]

        for urgency_level, expected_tip in test_cases:
            tip_lamports = self.profitability.calculate_jito_tip(amount_lamports, urgency_level)
            actual_tip = tip_lamports / 1_000_000_000

            assert abs(actual_tip - expected_tip) < 0.000001, \
                f"Jito tip calculation failed for {urgency_level}: expected {expected_tip}, got {actual_tip}"

    def test_gross_profit_calculation(self):
        """Test gross profit calculation"""
        test_cases = [
            (1.0, 0.02, 0.02),    # 1 SOL, 2% → 0.02 SOL
            (2.0, 0.05, 0.10),    # 2 SOL, 5% → 0.10 SOL
            (5.0, 0.03, 0.15),    # 5 SOL, 3% → 0.15 SOL
        ]

        for amount_sol, roi_percentage, expected_profit in test_cases:
            amount_lamports = int(amount_sol * 1_000_000_000)
            profit_lamports = self.profitability.calculate_gross_profit(amount_lamports, roi_percentage)
            actual_profit = profit_lamports / 1_000_000_000

            assert abs(actual_profit - expected_profit) < 0.000001, \
                f"Gross profit calculation failed: expected {expected_profit}, got {actual_profit}"

    def test_net_profit_calculation(self):
        """Test net profit calculation with success rate consideration"""
        amount_lamports = 2_000_000_000  # 2 SOL
        gross_profit_lamports = 100_000_000  # 0.1 SOL
        save_fee_lamports = 60_000        # 0.00006 SOL
        jito_tip_lamports = 150_000_000  # 0.15 SOL

        test_cases = [
            (1.0, 0.1 - 0.00006 - 0.15),   # 100% success rate
            (0.85, 0.1 * 0.85 - 0.00006 - 0.15),  # 85% success rate
            (0.70, 0.1 * 0.70 - 0.00006 - 0.15),  # 70% success rate
            (0.50, 0.1 * 0.50 - 0.00006 - 0.15),  # 50% success rate
        ]

        for success_rate, expected_net in test_cases:
            net_profit_lamports = self.profitability.calculate_net_profit(
                amount_lamports,
                gross_profit_lamports,
                save_fee_lamports,
                jito_tip_lamports,
                success_rate
            )
            actual_net = net_profit_lamports / 1_000_000_000

            assert abs(actual_net - expected_net) < 0.000001, \
                f"Net profit calculation failed for success rate {success_rate}: expected {expected_net}, got {actual_net}"

    def test_profitability_scenarios(self):
        """Test comprehensive profitability analysis"""
        self.setup_method()

        for scenario in self.scenarios:
            result = self.profitability.analyze_profitability(scenario)

            # Basic assertions
            assert result.scenario_name == scenario.name
            assert result.save_fee_lamports > 0
            assert result.jito_tip_lamports > 0
            assert 0 <= result.profitability_score <= 100

            # Validate fee calculations
            expected_save_fee = result.loan_amount_lamports * 3 // 10000
            assert result.save_fee_lamports == expected_save_fee, \
                f"Save fee mismatch in {scenario.name}: expected {expected_save_fee}, got {result.save_fee_lamports}"

            # Validate ROI calculation
            if result.loan_amount_lamports > 0:
                expected_roi = (result.net_profit_lamports / result.loan_amount_lamports) * 100
                assert abs(result.roi_net - expected_roi) < 0.01, \
                    f"ROI calculation mismatch in {scenario.name}: expected {expected_roi:.2f}%, got {result.roi_net:.2f}%"

            # Log detailed results
            logger.info(f"✅ Scenario: {scenario.name}")
            logger.info(f"   Amount: {scenario.loan_amount_sol} SOL")
            logger.info(f"   Gross Profit: {result.gross_profit_lamports/1_000_000_000:.4f} SOL")
            logger.info(f"   Net Profit: {result.net_profit_sol:.4f} SOL (${result.net_profit_usd:.2f})")
            logger.info(f"   ROI: {result.roi_net:.2f}%")
            logger.info(f"   Score: {result.profitability_score:.1f}/100")
            logger.info(f"   Risk: {result.risk_level}")
            logger.info(f"   Profitable: {result.is_profitable}")

    def test_profitability_thresholds(self):
        """Test profitability thresholds and minimum requirements"""
        self.setup_method()

        # Test minimum profitable scenarios
        profitable_scenarios = [
            (0.5, 3.0, 0.88),  # Small amount, high ROI
            (2.0, 4.0, 0.85),  # Medium amount, medium ROI
            (5.0, 3.5, 0.80),  # Large amount, lower ROI
        ]

        for amount, roi, success_rate in profitable_scenarios:
            scenario = ProfitabilityScenario(
                name=f"Test {amount} SOL {roi}% ROI",
                loan_amount_sol=amount,
                roi_percentage=roi,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=success_rate,
                expected_win_rate=success_rate
            )

            result = self.profitability.analyze_profitability(scenario)
            assert result.is_profitable, f"Expected profitable scenario {amount} SOL {roi}% ROI"
            assert result.net_profit_sol > 0, f"Expected positive net profit for {amount} SOL {roi}% ROI"

    def test_unprofitable_scenarios(self):
        """Test scenarios that should be unprofitable"""
        unprofitable_scenarios = [
            (0.1, 0.5, 0.95),  # Micro amount, very low ROI
            (1.0, 0.5, 0.80),  # Low ROI with reduced success rate
            (5.0, 0.5, 0.60),  # Large amount, very low ROI and success rate
        ]

        for amount, roi, success_rate in unprofitable_scenarios:
            scenario = ProfitabilityScenario(
                name=f"Unprofitable {amount} SOL {roi}% ROI",
                loan_amount_sol=amount,
                roi_percentage=roi,
                save_fee_bps=3,
                jito_tip_sol=0.15,
                success_rate=success_rate,
                expected_win_rate=success_rate
            )

            result = self.profitability.analyze_profitability(scenario)
            assert not result.is_profitable or result.net_profit_sol <= 0, \
                f"Expected unprofitable scenario {amount} SOL {roi}% ROI"
            assert result.profitability_score < 50, \
                f"Expected low profitability score for {amount} SOL {roi}% ROI"

    def test_edge_cases(self):
        """Test edge cases and boundary conditions"""
        # Zero amount (should be rejected)
        zero_scenario = ProfitabilityScenario(
            name="Zero Amount",
            loan_amount_sol=0.0,
            roi_percentage=5.0,
            save_fee_bps=3,
            jito_tip_sol=0.15,
            success_rate=1.0,
            expected_win_rate=1.0
        )

        result = self.profitability.analyze_profitability(zero_scenario)
        assert result.loan_amount_lamports == 0
        assert not result.is_profitable

        # Extremely high ROI (should be flagged as high risk)
        high_roi_scenario = ProfitabilityScenario(
            name="Extremely High ROI",
            loan_amount_sol=1.0,
            roi_percentage=50.0,
            save_fee_bps=3,
            jito_tip_sol=0.15,
            success_rate=0.50,  # Lower success rate for high ROI
            expected_win_rate=0.50
        )

        result = self.profitability.analyze_profitability(high_roi_scenario)
        assert result.risk_level in ["high", "extreme"]

        # Maximum amount with minimum ROI
        max_amount_scenario = ProfitabilityScenario(
            name="Max Amount Min ROI",
            loan_amount_sol=5.0,
            roi_percentage=1.0,
            save_fee_bps=3,
            jito_tip_sol=0.15,
            success_rate=0.82,
            expected_win_rate=0.82
        )

        result = self.profitability.analyze_profitability(max_amount_scenario)
        assert result.risk_level == "medium" or result.risk_level == "high"

    def test_urgency_level_impact(self):
        """Test how urgency levels affect profitability"""
        self.setup_method()

        base_scenario = ProfitabilityScenario(
            name="Base Scenario",
            loan_amount_sol=2.0,
            roi_percentage=4.0,
            save_fee_bps=3,
            jito_tip_sol=0.15,
            success_rate=0.85,
            expected_win_rate=0.85
        )

        urgency_levels = ["low", "medium", "high", "critical"]
        results = {}

        for urgency in urgency_levels:
            result = self.profitability.analyze_profitability(base_scenario, urgency)
            results[urgency] = result

        # Critical urgency should have highest Jito tip but potentially lowest net profit
        assert results["critical"].jito_tip_lamports > results["high"].jito_tip_lamports
        assert results["critical"].jito_tip_lamports > results["medium"].jito_tip_lamports
        assert results["critical"].jito_tip_lamports > results["low"].jito_tip_lamports

        # Net profit should decrease with higher urgency due to higher tips
        assert results["low"].net_profit_sol > results["medium"].net_profit_sol
        assert results["medium"].net_profit_sol > results["high"].net_profit_sol
        assert results["high"].net_profit_sol >= results["critical"].net_profit_sol

    def test_profitability_summary(self):
        """Generate profitability summary for analysis"""
        self.setup_method()

        logger.info("📊 SAVE FLASH LOAN PROFITABILITY SUMMARY")
        logger.info("=" * 60)

        total_scenarios = len(self.scenarios)
        profitable_scenarios = 0
        total_expected_profit = 0.0

        for scenario in self.scenarios:
            result = self.profitability.analyze_profitability(scenario)

            if result.is_profitable:
                profitable_scenarios += 1
                total_expected_profit += result.net_profit_usd

        logger.info(f"Total Scenarios: {total_scenarios}")
        logger.info(f"Profitable Scenarios: {profitable_scenarios} ({profitable_scenarios/total_scenarios*100:.1f}%)")
        logger.info(f"Expected Total Profit: ${total_expected_profit:.2f}")
        logger.info(f"Average Profit per Scenario: ${total_expected_profit/max(profitable_scenarios, 1):.2f}")

        # Best and worst scenarios
        all_results = []
        for scenario in self.scenarios:
            all_results.append(self.profitability.analyze_profitability(scenario))

        best_scenario = max(all_results, key=lambda x: x.net_profit_usd)
        worst_scenario = min(all_results, key=lambda x: x.net_profit_usd)

        logger.info(f"Best Scenario: {best_scenario.scenario_name} (${best_scenario.net_profit_usd:.2f})")
        logger.info(f"Worst Scenario: {worst_scenario.scenario_name} (${worst_scenario.net_profit_usd:.2f})")

        logger.info("=" * 60)

        # Verify profitability thresholds
        assert profitable_scenarios >= total_scenarios * 0.4, \
            f"Too few profitable scenarios: {profitable_scenarios}/{total_scenarios}"
        assert total_expected_profit > 0, "Expected total profit should be positive"

if __name__ == "__main__":
    # Run profitability tests
    pytest.main([__file__, "-v", "--tb=short"])