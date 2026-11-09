#!/usr/bin/env bash

CONFIG_DIR="/usr/local/etc/xray"
CONFIG_FILE="${CONFIG_DIR}/config.json"
ENV_FILE="${CONFIG_DIR}/client.env"

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Запустите от root: sudo bash clients.sh ..." >&2
    exit 1
  fi
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 || {
    apt-get update -qq && apt-get install -y jq
  }
}

ensure_config() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Конфиг не найден: ${CONFIG_FILE}" >&2
    echo "Сначала запустите generate-config.sh" >&2
    exit 1
  fi
}

# shellcheck source=lib/reality-keys.sh
source_clients_lib() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/reality-keys.sh
  source "${script_dir}/lib/reality-keys.sh"
}

load_server_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
  fi

  SERVER_IP="${SERVER_IP:-$(curl -4 -fsS ifconfig.me 2>/dev/null || curl -4 -fsS icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}')}"
  if [[ "${NGINX_MODE:-0}" == "1" && -n "${PUBLIC_PORT:-}" ]]; then
    PORT="${PUBLIC_PORT}"
  else
    PORT="$(jq -r '.inbounds[] | select(.protocol == "vless") | .port' "${CONFIG_FILE}" | head -1)"
  fi
  SNI="$(jq -r '.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.serverNames[0]' "${CONFIG_FILE}")"
  SHORT_ID="$(jq -r '.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.shortIds[] | select(. != "")' "${CONFIG_FILE}" | head -1)"
  FINGERPRINT="${FINGERPRINT:-chrome}"

  if [[ -z "${PUBLIC_KEY:-}" ]]; then
    local private_key derived
    private_key="$(jq -r '.inbounds[] | select(.protocol == "vless") | .streamSettings.realitySettings.privateKey' "${CONFIG_FILE}")"
    if [[ -n "${private_key}" && "${private_key}" != "null" && "${private_key}" != "" ]]; then
      derived="$(xray x25519 -i "${private_key}" 2>&1 || true)"
      PUBLIC_KEY="$(printf '%s\n' "${derived}" | awk -F':' '/Password|Public key/ {sub(/^[^:]*:[[:space:]]*/,""); gsub(/^[ \t]+|[ \t]+$/,""); print; exit}')"
    fi
  fi
}

build_vless_uri() {
  local uuid="$1"
  local name="$2"
  local tag
  tag="$(echo "${name}" | sed 's/ /_/g')"
  printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=%s&pbk=%s&sid=%s&spx=%%2F&type=tcp#%s' \
    "${uuid}" "${SERVER_IP}" "${PORT}" "${SNI}" "${FINGERPRINT}" "${PUBLIC_KEY}" "${SHORT_ID}" "${tag}"
}

apply_config() {
  local tmp
  tmp="$(mktemp)"
  jq '.' "${CONFIG_FILE}" > "${tmp}"
  mv "${tmp}" "${CONFIG_FILE}"
  source_clients_lib
  fix_xray_permissions
  xray run -test -config "${CONFIG_FILE}"
  systemctl reset-failed xray 2>/dev/null || true
  systemctl restart xray
}

cmd_list() {
  ensure_config
  ensure_jq
  local count
  count="$(jq '[.inbounds[] | select(.protocol == "vless") | .settings.clients[]] | length' "${CONFIG_FILE}")"

  echo "Клиентов: ${count}"
  echo ""
  printf "%-4s %-38s %-20s\n" "№" "UUID" "Имя (email)"
  printf "%-4s %-38s %-20s\n" "--" "------------------------------------" "--------------------"

  jq -r '
    [.inbounds[] | select(.protocol == "vless") | .settings.clients[]]
    | to_entries[]
    | "\(.key + 1)\t\(.value.id)\t\(.value.email // "-")"
  ' "${CONFIG_FILE}" | while IFS=$'\t' read -r num uuid email; do
    printf "%-4s %-38s %-20s\n" "${num}" "${uuid}" "${email}"
  done
}

cmd_add() {
  ensure_root
  ensure_config
  ensure_jq

  local name uuid tmp
  name="${1:-}"
  if [[ -z "${name}" ]]; then
    read -rp "Имя клиента (например: megafon-phone): " name
  fi
  if [[ -z "${name}" ]]; then
    name="client-$(date +%Y%m%d-%H%M%S)"
  fi

  uuid="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  if jq -e --arg id "${uuid}" '[.inbounds[] | select(.protocol == "vless") | .settings.clients[]] | any(.id == $id)' "${CONFIG_FILE}" >/dev/null; then
    echo "Клиент с таким UUID уже существует." >&2
    exit 1
  fi

  tmp="$(mktemp)"
  jq --arg id "${uuid}" --arg email "${name}" '
    .inbounds |= map(
      if .protocol == "vless" then
        .settings.clients += [{"id": $id, "flow": "xtls-rprx-vision", "email": $email}]
      else .
      end
    )
  ' "${CONFIG_FILE}" > "${tmp}"
  mv "${tmp}" "${CONFIG_FILE}"

  echo "Клиент добавлен:"
  echo "  Имя:  ${name}"
  echo "  UUID: ${uuid}"
  echo ""

  apply_config
  cmd_link "${uuid}"
}

