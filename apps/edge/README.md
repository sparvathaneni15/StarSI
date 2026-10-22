# starsi-edge

The portable inference node. Runs on the MacBook Pro (M4 Max, 36 GB).

This is where everything gets developed first; it is the only serving
node that exists until the Studio arrives. After that it becomes the
on-the-road fallback.

```sh
# one-time, persists via scripts/launchd
sudo sysctl iogpu.wired_limit_mb=32768

uv sync --extra mlx
uv run starsi-edge --config configs/edge.yaml
```

Validate the GPU path before touching the Swift client by pointing any
OpenAI-compatible iOS client at `http://<macbook>.local:8080/v1`.
