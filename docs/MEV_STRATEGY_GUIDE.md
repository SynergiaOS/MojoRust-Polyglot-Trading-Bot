# MEV Strategy Guide / Przewodnik po Strategiach MEV

**Owner:** @YourGitHubUsername
**Status:** Proposed

## 1. English

### 1.1. Overview

MEV (Maximal Extractable Value) refers to the profit a block producer can make through their ability to arbitrarily include, exclude, or reorder transactions within the blocks they produce. While often seen as a negative force, we can leverage MEV opportunities ethically, primarily through Jito-Solana integration for priority fees (tips) and front-running protection.

This guide outlines our strategy for integrating with Jito to improve trade execution and capture MEV.

### 1.2. Core Concepts

- **Jito Block Engine**: A replacement for the standard Solana validator client that allows for a more efficient and democratic MEV extraction process.
- **Bundles**: A set of transactions that are executed sequentially and atomically, as if they were one transaction. This is the primary mechanism for front-running and arbitrage.
- **Tips**: Users can pay a "tip" to the Jito validator to have their transaction included and executed faster. This is crucial for time-sensitive trades like sniping.

### 1.3. Our MEV Strategy

Our strategy is twofold: defensive and offensive.

#### 1.3.1. Defensive: Faster, More Reliable Execution

For all our standard trades (sniping, momentum), we will use Jito's `send_transaction` endpoint with a tip.

- **Purpose**: To ensure our transactions are prioritized by the block producer, increasing the likelihood of successful execution and reducing the chance of being front-run by others.
- **Mechanism**:
    1. When the bot decides to execute a trade, it calculates a dynamic tip based on network congestion and trade urgency.
    2. It sends the transaction to the Jito Block Engine's RPC endpoint instead of the standard Solana RPC.
- **Module**: The logic will be integrated into `src/execution/ultimate_executor.mojo`.

#### 1.3.2. Offensive: Sandwich Attacks (Proposed, High-Risk)

A sandwich attack is a form of front-running where we see a large pending trade and place our own trades *before* and *after* it to profit from the price impact.

- **Example Flow**:
    1. Monitor the Jito mempool for large pending swaps (e.g., someone is buying $100k of `MY_TOKEN`).
    2. **Front-run**: Submit a bundle where our first transaction buys `MY_TOKEN` just before the large trade.
    3. The large trade executes, pushing the price of `MY_TOKEN` up.
    4. **Back-run**: Our second transaction in the bundle sells `MY_TOKEN` at the new, higher price for a profit.
- **Implementation**: This would require a dedicated "MEV Bot" module that constantly scans the mempool and constructs these highly complex bundles. This is a future consideration and not in the initial scope.

### 1.4. Jito Integration

- **Jito RPC Endpoint**: We will use the dedicated RPC endpoint provided by Jito for sending transactions and bundles. This will be configured via `.env`.
- **FFI for Bundles**: Since bundle creation is complex, it will likely be implemented in a Rust module (`rust-modules/src/mev/jito.rs`) and exposed via FFI.

### 1.5. Configuration

#### `.env.example`
```
# Jito Integration for MEV
JITO_ENABLED=true
JITO_ENDPOINT="https://mainnet.block-engine.jito.wtf/api/v1"
JITO_TIP_ACCOUNT="96gYZGLnJYVFmbjzopPSU6QiEV5fGq5vLxtVfLM5wgC4" # Jito's tip account
JITO_DEFAULT_TIP_LAMPORTS=10000
JITO_MAX_TIP_LAMPORTS=100000
```

#### `config/trading.toml`
```toml
[mev]
# Strategy for calculating the tip. Can be "fixed" or "dynamic".
tip_strategy = "dynamic"
dynamic_tip_multiplier = 1.2 # Multiplies a base fee estimate
```

### 1.6. Risks

- **Financial Risk**: Tips are an additional cost. If not managed carefully, they can eat into profits. Dynamic tip calculation must be robust.
- **Complexity**: MEV strategies, especially offensive ones, are extremely complex and can fail in many ways, leading to lost funds.
- **Ethical Considerations**: While we are focusing on "ethical" MEV (priority fees), offensive strategies like sandwich attacks are controversial.

---

## 2. Polski

### 2.1. Przegląd

MEV (Maximal Extractable Value) odnosi się do zysku, jaki producent bloku może osiągnąć dzięki swojej zdolności do dowolnego włączania, wykluczania lub zmiany kolejności transakcji w produkowanych przez siebie blokach. Chociaż często postrzegane jako siła negatywna, możemy wykorzystywać możliwości MEV w sposób etyczny, głównie poprzez integrację z Jito-Solana w celu uzyskania opłat priorytetowych (napiwków) i ochrony przed front-runningiem.

