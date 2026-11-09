#!/usr/bin/env bash
# Хелперы для работы с релизами Xray-core (определение архитектуры и версий)

# Определяет имя ассета релиза под текущую архитектуру.
# Результат — в переменной XRAY_ASSET_NAME.
detect_xray_asset() {
  local arch xray_arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64)  xray_arch="64" ;;
    aarch64) xray_arch="arm64-v8a" ;;
    armv7l)  xray_arch="arm32-v7a" ;;
    *)
      echo "Неподдерживаемая архитектура: ${arch}" >&2
      return 1
      ;;
  esac
  XRAY_ASSET_NAME="Xray-linux-${xray_arch}.zip"
}

# Текущая установленная версия (без префикса v). Пусто, если xray не найден.
xray_installed_version() {
  command -v xray >/dev/null 2>&1 || return 0
  xray version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Последняя версия из GitHub (без префикса v). Результат — в XRAY_LATEST_VERSION.
xray_latest_version() {
  local tag
  tag="$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases/latest \
    | jq -r '.tag_name')"
  if [[ -z "${tag}" || "${tag}" == "null" ]]; then
    echo "Не удалось получить последнюю версию Xray с GitHub" >&2
    return 1
  fi
  XRAY_LATEST_VERSION="${tag#v}"
}
