# shellcheck shell=bash
# local-markdown conformance binding — a throwaway temp storage dir, fully offline
# and clean-at-start (fresh dir each run). This is the fast in-CI conformance path;
# the GitHub binding stays on-demand. CB_REPO is empty: local-markdown is a
# single-namespace store, so no --repo is threaded through — this binding leaves
# CB_REPO at the runner's default (empty, CWD-derivation path) rather than setting it.

CB_BINDING_TMP=""
CB_STORAGE_TMP=""

cb_setup() {
  CB_STORAGE_TMP="$(mktemp -d)"
  CB_BINDING_TMP="$(mktemp)"
  jq -cn --arg dir "$CB_STORAGE_TMP" \
    '{schema_version: "1.0", provider: "local-markdown", config: {lease_ttl_hours: 24, storage_dir: $dir}}' \
    >"$CB_BINDING_TMP"
  export WORK_ITEM_TRACKER_BINDING="$CB_BINDING_TMP"
}

cb_teardown() {
  [[ -n "$CB_STORAGE_TMP" ]] && rm -rf "$CB_STORAGE_TMP"
  [[ -n "$CB_BINDING_TMP" ]] && rm -f "$CB_BINDING_TMP"
}
