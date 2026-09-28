#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-publisher-token-alignment.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

if bash "$SCRIPT" >/dev/null 2>&1; then
  ok "real token files align"
else
  fail "real token files should align"
fi

test_harness::report
