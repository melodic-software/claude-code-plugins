#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SELF_DIR/lane-record.test.mjs"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

if [[ ! -f "$SUITE" ]]; then
  echo "FAIL: missing suite $SUITE" >&2
  exit 1
fi

node "$SUITE"
