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

mkt_catalog() {
  # mkt_catalog <dir> <marketplace-name> <plugin-name> <entry-source>: write a
  # directory marketplace's .claude-plugin/marketplace.json with one plugin entry
  # whose source is a path relative to <dir>
  mkdir -p "$1/.claude-plugin"
  jq -n --arg m "$2" --arg n "$3" --arg s "$4" \
    '{name:$m,owner:{name:"fixture"},plugins:[{name:$n,source:$s}]}' \
    >"$1/.claude-plugin/marketplace.json"
}

settings_mkt() {
  # settings_mkt <root> <marketplace-name> <path>: declare a directory-source
  # marketplace in the project settings, keeping whatever the file already holds
  local f="$1/project/.claude/settings.json"
  [[ -f "$f" ]] || printf '{}\n' >"$f"
  jq --arg m "$2" --arg p "$3" '.extraKnownMarketplaces[$m] = {source:{source:"directory",path:$p}}' \
    "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

known_mkt() {
  # known_mkt <root> <marketplace-name> <dir>: record a directory-source
  # marketplace in the user dir's plugins/known_marketplaces.json
  local f="$1/user/plugins/known_marketplaces.json"
  mkdir -p "$1/user/plugins"
  [[ -f "$f" ]] || printf '{}\n' >"$f"
  jq --arg m "$2" --arg p "$3" '.[$m] = {source:{source:"directory",path:$p},installLocation:$p}' \
    "$f" >"$f.tmp" && mv "$f.tmp" "$f"
}

hook_file() {
  # hook_file <path> <event> <matcher> <command>: write a one-hook hooks.json
  mkdir -p "$(dirname "$1")"
  jq -n --arg e "$2" --arg m "$3" --arg c "$4" \
    '{hooks:{($e):[{matcher:$m,hooks:[{type:"command",command:$c}]}]}}' >"$1"
}

run() {
  # run <root> [args...] — invoke the script against a fixture machine
  HOOK_COVERAGE_FIXTURE_DIR="$1/project" \
    HOOK_COVERAGE_USER_DIR="$1/user" \
    HOOK_COVERAGE_INSTALLED_JSON="$1/registry.json" \
    bash "$SCRIPT" "${@:2}"
}

json_field() {
  # json_field <json> <jq-filter>: echo the filter's raw result, or nothing
  printf '%s' "$1" | jq -r "$2" 2>/dev/null
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
# A downstream engine reads this document, so every hook entry field the hook
# schema allows (timeout, type, if, shell, args) rides along, each plugin row
# names the directory its hooks came from, and the project root is stated.
m="$(make_machine jsonout)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
mkdir -p "$m/plugins/guard/hooks"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"j.sh","timeout":30,"if":"Bash(git *)","shell":"bash","args":["-x","--y"]}]}]}}' \
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
assert_contains "case 9: project_root carried" "$(json_field "$out" '.project_root')" "$m/project"
assert_contains "case 9: hook timeout carried as a number" "$(json_field "$out" '.hooks[0].timeout')" "30"
assert_contains "case 9: hook type carried" "$(json_field "$out" '.hooks[0].type')" "command"
assert_contains "case 9: hook if carried" "$(json_field "$out" '.hooks[0].if')" "Bash(git *)"
assert_contains "case 9: hook shell carried" "$(json_field "$out" '.hooks[0].shell')" "bash"
assert_contains "case 9: hook args carried as an array" "$(json_field "$out" '.hooks[0].args | tojson')" '["-x","--y"]'
assert_contains "case 9: plugin path carried" "$(json_field "$out" '.plugins[0].path')" "$m/plugins/guard"
assert_contains "case 9: divergence array present" "$(json_field "$out" '.divergence | type')" "array"

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

