"""MECHA VPN backend: personal keys on every server, issued automatically.

Entry points:
- POST /api/v1/device-key  — the app asks for keys with an anonymous device id.
- POST /api/v1/google-login — the app signs in with Google; the backend checks the ID token.
- Telegram bot — /start gives the same keys to a Telegram user.

One user gets the same UUID on every server, so the app can switch servers without new keys.
Clients are created in each 3X-UI panel through its API. Secrets come from environment variables.
"""

import asyncio
import hashlib
import html
import json
import logging
import os
import sqlite3
import time
import uuid
from collections import defaultdict
from urllib.parse import quote

import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field

# SERVERS: JSON list, one object per server. Example in server/README.md.
SERVERS = json.loads(os.environ["SERVERS"])
GOOGLE_WEB_CLIENT_ID = os.environ.get("GOOGLE_WEB_CLIENT_ID", "")
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
DB_PATH = os.environ.get("DB_PATH", "/var/lib/mecha/mecha.db")
FREE_LIMIT_GB = int(os.environ.get("FREE_LIMIT_GB", "50"))
FREE_RESET_DAYS = int(os.environ.get("FREE_RESET_DAYS", "30"))
NEW_KEYS_PER_IP_PER_DAY = int(os.environ.get("NEW_KEYS_PER_IP_PER_DAY", "10"))

FREE_LIMIT_BYTES = FREE_LIMIT_GB * 1024**3
log = logging.getLogger("mecha")
logging.basicConfig(level=logging.INFO)

_lock = asyncio.Lock()
_new_by_ip: dict[str, list[float]] = defaultdict(list)


def _db() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        "create table if not exists users ("
        " key text primary key, uuid text not null, label text not null,"
        " servers text not null default '', created integer not null)"
    )
    return conn


def _link(client_uuid: str, server: dict) -> str:
    """vless:// link for one server. REALITY servers carry pbk/sid/sni/spx and the vision flow."""
    host, port, name = server["host"], server["port"], server["name"]
    reality = server.get("reality")
    if reality:
        params = (
            "type=tcp&encryption=none&security=reality&flow=xtls-rprx-vision"
            f"&pbk={reality['pbk']}&sid={reality['sid']}&sni={reality['sni']}"
            f"&fp=chrome&spx={quote(reality['spx'])}"
        )
    else:
        params = (
            "type=tcp&encryption=none&security=tls&fp=chrome&alpn=h2%2Chttp%2F1.1"
            f"&sni={host}&allowInsecure=1"
        )
    return f"vless://{client_uuid}@{host}:{port}?{params}#MECHA-{quote(name)}"


async def _create_on_panel(server: dict, email: str, client_uuid: str) -> None:
    flow = "xtls-rprx-vision" if server.get("reality") else ""
    body = {
        "inboundId": server["inbound_id"],
        "email": email,
        "id": client_uuid,
        "enable": True,
        "flow": flow,
        "limitIp": 0,
        "totalGB": FREE_LIMIT_BYTES,
        "expiryTime": 0,
        "reset": FREE_RESET_DAYS,
    }
    verify = server.get("panel_ca") or False
    async with httpx.AsyncClient(verify=verify, timeout=15) as http:
        resp = await http.post(
            f"{server['panel_url'].rstrip('/')}/panel/api/clients/add",
            json=body,
            headers={"Authorization": f"Bearer {server['panel_token']}"},
        )
    resp.raise_for_status()
    data = resp.json()
    if not data.get("success", True):
        raise RuntimeError(f"{server['name']}: panel refused the client: {data.get('msg')}")


