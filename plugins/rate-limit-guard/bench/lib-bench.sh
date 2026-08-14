#!/usr/bin/env bash
# Shared helpers for the rate-limit-guard statusline benchmarks (see README.md
# in this directory for the method and the #2521 baseline numbers).
#
# STATUSLINE_ENTRY is the script each render invokes: default is this repo's
# statusline-tee.sh in standalone mode (no wrapped statusline), so the harness
# runs from a clean checkout. Point it at your machine's real statusline
# entrypoint to measure the wrapped path you actually run.
set -uo pipefail

# Hard bash >= 5.0 requirement: the timers read EPOCHREALTIME because every
# alternative (`date +%s%3N`) is a process spawn — the very cost this harness
# measures — inside the timer read. Refuse loudly rather than fall back.
if [[ -z "${EPOCHREALTIME:-}" ]]; then
  echo "bench: this harness requires bash >= 5.0 (EPOCHREALTIME); found $BASH_VERSION" >&2
  exit 1
fi

BENCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE_ENTRY="${STATUSLINE_ENTRY:-$BENCH_LIB_DIR/../scripts/statusline-tee.sh}"

# Spawn-floor sample count (median of N bare `bash -c exit` spawns). The
# contract test drops it to keep the smoke runs fast; benchmarking keeps 11.
BENCH_FLOOR_N="${BENCH_FLOOR_N:-11}"

# shellcheck disable=SC2034  # consumed by the sourcing bench scripts, not this file
BENCH_PAYLOAD='{"hook_event_name":"Status","session_id":"bench-0000","transcript_path":"/tmp/none.jsonl","cwd":"/tmp","model":{"id":"claude-opus-4-8","display_name":"Opus"},"workspace":{"current_dir":"/tmp","project_dir":"/tmp"},"version":"2.1.0","output_style":{"name":"default"},"context_window":{"used_percentage":12,"used_tokens":24000,"max_tokens":200000},"exceeds_200k_tokens":false,"cost":{"total_cost_usd":0.12,"total_duration_ms":1000,"total_lines_added":3,"total_lines_removed":1},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}'

# now_ms VAR — store milliseconds-since-epoch into VAR. Assigns with printf -v
# instead of printing, so a timer read never costs the caller a subshell fork:
# on MSYS a $(now_ms) substitution would add a dominant fork between the two
# reads bracketing the thing being measured.
now_ms() {
  local _rlg_bench_r="${EPOCHREALTIME/,/.}"
  printf -v "$1" '%s' "$(((${_rlg_bench_r%%.*} * 1000) + (10#${_rlg_bench_r#*.} / 1000)))"
}

# render_once PAYLOAD — one statusline render; propagates the render's exit
# status so a misconfigured STATUSLINE_ENTRY or failing render aborts the lane
# instead of being timed as a plausible fast sample.
render_once() {
  printf '%s' "$1" | bash "$STATUSLINE_ENTRY" >/dev/null 2>&1
}

# pace_sleep_arg SPENT_MS — print the sleep argument that pads SPENT_MS up to
# one second. Handles the full second explicitly: a bare "0.$(printf '%03d')"
# would render 1000 ms as "0.1000" = 0.1 s (a %03d width is a minimum, not a
# cap) and fire ten times faster than intended.
pace_sleep_arg() {
  local rem=$((1000 - $1))
  printf '%s.%03d' "$((rem / 1000))" "$((rem % 1000))"
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
  local n="${1:-$BENCH_FLOOR_N}" i t0 t1
  for ((i = 0; i < n; i++)); do
    now_ms t0
    bash -c exit
    now_ms t1
    printf '%s\n' "$((t1 - t0))"
  done | median
}
