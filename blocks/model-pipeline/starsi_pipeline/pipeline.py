"""StarSI model lifecycle orchestrator.

Runs as a Job on the Pi cluster. The Pi never touches weights: every heavy
stage is an SSH command on the Mac (bare-metal MLX for fetch/train/fuse, the
artifact-packager container for Linux conversion + S3 upload). The "inverse
prep" of what put weights onto the Mac is the package stage.

    fetch    ssh mac  starsi-train fetch <hf-repo>
    dataset  ssh mac  docker compose run dataset-prep        (reads Pi memory)
    train    ssh mac  starsi-train lora ... ; poll status    (detached, hours)
    fuse     ssh mac  starsi-train fuse
    package  ssh mac  docker compose run artifact-packager   (gguf + tar -> S3)
    deploy   record version in registry; ssh aws kubectl set env + rollout

Config via env: MAC_SSH, AWS_SSH, HF_REPO, MODEL_NAME, VERSION, RUN_ID,
STARSI_REGISTRY_URL, STARSI_AUTH_TOKEN, REPO_DIR (StarSI checkout on the Mac).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time

import httpx

ALL_STAGES = ["fetch", "dataset", "train", "fuse", "package", "deploy"]
TRAIN_POLL_S = 120


class Runner:
    """Shell/ssh executor, swappable in tests."""

    def run(self, args: list[str]) -> str:
        print("+", " ".join(args), flush=True)
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode != 0:
            print(result.stdout, file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            raise RuntimeError(f"command failed ({result.returncode}): {' '.join(args)}")
        return result.stdout

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


class Pipeline:
    def __init__(self, env: dict | None = None, runner: Runner | None = None):
        self.env = env or dict(os.environ)
        self.r = runner or Runner()
        self.mac = self.env["MAC_SSH"]                  # e.g. samanyu@macbook.local
        self.repo = self.env.get("REPO_DIR", "~/StarSI")
        self.run_id = self.env.get("RUN_ID") or f"run-{int(time.time())}"
        self.version = self.env.get("VERSION") or self.run_id
        self.model_name = self.env.get("MODEL_NAME", "starsi")

    def ssh_mac(self, cmd: str) -> str:
        return self.r.run(["ssh", "-o", "BatchMode=yes", self.mac, cmd])

    def compose_mac(self, service: str, extra: str = "") -> str:
        return self.ssh_mac(
            f"docker compose -f {self.repo}/deploy/sites/mac/aux-compose.yaml "
            f"run --rm {service} {extra}".strip()
        )

    # ── stages ──────────────────────────────────────────────────────────────

    def fetch(self) -> None:
        repo = self.env["HF_REPO"]
        self.ssh_mac(f"uv --project {self.repo}/train run starsi-train fetch {repo}")

    def dataset(self) -> None:
        self.compose_mac("dataset-prep")

    def train(self) -> None:
        model = self.env.get("BASE_MODEL_PATH") or self.env["HF_REPO"]
        data = self.env.get("DATA_DIR", "~/starsi-train/data")
        self.ssh_mac(
            f"uv --project {self.repo}/train run starsi-train lora "
            f"--run-id {self.run_id} --model {model} --data {data}"
        )
        while True:
            out = self.ssh_mac(
                f"uv --project {self.repo}/train run starsi-train status {self.run_id}"
            )
            status = json.loads(out).get("status")
            print(f"train status: {status}", flush=True)
            if status == "succeeded":
                return
            if status in ("failed", "unknown"):
                raise RuntimeError(f"training {status} (run {self.run_id})")
            self.r.sleep(TRAIN_POLL_S)

    def fuse(self) -> None:
        self.ssh_mac(f"uv --project {self.repo}/train run starsi-train fuse --run-id {self.run_id}")

    def package(self) -> None:
        self.compose_mac(
            "artifact-packager",
            f"--run-id {self.run_id} --name {self.model_name} --version {self.version}",
        )

    def deploy(self) -> None:
        registry = self.env.get("STARSI_REGISTRY_URL", "http://starsi-registry:8080")
        bucket = self.env.get("S3_BUCKET", "starsi-artifacts")
        token = self.env.get("STARSI_AUTH_TOKEN", "")
        for tier, artifact in (
            ("starsi-cpu", "model.gguf"),
            ("starsi-gpu", "model.safetensors.tar"),
        ):
            httpx.put(
                f"{registry}/v1/models/{tier}",
                headers={"Authorization": f"Bearer {token}"},
                json={
                    "version": self.version,
                    "artifact": f"s3://{bucket}/{self.model_name}/{self.version}/{artifact}",
                },
                timeout=10,
            ).raise_for_status()
        # roll the CPU tier now; GPU picks the version up at its next start
        aws = self.env["AWS_SSH"]
        self.r.run([
            "ssh", "-o", "BatchMode=yes", aws,
            "sudo k3s kubectl set env deploy/starsi-inference-cpu "
            f"MODEL_VERSION={self.version} && "
            "sudo k3s kubectl rollout status deploy/starsi-inference-cpu --timeout=15m",
        ])

    def run(self, stages: list[str]) -> None:
        for stage in stages:
            print(f"── stage: {stage} ({self.run_id}) ──", flush=True)
            getattr(self, stage)()


def main() -> None:
    parser = argparse.ArgumentParser(prog="starsi-pipeline")
    parser.add_argument("--stages", default=",".join(ALL_STAGES))
    args = parser.parse_args()
    stages = [s.strip() for s in args.stages.split(",") if s.strip()]
    unknown = set(stages) - set(ALL_STAGES)
    if unknown:
        parser.error(f"unknown stages: {sorted(unknown)}")
    Pipeline().run(stages)


if __name__ == "__main__":
    main()
