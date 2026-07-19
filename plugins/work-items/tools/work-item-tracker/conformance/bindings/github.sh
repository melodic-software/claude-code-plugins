# shellcheck shell=bash
# GitHub conformance binding — targets a throwaway sandbox repo (NEVER a
# coordination repo). On-demand, not in CI. The target is required: set
# WIT_CONFORMANCE_GITHUB_REPO to the sandbox repo (owner/name). No default —
# no standing sandbox exists to fall back to (see ADR 0022 conformance note).

CB_BINDING_TMP=""

# Close every open issue in the sandbox so each run starts clean.
_cb_close_all_open() {
  local numbers
  numbers="$(gh issue list -R "$CB_REPO" --state open --limit 200 --json number --jq '.[].number' | tr -d '\r')"
  local n
  for n in $numbers; do
    gh issue close "$n" -R "$CB_REPO" --comment "conformance clean-at-start" >/dev/null 2>&1 || true
  done
}

cb_setup() {
  CB_REPO="${WIT_CONFORMANCE_GITHUB_REPO:?set WIT_CONFORMANCE_GITHUB_REPO to a throwaway sandbox repo (owner/name); NEVER a coordination repo}"
  CB_BINDING_TMP="$(mktemp)"
  printf '%s\n' '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}' >"$CB_BINDING_TMP"
  export WORK_ITEM_TRACKER_BINDING="$CB_BINDING_TMP"
  _cb_close_all_open
}

cb_teardown() {
  _cb_close_all_open
  [[ -n "$CB_BINDING_TMP" ]] && rm -f "$CB_BINDING_TMP"
}
