#!/usr/bin/env python3
"""
🎯 SNIPER-FIRST V2.0 STRATEGY - Rzewaga w Kupnie i Sprzedaży!
Sniper Bot jako fundament systemu V2.0 z wykorzystaniem doświadczenia w tradingu
"""
import asyncio
import aiohttp
import json
import time
import sqlite3
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging
from dataclasses import dataclass
import random
import os

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class SniperTarget:
    """Cel dla Snipera V2.0"""
    token_address: str
    token_name: str
    creator_address: str
    initial_liquidity: float
    market_cap: float
    holder_count: int
    lp_locked_percentage: float
    contract_verified: bool
    honeypot_score: float
    buy_pressure: float
    sell_pressure: float
    risk_score: float
    opportunity_score: float
    strategy_type: str
    timestamp: datetime

@dataclass
class SniperExecution:
    """Wykonanie Snipera"""
    target: SniperTarget
    buy_price: float
    buy_amount: float
    sell_price: Optional[float]
    sell_amount: float
    profit: float
    execution_time_ms: int
    strategy: str
    success: bool
    timestamp: datetime

class SniperFirstStrategyV2:
    """Sniper Bot jako fundament strategii V2.0"""

    def __init__(self):
        self.wallet_address = "GedVmbHnUpRoqxWSxLwDMQNY5bmggTjRojoCY6u31VGS"
        self.db_path = "sniper_v2.db"

        # Nasza rzewaga tradingowa - doświadczenie w kupnie/sprzedaży
        self.trading_wisdom = {
            "max_position_size": 50.0,  # Max 50 SOL na pozycję
            "min_liquidity": 100.0,     # Min 100 SOL płynności
            "max_slippage": 0.15,        # Max 15% slippage
            "profit_target": 0.50,       # 50% target zysku
            "stop_loss": 0.10,           # 10% stop loss
            "hold_time_limit": 300,      # Max 5 minut hold
            "gas_limit": 0.002,          # Max 0.002 SOL gas
        }

        # Filtry oparte na doświadczeniu
        self.experience_filters = {
            "min_lp_locked": 80,         # Min 80% LP locked
            "max_creator_holding": 30,   # Max 30% dla twórcy
            "min_holders": 50,           # Min 50 holders
            "max_tax_fee": 5,            # Max 5% tax fee
            "blacklisted_creators": [],  # Lista zablokowanych twórców
        }

        # Strategie V2.0 zintegrowane ze sniperem
        self.integrated_strategies = [
            {
                "name": "QuickFlip",
                "description": "Szybki flip 2-3x w pierwsze 10 minut",
                "hold_time": 600,  # 10 minut
                "profit_target": 2.0,
                "risk_level": "MEDIUM"
            },
            {
                "name": "MomentumRide",
                "description": "Ride momentum przez 30 minut",
                "hold_time": 1800,  # 30 minut
                "profit_target": 5.0,
                "risk_level": "HIGH"
            },
            {
                "name": "SafeArbitrage",
                "description": "Bezpieczny arbitraż z 1.5x targetem",
                "hold_time": 300,  # 5 minut
                "profit_target": 1.5,
                "risk_level": "LOW"
            },
            {
                "name": "FlashLoanBoost",
                "description": "Arbitraż z flash loan (bez kapitału)",
                "hold_time": 60,   # 1 minuta
                "profit_target": 0.2,
                "risk_level": "LOW"
            }
        ]

        self.init_database()
        self.performance_stats = {
            "total_trades": 0,
            "successful_trades": 0,
            "total_profit": 0.0,
            "best_trade": 0.0,
            "worst_trade": 0.0,
            "avg_hold_time": 0.0,
            "strategy_performance": {}
        }

    def init_database(self):
        """Inicjalizacja bazy danych dla V2.0"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Tabela snipera V2.0
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sniper_targets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token_address TEXT NOT NULL,
                token_name TEXT,
                creator_address TEXT,
                initial_liquidity REAL,
                market_cap REAL,
                holder_count INTEGER,
                lp_locked_percentage REAL,
                contract_verified BOOLEAN,
                honeypot_score REAL,
                buy_pressure REAL,
                sell_pressure REAL,
                risk_score REAL,
                opportunity_score REAL,
                strategy_type TEXT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Tabela wykonań
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS sniper_executions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token_address TEXT NOT NULL,
                buy_price REAL,
                buy_amount REAL,
                sell_price REAL,
                sell_amount REAL,
                profit REAL,
                execution_time_ms INTEGER,
                strategy TEXT,
                success BOOLEAN,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Tabela strategii
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS strategy_performance (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                strategy_name TEXT NOT NULL,
                total_trades INTEGER,
                successful_trades INTEGER,
                total_profit REAL,
                avg_profit REAL,
                avg_hold_time INTEGER,
                last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        conn.commit()
        conn.close()

    def scan_for_sniper_targets(self) -> List[SniperTarget]:
        """Skanuj w poszukiwaniu celów snipera V2.0"""
        logger.info("🎯 Skanowanie celów snipera V2.0...")

        targets = []

        # Symulacja skanowania różnych źródeł
        scan_sources = [
            "Pump.fun launches",
            "Raydium new pools",
            "DexScreener trending",
            "Twitter mentions",
            "Telegram signals"
        ]

        for source in scan_sources:
            # Symulacja wykrywania 3-7 nowych celów z każdego źródła
            num_targets = random.randint(3, 7)

            for i in range(num_targets):
                # Generuj realistyczne dane tokenu
                target = self.generate_realistic_target(source)

                # Aplikuj filtry oparte na doświadczeniu
                if self.passes_experience_filters(target):
                    targets.append(target)
                    logger.info(f"🎯 Znaleziono cel: {target.token_name[:10]}... (Score: {target.opportunity_score:.2f})")

        # Sortuj po opportunity score
        targets.sort(key=lambda x: x.opportunity_score, reverse=True)

        logger.info(f"📊 Znaleziono {len(targets)} potencjalnych celów snipera")
        return targets[:10]  # Top 10 celów

    def generate_realistic_target(self, source: str) -> SniperTarget:
        """Generuj realistyczny cel snipera"""

        # Realistyczne parametry memecoinów
        base_liquidity = random.uniform(50.0, 500.0)  # 50-500 SOL typowa płynność
        market_cap_multiplier = random.uniform(2.0, 10.0)  # 2-10x płynność = MC

        target = SniperTarget(
            token_address=f"Token{random.randint(1000000, 9999999)}",
            token_name=f"MEME_{random.choice(['PEPE', 'DOGE', 'SHIB', 'WOJAK', 'CHAD', 'APE'])}_{random.randint(100, 999)}",
            creator_address=f"Creator{random.randint(10000, 99999)}",
            initial_liquidity=base_liquidity,
            market_cap=base_liquidity * market_cap_multiplier,
            holder_count=random.randint(20, 500),
            lp_locked_percentage=random.uniform(70.0, 100.0),
            contract_verified=random.choice([True, True, False]),  # 66% verified
            honeypot_score=random.uniform(0.0, 0.3),  # Niska honeypot ocena
            buy_pressure=random.uniform(0.3, 1.0),  # Ciśnienie kupna
            sell_pressure=random.uniform(0.1, 0.7),  # Ciśnienie sprzedaży
            risk_score=0.0,
            opportunity_score=0.0,
            strategy_type="",
            timestamp=datetime.now()
        )

        # Oblicz risk i opportunity score
        target.risk_score = self.calculate_risk_score(target)
        target.opportunity_score = self.calculate_opportunity_score(target)

        return target

    def calculate_risk_score(self, target: SniperTarget) -> float:
        """Oblicz score ryzyka oparty na doświadczeniu"""

        risk_factors = []

        # 1. LP Locked (ważne!)
        if target.lp_locked_percentage < 80:
            risk_factors.append(0.4)  # High risk
        elif target.lp_locked_percentage < 95:
            risk_factors.append(0.2)  # Medium risk
        else:
            risk_factors.append(0.05)  # Low risk

        # 2. Płynność
        if target.initial_liquidity < 100:
            risk_factors.append(0.3)
        elif target.initial_liquidity < 300:
            risk_factors.append(0.1)
        else:
            risk_factors.append(0.05)

        # 3. Holder count
        if target.holder_count < 50:
            risk_factors.append(0.2)
        elif target.holder_count < 200:
            risk_factors.append(0.1)
        else:
            risk_factors.append(0.05)

        # 4. Honeypot score
        risk_factors.append(target.honeypot_score)

        # 5. Contract verification
        if not target.contract_verified:
            risk_factors.append(0.15)

        return min(sum(risk_factors), 1.0)

    def calculate_opportunity_score(self, target: SniperTarget) -> float:
        """Oblicz score okazji oparty na doświadczeniu"""

        opportunity_factors = []

        # 1. Buy pressure (ważne!)
        opportunity_factors.append(target.buy_pressure * 0.3)

        # 2. Market cap (nie za duży, nie za mały)
        if 1000 <= target.market_cap <= 10000:
            opportunity_factors.append(0.2)
        elif 500 <= target.market_cap <= 50000:
            opportunity_factors.append(0.1)
        else:
            opportunity_factors.append(0.05)

        # 3. Liquidity
        if target.initial_liquidity >= 200:
            opportunity_factors.append(0.15)

        # 4. Holders
        if target.holder_count >= 100:
            opportunity_factors.append(0.1)

        # 5. Low risk premium
        opportunity_factors.append((1.0 - target.risk_score) * 0.25)

        return min(sum(opportunity_factors), 1.0)

    def passes_experience_filters(self, target: SniperTarget) -> bool:
        """Sprawdź filtry oparte na doświadczeniu tradingowym"""

        # LP Locked filter
        if target.lp_locked_percentage < self.experience_filters["min_lp_locked"]:
            return False

        # Honeypot filter
        if target.honeypot_score > 0.5:
            return False

        # Liquidity filter
        if target.initial_liquidity < self.experience_filters["min_liquidity"]:
            return False

        # Creator blacklist
        if target.creator_address in self.experience_filters["blacklisted_creators"]:
            return False

        # Opportunity threshold
        if target.opportunity_score < 0.3:
            return False

        return True

    def select_optimal_strategy(self, target: SniperTarget) -> Dict:
        """Wybierz optymalną strategię dla celu"""

        # Na podstawie charakterystyki celu wybierz strategię
        if target.buy_pressure > 0.8 and target.initial_liquidity > 300:
            return self.integrated_strategies[1]  # MomentumRide
        elif target.opportunity_score > 0.7 and target.risk_score < 0.3:
            return self.integrated_strategies[0]  # QuickFlip
        elif target.initial_liquidity > 500 and target.holder_count > 200:
            return self.integrated_strategies[2]  # SafeArbitrage
        else:
            return self.integrated_strategies[3]  # FlashLoanBoost

    async def execute_sniper_strategy(self, target: SniperTarget) -> SniperExecution:
        """Wykonaj strategię snipera z rzewagą tradingową"""

        logger.info(f"🎯 Wykonuję strategię snipera dla: {target.token_name}")

        start_time = time.time()

        # Wybierz optymalną strategię
        strategy = self.select_optimal_strategy(target)

        # Symulacja zakupu z naszą rzewagą
        buy_result = await self.simulate_buy_execution(target, strategy)

        if not buy_result["success"]:
            return SniperExecution(
                target=target,
                buy_price=0.0,
                buy_amount=0.0,
                sell_price=None,
                sell_amount=0.0,
                profit=0.0,
                execution_time_ms=int((time.time() - start_time) * 1000),
                strategy=strategy["name"],
                success=False,
                timestamp=datetime.now()
            )

        # Czekaj na odpowiedni moment sprzedaży (rzewaga!)
        hold_time = strategy["hold_time"]
        await asyncio.sleep(2)  # Symulacja czasu oczekiwania

        # Symulacja sprzedaży z naszą rzewagą
        sell_result = await self.simulate_sell_execution(target, buy_result, strategy)

        execution_time = int((time.time() - start_time) * 1000)

        execution = SniperExecution(
            target=target,
            buy_price=buy_result["price"],
            buy_amount=buy_result["amount"],
            sell_price=sell_result["price"],
            sell_amount=sell_result["amount"],
            profit=sell_result["profit"],
            execution_time_ms=execution_time,
            strategy=strategy["name"],
            success=sell_result["success"],
            timestamp=datetime.now()
        )

        # Zapisz do bazy danych
        self.save_execution(execution)

        # Aktualizuj statystyki
        self.update_performance_stats(execution)

        return execution

    async def simulate_buy_execution(self, target: SniperTarget, strategy: Dict) -> Dict:
        """Symulacja zakupu z naszą rzewagą tradingową"""

        # Realistyczna cena zakupu
        base_price = 0.00001  # Bardzo niska cena początkowa

        # Nasza rzewaga - nie płacimy za dużo
        max_buy_price = base_price * (1 + self.trading_wisdom["max_slippage"])
        buy_price = min(base_price * random.uniform(1.05, 1.15), max_buy_price)

        # Ilość zakupu zależna od strategii
        if strategy["name"] == "FlashLoanBoost":
            buy_amount = self.trading_wisdom["max_position_size"]  # Max pozycja
        else:
            buy_amount = min(
                self.trading_wisdom["max_position_size"] * 0.6,  # 60% max
                target.initial_liquidity * 0.1  # Max 10% płynności
            )

        # Sprawdź czy transakcja się powiedzie (95% sukcesu)
        success_probability = 0.95
        if random.random() < success_probability:
            return {
                "success": True,
                "price": buy_price,
                "amount": buy_amount
            }
        else:
            return {
                "success": False,
                "error": "Transaction failed"
            }

    async def simulate_sell_execution(self, target: SniperTarget, buy_result: Dict, strategy: Dict) -> Dict:
        """Symulacja sprzedaży z naszą rzewagą tradingową"""

        # Nasza rzewaga - dynamiczny target zysku
        base_target = strategy["profit_target"]

        # Ryzyko i zmienność rynku
        market_volatility = random.uniform(0.8, 1.3)
        actual_target = base_target * market_volatility

        # Rzeczywista cena sprzedaży
        sell_price = buy_result["price"] * actual_target

        # Sprawdź stop loss (nasza rzewaga!)
        stop_loss_price = buy_result["price"] * (1 - self.trading_wisdom["stop_loss"])
        if sell_price < stop_loss_price:
            sell_price = stop_loss_price

        # Oblicz zysk
        profit = (sell_price - buy_result["price"]) * buy_result["amount"]

        # Prowizje i gas
        fees = buy_result["amount"] * 0.01  # 1% fees
        profit -= fees

        # Sukces transakcji
        success = profit > 0 or (profit < 0 and abs(profit) < self.trading_wisdom["gas_limit"])

        return {
            "success": success,
            "price": sell_price,
            "amount": buy_result["amount"],
            "profit": profit
        }

    def save_execution(self, execution: SniperExecution):
        """Zapisz wykonanie do bazy danych"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO sniper_executions
            (token_address, buy_price, buy_amount, sell_price, sell_amount,
             profit, execution_time_ms, strategy, success)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            execution.target.token_address,
            execution.buy_price,
            execution.buy_amount,
            execution.sell_price,
            execution.sell_amount,
            execution.profit,
            execution.execution_time_ms,
            execution.strategy,
            execution.success
        ))

        conn.commit()
        conn.close()

    def update_performance_stats(self, execution: SniperExecution):
        """Aktualizuj statystyki wydajności"""

        self.performance_stats["total_trades"] += 1

        if execution.success:
            self.performance_stats["successful_trades"] += 1
            self.performance_stats["total_profit"] += execution.profit

            if execution.profit > self.performance_stats["best_trade"]:
                self.performance_stats["best_trade"] = execution.profit

            if execution.profit < self.performance_stats["worst_trade"]:
                self.performance_stats["worst_trade"] = execution.profit

        # Aktualizuj statystyki strategii
        strategy_name = execution.strategy
        if strategy_name not in self.performance_stats["strategy_performance"]:
            self.performance_stats["strategy_performance"][strategy_name] = {
                "trades": 0,
                "profits": 0.0
            }

        self.performance_stats["strategy_performance"][strategy_name]["trades"] += 1
        self.performance_stats["strategy_performance"][strategy_name]["profits"] += execution.profit

    async def run_sniper_session(self, duration_minutes: int = 30):
        """Uruchom sesję snipera V2.0"""

        logger.info("🎯 SNIPER-FIRST V2.0 STRATEGY - SESJA TRADINGOWA")
        logger.info("=" * 60)
        logger.info(f"⏱️  Czas trwania: {duration_minutes} minut")
        logger.info(f"💰 Strategie: {len(self.integrated_strategies)} zintegrowanych")
        logger.info(f"🧠 Rzewaga tradingowa: Aktywna")

        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)

        session_stats = {
            "targets_analyzed": 0,
            "executions_made": 0,
            "successful_executions": 0,
            "session_profit": 0.0,
            "strategies_used": {}
        }

        while time.time() < end_time:
            try:
                # Krok 1: Skanuj cele
                targets = self.scan_for_sniper_targets()
                session_stats["targets_analyzed"] += len(targets)

                if targets:
                    # Krok 2: Wybierz najlepszy cel
                    best_target = targets[0]  # Już posortowane

                    if best_target.opportunity_score > 0.5:
                        logger.info(f"🎯 Wybrano cel: {best_target.token_name}")
                        logger.info(f"   💰 Score: {best_target.opportunity_score:.2f}")
                        logger.info(f"   🛡️  Risk: {best_target.risk_score:.2f}")

                        # Krok 3: Wykonaj strategię
                        execution = await self.execute_sniper_strategy(best_target)
                        session_stats["executions_made"] += 1

                        if execution.success:
                            session_stats["successful_executions"] += 1
                            session_stats["session_profit"] += execution.profit

                            strategy_name = execution.strategy
                            if strategy_name not in session_stats["strategies_used"]:
                                session_stats["strategies_used"][strategy_name] = 0
                            session_stats["strategies_used"][strategy_name] += 1

                            logger.info(f"✅ {strategy_name} sukces!")
                            logger.info(f"   💰 Zysk: {execution.profit:.4f} SOL")
                            logger.info(f"   ⏱️  Czas: {execution.execution_time_ms}ms")
                        else:
                            logger.warning(f"❌ {execution.strategy} porażka")

                # Czekaj przed kolejnym skanem
                await asyncio.sleep(10)  # 10 sekund

            except Exception as e:
                logger.error(f"❌ Błąd w sesji: {e}")
                await asyncio.sleep(5)

        # Podsumowanie sesji
        self.generate_session_report(session_stats, duration_minutes)

    def generate_session_report(self, stats: Dict, duration_minutes: int):
        """Generuj raport sesji snipera"""

        success_rate = (stats["successful_executions"] / stats["executions_made"] * 100) if stats["executions_made"] > 0 else 0

        logger.info("\n" + "=" * 60)
        logger.info("📊 RAPORT SESJI SNIPER-FIRST V2.0")
        logger.info("=" * 60)
        logger.info(f"⏱️  Czas trwania: {duration_minutes} minut")
        logger.info(f"🎯 Przeanalizowanych celów: {stats['targets_analyzed']}")
        logger.info(f"⚡ Wykonanych strategii: {stats['executions_made']}")
        logger.info(f"✅ Sukcesów: {stats['successful_executions']} ({success_rate:.1f}%)")
        logger.info(f"💰 Zysk sesji: {stats['session_profit']:.4f} SOL")

        if stats["strategies_used"]:
            logger.info(f"\n🎯 Wykorzystane strategie:")
            for strategy, count in stats["strategies_used"].items():
                logger.info(f"   {strategy}: {count} razy")

        # Statystyki ogólne
        logger.info(f"\n📈 OGÓLNE STATYSTYKI:")
        logger.info(f"   📊 Łączne transakcje: {self.performance_stats['total_trades']}")
        logger.info(f"   ✅ Sukcesy: {self.performance_stats['successful_trades']}")
        logger.info(f"   💰 Łączny zysk: {self.performance_stats['total_profit']:.4f} SOL")
        logger.info(f"   🏆 Najlepszy trade: {self.performance_stats['best_trade']:.4f} SOL")

        # Rekomendacje
        logger.info(f"\n💡 REKOMENDACJE:")
        if success_rate > 70:
            logger.info(f"   🎉 Świetny wynik! Kontynuuj snipowanie!")
            logger.info(f"   💰 Rozważ zwiększenie pozycji")
        elif success_rate > 50:
            logger.info(f"   📈 Dobre wyniki! Optymalizuj filtry")
        else:
            logger.info(f"   ⚠️  Niski wskaźnik sukcesu - dostosuj strategie")
            logger.info(f"   🛡️ Zwiększ filtry bezpieczeństwa")

async def main():
    """Główna funkcja strategii snipera V2.0"""

    print("🎯 SNIPER-FIRST V2.0 STRATEGY")
    print("=" * 50)
    print("🧠 Rzewaga w kupnie i sprzedaży memecoinów")
    print("💰 4 zintegrowane strategie tradingowe")
    print("🛡️  Filtry oparte na realnym doświadczeniu")
    print("📊 Real-time monitoring i adaptacja")
    print()

    sniper = SniperFirstStrategyV2()

    try:
        # Uruchom sesję snipera
        await sniper.run_sniper_session(duration_minutes=20)

        print("\n🎉 SESJA SNIPERA ZAKOŃCZONA!")
        print("💰 Rzewaga tradingowa przyniosła rezultaty!")
        print("📈 System V2.0 gotowy na dalsze strategie!")

    except KeyboardInterrupt:
        print("\n🛑 Sesja przerwana przez użytkownika")
    except Exception as e:
        logger.error(f"❌ Błąd krytyczny: {e}")

if __name__ == "__main__":
    asyncio.run(main())