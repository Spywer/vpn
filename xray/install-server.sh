#!/usr/bin/env bash
set -euo pipefail

# Xray VLESS-Reality — установка на Ubuntu/Debian VPS
# Запуск: sudo bash install-server.sh

XRAY_VERSION="${XRAY_VERSION:-latest}"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/usr/local/etc/xray"
SERVICE_NAME="xray"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/nginx-reality.sh
source "${SCRIPT_DIR}/lib/nginx-reality.sh"

setup_nginx_mode() {
  local domain www_answer backend cert_answer

  read -rp "Домен сайта (A-запись на этот VPS): " domain
  if [[ ! "${domain}" =~ ^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)+$ ]]; then
    echo "Некорректный домен: ${domain}"
    exit 1
  fi

  www_answer="y"
  if [[ "${domain}" != www.* ]]; then
    read -rp "Добавить www.${domain}? [Y/n]: " www_answer
    www_answer="${www_answer:-y}"
  else
    www_answer="n"
  fi

  read -rp "HTTP-бэкенд сайта [127.0.0.1:8080]: " backend
  backend="${backend:-127.0.0.1:8080}"
  if [[ ! "${backend}" =~ ^[A-Za-z0-9._-]+:[0-9]+$ ]]; then
    echo "Некорректный бэкенд: ${backend} (ожидается host:port)"
    exit 1
  fi

  NGINX_MODE=1
  WEB_DOMAIN="${domain}"
  WEB_WWW=0
  [[ "${www_answer}" =~ ^[Yy]$ ]] && WEB_WWW=1
  WEB_BACKEND="${backend}"
  WEB_TLS_ADDR="127.0.0.1:8443"
  XRAY_BIND="127.0.0.1"
  XRAY_PORT="10000"
  PUBLIC_PORT="443"

  mkdir -p "/etc/nginx/ssl" /var/www/html
  CERT_FILE="/etc/nginx/ssl/${domain}.crt"
  KEY_FILE="/etc/nginx/ssl/${domain}.key"
  if [[ ! -f "${CERT_FILE}" || ! -f "${KEY_FILE}" ]]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
      -keyout "${KEY_FILE}" -out "${CERT_FILE}" \
      -subj "/CN=${domain}" >/dev/null 2>&1
    chmod 600 "${KEY_FILE}"
  fi

  write_install_env
  write_reality_snis
  apply_nginx_reality

  read -rp "Получить сертификат Let's Encrypt сейчас? [y/N]: " cert_answer
  cert_answer="${cert_answer:-n}"
  if [[ "${cert_answer}" =~ ^[Yy]$ ]]; then
    apt-get install -y certbot
    local -a cert_domains=(-d "${domain}")
    [[ "${WEB_WWW}" == "1" ]] && cert_domains+=(-d "www.${domain}")
    if certbot certonly --webroot -w /var/www/html "${cert_domains[@]}" \
      --non-interactive --agree-tos --register-unsafely-without-email; then
      CERT_FILE="/etc/letsencrypt/live/${domain}/fullchain.pem"
      KEY_FILE="/etc/letsencrypt/live/${domain}/privkey.pem"
      write_install_env
      write_web_site_conf
      reload_nginx
      echo "Сертификат Let's Encrypt установлен."
    else
      echo "Certbot не получил сертификат. Nginx остаётся на самоподписанном."
      echo "Повторите позже: certbot certonly --webroot -w /var/www/html -d ${domain}"
    fi
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp || true
    ufw allow 443/tcp || true
  fi
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите скрипт от root: sudo bash install-server.sh"
  exit 1
fi

NGINX_CHOICE="1"
if [[ -t 0 ]]; then
  echo ""
  echo "Как занять порт 443:"
  echo "  1) Xray напрямую"
  echo "  2) Через Nginx (сайт и Reality на одном 443)"
  read -rp "Выбор [1]: " NGINX_CHOICE
  NGINX_CHOICE="${NGINX_CHOICE:-1}"
fi

PACKAGES=(curl jq uuid-runtime openssl ca-certificates unzip)
if [[ "${NGINX_CHOICE}" == "2" ]]; then
  PACKAGES+=(nginx)
fi

apt-get update -qq
apt-get install -y "${PACKAGES[@]}"

ARCH="$(uname -m)"
case "${ARCH}" in
  x86_64)  XRAY_ARCH="64" ;;
  aarch64) XRAY_ARCH="arm64-v8a" ;;
  armv7l)  XRAY_ARCH="arm32-v7a" ;;
  *)
    echo "Неподдерживаемая архитектура: ${ARCH}"
    exit 1
    ;;
esac

ASSET_NAME="Xray-linux-${XRAY_ARCH}.zip"
if [[ "${XRAY_VERSION}" == "latest" ]]; then
  RELEASE_URL="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r --arg name "${ASSET_NAME}" '.assets[] | select(.name == $name) | .browser_download_url')"
else
  RELEASE_URL="https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/${ASSET_NAME}"
fi

if [[ -z "${RELEASE_URL}" || "${RELEASE_URL}" == "null" ]]; then
  echo "Не удалось найти релиз Xray для ${ASSET_NAME}"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
curl -fsSL "${RELEASE_URL}" -o "${TMP_DIR}/xray.zip"
unzip -q "${TMP_DIR}/xray.zip" -d "${TMP_DIR}"
install -m 755 "${TMP_DIR}/xray" "${INSTALL_DIR}/xray"
rm -rf "${TMP_DIR}"

mkdir -p "${CONFIG_DIR}"

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
Type=simple
User=nobody
Group=nogroup
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=${INSTALL_DIR}/xray run -config ${CONFIG_DIR}/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
# Чтение конфига: root:nogroup, chmod 640 (задаётся в generate-config.sh)

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

if [[ "${NGINX_CHOICE}" == "2" ]]; then
  setup_nginx_mode
else
  NGINX_MODE=0
  write_install_env
  disable_nginx_reality
fi

echo ""
echo "Xray установлен: $(${INSTALL_DIR}/xray version | head -1)"
if [[ "${NGINX_MODE:-0}" == "1" ]]; then
  echo "Nginx слушает 443 и разводит трафик по SNI."
  echo "Сайт:  ${WEB_DOMAIN} → ${WEB_BACKEND} (TLS на ${WEB_TLS_ADDR})"
  echo "Xray:  ${XRAY_BIND}:${XRAY_PORT} (клиенты подключаются на ${PUBLIC_PORT})"
fi
echo "Далее запустите: sudo bash generate-config.sh"
