#!/usr/bin/env bash
# Tests for lib/frontier.sh — core-side frontier derivation over fixture JSON.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=frontier.sh
source "$SCRIPT_DIR/frontier.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

# frontier_ids <wit_filter_frontier args…>: stdin is an envelope, stdout the
# surviving item ids comma-joined (the shape nearly every case asserts).
frontier_ids() {
  wit_filter_frontier "$@" | jq -r '[.items[].id] | join(",")'
}

# frontier_count <wit_filter_frontier args…>: stdin is an envelope, stdout how
# many items survived.
frontier_count() {
  wit_filter_frontier "$@" | jq '.items | length'
}

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

IDS="$(frontier_ids false <<<"$FIXTURE")"
assert_eq "default frontier keeps open+unblocked+unassigned" "github:o/r#1,github:o/r#5" "$IDS"
SCHEMA="$(wit_filter_frontier false <<<"$FIXTURE" | jq -r '.schema_version')"
assert_eq "schema_version passthrough" "1.0" "$SCHEMA"

IDS="$(frontier_ids true <<<"$FIXTURE")"
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
IDS="$(frontier_ids true "do-not-auto-pick" <<<"$REMAPPED")"
assert_eq "autonomous frontier drops the configured remap, not the stale default" \
  "github:o/r#1,github:o/r#5" "$IDS"

EMPTY='{"schema_version":"1.0","items":[]}'
COUNT="$(frontier_count false <<<"$EMPTY")"
assert_eq "empty input yields empty frontier" "0" "$COUNT"

# Missing optional arrays tolerated (labels/assignees absent).
SPARSE='{"schema_version":"1.0","items":[{"id":"github:o/r#9","state":"open","blocked_by_count":0}]}'
COUNT="$(frontier_count true <<<"$SPARSE")"
assert_eq "sparse item survives filters" "1" "$COUNT"

# An open, unassigned, unblocked container item never surfaces as its own frontier
# item, unconditionally, not only under --autonomous.
CONTAINERS='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":[],"blocked_by_count":0},
    {"id":"github:o/r#10","state":"open","assignees":[],"labels":["work-map"],"blocked_by_count":0}
  ]
}'
IDS="$(frontier_ids false <<<"$CONTAINERS")"
assert_eq "default frontier excludes the container (work-map)" "github:o/r#1" "$IDS"
IDS="$(frontier_ids true <<<"$CONTAINERS")"
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
IDS="$(frontier_ids false "needs-human" "decision-map" <<<"$REMAP_CONTAINER")"
assert_eq "explicit container label excludes the remap, not the stale default" \
  "github:o/r#1,github:o/r#10" "$IDS"

# The autonomous frontier drops human-floor work classes (C4, C5) EVEN WHEN the item
# also carries the autonomous-eligible role label.
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
IDS="$(frontier_ids true <<<"$WORK_CLASS")"
assert_eq "autonomous frontier drops C4/C5 even when agent-ready is present" \
  "github:o/r#1,github:o/r#4,github:o/r#5" "$IDS"

# The floor is an AUTONOMOUS-only exclusion: the attended lane must still see
# these items, otherwise a human-gated item becomes unreachable by every view.
IDS="$(frontier_ids false <<<"$WORK_CLASS")"
assert_eq "default frontier still surfaces C4/C5 for the attended lane" \
  "github:o/r#1,github:o/r#2,github:o/r#3,github:o/r#4,github:o/r#5" "$IDS"

# C3 scoped is deliberately NOT in the floor (the admission gate owns it), so it
# must survive this filter.
SCOPED='{"schema_version":"1.0","items":[
  {"id":"github:o/r#7","state":"open","assignees":[],"labels":["work-class: scoped"],"blocked_by_count":0}]}'
COUNT="$(frontier_count true <<<"$SCOPED")"
assert_eq "C3 scoped is not floored by the frontier" "1" "$COUNT"

# Exact-match, not substring: a label that merely CONTAINS a floor member's text
# is a different label and must not be floored.
NEARMISS='{"schema_version":"1.0","items":[
  {"id":"github:o/r#8","state":"open","assignees":[],"labels":["work-class: structural-lite"],"blocked_by_count":0}]}'
COUNT="$(frontier_count true <<<"$NEARMISS")"
assert_eq "floor matching is exact, not substring" "1" "$COUNT"

[[ $FAILED -eq 0 ]] || exit 1
