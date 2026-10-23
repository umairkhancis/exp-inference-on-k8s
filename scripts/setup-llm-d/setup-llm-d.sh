#!/usr/bin/env bash
# One-command llm-d (phase 2) on the phase-1 cluster:
# Envoy gateway + EPP (standalone router) + 3 vLLM CPU pods, one per worker,
# with cache-aware routing. Idempotent — rerun after a failure.
#
# Layers:
#   host/resize-workers.sh       — workers to 6G RAM (vLLM CPU startup spike)
#   host/fetch-llm-d-repo.sh     — pinned quickstart clone (release-1.0)
#   cluster/prereqs.sh           — GAIE CRDs, namespace, HF token secret
#   cluster/install-router.sh    — llm-d-router-standalone chart (Envoy + EPP)
#   cluster/deploy-modelservers.sh — vLLM CPU x3 via kustomize overlay
#   access/expose-gateway.sh     — NodePort 30080 for the host
#   access/verify.sh             — completion via Envoy + cache-aware routing proof

set -euo pipefail
cd "$(dirname "$0")"

LAYERS=(
  host/resize-workers.sh
  host/fetch-llm-d-repo.sh
  cluster/prereqs.sh
  cluster/install-router.sh
  cluster/deploy-modelservers.sh
  access/expose-gateway.sh
  access/verify.sh
)

for step in "${LAYERS[@]}"; do
  echo
  echo "=============================================================="
  echo "==> ${step}"
  echo "=============================================================="
  "./${step}"
done
