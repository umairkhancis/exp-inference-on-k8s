#!/usr/bin/env bash
# 1.2.2 — Inspect vLLM's Prometheus /metrics endpoint for performance numbers.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

echo "[INFO] GET $BASE_URL/metrics — key vLLM performance metrics:"
echo

curl -fsS "$BASE_URL/metrics" | python3 -c "
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
echo
echo "[OK] Full raw dump: curl -s $BASE_URL/metrics | grep 'vllm:'"
