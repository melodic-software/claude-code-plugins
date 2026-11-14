#!/usr/bin/env bash
# Tests for lib/binding.sh (CONTRACT.md "Setup (binding file)").
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=binding.sh
source "$SCRIPT_DIR/binding.sh"
source "$SCRIPT_DIR/../tests/lib.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

write_binding() {
  printf '%s\n' "$2" >"$1"
}

VALID='{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}'
VALID_YAML='tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: 24'
HOME_YAML="docs/conventions/work-items.yaml"
HOME_RESOLVER="$WIT_HOME_RESOLVER"

# home_binding <dir>: a git repository at <dir> bound by the default home's YAML.
home_binding() {
  mkdir -p "$1/docs/conventions"
  git init -q "$1"
  write_binding "$1/$HOME_YAML" "$VALID_YAML"
}

# --- discovery: anchored at CLAUDE_PROJECT_DIR (never a CWD climb) ---

ROOT="$TEST_TMPDIR/repo"
mkdir -p "$ROOT/deep/nested"
home_binding "$ROOT"
OUT="$(cd "$ROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING && export CLAUDE_PROJECT_DIR="$ROOT" && wit_find_binding)"
assert_eq "CLAUDE_PROJECT_DIR anchor finds root binding from nested CWD" "$ROOT/$HOME_YAML" "$OUT"

# --- discovery: git-toplevel fallback when CLAUDE_PROJECT_DIR is unset ---

GITROOT="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITROOT/deep/nested"
home_binding "$GITROOT"
OUT="$(cd "$GITROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding)"
assert_eq "git-toplevel fallback finds root binding from nested CWD" "$GITROOT/$HOME_YAML" "$OUT"

# --- discovery: a nested per-subdirectory binding is not discovered ---

mkdir -p "$GITROOT/deep/docs/conventions"
write_binding "$GITROOT/deep/$HOME_YAML" "$VALID_YAML"
OUT="$(cd "$GITROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding)"
assert_eq "nested binding is ignored; root binding wins" "$GITROOT/$HOME_YAML" "$OUT"

# --- discovery: a stray ancestor binding ABOVE the repo root never captures it ---

mkdir -p "$TEST_TMPDIR/docs/conventions"
write_binding "$TEST_TMPDIR/$HOME_YAML" "$VALID_YAML"
BARE="$TEST_TMPDIR/bare-gitrepo"
mkdir -p "$BARE/sub"
git init -q "$BARE"
if (cd "$BARE/sub" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding >/dev/null); then
  fail "ancestor binding above the repo root is not discovered" "failure" "success"
else
  pass "ancestor binding above the repo root is not discovered"
fi

# --- discovery: no anchor at all (no CLAUDE_PROJECT_DIR, not a git repo) fails ---

NOANCHOR="$TEST_TMPDIR/no-anchor"
mkdir -p "$NOANCHOR/docs/conventions"
write_binding "$NOANCHOR/$HOME_YAML" "$VALID_YAML"
if (cd "$NOANCHOR" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding >/dev/null); then
  fail "no anchor → no discovery, even with a binding in CWD" "failure" "success"
else
  pass "no anchor → no discovery, even with a binding in CWD"
fi
ERR="$(cd "$NOANCHOR" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_no_binding_reason)"
assert_contains "no anchor → the reason names /work-items:setup apply" "$ERR" "run /work-items:setup apply from the repository root"

# --- discovery: env override wins ---

OVERRIDE="$TEST_TMPDIR/custom-binding.json"
write_binding "$OVERRIDE" "$VALID"
OUT="$(cd "$ROOT/deep/nested" && WORK_ITEM_TRACKER_BINDING="$OVERRIDE" wit_find_binding)"
assert_eq "env override wins" "$OVERRIDE" "$OUT"

# --- discovery: env override pointing nowhere fails ---

if (WORK_ITEM_TRACKER_BINDING="$TEST_TMPDIR/missing.json" wit_find_binding >/dev/null); then
  fail "missing env-override binding fails" "failure" "success"
else
  pass "missing env-override binding fails"
fi
ERR="$(WORK_ITEM_TRACKER_BINDING="$TEST_TMPDIR/missing.json" wit_no_binding_reason)"
assert_eq "missing env-override binding → the reason names the env path" \
  "no binding file at WORK_ITEM_TRACKER_BINDING=$TEST_TMPDIR/missing.json; unset it to read <home>/work-items.yaml, which /work-items:setup apply writes" "$ERR"

# --- validation ---

BINDING="$TEST_TMPDIR/b.json"

write_binding "$BINDING" "$VALID"
if wit_read_binding "$BINDING"; then
  pass "valid binding accepted"
  assert_eq "provider exported" "github" "$WIT_PROVIDER"
  assert_eq "ttl exported" "24" "$WIT_LEASE_TTL_HOURS"
