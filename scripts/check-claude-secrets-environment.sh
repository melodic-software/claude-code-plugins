#!/usr/bin/env bash
# Usage: check-claude-secrets-environment.sh [--check]. The rule, why it holds,
# and the exit contract (0 clean, 1 any offender, 2 usage or environment):
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#claude-secrets
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
  printf 'check-claude-secrets-environment: node is not on PATH\n' >&2
  exit 2
fi
exec node "$SCRIPT_DIR/check-claude-secrets-environment.mjs"
