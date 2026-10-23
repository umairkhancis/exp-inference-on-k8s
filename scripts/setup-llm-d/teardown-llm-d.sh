#!/usr/bin/env bash
# Removes llm-d from the cluster (router release, model servers, namespace).
# Keeps the GAIE CRDs, the quickstart clone, and the 6G worker sizing.

source "$(dirname "$0")/lib/common.sh"

helm --kubeconfig "${KUBECONFIG_PATH}" uninstall "${LLMD_RELEASE}" -n "${LLMD_NS}" 2>/dev/null \
  && log "helm release ${LLMD_RELEASE} uninstalled" || warn "helm release not found"
k delete namespace "${LLMD_NS}" --ignore-not-found
rm -rf "${LLMD_OVERLAY_DIR}"
log "llm-d teardown complete"
