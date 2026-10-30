#!/bin/bash
# StarSI AWS CPU node bootstrap: k3s server + tunnel user. AL2023 arm64.
set -euxo pipefail

# k3s server; agents join over the private VPC (SG `self` rule)
curl -sfL https://get.k3s.io | sh -s - server \
  --disable traefik \
  --write-kubeconfig-mode 0644

# share the join token with the GPU node via SSM
TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter --region ${region} --name /starsi/k3s-token \
  --type SecureString --value "$TOKEN" --overwrite

# unprivileged tunnel user — authorized_keys arrives via
# infra/ssh/distribute-authorized-keys.sh
useradd --create-home --shell /usr/sbin/nologin starsi || true
install -d -m 700 -o starsi -g starsi /home/starsi/.ssh

cat > /etc/ssh/sshd_config.d/starsi.conf <<'EOF'
Match User starsi
    AllowTcpForwarding yes
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
    ForceCommand /usr/sbin/nologin
    # gateway + capacity NodePorts, and the Pi reverse-tunnel listeners
    PermitOpen 127.0.0.1:30086 127.0.0.1:30087 127.0.0.1:18484 127.0.0.1:18485
    PermitListen 127.0.0.1:18484 127.0.0.1:18485
EOF
systemctl reload sshd
