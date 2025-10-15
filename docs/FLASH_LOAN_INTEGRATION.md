# Flash Loan Integration Guide / Przewodnik Integracji Flash Loan

**Owner:** @YourGitHubUsername
**Status:** Proposed

## 1. English

### 1.1. Overview

Flash loans provide instant, uncollateralized loans that must be borrowed and repaid within the same atomic transaction. This feature unlocks powerful strategies, such as capital-intensive arbitrage, without requiring upfront capital. This document outlines the proposed integration of flash loans into our trading bot.

**Disclaimer:** Flash loan integration is a high-risk, advanced feature. It introduces significant smart contract risk and complexity. Proceed with extreme caution.

### 1.2. Use Case: Arbitrage

The primary use case for flash loans is to amplify arbitrage profits.

1.  **Detect Opportunity**: The bot detects a significant price difference for `TOKEN_A` between DEX_1 and DEX_2.
2.  **Borrow**: Borrow a large amount of `USDC` via a flash loan from a provider like Solend or Kamino.
3.  **Execute Swaps**:
    - Use the borrowed `USDC` to buy `TOKEN_A` on DEX_1 where it's cheaper.
    - Immediately sell the acquired `TOKEN_A` on DEX_2 for more `USDC`.
4.  **Repay Loan**: Repay the `USDC` flash loan plus the provider's fee.
5.  **Profit**: The remaining `USDC` is the profit.

All these steps must be bundled into a single Solana transaction.

### 1.3. Proposed Implementation

The integration will require a dedicated Rust module to handle the complexities of building and executing flash loan transactions.

- **Flash Loan Aggregator (`rust-modules/src/flash_loans/mod.rs`)**: A new Rust module responsible for abstracting interactions with different flash loan providers.
    - It will expose a simple function like `build_arbitrage_tx_with_flash_loan(...)`.
    - This function will take the arbitrage details (tokens, DEXs, amounts) and construct the complex transaction with all the necessary instructions.
- **Provider-Specific Logic**: Inside the aggregator, there will be sub-modules for each provider (e.g., `solend.rs`, `kamino.rs`) that know how to build the specific `Borrow`, `Swap`, and `Repay` instructions.
- **FFI Interface**: The `build_arbitrage_tx_with_flash_loan` function will be exposed to Mojo/Python via FFI. The bot's execution engine can then call this to get a fully formed transaction, sign it, and send it.

#### Example Rust Structure

```rust
// In rust-modules/src/flash_loans/mod.rs

pub mod providers; // Contains solend.rs, kamino.rs etc.

pub struct ArbitrageWithFlashLoanParams {
    // ... details of the arbitrage opportunity
}

// This is the main function exposed via FFI
pub fn build_arbitrage_tx_with_flash_loan(
    params: ArbitrageWithFlashLoanParams
) -> Result<VersionedTransaction, anyhow::Error> {
    // 1. Choose the best flash loan provider
    // 2. Get the borrow instruction from the provider module
    // 3. Get the swap instructions for the DEXs
    // 4. Get the repay instruction
    // 5. Bundle them all into one transaction
    // 6. Return the transaction
}
```

### 1.4. Configuration (`config/trading.toml`)

```toml
[flash_loans]
enabled = false # Disabled by default for safety
max_loan_amount_usd = 100000.0 # Max amount to borrow
provider_priority = ["solend", "kamino"] # Order of preference

[flash_loans.providers.solend]
program_id = "..."

[flash_loans.providers.kamino]
program_id = "..."
```

### 1.5. Risks and Mitigations

- **Smart Contract Risk**: A bug in our code or the provider's code could lead to total loss of funds.
    - **Mitigation**: Extensive testing on devnet, transaction simulations, and initially only using very small loan amounts.
- **Execution Risk**: The transaction could fail if market conditions change mid-execution (slippage).
    - **Mitigation**: The entire sequence is atomic. If any step fails, the whole transaction reverts, and only a standard transaction fee is lost.
- **Fee Risk**: The flash loan fee could be higher than the arbitrage profit.
    - **Mitigation**: The bot must calculate the expected profit *after* all fees (loan fee, transaction fees, slippage) before even attempting the flash loan.

---

## 2. Polski

### 2.1. Przegląd

