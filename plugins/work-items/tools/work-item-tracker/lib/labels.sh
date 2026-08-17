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
