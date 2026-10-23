#!/usr/bin/env bash
# One-command kubeadm cluster on multipass: 1 master + 3 workers.
# Idempotent — safe to rerun after a failure; completed layers are skipped.
# (Or drive the layers individually from the repo root: `make up`, `make verify`, …)
#
# Layers:
#   host/prereqs.sh              — host tools + verified Ubuntu cloud image
#   host/create-instances.sh     — multipass VMs from file:// image
#   node/provision-all.sh        — containerd + kubeadm/kubelet/kubectl on every node
#   cluster/init-control-plane.sh— kubeadm init + flannel + default StorageClass
#   cluster/join-workers.sh
#   access/fetch-kubeconfig.sh   — kubectl access from the Mac
#   access/verify.sh             — nodes Ready, system pods up, scheduling smoke test

set -euo pipefail
cd "$(dirname "$0")"

LAYERS=(
  host/prereqs.sh
  host/create-instances.sh
  node/provision-all.sh
  cluster/init-control-plane.sh
  cluster/join-workers.sh
  access/fetch-kubeconfig.sh
  access/verify.sh
)

for step in "${LAYERS[@]}"; do
  echo
  echo "=============================================================="
  echo "==> ${step}"
  echo "=============================================================="
  "./${step}"
done

REPO_ROOT="$(cd ../.. && pwd)"
echo
echo "Cluster is ready. To use it:"
echo "  export KUBECONFIG=${REPO_ROOT}/kubeconfig/config"
echo "  kubectl get nodes"