Flash loans (pożyczki błyskawiczne) oferują natychmiastowe, niezabezpieczone pożyczki, które muszą być zaciągnięte i spłacone w ramach tej samej, atomowej transakcji. Ta funkcja odblokowuje potężne strategie, takie jak arbitraż wymagający dużego kapitału, bez konieczności posiadania go z góry. Ten dokument opisuje proponowaną integrację flash loans z naszym botem handlowym.

**Zastrzeżenie:** Integracja flash loans to zaawansowana funkcja wysokiego ryzyka. Wprowadza ona znaczne ryzyko związane z inteligentnymi kontraktami i dużą złożoność. Należy postępować z najwyższą ostrożnością.

### 2.2. Przypadek Użycia: Arbitraż

Głównym przypadkiem użycia flash loans jest zwielokrotnienie zysków z arbitrażu.

1.  **Wykryj Okazję**: Bot wykrywa znaczącą różnicę w cenie `TOKEN_A` między DEX_1 a DEX_2.
2.  **Pożycz**: Pożycz dużą ilość `USDC` za pomocą flash loan od dostawcy takiego jak Solend czy Kamino.
3.  **Wykonaj Swapy**:
    - Użyj pożyczonego `USDC`, aby kupić `TOKEN_A` na DEX_1, gdzie jest tańszy.
    - Natychmiast sprzedaj nabyty `TOKEN_A` na DEX_2 za więcej `USDC`.
4.  **Spłać Pożyczkę**: Spłać pożyczkę `USDC` wraz z opłatą dla dostawcy.
5.  **Zysk**: Pozostałe `USDC` to zysk.

Wszystkie te kroki muszą być spakowane w jedną transakcję Solana.

### 2.3. Proponowana Implementacja

Integracja będzie wymagać dedykowanego modułu w Rust do obsługi złożoności budowania i wykonywania transakcji flash loan.

- **Agregator Flash Loan (`rust-modules/src/flash_loans/mod.rs`)**: Nowy moduł w Rust odpowiedzialny za abstrakcję interakcji z różnymi dostawcami flash loan.
    - Będzie udostępniał prostą funkcję, taką jak `build_arbitrage_tx_with_flash_loan(...)`.
    - Ta funkcja przyjmie szczegóły arbitrażu (tokeny, DEX-y, kwoty) i skonstruuje złożoną transakcję ze wszystkimi niezbędnymi instrukcjami.
- **Logika Specyficzna dla Dostawcy**: Wewnątrz agregatora znajdą się pod-moduły dla każdego dostawcy (np. `solend.rs`, `kamino.rs`), które wiedzą, jak budować specyficzne instrukcje `Borrow`, `Swap` i `Repay`.
- **Interfejs FFI**: Funkcja `build_arbitrage_tx_with_flash_loan` będzie dostępna dla Mojo/Python poprzez FFI. Silnik wykonawczy bota będzie mógł ją wywołać, aby otrzymać w pełni uformowaną transakcję, podpisać ją i wysłać.

(Patrz sekcja 1.3 dla przykładu struktury w Rust)

### 2.4. Konfiguracja (`config/trading.toml`)

(Patrz sekcja 1.4 dla przykładu konfiguracji)

### 2.5. Ryzyka i Środki Zaradcze

- **Ryzyko Inteligentnych Kontraktów**: Błąd w naszym kodzie lub kodzie dostawcy może prowadzić do całkowitej utraty środków.
    - **Środek Zaradczy**: Obszerne testy na devnet, symulacje transakcji i początkowo używanie tylko bardzo małych kwot pożyczek.
- **Ryzyko Wykonania**: Transakcja może się nie udać, jeśli warunki rynkowe zmienią się w trakcie jej wykonywania (poślizg cenowy).
    - **Środek Zaradczy**: Cała sekwencja jest atomowa. Jeśli jakikolwiek krok się nie powiedzie, cała transakcja jest wycofywana, a tracona jest tylko standardowa opłata transakcyjna.
- **Ryzyko Opłat**: Opłata za flash loan może być wyższa niż zysk z arbitrażu.
    - **Środek Zaradczy**: Bot musi obliczyć oczekiwany zysk *po* odjęciu wszystkich opłat (opłata za pożyczkę, opłaty transakcyjne, poślizg) jeszcze przed próbą zaciągnięcia pożyczki.
