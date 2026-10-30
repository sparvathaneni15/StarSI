import json

import httpx
import pytest
from fastapi.testclient import TestClient
from starsi_gateway.config import Settings, Tier
from starsi_gateway.server import create_app

TOKEN = "test-token"


def make_settings(tmp_path):
    return Settings(
        site="test",
        auth_token=TOKEN,
        tiers={"starsi-cpu": Tier("starsi-cpu", "http://cpu/v1", "m-cpu")},
        default_tier="starsi-cpu",
        memory_url="http://memory",
        sync_spool_dir=tmp_path / "spool",
        stt_url="http://stt/v1",
        tts_url="http://tts/v1",
    )


class VoiceUpstream:
    def __init__(self):
        self.synth_requests = []
        self.memory_turns = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        host = request.url.host
        if host == "stt":
            return httpx.Response(200, json={"text": "what time is it"})
        if host == "tts":
            self.synth_requests.append(json.loads(request.content)["input"])
            return httpx.Response(200, content=b"FAKE-AUDIO")
        if host == "cpu":
            sse = "".join(
                f'data: {json.dumps({"choices": [{"delta": {"content": c}}]})}\n\n'
                for c in ["It is ", "three o'clock.", " Enjoy", " the afternoon!"]
            ) + "data: [DONE]\n\n"
            return httpx.Response(200, content=sse.encode())
        if host == "memory":
            self.memory_turns.extend(json.loads(request.content)["turns"])
            return httpx.Response(200, json={"accepted": 2})
        return httpx.Response(404)


@pytest.fixture()
def voice_client(tmp_path):
    app = create_app(make_settings(tmp_path))
    upstream = VoiceUpstream()
    with TestClient(app) as c:
        app.state.http = httpx.AsyncClient(transport=httpx.MockTransport(upstream.handler))
        c.upstream = upstream
        yield c


def collect_turn(ws):
    events, audio = [], b""
    while True:
        msg = ws.receive()
        if "text" in msg:
            event = json.loads(msg["text"])
            events.append(event)
            if event["type"] in ("turn_end", "error"):
                return events, audio
        elif "bytes" in msg:
            audio += msg["bytes"]


def test_voice_turn_roundtrip(voice_client):
    with voice_client.websocket_connect("/v1/voice") as ws:
        ws.send_json({"type": "start", "token": TOKEN, "format": "wav"})
        ws.send_bytes(b"fake-waveform")
        ws.send_json({"type": "end"})
        events, audio = collect_turn(ws)

    kinds = [e["type"] for e in events]
    assert kinds[0] == "transcript" and events[0]["text"] == "what time is it"
    assert "sentence" in kinds and kinds[-1] == "turn_end"
    assert audio.startswith(b"FAKE-AUDIO")
    # sentence-chunked synthesis, not one monolithic utterance
    assert len(voice_client.upstream.synth_requests) >= 2
    # both transcripts persisted for memory/retraining
    roles = [t["role"] for t in voice_client.upstream.memory_turns]
    assert roles == ["user", "assistant"]
    assert all(t["channel"] == "voice" for t in voice_client.upstream.memory_turns)


def test_voice_rejects_bad_token(voice_client):
    with voice_client.websocket_connect("/v1/voice") as ws:
        ws.send_json({"type": "start", "token": "wrong"})
        msg = ws.receive_json()
        assert msg == {"type": "error", "text": "bad token"}
