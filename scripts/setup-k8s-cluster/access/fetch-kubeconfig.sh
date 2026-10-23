#!/usr/bin/env bash
# Layer 5 — host access.
# Copies the cluster's admin kubeconfig to kubeconfig/config in the repo so
# kubectl on the Mac talks to the cluster directly (the API server is
# advertised on the master VM's IP, which the host can reach).

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
multipass exec "${MASTER_NAME}" -- sudo cat /etc/kubernetes/admin.conf >"${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"
log "Kubeconfig written to ${KUBECONFIG_PATH}"

log "Testing API server access from the host"
kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes
