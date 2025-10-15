#!/bin/bash

# scripts/backup.sh

# Configuration Variables
BACKUP_DIR="${BACKUP_DIR:-/home/tradingbot/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
PROJECT_DIR="${PROJECT_DIR:-~/Projects/MojoRust}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="mojorust-backup-${TIMESTAMP}.tar.gz"
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"

# Enhanced database configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-trading_bot}"
DB_USER="${DB_USER:-trading_user}"
DB_BACKUP_FORMAT="${DB_BACKUP_FORMAT:-custom}"  # custom, directory, or plain

# Command Line Options
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --retention-days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --stop-bot)
            STOP_BOT=true
            shift
            ;;
        --no-encrypt)
            NO_ENCRYPT=true
            shift
            ;;
        --database-only)
            DATABASE_ONLY=true
            shift
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --incremental)
            INCREMENTAL=true
            shift
            ;;
        --compress-level)
            COMPRESS_LEVEL="$2"
            shift 2
            ;;
        --db-format)
            DB_BACKUP_FORMAT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Expand tildes in paths
PROJECT_DIR=$(eval echo "${PROJECT_DIR}")
BACKUP_DIR=$(eval echo "${BACKUP_DIR}")

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Backup Process
log "Starting backup..."
log "Project directory: ${PROJECT_DIR}"
log "Backup directory: ${BACKUP_DIR}"

mkdir -p "${BACKUP_DIR}"

# Enhanced disk space check
REQUIRED_SPACE_MB=2048  # 2GB requirement
AVAILABLE_SPACE_KB=$(df -k "${BACKUP_DIR}" | awk 'NR==2 {print $4}')
AVAILABLE_SPACE_MB=$((AVAILABLE_SPACE_KB / 1024))

if [ "${AVAILABLE_SPACE_MB}" -lt "${REQUIRED_SPACE_MB}" ]; then
    log "ERROR: Not enough disk space in ${BACKUP_DIR}. Available: ${AVAILABLE_SPACE_MB}MB, Required: ${REQUIRED_SPACE_MB}MB"
    exit 1
fi

log "Disk space check passed: ${AVAILABLE_SPACE_MB}MB available"

if [ "${STOP_BOT}" = true ]; then
    log "Stopping trading bot..."
    if sudo systemctl stop trading-bot; then
        log "Trading bot stopped successfully"
    else
        log "WARNING: Failed to stop trading bot, continuing with backup"
    fi
fi

# Enhanced database backup function
backup_database() {
    local db_backup_file="${BACKUP_DIR}/db_backup_${TIMESTAMP}"

    log "Starting database backup..."
    log "Database: ${DB_NAME} on ${DB_HOST}:${DB_PORT}"
    log "Backup format: ${DB_BACKUP_FORMAT}"

    case "${DB_BACKUP_FORMAT}" in
        "custom")
            log "Creating compressed custom format backup..."
            if pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
                --format=custom --compress=9 --verbose --file="${db_backup_file}.dump" 2>&1 | tee -a "${LOG_FILE}"; then
                log "Database custom backup completed: ${db_backup_file}.dump"
                DB_BACKUP_FILE="${db_backup_file}.dump"
            else
                log "ERROR: Database custom backup failed"
                return 1
            fi
            ;;
        "directory")
            log "Creating directory format backup..."
            if pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
                --format=directory --file="${db_backup_file}_dir" --compress=9 --verbose 2>&1 | tee -a "${LOG_FILE}"; then
                log "Database directory backup completed: ${db_backup_file}_dir"
                DB_BACKUP_FILE="${db_backup_file}_dir"
            else
                log "ERROR: Database directory backup failed"
                return 1
            fi
            ;;
        "plain"|*)
            log "Creating plain SQL backup..."
            if pg_dump -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" \
                --format=plain --verbose --file="${db_backup_file}.sql" 2>&1 | tee -a "${LOG_FILE}"; then
                log "Database SQL backup completed: ${db_backup_file}.sql"
                DB_BACKUP_FILE="${db_backup_file}.sql"
            else
                log "ERROR: Database SQL backup failed"
                return 1
            fi
            ;;
    esac

    # Create database backup manifest
    cat > "${db_backup_file}_manifest.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "database": "${DB_NAME}",
    "host": "${DB_HOST}",
    "port": "${DB_PORT}",
    "user": "${DB_USER}",
    "format": "${DB_BACKUP_FORMAT}",
    "backup_file": "$(basename ${DB_BACKUP_FILE})",
    "size_bytes": $(du -b "${DB_BACKUP_FILE}" | cut -f1),
    "checksum": "$(sha256sum "${DB_BACKUP_FILE}" | cut -d' ' -f1)"
}
EOF

    return 0
}

