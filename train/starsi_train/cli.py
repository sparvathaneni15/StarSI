"""starsi-train — the Mac side of the model lifecycle.

Invoked over SSH by the Pi's model-pipeline Jobs. Long stages (lora) detach
with nohup semantics: the Job starts them, then polls `status` instead of
holding an SSH session open for hours.

    starsi-train fetch <hf-repo>               download base weights
    starsi-train lora --run-id X [...]         start a LoRA run, detached
    starsi-train status <run-id>               running | succeeded | failed
    starsi-train fuse --run-id X               fuse adapter into safetensors
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

HOME = Path(os.environ.get("STARSI_TRAIN_HOME", Path.home() / "starsi-train"))
MODELS = HOME / "models"
RUNS = HOME / "runs"


def run_dir(run_id: str) -> Path:
    d = RUNS / run_id
    d.mkdir(parents=True, exist_ok=True)
    return d


def write_state(run_id: str, **fields) -> None:
    state_file = run_dir(run_id) / "state.json"
    state = {}
    if state_file.exists():
        state = json.loads(state_file.read_text())
    state.update(fields)
    state_file.write_text(json.dumps(state, indent=2))


def read_state(run_id: str) -> dict:
    state_file = RUNS / run_id / "state.json"
    if not state_file.exists():
        return {"status": "unknown"}
    return json.loads(state_file.read_text())


def cmd_fetch(args: argparse.Namespace) -> int:
    from huggingface_hub import snapshot_download

    dest = MODELS / "base" / args.repo.replace("/", "--")
    path = snapshot_download(args.repo, local_dir=dest)
    print(json.dumps({"repo": args.repo, "path": str(path)}))
    return 0


def cmd_lora(args: argparse.Namespace) -> int:
    d = run_dir(args.run_id)
    log = d / "train.log"
    adapter_dir = d / "adapters"
    cmd = [
        sys.executable, "-m", "mlx_lm", "lora",
        "--model", args.model,
        "--train",
        "--data", args.data,
        "--adapter-path", str(adapter_dir),
        "--iters", str(args.iters),
        "--batch-size", str(args.batch_size),
    ]
    with log.open("a") as logf:
        proc = subprocess.Popen(
            cmd, stdout=logf, stderr=subprocess.STDOUT,
            start_new_session=True,  # survives the SSH session ending
        )
    write_state(
        args.run_id,
        status="running", stage="lora", pid=proc.pid,
        model=args.model, adapter_path=str(adapter_dir), started=time.time(),
    )
    print(json.dumps({"run_id": args.run_id, "pid": proc.pid, "log": str(log)}))
    return 0


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def cmd_status(args: argparse.Namespace) -> int:
    state = read_state(args.run_id)
    if state.get("status") == "running" and not _pid_alive(state.get("pid", -1)):
        # mlx_lm lora writes the adapter files on success
        adapters = Path(state.get("adapter_path", "/nonexistent"))
        state["status"] = "succeeded" if any(adapters.glob("*.safetensors")) else "failed"
        write_state(args.run_id, status=state["status"])
    print(json.dumps(state))
    return 0 if state.get("status") != "failed" else 1


def cmd_fuse(args: argparse.Namespace) -> int:
    state = read_state(args.run_id)
    fused = run_dir(args.run_id) / "fused"
    cmd = [
        sys.executable, "-m", "mlx_lm", "fuse",
        "--model", state["model"],
        "--adapter-path", state["adapter_path"],
        "--save-path", str(fused),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
        return result.returncode
    write_state(args.run_id, stage="fused", fused_path=str(fused))
    print(json.dumps({"run_id": args.run_id, "fused_path": str(fused)}))
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(prog="starsi-train")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("fetch", help="download base weights from HuggingFace")
    p.add_argument("repo")
    p.set_defaults(fn=cmd_fetch)

    p = sub.add_parser("lora", help="start a detached LoRA run")
    p.add_argument("--run-id", required=True)
    p.add_argument("--model", required=True, help="path or HF repo of base weights")
    p.add_argument("--data", required=True, help="directory containing train.jsonl")
    p.add_argument("--iters", type=int, default=600)
    p.add_argument("--batch-size", type=int, default=4)
    p.set_defaults(fn=cmd_lora)

    p = sub.add_parser("status", help="report run state as JSON")
    p.add_argument("run_id")
    p.set_defaults(fn=cmd_status)

    p = sub.add_parser("fuse", help="fuse adapter into full safetensors")
    p.add_argument("--run-id", required=True)
    p.set_defaults(fn=cmd_fuse)

    args = parser.parse_args()
    sys.exit(args.fn(args))


if __name__ == "__main__":
    main()
