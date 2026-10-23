#!/usr/bin/env bash
# Proves cache-AWARE routing: N requests sharing a long prompt prefix must all
# land on the SAME vLLM pod (per-pod vllm:request_success_total delta), and
# that pod must report prefix-cache HITS — i.e. the EPP routed by cache
# affinity, not round-robin.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

REQUESTS="${REQUESTS:-8}"
PODS=($(decode_pods))
[[ "${#PODS[@]}" -ge 2 ]] || die "need >=2 decode pods for a routing test, found ${#PODS[@]}"

declare -a R0 H0
for i in "${!PODS[@]}"; do
  R0[$i]="$(pod_metric "${PODS[$i]}" vllm:request_success_total)"
  H0[$i]="$(pod_metric "${PODS[$i]}" vllm:prefix_cache_hits_total)"
done

log "Sending ${REQUESTS} requests sharing a ~500-token prefix via $(gateway_url)"
PREFIX="$(printf 'The llm-d endpoint picker routes a request to the vllm pod that already holds its prefix in the kv cache. %.0s' {1..40})"
for i in $(seq 1 "${REQUESTS}"); do
  code="$(gateway_completion "${PREFIX} Question ${i}: what is llm-d?")"
  echo "  shared-prefix request ${i}: HTTP ${code}"
  [[ "${code}" == "200" ]] || die "shared-prefix request ${i} failed"
done

log "Per-pod deltas (requests served / prefix-cache hit tokens):"
TOTAL=0 WINNERS=0 HIT_OK=0
for i in "${!PODS[@]}"; do
  dr=$(( $(pod_metric "${PODS[$i]}" vllm:request_success_total) - R0[$i] ))
  dh=$(( $(pod_metric "${PODS[$i]}" vllm:prefix_cache_hits_total) - H0[$i] ))
  printf '  %-52s %-15s requests+%-3s hits+%s\n' "${PODS[$i]}" "($(pod_node "${PODS[$i]}"))" "${dr}" "${dh}"
  TOTAL=$(( TOTAL + dr ))
  if (( dr == REQUESTS )); then WINNERS=$(( WINNERS + 1 )); (( dh > 0 )) && HIT_OK=1; fi
done

(( TOTAL == REQUESTS )) || die "expected ${REQUESTS} served requests, metrics saw ${TOTAL}"
(( WINNERS == 1 ))      || die "shared-prefix traffic was spread across pods — cache-aware routing NOT in effect"
(( HIT_OK == 1 ))       || die "winning pod reports no prefix-cache hits"

log "PASS: all ${REQUESTS} shared-prefix requests pinned to one pod, with prefix-cache hits"
