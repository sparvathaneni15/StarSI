"""Turn the Pi's memory into MLX LoRA training data.

Pages GET /v1/turns out of the memory block, pairs user/assistant turns into
mlx_lm chat format, and writes train/valid jsonl splits where starsi-train
expects them. Runs on the Mac (compose service `dataset-prep`); the memory
block is reachable on the LAN at the Pi's NodePort.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import httpx

MEMORY_URL = os.environ.get("STARSI_MEMORY_URL", "http://raspberrypi.local:30084")
TOKEN = os.environ.get("STARSI_AUTH_TOKEN", "")
OUT_DIR = Path(os.environ.get("DATA_DIR", "/data"))
VALID_EVERY = 10  # every Nth pair goes to the validation split


def fetch_turns() -> list[dict]:
    turns, since = [], 0
    with httpx.Client(headers={"Authorization": f"Bearer {TOKEN}"}, timeout=30) as http:
        while True:
            r = http.get(f"{MEMORY_URL}/v1/turns", params={"since": since, "limit": 1000})
            r.raise_for_status()
            page = r.json()
            turns.extend(page["turns"])
            if page["next"] == since:
                return turns
            since = page["next"]


def to_pairs(turns: list[dict]) -> list[dict]:
    pairs = []
    pending_user = None
    for turn in turns:
        role, text = turn.get("role"), (turn.get("content") or "").strip()
        if not text:
            continue
        if role == "user":
            pending_user = text
        elif role == "assistant" and pending_user:
            pairs.append({"messages": [
                {"role": "user", "content": pending_user},
                {"role": "assistant", "content": text},
            ]})
            pending_user = None
    return pairs


def main() -> None:
    pairs = to_pairs(fetch_turns())
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    train = [p for i, p in enumerate(pairs) if i % VALID_EVERY != 0]
    valid = [p for i, p in enumerate(pairs) if i % VALID_EVERY == 0]
    for name, rows in (("train", train), ("valid", valid)):
        with (OUT_DIR / f"{name}.jsonl").open("w") as f:
            for row in rows:
                f.write(json.dumps(row) + "\n")
    print(json.dumps({"pairs": len(pairs), "train": len(train), "valid": len(valid)}))


if __name__ == "__main__":
    main()
