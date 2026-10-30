#!/usr/bin/env bash
# Provision the Raspberry Pi as StarSI's home site: single-node k3s + tunnel user.
# Run ON the Pi as a sudoer: bash install-k3s.sh
set -euo pipefail

# k3s needs cgroup memory on Raspberry Pi OS; append boot flags once.
CMDLINE=/boot/firmware/cmdline.txt
if [ -f "$CMDLINE" ] && ! grep -q cgroup_memory "$CMDLINE"; then
  sudo sed -i '1 s/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE"
  echo ">> cgroup flags added to $CMDLINE — reboot required before k3s will start"
fi

# Single-node server. Traefik disabled: blocks are exposed as loopback NodePorts
# behind SSH tunnels; there is no ingress/TLS layer by design.
if ! command -v k3s >/dev/null; then
  curl -sfL https://get.k3s.io | sh -s - server \
    --disable traefik \
    --write-kubeconfig-mode 0644
fi

# Unprivileged tunnel user. Keys land in authorized_keys via
# infra/ssh/distribute-authorized-keys.sh — never by hand-editing.
if ! id starsi >/dev/null 2>&1; then
  sudo useradd --create-home --shell /usr/sbin/nologin starsi
  sudo install -d -m 700 -o starsi -g starsi /home/starsi/.ssh
fi

sudo install -D -m 644 "$(dirname "$0")/sshd_starsi.conf" /etc/ssh/sshd_config.d/starsi.conf
sudo systemctl reload ssh || sudo systemctl reload sshd

echo ">> done. kubeconfig: /etc/rancher/k3s/k3s.yaml"
echo ">> deploy blocks:   helmfile -f deploy/sites/pi/helmfile.yaml apply"
