# Xray VLESS-Reality — краткая инструкция

## Требования

- VPS (Linux Ubuntu/Debian), порт **443/tcp** открыт в firewall
- Клиент на Windows: [v2rayN](https://github.com/2dust/v2rayN/releases)

---

## 1. Установка на сервере

```bash
cd /opt/vpn/xray
sudo bash install-server.sh
sudo bash generate-config.sh
```

При установке выбор порта 443:

- **1** — Xray напрямую
- **2** — Nginx: `ssl_preread` на 443, сайт на `127.0.0.1:8443`, Xray на `127.0.0.1:10000`. Клиенты по-прежнему ходят на 443. SNI Reality прописывается в карту Nginx на шаге `generate-config.sh`

- Профиль: **ru**
- Порт: **443** (Enter; в режиме Nginx порт не спрашивается)
- SNI: **1** (microsoft) или **6** (samsung)

Сохраните **vless://** ссылку из вывода.

Если сервис не стартует:

```bash
sudo bash fix-xray.sh
```

---

## 2. Клиент (Windows, Мегафон)

1. Импорт ссылки: v2rayN → **Серверы → Импорт из буфера**
2. **TUN Mode** — включить
3. **Параметры → Fragment** → `tlshello`, length `100-200`, interval `10-20`
4. Fingerprint: **chrome**

Если на мобильном «замирает» через 10–20 сек — нужен RU-мост: `bridge-ru.md`

---

## 3. Управление клиентами

```bash
sudo bash clients.sh list              # список
sudo bash clients.sh add имя           # добавить
sudo bash clients.sh link имя          # ссылка vless://
sudo bash clients.sh remove имя        # удалить
```

---

## 4. Полезные команды

```bash
sudo bash change-port.sh 443          # сменить порт
sudo systemctl status xray             # статус
sudo bash diagnose-xray.sh             # диагностика
sudo journalctl -u xray -n 20          # логи
ss -tlnp | grep 443                   # порт слушается?
```

---

## 4.1 Версия и обновление

```bash
bash version.sh                        # текущая vs актуальная версия
sudo bash update-xray.sh               # обновить до последней
sudo bash update-xray.sh 25.3.6        # установить конкретную версию
sudo bash update-xray.sh force         # переустановить текущую
```

`version.sh` коды выхода: `0` — актуальна, `1` — есть обновление, `2` — не установлен.
`update-xray.sh` обновляет только бинарник, конфиг и сервис сохраняются, при ошибке — автооткат.

---

## 5. Файлы

| Файл | Назначение |
|------|------------|
| `install-server.sh` | Установка Xray |
| `version.sh` | Проверка текущей и актуальной версии |
| `update-xray.sh` | Обновление бинарника до актуальной версии |
| `generate-config.sh` | Первичная настройка |
| `fix-xray.sh` | Исправить ключи и права |
| `clients.sh` | Клиенты: list / add / remove / link |
| `change-port.sh` | Сменить порт (например 443) |
| `bridge-ru.md` | Мост RU → EU для Мегафон |

Конфиг: `/usr/local/etc/xray/config.json`

---

## 6. Параметры подключения

| Параметр | Значение |
|----------|---------|
| Протокол | VLESS |
| Порт | 443 |
| Flow | xtls-rprx-vision |
| Security | Reality |
| Fingerprint | chrome |

UUID, public key, shortId, SNI — из вывода `generate-config.sh` или `clients.sh link`.
