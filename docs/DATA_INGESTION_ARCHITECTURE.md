# Data Ingestion Architecture / Architektura Pozyskiwania Danych

**Owner:** @YourGitHubUsername
**Status:** Final

## 1. English

### 1.1. Overview

The Data Ingestion Architecture is designed to consume, process, and normalize real-time data from multiple blockchain and off-chain sources. It is a multi-layered system that ensures high throughput, low latency, and data integrity. The core components include direct RPC clients, a Geyser gRPC client for Solana, and various API clients for off-chain data like social media sentiment and honeypot checks.

The goal is to provide a unified, reliable stream of `TokenData` events to the downstream analysis and execution engines.

### 1.2. Core Components

- **Geyser Client (`src/data/geyser_client.py`)**: Connects to a Solana Geyser gRPC stream (e.g., Yellowstone) to subscribe to real-time account, program, and transaction updates. This is the primary source for on-chain events.
- **RPC Clients (`src/data/helius_client.mojo`, `src/data/quicknode_client.mojo`)**: Used for fetching supplementary on-demand data, such as token metadata, historical transactions, or wallet balances. An `RPC Router` (`src/data/rpc_router.py`) manages failover and load balancing between providers.
- **Off-Chain API Clients**:
    - `src/data/social_client.mojo`: Fetches social media sentiment and activity.
    - `src/data/honeypot_client.mojo`: Checks if a token is a honeypot.
    - `src/data/dexscreener_client.mojo`: Fetches price and liquidity data from DEXs.
- **Enhanced Data Pipeline (`src/data/enhanced_data_pipeline.mojo`)**: The central orchestrator that consumes raw events from all sources, normalizes them into a common format, enriches them with additional data, and forwards them to the analysis engines.

### 1.3. Data Flow

1.  **Geyser Subscription**: The `GeyserClient` subscribes to relevant Solana programs (Raydium, Orca, Pump.fun).
2.  **Event Reception**: Raw events (e.g., `Swap`, `AddLiquidity`) are received via the gRPC stream.
3.  **Normalization**: The `EnhancedDataPipeline` receives the raw event and normalizes it into a standardized `TokenUpdate` struct.
4.  **Enrichment**: The pipeline calls out to various RPC and API clients to enrich the `TokenUpdate` with more context:
    - Helius/QuickNode for token metadata.
    - DexScreener for initial price/liquidity.
    - SocialClient for sentiment scores.
    - HoneypotClient for safety checks.
5.  **Synthesis**: The enriched data is packaged into a comprehensive `TokenData` object.
6.  **Forwarding**: The `TokenData` object is passed to the `DataSynthesisEngine` for final analysis and decision-making.

### 1.4. Key Technologies

- **gRPC (Geyser)**: For high-performance, low-latency streaming of on-chain data.
- **Asyncio (Python)**: The `GeyserClient` and `TaskPoolManager` use asyncio for concurrent I/O operations.
- **Mojo**: Used for performance-critical data processing and normalization in the `EnhancedDataPipeline`.
- **Rust**: Provides shared, thread-safe components like the `PortfolioManager`.

### 1.5. Configuration (`config/trading.toml`)

```toml
[geyser]
endpoint = "grpc.solana.mainnet.rpc.helius.xyz:443" # Example, use your own
enabled = true

[rpc_providers.helius]
api_key = "${HELIUS_API_KEY}"
# ... other settings

[rpc_providers.quicknode]
api_key = "${QUICKNODE_API_KEY}"
# ... other settings
```

### 1.6. Prometheus Metrics

- `data_ingestion_events_received_total`: Counter - Raw events received by source (Geyser, API, etc.).
- `data_ingestion_events_processed_total`: Counter - Normalized events successfully processed.
- `data_ingestion_events_dropped_total`: Counter - Events dropped due to errors or filtering.
- `data_ingestion_pipeline_latency_seconds`: Histogram - End-to-end latency from event reception to forwarding.
- `geyser_client_connection_status`: Gauge - Connection status of the Geyser client (1 for connected, 0 for disconnected).

---

## 2. Polski

### 2.1. Przegląd

Architektura Pozyskiwania Danych została zaprojektowana do konsumowania, przetwarzania i normalizowania danych w czasie rzeczywistym z wielu źródeł on-chain i off-chain. Jest to wielowarstwowy system, który zapewnia wysoką przepustowość, niskie opóźnienia i integralność danych. Główne komponenty obejmują bezpośrednich klientów RPC, klienta gRPC Geyser dla Solany oraz różnych klientów API dla danych off-chain, takich jak nastroje w mediach społecznościowych i kontrole honeypot.

