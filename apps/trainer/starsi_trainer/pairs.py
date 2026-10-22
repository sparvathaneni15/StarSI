"""Stage 3: build DPO preference pairs.

preferred  = high novelty AND acceptable plausibility
rejected   = the mode: low novelty, the first thing anyone would say,
             or a turn that caved to pressure without an argument

Writes data/pairs/*.jsonl in TRL's DPO format.

TODO: implement; keep weights configurable in configs/pairs.yaml.
"""

from __future__ import annotations


def main() -> None:
    raise NotImplementedError
