# shellcheck shell=bash

CB_BINDING_TMP=""

cb_setup() {
  CB_BINDING_TMP="$(mktemp)"
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
