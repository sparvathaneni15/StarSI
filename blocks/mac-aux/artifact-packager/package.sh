#!/usr/bin/env bash
# package.sh --run-id <id> --name <model> --version <v>
# Expects the fused model at $RUNS_DIR/<id>/fused (mounted from the Mac host).
set -euo pipefail

RUNS_DIR="${RUNS_DIR:-/runs}"
BUCKET="${S3_BUCKET:-starsi-artifacts}"
QUANT="${QUANT:-q4_K_M}"

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id) RUN_ID="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    *) echo "unknown arg $1" >&2; exit 2;;
  esac
done

FUSED="$RUNS_DIR/$RUN_ID/fused"
OUT="$RUNS_DIR/$RUN_ID/artifacts"
mkdir -p "$OUT"

echo ">> convert to GGUF f16"
python3 /app/convert_hf_to_gguf.py "$FUSED" --outfile "$OUT/model-f16.gguf" --outtype f16

echo ">> quantize $QUANT"
/app/llama-quantize "$OUT/model-f16.gguf" "$OUT/model.gguf" "$QUANT"
rm "$OUT/model-f16.gguf"

echo ">> tar safetensors for vLLM"
tar -cf "$OUT/model.safetensors.tar" -C "$FUSED" .

echo ">> upload to s3://$BUCKET/$NAME/$VERSION/"
aws s3 cp "$OUT/model.gguf" "s3://$BUCKET/$NAME/$VERSION/model.gguf"
aws s3 cp "$OUT/model.safetensors.tar" "s3://$BUCKET/$NAME/$VERSION/model.safetensors.tar"

echo ">> done: $NAME/$VERSION"