else
  fail "valid binding accepted" "success" "failure"
fi

assert_rejected() {
  local label="$1" content="$2"
  write_binding "$BINDING" "$content"
  assert_fails "$label" "failure" "success" wit_read_binding "$BINDING"
}

assert_rejected "non-JSON rejected" 'not json'
assert_rejected "major-version 2 rejected" '{"schema_version":"2.0","provider":"github","config":{"lease_ttl_hours":24}}'
assert_rejected "missing provider rejected" '{"schema_version":"1.0","config":{"lease_ttl_hours":24}}'
assert_rejected "missing lease_ttl_hours rejected" '{"schema_version":"1.0","provider":"github","config":{}}'
assert_rejected "local-markdown without storage_dir rejected" '{"schema_version":"1.0","provider":"local-markdown","config":{"lease_ttl_hours":24}}'

write_binding "$BINDING" '{"schema_version":"1.0","provider":"local-markdown","config":{"lease_ttl_hours":24,"storage_dir":"/tmp/x"}}'
if wit_read_binding "$BINDING"; then
  pass "local-markdown with storage_dir accepted"
  assert_eq "storage_dir exported" "/tmp/x" "$WIT_STORAGE_DIR"
else
  fail "local-markdown with storage_dir accepted" "success" "failure"
fi

# --- validation: provider name is restricted to a bare directory segment ---

assert_rejected "provider with path traversal rejected" '{"schema_version":"1.0","provider":"../../injected","config":{"lease_ttl_hours":24}}'
assert_rejected "provider with slash rejected" '{"schema_version":"1.0","provider":"github/extra","config":{"lease_ttl_hours":24}}'

# --- storage_dir: a relative value roots against the binding file's directory,
# not the caller's CWD ---

STORAGE_ROOT="$TEST_TMPDIR/storage-repo"
mkdir -p "$STORAGE_ROOT/deep/nested"
write_binding "$STORAGE_ROOT/binding.json" \
  '{"schema_version":"1.0","provider":"local-markdown","config":{"lease_ttl_hours":24,"storage_dir":".work-items"}}'
OUT="$(cd "$STORAGE_ROOT/deep/nested" && wit_read_binding "$STORAGE_ROOT/binding.json" && printf '%s\n' "$WIT_STORAGE_DIR")"
assert_eq "relative storage_dir roots against binding dir, not CWD" \
  "$STORAGE_ROOT/.work-items" "$OUT"

# --- role_labels: config.role_labels["human-gated"] remap and default fallback ---

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}'
wit_read_binding "$BINDING"
assert_eq "human-gated label defaults to needs-human when unset" "needs-human" "$WIT_HUMAN_GATED_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"role_labels":{"human-gated":"do-not-auto-pick"}}}'
wit_read_binding "$BINDING"
assert_eq "human-gated label honors configured remap" "do-not-auto-pick" "$WIT_HUMAN_GATED_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}'
wit_read_binding "$BINDING"
assert_eq "autonomous-eligible label defaults to agent-ready when unset" "agent-ready" "$WIT_AUTONOMOUS_ELIGIBLE_LABEL"
assert_eq "recurring-maintenance label defaults to recurring when unset" "recurring" "$WIT_RECURRING_MAINTENANCE_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"role_labels":{"autonomous-eligible":"ready-bot","recurring-maintenance":"maint"}}}'
wit_read_binding "$BINDING"
assert_eq "autonomous-eligible label honors configured remap" "ready-bot" "$WIT_AUTONOMOUS_ELIGIBLE_LABEL"
assert_eq "recurring-maintenance label honors configured remap" "maint" "$WIT_RECURRING_MAINTENANCE_LABEL"

# --- container_label: config.container_label remap and default fallback ---

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}'
wit_read_binding "$BINDING"
assert_eq "container label defaults to spec-container when unset" "spec-container" "$WIT_CONTAINER_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":"decision-map"}}'
wit_read_binding "$BINDING"
assert_eq "container label honors configured remap" "decision-map" "$WIT_CONTAINER_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":""}}'
wit_read_binding "$BINDING"
assert_eq "configured-empty container label falls back to the default" "spec-container" "$WIT_CONTAINER_LABEL"

# A present non-string container_label is a configuration error, not a silent
# stringification (jq -r would render 5 / true / {} as text no item carries).
assert_rejected "numeric container_label rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":5}}'
assert_rejected "boolean container_label rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":true}}'
assert_rejected "object container_label rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":{"a":1}}}'

