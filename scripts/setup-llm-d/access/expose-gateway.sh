#!/usr/bin/env bash
# Layer 5 — host access.
# Exposes the router's Envoy listener on a stable NodePort (default 30080) so
# the Mac can curl the gateway directly; port-forwards go stale, NodePorts don't.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

# The chart publishes the Envoy listener (8081) through a ClusterIP service;
# the name differs between chart versions, so take whichever exists.
SRC_SVC=""
for cand in "${LLMD_RELEASE}-epp" "${LLMD_RELEASE}-proxy" "${LLMD_RELEASE}"; do
  if kn get svc "${cand}" >/dev/null 2>&1; then SRC_SVC="${cand}"; break; fi
done
[[ -n "${SRC_SVC}" ]] || die "no router service found (tried ${LLMD_RELEASE}-epp/-proxy)"

log "Creating NodePort service llm-d-gateway (:${LLMD_NODEPORT}) with ${SRC_SVC}'s selector"
SELECTOR_YAML="$(kn get svc "${SRC_SVC}" -o json \
  | jq -r '.spec.selector | to_entries[] | "    \(.key): \"\(.value)\""')"
[[ -n "${SELECTOR_YAML}" ]] || die "service ${SRC_SVC} has no selector"

kn apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: llm-d-gateway
  labels:
    app.kubernetes.io/managed-by: exp-inference-on-k8s
spec:
  type: NodePort
  selector:
${SELECTOR_YAML}
  ports:
    - name: http
      port: 80
      targetPort: 8081
      nodePort: ${LLMD_NODEPORT}
EOF

MASTER_IP="$(vm_ip "${MASTER_NAME}")"
log "Gateway reachable from the host at http://${MASTER_IP}:${LLMD_NODEPORT}"