Ten przewodnik opisuje naszą strategię integracji z Jito w celu poprawy realizacji transakcji i przechwytywania MEV.

### 2.2. Główne Koncepcje

- **Jito Block Engine**: Zamiennik standardowego klienta walidatora Solana, który pozwala na bardziej wydajny i demokratyczny proces ekstrakcji MEV.
- **Pakiety (Bundles)**: Zestaw transakcji, które są wykonywane sekwencyjnie i atomowo, tak jakby były jedną transakcją. Jest to główny mechanizm do front-runningu i arbitrażu.
- **Napiwki (Tips)**: Użytkownicy mogą zapłacić "napiwek" walidatorowi Jito, aby ich transakcja została włączona i wykonana szybciej. Jest to kluczowe dla transakcji wrażliwych na czas, takich jak sniping.

### 2.3. Nasza Strategia MEV

Nasza strategia jest dwojaka: defensywna i ofensywna.

#### 2.3.1. Defensywna: Szybsza, Bardziej Niezawodna Realizacja

Dla wszystkich naszych standardowych transakcji (sniping, momentum) będziemy używać punktu końcowego `send_transaction` Jito z napiwkiem.

- **Cel**: Zapewnienie, że nasze transakcje są priorytetyzowane przez producenta bloku, co zwiększa prawdopodobieństwo pomyślnej realizacji i zmniejsza szansę na bycie ofiarą front-runningu przez innych.
- **Mechanizm**:
    1. Gdy bot zdecyduje się na wykonanie transakcji, oblicza dynamiczny napiwek na podstawie zatłoczenia sieci i pilności transakcji.
    2. Wysyła transakcję do punktu końcowego RPC Jito Block Engine zamiast standardowego RPC Solany.
- **Moduł**: Logika zostanie zintegrowana w `src/execution/ultimate_executor.mojo`.

#### 2.3.2. Ofensywna: Ataki Kanapkowe (Proponowane, Wysokie Ryzyko)

Atak kanapkowy (sandwich attack) to forma front-runningu, w której widzimy dużą oczekującą transakcję i umieszczamy nasze własne transakcje *przed* i *po* niej, aby zarobić na wpływie na cenę.

- **Przykładowy Przepływ**:
    1. Monitoruj mempool Jito w poszukiwaniu dużych oczekujących swapów (np. ktoś kupuje `MY_TOKEN` za 100 tys. USD).
    2. **Front-run**: Prześlij pakiet, w którym nasza pierwsza transakcja kupuje `MY_TOKEN` tuż przed dużą transakcją.
    3. Duża transakcja jest wykonywana, podnosząc cenę `MY_TOKEN`.
    4. **Back-run**: Nasza druga transakcja w pakiecie sprzedaje `MY_TOKEN` po nowej, wyższej cenie z zyskiem.
- **Implementacja**: Wymagałoby to dedykowanego modułu "MEV Bot", który stale skanuje mempool i konstruuje te bardzo złożone pakiety. Jest to kwestia przyszłościowa i nie wchodzi w zakres początkowy.

### 2.4. Integracja z Jito

- **Punkt Końcowy RPC Jito**: Będziemy używać dedykowanego punktu końcowego RPC dostarczanego przez Jito do wysyłania transakcji i pakietów. Będzie on konfigurowany poprzez `.env`.
- **FFI dla Pakietów**: Ponieważ tworzenie pakietów jest złożone, prawdopodobnie zostanie zaimplementowane w module Rust (`rust-modules/src/mev/jito.rs`) i udostępnione poprzez FFI.

### 2.5. Konfiguracja

(Patrz sekcja 1.5 dla przykładów konfiguracji)

### 2.6. Ryzyka

- **Ryzyko Finansowe**: Napiwki to dodatkowy koszt. Jeśli nie są zarządzane ostrożnie, mogą zjadać zyski. Dynamiczne obliczanie napiwków musi być solidne.
- **Złożoność**: Strategie MEV, zwłaszcza te ofensywne, są niezwykle złożone i mogą zawieść na wiele sposobów, prowadząc do utraty środków.
- **Kwestie Etyczne**: Chociaż koncentrujemy się na "etycznym" MEV (opłaty priorytetowe), strategie ofensywne, takie jak ataki kanapkowe, są kontrowersyjne.
