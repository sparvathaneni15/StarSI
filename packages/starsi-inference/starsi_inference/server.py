"""FastAPI app exposing the StarSI stream protocol.

Endpoints (subject to protocol/README.md):
  POST /v1/chat        — StarSI native: ChatRequest in, StreamEvent frames out
  POST /v1/chat/completions — OpenAI-compatible shim so off-the-shelf iOS
                              clients work during validation (roadmap step 2)
  GET  /v1/models      — registry for this node
  GET  /health         — used by the router's reachability check

TODO: wire Router + backends; SSE for the OpenAI shim, framed stream for native.
"""

from __future__ import annotations

from fastapi import FastAPI

from starsi_core import Registry
from starsi_inference.router import Router


def create_app(registry: Registry, self_node: str) -> FastAPI:
    app = FastAPI(title="StarSI node", version="0.0.1")
    router = Router(registry, self_node)
    app.state.router = router

    @app.get("/health")
    async def health() -> dict:
        return {"ok": True, "node": self_node}

    @app.get("/v1/models")
    async def models() -> Registry:
        return registry

    return app
