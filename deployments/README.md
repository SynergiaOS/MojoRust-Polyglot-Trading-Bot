# 🚀 HFT Deployment Scripts

Skrypty deployment dla środowiska produkcyjnego HFT MojoRust.

## Kategoria Skryptów

### 🌐 Deployment Scripts
- `deploy_to_server.sh` - Główny skrypt deploymentu na serwer
- `deploy_with_filters.sh` - Deployment z zaawansowanymi filtrami
- `deploy_algorithmic_bot.sh` - Deployment bota algorytmicznego
- `quick_deploy.sh` - Szybki deployment (dla developmentu)

### 🔄 Management Scripts
- `restart_bot.sh` - Restart bota tradingowego
- `health_check_cron.sh` - Cron job dla health checków
- `rollback.sh` - Powrót do poprzedniej wersji
- `backup.sh` - Backup systemu

### 🐳 Docker Scripts
- `docker-entrypoint.sh` - Entrypoint dla kontenerów
- `server_health.sh` - Sprawdzanie zdrowia serwera

### 🔧 Configuration Scripts
- `validate_config.sh` - Walidacja konfiguracji
- `setup_vpc_peering.sh` - Setup VPC peering

## Użycie

```bash
# Pełny deployment produkcyjny
./deployments/scripts/deploy_to_server.sh

# Szybki deployment development
./deployments/scripts/quick_deploy.sh

# Restart bota
./deployments/scripts/restart_bot.sh

# Health check serwera
./deployments/scripts/server_health.sh --remote
```

## Środowiska

- **Development**: Używaj `quick_deploy.sh`
- **Staging**: Używaj `deploy_with_filters.sh`
- **Production**: Używaj `deploy_to_server.sh`

## Bezpieczeństwo

Wszystkie skrypty deployment zawierają:
- Weryfikację sum kontrolnych plików
- Rollback automatyczny w razie błędu
- Logowanie wszystkich operacji
- Sprawdzanie uprawnień przed wykonaniem