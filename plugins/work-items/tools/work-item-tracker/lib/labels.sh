#!/usr/bin/env bash

[[ -n "${_WIT_LABELS_LOADED:-}" ]] && return 0
readonly _WIT_LABELS_LOADED=1

# SC2034 is a false positive on a sourced-only constants file.
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

# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_PROVENANCE_LABELS=(
  "provenance: untrusted"
  "provenance: signal"
)

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

# shellcheck disable=SC2034
readonly WIT_DEFAULT_READY_STATE="agent-ready"
