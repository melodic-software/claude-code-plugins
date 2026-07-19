#!/usr/bin/env bash
# get-item <id> — CONTRACT.md "Verbs (core public surface)". Read-only. The ID's
# owner/repo namespace is opaque here; the item file is addressed by number.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

wit_help_if_requested "usage: get-item <id>" "$@"

id="${1:-}"
[[ -n "$id" && $# -eq 1 ]] || wit_usage_error "usage: get-item <id>"
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id (expected local-markdown:<owner>/<repo>#<number>)"

wit_need_storage
wit_emit_local_item "$WIT_ID_NUMBER" || {
  printf 'get-item: no item %s\n' "$id" >&2
  exit "$EX_NOT_FOUND"
}
