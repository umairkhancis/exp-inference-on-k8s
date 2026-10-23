#!/usr/bin/env bash
# Layer 6 — verification (all from the host).
# Waits for every node to be Ready and kube-system to settle, then runs a
# tiny scheduling smoke test on the workers.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

k() { kubectl --kubeconfig "${KUBECONFIG_PATH}" "$@"; }

log "Waiting for ${#ALL_NODES[@]} nodes to be Ready (up to 5m)"
for node in "${ALL_NODES[@]}"; do
  k wait --for=condition=Ready "node/${node}" --timeout=300s
done

log "Waiting for kube-system pods"
k -n kube-system wait --for=condition=Ready pods --all --timeout=300s
k -n kube-flannel wait --for=condition=Ready pods --all --timeout=300s
k -n local-path-storage wait --for=condition=Ready pods --all --timeout=300s

log "Scheduling smoke test (nginx pod on a worker)"
k delete pod smoke-test --ignore-not-found >/dev/null
k run smoke-test --image=nginx --restart=Never
k wait --for=condition=Ready pod/smoke-test --timeout=180s
k delete pod smoke-test --wait=false >/dev/null

log "Cluster state:"
k get nodes -o wide
k get storageclass

log "Verification passed — cluster is ready for llm-d (phase 2)"
