#!/usr/bin/env bash
# Contract smoke for audit-scan.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/audit-scan.sh"
FIX="$SCRIPT_DIR/../evals/fixtures"

PASS=0
FAIL=0
ok() { echo "ok: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

out="$(bash "$SCAN" "$FIX/terse-agent.md" 2>/dev/null)" || true
case "$out" in
*'| SKIP |'*) ok "terse-agent classifies SKIP" ;;
*) fail "terse-agent classifies SKIP (got: $out)" ;;
esac

out2="$(bash "$SCAN" "$FIX/audit-fixture-dir/verbose.md" 2>/dev/null)" || true
case "$out2" in
*'| COMPRESS |'*) ok "verbose fixture classifies COMPRESS" ;;
*) fail "verbose fixture classifies COMPRESS (got: $out2)" ;;
esac

out3="$(bash "$SCAN" "$FIX/audit-fixture-dir/lean.md" 2>/dev/null)" || true
case "$out3" in
*'| SKIP |'*) ok "lean fixture classifies SKIP" ;;
*) fail "lean fixture classifies SKIP (got: $out3)" ;;
esac

if [[ $FAIL -ne 0 ]]; then
  echo "$FAIL check(s) failed." >&2
  exit 1
fi
echo "OK: audit-scan.sh tests passed ($PASS checks)"
