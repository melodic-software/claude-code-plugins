#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

USAGE="usage: link-relates <id> --related-to <id>"
wit_help_if_requested "$USAGE" "$@"
wit_parse_edge_args "$USAGE" related-to "$@"

wit_gh_mutate_relates link-relates addRelatesTo \
  "$WIT_EDGE_ID" "$WIT_EDGE_OWNER" "$WIT_EDGE_REPO" "$WIT_EDGE_NUMBER" \
  "$WIT_EDGE_OTHER" "$WIT_EDGE_OTHER_OWNER" "$WIT_EDGE_OTHER_REPO" "$WIT_EDGE_OTHER_NUMBER"
