#!/usr/bin/env bash
# Discovery wrapper for merge-risk-failures.test.mjs: run-plugin-tests.sh discovers only *.test.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

node --test "$SELF_DIR/merge-risk-failures.test.mjs"
