"""Request routing and the ideation loop.

Routing signals, in order:
  1. reachability  — which nodes answered a recent heartbeat
  2. loaded models — what each reachable node currently has in memory
  3. request type  — ideation (fan-out) vs. ordinary turn vs. specialist

Ideation loop (README.md → Request path, step 3):
  fan out N candidates at the request's sampling config
  → score novelty and plausibility separately
  → stream the top `survivors` as "candidate" events, then continue
    the thread with the best one.

TODO: implement; novelty scorer lives in starsi_trainer.judges so the
      same function is used at train time and serve time.
"""

from __future__ import annotations

from starsi_core import ChatRequest, Registry


class Router:
    def __init__(self, registry: Registry, self_node: str) -> None:
        self.registry = registry
        self.self_node = self_node

    def choose(self, request: ChatRequest):
        """Return (node, model) to serve this request."""
        if request.model:
            found = self.registry.find_model(request.model)
            if found:
                return found
        primary = self.registry.with_tag("primary")
        if not primary:
            raise RuntimeError("no primary model registered")
        return primary[0]
