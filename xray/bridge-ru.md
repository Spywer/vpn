# Мост RU → зарубежный сервер (максимальная устойчивость в РФ)

## Зачем

С 2025 года ТСПУ на мобильных и части домашних провайдеров «замораживает» TCP-сессии
к зарубежным IP после ~16–20 KB данных в одном соединении. Reality это не обходит сам по себе.

**Схема:** клиент в РФ → VPS в РФ (мост) → ваш Xray за рубежом.

ТСПУ обычно не режет трафик между клиентом и российским IP так агрессивно.

```
[Вы, Windows] --VLESS-Reality--> [VPS RU] --VLESS-Reality--> [VPS EU/US]
```

## 1. Зарубежный сервер (уже есть)

Запустите `generate-config.sh` с профилем `ru`, порт 443.

## 2. Российский VPS (мост)

Минимальный тариф (1 vCPU, 512 MB), любой провайдер с IP в РФ.

На мосте установите Xray и создайте **два** inbound:

- **inbound A** — для клиентов (слушает 443, свои ключи Reality)
- **outbound** — VLESS к зарубежному серверу

Пример фрагмента `/usr/local/etc/xray/config.json` на мосте:

```json
{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [{ "id": "UUID-ДЛЯ-КЛИЕНТОВ", "flow": "xtls-rprx-vision" }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "КЛЮЧ-МОСТА",
          "shortIds": ["", "abcd1234"]
        }
      },
      "tag": "from-clients"
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [{
          "address": "IP-ЗАРУБЕЖНОГО-VPS",
          "port": 443,
          "users": [{ "id": "UUID-ЗАРУБЕЖНОГО", "encryption": "none", "flow": "xtls-rprx-vision" }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "www.microsoft.com",
          "publicKey": "PUBLIC-KEY-ЗАРУБЕЖНОГО",
          "shortId": "SHORT-ID-ЗАРУБЕЖНОГО",
          "spiderX": "/"
        }
      },
      "tag": "to-foreign"
    },
    { "protocol": "freedom", "tag": "direct" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["from-clients"], "outboundTag": "to-foreign" }
    ]
  }
}
```

## 3. Клиент (Windows)

Подключайтесь к **IP моста (RU)**, не к зарубежному напрямую.
Параметры Reality — от моста (ключи/SNI из inbound A).

## 4. Выбор VPS

| Роль | Рекомендация |
|------|----------------|
| Зарубежный | Не Hetzner/DO/OVH если возможно; Турция, KZ, FI, AE |
| Мост RU | Любой недорогой RU VPS (Timeweb, Selectel, VDSina) |

## 5. Проверка лимита провайдера

Отключите VPN и откройте: https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/

Если тест красный — мост или Fragment в клиенте обязательны.
