#!/usr/bin/env bash
# test-scope: plugins/*/.mcp.json plugins/harness-config/skills/*/SKILL.md .claude/settings.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$SCRIPT_DIR/inventory.sh"

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_line() {
  if grep -Fxq -- "$3" <<<"$2"; then
    pass "$1"
  else
    fail "$1" "no line exactly equal to: $3"
  fi
}
row_for() {
  printf '%s\n' "$2" | awk -v want="$1" '$1 == want { print; exit }'
}
row6() {
  printf '%s\n' "$2" |
    awk -v want="$1" '$1 == want { printf "%s %s %s %s %s %s", $1, $2, $3, $4, $5, $6; exit }'
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

rc=0
help_out="$(bash "$INVENTORY" --help 2>/dev/null)" || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help documents the never-zero contract" "$help_out" "It never reports that location as 0."


rc=0
bad_out="$(cd "$WORK" && bash "$INVENTORY" --plugin-data /x 2>/dev/null)" || rc=$?
assert_exit "an unknown argument is a usage error" 2 "$rc"
assert_eq "an unknown argument prints no inventory" "" "$bad_out"
bad_err="$(cd "$WORK" && bash "$INVENTORY" --plugin-data /x 2>&1 >/dev/null)"
assert_contains "the usage error names the argument" "$bad_err" "unrecognized argument: --plugin-data"

rc=0
(cd "$WORK" && bash "$INVENTORY" extra-positional >/dev/null 2>&1) || rc=$?
assert_exit "a bare positional argument is a usage error" 2 "$rc"

rc=0
(cd "$WORK" && bash "$INVENTORY" --help --and-more >/dev/null 2>&1) || rc=$?
assert_exit "--help plus a second argument is a usage error" 2 "$rc"


for badroot in "$WORK/no-such-directory" /etc/hosts -leading-dash; do
  rc=0
  bad_root_out="$(INVENTORY_PROJECT_DIR="$badroot" bash "$INVENTORY" 2>/dev/null)" || rc=$?
  assert_exit "unusable project root is fatal: $badroot" 2 "$rc"
  assert_eq "unusable project root emits no table: $badroot" "" "$bad_root_out"
done
bad_root_err="$(INVENTORY_PROJECT_DIR="$WORK/no-such-directory" bash "$INVENTORY" 2>&1 >/dev/null)"
assert_contains "the fatal root message names the root" "$bad_root_err" "$WORK/no-such-directory"
assert_contains "the fatal root message says nothing was counted" "$bad_root_err" "no counts were produced"


GOLD="$WORK/golden"
mkdir -p "$GOLD/.claude/skills/alpha" "$GOLD/.claude/skills/beta" \
  "$GOLD/.claude/agents" "$GOLD/.claude/hooks" "$GOLD/.claude-plugin" \
  "$GOLD/plug1/.claude-plugin" "$GOLD/plug1/hooks" \
  "$GOLD/plug2/.claude-plugin" "$GOLD/plug2/hooks" "$GOLD/plug2/skills/gamma" \
  "$WORK/managed-present" "$WORK/no-lib"

printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}],"Stop":[{"hooks":[{"type":"command","command":"c"}]}]}}' \
  >"$GOLD/.claude/settings.json"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"d"}]}]}}' \
  >"$GOLD/.claude/settings.local.json"
printf '%s\n' '{"enabledPlugins":{"a@m":true,"b@m":true,"c@m":false}}' >"$GOLD/user-settings.json"
printf '%s\n' '{"hooks":{}}' >"$WORK/managed-present/managed-settings.json"

