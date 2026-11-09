#!/usr/bin/env bash
set -euo pipefail

# Генерация конфига Xray VLESS-Reality (профиль для РФ)
# Запуск на VPS: sudo bash generate-config.sh

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ENV_FILE="${CONFIG_DIR}/client.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/reality-keys.sh
source "${SCRIPT_DIR}/lib/reality-keys.sh"
# shellcheck source=lib/nginx-reality.sh
source "${SCRIPT_DIR}/lib/nginx-reality.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root: sudo bash generate-config.sh"
  exit 1
fi

if ! command -v xray >/dev/null 2>&1; then
  echo "Xray не найден. Сначала запустите install-server.sh"
  exit 1
fi

echo ""
echo "Профиль устойчивости к блокировкам:"
echo "  ru   — для клиентов из России (рекомендуется)"
echo "  intl — для остальных регионов"
read -rp "Профиль [ru]: " PROFILE
PROFILE="${PROFILE:-ru}"

load_nginx_install_env
if [[ "${NGINX_MODE}" == "1" ]]; then
  PORT="${PUBLIC_PORT}"
  LISTEN_ADDR="${XRAY_BIND}"
  LISTEN_PORT="${XRAY_PORT}"
  echo "Режим Nginx: клиенты на порту ${PORT}, Xray слушает ${LISTEN_ADDR}:${LISTEN_PORT}"
else
  read -rp "Порт Xray [443]: " PORT
  PORT="${PORT:-443}"
  LISTEN_ADDR="0.0.0.0"
  LISTEN_PORT="${PORT}"
fi

read -rp "UUID клиента (Enter = сгенерировать): " CLIENT_UUID
if [[ -z "${CLIENT_UUID}" ]]; then
  CLIENT_UUID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
fi

echo ""
if [[ "${PROFILE}" == "ru" ]]; then
  echo "SNI/dest из whitelist (сайты доступны в РФ, не ассоциированы с VPN):"
  echo "  1) www.apple.com:443          (рекомендуется)"
  echo "  2) www.bing.com:443"
  echo "  3) update.microsoft.com:443"
  echo "  4) www.microsoft.com:443"
  echo "  5) gateway.icloud.com:443"
  echo "  6) www.samsung.com:443"
  echo "  7) Свой (проверьте доступность из РФ)"
  read -rp "Выбор [1]: " DEST_CHOICE
  DEST_CHOICE="${DEST_CHOICE:-1}"

  case "${DEST_CHOICE}" in
    1) DEST="www.apple.com:443"; SNI="www.apple.com"; EXTRA_SNIS='"apple.com"' ;;
    2) DEST="www.bing.com:443"; SNI="www.bing.com"; EXTRA_SNIS="" ;;
    3) DEST="update.microsoft.com:443"; SNI="update.microsoft.com"; EXTRA_SNIS="" ;;
    4) DEST="www.microsoft.com:443"; SNI="www.microsoft.com"; EXTRA_SNIS='"microsoft.com"' ;;
    5) DEST="gateway.icloud.com:443"; SNI="gateway.icloud.com"; EXTRA_SNIS="" ;;
    6) DEST="www.samsung.com:443"; SNI="www.samsung.com"; EXTRA_SNIS="" ;;
    7)
      read -rp "dest (host:443): " DEST
      SNI="${DEST%%:*}"
      EXTRA_SNIS=""
      ;;
    *) DEST="www.apple.com:443"; SNI="www.apple.com"; EXTRA_SNIS='"apple.com"' ;;
  esac

  # Пустой shortId + случайный — повышает совместимость с разными клиентами
  SHORT_ID="$(openssl rand -hex 4)"
  SHORT_IDS_JSON="\"\", \"${SHORT_ID}\""
  SPIDER_X="/"
  FINGERPRINT="chrome"
else
  echo "Выберите сайт-маскировку (SNI / dest):"
  echo "  1) www.apple.com:443"
  echo "  2) www.cloudflare.com:443"
  echo "  3) www.microsoft.com:443"
  echo "  4) www.samsung.com:443"
  echo "  5) Свой"
  read -rp "Выбор [1]: " DEST_CHOICE
  DEST_CHOICE="${DEST_CHOICE:-1}"

  case "${DEST_CHOICE}" in
    1) DEST="www.apple.com:443"; SNI="www.apple.com"; EXTRA_SNIS="" ;;
    2) DEST="www.cloudflare.com:443"; SNI="www.cloudflare.com"; EXTRA_SNIS="" ;;
    3) DEST="www.microsoft.com:443"; SNI="www.microsoft.com"; EXTRA_SNIS="" ;;
    4) DEST="www.samsung.com:443"; SNI="www.samsung.com"; EXTRA_SNIS="" ;;
    5)
      read -rp "dest (host:443): " DEST
      SNI="${DEST%%:*}"
      EXTRA_SNIS=""
      ;;
    *) DEST="www.apple.com:443"; SNI="www.apple.com"; EXTRA_SNIS="" ;;
  esac

  SHORT_ID="$(openssl rand -hex 8)"
  SHORT_IDS_JSON="\"${SHORT_ID}\""
  SPIDER_X=""
  FINGERPRINT="chrome"
