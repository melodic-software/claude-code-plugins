#!/usr/bin/env bash
# add-recurrence <id> --source-link <url> --note <text>: CONTRACT.md "Verbs (core public
# surface)". Appends one recurrence marker line, which carries the link and the note, to the
# item file, and appends nothing when a marker line there already records the same link.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
wit_local_require_seam_lib "$WIT_LOCAL_ADAPTER_DIR/../../lib/recurrence.sh"
# shellcheck source=../../lib/recurrence.sh
source "$WIT_LOCAL_ADAPTER_DIR/../../lib/recurrence.sh"

usage='usage: add-recurrence <id> --source-link <url> --note <text>'
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
shift
link="" note=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --source-link)
    [[ $# -ge 2 ]] || wit_usage_error "--source-link needs a value"
    link="$2"
    shift 2
    ;;
  --note)
    [[ $# -ge 2 ]] || wit_usage_error "--note needs a value"
    note="$2"
    shift 2
    ;;
  *) wit_usage_error "unknown argument: $1" ;;
  esac
done
wit_recurrence_link_ok "$link" || wit_usage_error "--source-link must be an http(s) URL with no whitespace"
[[ -n "$note" ]] || wit_usage_error "--note is required"
wit_require_local_id "$id" || wit_usage_error "malformed or non-local-markdown id: $id"

wit_need_storage
file="$(wit_item_file "$WIT_ID_NUMBER")"
[[ -f "$file" ]] || {
  printf 'add-recurrence: no item %s\n' "$id" >&2
  exit "$EX_NOT_FOUND"
}

emit() {
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg link "$link" \
    --argjson recorded "$1" --arg reason "$2" \
    '{schema_version: $sv, id: $id, source_link: $link, recorded: $recorded, reason: $reason}'
}

if wit_recurrence_has_link "$link" "$(grep -F "$WIT_RECURRENCE_MARKER" "$file" 2>/dev/null)"; then
  emit false "source link already recorded"
  exit 0
fi

marker="$(wit_recurrence_marker "$link" "$note")" || exit 1
printf '%s\n' "$marker" >>"$file"
emit true "recurrence recorded"
