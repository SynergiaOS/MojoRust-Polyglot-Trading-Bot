# 🚀 WDRÓŻ TERAZ - Przewodnik Szybkiego Wdrożenia
## Server Produkcyjny: 38.242.239.150

### ⚡ Szybki Start (Komendy Copy-Paste)

#### Lista Kontrolna Przed Wdrożeniem
- ✅ Konto Infisical: https://app.infisical.com
- ✅ Klucz API Helius
- ✅ Endpoint RPC QuickNode
- ✅ Portfel Solana gotowy
- ✅ Dostęp SSH do 38.242.239.150

---

## Krok 1: Połącz się z Serverem Produkcyjnym

```bash
# Połącz się z swoim VPS
ssh root@38.242.239.150

# Po połączeniu, zaktualizuj system
apt update && apt upgrade -y
```

---

## Krok 2: Uruchom Automatyczną Konfigurację VPS

```bash
# Utwórz katalog projektu
mkdir -p ~/mojo-trading-bot
cd ~/mojo-trading-bot

# Pobierz i uruchom skrypt konfiguracyjny VPS
curl -fsSL https://raw.githubusercontent.com/SynergiaOS/MojoRust/main/scripts/vps_setup.sh | bash

# Załaduj zmienne środowiskowe
source ~/.bashrc
```

**Skrypt VPS setup zainstaluje:**
- ✅ Mojo 24.4+
- ✅ Rust 1.70+
- ✅ Infisical CLI
- ✅ Docker & Docker Compose
- ✅ Konfigurację firewalla
- ✅ Konto użytkownika trading

---

## Krok 3: Klonuj Repozytorium

```bash
# Klonuj projekt
git clone https://github.com/SynergiaOS/MojoRust.git .

# Nadaj uprawnienia wykonywania skryptom
chmod +x scripts/*.sh

# Utwórz niezbędne katalogi
mkdir -p logs data secrets
```

---

## Krok 4: Konfiguracja Infisical

```bash
# Zaloguj się do Infisical
infisical login

# Zainicjalizuj projekt Infisical (tworzy .infisical.json)
infisical init
# Ustaw workspaceId i defaultEnvironment when prompted
# Lub listuj sekrety jawnie:
infisical secrets list --projectId <PROJECT_ID> --env production

# Testuj połączenie
infisical secrets list --projectId <PROJECT_ID> --env production
```

---

## Krok 5: Konfiguracja Środowiska

```bash
# Skopiuj szablon środowiska produkcyjnego
cp .env.production.example .env

# Edytuj konfigurację (BARDZO WAŻNE - zacznij od PAPER TRADING!)
nano .env
```

**Krytyczne ustawienia w .env:**
```bash
# Zacznij od trybu PAPER trading
EXECUTION_MODE=paper

# Konfiguracja servera
SERVER_HOST=38.242.239.150
SERVER_PORT=8080

# Parametry tradingowe (konserwatywny start)
INITIAL_CAPITAL=1.0
MAX_POSITION_SIZE=0.10
MAX_DRAWDOWN=0.15

# Klucze API (pobierz z Infisical lub ustaw ręcznie)
HELIUS_API_KEY=twój_klucz_helius
QUICKNODE_RPC_URL=twój_url_quicknode
```

---

## Krok 6: Wdróż Bota Tradingowego

```bash
# Uruchom skrypt wdrożenia
./scripts/deploy_with_filters.sh

# Lub uruchom bezpośrednio z Mojo
mojo run src/main.mojo --mode=paper
```

**Skrypt wdrożenia:**
- ✅ Zbuduje moduły Rust FFI
- ✅ Skompiluje kod Mojo
- ✅ Zainicjalizuje bazę danych
- ✅ Uruchomi usługi monitorowania
- ✅ Skonfiguruje health checks

---

## Krok 7: Weryfikacja Wdrożenia

```bash
# Sprawdź czy bot działa
ps aux | grep mojo

# Oglądaj logi w czasie rzeczywistym
tail -f logs/trading-bot-$(date +%Y%m%d).log

# Sprawdź status API
curl http://localhost:8080/api/health

# Zobacz metryki wydajności
curl http://localhost:8080/api/metrics
```

