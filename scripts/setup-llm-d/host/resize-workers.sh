#!/usr/bin/env bash
# Layer 0 — worker memory.
# vLLM CPU's startup profiling spike OOMs inside 4G nodes, so the workers get
# ${LLMD_WORKER_MEM} (default 6G). Rolling: one worker at a time, waiting for
# the node to come back Ready before touching the next.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

target_bytes() { # "6G"/"6GiB" -> bytes
  local n="${1%GiB}"; n="${n%G}"
  echo $(( n * 1024 * 1024 * 1024 ))
}
TARGET_BYTES="$(target_bytes "${LLMD_WORKER_MEM}")"

for w in "${WORKER_NAMES[@]}"; do
  current="$(multipass get "local.${w}.memory" 2>/dev/null || echo unknown)"
  # multipass reports e.g. "4.0GiB" / "6.0GiB"
  current_bytes="$(target_bytes "${current%.0GiB}" 2>/dev/null || echo 0)"
  if [[ "${current_bytes}" -ge "${TARGET_BYTES}" ]]; then
    log "${w} already has ${current} RAM"
    continue
  fi
  log "Resizing ${w}: ${current} -> ${LLMD_WORKER_MEM} (stop, set, start)"
  multipass stop "${w}"
  multipass set "local.${w}.memory=${LLMD_WORKER_MEM}"
  multipass start "${w}"
  log "Waiting for node ${w} to be Ready again"
  k wait --for=condition=Ready "node/${w}" --timeout=300s
done

log "Worker memory:"
k get nodes -o custom-columns='NODE:.metadata.name,MEMORY:.status.capacity.memory'
