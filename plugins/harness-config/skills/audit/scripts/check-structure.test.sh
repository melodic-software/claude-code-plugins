#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-structure.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

fixture_dir="$TEST_TMPDIR/valid"
mkdir -p "$fixture_dir/.claude"
printf '{"permissions":{"deny":["Read(./.env)"],"ask":[],"allow":["Bash(git status)"]},"enabledPlugins":{"a@m":true}}\n' >"$fixture_dir/.claude/settings.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 1: exit 0 on valid settings" 0 "$rc"
assert_contains "case 1: settings.json facts" "$out" "File: .claude/settings.json"
assert_contains "case 1: valid json" "$out" "Valid JSON: yes"
assert_contains "case 1: deny count" "$out" "Deny count: 1"
assert_contains "case 1: absent local reported" "$out" "Present: no"
assert_not_contains "case 1: no env dump" "$out" "sk-"

fixture_dir="$TEST_TMPDIR/invalid-json"
mkdir -p "$fixture_dir/.claude"
printf '{invalid\n' >"$fixture_dir/.claude/settings.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 2: exit 1 on invalid JSON" 1 "$rc"
assert_contains "case 2: invalid json reported" "$out" "Valid JSON: no"

fixture_dir="$TEST_TMPDIR/unreadable"
mkdir -p "$fixture_dir/.claude"
printf '{"env":{"TOKEN":"sk-not-a-real-secret"}}\n' >"$fixture_dir/.claude/settings.local.json"
printf '{"permissions":{"deny":[]}}\n' >"$fixture_dir/.claude/settings.json"
chmod 000 "$fixture_dir/.claude/settings.local.json" 2>/dev/null
if [[ -r "$fixture_dir/.claude/settings.local.json" ]]; then
  echo "SKIP: case 4 — this platform/user does not enforce chmod 000 on the fixture" >&2
else
  rc=0
  out=$(
    SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
      bash "$SCRIPT" 2>/dev/null
  ) || rc=$?
  assert_exit "case 4: unreadable file does not fail the run" 0 "$rc"
  assert_contains "case 4: reported unreadable" "$out" "Readable: no"
  assert_contains "case 4: reported not inspectable" "$out" "not inspectable"
  assert_not_contains "case 4: not reported as invalid JSON" "$out" "Valid JSON: no"
  assert_not_contains "case 4: no secret leaked" "$out" "sk-"
fi
chmod 600 "$fixture_dir/.claude/settings.local.json" 2>/dev/null

fixture_dir="$TEST_TMPDIR/category-h"
mkdir -p "$fixture_dir/.claude"
printf '{"permissions":{"deny":[]}}\n' >"$fixture_dir/.claude/settings.json"
printf '%s\n' '{"env":{"TOKEN":"sk-not-a-real-secret"},"effortLevel":"max","fallbackModel":["sonnet","haiku","sonnet","opus"],"availableModels":["sonnet","claude-sonnet-4-5"],"enforceAvailableModels":true}' >"$fixture_dir/.claude/settings.local.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 5: exit 0 on valid local settings" 0 "$rc"
assert_contains "case 5: effort level surfaced" "$out" "Effort level: max"
assert_contains "case 5: raw and dedup counts differ" "$out" "Fallback chain: 4 raw, 3 after dedup"
assert_contains "case 5: fallback order preserved" "$out" "Fallback entries: sonnet, haiku, sonnet, opus"
assert_contains "case 5: allowlist entries surfaced" "$out" "Available models: sonnet, claude-sonnet-4-5"
assert_contains "case 5: enforce flag surfaced" "$out" "Enforce available models: true"
assert_contains "case 5: env still counted not dumped" "$out" "Env keys: 1"
assert_not_contains "case 5: no secret leaked" "$out" "sk-"
assert_not_contains "case 5: no env key name leaked" "$out" "TOKEN"

fixture_dir="$TEST_TMPDIR/category-h-absent"
mkdir -p "$fixture_dir/.claude"
printf '%s\n' '{"availableModels":[],"permissions":{"allow":[]}}' >"$fixture_dir/.claude/settings.local.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 6: exit 0" 0 "$rc"
assert_contains "case 6: absent effortLevel is unset" "$out" "Effort level: unset"
assert_contains "case 6: absent fallbackModel is unset" "$out" "Fallback chain: unset"
assert_contains "case 6: empty allowlist is distinct from unset" "$out" "Available models: (empty list)"
assert_contains "case 6: absent enforce flag is unset" "$out" "Enforce available models: unset"

