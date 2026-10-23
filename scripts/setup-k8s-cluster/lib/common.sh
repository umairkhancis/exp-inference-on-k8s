# Shared configuration and helpers for the kubeadm-on-multipass cluster.
# Sourced by every script; override any of these via environment variables.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOG_DIR="${REPO_ROOT}/.logs"
KUBECONFIG_PATH="${REPO_ROOT}/kubeconfig/config"

# --- Cluster topology ---
MASTER_NAME="${MASTER_NAME:-k8s-master}"
WORKER_COUNT="${WORKER_COUNT:-3}"
WORKER_NAMES=()
for i in $(seq 1 "${WORKER_COUNT}"); do WORKER_NAMES+=("k8s-worker-${i}"); done
ALL_NODES=("${MASTER_NAME}" "${WORKER_NAMES[@]}")

# --- VM sizing (host: 15 CPUs / 24GB RAM) ---
MASTER_CPUS="${MASTER_CPUS:-2}"
MASTER_MEM="${MASTER_MEM:-3G}"
MASTER_DISK="${MASTER_DISK:-20G}"
WORKER_CPUS="${WORKER_CPUS:-3}"
WORKER_MEM="${WORKER_MEM:-4G}"
WORKER_DISK="${WORKER_DISK:-30G}"

# --- Kubernetes ---
K8S_VERSION="${K8S_VERSION:-v1.34}"           # pkgs.k8s.io minor-version channel
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"         # flannel default
FLANNEL_MANIFEST="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
LOCAL_PATH_MANIFEST="https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml"

# --- Ubuntu cloud image (multipassd's own downloader truncates on this host,
# so we fetch + verify ourselves and launch from file://) ---
IMAGE_CACHE_DIR="${IMAGE_CACHE_DIR:-${HOME}/.cache/exp-inference-on-k8s}"
IMAGE_NAME="ubuntu-24.04-server-cloudimg-arm64.img"
IMAGE_PATH="${IMAGE_CACHE_DIR}/${IMAGE_NAME}"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/24.04/release/${IMAGE_NAME}"
SHA256SUMS_URL="https://cloud-images.ubuntu.com/releases/24.04/release/SHA256SUMS"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[%s] WARN:\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
die()  { printf '\033[1;31m[%s] ERROR:\033[0m %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }

vm_exists() { multipass info "$1" >/dev/null 2>&1; }

vm_state() { multipass info "$1" --format json 2>/dev/null | jq -r ".info[\"$1\"].state"; }

vm_ip() {
  local ip
  ip="$(multipass info "$1" --format json | jq -r ".info[\"$1\"].ipv4[0]")"
  [[ -n "${ip}" && "${ip}" != "null" ]] || die "could not determine IPv4 of ${1}"
  echo "${ip}"
}

# Verify the cached cloud image against the cached SHA256SUMS. Returns non-zero
# if either file is missing or the hash does not match.
image_is_verified() {
  [[ -f "${IMAGE_PATH}" && -f "${IMAGE_CACHE_DIR}/SHA256SUMS" ]] || return 1
  (cd "${IMAGE_CACHE_DIR}" \
    && grep "${IMAGE_NAME}" SHA256SUMS | shasum -a 256 -c - >/dev/null 2>&1)
}
