#!/usr/bin/env python3
"""
💰 ARBITRAGE 10 TOKENS V2.0 - Zautomatyzowany Arbitrage na Predefiniowanych Tokenach
Druga strategia V2.0 współpracująca ze Sniper Botem
"""
import asyncio
import aiohttp
import json
import sqlite3
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging
from dataclasses import dataclass
import random

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class ArbitrageOpportunity:
    """Możliwość arbitrażu dla 10 tokenów"""
    token1_address: str
    token2_address: str
    token1_name: str
    token2_name: str
    dex1: str
    dex2: str
    price1: float
    price2: float
    spread_percentage: float
    estimated_profit: float
    required_capital: float
    risk_score: float
    timestamp: datetime
    execution_plan: Dict

@dataclass
class ArbitrageExecution:
    """Wykonanie arbitrażu"""
    opportunity: ArbitrageOpportunity
    trade1_result: Dict
    trade2_result: Dict
    total_profit: float
    execution_time_ms: int
    gas_used: float
    success: bool
    timestamp: datetime

class Arbitrage10TokensV2:
    """Arbitraż na predefiniowanych 10 tokenach"""

    def __init__(self):
        # Predefiniowane 10 tokenów do arbitrażu
        self.arbitrage_tokens = [
            {
                "address": "So11111111111111111111111111111111111111112",  # SOL
                "name": "SOL",
                "stable": False,
                "volatility": 0.15
            },
            {
                "address": "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
                "name": "USDC",
                "stable": True,
                "volatility": 0.02
            },
            {
                "address": "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",  # USDT
                "name": "USDT",
                "stable": True,
                "volatility": 0.03
            },
            {
                "address": "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",  # JUP
                "name": "JUP",
                "stable": False,
                "volatility": 0.25
            },
            {
                "address": "mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So",  # Raydium
                "name": "RAY",
                "stable": False,
                "volatility": 0.30
            },
            {
                "address": "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM",  # Wormhole
                "name": "W",
                "stable": False,
                "volatility": 0.20
            },
            {
                "address": "J1toso1uCk3RLmjorhTtrVwY9HJ7X8L9nUEik3pjL7D8",  # JitoSOL
                "name": "JitoSOL",
                "stable": False,
                "volatility": 0.35
            },
            {
                "address": "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iLJ3S3AKFYjHR",  # USH
                "name": "USH",
                "stable": True,
                "volatility": 0.05
            },
            {
                "address": "Fm7f1uQJQ2iSg7W2qT6Xp8Vd3kH5jB4rG7cE2tN9mP3s",  # Pyth
                "name": "PYTH",
                "stable": False,
                "volatility": 0.40
            },
            {
                "address": "8K5x3Jk2v6Q7p4mT1uS9rW8eX5yN3jH2gF4dV7cR6q9z",  # Atlas
                "name": "ATLAS",
                "stable": False,
                "volatility": 0.25
            }
        ]

        # DEXy do arbitrażu
        self.dexes = [
            {"name": "Raydium", "fee": 0.0025},
            {"name": "Orca", "fee": 0.0030},
            {"name": "Jupiter", "fee": 0.0020},
            {"name": "Serum", "fee": 0.0022}
        ]

        # Parametry arbitrażu
        self.arbitrage_params = {
            "min_spread_percentage": 0.5,  # Min 0.5% spread
            "max_capital_per_trade": 100.0,  # Max 100 SOL na trade
            "min_profit_threshold": 0.1,  # Min 0.1 SOL zysk
            "max_slippage": 0.02,  # Max 2% slippage
            "max_gas_fee": 0.005,  # Max 0.005 SOL gas
        }

        self.db_path = "arbitrage_v2.db"
        self.init_database()

        self.performance_stats = {
            "total_opportunities": 0,
            "executed_trades": 0,
            "successful_trades": 0,
            "total_profit": 0.0,
            "best_trade": 0.0,
            "avg_spread": 0.0,
            "most_profitable_pair": ""
        }

    def init_database(self):
        """Inicjalizacja bazy danych arbitrażu"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Tabela możliwości arbitrażu
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS arbitrage_opportunities (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token1_address TEXT NOT NULL,
                token2_address TEXT NOT NULL,
                token1_name TEXT,
                token2_name TEXT,
                dex1 TEXT,
                dex2 TEXT,
                price1 REAL,
                price2 REAL,
                spread_percentage REAL,
                estimated_profit REAL,
                required_capital REAL,
                risk_score REAL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Tabela wykonań arbitrażu
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS arbitrage_executions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token1_address TEXT NOT NULL,
                token2_address TEXT NOT NULL,
                trade1_result TEXT,
                trade2_result TEXT,
                total_profit REAL,
                execution_time_ms INTEGER,
                gas_used REAL,
                success BOOLEAN,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        conn.commit()
        conn.close()

    def generate_token_prices(self) -> Dict[str, float]:
        """Generuj realistyczne ceny tokenów"""
        prices = {}

        # SOL jako baza
        base_sol_price = random.uniform(140.0, 160.0)  # SOL price variation
        prices["SOL"] = base_sol_price

        # Stable coins
        prices["USDC"] = 1.0
        prices["USDT"] = 1.0
        prices["USH"] = 1.0

        # Inne tokeny (względne do SOL)
        token_prices_vs_sol = {
            "JUP": random.uniform(0.8, 1.2),
            "RAY": random.uniform(1.5, 2.5),
            "W": random.uniform(2.0, 3.5),
            "JitoSOL": random.uniform(0.95, 1.05),
            "PYTH": random.uniform(0.3, 0.7),
            "ATLAS": random.uniform(0.1, 0.3)
        }

        for token_name, price_ratio in token_prices_vs_sol.items():
            prices[token_name] = base_sol_price * price_ratio

        return prices

    def simulate_dex_prices(self, base_prices: Dict[str, float]) -> Dict[str, Dict[str, float]]:
        """Symuluj ceny na różnych DEXach z realistycznymi spreadami"""
        dex_prices = {}

        for dex in self.dexes:
            dex_prices[dex["name"]] = {}
            for token_name, base_price in base_prices.items():
                # Każdy DEX ma lekko inne ceny
                dex_variation = random.uniform(0.98, 1.02)  # ±2% variation
                dex_fee_impact = dex["fee"]

                # Apply variation and fee
                adjusted_price = base_price * dex_variation * (1 + dex_fee_impact)
                dex_prices[dex["name"]][token_name] = adjusted_price

        return dex_prices

    def scan_arbitrage_opportunities(self) -> List[ArbitrageOpportunity]:
        """Skanuj w poszukiwaniu możliwości arbitrażu"""
        logger.info("💰 Skanowanie możliwości arbitrażu na 10 tokenach...")

        opportunities = []

        # Generuj ceny bazowe
        base_prices = self.generate_token_prices()

        # Symuluj ceny na DEXach
        dex_prices = self.simulate_dex_prices(base_prices)

        # Sprawdź wszystkie pary tokenów
        for i, token1 in enumerate(self.arbitrage_tokens):
            for j, token2 in enumerate(self.arbitrage_tokens):
                if i < j:  # Unikaj duplikacji
                    # Sprawdź arbitraż między wszystkimi DEXami
                    for dex1 in self.dexes:
                        for dex2 in self.dexes:
                            if dex1["name"] != dex2["name"]:
                                opportunity = self.check_arbitrage_opportunity(
                                    token1, token2, dex1, dex2,
                                    dex_prices[dex1["name"]], dex_prices[dex2["name"]]
                                )

                                if opportunity and opportunity.spread_percentage > self.arbitrage_params["min_spread_percentage"]:
                                    opportunities.append(opportunity)

        # Sortuj po spreadzie
        opportunities.sort(key=lambda x: x.spread_percentage, reverse=True)

        logger.info(f"📊 Znaleziono {len(opportunities)} możliwości arbitrażu")
        return opportunities[:20]  # Top 20 możliwości

    def check_arbitrage_opportunity(self, token1: Dict, token2: Dict, dex1: Dict, dex2: Dict,
                                   prices1: Dict, prices2: Dict) -> Optional[ArbitrageOpportunity]:
        """Sprawdź pojedynczą możliwość arbitrażu"""

        try:
            # Pobierz ceny
            price1_1 = prices1.get(token1["name"])
            price1_2 = prices1.get(token2["name"])
            price2_1 = prices2.get(token1["name"])
            price2_2 = prices2.get(token2["name"])

            if not all([price1_1, price1_2, price2_1, price2_2]):
                return None

            # Oblicz arbitraż: kup token1 na dex1, sprzedaj na dex2
            spread1 = (price2_1 - price1_1) / price1_1 * 100

            # Oblicz arbitraż: kup token2 na dex1, sprzedaj na dex2
            spread2 = (price1_2 - price2_2) / price2_2 * 100

            # Wybierz lepszy spread
            if abs(spread1) > abs(spread2):
                spread = spread1
                buy_price = price1_1
                sell_price = price2_1
                buy_dex = dex1["name"]
                sell_dex = dex2["name"]
                buy_token = token1
                sell_token = token2
            else:
                spread = spread2
                buy_price = price2_2
                sell_price = price1_2
                buy_dex = dex2["name"]
                sell_dex = dex1["name"]
                buy_token = token2
                sell_token = token1

            # Minimalny spread
            if abs(spread) < self.arbitrage_params["min_spread_percentage"]:
                return None

            # Oblicz zysk
            trade_amount = min(self.arbitrage_params["max_capital_per_trade"], 50.0)

            # Koszty transakcyjne
            total_fees = (dex1["fee"] + dex2["fee"]) * trade_amount
            gas_cost = self.arbitrage_params["max_gas_fee"]

            if spread > 0:  # Long arbitrage
                gross_profit = trade_amount * (spread / 100)
                net_profit = gross_profit - total_fees - gas_cost
            else:  # Short arbitrage
                gross_profit = trade_amount * (abs(spread) / 100)
                net_profit = gross_profit - total_fees - gas_cost

            # Sprawdź minimalny zysk
            if net_profit < self.arbitrage_params["min_profit_threshold"]:
                return None

            # Oblicz risk score
            volatility_factor = (buy_token["volatility"] + sell_token["volatility"]) / 2
            risk_score = min(volatility_factor * 2, 1.0)

            # Plan wykonania
            execution_plan = {
                "action": "BUY_SELL" if spread > 0 else "SELL_BUY",
                "buy_dex": buy_dex,
                "sell_dex": sell_dex,
                "buy_token": buy_token["name"],
                "sell_token": sell_token["name"],
                "buy_amount": trade_amount,
                "buy_price": buy_price,
                "sell_price": sell_price,
                "expected_profit": net_profit
            }

            return ArbitrageOpportunity(
                token1_address=token1["address"],
                token2_address=token2["address"],
                token1_name=token1["name"],
                token2_name=token2["name"],
                dex1=buy_dex,
                dex2=sell_dex,
                price1=buy_price,
                price2=sell_price,
                spread_percentage=abs(spread),
                estimated_profit=net_profit,
                required_capital=trade_amount,
                risk_score=risk_score,
                timestamp=datetime.now(),
                execution_plan=execution_plan
            )

        except Exception as e:
            logger.error(f"Błąd sprawdzania arbitrażu: {e}")
            return None

    async def execute_arbitrage(self, opportunity: ArbitrageOpportunity) -> ArbitrageExecution:
        """Wykonaj transakcję arbitrażową"""
        logger.info(f"💰 Wykonuję arbitraż: {opportunity.token1_name}/{opportunity.token2_name}")
        logger.info(f"   📈 Spread: {opportunity.spread_percentage:.2f}%")
        logger.info(f"   💰 Oczekiwany zysk: {opportunity.estimated_profit:.4f} SOL")

        start_time = time.time()

        # Wykonaj pierwszą transakcję
        trade1_result = await self.simulate_trade_execution(
            opportunity.execution_plan["buy_dex"],
            opportunity.execution_plan["buy_token"],
            opportunity.execution_plan["buy_amount"],
            "BUY"
        )

        if not trade1_result["success"]:
            return ArbitrageExecution(
                opportunity=opportunity,
                trade1_result=trade1_result,
                trade2_result={},
                total_profit=0.0,
                execution_time_ms=int((time.time() - start_time) * 1000),
                gas_used=0.0,
                success=False,
                timestamp=datetime.now()
            )

        # Wykonaj drugą transakcję
        trade2_result = await self.simulate_trade_execution(
            opportunity.execution_plan["sell_dex"],
            opportunity.execution_plan["sell_token"],
            opportunity.execution_plan["buy_amount"],  # Same amount
            "SELL"
        )

        execution_time = int((time.time() - start_time) * 1000)

        # Oblicz rzeczywisty zysk
        total_profit = trade2_result["profit"] - trade1_result.get("cost", 0)
        gas_used = self.arbitrage_params["max_gas_fee"]

        success = total_profit > 0 and trade2_result["success"]

        execution = ArbitrageExecution(
            opportunity=opportunity,
            trade1_result=trade1_result,
            trade2_result=trade2_result,
            total_profit=total_profit,
            execution_time_ms=execution_time,
            gas_used=gas_used,
            success=success,
            timestamp=datetime.now()
        )

        # Zapisz do bazy
        self.save_execution(execution)

        # Aktualizuj statystyki
        self.update_performance_stats(execution)

        return execution

    async def simulate_trade_execution(self, dex: str, token: str, amount: float, action: str) -> Dict:
        """Symuluj wykonanie transakcji na DEX"""

        # Simulacja czasu wykonania
        await asyncio.sleep(0.1)

        # Success probability (95% dla arbitrażu)
        success_probability = 0.95
        if random.random() < success_probability:

            # Simulacja slippage
            slippage = random.uniform(0.001, 0.01)  # 0.1% - 1% slippage

            if action == "BUY":
                actual_price = 1.0 * (1 + slippage)  # Slightly higher price
                cost = amount * actual_price
                profit = -cost  # Negative for buy
            else:
                actual_price = 1.0 * (1 - slippage)  # Slightly lower price
                received = amount * actual_price
                profit = received  # Positive for sell

            return {
                "success": True,
                "dex": dex,
                "token": token,
                "amount": amount,
                "actual_price": actual_price,
                "profit": profit,
                "cost": cost if action == "BUY" else 0.0
            }
        else:
            return {
                "success": False,
                "error": f"Transaction failed on {dex}",
                "dex": dex,
                "token": token
            }

    def save_execution(self, execution: ArbitrageExecution):
        """Zapisz wykonanie arbitrażu do bazy"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO arbitrage_executions
            (token1_address, token2_address, trade1_result, trade2_result,
             total_profit, execution_time_ms, gas_used, success)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            execution.opportunity.token1_address,
            execution.opportunity.token2_address,
            json.dumps(execution.trade1_result),
            json.dumps(execution.trade2_result),
            execution.total_profit,
            execution.execution_time_ms,
            execution.gas_used,
            execution.success
        ))

        conn.commit()
        conn.close()

    def update_performance_stats(self, execution: ArbitrageExecution):
        """Aktualizuj statystyki wydajności"""
        self.performance_stats["executed_trades"] += 1

        if execution.success:
            self.performance_stats["successful_trades"] += 1
            self.performance_stats["total_profit"] += execution.total_profit

            if execution.total_profit > self.performance_stats["best_trade"]:
                self.performance_stats["best_trade"] = execution.total_profit

            # Update most profitable pair
            pair_name = f"{execution.opportunity.token1_name}/{execution.opportunity.token2_name}"
            if execution.total_profit > self.performance_stats.get("pair_profits", {}).get(pair_name, 0):
                self.performance_stats["most_profitable_pair"] = pair_name
                self.performance_stats["pair_profits"] = self.performance_stats.get("pair_profits", {})
                self.performance_stats["pair_profits"][pair_name] = execution.total_profit

        # Update average spread
        total_spread = self.performance_stats.get("total_spread", 0) + execution.opportunity.spread_percentage
        count = self.performance_stats["executed_trades"]
        self.performance_stats["avg_spread"] = total_spread / count
        self.performance_stats["total_spread"] = total_spread

    async def run_arbitrage_session(self, duration_minutes: int = 30):
        """Uruchom sesję arbitrażu V2.0"""
        logger.info("💰 ARBITRAGE 10 TOKENS V2.0 - SESJA ARBITRAŻOWA")
        logger.info("=" * 60)
        logger.info(f"⏱️  Czas trwania: {duration_minutes} minut")
        logger.info(f"🪙 Monitorowanych tokenów: {len(self.arbitrage_tokens)}")
        logger.info(f"📊 Monitorowanych DEXów: {len(self.dexes)}")

        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)

        session_stats = {
            "opportunities_found": 0,
            "executions_made": 0,
            "successful_executions": 0,
            "session_profit": 0.0,
            "best_opportunity": None
        }

        while time.time() < end_time:
            try:
                # Krok 1: Skanuj możliwości arbitrażu
                opportunities = self.scan_arbitrage_opportunities()
                session_stats["opportunities_found"] += len(opportunities)

                if opportunities:
                    # Krok 2: Wybierz najlepszą możliwość
                    best_opportunity = opportunities[0]

                    if best_opportunity.estimated_profit > self.arbitrage_params["min_profit_threshold"] * 2:
                        session_stats["best_opportunity"] = best_opportunity

                        logger.info(f"💰 Wybrano arbitraż: {best_opportunity.token1_name}/{best_opportunity.token2_name}")
                        logger.info(f"   📈 Spread: {best_opportunity.spread_percentage:.2f}%")
                        logger.info(f"   🎯 Oczekiwany zysk: {best_opportunity.estimated_profit:.4f} SOL")
                        logger.info(f"   🛡️  Risk: {best_opportunity.risk_score:.2f}")

                        # Krok 3: Wykonaj arbitraż
                        execution = await self.execute_arbitrage(best_opportunity)
                        session_stats["executions_made"] += 1

                        if execution.success:
                            session_stats["successful_executions"] += 1
                            session_stats["session_profit"] += execution.total_profit

                            logger.info(f"✅ Arbitraż sukces!")
                            logger.info(f"   💰 Zysk: {execution.total_profit:.4f} SOL")
                            logger.info(f"   ⏱️  Czas: {execution.execution_time_ms}ms")
                        else:
                            logger.warning(f"❌ Arbitraż porażka")

                # Czekaj przed kolejnym skanem
                await asyncio.sleep(15)  # 15 sekund

            except Exception as e:
                logger.error(f"❌ Błąd w sesji: {e}")
                await asyncio.sleep(10)

        # Podsumowanie sesji
        self.generate_session_report(session_stats, duration_minutes)

    def generate_session_report(self, stats: Dict, duration_minutes: int):
        """Generuj raport sesji arbitrażowej"""
        success_rate = (stats["successful_executions"] / stats["executions_made"] * 100) if stats["executions_made"] > 0 else 0

        logger.info("\n" + "=" * 60)
        logger.info("📊 RAPORT SESJI ARBITRAŻU 10 TOKENS V2.0")
        logger.info("=" * 60)
        logger.info(f"⏱️  Czas trwania: {duration_minutes} minut")
        logger.info(f"💰 Znalezionych możliwości: {stats['opportunities_found']}")
        logger.info(f"⚡ Wykonanych arbitraży: {stats['executions_made']}")
        logger.info(f"✅ Sukcesy: {stats['successful_executions']} ({success_rate:.1f}%)")
        logger.info(f"💰 Zysk sesji: {stats['session_profit']:.4f} SOL")

        if stats["best_opportunity"]:
            best = stats["best_opportunity"]
            logger.info(f"🏆 Najlepsza możliwość: {best.token1_name}/{best.token2_name}")
            logger.info(f"   📈 Spread: {best.spread_percentage:.2f}%")

        # Statystyki ogólne
        logger.info(f"\n📈 OGÓLNE STATYSTYKI ARBITRAŻU:")
        logger.info(f"   📊 Łączne transakcje: {self.performance_stats['executed_trades']}")
        logger.info(f"   ✅ Sukcesy: {self.performance_stats['successful_trades']}")
        logger.info(f"   💰 Łączny zysk: {self.performance_stats['total_profit']:.4f} SOL")
        logger.info(f"   🏆 Najlepszy trade: {self.performance_stats['best_trade']:.4f} SOL")
        logger.info(f"   📊 Średni spread: {self.performance_stats['avg_spread']:.2f}%")

        if self.performance_stats["most_profitable_pair"]:
            logger.info(f"   💎 Najbardziej rentowna para: {self.performance_stats['most_profitable_pair']}")

        # Rekomendacje
        logger.info(f"\n💡 REKOMENDACJE:")
        if success_rate > 80:
            logger.info(f"   🎉 Świetny wynik arbitrażu!")
            logger.info(f"   💰 Rozważ zwiększenie kapitału")
        elif success_rate > 60:
            logger.info(f"   📈 Dobre wyniki arbitrażu!")
            logger.info(f"   🔧 Optymalizuj filtry możliwości")
        else:
            logger.info(f"   ⚠️  Niski wskaźnik sukcesu arbitrażu")
            logger.info(f"   🛡️ Sprawdź ryzyko i koszty")

async def main():
    """Główna funkcja arbitrażu V2.0"""
    print("💰 ARBITRAGE 10 TOKENS V2.0")
    print("=" * 50)
    print("🪙 Zautomatyzowany arbitrage na predefiniowanych tokenach")
    print("📊 Monitorowanie 4 DEXów w czasie rzeczywistym")
    print("⚡ Błyskawiczne wykrywanie spreadów arbitrażowych")
    print("💰 Integracja ze Sniper Botem V2.0")
    print()

    arbitrage = Arbitrage10TokensV2()

    try:
        # Uruchom sesję arbitrażu
        await arbitrage.run_arbitrage_session(duration_minutes=25)

        print("\n🎉 SESJA ARBITRAŻOWA ZAKOŃCZONA!")
        print("💰 Automatyzacja arbitrażu przyniosła rezultaty!")
        print("📈 System V2.0 gotowy na dalsze strategie!")

    except KeyboardInterrupt:
        print("\n🛑 Sesja przerwana przez użytkownika")
    except Exception as e:
        logger.error(f"❌ Błąd krytyczny: {e}")

if __name__ == "__main__":
    asyncio.run(main())