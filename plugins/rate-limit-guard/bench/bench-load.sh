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
FAIL_MARKER="$OUT/render-failed"

FLOOR_BEFORE="$(spawn_floor)"

session_worker() {
  local id="$1" deadline="$2" log="$3" t0 t1 now spent
  local payload="${BENCH_PAYLOAD/bench-0000/bench-$id}"
  while
    now_ms now
    ((now < deadline))
  do
    now_ms t0
    if ! render_once "$payload"; then
      : >"$FAIL_MARKER"
      return 1
    fi
    now_ms t1
    printf '%s\n' "$((t1 - t0))" >>"$log"
    spent=$((t1 - t0))
    ((spent < 1000)) && sleep "$(pace_sleep_arg "$spent")"
  done
}

START=0
now_ms START
DEADLINE=$((START + SECS * 1000))
for ((s = 0; s < SESSIONS; s++)); do
  session_worker "$s" "$DEADLINE" "$OUT/s$s.txt" &
done
wait

if [[ -e "$FAIL_MARKER" ]]; then
  echo "bench-load: a render failed (STATUSLINE_ENTRY=$STATUSLINE_ENTRY); discarding run" >&2
  exit 1
fi

FLOOR_AFTER="$(spawn_floor)"

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
