"""starsi-core: shared contracts between every StarSI node.

Nothing here does I/O. This package is the single source of truth for
what a request, a response, a model, and a node look like, so that the
hub, the edge, the trainer, and the iOS client (via protocol/) all agree.
"""

from starsi_core.protocol import (
    ChatMessage,
    ChatRequest,
    IdeationConfig,
    Role,
    SamplingConfig,
    StreamEvent,
)
from starsi_core.registry import ModelEntry, NodeEntry, NodeKind, Registry

__all__ = [
    "ChatMessage",
    "ChatRequest",
    "IdeationConfig",
    "ModelEntry",
    "NodeEntry",
    "NodeKind",
    "Registry",
    "Role",
    "SamplingConfig",
    "StreamEvent",
]
