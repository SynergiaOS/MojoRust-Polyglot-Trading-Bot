# =============================================================================
# HARDCODED TRADING SIMULATION - DEVNET MODE
# =============================================================================
# Deterministic trading scenarios for development and testing
# No randomness - fully predictable outcomes

from collections import Dict, List, Any
from core.types import TradingSignal, Portfolio, Position, TradingAction, MarketData
from core.config import Config
from core.logger import get_logger
from time import time
from random import seed

@value
struct HardcodedScenario:
    """
    Predefined trading scenario with deterministic outcomes
    """
    var name: String
    var description: String
    var signals: List[TradingSignal]
    var market_movements: Dict[String, List[Float]]
    var expected_pnl: Float
    var expected_win_rate: Float
    var duration_minutes: Int

struct HardcodedTrader:
    """
    Hardcoded trading simulation with deterministic outcomes
    """
    var config: Config
    var logger: Any
    var current_scenario: Int
    var scenarios: List[HardcodedScenario]
    var simulation_start_time: Float
    var deterministic_seed: Int

    fn __init__(config: Config):
        self.config = config
        self.logger = get_logger("HardcodedTrader")
        self.current_scenario = 0
        self.deterministic_seed = 42  # Fixed seed for reproducibility
        self.simulation_start_time = time()

        # Initialize with predefined scenarios
        self.scenarios = self._create_scenarios()

        # Set deterministic seed
        seed(self.deterministic_seed)

    fn _create_scenarios(self) -> List[HardcodedScenario]:
        """
        Create predefined trading scenarios
        """
        scenarios = []

        # Scenario 1: Perfect win (BONK)
        bonk_signals = [
            TradingSignal(
                symbol="BONK",
                action=TradingAction.BUY,
                confidence=0.87,
                timeframe="1m",
                timestamp=self.simulation_start_time + 60,
                price_target=0.00001450,
                stop_loss=0.00001050,
                volume=2500000.0,
                liquidity=150000.0,
                metadata={"scenario": "perfect_win", "entry_price": 0.00001234}
            )
        ]

        bonk_movements = {
            "BONK": [0.00001234, 0.00001245, 0.00001258, 0.00001320, 0.00001385, 0.00001441]
        }

        scenarios.append(HardcodedScenario(
            name="Perfect Win - BONK",
            description="Guaranteed profitable trade with BONK",
            signals=bonk_signals,
            market_movements=bonk_movements,
            expected_pnl=0.00102,
            expected_win_rate=1.0,
            duration_minutes=12
        ))

        # Scenario 2: Small loss (WIF)
        wif_signals = [
            TradingSignal(
                symbol="WIF",
                action=TradingAction.BUY,
                confidence=0.72,
                timeframe="1m",
                timestamp=self.simulation_start_time + 300,
                price_target=0.00008950,
                stop_loss=0.00007500,
                volume=1800000.0,
                liquidity=120000.0,
                metadata={"scenario": "small_loss", "entry_price": 0.00008200}
            )
        ]

        wif_movements = {
            "WIF": [0.00008200, 0.00008150, 0.00008080, 0.00007920, 0.00007650]
        }

        scenarios.append(HardcodedScenario(
            name="Small Loss - WIF",
            description="Controlled loss with stop loss hit",
            signals=wif_signals,
            market_movements=wif_movements,
            expected_pnl=-0.00055,
            expected_win_rate=0.0,
            duration_minutes=8
        ))

        # Scenario 3: Break-even (PEPE)
        pepe_signals = [
            TradingSignal(
                symbol="PEPE",
                action=TradingAction.BUY,
                confidence=0.68,
                timeframe="1m",
                timestamp=self.simulation_start_time + 600,
                price_target=0.00000980,
                stop_loss=0.00000820,
                volume=3200000.0,
                liquidity=200000.0,
                metadata={"scenario": "break_even", "entry_price": 0.00000900}
            )
        ]

        pepe_movements = {
            "PEPE": [0.00000900, 0.00000915, 0.00000930, 0.00000910, 0.00000905, 0.00000902]
        }

        scenarios.append(HardcodedScenario(
            name="Break Even - PEPE",
            description="Trade that ends near break-even",
            signals=pepe_signals,
            market_movements=pepe_movements,
            expected_pnl=0.00001,
            expected_win_rate=0.5,
            duration_minutes=15
        ))

        # Scenario 4: Multiple trades mixed
        mixed_signals = []
        mixed_movements = {}

        # Add multiple signals for complex scenario
        doge_signal = TradingSignal(
            symbol="DOGE",
            action=TradingAction.BUY,
            confidence=0.75,
            timeframe="1m",
            timestamp=self.simulation_start_time + 900,
            price_target=0.0000850,
            stop_loss=0.0000750,
            volume=1500000.0,
            liquidity=180000.0,
            metadata={"scenario": "mixed", "entry_price": 0.0000800, "outcome": "win"}
        )
        mixed_signals.append(doge_signal)

        shib_signal = TradingSignal(
            symbol="SHIB",
            action=TradingAction.BUY,
            confidence=0.69,
            timeframe="1m",
            timestamp=self.simulation_start_time + 1200,
            price_target=0.0000150,
            stop_loss=0.0000130,
            volume=2100000.0,
            liquidity=160000.0,
            metadata={"scenario": "mixed", "entry_price": 0.0000140, "outcome": "loss"}
        )
        mixed_signals.append(shib_signal)

        mixed_movements = {
            "DOGE": [0.0000800, 0.0000815, 0.0000830, 0.0000845],
            "SHIB": [0.0000140, 0.0000138, 0.0000135, 0.0000132]
        }

        scenarios.append(HardcodedScenario(
            name="Mixed Results - DOGE/SHIB",
            description="Multiple trades with mixed outcomes",
            signals=mixed_signals,
            market_movements=mixed_movements,
            expected_pnl=0.00015,
            expected_win_rate=0.5,
            duration_minutes=20
        ))

        return scenarios

    fn run_scenario(self, scenario_index: Int) -> Dict[String, Any]:
        """
        Run a specific hardcoded scenario
        """
        if scenario_index >= len(self.scenarios):
            self.logger.error(f"Scenario {scenario_index} not found")
            return {"success": False, "error": "Scenario not found"}

        scenario = self.scenarios[scenario_index]
        self.logger.info(f"Running hardcoded scenario: {scenario.name}")

        results = {
            "scenario_name": scenario.name,
            "scenario_description": scenario.description,
            "start_time": time(),
            "signals_processed": 0,
            "trades_executed": 0,
            "total_pnl": 0.0,
            "win_rate": 0.0,
            "execution_times": [],
            "filter_rejections": 0,
            "portfolio_changes": []
        }

        # Simulate each signal in the scenario
        for signal in scenario.signals:
            # Simulate signal processing time
            processing_time = 0.023  # Fixed 23ms for consistency
            results["execution_times"].append(processing_time)

            # Simulate filtering (always pass in hardcoded mode)
            if self._simulate_filter_decision(signal):
                results["signals_processed"] += 1

                # Simulate trade execution
                trade_result = self._execute_hardcoded_trade(signal, scenario.market_movements)

                if trade_result["executed"]:
                    results["trades_executed"] += 1
                    results["total_pnl"] += trade_result["pnl"]
                    results["portfolio_changes"].append(trade_result)
            else:
                results["filter_rejections"] += 1

        # Calculate final metrics
        if results["trades_executed"] > 0:
            winning_trades = sum(1 for change in results["portfolio_changes"] if change["pnl"] > 0)
            results["win_rate"] = Float(winning_trades) / Float(results["trades_executed"])

        results["end_time"] = time()
        results["duration_seconds"] = results["end_time"] - results["start_time"]
        results["expected_vs_actual_pnl"] = results["total_pnl"] - scenario.expected_pnl
        results["expected_vs_actual_win_rate"] = results["win_rate"] - scenario.expected_win_rate

        self.logger.info(f"Scenario completed: {scenario.name}",
                        pnl=results["total_pnl"],
                        win_rate=results["win_rate"],
                        trades=results["trades_executed"])

        return results

    fn _simulate_filter_decision(self, signal: TradingSignal) -> Bool:
        """
        Simulate filter decision (always pass hardcoded signals)
        """
        # In hardcoded mode, all signals pass filters
        return True

    fn _execute_hardcoded_trade(self, signal: TradingSignal, market_movements: Dict[String, List[Float]]) -> Dict[String, Any]:
        """
        Execute trade with deterministic outcome based on market movements
        """
        symbol = signal.symbol

        if symbol not in market_movements:
            self.logger.error(f"No market movements defined for {symbol}")
            return {"executed": False, "error": f"No market data for {symbol}"}

        price_series = market_movements[symbol]
        entry_price = price_series[0]

        # Calculate position size (fixed 5% of portfolio)
        position_value = 0.05  # 5% of 1 SOL portfolio
        token_amount = position_value / entry_price

        # Simulate market progression and determine exit
        exit_price = price_series[-1]
        pnl = (exit_price - entry_price) * token_amount
        pnl_percentage = (exit_price - entry_price) / entry_price

        # Determine exit reason
        exit_reason = "take_profit" if pnl > 0 else "stop_loss"
        if abs(pnl_percentage) < 0.02:  # Less than 2% movement
            exit_reason = "time_based"

        execution_time = 0.087  # Fixed 87ms execution time

        return {
            "executed": True,
            "symbol": symbol,
            "action": "BUY",
            "entry_price": entry_price,
            "exit_price": exit_price,
            "token_amount": token_amount,
            "pnl": pnl,
            "pnl_percentage": pnl_percentage,
            "execution_time_ms": execution_time,
            "exit_reason": exit_reason,
            "hold_duration_seconds": len(price_series) * 60,  # 1 minute per price point
            "transaction_id": f"hardcoded_tx_{int(time())}_{symbol}"
        }

    fn run_all_scenarios(self) -> Dict[String, Any]:
        """
        Run all hardcoded scenarios sequentially
        """
        self.logger.info("Starting all hardcoded scenarios")

        all_results = {
            "start_time": time(),
            "scenarios_completed": 0,
            "total_scenarios": len(self.scenarios),
            "scenario_results": [],
            "aggregate_metrics": {
                "total_pnl": 0.0,
                "total_trades": 0,
                "total_wins": 0,
                "average_execution_time": 0.0,
                "filter_efficiency": 0.0
            }
        }

        for i in range(len(self.scenarios)):
            scenario_result = self.run_scenario(i)
            all_results["scenario_results"].append(scenario_result)
            all_results["scenarios_completed"] += 1

            # Update aggregate metrics
            all_results["aggregate_metrics"]["total_pnl"] += scenario_result["total_pnl"]
            all_results["aggregate_metrics"]["total_trades"] += scenario_result["trades_executed"]

            if scenario_result["trades_executed"] > 0:
                winning_trades = sum(1 for change in scenario_result["portfolio_changes"] if change["pnl"] > 0)
                all_results["aggregate_metrics"]["total_wins"] += winning_trades

        # Calculate final aggregate metrics
        total_trades = all_results["aggregate_metrics"]["total_trades"]
        if total_trades > 0:
            all_results["aggregate_metrics"]["win_rate"] = (
                Float(all_results["aggregate_metrics"]["total_wins"]) / Float(total_trades)
            )

        # Calculate average execution time
        all_execution_times = []
        for result in all_results["scenario_results"]:
            all_execution_times.extend(result["execution_times"])

        if len(all_execution_times) > 0:
            all_results["aggregate_metrics"]["average_execution_time"] = (
                sum(all_execution_times) / len(all_execution_times)
            )

        # Calculate filter efficiency
        total_signals = sum(result["signals_processed"] + result["filter_rejections"]
                          for result in all_results["scenario_results"])
        if total_signals > 0:
            total_rejections = sum(result["filter_rejections"] for result in all_results["scenario_results"])
            all_results["aggregate_metrics"]["filter_efficiency"] = Float(total_rejections) / Float(total_signals)

        all_results["end_time"] = time()
        all_results["total_duration"] = all_results["end_time"] - all_results["start_time"]

        self.logger.info("All hardcoded scenarios completed",
                        total_scenarios=all_results["scenarios_completed"],
                        total_pnl=all_results["aggregate_metrics"]["total_pnl"],
                        win_rate=all_results["aggregate_metrics"]["win_rate"],
                        duration_seconds=all_results["total_duration"])

        return all_results

    fn get_scenario_summary(self, scenario_index: Int) -> Dict[String, Any]:
        """
        Get summary of a specific scenario without running it
        """
        if scenario_index >= len(self.scenarios):
            return {"error": "Scenario not found"}

        scenario = self.scenarios[scenario_index]
        return {
            "name": scenario.name,
            "description": scenario.description,
            "signal_count": len(scenario.signals),
            "expected_pnl": scenario.expected_pnl,
            "expected_win_rate": scenario.expected_win_rate,
            "duration_minutes": scenario.duration_minutes,
            "symbols": list(set(signal.symbol for signal in scenario.signals))
        }

    fn create_custom_scenario(self, name: String, signals: List[TradingSignal],
                           movements: Dict[String, List[Float]], expected_pnl: Float) -> HardcodedScenario:
        """
        Create a custom scenario for testing
        """
        return HardcodedScenario(
            name=name,
            description=f"Custom scenario: {name}",
            signals=signals,
            market_movements=movements,
            expected_pnl=expected_pnl,
            expected_win_rate=1.0,  # Assume win unless specified otherwise
            duration_minutes=10
        )

    fn run_devnet_simulation(self) -> Dict[String, Any]:
        """
        Run simulation optimized for DevNet testing
        """
        self.logger.info("Starting DevNet simulation mode")

        # Create DevNet-optimized scenarios
        devnet_scenarios = self._create_devnet_scenarios()

        results = {
            "mode": "devnet",
            "start_time": time(),
            "scenarios": [],
            "summary": {
                "total_pnl": 0.0,
                "total_trades": 0,
                "success_rate": 0.0,
                "average_execution_time": 0.0
            }
        }

        for i, scenario in enumerate(devnet_scenarios):
            self.logger.info(f"Running DevNet scenario {i+1}: {scenario.name}")

            # Quick execution for DevNet
            scenario_result = {
                "scenario_name": scenario.name,
                "trades_executed": len(scenario.signals),
                "total_pnl": scenario.expected_pnl,
                "execution_time": 0.050,  # 50ms for DevNet
                "success": True
            }

            results["scenarios"].append(scenario_result)
            results["summary"]["total_pnl"] += scenario.expected_pnl
            results["summary"]["total_trades"] += len(scenario.signals)

        # Calculate success rate
        if results["summary"]["total_trades"] > 0:
            successful_trades = sum(1 for s in results["scenarios"] if s["total_pnl"] > 0)
            results["summary"]["success_rate"] = Float(successful_trades) / len(results["scenarios"])

        results["end_time"] = time()
        results["duration"] = results["end_time"] - results["start_time"]

        return results

    fn _create_devnet_scenarios(self) -> List[HardcodedScenario]:
        """
        Create scenarios optimized for DevNet testing
        """
        scenarios = []

        # Quick win scenario
        quick_win = TradingSignal(
            symbol="TEST",
            action=TradingAction.BUY,
            confidence=0.95,
            timeframe="1m",
            timestamp=time(),
            price_target=1.10,
            stop_loss=0.90,
            volume=1000000.0,
            liquidity=500000.0,
            metadata={"devnet": True, "outcome": "win"}
        )

        scenarios.append(HardcodedScenario(
            name="DevNet Quick Win",
            description="Fast profitable trade for DevNet testing",
            signals=[quick_win],
            market_movements={"TEST": [1.0, 1.05, 1.10]},
            expected_pnl=0.05,
            expected_win_rate=1.0,
            duration_minutes=2
        ))

        # Quick loss scenario
        quick_loss = TradingSignal(
            symbol="FAIL",
            action=TradingAction.BUY,
            confidence=0.85,
            timeframe="1m",
            timestamp=time(),
            price_target=1.15,
            stop_loss=0.85,
            volume=800000.0,
            liquidity=400000.0,
            metadata={"devnet": True, "outcome": "loss"}
        )

        scenarios.append(HardcodedScenario(
            name="DevNet Stop Loss",
            description="Stop loss trigger for DevNet testing",
            signals=[quick_loss],
            market_movements={"FAIL": [1.0, 0.95, 0.85]},
            expected_pnl=-0.15,
            expected_win_rate=0.0,
            duration_minutes=3
        ))

        return scenarios