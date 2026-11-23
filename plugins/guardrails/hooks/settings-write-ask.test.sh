#!/usr/bin/env bash
# Contract test for the settings-write ask checkpoint hook.
#
# Contract: a Write/Edit/NotebookEdit whose target is a settings file Claude
# Code reads gets permissionDecision "ask": settings.json in the user settings
# directory ($CLAUDE_CONFIG_DIR, else ~/.claude), settings(.local).json in
# .claude/ under the project directory or the payload cwd, settings.local.json
# at the main checkout's root, plus managed-settings.json and
# managed-settings.d/*.json in the managed system directory, case-insensitively, since macOS and Windows filesystems resolve
# case variants to the same file. Every other payload, including a fixture
# named .claude/settings.json elsewhere in the tree, gets NO output and exit 0.
# Fail-open on garbage input. Kill switch via the
# CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED mirror.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.
# test-scope: plugins/guardrails/hooks/hooks.json

set -uo pipefail

unset CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR GIT_DIR GIT_WORK_TREE GIT_CONFIG \
  CLAUDE_CODE_SESSION_ATTENDED GUARDRAILS_SESSION_UNWATCHED
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

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
assert_asks() {
  if grep -q '"permissionDecision":"ask"' <<<"$1"; then
    ok "$2"
  else
    fail "$2 — no ask in output: $1"
  fi
}
assert_denies() {
  if grep -q '"permissionDecision":"deny"' <<<"$1"; then
    ok "$2"
  else
    fail "$2 — no deny in output: $1"
  fi
}
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
git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null \
  commit -q --allow-empty -m init
git -C "$REPO" worktree add -q --detach "$WORK/wt"

run() {
  local tool="$1" path="$2" cwd="${3:-$REPO}"
  shift $(($# < 3 ? $# : 3))
  local payload
  payload=$(printf '{"tool_name":"%s","cwd":"%s","tool_input":{"file_path":"%s"}}' "$tool" "$cwd" "$path")
  env HOME="$FAKEHOME" CLAUDE_CODE_SESSION_ATTENDED=1 "$@" node "$HOOK" <<<"$payload"
}

assert_asks "$(run Write "$REPO/.claude/settings.json")" \
  "project settings.json write asks"

assert_asks "$(run Edit "$REPO/.claude/settings.local.json")" \
  "settings.local.json edit asks"

assert_asks "$(run Edit "$REPO/.claude/settings.local.json" "$REPO/sub")" \
  "settings at the git toplevel asks from a subdirectory cwd"

assert_asks "$(run Edit "$REPO/.claude/settings.local.json" "$WORK/wt")" \
  "the main checkout's settings.local.json asks from a linked worktree cwd"

assert_asks "$(run Write "$WORK/pf/ClaudeCode/managed-settings.json" "$REPO" "PROGRAMFILES=$WORK/pf")" \
  "managed-settings.json under a relocated PROGRAMFILES asks"

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

assert_silent "$(run Write "$REPO/tests/fixtures/.claude/settings.json")" \
  "a fixture .claude/settings.json below the project root passes silently"

assert_silent "$(run Write "$REPO/sub/.claude/settings.local.json")" \
  "a nested .claude/settings.local.json outside cwd and root passes silently"

assert_silent "$(run Write "$REPO/.claude/settings.json" "$REPO/sub")" \
  "a repository-root settings.json passes silently from a subdirectory cwd"

assert_silent "$(run Write "$FAKEHOME/.claude/settings.local.json")" \
  "settings.local.json in the user settings directory passes silently"

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

assert_asks "$(run Write "$REPO/.claude/Settings.json")" \
  "case-variant settings path still asks (case-insensitive filesystems)"

assert_asks "$(run Edit "$REPO/.claude/settings.LOCAL.json")" \
  "case-variant settings.local path still asks"

# Windows-style path separators must still match.
# portability-ok: the doubled backslashes are literal JSON escapes for printf, not a GNU regex class
assert_asks "$(printf '{"tool_name":"Write","cwd":"C:\\\\repo","tool_input":{"file_path":"C:\\\\repo\\\\.claude\\\\settings.json"}}' | CLAUDE_CODE_SESSION_ATTENDED=1 node "$HOOK")" \
  "backslash paths normalize and ask"

assert_denies "$(printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s/.claude/settings.json"}}' "$REPO" "$REPO" | HOME="$FAKEHOME" node "$HOOK")" \
  "CLAUDE_CODE_SESSION_ATTENDED unset denies"

assert_denies "$(run Write "$REPO/.claude/settings.json" "$REPO" "CLAUDE_CODE_SESSION_ATTENDED=0")" \
  "CLAUDE_CODE_SESSION_ATTENDED=0 (claude -p, --bg) denies"

assert_denies "$(run Edit "$FAKEHOME/.claude/settings.json" "$REPO" "CLAUDE_CODE_SESSION_ATTENDED=true")" \
  "an ATTENDED value other than 1 denies"

assert_denies "$(run Write "$REPO/.claude/settings.json" "$REPO" "GUARDRAILS_SESSION_UNWATCHED=1")" \
  "attended but GUARDRAILS_SESSION_UNWATCHED=1 denies"

assert_asks "$(run Write "$REPO/.claude/settings.json" "$REPO" "GUARDRAILS_SESSION_UNWATCHED=0")" \
  "attended with GUARDRAILS_SESSION_UNWATCHED other than 1 asks"

assert_silent "$(run Write "$REPO/src/settings.json" "$REPO" "CLAUDE_CODE_SESSION_ATTENDED=0")" \
  "unattended, an unmatched path still passes silently"

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
