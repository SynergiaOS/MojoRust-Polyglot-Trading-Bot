#!/usr/bin/env python3
"""
🔄 AUTOMATIC REINVESTMENT ENGINE - Zyski Pracują Dla Ciebie!
Polyglot Trading System: Mojo + Rust + Python
Automatyczna reinwestycja zysków z flash loan snipera
"""

import asyncio
import sqlite3
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import logging
from dataclasses import dataclass

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class ReinvestmentStrategy:
    """Strategia reinwestycji"""
    name: str
    reinvest_percentage: float  # % zysku do reinwestycji
    min_profit_threshold: float  # Minimalny zysk do reinwestycji
    risk_level: str  # LOW, MEDIUM, HIGH
    target_allocation: float  # Docelowa alokacja

class AutomaticReinvestmentEngine:
    """Silnik automatycznej reinwestycji"""

    def __init__(self, db_path: str = "profits.db"):
        self.db_path = db_path
        self.initial_capital = 1.0
        self.current_capital = 1.0

        # Strategie reinwestycji
        self.strategies = [
            ReinvestmentStrategy(
                name="conservative",
                reinvest_percentage=0.5,  # 50% reinwestycji
                min_profit_threshold=0.01,  # Min 0.01 SOL
                risk_level="LOW",
                target_allocation=0.3  # 30% kapitału
            ),
            ReinvestmentStrategy(
                name="balanced",
                reinvest_percentage=0.7,  # 70% reinwestycji
                min_profit_threshold=0.005,  # Min 0.005 SOL
                risk_level="MEDIUM",
                target_allocation=0.5  # 50% kapitału
            ),
            ReinvestmentStrategy(
                name="aggressive",
                reinvest_percentage=0.9,  # 90% reinwestycji
                min_profit_threshold=0.001,  # Min 0.001 SOL
                risk_level="HIGH",
                target_allocation=0.7  # 70% kapitału
            )
        ]

        # Aktualna strategia
        self.current_strategy = self.strategies[1]  # Balanced domyślnie

        # Statystyki reinwestycji
        self.total_reinvested = 0.0
        self.reinvestment_count = 0
        self.compounding_periods = 0

    def get_portfolio_state(self) -> Dict:
        """Pobierz stan portfela z bazy"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('SELECT * FROM portfolio_state WHERE id = 1')
        state = cursor.fetchone()

        if state:
            columns = [desc[0] for desc in cursor.description]
            portfolio_dict = dict(zip(columns, state))
            conn.close()
            return portfolio_dict
        else:
            conn.close()
            return {}

    def calculate_compounding_potential(self) -> Dict:
        """Oblicz potencjał reinwestycji"""

        portfolio = self.get_portfolio_state()

        if not portfolio:
            return {"potential": 0.0, "available_for_reinvestment": 0.0}

        total_profit = portfolio.get('profits_earned', 0.0)
        total_loss = portfolio.get('losses_incurred', 0.0)
        net_profit = portfolio.get('net_profit', 0.0)
        successful_trades = portfolio.get('successful_trades', 0)
        total_trades = portfolio.get('total_trades', 0)

        # Oblicz wskaźniki
        success_rate = (successful_trades / total_trades) if total_trades > 0 else 0.0
        profit_per_trade = net_profit / successful_trades if successful_trades > 0 else 0.0

        # Określ dostępną kwotę do reinwestycji
        available_for_reinvestment = max(0.0, total_profit * self.current_strategy.reinvest_percentage)

        # Oceń potencjał
        if success_rate > 0.7 and profit_per_trade > 0.01:
            potential = "HIGH"
        elif success_rate > 0.5 and profit_per_trade > 0.005:
            potential = "MEDIUM"
        else:
            potential = "LOW"

        return {
            "potential": potential,
            "available_for_reinvestment": available_for_reinvestment,
            "total_profit": total_profit,
            "net_profit": net_profit,
            "success_rate": success_rate,
            "profit_per_trade": profit_per_trade,
            "current_capital": self.initial_capital + net_profit
        }

    def select_optimal_strategy(self, performance_metrics: Dict) -> ReinvestmentStrategy:
        """Wybierz optymalną strategię"""

        success_rate = performance_metrics.get('success_rate', 0.0)
        profit_per_trade = performance_metrics.get('profit_per_trade', 0.0)
        net_profit = performance_metrics.get('net_profit', 0.0)

        # Dynamiczne dobieranie strategii
        if success_rate > 0.8 and profit_per_trade > 0.02:
            # Bardzo dobre wyniki - agresywna reinwestycja
            return self.strategies[2]  # Aggressive
        elif success_rate > 0.6 and profit_per_trade > 0.01:
            # Dobre wyniki - zbalansowana reinwestycja
            return self.strategies[1]  # Balanced
        else:
            # Niskie wyniki - konserwatywna reinwestycja
            return self.strategies[0]  # Conservative

    def simulate_reinvestment_growth(self, periods: int = 30) -> List[Dict]:
        """Symuluj wzrost z reinwestycją"""

        growth_projection = []
        current_capital = self.initial_capital

        # Pobierz aktualne metryki
        metrics = self.calculate_compounding_potential()
        strategy = self.select_optimal_strategy(metrics)

        # Średni zysk na trade
        avg_profit_per_trade = metrics.get('profit_per_trade', 0.01)
        success_rate = metrics.get('success_rate', 0.6)

        # Oczekiwana dzienna liczba trade'ów
        daily_trades = 5  # Przeciętnie 5 snipów dziennie

        for period in range(1, periods + 1):
            # Dzienny zysk
            daily_profit = daily_trades * success_rate * avg_profit_per_trade * strategy.reinvest_percentage

            # Dodaj zysk do kapitału
            current_capital += daily_profit

            # Zwiększ kapitał bazowy (efekt snowball)
            base_growth = daily_profit * (1 - strategy.reinvest_percentage)
            current_capital += base_growth

            # Zapisz stan
            growth_projection.append({
                "period": period,
                "capital": current_capital,
                "daily_profit": daily_profit,
                "total_growth": current_capital - self.initial_capital,
                "growth_percentage": ((current_capital - self.initial_capital) / self.initial_capital) * 100
            })

        return growth_projection

    def execute_reinvestment(self, available_profit: float) -> Dict:
        """Wykonaj reinwestycję"""

        if available_profit < self.current_strategy.min_profit_threshold:
            return {
                "success": False,
                "reason": "Profit below threshold",
                "required": self.current_strategy.min_profit_threshold,
                "available": available_profit
            }

        # Kwota do reinwestycji
        reinvest_amount = available_profit * self.current_strategy.reinvest_percentage
        keep_amount = available_profit - reinvest_amount

        # Aktualizuj kapitał
        self.current_capital += reinvest_amount
        self.total_reinvested += reinvest_amount
        self.reinvestment_count += 1
        self.compounding_periods += 1

        return {
            "success": True,
            "reinvested": reinvest_amount,
            "kept": keep_amount,
            "new_capital": self.current_capital,
            "strategy": self.current_strategy.name
        }

    def generate_reinvestment_report(self) -> Dict:
        """Generuj raport reinwestycji"""

        metrics = self.calculate_compounding_potential()
        strategy = self.select_optimal_strategy(metrics)

        # Symulacja wzrostu na 30 dni
        growth_projection = self.simulate_reinvestment_growth(30)

        # Oblicz prognozy
        final_capital = growth_projection[-1]['capital'] if growth_projection else self.initial_capital
        total_growth = final_capital - self.initial_capital
        growth_percentage = (total_growth / self.initial_capital) * 100

        return {
            "current_strategy": strategy.name,
            "current_metrics": metrics,
            "growth_projection": growth_projection,
            "projections": {
                "daily_average_profit": sum(p['daily_profit'] for p in growth_projection) / len(growth_projection) if growth_projection else 0,
                "final_capital": final_capital,
                "total_growth": total_growth,
                "growth_percentage": growth_percentage,
                "monthly_roi": growth_percentage
            },
            "recommendations": self.generate_recommendations(metrics, growth_projection)
        }

    def generate_recommendations(self, metrics: Dict, projection: List[Dict]) -> List[str]:
        """Generuj rekomendacje"""

        recommendations = []

        success_rate = metrics.get('success_rate', 0.0)
        net_profit = metrics.get('net_profit', 0.0)

        # Rekomendacje strategii
        if success_rate > 0.8:
            recommendations.append("🚀 Świetny wskaźnik sukcesu! Rozważ agresywniejszą reinwestycję")
        elif success_rate < 0.5:
            recommendations.append("⚠️ Niski wskaźnik sukcesu - zmniejsz ryzyko lub popraw filtry")

        # Rekomendacje kapitałowe
        if net_profit > 0.5:
            recommendations.append("💰 Dobry zysk - czas na zwiększenie kapitału bazowego")
        elif net_profit < -0.1:
            recommendations.append("🛑 Straty - przerwij trading i przeanalizuj strategię")

        # Rekomendacje wzrostu
        if projection:
            monthly_growth = projection[-1]['growth_percentage'] if projection else 0
            if monthly_growth > 100:
                recommendations.append("📈 Niesamowity wzrost! Utrzymaj tę strategię")
            elif monthly_growth > 50:
                recommendations.append("✅ Dobry wzrost - kontynuuj reinwestycję")
            elif monthly_growth < 10:
                recommendations.append("📊 Niski wzrost - optymalizuj parametry")

        # Rekomendacje operacyjne
        recommendations.append("💾 Regularnie sprawdzaj stan portfela w bazie danych")
        recommendations.append("🔄 Rozważ dostosowanie strategii co tydzień")
        recommendations.append("📊 Monitoruj wskaźniki sukcesu i rentowności")

        return recommendations

    def show_compounding_effect(self):
        """Pokaż efekt składany"""

        print("🔄 EFEKT SKŁADANY - REINWESTYCJA")
        print("=" * 50)

        # Symulacja różnych scenariuszy
        scenarios = {
            "Bez reinwestycji": self.simulate_fixed_growth(),
            "Reinvestycja 50%": self.simulate_growth_with_reinvestment(0.5),
            "Reinvestycja 75%": self.simulate_growth_with_reinvestment(0.75),
            "Reinvestycja 90%": self.simulate_growth_with_reinvestment(0.9)
        }

        print("📊 PORÓWNANIE SCENARIUSZY (30 dni):")
        print("-" * 50)

        for scenario_name, growth in scenarios.items():
            final_capital = growth[-1]['capital'] if growth else self.initial_capital
            total_growth = final_capital - self.initial_capital
            growth_pct = (total_growth / self.initial_capital) * 100

            print(f"{scenario_name:20}: {final_capital:8.2f} SOL ({growth_pct:+6.1f}%)")

        print("\n💡 WNIOSKI:")
        print("   📈 Wyższy procent reinwestycji = większy wzrost")
        print("   ⚠️  Większa reinwestycja = większe ryzyko")
        print("   🎯 Znajdź optymalny balans dla swojego profilu")

    def simulate_fixed_growth(self, days: int = 30) -> List[Dict]:
        """Symuluj wzrost bez reinwestycji"""

        projection = []
        daily_profit = 0.01  # Stały dzienny zysk
        current_capital = self.initial_capital

        for day in range(1, days + 1):
            current_capital += daily_profit
            projection.append({
                "period": day,
                "capital": current_capital,
                "daily_profit": daily_profit,
                "total_growth": current_capital - self.initial_capital,
                "growth_percentage": ((current_capital - self.initial_capital) / self.initial_capital) * 100
            })

        return projection

    def simulate_growth_with_reinvestment(self, reinvest_percentage: float, days: int = 30) -> List[Dict]:
        """Symuluj wzrost z reinwestycją"""

        projection = []
        current_capital = self.initial_capital
        base_daily_profit = 0.01  # Bazowy dzienny zysk

        for day in range(1, days + 1):
            # Zysk proporcjonalny do kapitału
            daily_profit = base_daily_profit * (current_capital / self.initial_capital)

            # Reinwestycja
            reinvested = daily_profit * reinvest_percentage
            kept = daily_profit * (1 - reinvest_percentage)

            # Aktualizuj kapitał
            current_capital += reinvested

            projection.append({
                "period": day,
                "capital": current_capital,
                "daily_profit": daily_profit,
                "total_growth": current_capital - self.initial_capital,
                "growth_percentage": ((current_capital - self.initial_capital) / self.initial_capital) * 100
            })

        return projection

async def main():
    """Główna funkcja silnika reinwestycji"""

    print("🔄 AUTOMATIC REINVESTMENT ENGINE")
    print("=" * 50)
    print("💰 Zyski pracują dla Ciebie!")
    print("📈 Automatyczna reinwestycja z efektem składanym")
    print("🎯 Dynamiczne dostosowywanie strategii")
    print()

    engine = AutomaticReinvestmentEngine()

    try:
        # Pokaż efekt składany
        engine.show_compounding_effect()

        # Generuj raport
        print("\n" + "=" * 50)
        print("📊 RAPORT REINWESTYCJI")
        print("=" * 50)

        report = engine.generate_reinvestment_report()

        print(f"🎯 Aktualna strategia: {report['current_strategy']}")
        print(f"💰 Dostępne do reinwestycji: {report['current_metrics']['available_for_reinvestment']:.4f} SOL")
        print(f"📈 Wskaźnik sukcesu: {report['current_metrics']['success_rate']:.1%}")
        print(f"💸 Zysk na trade: {report['current_metrics']['profit_per_trade']:.4f} SOL")

        print(f"\n📈 PROGNOZY NA 30 DNI:")
        print(f"   💰 Kapitał końcowy: {report['projections']['final_capital']:.2f} SOL")
        print(f"   📊 Całkowity wzrost: {report['projections']['total_growth']:.2f} SOL")
        print(f"   🎯 ROI miesięczne: {report['projections']['monthly_roi']:.1f}%")
        print(f"   📈 Średni dzienny zysk: {report['projections']['daily_average_profit']:.4f} SOL")

        print(f"\n💡 REKOMENDACJE:")
        for i, rec in enumerate(report['recommendations'], 1):
            print(f"   {i}. {rec}")

        # Wykonaj reinwestycję jeśli jest dostępny zysk
        available = report['current_metrics']['available_for_reinvestment']
        if available > report['current_metrics'].get('min_profit_threshold', 0.01):
            print(f"\n🔄 WYKONUJĘ REINWESTYCJĘ...")
            result = engine.execute_reinvestment(available)

            if result['success']:
                print(f"✅ Reinvestycja udana!")
                print(f"   💰 Zainwestowano: {result['reinvested']:.4f} SOL")
                print(f"   💸 Zachowano: {result['kept']:.4f} SOL")
                print(f"   💻 Nowy kapitał: {result['new_capital']:.4f} SOL")
            else:
                print(f"❌ Reinvestycja nieudana: {result['reason']}")
        else:
            print(f"\n💤 Brak dostępnych zysków do reinwestycji")
            print(f"   💡 Potrzebujesz minimum: {report['current_metrics'].get('min_profit_threshold', 0.01):.4f} SOL")

    except Exception as e:
        logger.error(f"❌ Błąd silnika reinwestycji: {e}")

if __name__ == "__main__":
    asyncio.run(main())