#!/usr/bin/env bash
# One command, full stack: a real 4-node Kubernetes cluster (kubeadm on
# Multipass VMs) + llm-d distributed inference (Envoy gateway, cache-aware
# EPP routing, 3 vLLM replicas) + Prometheus/Grafana monitoring.
#
#   curl -fsSL https://raw.githubusercontent.com/umairkhancis/exp-inference-on-k8s/main/install.sh | bash
#
# (or, from a clone: ./install.sh)
#
# Requirements: Apple Silicon Mac, 24GB RAM, ~40GB disk, Homebrew.
# Everything else (Multipass, jq, kubectl, helm, ...) is installed for you.
# Safe to rerun after any failure — every layer is idempotent.

set -euo pipefail

# Everything lives in main() so that `curl | bash` parses the WHOLE script
# before running any of it — otherwise a child process reading stdin would
# swallow the not-yet-read remainder of the script and bash would stop early.
main() {

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[0;36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; CYAN=""; RESET=""
fi

echo "${CYAN}${BOLD}"
cat <<'EOF'
  ___        __
 |_ _|_ __  / _| ___ _ __ ___ _ __   ___ ___
  | || '_ \| |_ / _ \ '__/ _ \ '_ \ / __/ _ \
  | || | | |  _|  __/ | |  __/ | | | (_|  __/
 |___|_| |_|_|  \___|_|  \___|_| |_|\___\___|
  _   _                        _            _
 | | | |_ __  _ __   __ _  ___| | _____  __| |
 | | | | '_ \| '_ \ / _` |/ __| |/ / _ \/ _` |
 | |_| | | | | |_) | (_| | (__|   <  __/ (_| |
  \___/|_| |_| .__/ \__,_|\___|_|\_\___|\__,_|
             |_|
EOF
echo "${RESET}"
echo "  ${BOLD}Inference Unpacked${RESET} ${DIM}· experiment 04 · distributed inference with cache-aware routing${RESET}"
echo

REPO_URL="https://github.com/umairkhancis/exp-inference-on-k8s.git"
REPO_BRANCH="main"
REPO_DIR="exp-inference-on-k8s"

# Bootstrap: when piped from curl there is no repo around this script — clone it.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/Makefile" ]]; then
  cd "$(dirname "${BASH_SOURCE[0]}")"
else
  [[ -d "${REPO_DIR}" ]] || git clone --branch "${REPO_BRANCH}" "${REPO_URL}" "${REPO_DIR}"
  cd "${REPO_DIR}"
fi

make up               # the Kubernetes cluster
make llmd-up          # llm-d: gateway + EPP + vLLM fleet (verifies routing at the end)
make llmd-monitoring  # Prometheus + Grafana

MASTER_IP="$(multipass info k8s-master --format json | jq -r '.info["k8s-master"].ipv4[0]')"
HOST="${MASTER_IP}"
grep -qE "^${MASTER_IP}[[:space:]]+inference\.local\$" /etc/hosts && HOST="inference.local"
echo
echo "=============================================================="
echo "  Done. Your inference layer is live."
echo
echo "  OpenAI-compatible API:  http://${HOST}:30080/v1"
echo "  Grafana dashboards:     http://${HOST}:30300  (admin/admin)"
echo "  Prometheus:             http://${HOST}:30090"
echo "  kubectl:                export KUBECONFIG=$(pwd)/kubeconfig/config"
echo
echo "  Try it:"
echo "  curl -s http://${HOST}:30080/v1/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\": \"Qwen/Qwen2.5-0.5B-Instruct\", \"prompt\": \"Hello\", \"max_tokens\": 32}' | jq"
echo
echo "  Tear down: make llmd-down && make down"
echo "=============================================================="

}

main "$@"
