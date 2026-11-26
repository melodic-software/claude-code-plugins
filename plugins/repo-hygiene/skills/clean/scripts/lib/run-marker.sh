# shellcheck shell=bash

[[ -n "${_CLEAN_RUN_MARKER_LOADED:-}" ]] && return 0
readonly _CLEAN_RUN_MARKER_LOADED=1

RUN_MARKER_IDLE_SECONDS=3600

run_marker_data_dir_ours() {
  local seg="${1%[/\\]}"
  seg="${seg##*[/\\]}"
  [[ "$seg" == repo-hygiene || "$seg" == repo-hygiene-* ]]
}

run_marker_path_to() {
  local -n __rm_out="$1"
  local data="$2" session="$3"
  __rm_out=""
  # shellcheck disable=SC2016 # the literal, unexpanded ${ is what is matched
  [[ -n "$data" && "$data" != *'${'* ]] || return 1
  [[ "$session" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  __rm_out="${data%/}/clean-run/${session}.open"
}

run_marker_write() {
  local now
  printf -v now '%(%s)T' -1
  mkdir -p "${1%/*}" 2>/dev/null || return 1
  printf '%s\n' "$now" >"$1"
}

run_marker_state_to() {
  local -n __rm_state="$1"
  local file="$2" stamp="" now
  if [[ ! -e "$file" ]]; then
    __rm_state=absent
    return 0
  fi
  read -r stamp <"$file" 2>/dev/null || true
  printf -v now '%(%s)T' -1
  if [[ "$stamp" =~ ^[0-9]+$ ]] && ((now - stamp > RUN_MARKER_IDLE_SECONDS)); then
    __rm_state=stale
  else
    __rm_state=live
  fi
}
