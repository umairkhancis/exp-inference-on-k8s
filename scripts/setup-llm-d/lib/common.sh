# Shared configuration for the llm-d (phase 2) layers.
# Builds on the phase-1 cluster lib for logging, VM helpers and cluster names.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../setup-k8s-cluster/lib/common.sh"

# --- llm-d quickstart pins (mirrors guides/env.sh in the llm-d repo) ---
LLMD_BRANCH="${LLMD_BRANCH:-release-1.0}"
LLMD_REPO_URL="https://github.com/llm-d/llm-d.git"
LLMD_REPO="${IMAGE_CACHE_DIR}/llm-d"                 # quickstart clone, pinned
LLMD_OVERLAY_DIR="${IMAGE_CACHE_DIR}/llmd-overlay"   # our kustomize overlay, copied beside the clone
GAIE_VERSION="${GAIE_VERSION:-v1.6.2}"
GAIE_MANIFESTS="https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${GAIE_VERSION}/v1-manifests.yaml"
ROUTER_CHART="oci://ghcr.io/llm-d/charts/llm-d-router-standalone"
ROUTER_CHART_VERSION="${ROUTER_CHART_VERSION:-v1.0.0}"

# --- Our deployment choices ---
LLMD_NS="${LLMD_NS:-llm-d}"
LLMD_RELEASE="${LLMD_RELEASE:-llm-d}"
LLMD_MODEL="${LLMD_MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"  # small, ungated, fits CPU workers
LLMD_NODEPORT="${LLMD_NODEPORT:-30080}"
LLMD_WORKER_MEM="${LLMD_WORKER_MEM:-6G}"             # vLLM CPU startup spike needs >4G nodes

SETUP_LLMD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

k() { kubectl --kubeconfig "${KUBECONFIG_PATH}" "$@"; }
kn() { k -n "${LLMD_NS}" "$@"; }

gateway_url() { echo "http://$(vm_ip "${MASTER_NAME}"):${LLMD_NODEPORT}"; }

decode_pods() { kn get pods -l llm-d.ai/role=decode -o jsonpath='{.items[*].metadata.name}'; }

pod_node() { kn get pod "$1" -o jsonpath='{.spec.nodeName}'; }

# pod_metric <pod> <metric-name> — summed value of a vLLM counter, read through
# the API-server proxy (no port-forward needed)
pod_metric() {
  k get --raw "/api/v1/namespaces/${LLMD_NS}/pods/${1}:8000/proxy/metrics" 2>/dev/null \
    | awk -v m="$2" '$0 ~ "^"m"{" || $1 == m {s+=$NF} END {printf "%.0f", s}'
}

# gateway_completion <prompt> [max_tokens] — one completion via the gateway,
# prints the HTTP status code
gateway_completion() {
  curl -sS -m 120 -o /dev/null -w '%{http_code}' -X POST "$(gateway_url)/v1/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${LLMD_MODEL}\", \"prompt\": $(jq -Rn --arg p "$1" '$p'), \"max_tokens\": ${2:-8}}"
}