# --- Case 14: a directory-source marketplace is read from its checkout -------
# The session loads a directory marketplace's plugin from the marketplace
# directory itself, not from the registry's versioned cache snapshot. A cache
# taken at an earlier commit can lack a hook the checkout ships, so the loaded
# directory is what gets enumerated and the pair is reported as divergence.
m="$(make_machine mkt-directory)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
settings_mkt "$m" "mkt" "$m/mkt"
mkt_catalog "$m/mkt" "mkt" "guard" "./plugins/guard"
hook_file "$m/mkt/plugins/guard/hooks/hooks.json" PreToolUse '^mcp__github__(push_files|create_or_update_file)$' "loaded-hook.sh"
hook_file "$m/cache/mkt/guard/0.9.0/hooks/hooks.json" PreToolUse Bash "cache-only-hook.sh"
reg "$m" "guard@mkt" "$m/cache/mkt/guard/0.9.0"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 14: exit 0" 0 "$rc"
assert_contains "case 14: hook from the marketplace directory enumerated" "$out" "loaded-hook.sh"
assert_not_contains "case 14: cache-only hook not enumerated" "$out" "cache-only-hook.sh"
assert_contains "case 14: plugin row says where it loaded from" "$out" "(loaded from marketplace directory)"
assert_contains "case 14: divergence block present" "$out" "Cache-versus-loaded divergence (1):"
assert_contains "case 14: divergence names the loaded path" "$out" "guard@mkt: loads $m/mkt/plugins/guard;"
assert_contains "case 14: divergence names the cache path" "$out" "registry cache at $m/cache/mkt/guard/0.9.0"
assert_contains "case 14: divergence is info" "$out" "Info: the session loads the marketplace directory"
assert_contains "case 14: inventory complete" "$out" "INVENTORY: complete"

# --- Case 15: directory marketplace with no registry file is still complete --
# Before the marketplace route, an absent installed_plugins.json made every
# enabled plugin UNREADABLE. A plugin the session loads from a marketplace
# directory never needed the registry, so its absence is not a gap here. The
# relative marketplace path exercises project-root resolution.
m="$(make_machine mkt-no-registry)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
settings_mkt "$m" "mkt" "./mkt"
mkt_catalog "$m/project/mkt" "mkt" "guard" "./plugins/guard"
hook_file "$m/project/mkt/plugins/guard/hooks/hooks.json" PreToolUse Bash "no-registry-hook.sh"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 15: exit 0 without a registry" 0 "$rc"
assert_contains "case 15: hook enumerated" "$out" "no-registry-hook.sh"
assert_contains "case 15: inventory complete" "$out" "INVENTORY: complete"
assert_not_contains "case 15: missing registry not reported" "$out" "installed_plugins.json not found"
assert_not_contains "case 15: no divergence without a cache path" "$out" "Cache-versus-loaded divergence"

# --- Case 16: a marketplace known only through known_marketplaces.json -------
# `claude plugin marketplace add <dir>` records the marketplace in the user
# dir's known_marketplaces.json with an installLocation and no settings entry.
m="$(make_machine mkt-known)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
known_mkt "$m" "mkt" "$m/mkt/"
mkt_catalog "$m/mkt" "mkt" "guard" "plugins/guard"
hook_file "$m/mkt/plugins/guard/hooks/hooks.json" PreToolUse Bash "known-mkt-hook.sh"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 16: exit 0" 0 "$rc"
assert_contains "case 16: hook enumerated via installLocation" "$out" "known-mkt-hook.sh"
assert_contains "case 16: plugin row says where it loaded from" "$out" "(loaded from marketplace directory)"
assert_contains "case 16: inventory complete" "$out" "INVENTORY: complete"

# --- Case 17: a plugin absent from the catalog falls back to the registry ----
m="$(make_machine mkt-fallback)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
settings_mkt "$m" "mkt" "$m/mkt"
mkt_catalog "$m/mkt" "mkt" "other" "./plugins/other"
mkdir -p "$m/mkt/plugins/other"
hook_file "$m/plugins/guard/hooks/hooks.json" PreToolUse Bash "registry-hook.sh"
reg "$m" "guard@mkt" "$m/plugins/guard"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 17: exit 0" 0 "$rc"
assert_contains "case 17: registry path enumerated" "$out" "registry-hook.sh"
assert_not_contains "case 17: not marked as marketplace-loaded" "$out" "(loaded from marketplace directory)"
assert_not_contains "case 17: no divergence" "$out" "Cache-versus-loaded divergence"

