#!/usr/bin/env bash
# Contract tests for the opt-in Stop row (go_format_end_of_turn), launched
# exactly as hooks.json registers it: off by default; on, an uncommitted file
# goimports cannot parse exits 2 with its line on stderr and nothing is
# rewritten; stop_hook_active keeps it from blocking twice in one turn; the
# plugin kill switch wins. The spawn budget case fences the cost every user pays
# per turn with the option off: the node launcher only.
# test-scope: plugins/go-format/hooks/hooks.json plugins/go-format/git-hooks/goimports-format.sh plugins/go-format/.claude-plugin/plugin.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HOOK_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
for tool in node jq goimports git; do
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
  "node --run-if-unset-or-true GO_FORMAT_ENABLED --require-true GO_FORMAT_END_OF_TURN --end-of-turn" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$PLUGIN/hooks/hooks.json") ${ARGS[1]} ${ARGS[2]} ${ARGS[3]} ${ARGS[4]} ${ARGS[6]}"

R="$WORK/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
printf 'package seed\n' >"$R/a.go"
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

BROKEN=$'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}'
# The finding lines are the tool's own documented messages; the closing hint
# line is this plugin's wording, so the case drops it instead of restating it.
findings() { printf '%s' "${1%$'\n'*}"; }
FINDING="a.go:4: missing ',' before newline in argument list
a.go:5: expected operand, found '}'"
printf '%s\n' "$BROKEN" >"$R/a.go"
expect "off by default: an uncommitted unparseable file does not block" "0|" "$(stop false)"
expect "on: an uncommitted unparseable file exits 2 with its line" "2|$FINDING" \
  "$(findings "$(stop false CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN=true)")"
expect "on: nothing is rewritten" "$BROKEN" "$(cat "$R/a.go")"
expect "on: stop_hook_active means it already blocked this turn" "0|" \
  "$(stop true CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN=true)"
expect "on: the plugin kill switch wins" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN=true CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=false)"
# Without goimports the check script fails an agent (git-hooks test); the row
# turns that one failure into a silent pass, since the SessionStart probe
# already reports the missing tool.
NOTOOL="$WORK/no-goimports"
mkdir -p "$NOTOOL"
for t in node git bash sed awk cat mktemp rm dirname grep tr jq; do
  ln -s "$(command -v "$t")" "$NOTOOL/$t"
done
expect "on: a missing goimports passes silently" "0|" \
  "$(stop false CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN=true PATH="$NOTOOL")"
printf 'package main\n\nfunc main() {\n\tprintln("hi")\n}\n' >"$R/a.go"
expect "on: an unformatted file that parses passes and is not rewritten" "0|" "$(stop false CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN=true)"
git -C "$R" checkout -q a.go
expect "on: a clean work tree passes" "0|" "$(stop false CLAUDE_PLUGIN_OPTION_GO_FORMAT_END_OF_TURN=true)"

CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" go-format Stop go-format.sh \
    '{"session_id":"census","hook_event_name":"Stop","stop_hook_active":false,"cwd":"@DIR@"}' --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: with the option off a Stop costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo "go-format end-of-turn: $PASS passed, $FAIL failed"
((FAIL == 0))
