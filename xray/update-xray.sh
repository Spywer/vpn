#!/usr/bin/env bash
set -euo pipefail

# Обновление бинарника Xray до актуальной версии (конфиг и сервис не трогаем)
# Запуск: sudo bash update-xray.sh [версия]
#   без аргумента  — обновление до последней версии с GitHub
#   с аргументом   — установка конкретной версии, например: sudo bash update-xray.sh 25.3.6
#   force          — переустановить даже если версия уже актуальна

INSTALL_DIR="/usr/local/bin"
SERVICE_NAME="xray"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_VERSION="${1:-latest}"

# shellcheck source=lib/xray-release.sh
source "${SCRIPT_DIR}/lib/xray-release.sh"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root: sudo bash update-xray.sh ${TARGET_VERSION}"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y curl jq unzip ca-certificates
fi

detect_xray_asset

if [[ "${TARGET_VERSION}" == "latest" || "${TARGET_VERSION}" == "force" ]]; then
  xray_latest_version
  NEW_VERSION="${XRAY_LATEST_VERSION}"
else
  NEW_VERSION="${TARGET_VERSION#v}"
fi

INSTALLED="$(xray_installed_version)"
echo "Установлена:  ${INSTALLED:-нет}"
echo "Цель:         ${NEW_VERSION}"

if [[ "${INSTALLED}" == "${NEW_VERSION}" && "${TARGET_VERSION}" != "force" ]]; then
  echo "Версия уже актуальна. Для переустановки: sudo bash update-xray.sh force"
  exit 0
fi

RELEASE_URL="https://github.com/XTLS/Xray-core/releases/download/v${NEW_VERSION}/${XRAY_ASSET_NAME}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

echo "Загрузка ${XRAY_ASSET_NAME} (v${NEW_VERSION})..."
curl -fsSL "${RELEASE_URL}" -o "${TMP_DIR}/xray.zip"
unzip -q "${TMP_DIR}/xray.zip" -d "${TMP_DIR}"

# Бэкап текущего бинарника на случай отката
if [[ -f "${INSTALL_DIR}/xray" ]]; then
  cp -f "${INSTALL_DIR}/xray" "${INSTALL_DIR}/xray.bak"
fi

# Атомарная замена: новый бинарник кладём рядом и переименовываем
install -m 755 "${TMP_DIR}/xray" "${INSTALL_DIR}/xray.new"
mv -f "${INSTALL_DIR}/xray.new" "${INSTALL_DIR}/xray"

echo "Проверка нового бинарника..."
INSTALLED_NOW="$(xray_installed_version)"
if [[ "${INSTALLED_NOW}" != "${NEW_VERSION}" ]]; then
  echo "Версия после установки (${INSTALLED_NOW:-нет}) не совпадает с целевой (${NEW_VERSION})." >&2
  if [[ -f "${INSTALL_DIR}/xray.bak" ]]; then
    echo "Откат к предыдущей версии..." >&2
    mv -f "${INSTALL_DIR}/xray.bak" "${INSTALL_DIR}/xray"
  fi
  exit 1
fi

# Перезапуск сервиса, если он зарегистрирован
if systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
  systemctl restart "${SERVICE_NAME}"
  systemctl --no-pager status "${SERVICE_NAME}" | head -5
fi

rm -f "${INSTALL_DIR}/xray.bak"

echo ""
echo "Готово. Установлена версия: $(xray version | head -1)"
