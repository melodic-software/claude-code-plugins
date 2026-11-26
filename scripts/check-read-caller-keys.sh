#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v node >/dev/null 2>&1; then
  printf 'check-read-caller-keys: node is not on PATH\n' >&2
  exit 2
fi
exec node "$SCRIPT_DIR/check-read-caller-keys.mjs"
