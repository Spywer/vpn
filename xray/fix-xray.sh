#!/usr/bin/env bash
set -euo pipefail

# Быстрое исправление: ключи + права + перезапуск
# Запуск: sudo bash fix-xray.sh

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ENV_FILE="${CONFIG_DIR}/client.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/reality-keys.sh
source "${SCRIPT_DIR}/lib/reality-keys.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root: sudo bash fix-xray.sh"
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "Конфиг не найден: ${CONFIG_FILE}"
  echo "Сначала запустите generate-config.sh"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y jq
fi

echo "Генерация ключей..."
parse_reality_keys

echo "Private key: ${PRIVATE_KEY:0:12}..."
echo "Public key:  ${PUBLIC_KEY:0:12}..."

echo "Обновление config.json..."
tmp="$(mktemp)"
jq --arg pk "${PRIVATE_KEY}" \
  '.inbounds[0].streamSettings.realitySettings.privateKey = $pk' \
  "${CONFIG_FILE}" > "${tmp}"
mv "${tmp}" "${CONFIG_FILE}"

if [[ -f "${ENV_FILE}" ]]; then
  sed -i "s/^PUBLIC_KEY=.*/PUBLIC_KEY=${PUBLIC_KEY}/" "${ENV_FILE}" 2>/dev/null || true
fi

fix_xray_permissions

echo "Проверка конфига..."
xray run -test -config "${CONFIG_FILE}"

systemctl reset-failed xray 2>/dev/null || true
systemctl daemon-reload
systemctl restart xray
systemctl --no-pager status xray

PORT="$(jq -r '.inbounds[0].port' "${CONFIG_FILE}")"
if [[ -f "${CONFIG_DIR}/install.env" ]]; then
  # shellcheck disable=SC1091
  source "${CONFIG_DIR}/install.env"
fi
if [[ "${NGINX_MODE:-0}" == "1" && -n "${PUBLIC_PORT:-}" ]]; then
  PORT="${PUBLIC_PORT}"
fi
UUID="$(jq -r '.inbounds[0].settings.clients[0].id' "${CONFIG_FILE}")"
SNI="$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' "${CONFIG_FILE}")"
SHORT_ID="$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[] | select(. != "")' "${CONFIG_FILE}" | head -1)"
SERVER_IP="$(curl -4 -fsS ifconfig.me 2>/dev/null || curl -4 -fsS icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"

echo ""
echo "Клиентская ссылка:"
echo "vless://${UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F&type=tcp#VLESS-Reality-RU"
