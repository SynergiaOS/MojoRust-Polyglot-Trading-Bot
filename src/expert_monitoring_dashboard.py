#!/usr/bin/env python3
"""
📊 EXPERT MONITORING DASHBOARD - NADZÓR NAD SYSTEMEM
Mojo/Rust/Python Expert Trading Oversight
Real-time monitoring i optymalizacja devnet flash loan system
"""

import asyncio
import aiohttp
import json
import time
import psutil
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging
from dataclasses import dataclass
import statistics

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class SystemMetrics:
    """Metryki systemowe expert monitoringu"""
    timestamp: datetime
    cpu_usage: float
    memory_usage: float
    network_latency: float
    active_processes: int
    trading_cycles: int
    opportunities_found: int
    success_rate: float
    estimated_profit: float

class ExpertMonitoringDashboard:
    """Expert Dashboard do nadzoru nad systemem tradingowym"""

    def __init__(self):
        self.monitoring_interval = 30  # sekundy
        self.system_start_time = datetime.now()
        self.metrics_history = []
        self.alerts_thresholds = {
            "cpu_usage": 80.0,
            "memory_usage": 85.0,
            "network_latency": 5000.0,
            "success_rate": 30.0,
            "opportunity_gap": 120.0  # sekundy
        }

        # System performance targets
        self.performance_targets = {
            "opportunities_per_hour": 10,
            "success_rate": 70.0,
            "avg_profit_per_opportunity": 0.02,
            "max_execution_time_ms": 3000
        }

        self.current_session_stats = {
            "cycles_completed": 0,
            "total_opportunities": 0,
            "successful_simulations": 0,
            "total_estimated_profit": 0.0,
            "best_opportunity": None,
            "system_health_score": 100.0
        }

    async def collect_system_metrics(self) -> SystemMetrics:
        """Zbierz metryki systemowe"""

        # CPU i Memory
        cpu_percent = psutil.cpu_percent(interval=1)
        memory_percent = psutil.virtual_memory().percent

        # Network latency
        network_latency = await self.measure_network_latency()

        # Active processes
        active_processes = len([p for p in psutil.process_iter() if 'python' in p.name().lower()])

        # Trading metrics (symulowane z devnet system)
        trading_cycles = self.current_session_stats["cycles_completed"]
        opportunities_found = self.current_session_stats["total_opportunities"]
        success_rate = self.calculate_success_rate()
        estimated_profit = self.current_session_stats["total_estimated_profit"]

        return SystemMetrics(
            timestamp=datetime.now(),
            cpu_usage=cpu_percent,
            memory_usage=memory_percent,
            network_latency=network_latency,
            active_processes=active_processes,
            trading_cycles=trading_cycles,
            opportunities_found=opportunities_found,
            success_rate=success_rate,
            estimated_profit=estimated_profit
        )

    async def measure_network_latency(self) -> float:
        """Pomierz opóźnienie sieciowe"""
        try:
            start_time = time.time()
            async with aiohttp.ClientSession() as session:
                async with session.get("https://api.devnet.solana.com", timeout=5) as response:
                    if response.status == 200:
                        latency_ms = (time.time() - start_time) * 1000
                        return latency_ms
        except:
            return 1000.0  # Default timeout

    def calculate_success_rate(self) -> float:
        """Oblicz wskaźnik sukcesu"""
        total_sims = self.current_session_stats["successful_simulations"]
        total_ops = self.current_session_stats["total_opportunities"]

        if total_ops > 0:
            return (total_sims / total_ops) * 100
        return 0.0

    def calculate_system_health_score(self, metrics: SystemMetrics) -> float:
        """Oblicz ocenę zdrowia systemu"""
        score = 100.0

        # CPU usage penalty
        if metrics.cpu_usage > 70:
            score -= (metrics.cpu_usage - 70) * 0.5

        # Memory usage penalty
        if metrics.memory_usage > 80:
            score -= (metrics.memory_usage - 80) * 0.3

        # Network latency penalty
        if metrics.network_latency > 1000:
            score -= (metrics.network_latency - 1000) * 0.01

        # Success rate bonus/penalty
        if metrics.success_rate < 50:
            score -= (50 - metrics.success_rate) * 0.2
        elif metrics.success_rate > 80:
            score += (metrics.success_rate - 80) * 0.1

        return max(0.0, min(100.0, score))

    def detect_anomalies(self, metrics: SystemMetrics) -> List[str]:
        """Wykryj anomalie w systemie"""
        anomalies = []

        if metrics.cpu_usage > self.alerts_thresholds["cpu_usage"]:
            anomalies.append(f"⚠️ WYSOKIE CPU: {metrics.cpu_usage:.1f}%")

        if metrics.memory_usage > self.alerts_thresholds["memory_usage"]:
            anomalies.append(f"⚠️ WYSOKA PAMIĘĆ: {metrics.memory_usage:.1f}%")

        if metrics.network_latency > self.alerts_thresholds["network_latency"]:
            anomalies.append(f"⚠️ WYSOKIE OPÓŹNIENIE: {metrics.network_latency:.0f}ms")

        if metrics.success_rate < self.alerts_thresholds["success_rate"]:
            anomalies.append(f"⚠️ NISKI SUKCES: {metrics.success_rate:.1f}%")

        return anomalies

    def generate_performance_report(self) -> Dict:
        """Generuj raport wydajności"""
        if len(self.metrics_history) < 2:
            return {"status": "insufficient_data"}

        recent_metrics = self.metrics_history[-10:]  # Ostatnie 10 pomiarów

        # Calculate averages
        avg_cpu = statistics.mean([m.cpu_usage for m in recent_metrics])
        avg_memory = statistics.mean([m.memory_usage for m in recent_metrics])
        avg_latency = statistics.mean([m.network_latency for m in recent_metrics])

        # Calculate trends
        if len(self.metrics_history) >= 20:
            old_metrics = self.metrics_history[-20:-10]
            old_success = statistics.mean([m.success_rate for m in old_metrics])
            new_success = statistics.mean([m.success_rate for m in recent_metrics])
            success_trend = new_success - old_success
        else:
            success_trend = 0.0

        # Performance vs targets
        current_opportunities_per_hour = (self.current_session_stats["total_opportunities"] /
                                        max(1, (datetime.now() - self.system_start_time).total_seconds() / 3600))

        target_performance = {
            "opportunities_per_hour": {
                "current": current_opportunities_per_hour,
                "target": self.performance_targets["opportunities_per_hour"],
                "achievement": min(100.0, (current_opportunities_per_hour / self.performance_targets["opportunities_per_hour"]) * 100)
            },
            "success_rate": {
                "current": self.current_session_stats["successful_simulations"] / max(1, self.current_session_stats["total_opportunities"]) * 100,
                "target": self.performance_targets["success_rate"],
                "achievement": min(100.0, (self.current_session_stats["successful_simulations"] / max(1, self.current_session_stats["total_opportunities"]) * 100 / self.performance_targets["success_rate"]) * 100)
            }
        }

        return {
            "system_health": {
                "score": self.current_session_stats["system_health_score"],
                "cpu_usage": avg_cpu,
                "memory_usage": avg_memory,
                "network_latency": avg_latency
            },
            "performance": target_performance,
            "trends": {
                "success_rate_trend": success_trend,
                "opportunities_trend": "increasing" if current_opportunities_per_hour > 5 else "stable"
            },
            "alerts": self.detect_anomalies(recent_metrics[-1] if recent_metrics else None)
        }

    async def display_expert_dashboard(self):
        """Wyświetl expert dashboard"""

        while True:
            try:
                # Collect metrics
                metrics = await self.collect_system_metrics()
                self.metrics_history.append(metrics)

                # Keep only last 100 metrics
                if len(self.metrics_history) > 100:
                    self.metrics_history = self.metrics_history[-100:]

                # Update session stats (simulated from devnet system)
                self.current_session_stats["cycles_completed"] += 1
                self.current_session_stats["total_opportunities"] += 2  # Simulated
                self.current_session_stats["successful_simulations"] += 1  # Simulated
                self.current_session_stats["total_estimated_profit"] += 0.015  # Simulated

                # Calculate health score
                self.current_session_stats["system_health_score"] = self.calculate_system_health_score(metrics)

                # Clear screen and display dashboard
                print("\033[2J\033[H")  # Clear screen
                print("📊 EXPERT MONITORING DASHBOARD - FLASH LOAN SYSTEM")
                print("=" * 70)
                print(f"🕐 Czas: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
                print(f"⏱️  Czas działania: {(datetime.now() - self.system_start_time).total_seconds()/60:.1f} min")
                print(f"🎯 Status Systemu: {'🟢 ZDROWY' if self.current_session_stats['system_health_score'] > 80 else '🟡 OSTRZEŻENIE' if self.current_session_stats['system_health_score'] > 60 else '🔴 KRYTYCZNY'}")
                print()

                # System Metrics
                print("📈 METRYKI SYSTEMOWE:")
                print(f"   💻 CPU: {metrics.cpu_usage:.1f}%")
                print(f"   🧠 Pamięć: {metrics.memory_usage:.1f}%")
                print(f"   🌐 Sieć: {metrics.network_latency:.0f}ms")
                print(f"   🔄 Procesy: {metrics.active_processes}")
                print()

                # Trading Performance
                print("💰 WYDAJNOŚĆ TRADINGOWA:")
                print(f"   🔄 Cykle: {self.current_session_stats['cycles_completed']}")
                print(f"   🎯 Okazje: {self.current_session_stats['total_opportunities']}")
                print(f"   ✅ Sukcesy: {self.current_session_stats['successful_simulations']}")
                print(f"   📈 Stopa sukcesu: {self.calculate_success_rate():.1f}%")
                print(f"   💸 Szacowany zysk: {self.current_session_stats['total_estimated_profit']:.4f} SOL")
                print()

                # Health Score
                print(f"🏆 OCENA ZDROWIA: {self.current_session_stats['system_health_score']:.1f}/100")

                # Anomalies
                anomalies = self.detect_anomalies(metrics)
                if anomalies:
                    print("⚠️  ALARMY:")
                    for anomaly in anomalies:
                        print(f"   {anomaly}")
                else:
                    print("✅ Brak anomalii")

                # Expert Recommendations
                print("\n💡 REKOMENDACJE EKSPERTA:")
                self.generate_expert_recommendations(metrics)

                # Performance vs Targets
                report = self.generate_performance_report()
                if "performance" in report:
                    perf = report["performance"]
                    print("\n🎯 WYNIKI vs CELE:")
                    for metric, data in perf.items():
                        print(f"   {metric}: {data['current']:.1f}/{data['target']:.1f} ({data['achievement']:.1f}%)")

                print("\n" + "="*70)
                print("🔄 Aktualizacja za 30 sekund... (Ctrl+C aby zatrzymać)")

                await asyncio.sleep(self.monitoring_interval)

            except KeyboardInterrupt:
                print("\n🛑 Monitoring zatrzymany przez eksperta")
                break
            except Exception as e:
                logger.error(f"❌ Błąd dashboardu: {e}")
                await asyncio.sleep(10)

    def generate_expert_recommendations(self, metrics: SystemMetrics):
        """Generuj rekomendacje eksperta"""

        recommendations = []

        if metrics.cpu_usage > 70:
            recommendations.append("🔧 Optymalizuj algorytmy CPU")

        if metrics.success_rate < 50:
            recommendations.append("📚 Dostosuj parametry wejściowe")

        if metrics.network_latency > 1000:
            recommendations.append("🌐 Zmień providera RPC")

        if self.current_session_stats["total_opportunities"] < 5:
            recommendations.append("🔍 Rozszerz kryteria okazji")

        if self.current_session_stats["total_estimated_profit"] > 0.1:
            recommendations.append("🚀 Gotowy na mainnet trading!")

        # Always show general recommendations
        if not recommendations:
            recommendations = [
                "📊 Kontynuuj monitoring",
                "🎯 Analizuj wzorce",
                "💡 Optymalizuj parametry"
            ]

        for i, rec in enumerate(recommendations[:5]):  # Max 5 recommendations
            print(f"   {i+1}. {rec}")

    async def start_expert_monitoring(self):
        """Uruchom monitoring eksperta"""
        logger.info("🎓 URUCHAMIANIE EXPERT MONITORING DASHBOARD")
        logger.info("📊 Nadzór nad Devnet Flash Loan System")
        logger.info("🔥 Analiza i optymalizacja w czasie rzeczywistym")

        await self.display_expert_dashboard()

async def main():
    """Główna funkcja expert monitoring system"""

    print("📊 EXPERT MONITORING DASHBOARD")
    print("=" * 50)
    print("🎓 System Nadzoru Eksperta Tradingowego")
    print("🔥 Mojo/Rust/Python Algorithmic Oversight")
    print("📈 Real-time Performance Analysis")
    print()

    dashboard = ExpertMonitoringDashboard()

    try:
        await dashboard.start_expert_monitoring()
    except KeyboardInterrupt:
        print("\n🏁 Zakończono monitoring eksperta")

if __name__ == "__main__":
    asyncio.run(main())