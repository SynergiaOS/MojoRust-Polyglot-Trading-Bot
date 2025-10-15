# Advanced Filters Guide / Przewodnik po Zaawansowanych Filtrach

**Owner:** @YourGitHubUsername
**Status:** Final

## 1. English

### 1.1. Overview

The `MasterFilter` is the gatekeeper that decides whether a new token pair is worth considering for a snipe trade. While basic filters check for liquidity and mint authority, the advanced filters provide a much deeper, more nuanced analysis. This guide details the advanced filters implemented in the system to improve decision-making and reduce risk.

These filters are implemented within the `engine/master_filter.mojo` module and its sub-components.

### 1.2. Advanced Filter Modules

#### 1.2.1. Social Intelligence Filter

- **Purpose**: To gauge community interest and detect inorganic activity. A token with no social presence is a red flag.
- **Module**: `src/data/social_client.mojo`
- **Metrics Checked**:
    - Twitter/X account age and follower count.
    - Telegram channel member count and activity.
    - Ratio of followers to engagement (likes, retweets).
    - Detection of bot-like activity (spammy comments, generic profiles).
- **Configuration (`config/trading.toml`)**:
    ```toml
    [advanced_filters.social_intelligence]
    enabled = true
    min_followers = 100
    min_account_age_days = 30
    max_bot_activity_score = 0.5 # A score from 0 to 1
    ```

#### 1.2.2. Honeypot Detection Filter

- **Purpose**: To identify malicious tokens where buyers are unable to sell their holdings.
- **Module**: `src/data/honeypot_client.mojo`
- **Mechanism**:
    - Integrates with APIs like `honeypot.is`.
    - Performs a simulation of a buy and sell transaction to confirm sellability.
- **Metrics Checked**:
    - `is_honeypot` boolean flag.
    - Sell tax and buy tax.
    - Transferability of the token.
- **Configuration (`config/trading.toml`)**:
    ```toml
    [advanced_filters.honeypot_detection]
    enabled = true
    max_sell_tax = 10 # Percentage
    allow_unverified_tokens = false
    ```

#### 1.2.3. Whale & Holder Distribution Filter

- **Purpose**: To analyze the distribution of token holders to identify risks of a "rug pull" or price manipulation.
- **Module**: `src/analysis/whale_tracker.mojo`
- **Metrics Checked**:
    - Percentage of supply held by the top 10 holders.
    - Percentage of supply held by the contract creator.
    - Number of active holders.
    - Liquidity pool token distribution (is it locked or concentrated?).
- **Configuration (`config/trading.toml`)**:
    ```toml
    [advanced_filters.holder_distribution]
    enabled = true
    max_top_10_holder_percentage = 20.0
    max_creator_balance_percentage = 5.0
    min_holder_count = 50
    ```

#### 1.2.4. Organic Score Filter (Helius)

- **Purpose**: To leverage Helius's proprietary score that measures the "organic-ness" of a token's activity.
- **Module**: `src/data/helius_client.mojo`
- **Mechanism**: This is a direct API call to a Helius endpoint that provides a score based on various on-chain and off-chain heuristics.
- **Configuration (`.env.example`)**:
    ```
    HELIUS_ORGANIC_SCORE_ENABLED=true
    MIN_HELIUS_ORGANIC_SCORE=70 # Score from 0-100
    ```

### 1.3. Integration in `MasterFilter`

The `MasterFilter` orchestrates these checks. A token must pass all enabled advanced filters to be considered for trading.

```python
# In src/engine/master_filter.mojo (pseudocode)

fn verify_token(token_address: String) -> Bool:
    let basic_checks_pass = self.run_basic_checks(token_address)
    if not basic_checks_pass:
        return False

    let social_pass = self.social_filter.verify(token_address)
    let honeypot_pass = self.honeypot_filter.verify(token_address)
    let distribution_pass = self.distribution_filter.verify(token_address)

    return social_pass and honeypot_pass and distribution_pass
```

---

## 2. Polski

### 2.1. Przegląd

`MasterFilter` to strażnik, który decyduje, czy nowa para tokenów jest warta rozważenia do transakcji typu "snipe". Podczas gdy podstawowe filtry sprawdzają płynność i uprawnienia do mintowania, zaawansowane filtry zapewniają znacznie głębszą, bardziej zniuansowaną analizę. Ten przewodnik szczegółowo opisuje zaawansowane filtry zaimplementowane w systemie w celu poprawy podejmowania decyzji i zmniejszenia ryzyka.

Filtry te są zaimplementowane w module `engine/master_filter.mojo` i jego pod-komponentach.

### 2.2. Moduły Filtrów Zaawansowanych

#### 2.2.1. Filtr Inteligencji Społecznościowej

- **Cel**: Ocena zainteresowania społeczności i wykrywanie nienaturalnej aktywności. Token bez obecności w mediach społecznościowych jest sygnałem ostrzegawczym.
- **Moduł**: `src/data/social_client.mojo`
- **Sprawdzane Metryki**:
    - Wiek konta i liczba obserwujących na Twitter/X.
    - Liczba członków i aktywność na kanale Telegram.
    - Stosunek liczby obserwujących do zaangażowania (polubienia, retweety).
    - Wykrywanie aktywności botów (spamowe komentarze, generyczne profile).
- **Konfiguracja (`config/trading.toml`)**:
    (Patrz sekcja 1.2.1)

#### 2.2.2. Filtr Wykrywania Honeypotów

- **Cel**: Identyfikacja złośliwych tokenów, w przypadku których kupujący nie mogą sprzedać swoich aktywów.
- **Moduł**: `src/data/honeypot_client.mojo`
- **Mechanizm**:
    - Integracja z API takimi jak `honeypot.is`.
    - Przeprowadzenie symulacji transakcji kupna i sprzedaży w celu potwierdzenia możliwości sprzedaży.
- **Sprawdzane Metryki**:
    - Flaga logiczna `is_honeypot`.
    - Podatek od sprzedaży i podatek od kupna.
    - Możliwość transferu tokena.
- **Konfiguracja (`config/trading.toml`)**:
    (Patrz sekcja 1.2.2)

#### 2.2.3. Filtr Dystrybucji Wielorybów i Posiadaczy

- **Cel**: Analiza dystrybucji posiadaczy tokenów w celu identyfikacji ryzyka "rug pull" lub manipulacji ceną.
- **Moduł**: `src/analysis/whale_tracker.mojo`
- **Sprawdzane Metryki**:
    - Procent podaży posiadany przez 10 największych posiadaczy.
    - Procent podaży posiadany przez twórcę kontraktu.
    - Liczba aktywnych posiadaczy.
    - Dystrybucja tokenów puli płynności (czy jest zablokowana czy skoncentrowana?).
- **Konfiguracja (`config/trading.toml`)**:
    (Patrz sekcja 1.2.3)

#### 2.2.4. Filtr Oceny Organiczności (Helius)

- **Cel**: Wykorzystanie autorskiej oceny Helius, która mierzy "organiczność" aktywności tokena.
- **Moduł**: `src/data/helius_client.mojo`
- **Mechanizm**: Jest to bezpośrednie wywołanie API do punktu końcowego Helius, który dostarcza ocenę opartą na różnych heurystykach on-chain i off-chain.
- **Konfiguracja (`.env.example`)**:
    (Patrz sekcja 1.2.4)

### 2.3. Integracja w `MasterFilter`

`MasterFilter` koordynuje te wszystkie sprawdzenia. Token musi przejść wszystkie włączone filtry zaawansowane, aby został rozważony do handlu.

(Patrz sekcja 1.3 dla pseudokodu)
