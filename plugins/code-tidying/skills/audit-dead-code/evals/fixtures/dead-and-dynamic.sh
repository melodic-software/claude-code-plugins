#!/usr/bin/env bash
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
