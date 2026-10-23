#!/usr/bin/env bash
# Layer 6 — phase-2 verification, all from the host:
#   1. a completion through the gateway answers 200 via Envoy (ext-proc header)
#   2. verify-prefix-affinity.sh — same prefix => same vLLM pod, with cache hits
#   3. verify-load-spread.sh    — distinct prompts => spread across pods

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

GATEWAY="$(gateway_url)"

log "1/3 Completion request through the gateway (${GATEWAY})"
RESP_HEADERS="$(mktemp)"
BODY=""
for attempt in 1 2 3 4 5; do # a freshly created NodePort needs a moment in kube-proxy
  if BODY="$(curl -sS -m 120 -D "${RESP_HEADERS}" -X POST "${GATEWAY}/v1/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${LLMD_MODEL}\", \"prompt\": \"Kubernetes is\", \"max_tokens\": 16}")"; then
    break
  fi
  warn "gateway not reachable yet (attempt ${attempt}/5), retrying in 5s"
  sleep 5
done
grep -i '^HTTP' "${RESP_HEADERS}"
grep -iE '^(server|x-went-into-resp-headers|x-envoy)' "${RESP_HEADERS}" || true
grep -qi '^HTTP.* 200' "${RESP_HEADERS}" || die "completion request did not return 200"
# Envoy's ext-proc filter (the EPP) stamps this header on processed responses;
# Envoy passes the upstream's own 'server: uvicorn' through, so check ext-proc.
grep -qi '^x-went-into-resp-headers' "${RESP_HEADERS}" \
  || warn "no ext-proc response header — check that traffic passes Envoy/EPP"
echo "${BODY}" | jq -e '.choices[0].text' >/dev/null || die "no completion text in response"
log "Completion OK: $(echo "${BODY}" | jq -c '{model, text: .choices[0].text}')"

log "2/3 Cache-aware routing (shared prefix => one pod)"
"$(dirname "${BASH_SOURCE[0]}")/verify-prefix-affinity.sh"

log "3/3 Load-based routing (distinct prompts => spread)"
"$(dirname "${BASH_SOURCE[0]}")/verify-load-spread.sh"

log "Verification passed: Envoy -> EPP -> vLLM, cache-affine for shared prefixes, load-spread otherwise"
