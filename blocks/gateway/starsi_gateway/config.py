"""12-factor configuration. Every knob is an environment variable so the same
image runs on any site; Helm values / compose env pick the assembly."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path


def _env_bool(name: str, default: bool = False) -> bool:
    val = os.environ.get(name)
    if val is None:
        return default
    return val.strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Tier:
    name: str            # public model id the client sends, e.g. "starsi-cpu"
    base_url: str        # OpenAI-compatible upstream, e.g. http://inference-cpu:8080/v1
    upstream_model: str  # value to put in the upstream request's "model" field


@dataclass(frozen=True)
class Settings:
    site: str
    auth_token: str
    tiers: dict[str, Tier] = field(default_factory=dict)
    default_tier: str = "starsi-cpu"
    memory_url: str | None = None          # http://memory:8080 (Pi) or tunnel localhost
    sync_spool_dir: Path = Path("/var/lib/starsi/spool")
    agent_enabled: bool = False
    hermes_dir: str | None = None          # mounted hermes-agent source, if any
    stt_url: str | None = None             # OpenAI-compatible /v1/audio/transcriptions base
    tts_url: str | None = None             # /v1/audio/speech base
    capacity_url: str | None = None        # capacity-controller; GPU-tier requests touch it

    @classmethod
    def from_env(cls) -> Settings:
        tiers: dict[str, Tier] = {}
        # STARSI_TIER_<NAME>=<base_url>[|<upstream_model>] → tier "starsi-<name>"
        for key, raw in sorted(os.environ.items()):
            if not key.startswith("STARSI_TIER_") or not raw.strip():
                continue
            name = "starsi-" + key.removeprefix("STARSI_TIER_").lower()
            base_url, _, upstream_model = raw.partition("|")
            tiers[name] = Tier(name, base_url.rstrip("/"), upstream_model or name)
        return cls(
            site=os.environ.get("STARSI_SITE", "dev"),
            auth_token=os.environ.get("STARSI_AUTH_TOKEN", ""),
            tiers=tiers,
            default_tier=os.environ.get("STARSI_DEFAULT_TIER", "starsi-cpu"),
            memory_url=os.environ.get("STARSI_MEMORY_URL") or None,
            sync_spool_dir=Path(os.environ.get("STARSI_SYNC_SPOOL", "/var/lib/starsi/spool")),
            agent_enabled=_env_bool("STARSI_AGENT_ENABLED"),
            hermes_dir=os.environ.get("STARSI_HERMES_DIR") or None,
            stt_url=os.environ.get("STARSI_STT_URL") or None,
            tts_url=os.environ.get("STARSI_TTS_URL") or None,
            capacity_url=os.environ.get("STARSI_CAPACITY_URL") or None,
        )
