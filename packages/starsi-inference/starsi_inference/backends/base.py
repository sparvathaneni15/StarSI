"""Engine-agnostic backend interface."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass

from starsi_core import ChatMessage, SamplingConfig


@dataclass
class GenerationChunk:
    text: str
    is_thinking: bool = False
    finished: bool = False


class Backend(ABC):
    """One loaded model on one node."""

    name: str

    @abstractmethod
    async def load(self) -> None: ...

    @abstractmethod
    async def unload(self) -> None: ...

    @abstractmethod
    def generate(
        self, messages: list[ChatMessage], sampling: SamplingConfig
    ) -> AsyncIterator[GenerationChunk]: ...
