#!/usr/bin/env bash
# Shared helpers for the rate-limit-guard statusline benchmarks (see README.md
# in this directory for the method and the #2521 baseline numbers).
#
# STATUSLINE_ENTRY is the script each render invokes: default is this repo's
# statusline-tee.sh in standalone mode (no wrapped statusline), so the harness
# runs from a clean checkout. Point it at your machine's real statusline
# entrypoint to measure the wrapped path you actually run.
set -uo pipefail

BENCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE_ENTRY="${STATUSLINE_ENTRY:-$BENCH_LIB_DIR/../scripts/statusline-tee.sh}"

# shellcheck disable=SC2034  # consumed by the sourcing bench scripts, not this file
BENCH_PAYLOAD='{"hook_event_name":"Status","session_id":"bench-0000","transcript_path":"/tmp/none.jsonl","cwd":"/tmp","model":{"id":"claude-opus-4-8","display_name":"Opus"},"workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"version":"2.1.0","output_style":{"name":"default"},"context_window":{"used_percentage":12,"used_tokens":24000,"max_tokens":200000},"exceeds_200k_tokens":false,"cost":{"total_cost_usd":0.12,"total_duration_ms":1000,"total_lines_added":3,"total_lines_removed":1},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}'

now_ms() { # prints milliseconds as an integer
  local r="${EPOCHREALTIME/,/.}"
  printf '%s' "$(((${r%%.*} * 1000) + (10#${r#*.} / 1000)))"
}

median() { # median of the integers on stdin
  local -a v=()
  local x
  while read -r x; do [[ -n "$x" ]] && v+=("$x"); done
  ((${#v[@]})) || {
    printf '0'
    return
  }
  local sorted
  sorted="$(printf '%s\n' "${v[@]}" | sort -n)"
  local -a s=()
  while read -r x; do s+=("$x"); done <<<"$sorted"
  printf '%s' "${s[$((${#s[@]} / 2))]}"
}

# The window's process-creation floor. Everything measured here is dominated by
# it on MSYS, so a run whose floor moved is a run whose numbers are not
# comparable to its neighbour.
spawn_floor() {
  local n="${1:-11}" i t0 t1
  for ((i = 0; i < n; i++)); do
    t0="$(now_ms)"
    bash -c exit
    t1="$(now_ms)"
    printf '%s\n' "$((t1 - t0))"
  done | median
}
