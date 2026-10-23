#!/usr/bin/env bash
# One command, full stack: a real 4-node Kubernetes cluster (kubeadm on
# Multipass VMs) + llm-d distributed inference (Envoy gateway, cache-aware
# EPP routing, 3 vLLM replicas) + Prometheus/Grafana monitoring.
#
#   curl -fsSL https://raw.githubusercontent.com/umairkhancis/exp-inference-on-k8s/experiment/04/install.sh | bash
#
# (or, from a clone: ./install.sh)
#
# Requirements: Apple Silicon Mac, 24GB RAM, ~40GB disk,
#   brew install --cask multipass && brew install jq
# Safe to rerun after any failure — every layer is idempotent.

set -euo pipefail

REPO_URL="https://github.com/umairkhancis/exp-inference-on-k8s.git"
REPO_BRANCH="experiment/04"
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
echo
echo "=============================================================="
echo "  Done. Your inference layer is live."
echo
echo "  OpenAI-compatible API:  http://${MASTER_IP}:30080/v1"
echo "  Grafana dashboards:     http://${MASTER_IP}:30300  (admin/admin)"
echo "  Prometheus:             http://${MASTER_IP}:30090"
echo "  kubectl:                export KUBECONFIG=$(pwd)/kubeconfig/config"
echo
echo "  Try it:"
echo "  curl -s http://${MASTER_IP}:30080/v1/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\": \"Qwen/Qwen2.5-0.5B-Instruct\", \"prompt\": \"Hello\", \"max_tokens\": 32}' | jq"
echo
echo "  Tear down: make llmd-down && make down"
echo "=============================================================="
