"""Technical plausibility via a judge model.

Rubric, not a verifier — there is no ground truth for open-ended ideas.
Judge: gpt-oss-20b (strong on STEM reasoning, fits the 5080) or whatever
the hub is serving once it exists.

TODO: write the rubric in data/prompts/plausibility_rubric.md; return a
      calibrated 0–1 score plus a one-line rationale for inspection.
"""

from __future__ import annotations


def plausibility_score(candidate: str, context: list[str]) -> tuple[float, str]:
    raise NotImplementedError
