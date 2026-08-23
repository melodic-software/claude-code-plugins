#!/usr/bin/env bash
# Paired discrimination fixture for the grep (shell) lane.
#
# format_legacy_row is a dead FUNCTION on purpose: a dead shell VARIABLE would
# fire SC2034 under this repository's unconditional whole-repo shellcheck step,
# so the fixture could not be committed. handle_alpha is the trap -- it is
# called only through the indirect expansion in main, which `grep -w -F` cannot
# see, so the lane misses the reference and reads it as dead.
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
