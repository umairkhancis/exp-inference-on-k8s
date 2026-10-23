#!/usr/bin/env bash
# Layer 1 — infrastructure.
# Launches the multipass VMs (1 master + N workers) from the locally verified
# cloud image (file://), because multipassd's own downloader truncates images
# on this host. Idempotent: existing instances are started, not recreated.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

image_is_verified || die "verified image missing; run host/prereqs.sh (make host-prereqs) first"

launch_vm() {
  local name="$1" cpus="$2" mem="$3" disk="$4"
  if vm_exists "${name}"; then
    local state; state="$(vm_state "${name}")"
    if [[ "${state}" == "Running" ]]; then
      log "${name} already running"
    else
      log "${name} exists (${state}); starting"
      multipass start "${name}"
    fi
    return 0
  fi
  log "Launching ${name} (${cpus} CPUs, ${mem} RAM, ${disk} disk)"
  multipass launch "file://${IMAGE_PATH}" \
    --name "${name}" --cpus "${cpus}" --memory "${mem}" --disk "${disk}" \
    --timeout 600
}

launch_vm "${MASTER_NAME}" "${MASTER_CPUS}" "${MASTER_MEM}" "${MASTER_DISK}"
for w in "${WORKER_NAMES[@]}"; do
  launch_vm "${w}" "${WORKER_CPUS}" "${WORKER_MEM}" "${WORKER_DISK}"
done

log "All instances up:"
multipass list | grep -E "Name|$(IFS='|'; echo "${ALL_NODES[*]}")"
