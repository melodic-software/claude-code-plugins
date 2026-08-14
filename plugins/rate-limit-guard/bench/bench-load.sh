#!/usr/bin/env bash
# bench-load.sh SESSIONS SECONDS — SESSIONS concurrent virtual sessions, each
# firing a statusline render once a second for SECONDS. Reports the spawn floor
# BEFORE and AFTER (discard the run if they disagree materially), total renders,
# and the mean render latency across all of them.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-bench.sh
source "$DIR/lib-bench.sh"

SESSIONS="${1:-10}"
SECS="${2:-60}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

FLOOR_BEFORE="$(spawn_floor 11)"

session_worker() {
  local id="$1" deadline="$2" log="$3" t0 t1
  local payload="${BENCH_PAYLOAD/bench-0000/bench-$id}"
  while (($(now_ms) < deadline)); do
    t0="$(now_ms)"
    printf '%s' "$payload" | bash "$STATUSLINE_ENTRY" >/dev/null 2>&1
    t1="$(now_ms)"
    printf '%s\n' "$((t1 - t0))" >>"$log"
    local spent=$((t1 - t0))
    ((spent < 1000)) && sleep "0.$(printf '%03d' $((1000 - spent)))"
  done
}

DEADLINE=$(($(now_ms) + SECS * 1000))
for ((s = 0; s < SESSIONS; s++)); do
  session_worker "$s" "$DEADLINE" "$OUT/s$s.txt" &
done
wait

FLOOR_AFTER="$(spawn_floor 11)"

TOTAL=0
SUM=0
while read -r x; do
  [[ -n "$x" ]] || continue
  TOTAL=$((TOTAL + 1))
  SUM=$((SUM + x))
done < <(cat "$OUT"/s*.txt 2>/dev/null)
MED="$(cat "$OUT"/s*.txt 2>/dev/null | median)"
printf 'load sessions=%s secs=%s floor_before=%s floor_after=%s renders=%s median=%s mean=%s\n' \
  "$SESSIONS" "$SECS" "$FLOOR_BEFORE" "$FLOOR_AFTER" "$TOTAL" "$MED" \
  "$((TOTAL > 0 ? SUM / TOTAL : 0))"
