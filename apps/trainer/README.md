# starsi-trainer

The data factory and post-training pipeline. Runs on beast-pc (RTX 5080, 16 GB, CUDA).

```sh
uv sync --extra cuda
uv run starsi-generate   # dialogues from a serving node → data/generated/
uv run starsi-judge      # novelty + plausibility scores
uv run starsi-pairs      # DPO preference pairs → data/pairs/
uv run starsi-train      # QLoRA SFT → DPO on a ≤14B base
```

The 27B run is executed elsewhere (Studio via MLX, or rented GPU) using the
pairs this pipeline produces. See `scripts/mlx_lora.sh`.

`data/raw`, `data/generated`, `data/pairs` are git-ignored.
