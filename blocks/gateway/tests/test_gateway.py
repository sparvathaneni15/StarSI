import json

import httpx
import pytest
from fastapi.testclient import TestClient
from starsi_gateway.config import Settings, Tier
from starsi_gateway.server import create_app
from starsi_gateway.spool import SyncSpool

TOKEN = "test-token"
AUTH = {"Authorization": f"Bearer {TOKEN}"}


def make_settings(tmp_path, memory_url="http://memory"):
    return Settings(
        site="test",
        auth_token=TOKEN,
        tiers={
            "starsi-cpu": Tier("starsi-cpu", "http://cpu/v1", "m-cpu"),
            "starsi-gpu": Tier("starsi-gpu", "http://gpu/v1", "m-gpu"),
        },
        default_tier="starsi-cpu",
        memory_url=memory_url,
        sync_spool_dir=tmp_path / "spool",
    )


class Upstream:
    """Scriptable fake for every sibling service the gateway talks to."""

    def __init__(self):
        self.requests = []
        self.memory_up = True

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        host, path = request.url.host, request.url.path
        if host == "memory":
            if not self.memory_up:
                raise httpx.ConnectError("memory down")
            turns = json.loads(request.content)["turns"]
            return httpx.Response(200, json={"accepted": len(turns)})
        if path.endswith("/models"):
            return httpx.Response(200 if host == "cpu" else 503, json={"data": []})
        if path.endswith("/chat/completions"):
            body = json.loads(request.content)
            if body.get("stream"):
                sse = (
                    'data: {"choices":[{"delta":{"content":"hi"},"index":0}]}\n\n'
                    "data: [DONE]\n\n"
                )
                return httpx.Response(
                    200, content=sse.encode(), headers={"content-type": "text/event-stream"}
                )
            return httpx.Response(
                200,
                json={"model": body["model"], "choices": [{"message": {"content": "hi"}}]},
            )
        return httpx.Response(404)


@pytest.fixture()
def client(tmp_path):
    app = create_app(make_settings(tmp_path))
    upstream = Upstream()
    with TestClient(app) as c:
        app.state.http = httpx.AsyncClient(transport=httpx.MockTransport(upstream.handler))
        c.upstream = upstream
        c.app = app
        yield c


def test_health_reports_tiers(client):
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["tiers"]["starsi-cpu"]["up"] is True
    assert body["tiers"]["starsi-gpu"]["up"] is False


def test_chat_requires_auth(client):
    r = client.post("/v1/chat/completions", json={"messages": [{"role": "user", "content": "x"}]})
    assert r.status_code == 401


def test_chat_routes_tier_and_rewrites_model(client):
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={
            "model": "starsi-gpu",
            "stream": False,
            "messages": [{"role": "user", "content": "x"}],
        },
    )
    assert r.status_code == 200
    sent = json.loads(client.upstream.requests[-1].content)
    assert client.upstream.requests[-1].url.host == "gpu"
    assert sent["model"] == "m-gpu"


def test_chat_unknown_model_falls_back_to_default(client):
    client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={"model": "nope", "stream": False, "messages": [{"role": "user", "content": "x"}]},
    )
    assert client.upstream.requests[-1].url.host == "cpu"


def test_chat_streams_sse(client):
    r = client.post(
        "/v1/chat/completions",
        headers=AUTH,
        json={"messages": [{"role": "user", "content": "x"}]},
    )
    assert r.status_code == 200
    assert "data: [DONE]" in r.text


def test_sync_forwards_to_memory(client):
    r = client.post("/v1/sync", headers=AUTH, json={"turns": [{"turn_id": "a"}]})
    assert r.json() == {"accepted": 1}


def test_sync_spools_when_memory_down_then_flushes(client):
    client.upstream.memory_up = False
    r = client.post("/v1/sync", headers=AUTH, json={"turns": [{"turn_id": "a"}]})
    assert r.json() == {"accepted": 0, "spooled": 1}
    assert client.get("/health").json()["spooled_turns"] == 1

    client.upstream.memory_up = True
    flushed = client.portal.call(client.app.state.flush_spool, client.app.state.http)
    assert flushed == 1
    assert client.get("/health").json()["spooled_turns"] == 0


def test_spool_clear_keeps_unflushed(tmp_path):
    spool = SyncSpool(tmp_path)
    spool.append([{"turn_id": "a"}, {"turn_id": "b"}, {"turn_id": "c"}])
    spool.clear(2)
    assert spool.peek() == [{"turn_id": "c"}]
