# Parallel Processing Architecture / Architektura Przetwarzania Równoległego

**Owner:** @YourGitHubUsername
**Status:** Final

## 1. English

### 1.1. Overview

To effectively snipe new token pairs, the bot must analyze a high volume of potential candidates in near real-time. Processing tokens sequentially is too slow and will miss opportunities. This document describes the parallel processing architecture designed to analyze multiple tokens concurrently, maximizing throughput and minimizing decision latency.

The core of this architecture is the `TaskPoolManager` implemented in Python.

### 1.2. The Challenge

When a new liquidity pool is created on a DEX, we need to perform a series of I/O-bound checks as quickly as possible:
- Fetch token metadata (RPC call).
- Check holder distribution (RPC call).
- Check social media presence (API call).
- Verify if it's a honeypot (API call).
- Get an organic score (API call).

Doing these sequentially for each new token is a major bottleneck.

### 1.3. The Solution: `TaskPoolManager`

We use a Python-based `TaskPoolManager` (`src/orchestration/task_pool_manager.py`) that leverages `asyncio` to run these analysis tasks in parallel.

#### 1.3.1. Core Components

- **`TaskPoolManager`**: A class that manages a pool of asyncio tasks.
- **`submit_batch(tokens)`**: A method that takes a list of token addresses and creates a concurrent analysis task for each one.
- **`analyze_token(address)`**: An async function that performs the full, multi-step analysis for a single token. This function orchestrates the parallel calls to the various data clients (Helius, Social, Honeypot, etc.).

#### 1.3.2. Workflow

1.  **Batch Ingestion**: The main application loop (or the `EnhancedDataPipeline`) detects a batch of new tokens.
2.  **Task Submission**: It calls `task_pool_manager.submit_batch(list_of_token_addresses)`.
3.  **Concurrent Analysis**: The `TaskPoolManager` creates an `asyncio.Task` for each token. Inside each task, the `analyze_token` function is called.
4.  **Parallel I/O**: `analyze_token` uses `asyncio.gather` to run all the necessary I/O-bound checks (Helius, Twitter, etc.) for its token *concurrently*.
5.  **Decision Synthesis**: Once all data for a token is gathered, it's passed to the Mojo `DataSynthesisEngine` for a final, CPU-bound score calculation and trading decision.
6.  **Result Aggregation**: The `TaskPoolManager` collects the `TradingDecision` for each token and passes them to the `UltimateExecutor`.

#### Example Python Code

```python
# In src/orchestration/task_pool_manager.py
import asyncio

class TaskPoolManager:
    def __init__(self, config, data_clients, synthesis_engine):
        self.pool_size = config.parallel_processing.pool_size
        self.semaphore = asyncio.Semaphore(self.pool_size)
        self.clients = data_clients
        self.synthesis_engine = synthesis_engine

    async def analyze_token(self, token_address: str):
        async with self.semaphore:
            # Step 1: Gather data concurrently
            results = await asyncio.gather(
                self.clients.helius.get_metadata(token_address),
                self.clients.social.get_analysis(token_address),
                self.clients.honeypot.check_token(token_address),
                # ... other checks
            )
            
            # Step 2: Synthesize the data into a single object
            token_data = self._consolidate_results(results)

            # Step 3: Call the Mojo engine for a final decision
            decision = self.synthesis_engine.synthesize_trading_decision(token_data)
            
            return decision

    async def submit_batch(self, token_addresses: list[str]):
        tasks = [self.analyze_token(addr) for addr in token_addresses]
        decisions = await asyncio.gather(*tasks)
        return [d for d in decisions if d.should_trade]

```

### 1.4. Configuration (`config/trading.toml`)

```toml
[parallel_processing]
# Max number of tokens to analyze concurrently.
# This should be tuned based on machine resources and API rate limits.
pool_size = 20 
# Timeout in seconds for the analysis of a single token.
task_timeout_seconds = 15 
```

### 1.5. Performance Targets

