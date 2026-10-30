# StarSI wire protocol

Five contracts, all served by the gateway block and reached only through SSH
tunnels (loopback NodePorts — see `infra/tunnels/tunnels.toml`). The Swift and
Python sides mirror these by hand; keep them in sync.

## 1. Chat — OpenAI-compatible

`POST /v1/chat/completions` with `Authorization: Bearer <device-token>`.
The `model` field selects the inference tier: `starsi-cpu` (always-on
llama.cpp) or `starsi-gpu` (scale-to-zero vLLM; requests touch the
capacity-controller so a stopped instance wakes).

```json
{
  "model": "starsi-cpu",
  "messages": [{"role": "user", "content": "hello"}],
  "stream": true,
  "max_tokens": 2048,
  "temperature": 0.7
}
```

Streaming response: SSE frames `data: {chat.completion.chunk}` with
`choices[0].delta.content` text deltas, a final frame with
`finish_reason: "stop"`, then `data: [DONE]`.

## 2. Voice — `/v1/voice` WebSocket (the native interface)

The wire carries waveforms; text frames are JSON metadata. The phone renders
its own display text locally (on-device recognition); server transcripts are
authoritative for memory/retraining.

Client → server:

```
{"type":"start","token":"...","model":"starsi-cpu","format":"wav"}
<binary: one utterance as 16 kHz mono 16-bit WAV>     (phone-side VAD decides)
{"type":"end"}
{"type":"cancel"}                                     (barge-in)
```

Server → client, per turn:

```
{"type":"transcript","role":"user","text":"..."}      (whisper)
{"type":"sentence","text":"..."}                      (precedes its audio)
<binary: synthesized speech for that sentence (WAV)>
{"type":"turn_end"}
{"type":"error","text":"..."}
```

Pipeline server-side: stt block (faster-whisper) → inference tier (SSE) →
sentence-chunking → tts block (Kokoro/Piper). Both transcripts are appended
to memory.

## 3. Health

`GET /health` on the gateway (no auth):

```json
{
  "status": "ok", "site": "aws",
  "tiers": {"starsi-cpu": {"up": true}, "starsi-gpu": {"up": false}},
  "gpu_state": "stopped",
  "agent": false, "spooled_turns": 0, "uptime_s": 12.3
}
```

One call tells the router everything: per-tier health and the GPU instance
state. Tunnel liveness itself is known client-side from the SSH connection.

## 4. Router labels — System One

The on-device router model (Kev-0.8B, or hosted TypeSafe Jev later) answers
typed questions about the prompt via the System One shape
(`POST /v1/systemone` when hosted; same types in-process):

| label | question type | values |
|---|---|---|
| `reasoning` | score | `low < medium < high` |
| `latency_tolerance` | score | `instant < normal < patient` |
| `needs_live_phone_data` | noul | yes/no |
| `sensitivity` | noul | normal/private |

Answers carry per-option probabilities; the rule table consumes the argmax
and logs the confidence. Low-confidence answers fall back to
`medium / normal / false / normal`.

## 5. Turn sync + read-back

`POST /v1/sync` with auth (gateway forwards to the Pi memory block, spooling
locally while the reverse tunnel is down):

```json
{"turns": [{"turn_id": "uuid", "ts": 1767000000.0, "role": "user", "content": "...", "channel": "voice"}]}
```

Response `{"accepted": n}`. `turn_id` dedupes; replaying a batch is idempotent.
`GET /v1/turns?since=<offset>&limit=<n>` (memory block, auth) pages turns back
out for dataset-prep: `{"turns": [...], "next": <offset>}`.

## Discovery

There is none — no Bonjour, no mDNS. Hosts and pinned SSH host keys are static
config (`config/targets.toml`, phone Settings); reachability is tunnel health.
