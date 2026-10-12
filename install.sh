#!/usr/bin/env bash
# One-shot installer (Quickstart / Path B):
#
#     curl -sfL https://raw.githubusercontent.com/umairkhancis/exp-inference-on-k8s/main/install.sh | bash
#
# Installs Multipass on the host (the ONLY host-level change), launches an
# isolated Ubuntu VM, stands up a single-node k8s cluster inside it, and
# deploys a flat-rate vLLM inference engine with an OpenAI-compatible API.
#
# Prefer to see every step before it runs? Use the security-explicit path
# in the README (scripts/01..03) instead.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/umairkhancis/exp-inference-on-k8s.git}"
INSTANCE_NAME="${INSTANCE_NAME:-$(whoami)-inference-engine}"
export INSTANCE_NAME

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[0;36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; CYAN=""; RESET=""
fi

banner() {
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
  echo "  ${BOLD}Inference Unpacked${RESET} ${DIM}· flat-rate vLLM on k8s, one-shot installer${RESET}"
  echo "  ${DIM}instance:${RESET} ${INSTANCE_NAME}"
  echo
}

banner

# When piped via curl there is no local checkout — fetch one.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/scripts/03-setup-stack.sh" ]]; then
  WORK_DIR="$(mktemp -d)"
  echo "[INFO] Fetching stack files into $WORK_DIR..."
  git clone --depth 1 "$REPO_URL" "$WORK_DIR/exp-inference-on-k8s"
  SCRIPT_DIR="$WORK_DIR/exp-inference-on-k8s"
fi

bash "$SCRIPT_DIR/scripts/01-install-multipass.sh"
AUTO_SHELL=0 bash "$SCRIPT_DIR/scripts/02-create-instance.sh"

echo "[INFO] Running k8s + vLLM setup inside '$INSTANCE_NAME' (first run takes 10-20 min)..."
multipass exec "$INSTANCE_NAME" -- /home/ubuntu/inference/03-setup-stack.sh

VM_IP="$(multipass info "$INSTANCE_NAME" --format csv | tail -1 | cut -d, -f3)"
cat <<EOF

[OK] Done. Your flat-rate inference API: http://${VM_IP}:8000/v1
     Verify from this machine:   ./verify/curl-check.sh
     Metrics:                    ./verify/metrics-check.sh
     10-developer load test:     ./verify/load-test.sh
EOF
