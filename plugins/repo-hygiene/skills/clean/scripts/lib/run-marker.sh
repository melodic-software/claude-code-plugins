# shellcheck shell=bash
# Per-session run-open marker shared by clean-run-marker.sh (writes it) and
# destructive-guard.sh (reads it). A marker file says "a mutating clean run is
# open in this session"; the guard gates only while one is live. The marker holds
# the epoch second of its last write, and the guard refreshes it on every call it
# gates, so the idle timeout counts from the last guarded tool call.

[[ -n "${_CLEAN_RUN_MARKER_LOADED:-}" ]] && return 0
readonly _CLEAN_RUN_MARKER_LOADED=1

# One hour without a guarded tool call clears a marker nobody closed.
RUN_MARKER_IDLE_SECONDS=3600

# run_marker_path_to <var> <data-dir> <session-id>
# Writes the marker path into <var>. Returns 1, leaving <var> empty, when the
# data directory is empty or still an unsubstituted ${...} reference, or the
# session id holds anything but [A-Za-z0-9_-] (it becomes a file name).
run_marker_path_to() {
  local -n __rm_out="$1"
  local data="$2" session="$3"
  __rm_out=""
  [[ -n "$data" && "$data" != *'${'* ]] || return 1
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  __rm_out="${data%/}/clean-run/${session}.open"
}

# run_marker_write <path>: create or refresh the marker with the current epoch second.
run_marker_write() {
  local now
  printf -v now '%(%s)T' -1
  mkdir -p "${1%/*}" 2>/dev/null || return 1
  printf '%s\n' "$now" >"$1"
}

# run_marker_state_to <var> <path>
# Writes absent, live or stale. An unreadable or non-numeric marker is live: a
# marker that cannot be aged keeps the guard armed rather than dropping it.
run_marker_state_to() {
  local -n __rm_state="$1"
  local file="$2" stamp="" now
  if [[ ! -e "$file" ]]; then
    __rm_state=absent
    return 0
  fi
  read -r stamp <"$file" 2>/dev/null || true
  if [[ ! "$stamp" =~ ^[0-9]+$ ]]; then
    __rm_state=live
    return 0
  fi
  printf -v now '%(%s)T' -1
  if ((now - stamp > RUN_MARKER_IDLE_SECONDS)); then
    __rm_state=stale
  else
    __rm_state=live
  fi
}
