#!/usr/bin/env bash
# One command, full stack: a real 4-node Kubernetes cluster (kubeadm on
# Multipass VMs) + llm-d distributed inference (Envoy gateway, cache-aware
# EPP routing, 3 vLLM replicas) + Prometheus/Grafana monitoring.
#
#   ./install.sh
#
# Requirements: Apple Silicon Mac, 24GB RAM, ~40GB disk,
#   brew install --cask multipass && brew install jq
# Safe to rerun after any failure — every layer is idempotent.

set -euo pipefail
cd "$(dirname "$0")"

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
