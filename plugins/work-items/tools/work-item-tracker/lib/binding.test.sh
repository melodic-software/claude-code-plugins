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

# --- discovery: anchored at CLAUDE_PROJECT_DIR (never a CWD climb) ---

ROOT="$TEST_TMPDIR/repo"
mkdir -p "$ROOT/deep/nested"
write_binding "$ROOT/.work-item-tracker.json" "$VALID"
OUT="$(cd "$ROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING && export CLAUDE_PROJECT_DIR="$ROOT" && wit_find_binding)"
assert_eq "CLAUDE_PROJECT_DIR anchor finds root binding from nested CWD" "$ROOT/.work-item-tracker.json" "$OUT"

# --- discovery: git-toplevel fallback when CLAUDE_PROJECT_DIR is unset ---

GITROOT="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITROOT/deep/nested"
git init -q "$GITROOT"
write_binding "$GITROOT/.work-item-tracker.json" "$VALID"
OUT="$(cd "$GITROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding)"
assert_eq "git-toplevel fallback finds root binding from nested CWD" "$GITROOT/.work-item-tracker.json" "$OUT"

# --- discovery: a nested per-subdirectory binding is not discovered ---

write_binding "$GITROOT/deep/.work-item-tracker.json" "$VALID"
OUT="$(cd "$GITROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding)"
assert_eq "nested binding is ignored; root binding wins" "$GITROOT/.work-item-tracker.json" "$OUT"

# --- discovery: a stray ancestor binding ABOVE the repo root never captures it ---

write_binding "$TEST_TMPDIR/.work-item-tracker.json" "$VALID"
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
mkdir -p "$NOANCHOR"
write_binding "$NOANCHOR/.work-item-tracker.json" "$VALID"
if (cd "$NOANCHOR" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding >/dev/null); then
  fail "no anchor → no discovery, even with a binding in CWD" "failure" "success"
else
  pass "no anchor → no discovery, even with a binding in CWD"
fi

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
write_binding "$STORAGE_ROOT/.work-item-tracker.json" \
  '{"schema_version":"1.0","provider":"local-markdown","config":{"lease_ttl_hours":24,"storage_dir":".work-items"}}'
OUT="$(cd "$STORAGE_ROOT/deep/nested" && wit_read_binding "$STORAGE_ROOT/.work-item-tracker.json" && printf '%s\n' "$WIT_STORAGE_DIR")"
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
assert_eq "container label defaults to work-map when unset" "work-map" "$WIT_CONTAINER_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":"decision-map"}}'
wit_read_binding "$BINDING"
assert_eq "container label honors configured remap" "decision-map" "$WIT_CONTAINER_LABEL"

write_binding "$BINDING" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":""}}'
wit_read_binding "$BINDING"
assert_eq "configured-empty container label falls back to the default" "work-map" "$WIT_CONTAINER_LABEL"

# A present non-string container_label is a configuration error, not a silent
# stringification (jq -r would render 5 / true / {} as text no item carries).
assert_rejected "numeric container_label rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":5}}'
assert_rejected "boolean container_label rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":true}}'
assert_rejected "object container_label rejected" '{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24,"container_label":{"a":1}}}'

# --- overlay: .work-item-tracker.local.json beside the binding, allowlist-only ---

OROOT="$TEST_TMPDIR/overlay-repo"
mkdir -p "$OROOT"
OBINDING="$OROOT/.work-item-tracker.json"
OVERLAY="$OROOT/.work-item-tracker.local.json"

# Overlay cases write the overlay and re-read the team binding through it. A
# rejection prints a diagnostic these cases do not assert, so stderr is muted.
assert_overlay_accepted() {
  local label="$1" content="$2"
  write_binding "$OVERLAY" "$content"
  assert_succeeds "$label" "success" "failure" wit_read_binding "$OBINDING"
}

