#!/usr/bin/env bash
# Install the StarSI node as a LaunchDaemon so it survives logout and reboot.
#   scripts/launchd/install.sh edge 32768   # MacBook, 36 GB → ~32 GB wired
#   scripts/launchd/install.sh hub  235000  # Studio, 256 GB
set -euo pipefail
ROLE="${1:?role: hub|edge}"
MB="${2:?wired limit in MB}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

for f in node wiredlimit; do
  sed -e "s|__REPO__|$REPO|g" -e "s|__ROLE__|$ROLE|g" -e "s|__MB__|$MB|g" \
    "$REPO/scripts/launchd/com.starsi.$f.plist" | sudo tee "/Library/LaunchDaemons/com.starsi.$f.plist" >/dev/null
  sudo launchctl bootout system "/Library/LaunchDaemons/com.starsi.$f.plist" 2>/dev/null || true
  sudo launchctl bootstrap system "/Library/LaunchDaemons/com.starsi.$f.plist"
done
sudo pmset -c disablesleep 1
echo "installed: starsi-$ROLE, wired limit ${MB}MB, sleep disabled on AC"
