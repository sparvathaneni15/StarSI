#!/usr/bin/env bash
# LoRA on the 27B, run on the Studio (or any Mac with the memory).
# Consumes pairs produced by apps/trainer; see starsi_trainer/train.py.
#   scripts/mlx_lora.sh mlx-community/Qwen3.8-27B-8bit apps/trainer/data/pairs adapters/qwen27b-v1
set -euo pipefail
MODEL="${1:?base model repo}"
DATA="${2:?pairs dir}"
OUT="${3:?adapter output dir}"
# TODO: mlx_lm.lora --model "$MODEL" --train --data "$DATA" --adapter-path "$OUT" \
#       --lora-rank 8 --iters ... ; DPO via mlx_lm's preference-training path once chosen.
echo "not implemented: $MODEL $DATA $OUT"
