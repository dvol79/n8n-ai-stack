#!/usr/bin/env bash
#
# Ежедневный бэкап стека n8n (PostgreSQL + .env)
# Запускается из cron, сохраняет архивы в ./backups, хранит последние N дней.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"
LOG_FILE="${BACKUP_DIR}/backup.log"

if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/.env"
  set +a
else
  echo "Ошибка: файл .env не найден в ${SCRIPT_DIR}" >&2
  exit 1
fi

RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-10}"
CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-n8n_ai_postgres}"

: "${POSTGRES_USER:?POSTGRES_USER не задан}"
: "${POSTGRES_DB:?POSTGRES_DB не задан}"

mkdir -p "${BACKUP_DIR}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  log "ОШИБКА: контейнер ${CONTAINER_NAME} не запущен."
  exit 1
fi

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/n8n_backup_${TIMESTAMP}.tar.gz"
TEMP_DIR=$(mktemp -d)

log "Начинаю комплексный бэкап (БД + .env) -> ${BACKUP_FILE}"

# 1. Копируем .env (обязательно для расшифровки n8n!)
cp "${SCRIPT_DIR}/.env" "${TEMP_DIR}/.env"

# 2. Делаем дамп базы
if docker exec "${CONTAINER_NAME}" pg_dump -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" --clean --if-exists > "${TEMP_DIR}/dump.sql"; then
  tar -czf "${BACKUP_FILE}" -C "${TEMP_DIR}" .
  SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
  log "Бэкап успешно создан. Размер: ${SIZE}"
else
  log "ОШИБКА: pg_dump завершился с ошибкой."
  rm -rf "${TEMP_DIR}"
  exit 1
fi

rm -rf "${TEMP_DIR}"

log "Удаляю бэкапы старше ${RETENTION_DAYS} дней..."
find "${BACKUP_DIR}" -maxdepth 1 -name 'n8n_backup_*.tar.gz' -type f -mtime +${RETENTION_DAYS} -delete
log "----- Готово -----"