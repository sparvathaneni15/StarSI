# Architecture notes

Supplements the diagram in the root README.

## Repo layout

```
apps/
  trainer/   beast-pc · data factory + post-training (CUDA)
  hub/       Mac Studio · always-on inference hub (MLX)
  edge/      MacBook Pro · portable inference (MLX)
  ios/       iPhone · SwiftUI interface + on-device MCP host
packages/
  starsi-core/        shared types: protocol, registry   (pure Python)
  starsi-inference/   serving layer used by hub and edge
protocol/             wire protocol schema + transport decision
scripts/              launchd install, MLX LoRA runner
docs/                 this
```

## Why hub and edge are separate apps

They run the same `starsi-inference` package. They are separate apps
because their configs, lifecycles, and failure modes differ: the hub never
sleeps and loads 100 GB models; the edge is on battery, sleeps, and must
know whether it is at home (defer to hub) or away (serve itself). Those
concerns get files of their own instead of `if node.kind == "edge"` spread
through shared code.

## Tool calling runs through the phone

The phone hosts MCP servers (`apps/ios/Sources/StarSIMCP`). A node never
connects to the phone; it emits `tool_call` frames on the stream the
phone already opened, the phone executes the tool on-device, and the
result comes back as the next `tool` message. This keeps the phone
unreachable from the network while still letting the model use calendar,
location, the Zettelkasten, and anything else only the phone has.

## Where the shared judge lives

`novelty_score` is defined once in `starsi_trainer.judges` and imported by
`starsi_inference.router` for the serve-time ideation loop, so "novel"
means the same thing at training time and at inference time.