assert_overlay_rejected() {
  local label="$1" content="$2"
  write_binding "$OVERLAY" "$content"
  if wit_read_binding "$OBINDING" 2>/dev/null; then
    fail "$label" "failure" "success"
  else
    pass "$label"
  fi
}

write_binding "$OBINDING" "$VALID"
write_binding "$OVERLAY" '{"config":{"lease_ttl_hours":2,"lease_ttl_minutes":30}}'
if wit_read_binding "$OBINDING"; then
  pass "overlay-merged binding accepted"
  assert_eq "overlay lease_ttl_hours wins" "2" "$WIT_LEASE_TTL_HOURS"
  assert_eq "overlay lease_ttl_minutes wins" "30" "$WIT_LEASE_TTL_MINUTES"
  assert_eq "team provider survives the merge" "github" "$WIT_PROVIDER"
else
  fail "overlay-merged binding accepted" "success" "failure"
fi

# Keys the overlay does not mention keep their team values (per-key, never wholesale).
write_binding "$OVERLAY" '{"config":{"lease_ttl_minutes":45}}'
wit_read_binding "$OBINDING"
assert_eq "unmentioned team key keeps its value" "24" "$WIT_LEASE_TTL_HOURS"
assert_eq "mentioned overlay key wins" "45" "$WIT_LEASE_TTL_MINUTES"

# jira auth identity is per-account and overlayable; site/project_keys are not.
write_binding "$OBINDING" '{"schema_version":"1.0","provider":"jira","config":{"lease_ttl_hours":24,"jira":{"site":"a.atlassian.net","project_keys":["AB"],"auth_email":"team@example.com","auth_env":"TEAM_TOKEN"}}}'
write_binding "$OVERLAY" '{"config":{"jira":{"auth_email":"me@example.com","auth_env":"MY_TOKEN"}}}'
EJ="$(wit_effective_binding_json "$OBINDING")"
assert_eq "overlay jira auth_email wins" "me@example.com" "$(jq -r '.config.jira.auth_email' <<<"$EJ")"
assert_eq "overlay jira auth_env wins" "MY_TOKEN" "$(jq -r '.config.jira.auth_env' <<<"$EJ")"
assert_eq "team jira site survives the merge" "a.atlassian.net" "$(jq -r '.config.jira.site' <<<"$EJ")"

# The optional self-describing docs pointer is allowed in either layer.
assert_overlay_accepted "docs key allowed in the overlay" '{"docs":"see CONTRACT.md"}'

# Empty scaffolding on an allowlisted prefix is inert, not an error.
assert_overlay_accepted "empty overlay scaffolding is inert" '{"config":{}}'
assert_overlay_accepted "empty jira scaffolding is inert" '{"config":{"jira":{}}}'

# An explicitly null allowlisted value MERGES (presence, not non-null) and is
# judged by normal binding validation — never a silent fallback to team values.
write_binding "$OVERLAY" '{"config":{"jira":{"auth_email":null}}}'
EJ="$(wit_effective_binding_json "$OBINDING")"
assert_eq "explicit null overlay value merges as null" "null" "$(jq -c '.config.jira.auth_email' <<<"$EJ")"
write_binding "$OVERLAY" '{"config":{"lease_ttl_hours":null}}'
if wit_read_binding "$OBINDING" 2>/dev/null; then
  fail "null lease_ttl_hours overlay fails binding validation" "failure" "success"
else
  pass "null lease_ttl_hours overlay fails binding validation"
fi

