# MECHA VPN backend

Один сервис, который выдаёт каждому пользователю персональные ключи на все серверы.

- `POST /api/v1/device-key` — приложение присылает анонимный ID устройства, получает ключи.
- `POST /api/v1/google-login` — вход через Google, ключи выдаются тому же пользователю.
- Telegram-бот — на `/start` выдаёт ключи.

Один пользователь получает **один UUID на всех серверах**, поэтому приложение может переключаться между серверами без новых ключей.

## 1. Переменные окружения

Файл `/etc/mecha/mecha.env` (права только для root, `chmod 600`):

```
SERVERS=[{"name":"AT","panel_url":"https://45.155.71.152:2053","panel_token":"ТОКЕН_1","panel_ca":"","inbound_id":1,"host":"45.155.71.152","port":8443,"reality":null},{"name":"DE","panel_url":"https://ВТОРОЙ_СЕРВЕР:ПОРТ_ПАНЕЛИ/ПУТЬ","panel_token":"ТОКЕН_2","panel_ca":"","inbound_id":1,"host":"ВТОРОЙ_IP","port":443,"reality":{"pbk":"ПУБЛИЧНЫЙ_КЛЮЧ","sid":"a6","sni":"www.microsoft.com","spx":"/f7288fdee76911a"}}]
GOOGLE_WEB_CLIENT_ID=ИДЕНТИФИКАТОР_WEB_КЛИЕНТА.apps.googleusercontent.com
BOT_TOKEN=НОВЫЙ_ТОКЕН_БОТА
DB_PATH=/var/lib/mecha/mecha.db
FREE_LIMIT_GB=50
FREE_RESET_DAYS=30
NEW_KEYS_PER_IP_PER_DAY=10
```

- `reality: null` — сервер на TLS (старый, 45.155.71.152).
- Сервер с `reality` — подключение REALITY (новый, 213.165.35.253). Значения `pbk`, `sid`, `sni`, `spx` берите из панели того сервера.
- `panel_token` — API-токен из панели каждого сервера. Не публикуйте его.
- Порт и путь панели для нового сервера: `https://213.165.35.253:61132`, если путь пустой — оставьте без него.

## 2. Установка

```
apt install -y python3-venv
mkdir -p /opt/mecha && cd /opt/mecha
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Скопируйте `mecha_server.py` и `requirements.txt` из `server/`.

## 3. Сертификат на IP

Для старого сервера сертификат Let's Encrypt на IP уже выпущен (его продлевает `x-ui`). Для самого backend нужен HTTPS, поэтому используем тот же сертификат или отдельный, выпущенный через certbot на IP. Команды выполнит владелец сервера.

## 4. Запуск

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
```

## 5. Проверка

```
curl -s -X POST https://45.155.71.152/api/v1/device-key -H "Content-Type: application/json" -d '{"device_id":"test-device-0001"}'
```

В ответе должен быть список `links` — по одной ссылке на каждый доступный сервер.

## 6. Google-вход: что настроить

1. Google Cloud Console → создать проект.
2. **OAuth consent screen** → External → заполнить название и почту.
3. **Credentials → Create credentials → OAuth client ID**:
   - тип **Web application** — его Client ID идёт в `GOOGLE_WEB_CLIENT_ID`;
   - тип **Android**, package `com.mechavpn.app`, SHA-1 отпечаток ключа подписи:
     `F9:A0:CE:72:58:44:BF:E4:9B:B4:56:9A:92:90:30:55:E1:48:7B:AE`
4. Пока приложение в режиме «Testing», входить смогут только добавленные тестовые пользователи. Для публичного запуска нужно опубликовать OAuth-приложение.
