#!/bin/bash

# scripts/rollback.sh

# Configuration
DEPLOYMENT_DIR="${DEPLOYMENT_DIR:-~/Projects/MojoRust}"
BACKUP_DIR="${BACKUP_DIR:-/home/tradingbot/backups}"
ROLLBACK_TARGET=""
ROLLBACK_LOG="/tmp/rollback_$(date +%Y%m%d_%H%M%S).log"

# Database configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-trading_bot}"
DB_USER="${DB_USER:-trading_user}"

# Command Line Options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --backup-file)
            ROLLBACK_TARGET="$2"
            shift 2
            ;;
        --latest)
            LATEST=true
            shift
            ;;
        --list)
            LIST=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-database)
            NO_DATABASE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --gpg-passphrase)
            GPG_PASSPHRASE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Expand tildes in paths
DEPLOYMENT_DIR=$(eval echo "${DEPLOYMENT_DIR}")
BACKUP_DIR=$(eval echo "${BACKUP_DIR}")

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${ROLLBACK_LOG}"
}

# Enhanced listing function
if [ "${LIST}" = true ]; then
    echo "Available backups:"
    echo "=================="
    if [ -f "${BACKUP_DIR}/latest_backup.json" ]; then
        echo "Latest backup:"
        cat "${BACKUP_DIR}/latest_backup.json" | jq -r '"\(.timestamp) - \(.backup_file) (\(.size))"'
        echo ""
    fi

    echo "All backups:"
    find "${BACKUP_DIR}" -name "mojorust-backup-*.tar.gz*" -type f -exec ls -lh {} \; | \
        awk '{print $9 " (" $5 ", " $6 " " $7 " " $8 ")"}'
    exit 0
fi

# Enhanced latest backup detection
if [ "${LATEST}" = true ]; then
    if [ -f "${BACKUP_DIR}/latest_backup.json" ]; then
        ROLLBACK_TARGET="${BACKUP_DIR}/$(cat "${BACKUP_DIR}/latest_backup.json" | jq -r '.backup_file')"
    else
        ROLLBACK_TARGET=$(ls -t "${BACKUP_DIR}"/mojorust-backup-*.tar.gz* 2>/dev/null | head -1)
    fi
fi

if [ -z "${ROLLBACK_TARGET}" ]; then
    log "ERROR: No rollback target specified. Use --latest or --backup-file <file>"
    exit 1
fi

