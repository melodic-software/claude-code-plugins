#!/usr/bin/env bash
# Black-box contract test for the go-format PostToolBatch row, launched exactly
# as hooks.json registers it (node exec-bash.mjs with the row's args).
#
# Proves WIRING: one PostToolBatch row and no PostToolUse row; the row rewrites
# the .go files a Write, Edit or MultiEdit in the batch named, once per batch,
# and never anything a Read named; it prints nothing (no finding, no disclosure
# reaches the model) and exits 0; no Go config is needed; a file with Go's
# generated-code marker, a file under .githooks/, a gitignored file and a
# disabled plugin are left alone; a batch with no Go edit costs only the launcher.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The row is run from an UNRELATED cwd so any reliance on the caller's working
# directory would surface.
#
# Requires a real goimports binary: $GOIMPORTS_TEST_BIN if set, else `goimports`
# on PATH. Without one the behavioral assertions cannot run, so the suite skips.
# test-scope: plugins/go-format/.claude-plugin/plugin.json plugins/go-format/hooks/hooks.json plugins/go-format/prerequisites.json

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${HOOK_DIR%/*}"
HOOKS_JSON="$HOOK_DIR/hooks.json"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"

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
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1: want [$2] got [$3]"; fi
}

# --- hooks.json: one PostToolBatch row, an opt-in Stop row, no PostToolUse ----
# The batch row takes no matcher and no `if`: the hooks reference says neither
# applies to the event, so its launcher flag is the only filter. The script reads
# the paths itself.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" ]]; then
  # shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
  EXPECTED_ROW='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","GO_FORMAT_ENABLED","--skip-unless-stdin-contains",".go","${CLAUDE_PLUGIN_ROOT}/hooks/go-format.sh"]'
  expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
  expect "hooks.json: one PostToolBatch group with one handler" "1 1" "$(jq -r '.hooks.PostToolBatch | "\(length) \(.[0].hooks | length)"' "$HOOKS_JSON")"
  expect "hooks.json: the batch handler has no matcher, no if, and runs the script behind the .go prefilter" \
    "node true true $EXPECTED_ROW" \
    "$(jq -r '.hooks.PostToolBatch[0] as $g | $g.hooks[0] | "\(.command) \($g | has("matcher") | not) \(has("if") | not) \(.args | tojson)"' "$HOOKS_JSON")"
  # shellcheck disable=SC2016
  EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","GO_FORMAT_ENABLED","--require-true","GO_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/go-format.sh","--end-of-turn"]'
  expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
  expect "hooks.json: the end-of-turn option is declared, default false" "boolean false" \
    "$(jq -r '.userConfig.go_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  expect "hooks.json: SessionStart holds the probe and the node notice only" "2" "$(jq '[.hooks.SessionStart[] | .hooks[]] | length' "$HOOKS_JSON")"
else
  fail "hooks.json assertions need jq and $HOOKS_JSON"
fi

# --- SessionStart probe honors go_format_enabled -------------------------------
# With the option false the plugin is off, so the missing-goimports notice is
# noise. The row's --run-if-unset-or-true gate makes the launcher exit 0 before
# bash starts. The argv is read out of hooks.json, so the row and this test
# cannot disagree. The unset and true cases guard against gating everything off.
NODE_BIN="$(command -v node || true)"
SYS_PATH="/usr/bin:/bin"
WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$WORK" "$UNRELATED"' EXIT
if [[ -z "$NODE_BIN" ]] || ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: node or jq not on PATH -- SessionStart probe gate cases skipped"
elif PATH="$SYS_PATH" command -v goimports >/dev/null 2>&1; then
  echo "SKIP: goimports is under $SYS_PATH -- SessionStart probe gate cases skipped"
else
  PROBE_ARGS=()
  while IFS= read -r probe_arg; do
    PROBE_ARGS+=("${probe_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
  done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")
  # run_probe_row <data-dir> [NAME=value ...]: the row under a clean environment.
  run_probe_row() {
    local data="$1"
    shift
    env -i PATH="$SYS_PATH" CLAUDE_PLUGIN_DATA="$data" "$@" "$NODE_BIN" "${PROBE_ARGS[@]}" <<<'{"session_id":"s1"}'
  }
  for probe_case in false unset true; do
    PROBE_DATA="$(mktemp -d "$WORK/probe-data.XXXXXX")"
    probe_env=()
    [[ "$probe_case" == unset ]] || probe_env=("CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=$probe_case")
    PROBE_OUT="$(run_probe_row "$PROBE_DATA" ${probe_env[@]+"${probe_env[@]}"})"
    PROBE_RC=$?
    if [[ "$probe_case" == false ]]; then
      expect "probe-gate/false: go_format_enabled=false exits 0 with no goimports notice" "0|" "$PROBE_RC|$PROBE_OUT"
    elif [[ $PROBE_RC -eq 0 && "$PROBE_OUT" == *"goimports not on the hook PATH"* ]]; then
      ok "probe-gate/$probe_case: go_format_enabled $probe_case still reports the missing goimports"
    else
      fail "probe-gate/$probe_case: want rc 0 and the missing-goimports notice (rc=$PROBE_RC out=$PROBE_OUT)"
    fi
  done
fi

# Resolve a real goimports binary. Skip the rest of the suite when none is available.
if [[ -n "${GOIMPORTS_TEST_BIN:-}" && -x "${GOIMPORTS_TEST_BIN}" ]]; then
  REAL_GOIMPORTS="${GOIMPORTS_TEST_BIN}"
elif command -v goimports >/dev/null 2>&1; then
  REAL_GOIMPORTS="$(command -v goimports)"
else
  echo "SKIP: no goimports binary (set GOIMPORTS_TEST_BIN or put goimports on PATH) -- remaining go-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
fi
# The PATH every run that needs the real binary hands the hook.
GOIMPORTS_PATH="$(dirname "$REAL_GOIMPORTS"):$PATH"

# The row's args from hooks.json, with the plugin root substituted.
mapfile -t ROW_ARGS < <(jq -r '.hooks.PostToolBatch[0].hooks[0].args[]' "$HOOKS_JSON" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN_ROOT#g")

new_go_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# payload <tool> <file>...: a PostToolBatch payload with one call per file.
payload() {
  local tool="$1"
  shift
  jq -n --arg t "$tool" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [$ARGS.positional[] | {tool_name: $t, tool_input: {file_path: .}, tool_use_id: "toolu_x", tool_response: "ok"}]}' --args "$@"
}

# fire <payload> [env...]: the registered row, from an unrelated cwd. CLAUDE_PROJECT_DIR
# stays unset so scoping falls to git-working-tree membership.
fire() {
  local p="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true PATH="$GOIMPORTS_PATH" "$@" node "${ROW_ARGS[@]}" <<<"$p" 2>&1
  )
}

# run_edit <file>: Edit one file in a batch; prints the row's whole output.
run_edit() { fire "$(payload Edit "$1")"; }

NEEDS_IMPORT=$'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}'
WITH_IMPORT=$'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("hi")\n}'

REPO="$WORK/consumer"
new_go_repo "$REPO"
mkdir -p "$REPO/src"

# --- No Go config anywhere: the file is still rewritten, and nothing prints ----
printf '%s\n' "$NEEDS_IMPORT" >"$REPO/src/fix.go"
OUT=$(run_edit "$REPO/src/fix.go")
RC=$?
expect "Edit of a subdirectory file: the missing import is added" "$WITH_IMPORT" "$(cat "$REPO/src/fix.go")"
expect "a rewrite prints nothing to the model or the user, exit 0" "0|" "$RC|$OUT"

printf '%s\n' "$WITH_IMPORT" >"$REPO/clean.go"
OUT=$(run_edit "$REPO/clean.go")
expect "a clean file: silent exit 0 and unchanged" "0||$WITH_IMPORT" "$?|$OUT|$(cat "$REPO/clean.go")"

printf 'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/unused.go"
run_edit "$REPO/unused.go" >/dev/null
unused_src="$(cat "$REPO/unused.go")"
expect "an unused import is removed and the used one stays" "no yes" \
  "$([[ "$unused_src" == *'"os"'* ]] && echo yes || echo no) $([[ "$unused_src" == *'"fmt"'* ]] && echo yes || echo no)"

# A syntax error is left alone and nothing about it reaches the model.
BROKEN=$'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}'
printf '%s\n' "$BROKEN" >"$REPO/syntax.go"
OUT=$(run_edit "$REPO/syntax.go")
expect "a file that does not parse: silent, exit 0, bytes unchanged" "0||$BROKEN" "$?|$OUT|$(cat "$REPO/syntax.go")"

# -local: the module's own imports get their own group after third-party ones.
if command -v go >/dev/null 2>&1; then
  REPO_LOCAL="$WORK/local-grouping"
  new_go_repo "$REPO_LOCAL"
  printf 'module example.com/localtest\n\ngo 1.23\n' >"$REPO_LOCAL/go.mod"
  mkdir -p "$REPO_LOCAL/internal/pkg"
  printf 'package pkg\n\nfunc Hello() string { return "hi" }\n' >"$REPO_LOCAL/internal/pkg/pkg.go"
  printf 'package main\n\nimport (\n\t"example.com/localtest/internal/pkg"\n\t"fmt"\n\t"github.com/pkg/errors"\n)\n\nfunc main() {\n\tfmt.Println(pkg.Hello())\n\t_ = errors.New("x")\n}\n' >"$REPO_LOCAL/main.go"
  run_edit "$REPO_LOCAL/main.go" >/dev/null
  grouped="$(cat "$REPO_LOCAL/main.go")"
  expect "-local derived from go.mod: the module's own import is grouped after third-party ones" yes \
    "$([[ "$grouped" == *$'"github.com/pkg/errors"\n\n\t"example.com/localtest/internal/pkg"'* ]] && echo yes)"
else
  echo "SKIP: no go binary on PATH -- -local grouping case skipped"
fi

# --- The batch -----------------------------------------------------------------
# One call, several files, all rewritten; a Read, a non-Go file and a duplicate
# are not.
for f in b1 b2 b3; do printf '%s\n' "$NEEDS_IMPORT" >"$REPO/$f.go"; done
printf 'q=1\n' >"$REPO/notes.txt"
BATCH="$(jq -n --arg d "$REPO" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [
  {tool_name: "Write", tool_input: {file_path: "\($d)/b1.go"}, tool_use_id: "1", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b2.go"}, tool_use_id: "2", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b1.go"}, tool_use_id: "3", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/notes.txt"}, tool_use_id: "4", tool_response: "ok"},
  {tool_name: "Read", tool_input: {file_path: "\($d)/b3.go"}, tool_use_id: "5", tool_response: "1\tpackage main"},
  {tool_name: "Bash", tool_input: {command: "ls b3.go"}, tool_use_id: "6", tool_response: "b3.go"}]}')"
OUT=$(fire "$BATCH")
expect "a mixed batch prints nothing" "0|" "$?|$OUT"
expect "batch: a Write'd .go is rewritten" "$WITH_IMPORT" "$(cat "$REPO/b1.go")"
expect "batch: an Edit'd .go is rewritten" "$WITH_IMPORT" "$(cat "$REPO/b2.go")"
expect "batch: a Read'd .go is never rewritten" "$NEEDS_IMPORT" "$(cat "$REPO/b3.go")"
expect "batch: a non-Go file is untouched" "q=1" "$(cat "$REPO/notes.txt")"

# A file that does not parse does not stop its neighbors from being rewritten.
printf '%s\n' "$BROKEN" >"$REPO/bad.go"
printf '%s\n' "$NEEDS_IMPORT" >"$REPO/good.go"
fire "$(payload Edit "$REPO/bad.go" "$REPO/good.go")" >/dev/null
expect "a file that does not parse does not stop another file in the batch" "$WITH_IMPORT" "$(cat "$REPO/good.go")"

printf '%s\n' "$NEEDS_IMPORT" >"$REPO/multi.go"
fire "$(payload MultiEdit "$REPO/multi.go")" >/dev/null
expect "a MultiEdit'd file is rewritten" "$WITH_IMPORT" "$(cat "$REPO/multi.go")"

# --- Skips ----------------------------------------------------------------------
# Go's generated-code marker, behind a license header, a block comment, a BOM, CRLF.
GEN_BODY=$'package main\n\nfunc main() {\n\tfmt.Println("hi")\n}\n'
printf '// Code generated by protoc-gen-go. DO NOT EDIT.\n%s' "$GEN_BODY" >"$REPO/gen1.go"
printf '// Copyright 2026 Example Corp.\n\n// Code generated by "stringer -type Op"; DO NOT EDIT.\n%s' "$GEN_BODY" >"$REPO/gen2.go"
printf '/*\nCopyright.\n*/\n\n// Code generated by protoc-gen-go. DO NOT EDIT.\n%s' "$GEN_BODY" >"$REPO/gen3.go"
printf '  /*\n  Copyright.\n  */\n\t\n// Code generated by protoc-gen-go. DO NOT EDIT.\n%s' "$GEN_BODY" >"$REPO/gen4.go"
printf '// Code generated by protoc-gen-go. DO NOT EDIT.\r\npackage main\r\n\r\nfunc main() {\r\n\tfmt.Println("hi")\r\n}\r\n' >"$REPO/gen5.go"
printf '\xEF\xBB\xBF// Code generated by protoc-gen-go. DO NOT EDIT.\n%s' "$GEN_BODY" >"$REPO/gen6.go"
for g in gen1 gen2 gen3 gen4 gen5 gen6; do cp "$REPO/$g.go" "$WORK/$g.before"; done
fire "$(payload Edit "$REPO/gen1.go" "$REPO/gen2.go" "$REPO/gen3.go" "$REPO/gen4.go" "$REPO/gen5.go" "$REPO/gen6.go")" >/dev/null
for g in gen1 gen2 gen3 gen4 gen5 gen6; do
  expect "generated marker ($g): the file keeps its bytes" "same" "$(cmp -s "$REPO/$g.go" "$WORK/$g.before" && echo same || echo changed)"
done

# The marker after the package clause is not a generated file.
printf 'package main\n\n// Code generated by protoc-gen-go. DO NOT EDIT.\nfunc main() {\n\tfmt.Println("hi")\n}\n' >"$REPO/late.go"
run_edit "$REPO/late.go" >/dev/null
late_src="$(cat "$REPO/late.go")"
expect "the marker after the leading block does not make a file generated" yes "$([[ "$late_src" == *'import "fmt"'* ]] && echo yes)"

# .githooks/ holds installed copies of check scripts, never rewritten here.
mkdir -p "$REPO/.githooks/go-format"
printf '%s\n' "$NEEDS_IMPORT" >"$REPO/.githooks/go-format/copy.go"
fire "$(payload Write "$REPO/.githooks/go-format/copy.go")" >/dev/null
expect "a file under .githooks/ is skipped" "$NEEDS_IMPORT" "$(cat "$REPO/.githooks/go-format/copy.go")"

# The kill switch.
printf '%s\n' "$NEEDS_IMPORT" >"$REPO/kill.go"
OUT=$(fire "$(payload Edit "$REPO/kill.go")" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=false)
expect "kill switch off: silent and the file untouched" "0|$NEEDS_IMPORT" "$?|$OUT$(cat "$REPO/kill.go")"

# goimports absent: the file is skipped silently; the SessionStart probe reports the gap.
REPO_NG="$WORK/no-goimports"
new_go_repo "$REPO_NG"
printf '%s\n' "$NEEDS_IMPORT" >"$REPO_NG/app.go"
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink rm node; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
OUT=$(fire "$(payload Edit "$REPO_NG/app.go")" PATH="$FAKEBIN")
expect "goimports absent: silent exit 0 and the file untouched" "0|$NEEDS_IMPORT" "$?|$OUT$(cat "$REPO_NG/app.go")"

# Gitignored path: neither rewritten by default, unless go_format_lint_gitignored is set.
REPO_IGN="$WORK/gitignored"
new_go_repo "$REPO_IGN"
git -C "$REPO_IGN" config core.excludesFile /dev/null
printf '.work/\n' >"$REPO_IGN/.gitignore"
mkdir -p "$REPO_IGN/.work"
printf '%s\n' "$NEEDS_IMPORT" >"$REPO_IGN/.work/scratch.go"
OUT=$(run_edit "$REPO_IGN/.work/scratch.go")
expect "gitignored: silent and the file not rewritten" "0|$NEEDS_IMPORT" "$?|$OUT$(cat "$REPO_IGN/.work/scratch.go")"
fire "$(payload Edit "$REPO_IGN/.work/scratch.go")" CLAUDE_PLUGIN_OPTION_GO_FORMAT_LINT_GITIGNORED=true >/dev/null
expect "gitignored + go_format_lint_gitignored=true: import added" "$WITH_IMPORT" "$(cat "$REPO_IGN/.work/scratch.go")"

# Symlinked repo root: the file reached through a symlinked directory is still rewritten.
if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_go_repo "$REPO_SL"
  mkdir -p "$REPO_SL/pkg"
  printf '%s\n' "$NEEDS_IMPORT" >"$REPO_SL/pkg/mod.go"
  run_edit "$WORK/symlink-link/pkg/mod.go" >/dev/null
  expect "symlinked root: the file is rewritten" "$WITH_IMPORT" "$(cat "$REPO_SL/pkg/mod.go")"
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

# --- Spawn budget ----------------------------------------------------------------
# PostToolBatch has no matcher, so the row fires on every batch of every session.
# A batch that never mentions .go costs only the node launcher.
CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" go-format PostToolBatch go-format.sh \
    '{"session_id":"census","hook_event_name":"PostToolBatch","cwd":"@DIR@","tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"@DIR@/README.md"},"tool_use_id":"toolu_census","tool_response":"# readme"}]}' \
    --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: a batch with no Go costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
