#!/usr/bin/env bash
# Layer 2 — cluster prerequisites for llm-d.
# Gateway API Inference Extension CRDs, the namespace, and the HF token secret
# the model-server manifests reference (empty token is fine for public models).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log "Applying Gateway API Inference Extension CRDs (${GAIE_VERSION})"
k apply -f "${GAIE_MANIFESTS}"

log "Ensuring namespace ${LLMD_NS}"
k create namespace "${LLMD_NS}" --dry-run=client -o yaml | k apply -f -

log "Ensuring llm-d-hf-token secret (HF_TOKEN=${HF_TOKEN:+<set>}${HF_TOKEN:-<empty, public models only>})"
kn create secret generic llm-d-hf-token \
  --from-literal="HF_TOKEN=${HF_TOKEN:-}" \
  --dry-run=client -o yaml | kn apply -f -

log "Cluster prerequisites ready"
