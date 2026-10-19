#!/usr/bin/env bash
# Contract tests for the opt-in Stop row (biome_format_end_of_turn), launched
# exactly as hooks.json registers it: off by default; on, an uncommitted finding
# exits 2 with the finding on stderr and nothing is rewritten; stop_hook_active
# keeps it from blocking twice in one turn; the plugin kill switch wins. The
# spawn budget case fences the cost every user pays per turn with the option
# off: the node launcher only.
# test-scope: plugins/biome-format/hooks/hooks.json plugins/biome-format/git-hooks/biome-check.sh plugins/biome-format/.claude-plugin/plugin.json plugins/biome-format/hooks/exec-bash.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE BIOME_CONFIG_PATH CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HOOK_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
for tool in node jq biome git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- end-of-turn tests skipped"
    exit 0
  }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# The Stop row's args from hooks.json, with the plugin root substituted.
mapfile -t ARGS < <(jq -r '.hooks.Stop[0].hooks[0].args[]' "$PLUGIN/hooks/hooks.json" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN#g")
expect "the Stop row launches node with the end-of-turn gate" \
  "node --run-if-unset-or-true BIOME_FORMAT_ENABLED --require-true BIOME_FORMAT_END_OF_TURN --end-of-turn" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$PLUGIN/hooks/hooks.json") ${ARGS[1]} ${ARGS[2]} ${ARGS[3]} ${ARGS[4]} ${ARGS[6]}"

R="$WORK/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
printf '{}\n' >"$R/biome.json"
printf 'export const seed = 1;\n' >"$R/a.ts"
git -C "$R" add -A
git -C "$R" commit -q -m seed

stop() { # <stop_hook_active> [env...] -> "<rc>|<stderr>"
  local active="$1" err rc
  shift
  err="$(cd "$R" && printf '{"session_id":"s","hook_event_name":"Stop","stop_hook_active":%s,"cwd":"%s"}' "$active" "$R" |
    env "$@" node "${ARGS[@]}" 2>&1 >/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$err"
}

# The finding lines are the tool's own documented messages; the closing hint
# line is this plugin's wording, so the case drops it instead of restating it.
findings() { printf '%s' "${1%$'\n'*}"; }
FINDING='a.ts:2: lint/correctness/noUnusedVariables: This variable unusedVar is unused.'
printf 'export const seed = 1;\nconst unusedVar = 1;\n' >"$R/a.ts"
expect "off by default: an uncommitted finding does not block" "0|" "$(stop false)"
expect "on: an uncommitted finding on a changed line exits 2 with the finding" "2|$FINDING" \
  "$(findings "$(stop false CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN=true)")"
expect "on: nothing is rewritten" "$(printf 'export const seed = 1;\nconst unusedVar = 1;')" "$(cat "$R/a.ts")"
expect "on: stop_hook_active means it already blocked this turn" "0|" \
  "$(stop true CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN=true)"
expect "on: the plugin kill switch wins" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN=true CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=false)"
# Without biome the check script fails an agent (git-hooks test); the row turns
# that one failure into a silent pass, since the SessionStart probe already
# reports the missing tool.
NOTOOL="$WORK/no-biome"
mkdir -p "$NOTOOL"
for t in node git bash sed awk cat mktemp rm dirname grep tr jq; do
  ln -s "$(command -v "$t")" "$NOTOOL/$t"
done
expect "on: a missing biome passes silently" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN=true PATH="$NOTOOL")"
git -C "$R" checkout -q a.ts
expect "on: a clean work tree passes" "0|" "$(stop false CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_END_OF_TURN=true)"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" biome-format Stop biome-format.sh \
    '{"session_id":"census","hook_event_name":"Stop","stop_hook_active":false,"cwd":"@DIR@"}' --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: with the option off a Stop costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo "biome-format end-of-turn: $PASS passed, $FAIL failed"
((FAIL == 0))