# Deny-by-default: any key outside the allowlist is a configuration error, not a merge.
assert_overlay_rejected "overlay provider override rejected" '{"provider":"local-markdown"}'
assert_overlay_rejected "overlay role_labels rejected" '{"config":{"role_labels":{"human-gated":"x"}}}'
assert_overlay_rejected "overlay container_label rejected" '{"config":{"container_label":"my-map"}}'
assert_overlay_rejected "overlay storage_dir rejected" '{"config":{"storage_dir":"/tmp/x"}}'
assert_overlay_rejected "overlay jira site rejected" '{"config":{"jira":{"site":"evil.example.com"}}}'
assert_overlay_rejected "overlay jira project_keys rejected" '{"config":{"jira":{"project_keys":["ZZ"]}}}'
assert_overlay_rejected "wrong-typed intermediate rejected" '{"config":5}'
assert_overlay_rejected "non-JSON overlay rejected" 'not json'
# Empty-object values cannot smuggle a non-allowlisted key past the leaf check.
assert_overlay_rejected "empty-object provider rejected" '{"provider":{}}'
assert_overlay_rejected "empty-object unknown key rejected" '{"evil":{}}'
assert_overlay_rejected "empty-object role_labels rejected" '{"config":{"role_labels":{}}}'
# A null at a non-leaf allowlisted prefix is a leaf, not scaffolding.
assert_overlay_rejected "null jira subtree rejected" '{"config":{"jira":null}}'
# An allowlisted key must hold a scalar: an object or array there is rejected at
# load with the key named, never a silent fallback to the team value.
assert_overlay_rejected "object-valued allowlisted key rejected" '{"config":{"jira":{"auth_email":{}}}}'
assert_overlay_rejected "populated object at allowlisted key rejected" '{"config":{"jira":{"auth_email":{"x":1}}}}'
assert_overlay_rejected "array-valued allowlisted key rejected" '{"config":{"lease_ttl_hours":[]}}'

# linear and gitea auth identity is per-account for the same reason jira's is:
# both adapters read the credential's env-var NAME from the merged view.
write_binding "$OBINDING" '{"schema_version":"1.0","provider":"linear","config":{"lease_ttl_hours":24,"linear":{"team_keys":["ENG"],"auth_env":"TEAM_LINEAR_TOKEN"}}}'
write_binding "$OVERLAY" '{"config":{"linear":{"auth_env":"MY_LINEAR_TOKEN"}}}'
EL="$(wit_effective_binding_json "$OBINDING")"
assert_eq "overlay linear auth_env wins" "MY_LINEAR_TOKEN" "$(jq -r '.config.linear.auth_env' <<<"$EL")"
assert_eq "team linear team_keys survive the merge" "ENG" "$(jq -r '.config.linear.team_keys[0]' <<<"$EL")"

write_binding "$OBINDING" '{"schema_version":"1.0","provider":"gitea","config":{"lease_ttl_hours":24,"gitea":{"base_url":"https://git.example.com","repo":"o/r","auth_env":"TEAM_GITEA_TOKEN"}}}'
write_binding "$OVERLAY" '{"config":{"gitea":{"auth_env":"MY_GITEA_TOKEN"}}}'
EG="$(wit_effective_binding_json "$OBINDING")"
assert_eq "overlay gitea auth_env wins" "MY_GITEA_TOKEN" "$(jq -r '.config.gitea.auth_env' <<<"$EG")"
assert_eq "team gitea repo survives the merge" "o/r" "$(jq -r '.config.gitea.repo' <<<"$EG")"

# Widening auth_env must not widen the rest of either subtree: everything else
# under linear/gitea is shared coordination state, exactly as jira's site is.
assert_overlay_rejected "overlay linear team_keys rejected" '{"config":{"linear":{"team_keys":["X"]}}}'
assert_overlay_rejected "overlay gitea repo rejected" '{"config":{"gitea":{"repo":"other/repo"}}}'
assert_overlay_rejected "object-valued linear auth_env rejected" '{"config":{"linear":{"auth_env":{}}}}'
assert_overlay_rejected "object-valued gitea auth_env rejected" '{"config":{"gitea":{"auth_env":{}}}}'

