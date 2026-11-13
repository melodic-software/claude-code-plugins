#!/usr/bin/env bash
# Shipped label defaults (label-taxonomy.md "Canonical roles"), remapped by binding
# config keys in lib/binding.sh. Never restate these literals elsewhere. Sourced.

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
# The owner-decision role: an item parked on an owner's decision. Remapped through
# config.role_labels["owner-decision"]; a remap replaces this entry in the hold
# label defaults below (lib/binding.sh).
# shellcheck disable=SC2034
readonly WIT_DEFAULT_OWNER_DECISION_LABEL="needs-owner-decision"
# Container marker (CONTRACT.md "Containers and state"): not a canonical role, but
# remapped the same way through binding config.container_label.
# shellcheck disable=SC2034
readonly WIT_DEFAULT_CONTAINER_LABEL="spec-container"

# `/planning:wayfind` owns every item carrying a label with this prefix (its map
# items), so the frontier never surfaces one. Remapped through binding
# config.wayfind_label_prefix.
# shellcheck disable=SC2034
readonly WIT_WAYFIND_LABEL_PREFIX="wayfind:"

# The human floor holds provenance labels (reference/work-class-labels.md): an item
# marked untrusted, or filed from a signal, is C5 whatever its work-class label says.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_PROVENANCE_LABELS=(
  "provenance: untrusted"
  "provenance: signal"
)

# An item waiting on an owner decision, on information or on a spec is not
# workable by an autonomous lane, whatever else it carries. Defaults of binding
# config.hold_labels. needs-spec is a bare Meta label, not a status: value.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_STATUS_LABELS=(
  "$WIT_DEFAULT_OWNER_DECISION_LABEL"
  "needs-reporter-info"
  "needs-spec"
)

# The Work status field's states that hold an item for a person, added to the
# label floor when the tracker stores status in that field (CONTRACT.md "Verbs",
# list-frontier). Option names of the field; defaults of binding config.hold_states.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_STATUS_STATES=(
  "needs-human"
  "needs-owner-decision"
  "needs-reporter-info"
  "needs-spec"
)

# The labels of those states. An item carrying one already has its hold decided by
# its labels, so the field adds none.
# Defaults of binding config.hold_state_labels.
# shellcheck disable=SC2034
readonly WIT_HOLD_STATE_LABELS=(
  "needs-human"
  "$WIT_DEFAULT_OWNER_DECISION_LABEL"
  "needs-reporter-info"
  "needs-spec"
)

# The Work status state that admits an item to an autonomous lane, which only a
# person's value counts for under the GitHub adapter's Work status trust. The
# trust model's models.issue-status.ready-state remaps it.
# shellcheck disable=SC2034
readonly WIT_DEFAULT_READY_STATE="agent-ready"
