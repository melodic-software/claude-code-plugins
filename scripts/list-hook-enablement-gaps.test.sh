#!/usr/bin/env bash
# test-scope: plugins/*/hooks/hooks.json plugins/*/.claude-plugin/plugin.json
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SCRIPT="$SELF_DIR/list-hook-enablement-gaps.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh" || exit 2

PENDING=(
  context-budget
  discovery
  display-redaction
  fleet
  themes
)

f=""
OUT=""
ERR=""
RC=0

HOOK='{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash x.sh"}]}]}}'

plugin() {
  local name="$1" hooks="$2" manifest="${3:-}"
  mkdir -p "$f/plugins/$name/hooks"
  printf '%s\n' "$hooks" >"$f/plugins/$name/hooks/hooks.json"
  if [[ -n "$manifest" ]]; then
    mkdir -p "$f/plugins/$name/.claude-plugin"
    printf '%s\n' "$manifest" >"$f/plugins/$name/.claude-plugin/plugin.json"
  fi
}

run_list() {
  local errf
  errf="$(mktemp)" || return 2
  OUT="$(bash "$1/scripts/list-hook-enablement-gaps.sh" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
  rm -f "$errf"
}

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin keyed "$HOOK" '{"name":"keyed","userConfig":{"keyed_enabled":{"type":"boolean","default":true}}}'
plugin bare "$HOOK" '{"name":"bare","userConfig":{"level":{"type":"string","default":"x"}}}'
plugin nomanifest "$HOOK"
plugin stringkey "$HOOK" '{"name":"stringkey","userConfig":{"stringkey_enabled":{"type":"string","default":"true"}}}'
plugin otherbool "$HOOK" '{"name":"otherbool","userConfig":{"sound":{"type":"boolean","default":true}}}'
plugin moddy '{"modules":["./register.tsx"]}' '{"name":"moddy"}'
plugin empty '{"hooks":{}}' '{"name":"empty"}'
plugin hollow '{"hooks":{"Stop":[{"hooks":[]}]}}' '{"name":"hollow"}'
run_list "$f"
want=$'bare\nmoddy\nnomanifest\notherbool\nstringkey'
if ((RC == 0)) && [[ "$OUT" == "$want" && "$ERR" == *"5 of 6 plugin(s)"* ]]; then
  ok "lists each plugin whose hooks have no boolean <name>_enabled option, sorted"
else
  fail "wanted exit 0 and '$want' (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin keyed "$HOOK" '{"name":"keyed","userConfig":{"keyed_enabled":{"type":"boolean","default":false}}}'
run_list "$f"
if ((RC == 0)) && [[ -z "$OUT" && "$ERR" == *"0 of 1 plugin(s)"* ]]; then
  ok "a tree where every hook plugin has its option lists nothing"
else
  fail "wanted exit 0 and an empty list (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin keyed "$HOOK" '{"name":"keyed","userConfig":{"keyed_enabled":{"type":"boolean"}}}'
plugin broken '{"hooks":' '{"name":"broken"}'
run_list "$f"
if ((RC == 2)) && [[ -z "$OUT" && "$ERR" == *"plugins/broken/hooks/hooks.json is not readable JSON"* ]]; then
  ok "an unreadable hooks.json exits 2 and names the file"
else
  fail "wanted exit 2 naming the broken hooks.json (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin keyed "$HOOK" '{"name":"keyed","userConfig":{"keyed_enabled":{"type":"boolean"}}}'
: >"$f/plugins/keyed/hooks/hooks.json"
run_list "$f"
if ((RC == 2)) && [[ -z "$OUT" && "$ERR" == *"plugins/keyed/hooks/hooks.json is not readable JSON"* ]]; then
  ok "an empty hooks.json exits 2 and names the file"
else
  fail "wanted exit 2 naming the empty hooks.json (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin keyed "$HOOK" '{"name":"keyed","userConfig":'
run_list "$f"
if ((RC == 2)) && [[ -z "$OUT" && "$ERR" == *"plugins/keyed/.claude-plugin/plugin.json is not readable JSON"* ]]; then
  ok "an unreadable plugin.json exits 2 and names the file"
else
  fail "wanted exit 2 naming the broken plugin.json (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin empty '{"hooks":{}}' '{"name":"empty"}'
run_list "$f"
if ((RC == 2)) && [[ -z "$OUT" && "$ERR" == *"refusing to report an empty list"* ]]; then
  ok "a tree with no hook to scan exits 2, not an empty list"
else
  fail "wanted exit 2 on an empty corpus (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
plugin keyed "$HOOK" '{"name":"keyed","userConfig":{"keyed_enabled":{"type":"boolean","default":true}}}'
# shellcheck disable=SC2016
plugin multi-agent '{"hooks":{"PreToolUse":[{"matcher":"WebFetch","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/drift-checker-fetch-gate.mjs"]}]},{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs","multi-agent:docs-fetcher","code.claude.com"]}]},{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs","multi-agent:registry-fetcher","arena.ai"]}]}]}}' '{"name":"multi-agent"}'
# shellcheck disable=SC2016
plugin discovery '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs","discovery:docs-fetcher"]}]}]}}' '{"name":"discovery"}'
run_list "$f"
if ((RC == 0)) && [[ -z "$OUT" && "$ERR" == *"0 of 1 plugin(s)"* ]]; then
  ok "exempt subagent-confining gates alone do not place a plugin on the gap list"
else
  fail "wanted exit 0 and an empty list for exempt-only plugins (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
# shellcheck disable=SC2016
plugin discovery '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs","discovery:docs-fetcher"]}]}],"PostToolUse":[{"matcher":"WebFetch","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/webfetch-truncation.mjs"]}]}]}}' '{"name":"discovery"}'
# shellcheck disable=SC2016
plugin multi-agent '{"hooks":{"PreToolUse":[{"matcher":"WebFetch","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/drift-checker-fetch-gate.mjs"]}]},{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/hooks/extra.mjs"]}]}]}}' '{"name":"multi-agent"}'
# shellcheck disable=SC2016
plugin other '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs","discovery:docs-fetcher"]}]}]}}' '{"name":"other"}'
run_list "$f"
want=$'discovery\nmulti-agent\nother'
if ((RC == 0)) && [[ "$OUT" == "$want" && "$ERR" == *"3 of 3 plugin(s)"* ]]; then
  ok "a non-exempt hook in an exempt plugin, or a different plugin with exempt args, is still listed"
else
  fail "wanted exit 0 and '$want' (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

fixture_tree::build f --sut "$SCRIPT" --plugins || exit 2
# shellcheck disable=SC2016
plugin discovery '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/lib/docs-fetcher-gate.mjs","discovery:other"]}]}]}}' '{"name":"discovery"}'
run_list "$f"
if ((RC == 0)) && [[ "$OUT" == "discovery" && "$ERR" == *"1 of 1 plugin(s)"* ]]; then
  ok "an exempt plugin with a non-matching gate agent argument is still listed"
else
  fail "wanted exit 0 and 'discovery' (rc=$RC, stdout='$OUT', stderr='$ERR')"
fi

run_list "$SELF_DIR/.."
want="$(printf '%s\n' "${PENDING[@]}")"
if ((RC == 0)) && [[ "$OUT" == "$want" ]]; then
  ok "the repository's list matches PENDING (${#PENDING[@]} plugin(s))"
else
  fail "the repository's list differs from PENDING in $0 (rc=$RC). A plugin that adopts its option leaves both; a new plugin with a hook ships its option. Got:
$OUT
$ERR"
fi

test_harness::report
