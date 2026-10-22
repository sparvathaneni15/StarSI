"""Entry point for the MacBook edge node.

Identical shape to starsi_hub.main; kept separate so edge-only concerns
(battery awareness, pause-on-sleep, "am I at home or away" detection)
have somewhere to live without leaking into the hub.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import uvicorn
import yaml

from starsi_core import Registry
from starsi_inference.server import create_app


def main() -> None:
    parser = argparse.ArgumentParser(prog="starsi-edge")
    parser.add_argument("--config", type=Path, default=Path("configs/edge.yaml"))
    args = parser.parse_args()

    cfg = yaml.safe_load(args.config.read_text())
    registry = Registry.model_validate({"nodes": [cfg["node"]]})
    app = create_app(registry, self_node=cfg["node"]["name"])
    uvicorn.run(app, host=cfg.get("bind", "0.0.0.0"), port=cfg["node"]["port"])


if __name__ == "__main__":
    main()
