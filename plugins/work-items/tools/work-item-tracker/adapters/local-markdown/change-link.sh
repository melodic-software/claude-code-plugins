#!/usr/bin/env bash
# change-link — CONTRACT.md "Change links". Offline. A local store has no forge
# integration, so merging a change closes nothing (closes: null); the link is a plain
# reference to the qualified id.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: change-link (<id> | --branch-ref <N>) [--repo <owner>/<repo>]" "$@"

wit_change_link_args "$@"
if [[ -n "$WIT_CL_REF" ]]; then
  [[ "$WIT_CL_REF" =~ ^[0-9]+$ ]] || wit_change_link_no_item "branch ref '$WIT_CL_REF' is not a local item number"
  # A local store has no forge, so the change's --repo is not the item namespace: a
  # branch names an item in the store's default namespace.
  WIT_CL_ID="local-markdown:$WIT_LOCAL_DEFAULT_NS#$WIT_CL_REF"
fi
wit_require_local_id "$WIT_CL_ID" ||
  wit_usage_error "malformed or non-local-markdown id: $WIT_CL_ID"

wit_emit_change_link "$WIT_CL_ID" "" "Refs: $WIT_CL_ID" "$WIT_ID_NUMBER"
