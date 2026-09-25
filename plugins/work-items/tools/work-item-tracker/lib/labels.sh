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

# Human-floor work classes: human-gated even beside the autonomous-eligible label
# (reference/work-class-labels.md). Fixed strings; the work-class axis has no binding key.
#
# C3 scoped is excluded: its disposition is not readable from a label, so the
# work-loop admission gate owns it.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_WORK_CLASS_LABELS=(
  "work-class: structural"
  "work-class: untrusted-provenance"
)