printf -- '---\nname: alpha\nhooks:\n  PreToolUse:\n    - x\n---\nbody\n' >"$GOLD/.claude/skills/alpha/SKILL.md"
printf -- '---\nname: beta\n---\nbody with a hooks: mention in prose\n' >"$GOLD/.claude/skills/beta/SKILL.md"
printf -- '---\nname: one\nhooks:\n  Stop:\n    - y\n---\nbody\n' >"$GOLD/.claude/agents/one.md"
printf -- '---\nname: two\n---\nbody\n' >"$GOLD/.claude/agents/two.md"
printf '#!/bin/sh\n' >"$GOLD/.claude/hooks/h1.sh"
printf '#!/bin/sh\n' >"$GOLD/.claude/hooks/h2.sh"
printf '#!/bin/sh\n' >"$GOLD/.claude/hooks/h1.test.sh"
printf '{}\n' >"$GOLD/.claude/hooks/config.json"

printf '%s\n' '{"name":"plug1"}' >"$GOLD/plug1/.claude-plugin/plugin.json"
printf '%s\n' '{"PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"x"},{"type":"command","command":"y"}]}],"PostToolUse":[{"hooks":[{"type":"command","command":"z"}]}]}' \
  >"$GOLD/plug1/hooks/hooks.json"
printf '#!/bin/sh\n' >"$GOLD/plug1/hooks/run.sh"
printf '#!/bin/sh\n' >"$GOLD/plug1/hooks/run.test.sh"
printf '{}\n' >"$GOLD/plug1/hooks/notes.json"
printf '%s\n' '{"mcpServers":{"one":{}}}' >"$GOLD/plug1/.mcp.json"

printf '%s\n' '{"name":"plug2"}' >"$GOLD/plug2/.claude-plugin/plugin.json"
printf '%s\n' '{"hooks":{}}' >"$GOLD/plug2/hooks/hooks.json"
printf -- '---\nname: gamma\n---\nbody\n' >"$GOLD/plug2/skills/gamma/SKILL.md"
printf '%s\n' '{"mcpServers":{"alpha":{},"beta":{}}}' >"$GOLD/.mcp.json"
printf '%s\n' '{"plugins":[{"name":"a"},{"name":"b","defaultEnabled":false},{"name":"c"}]}' \
  >"$GOLD/.claude-plugin/marketplace.json"

gold_out="$(INVENTORY_PROJECT_DIR="$GOLD" INVENTORY_USER_SETTINGS="$GOLD/user-settings.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
rc=0
gold_out2="$(INVENTORY_PROJECT_DIR="$GOLD" INVENTORY_USER_SETTINGS="$GOLD/user-settings.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)" || rc=$?
assert_exit "golden fixture run exits 0" 0 "$rc"
assert_eq "golden output is deterministic across runs" "$gold_out" "$gold_out2"

assert_eq "user-settings row" \
  "user-settings present standing 1 0 0" "$(row6 user-settings "$gold_out")"
assert_eq "project-settings row counts 2 events as 3 handlers" \
  "project-settings present standing 1 1 3" "$(row6 project-settings "$gold_out")"
assert_eq "local-settings row counts 1 handler" \
  "local-settings present standing 1 1 1" "$(row6 local-settings "$gold_out")"
assert_eq "managed-policy row is absent at an absent path" \
  "managed-policy absent standing 1 - -" "$(row6 managed-policy "$gold_out")"
assert_eq "plugin-hooks-json row counts 2 manifests, 1 declaring, 3 handlers" \
  "plugin-hooks-json present standing 2 1 3" "$(row6 plugin-hooks-json "$gold_out")"
assert_eq "skill-frontmatter row counts 3 skills, 1 declaring" \
  "skill-frontmatter present conditional 3 1 -" "$(row6 skill-frontmatter "$gold_out")"
assert_eq "subagent-frontmatter row counts 2 agents, 1 declaring" \
  "subagent-frontmatter present conditional 2 1 -" "$(row6 subagent-frontmatter "$gold_out")"

assert_line "components: 2 plugin roots" "$gold_out" "  plugin roots         2"
assert_line "components: 3 skills" "$gold_out" "  skills               3 SKILL.md"
assert_line "components: 2 subagents" "$gold_out" "  subagents            2 definitions"
assert_line "components: 3 mcp servers across 2 files" "$gold_out" \
  "  mcp servers          3 across 2 .mcp.json file(s)"
