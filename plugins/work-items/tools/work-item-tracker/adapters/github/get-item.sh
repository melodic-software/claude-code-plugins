#!/usr/bin/env bash
# get-item <id> — CONTRACT.md "Verbs (core public surface)". Read-only.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: get-item <id>" "$@"

id="${1:-}"
[[ -n "$id" && $# -eq 1 ]] || wit_usage_error "usage: get-item <id>"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id (expected github:<owner>/<repo>#<number>)"

wit_emit_item "$WIT_ID_OWNER" "$WIT_ID_REPO" "$WIT_ID_NUMBER"
