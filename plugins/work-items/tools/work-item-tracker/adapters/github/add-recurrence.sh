#!/usr/bin/env bash
# add-recurrence <id> --source-link <url> --note <text>: CONTRACT.md "Verbs (core public
# surface)". Write. Posts one issue comment carrying the recurrence marker and the note, and
# posts nothing when an owner's, member's, collaborator's or bot's comment on the item
# already records the same source link. The post routes through the bot writer.
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
wit_gh_require_seam_lib "$WIT_GH_ADAPTER_DIR/../../lib/recurrence.sh"
# shellcheck source=../../lib/recurrence.sh
source "$WIT_GH_ADAPTER_DIR/../../lib/recurrence.sh"

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
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"

owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

emit() {
  jq -cn --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg link "$link" \
    --argjson recorded "$1" --arg reason "$2" \
    '{schema_version: $sv, id: $id, source_link: $link, recorded: $recorded, reason: $reason}'
}

# Anyone can comment on a public repository, so only the authors a lease comment counts from
# (common.sh wit_list_lease_comments) can mark a link recorded.
wit_run_gh read api --paginate "repos/$owner/$repo/issues/$number/comments?per_page=100" \
  --jq "[.[] | select(.body | startswith(\"$WIT_RECURRENCE_MARKER\"))
    | {line: (.body | split(\"\\n\")[0]), author_association, type: .user.type}]"
recorded="$(jq -rs 'add // [] | .[] | select(.author_association == "OWNER" or .author_association == "MEMBER"
  or .author_association == "COLLABORATOR" or .type == "Bot") | .line' <<<"$WIT_GH_OUT")"
if wit_recurrence_has_link "$link" "$recorded"; then
  emit false "source link already recorded"
  exit 0
fi

marker="$(wit_recurrence_marker "$link" "$note")" || exit "$EX_INTERNAL"
wit_run_gh write api --method POST "repos/$owner/$repo/issues/$number/comments" \
  -f body="$marker"$'\n\n'"$note" --jq '.id'
emit true "recurrence recorded"
