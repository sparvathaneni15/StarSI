#!/bin/bash
# StarSI GPU node bootstrap: k3s agent joining the CPU node over the private
# VPC, with the NVIDIA container runtime k3s auto-detects. Runs once at launch;
# subsequent start/stop cycles just restart the k3s-agent service.
set -euxo pipefail

TOKEN=$(aws ssm get-parameter --region ${region} --name /starsi/k3s-token \
  --with-decryption --query Parameter.Value --output text)

curl -sfL https://get.k3s.io | K3S_URL=https://${server_ip}:6443 K3S_TOKEN="$TOKEN" \
  sh -s - agent --node-label starsi/gpu=true

# k3s auto-detects the NVIDIA container runtime from the ECS GPU AMI's drivers.
# The nvidia-device-plugin DaemonSet (deploy/sites/aws/helmfile.yaml) makes
# nvidia.com/gpu schedulable once this node joins.
