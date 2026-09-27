#!/usr/bin/env bash
# link-blocks <id> --blocked-by <id> — CONTRACT.md "Verbs (core public surface)".
# Cross-repo edges supported (blocker URL form). Provider ceilings map to exit 7.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

USAGE="usage: link-blocks <id> --blocked-by <id>"
wit_help_if_requested "$USAGE" "$@"
wit_parse_edge_args "$USAGE" blocked-by "$@"

wit_run_gh write issue edit "$WIT_EDGE_NUMBER" -R "$WIT_EDGE_OWNER/$WIT_EDGE_REPO" --add-blocked-by "$WIT_EDGE_OTHER_URL"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$WIT_EDGE_ID" --arg blocker "$WIT_EDGE_OTHER" \
  '{schema_version: $sv, id: $id, blocked_by: $blocker, linked: true}'
