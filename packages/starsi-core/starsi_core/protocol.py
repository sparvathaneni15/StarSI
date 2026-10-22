"""Wire protocol between the iPhone client and a StarSI node.

Transport-agnostic: these are the payloads, whichever of gRPC / framed
TCP / WebSocket ends up carrying them (see protocol/README.md). Keep
the JSON schema in protocol/ in sync with these models; the Swift
client is generated from the schema, not from this file.
"""

from __future__ import annotations

from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field


class Role(StrEnum):
    SYSTEM = "system"
    USER = "user"
    ASSISTANT = "assistant"
    TOOL = "tool"


class ChatMessage(BaseModel):
    role: Role
    content: str
    # Populated on assistant turns that invoked a tool hosted on the phone.
    tool_call_id: str | None = None


class SamplingConfig(BaseModel):
    """Defaults are the ideation-leaning settings from README.md."""

    temperature: float = 1.0
    min_p: float = 0.05
    top_p: float | None = None
    max_tokens: int = 2048
    reasoning_effort: Literal["low", "medium", "high"] = "medium"


class IdeationConfig(BaseModel):
    """Generate-many-then-critique loop.

    When enabled, the node fans out `candidates` completions at the
    request's sampling config, scores them on novelty and plausibility
    separately, and streams only the survivors.
    """

    enabled: bool = False
    candidates: int = Field(default=8, ge=2, le=32)
    survivors: int = Field(default=2, ge=1, le=8)
    novelty_weight: float = 0.5
    plausibility_weight: float = 0.5


class ChatRequest(BaseModel):
    messages: list[ChatMessage]
    model: str | None = None  # None → router picks
    sampling: SamplingConfig = SamplingConfig()
    ideation: IdeationConfig = IdeationConfig()
    # MCP servers the phone is exposing for this session, by name.
    # The node will route tool calls back to the client over the same stream.
    tools: list[str] = []
    stream: bool = True


class StreamEvent(BaseModel):
    """One frame on the response stream."""

    type: Literal["token", "thinking", "tool_call", "candidate", "done", "error"]
    content: str = ""
    # For type == "tool_call": which phone-hosted tool, with JSON args.
    tool_name: str | None = None
    tool_args: dict | None = None
    tool_call_id: str | None = None
    # For type == "candidate": index + scores from the ideation loop.
    candidate_index: int | None = None
    novelty: float | None = None
    plausibility: float | None = None
    # For type == "done": which node and model actually answered.
    served_by: str | None = None
    model: str | None = None
