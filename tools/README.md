# 🛠️ HFT Development Tools

Narzędzia deweloperskie dla systemu HFT MojoRust.

## Kategoria Skryptów

### 🏗️ Build Scripts
- `build_rust_modules.sh` - Budowanie modułów Rust
- `build_mojo_binary.sh` - Kompilacja komponentów Mojo
- `build_and_deploy.sh` - Kompletny pipeline build i deploy

### 🔍 Verification Scripts
- `verify_ffi.sh` - Weryfikacja integracji FFI
- `verify_api_health.sh` - Sprawdzanie zdrowia API
- `verify_filter_performance.sh` - Testowanie wydajności filtrów
- `verify_dragonflydb_connection.sh` - Sprawdzanie połączenia z DragonflyDB

### 🩺 Diagnostic Scripts
- `diagnose_cpu_usage.sh` - Diagnostyka zużycia CPU
- `diagnose_port_conflict.sh` - Identyfikacja konfliktów portów

### ⚙️ Setup Scripts
- `setup_infisical.sh` - Konfiguracja Infisical
- `setup_flash_loan_free.sh` - Setup darmowych flash loans
- `setup_universal_auth_free.sh` - Konfiguracja Universal Auth

## Użycie

```bash
# Build wszystkie komponenty
./tools/scripts/build_and_deploy.sh --skip-deploy

# Diagnostyka CPU
./tools/scripts/diagnose_cpu_usage.sh

# Weryfikacja połączenia z DragonflyDB
./tools/scripts/verify_dragonflydb_connection.sh
```

Wszystkie skrypty są zoptymalizowane pod kątem wydajności HFT
i zawierają obszerne logowanie dla celów diagnostycznych.