# shellcheck shell=bash
# shellcheck disable=SC2034  # CB_REPO is the binding contract's output — read by run-conformance.sh, which sources this file
# shellcheck disable=SC2154  # WIT_CONFORMANCE_LINEAR_* are operator-supplied env vars; cb_setup's `:?` guards prove they are set before _cb_clean_at_start reads them

CB_BINDING_TMP=""

_cb_clean_at_start() {
  local host team key page after body ids id
  host="$WIT_CONFORMANCE_LINEAR_HOST"
  team="${WIT_CONFORMANCE_LINEAR_SCOPE##*/}"
  key="${WIT_LINEAR_API_KEY:?set WIT_LINEAR_API_KEY to the throwaway workspace credential}"

  _cb_gql() {
    printf 'header = "Authorization: %s"\n' "$key" |
      curl -sS -X POST "https://$host/graphql" \
        --proto '=https' \
        -H 'Content-Type: application/json' \
        -K - --data-binary "$1"
  }

  after="null"
  while :; do
    page="$(jq -cn --arg t "$team" --argjson a "$after" \
      '{query:"query($t: String!, $a: String) { issues(filter: { team: { key: { eq: $t } } }, first: 50, after: $a) { nodes { id } pageInfo { hasNextPage endCursor } } }",
        variables:{t:$t, a:$a}}')"
    body="$(_cb_gql "$page")" || {
      printf 'conformance(linear): clean-at-start could not list issues in team %s — refusing to run against an unknown state\n' "$team" >&2
      return 1
    }
    if [[ "$(jq -c '.errors // []' <<<"$body")" != "[]" ]]; then
      printf 'conformance(linear): clean-at-start list failed: %s\n' \
        "$(jq -r '.errors[0].message // "unknown GraphQL error"' <<<"$body")" >&2
      return 1
    fi

    ids="$(jq -r '.data.issues.nodes[]?.id' <<<"$body")"
    for id in $ids; do
      _cb_gql "$(jq -cn --arg id "$id" \
        '{query:"mutation($id: String!) { issueArchive(id: $id) { success } }",
          variables:{id:$id}}')" >/dev/null || {
        printf 'conformance(linear): failed to archive issue %s\n' "$id" >&2
        return 1
      }
    done

    [[ "$(jq -r '.data.issues.pageInfo.hasNextPage' <<<"$body")" == "true" ]] || break
    after="$(jq -c '.data.issues.pageInfo.endCursor' <<<"$body")"
  done
}

cb_setup() {
  local host scope
  host="${WIT_CONFORMANCE_LINEAR_HOST:?set WIT_CONFORMANCE_LINEAR_HOST to a throwaway Linear host; never a coordination instance}"
  scope="${WIT_CONFORMANCE_LINEAR_SCOPE:?set WIT_CONFORMANCE_LINEAR_SCOPE to a throwaway scope; never a coordination scope}"
  CB_REPO="$scope"
  CB_BINDING_TMP="$(mktemp)"
  jq -cn --arg h "$host" --arg s "$scope" \
    '{schema_version:"1.0", provider:"linear",
      config:{lease_ttl_hours:24,
        "linear":{host:$h, scopes:[$s], auth_env:"WIT_LINEAR_API_KEY"}}}' \
    >"$CB_BINDING_TMP"
  export WORK_ITEM_TRACKER_BINDING="$CB_BINDING_TMP"
  _cb_clean_at_start
}

cb_teardown() {
  _cb_clean_at_start
  [[ -n "$CB_BINDING_TMP" ]] && rm -f "$CB_BINDING_TMP"
}
