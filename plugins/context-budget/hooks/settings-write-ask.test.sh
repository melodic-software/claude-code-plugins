#!/usr/bin/env bash
# Contract test for the settings-write ask checkpoint hook.
#
# Contract: a Write/Edit/MultiEdit/NotebookEdit whose target is a Claude Code
# settings surface (settings.json / settings.local.json under any .claude
# directory, or managed-settings.json) gets permissionDecision "ask"; every
# other payload gets NO output and exit 0. Fail-open on garbage input. Kill
# switch via the CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED mirror.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/settings-write-ask.mjs"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
FAKEHOME="$WORK/home"
mkdir -p "$FAKEHOME/.claude"

# run <tool_name> <file_path> [env KEY=VALUE] — prints hook stdout
run() {
  local tool="$1" path="$2" kv="${3:-}"
  local payload
  payload=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$path")
  if [[ -n "$kv" ]]; then
    env "$kv" node "$HOOK" <<<"$payload"
  else
    node "$HOOK" <<<"$payload"
  fi
}

out=$(run Write "$WORK/repo/.claude/settings.json")
grep -q '"permissionDecision":"ask"' <<<"$out" &&
  ok "project settings.json write asks" ||
  fail "project settings.json write did not ask: $out"

out=$(run Edit "$WORK/repo/.claude/settings.local.json")
grep -q '"permissionDecision":"ask"' <<<"$out" &&
  ok "settings.local.json edit asks" ||
  fail "settings.local.json edit did not ask"

out=$(run Write "$WORK/managed/managed-settings.json")
grep -q '"permissionDecision":"ask"' <<<"$out" &&
  ok "managed-settings.json write asks" ||
  fail "managed-settings.json write did not ask"

out=$(run Write "$FAKEHOME/.claude/settings.json" "HOME=$FAKEHOME")
grep -q 'never writes user-global' <<<"$out" &&
  ok "user-global settings write carries the print-only note" ||
  fail "user-global note missing: $out"

out=$(run Write "$WORK/repo/src/settings.json")
[[ -z "$out" ]] &&
  ok "a non-.claude settings.json passes silently (hook precision)" ||
  fail "non-settings path produced output: $out"

out=$(run Write "$WORK/repo/.claude/skills/x/SKILL.md")
[[ -z "$out" ]] &&
  ok "other .claude files pass silently" ||
  fail "non-settings .claude file produced output"

out=$(run Read "$WORK/repo/.claude/settings.json")
[[ -z "$out" ]] &&
  ok "non-mutating tools pass silently" ||
  fail "non-mutating tool produced output"

out=$(run Write "$WORK/repo/.claude/settings.json" "CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED=false")
[[ -z "$out" ]] &&
  ok "kill switch disables the checkpoint" ||
  fail "kill switch ignored"

out=$(printf 'not json at all' | node "$HOOK")
rc=$?
[[ $rc -eq 0 && -z "$out" ]] &&
  ok "garbage input fails open (exit 0, no output)" ||
  fail "garbage input: rc=$rc out=$out"

# Case variants resolve to the same file on macOS/Windows filesystems and
# must still ask — a case-sensitive match would be a silent bypass there.
out=$(run Write "$WORK/repo/.claude/Settings.json")
grep -q '"permissionDecision":"ask"' <<<"$out" &&
  ok "case-variant settings path still asks (case-insensitive filesystems)" ||
  fail "case-variant path bypassed the checkpoint: $out"

out=$(run Edit "$WORK/repo/.claude/settings.LOCAL.json")
grep -q '"permissionDecision":"ask"' <<<"$out" &&
  ok "case-variant settings.local path still asks" ||
  fail "case-variant local path bypassed the checkpoint"

# Windows-style path separators must still match.
# portability-ok: the doubled backslashes are literal JSON escapes for printf, not a GNU regex class
out=$(printf '{"tool_name":"Write","tool_input":{"file_path":"C:\\\\repo\\\\.claude\\\\settings.json"}}' | node "$HOOK")
grep -q '"permissionDecision":"ask"' <<<"$out" &&
  ok "backslash paths normalize and ask" ||
  fail "backslash path missed: $out"

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