fi

echo "Генерация ключей Reality..."
parse_reality_keys
echo "Private key: ${PRIVATE_KEY:0:12}..."
echo "Public key:  ${PUBLIC_KEY:0:12}..."

SERVER_IP="$(curl -4 -fsS ifconfig.me 2>/dev/null || curl -4 -fsS icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')"

mkdir -p "${CONFIG_DIR}"

if [[ -n "${EXTRA_SNIS}" ]]; then
  SERVER_NAMES="\"${SNI}\", ${EXTRA_SNIS}"
else
  SERVER_NAMES="\"${SNI}\""
fi

cat > "${CONFIG_FILE}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "${LISTEN_ADDR}",
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${CLIENT_UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DEST}",
          "xver": 0,
          "serverNames": [
            ${SERVER_NAMES}
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            ${SHORT_IDS_JSON}
          ],
          "maxTimeDiff": 60000,
          "spiderX": "${SPIDER_X:-/}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

cat > "${ENV_FILE}" <<EOF
PROFILE=${PROFILE}
SERVER_IP=${SERVER_IP}
PORT=${PORT}
NGINX_MODE=${NGINX_MODE}
PUBLIC_PORT=${PORT}
XRAY_PORT=${LISTEN_PORT}
UUID=${CLIENT_UUID}
PUBLIC_KEY=${PUBLIC_KEY}
SHORT_ID=${SHORT_ID}
SNI=${SNI}
FLOW=xtls-rprx-vision
FINGERPRINT=${FINGERPRINT}
SPIDER_X=${SPIDER_X}
EOF

chmod 640 "${CONFIG_FILE}"
chmod 640 "${ENV_FILE}"
fix_xray_permissions

echo ""
echo "Проверка конфига..."
if ! xray run -test -config "${CONFIG_FILE}"; then
  echo ""
  echo "Конфиг невалиден. Сервис не перезапускался."
  exit 1
fi

if [[ "${NGINX_MODE}" == "1" ]]; then
  sni_args=("${SNI}")
  if [[ -n "${EXTRA_SNIS}" ]]; then
    extra_host="${EXTRA_SNIS//\"/}"
    sni_args+=("${extra_host}")
  fi
  if [[ "${SNI}" == "${WEB_DOMAIN}" || "${extra_host:-}" == "${WEB_DOMAIN}" ]]; then
    echo "SNI совпадает с доменом сайта. Этот SNI уйдёт в Xray, сайт по нему открываться не будет."
  fi
  write_reality_snis "${sni_args[@]}"
  write_stream_conf
  nginx -t
  systemctl reload nginx
fi

systemctl daemon-reload
if ! systemctl restart xray; then
  echo ""
  echo "Сервис не запустился. Смотрите:"
  echo "  journalctl -u xray -n 30 --no-pager"
  exit 1
fi
systemctl --no-pager --full status xray || true

VLESS_URI="vless://${CLIENT_UUID}@${SERVER_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=${FINGERPRINT}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&spx=%2F&type=tcp#VLESS-Reality-RU"

echo ""
echo "=========================================="
echo " Сервер настроен (профиль: ${PROFILE})"
echo "=========================================="
echo "IP:          ${SERVER_IP}"
echo "Port:        ${PORT}"
echo "UUID:        ${CLIENT_UUID}"
echo "Public key:  ${PUBLIC_KEY}"
echo "Short ID:    ${SHORT_ID}  (также поддерживается пустой)"
echo "SNI:         ${SNI}"
echo "Flow:        xtls-rprx-vision"
echo "Fingerprint: ${FINGERPRINT}"
echo ""
echo "Клиентская ссылка (v2rayN / Nekoray / Hiddify):"
echo "${VLESS_URI}"
echo ""
echo "Параметры: ${ENV_FILE}"
echo ""
if [[ "${NGINX_MODE}" == "1" ]]; then
  echo "Nginx: 443/tcp. Сайт ${WEB_DOMAIN} → ${WEB_BACKEND}. Xray ${LISTEN_ADDR}:${LISTEN_PORT}."
else
  echo "Откройте порт ${PORT}/tcp в ufw и панели VPS."
fi

if [[ "${PROFILE}" == "ru" ]]; then
  echo ""
  echo "=========================================="
  echo " Рекомендации для клиентов из РФ"
  echo "=========================================="
  echo "1. В v2rayN включите: Параметры → Fragment → tlshello"
  echo "   (length 100-200, interval 10-20) — обход лимита ~16 KB на TCP."
  echo "2. Используйте TUN Mode, fingerprint chrome."
  echo "3. Избегайте VPS у Hetzner/DO/OVH — часто в «чёрных» списках."
  echo "   Лучше: Турция, Казахстан, Финляндия, менее известные DC."
  echo "4. Если мобильный интернет «замирает» после 15-20 KB —"
  echo "   нужен мост: RU VPS → ваш зарубежный сервер (см. vpn/xray/bridge-ru.md)."
  echo "5. Проверьте лимит провайдера: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/"
fi