assert_line "components: hook scripts and tests" "$gold_out" \
  "  hook scripts on disk 1 in plugin hooks/ dirs, 2 in .claude/hooks (+2 test scripts)"

assert_line "enablement: user map read as 2 true, 1 false" "$gold_out" \
  "  user       present      2 true, 1 false"
assert_line "enablement: project map read as empty" "$gold_out" \
  "  project    present      0 true, 0 false"
assert_line "enablement: catalog read as 3 entries, 1 defaultEnabled false" "$gold_out" \
  "  catalog    present      3 entries, 1 with defaultEnabled false"
assert_contains "enablement verdict is declined" "$gold_out" "No effective enablement is computed here"
assert_contains "precedence is named, not merge" "$gold_out" "PRECEDENCE, not merge"
assert_contains "hook merge mechanic is named" "$gold_out" "MERGE across settings levels"
assert_contains "cloud-session scope difference is stated" "$gold_out" "cloud session"
assert_contains "the conditional rows are explained" "$gold_out" "not part of the standing set"
assert_not_contains "project settings are not conditional" \
  "$(row_for project-settings "$gold_out")" "conditional"

gold_lines="$(printf '%s\n' "$gold_out" | wc -l | tr -d ' ')"
assert_eq "golden output is exactly the count table" 35 "$gold_lines"


managed_present_out="$(INVENTORY_PROJECT_DIR="$GOLD" INVENTORY_USER_SETTINGS="$GOLD/user-settings.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-present/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a managed policy that exists is present, with its counts" \
  "managed-policy present standing 1 0 0" "$(row6 managed-policy "$managed_present_out")"

managed_dir_out="$(INVENTORY_PROJECT_DIR="$GOLD" INVENTORY_USER_SETTINGS="$GOLD/user-settings.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-present" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a managed path that is a directory is unreadable, not absent" \
  "managed-policy unreadable standing 1 - -" "$(row6 managed-policy "$managed_dir_out")"

nolib_out="$(CLAUDE_PLUGIN_ROOT="$WORK/no-lib" INVENTORY_PROJECT_DIR="$GOLD" \
  INVENTORY_USER_SETTINGS="$GOLD/user-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "no managed-scope library means not-probed, never absent" \
  "managed-policy not-probed standing - - -" "$(row6 managed-policy "$nolib_out")"
assert_contains "the not-probed row explains itself" "$nolib_out" "not evidence that no policy is deployed"


LINKED="$WORK/linked"
mkdir -p "$LINKED/real/skills/one" "$LINKED/real/agents" "$LINKED/real/hooks" "$LINKED/.claude"
printf -- '---\nname: one\nhooks:\n  Stop:\n    - z\n---\nbody\n' >"$LINKED/real/skills/one/SKILL.md"
printf -- '---\nname: ag\n---\nbody\n' >"$LINKED/real/agents/ag.md"
printf '#!/bin/sh\n' >"$LINKED/real/hooks/h.sh"
ln -s "$LINKED/real/skills" "$LINKED/.claude/skills"
ln -s "$LINKED/real/agents" "$LINKED/.claude/agents"
ln -s "$LINKED/real/hooks" "$LINKED/.claude/hooks"
linked_out="$(INVENTORY_PROJECT_DIR="$LINKED" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a symlinked .claude/skills is walked" \
  "skill-frontmatter present conditional 1 1 -" "$(row6 skill-frontmatter "$linked_out")"
assert_eq "a symlinked .claude/agents is walked" \
  "subagent-frontmatter present conditional 1 0 -" "$(row6 subagent-frontmatter "$linked_out")"
assert_line "a symlinked .claude/skills reaches the components count" "$linked_out" \
  "  skills               1 SKILL.md"
