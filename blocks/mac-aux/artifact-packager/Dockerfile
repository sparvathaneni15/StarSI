# The "inverse prep": fused safetensors from MLX training -> deployable
# artifacts (GGUF q4_K_M for the CPU tier, safetensors tarball for vLLM) -> S3.
# Built on llama.cpp's full image, which carries convert_hf_to_gguf.py and
# llama-quantize.
FROM ghcr.io/ggml-org/llama.cpp:full
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip curl unzip && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir --break-system-packages awscli
COPY package.sh /package.sh
RUN chmod +x /package.sh
ENTRYPOINT ["/package.sh"]
