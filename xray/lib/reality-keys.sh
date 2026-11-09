#!/usr/bin/env bash
# Парсинг ключей Reality из вывода xray x25519 (все версии Xray 25+)
parse_reality_keys() {
  local keys private public
  keys="$(xray x25519 2>&1)"

  private="$(printf '%s\n' "${keys}" | awk -F':' '
    /^[Pp]rivate[Kk]ey/ || /^[Pp]rivate key/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ')"

  public="$(printf '%s\n' "${keys}" | awk -F':' '
    /^[Pp]assword/ || /^[Pp]ublic [Kk]ey/ {
      sub(/^[^:]*:[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
  ')"

  if [[ -z "${private}" || -z "${public}" ]]; then
    echo "Не удалось распарсить ключи. Вывод xray x25519:" >&2
    printf '%s\n' "${keys}" >&2
    return 1
  fi

  PRIVATE_KEY="${private}"
  PUBLIC_KEY="${public}"
}

fix_xray_permissions() {
  local config_dir="/usr/local/etc/xray"
  local config_file="${config_dir}/config.json"
  local env_file="${config_dir}/client.env"

  chmod 755 "${config_dir}"
  chown root:root "${config_dir}"

  if getent group nogroup >/dev/null 2>&1; then
    chown root:nogroup "${config_file}" "${env_file}" 2>/dev/null || true
  else
    chown root:nobody "${config_file}" "${env_file}" 2>/dev/null || true
  fi

  chmod 640 "${config_file}" "${env_file}" 2>/dev/null || true
}
