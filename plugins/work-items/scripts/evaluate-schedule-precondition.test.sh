#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL="$SCRIPT_DIR/evaluate-schedule-precondition.sh"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

cat >"$TMP" <<'JSON'
{
  "items": [
    {
      "id": "demo",
      "title": "Demo",
      "precondition": {
        "id": "frontier-release-since-last-checked",
        "prompt": "confirm release",
        "requires_operator_confirmation": true
      }
    },
    {
      "id": "plain",
      "title": "Plain"
    }
  ]
}
JSON

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FAIL: %s\n' "$1" >&2; }

chmod +x "$EVAL"
out="$("$EVAL" "$TMP" plain)"
if [[ "$out" == "no-precondition" ]]; then
  pass "plain row has no precondition"
else
  fail "plain row"
fi

rc=0
if ! "$EVAL" "$TMP" demo >/dev/null 2>&1; then
  rc=$?
fi
if [[ "$rc" -eq 2 ]]; then
  pass "confirmation precondition needs operator"
else
  fail "confirmation precondition exit=$rc"
fi

rc=0
out=""
if out="$("$EVAL" "$TMP" demo --operator-confirmed)"; then
  :
else
  rc=$?
fi
if [[ "$rc" -eq 0 && "$out" == "met" ]]; then
  pass "operator confirmation satisfies precondition"
else
  fail "confirmed path"
fi

if [[ "$FAILED" -eq 0 ]]; then
  exit 0
fi
exit 1
