#!/usr/bin/env bash
# Shared: resolve the inference endpoint from the Multipass VM.
INSTANCE_NAME="${INSTANCE_NAME:-$(whoami)-inference-engine}"
VM_IP="$(multipass info "$INSTANCE_NAME" --format csv 2>/dev/null | tail -1 | cut -d, -f3)"
if [[ -z "$VM_IP" || "$VM_IP" == "--" ]]; then
  echo "[ERROR] Could not resolve IP of instance '$INSTANCE_NAME'. Is it running?" >&2
  exit 1
fi
BASE_URL="http://${VM_IP}:8000"
MODEL="${MODEL:-Qwen/Qwen2.5-0.5B-Instruct}"
