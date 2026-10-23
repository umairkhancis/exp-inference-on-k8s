#!/usr/bin/env bash
# Deletes the cluster VMs and the local kubeconfig. The cached cloud image in
# ~/.cache/exp-inference-on-k8s is kept for fast recreation.

source "$(dirname "$0")/lib/common.sh"

for vm in "${ALL_NODES[@]}"; do
  if vm_exists "${vm}"; then
    log "Deleting ${vm}"
    multipass delete --purge "${vm}"
  fi
done

rm -rf "${REPO_ROOT}/kubeconfig" "${LOG_DIR}"
log "Teardown complete"
