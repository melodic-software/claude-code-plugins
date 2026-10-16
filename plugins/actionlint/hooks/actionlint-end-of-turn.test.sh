#!/usr/bin/env bash
# Contract tests for the opt-in Stop row (actionlint_end_of_turn), launched
# exactly as hooks.json registers it: off by default; on, an uncommitted finding
# exits 2 with the finding on stderr and nothing is rewritten; stop_hook_active
# keeps it from blocking twice in one turn; the plugin kill switch wins. The
# spawn budget case fences the cost every user pays per turn with the option
# off: the node launcher only.
# Expected values are actionlint's documented output (docs/checks.md): an
# undefined property in an expression, reported on line 7 of the fixture.
# test-scope: plugins/actionlint/hooks/hooks.json plugins/actionlint/hooks/actionlint-check.sh plugins/actionlint/git-hooks/actionlint-check.sh plugins/actionlint/.claude-plugin/plugin.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDE_PLUGIN_OPTION_ACTIONLINT_END_OF_TURN CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HOOK_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
for tool in node jq actionlint git; do
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
  "node --run-if-unset-or-true ACTIONLINT_ENABLED --require-true ACTIONLINT_END_OF_TURN --end-of-turn" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$PLUGIN/hooks/hooks.json") ${ARGS[1]} ${ARGS[2]} ${ARGS[3]} ${ARGS[4]} ${ARGS[6]}"

R="$WORK/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
mkdir -p "$R/.github/workflows"
CLEAN=$'name: ok\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n'
# shellcheck disable=SC2016 # literal workflow YAML: ${{ }} must stay unexpanded
BAD=$'name: bad\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "${{ steps.missing.outputs.x }}"\n'
printf '%s' "$CLEAN" >"$R/.github/workflows/ci.yml"
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

FINDING='.github/workflows/ci.yml:7: property "missing" is not defined in object type {} [expression]
actionlint: fix the findings above, or adjust .github/actionlint.yaml.'
printf '%s' "$BAD" >"$R/.github/workflows/ci.yml"
expect "off by default: an uncommitted finding does not block" "0|" "$(stop false)"
expect "on: an uncommitted finding on a changed line exits 2 with the finding" "2|$FINDING" \
  "$(stop false CLAUDE_PLUGIN_OPTION_ACTIONLINT_END_OF_TURN=true)"
expect "on: nothing is rewritten" "$(printf '%s' "$BAD")" "$(cat "$R/.github/workflows/ci.yml")"
expect "on: stop_hook_active means it already blocked this turn" "0|" \
  "$(stop true CLAUDE_PLUGIN_OPTION_ACTIONLINT_END_OF_TURN=true)"
expect "on: the plugin kill switch wins" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_ACTIONLINT_END_OF_TURN=true CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=false)"
git -C "$R" checkout -q .github/workflows/ci.yml
expect "on: a clean work tree passes" "0|" "$(stop false CLAUDE_PLUGIN_OPTION_ACTIONLINT_END_OF_TURN=true)"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" actionlint Stop actionlint-check.sh \
    '{"session_id":"census","hook_event_name":"Stop","stop_hook_active":false,"cwd":"@DIR@"}' --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: with the option off a Stop costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo "actionlint end-of-turn: $PASS passed, $FAIL failed"
((FAIL == 0))
