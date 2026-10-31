# shellcheck shell=bash
# Run as `bash result-gate.test.sh`, the way scripts/run-plugin-tests.sh runs every suite.
# Contract tests for the turn-end result gate, launched as hooks.json registers it. A recorded
# FAIL, INCOMPLETE or STOPPED for the current tree, from check or lint, is a systemMessage and no
# block; a recorded PASS is silent; a record for another tree does not count; a clean tree is
# silent, and so is a turn that changed no file and recorded nothing; the mode comes from user settings only, defaults to advisory, and enforce blocks once on
# a recorded FAIL and never on an unreadable record or a missing git. The hook runs no build, test
# or lint command.
# test-scope: plugins/toolchain/hooks/hooks.json plugins/toolchain/lib/tree-result.mjs plugins/toolchain/scripts/record-result.mjs plugins/toolchain/.claude-plugin/plugin.json
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDE_PLUGIN_OPTION_TURN_END_RESULT_GATE

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HOOK_DIR/.." && pwd)"
for tool in node jq git; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP: $tool not on PATH -- result gate tests skipped"
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

# shellcheck disable=SC2016 # the want is hooks.json's literal placeholder text
expect "the Stop row launches node on the result gate" \
  'node ${CLAUDE_PLUGIN_ROOT}/hooks/result-gate.mjs' \
  "$(jq -r '.hooks.Stop[0].hooks[0] | "\(.command) \(.args | join(" "))"' "$PLUGIN/hooks/hooks.json")"
expect "the option defaults to advisory" "advisory" \
  "$(jq -r '.userConfig.turn_end_result_gate.default' "$PLUGIN/.claude-plugin/plugin.json")"

# An install in the plugin cache layout, so its user settings file is the one beside the cache.
CONFIG="$WORK/config"
INSTALL="$CONFIG/plugins/cache/mkt/toolchain/1.0.0"
mkdir -p "$INSTALL"
cp -R "$PLUGIN/.claude-plugin" "$PLUGIN/hooks" "$PLUGIN/lib" "$PLUGIN/scripts" "$INSTALL/"
HOOK="$INSTALL/hooks/result-gate.mjs"
RECORD="$INSTALL/scripts/record-result.mjs"
set_mode() { # <mode or empty for no settings file>
  if [[ -z "$1" ]]; then
    rm -f "$CONFIG/settings.json"
  else
    jq -n --arg m "$1" '{pluginConfigs: {"toolchain@mkt": {options: {turn_end_result_gate: $m}}}}' >"$CONFIG/settings.json"
  fi
}

R="$WORK/repo"
git init -q -b main "$R"
git -C "$R" config user.name t
git -C "$R" config user.email t@example.invalid
printf 'seed\n' >"$R/a.txt"
git -C "$R" add -A
git -C "$R" commit -q -m seed

# Each call is a fresh session unless SESSION names one, so the hook's "nothing new since this
# session's last turn end" rule only applies where a case asks for it.
stop() { # <stop_hook_active> [env...] -> "<rc>|<stdout>"
  local active="$1" out rc sid="${SESSION:-s$BASHPID-$RANDOM}"
  shift
  out="$(printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s,"cwd":"%s"}' "$sid" "$active" "$R" |
    env "$@" node "$HOOK" 2>/dev/null)"
  rc=$?
  printf '%s|%s' "$rc" "$out"
}
message() { jq -r '.systemMessage // ""' <<<"${1#*|}"; }
decision() { jq -r '.decision // "none"' <<<"${1#*|}"; }
record() { node "$RECORD" --dir "$R" --skill "$1" --overall "$2" >/dev/null; }
store() { printf '%s/.git/toolchain-results' "$R"; }

set_mode ""
expect "AC5: a clean tree with no record prints nothing" "0|" "$(stop false)"
record check "Overall: FAIL (1 of 1 ecosystems failed)"
expect "AC5: a clean tree prints nothing even with a recorded FAIL" "0|" "$(stop false)"
expect "a non-Stop event prints nothing" "" \
  "$(printf '{"hook_event_name":"SubagentStop","cwd":"%s"}' "$R" | node "$HOOK" 2>/dev/null)"

printf 'changed\n' >"$R/a.txt"
out="$(stop false)"
expect "a changed tree with no record says so" "yes" \
  "$([[ "$(message "$out")" == *"no /toolchain:check or /toolchain:lint result is recorded for this tree"* ]] && echo yes)"
expect "no record never blocks" "none" "$(decision "$out")"

for verdict in FAIL INCOMPLETE STOPPED; do
  rm -rf "$(store)"
  record check "Overall: $verdict (detail)"
  out="$(stop false)"
  expect "AC1: check $verdict exits 0" "0" "${out%%|*}"
  expect "AC1: check $verdict is named in the systemMessage" "yes" \
    "$([[ "$(message "$out")" == *"check: Overall: $verdict (detail)"* ]] && echo yes)"
  expect "AC1: check $verdict sets no block" "none" "$(decision "$out")"
