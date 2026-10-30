"""Optional Hermes agent layer.

The retired apps/node ran Hermes via its bundled Python at ~/.hermes; here the
hermes-agent source is mounted into the container (STARSI_HERMES_DIR) and run
in-process against the configured inference tier. Default off — the raw proxy
path never depends on this import succeeding.
"""

from __future__ import annotations

import asyncio
import sys
from collections.abc import AsyncIterator

from .config import Settings


class HermesAgent:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.ready = False
        self.error: str | None = None
        self._agent = None
        self._lock = asyncio.Lock()

    async def start(self) -> None:
        tier = self.settings.tiers.get(self.settings.default_tier)
        if tier is None:
            self.error = "no default tier for the agent to target"
            return
        try:
            if self.settings.hermes_dir:
                sys.path.insert(0, self.settings.hermes_dir)
            from run_agent import AIAgent  # provided by the mounted hermes-agent

            self._agent = await asyncio.to_thread(
                AIAgent,
                provider="custom",
                base_url=tier.base_url,
                model=tier.upstream_model,
            )
            self.ready = True
        except Exception as exc:  # noqa: BLE001 — degrade to raw proxy, never crash
            self.error = f"{type(exc).__name__}: {exc}"
            self.ready = False

    async def ask(self, message: str) -> AsyncIterator[dict]:
        if not self.ready or self._agent is None:
            yield {"type": "error", "text": self.error or "agent not running"}
            return
        async with self._lock:
            try:
                reply = await asyncio.to_thread(self._agent.run, message)
                yield {"type": "final", "text": str(reply)}
            except Exception as exc:  # noqa: BLE001
                yield {"type": "error", "text": f"{type(exc).__name__}: {exc}"}

    async def stop(self) -> None:
        self._agent = None
        self.ready = False