assert_line "a symlinked .claude/hooks reaches the components count" "$linked_out" \
  "  hook scripts on disk 0 in plugin hooks/ dirs, 1 in .claude/hooks (+0 test scripts)"

scope_cases=(
  "skills|skill-frontmatter|skill-frontmatter unreadable conditional - - -|  skills               0+unreadable SKILL.md"
  "agents|subagent-frontmatter|subagent-frontmatter unreadable conditional - - -|  subagents            0+unreadable definitions"
  "hooks|-|-|  hook scripts on disk 0 in plugin hooks/ dirs, unreadable in .claude/hooks (+0+unreadable test scripts)"
)
for shape in dangling file; do
  for scope_case in "${scope_cases[@]}"; do
    IFS='|' read -r scope rowlabel want_row want_line <<<"$scope_case"
    U="$WORK/unreadable-$scope-$shape"
    mkdir -p "$U/.claude"
    case "$shape" in
    dangling) ln -s "$U/gone-$scope" "$U/.claude/$scope" ;;
    file) printf 'not a directory\n' >"$U/.claude/$scope" ;;
    *) ;;
    esac
    u_out="$(INVENTORY_PROJECT_DIR="$U" INVENTORY_USER_SETTINGS="$WORK/none.json" \
      INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
    if [[ "$rowlabel" != "-" ]]; then
      assert_eq "an unreadable .claude/$scope ($shape) row is not absent with a 0" \
        "$want_row" "$(row6 "$rowlabel" "$u_out")"
    fi
    assert_line "an unreadable .claude/$scope ($shape) reaches Components as a status word" \
      "$u_out" "$want_line"
    assert_contains "an unreadable .claude/$scope ($shape) is explained in the notes" \
      "$u_out" ".claude/$scope exists but could not be traversed"
  done
done

PLAINROOT="$WORK/plainroot"
MD="$WORK/managed-dropin"
mkdir -p "$PLAINROOT" "$MD/managed-settings.d"
printf '%s\n' '{"hooks":{}}' >"$MD/managed-settings.json"
printf '%s\n' '{"hooks":{}}' >"$MD/managed-settings.d/10-a.json"
printf '%s\n' '{"hooks":{}}' >"$MD/managed-settings.d/20-b.json"
md_ok_out="$(INVENTORY_PROJECT_DIR="$PLAINROOT" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$MD/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_contains "a readable managed-settings.d reports its exact file count" "$md_ok_out" \
  "managed-settings.d exists at $MD/managed-settings.d with 2 drop-in file(s)"
assert_eq "readable drop-ins are probed by the managed-policy row" \
  "managed-policy present standing 3 0 0" "$(row6 managed-policy "$md_ok_out")"

MDH="$WORK/managed-dropin-hooks"
mkdir -p "$MDH/managed-settings.d"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"base"}]}]}}' \
  >"$MDH/managed-settings.json"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}]}}' \
  >"$MDH/managed-settings.d/10-a.json"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"c"}]}]}}' \
  >"$MDH/managed-settings.d/20-b.json"
mdh_out="$(INVENTORY_PROJECT_DIR="$PLAINROOT" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$MDH/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "drop-in handlers reach the managed-policy row" \
  "managed-policy present standing 3 3 4" "$(row6 managed-policy "$mdh_out")"
assert_contains "the drop-in note says the row counts them" "$mdh_out" \
  "counted in the managed-policy row above"

MDNB="$WORK/managed-dropin-nobase"
mkdir -p "$MDNB/managed-settings.d"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"a"},{"type":"command","command":"b"}]}]}}' \
  >"$MDNB/managed-settings.d/10-a.json"
mdnb_out="$(INVENTORY_PROJECT_DIR="$PLAINROOT" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$MDNB/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "drop-ins without a base file are still counted" \
  "managed-policy present standing 2 1 2" "$(row6 managed-policy "$mdnb_out")"

