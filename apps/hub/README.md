# starsi-hub

The always-on inference hub. Runs on the Mac Studio (M5 Ultra, 256 GB).

Same software as `apps/edge`; the difference is `configs/hub.yaml` and the
fact that this one never sleeps. Until the Studio arrives in January,
nothing here runs — develop against `apps/edge` on the MacBook instead.

```sh
uv sync --extra mlx
uv run starsi-hub --config configs/hub.yaml
```

Install as a LaunchDaemon with `scripts/launchd/install.sh hub`.
