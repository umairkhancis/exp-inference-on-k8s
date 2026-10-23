#!/usr/bin/env bash
# Layer 2 — node runtime.
# Provisions every VM (containerd + kubeadm/kubelet/kubectl) in parallel.
# Per-node output lands in .logs/<node>-prereqs.log.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
mkdir -p "${LOG_DIR}"

provision_node() {
  local vm="$1"
  multipass transfer "$(dirname "${BASH_SOURCE[0]}")/k8s-node-setup.sh" "${vm}:/tmp/k8s-node-setup.sh"
  multipass exec "${vm}" -- sudo bash /tmp/k8s-node-setup.sh "${K8S_VERSION}"
}

pids=()
for vm in "${ALL_NODES[@]}"; do
  log "Provisioning ${vm} (log: .logs/${vm}-prereqs.log)"
  provision_node "${vm}" >"${LOG_DIR}/${vm}-prereqs.log" 2>&1 &
  pids+=("$!:${vm}")
done

failed=0
for entry in "${pids[@]}"; do
  pid="${entry%%:*}"; vm="${entry#*:}"
  if wait "${pid}"; then
    log "${vm} provisioned"
  else
    warn "${vm} provisioning FAILED — see .logs/${vm}-prereqs.log"
    failed=1
  fi
done
[[ "${failed}" -eq 0 ]] || die "one or more nodes failed provisioning"

log "All nodes provisioned"
