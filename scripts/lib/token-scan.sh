# shellcheck shell=bash

token_scan::awk_operand() {
  case "$1" in
  ./* | /*) printf '%s' "$1" ;;
  *) printf './%s' "$1" ;;
  esac
}

token_scan::require_token_file() {
  if [[ ! -f "$1" ]]; then
    printf 'Error: token list not found: %s\n' "$1" >&2
    return 1
  fi
}

token_scan::load_active() {
  local _ts_src="$1"
  local -n _ts_active="$2" _ts_operand="$3"
  local _ts_patterns=()
  token_scan::require_token_file "$_ts_src" || return 1
  read_list::into _ts_patterns "$_ts_src" --comments leading || return 1
  if ((${#_ts_patterns[@]} == 0)); then
    printf 'Error: token list loaded no active patterns: %s\n' "$_ts_src" >&2
    return 1
  fi
  _ts_active="$(mktemp)" || return 1
  # shellcheck disable=SC2064 # the variable NAME is fixed now; its value expands at exit
  trap "rm -f \"\$$2\"" EXIT
  printf '%s\n' "${_ts_patterns[@]}" >"$_ts_active"
  _ts_operand="$(token_scan::awk_operand "$_ts_active")"
}