MDMAL="$WORK/managed-dropin-malformed"
mkdir -p "$MDMAL/managed-settings.d"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"base"}]}]}}' \
  >"$MDMAL/managed-settings.json"
printf '%s\n' '{"hooks":"oops"}' >"$MDMAL/managed-settings.d/10-a.json"
mdmal_out="$(INVENTORY_PROJECT_DIR="$PLAINROOT" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$MDMAL/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a malformed drop-in makes the managed counts floors" \
  "managed-policy present standing 2 1+invalid-json 1+invalid-json" \
  "$(row6 managed-policy "$mdmal_out")"
assert_contains "a malformed drop-in is named" "$mdmal_out" \
  "managed drop-in $MDMAL/managed-settings.d/10-a.json is invalid-json"

MDBAD="$WORK/managed-dropin-bad"
mkdir -p "$MDBAD"
printf '%s\n' '{"hooks":{}}' >"$MDBAD/managed-settings.json"
ln -s "$MDBAD/gone" "$MDBAD/managed-settings.d"
md_bad_out="$(INVENTORY_PROJECT_DIR="$PLAINROOT" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$MDBAD/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_contains "an unreadable managed-settings.d is named, not passed over" "$md_bad_out" \
  "managed-settings.d exists at $MDBAD/managed-settings.d but could not be traversed (unreadable)"
assert_not_contains "an unreadable managed-settings.d publishes no file count" "$md_bad_out" \
  "drop-in file(s)"
assert_eq "an unreadable managed-settings.d makes every managed figure a floor" \
  "managed-policy present standing 1+unreadable 0+unreadable 0+unreadable" \
  "$(row6 managed-policy "$md_bad_out")"



SELFPLUG="$WORK/selfplug"
mkdir -p "$SELFPLUG/.claude-plugin" "$SELFPLUG/hooks" \
  "$SELFPLUG/.git/hooks" "$SELFPLUG/node_modules/dep/hooks"
printf '%s\n' '{"name":"self"}' >"$SELFPLUG/.claude-plugin/plugin.json"
printf '#!/bin/sh\n' >"$SELFPLUG/hooks/real.sh"
for sample in pre-commit pre-push commit-msg update; do
  printf '#!/bin/sh\n' >"$SELFPLUG/.git/hooks/$sample.sample"
done
printf '#!/bin/sh\n' >"$SELFPLUG/node_modules/dep/hooks/vendored.sh"
mkdir -p "$SELFPLUG/node_modules/dep/.claude-plugin"
printf '%s\n' '{"name":"dep"}' >"$SELFPLUG/node_modules/dep/.claude-plugin/plugin.json"
selfplug_out="$(INVENTORY_PROJECT_DIR="$SELFPLUG" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_line "a vendored plugin manifest is not a plugin root" "$selfplug_out" \
  "  plugin roots         1"
assert_line ".git/hooks samples are not this repository's hook scripts" "$selfplug_out" \
  "  hook scripts on disk 1 in plugin hooks/ dirs, 0 in .claude/hooks (+0 test scripts)"
assert_contains "the pruned trees are named in the notes" "$selfplug_out" \
  "prunes .git and node_modules"


for badhooks in '"oops"' '5' 'true' '[1,2]' 'null'; do
  BAD="$WORK/badhooks"
  rm -rf "$BAD"
  mkdir -p "$BAD/.claude"
  printf '{"hooks":%s}\n' "$badhooks" >"$BAD/.claude/settings.json"
  bad_hooks_out="$(INVENTORY_PROJECT_DIR="$BAD" INVENTORY_USER_SETTINGS="$WORK/none.json" \
    INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
  case "$badhooks" in
  'null')
    assert_eq "a null hooks key is an empty hook block: $badhooks" \
      "project-settings present standing 1 0 0" "$(row6 project-settings "$bad_hooks_out")"
    ;;
  *)
    assert_eq "a wrong-typed hooks block is invalid-json: $badhooks" \
      "project-settings invalid-json standing 1 - -" "$(row6 project-settings "$bad_hooks_out")"
    assert_contains "the malformed hooks block is explained: $badhooks" "$bad_hooks_out" \
      "A malformed hooks block is not an absence of hooks."
    ;;
  esac
