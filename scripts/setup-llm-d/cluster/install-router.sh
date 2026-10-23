#!/usr/bin/env bash
# Layer 3 — the llm-d router in standalone mode (Envoy proxy + EPP in one pod),
# installed from the official OCI chart with the quickstart's values files plus
# our CPU/ARM64 downsizing overrides.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ -d "${LLMD_REPO}/guides" ]] || die "llm-d repo missing; run host/fetch-llm-d-repo.sh first"

log "Installing router chart ${ROUTER_CHART} ${ROUTER_CHART_VERSION} as release ${LLMD_RELEASE}"
helm --kubeconfig "${KUBECONFIG_PATH}" upgrade --install "${LLMD_RELEASE}" \
  "${ROUTER_CHART}" \
  -f "${LLMD_REPO}/guides/recipes/router/base.values.yaml" \
  -f "${LLMD_REPO}/guides/optimized-baseline/router/optimized-baseline.values.yaml" \
  -f "${SETUP_LLMD_DIR}/values/cpu-arm64.values.yaml" \
  -n "${LLMD_NS}" --version "${ROUTER_CHART_VERSION}"

log "Waiting for router rollout"
kn rollout status "deployment/${LLMD_RELEASE}-epp" --timeout=600s \
  || { warn "router not Ready:"; kn get pods -o wide; exit 1; }

log "Router installed:"
kn get pods,svc,inferencepool -o wide 2>/dev/null || kn get pods,svc -o wide
