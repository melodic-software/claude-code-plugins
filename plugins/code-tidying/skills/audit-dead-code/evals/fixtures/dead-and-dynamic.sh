#!/usr/bin/env bash
# Paired discrimination fixture for the grep (shell) lane.
#
# Two of the functions below are unreferenced by any literal search. The first
# is genuinely dead. The second is the trap: it is reached only through the
# handler name constructed in main, which `grep -w -F` cannot see, so the lane
# misses that reference and reads it as dead too. Separating the two is
# adjudication's job, not the lane's.
#
# They are FUNCTIONS, not variables, on purpose: a dead shell VARIABLE would
# fire SC2034 under this repository's unconditional whole-repo shellcheck step,
# so the fixture could not be committed.
#
# This file must NEVER spell either function's name anywhere but its own
# definition line. The lane's reference search is repository-wide and literal,
# so one prose mention of an identifier counts as a reference and saves the very
# symbol the fixture exists to condemn -- which is exactly what the original
# header comment here did, yielding zero candidates from a fixture built to
# produce two.
set -euo pipefail

format_legacy_row() {
  printf '%s\n' "$*"
}

handle_alpha() {
  printf 'alpha:%s\n' "${1:-}"
}

main() {
  local kind="${1:-alpha}"
  local handler="handle_${kind}"
  "$handler" "${2:-}"
}

main "$@"
