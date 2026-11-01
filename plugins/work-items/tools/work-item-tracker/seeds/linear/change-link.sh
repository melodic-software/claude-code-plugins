#!/usr/bin/env bash
# change-link — CONTRACT.md "Change links". Offline: no request is made. Linear's
# GitHub integration closes an issue on merge for a closing magic word ("Closes
# ENG-123") and links without closing for a non-closing one ("Refs ENG-123").
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: change-link (<id> | --branch-ref <TEAM-N>)  (id: linear:<workspace>/<TEAMKEY>#<number>)" "$@"

wit_change_link_args "$@"
if [[ -n "$WIT_CL_REF" ]]; then
  # Linear's own branch names carry the identifier in lower case.
  ref="$(printf '%s' "$WIT_CL_REF" | tr '[:lower:]' '[:upper:]')"
  [[ "$ref" =~ ^([A-Z][A-Z0-9]*)-([0-9]+)$ ]] ||
    wit_change_link_no_item "branch ref '$WIT_CL_REF' is not a Linear issue identifier (TEAM-number)"
  team="${BASH_REMATCH[1]}" number="${BASH_REMATCH[2]}"
  # The workspace comes from the binding, and its scopes are the declared boundary.
  wit_need_linear_config
  workspace="$(jq -r '.[0] | split("/")[0]' <<<"$WIT_LINEAR_SCOPES")"
  wit_linear_scope_in_scope "$workspace/$team" ||
    wit_change_link_no_item "team '$team' is not in the binding's config.linear.scopes"
  WIT_CL_ID="linear:$workspace/$team#$number"
fi
wit_require_linear_id "$WIT_CL_ID" ||
  wit_usage_error "malformed or non-linear id: $WIT_CL_ID (expected linear:<workspace>/<TEAMKEY>#<number>)"

identifier="$WIT_ID_REPO-$WIT_ID_NUMBER"
wit_emit_change_link "$WIT_CL_ID" "Closes $identifier" "Refs $identifier" "$identifier"
