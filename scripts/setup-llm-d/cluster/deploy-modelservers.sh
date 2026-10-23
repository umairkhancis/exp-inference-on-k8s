#!/usr/bin/env bash
# Layer 4 — the vLLM CPU model servers (one per worker).
# Copies our overlay beside the quickstart clone so its relative base resolves,
# then applies it and waits for the rollout (first boot downloads the model).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ -d "${LLMD_REPO}/guides" ]] || die "llm-d repo missing; run host/fetch-llm-d-repo.sh first"

log "Staging overlay at ${LLMD_OVERLAY_DIR}"
rm -rf "${LLMD_OVERLAY_DIR}"
cp -R "${SETUP_LLMD_DIR}/manifests/modelserver" "${LLMD_OVERLAY_DIR}"

log "Applying model servers (model: ${LLMD_MODEL})"
kn apply -k "${LLMD_OVERLAY_DIR}"

log "Waiting for the vLLM rollout (image + weights on first boot; up to 30m)"
kn rollout status deployment/optimized-baseline-cpu-vllm-decode --timeout=1800s

log "Model servers up:"
kn get pods -l llm-d.ai/role=decode -o wide
