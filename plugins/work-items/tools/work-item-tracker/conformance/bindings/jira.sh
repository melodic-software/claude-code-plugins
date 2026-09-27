# shellcheck shell=bash
# jira conformance binding, fully offline: the consume-only manifest means the suite
# never seeds an item, so no read verb's network path runs (the adapter tests cover those).
#
# CB_REPO is left empty: no --repo is threaded through (the suite's read/create paths
# that would use it are all skipped under the consume-only manifest).

CB_BINDING_TMP=""

cb_setup() {
  CB_BINDING_TMP="$(mktemp)"
  # The jira config subtree holds placeholders: no exercised path reaches
  # wit_need_jira_config, since create-item=false blocks item seeding.
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
