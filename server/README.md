# MECHA VPN backend

Один сервис на вашем VPS (`45.155.71.152`):
- `POST /api/v1/key` — приложение присылает анонимный ID устройства и получает свой VLESS-ключ.
- Telegram-бот — на `/start` выдаёт ключ тому, кто написал.

Клиентов создаёт 3X-UI через API. Секреты только в переменных окружения, в git их нет.

## 1. Переменные окружения

Создайте `/etc/mecha/mecha.env` (права только для root):

```
PANEL_URL=https://45.155.71.152:2053
PANEL_TOKEN=ВАШ_API_ТОКЕН_ИЗ_ПАНЕЛИ
PANEL_CA=
INBOUND_ID=1
SERVER_HOST=45.155.71.152
SERVER_PORT=8443
BOT_TOKEN=НОВЫЙ_ТОКЕН_БОТА
DB_PATH=/var/lib/mecha/mecha.db
NEW_KEYS_PER_IP_PER_DAY=10
FREE_LIMIT_GB=50
FREE_RESET_DAYS=30
```

Лимит бесплатного режима: 50 ГБ, сброс каждые 30 дней. В 3X-UI поле `totalGB` хранится в байтах, сервер сам переводит ГБ в байты. После первого клиента проверьте в панели, что у него лимит 50 ГБ, а не 50 Б. Если сброс по дням не поддерживается, поле `reset` просто игнорируется, и тогда сбрасывать лимит придётся вручную.

```
chmod 600 /etc/mecha/mecha.env
```

`PANEL_CA` оставьте пустым, если панель на самоподписанном сертификате. Тогда проверка сертификата панели отключена, это допустимо, потому что запросы идут на ваш же сервер.

## 2. Установка

```
apt install -y python3-venv
mkdir -p /opt/mecha && cd /opt/mecha
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Скопируйте сюда `mecha_server.py` и `requirements.txt` из папки `server/` репозитория.

## 3. Сертификат Let's Encrypt на IP-адрес

Порт 80 должен быть свободен на время выпуска (certbot сам поднимет проверку).

```
apt install -y certbot
certbot certonly --standalone --preferred-profile shortlived -d 45.155.71.152
```

Сертификат короткоживущий (примерно неделю), поэтому продление нужно автоматизировать. Certbot ставит таймер сам; проверьте его командой `systemctl list-timers | grep certbot`. После продления нужно перезапускать сервис, см. ниже (`--deploy-hook`).

Пути к файлам: `/etc/letsencrypt/live/45.155.71.152/fullchain.pem` и `privkey.pem`.

Если certbot ругается на флаг `--preferred-profile`, пришлите вывод ошибки.

## 4. Запуск на порту 443

Порт 443 свободен: VLESS работает на 8443, панель на 2053.

`/etc/systemd/system/mecha.service`:

```
[Unit]
Description=MECHA VPN backend
After=network-online.target

[Service]
EnvironmentFile=/etc/mecha/mecha.env
WorkingDirectory=/opt/mecha
ExecStart=/opt/mecha/.venv/bin/uvicorn mecha_server:app --host 0.0.0.0 --port 443 --ssl-keyfile /etc/letsencrypt/live/45.155.71.152/privkey.pem --ssl-certfile /etc/letsencrypt/live/45.155.71.152/fullchain.pem
Restart=always

[Install]
WantedBy=multi-user.target
```

```
systemctl daemon-reload
systemctl enable --now mecha
systemctl status mecha
```

Продление сертификата должно перезапускать сервис:

```
certbot renew --deploy-hook "systemctl restart mecha"
```

## 5. Проверка

С любого устройства (например, с телефона через мобильный интернет):

```
curl -s -X POST https://45.155.71.152/api/v1/key -H "Content-Type: application/json" -d '{"device_id":"test-device-0001"}'
```

Ожидаем ответ с полем `link` (`vless://...`). Если в ответе ошибка панели, пришлите её текст — обычно дело в формате тела запроса или в правах токена.

Бот: напишите `/start` вашему боту — он пришлёт ключ.
