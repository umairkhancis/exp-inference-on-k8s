#!/usr/bin/env bash
# 1.2.2 — Inspect vLLM's Prometheus /metrics endpoint for performance numbers.
# Counters are cumulative, so throughput is measured as the delta between
# two samples taken SAMPLE_SECONDS apart (default 5).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SAMPLE_SECONDS="${SAMPLE_SECONDS:-5}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[0;36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; CYAN=""; RESET=""
fi

banner() {
  echo "${CYAN}${BOLD}"
  cat <<'EOF'
  ___        __
 |_ _|_ __  / _| ___ _ __ ___ _ __   ___ ___
  | || '_ \| |_ / _ \ '__/ _ \ '_ \ / __/ _ \
  | || | | |  _|  __/ | |  __/ | | | (_|  __/
 |___|_| |_|_|  \___|_|  \___|_| |_|\___\___|
  _   _                        _            _
 | | | |_ __  _ __   __ _  ___| | _____  __| |
 | | | | '_ \| '_ \ / _` |/ __| |/ / _ \/ _` |
 | |_| | | | | |_) | (_| | (__|   <  __/ (_| |
  \___/|_| |_| .__/ \__,_|\___|_|\_\___|\__,_|
             |_|
EOF
  echo "${RESET}"
  echo "  ${BOLD}Inference Unpacked${RESET} ${DIM}· metrics check (${SAMPLE_SECONDS}s throughput window)${RESET}"
  echo "  ${DIM}gateway:${RESET} ${BASE_URL}/v1"
  echo "  ${DIM}model:  ${RESET} ${MODEL}"
  echo
}

banner

echo "[INFO] GET $BASE_URL/metrics — key vLLM performance metrics:"
echo

SNAP_A="$(mktemp)"; SNAP_B="$(mktemp)"
trap 'rm -f "$SNAP_A" "$SNAP_B"' EXIT
curl -fsS "$BASE_URL/metrics" > "$SNAP_A"
sleep "$SAMPLE_SECONDS"
curl -fsS "$BASE_URL/metrics" > "$SNAP_B"

cat "$SNAP_B" | python3 -c "
import sys, re

interesting = [
    ('vllm:prompt_tokens_total',            'Prompt tokens processed'),
    ('vllm:generation_tokens_total',        'Tokens generated'),
    ('vllm:request_success_total',          'Successful requests'),
    ('vllm:num_requests_running',           'Requests running now'),
    ('vllm:num_requests_waiting',           'Requests queued'),
    ('vllm:kv_cache_usage_perc',            'KV cache usage'),
    ('vllm:gpu_cache_usage_perc',           'KV cache usage'),
    ('vllm:time_to_first_token_seconds_sum',   'TTFT total (s)'),
    ('vllm:time_to_first_token_seconds_count', 'TTFT samples'),
    ('vllm:e2e_request_latency_seconds_sum',   'E2E latency total (s)'),
    ('vllm:e2e_request_latency_seconds_count', 'E2E latency samples'),
]

values = {}
for line in sys.stdin:
    if line.startswith('#'):
        continue
    m = re.match(r'^(\S+?)(?:\{[^}]*\})?\s+([0-9eE+.\-]+)$', line.strip())
    if m:
        name, val = m.group(1), float(m.group(2))
        values[name] = values.get(name, 0.0) + val

found = False
for key, label in interesting:
    if key in values:
        found = True
        print(f'  {label:<28} {values[key]:,.2f}')

ttft_s, ttft_n = values.get('vllm:time_to_first_token_seconds_sum'), values.get('vllm:time_to_first_token_seconds_count')
if ttft_s and ttft_n:
    print(f'  {\"Avg time-to-first-token\":<28} {ttft_s/ttft_n:.3f}s')
e2e_s, e2e_n = values.get('vllm:e2e_request_latency_seconds_sum'), values.get('vllm:e2e_request_latency_seconds_count')
if e2e_s and e2e_n:
    print(f'  {\"Avg end-to-end latency\":<28} {e2e_s/e2e_n:.3f}s')

if not found:
    print('  No vllm: metrics found yet — send a request first (./verify/curl-check.sh).')
    sys.exit(1)
"

python3 - "$SNAP_A" "$SNAP_B" "$SAMPLE_SECONDS" <<'PYEOF'
import re, sys

def totals(path):
    sums = {}
    with open(path) as f:
        for line in f:
            m = re.match(r'^(vllm:(?:prompt|generation)_tokens_total|vllm:request_success_total)(?:\{[^}]*\})?\s+([0-9eE+.\-]+)', line)
            if m:
                sums[m.group(1)] = sums.get(m.group(1), 0.0) + float(m.group(2))
    return sums

a, b, window = totals(sys.argv[1]), totals(sys.argv[2]), float(sys.argv[3])
def rate(key):
    return max(0.0, b.get(key, 0.0) - a.get(key, 0.0)) / window

print()
print(f'  Live throughput (over a {window:.0f}s window):')
print(f'  {"Generation throughput":<28} {rate("vllm:generation_tokens_total"):,.1f} tok/s')
print(f'  {"Prompt throughput":<28} {rate("vllm:prompt_tokens_total"):,.1f} tok/s')
print(f'  {"Requests completed":<28} {rate("vllm:request_success_total"):,.2f} req/s')
if all(rate(k) == 0 for k in a.keys() | b.keys()):
    print('  (engine is idle — run ./verify/load-test.sh in another terminal to see it move)')
PYEOF

echo
echo "[OK] Full raw dump: curl -s $BASE_URL/metrics | grep 'vllm:'"
