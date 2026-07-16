#!/usr/bin/env bash
# Tests for lib/frontier.sh — core-side frontier derivation over fixture JSON.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frontier.sh
source "$SCRIPT_DIR/frontier.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

FIXTURE='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#2","state":"open","assignees":[],"labels":[],"blocked_by_count":2},
    {"id":"github:o/r#3","state":"open","assignees":["someone"],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#4","state":"closed","assignees":[],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#5","state":"open","assignees":[],"labels":["needs-human"],"blocked_by_count":0}
  ]
}'

OUT="$(wit_filter_frontier false <<<"$FIXTURE")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "default frontier keeps open+unblocked+unassigned" "github:o/r#1,github:o/r#5" "$IDS"
assert_eq "schema_version passthrough" "1.0" "$(jq -r '.schema_version' <<<"$OUT")"

OUT="$(wit_filter_frontier true <<<"$FIXTURE")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "autonomous frontier drops needs-human" "github:o/r#1" "$IDS"

EMPTY='{"schema_version":"1.0","items":[]}'
OUT="$(wit_filter_frontier false <<<"$EMPTY")"
assert_eq "empty input yields empty frontier" "0" "$(jq '.items | length' <<<"$OUT")"

# Missing optional arrays tolerated (labels/assignees absent).
SPARSE='{"schema_version":"1.0","items":[{"id":"github:o/r#9","state":"open","blocked_by_count":0}]}'
OUT="$(wit_filter_frontier true <<<"$SPARSE")"
assert_eq "sparse item survives filters" "1" "$(jq '.items | length' <<<"$OUT")"

[[ $FAILED -eq 0 ]] || exit 1
