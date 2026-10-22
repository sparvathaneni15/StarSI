"""Model and node registry.

The router consults this to answer: which nodes are reachable, which
models does each have loaded, and which one should answer this request.
Populated from each app's configs/*.yaml at startup.
"""

from __future__ import annotations

from enum import StrEnum

from pydantic import BaseModel


class NodeKind(StrEnum):
    HUB = "hub"  # Mac Studio — always-on, largest models
    EDGE = "edge"  # MacBook — portable, mid-size models
    BATCH = "batch"  # beast-pc — CUDA, batch/specialist only


class ModelEntry(BaseModel):
    name: str  # e.g. "qwen3.8-27b"
    repo: str  # e.g. "mlx-community/Qwen3.8-27B-4bit"
    engine: str  # "mlx" | "vllm"
    quant: str | None = None  # "4bit", "8bit", "mxfp4", ...
    memory_gb: float
    supports_reasoning_effort: bool = False
    is_base: bool = False  # pre-instruct weights, used for divergent fan-out
    adapter: str | None = None  # path to a LoRA adapter, if post-trained
    tags: list[str] = []  # "primary", "ideation", "judge", "teacher", ...


class NodeEntry(BaseModel):
    name: str  # "studio", "macbook", "beast-pc"
    kind: NodeKind
    host: str  # Bonjour name, Tailscale name, or IP
    port: int
    memory_gb: float
    models: list[ModelEntry] = []


class Registry(BaseModel):
    nodes: list[NodeEntry] = []

    def find_model(self, name: str) -> tuple[NodeEntry, ModelEntry] | None:
        for node in self.nodes:
            for model in node.models:
                if model.name == name:
                    return node, model
        return None

    def with_tag(self, tag: str) -> list[tuple[NodeEntry, ModelEntry]]:
        return [(n, m) for n in self.nodes for m in n.models if tag in m.tags]
