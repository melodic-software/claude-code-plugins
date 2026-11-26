# shellcheck shell=bash

[[ -n "${_WIT_VERB_CLI_LOADED:-}" ]] && return 0
readonly _WIT_VERB_CLI_LOADED=1

# wit_usage_error <message> — name the file the call sits in and exit 2.
# shellcheck disable=SC2154  # EX_USAGE is a readonly constant of the sourcing adapter's common.sh
wit_usage_error() {
  printf '%s: %s\n' "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  exit "$EX_USAGE"
}

wit_help_if_requested() {
  local usage="$1"
  shift
  if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' "$usage"
    exit 0
  fi
}
