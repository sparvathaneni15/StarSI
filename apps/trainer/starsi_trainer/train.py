"""Stage 4: SFT on the top slice, then short low-rank DPO.

On beast-pc (16 GB) this fits bases ≤ ~14B via QLoRA — judges and
experiments. The headline 27B run uses the same data but executes on the
Studio with MLX (scripts/mlx_lora.sh) or a rented 48–80 GB card.

Keep rank low and the run short: the goal is to shift the distribution
toward non-obvious answers, not to retrain the model's personality.

TODO: implement with TRL SFTTrainer → DPOTrainer; configs/train.yaml.
"""

from __future__ import annotations


def main() -> None:
    raise NotImplementedError
