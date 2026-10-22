"""Novelty = distance from the space of generic answers.

Embed the candidate; compare against a corpus of "mode" answers to the
same prompt (generated at low temperature). Larger distance → more novel.
Shared with starsi_inference.router so the serve-time ideation loop and
the train-time judge agree on what "novel" means.

TODO: pick embedding model (small, runs on both CUDA and MLX); define
      the generic-corpus generation step.
"""

from __future__ import annotations


def novelty_score(candidate: str, generic_pool: list[str]) -> float:
    raise NotImplementedError
