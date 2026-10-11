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

readonly WIT_REPO_REGEX='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

# wit_change_link_args <args…> — parse the change-link input (CONTRACT.md "Change
# links"): exactly one of <id> or --branch-ref <ref>, plus optional --repo <o>/<r>.
# Sets WIT_CL_ID, WIT_CL_REF, WIT_CL_REPO. Calls the sourcing adapter's
# wit_usage_error (exit 2) on bad input.
# shellcheck disable=SC2034  # WIT_CL_* are read by the sourcing change-link verb scripts
wit_change_link_args() {
  WIT_CL_ID="" WIT_CL_REF="" WIT_CL_REPO=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --branch-ref)
      [[ $# -ge 2 && -n "$2" && -z "$WIT_CL_REF" ]] || wit_usage_error "--branch-ref needs one value"
      WIT_CL_REF="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 && "$2" =~ $WIT_REPO_REGEX ]] || wit_usage_error "--repo needs <owner>/<repo>"
      WIT_CL_REPO="$2"
      shift 2
      ;;
    -*) wit_usage_error "unknown flag: $1" ;;
    *)
      [[ -z "$WIT_CL_ID" ]] || wit_usage_error "change-link takes one id"
      WIT_CL_ID="$1"
      shift
      ;;
    esac
  done
  [[ -n "$WIT_CL_ID" || -n "$WIT_CL_REF" ]] || wit_usage_error "change-link needs <id> or --branch-ref <ref>"
  [[ -z "$WIT_CL_ID" || -z "$WIT_CL_REF" ]] || wit_usage_error "pass <id> or --branch-ref, not both"
}

# wit_change_link_no_item <message> — a well-formed --branch-ref this binding cannot
# name an item from (wrong shape, or outside the declared scope): exit 5, not 2, so a
# caller can tell "no linked item" from its own usage error.
wit_change_link_no_item() {
  printf 'change-link: %s\n' "$1" >&2
  exit 5
}

# wit_hash_ref <change-repo> — after wit_parse_id: `#N` when <change-repo> is the
# item's own repository, else the cross-repository `owner/repo#N` form.
wit_hash_ref() {
  if [[ "${1:-}" == "$WIT_ID_OWNER/$WIT_ID_REPO" ]]; then
    printf '#%s\n' "$WIT_ID_NUMBER"
  else
    printf '%s/%s#%s\n' "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER"
  fi
}

# wit_emit_change_link <id> <closes> <refs> <branch_ref> — the change-link object.
# An empty <closes> is emitted as null: merging closes nothing on this provider.
wit_emit_change_link() {
  jq -cn --arg v "${WIT_SCHEMA_VERSION:-1.0}" --arg id "$1" --arg c "$2" --arg r "$3" --arg b "$4" \
    '{schema_version: $v, item_id: $id, closes: (if $c == "" then null else $c end), refs: $r, branch_ref: $b}'
}
