#!/usr/bin/env bash
# Step 3/3 (inside the VM): single-node k8s cluster (minikube) + vLLM stack.
# Run this from the Multipass shell: ./inference/03-setup-stack.sh
set -euo pipefail

INFO="[\033[0;34mINFO\033[0m]"
OK="[\033[0;32mOK\033[0m]"
ERR="[\033[0;31mERROR\033[0m]"

ARCH="$(dpkg --print-architecture)"   # arm64 on Apple Silicon, amd64 on Intel
MANIFEST="${MANIFEST:-$HOME/inference/manifests/vllm.yaml}"

if [[ ! -f "$MANIFEST" ]]; then
  echo -e "$ERR Manifest not found at $MANIFEST. Run 02-create-instance.sh from the host first." >&2
  exit 1
fi

# ---------------------------------------------------------------- docker ----
if ! command -v docker >/dev/null 2>&1; then
  echo -e "$INFO Installing docker..."
  sudo apt-get -o DPkg::Lock::Timeout=300 update -q
  sudo apt-get -o DPkg::Lock::Timeout=300 install -y -q docker.io curl jq
fi
sudo usermod -aG docker "$USER"

# --------------------------------------------------------------- kubectl ----
if ! command -v kubectl >/dev/null 2>&1; then
  echo -e "$INFO Installing kubectl..."
  KUBE_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KUBE_VERSION}/bin/linux/${ARCH}/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

# -------------------------------------------------------------- minikube ----
if ! command -v minikube >/dev/null 2>&1; then
  echo -e "$INFO Installing minikube..."
  curl -fsSLo /tmp/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${ARCH}"
  sudo install -m 0755 /tmp/minikube /usr/local/bin/minikube
fi

# Leave ~2G for the OS + vLLM scheduling headroom comes from the k8s limits.
TOTAL_MB="$(free -m | awk '/^Mem:/{print $2}')"
MINIKUBE_MB=$(( TOTAL_MB - 2048 ))

echo -e "$INFO Starting single-node minikube cluster (${MINIKUBE_MB}MB, $(nproc) CPUs)..."
# 'sg docker' because the docker group membership is new in this session.
sg docker -c "minikube start --driver=docker --cpus=$(nproc) --memory=${MINIKUBE_MB}mb --wait=all"

# ------------------------------------------------------------ vLLM stack ----
echo -e "$INFO Deploying vLLM stack..."
sg docker -c "kubectl apply -f '$MANIFEST'"

echo -e "$INFO Waiting for vLLM to come up (first boot pulls the image + ~1GB of model weights; this can take 10-20 min)..."
sg docker -c "kubectl rollout status deployment/vllm -n inference --timeout=30m"

# ----------------------------------------------- expose to the host (Mac) ---
# kubectl port-forward bound to 0.0.0.0 as a systemd unit, so the Mac host
# can reach the API at http://<vm-ip>:8000 and it survives reboots/crashes.
echo -e "$INFO Installing port-forward systemd service (VM:8000 -> svc/vllm:8000)..."
sudo tee /etc/systemd/system/vllm-portforward.service >/dev/null <<EOF
[Unit]
Description=Forward VM port 8000 to the vLLM k8s service
After=network-online.target docker.service
Wants=network-online.target

[Service]
User=$USER
Environment=KUBECONFIG=$HOME/.kube/config
ExecStart=/usr/local/bin/kubectl port-forward --address 0.0.0.0 -n inference svc/vllm 8000:8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now vllm-portforward.service

sleep 3
VM_IP="$(hostname -I | awk '{print $1}')"

echo -e "$INFO Smoke test from inside the VM..."
if curl -fsS "http://localhost:8000/v1/models" | jq -e '.data[0].id' >/dev/null; then
  MODEL_ID="$(curl -fsS http://localhost:8000/v1/models | jq -r '.data[0].id')"
  echo -e "$OK Model '$MODEL_ID' is serving."
else
  echo -e "$ERR vLLM endpoint did not respond; check: kubectl logs -n inference deploy/vllm" >&2
  exit 1
fi

cat <<EOF

=========================================================================
 Flat-rate inference engine is LIVE (zero $ per token).

 OpenAI-compatible API (from your host machine):
     http://${VM_IP}:8000/v1

 Try it from your host:
     curl -s http://${VM_IP}:8000/v1/chat/completions \\
       -H 'Content-Type: application/json' \\
       -d '{"model":"Qwen/Qwen2.5-0.5B-Instruct","messages":[{"role":"user","content":"Say hello"}]}'

 Prometheus metrics:
     curl -s http://${VM_IP}:8000/metrics | grep vllm:
=========================================================================
EOF
