#!/usr/bin/env bash
set -euo pipefail

# Смена порта Xray на уже настроенном сервере
# Запуск: sudo bash change-port.sh [порт]
# По умолчанию: 443

CONFIG="/usr/local/etc/xray/config.json"
ENV_FILE="/usr/local/etc/xray/client.env"
NEW_PORT="${1:-443}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/nginx-reality.sh
source "${SCRIPT_DIR}/lib/nginx-reality.sh"
load_nginx_install_env

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root: sudo bash change-port.sh ${NEW_PORT}"
  exit 1
fi

if [[ ! -f "${CONFIG}" ]]; then
  echo "Конфиг не найден: ${CONFIG}"
  exit 1
fi

command -v jq >/dev/null 2>&1 || apt-get update -qq && apt-get install -y jq

if [[ "${NGINX_MODE}" == "1" ]]; then
  if [[ "${NEW_PORT}" == "80" || "${NEW_PORT}" == "443" || "${NEW_PORT}" == "${WEB_TLS_ADDR##*:}" ]]; then
    echo "В режиме Nginx внутренний порт Xray не может быть 80, 443 или ${WEB_TLS_ADDR##*:}."
    echo "Публичный порт клиентов: ${PUBLIC_PORT}."
    exit 1
  fi
fi

OLD_PORT="$(jq -r '.inbounds[] | select(.protocol == "vless") | .port' "${CONFIG}" | head -1)"
echo "Порт: ${OLD_PORT} → ${NEW_PORT}"

tmp="$(mktemp)"
jq --argjson port "${NEW_PORT}" '
  .inbounds |= map(
    if .protocol == "vless" then .port = $port else . end
  )
' "${CONFIG}" > "${tmp}"
mv "${tmp}" "${CONFIG}"

if [[ "${NGINX_MODE}" == "1" ]]; then
  XRAY_PORT="${NEW_PORT}"
  write_install_env
  write_stream_conf
  nginx -t
  systemctl reload nginx
  if [[ -f "${ENV_FILE}" ]]; then
    sed -i "s/^XRAY_PORT=.*/XRAY_PORT=${NEW_PORT}/" "${ENV_FILE}"
  fi
  echo "Публичный порт клиентов остаётся ${PUBLIC_PORT}."
elif [[ -f "${ENV_FILE}" ]]; then
  sed -i "s/^PORT=.*/PORT=${NEW_PORT}/" "${ENV_FILE}"
fi

# shellcheck source=lib/reality-keys.sh
source "${SCRIPT_DIR}/lib/reality-keys.sh"
fix_xray_permissions

xray run -test -config "${CONFIG}"

if [[ "${NGINX_MODE}" != "1" ]] && command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow "${NEW_PORT}/tcp" 2>/dev/null || true
  if [[ -n "${OLD_PORT}" && "${OLD_PORT}" != "${NEW_PORT}" ]]; then
    ufw delete allow "${OLD_PORT}/tcp" 2>/dev/null || true
  fi
fi

systemctl restart xray
systemctl --no-pager status xray

echo ""
if [[ "${NGINX_MODE}" == "1" ]]; then
  echo "Готово. Клиенты по-прежнему подключаются на порт ${PUBLIC_PORT}."
else
  echo "Готово. Откройте ${NEW_PORT}/tcp в панели VPS."
  echo "Обновите ссылки клиентов: sudo bash clients.sh link <имя>"
fi
