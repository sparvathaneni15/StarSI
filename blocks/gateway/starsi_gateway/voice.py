"""/v1/voice — the voice-native session.

The wire carries waveforms: the phone streams an utterance up as binary
frames, and synthesized speech comes back down as binary frames. Text frames
are JSON metadata (transcripts for memory, sentence markers, errors); the
phone renders its own display text locally and may ignore them.

Client → server:
    {"type":"start","token":"...","model":"starsi-cpu","format":"wav"}
    <binary audio frames of one utterance>          (phone-side VAD decides)
    {"type":"end"}
    {"type":"cancel"}                               (barge-in)

Server → client:
    {"type":"transcript","role":"user","text":...}  (whisper, authoritative)
    {"type":"sentence","text":...}                  (precedes its audio)
    <binary audio frames (synthesized speech)>
    {"type":"turn_end"}
    {"type":"error","text":...}

Turn flow: audio → stt block → inference tier (SSE) → sentence-chunk → tts
block → audio. Both transcripts are appended to memory (or the spool), so
voice turns feed retraining like any other.
"""

from __future__ import annotations

import asyncio
import json
import re
import time
import uuid

import httpx
from fastapi import FastAPI, WebSocket, WebSocketDisconnect

from .config import Settings
from .spool import SyncSpool

SENTENCE_RE = re.compile(r"(.*?[.!?\n])(\s|$)", re.S)
MIN_SENTENCE_CHARS = 12


def sentence_chunks(deltas):
    """Re-chunk a token/delta stream into speakable sentences."""

    async def gen():
        buf = ""
        async for delta in deltas:
            buf += delta
            while True:
                m = SENTENCE_RE.match(buf)
                if not m or len(m.group(1).strip()) < MIN_SENTENCE_CHARS:
                    break
                yield m.group(1).strip()
                buf = buf[m.end():]
        if buf.strip():
            yield buf.strip()

    return gen()


def add_voice_routes(app: FastAPI, settings: Settings, spool: SyncSpool) -> None:
    async def store_turns(http: httpx.AsyncClient, turns: list[dict]) -> None:
        if settings.memory_url is not None:
            try:
                r = await http.post(
                    f"{settings.memory_url}/v1/sync", json={"turns": turns}, timeout=10
                )
                r.raise_for_status()
                return
            except httpx.HTTPError:
                pass
        spool.append(turns)

    async def transcribe(http: httpx.AsyncClient, audio: bytes, fmt: str) -> str:
        r = await http.post(
            f"{settings.stt_url}/audio/transcriptions",
            files={"file": (f"utterance.{fmt}", audio, f"audio/{fmt}")},
            data={"response_format": "json"},
            timeout=60,
        )
        r.raise_for_status()
        return r.json().get("text", "").strip()

    async def synthesize(http: httpx.AsyncClient, text: str, fmt: str) -> bytes:
        r = await http.post(
            f"{settings.tts_url}/audio/speech",
            json={"input": text, "response_format": fmt, "model": "tts", "voice": "default"},
            timeout=60,
        )
        r.raise_for_status()
        return r.content

    def chat_deltas(http: httpx.AsyncClient, tier, messages, cancelled: asyncio.Event):
        async def gen():
            body = {"model": tier.upstream_model, "messages": messages, "stream": True}
            async with http.stream(
                "POST", f"{tier.base_url}/chat/completions", json=body, timeout=300
            ) as r:
                r.raise_for_status()
                async for line in r.aiter_lines():
                    if cancelled.is_set():
                        return
                    if not line.startswith("data: "):
                        continue
                    data = line[len("data: "):]
                    if data == "[DONE]":
                        return
                    try:
                        delta = json.loads(data)["choices"][0]["delta"].get("content")
                    except (json.JSONDecodeError, KeyError, IndexError):
                        continue
                    if delta:
                        yield delta

        return gen()

    @app.websocket("/v1/voice")
    async def voice(ws: WebSocket):
        await ws.accept()
        http: httpx.AsyncClient = ws.app.state.http
        if settings.stt_url is None or settings.tts_url is None:
            await ws.send_json({"type": "error", "text": "voice blocks not configured"})
            await ws.close()
            return

        session_messages: list[dict] = []
        authed = False
        audio = bytearray()
        fmt = "wav"
        tier_name = settings.default_tier
        cancelled = asyncio.Event()
        speaking_task: asyncio.Task | None = None

        async def run_turn(utterance: bytes) -> None:
            tier = settings.tiers.get(tier_name) or settings.tiers.get(settings.default_tier)
            if tier is None:
                await ws.send_json({"type": "error", "text": "no inference tier configured"})
                return
            try:
                user_text = await transcribe(http, utterance, fmt)
            except httpx.HTTPError as exc:
                await ws.send_json({"type": "error", "text": f"stt failed: {exc}"})
                return
            if not user_text:
                await ws.send_json({"type": "turn_end"})
                return
            await ws.send_json({"type": "transcript", "role": "user", "text": user_text})
            session_messages.append({"role": "user", "content": user_text})

            reply_parts: list[str] = []
            try:
                deltas = chat_deltas(http, tier, session_messages, cancelled)
                async for sentence in sentence_chunks(deltas):
                    if cancelled.is_set():
                        break
                    reply_parts.append(sentence)
                    await ws.send_json({"type": "sentence", "text": sentence})
                    try:
                        await ws.send_bytes(await synthesize(http, sentence, fmt))
                    except httpx.HTTPError as exc:
                        await ws.send_json({"type": "error", "text": f"tts failed: {exc}"})
            except httpx.HTTPError as exc:
                await ws.send_json({"type": "error", "text": f"inference failed: {exc}"})

            reply = " ".join(reply_parts)
            if reply:
                session_messages.append({"role": "assistant", "content": reply})
                now = time.time()
                await store_turns(http, [
                    {"turn_id": uuid.uuid4().hex, "role": "user",
                     "content": user_text, "ts": now, "channel": "voice"},
                    {"turn_id": uuid.uuid4().hex, "role": "assistant",
                     "content": reply, "ts": now, "channel": "voice",
                     "model": tier.name},
                ])
            await ws.send_json({"type": "turn_end"})

        try:
            while True:
                message = await ws.receive()
                if message.get("type") == "websocket.disconnect":
                    break
                if (data := message.get("bytes")) is not None:
                    if authed:
                        audio.extend(data)
                    continue
                event = json.loads(message.get("text") or "{}")
                kind = event.get("type")
                if kind == "start":
                    if event.get("token") != settings.auth_token:
                        await ws.send_json({"type": "error", "text": "bad token"})
                        await ws.close(code=4401)
                        return
                    authed = True
                    audio.clear()
                    cancelled.clear()
                    fmt = event.get("format", "wav")
                    tier_name = event.get("model", settings.default_tier)
                elif kind == "end" and authed:
                    utterance = bytes(audio)
                    audio.clear()
                    speaking_task = asyncio.create_task(run_turn(utterance))
                elif kind == "cancel":
                    cancelled.set()
                    if speaking_task:
                        await speaking_task
        except WebSocketDisconnect:
            pass
        finally:
            cancelled.set()
            if speaking_task and not speaking_task.done():
                await speaking_task
