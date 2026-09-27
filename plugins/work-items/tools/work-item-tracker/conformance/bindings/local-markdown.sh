# shellcheck shell=bash
# local-markdown conformance binding: a fresh temp storage dir per run, fully offline.
# CB_REPO stays at the runner's empty default: a single-namespace store takes no --repo.

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
