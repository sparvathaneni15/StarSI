# StarSI wire protocol

Transport-agnostic payloads exchanged between the iPhone client and a node.

- `starsi.schema.json` — JSON Schema for `ChatRequest` and `StreamEvent`.
- Python reference types: `packages/starsi-core/starsi_core/protocol.py`
- Swift reference types: `apps/ios/Sources/StarSIClient/Protocol.swift`

Both implementations are checked against the schema in CI (TODO).

## Transport (open question)

All candidates run over IP; proximity is a *discovery* concern, not a
transport one.

| Option | Pros | Cons |
|---|---|---|
| HTTP + newline-delimited JSON | Already exposed by the node; trivially testable with curl | Request/response per turn; tool round-trips need a second connection |
| WebSocket | Bidirectional on one socket; tool_call → tool result stays in-stream | Framing overhead; another dependency on the Swift side |
| gRPC bidi stream | Typed, efficient, codegen for both sides | Heavier toolchain; harder to debug by hand |
| Framed TCP over `NWConnection` | Minimal; works identically over Bonjour, Multipeer, Tailscale | Hand-rolled framing and reconnection |

Starting point: HTTP+NDJSON for validation. Likely destination: framed
TCP over `NWConnection`, because the tool-calling loop (node → phone →
node) wants one long-lived bidirectional stream and the phone already
holds the socket.

## Stream contract

Frames are `StreamEvent` objects. Order per turn:

```
thinking*  token*  (tool_call  → client replies with a tool message → thinking* token*)*  done
```

`candidate` frames appear only when `ideation.enabled`, before the first
`token`, and carry per-candidate novelty/plausibility scores.
