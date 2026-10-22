"""starsi-inference: everything a serving node needs.

hub and edge are the same software with different configs. This package
holds the parts they share; the apps are thin entry points.

Modules
- backends/   engine adapters (MLX now; vLLM later for beast-pc specialists)
- router      picks node + model per request, runs the ideation loop
- server      FastAPI app exposing the StarSI stream protocol
- discovery   Bonjour (_starsi._tcp) advertisement on macOS
"""
