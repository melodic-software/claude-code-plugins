#!/usr/bin/env bash
# Self-contained tests for check-hook-coverage.sh (no external test lib — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/check-hook-coverage.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

# Every case builds a whole fake machine: a project root, a user config dir, an
# installed-plugin registry, and plugin directories. Nothing here reads the real
# machine, so the registry's version-directory layout is fixture data rather than
# a live-cache dependency.
make_machine() {
  # make_machine <name> — echo the fixture root; creates <root>/project and <root>/user
  local root="$TEST_TMPDIR/$1"
  mkdir -p "$root/project/.claude" "$root/user" "$root/plugins"
  printf '%s' "$root"
}

reg() {
  # reg <root> <plugin-key> <install-path> [scope] [project-path]
  local root="$1" key="$2" path="$3" scope="${4:-user}" project="${5:-}"
  local f="$1/registry.json"
  [[ -f "$f" ]] || printf '{"plugins":{}}\n' >"$f"
  jq --arg k "$key" --arg p "$path" --arg s "$scope" --arg proj "$project" \
    '.plugins[$k] += [{"scope":$s,"installPath":$p,"version":"1.0.0","projectPath":$proj}]' \
    "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

run() {
  # run <root> [args...] — invoke the script against a fixture machine
  HOOK_COVERAGE_FIXTURE_DIR="$1/project" \
    HOOK_COVERAGE_USER_DIR="$1/user" \
    HOOK_COVERAGE_INSTALLED_JSON="$1/registry.json" \
    bash "$SCRIPT" "${@:2}"
}

# --- Case 1: a plugin's hooks/hooks.json is enumerated ------------------------
# This is the whole point of the script: before it, a PreToolUse hook shipped by
# an enabled plugin was invisible to the audit, and three of the skill's own
# surfaces said the enumeration was impossible.
m="$(make_machine plugin-hooks)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/guard/hooks"
# shellcheck disable=SC2016  # ${CLAUDE_PLUGIN_ROOT} is the literal placeholder a plugin hook ships; it must stay unexpanded
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/block-force-push.sh"}]}]}}' \
  >"$m/plugins/guard/hooks/hooks.json"
reg "$m" "guard@mkt" "$m/plugins/guard"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 1: complete inventory exits 0" 0 "$rc"
assert_contains "case 1: plugin hook enumerated" "$out" "plugin:guard@mkt"
assert_contains "case 1: event surfaced" "$out" "PreToolUse"
assert_contains "case 1: matcher surfaced" "$out" "Bash"
assert_contains "case 1: command surfaced" "$out" "block-force-push.sh"
assert_contains "case 1: inventory declared complete" "$out" "INVENTORY: complete"

# --- Case 2: settings-declared hooks are still enumerated, per scope ----------
m="$(make_machine settings-hooks)"
printf '%s\n' '{"hooks":{"PostToolUse":[{"matcher":"Write","hooks":[{"type":"command","command":"fmt.sh"}]}]}}' \
  >"$m/project/.claude/settings.json"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"greet.sh"}]}]}}' \
  >"$m/user/settings.json"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 2: exit 0" 0 "$rc"
assert_contains "case 2: project scope labelled" "$out" "settings:project"
assert_contains "case 2: user scope labelled" "$out" "settings:user"
assert_contains "case 2: missing matcher defaults to *" "$out" "SessionStart"

# --- Case 3: an enabled plugin with no registry entry is PARTIAL, not absent ---
# The fail-open this script exists to remove. "Could not look" must never render
# as "looked and found nothing", because Category B's narrowing 3 turns on it.
m="$(make_machine unresolved)"
printf '{"enabledPlugins":{"ghost@mkt":true}}\n' >"$m/project/.claude/settings.json"
printf '{"plugins":{}}\n' >"$m/registry.json"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 3: partial inventory exits 1" 1 "$rc"
assert_contains "case 3: plugin marked UNRESOLVED" "$out" "UNRESOLVED"
assert_contains "case 3: inventory declared partial" "$out" "INVENTORY: partial"
assert_not_contains "case 3: never claims completeness" "$out" "INVENTORY: complete"

# --- Case 4: a CRLF settings file still resolves its plugins ------------------
# Regression guard for the defect found while writing this script. On Git for
# Windows, jq writes stdout in text mode and appends a CR to every line — its
# own output stream, not the input's line endings — so a plugin key read out of
# jq was "name@mkt\r", every registry lookup missed, and the plugin was reported
# as not installed on a machine where it was installed. Measured: removing the
# CR strip fails 17 of this file's 34 checks, cases 1/5/6/9 included, whose
# fixtures are pure LF. This case pins the harsher input on top of that.
m="$(make_machine crlf)"
printf '{\r\n  "enabledPlugins": {\r\n    "guard@mkt": true\r\n  }\r\n}\r\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/guard/hooks"
printf '%s\r\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"crlf-hook.sh"}]}]}}' \
  >"$m/plugins/guard/hooks/hooks.json"
reg "$m" "guard@mkt" "$m/plugins/guard"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 4: CRLF settings still complete" 0 "$rc"
assert_contains "case 4: CRLF plugin resolved" "$out" "crlf-hook.sh"
assert_not_contains "case 4: not reported unresolved" "$out" "UNRESOLVED"

