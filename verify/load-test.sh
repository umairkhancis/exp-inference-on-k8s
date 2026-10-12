#!/usr/bin/env bash
# 1.2.3 — Simulate N developers (default 10) hammering the endpoint in
# parallel, then report latency percentiles and token throughput.
#
#   DEVELOPERS=10 DURATION=60 ./verify/load-test.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

DEVELOPERS="${DEVELOPERS:-10}"
DURATION="${DURATION:-60}"
MAX_TOKENS="${MAX_TOKENS:-64}"

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
  echo "  ${BOLD}Inference Unpacked${RESET} ${DIM}· load test (${DEVELOPERS} developers, ${DURATION}s)${RESET}"
  echo "  ${DIM}gateway:${RESET} ${BASE_URL}/v1"
  echo "  ${DIM}model:  ${RESET} ${MODEL}"
  echo
}

banner

RESULTS_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULTS_DIR"' EXIT

PROMPTS=(
  "Write a fast sorting algorithm in Rust."
  "Explain Kubernetes StatefulSets in two sentences."
  "Optimize a PostgreSQL connection pool configuration."
  "Refactor a multi-threaded Python web scraper."
  "What is the difference between a Deployment and a DaemonSet?"
  "Write a one-line jq command to extract all keys."
)

snapshot_tokens() {
  curl -fsS "$BASE_URL/metrics" | python3 -c "
import sys, re
p = g = 0.0
for line in sys.stdin:
    m = re.match(r'^(vllm:(?:prompt|generation)_tokens_total)(?:\{[^}]*\})?\s+([0-9eE+.\-]+)', line)
    if m:
        if 'prompt' in m.group(1): p += float(m.group(2))
        else: g += float(m.group(2))
print(f'{p} {g}')
"
}

developer() {
  local id="$1" end=$(( $(date +%s) + DURATION ))
  local n=${#PROMPTS[@]}
  while (( $(date +%s) < end )); do
    local prompt="${PROMPTS[$(( RANDOM % n ))]}"
    local start elapsed code
    start=$(python3 -c 'import time; print(time.time())')
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 120 \
      "$BASE_URL/v1/chat/completions" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$prompt\"}],\"max_tokens\":$MAX_TOKENS}") || code=000
    elapsed=$(python3 -c "import time; print(time.time() - $start)")
    echo "$code $elapsed" >> "$RESULTS_DIR/dev-$id.log"
    # Typical developer pace: think for 1-3 seconds between calls.
    sleep "$(python3 -c 'import random; print(round(random.uniform(1,3),2))')"
  done
}

echo "[INFO] Simulating $DEVELOPERS developers for ${DURATION}s (max_tokens=$MAX_TOKENS)..."

read -r P0 G0 <<< "$(snapshot_tokens)"
WALL_START=$(date +%s)

for i in $(seq 1 "$DEVELOPERS"); do developer "$i" & done
wait

WALL=$(( $(date +%s) - WALL_START ))
read -r P1 G1 <<< "$(snapshot_tokens)"

cat "$RESULTS_DIR"/dev-*.log | python3 -c "
import sys
rows = [line.split() for line in sys.stdin if line.strip()]
lat = sorted(float(e) for c, e in rows if c == '200')
fail = sum(1 for c, _ in rows if c != '200')
total = len(rows)
wall, p0, g0, p1, g1 = $WALL, $P0, $G0, $P1, $G1

def pct(p):
    return lat[min(len(lat)-1, int(p/100*len(lat)))] if lat else 0

print()
print('================ LOAD TEST REPORT ================')
print(f'  Developers          : $DEVELOPERS')
print(f'  Wall time           : {wall}s')
print(f'  Requests            : {total} total, {len(lat)} ok, {fail} failed')
if lat:
    print(f'  Throughput          : {len(lat)/wall:.2f} req/s')
    print(f'  Latency p50/p95/max : {pct(50):.2f}s / {pct(95):.2f}s / {lat[-1]:.2f}s')
print(f'  Prompt tokens       : {p1-p0:,.0f}')
print(f'  Generated tokens    : {g1-g0:,.0f}  ({(g1-g0)/wall:.1f} tok/s sustained)')
print(f'  Cost on this stack  : \$0.00 per token (flat-rate infra)')
print('===================================================')
sys.exit(1 if (total == 0 or fail > total * 0.1) else 0)
"
echo
echo "[OK] Inspect live engine state: ./verify/metrics-check.sh"