# --- hold lists, wayfind prefix and the owner-decision role: defaults and remaps ---

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}'
wit_read_binding "$BINDING"
assert_eq "owner-decision label defaults when unset" "needs-owner-decision" "$WIT_OWNER_DECISION_LABEL"
assert_eq "hold labels default when unset" '["needs-owner-decision","needs-reporter-info","needs-spec"]' "$WIT_HOLD_LABELS_JSON"
assert_eq "hold states default when unset" '["needs-human","needs-owner-decision","needs-reporter-info","needs-spec"]' "$WIT_HOLD_STATES_JSON"
assert_eq "hold-state labels default when unset" '["needs-human","needs-owner-decision","needs-reporter-info","needs-spec"]' "$WIT_HOLD_STATE_LABELS_JSON"
assert_eq "wayfind prefix defaults when unset" "wayfind:" "$WIT_WAYFIND_PREFIX"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"role_labels":{"owner-decision":"awaiting-owner"}}}'
wit_read_binding "$BINDING"
assert_eq "an owner-decision remap reaches the hold label defaults" '["awaiting-owner","needs-reporter-info","needs-spec"]' "$WIT_HOLD_LABELS_JSON"
assert_eq "an owner-decision remap reaches the hold-state label defaults" '["needs-human","awaiting-owner","needs-reporter-info","needs-spec"]' "$WIT_HOLD_STATE_LABELS_JSON"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"hold_labels":["on hold"],"hold_states":["parked"],"hold_state_labels":["parked"],"wayfind_label_prefix":"map:"}}'
wit_read_binding "$BINDING"
assert_eq "hold labels honor configured list" '["on hold"]' "$WIT_HOLD_LABELS_JSON"
assert_eq "hold states honor configured list" '["parked"]' "$WIT_HOLD_STATES_JSON"
assert_eq "hold-state labels honor configured list" '["parked"]' "$WIT_HOLD_STATE_LABELS_JSON"
assert_eq "wayfind prefix honors configured value" "map:" "$WIT_WAYFIND_PREFIX"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"hold_states":[],"wayfind_label_prefix":""}}'
wit_read_binding "$BINDING"
assert_eq "an empty hold-state list keeps the default" '["needs-human","needs-owner-decision","needs-reporter-info","needs-spec"]' "$WIT_HOLD_STATES_JSON"
assert_eq "an empty wayfind prefix keeps the default" "wayfind:" "$WIT_WAYFIND_PREFIX"

assert_rejected "scalar hold_labels rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"hold_labels":"on hold"}}'
assert_rejected "hold_states with an empty entry rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"hold_states":["parked",""]}}'
assert_rejected "hold_state_labels with a numeric entry rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"hold_state_labels":[5]}}'
assert_rejected "non-string wayfind_label_prefix rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"wayfind_label_prefix":["map:"]}}'

# --- personal override: .work-item-tracker.local.json beside a JSON binding (one the
# WORK_ITEM_TRACKER_BINDING override names), allowlist-only ---

OROOT="$TEST_TMPDIR/override-repo"
mkdir -p "$OROOT"
OBINDING="$OROOT/binding.json"
PERSONAL_OVERRIDE="$OROOT/.work-item-tracker.local.json"

# Personal override cases write the personal override and re-read the team binding through it. A
# rejection prints a diagnostic these cases do not assert, so stderr is muted.
assert_override_accepted() {
  local label="$1" content="$2"
  write_binding "$PERSONAL_OVERRIDE" "$content"
  assert_succeeds "$label" "success" "failure" wit_read_binding "$OBINDING"
}

assert_override_rejected() {
  local label="$1" content="$2"
  write_binding "$PERSONAL_OVERRIDE" "$content"
  if wit_read_binding "$OBINDING" 2>/dev/null; then
    fail "$label" "failure" "success"
  else
    pass "$label"
  fi
}

write_binding "$OBINDING" "$VALID"
write_binding "$PERSONAL_OVERRIDE" '{"config":{"lease_ttl_hours":2,"lease_ttl_minutes":30}}'
if wit_read_binding "$OBINDING"; then
  pass "override-merged binding accepted"
  assert_eq "personal override lease_ttl_hours wins" "2" "$WIT_LEASE_TTL_HOURS"
  assert_eq "personal override lease_ttl_minutes wins" "30" "$WIT_LEASE_TTL_MINUTES"
  assert_eq "team provider survives the merge" "github" "$WIT_PROVIDER"
else
  fail "override-merged binding accepted" "success" "failure"
fi

# Keys the personal override does not mention keep their team values (per-key, never wholesale).
write_binding "$PERSONAL_OVERRIDE" '{"config":{"lease_ttl_minutes":45}}'
wit_read_binding "$OBINDING"
assert_eq "unmentioned team key keeps its value" "24" "$WIT_LEASE_TTL_HOURS"
assert_eq "mentioned personal override key wins" "45" "$WIT_LEASE_TTL_MINUTES"

