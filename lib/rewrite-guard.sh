# shellcheck shell=bash

[[ -n "${_HOOK_REWRITE_GUARD_LOADED:-}" ]] && return 0
readonly _HOOK_REWRITE_GUARD_LOADED=1

_HOOK_REWRITE_BEFORE=""
_HOOK_REWRITE_FILE=""
_HOOK_REWRITE_PREV_EXIT_TRAP=""
_HOOK_REWRITE_SNAPSHOT_FAILED=0
HOOK_REWRITE_MESSAGE=""
HOOK_REWRITE_CHANGED=""

hook::_rewrite_guard_on_exit() {
  [[ -n "${_HOOK_REWRITE_BEFORE:-}" ]] && rm -f "$_HOOK_REWRITE_BEFORE"
  if [[ -n "$_HOOK_REWRITE_PREV_EXIT_TRAP" ]]; then
    eval "$_HOOK_REWRITE_PREV_EXIT_TRAP"
  fi
  return 0
}

hook::rewrite_guard_begin() {
  _HOOK_REWRITE_BEFORE=""
  _HOOK_REWRITE_FILE="$1"
  _HOOK_REWRITE_SNAPSHOT_FAILED=1
  HOOK_REWRITE_MESSAGE=""
  HOOK_REWRITE_CHANGED=""
  local snap prev
  snap=$(mktemp 2>/dev/null) || return 0
  if ! cp "$1" "$snap" 2>/dev/null; then
    rm -f "$snap" 2>/dev/null || true
    return 0
  fi
  _HOOK_REWRITE_BEFORE="$snap"
  _HOOK_REWRITE_SNAPSHOT_FAILED=0
  prev=$(trap -p EXIT 2>/dev/null) || prev=""
  if [[ -n "$prev" ]]; then
    prev=${prev#trap -- }
    prev=${prev% EXIT}
    eval "prev=$prev"
    if [[ "$prev" != "hook::_rewrite_guard_on_exit" && -n "$prev" ]]; then
      _HOOK_REWRITE_PREV_EXIT_TRAP="$prev"
    fi
  fi
  trap hook::_rewrite_guard_on_exit EXIT
  return 0
}

hook::rewrite_take_disclosure() {
  local file="${1:-$_HOOK_REWRITE_FILE}" message="$2"
  HOOK_REWRITE_MESSAGE=""
  if [[ -z "$_HOOK_REWRITE_BEFORE" ]]; then
    if [[ -z "$HOOK_REWRITE_CHANGED" && "$_HOOK_REWRITE_SNAPSHOT_FAILED" -eq 0 ]]; then
      HOOK_REWRITE_CHANGED="false"
    fi
    return 0
  fi
  if ! cmp -s "$_HOOK_REWRITE_BEFORE" "$file" 2>/dev/null; then
    HOOK_REWRITE_MESSAGE="$message"
    HOOK_REWRITE_CHANGED="true"
  else
    HOOK_REWRITE_CHANGED="false"
  fi
  rm -f "$_HOOK_REWRITE_BEFORE"
  _HOOK_REWRITE_BEFORE=""
  return 0
}

hook::rewrite_disclose() {
  hook::rewrite_take_disclosure "$2" "$3"
  [[ -n "$HOOK_REWRITE_MESSAGE" ]] || return 0
  hook::emit_channels "$1" "" "$HOOK_REWRITE_MESSAGE"
}