rm -f "$OVERLAY"

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
write_binding "$YREPO/.work-item-tracker.json" '{"schema_version":"1.0","provider":"local-markdown","config":{"lease_ttl_hours":1,"storage_dir":"x"}}'
OUT="$(cd "$YREPO/deep" && unset WORK_ITEM_TRACKER_BINDING CLAUDE_PROJECT_DIR && wit_find_binding)"
assert_eq "YAML binding in the default home wins over the legacy JSON" "$YREPO/docs/conventions/work-items.yaml" "$OUT"
if wit_read_binding "$OUT" 2>"$TEST_TMPDIR/yaml.err"; then
  pass "YAML binding accepted"
  assert_eq "YAML provider exported" "github" "$WIT_PROVIDER"
  assert_eq "YAML lease_ttl_hours exported" "12" "$WIT_LEASE_TTL_HOURS"
  assert_eq "YAML role label remap exported" "hold" "$WIT_HUMAN_GATED_LABEL"
else
  fail "YAML binding accepted" "success" "failure"
fi
assert_not_contains "YAML binding prints no legacy notice" "$(<"$TEST_TMPDIR/yaml.err")" "notice"

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

# --- YAML plus the personal overlay work-items.local.yaml ---

YOVERLAY="$YREPO/docs/conventions/work-items.local.yaml"
write_binding "$YOVERLAY" 'tracker:
  config:
    lease_ttl_hours: 2'
if wit_read_binding "$YREPO/docs/conventions/work-items.yaml" 2>/dev/null; then
  assert_eq "YAML overlay lease_ttl_hours wins" "2" "$WIT_LEASE_TTL_HOURS"
  assert_eq "team YAML provider survives the overlay" "github" "$WIT_PROVIDER"
else
  fail "YAML plus overlay accepted" "success" "failure"
fi
write_binding "$YOVERLAY" 'tracker:
  config:
    lease_ttl_hours: later'
ERR="$(wit_read_binding "$YREPO/docs/conventions/work-items.yaml" 2>&1 >/dev/null)"
assert_contains "an invalid overlay value names the overlay file" "$ERR" "$YOVERLAY: invalid tracker.config.lease_ttl_hours: later"
write_binding "$YOVERLAY" 'tracker:
  provider: local-markdown'
assert_fails "YAML overlay provider override rejected" "failure" "success" \
  wit_read_binding "$YREPO/docs/conventions/work-items.yaml"
write_binding "$YOVERLAY" 'ai_disclaimer: true'
assert_succeeds "YAML overlay with no tracker key is inert" "success" "failure" \
  wit_read_binding "$YREPO/docs/conventions/work-items.yaml"
rm -f "$YOVERLAY"

# --- legacy JSON fallback, with a one-line notice, when the YAML has no binding ---

JREPO="$(yaml_repo json-fallback-repo)"
write_binding "$JREPO/docs/conventions/work-items.yaml" 'ai_disclaimer: false'
write_binding "$JREPO/.work-item-tracker.json" "$VALID"
OUT="$(unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$JREPO" wit_find_binding)"
assert_eq "legacy JSON read when the YAML has no tracker key" "$JREPO/.work-item-tracker.json" "$OUT"
ERR="$(unset WORK_ITEM_TRACKER_BINDING && wit_read_binding "$OUT" 2>&1 >/dev/null)"
assert_contains "legacy JSON read prints a notice" "$ERR" "notice: read the legacy binding $JREPO/.work-item-tracker.json"
assert_eq "the notice is one line" "1" "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')"

# --- neither: no YAML binding and no legacy JSON → no binding (the caller stops) ---

NREPO="$(yaml_repo neither-repo)"
write_binding "$NREPO/docs/conventions/work-items.yaml" 'ai_disclaimer: false'
if (unset WORK_ITEM_TRACKER_BINDING && CLAUDE_PROJECT_DIR="$NREPO" wit_find_binding >/dev/null); then
  fail "neither YAML nor JSON binding → discovery fails" "failure" "success"
else
  pass "neither YAML nor JSON binding → discovery fails"
fi

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

[[ $FAILED -eq 0 ]] || exit 1