# jira auth identity is per-account and overridable; site/project_keys are not.
write_binding "$OBINDING" '{"schema_version":"1.0","provider":"jira","config":{"lease_ttl_hours":24,"jira":{"site":"a.atlassian.net","project_keys":["AB"],"auth_email":"team@example.com","auth_env":"TEAM_TOKEN"}}}'
write_binding "$PERSONAL_OVERRIDE" '{"config":{"jira":{"auth_email":"me@example.com","auth_env":"MY_TOKEN"}}}'
EJ="$(wit_effective_binding_json "$OBINDING")"
assert_eq "personal override jira auth_email wins" "me@example.com" "$(jq -r '.config.jira.auth_email' <<<"$EJ")"
assert_eq "personal override jira auth_env wins" "MY_TOKEN" "$(jq -r '.config.jira.auth_env' <<<"$EJ")"
assert_eq "team jira site survives the merge" "a.atlassian.net" "$(jq -r '.config.jira.site' <<<"$EJ")"

# The optional self-describing docs pointer is allowed in either layer.
assert_override_accepted "docs key allowed in the personal override" '{"docs":"see CONTRACT.md"}'

# Empty scaffolding on an allowlisted prefix is inert, not an error.
assert_override_accepted "empty personal override scaffolding is inert" '{"config":{}}'
assert_override_accepted "empty jira scaffolding is inert" '{"config":{"jira":{}}}'

# An explicitly null allowlisted value MERGES (presence, not non-null) and is
# judged by normal binding validation — never a silent fallback to team values.
write_binding "$PERSONAL_OVERRIDE" '{"config":{"jira":{"auth_email":null}}}'
EJ="$(wit_effective_binding_json "$OBINDING")"
assert_eq "explicit null personal override value merges as null" "null" "$(jq -c '.config.jira.auth_email' <<<"$EJ")"
write_binding "$PERSONAL_OVERRIDE" '{"config":{"lease_ttl_hours":null}}'
if wit_read_binding "$OBINDING" 2>/dev/null; then
  fail "null lease_ttl_hours personal override fails binding validation" "failure" "success"
else
  pass "null lease_ttl_hours personal override fails binding validation"
fi

# Deny-by-default: any key outside the allowlist is a configuration error, not a merge.
assert_override_rejected "personal override provider rejected" '{"provider":"local-markdown"}'
assert_override_rejected "personal override role_labels rejected" '{"config":{"role_labels":{"human-gated":"x"}}}'
assert_override_rejected "personal override container_label rejected" '{"config":{"container_label":"my-map"}}'
assert_override_rejected "personal override storage_dir rejected" '{"config":{"storage_dir":"/tmp/x"}}'
assert_override_rejected "personal override jira site rejected" '{"config":{"jira":{"site":"evil.example.com"}}}'
assert_override_rejected "personal override jira project_keys rejected" '{"config":{"jira":{"project_keys":["ZZ"]}}}'
assert_override_rejected "wrong-typed intermediate rejected" '{"config":5}'
assert_override_rejected "non-JSON personal override rejected" 'not json'
# Empty-object values cannot smuggle a non-allowlisted key past the leaf check.
assert_override_rejected "empty-object provider rejected" '{"provider":{}}'
assert_override_rejected "empty-object unknown key rejected" '{"evil":{}}'
assert_override_rejected "empty-object role_labels rejected" '{"config":{"role_labels":{}}}'
# A null at a non-leaf allowlisted prefix is a leaf, not scaffolding.
assert_override_rejected "null jira subtree rejected" '{"config":{"jira":null}}'
# An allowlisted key must hold a scalar: an object or array there is rejected at
# load with the key named, never a silent fallback to the team value.
assert_override_rejected "object-valued allowlisted key rejected" '{"config":{"jira":{"auth_email":{}}}}'
assert_override_rejected "populated object at allowlisted key rejected" '{"config":{"jira":{"auth_email":{"x":1}}}}'
assert_override_rejected "array-valued allowlisted key rejected" '{"config":{"lease_ttl_hours":[]}}'

# linear and gitea auth identity is per-account for the same reason jira's is:
# both adapters read the credential's env-var NAME from the merged view.
write_binding "$OBINDING" '{"schema_version":"1.0","provider":"linear","config":{"lease_ttl_hours":24,"linear":{"team_keys":["ENG"],"auth_env":"TEAM_LINEAR_TOKEN"}}}'
write_binding "$PERSONAL_OVERRIDE" '{"config":{"linear":{"auth_env":"MY_LINEAR_TOKEN"}}}'
EL="$(wit_effective_binding_json "$OBINDING")"
assert_eq "personal override linear auth_env wins" "MY_LINEAR_TOKEN" "$(jq -r '.config.linear.auth_env' <<<"$EL")"
assert_eq "team linear team_keys survive the merge" "ENG" "$(jq -r '.config.linear.team_keys[0]' <<<"$EL")"

