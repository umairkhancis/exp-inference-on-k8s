#!/usr/bin/env bash
# Proves routing WITHOUT a shared prefix is load-based, not pinned: N requests
# with completely distinct prompts (nothing cached anywhere) must spread over
# MULTIPLE vLLM pods. Requests go out in small concurrent batches so the EPP's
# inflight-load scorer has real load differences to balance on.

source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

REQUESTS="${REQUESTS:-12}"
BATCH="${BATCH:-4}"
PODS=($(decode_pods))
[[ "${#PODS[@]}" -ge 2 ]] || die "need >=2 decode pods for a routing test, found ${#PODS[@]}"

declare -a R0
for i in "${!PODS[@]}"; do
  R0[$i]="$(pod_metric "${PODS[$i]}" vllm:request_success_total)"
done

log "Sending ${REQUESTS} distinct-prompt requests (batches of ${BATCH}) via $(gateway_url)"
sent=0
while (( sent < REQUESTS )); do
  pids=()
  for j in $(seq 1 "${BATCH}"); do
    (( sent + j > REQUESTS )) && break
    n=$(( sent + j ))
    # unique leading tokens per prompt => no common prefix block to cache
    ( code="$(gateway_completion "Topic ${n}-${RANDOM}-$(date +%s%N): write one sentence about subject number ${n}.")"
      echo "  distinct request ${n}: HTTP ${code}"
      [[ "${code}" == "200" ]] ) &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "${p}" || die "a distinct-prompt request failed"; done
  sent=$(( sent + ${#pids[@]} ))
done

log "Per-pod deltas (requests served):"
TOTAL=0 PODS_HIT=0
for i in "${!PODS[@]}"; do
  dr=$(( $(pod_metric "${PODS[$i]}" vllm:request_success_total) - R0[$i] ))
  printf '  %-52s %-15s requests+%s\n' "${PODS[$i]}" "($(pod_node "${PODS[$i]}"))" "${dr}"
  TOTAL=$(( TOTAL + dr ))
  (( dr > 0 )) && PODS_HIT=$(( PODS_HIT + 1 ))
done

(( TOTAL == REQUESTS )) || die "expected ${REQUESTS} served requests, metrics saw ${TOTAL}"
(( PODS_HIT >= 2 ))     || die "all distinct-prompt traffic went to ONE pod — load balancing NOT in effect"

log "PASS: ${REQUESTS} unrelated requests spread across ${PODS_HIT}/${#PODS[@]} pods (no false pinning)"
