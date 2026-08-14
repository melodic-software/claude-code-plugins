#!/usr/bin/env bash
# bench-idle.sh N — N sequential statusline renders, back to back (the shape a
# single idle session produces). Reports the spawn floor, then per-render ms.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-bench.sh
source "$DIR/lib-bench.sh"

N="${1:-11}"
FLOOR_BEFORE="$(spawn_floor 11)"
declare -a T=()
for ((i = 0; i < N; i++)); do
  t0="$(now_ms)"
  printf '%s' "$BENCH_PAYLOAD" | bash "$STATUSLINE_ENTRY" >/dev/null 2>&1
  t1="$(now_ms)"
  T+=("$((t1 - t0))")
done
FLOOR_AFTER="$(spawn_floor 11)"
MED="$(printf '%s\n' "${T[@]}" | median)"
SUM=0
for x in "${T[@]}"; do SUM=$((SUM + x)); done
printf 'idle n=%s floor_before=%s floor_after=%s median=%s mean=%s samples=%s\n' \
  "$N" "$FLOOR_BEFORE" "$FLOOR_AFTER" "$MED" "$((SUM / N))" "${T[*]}"