write_binding "$OBINDING" '{"schema_version":"1.0","provider":"gitea","config":{"lease_ttl_hours":24,"gitea":{"base_url":"https://git.example.com","repo":"o/r","auth_env":"TEAM_GITEA_TOKEN"}}}'
write_binding "$PERSONAL_OVERRIDE" '{"config":{"gitea":{"auth_env":"MY_GITEA_TOKEN"}}}'
EG="$(wit_effective_binding_json "$OBINDING")"
assert_eq "personal override gitea auth_env wins" "MY_GITEA_TOKEN" "$(jq -r '.config.gitea.auth_env' <<<"$EG")"
assert_eq "team gitea repo survives the merge" "o/r" "$(jq -r '.config.gitea.repo' <<<"$EG")"

# Widening auth_env must not widen the rest of either subtree: everything else
# under linear/gitea is shared coordination state, exactly as jira's site is.
assert_override_rejected "personal override linear team_keys rejected" '{"config":{"linear":{"team_keys":["X"]}}}'
assert_override_rejected "personal override gitea repo rejected" '{"config":{"gitea":{"repo":"other/repo"}}}'
assert_override_rejected "object-valued linear auth_env rejected" '{"config":{"linear":{"auth_env":{}}}}'
assert_override_rejected "object-valued gitea auth_env rejected" '{"config":{"gitea":{"auth_env":{}}}}'

rm -f "$PERSONAL_OVERRIDE"

# --- convention home: the `tracker` mapping of <home>/work-items.yaml ---

# yaml_repo <name>: a git repository with the default home, echoed.
yaml_repo() {
  local dir="$TEST_TMPDIR/$1"
  mkdir -p "$dir/docs/conventions" "$dir/deep"
  git init -q "$dir"
  printf '%s\n' "$dir"
}

YAML_BINDING='ai_disclaimer: false
tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: 12
    role_labels:
      human-gated: hold'

YREPO="$(yaml_repo yaml-repo)"
write_binding "$YREPO/docs/conventions/work-items.yaml" "$YAML_BINDING"
OUT="$(cd "$YREPO/deep" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding)"
assert_eq "YAML binding in the default home binds" "$YREPO/docs/conventions/work-items.yaml" "$OUT"
if wit_read_binding "$OUT" 2>"$TEST_TMPDIR/yaml.err"; then
  pass "YAML binding accepted"
  assert_eq "YAML provider exported" "github" "$WIT_PROVIDER"
  assert_eq "YAML lease_ttl_hours exported" "12" "$WIT_LEASE_TTL_HOURS"
  assert_eq "YAML role label remap exported" "hold" "$WIT_HUMAN_GATED_LABEL"
else
  fail "YAML binding accepted" "success" "failure"
fi
assert_not_contains "YAML binding prints no notice" "$(<"$TEST_TMPDIR/yaml.err")" "notice"

# Scalars stay strings and sequences become arrays: a jira resolution id is a
# digit string the adapter requires as a string.
write_binding "$TEST_TMPDIR/ids.yaml" 'tracker:
  config:
    jira:
      resolutions:
        completed: ["10000"]
        wont_do:
          - 10001'
assert_eq "YAML scalars stay strings inside arrays" '{"completed":["10000"],"wont_do":["10001"]}' \
  "$(wit_yaml_binding_json "$TEST_TMPDIR/ids.yaml" | jq -c '.config.jira.resolutions')"

# An empty flow sequence stays [], as a JSON binding writes it, where the parser
# alone prints nothing: jira tells a present empty done_category_keys (a config
# error) from an absent one (the default) by presence, and requires both resolutions
# keys. A `[]` inside a quoted scalar or a comment is text, and a key with no value
# reads as absent.
write_binding "$TEST_TMPDIR/empty.yaml" 'tracker:
  config:
    jira:
      site: a.atlassian.net # not a list: []
      blocked_by_link_type: "[]"
      auth_email:
      done_category_keys: []
      resolutions:
        completed: ["10000"]
        wont_do: [ ]  # none yet'
assert_eq "an empty YAML flow sequence stays [], as in a JSON binding" \
  '{"site":"a.atlassian.net","blocked_by_link_type":"[]","done_category_keys":[],"resolutions":{"completed":["10000"],"wont_do":[]}}' \
  "$(wit_yaml_binding_json "$TEST_TMPDIR/empty.yaml" | jq -c '.config.jira')"
printf 'tracker:\r\n  config:\r\n    jira:\r\n      done_category_keys: []\r\n' >"$TEST_TMPDIR/crlf.yaml"
assert_eq "an empty flow sequence on a CRLF line stays []" '[]' \
  "$(wit_yaml_binding_json "$TEST_TMPDIR/crlf.yaml" | jq -c '.config.jira.done_category_keys')"
write_binding "$TEST_TMPDIR/dup.yaml" 'tracker:
  config:
    jira:
      done_category_keys: []
      done_category_keys: ["done"]'