async def issue(key: str, label: str) -> list[str]:
    """Creates the user on every server that does not have the client yet, returns links for all reachable ones."""
    async with _lock:
        conn = _db()
        try:
            row = conn.execute("select uuid, servers from users where key = ?", (key,)).fetchone()
            if row:
                client_uuid, done = row[0], set(filter(None, row[1].split(",")))
            else:
                client_uuid, done = str(uuid.uuid4()), set()
                conn.execute(
                    "insert into users (key, uuid, label, servers, created) values (?, ?, ?, '', ?)",
                    (key, client_uuid, label, int(time.time())),
                )
                conn.commit()

            email = f"u_{hashlib.sha256(key.encode()).hexdigest()[:16]}"
            for server in SERVERS:
                if server["name"] in done:
                    continue
                try:
                    await _create_on_panel(server, email, client_uuid)
                    done.add(server["name"])
                except (httpx.HTTPError, RuntimeError) as exc:
                    log.error("server %s is not ready for %s: %s", server["name"], label, exc)
            conn.execute(
                "update users set servers = ? where key = ?",
                (",".join(sorted(done)), key),
            )
            conn.commit()
        finally:
            conn.close()

    links = [_link(client_uuid, s) for s in SERVERS if s["name"] in done]
    if not links:
        raise HTTPException(status_code=503, detail="no server is available right now")
    return links


def _check_ip_limit(ip: str) -> None:
    now = time.time()
    recent = [t for t in _new_by_ip[ip] if now - t < 86400]
    _new_by_ip[ip] = recent
    if len(recent) >= NEW_KEYS_PER_IP_PER_DAY:
        raise HTTPException(status_code=429, detail="too many new accounts from this address today")


async def _verify_google(id_token: str) -> dict:
    if not GOOGLE_WEB_CLIENT_ID:
        raise HTTPException(status_code=500, detail="google login is not configured")
    async with httpx.AsyncClient(timeout=10) as http:
        resp = await http.get("https://oauth2.googleapis.com/tokeninfo", params={"id_token": id_token})
    if resp.status_code != 200:
        raise HTTPException(status_code=401, detail="invalid google token")
    info = resp.json()
    if info.get("aud") != GOOGLE_WEB_CLIENT_ID:
        raise HTTPException(status_code=401, detail="token was issued for another app")
    if info.get("email_verified") not in ("true", True):
        raise HTTPException(status_code=401, detail="google email is not verified")
    return info


class DeviceRequest(BaseModel):
    device_id: str = Field(min_length=8, max_length=128)


class GoogleRequest(BaseModel):
    id_token: str = Field(min_length=20, max_length=4096)


app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


@app.post("/api/v1/device-key")
async def device_key(req: DeviceRequest, request: Request) -> dict:
    digest = hashlib.sha256(req.device_id.encode()).hexdigest()
    key = f"dev:{digest}"
    exists = _db().execute("select 1 from users where key = ?", (key,)).fetchone()
    if not exists:
        ip = request.client.host if request.client else "unknown"
        _check_ip_limit(ip)
        _new_by_ip[ip].append(time.time())
    return {"links": await issue(key, "device")}


@app.post("/api/v1/google-login")
async def google_login(req: GoogleRequest, request: Request) -> dict:
    info = await _verify_google(req.id_token)
    sub = info["sub"]
    key = f"g:{sub}"
    exists = _db().execute("select 1 from users where key = ?", (key,)).fetchone()
    if not exists:
        ip = request.client.host if request.client else "unknown"
        _check_ip_limit(ip)
        _new_by_ip[ip].append(time.time())
    return {"email": info.get("email", ""), "links": await issue(key, info.get("email", "google"))}


async def _send(http: httpx.AsyncClient, chat_id: int, text: str) -> None:
    await http.post(
        f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage",
        json={"chat_id": chat_id, "text": text, "parse_mode": "HTML"},
    )


async def _bot_loop() -> None:
    """Long polling: the bot needs no public URL of its own."""
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
                    links = await issue(f"tg:{chat_id}", f"tg_{chat_id}")
                    body = "\n".join(f"<code>{html.escape(link)}</code>" for link in links)
                    await _send(http, chat_id, f"Ваши ключи MECHA VPN. Вставьте их в приложение:\n\n{body}")
                except Exception as exc:  # keep serving other users
                    log.error("bot could not issue keys for %s: %s", chat_id, exc)
                    await _send(http, chat_id, "Не удалось выдать ключи, попробуйте позже.")


@app.on_event("startup")
async def _start_bot() -> None:
    if BOT_TOKEN:
        asyncio.create_task(_bot_loop())