# --- Case 18: --json carries the divergence array ----------------------------
m="$(make_machine mkt-json)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
settings_mkt "$m" "mkt" "$m/mkt"
mkt_catalog "$m/mkt" "mkt" "guard" "./plugins/guard"
hook_file "$m/mkt/plugins/guard/hooks/hooks.json" PreToolUse Bash "loaded-json-hook.sh"
hook_file "$m/cache/guard/hooks/hooks.json" PreToolUse Bash "cached-json-hook.sh"
reg "$m" "guard@mkt" "$m/cache/guard"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 18: exit 0" 0 "$rc"
if printf '%s' "$out" | jq empty 2>/dev/null; then
  pass "case 18: --json output is valid JSON"
else
  fail "case 18: --json output is valid JSON" "jq could not parse it"
fi
assert_contains "case 18: divergence plugin" "$(json_field "$out" '.divergence[0].plugin')" "guard@mkt"
assert_contains "case 18: divergence loaded path" "$(json_field "$out" '.divergence[0].loaded')" "$m/mkt/plugins/guard"
assert_contains "case 18: divergence cached path" "$(json_field "$out" '.divergence[0].cached')" "$m/cache/guard"
assert_contains "case 18: plugin path is the loaded directory" "$(json_field "$out" '.plugins[0].path')" "$m/mkt/plugins/guard"
assert_contains "case 18: inventory complete despite divergence" "$(json_field "$out" '.inventory')" "complete"
assert_contains "case 18: args is an array, encoded once" "$(json_field "$out" '.hooks[0].args | type')" "array"
assert_contains "case 18: lever state is complete when every scope parsed" "$(json_field "$out" '.lever_state')" "complete"

# --- Case 20: a scope that does not parse leaves the lever state unknown -----
m="$(make_machine lever-unknown)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
printf '{not json\n' >"$m/project/.claude/settings.local.json"
settings_mkt "$m" "mkt" "$m/mkt"
mkt_catalog "$m/mkt" "mkt" "guard" "./plugins/guard"
hook_file "$m/mkt/plugins/guard/hooks/hooks.json" PreToolUse Bash "loaded-hook.sh"
rc=0
out=$(run "$m" --json 2>&1) || rc=$?
assert_exit "case 20: an unparsed scope leaves the inventory partial" 1 "$rc"
assert_contains "case 20: lever state is unknown" "$(json_field "$out" '.lever_state')" "unknown"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_contains "case 20: the text report says the lever state is unknown" "$out" "lever state: UNKNOWN"

# --- Case 19: an unparsable directory catalog is reported, not treated as absent
m="$(make_machine mkt-badcatalog)"
printf '{"enabledPlugins":{"guard@mkt":true}}\n' >"$m/project/.claude/settings.json"
settings_mkt "$m" "mkt" "$m/mkt"
mkdir -p "$m/mkt/.claude-plugin"
printf '{"name":"mkt","plugins":[\n' >"$m/mkt/.claude-plugin/marketplace.json"
hook_file "$m/plugins/guard/hooks/hooks.json" PreToolUse Bash "registry-hook.sh"
reg "$m" "guard@mkt" "$m/plugins/guard"
rc=0
out=$(run "$m" 2>&1) || rc=$?
assert_exit "case 19: an unparsable catalog leaves the inventory partial" 1 "$rc"
assert_contains "case 19: the catalog is named as unreadable" "$out" "marketplace:mkt"
assert_contains "case 19: the reason is the parse failure" "$out" "not valid JSON"
assert_contains "case 19: the registry route still enumerates the plugin" "$out" "registry-hook.sh"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
