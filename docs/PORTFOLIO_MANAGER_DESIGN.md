# Portfolio Manager Design / Projekt Menedżera Portfela

**Owner:** @YourGitHubUsername
**Status:** Final

## 1. English

### 1.1. Overview

The `PortfolioManager` is a Rust-based module responsible for centralized capital allocation across all trading strategies. It ensures that capital is deployed efficiently and safely, preventing over-allocation and prioritizing high-conviction trades. It operates on a reservation-based system, where strategies request capital for a specific token and are granted a time-limited reservation.

This module is critical for risk management and performance optimization. It is designed to be thread-safe and accessible from both Rust and Mojo/Python via FFI.

### 1.2. Core Components

- **`PortfolioManager`**: The main struct that holds the state of all allocations, available capital, and the priority queue.
- **`Strategy`**: An enum representing the different trading strategies that can request capital (e.g., `Arbitrage`, `Sniper`, `Momentum`).
- **`Priority`**: An enum defining the priority level of a capital request (`Low`, `Medium`, `High`, `Critical`).
- **`CapitalRequest`**: A struct representing a request from a strategy for a certain amount of capital for a specific token.
- **`CapitalReservation`**: A struct representing a successful reservation of capital, with a unique ID and an expiry timestamp.

### 1.3. Workflow

1.  **Request**: A strategy submits a `CapitalRequest` to the `PortfolioManager`. The request includes the strategy type, token address, amount, and priority.
2.  **Prioritization**: The request is placed in a priority queue. `Critical` requests are processed first.
3.  **Verification**: The `PortfolioManager` checks if sufficient capital is available.
4.  **Allocation**: If capital is available, a `CapitalReservation` is created and returned to the strategy. The reservation has a specific lifetime (e.g., 30 seconds).
5.  **Execution**: The strategy uses the reservation ID to execute the trade.
6.  **Release**: Upon trade completion (fill or failure), the strategy releases the capital using the reservation ID.
7.  **Timeout**: If a reservation is not used within its lifetime, it expires automatically, and the capital is returned to the pool. This prevents "stuck" capital.

### 1.4. Data Structures (Rust)

```rust
// In rust-modules/src/portfolio/mod.rs

use std::collections::{BinaryHeap, HashMap};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Strategy {
    Arbitrage,
    Sniper,
    Momentum,
    MarketMaking,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Priority {
    Low,
    Medium,
    High,
    Critical,
}

#[derive(Debug, Clone)]
pub struct CapitalRequest {
    pub strategy: Strategy,
    pub token_address: String,
    pub amount: f64,
    pub priority: Priority,
}

#[derive(Debug, Clone)]
pub struct CapitalReservation {
    pub reservation_id: u64,
    pub strategy: Strategy,
    pub token_address: String,
    pub amount: f64,
    pub expires_at: Instant,
}

pub struct PortfolioManager {
    total_capital: f64,
    allocated_capital: HashMap<u64, CapitalReservation>,
    request_queue: BinaryHeap<(Priority, CapitalRequest)>,
    next_reservation_id: u64,
}

impl PortfolioManager {
    pub fn new(total_capital: f64) -> Self {
        // ... implementation ...
    }

    pub fn request_capital(&mut self, request: CapitalRequest) {
        // ... implementation ...
    }

    pub fn process_requests(&mut self) -> Vec<CapitalReservation> {
        // ... implementation ...
    }

    pub fn release_capital(&mut self, reservation_id: u64) {
        // ... implementation ...
    }

    fn cleanup_expired_reservations(&mut self) {
        // ... implementation ...
    }
}
```

### 1.5. FFI Interface

The `PortfolioManager` will be exposed to Mojo and Python via FFI shims in `rust-modules/src/ffi/mod.rs`.

```rust
// In rust-modules/src/ffi/mod.rs

use crate::portfolio::PortfolioManager;
use std::sync::{Arc, Mutex};

lazy_static! {
    static ref PORTFOLIO_MANAGER: Arc<Mutex<PortfolioManager>> =
        Arc::new(Mutex::new(PortfolioManager::new(10000.0))); // Example capital
}

#[no_mangle]
pub extern "C" fn request_capital_ffi(...) -> u64 {
    // ... implementation ...
}

#[no_mangle]
pub extern "C" fn release_capital_ffi(reservation_id: u64) {
    // ... implementation ...
}
```

### 1.6. Configuration (`config/trading.toml`)

```toml
[portfolio_manager]
total_capital = 10000.0 # Total capital in USDT to be managed
reservation_timeout_seconds = 30 # Time in seconds before a reservation expires
```

### 1.7. Prometheus Metrics

