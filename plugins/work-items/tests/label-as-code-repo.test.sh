#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SELF_DIR/.." && pwd)"
PARSE="$PLUGIN_ROOT/skills/triage/scripts/parse-concern-value.sh"
SCHEMA="$PLUGIN_ROOT/schemas/work-items.schema.json"
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
printf 'label_as_code_repo: acme/labels-iac\n' >"$TMP/set.yaml"
check "absent: no label-as-code owner is declared" "" "$(bash "$PARSE" "$TMP/absent.yaml" label_as_code_repo)"
check "set: the owner repository is read" "acme/labels-iac" "$(bash "$PARSE" "$TMP/set.yaml" label_as_code_repo)"
check "no file: no owner" "" "$(bash "$PARSE" "$TMP/missing.yaml" label_as_code_repo)"
check "the schema declares label_as_code_repo" "true" "$(jq '.properties | has("label_as_code_repo")' "$SCHEMA")"
check "the schema declares the Lanes keys" "true true" \
  "$(jq -r '.properties.morning_brief.properties | [has("lane_workflows"), has("lane_outcome_contract_ref")] | map(tostring) | join(" ")' "$SCHEMA")"

printf '%s: %d passed, %d failed\n' "${BASH_SOURCE[0]##*/}" "$PASS" "$FAIL"
((FAIL == 0))
