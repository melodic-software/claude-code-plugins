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

# `truncated` describes the listing, not the filter: an empty frontier over a
# truncated listing is still truncated, and a listing that never carried the flag
# (an adapter predating it) must not gain a `false` that reads as complete.
TRUNC='{"schema_version":"1.0","items":[{"id":"github:o/r#4","state":"closed","blocked_by_count":0}],"truncated":true}'
assert_eq "a truncated listing filtered to nothing stays truncated" "true" \
  "$(wit_filter_frontier false <<<"$TRUNC" | jq -c '.truncated')"
assert_eq "a complete listing reports truncated:false" "false" \
  "$(wit_filter_frontier true <<<'{"schema_version":"1.0","items":[],"truncated":false}' | jq -c '.truncated')"
assert_eq "a listing without the flag yields a frontier without it" "false" \
  "$(wit_filter_frontier false <<<"$EMPTY" | jq -c 'has("truncated")')"

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

# A wayfind map item (any `wayfind:` label) belongs to /planning:wayfind, so neither
# frontier surfaces it; a label that only contains the text elsewhere still does.
WAYFIND='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":["agent-ready"],"blocked_by_count":0},
    {"id":"github:o/r#12","state":"open","assignees":[],"labels":["agent-ready","wayfind: research"],"blocked_by_count":0},
    {"id":"github:o/r#13","state":"open","assignees":[],"labels":["wayfind: task"],"blocked_by_count":0},
    {"id":"github:o/r#14","state":"open","assignees":[],"labels":["area: wayfind:"],"blocked_by_count":0}
  ]
}'
IDS="$(frontier_ids false <<<"$WAYFIND")"
assert_eq "default frontier excludes wayfind: items" "github:o/r#1,github:o/r#14" "$IDS"
IDS="$(frontier_ids true <<<"$WAYFIND")"
assert_eq "autonomous frontier excludes wayfind: items even when agent-ready" \
  "github:o/r#1,github:o/r#14" "$IDS"
# A hand-edited local-markdown item can carry a non-string label; the prefix check skips it.
COUNT="$(frontier_count false <<<'{"schema_version":"1.0","items":[{"id":"local:a#1","state":"open","labels":[1],"blocked_by_count":0}]}')"
assert_eq "a non-string label does not fail the wayfind check" "1" "$COUNT"

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

# The autonomous frontier drops only the untrusted-provenance work class, EVEN WHEN
# the item also carries the autonomous-eligible role label. A structural item and
# an item with no class stay listed: work class is not an admission gate.
WORK_CLASS='{
  "schema_version": "1.0",
  "items": [
    {"id":"github:o/r#1","state":"open","assignees":[],"labels":["agent-ready","work-class: scoped"],"blocked_by_count":0},
    {"id":"github:o/r#2","state":"open","assignees":[],"labels":["agent-ready","work-class: structural"],"blocked_by_count":0},
    {"id":"github:o/r#3","state":"open","assignees":[],"labels":["agent-ready","work-class: untrusted-provenance"],"blocked_by_count":0},
    {"id":"github:o/r#4","state":"open","assignees":[],"labels":["work-class: read-only"],"blocked_by_count":0},
    {"id":"github:o/r#5","state":"open","assignees":[],"labels":["work-class: mechanical"],"blocked_by_count":0},
    {"id":"github:o/r#12","state":"open","assignees":[],"labels":["agent-ready"],"blocked_by_count":0}
  ]
}'
IDS="$(frontier_ids true <<<"$WORK_CLASS")"
assert_eq "autonomous frontier lists structural and unclassified agent-ready items, drops untrusted-provenance" \
  "github:o/r#1,github:o/r#2,github:o/r#4,github:o/r#5,github:o/r#12" "$IDS"

# The floor is an AUTONOMOUS-only exclusion: the attended lane must still see
# these items, otherwise a human-gated item becomes unreachable by every view.
IDS="$(frontier_ids false <<<"$WORK_CLASS")"
assert_eq "default frontier still surfaces untrusted-provenance for the attended lane" \
  "github:o/r#1,github:o/r#2,github:o/r#3,github:o/r#4,github:o/r#5,github:o/r#12" "$IDS"

