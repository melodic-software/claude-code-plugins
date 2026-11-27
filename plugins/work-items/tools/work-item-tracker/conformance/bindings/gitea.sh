# shellcheck shell=bash
# shellcheck disable=SC2034  # CB_REPO is the binding contract's output — read by run-conformance.sh, which sources this file

CB_BINDING_TMP=""

_cb_clean_at_start() {
  printf 'conformance(gitea): clean-at-start is an unfilled placeholder — items created by this run will be left in %s, and count assertions may flap against leftovers from a previous run\n' \
    "${CB_REPO:-the configured scope}" >&2
}

cb_setup() {
  local host scope
  host="${WIT_CONFORMANCE_GITEA_HOST:?set WIT_CONFORMANCE_GITEA_HOST to a throwaway Gitea / Forgejo host; never a coordination instance}"
  scope="${WIT_CONFORMANCE_GITEA_SCOPE:?set WIT_CONFORMANCE_GITEA_SCOPE to a throwaway scope; never a coordination scope}"
  CB_REPO="$scope"
  CB_BINDING_TMP="$(mktemp)"
  jq -cn --arg h "$host" --arg s "$scope" \
    '{schema_version:"1.0", provider:"gitea",
      config:{lease_ttl_hours:24,
        "gitea":{host:$h, scopes:[$s], auth_env:"WIT_GITEA_TOKEN"}}}' \
    >"$CB_BINDING_TMP"
  export WORK_ITEM_TRACKER_BINDING="$CB_BINDING_TMP"
  _cb_clean_at_start
}

cb_teardown() {
  _cb_clean_at_start
  [[ -n "$CB_BINDING_TMP" ]] && rm -f "$CB_BINDING_TMP"
}
