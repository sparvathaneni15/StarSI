"""MLX backend for Apple Silicon.

Wraps mlx-lm. Sampling notes from README.md: prefer min-p over top-p,
expose reasoning_effort where the model supports it.

TODO: implement against mlx_lm.generate / stream_generate; handle
      reasoning_effort via chat-template kwargs; honour adapters.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

from starsi_core import ChatMessage, ModelEntry, SamplingConfig
from starsi_inference.backends.base import Backend, GenerationChunk


class MLXBackend(Backend):
    def __init__(self, entry: ModelEntry) -> None:
        self.entry = entry
        self.name = entry.name
        self._model = None
        self._tokenizer = None

    async def load(self) -> None:
        raise NotImplementedError

    async def unload(self) -> None:
        self._model = None
        self._tokenizer = None

    async def generate(
        self, messages: list[ChatMessage], sampling: SamplingConfig
    ) -> AsyncIterator[GenerationChunk]:
        raise NotImplementedError
        yield  # pragma: no cover — makes this an async generator
