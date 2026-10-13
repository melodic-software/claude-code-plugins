#!/usr/bin/env bash
# Tests for lib/json.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=json.sh
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

OUT="$(printf 'line1\r\nline2\r\n' | wit_strip_cr)"
assert_eq "CR stripped" "$(printf 'line1\nline2\n')" "$OUT"
assert_not_contains "no CR remains" "$OUT" "$(printf '\r')"

assert_eq "schema version constant" "1.0" "$WIT_SCHEMA_VERSION"

# created_at normalization: each provider's own timestamp shape becomes UTC with second
# precision, so timestamps from one adapter sort as text. Expected values are the input
# instants shifted to UTC by hand.
utc() { jq -c "$WIT_JQ_DEF_UTC_TS map(wit_utc_ts)" <<<"$1"; }
assert_eq "github Z form passes through" '["2026-01-02T03:04:05Z"]' "$(utc '["2026-01-02T03:04:05Z"]')"
assert_eq "linear fractional seconds are dropped" '["2026-01-02T03:04:05Z"]' "$(utc '["2026-01-02T03:04:05.123Z"]')"
assert_eq "jira -0500 offset shifts forward to UTC" '["2026-01-02T08:04:05Z"]' "$(utc '["2026-01-02T03:04:05.000-0500"]')"
assert_eq "gitea +08:00 offset shifts back across midnight" '["2026-01-01T19:04:05Z"]' "$(utc '["2026-01-02T03:04:05+08:00"]')"
assert_eq "unparsable, null and non-string values become null, one each" '[null,null,null]' \
  "$(utc '["yesterday",null,5]')"

[[ $FAILED -eq 0 ]] || exit 1
