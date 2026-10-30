"""StarSI memory block.

    GET  /health                 turn count, no auth
    POST /v1/sync                idempotent turn append (turn_id-keyed)
    GET  /v1/turns?since=&limit= paged read for dataset-prep / replicas
"""

from __future__ import annotations

import os
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request


def create_app(store_path: Path | None = None, token: str | None = None) -> FastAPI:
    store_path = store_path or Path(os.environ.get("STARSI_MEMORY_PATH", "/var/lib/starsi/memory"))
    token = token if token is not None else os.environ.get("STARSI_AUTH_TOKEN", "")

    from . import MemoryStore

    store = MemoryStore(store_path)
    started = time.time()
    app = FastAPI(title="starsi-memory")

    def check_auth(request: Request) -> None:
        if request.headers.get("authorization") != f"Bearer {token}":
            raise HTTPException(status_code=401, detail="bad or missing token")

    @app.get("/health")
    async def health():
        return {
            "status": "ok",
            "turns": store.count(),
            "uptime_s": round(time.time() - started, 1),
        }

    @app.post("/v1/sync")
    async def sync(request: Request):
        check_auth(request)
        body = await request.json()
        return {"accepted": store.append_turns(body.get("turns", []))}

    @app.get("/v1/turns")
    async def turns(request: Request, since: int = 0, limit: int = 1000):
        check_auth(request)
        items, next_offset = store.read_turns(since=since, limit=limit)
        return {"turns": items, "next": next_offset}

    return app
