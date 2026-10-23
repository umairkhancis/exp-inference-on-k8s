#!/usr/bin/env bash
# Layer 1 — the llm-d quickstart repo.
# Clones github.com/llm-d/llm-d at ${LLMD_BRANCH} (as the quickstart instructs)
# into the project cache; the router values files and the model-server
# kustomize base are applied from this pinned clone.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

if [[ -d "${LLMD_REPO}/.git" ]]; then
  log "llm-d repo already cloned at ${LLMD_REPO} ($(git -C "${LLMD_REPO}" rev-parse --short HEAD) on ${LLMD_BRANCH})"
else
  log "Cloning llm-d (${LLMD_BRANCH}) into ${LLMD_REPO}"
  git clone --depth 1 -b "${LLMD_BRANCH}" "${LLMD_REPO_URL}" "${LLMD_REPO}"
fi

[[ -d "${LLMD_REPO}/guides/optimized-baseline/modelserver/cpu/vllm/base" ]] \
  || die "clone looks wrong: missing guides/optimized-baseline/modelserver/cpu/vllm/base"
log "llm-d repo ready"
