# StarSI iOS

The interface, and the host for MCP servers the model can call.

- `Sources/StarSIClient` — discovery (Bonjour / Multipeer / static Tailscale), transport, protocol types, `ChatSession`.
- `Sources/StarSIMCP` — `MCPHost` and the on-device tools it exposes (`Tools/`).
- `Sources/StarSIApp` — SwiftUI shell.

```sh
brew install xcodegen
xcodegen generate        # → StarSI.xcodeproj (git-ignored)
open StarSI.xcodeproj
```

Library targets build and test without Xcode: `swift test` from this directory.

Protocol types mirror `packages/starsi-core/starsi_core/protocol.py`; the
JSON schema in `protocol/` is the contract both sides are checked against.
