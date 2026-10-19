#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
ENV_FILE="${SCRIPT_DIR}/.env"

if [[ ! -f "${ENV_EXAMPLE}" ]]; then
  echo "❌ Ошибка: не найден ${ENV_EXAMPLE}" >&2
  exit 1
fi

if [[ -f "${ENV_FILE}" ]]; then
  echo "⚠️  Файл .env уже существует."
  read -r -p "   Перезаписать его? Все текущие секреты будут потеряны! [y/N] " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "Отменено."
    exit 0
  fi
  cp "${ENV_FILE}" "${ENV_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  echo "   Старый .env сохранён в .env.bak.*"
fi

gen_password() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '\n=+/' | cut -c1-32
  else
    LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
  fi
}

gen_encryption_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '\n'
  else
    head -c 32 /dev/urandom | base64 | tr -d '\n'
  fi
}

echo "🔐 Генерирую секреты..."
POSTGRES_PASSWORD="$(gen_password)"
N8N_ENCRYPTION_KEY="$(gen_encryption_key)"
QDRANT_API_KEY="$(gen_password)"
LITELLM_MASTER_KEY="sk-$(gen_password)"

cp "${ENV_EXAMPLE}" "${ENV_FILE}"
tmp="$(mktemp)"

while IFS= read -r line; do
  case "${line}" in
    POSTGRES_PASSWORD=*)
      echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> "${tmp}"
      ;;
    N8N_ENCRYPTION_KEY=*)
      echo "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}" >> "${tmp}"
      ;;
    QDRANT_API_KEY=*)
      echo "QDRANT_API_KEY=${QDRANT_API_KEY}" >> "${tmp}"
      ;;
    LITELLM_MASTER_KEY=*)
      echo "LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}" >> "${tmp}"
      ;;
    *)
      echo "${line}" >> "${tmp}"
      ;;
  esac
done < "${ENV_EXAMPLE}"

mv "${tmp}" "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

echo
echo "✅ Файл .env успешно создан."
echo "📋 Сохрани эти ключи (особенно N8N_ENCRYPTION_KEY и LITELLM_MASTER_KEY):"
echo "   POSTGRES_PASSWORD    : ${POSTGRES_PASSWORD}"
echo "   N8N_ENCRYPTION_KEY   : ${N8N_ENCRYPTION_KEY}"
echo "   QDRANT_API_KEY       : ${QDRANT_API_KEY}"
echo "   LITELLM_MASTER_KEY   : ${LITELLM_MASTER_KEY}"
echo
echo "⚠️  Не забудь вручную вписать PROVIDER_API_KEY в файл .env!"
echo "🚀 Далее: docker compose up -d"