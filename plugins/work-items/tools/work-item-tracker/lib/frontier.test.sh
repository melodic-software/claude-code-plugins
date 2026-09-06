#!/usr/bin/env bash
# Tests for lib/frontier.sh — core-side frontier derivation over fixture JSON.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frontier.sh
source "$SCRIPT_DIR/frontier.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

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
assert_eq "autonomous frontier drops needs-human (default label)" "github:o/r#1" "$IDS"

# A repo that remaps config.role_labels["human-gated"] away from the default
# must have its remapped label honored, not the literal string "needs-human".
REMAPPED='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#5","state":"open","assignees":[],"labels":["needs-human"],"blocked_by_count":0},
    {"id":"github:o/r#6","state":"open","assignees":[],"labels":["do-not-auto-pick"],"blocked_by_count":0}
  ]
}'
OUT="$(wit_filter_frontier true "do-not-auto-pick" <<<"$REMAPPED")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "autonomous frontier drops the configured remap, not the stale default" \
  "github:o/r#1,github:o/r#5" "$IDS"

EMPTY='{"schema_version":"1.0","items":[]}'
OUT="$(wit_filter_frontier false <<<"$EMPTY")"
assert_eq "empty input yields empty frontier" "0" "$(jq '.items | length' <<<"$OUT")"

# Missing optional arrays tolerated (labels/assignees absent).
SPARSE='{"schema_version":"1.0","items":[{"id":"github:o/r#9","state":"open","blocked_by_count":0}]}'
OUT="$(wit_filter_frontier true <<<"$SPARSE")"
assert_eq "sparse item survives filters" "1" "$(jq '.items | length' <<<"$OUT")"

# Container exclusion: a container item (default work-map
# label) that is itself open/unassigned/unblocked must never surface as its own
# frontier item — unconditionally, not only under --autonomous.
CONTAINERS='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#10","state":"open","assignees":[],"labels":["work-map"],"blocked_by_count":0}
  ]
}'
OUT="$(wit_filter_frontier false <<<"$CONTAINERS")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "default frontier excludes the container (work-map)" "github:o/r#1" "$IDS"
OUT="$(wit_filter_frontier true <<<"$CONTAINERS")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "autonomous frontier also excludes the container" "github:o/r#1" "$IDS"

# A non-default container label passed explicitly is honored (parity with the
# human-gated remap path); the shipped default must not exclude once remapped.
REMAP_CONTAINER='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#10","state":"open","assignees":[],"labels":["work-map"],"blocked_by_count":0},
    {"id":"github:o/r#11","state":"open","assignees":[],"labels":["decision-map"],"blocked_by_count":0}
  ]
}'
OUT="$(wit_filter_frontier false "needs-human" "decision-map" <<<"$REMAP_CONTAINER")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "explicit container label excludes the remap, not the stale default" \
  "github:o/r#1,github:o/r#10" "$IDS"

# Human-floor work classes (labels.sh WIT_HUMAN_FLOOR_WORK_CLASS_LABELS): C4
# structural and C5 untrusted-provenance are human-gated regardless of any other
# signal, so the autonomous frontier must drop them EVEN WHEN the item also
# carries the autonomous-eligible role label. Before this filter existed such a
# contradictory item was claimed and then escalated once per lane instance.
WORK_CLASS='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":["agent-ready","work-class: scoped"],"blocked_by_count":0},
    {"id":"github:o/r#2","state":"open","assignees":[],"labels":["agent-ready","work-class: structural"],"blocked_by_count":0},
    {"id":"github:o/r#3","state":"open","assignees":[],"labels":["agent-ready","work-class: untrusted-provenance"],"blocked_by_count":0},
    {"id":"github:o/r#4","state":"open","assignees":[],"labels":["work-class: read-only"],"blocked_by_count":0},
    {"id":"github:o/r#5","state":"open","assignees":[],"labels":["work-class: mechanical"],"blocked_by_count":0}
  ]
}'
OUT="$(wit_filter_frontier true <<<"$WORK_CLASS")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "autonomous frontier drops C4/C5 even when agent-ready is present" \
  "github:o/r#1,github:o/r#4,github:o/r#5" "$IDS"

# The floor is an AUTONOMOUS-only exclusion: the attended lane must still see
# these items, otherwise a human-gated item becomes unreachable by every view.
OUT="$(wit_filter_frontier false <<<"$WORK_CLASS")"
IDS="$(jq -r '[.items[].id] | join(",")' <<<"$OUT")"
assert_eq "default frontier still surfaces C4/C5 for the attended lane" \
  "github:o/r#1,github:o/r#2,github:o/r#3,github:o/r#4,github:o/r#5" "$IDS"

# C3 scoped is deliberately NOT in the floor: its disposition depends on
# bug-fix-vs-feature shape and first-drain ratification, which the work-loop
# admission gate owns and no label carries. It must survive this filter.
SCOPED='{"schema_version":"1.0","items":[
  {"id":"github:o/r#7","state":"open","assignees":[],"labels":["work-class: scoped"],"blocked_by_count":0}]}'
assert_eq "C3 scoped is not floored by the frontier" "1" \
  "$(jq '.items | length' <<<"$(wit_filter_frontier true <<<"$SCOPED")")"

# Exact-match, not substring: a label that merely CONTAINS a floor member's text
# is a different label and must not be floored.
NEARMISS='{"schema_version":"1.0","items":[
  {"id":"github:o/r#8","state":"open","assignees":[],"labels":["work-class: structural-lite"],"blocked_by_count":0}]}'
assert_eq "floor matching is exact, not substring" "1" \
  "$(jq '.items | length' <<<"$(wit_filter_frontier true <<<"$NEARMISS")")"

[[ $FAILED -eq 0 ]] || exit 1