cmd_remove() {
  ensure_root
  ensure_config
  ensure_jq

  local query="$1"
  if [[ -z "${query}" ]]; then
    cmd_list
    echo ""
    read -rp "UUID или имя клиента для удаления: " query
  fi
  if [[ -z "${query}" ]]; then
    echo "Укажите UUID или имя." >&2
    exit 1
  fi

  local count_before removed_uuid removed_name tmp
  count_before="$(jq '[.inbounds[] | select(.protocol == "vless") | .settings.clients[]] | length' "${CONFIG_FILE}")"

  removed_uuid="$(jq -r --arg q "${query}" "
    [.inbounds[] | select(.protocol == \"vless\") | .settings.clients[]]
    | map(select(.id == \$q or .email == \$q))
    | .[0].id // empty
  " "${CONFIG_FILE}")"

  if [[ -z "${removed_uuid}" ]]; then
    echo "Клиент не найден: ${query}" >&2
    exit 1
  fi

  removed_name="$(jq -r --arg id "${removed_uuid}" "
    [.inbounds[] | select(.protocol == \"vless\") | .settings.clients[]]
    | map(select(.id == \$id)) | .[0].email // \"-\"
  " "${CONFIG_FILE}")"

  tmp="$(mktemp)"
  jq --arg id "${removed_uuid}" '
    .inbounds |= map(
      if .protocol == "vless" then
        .settings.clients |= map(select(.id != $id))
      else .
      end
    )
  ' "${CONFIG_FILE}" > "${tmp}"
  mv "${tmp}" "${CONFIG_FILE}"

  if [[ "$(jq '[.inbounds[] | select(.protocol == "vless") | .settings.clients[]] | length' "${CONFIG_FILE}")" -eq 0 ]]; then
    echo "Внимание: клиентов не осталось. Добавьте нового: sudo bash clients.sh add" >&2
  fi

  echo "Удалён клиент:"
  echo "  Имя:  ${removed_name}"
  echo "  UUID: ${removed_uuid}"
  echo ""

  apply_config
}

cmd_link() {
  ensure_config
  ensure_jq
  load_server_env

  local query="${1:-}"
  if [[ -z "${query}" ]]; then
    cmd_list
    echo ""
    read -rp "UUID или имя клиента: " query
  fi
  if [[ -z "${query}" ]]; then
    echo "Укажите UUID или имя." >&2
    exit 1
  fi

  local uuid name
  uuid="$(jq -r --arg q "${query}" "
    [.inbounds[] | select(.protocol == \"vless\") | .settings.clients[]]
    | map(select(.id == \$q or .email == \$q))
    | .[0].id // empty
  " "${CONFIG_FILE}")"

  if [[ -z "${uuid}" ]]; then
    echo "Клиент не найден: ${query}" >&2
    exit 1
  fi

  name="$(jq -r --arg id "${uuid}" "
    [.inbounds[] | select(.protocol == \"vless\") | .settings.clients[]]
    | map(select(.id == \$id)) | .[0].email // \"client\"
  " "${CONFIG_FILE}")"

  if [[ -z "${PUBLIC_KEY:-}" ]]; then
    echo "Public key не найден. Запустите fix-xray.sh" >&2
    exit 1
  fi

  echo "Клиент: ${name}"
  echo "UUID:   ${uuid}"
  echo ""
  build_vless_uri "${uuid}" "${name}"
  echo ""
}

cmd_help() {
  cat <<'EOF'
Управление клиентами Xray VLESS-Reality

  sudo bash clients.sh list              — список клиентов
  sudo bash clients.sh add [имя]         — добавить клиента
  sudo bash clients.sh remove <uuid|имя> — удалить клиента
  sudo bash clients.sh link [uuid|имя]   — показать vless:// ссылку

Примеры:
  sudo bash clients.sh list
  sudo bash clients.sh add megafon-phone
  sudo bash clients.sh link megafon-phone
  sudo bash clients.sh remove 465d4081-e220-494b-b59c-f7727541bd7e
EOF
}

main() {
  local cmd="${1:-help}"
  shift || true

  case "${cmd}" in
    list|ls)   cmd_list "$@" ;;
    add)       cmd_add "$@" ;;
    remove|rm|del|delete) cmd_remove "$@" ;;
    link|uri|url) cmd_link "$@" ;;
    help|-h|--help) cmd_help ;;
    *)
      echo "Неизвестная команда: ${cmd}" >&2
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
