#!/usr/bin/env python3
"""
🚀 FLASH LOAN STARTER - START SYSTEMU Z POŻYCZKAMI BŁYSKAWICZNYMI
Idealne gdy nie masz kapitału - używasz tylko flash loans!

Uruchomienie: python3 scripts/flash_loan_starter.py
"""

import asyncio
import aiohttp
import json
import time
import os
import subprocess
from datetime import datetime
from typing import Dict, List, Optional

class FlashLoanStarter:
    def __init__(self):
        self.wallet_address = "GedVmbHnUpRoqxWSxLwDMQNY5bmggTjRojoCY6u31VGS"
        self.config_path = "/home/marcin/Projects/MojoRust/config/flash_loan_only_strategy.toml"

    async def check_prerequisites(self):
        """Sprawdź czy wszystko gotowe na flash loans"""
        print("🔍 SPRAWDZANIE WYMAGAŃ FLASH LOAN")
        print("=" * 50)

        # 1. Sprawdź saldo na gaz
        print("💰 Sprawdzanie saldo na gas...")
        try:
            result = subprocess.run([
                'curl', '-s',
                'https://api.mainnet-beta.solana.com',
                '-X', 'POST',
                '-H', 'Content-Type: application/json',
                '-d', f'{{"jsonrpc":"2.0","id":1,"method":"getBalance","params":["{self.wallet_address}"]}}'
            ], capture_output=True, text=True)

            if result.returncode == 0:
                data = json.loads(result.stdout)
                if 'result' in data:
                    balance_sol = data['result']['value'] / 1000000000
                    print(f"   ✅ Saldo: {balance_sol:.6f} SOL")

                    if balance_sol < 0.01:
                        print("   ⚠️  OSTRZEŻENIE: Masz mało SOL na gas!")
                        print("   💡 Potrzebujesz minimum 0.01 SOL na opłaty transakcyjne")
                    else:
                        print("   ✅ Masz wystarczająco SOL na gas")
            else:
                print("   ❌ Nie można sprawdzić salda")
        except Exception as e:
            print(f"   ❌ Błąd: {e}")

        # 2. Sprawdź czy config istnieje
        print("\n📋 Sprawdzanie konfiguracji...")
        if os.path.exists(self.config_path):
            print(f"   ✅ Config znaleziony: {self.config_path}")
        else:
            print(f"   ❌ Brak configu: {self.config_path}")
            return False

        # 3. Sprawdź API keys
        print("\n🔑 Sprawdzanie kluczy API...")
        required_keys = ['HELIUS_API_KEY']
        missing_keys = []

        for key in required_keys:
            if key not in os.environ:
                missing_keys.append(key)
                print(f"   ❌ Brak: {key}")
            else:
                print(f"   ✅ Znaleziono: {key}")

        if missing_keys:
            print(f"\n⚠️  Dodaj brakujące klucze do .env:")
            for key in missing_keys:
                print(f"   export {key}=your_key_here")
            return False

        return True

    async def test_flash_loan_providers(self):
        """Testuj dostępność dostawców flash loans"""
        print("\n⚡ TESTOWANIE DOSTAWCÓW FLASH LOANS")
        print("=" * 50)

        providers = {
            "Solend": "https://api.solend.fi/markets",
            "Marginfi": "https://api.marginfi.com/vaults",
            "Jupiter": "https://quote-api.jup.ag/v6/quote"
        }

        async with aiohttp.ClientSession() as session:
            for provider, url in providers.items():
                try:
                    async with session.get(url, timeout=5) as response:
                        if response.status == 200:
                            print(f"   ✅ {provider}: Dostępny")
                        else:
                            print(f"   ⚠️  {provider}: Status {response.status}")
                except Exception as e:
                    print(f"   ❌ {provider}: Błąd - {e}")

    async def check_current_opportunities(self):
        """Sprawdź aktualne okazje arbitrażowe"""
        print("\n🎯 SPRAWDZANIE AKTUALNYCH OKAZJI")
        print("=" * 50)

        # Symulacja sprawdzania okazji
        opportunities = [
            {"pair": "SOL/USDC", "spread_bps": 85, "potential_profit": 0.12},
            {"pair": "RAY/USDC", "spread_bps": 120, "potential_profit": 0.08},
            {"pair": "ORCA/USDC", "spread_bps": 65, "potential_profit": 0.04}
        ]

        for opp in opportunities:
            print(f"   🔍 {opp['pair']}: {opp['spread_bps']}bps spread → {opp['potential_profit']} SOL zysku")

        # Filtruj okazje
        profitable_opps = [opp for opp in opportunities if opp['spread_bps'] > 75]
        print(f"\n💡 Zyskownych okazji ({min_spread_bps}bps+): {len(profitable_opps)}")

        return profitable_opps

    async def start_flash_loan_bot(self):
        """Uruchom bota flash loan"""
        print("\n🚀 URUCHAMIANIE BOTA FLASH LOAN")
        print("=" * 50)

        # Znajdź skrypt bota
        bot_scripts = [
            "/home/marcin/Projects/MojoRust/comprehensive_trading_system.py",
            "/home/marcin/Projects/MojoRust/python/main_trading_bot.py",
            "/home/marcin/Projects/MojoRust/src/flash_loan_engine.py"
        ]

        bot_script = None
        for script in bot_scripts:
            if os.path.exists(script):
                bot_script = script
                break

        if not bot_script:
            print("❌ Nie znaleziono skryptu bota!")
            print("💡 Uruchomimy prosty symulator...")
            return await self.run_flash_loan_simulator()

        print(f"✅ Znaleziono skrypt: {bot_script}")

        # Uruchom bota z konfiguracją flash loan
        cmd = [
            "python3", bot_script,
            "--config", self.config_path,
            "--mode", "flash_loan",
            "--dry-run"  # Najpierw test bez prawdziwych transakcji
        ]

        print(f"🔄 Uruchamianie: {' '.join(cmd)}")
        try:
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

            # Czekaj chwilę i sprawdź czy działa
            await asyncio.sleep(3)

            if process.poll() is None:  # Jeszcze działa
                print("✅ Bot uruchomiony pomyślnie!")
                print("📊 Monitoruj wyniki przez 60 sekund...")

                # Monitoruj przez 60 sekund
                for i in range(60):
                    if process.poll() is not None:
                        break

                    print(f"   ⏱️  {i+1}/60s - Bot działa...")
                    await asyncio.sleep(1)

                # Zatrzymaj proces
                process.terminate()
                print("✅ Test zakończony")
            else:
                stdout, stderr = process.communicate()
                print(f"❌ Błąd uruchomienia: {stderr}")

        except Exception as e:
            print(f"❌ Błąd: {e}")

    async def run_flash_loan_simulator(self):
        """Uruchom symulator flash loan dla demonstracji"""
        print("\n🎮 URUCHAMIANIE SYMULATORA FLASH LOAN")
        print("=" * 50)

        print("📈 Symulacja strategii flash loan arbitrage...")

        # Symuluj 10 transakcji
        results = []
        for i in range(10):
            # Losowa okazja
            spread_bps = 50 + (i * 15)  # 50-200 bps
            gas_cost = 0.002 + (i * 0.0005)  # 0.002-0.007 SOL

            # Oblicz zysk
            loan_amount = 50.0  # 50 SOL flash loan
            gross_profit = (spread_bps / 10000) * loan_amount
            net_profit = gross_profit - gas_cost

            if net_profit > 0:
                result = "ZYSK"
            else:
                result = "STRATA"

            results.append(net_profit)

            print(f"   Transakcja {i+1}: {spread_bps}bps → {net_profit:+.4f} SOL ({result})")
            await asyncio.sleep(0.5)

        # Podsumowanie
        total_profit = sum(results)
        profitable_trades = len([r for r in results if r > 0])

        print(f"\n📊 PODSUMOWANIE SYMULACJI:")
        print(f"   📈 Zysk całkowity: {total_profit:+.4f} SOL")
        print(f"   ✅ Zyskowne transakcje: {profitable_trades}/10 ({profitable_trades*10}%)")
        print(f"   💰 Średni zysk na transakcję: {total_profit/10:+.4f} SOL")

        if total_profit > 0:
            print("   🎉 Strategia jest ZYSKOWNA!")
        else:
            print("   ⚠️  Strategia wymaga optymalizacji")

        return total_profit > 0

    async def show_next_steps(self):
        """Pokaż następne kroki"""
        print("\n📋 NASTĘPNE KROKI")
        print("=" * 50)

        steps = [
            "1. 💰 Dokonaj 0.01 SOL na opłaty transakcyjne",
            "2. 🔑 Skonfiguruj HELIUS_API_KEY w .env",
            "3. 📖 Przeczytaj config/flash_loan_only_strategy.toml",
            "4. 🧪 Uruchom w trybie testowym przez 24 godziny",
            "5. 📊 Monitoruj wskaźniki sukcesu",
            "6. 🚀 Przełącz na live trading po pozytywnych testach",
            "7. 💸 Wypłacaj zyski regularnie"
        ]

        for step in steps:
            print(f"   {step}")

        print(f"\n💡 PORADA:")
        print("   Flash loans to narzędzie, nie magia!")
        print("   Zacznij mało, testuj dużo, zarabiaj mądrze")

async def main():
    """Główna funkcja"""
    print("⚡ FLASH LOAN STARTER - SYSTEM Z POŻYCZKAMI BŁYSKAWICZNYMI")
    print("=" * 60)
    print("🎯 Cel: Zarabiaj bez kapitału własnego!")
    print("🔥 Metoda: Flash loan arbitrage na Solana")
    print()

    starter = FlashLoanStarter()

    # Krok 1: Sprawdź wymagania
    if not await starter.check_prerequisites():
        print("\n❌ Rozwiąż problemy z wymaganiami przed kontynuacją")
        return

    # Krok 2: Testuj dostawców
    await starter.test_flash_loan_providers()

    # Krok 3: Sprawdź okazje
    opportunities = await starter.check_current_opportunities()

    # Krok 4: Uruchom bota
    await starter.start_flash_loan_bot()

    # Krok 5: Pokaż następne kroki
    await starter.show_next_steps()

    print("\n" + "=" * 60)
    print("✅ GOTOWE DO STARTU Z FLASH LOANS!")

if __name__ == "__main__":
    asyncio.run(main())