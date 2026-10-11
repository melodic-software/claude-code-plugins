#!/usr/bin/env bash
# change-link — CONTRACT.md "Change links". Offline: GitHub's closing-keyword text for an
# item, and the issue number a branch name carries.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: change-link (<id> | --branch-ref <N>) [--repo <owner>/<repo>]" "$@"

wit_change_link_args "$@"
if [[ -n "$WIT_CL_REF" ]]; then
  [[ "$WIT_CL_REF" =~ ^[0-9]+$ ]] || wit_change_link_no_item "branch ref '$WIT_CL_REF' is not a GitHub issue number"
  [[ -n "$WIT_CL_REPO" ]] || wit_usage_error "--branch-ref needs --repo <owner>/<repo>"
  WIT_CL_ID="github:$WIT_CL_REPO#$WIT_CL_REF"
fi
wit_require_github_id "$WIT_CL_ID" ||
  wit_usage_error "malformed or non-github id: $WIT_CL_ID (expected github:<owner>/<repo>#<number>)"

ref="$(wit_hash_ref "$WIT_CL_REPO")"
wit_emit_change_link "$WIT_CL_ID" "Closes $ref" "Refs: $ref" "$WIT_ID_NUMBER"
