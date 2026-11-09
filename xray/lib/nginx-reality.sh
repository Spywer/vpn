#!/usr/bin/env bash
# Nginx stream (ssl_preread) перед Xray Reality.
# Публичный 443 — Nginx. Сайт — 127.0.0.1:8443. Xray — 127.0.0.1:XRAY_PORT.

XRAY_CONFIG_DIR="${XRAY_CONFIG_DIR:-/usr/local/etc/xray}"
NGINX_INSTALL_ENV="${XRAY_CONFIG_DIR}/install.env"
NGINX_SNIS_FILE="${XRAY_CONFIG_DIR}/reality-snis.txt"
NGINX_MAIN_CONF="/etc/nginx/nginx.conf"
NGINX_STREAM_BEGIN="# BEGIN XRAY REALITY STREAM"
NGINX_STREAM_END="# END XRAY REALITY STREAM"

load_nginx_install_env() {
  NGINX_MODE=0
  if [[ -f "${NGINX_INSTALL_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${NGINX_INSTALL_ENV}"
  fi
  NGINX_MODE="${NGINX_MODE:-0}"
}

nginx_site_conf() {
  printf '/etc/nginx/conf.d/%s.conf' "${WEB_DOMAIN}"
}

write_install_env() {
  mkdir -p "${XRAY_CONFIG_DIR}"
  cat > "${NGINX_INSTALL_ENV}" <<EOF
NGINX_MODE=${NGINX_MODE}
WEB_DOMAIN=${WEB_DOMAIN:-}
WEB_WWW=${WEB_WWW:-0}
WEB_BACKEND=${WEB_BACKEND:-127.0.0.1:8080}
WEB_TLS_ADDR=${WEB_TLS_ADDR:-127.0.0.1:8443}
XRAY_BIND=${XRAY_BIND:-127.0.0.1}
XRAY_PORT=${XRAY_PORT:-10000}
PUBLIC_PORT=${PUBLIC_PORT:-443}
CERT_FILE=${CERT_FILE:-}
KEY_FILE=${KEY_FILE:-}
EOF
  chmod 640 "${NGINX_INSTALL_ENV}"
}

remove_stream_block() {
  local conf="${1:-${NGINX_MAIN_CONF}}"
  [[ -f "${conf}" ]] || return 0
  if grep -qF "${NGINX_STREAM_BEGIN}" "${conf}"; then
    sed -i "/${NGINX_STREAM_BEGIN}/,/${NGINX_STREAM_END}/d" "${conf}"
  fi
  # Старый вариант со внешним include
  sed -i '/xray-stream\.conf/d' "${conf}" 2>/dev/null || true
  rm -f /etc/nginx/xray-stream.conf
}

disable_public_443_sites() {
  local f dir site_name
  site_name="$(basename "$(nginx_site_conf)")"
  for dir in /etc/nginx/conf.d /etc/nginx/sites-enabled; do
    [[ -d "${dir}" ]] || continue
    for f in "${dir}"/*.conf; do
      [[ -f "${f}" ]] || continue
      [[ "$(basename "${f}")" == "${site_name}" ]] && continue
      if grep -Eq 'listen[[:space:]]+([^;]*:)?443\b' "${f}"; then
        echo "Отключаю ${f}: занимает публичный 443"
        mv "${f}" "${f}.off"
      fi
    done
  done
}

write_reality_snis() {
  mkdir -p "${XRAY_CONFIG_DIR}"
  : > "${NGINX_SNIS_FILE}"
  local host
  for host in "$@"; do
    [[ "${host}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    printf '%s\n' "${host}" >> "${NGINX_SNIS_FILE}"
  done
  chmod 640 "${NGINX_SNIS_FILE}"
}

write_stream_conf() {
  load_nginx_install_env
  local lines="" host www_line="" block
  if [[ "${WEB_WWW:-0}" == "1" ]]; then
    www_line="        www.${WEB_DOMAIN} web;"$'\n'
  fi
  if [[ -f "${NGINX_SNIS_FILE}" ]]; then
    while IFS= read -r host; do
      [[ -z "${host}" ]] && continue
      lines+="        ${host} vpn;"$'\n'
    done < "${NGINX_SNIS_FILE}"
  fi

  remove_stream_block "${NGINX_MAIN_CONF}"

  block="$(cat <<EOF

${NGINX_STREAM_BEGIN}
# Сгенерировано install-server.sh / generate-config.sh
stream {
    map \$ssl_preread_server_name \$xray_backend {
        ${WEB_DOMAIN} web;
${www_line}${lines}        default web;
    }

    upstream web { server ${WEB_TLS_ADDR}; }
    upstream vpn { server ${XRAY_BIND}:${XRAY_PORT}; }

    server {
        listen 443;
        listen [::]:443;
        proxy_pass \$xray_backend;
        ssl_preread on;
        proxy_socket_keepalive on;
        proxy_timeout 1h;
    }
}
${NGINX_STREAM_END}
EOF
)"
  printf '%s\n' "${block}" >> "${NGINX_MAIN_CONF}"
}

write_web_site_conf() {
  load_nginx_install_env
  local names="${WEB_DOMAIN}" site_conf
  if [[ "${WEB_WWW:-0}" == "1" ]]; then
    names="${names} www.${WEB_DOMAIN}"
  fi

  site_conf="$(nginx_site_conf)"
  mkdir -p /etc/nginx/conf.d
  # Старое имя конфига
  rm -f /etc/nginx/conf.d/xray-reality-web.conf \
    /etc/nginx/sites-enabled/xray-reality-web.conf \
    /etc/nginx/sites-available/xray-reality-web.conf

  cat > "${site_conf}" <<EOF
# Сгенерировано install-server.sh
server {
    listen 80;
    listen [::]:80;
    server_name ${names};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen ${WEB_TLS_ADDR} ssl;
    http2 on;
    server_name ${names};

    ssl_certificate     ${CERT_FILE};
    ssl_certificate_key ${KEY_FILE};
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://${WEB_BACKEND};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
}

reload_nginx() {
  nginx -t
  systemctl enable nginx
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx
  else
    systemctl restart nginx
  fi
}

disable_nginx_reality() {
  load_nginx_install_env
  remove_stream_block "${NGINX_MAIN_CONF}"
  if [[ -n "${WEB_DOMAIN:-}" ]]; then
    rm -f "$(nginx_site_conf)"
  fi
  rm -f /etc/nginx/conf.d/xray-reality-web.conf \
    /etc/nginx/sites-enabled/xray-reality-web.conf \
    /etc/nginx/sites-available/xray-reality-web.conf
  if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
    nginx -t
    systemctl reload nginx
  fi
}

apply_nginx_reality() {
  disable_public_443_sites
  write_stream_conf
  write_web_site_conf
  reload_nginx
}
