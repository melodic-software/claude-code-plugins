#!/usr/bin/env bash

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
# shellcheck disable=SC2034
readonly WIT_DEFAULT_OWNER_DECISION_LABEL="needs-owner-decision"
# shellcheck disable=SC2034
readonly WIT_DEFAULT_SESSION_OWNED_LABEL="session-owned"
# shellcheck disable=SC2034
readonly WIT_DEFAULT_CONTAINER_LABEL="spec-container"

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

# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_STATUS_STATES=(
  "needs-human"
  "needs-owner-decision"
  "needs-reporter-info"
  "needs-spec"
)

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
