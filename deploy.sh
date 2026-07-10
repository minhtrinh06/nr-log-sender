#!/usr/bin/env bash
# Apply everything: namespace/deployment/script configmap via kustomize, plus
# the payloads configmap built from payloads/ (kustomize can't glob a dir).
set -eu
cd "$(dirname "$0")"

sudo k3s kubectl apply -k .
sudo k3s kubectl -n nr-log-sender create configmap nr-log-sender-payloads --from-file=payloads/ --dry-run=client -o yaml \
  | sudo k3s kubectl apply -f -
sudo k3s kubectl -n nr-log-sender rollout status deploy/nr-log-sender
