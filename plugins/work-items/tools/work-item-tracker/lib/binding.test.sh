#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by sourced tests/lib.sh
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
  if wit_read_binding "$BINDING"; then
    fail "$label" "failure" "success"
  else
    pass "$label"
  fi
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
# not the caller's CWD (a verb invoked from a subdirectory must resolve the
# same store as one invoked from the repo root) ---

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

# --- container_label: config.container_label remap and default fallback (a
# sibling of config.role_labels — the container marker is not a worker role) ---

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
write_binding "$OVERLAY" '{"docs":"see CONTRACT.md"}'
if wit_read_binding "$OBINDING"; then
  pass "docs key allowed in the overlay"
else
  fail "docs key allowed in the overlay" "success" "failure"
fi

# Empty scaffolding is inert, not an error.
write_binding "$OVERLAY" '{"config":{}}'
if wit_read_binding "$OBINDING"; then
  pass "empty overlay scaffolding is inert"
else
  fail "empty overlay scaffolding is inert" "success" "failure"
fi

# Deny-by-default: any key outside the allowlist is a configuration error, not a merge.
assert_overlay_rejected() {
  local label="$1" content="$2"
  write_binding "$OVERLAY" "$content"
  if wit_read_binding "$OBINDING" 2>/dev/null; then
    fail "$label" "failure" "success"
  else
    pass "$label"
  fi
}

assert_overlay_rejected "overlay provider override rejected" '{"provider":"local-markdown"}'
assert_overlay_rejected "overlay role_labels rejected" '{"config":{"role_labels":{"human-gated":"x"}}}'
assert_overlay_rejected "overlay container_label rejected" '{"config":{"container_label":"my-map"}}'
assert_overlay_rejected "overlay storage_dir rejected" '{"config":{"storage_dir":"/tmp/x"}}'
assert_overlay_rejected "overlay jira site rejected" '{"config":{"jira":{"site":"evil.example.com"}}}'
assert_overlay_rejected "overlay jira project_keys rejected" '{"config":{"jira":{"project_keys":["ZZ"]}}}'
assert_overlay_rejected "wrong-typed intermediate rejected" '{"config":5}'
assert_overlay_rejected "non-JSON overlay rejected" 'not json'

rm -f "$OVERLAY"

[[ $FAILED -eq 0 ]] || exit 1