---

## Krok 8: Monitorowanie i Zarządzanie

```bash
# Dashboard statusu bota
curl http://localhost:8080/api/status

# Ostatnie transakcje
curl http://localhost:8080/api/trades/recent

# Podsumowanie wydajności
curl http://localhost:8080/api/performance/summary

# Zatrzymaj bota (gracefully)
curl -X POST http://localhost:8080/api/stop

# Awaryjne zatrzymanie
pkill -f "mojo run"
```

---

## 🚨 Procedury Awaryjne

### Awaryjne Zatrzymanie
```bash
# Natychmiastowe zatrzymanie
pkill -9 mojo

# Zatrzymaj wszystkie usługi
docker-compose down

# Wyłącz trading (zachowaj monitorowanie)
curl -X POST http://localhost:8080/api/disable-trading
```

### Restart Usług
```bash
# Restart bota
./scripts/restart_bot.sh

# Restart monitorowania
docker-compose restart monitoring

# Pełny restart
./scripts/deploy_with_filters.sh --restart
```

---

## 🔧 Komendy Utrzymania

### Codzienny Health Check
```bash
# Zdrowie systemu
./scripts/server_health.sh

# Sprawdź logi pod kątem błędów
grep -i error logs/trading-bot-*.log | tail -20

# Sprawdź użycie zasobów
htop

# Miejsce na dysku
df -h
```

### Aktualizacje
```bash
# Zaktualizuj kod
git pull origin main

# Wdróż ponownie
./scripts/deploy_with_filters.sh

# Zaktualizuj zależności
./scripts/update_dependencies.sh
```

---

## 📊 URL-e Monitorowania

Otwórz te URL-e w przeglądarce:
- **Dashboard Bota**: http://38.242.239.150:8080
- **Metryki**: http://38.242.239.150:9090 (Prometheus)
- **Grafana**: http://38.242.239.150:3000 (admin/admin)
- **Health Check**: http://38.242.239.150:8080/api/health

---

## 🆘 Rozwiązywanie Problemów

### Bot Nie Startuje
```bash
# Sprawdź logi
tail -f logs/trading-bot-*.log

# Sprawdź konfigurację
./scripts/validate_config.sh

# Sprawdź zależności
which mojo && which rustc && which infisical
```

### Problemy z Połączeniem API
```bash
# Testuj Infisical
infisical secrets list

# Testuj API Helius
curl -H "Authorization: Bearer $HELIUS_API_KEY" \
     https://api.helius.xyz/v0/tokens/addresses

# Testuj QuickNode
curl -X POST -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"getSlot"}' \
     $QUICKNODE_RPC_URL
```

### Problemy z Wydajnością
```bash
# Sprawdź zasoby systemowe
free -h
df -h
iostat 1 5

# Sprawdź procesy bota
ps aux | grep -E "(mojo|rust)"

# Profiluj wydajność
./scripts/profile_bot.sh
```

---

## 🎯 Następne Kroki

### Gdy Paper Trading jest Stabilny:
1. **Przełącz na Live Trading** (edytuj `.env`):
   ```bash
   EXECUTION_MODE=live
   INITIAL_CAPITAL=10.0  # Zwiększaj stopniowo
   ```

2. **Włącz Alerty**:
   ```bash
   ENABLE_ALERTS=true
   ALERT_EMAIL=twój@email.com
   ```

3. **Skaluj w Górę**:
   - Dodaj więcej strategii
   - Zwiększ rozmiary pozycji
   - Dodaj więcej par

---

## 📞 Wsparcie

- **Dokumentacja**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **Infisical**: https://app.infisical.com
- **Repozytorium**: https://github.com/SynergiaOS/MojoRust
- **Problemy**: https://github.com/SynergiaOS/MojoRust/issues

---

**⚠️ WAŻNE**: Zawsze zaczynaj od trybu PAPER trading. Monitoruj przez co najmniej 24 godziny przed przełączeniem na LIVE trading z prawdziwymi środkami.

**🔒 BEZPIECZEŃSTWO**: Nigdy nie udostępniaj pliku `.env` ani kluczy API. Używaj Infisical do bezpiecznego zarządzania sekretami.