#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage="usage: list-relates <id>"
wit_help_if_requested "$usage" "$@"

id="${1:-}"
[[ $# -eq 1 && -n "$id" && "$id" != --* ]] || wit_usage_error "$usage"
wit_require_github_id "$id" || wit_usage_error "malformed or non-github id: $id"
owner="$WIT_ID_OWNER" repo="$WIT_ID_REPO" number="$WIT_ID_NUMBER"

unavail_extra='{"items":[]}'
if ! wit_gh_capture read api --paginate "repos/$owner/$repo/issues/$number/relates_to?per_page=100"; then
  if wit_gh_is_feature_unavailable "$WIT_GH_ERR" "$owner" "$repo" "$number" 1; then
    wit_gh_emit_unavailable list-relates "$id" "refs-comment" "$WIT_GH_ERR" "$unavail_extra"
  fi
  printf '%s\n' "$WIT_GH_ERR" >&2
  exit "$(wit_map_gh_error "$WIT_GH_ERR")"
fi

# shellcheck disable=SC2016  # jq variables, not bash expansions
jq -cs --arg sv "$WIT_SCHEMA_VERSION" --arg id "$id" --arg or "$owner/$repo" '
  add // [] | {
    schema_version: $sv,
    id: $id,
    available: true,
    items: map(
      .number as $num | {
        id: (
          if (.html_url // "") != "" and (.html_url | test("github\\.com/[^/]+/[^/]+/issues/[0-9]+")) then
            (.html_url | capture("github\\.com/(?<o>[^/]+)/(?<r>[^/]+)/issues/(?<n>[0-9]+)") | "github:" + .o + "/" + .r + "#" + .n)
          elif (.repository_url // "") != "" and (.repository_url | test("/repos/[^/]+/[^/]+$")) then
            (.repository_url | capture("/repos/(?<o>[^/]+)/(?<r>[^/]+)$") | "github:" + .o + "/" + .r + "#" + ($num | tostring))
          else
            "github:" + $or + "#" + ($num | tostring)
          end
        ),
        title: (.title // null),
        state: (if (.state // null) != null then (.state | ascii_downcase) else null end),
        url: (.html_url // .url // null)
      }
    )
  }' <<<"$WIT_GH_OUT" || {
  printf 'list-relates: response for %s is not JSON\n' "$id" >&2
  exit "$EX_INTERNAL"
}
