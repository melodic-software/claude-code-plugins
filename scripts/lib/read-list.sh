# shellcheck shell=bash

_read_list::mode() {
  local -n _rl_mode_out="$1"
  shift
  _rl_mode_out=""
  while (($# > 0)); do
    case "$1" in
    --comments)
      _rl_mode_out="${2-}"
      # `shift 2` with one argument left shifts nothing and returns non-zero:
      # https://www.gnu.org/software/bash/manual/html_node/Bourne-Shell-Builtins.html
      shift $(($# > 1 ? 2 : 1))
      ;;
    *)
      printf 'read-list: unknown option %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  case "$_rl_mode_out" in
  inline | leading) return 0 ;;
  "")
    printf 'read-list: --comments is required (inline|leading); there is no default\n' >&2
    return 2
    ;;
  *)
    printf 'read-list: unknown --comments mode %s (want inline|leading)\n' "$_rl_mode_out" >&2
    return 2
    ;;
  esac
}

_read_list::parse() {
  local -n _rl_parse_out="$1"
  local _rl_parse_mode="$2"

  _rl_parse_out=()
  local _rl_line
  while IFS= read -r _rl_line || [[ -n "$_rl_line" ]]; do
    _rl_line="${_rl_line%$'\r'}"
    if [[ "$_rl_parse_mode" == inline ]]; then
      _rl_line="${_rl_line%%#*}"
    fi
    _rl_line="${_rl_line#"${_rl_line%%[![:space:]]*}"}"
    _rl_line="${_rl_line%"${_rl_line##*[![:space:]]}"}"
    [[ -n "$_rl_line" ]] || continue
    if [[ "$_rl_parse_mode" == leading && "$_rl_line" == '#'* ]]; then
      continue
    fi
    _rl_parse_out+=("$_rl_line")
  done
  return 0
}

read_list::into() {
  local _rl_name="$1"
  local _rl_file="$2"
  shift 2

  local _rl_mode
  _read_list::mode _rl_mode "$@" || return 2

  if [[ ! -f "$_rl_file" ]]; then
    printf 'read-list: list file not found: %s\n' "$_rl_file" >&2
    return 1
  fi
  if [[ ! -r "$_rl_file" ]]; then
    printf 'read-list: list file not readable: %s\n' "$_rl_file" >&2
    return 1
  fi

  _read_list::parse "$_rl_name" "$_rl_mode" <"$_rl_file"
}

read_list::into_text() {
  local _rl_name="$1"
  local _rl_text="$2"
  shift 2

  local _rl_mode
  _read_list::mode _rl_mode "$@" || return 2

  _read_list::parse "$_rl_name" "$_rl_mode" <<<"$_rl_text"
}

declare -gA _RL_USED=()

read_list::mark_used() {
  local _rl_entry
  for _rl_entry in "$@"; do
    _RL_USED["$_rl_entry"]=1
  done
}

read_list::reset_used() {
  _RL_USED=()
}

read_list::stale_to() {
  local -n _rl_stale_out="$1"
  local -n _rl_stale_list="$2"
  _rl_stale_out=()
  local -A _rl_seen=()
  local _rl_entry
  for _rl_entry in ${_rl_stale_list[@]+"${_rl_stale_list[@]}"}; do
    [[ -n "${_RL_USED[$_rl_entry]:-}" ]] && continue
    [[ -n "${_rl_seen[$_rl_entry]:-}" ]] && continue
    _rl_seen["$_rl_entry"]=1
    _rl_stale_out+=("$_rl_entry")
  done
  return 0
}

read_list::stale_line() {
  printf "STALE BASELINE: %s: '%s' %s\n" "$1" "$2" "$3" >&2
}

read_list::report_stale() {
  local _rl_list_name="$1" _rl_label="$2" _rl_reason="$3"
  local -a _rl_stale=()
  read_list::stale_to _rl_stale "$_rl_list_name"
  ((${#_rl_stale[@]} > 0)) || return 0
  local _rl_entry
  for _rl_entry in "${_rl_stale[@]}"; do
    read_list::stale_line "$_rl_label" "$_rl_entry" "$_rl_reason"
  done
  return 1
}
