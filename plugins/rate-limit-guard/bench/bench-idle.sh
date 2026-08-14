#!/usr/bin/env bash
# bench-idle.sh N — N sequential statusline renders, back to back (the shape a
# single idle session produces). Reports the spawn floor, then per-render ms.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-bench.sh
source "$DIR/lib-bench.sh"

N="${1:-11}"
FLOOR_BEFORE="$(spawn_floor)"
declare -a T=()
t0=0
t1=0
for ((i = 0; i < N; i++)); do
  now_ms t0
  if ! render_once "$BENCH_PAYLOAD"; then
    echo "bench-idle: render failed (STATUSLINE_ENTRY=$STATUSLINE_ENTRY); discarding run" >&2
    exit 1
  fi
  now_ms t1
  T+=("$((t1 - t0))")
done
FLOOR_AFTER="$(spawn_floor)"
MED="$(printf '%s\n' "${T[@]}" | median)"
SUM=0
for x in "${T[@]}"; do SUM=$((SUM + x)); done
printf 'idle n=%s floor_before=%s floor_after=%s median=%s mean=%s samples=%s\n' \
  "$N" "$FLOOR_BEFORE" "$FLOOR_AFTER" "$MED" "$((SUM / N))" "${T[*]}"
