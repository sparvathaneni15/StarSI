"""Local spool for /v1/sync turns while the memory block is unreachable
(e.g. the Pi reverse tunnel is down). Append-only JSONL, flushed in order."""

from __future__ import annotations

import json
import threading
from pathlib import Path


class SyncSpool:
    def __init__(self, directory: Path):
        self.file = directory / "sync-spool.jsonl"
        self.file.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def append(self, turns: list[dict]) -> None:
        if not turns:
            return
        with self._lock, self.file.open("a") as f:
            for turn in turns:
                f.write(json.dumps(turn) + "\n")

    def peek(self) -> list[dict]:
        with self._lock:
            if not self.file.exists():
                return []
            with self.file.open() as f:
                return [json.loads(line) for line in f if line.strip()]

    def clear(self, count: int) -> None:
        """Drop the first `count` entries (those successfully flushed)."""
        with self._lock:
            if not self.file.exists():
                return
            with self.file.open() as f:
                lines = [line for line in f if line.strip()]
            remaining = lines[count:]
            with self.file.open("w") as f:
                f.writelines(remaining)

    def size(self) -> int:
        with self._lock:
            if not self.file.exists():
                return 0
            with self.file.open() as f:
                return sum(1 for line in f if line.strip())