done

BADMAN="$WORK/badmanifest"
mkdir -p "$BADMAN/p/.claude-plugin" "$BADMAN/p/hooks"
printf '%s\n' '{"name":"p"}' >"$BADMAN/p/.claude-plugin/plugin.json"
printf '%s\n' '{"hooks":"oops"}' >"$BADMAN/p/hooks/hooks.json"
badman_out="$(INVENTORY_PROJECT_DIR="$BADMAN" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a wrong-shaped plugin manifest is still probed" \
  "plugin-hooks-json present standing 1 0 0" "$(row6 plugin-hooks-json "$badman_out")"
assert_contains "a wrong-shaped plugin manifest is named" "$badman_out" \
  "its hooks block is the wrong shape to read"
assert_contains "a wrong-shaped plugin manifest makes the row a floor" "$badman_out" \
  "floor rather than a total"

BADCAT="$WORK/badcatalog"
mkdir -p "$BADCAT/.claude-plugin"
printf '%s\n' '{"plugins":"seventeen"}' >"$BADCAT/.claude-plugin/marketplace.json"
badcat_out="$(INVENTORY_PROJECT_DIR="$BADCAT" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_line "a wrong-typed catalog is invalid-json, not an entry count" "$badcat_out" \
  "  catalog    invalid-json .claude-plugin/marketplace.json (plugins is not an array)"
assert_not_contains "a wrong-typed catalog publishes no entry count" "$badcat_out" "entries, "

BADEP="$WORK/badenabled"
mkdir -p "$BADEP/.claude"
printf '%s\n' '{"enabledPlugins":"all"}' >"$BADEP/.claude/settings.json"
bad_ep_out="$(INVENTORY_PROJECT_DIR="$BADEP" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_contains "a wrong-typed enabledPlugins is invalid-json" "$bad_ep_out" \
  "enabledPlugins holds string, not an object"
assert_not_contains "a wrong-typed enabledPlugins is not 0 true, 0 false" "$bad_ep_out" \
  "project    present      0 true, 0 false"


MCPBAD="$WORK/mcp-badtype"
mkdir -p "$MCPBAD"
printf '%s\n' '{"mcpServers":"oops"}' >"$MCPBAD/.mcp.json"
mcp_bad_out="$(INVENTORY_PROJECT_DIR="$MCPBAD" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_line "a wrong-typed mcpServers key is a floor, not a zero" "$mcp_bad_out" \
  "  mcp servers          0+invalid-json across 1 .mcp.json file(s)"
assert_not_contains "a wrong-typed mcpServers key never reports 0 across 0" "$mcp_bad_out" \
  "0 across 0 .mcp.json file(s)"

MCPDIR="$WORK/mcp-notafile"
mkdir -p "$MCPDIR/.mcp.json"
mcp_dir_out="$(INVENTORY_PROJECT_DIR="$MCPDIR" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_line "an unreadable .mcp.json is examined and reported unreadable" "$mcp_dir_out" \
  "  mcp servers          0+unreadable across 1 .mcp.json file(s)"
assert_contains "an unreadable .mcp.json is explained" "$mcp_dir_out" \
  "is unreadable, so the MCP servers it configures could not be counted"

MCPMIX="$WORK/mcp-mixed"
mkdir -p "$MCPMIX/p/.claude-plugin"
printf '%s\n' '{"name":"p"}' >"$MCPMIX/p/.claude-plugin/plugin.json"
printf '%s\n' 'not json at all' >"$MCPMIX/p/.mcp.json"
printf '%s\n' '{"mcpServers":{"alpha":{},"beta":{}}}' >"$MCPMIX/.mcp.json"
mcp_mix_out="$(INVENTORY_PROJECT_DIR="$MCPMIX" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_line "a broken plugin .mcp.json floors the total without losing the read one" \
  "$mcp_mix_out" "  mcp servers          2+invalid-json across 2 .mcp.json file(s)"
