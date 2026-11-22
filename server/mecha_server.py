"""MECHA VPN backend: personal VLESS keys for the app and the Telegram bot.

Both entry points call the same `issue()`: the app sends an anonymous device id and gets its own
key; the bot gives a key to a Telegram user on /start. Clients are created in 3X-UI through its API.

Configuration comes from environment variables (see server/README.md). Nothing secret lives here.
"""

import asyncio
import hashlib
import html
import logging
import os
import sqlite3
import time
import uuid
from collections import defaultdict

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

PANEL_URL = os.environ["PANEL_URL"].rstrip("/")  # e.g. https://45.155.71.152:2053
PANEL_TOKEN = os.environ["PANEL_TOKEN"]  # 3X-UI API token, Authorization: Bearer
PANEL_CA = os.environ.get("PANEL_CA", "")  # path to the panel's CA/cert; empty = no verification
INBOUND_ID = int(os.environ.get("INBOUND_ID", "1"))
SERVER_HOST = os.environ.get("SERVER_HOST", "45.155.71.152")
SERVER_PORT = int(os.environ.get("SERVER_PORT", "8443"))
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
DB_PATH = os.environ.get("DB_PATH", "/var/lib/mecha/mecha.db")
NEW_KEYS_PER_IP_PER_DAY = int(os.environ.get("NEW_KEYS_PER_IP_PER_DAY", "10"))
# Free plan: 50 GB per user. 3X-UI stores `totalGB` in bytes, so the GB value is converted.
FREE_LIMIT_GB = int(os.environ.get("FREE_LIMIT_GB", "50"))
FREE_LIMIT_BYTES = FREE_LIMIT_GB * 1024**3
FREE_RESET_DAYS = int(os.environ.get("FREE_RESET_DAYS", "30"))

log = logging.getLogger("mecha")
logging.basicConfig(level=logging.INFO)

_lock = asyncio.Lock()
_issued_by_ip: dict[str, list[float]] = defaultdict(list)


def _db() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "create table if not exists users (key text primary key, uuid text not null, email text not null, created integer not null)"
    )
    return conn


def _vless_link(client_uuid: str, name: str) -> str:
    return (
        f"vless://{client_uuid}@{SERVER_HOST}:{SERVER_PORT}"
        "?type=tcp&encryption=none&security=tls&flow=xtls-rprx-vision"
        f"&fp=chrome&alpn=h2%2Chttp%2F1.1&sni={SERVER_HOST}&allowInsecure=1#{name}"
    )


async def _create_client(email: str, client_uuid: str) -> None:
    body = {
        "inboundId": INBOUND_ID,
        "email": email,
        "id": client_uuid,
        "enable": True,
        "flow": "xtls-rprx-vision",
        "limitIp": 2,
        "totalGB": FREE_LIMIT_BYTES,
        "expiryTime": 0,
        "reset": FREE_RESET_DAYS,  # monthly traffic reset, if this panel version supports it
    }
    verify = PANEL_CA or False
    async with httpx.AsyncClient(verify=verify, timeout=15) as http:
        resp = await http.post(
            f"{PANEL_URL}/panel/api/clients/add",
            json=body,
            headers={"Authorization": f"Bearer {PANEL_TOKEN}"},
        )
    resp.raise_for_status()
    data = resp.json()
    if not data.get("success", True):
        raise RuntimeError(f"panel refused the client: {data.get('msg')}")


async def issue(key: str, email: str, name: str) -> str:
    """Returns the VLESS link of the user's own key, creating the client on first call."""
    async with _lock:
        conn = _db()
        try:
            row = conn.execute("select uuid from users where key = ?", (key,)).fetchone()
            if row:
                return _vless_link(row[0], name)
            client_uuid = str(uuid.uuid4())
            await _create_client(email, client_uuid)
            conn.execute(
                "insert into users (key, uuid, email, created) values (?, ?, ?, ?)",
                (key, client_uuid, email, int(time.time())),
            )
            conn.commit()
            return _vless_link(client_uuid, name)
        finally:
            conn.close()


def _check_ip_limit(ip: str) -> None:
    now = time.time()
    recent = [t for t in _issued_by_ip[ip] if now - t < 86400]
    _issued_by_ip[ip] = recent
    if len(recent) >= NEW_KEYS_PER_IP_PER_DAY:
        raise HTTPException(status_code=429, detail="too many new keys from this address today")


class DeviceRequest(BaseModel):
    device_id: str = Field(min_length=8, max_length=128)


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


@app.post("/api/v1/key")
async def device_key(req: DeviceRequest, request: Request) -> dict:
    """The app asks for its own key. The device id is hashed before it reaches the panel."""
    digest = hashlib.sha256(req.device_id.encode()).hexdigest()
    key = f"dev:{digest}"
    email = f"dev_{digest[:16]}"
    existing = _db().execute("select 1 from users where key = ?", (key,)).fetchone()
    if not existing:
        ip = request.client.host if request.client else "unknown"
        _check_ip_limit(ip)
        _issued_by_ip[ip].append(time.time())
    try:
        link = await issue(key, email, "MECHA")
    except httpx.HTTPError as exc:
        log.error("panel request failed: %s", exc)
        raise HTTPException(status_code=502, detail="panel is unavailable") from exc
    return {"link": link}


async def _send(http: httpx.AsyncClient, chat_id: int, text: str) -> None:
    await http.post(
        f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
        json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"},
    )


async def _bot_loop() -> None:
    """Long polling: no webhook, so the bot needs no public URL of its own."""
    offset = 0
    async with httpx.AsyncClient(timeout=70) as http:
        while True:
            try:
                resp = await http.get(
                    f"https://api.telegram.org/bot{BOT_TOKEN}/getUpdates",
                    params={"offset": offset, "timeout": 50},
                )
                updates = resp.json().get("result", [])
            except (httpx.HTTPError, ValueError) as exc:
                log.warning("telegram poll failed: %s", exc)
                await asyncio.sleep(5)
                continue
            for update in updates:
                offset = update["update_id"] + 1
                message = update.get("message") or {}
                chat_id = message.get("chat", {}).get("id")
                if chat_id is None or not (message.get("text") or "").startswith("/start"):
                    continue
                try:
                    link = await issue(f"tg:{chat_id}", f"tg_{chat_id}", "MECHA")
                    await _send(
                        http,
                        chat_id,
                        "Ваш ключ MECHA VPN. Скопируйте его и вставьте в приложение:\n\n"
                        f"<code>{html.escape(link)}</code>",
                    )
                except Exception as exc:  # the bot keeps serving other users
                    log.error("bot could not issue a key for %s: %s", chat_id, exc)
                    await _send(http, chat_id, "Не удалось выдать ключ, попробуйте позже.")


@app.on_event("startup")
async def _start_bot() -> None:
    if BOT_TOKEN:
        asyncio.create_task(_bot_loop())
