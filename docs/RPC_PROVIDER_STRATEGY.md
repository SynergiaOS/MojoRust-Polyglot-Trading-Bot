# RPC Provider Strategy / Strategia Dostawców RPC

**Owner:** @YourGitHubUsername
**Status:** Final

## 1. English

### 1.1. Overview

A robust and resilient RPC (Remote Procedure Call) strategy is essential for reliable trading bot operation. This document outlines our multi-layered approach to RPC providers, focusing on performance, cost-efficiency, and high availability. We use a combination of primary, secondary, and archive providers, managed by a central `RPC Router`.

### 1.2. The Problem

Relying on a single RPC provider introduces a single point of failure. Providers can experience downtime, performance degradation, or rate limiting, which can cripple the bot's ability to analyze opportunities and execute trades.

### 1.3. Our Strategy: Tiered Routing & Failover

We employ a tiered system of RPC providers, managed by the `RPC Router` (`src/data/rpc_router.py`):

- **Primary Provider (e.g., Helius)**: Used for latency-sensitive, high-throughput operations like fetching real-time account states and submitting transactions. Typically the highest performance and most expensive provider.
- **Secondary Provider (e.g., QuickNode)**: Acts as a hot-standby. The `RPC Router` automatically fails over to the secondary if the primary provider becomes unhealthy (high latency, errors).
- **Archive Provider (e.g., public RPC)**: A best-effort, low-cost provider used for non-critical, background tasks like fetching historical data. This minimizes costs on the premium providers.

### 1.4. The RPC Router (`src/data/rpc_router.py`)

This Python module is the core of our strategy. Its responsibilities include:

- **Health Checks**: Periodically pings each provider's health check endpoint to measure latency and availability.
- **Dynamic Routing**: Directs RPC calls to the appropriate provider based on the current health status and the type of request (e.g., `send_transaction` goes to primary, `get_block` might go to secondary).
- **Automatic Failover**: If the primary provider fails, it seamlessly redirects traffic to the secondary. It will automatically switch back once the primary is healthy again.
- **Metrics Export**: Exposes Prometheus metrics for monitoring the health and performance of each provider.

#### Example Logic (Python)

```python
# In src/data/rpc_router.py

class RPCRouter:
    def __init__(self, config):
        self.primary = RPCClient(config.primary)
        self.secondary = RPCClient(config.secondary)
        self.archive = RPCClient(config.archive)
        # ... health check state ...

    async def perform_health_checks(self):
        # ... logic to ping each provider ...

    async def get_best_provider(self):
        if await self.primary.is_healthy():
            return self.primary
        elif await self.secondary.is_healthy():
            return self.secondary
        else:
            return self.archive # Last resort

    async def send_transaction(self, txn):
        provider = await self.get_best_provider()
        return await provider.send_transaction(txn)
```

### 1.5. Configuration (`config/trading.toml`)

The routing strategy is configured in `trading.toml`.

```toml
[rpc_providers]
primary = "helius"
secondary = "quicknode"
archive = "public" # A generic public endpoint

[rpc_providers.routing]
health_check_interval_seconds = 10
latency_threshold_ms = 500
error_rate_threshold = 0.1 # 10% error rate

[rpc_providers.helius]
api_key = "${HELIUS_API_KEY}"
# ...

[rpc_providers.quicknode]
api_key = "${QUICKNODE_API_KEY}"
# ...
```

### 1.6. Prometheus Metrics

- `rpc_provider_health_status`: Gauge - Health of each provider (1 for healthy, 0 for unhealthy).
- `rpc_provider_latency_ms`: Gauge - Average latency for each provider.
- `rpc_provider_error_rate`: Gauge - Rate of failed requests for each provider.
- `rpc_active_provider`: Info Gauge - Indicates which provider is currently active (primary/secondary).

---

## 2. Polski

### 2.1. Przegląd

Solidna i odporna na awarie strategia RPC (Remote Procedure Call) jest niezbędna do niezawodnego działania bota handlowego. Ten dokument opisuje nasze wielowarstwowe podejście do dostawców RPC, koncentrując się na wydajności, efektywności kosztowej i wysokiej dostępności. Używamy kombinacji dostawców głównych, zapasowych i archiwalnych, zarządzanych przez centralny `RPC Router`.

### 2.2. Problem

Poleganie na jednym dostawcy RPC wprowadza pojedynczy punkt awarii. Dostawcy mogą doświadczać przestojów, degradacji wydajności lub limitów zapytań, co może sparaliżować zdolność bota do analizowania okazji i wykonywania transakcji.

### 2.3. Nasza Strategia: Warstwowy Routing i Failover

Stosujemy warstwowy system dostawców RPC, zarządzany przez `RPC Router` (`src/data/rpc_router.py`):

- **Dostawca Główny (np. Helius)**: Używany do operacji wrażliwych na opóźnienia i o wysokiej przepustowości, takich jak pobieranie stanu kont w czasie rzeczywistym i wysyłanie transakcji. Zazwyczaj jest to dostawca o najwyższej wydajności i najwyższych kosztach.
- **Dostawca Zapasowy (np. QuickNode)**: Działa jako gorąca rezerwa. `RPC Router` automatycznie przełącza się na dostawcę zapasowego, jeśli główny dostawca staje się niedostępny (wysokie opóźnienia, błędy).
- **Dostawca Archiwalny (np. publiczne RPC)**: Dostawca "best-effort" o niskich kosztach, używany do niekrytycznych zadań w tle, takich jak pobieranie danych historycznych. Minimalizuje to koszty u dostawców premium.

### 2.4. RPC Router (`src/data/rpc_router.py`)

Ten moduł w Pythonie jest rdzeniem naszej strategii. Jego obowiązki obejmują:

- **Kontrola Kondycji**: Okresowo wysyła zapytania do punktów kontroli kondycji każdego dostawcy, aby mierzyć opóźnienia i dostępność.
- **Dynamiczny Routing**: Kieruje wywołania RPC do odpowiedniego dostawcy na podstawie aktualnego stanu kondycji i typu żądania (np. `send_transaction` idzie do głównego, `get_block` może iść do zapasowego).
- **Automatyczny Failover**: Jeśli główny dostawca zawiedzie, płynnie przekierowuje ruch do dostawcy zapasowego. Automatycznie przełączy się z powrotem, gdy główny dostawca odzyska sprawność.
- **Eksport Metryk**: Udostępnia metryki Prometheus do monitorowania kondycji i wydajności każdego dostawcy.

(Patrz sekcja 1.4 dla przykładu logiki w Pythonie)

### 2.5. Konfiguracja (`config/trading.toml`)

Strategia routingu jest konfigurowana w `trading.toml`.

(Patrz sekcja 1.5 dla przykładu konfiguracji)

### 2.6. Metryki Prometheus

- `rpc_provider_health_status`: Gauge - Kondycja każdego dostawcy (1 dla zdrowego, 0 dla niezdrowego).
- `rpc_provider_latency_ms`: Gauge - Średnie opóźnienie dla każdego dostawcy.
- `rpc_provider_error_rate`: Gauge - Wskaźnik nieudanych żądań dla każdego dostawcy.
- `rpc_active_provider`: Info Gauge - Wskazuje, który dostawca jest aktualnie aktywny (główny/zapasowy).
