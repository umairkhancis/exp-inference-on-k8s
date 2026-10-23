#!/usr/bin/env bash
# Layer 0 — host prerequisites.
# Verifies host tooling (installs the llm-d client tools via brew when missing)
# and ensures a hash-verified Ubuntu cloud image is cached for file:// launches.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

log "Checking required host tools"
for tool in multipass jq curl shasum git; do
  command -v "${tool}" >/dev/null || die "'${tool}' is required but not installed"
done

# Client-side tools llm-d's quickstart expects (phase 2 will use them).
if command -v brew >/dev/null; then
  for tool in kubectl helm helmfile yq; do
    if ! command -v "${tool}" >/dev/null; then
      log "Installing ${tool} via Homebrew"
      brew install "${tool}"
    fi
  done
  if ! helm plugin list 2>/dev/null | grep -q '^diff'; then
    log "Installing helm-diff plugin (needed by helmfile)"
    # helm >= 4 refuses unsigned plugin sources unless verification is skipped
    helm plugin install https://github.com/databus23/helm-diff --verify=false \
      || helm plugin install https://github.com/databus23/helm-diff
  fi
else
  command -v kubectl >/dev/null || die "kubectl is required (no Homebrew found to install it)"
  warn "Homebrew not found: install helm, helmfile and yq manually before phase 2"
fi

log "Ensuring verified Ubuntu 24.04 arm64 cloud image in ${IMAGE_CACHE_DIR}"
mkdir -p "${IMAGE_CACHE_DIR}"
if image_is_verified; then
  log "Cached image already verified: ${IMAGE_PATH}"
else
  log "Downloading SHA256SUMS and cloud image (resumable)"
  curl -fL --retry 5 -o "${IMAGE_CACHE_DIR}/SHA256SUMS" "${SHA256SUMS_URL}"
  curl -fL -C - --retry 5 -o "${IMAGE_PATH}" "${IMAGE_URL}" || true
  if ! image_is_verified; then
    # A cached image from an older 'release' snapshot can't be resumed into
    # the new one — discard it and download from scratch.
    warn "cached image is stale or corrupt; re-downloading from scratch"
    rm -f "${IMAGE_PATH}"
    curl -fL --retry 5 -o "${IMAGE_PATH}" "${IMAGE_URL}"
    image_is_verified || die "downloaded image failed SHA256 verification"
  fi
  log "Image downloaded and verified"
fi

log "Host prerequisites OK"
