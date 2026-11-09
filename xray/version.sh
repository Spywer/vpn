#!/usr/bin/env bash
set -euo pipefail

# Проверка установленной версии Xray и сравнение с актуальной на GitHub
# Запуск: bash version.sh
# Код выхода: 0 — установлена последняя версия; 1 — доступно обновление; 2 — не установлен

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/xray-release.sh
source "${SCRIPT_DIR}/lib/xray-release.sh"

if ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  echo "Требуются jq и curl. Установите: sudo apt-get install -y jq curl"
  exit 1
fi

INSTALLED="$(xray_installed_version)"
xray_latest_version

if [[ -z "${INSTALLED}" ]]; then
  echo "Xray не установлен."
  echo "Актуальная версия: ${XRAY_LATEST_VERSION}"
  echo "Установка: sudo bash install-server.sh"
  exit 2
fi

echo "Установлена:  ${INSTALLED}"
echo "Актуальная:   ${XRAY_LATEST_VERSION}"

if [[ "${INSTALLED}" == "${XRAY_LATEST_VERSION}" ]]; then
  echo "Установлена последняя версия."
  exit 0
fi

echo "Доступно обновление: ${INSTALLED} → ${XRAY_LATEST_VERSION}"
echo "Обновление: sudo bash update-xray.sh"
exit 1