assert_contains "the broken plugin .mcp.json is named" "$mcp_mix_out" \
  "./p/.mcp.json is invalid-json"


NL="$WORK/newline"
nl_dir="$NL/.claude/skills/we
ird"
mkdir -p "$nl_dir"
printf -- '---\nname: n\nhooks:\n  PreToolUse:\n    - q\n---\nbody\n' >"$nl_dir/SKILL.md"
nl_out="$(INVENTORY_PROJECT_DIR="$NL" INVENTORY_USER_SETTINGS="$WORK/none.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a newline in a path is one skill, and its hooks block is seen" \
  "skill-frontmatter present conditional 1 1 -" "$(row6 skill-frontmatter "$nl_out")"
assert_line "a newline in a path does not double the components count" "$nl_out" \
  "  skills               1 SKILL.md"


FIX="$WORK/fixture"
mkdir -p "$FIX/.claude"
mkdir -p "$FIX/user-settings.json"
printf '{"hooks":{}}\n' >"$FIX/.claude/settings.json"
unreadable_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_USER_SETTINGS="$FIX/user-settings.json" \
  bash "$INVENTORY" 2>/dev/null)"
assert_eq "unreadable user settings report unreadable and carry no count" \
  "user-settings unreadable standing 1 - -" "$(row6 user-settings "$unreadable_out")"

printf 'not json at all\n' >"$WORK/broken.json"
broken_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_USER_SETTINGS="$WORK/broken.json" \
  bash "$INVENTORY" 2>/dev/null)"
assert_eq "unparsable settings report invalid-json" \
  "user-settings invalid-json standing 1 - -" "$(row6 user-settings "$broken_out")"

absent_out="$(INVENTORY_PROJECT_DIR="$FIX" INVENTORY_USER_SETTINGS="$WORK/nope.json" \
  bash "$INVENTORY" 2>/dev/null)"
assert_eq "missing settings report absent" \
  "user-settings absent standing 1 - -" "$(row6 user-settings "$absent_out")"

nojq_out="$(INVENTORY_PROJECT_DIR="$GOLD" INVENTORY_JQ="jq-that-does-not-exist" \
  INVENTORY_USER_SETTINGS="$GOLD/user-settings.json" \
  INVENTORY_MANAGED_PATH="$WORK/managed-absent/managed-settings.json" bash "$INVENTORY" 2>/dev/null)"
assert_eq "missing jq reports skipped, and no handler count" \
  "project-settings skipped standing 1 - -" "$(row6 project-settings "$nojq_out")"
assert_eq "missing jq skips the plugin manifests too" \
  "plugin-hooks-json skipped standing 2 - -" "$(row6 plugin-hooks-json "$nojq_out")"
assert_contains "missing jq is called out as not a measurement" "$nojq_out" \
  "The count below is not a measurement."
assert_line "missing jq still counts the tree" "$nojq_out" "  skills               3 SKILL.md"


empty_out="$(INVENTORY_PROJECT_DIR="$FIX" bash "$INVENTORY" 2>/dev/null)"
assert_eq "a plugin-free repo reports the plugin row absent, not 0 handlers" \
  "plugin-hooks-json absent standing 0 - -" "$(row6 plugin-hooks-json "$empty_out")"
assert_line "a plugin-free repo reports 0 plugin roots" "$empty_out" "  plugin roots         0"
assert_contains "a plugin-free repo still emits components" "$empty_out" "Components in this repository"


