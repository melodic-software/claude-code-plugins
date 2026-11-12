#!/usr/bin/env bash
# Verb CLI helpers every adapter verb script uses for --help and usage errors. Sourced.

[[ -n "${_WIT_VERB_CLI_LOADED:-}" ]] && return 0
readonly _WIT_VERB_CLI_LOADED=1

# wit_usage_error <message> — name the file the call sits in and exit 2.
# shellcheck disable=SC2154  # EX_USAGE is a readonly constant of the sourcing adapter's common.sh
wit_usage_error() {
  printf '%s: %s\n' "$(basename "${BASH_SOURCE[1]}")" "$1" >&2
  exit "$EX_USAGE"
}

# wit_help_if_requested <usage-text> <args…> — print usage + exit 0 when the first
# arg is --help. Adapter verbs are dispatched by the core, but each is a standalone
# entry script (skill-script contract) and answers --help directly.
wit_help_if_requested() {
  local usage="$1"
  shift
  if [[ "${1:-}" == "--help" ]]; then
    printf '%s\n' "$usage"
    exit 0
  fi
}
