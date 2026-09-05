#!/usr/bin/env bash
# Shipped role-label defaults — the seam's ONE definition source for the canonical-role
# label strings (label-taxonomy.md "Canonical roles"). A repo remaps them via binding
# config.role_labels (lib/binding.sh resolves configured-over-default); everything
# core-side reads the resolved WIT_*_LABEL exports or, absent a binding context, these
# constants. Never restate these literals elsewhere in the seam. Sourced.

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
# Container marker (CONTRACT.md "Containers and state") — not a canonical role
# (it marks a graph root, not worker eligibility) but remapped the same way:
# binding config.container_label, resolved configured-over-default.
# shellcheck disable=SC2034
readonly WIT_DEFAULT_CONTAINER_LABEL="work-map"

# Human-floor work classes: the work-class axis members whose admission
# disposition is human-gated REGARDLESS of any other signal — C4 structural and
# C5 untrusted-provenance (reference/work-class-labels.md; the admission-gate
# table in skills/work-loop/SKILL.md "Admission gate", which binds whether or
# not the autonomy plugin is installed). Carrying the autonomous-eligible role
# label does NOT lift the floor: the two contradict, and the frontier resolves
# the contradiction against the floor (lib/frontier.sh).
#
# Only the UNCONDITIONALLY human-gated classes belong here. C3 scoped is
# excluded on purpose: its disposition turns on bug-fix-vs-feature shape and on
# first-drain ratification, neither of which is readable from a label, so the
# work-loop admission gate — not this filter — owns it.
#
# These are fixed strings, not a remap seam: the work-class axis has no binding
# key (label-taxonomy.md "Work class"), unlike the canonical roles above.
# shellcheck disable=SC2034
readonly WIT_HUMAN_FLOOR_WORK_CLASS_LABELS=(
  "work-class: structural"
  "work-class: untrusted-provenance"
)
