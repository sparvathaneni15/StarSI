"""StarSI gateway block.

The same image runs on every site; env vars select the assembly:

    GET  /health               site + per-tier reachability, no auth
    GET  /v1/models            tiers advertised as OpenAI model objects
    POST /v1/chat/completions  OpenAI-compatible SSE; the request's "model"
                               field picks the inference tier
    POST /v1/sync              forward offline turns to the memory block;
                               spool locally and retry when it is unreachable

Inference, STT, TTS, and memory are sibling services — this process never
spawns children (unlike the retired apps/node, which owned mlx_lm.server).
"""

from __future__ import annotations

import asyncio
import json
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse

from .config import Settings
from .spool import SyncSpool

SPOOL_FLUSH_INTERVAL_S = 30.0


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    spool = SyncSpool(settings.sync_spool_dir)
    started = time.time()
    agent = None
    if settings.agent_enabled:
        from .agent import HermesAgent

        agent = HermesAgent(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.http = httpx.AsyncClient()
        flusher = asyncio.create_task(flush_spool_forever(app.state.http))
        if agent:
            await agent.start()
        try:
            yield
        finally:
            flusher.cancel()
            if agent:
                await agent.stop()
            await app.state.http.aclose()

    app = FastAPI(title="starsi-gateway", lifespan=lifespan)

    def check_auth(request: Request) -> None:
        if request.headers.get("authorization") != f"Bearer {settings.auth_token}":
            raise HTTPException(status_code=401, detail="bad or missing token")

    def pick_tier(body: dict):
        name = body.get("model") or settings.default_tier
        tier = settings.tiers.get(name) or settings.tiers.get(settings.default_tier)
        if tier is None:
            raise HTTPException(status_code=503, detail="no inference tier configured")
        return tier

    def touch_capacity(http: httpx.AsyncClient, tier_name: str) -> None:
        """GPU-tier traffic keeps the instance awake (and wakes it when stopped)."""
        if settings.capacity_url is None or not tier_name.endswith("gpu"):
            return

        async def fire():
            try:
                await http.post(
                    f"{settings.capacity_url}/capacity/gpu/touch",
                    headers={"Authorization": f"Bearer {settings.auth_token}"},
                    timeout=5,
                )
            except httpx.HTTPError:
                pass

        asyncio.get_running_loop().create_task(fire())

    async def tier_up(http: httpx.AsyncClient, base_url: str) -> bool:
        try:
            r = await http.get(f"{base_url}/models", timeout=1.5)
            return r.status_code == 200
        except httpx.HTTPError:
            return False

    async def flush_spool_forever(http: httpx.AsyncClient) -> None:
        while True:
            await asyncio.sleep(SPOOL_FLUSH_INTERVAL_S)
            await flush_spool(http)

    async def flush_spool(http: httpx.AsyncClient) -> int:
        """Replay spooled turns into memory. Returns count accepted upstream."""
        if settings.memory_url is None:
            return 0
        turns = spool.peek()
        if not turns:
            return 0
        try:
            r = await http.post(
                f"{settings.memory_url}/v1/sync", json={"turns": turns}, timeout=10
            )
            r.raise_for_status()
        except httpx.HTTPError:
            return 0
        spool.clear(len(turns))
        return r.json().get("accepted", 0)

    @app.get("/health")
    async def health(request: Request):
        tiers = {
            t.name: {"up": await tier_up(request.app.state.http, t.base_url)}
            for t in settings.tiers.values()
        }
        return {
            "status": "ok",
            "site": settings.site,
            "tiers": tiers,
            "agent": bool(agent and agent.ready),
            "spooled_turns": spool.size(),
            "uptime_s": round(time.time() - started, 1),
        }

    @app.get("/v1/models")
    async def models():
        return {
            "object": "list",
            "data": [
                {"id": t.name, "object": "model", "owned_by": "starsi"}
                for t in settings.tiers.values()
            ],
        }

    @app.post("/v1/chat/completions")
    async def chat(request: Request):
        check_auth(request)
        body = await request.json()
        if not body.get("messages"):
            raise HTTPException(status_code=400, detail="messages required")
        tier = pick_tier(body)
        touch_capacity(request.app.state.http, tier.name)

        if agent and agent.ready and not body.get("raw"):
            user_text = next(
                (m["content"] for m in reversed(body["messages"]) if m.get("role") == "user"),
                "",
            )
            return StreamingResponse(
                agent_sse(user_text, tier.name), media_type="text/event-stream"
            )

        upstream_body = {k: v for k, v in body.items() if k != "raw"}
        upstream_body["model"] = tier.upstream_model
        url = f"{tier.base_url}/chat/completions"
        http: httpx.AsyncClient = request.app.state.http

        if body.get("stream", True):
            upstream_body["stream"] = True

            async def relay() -> AsyncIterator[bytes]:
                try:
                    async with http.stream(
                        "POST", url, json=upstream_body, timeout=300
                    ) as r:
                        if r.status_code != 200:
                            detail = (await r.aread()).decode(errors="replace")[:500]
                            yield sse_error(f"upstream {r.status_code}: {detail}")
                            return
                        async for chunk in r.aiter_bytes():
                            yield chunk
                except httpx.HTTPError as exc:
                    yield sse_error(f"upstream unreachable: {exc}")

            return StreamingResponse(relay(), media_type="text/event-stream")

        r = await http.post(url, json=upstream_body, timeout=300)
        return JSONResponse(r.json(), status_code=r.status_code)

    def sse_chunk(completion_id: str, created: int, model: str,
                  delta: dict, finish: str | None = None) -> str:
        payload = {
            "id": completion_id, "object": "chat.completion.chunk",
            "created": created, "model": model,
            "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
        }
        return f"data: {json.dumps(payload)}\n\n"

    def sse_error(text: str) -> bytes:
        cid = f"chatcmpl-{uuid.uuid4().hex[:12]}"
        now = int(time.time())
        out = sse_chunk(cid, now, "starsi", {"content": f"[gateway error: {text}]"})
        out += sse_chunk(cid, now, "starsi", {}, finish="stop")
        return (out + "data: [DONE]\n\n").encode()

    async def agent_sse(user_text: str, model: str) -> AsyncIterator[str]:
        completion_id = f"chatcmpl-{uuid.uuid4().hex[:12]}"
        created = int(time.time())
        yield sse_chunk(completion_id, created, model, {"role": "assistant"})
        streamed = 0
        async for event in agent.ask(user_text):
            kind, text = event.get("type"), event.get("text", "")
            if kind == "delta" and text:
                streamed += len(text)
                yield sse_chunk(completion_id, created, model, {"content": text})
            elif kind == "final" and streamed == 0 and text:
                yield sse_chunk(completion_id, created, model, {"content": text})
            elif kind == "error":
                yield sse_chunk(completion_id, created, model,
                                {"content": f"\n[agent error: {text}]"})
        yield sse_chunk(completion_id, created, model, {}, finish="stop")
        yield "data: [DONE]\n\n"

    @app.post("/v1/sync")
    async def sync(request: Request):
        check_auth(request)
        body = await request.json()
        turns = body.get("turns", [])
        http: httpx.AsyncClient = request.app.state.http
        if settings.memory_url is not None:
            try:
                r = await http.post(
                    f"{settings.memory_url}/v1/sync", json={"turns": turns}, timeout=10
                )
                r.raise_for_status()
                return r.json()
            except httpx.HTTPError:
                pass
        spool.append(turns)
        return {"accepted": 0, "spooled": len(turns)}

    from .voice import add_voice_routes

    add_voice_routes(app, settings, spool)

    app.state.flush_spool = flush_spool  # exposed for tests
    return app
