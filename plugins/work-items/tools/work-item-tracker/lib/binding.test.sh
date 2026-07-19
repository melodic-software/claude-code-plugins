#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by sourced tests/lib.sh
# Tests for lib/binding.sh (CONTRACT.md "Setup (binding file)").
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=binding.sh
source "$SCRIPT_DIR/binding.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

write_binding() {
  printf '%s\n' "$2" >"$1"
}

VALID='{"schema_version":"1.0","provider":"github","config":{"lease_ttl_hours":24}}'

# --- discovery: climb from nested CWD ---

ROOT="$TEST_TMPDIR/repo"
mkdir -p "$ROOT/deep/nested"
write_binding "$ROOT/.work-item-tracker.json" "$VALID"
OUT="$(cd "$ROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING && wit_find_binding)"
assert_eq "climb finds root binding" "$ROOT/.work-item-tracker.json" "$OUT"

# --- discovery: nearest binding wins ---

write_binding "$ROOT/deep/.work-item-tracker.json" "$VALID"
OUT="$(cd "$ROOT/deep/nested" && unset WORK_ITEM_TRACKER_BINDING && wit_find_binding)"
assert_eq "nearest binding wins" "$ROOT/deep/.work-item-tracker.json" "$OUT"

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

[[ $FAILED -eq 0 ]] || exit 1
