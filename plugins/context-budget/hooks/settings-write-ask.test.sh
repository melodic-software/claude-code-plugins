#!/usr/bin/env bash
# Contract test for the settings-write ask checkpoint hook.
#
# Contract: a Write/Edit/MultiEdit/NotebookEdit whose target is a Claude Code
# settings surface (settings.json / settings.local.json under any .claude
# directory, or managed-settings.json — case-insensitively, since macOS and
# Windows filesystems resolve case variants to the same file) gets
# permissionDecision "ask"; every other payload gets NO output and exit 0.
# Fail-open on garbage input. Kill switch via the
# CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED mirror.
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
# assert_asks <hook-output> <message> — the payload must have been asked
assert_asks() {
  if grep -q '"permissionDecision":"ask"' <<<"$1"; then
    ok "$2"
  else
    fail "$2 — no ask in output: $1"
  fi
}
# assert_silent <hook-output> <message> — the payload must pass untouched
assert_silent() {
  if [[ -z "$1" ]]; then
    ok "$2"
  else
    fail "$2 — unexpected output: $1"
  fi
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

assert_asks "$(run Write "$WORK/repo/.claude/settings.json")" \
  "project settings.json write asks"

assert_asks "$(run Edit "$WORK/repo/.claude/settings.local.json")" \
  "settings.local.json edit asks"

assert_asks "$(run Write "$WORK/managed/managed-settings.json")" \
  "managed-settings.json write asks"

out=$(run Write "$FAKEHOME/.claude/settings.json" "HOME=$FAKEHOME")
if grep -q 'never writes user-global' <<<"$out"; then
  ok "user-global settings write carries the print-only note"
else
  fail "user-global note missing: $out"
fi

assert_silent "$(run Write "$WORK/repo/src/settings.json")" \
  "a non-.claude settings.json passes silently (hook precision)"

assert_silent "$(run Write "$WORK/repo/.claude/skills/x/SKILL.md")" \
  "other .claude files pass silently"

assert_silent "$(run Read "$WORK/repo/.claude/settings.json")" \
  "non-mutating tools pass silently"

assert_silent "$(run Write "$WORK/repo/.claude/settings.json" "CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED=false")" \
  "kill switch disables the checkpoint"

out=$(printf 'not json at all' | node "$HOOK")
rc=$?
if [[ $rc -eq 0 && -z "$out" ]]; then
  ok "garbage input fails open (exit 0, no output)"
else
  fail "garbage input: rc=$rc out=$out"
fi

# Case variants resolve to the same file on macOS/Windows filesystems and
# must still ask — a case-sensitive match would be a silent bypass there.
assert_asks "$(run Write "$WORK/repo/.claude/Settings.json")" \
  "case-variant settings path still asks (case-insensitive filesystems)"

assert_asks "$(run Edit "$WORK/repo/.claude/settings.LOCAL.json")" \
  "case-variant settings.local path still asks"

# Windows-style path separators must still match.
# portability-ok: the doubled backslashes are literal JSON escapes for printf, not a GNU regex class
assert_asks "$(printf '{"tool_name":"Write","tool_input":{"file_path":"C:\\\\repo\\\\.claude\\\\settings.json"}}' | node "$HOOK")" \
  "backslash paths normalize and ask"

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