Celem jest dostarczenie zunifikowanego, niezawodnego strumienia zdarzeń `TokenData` do silników analitycznych i wykonawczych.

### 2.2. Główne Komponenty

- **Klient Geyser (`src/data/geyser_client.py`)**: Łączy się ze strumieniem gRPC Geyser Solany (np. Yellowstone), aby subskrybować aktualizacje kont, programów i transakcji w czasie rzeczywistym. Jest to główne źródło zdarzeń on-chain.
- **Klienci RPC (`src/data/helius_client.mojo`, `src/data/quicknode_client.mojo`)**: Używani do pobierania dodatkowych danych na żądanie, takich jak metadane tokenów, historyczne transakcje czy salda portfeli. `RPC Router` (`src/data/rpc_router.py`) zarządza przełączaniem awaryjnym i równoważeniem obciążenia między dostawcami.
- **Klienci API Off-Chain**:
    - `src/data/social_client.mojo`: Pobiera nastroje i aktywność w mediach społecznościowych.
    - `src/data/honeypot_client.mojo`: Sprawdza, czy token jest honeypotem.
    - `src/data/dexscreener_client.mojo`: Pobiera dane o cenie i płynności z giełd zdecentralizowanych (DEX).
- **Rozszerzony Potok Danych (`src/data/enhanced_data_pipeline.mojo`)**: Centralny orkiestrator, który konsumuje surowe zdarzenia ze wszystkich źródeł, normalizuje je do wspólnego formatu, wzbogaca o dodatkowe dane i przekazuje do silników analitycznych.

### 2.3. Przepływ Danych

1.  **Subskrypcja Geyser**: `GeyserClient` subskrybuje odpowiednie programy Solany (Raydium, Orca, Pump.fun).
2.  **Odbiór Zdarzeń**: Surowe zdarzenia (np. `Swap`, `AddLiquidity`) są odbierane przez strumień gRPC.
3.  **Normalizacja**: `EnhancedDataPipeline` odbiera surowe zdarzenie i normalizuje je do standardowej struktury `TokenUpdate`.
4.  **Wzbogacanie**: Potok wywołuje różnych klientów RPC i API, aby wzbogacić `TokenUpdate` o dodatkowy kontekst:
    - Helius/QuickNode dla metadanych tokena.
    - DexScreener dla początkowej ceny/płynności.
    - SocialClient dla ocen nastrojów.
    - HoneypotClient dla kontroli bezpieczeństwa.
5.  **Synteza**: Wzbogacone dane są pakowane w kompleksowy obiekt `TokenData`.
6.  **Przekazanie**: Obiekt `TokenData` jest przekazywany do `DataSynthesisEngine` w celu ostatecznej analizy i podjęcia decyzji.

### 2.4. Kluczowe Technologie

- **gRPC (Geyser)**: Dla wysokowydajnego strumieniowania danych on-chain z niskim opóźnieniem.
- **Asyncio (Python)**: `GeyserClient` i `TaskPoolManager` używają asyncio do współbieżnych operacji I/O.
- **Mojo**: Używane do krytycznego pod względem wydajności przetwarzania i normalizacji danych w `EnhancedDataPipeline`.
- **Rust**: Dostarcza współdzielone, bezpieczne wątkowo komponenty, takie jak `PortfolioManager`.

### 2.5. Konfiguracja (`config/trading.toml`)

(Patrz sekcja 1.5 dla przykładu konfiguracji)

### 2.6. Metryki Prometheus

- `data_ingestion_events_received_total`: Counter - Surowe zdarzenia odebrane wg źródła (Geyser, API, itp.).
- `data_ingestion_events_processed_total`: Counter - Znormalizowane zdarzenia pomyślnie przetworzone.
- `data_ingestion_events_dropped_total`: Counter - Zdarzenia odrzucone z powodu błędów lub filtrowania.
- `data_ingestion_pipeline_latency_seconds`: Histogram - Opóźnienie end-to-end od odbioru zdarzenia do przekazania.
- `geyser_client_connection_status`: Gauge - Status połączenia klienta Geyser (1 - połączony, 0 - rozłączony).