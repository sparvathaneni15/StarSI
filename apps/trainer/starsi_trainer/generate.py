"""Stage 1: generate multi-turn dialogues.

Drives a serving node (edge now, hub later) with the interlocutor system
prompt as both sides of a conversation, across data/prompts/topics.yaml.
Writes JSONL to data/generated/.

TODO: implement against the StarSI /v1/chat endpoint; vary sampling per
      dialogue so the corpus itself is diverse.
"""

from __future__ import annotations


def main() -> None:
    raise NotImplementedError