# Resolve full path
if [[ ! "${ROLLBACK_TARGET}" = /* ]]; then
    ROLLBACK_TARGET="${BACKUP_DIR}/${ROLLBACK_TARGET}"
fi

if [ ! -f "${ROLLBACK_TARGET}" ]; then
    log "ERROR: Backup file not found: ${ROLLBACK_TARGET}"
    exit 1
fi

# Enhanced confirmation with backup info
if [ "${FORCE}" != true ]; then
    echo "Rollback Information:"
    echo "===================="
    echo "Target: ${ROLLBACK_TARGET}"

    # Show backup details if manifest exists
    if [ -f "${ROLLBACK_TARGET}_manifest.json" ]; then
        echo "Backup Details:"
        cat "${ROLLBACK_TARGET}_manifest.json" | jq -r '"  Timestamp: \(.timestamp)\n  Size: \(.size_human)\n  Type: \(.backup_type)\n  Encrypted: \(.encrypted)"'
    fi

    echo ""
    read -p "Are you sure you want to roll back to this backup? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Rollback cancelled by user"
        exit 1
    fi
fi

if [ "${DRY_RUN}" = true ]; then
    log "DRY RUN: Would roll back to ${ROLLBACK_TARGET}"
    if [ "${DB_ONLY}" = true ]; then
        log "DRY RUN: Database-only rollback requested"
    fi
    exit 0
fi

# Rollback Process
log "Starting rollback process..."
log "Rollback target: ${ROLLBACK_TARGET}"
log "Deployment directory: ${DEPLOYMENT_DIR}"

# Enhanced backup verification
verify_backup() {
    local backup_file="$1"

    log "Verifying backup integrity..."

    # Check checksum
    if [ -f "${backup_file}.sha256" ]; then
        if sha256sum -c "${backup_file}.sha256" >/dev/null 2>&1; then
            log "Checksum verification passed"
        else
            log "ERROR: Checksum verification failed"
            return 1
        fi
    else
        log "WARNING: No checksum file found, proceeding without verification"
    fi

    # Determine if encrypted and verify structure
    if [[ "${backup_file}" == *.gpg ]]; then
        log "Encrypted backup detected, verifying GPG structure..."
        if gpg --list-packets "${backup_file}" >/dev/null 2>&1; then
            log "GPG structure verification passed"
        else
            log "ERROR: GPG file structure verification failed"
            return 1
        fi
    else
        log "Unencrypted backup detected, verifying tar structure..."
        if tar -tzf "${backup_file}" >/dev/null 2>&1; then
            log "Tar structure verification passed"
        else
            log "ERROR: Tar file structure verification failed"
            return 1
        fi
    fi

    return 0
}

if ! verify_backup "${ROLLBACK_TARGET}"; then
    log "ERROR: Backup verification failed"
    exit 1
fi

# Enhanced GPG decryption function
decrypt_backup() {
    local encrypted_file="$1"
    local output_file="$2"

    log "Decrypting backup file..."

    if [ -n "${GPG_PASSPHRASE}" ]; then
        # Use provided passphrase
        echo "${GPG_PASSPHRASE}" | gpg --batch --yes --passphrase-fd 0 \
            --decrypt "${encrypted_file}" > "${output_file}" 2>>"${ROLLBACK_LOG}"
    else
        # Prompt for passphrase
        gpg --decrypt "${encrypted_file}" > "${output_file}" 2>>"${ROLLBACK_LOG}"
    fi

    if [ $? -eq 0 ]; then
        log "Backup decryption successful"
        return 0
    else
        log "ERROR: Backup decryption failed"
        rm -f "${output_file}"
        return 1
    fi
}

# Enhanced database restore function
restore_database() {
    local backup_dir="$1"

    log "Starting database restore..."
    log "Database: ${DB_NAME} on ${DB_HOST}:${DB_PORT}"

    # Find database backup files
    local db_backup_file=""
    local db_manifest=""

    # Check for custom format backup
    if [ -f "${backup_dir}/db_backup_"*.dump ]; then
        db_backup_file=$(ls "${backup_dir}/db_backup_"*.dump | head -1)
        db_manifest="${db_backup_file}_manifest.json"
        log "Found custom format database backup: $(basename ${db_backup_file})"
    # Check for directory format backup
    elif [ -d "${backup_dir}/db_backup_"*_dir ]; then
        db_backup_file=$(ls -d "${backup_dir}/db_backup_"*_dir | head -1)
        db_manifest="${db_backup_file}_manifest.json"
        log "Found directory format database backup: $(basename ${db_backup_file})"
    # Check for SQL backup
    elif [ -f "${backup_dir}/db_backup_"*.sql ]; then
        db_backup_file=$(ls "${backup_dir}/db_backup_"*.sql | head -1)
        db_manifest="${db_backup_file}_manifest.json"
        log "Found SQL format database backup: $(basename ${db_backup_file})"
    else
        log "WARNING: No database backup found in backup directory"
        return 1
    fi

    if [ ! -f "${db_backup_file}" ] && [ ! -d "${db_backup_file}" ]; then
        log "ERROR: Database backup file not found: ${db_backup_file}"
        return 1
    fi

    # Create database connection test
    log "Testing database connection..."
    if ! psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT 1;" >/dev/null 2>&1; then
        log "ERROR: Cannot connect to database"
        return 1
    fi

    # Restore based on format
    if [[ "${db_backup_file}" == *.dump ]]; then
        log "Restoring from custom format backup..."
        if pg_restore -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
            --clean --if-exists --verbose --no-password "${db_backup_file}" 2>>"${ROLLBACK_LOG}"; then
            log "Custom format database restore successful"
        else
            log "ERROR: Custom format database restore failed"
            return 1
        fi
    elif [ -d "${db_backup_file}" ]; then
        log "Restoring from directory format backup..."
        if pg_restore -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
            --clean --if-exists --verbose --no-password "${db_backup_file}" 2>>"${ROLLBACK_LOG}"; then
            log "Directory format database restore successful"
        else
            log "ERROR: Directory format database restore failed"
            return 1
        fi
    elif [[ "${db_backup_file}" == *.sql ]]; then
        log "Restoring from SQL backup..."
        if psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
            --verbose --file="${db_backup_file}" 2>>"${ROLLBACK_LOG}"; then
            log "SQL database restore successful"
        else
            log "ERROR: SQL database restore failed"
            return 1
        fi
    fi

    return 0
}

# Stop Current Bot
log "Stopping trading bot..."
if sudo systemctl stop trading-bot; then
    log "Trading bot stopped successfully"
else
    log "WARNING: Failed to stop trading bot, continuing with rollback"
fi

# Create emergency backup of current state
EMERGENCY_BACKUP_DIR="/tmp/emergency-backup-$(date +%Y%m%d_%H%M%S)"
log "Creating emergency backup to ${EMERGENCY_BACKUP_DIR}..."

mkdir -p "${EMERGENCY_BACKUP_DIR}"
cp -r "${DEPLOYMENT_DIR}/config" "${EMERGENCY_BACKUP_DIR}/" 2>/dev/null
cp -r "${DEPLOYMENT_DIR}/.env"* "${EMERGENCY_BACKUP_DIR}/" 2>/dev/null
cp -r "${DEPLOYMENT_DIR}/data" "${EMERGENCY_BACKUP_DIR}/" 2>/dev/null

log "Emergency backup created"

# Prepare for restoration
TEMP_EXTRACT_DIR="/tmp/rollback_extract_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${TEMP_EXTRACT_DIR}"

# Decrypt backup if needed
if [[ "${ROLLBACK_TARGET}" == *.gpg ]]; then
    DECRYPTED_FILE="${TEMP_EXTRACT_DIR}/$(basename ${ROLLBACK_TARGET%.gpg})"
    if ! decrypt_backup "${ROLLBACK_TARGET}" "${DECRYPTED_FILE}"; then
        log "ERROR: Failed to decrypt backup"
        rm -rf "${TEMP_EXTRACT_DIR}"
        exit 1
    fi
    BACKUP_TO_EXTRACT="${DECRYPTED_FILE}"
else
    BACKUP_TO_EXTRACT="${ROLLBACK_TARGET}"
fi

# Restore files
if [ "${DB_ONLY}" != true ]; then
    log "Restoring files from backup..."
    if tar -xzf "${BACKUP_TO_EXTRACT}" -C "${TEMP_EXTRACT_DIR}" 2>>"${ROLLBACK_LOG}"; then
        log "Files extracted successfully"

        # Backup current deployment directory
        if [ -d "${DEPLOYMENT_DIR}" ]; then
            mv "${DEPLOYMENT_DIR}" "${DEPLOYMENT_DIR}.rollback_backup_$(date +%Y%m%d_%H%M%S)"
        fi

        # Restore files
        mkdir -p "${DEPLOYMENT_DIR}"
        cp -r "${TEMP_EXTRACT_DIR}"/* "${DEPLOYMENT_DIR}/"

        log "File restoration completed"
    else
        log "ERROR: File extraction failed"
        rm -rf "${TEMP_EXTRACT_DIR}"
        exit 1
    fi
else
    # Extract to temp directory for database-only restore
    log "Extracting backup for database restore..."
    tar -xzf "${BACKUP_TO_EXTRACT}" -C "${TEMP_EXTRACT_DIR}" 2>>"${ROLLBACK_LOG}"
fi

# Restore database if requested
if [ "${NO_DATABASE}" != true ]; then
    if restore_database "${TEMP_EXTRACT_DIR}"; then
        log "Database restore completed"
    else
        log "WARNING: Database restore failed, but continuing with file restore"
    fi
fi

# Cleanup
rm -rf "${TEMP_EXTRACT_DIR}"

# Restart Bot
log "Starting trading bot..."
if sudo systemctl start trading-bot; then
    log "Trading bot started successfully"
else
    log "WARNING: Failed to start trading bot"
fi

# Post-Rollback Verification
log "Performing post-rollback verification..."
sleep 5  # Give the bot time to start

# Check service status
if sudo systemctl is-active --quiet trading-bot; then
    log "✓ Trading bot service is running"
else
    log "✗ Trading bot service is not running"
fi

# Check health endpoint
if command -v curl >/dev/null 2>&1; then
    if curl -f -s http://localhost:8082/health >/dev/null 2>&1; then
        log "✓ Health check passed"
        HEALTH_STATUS="PASS"
    else
        log "✗ Health check failed"
        HEALTH_STATUS="FAIL"
    fi
else
    log "WARNING: curl not available, skipping health check"
    HEALTH_STATUS="UNKNOWN"
fi

# Final summary
ROLLBACK_DURATION=$((SECONDS))

log "=== ROLLBACK SUMMARY ==="
log "Rollback target: ${ROLLBACK_TARGET}"
log "Deployment directory: ${DEPLOYMENT_DIR}"
log "Emergency backup: ${EMERGENCY_BACKUP_DIR}"
log "Duration: ${ROLLBACK_DURATION} seconds"
log "Service status: $(sudo systemctl is-active trading-bot)"
log "Health check: ${HEALTH_STATUS}"
log "Log file: ${ROLLBACK_LOG}"

if [ "${HEALTH_STATUS}" = "PASS" ]; then
    log "✓ Rollback completed successfully!"
    exit 0
elif [ "${HEALTH_STATUS}" = "UNKNOWN" ]; then
    log "⚠ Rollback completed, but health check unavailable"
    exit 0
else
    log "✗ Rollback completed but verification failed"
    log "Check the log file: ${ROLLBACK_LOG}"
    exit 1
fi