# --- Case 5: hooks declared inline in plugin.json ----------------------------
# plugins-reference documents `hooks` as string|array|object; an object is an
# inline config. A script that only looked for hooks/hooks.json would report
# this plugin as hookless.
m="$(make_machine inline-hooks)"
printf '{"enabledPlugins":{"inline@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/inline/.claude-plugin"
printf '%s\n' '{"name":"inline","version":"1.0.0","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"inline-guard.sh"}]}]}}' \
  >"$m/plugins/inline/.claude-plugin/plugin.json"
reg "$m" "inline@mkt" "$m/plugins/inline"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 5: exit 0" 0 "$rc"
assert_contains "case 5: inline hook enumerated" "$out" "inline-guard.sh"

# --- Case 6: hooks declared at a custom path in plugin.json ------------------
m="$(make_machine custom-path)"
printf '{"enabledPlugins":{"custom@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/custom/.claude-plugin" "$m/plugins/custom/config"
printf '%s\n' '{"name":"custom","version":"1.0.0","hooks":"./config/hooks.json"}' \
  >"$m/plugins/custom/.claude-plugin/plugin.json"
printf '%s\n' '{"hooks":{"PostToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"custom-path-hook.sh"}]}]}}' \
  >"$m/plugins/custom/config/hooks.json"
reg "$m" "custom@mkt" "$m/plugins/custom"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 6: exit 0" 0 "$rc"
assert_contains "case 6: custom-path hook enumerated" "$out" "custom-path-hook.sh"

# --- Case 7: a declared hook path that does not exist is PARTIAL -------------
m="$(make_machine missing-path)"
printf '{"enabledPlugins":{"broken@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/broken/.claude-plugin"
printf '%s\n' '{"name":"broken","version":"1.0.0","hooks":"./config/hooks.json"}' \
  >"$m/plugins/broken/.claude-plugin/plugin.json"
reg "$m" "broken@mkt" "$m/plugins/broken"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 7: missing declared path is partial" 1 "$rc"
assert_contains "case 7: names the missing path" "$out" "config/hooks.json"

# --- Case 8: suppression levers are reported ---------------------------------
# A hook that cannot run is not coverage, so an inventory that lists hooks
# without listing disableAllHooks would license exactly the wrong narrowing.
m="$(make_machine levers)"
printf '{"disableAllHooks":true,"enabledPlugins":{}}\n' >"$m/project/.claude/settings.json"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 8: exit 0" 0 "$rc"
assert_contains "case 8: lever reported" "$out" "disableAllHooks"
assert_contains "case 8: lever value reported" "$out" "true"

# --- Case 9: --json emits parseable JSON with the inventory verdict ----------
m="$(make_machine jsonout)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/guard/hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"j.sh"}]}]}}' \
  >"$m/plugins/guard/hooks/hooks.json"
reg "$m" "guard@mkt" "$m/plugins/guard"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 9: exit 0" 0 "$rc"
if printf '%s' "$out" | jq empty 2>/dev/null; then
  pass "case 9: --json output is valid JSON"
else
  fail "case 9: --json output is valid JSON" "jq could not parse it"
fi
assert_contains "case 9: inventory verdict present" "$out" '"inventory": "complete"'
assert_contains "case 9: hook command present" "$out" "j.sh"

# --- Case 10: no settings scope at all is fatal, not an empty inventory -------
m="$(make_machine nosettings)"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 10: exit 2 with no readable scope" 2 "$rc"
assert_contains "case 10: says why" "$out" "no readable settings scope"

# --- Case 11: jq missing is fatal --------------------------------------------
real_bash=$(command -v bash)
empty_path_dir="$TEST_TMPDIR/empty-path"
mkdir -p "$empty_path_dir"
rc=0
err_out=$(PATH="$empty_path_dir" "$real_bash" "$SCRIPT" 2>&1) || rc=$?
assert_exit "case 11: exit 2 when jq missing" 2 "$rc"
assert_contains "case 11: jq required message" "$err_out" "jq required"

# --- Case 12: local scope disables a plugin enabled in user scope ----------
m="$(make_machine scope-precedence)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/user/settings.json"
printf '{"enabledPlugins":{"guard@mkt":false}}\n' >"$m/project/.claude/settings.local.json"
mkdir -p "$m/plugins/guard/hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"should-not-run.sh"}]}]}}' \
  >"$m/plugins/guard/hooks/hooks.json"
reg "$m" "guard@mkt" "$m/plugins/guard"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 12: exit 0" 0 "$rc"
assert_not_contains "case 12: locally disabled plugin not enumerated" "$out" "should-not-run.sh"

# --- Case 13: project-scoped install record wins over user -------------------
m="$(make_machine install-scope)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/guard-user/hooks" "$m/plugins/guard-project/hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"user-hook.sh"}]}]}}' \
  >"$m/plugins/guard-user/hooks/hooks.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"project-hook.sh"}]}]}}' \
  >"$m/plugins/guard-project/hooks/hooks.json"
reg "$m" "guard@mkt" "$m/plugins/guard-user" "user" ""
reg "$m" "guard@mkt" "$m/plugins/guard-project" "project" "$m/project"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 13: exit 0" 0 "$rc"
assert_contains "case 13: project install record used" "$out" "project-hook.sh"
assert_not_contains "case 13: user install record not used" "$out" "user-hook.sh"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
