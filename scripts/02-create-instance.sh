#!/usr/bin/env bash
# Step 2/3 (host): create the isolated VM and copy the stack files into it.
# Nothing from this project touches your host beyond this sandbox.
set -euo pipefail

INSTANCE_NAME="${INSTANCE_NAME:-$(whoami)-inference-engine}"
# 6 CPUs / 12G: vLLM (CPU inference) + Prometheus + Grafana + Open WebUI.
# 4/8G ran out of headroom once Open WebUI joined the stack (Phase 3).
VM_CPUS="${VM_CPUS:-6}"
VM_MEMORY="${VM_MEMORY:-12G}"
VM_DISK="${VM_DISK:-40G}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# multipassd's own image downloader sometimes truncates the download and
# then fails hash verification ("Hash of ... does not match"). Fallback:
# download the official cloud image ourselves (resumable), verify its
# SHA256 against Canonical's published sums, and launch from the file.
launch_from_verified_image() {
  local cache_dir="$HOME/.cache/exp-inference-on-k8s"
  local base_url="https://cloud-images.ubuntu.com/releases/noble/release"
  local arch; arch="$( [[ "$(uname -m)" == "x86_64" ]] && echo amd64 || echo arm64 )"
  local img="ubuntu-24.04-server-cloudimg-${arch}.img"

  mkdir -p "$cache_dir"
  echo "[INFO] Downloading $img (resumable, SHA256-verified)..."
  curl -fL -C - --retry 5 -o "$cache_dir/$img" "$base_url/$img"
  curl -fsSL -o "$cache_dir/SHA256SUMS" "$base_url/SHA256SUMS"

  local want have
  want="$(grep " \*${img}\$" "$cache_dir/SHA256SUMS" | cut -d' ' -f1)"
  have="$(shasum -a 256 "$cache_dir/$img" 2>/dev/null || sha256sum "$cache_dir/$img")"
  have="${have%% *}"
  if [[ -z "$want" || "$want" != "$have" ]]; then
    echo "[ERROR] SHA256 mismatch for $img (want=$want have=$have). Delete $cache_dir and retry." >&2
    exit 1
  fi
  echo "[OK] Image verified: $have"

  multipass launch "file://$cache_dir/$img" \
    --name "$INSTANCE_NAME" \
    --cpus "$VM_CPUS" \
    --memory "$VM_MEMORY" \
    --disk "$VM_DISK" \
    --timeout 600
}

if multipass info "$INSTANCE_NAME" >/dev/null 2>&1; then
  echo "[OK] Instance '$INSTANCE_NAME' already exists."
  multipass start "$INSTANCE_NAME" 2>/dev/null || true
else
  echo "[INFO] Launching instance '$INSTANCE_NAME' (${VM_CPUS} CPUs, ${VM_MEMORY} RAM, ${VM_DISK} disk)..."
  if ! multipass launch 24.04 \
      --name "$INSTANCE_NAME" \
      --cpus "$VM_CPUS" \
      --memory "$VM_MEMORY" \
      --disk "$VM_DISK" \
      --timeout 600; then
    echo "[WARN] Standard launch failed (often a corrupt multipass image cache)."
    echo "[INFO] Falling back to a locally verified image download..."
    multipass delete --purge "$INSTANCE_NAME" 2>/dev/null || true
    launch_from_verified_image
  fi
fi

echo "[INFO] Copying stack files into the instance..."
multipass exec "$INSTANCE_NAME" -- mkdir -p /home/ubuntu/inference/manifests/dashboards
for f in "$REPO_DIR"/manifests/*.yaml; do
  multipass transfer "$f" "$INSTANCE_NAME":/home/ubuntu/inference/manifests/"$(basename "$f")"
done
for f in "$REPO_DIR"/manifests/dashboards/*.json; do
  multipass transfer "$f" "$INSTANCE_NAME":/home/ubuntu/inference/manifests/dashboards/"$(basename "$f")"
done
multipass transfer "$SCRIPT_DIR/03-setup-stack.sh" "$INSTANCE_NAME":/home/ubuntu/inference/03-setup-stack.sh
multipass exec "$INSTANCE_NAME" -- chmod +x /home/ubuntu/inference/03-setup-stack.sh

cat <<EOF

[OK] Instance ready: $INSTANCE_NAME ($(multipass info "$INSTANCE_NAME" --format csv | tail -1 | cut -d, -f3))

Next (step 3/3) — enter the sandbox and start the k8s stack:

    multipass shell $INSTANCE_NAME
    ./inference/03-setup-stack.sh

EOF

if [[ "${AUTO_SHELL:-1}" == "1" && -t 0 ]]; then
  exec multipass shell "$INSTANCE_NAME"
fi