# A signal-filed item is C5 by rule: the provenance label floors it whatever its
# work-class label says, and the attended lane still sees it.
SIGNAL='{"schema_version":"1.0","items":[
  {"id":"github:o/r#1","state":"open","assignees":[],"labels":["agent-ready","work-class: scoped"],"blocked_by_count":0},
  {"id":"github:o/r#6","state":"open","assignees":[],"labels":["agent-ready","work-class: scoped","provenance: signal"],"blocked_by_count":0}]}'
IDS="$(frontier_ids true <<<"$SIGNAL")"
assert_eq "autonomous frontier drops provenance: signal even when agent-ready and scoped" \
  "github:o/r#1" "$IDS"
IDS="$(frontier_ids false <<<"$SIGNAL")"
assert_eq "default frontier still surfaces a provenance: signal item" \
  "github:o/r#1,github:o/r#6" "$IDS"

# A status label that waits on a person floors the item too, and the attended lane
# still sees it.
STATUS='{"schema_version":"1.0","items":[
  {"id":"github:o/r#1","state":"open","assignees":[],"labels":["agent-ready","work-class: scoped"],"blocked_by_count":0},
  {"id":"github:o/r#9","state":"open","assignees":[],"labels":["agent-ready","status: needs-decision"],"blocked_by_count":0},
  {"id":"github:o/r#10","state":"open","assignees":[],"labels":["agent-ready","status: needs-info"],"blocked_by_count":0},
  {"id":"github:o/r#11","state":"open","assignees":[],"labels":["needs-spec"],"blocked_by_count":0}]}'
IDS="$(frontier_ids true <<<"$STATUS")"
assert_eq "autonomous frontier drops status: needs-decision and needs-info even when agent-ready, and a parked needs-spec item" \
  "github:o/r#1" "$IDS"
IDS="$(frontier_ids false <<<"$STATUS")"
assert_eq "default frontier still surfaces status: needs-decision, needs-info and needs-spec items" \
  "github:o/r#1,github:o/r#9,github:o/r#10,github:o/r#11" "$IDS"

# C3 scoped is not in the floor, so it must survive this filter.
SCOPED='{"schema_version":"1.0","items":[
  {"id":"github:o/r#7","state":"open","assignees":[],"labels":["work-class: scoped"],"blocked_by_count":0}]}'
COUNT="$(frontier_count true <<<"$SCOPED")"
assert_eq "C3 scoped is not floored by the frontier" "1" "$COUNT"

# Exact-match, not substring: a label that merely CONTAINS a floor member's text
# is a different label and must not be floored.
NEARMISS='{"schema_version":"1.0","items":[
  {"id":"github:o/r#8","state":"open","assignees":[],"labels":["work-class: untrusted-provenance-lite"],"blocked_by_count":0}]}'
COUNT="$(frontier_count true <<<"$NEARMISS")"
assert_eq "floor matching is exact, not substring" "1" "$COUNT"

# --- wit_filter_label: exact label match, envelope keys untouched ---
LABELED='{"schema_version":"1.0","truncated":true,"items":[
  {"id":"github:o/r#1","labels":["area: ci"]},
  {"id":"github:o/r#2","labels":["Area: CI"]},
  {"id":"github:o/r#3","labels":["area: ci-extra","area: ci"]},
  {"id":"github:o/r#4","labels":["area: ci-extra"]},
  {"id":"github:o/r#5"}]}'
assert_eq "label filter keeps only exact matches" "github:o/r#1,github:o/r#3" \
  "$(wit_filter_label "area: ci" <<<"$LABELED" | jq -r '[.items[].id] | join(",")')"
assert_eq "label filter passes truncated through" "true" \
  "$(wit_filter_label "area: ci" <<<"$LABELED" | jq -c '.truncated')"

[[ $FAILED -eq 0 ]] || exit 1