# Enhanced file backup function
backup_files() {
    local include_db="${1:-false}"
    local tar_options=""
    local backup_list="${BACKUP_DIR}/backup_files_${TIMESTAMP}.txt"

    log "Creating file backup list..."

    # Create comprehensive backup list
    cat > "${backup_list}" << EOF
# Configuration files
.env*
config/
scripts/
Makefile
requirements.txt
Cargo.toml
Cargo.lock
rust-modules/

# Source code
src/
tests/
docs/

# Data directories (exclude large temporary files)
data/
logs/
backups/

# Exclusions
--exclude=*.pyc
--exclude=__pycache__/
--exclude=*.log
--exclude=node_modules/
--exclude=target/debug/
--exclude=target/release/
--exclude=.git/
--exclude=*.tmp
--exclude=*.cache
--exclude=.pytest_cache/
EOF

    # Add database backup to file backup if requested
    if [ "${include_db}" = "true" ] && [ -n "${DB_BACKUP_FILE}" ]; then
        echo "${DB_BACKUP_FILE}" >> "${backup_list}"
        echo "${DB_BACKUP_FILE}_manifest.json" >> "${backup_list}"
    fi

    # Set compression level
    if [ -n "${COMPRESS_LEVEL}" ]; then
        tar_options="-I 'gzip -${COMPRESS_LEVEL}'"
    else
        tar_options="-czf"
    fi

    log "Creating archive with options: ${tar_options}"

    if tar ${tar_options} "${BACKUP_DIR}/${BACKUP_NAME}" \
        -C "${PROJECT_DIR}" \
        --files-from="${backup_list}" \
        --exclude-backups \
        --exclude-vcs 2>&1 | tee -a "${LOG_FILE}"; then

        local archive_size=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)
        log "File backup completed: ${BACKUP_NAME} (${archive_size})"

        # Create backup manifest
        cat > "${BACKUP_DIR}/${BACKUP_NAME}_manifest.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "backup_type": "full",
    "backup_file": "${BACKUP_NAME}",
    "size_human": "${archive_size}",
    "size_bytes": $(du -b "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1),
    "project_dir": "${PROJECT_DIR}",
    "includes_database": ${include_db},
    "compression_level": "${COMPRESS_LEVEL:-default}",
    "checksum": "$(sha256sum "${BACKUP_DIR}/${BACKUP_NAME}" | cut -d' ' -f1)"
}
EOF

        rm -f "${backup_list}"
        return 0
    else
        log "ERROR: File backup failed"
        rm -f "${backup_list}"
        return 1
    fi
}

# Execute backup based on options
if [ "${DATABASE_ONLY}" = true ]; then
    if backup_database; then
        log "Database-only backup completed successfully"
        BACKUP_NAME="${DB_BACKUP_FILE}"
    else
        log "ERROR: Database backup failed"
        exit 1
    fi
else
    log "Starting comprehensive backup..."

    # Always backup database first
    if backup_database; then
        log "Database backup successful, proceeding with file backup"
        INCLUDE_DB_IN_FILES=true
    else
        log "WARNING: Database backup failed, proceeding with file backup only"
        INCLUDE_DB_IN_FILES=false
    fi

    # Backup files
    if backup_files "${INCLUDE_DB_IN_FILES}"; then
        log "Full backup completed successfully"
    else
        log "ERROR: File backup failed"
        exit 1
    fi
fi

# Enhanced encryption
if [ "${NO_ENCRYPT}" != true ]; then
    log "Encrypting backup with GPG..."
    if gpg --batch --yes --symmetric --cipher-algo AES256 \
        --s2k-mode 3 \
        --s2k-digest-algo SHA512 \
        --s2k-count 65536 \
        --compress-algo 9 \
        -o "${BACKUP_DIR}/${BACKUP_NAME}.gpg" "${BACKUP_DIR}/${BACKUP_NAME}" 2>&1 | tee -a "${LOG_FILE}"; then

        rm "${BACKUP_DIR}/${BACKUP_NAME}"
        BACKUP_NAME="${BACKUP_NAME}.gpg"
        log "Backup encryption completed"
    else
        log "WARNING: Backup encryption failed, keeping unencrypted backup"
    fi