- `portfolio_total_capital`: Gauge - Total capital managed.
- `portfolio_allocated_capital`: Gauge - Currently allocated capital.
- `portfolio_available_capital`: Gauge - Currently available capital.
- `portfolio_capital_requests_total`: Counter - Total number of capital requests by strategy and priority.
- `portfolio_capital_allocations_total`: Counter - Total number of successful allocations by strategy.
- `portfolio_capital_releases_total`: Counter - Total number of releases by strategy.
- `portfolio_reservation_timeouts_total`: Counter - Total number of expired reservations by strategy.

---

## 2. Polski

### 2.1. Przegląd

`PortfolioManager` to moduł oparty na Rust, odpowiedzialny za scentralizowaną alokację kapitału pomiędzy wszystkimi strategiami handlowymi. Zapewnia, że kapitał jest wykorzystywany efektywnie i bezpiecznie, zapobiegając nadmiernej alokacji i priorytetyzując transakcje o wysokim stopniu pewności. Działa w oparciu o system rezerwacji, w którym strategie wnioskują o kapitał dla określonego tokena i otrzymują rezerwację ograniczoną czasowo.

Moduł ten jest kluczowy dla zarządzania ryzykiem i optymalizacji wydajności. Został zaprojektowany jako bezpieczny wątkowo i dostępny zarówno z Rust, jak i Mojo/Python poprzez FFI.

### 2.2. Główne Komponenty

- **`PortfolioManager`**: Główna struktura przechowująca stan wszystkich alokacji, dostępny kapitał oraz kolejkę priorytetową.
- **`Strategy`**: Enum reprezentujący różne strategie handlowe, które mogą wnioskować o kapitał (np. `Arbitrage`, `Sniper`, `Momentum`).
- **`Priority`**: Enum definiujący poziom priorytetu wniosku o kapitał (`Low`, `Medium`, `High`, `Critical`).
- **`CapitalRequest`**: Struktura reprezentująca wniosek od strategii o określoną ilość kapitału dla konkretnego tokena.
- **`CapitalReservation`**: Struktura reprezentująca udaną rezerwację kapitału, z unikalnym ID i znacznikiem czasu wygaśnięcia.

### 2.3. Przepływ Pracy

1.  **Wniosek**: Strategia przesyła `CapitalRequest` do `PortfolioManager`. Wniosek zawiera typ strategii, adres tokena, kwotę i priorytet.
2.  **Priorytetyzacja**: Wniosek jest umieszczany w kolejce priorytetowej. Wnioski `Critical` są przetwarzane w pierwszej kolejności.
3.  **Weryfikacja**: `PortfolioManager` sprawdza, czy dostępny jest wystarczający kapitał.
4.  **Alokacja**: Jeśli kapitał jest dostępny, tworzona jest `CapitalReservation` i zwracana do strategii. Rezerwacja ma określony czas życia (np. 30 sekund).
5.  **Wykonanie**: Strategia używa ID rezerwacji do wykonania transakcji.
6.  **Zwolnienie**: Po zakończeniu transakcji (zrealizowanej lub nieudanej), strategia zwalnia kapitał, używając ID rezerwacji.
7.  **Timeout**: Jeśli rezerwacja nie zostanie wykorzystana w czasie swojego życia, wygasa automatycznie, a kapitał wraca do puli. Zapobiega to "zablokowaniu" kapitału.

### 2.4. Struktury Danych (Rust)

(Patrz sekcja 1.4 dla przykładu kodu w Rust)

### 2.5. Interfejs FFI

`PortfolioManager` będzie dostępny dla Mojo i Python poprzez FFI w `rust-modules/src/ffi/mod.rs`.

(Patrz sekcja 1.5 dla przykładu kodu w Rust)

### 2.6. Konfiguracja (`config/trading.toml`)

```toml
[portfolio_manager]
total_capital = 10000.0 # Całkowity kapitał w USDT do zarządzania
reservation_timeout_seconds = 30 # Czas w sekundach do wygaśnięcia rezerwacji
```

### 2.7. Metryki Prometheus

- `portfolio_total_capital`: Gauge - Całkowity zarządzany kapitał.
- `portfolio_allocated_capital`: Gauge - Aktualnie alokowany kapitał.
- `portfolio_available_capital`: Gauge - Aktualnie dostępny kapitał.
- `portfolio_capital_requests_total`: Counter - Całkowita liczba wniosków o kapitał wg strategii i priorytetu.
- `portfolio_capital_allocations_total`: Counter - Całkowita liczba udanych alokacji wg strategii.
- `portfolio_capital_releases_total`: Counter - Całkowita liczba zwolnień wg strategii.
- `portfolio_reservation_timeouts_total`: Counter - Całkowita liczba wygasłych rezerwacji wg strategii.