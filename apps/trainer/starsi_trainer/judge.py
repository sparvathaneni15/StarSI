"""Stage 2: score every assistant turn.

Two independent signals, never collapsed into one number:
  novelty      — judges/novelty.py   (embedding distance from generic answers)
  plausibility — judges/plausibility.py (judge-model rubric, technical correctness)

Writes data/generated/*.scored.jsonl.

TODO: implement; run the judge model under vLLM for throughput.
"""

from __future__ import annotations


def main() -> None:
    raise NotImplementedError