fixture_dir="$TEST_TMPDIR/managed-present"
mkdir -p "$fixture_dir/.claude" "$fixture_dir/policy/managed-settings.d"
printf '%s\n' '{}' >"$fixture_dir/.claude/settings.json"
printf '%s\n' '{"permissions":{"deny":["WebFetch"]},"env":{"ORG_SECRET":"hunter2"},"hooks":{"PreToolUse":[]}}' \
  >"$fixture_dir/policy/managed-settings.json"
printf '%s\n' '{"env":{"B":"2"}}' >"$fixture_dir/policy/managed-settings.d/10-extra.json"
printf '%s\n' '{"env":{"C":"3"}}' >"$fixture_dir/policy/managed-settings.d/20-more.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    SETTINGS_AUDIT_MANAGED_PATH="$fixture_dir/policy/managed-settings.json" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 7: exit 0" 0 "$rc"
assert_contains "case 7: managed file reported" "$out" "managed-settings.json (machine scope)"
assert_contains "case 7: managed deny counted" "$out" "Deny count: 1"
assert_contains "case 7: managed hooks counted" "$out" "Hooks events: 1"
assert_contains "case 7: managed env counted" "$out" "Env keys: 1"
assert_not_contains "case 7: no managed env value leaked" "$out" "hunter2"
assert_not_contains "case 7: no managed env key leaked" "$out" "ORG_SECRET"
assert_contains "case 7: drop-in dir counted" "$out" "Managed drop-in dir: present (2 "

fixture_dir="$TEST_TMPDIR/managed-absent"
mkdir -p "$fixture_dir/.claude"
printf '%s\n' '{}' >"$fixture_dir/.claude/settings.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    SETTINGS_AUDIT_MANAGED_PATH="$fixture_dir/policy/managed-settings.json" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 8: exit 0" 0 "$rc"
assert_contains "case 8: managed absence reported" "$out" "managed-settings.json (machine scope)"
assert_contains "case 8: drop-in absence reported" "$out" "Managed drop-in dir: absent"

fixture_dir="$TEST_TMPDIR/startdir-present"
startdir="$TEST_TMPDIR/startdir-present-cwd"
mkdir -p "$fixture_dir/.claude" "$startdir/.claude"
printf '%s\n' '{}' >"$fixture_dir/.claude/settings.json"
printf '%s\n' '{"permissions":{"allow":["Bash(git status)","Bash(ls)"]}}' >"$startdir/.claude/settings.local.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    SETTINGS_AUDIT_STARTDIR_FIXTURE_DIR="$startdir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 9: exit 0" 0 "$rc"
assert_contains "case 9: start-directory copy reported" "$out" "start-directory copy, pre-v2.1.211"
assert_contains "case 9: names the leftover file" "$out" "$startdir/.claude/settings.local.json"
assert_contains "case 9: its allow rules counted" "$out" "Allow count: 2"
assert_contains "case 9: both-files note emitted" "$out" "permission rules from BOTH files stay in effect"

fixture_dir="$TEST_TMPDIR/startdir-absent"
startdir="$TEST_TMPDIR/startdir-absent-cwd"
mkdir -p "$fixture_dir/.claude" "$startdir"
printf '%s\n' '{}' >"$fixture_dir/.claude/settings.json"
rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    SETTINGS_AUDIT_STARTDIR_FIXTURE_DIR="$startdir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 10: exit 0" 0 "$rc"
assert_not_contains "case 10: no start-directory row" "$out" "start-directory copy"

rc=0
out=$(
  SETTINGS_AUDIT_STRUCTURE_FIXTURE_DIR="$fixture_dir" \
    bash "$SCRIPT" 2>/dev/null
) || rc=$?
assert_exit "case 11: exit 0" 0 "$rc"
assert_not_contains "case 11: same directory is not a second source" "$out" "start-directory copy"

real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(
  PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1
) || rc=$?
assert_exit "case 3: exit 2 when jq missing" 2 "$rc"
assert_contains "case 3: jq required message" "$err_out" "jq required"

report_and_exit
