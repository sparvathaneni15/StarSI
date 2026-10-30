"""Conversation memory store (moved from apps/node).

The Pi's memory block is the source of truth. Turns arrive via POST /v1/sync
keyed by turn_id for idempotent replay; dataset-prep reads them back out via
GET /v1/turns for training pairs.
"""

from __future__ import annotations

import json
import threading
from pathlib import Path


class MemoryStore:
    def __init__(self, path: Path):
        self.path = path
        self.path.mkdir(parents=True, exist_ok=True)
        self._turns_file = self.path / "turns.jsonl"
        self._lock = threading.Lock()
        self._seen_ids: set[str] = set()
        if self._turns_file.exists():
            with self._turns_file.open() as f:
                for line in f:
                    try:
                        self._seen_ids.add(json.loads(line)["turn_id"])
                    except (json.JSONDecodeError, KeyError):
                        continue

    def append_turns(self, turns: list[dict]) -> int:
        """Append turns, skipping any turn_id already stored. Returns count added."""
        added = 0
        with self._lock, self._turns_file.open("a") as f:
            for turn in turns:
                tid = turn.get("turn_id")
                if not tid or tid in self._seen_ids:
                    continue
                f.write(json.dumps(turn) + "\n")
                self._seen_ids.add(tid)
                added += 1
        return added

    def read_turns(self, since: int = 0, limit: int = 1000) -> tuple[list[dict], int]:
        """Return (turns, next_offset) starting at line offset `since`."""
        with self._lock:
            if not self._turns_file.exists():
                return [], since
            turns = []
            offset = 0
            with self._turns_file.open() as f:
                for offset, line in enumerate(f):  # noqa: B007
                    if offset < since or len(turns) >= limit:
                        continue
                    try:
                        turns.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            return turns, since + len(turns)

    def count(self) -> int:
        with self._lock:
            return len(self._seen_ids)
