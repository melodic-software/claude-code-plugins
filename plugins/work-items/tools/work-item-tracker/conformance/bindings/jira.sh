# shellcheck shell=bash
# jira conformance binding — a temp binding file, fully offline and in-CI. The jira
# adapter is consume-only (create-item and every write verb declared false), so the
# abstract suite never seeds an item and thus never exercises a read verb's network
# path: it asserts capabilities, usage/binding errors, and that every write verb +
# list-sub-items degrades to exit 6 at the core capability gate (all pre-network).
# The read verbs (get-item/list-items) are covered offline by the adapter's own
# *.test.sh with a mocked curl; a live-Jira conformance pass is deferred to the
# work-laptop pass that settles the #4 statusCategory key and #6 link type (see #379).
#
# CB_REPO is left empty: no --repo is threaded through (the suite's read/create paths
# that would use it are all skipped under the consume-only manifest).

CB_BINDING_TMP=""

cb_setup() {
  CB_BINDING_TMP="$(mktemp)"
  # A syntactically valid jira binding. The jira config subtree carries placeholder
  # values; it is never read, because no exercised path reaches wit_need_jira_config
  # (create-item=false blocks item seeding, so get-item/list-items never run).
  jq -cn '{schema_version:"1.0", provider:"jira",
    config:{lease_ttl_hours:24,
      jira:{site:"conformance.atlassian.net", project_keys:["CONF"],
        auth_email:"conformance@example.invalid", auth_env:"WIT_JIRA_CONFORMANCE_TOKEN_UNUSED"}}}' \
    >"$CB_BINDING_TMP"
  export WORK_ITEM_TRACKER_BINDING="$CB_BINDING_TMP"
}

cb_teardown() {
  [[ -n "$CB_BINDING_TMP" ]] && rm -f "$CB_BINDING_TMP"
}
