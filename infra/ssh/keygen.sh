#!/usr/bin/env bash
# Generate StarSI device keys (ed25519, one per machine; the iPhone generates
# its own in the Secure-Keychain and is enrolled via the Settings screen).
#   ./keygen.sh pi mac ops
set -euo pipefail
KEYDIR="${STARSI_KEYDIR:-$HOME/.starsi/keys}"
mkdir -p "$KEYDIR"
chmod 700 "$KEYDIR"
for name in "$@"; do
  key="$KEYDIR/starsi_$name"
  [ -f "$key" ] && { echo "exists: $key"; continue; }
  ssh-keygen -t ed25519 -N "" -C "starsi-$name" -f "$key"
  echo "created: $key"
  echo ">> add the .pub line to infra/ssh/authorized_keys.d/<target-host> and run distribute-authorized-keys.sh"
done
