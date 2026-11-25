#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

USAGE='usage: get-item.sh <id>'
wit_help_if_requested "$USAGE" "$@"

ID="${1:-}"
[[ -n "$ID" ]] || wit_usage_error "$USAGE"
shift
[[ $# -eq 0 ]] || wit_usage_error "unexpected argument: $1"
wit_require_linear_id "$ID" || wit_usage_error "not a linear item id: $ID"

wit_need_linear_config
wit_linear_require_scoped_id "$ID"

wit_linear_fetch_issue "$WIT_LINEAR_TEAM" "$WIT_ID_NUMBER"
wit_linear_normalize "$WIT_LINEAR_ISSUE"
