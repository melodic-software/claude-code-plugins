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
[[ "$out" == "no-precondition" ]] && pass "plain row has no precondition" || fail "plain row"

rc=0
"$EVAL" "$TMP" demo >/dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] && pass "confirmation precondition needs operator" || fail "confirmation precondition exit=$rc"

rc=0
out="$("$EVAL" "$TMP" demo --operator-confirmed)" || rc=$?
[[ "$rc" -eq 0 && "$out" == "met" ]] && pass "operator confirmation satisfies precondition" || fail "confirmed path"

[[ "$FAILED" -eq 0 ]] && exit 0
exit 1
