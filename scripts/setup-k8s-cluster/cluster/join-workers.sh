#!/usr/bin/env bash
# Layer 4 — workers.
# Generates a fresh join token on the master and joins every worker that is
# not already part of the cluster.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

JOIN_CMD="$(multipass exec "${MASTER_NAME}" -- sudo kubeadm token create --print-join-command)"
[[ "${JOIN_CMD}" == kubeadm\ join* ]] || die "unexpected join command: ${JOIN_CMD}"

for w in "${WORKER_NAMES[@]}"; do
  if multipass exec "${w}" -- sudo test -f /etc/kubernetes/kubelet.conf; then
    log "${w} already joined"
  else
    log "Joining ${w}"
    multipass exec "${w}" -- sudo bash -c "${JOIN_CMD}"
  fi
done

log "All workers joined"