ERR="$(wit_yaml_binding_json "$TEST_TMPDIR/dup.yaml" 2>&1 >/dev/null)"
assert_contains "a parse error after an empty flow sequence names the file's own line" "$ERR" "$TEST_TMPDIR/dup.yaml: line 5"

# The pointer region binds a home other than the default.
PREPO="$(yaml_repo pointer-repo)"
mkdir -p "$PREPO/team/conf"
# shellcheck disable=SC2016 # the backticks are the pointer grammar, not a command substitution
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' 'Conventions live in `team/conf`.' '<!-- END GENERATED: convention-home -->' >"$PREPO/AGENTS.md"
write_binding "$PREPO/team/conf/work-items.yaml" "$YAML_BINDING"
OUT="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$PREPO" wit_find_binding)"
assert_eq "YAML binding read from the home the pointer region binds" "$PREPO/team/conf/work-items.yaml" "$OUT"

# A relative storage_dir in a YAML binding roots at the project root, not the home.
write_binding "$PREPO/team/conf/work-items.yaml" 'tracker:
  schema_version: "1.0"
  provider: local-markdown
  config:
    lease_ttl_hours: 24
    storage_dir: .work-items'
OUT="$(CLAUDE_PROJECT_DIR="$PREPO" && export CLAUDE_PROJECT_DIR && wit_read_binding "$PREPO/team/conf/work-items.yaml" && printf '%s\n' "$WIT_STORAGE_DIR")"
assert_eq "YAML relative storage_dir roots at the project root" "$PREPO/.work-items" "$OUT"

# --- YAML plus the personal override work-items.local.yaml ---

YOVERRIDE="$YREPO/docs/conventions/work-items.local.yaml"
write_binding "$YOVERRIDE" 'tracker:
  config:
    lease_ttl_hours: 2'
if wit_read_binding "$YREPO/docs/conventions/work-items.yaml" 2>/dev/null; then
  assert_eq "YAML personal override lease_ttl_hours wins" "2" "$WIT_LEASE_TTL_HOURS"
  assert_eq "team YAML provider survives the personal override" "github" "$WIT_PROVIDER"
else
  fail "YAML plus personal override accepted" "success" "failure"
fi
write_binding "$YOVERRIDE" 'tracker:
  config:
    lease_ttl_hours: later'
ERR="$(wit_read_binding "$YREPO/docs/conventions/work-items.yaml" 2>&1 >/dev/null)"
assert_contains "an invalid personal override value names the personal override file" "$ERR" "$YOVERRIDE: invalid tracker.config.lease_ttl_hours: later"
write_binding "$YOVERRIDE" 'tracker:
  provider: local-markdown'
assert_fails "YAML personal override provider rejected" "failure" "success" \
  wit_read_binding "$YREPO/docs/conventions/work-items.yaml"
write_binding "$YOVERRIDE" 'ai_disclaimer: true'
assert_succeeds "YAML personal override with no tracker key is inert" "success" "failure" \
  wit_read_binding "$YREPO/docs/conventions/work-items.yaml"
rm -f "$YOVERRIDE"

# --- the retired root .work-item-tracker.json never binds; the reason names the fix ---

