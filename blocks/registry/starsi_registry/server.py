"""StarSI registry block.

Single JSON file of system state on the Pi:

    GET  /health                       no auth
    GET  /v1/models                    which model version is live per tier
    PUT  /v1/models/{tier}             pipeline records a deploy {version, artifact}
    POST /v1/health-report             sites push their /health rollups
    GET  /v1/status                    latest report per source
"""

from __future__ import annotations

import json
import os
import threading
import time
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request


class StateFile:
    def __init__(self, path: Path):
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()
        self.state: dict = {"models": {}, "reports": {}}
        if self.path.exists():
            try:
                self.state = json.loads(self.path.read_text())
            except json.JSONDecodeError:
                pass

    def update(self, fn) -> None:
        with self._lock:
            fn(self.state)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(self.state, indent=2))
            tmp.replace(self.path)


def create_app(state_path: Path | None = None, token: str | None = None) -> FastAPI:
    state_path = state_path or Path(
        os.environ.get("STARSI_REGISTRY_PATH", "/var/lib/starsi/registry/state.json")
    )
    token = token if token is not None else os.environ.get("STARSI_AUTH_TOKEN", "")
    store = StateFile(state_path)
    started = time.time()
    app = FastAPI(title="starsi-registry")

    def check_auth(request: Request) -> None:
        if request.headers.get("authorization") != f"Bearer {token}":
            raise HTTPException(status_code=401, detail="bad or missing token")

    @app.get("/health")
    async def health():
        return {"status": "ok", "uptime_s": round(time.time() - started, 1)}

    @app.get("/v1/models")
    async def models():
        return {"tiers": store.state["models"]}

    @app.put("/v1/models/{tier}")
    async def put_model(tier: str, request: Request):
        check_auth(request)
        body = await request.json()
        if "version" not in body:
            raise HTTPException(status_code=400, detail="version required")
        record = {
            "version": body["version"],
            "artifact": body.get("artifact"),
            "deployed_at": time.time(),
        }
        store.update(lambda s: s["models"].__setitem__(tier, record))
        return record

    @app.post("/v1/health-report")
    async def health_report(request: Request):
        check_auth(request)
        body = await request.json()
        source = body.get("source")
        if not source:
            raise HTTPException(status_code=400, detail="source required")
        report = {"payload": body.get("payload", {}), "at": time.time()}
        store.update(lambda s: s["reports"].__setitem__(source, report))
        return {"ok": True}

    @app.get("/v1/status")
    async def status(request: Request):
        check_auth(request)
        return {"reports": store.state["reports"]}

    return app
