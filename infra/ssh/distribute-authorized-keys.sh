#!/usr/bin/env bash
# Push the committed authorized_keys.d/<host> files to each machine's
# `starsi` tunnel user (uses your admin SSH access, not the tunnel user).
#   ./distribute-authorized-keys.sh pi=pi.local aws=ec2-user@<aws-ip> mac=localhost
set -euo pipefail
cd "$(dirname "$0")"

for pair in "$@"; do
  host_file="${pair%%=*}"
  target="${pair#*=}"
  src="authorized_keys.d/$host_file"
  [ -f "$src" ] || { echo "no such file: $src" >&2; exit 1; }
  # strip comments/blank lines; what ships is exactly the active grants
  grep -vE '^(#|$)' "$src" > /tmp/starsi-ak || true
  echo ">> $src -> $target (:starsi)"
  if [ "$target" = "localhost" ]; then
    sudo install -D -m 600 -o starsi -g staff /tmp/starsi-ak /Users/starsi/.ssh/authorized_keys
  else
    scp -q /tmp/starsi-ak "$target:/tmp/starsi-ak"
    ssh "$target" 'sudo install -D -m 600 -o starsi -g starsi /tmp/starsi-ak /home/starsi/.ssh/authorized_keys && rm /tmp/starsi-ak'
  fi
  [ -f known_hosts ] && scp -q known_hosts "$target:/tmp/starsi-kh" 2>/dev/null \
    && ssh "$target" 'sudo install -D -m 644 /tmp/starsi-kh /home/starsi/.ssh/known_hosts && rm /tmp/starsi-kh' || true
done
rm -f /tmp/starsi-ak