- **Throughput**: The system should be able to process at least 50-100 tokens per second, depending on the `pool_size`.
- **Latency**: The end-to-end analysis time for a single token should be under 5 seconds.

---

## 2. Polski

### 2.1. Przegląd

Aby skutecznie "snajpić" nowe pary tokenów, bot musi analizować dużą liczbę potencjalnych kandydatów w czasie zbliżonym do rzeczywistego. Przetwarzanie tokenów sekwencyjnie jest zbyt wolne i prowadzi do utraty okazji. Ten dokument opisuje architekturę przetwarzania równoległego, zaprojektowaną do jednoczesnej analizy wielu tokenów, maksymalizując przepustowość i minimalizując opóźnienia w podejmowaniu decyzji.

Rdzeniem tej architektury jest `TaskPoolManager` zaimplementowany w Pythonie.

### 2.2. Wyzwanie

Gdy na giełdzie DEX tworzona jest nowa pula płynności, musimy jak najszybciej przeprowadzić serię sprawdzeń zależnych od operacji I/O:
- Pobranie metadanych tokena (wywołanie RPC).
- Sprawdzenie dystrybucji posiadaczy (wywołanie RPC).
- Sprawdzenie obecności w mediach społecznościowych (wywołanie API).
- Weryfikacja, czy to nie jest honeypot (wywołanie API).
- Uzyskanie oceny organiczności (wywołanie API).

Wykonywanie tych operacji sekwencyjnie dla każdego nowego tokena jest głównym wąskim gardłem.

### 2.3. Rozwiązanie: `TaskPoolManager`

Używamy opartego na Pythonie `TaskPoolManager` (`src/orchestration/task_pool_manager.py`), który wykorzystuje `asyncio` do równoległego uruchamiania tych zadań analitycznych.

#### 2.3.1. Główne Komponenty

- **`TaskPoolManager`**: Klasa zarządzająca pulą zadań asyncio.
- **`submit_batch(tokens)`**: Metoda, która przyjmuje listę adresów tokenów i tworzy dla każdego z nich współbieżne zadanie analityczne.
- **`analyze_token(address)`**: Funkcja asynchroniczna, która wykonuje pełną, wieloetapową analizę dla pojedynczego tokena. Ta funkcja koordynuje równoległe wywołania do różnych klientów danych (Helius, Social, Honeypot itp.).

#### 2.3.2. Przepływ Pracy

1.  **Przetwarzanie Wsadowe**: Główna pętla aplikacji (lub `EnhancedDataPipeline`) wykrywa partię nowych tokenów.
2.  **Przesłanie Zadań**: Wywołuje `task_pool_manager.submit_batch(list_of_token_addresses)`.
3.  **Analiza Współbieżna**: `TaskPoolManager` tworzy `asyncio.Task` dla każdego tokena. Wewnątrz każdego zadania wywoływana jest funkcja `analyze_token`.
4.  **Równoległe I/O**: `analyze_token` używa `asyncio.gather` do uruchomienia wszystkich niezbędnych sprawdzeń I/O (Helius, Twitter itp.) dla swojego tokena *jednocześnie*.
5.  **Synteza Decyzji**: Po zebraniu wszystkich danych dla tokena, są one przekazywane do `DataSynthesisEngine` w Mojo w celu ostatecznego, obciążającego procesor obliczenia wyniku i podjęcia decyzji handlowej.
6.  **Agregacja Wyników**: `TaskPoolManager` zbiera `TradingDecision` dla każdego tokena i przekazuje je do `UltimateExecutor`.

(Patrz sekcja 1.3 dla przykładu kodu w Pythonie)

### 2.4. Konfiguracja (`config/trading.toml`)

(Patrz sekcja 1.4 dla przykładu konfiguracji)

### 2.5. Cele Wydajnościowe

- **Przepustowość**: System powinien być w stanie przetwarzać co najmniej 50-100 tokenów na sekundę, w zależności od `pool_size`.
- **Opóźnienie**: Czas analizy end-to-end dla pojedynczego tokena powinien być poniżej 5 sekund.
