#!/usr/bin/env bash
# Step 1/3 (host): install Multipass — the security boundary.
# Everything else in this project runs inside an isolated Ubuntu VM;
# this is the only thing we ever install on your host machine.
set -euo pipefail

if command -v multipass >/dev/null 2>&1; then
  echo "[OK] multipass already installed: $(multipass version | head -1)"
  exit 0
fi

OS="$(uname -s)"
case "$OS" in
  Darwin)
    if ! command -v brew >/dev/null 2>&1; then
      echo "[ERROR] Homebrew not found. Install it from https://brew.sh then re-run." >&2
      exit 1
    fi
    echo "[INFO] Installing Multipass via Homebrew..."
    brew install --cask multipass
    ;;
  Linux)
    if command -v snap >/dev/null 2>&1; then
      echo "[INFO] Installing Multipass via snap..."
      sudo snap install multipass
    else
      echo "[ERROR] snap not found. See https://canonical.com/multipass/install" >&2
      exit 1
    fi
    ;;
  *)
    echo "[ERROR] Unsupported OS: $OS. See https://canonical.com/multipass/install" >&2
    exit 1
    ;;
esac

echo "[OK] $(multipass version | head -1)"
