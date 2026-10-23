#!/usr/bin/env bash
# Layer 6 — phase-2 verification, all from the host:
#   1. a completion request to the NodePort answered 200 via Envoy (server header)
#   2. cache-aware routing: N requests sharing a long prefix land on ONE vLLM pod
#      (per-pod vllm:prefix_cache_queries_total delta) and that pod reports
#      prefix-cache HITS — i.e. the EPP routed by cache affinity, not round-robin.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

GATEWAY="http://$(vm_ip "${MASTER_NAME}"):${LLMD_NODEPORT}"
PODS=($(kn get pods -l llm-d.ai/role=decode -o jsonpath='{.items[*].metadata.name}'))
[[ "${#PODS[@]}" -ge 2 ]] || die "need >=2 decode pods for a routing test, found ${#PODS[@]}"

metric() { # metric <pod> <metric-name> -> summed value (or 0)
  k get --raw "/api/v1/namespaces/${LLMD_NS}/pods/${1}:8000/proxy/metrics" 2>/dev/null \
    | awk -v m="$2" '$0 ~ "^"m"{" || $1 == m {s+=$NF} END {printf "%.0f", s}'
}

log "1/2 Completion request through the gateway (${GATEWAY})"
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

log "2/2 Cache-aware routing: 8 requests sharing a ~500-token prefix"
declare -a Q0 H0
for i in "${!PODS[@]}"; do
  Q0[$i]="$(metric "${PODS[$i]}" vllm:prefix_cache_queries_total)"
  H0[$i]="$(metric "${PODS[$i]}" vllm:prefix_cache_hits_total)"
done

PREFIX="$(printf 'The llm-d endpoint picker routes a request to the vllm pod that already holds its prefix in the kv cache. %.0s' {1..40})"
for i in $(seq 1 8); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "${GATEWAY}/v1/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${LLMD_MODEL}\", \"prompt\": \"${PREFIX} Question ${i}: what is llm-d?\", \"max_tokens\": 8}")"
  echo "  shared-prefix request ${i}: HTTP ${code}"
  [[ "${code}" == "200" ]] || die "shared-prefix request ${i} failed"
done

log "Per-pod prefix-cache deltas (queries routed / cache hits):"
TOTAL_DQ=0 WINNERS=0 HIT_OK=0
for i in "${!PODS[@]}"; do
  dq=$(( $(metric "${PODS[$i]}" vllm:prefix_cache_queries_total) - Q0[$i] ))
  dh=$(( $(metric "${PODS[$i]}" vllm:prefix_cache_hits_total) - H0[$i] ))
  node="$(kn get pod "${PODS[$i]}" -o jsonpath='{.spec.nodeName}')"
  printf '  %-45s %-14s queries+%-4s hits+%s\n' "${PODS[$i]}" "(${node})" "${dq}" "${dh}"
  TOTAL_DQ=$(( TOTAL_DQ + dq ))
  if (( dq >= 7 )); then WINNERS=$(( WINNERS + 1 )); (( dh > 0 )) && HIT_OK=1; fi
done

(( TOTAL_DQ >= 8 )) || die "expected >=8 routed queries, metrics saw ${TOTAL_DQ}"
(( WINNERS == 1 )) || die "shared-prefix traffic was spread across pods — cache-aware routing NOT in effect"
(( HIT_OK == 1 )) || die "winning pod reports no prefix-cache hits"

log "Verification passed: Envoy -> EPP -> vLLM with cache-aware routing (all shared-prefix requests pinned to one pod, with prefix-cache hits)"