if command -v git >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  GMAIN="$WORK/git-main"
  mkdir -p "$GMAIN/sub/.claude" "$GMAIN/.claude"
  git -C "$GMAIN" init -q
  printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}]}}' \
    >"$GMAIN/sub/.claude/settings.json"
  git -C "$GMAIN" add sub
  git -C "$GMAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q -m init
  printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"true"},{"type":"command","command":"true"}]}]}}' \
    >"$GMAIN/.claude/settings.local.json"
  git -C "$GMAIN" worktree add -q "$WORK/git-linked" 2>/dev/null
  main_real="$(cd "$GMAIN" && pwd -P)"
  wt_out="$(cd "$WORK/git-linked" && env -u INVENTORY_PROJECT_DIR -u CLAUDE_PROJECT_DIR \
    INVENTORY_USER_SETTINGS="$WORK/none.json" bash "$INVENTORY" 2>/dev/null)"
  assert_eq "linked worktree: local-settings reads the main checkout's file" \
    "local-settings present standing 1 1 2" "$(row6 local-settings "$wt_out")"
  assert_contains "linked worktree: local-settings names the main checkout's file" \
    "$(row_for local-settings "$wt_out")" "$main_real/.claude/settings.local.json"
  assert_eq "linked worktree at its root: project-settings is the worktree's own, absent" \
    "project-settings absent standing 1 - -" "$(row6 project-settings "$wt_out")"
  win_out="$(cd "$WORK/git-linked" && env -u INVENTORY_PROJECT_DIR -u CLAUDE_PROJECT_DIR \
    INVENTORY_USER_SETTINGS="$WORK/none.json" OSTYPE=msys bash "$INVENTORY" 2>/dev/null)"
  assert_eq "linked worktree on Windows: local-settings is the worktree's own, absent" \
    "local-settings absent standing 1 - -" "$(row6 local-settings "$win_out")"
  sub_out="$(cd "$GMAIN/sub" && env -u INVENTORY_PROJECT_DIR -u CLAUDE_PROJECT_DIR \
    INVENTORY_USER_SETTINGS="$WORK/none.json" bash "$INVENTORY" 2>/dev/null)"
  assert_eq "subdirectory: project-settings reads the subdirectory's file" \
    "project-settings present standing 1 1 1" "$(row6 project-settings "$sub_out")"
  assert_contains "subdirectory: project-settings names the subdirectory's file" \
    "$(row_for project-settings "$sub_out")" "$main_real/sub/.claude/settings.json"
  assert_eq "subdirectory of the main checkout: local-settings stays at the root" \
    "local-settings present standing 1 1 2" "$(row6 local-settings "$sub_out")"
  assert_line "subdirectory: the header still names the repository root" "$sub_out" \
    "Claude Code automation inventory for $main_real"
else
  fail "worktree and subdirectory roots" "git or jq is not on PATH, so these cases could not run"
fi


rc=0
out="$(cd "$GOLD" && env -u CLAUDE_PROJECT_DIR bash "$INVENTORY" 2>/dev/null)" || rc=$?
assert_exit "default run exits 0" 0 "$rc"
assert_contains "table header present" "$out" "LOCATION"
assert_contains "table header carries PROBED" "$out" "PROBED"
assert_contains "table header carries DECLARING" "$out" "DECLARING"
assert_contains "table header carries HANDLERS" "$out" "HANDLERS"
for loc in user-settings project-settings local-settings managed-policy \
  plugin-hooks-json skill-frontmatter subagent-frontmatter; do
  if [[ -n "$(row_for "$loc" "$out")" ]]; then
    pass "hook location row: $loc"
  else
    fail "hook location row: $loc" "no row whose first column is $loc"
  fi
done
assert_contains "skill frontmatter is conditional" "$(row_for skill-frontmatter "$out")" "conditional"
assert_contains "subagent frontmatter is conditional" "$(row_for subagent-frontmatter "$out")" "conditional"

line_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [[ "$line_count" -ge 30 && "$line_count" -le 45 ]]; then
  pass "default-root output stays a count table ($line_count lines)"
else
  fail "default-root output stays a count table" "expected 30 to 45 lines, got $line_count"
fi

report_and_exit