done

rm -rf "$(store)"
record lint "Overall: INCOMPLETE (1 of 2 ecosystems passed; markdown: skip (tool missing: markdownlint-cli2))"
out="$(stop false)"
expect "AC2: lint INCOMPLETE is reported like check's" "0|none|yes" \
  "${out%%|*}|$(decision "$out")|$([[ "$(message "$out")" == *"lint: Overall: INCOMPLETE (1 of 2 ecosystems passed;"* ]] && echo yes)"

rm -rf "$(store)"
record check "Overall: PASS (1 of 1 ecosystems passed)"
expect "AC3: a recorded PASS prints nothing" "0|" "$(stop false)"
record lint "Overall: PASS (1 of 1 ecosystems passed)"
expect "AC3: PASS from both skills prints nothing" "0|" "$(stop false)"
record lint "Overall: FAIL (1 of 1 ecosystems failed)"
expect "a newer lint FAIL beside a check PASS is named" "yes" \
  "$([[ "$(message "$(stop false)")" == *"lint: Overall: FAIL"* ]] && echo yes)"

rm -rf "$(store)"
record check "Overall: FAIL (1 of 1 ecosystems failed)"
printf 'untracked\n' >"$R/new.txt"
out="$(stop false)"
expect "AC4: a result recorded for another tree does not count" "yes|none" \
  "$([[ "$(message "$out")" == *"no /toolchain:check or /toolchain:lint result is recorded"* ]] && echo yes)|$(decision "$out")"
expect "hashing leaves the real index untouched" "?? new.txt" "$(git -C "$R" status --porcelain -- new.txt)"
rm "$R/new.txt"
expect "the same content hashes to the same tree, so its record counts again" "yes" \
  "$([[ "$(message "$(stop false)")" == *"check: Overall: FAIL"* ]] && echo yes)"

# AC5 within one session: a turn that changes no file and records nothing says nothing new.
rm -rf "$(store)"
printf 'turn\n' >"$R/turn.txt"
NO_RECORD="no /toolchain:check or /toolchain:lint result is recorded"
expect "AC5: the first turn end on a changed tree reports" "yes" \
  "$([[ "$(message "$(SESSION=turns stop false)")" == *"$NO_RECORD"* ]] && echo yes)"
expect "AC5: a turn with no changed file produces no warning" "0|" "$(SESSION=turns stop false)"
record check "Overall: FAIL (1 of 1 ecosystems failed)"
expect "a turn that records a result reports it" "yes" \
  "$([[ "$(message "$(SESSION=turns stop false)")" == *"check: Overall: FAIL"* ]] && echo yes)"
expect "AC5: the next turn with no changed file is quiet again" "0|" "$(SESSION=turns stop false)"
printf 'turn 2\n' >"$R/turn.txt"
expect "a turn that changes a file reports that the record no longer counts" "yes" \
  "$([[ "$(message "$(SESSION=turns stop false)")" == *"$NO_RECORD"* ]] && echo yes)"
rm "$R/turn.txt"
rm -rf "$(store)"
record check "Overall: FAIL (1 of 1 ecosystems failed)"

set_mode off
expect "AC6: off prints nothing" "0|" "$(stop false)"
set_mode bogus
expect "an unknown mode reads as advisory" "none|yes" \
  "$(decision "$(stop false)")|$([[ -n "$(message "$(stop false)")" ]] && echo yes)"
set_mode advisory
out="$(stop false)"
expect "AC6: advisory reports a FAIL and never blocks it" "none|yes" \
  "$(decision "$out")|$([[ "$(message "$out")" == *"check: Overall: FAIL"* ]] && echo yes)"
set_mode ""
expect "the environment mirror cannot turn the gate off" "yes" \
  "$([[ -n "$(message "$(stop false CLAUDE_PLUGIN_OPTION_TURN_END_RESULT_GATE=off)")" ]] && echo yes)"
printf '{not json' >"$CONFIG/settings.json"
expect "an unreadable settings file reads as advisory" "none|yes" \
  "$(decision "$(stop false)")|$([[ -n "$(message "$(stop false)")" ]] && echo yes)"

set_mode enforce
out="$(stop false)"
expect "AC6: enforce blocks a recorded FAIL" "0|block" "${out%%|*}|$(decision "$out")"
expect "AC6: enforce does not block twice in one stop" "none" "$(decision "$(stop true)")"
rm -rf "$(store)"
record check "Overall: INCOMPLETE (python: skip (tool missing: uv))"
out="$(stop false)"
expect "AC6: enforce reports INCOMPLETE and does not block it" "none|yes" \
  "$(decision "$out")|$([[ "$(message "$out")" == *"check: Overall: INCOMPLETE"* ]] && echo yes)"
rm -rf "$(store)"
out="$(stop false)"
expect "AC6: enforce reports a missing record and does not block it" "none|yes" \
  "$(decision "$out")|$([[ "$(message "$out")" == *"$NO_RECORD"* ]] && echo yes)"
record check "Overall: FAIL (1 of 1 ecosystems failed)"
for f in "$(store)"/*/check; do printf 'garbage\n' >"$f"; done
out="$(stop false)"
expect "AC6: enforce does not block an unreadable record" "none|yes" \
  "$(decision "$out")|$([[ "$(message "$out")" == *"check: unreadable record"* ]] && echo yes)"
NOGIT="$WORK/no-git"
mkdir -p "$NOGIT"
ln -s "$(command -v node)" "$NOGIT/node"
expect "AC6: enforce with git missing fails open, silent" "0|" "$(stop false PATH="$NOGIT")"

# AC7: every build, test or lint entry point a project could use is a stub that leaves a mark.
rm -rf "$(store)"
record check "Overall: FAIL (1 of 1 ecosystems failed)"
STUBS="$WORK/stubs"
MARK="$WORK/ran"
mkdir -p "$STUBS"
ln -s "$(command -v node)" "$STUBS/node"
ln -s "$(command -v git)" "$STUBS/git"
for t in make npm npx pnpm yarn bun dotnet uv uvx python python3 pytest ruff pyright go golangci-lint gofmt cargo shellcheck shfmt pwsh tsc eslint biome markdownlint-cli2 yamllint actionlint just task; do
  printf '#!/bin/sh\necho %s >>"%s"\n' "$t" "$MARK" >"$STUBS/$t"
  chmod +x "$STUBS/$t"
done
set_mode advisory
out="$(stop false PATH="$STUBS")"
expect "AC7: the hook still reports with only git and node" "yes" \
  "$([[ "$(message "$out")" == *"check: Overall: FAIL"* ]] && echo yes)"
expect "AC7: the hook runs no build, test or lint command" "" "$(cat "$MARK" 2>/dev/null)"

expect "record refuses a line that is not an Overall line" "1" \
  "$(node "$RECORD" --dir "$R" --skill check --overall "all good" >/dev/null 2>&1; echo $?)"
expect "record refuses an unknown skill" "1" \
  "$(node "$RECORD" --dir "$R" --skill verify --overall "Overall: PASS" >/dev/null 2>&1; echo $?)"
expect "record outside a repository exits 2" "2" \
  "$(node "$RECORD" --dir "$WORK" --skill check --overall "Overall: PASS" >/dev/null 2>&1; echo $?)"

# An unstaged change that swaps a tracked file for a directory, or a directory for a file, hashes
# to the tree `git add -A` would stage.
LIB="$INSTALL/lib/tree-result.mjs"
hash_of() { node --input-type=module -e "import { repository, treeHash } from '$LIB'; console.log(treeHash(repository(process.argv[1])));" "$1" 2>/dev/null; }
staged_tree() { (export GIT_INDEX_FILE="$WORK/staged-index" && cp "$1/.git/index" "$GIT_INDEX_FILE" && git -C "$1" add -A && git -C "$1" write-tree && rm -f "$GIT_INDEX_FILE"); }
swap_repo() { # <dir>: a repository with a tracked file `f` and a tracked directory `d/`
  git init -q -b main "$1"
  printf 'f\n' >"$1/f"
  mkdir -p "$1/d"
  printf 'x\n' >"$1/d/x"
  printf 'y\n' >"$1/d/y"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.invalid commit -q -m seed
}
S="$WORK/swap-file-to-dir"
swap_repo "$S"
rm "$S/f"
mkdir "$S/f"
printf 'inner\n' >"$S/f/inner"
expect "a tracked file replaced by a directory hashes to the staged tree" "$(staged_tree "$S")" "$(hash_of "$S")"
expect "a file-to-directory swap records a result" "0" \
  "$(node "$RECORD" --dir "$S" --skill check --overall "Overall: PASS" >/dev/null 2>&1; echo $?)"
S="$WORK/swap-dir-to-file"
swap_repo "$S"
rm -r "$S/d"
printf 'now a file\n' >"$S/d"
expect "a tracked directory replaced by a file hashes to the staged tree" "$(staged_tree "$S")" "$(hash_of "$S")"
expect "a directory-to-file swap records a result" "0" \
  "$(node "$RECORD" --dir "$S" --skill check --overall "Overall: PASS" >/dev/null 2>&1; echo $?)"

echo "result-gate: $PASS passed, $FAIL failed"
((FAIL == 0))
