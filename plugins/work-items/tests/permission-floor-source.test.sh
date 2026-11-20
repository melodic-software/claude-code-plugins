#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/.." && pwd)"
PARSE="$PLUGIN_ROOT/skills/triage/scripts/parse-concern-value.sh"
SCHEMA="$PLUGIN_ROOT/schemas/work-items.schema.json"
DOC="$PLUGIN_ROOT/reference/permission-preflight.md"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
check() {
  if [[ "$2" == "$3" ]]; then
    printf 'PASS: %s\n' "$1"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s\n  expected: %q\n  got: %q\n' "$1" "$2" "$3" >&2
    FAIL=$((FAIL + 1))
  fi
}

printf 'filing_posture: allowed\n' >"$TMP/absent.yaml"
printf 'permission_floor_source: https://example.com/acme/permissions-floor\n' >"$TMP/set.yaml"
check "absent: no shared floor is configured" "" "$(bash "$PARSE" "$TMP/absent.yaml" permission_floor_source)"
check "set: the floor location is read" "https://example.com/acme/permissions-floor" \
  "$(bash "$PARSE" "$TMP/set.yaml" permission_floor_source)"
check "no file: no floor" "" "$(bash "$PARSE" "$TMP/missing.yaml" permission_floor_source)"
check "the schema declares permission_floor_source" "true" "$(jq '.properties | has("permission_floor_source")' "$SCHEMA")"
check "the preflight doc reads the key and states the unset case" "2" \
  "$(grep -c -e 'parse-concern-value.sh" docs/conventions/work-items.yaml permission_floor_source' -e 'no shared floor is configured' "$DOC")"

printf '%s: %d passed, %d failed\n' "${BASH_SOURCE[0]##*/}" "$PASS" "$FAIL"
((FAIL == 0))
