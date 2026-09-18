#!/usr/bin/env bash
# add-sub-item <id> --parent <id> — CONTRACT.md "Verbs (core public surface)".
# Provider ceilings (100 sub-items/parent, 8 levels) map to exit 7.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

USAGE="usage: add-sub-item <id> --parent <id>"
wit_help_if_requested "$USAGE" "$@"
wit_parse_edge_args "$USAGE" parent "$@"

wit_run_gh write issue edit "$WIT_EDGE_NUMBER" -R "$WIT_EDGE_OWNER/$WIT_EDGE_REPO" --parent "$WIT_EDGE_OTHER_URL"

jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$WIT_EDGE_ID" --arg parent "$WIT_EDGE_OTHER" \
  '{schema_version: $sv, id: $id, parent_id: $parent, linked: true}'
