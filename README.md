# StarSI

**A voice-native personal AI assistant built from lego-block services: the Mac trains, the Pi orchestrates, AWS serves, and every byte between devices rides SSH.**

| Machine | Role | Runs |
|---|---|---|
| **iPhone** | Voice/chat UI, router, SSH client | SwiftUI app; swift-nio-ssh tunnel; on-device captions (SFSpeechRecognizer) |
| **Mac combo** (MacBook now, Studio later) | **Model training**, bare-metal MLX | `train/` CLI + Docker Compose aux blocks (mlflow, dataset-prep, artifact-packager) |
| **Raspberry Pi** | Always-on home hub + model-lifecycle orchestrator | k3s: memory, registry, pipeline Jobs |
| **AWS** | **All inference** + voice | k3s: gateway, llama.cpp CPU tier (always on), vLLM GPU tier (scale-to-zero), whisper STT, Kokoro TTS, capacity-controller |

## Architecture rules

1. **Kubernetes is the unit of assembly.** Every service is a lego block in `blocks/<name>/{src,Dockerfile,chart}`; a site is just a helmfile/compose picking blocks (`deploy/sites/{pi,aws,mac}`). Per-site single-node k3s clusters — never one stretched cluster (SSH-only networking can't carry CNI traffic).
2. **All networking rides SSH.** The only public port anywhere is 22. Services are loopback NodePorts reached through `ssh -L`/`-R` (see `infra/tunnels/tunnels.toml` for the canonical port map). The phone embeds swift-nio-ssh with a per-device ed25519 key and pinned host keys; machines use autossh units. No TLS, no VPN, no exceptions.
3. **Voice is the native interface.** The wire carries waveforms (`/v1/voice` WebSocket): the phone streams an utterance up, synthesized speech streams back. Display text is rendered locally on the phone; server-side Whisper transcripts feed the LLM, memory, and retraining.
4. **Containers never touch Apple GPUs.** MLX training runs bare-metal on the Mac; its containers are auxiliaries only.
5. **The Pi never touches weights.** Pipeline Jobs are thin SSH drivers; fetch/train/fuse run on the Mac bare-metal, conversion/quantization in the Mac's `artifact-packager` container, artifacts land in S3.

## Model lifecycle (the Pi's loop)

```
HuggingFace ─fetch→ Mac (MLX LoRA ─fuse→ safetensors)
   ─package→ GGUF q4_K_M + safetensors.tar → S3
   ─deploy→ registry records version; AWS tiers roll to it
memory turns ─dataset-prep→ training pairs (the retraining flywheel)
```

Run it: `kubectl create job --from=cronjob/starsi-pipeline retrain-1` on the Pi.

## Routing (on the iPhone, `apps/ios/Sources/StarSIRouter/RuleTable.swift`, unit-tested)

private → on-device (opt-in to own-cloud) · live phone data → on-device · instant+low → on-device · medium/high reasoning → GPU tier (waking the instance if stopped; "waking GPU…" badge; CPU tier serves meanwhile) · otherwise → CPU tier · tunnel down → on-device with offline badge. Fallback chain GPU → CPU → iPhone. Reachability is one fact — is the SSH tunnel up — plus the gateway's `/health`.

## Repo layout

```
apps/ios        SwiftUI app — StarSIApp (UI), StarSIClient (SSE protocol),
                StarSIRouter (rule table), StarSITunnel (swift-nio-ssh),
                StarSIVoice (capture/VAD/playback/captions), StarSITools
blocks/         gateway · memory · registry · model-pipeline · inference-cpu ·
                inference-gpu · capacity-controller · stt · tts · mac-aux
deploy/sites/   pi/ aws/ (helmfiles) · mac/ (compose: dev stack + training aux)
infra/          pi/ (k3s install) · aws/ (terraform: EC2+SG+S3+IAM) ·
                ssh/ (keys, authorized_keys.d, distribution) · tunnels/ (autossh)
train/          bare-metal Mac MLX CLI: starsi-train fetch|lora|status|fuse
protocol/       wire contracts (chat SSE, health, sync, voice frames)
.github/        CI: pytest + swift test + helm lint; buildx multi-arch → GHCR
```

## Bring-up order

1. **Local dev** (no hardware): `make compose-up` → gateway + memory + small llama.cpp on the Mac; `curl localhost:8484/health`.
2. **AWS**: `cd infra/aws && terraform apply`, push `authorized_keys`, `helmfile -f deploy/sites/aws/helmfile.yaml apply`. Verify: `ssh -L 8484:127.0.0.1:30086 starsi@<ip>` then chat via curl.
3. **Pi**: `infra/pi/install-k3s.sh`, `helmfile -f deploy/sites/pi/helmfile.yaml apply`, enable `pi-to-aws.service`.
4. **Phone**: `cd apps/ios && xcodegen generate`, build StarSIApp; Settings → AWS host + pinned host key; copy the phone's public key into `infra/ssh/authorized_keys.d/aws` and redistribute.
5. **First retrain**: run the pipeline Job; watch mlflow at `mac:5000`.

## Tests

- Python blocks: `make test` (gateway SSE/tier-routing/spool, voice WS round-trip, memory idempotency, registry, pipeline sequencing, capacity controller)
- Swift: `make ios-test` (rule table matrix, SSE parsing, and a real SSH round-trip against an in-process NIOSSH server + host-key-pinning rejection)
- Charts: `make charts` (helm lint + render all nine)
