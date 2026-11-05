#!/usr/bin/env bash
# Shipped role-label defaults (label-taxonomy.md "Canonical roles"), remapped by binding
# config.role_labels in lib/binding.sh. Never restate these literals elsewhere. Sourced.

[[ -n "${_WIT_LABELS_LOADED:-}" ]] && return 0
readonly _WIT_LABELS_LOADED=1

# Consumed by sourcing files (lib/binding.sh, lib/frontier.sh), not within this
# file — SC2034 is a false positive on a sourced-only constants file.
# shellcheck disable=SC2034
readonly WIT_DEFAULT_HUMAN_GATED_LABEL="needs-human"
# shellcheck disable=SC2034
readonly WIT_DEFAULT_AUTONOMOUS_ELIGIBLE_LABEL="agent-ready"
# shellcheck disable=SC2034
readonly WIT_DEFAULT_RECURRING_MAINTENANCE_LABEL="recurring"
# Container marker (CONTRACT.md "Containers and state"): not a canonical role, but
# remapped the same way through binding config.container_label.
# shellcheck disable=SC2034
readonly WIT_DEFAULT_CONTAINER_LABEL="work-map"

# `/planning:wayfind` owns every item carrying a label with this prefix (its map
# items), so the frontier never surfaces one. Fixed prefix, no binding key.
# shellcheck disable=SC2034
readonly WIT_WAYFIND_LABEL_PREFIX="wayfind:"

# Human-floor work class: human-gated even beside the autonomous-eligible label
# (reference/work-class-labels.md). Fixed string; the work-class axis has no binding key.
# No work class floors an item now; the one entry is the legacy name of the
# untrusted-provenance marker, held until the label source drops it.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_WORK_CLASS_LABELS=(
  "work-class: untrusted-provenance" # legacy name of provenance: untrusted
)

# The human floor holds provenance labels as well as work classes: an item marked
# untrusted, or filed from a signal, is C5 whatever its work-class label says.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_PROVENANCE_LABELS=(
  "provenance: untrusted"
  "provenance: signal"
)

# An item waiting on an owner decision, on information or on a spec is not
# workable by an autonomous lane, whatever else it carries. Fixed strings, no
# binding key. needs-spec is a bare Meta label, not a status: value.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_STATUS_LABELS=(
  "status: needs-decision"
  "status: needs-info"
  "needs-spec"
)

# The Work status field's states that hold an item for a person, added to the
# label floor when the tracker stores status in that field (CONTRACT.md "Verbs",
# list-frontier). Option names of the field; no binding key.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_STATUS_STATES=(
  "needs-human"
  "needs-owner-decision"
  "needs-reporter-info"
  "needs-spec"
)

# The labels of those states. An item carrying one already has its hold decided by
# its labels, so the field adds none (needs-owner-decision floors only through the
# field's hold, never through its bare label, as before the field was read).
# shellcheck disable=SC2034
readonly WIT_HOLD_STATE_LABELS=(
  "needs-human"
  "status: needs-decision"
  "needs-owner-decision"
  "status: needs-info"
  "needs-spec"
)
