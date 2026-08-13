#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKFILL="$SCRIPT_DIR/backfill-capability-tier-labels.sh"
LIB_TEST="$SCRIPT_DIR/lib/legacy-frontier-tier-signal.test.sh"

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1" >&2; }

chmod +x "$BACKFILL" "$LIB_TEST"

if bash "$LIB_TEST"; then
  pass "legacy signal unit tests"
else
  fail "legacy signal unit tests"
fi

# Offline: apply without gh should fail clearly.
if "$BACKFILL" apply --dry-run 2>/dev/null; then
  fail "apply without gh should not succeed"
else
  pass "apply without gh exits non-zero"
fi

if [[ "$FAILED" -eq 0 ]]; then
  exit 0
fi
exit 1
