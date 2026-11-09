#!/usr/bin/env bash
# Диагностика Xray — запуск: sudo bash diagnose-xray.sh

CONFIG="/usr/local/etc/xray/config.json"

echo "=== Xray binary ==="
command -v xray && xray version | head -1 || echo "xray не найден в PATH"

echo ""
echo "=== systemd ==="
systemctl status xray --no-pager -l 2>&1 | head -20

echo ""
echo "=== Последние логи ==="
journalctl -u xray -n 25 --no-pager 2>&1

echo ""
echo "=== Конфиг ==="
if [[ -f "${CONFIG}" ]]; then
  ls -la "${CONFIG}"
  echo ""
  xray run -test -config "${CONFIG}" 2>&1 || true
else
  echo "Файл ${CONFIG} не найден — запустите generate-config.sh"
fi

echo ""
echo "=== Порт 443 ==="
ss -tlnp | grep -E ':443\b' || echo "Порт 443 не слушается"

echo ""
echo "=== Ключи в конфиге (не должны быть пустыми) ==="
if [[ -f "${CONFIG}" ]]; then
  grep -E 'privateKey|shortIds' "${CONFIG}" | head -5
fi
