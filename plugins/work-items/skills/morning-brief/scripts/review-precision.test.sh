#!/usr/bin/env bash
# Discovery wrapper for review-precision.test.mjs: run-plugin-tests.sh discovers only *.test.sh,
# so the cases live in the .mjs file and this only runs node and forwards its exit status.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

node --test "$SELF_DIR/review-precision.test.mjs"
