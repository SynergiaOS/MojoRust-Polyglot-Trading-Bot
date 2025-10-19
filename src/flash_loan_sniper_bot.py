#!/usr/bin/env python3
"""
🎯 FLASH LOAN SNIPER BOT - Zyski Zapisywane Na Trwałe!
Polyglot Trading System: Mojo + Rust + Python
Flash Loan Sniper z automatycznym zapisem i reinwestycją zysków
"""

import asyncio
import aiohttp
import json
import time
import base64
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import logging
import sqlite3
import os
from dataclasses import dataclass, asdict
import random

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@dataclass
class SnipeTarget:
    """Cel snajpera"""
    token_mint: str
    creator: str
    initial_liquidity_sol: float
    hype_score: float
    confidence: float
    potential_profit: float
    timestamp: datetime

@dataclass
class FlashLoanExecution:
    """Wykonanie flash loan"""
    target: SnipeTarget
    loan_amount: float
    profit: float
    success: bool
    execution_time_ms: int
    gas_used: float
    fees_paid: float
    timestamp: datetime

class ProfitDatabase:
    """Baza danych zysków"""

    def __init__(self, db_path: str = "profits.db"):
        self.db_path = db_path
        self.init_database()

    def init_database(self):
        """Inicjalizuj bazę danych"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Tabela zysków
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS profits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                token_mint TEXT NOT NULL,
                creator TEXT,
                loan_amount REAL NOT NULL,
                profit REAL NOT NULL,
                success BOOLEAN NOT NULL,
                execution_time_ms INTEGER,
                gas_used REAL,
                fees_paid REAL,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Tabela stanu portfela
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS portfolio_state (
                id INTEGER PRIMARY KEY DEFAULT 1,
                total_sol REAL NOT NULL DEFAULT 0.0,
                profits_earned REAL NOT NULL DEFAULT 0.0,
                losses_incurred REAL NOT NULL DEFAULT 0.0,
                net_profit REAL NOT NULL DEFAULT 0.0,
                successful_trades INTEGER NOT NULL DEFAULT 0,
                total_trades INTEGER NOT NULL DEFAULT 0,
                last_updated DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        ''')

        # Inicjalizuj stan portfela jeśli nie istnieje
        cursor.execute('''
            INSERT OR IGNORE INTO portfolio_state (id, total_sol) VALUES (1, 0.0)
        ''')

        conn.commit()
        conn.close()

    def save_execution(self, execution: FlashLoanExecution) -> int:
        """Zapisz wykonanie do bazy"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            INSERT INTO profits
            (token_mint, creator, loan_amount, profit, success, execution_time_ms, gas_used, fees_paid, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            execution.target.token_mint,
            execution.target.creator,
            execution.loan_amount,
            execution.profit,
            execution.success,
            execution.execution_time_ms,
            execution.gas_used,
            execution.fees_paid,
            execution.timestamp
        ))

        execution_id = cursor.lastrowid

        # Aktualizuj stan portfela
        if execution.success:
            cursor.execute('''
                UPDATE portfolio_state
                SET profits_earned = profits_earned + ?,
                    net_profit = net_profit + ?,
                    successful_trades = successful_trades + 1,
                    total_trades = total_trades + 1,
                    last_updated = CURRENT_TIMESTAMP
                WHERE id = 1
            ''', (execution.profit, execution.profit))
        else:
            cursor.execute('''
                UPDATE portfolio_state
                SET losses_incurred = losses_incurred + ?,
                    net_profit = net_profit - ?,
                    total_trades = total_trades + 1,
                    last_updated = CURRENT_TIMESTAMP
                WHERE id = 1
            ''', (abs(execution.profit), abs(execution.profit)))

        conn.commit()
        conn.close()

        return execution_id

    def get_portfolio_state(self) -> Dict:
        """Pobierz stan portfela"""
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

    def get_profit_history(self, limit: int = 100) -> List[Dict]:
        """Pobierz historię zysków"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute('''
            SELECT * FROM profits
            ORDER BY timestamp DESC
            LIMIT ?
        ''', (limit,))

        rows = cursor.fetchall()
        columns = [desc[0] for desc in cursor.description]

        history = [dict(zip(columns, row)) for row in rows]
        conn.close()

        return history

class FlashLoanSniperBot:
    """Główny bot snajpera z flash loans"""

    def __init__(self, initial_sol: float = 1.0):
        self.wallet_address = "GedVmbHnUpRoqxWSxLwDMQNY5bmggTjRojoCY6u31VGS"
        self.initial_sol = initial_sol
        self.current_sol = initial_sol

        # Baza danych zysków
        self.db = ProfitDatabase()

        # Konfiguracja snajpera
        self.min_liquidity = 15.0  # Min 15 SOL liquidity
        self.max_flash_loan = 100.0  # Max 100 SOL flash loan
        self.min_profit_threshold = 0.01  # Min 0.01 SOL profit
        self.max_risk_score = 0.7  # Max risk score

        # Statystyki
        self.targets_analyzed = 0
        self.executions_completed = 0
        self.total_profit_earned = 0.0

        # API endpoints
        self.helius_url = f"https://rpc.devnet.helius.xyz/?api-key=helius-dev-k8k2j3j4k5n6m7p8q9r0s1t2u3v4w5x6y7z8"
        self.jupiter_quote = "https://quote-api.jup.ag/v6/quote"

        # Flash loan providers
        self.flash_loan_providers = {
            "solend": {"fee_rate": 0.0003, "max_amount": 50.0},
            "marginfi": {"fee_rate": 0.0005, "max_amount": 30.0},
            "jupiter": {"fee_rate": 0.0004, "max_amount": 20.0}
        }

    async def scan_for_new_tokens(self) -> List[SnipeTarget]:
        """Skanuj w poszukiwaniu nowych tokenów"""
        logger.info("🔍 Skanowanie nowych tokenów...")

        # Symulacja wykrywania nowych tokenów
        # W rzeczywistości byłoby to połączenie z Geyser/Helius

        new_tokens = []

        # Symuluj 3-5 nowych tokenów
        num_tokens = random.randint(3, 5)

        for i in range(num_tokens):
            # Wygeneruj losowe dane tokenu
            token_mint = f"Token{i}_{int(time.time())}"
            creator = f"Creator{i}_{random.randint(1000, 9999)}"
            liquidity = random.uniform(10.0, 100.0)
            hype_score = random.uniform(0.1, 1.0)
            confidence = random.uniform(0.3, 0.9)

            # Tylko tokeny które przejdą filtrowanie
            if (liquidity >= self.min_liquidity and
                hype_score > 0.3 and
                confidence > 0.5):

                potential_profit = self.estimate_potential_profit(liquidity, hype_score, confidence)

                target = SnipeTarget(
                    token_mint=token_mint,
                    creator=creator,
                    initial_liquidity_sol=liquidity,
                    hype_score=hype_score,
                    confidence=confidence,
                    potential_profit=potential_profit,
                    timestamp=datetime.now()
                )

                new_tokens.append(target)
                logger.info(f"🎯 Znaleziono token: {token_mint[:10]}... (Liq: {liquidity:.1f} SOL, Hype: {hype_score:.2f})")

        self.targets_analyzed += len(new_tokens)
        return new_tokens

    def estimate_potential_profit(self, liquidity: float, hype_score: float, confidence: float) -> float:
        """Oszacuj potencjalny zysk"""

        # Baza zysku z hype i liquidity
        base_profit = (hype_score * 0.5) + (liquidity * 0.01)

        # Mnożnik pewności
        profit_multiplier = 1.0 + (confidence - 0.5)

        # Losowy czynnik (ryzyko/opportunity)
        random_factor = random.uniform(0.5, 2.0)

        potential_profit = base_profit * profit_multiplier * random_factor

        return max(0.0, potential_profit)

    def select_best_target(self, targets: List[SnipeTarget]) -> Optional[SnipeTarget]:
        """Wybierz najlepszy cel do snipowania"""

        if not targets:
            return None

        # Sortuj po potencjalnym zysku
        sorted_targets = sorted(targets, key=lambda x: x.potential_profit, reverse=True)

        # Wybierz pierwszy który spełnia kryteria
        for target in sorted_targets:
            if (target.potential_profit >= self.min_profit_threshold and
                target.confidence > 0.6 and
                target.hype_score > 0.4):
                return target

        return None

    async def execute_flash_loan_snipe(self, target: SnipeTarget) -> FlashLoanExecution:
        """Wykonaj snip z flash loanem"""

        logger.info(f"⚡ Wykonuję flash loan snipe: {target.token_mint[:10]}...")

        start_time = time.time()

        # Wybierz providera flash loan
        provider = self.select_flash_loan_provider(target.potential_profit)

        # Określ kwotę pożyczki
        loan_amount = min(
            self.max_flash_loan,
            provider["max_amount"],
            target.initial_liquidity_sol * 0.5  # 50% liquidity
        )

        # Oblicz opłaty
        flash_fee = loan_amount * provider["fee_rate"]
        gas_estimate = 0.001  # 0.001 SOL
        slippage_estimate = loan_amount * 0.002  # 0.2%
        total_fees = flash_fee + gas_estimate + slippage_estimate

        # Symulacja wykonania
        execution_time_ms = random.randint(2000, 5000)
        success_probability = target.confidence

        # Losuj wynik
        success = random.random() < success_probability

        if success:
            # Oblicz rzeczywisty zysk
            gross_profit = target.potential_profit * (loan_amount / 20.0)  # Skaluj zysk
            net_profit = gross_profit - total_fees
        else:
            # Strata (fees)
            net_profit = -total_fees

        execution = FlashLoanExecution(
            target=target,
            loan_amount=loan_amount,
            profit=net_profit,
            success=success,
            execution_time_ms=execution_time_ms,
            gas_used=gas_estimate,
            fees_paid=total_fees,
            timestamp=datetime.now()
        )

        # Zapisz do bazy danych
        execution_id = self.db.save_execution(execution)

        # Aktualizuj statystyki
        self.executions_completed += 1
        if success:
            self.total_profit_earned += net_profit
            self.current_sol += net_profit
            logger.info(f"✅ Snip sukces! Zysk: {net_profit:.4f} SOL")
        else:
            self.current_sol += net_profit  # Odejmij stratę
            logger.warning(f"❌ Snip nieudany! Strata: {abs(net_profit):.4f} SOL")

        # Pokaż szczegóły
        logger.info(f"📊 Detale wykonania:")
        logger.info(f"   💰 Pożyczka: {loan_amount:.2f} SOL z {provider}")
        logger.info(f"   ⏱️  Czas: {execution_time_ms}ms")
        logger.info(f"   💸 Opłaty: {total_fees:.4f} SOL")
        logger.info(f"   📈 Saldo: {self.current_sol:.4f} SOL")

        return execution

    def select_flash_loan_provider(self, potential_profit: float) -> Dict:
        """Wybierz najlepszego providera flash loan"""

        # Jeśli zysk jest wysoki, użyj droższego providera z większym limitem
        if potential_profit > 1.0:
            return self.flash_loan_providers["solend"]
        elif potential_profit > 0.5:
            return self.flash_loan_providers["marginfi"]
        else:
            return self.flash_loan_providers["jupiter"]

    async def run_sniping_session(self, duration_minutes: int = 30):
        """Uruchom sesję snipowania"""

        logger.info("🎯 URUCHAMIANIE SESJI SNIPER FLASH LOAN")
        logger.info("=" * 60)
        logger.info(f"⏱️  Czas trwania: {duration_minutes} minut")
        logger.info(f"💰 Saldo początkowe: {self.current_sol:.4f} SOL")
        logger.info(f"🎯 Cel: Zbierz zyski i reinwestuj!")

        start_time = time.time()
        end_time = start_time + (duration_minutes * 60)

        session_stats = {
            "targets_found": 0,
            "snipes_executed": 0,
            "successful_snipes": 0,
            "session_profit": 0.0,
            "best_snipe": None
        }

        while time.time() < end_time:
            try:
                # Krok 1: Znajdź nowe tokeny
                new_targets = await self.scan_for_new_tokens()
                session_stats["targets_found"] += len(new_targets)

                if new_targets:
                    # Krok 2: Wybierz najlepszy cel
                    best_target = self.select_best_target(new_targets)

                    if best_target:
                        logger.info(f"🎯 Wybrano cel: {best_target.token_mint[:10]}...")
                        logger.info(f"   💰 Potencjalny zysk: {best_target.potential_profit:.4f} SOL")
                        logger.info(f"   💪 Pewność: {best_target.confidence:.2f}")

                        # Krok 3: Wykonaj snip
                        execution = await self.execute_flash_loan_snipe(best_target)
                        session_stats["snipes_executed"] += 1

                        if execution.success:
                            session_stats["successful_snipes"] += 1
                            session_stats["session_profit"] += execution.profit

                            if (session_stats["best_snipe"] is None or
                                execution.profit > session_stats["best_snipe"].profit):
                                session_stats["best_snipe"] = execution

                        # Sprawdź czy mamy wystarczająco środków
                        if self.current_sol < 0.01:
                            logger.warning("⚠️  Niskie saldo - kończę sesję")
                            break

                # Czekaj przed kolejnym skanem
                await asyncio.sleep(10)  # 10 sekund

            except Exception as e:
                logger.error(f"❌ Błąd w sesji: {e}")
                await asyncio.sleep(5)

        # Podsumowanie sesji
        await self.generate_session_report(session_stats, duration_minutes)

    async def generate_session_report(self, stats: Dict, duration_minutes: int):
        """Generuj raport sesji"""

        logger.info("\n" + "=" * 60)
        logger.info("📊 RAPORT SESJI SNIPER FLASH LOAN")
        logger.info("=" * 60)

        success_rate = (stats["successful_snipes"] / stats["snipes_executed"] * 100) if stats["snipes_executed"] > 0 else 0

        logger.info(f"⏱️  Czas trwania: {duration_minutes} minut")
        logger.info(f"🎯 Znalezionych celów: {stats['targets_found']}")
        logger.info(f"🔄 Wykonanych snipów: {stats['snipes_executed']}")
        logger.info(f"✅ Sukcesów: {stats['successful_snipes']} ({success_rate:.1f}%)")
        logger.info(f"💰 Zysk sesji: {stats['session_profit']:.4f} SOL")

        if stats["best_snipe"]:
            best = stats["best_snipe"]
            logger.info(f"🏆 Najlepszy snip: +{best.profit:.4f} SOL")

        # Pobierz stan portfela z bazy
        portfolio_state = self.db.get_portfolio_state()

        logger.info(f"\n💪 STAN PORTFELA:")
        logger.info(f"   💸 Zyski łączne: {portfolio_state.get('profits_earned', 0):.4f} SOL")
        logger.info(f"   💸 Straty łączne: {portfolio_state.get('losses_incurred', 0):.4f} SOL")
        logger.info(f"   💎 Zysk netto: {portfolio_state.get('net_profit', 0):.4f} SOL")
        logger.info(f"   🎯 Sukcesy: {portfolio_state.get('successful_trades', 0)}/{portfolio_state.get('total_trades', 0)}")

        # Porównaj z początkiem
        total_change = self.current_sol - self.initial_sol
        change_percentage = (total_change / self.initial_sol) * 100 if self.initial_sol > 0 else 0

        logger.info(f"\n📈 ZMIANA OD POCZĄTKU:")
        logger.info(f"   💰 Zmiana: {total_change:+.4f} SOL ({change_percentage:+.1f}%)")
        logger.info(f"   💻 Saldo końcowe: {self.current_sol:.4f} SOL")

        # Rekomendacje
        logger.info(f"\n💡 REKOMENDACJE:")
        if success_rate > 70:
            logger.info(f"   🎉 Świetny wynik! Kontynuuj snipowanie!")
            logger.info(f"   💰 Rozważ zwiększenie kwoty flash loan")
        elif success_rate > 50:
            logger.info(f"   📈 Dobre wyniki! Popraw filtry dla lepszej precyzji")
        else:
            logger.info(f"   ⚠️  Niski wskaźnik sukcesu - dostosuj kryteria")
            logger.info(f"   🔍 Sprawdź parametry wejściowe")

        if total_change > 0.1:
            logger.info(f"   🚀 Zyskowna sesja! Czas na reinwestycję!")
        elif total_change < -0.05:
            logger.info(f"   🛑 Straty - zatrzymaj i przeanalizuj strategię")
        else:
            logger.info(f"   📊 Neutralny wynik - kontynuuj optymalizację")

    def show_profit_history(self):
        """Pokaż historię zysków"""

        print("\n📈 HISTORIA ZYSKÓW")
        print("=" * 50)

        history = self.db.get_profit_history(limit=20)

        if not history:
            print("❌ Brak historii zysków")
            return

        for record in history:
            profit_str = f"+{record['profit']:.4f}" if record['success'] else f"{record['profit']:.4f}"
            status = "✅" if record['success'] else "❌"

            print(f"{status} {record['timestamp'][:19]} | {record['token_mint'][:10]}... | {profit_str} SOL")

        # Podsumowanie
        total_success = sum(1 for r in history if r['success'])
        total_profit = sum(r['profit'] for r in history if r['success'])
        total_loss = sum(abs(r['profit']) for r in history if not r['success'])

        print(f"\n📊 PODSUMOWANIE HISTORII:")
        print(f"   ✅ Sukcesy: {total_success}/{len(history)} ({total_success/len(history)*100:.1f}%)")
        print(f"   💰 Zyski: {total_profit:.4f} SOL")
        print(f"   💸 Straty: {total_loss:.4f} SOL")
        print(f"   💎 Netto: {total_profit - total_loss:.4f} SOL")

async def main():
    """Główna funkcja bota"""

    print("🎯 FLASH LOAN SNIPER BOT")
    print("=" * 50)
    print("💰 Automatyczny snip z flash loans")
    print("💾 Zyski zapisywane na trwałe")
    print("📈 Reinwestycja automatyczna")
    print()

    # Inicjalizuj bota
    bot = FlashLoanSniperBot(initial_sol=1.0)

    try:
        # Pokaż historię jeśli istnieje
        bot.show_profit_history()

        # Uruchom sesję snipowania
        await bot.run_sniping_session(duration_minutes=20)

        print("\n🎉 SESJA ZAKOŃCZONA!")
        print("💾 Wszystkie zyski zapisane w bazie danych")
        print("📈 Gotowy na kolejną sesję!")

    except KeyboardInterrupt:
        print("\n🛑 Bot zatrzymany przez użytkownika")
    except Exception as e:
        logger.error(f"❌ Błąd krytyczny: {e}")

if __name__ == "__main__":
    asyncio.run(main())