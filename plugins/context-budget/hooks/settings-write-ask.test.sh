#!/usr/bin/env bash
# Contract test for the settings-write ask checkpoint hook.
#
# Contract: a Write/Edit/NotebookEdit whose target is a settings file Claude
# Code reads gets permissionDecision "ask": settings(.local).json in the user
# settings directory ($CLAUDE_CONFIG_DIR, else ~/.claude) or in .claude/ under
# the project directory, the payload cwd or its git toplevel, plus
# managed-settings.json and managed-settings.d/*.json in the managed system
# directory, case-insensitively, since macOS and Windows filesystems resolve
# case variants to the same file. Every other payload, including a fixture
# named .claude/settings.json elsewhere in the tree, gets NO output and exit 0.
# Fail-open on garbage input. Kill switch via the
# CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED mirror.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

# The session running this test may export these; the hook reads them.
unset CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR GIT_DIR GIT_WORK_TREE GIT_CONFIG

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
REPO="$WORK/repo"
mkdir -p "$FAKEHOME/.claude" "$REPO/sub"
git init -q "$REPO"

# run <tool_name> <file_path> [cwd] [env KEY=VALUE] — prints hook stdout
run() {
  local tool="$1" path="$2" cwd="${3:-$REPO}" kv="${4:-}"
  local payload
  payload=$(printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$cwd" "$path")
  if [[ -n "$kv" ]]; then
    env HOME="$FAKEHOME" "$kv" node "$HOOK" <<<"$payload"
  else
    env HOME="$FAKEHOME" node "$HOOK" <<<"$payload"
  fi
}

assert_asks "$(run Write "$REPO/.claude/settings.json")" \
  "project settings.json write asks"

assert_asks "$(run Edit "$REPO/.claude/settings.local.json")" \
  "settings.local.json edit asks"

assert_asks "$(run Edit "$REPO/.claude/settings.local.json" "$REPO/sub")" \
  "settings at the git toplevel asks from a subdirectory cwd"

assert_asks "$(run Write "$WORK/elsewhere/.claude/settings.json" "$REPO" "CLAUDE_PROJECT_DIR=$WORK/elsewhere")" \
  "settings under CLAUDE_PROJECT_DIR asks"

assert_asks "$(run Write "/etc/claude-code/managed-settings.json")" \
  "managed-settings.json in the managed directory asks"

assert_asks "$(run Write "/etc/claude-code/managed-settings.d/10-team.json")" \
  "a managed-settings.d drop-in asks"

out=$(run Write "$FAKEHOME/.claude/settings.json")
if grep -q 'never writes user-global' <<<"$out"; then
  ok "user-global settings write carries the print-only note"
else
  fail "user-global note missing: $out"
fi

assert_asks "$(run Write "$WORK/cfg/settings.json" "$REPO" "CLAUDE_CONFIG_DIR=$WORK/cfg")" \
  "settings in CLAUDE_CONFIG_DIR asks"

# Hook precision: a file named like a settings file that Claude Code never
# reads must pass silently.
assert_silent "$(run Write "$REPO/tests/fixtures/.claude/settings.json")" \
  "a fixture .claude/settings.json below the project root passes silently"

assert_silent "$(run Write "$REPO/sub/.claude/settings.local.json")" \
  "a nested .claude/settings.local.json outside cwd and root passes silently"

assert_silent "$(run Write "$REPO/docs/managed-settings.json")" \
  "a managed-settings.json outside the managed directory passes silently"

assert_silent "$(run Write "$REPO/src/settings.json")" \
  "a non-.claude settings.json passes silently"

assert_silent "$(run Write "$REPO/.claude/skills/x/SKILL.md")" \
  "other .claude files pass silently"

assert_silent "$(run Read "$REPO/.claude/settings.json")" \
  "non-mutating tools pass silently"

assert_silent "$(run Write "$REPO/.claude/settings.json" "$REPO" "CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED=false")" \
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
assert_asks "$(run Write "$REPO/.claude/Settings.json")" \
  "case-variant settings path still asks (case-insensitive filesystems)"

assert_asks "$(run Edit "$REPO/.claude/settings.LOCAL.json")" \
  "case-variant settings.local path still asks"

# Windows-style path separators must still match.
# portability-ok: the doubled backslashes are literal JSON escapes for printf, not a GNU regex class
assert_asks "$(printf '{"tool_name":"Write","cwd":"C:\\\\repo","tool_input":{"file_path":"C:\\\\repo\\\\.claude\\\\settings.json"}}' | node "$HOOK")" \
  "backslash paths normalize and ask"

# The hook is inert unless hooks.json routes the tools to it, so the registered
# matcher is part of the contract.
matcher=$(node -e '
  const h = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const row = h.hooks.PreToolUse.find((r) =>
    r.hooks.some((c) => JSON.stringify(c).includes("settings-write-ask")));
  process.stdout.write(row ? row.matcher : "");
' "$SCRIPT_DIR/hooks.json")
if [[ "$matcher" == "Write|Edit|NotebookEdit" ]]; then
  ok "hooks.json routes exactly Write, Edit and NotebookEdit to the hook"
else
  fail "hooks.json matcher is '$matcher'"
fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