fi

# Create checksum
log "Creating checksum..."
sha256sum "${BACKUP_DIR}/${BACKUP_NAME}" > "${BACKUP_DIR}/${BACKUP_NAME}.sha256"

# Enhanced verification
verify_backup() {
    log "Verifying backup integrity..."

    if [ "${NO_ENCRYPT}" != true ]; then
        log "Verifying encrypted backup..."
        if gpg --decrypt "${BACKUP_DIR}/${BACKUP_NAME}" 2>/dev/null | tar -tzf - > /dev/null 2>&1; then
            log "Encrypted backup verification successful"
            return 0
        else
            log "ERROR: Encrypted backup verification failed"
            return 1
        fi
    else
        log "Verifying unencrypted backup..."
        if tar -tzf "${BACKUP_DIR}/${BACKUP_NAME}" > /dev/null 2>&1; then
            log "Unencrypted backup verification successful"
            return 0
        else
            log "ERROR: Unencrypted backup verification failed"
            return 1
        fi
    fi
}

# Run verification if requested
if [ "${VERIFY}" = true ]; then
    if ! verify_backup; then
        log "ERROR: Backup verification failed"
        exit 1
    fi
fi

# Enhanced retention policy with logging
cleanup_old_backups() {
    log "Starting cleanup of old backups..."
    local deleted_count=0

    # Clean up old full backups
    while IFS= read -r -d '' backup_file; do
        log "Removing old backup: $(basename "${backup_file}")"
        rm "${backup_file}"
        ((deleted_count++))
    done < <(find "${BACKUP_DIR}" -type f -name "mojorust-backup-*.tar.gz*" -mtime +${RETENTION_DAYS} -print0 2>/dev/null)

    # Clean up old database-only backups
    while IFS= read -r -d '' backup_file; do
        log "Removing old database backup: $(basename "${backup_file}")"
        rm "${backup_file}"
        ((deleted_count++))
    done < <(find "${BACKUP_DIR}" -type f \( -name "db_backup_*.sql" -o -name "db_backup_*.dump" \) -mtime +${RETENTION_DAYS} -print0 2>/dev/null)

    # Clean up old log files
    while IFS= read -r -d '' log_file; do
        log "Removing old log file: $(basename "${log_file}")"
        rm "${log_file}"
        ((deleted_count++))
    done < <(find "${BACKUP_DIR}" -name "backup_*.log" -mtime +${RETENTION_DAYS} -print0 2>/dev/null)

    log "Cleanup completed: ${deleted_count} files removed"
}

cleanup_old_backups

# Restart trading bot if stopped
if [ "${STOP_BOT}" = true ]; then
    log "Starting trading bot..."
    if sudo systemctl start trading-bot; then
        log "Trading bot started successfully"
    else
        log "WARNING: Failed to start trading bot"
    fi
fi

# Final summary
FINAL_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}" | cut -f1)
BACKUP_DURATION=$((SECONDS))

log "=== BACKUP SUMMARY ==="
log "Backup completed: ${BACKUP_DIR}/${BACKUP_NAME}"
log "Final size: ${FINAL_SIZE}"
log "Duration: ${BACKUP_DURATION} seconds"
log "Log file: ${LOG_FILE}"

# Create backup index
cat > "${BACKUP_DIR}/latest_backup.json" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "backup_file": "${BACKUP_NAME}",
    "backup_dir": "${BACKUP_DIR}",
    "size": "${FINAL_SIZE}",
    "duration_seconds": ${BACKUP_DURATION},
    "backup_type": "$([ "${DATABASE_ONLY}" = true ] && echo "database-only" || echo "full")",
    "encrypted": $([ "${NO_ENCRYPT}" != true ] && echo "true" || echo "false"),
    "verified": $([ "${VERIFY}" = true ] && echo "true" || echo "false"),
    "project_dir": "${PROJECT_DIR}",
    "log_file": "${LOG_FILE}"
}
EOF

log "Backup index created: ${BACKUP_DIR}/latest_backup.json"
log "Backup process completed successfully!"
