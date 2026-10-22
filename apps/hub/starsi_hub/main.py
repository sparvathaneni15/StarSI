"""Entry point for the Mac Studio hub.

Runs as a LaunchDaemon (see scripts/launchd/). Loads models listed in
configs/hub.yaml, advertises over Bonjour, serves the stream protocol.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import uvicorn
import yaml

from starsi_core import Registry
from starsi_inference.server import create_app


def main() -> None:
    parser = argparse.ArgumentParser(prog="starsi-hub")
    parser.add_argument("--config", type=Path, default=Path("configs/hub.yaml"))
    args = parser.parse_args()

    cfg = yaml.safe_load(args.config.read_text())
    registry = Registry.model_validate({"nodes": [cfg["node"]]})
    app = create_app(registry, self_node=cfg["node"]["name"])
    uvicorn.run(app, host=cfg.get("bind", "0.0.0.0"), port=cfg["node"]["port"])


if __name__ == "__main__":
    main()
