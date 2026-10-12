#!/usr/bin/env bash
# 1.2.1 — Verify the OpenAI-compatible endpoint from the host machine.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "[INFO] Endpoint: $BASE_URL/v1  (model: $MODEL)"

echo "[INFO] GET /v1/models"
curl -fsS "$BASE_URL/v1/models" | python3 -m json.tool

echo
echo "[INFO] POST /v1/chat/completions"
START=$(date +%s.%N)
RESPONSE="$(curl -fsS "$BASE_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Reply with exactly: inference engine online\"}],
    \"max_tokens\": 32
  }")"
ELAPSED=$(echo "$(date +%s.%N) - $START" | bc)

echo "$RESPONSE" | python3 -c "
import json, sys
r = json.load(sys.stdin)
print('  Reply   :', r['choices'][0]['message']['content'].strip())
u = r.get('usage', {})
print('  Tokens  : prompt=%s completion=%s total=%s' % (u.get('prompt_tokens'), u.get('completion_tokens'), u.get('total_tokens')))
"
printf '  Latency : %.2fs\n' "$ELAPSED"
echo
echo "[OK] vLLM inside the Multipass k8s cluster is reachable from this host."