JREPO="$(yaml_repo json-only-repo)"
write_binding "$JREPO/docs/conventions/work-items.yaml" 'ai_disclaimer: false'
write_binding "$JREPO/.work-item-tracker.json" "$VALID"
if (unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$JREPO" wit_find_binding >/dev/null); then
  fail "a root .work-item-tracker.json alone → discovery fails" "failure" "success"
else
  pass "a root .work-item-tracker.json alone → discovery fails"
fi
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$JREPO" wit_no_binding_reason)"
assert_eq "a root .work-item-tracker.json alone → the reason names apply and the target" \
  "no binding: $JREPO/.work-item-tracker.json no longer binds the tracker; run /work-items:setup apply to copy it under tracker: in docs/conventions/work-items.yaml" "$ERR"
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$JREPO" bash "$SCRIPT_DIR/../work-item-tracker.sh" capabilities 2>&1 >/dev/null)"
assert_eq "the dispatcher exits 3 on a root .work-item-tracker.json alone" "3" "$?"
assert_contains "the dispatcher's message names /work-items:setup apply" "$ERR" "run /work-items:setup apply to copy it"

# --- neither: no YAML binding and no root JSON → no binding (the caller stops) ---

NREPO="$(yaml_repo neither-repo)"
write_binding "$NREPO/docs/conventions/work-items.yaml" 'ai_disclaimer: false'
if (unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$NREPO" wit_find_binding >/dev/null); then
  fail "neither YAML nor JSON binding → discovery fails" "failure" "success"
else
  pass "neither YAML nor JSON binding → discovery fails"
fi
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$NREPO" wit_no_binding_reason)"
assert_eq "neither → the reason names the home file and apply" \
  "no binding: $NREPO/docs/conventions/work-items.yaml sets no tracker: mapping; run /work-items:setup apply" "$ERR"

# --- no home applies: a root outside a git work tree binds nothing ---

LOOSE="$TEST_TMPDIR/loose-folder"
mkdir -p "$LOOSE/docs/conventions"
write_binding "$LOOSE/docs/conventions/work-items.yaml" "$YAML_BINDING"
if (unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$LOOSE" wit_find_binding >/dev/null); then
  fail "a non-git root never reads <home>/work-items.yaml" "failure" "success"
else
  pass "a non-git root never reads <home>/work-items.yaml"
fi
write_binding "$LOOSE/.work-item-tracker.json" "$VALID"
if (unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$LOOSE" wit_find_binding >/dev/null); then
  fail "a non-git root never binds through a root .work-item-tracker.json" "failure" "success"
else
  pass "a non-git root never binds through a root .work-item-tracker.json"
fi
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$LOOSE" wit_no_binding_reason)"
assert_contains "no home → the reason names the retired file" "$ERR" "$LOOSE/.work-item-tracker.json no longer binds the tracker"
assert_contains "no home → the reason names apply from a git work tree" "$ERR" "run /work-items:setup apply from a git work tree that binds a home"

# --- a declined home: no home applies ---

DREPO="$(yaml_repo declined-repo)"
write_binding "$DREPO/AGENTS.md" '<!-- BEGIN GENERATED: convention-home -->
declined
<!-- END GENERATED: convention-home -->'
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$DREPO" wit_no_binding_reason)"
assert_contains "declined home → the reason says no home applies" "$ERR" "no convention home applies under $DREPO"

# --- a broken pointer: the reason names setup check, not apply ---

PREPO="$(yaml_repo broken-pointer-repo)"
# shellcheck disable=SC2016 # the backticks are markdown, not an expansion
write_binding "$PREPO/AGENTS.md" '<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/missing`.
<!-- END GENERATED: convention-home -->'
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$PREPO" wit_find_binding 2>&1 >/dev/null)"
assert_eq "broken pointer → discovery fails" "1" "$?"
assert_contains "broken pointer → discovery passes the resolver's message through" "$ERR" "docs/missing"
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$PREPO" wit_no_binding_reason 2>/dev/null)"
assert_eq "broken pointer → the reason names setup check" \
  "no binding: the convention-home pointer under $PREPO is broken; run /work-items:setup check to see why" "$ERR"

# --- missing shared copies: the reason names a reinstall ---

ERR="$(unset WORK_ITEM_TRACKER_BINDING && WIT_HOME_RESOLVER="$TEST_TMPDIR/absent.sh" && CLAUDE_PROJECT_DIR="$NREPO" wit_no_binding_reason)"
assert_contains "missing shared copies → the reason names the missing copy" "$ERR" "$TEST_TMPDIR/absent.sh"
assert_contains "missing shared copies → the reason names a reinstall" "$ERR" "reinstall the work-items plugin"
assert_contains "missing shared copies → the parser copy is plugin-relative" "$ERR" " or skills/triage/scripts/yaml-subset.awk;"

# --- invalid YAML: the error names the file, the key and the value ---

IREPO="$(yaml_repo invalid-repo)"
IYAML="$IREPO/docs/conventions/work-items.yaml"
write_binding "$IYAML" 'tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: soon'
OUT="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$IREPO" wit_find_binding)"
assert_eq "an invalid YAML binding is still the binding (no JSON fallback)" "$IYAML" "$OUT"
ERR="$(wit_read_binding "$IYAML" 2>&1 >/dev/null)"
assert_eq "invalid YAML value rejected" "1" "$?"
assert_contains "invalid YAML error names the file" "$ERR" "$IYAML"
assert_contains "invalid YAML error names the key" "$ERR" "tracker.config.lease_ttl_hours"
assert_contains "invalid YAML error names the value" "$ERR" "soon"

write_binding "$IYAML" 'tracker:
  schema_version: "1.0"
  provider: github
  owner: someone
  config:
    lease_ttl_hours: 24'
ERR="$(wit_read_binding "$IYAML" 2>&1 >/dev/null)"
assert_contains "a key outside the schema is named" "$ERR" "tracker.owner"

write_binding "$IYAML" 'tracker:
  provider: github
  provider: jira'
ERR="$(wit_read_binding "$IYAML" 2>&1 >/dev/null)"
assert_contains "a YAML parse error names the file and line" "$ERR" "$IYAML: line 3"

# --- wayfind-labels: the prefix and human-gated label, failing closed on the home ---

WAYFIND_YAML='tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: 24
    wayfind_label_prefix: "decide:"
    role_labels:
      human-gated: owner-call'
DISPATCHER="$SCRIPT_DIR/../work-item-tracker.sh"

# run_wayfind_labels <root>: the dispatcher verb at <root>; stdout to OUT, exit to RC.
run_wayfind_labels() {
  OUT="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$1" bash "$DISPATCHER" wayfind-labels 2>/dev/null)"
  RC=$?
}

WREPO="$(yaml_repo wayfind-default-home)"
run_wayfind_labels "$WREPO"
assert_eq "wayfind-labels, no binding → exit 0" "0" "$RC"
assert_eq "wayfind-labels, no binding → both defaults" \
  '{"schema_version":"1.0","prefix":"wayfind:","prefix_source":"default","human_gated":"needs-human","human_gated_source":"default"}' "$OUT"
write_binding "$WREPO/$HOME_YAML" "$WAYFIND_YAML"
run_wayfind_labels "$WREPO"
assert_eq "wayfind-labels, default home → the binding's labels" \
  '{"schema_version":"1.0","prefix":"decide:","prefix_source":"binding","human_gated":"owner-call","human_gated_source":"binding"}' "$OUT"
write_binding "$WREPO/$HOME_YAML" "$VALID_YAML"
run_wayfind_labels "$WREPO"
assert_eq "wayfind-labels, a binding without the keys → defaults" \
  '{"schema_version":"1.0","prefix":"wayfind:","prefix_source":"default","human_gated":"needs-human","human_gated_source":"default"}' "$OUT"

WPREPO="$(yaml_repo wayfind-relocated-home)"
mkdir -p "$WPREPO/config/team"
# shellcheck disable=SC2016 # the backticks are the pointer grammar, not a command substitution
printf '%s\n' '<!-- BEGIN GENERATED: convention-home -->' 'Conventions live in `config/team`.' '<!-- END GENERATED: convention-home -->' >"$WPREPO/AGENTS.md"
write_binding "$WPREPO/config/team/work-items.yaml" "$WAYFIND_YAML"
run_wayfind_labels "$WPREPO"
assert_eq "wayfind-labels, relocated home → exit 0" "0" "$RC"
assert_eq "wayfind-labels, relocated home → the binding's labels" "decide: owner-call" "$(jq -r '.prefix + " " + .human_gated' <<<"$OUT")"

write_binding "$WREPO/$HOME_YAML" 'tracker:
  schema_version: "1.0"
  provider: github
  config:
    lease_ttl_hours: 24
    wayfind_label_prefix: [decide]'
run_wayfind_labels "$WREPO"
assert_eq "wayfind-labels, a non-string prefix → exit 3" "3" "$RC"
assert_eq "wayfind-labels, a non-string prefix → nothing on stdout" "" "$OUT"

# assert_wayfind_refuses <root> <resolver exit> <what>: the resolver exits as named at
# <root>, and the verb refuses with nothing on stdout.
assert_wayfind_refuses() {
  bash "$HOME_RESOLVER" --root "$1" >/dev/null 2>&1
  assert_eq "resolver exits $2 on $3" "$2" "$?"
  run_wayfind_labels "$1"
  assert_eq "wayfind-labels refuses on $3 (resolver exit $2) → exit 3" "3" "$RC"
  assert_eq "wayfind-labels refuses on $3 (resolver exit $2) → nothing on stdout" "" "$OUT"
}

WBROKEN="$(yaml_repo wayfind-broken-pointer)"
write_binding "$WBROKEN/$HOME_YAML" "$WAYFIND_YAML"
# shellcheck disable=SC2016 # the backticks are markdown, not an expansion
write_binding "$WBROKEN/AGENTS.md" '<!-- BEGIN GENERATED: convention-home -->
Team conventions live in `docs/missing`.
<!-- END GENERATED: convention-home -->'
assert_wayfind_refuses "$WBROKEN" 3 "a pointer to a missing directory"
ERR="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$WBROKEN" bash "$DISPATCHER" wayfind-labels 2>&1 >/dev/null)"
assert_contains "wayfind-labels on a broken pointer passes the resolver's message through" "$ERR" "docs/missing"

WDECLINED="$(yaml_repo wayfind-declined)"
write_binding "$WDECLINED/$HOME_YAML" "$WAYFIND_YAML"
write_binding "$WDECLINED/AGENTS.md" '<!-- BEGIN GENERATED: convention-home -->
declined
<!-- END GENERATED: convention-home -->'
assert_wayfind_refuses "$WDECLINED" 4 "a declined home"

WLOOSE="$TEST_TMPDIR/wayfind-loose"
mkdir -p "$WLOOSE/docs/conventions"
write_binding "$WLOOSE/$HOME_YAML" "$WAYFIND_YAML"
assert_wayfind_refuses "$WLOOSE" 5 "a root outside a git work tree"

(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$WREPO" bash "$DISPATCHER" wayfind-labels --bogus >/dev/null 2>&1)
assert_eq "wayfind-labels takes no arguments → exit 2" "2" "$?"

[[ $FAILED -eq 0 ]] || exit 1
