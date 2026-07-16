#!/usr/bin/env bash
# ID grammar helpers (CONTRACT.md "ID grammar"): <provider>:<owner>/<repo>#<number>.
# Sourced — callers map parse failure to exit 2.

[[ -n "${_WIT_ID_LOADED:-}" ]] && return 0
readonly _WIT_ID_LOADED=1

readonly WIT_ID_REGEX='^([a-z0-9][a-z0-9-]*):([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)$'

# wit_parse_id <id> — export WIT_ID_PROVIDER / WIT_ID_OWNER / WIT_ID_REPO /
# WIT_ID_NUMBER. Returns 1 on malformed input (bare #123 etc.).
wit_parse_id() {
  local id="${1:-}"
  [[ "$id" =~ $WIT_ID_REGEX ]] || return 1
  WIT_ID_PROVIDER="${BASH_REMATCH[1]}"
  WIT_ID_OWNER="${BASH_REMATCH[2]}"
  WIT_ID_REPO="${BASH_REMATCH[3]}"
  WIT_ID_NUMBER="${BASH_REMATCH[4]}"
  export WIT_ID_PROVIDER WIT_ID_OWNER WIT_ID_REPO WIT_ID_NUMBER
}

# wit_make_id <provider> <owner> <repo> <number> — echo a well-formed ID.
wit_make_id() {
  printf '%s:%s/%s#%s\n' "$1" "$2" "$3" "$4"
}
