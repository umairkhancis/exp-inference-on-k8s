#!/usr/bin/env bash
# Layer 7 — monitoring, as per the llm-d guide:
#   1. kube-prometheus-stack via the guide's own installer (release "llmd",
#      namespace llm-d-monitoring), right-sized for this cluster afterwards
#   2. router re-installed with guides/recipes/router/features/monitoring.values.yaml
#      (install-router.sh picks it up automatically once the CRDs exist)
#   3. the guide's PodMonitor for the vLLM decode pods
#   4. the guide's Grafana dashboards
#   5. Grafana on NodePort 30300 for the host

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

MON_NS="${MON_NS:-llm-d-monitoring}"
export KUBECONFIG="${KUBECONFIG_PATH}"

[[ -d "${LLMD_REPO}/guides" ]] || die "llm-d repo missing; run host/fetch-llm-d-repo.sh first"

log "Installing kube-prometheus-stack via the llm-d installer (ns ${MON_NS})"
MONITORING_NAMESPACE="${MON_NS}" bash "${LLMD_REPO}/guides/recipes/observability/install-prometheus-grafana.sh"

log "Right-sizing Prometheus for this cluster (the guide's 4Gi request cannot schedule on 6G workers)"
# --force-conflicts: reruns must reclaim Service fields owned by our
# kubectl-patch NodePort steps below (helm 4 applies server-side)
helm upgrade llmd prometheus-community/kube-prometheus-stack -n "${MON_NS}" --reuse-values \
  --force-conflicts \
  --set prometheus.prometheusSpec.resources.requests.cpu=200m \
  --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
  --set prometheus.prometheusSpec.resources.limits.memory=1536Mi
k -n "${MON_NS}" wait --for=condition=Available "prometheus/llmd-kube-prometheus-stack-prometheus" --timeout=300s 2>/dev/null \
  || kn get pods -n "${MON_NS}" || true

log "Re-installing the router with the guide's monitoring values (EPP ServiceMonitor)"
"$(dirname "${BASH_SOURCE[0]}")/install-router.sh"

log "Applying the guide's PodMonitor for the vLLM decode pods"
kn apply -k "${LLMD_REPO}/guides/recipes/modelserver/components/monitoring" 2>/dev/null \
  || kn apply -f "${LLMD_REPO}/guides/recipes/modelserver/components/monitoring/decode-podmonitor.yaml"

log "Loading the llm-d Grafana dashboards"
bash "${LLMD_REPO}/guides/recipes/observability/load-llm-d-dashboards.sh" "${MON_NS}"

log "Exposing Grafana on NodePort 30300 and Prometheus on NodePort 30090"
k -n "${MON_NS}" patch svc llmd-grafana -p \
  '{"spec":{"type":"NodePort","ports":[{"name":"http-web","port":80,"targetPort":3000,"nodePort":30300}]}}'
k -n "${MON_NS}" patch svc llmd-kube-prometheus-stack-prometheus -p \
  '{"spec":{"type":"NodePort","ports":[{"name":"http-web","port":9090,"targetPort":9090,"nodePort":30090}]}}'

log "Waiting for Prometheus to scrape the llm-d targets"
PROM_PROXY="/api/v1/namespaces/${MON_NS}/services/llmd-kube-prometheus-stack-prometheus:9090/proxy"
for attempt in $(seq 1 18); do
  UP="$(k get --raw "${PROM_PROXY}/api/v1/targets" 2>/dev/null \
    | jq -r "[.data.activeTargets[] | select(.labels.namespace==\"${LLMD_NS}\" and .health==\"up\")] | length" || echo 0)"
  [[ "${UP:-0}" -ge 2 ]] && break
  sleep 10
done
k get --raw "${PROM_PROXY}/api/v1/targets" \
  | jq -r ".data.activeTargets[] | select(.labels.namespace==\"${LLMD_NS}\") | \"\(.labels.job // .scrapePool): \(.health)\"" | sort -u
[[ "${UP:-0}" -ge 2 ]] || die "expected >=2 healthy llm-d scrape targets (EPP + decode pods), got ${UP:-0}"

MASTER_IP="$(vm_ip "${MASTER_NAME}")"
log "Monitoring ready: Grafana http://${MASTER_IP}:30300 (admin/admin), Prometheus http://${MASTER_IP}:30090"
