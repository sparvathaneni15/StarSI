"""Bonjour advertisement: _starsi._tcp on the LAN.

macOS: shell out to `dns-sd -R` for now; later register in-process so
the record dies with the server. Away from home the phone falls back to
the Tailscale name, so this is discovery only, not transport.

TODO: implement; include node kind + loaded models as TXT records so the
      client can pick before connecting.
"""

from __future__ import annotations


def advertise(name: str, port: int, txt: dict[str, str]) -> None:
    raise NotImplementedError
