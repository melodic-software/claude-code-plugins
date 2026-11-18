#!/usr/bin/env bash
# test-scope: plugins/python-format/.claude-plugin/plugin.json plugins/python-format/hooks/hooks.json plugins/python-format/prerequisites.json plugins/python-format/lib/prerequisites.mjs plugins/python-format/lib/git-hooks/install.mjs
# test-scope: plugins/python-format/git-hooks/adapters.sh plugins/python-format/lib/git-hooks/resolve-tool.sh

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

MANIFEST="$PLUGIN_ROOT/prerequisites.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
  if jq -e '(.requires | map(.id)) == ["ruff", "jq", "node"] and .requires[0].detect.local_bin == [".venv/bin/ruff"]' "$MANIFEST" >/dev/null 2>&1; then
    ok "manifest: declares exactly ruff (at .venv/bin/ruff), jq and node"
  else
    fail "manifest: expected tools ruff, jq and node with local_bin .venv/bin/ruff: $(cat "$MANIFEST")"
  fi
  MF_LOCAL="$(jq -r '.requires[0].detect.local_bin[0]' "$MANIFEST")"
  WALK_FN="$(sed -n '/^pf__venv_here()/,/^}/p' "$PLUGIN_ROOT/git-hooks/adapters.sh")"
  if [[ -n "$MF_LOCAL" ]] && grep -qF -- "$MF_LOCAL" <<<"$WALK_FN"; then
    ok "manifest binding: the adapter states the manifest's local_bin ($MF_LOCAL)"
  else
    fail "manifest binding: the adapter does not state the manifest's local_bin (needle='$MF_LOCAL')"
  fi
else
  fail "manifest binding needs jq and $MANIFEST"
fi

if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]]; then
  echo "SKIP: the probe cases run git alone on PATH, which Git for Windows cannot"
elif command -v git >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  PROBE_DIR="$(mktemp -d)"
  ln -s "$(command -v git)" "$PROBE_DIR/git"
  PROBE_NODE="$(node -p process.execPath)"
  probe_says() {
    local r="$1" f
    shift
    git init -q "$r"
    for f in "$@"; do mkdir -p "$(dirname "$r/$f")" && : >"$r/$f"; done
    git -C "$r" add -- "$@"
    (cd "$r" && printf '{"session_id":"t"}' | env -i PATH="$PROBE_DIR" HOME="$r" CLAUDE_PROJECT_DIR="$r" \
      "$PROBE_NODE" "$PLUGIN_ROOT/lib/prerequisites.mjs" probe "$PLUGIN_ROOT") || echo "probe exited $?"
  }
  reports() {
    local label="$1" want="$2" got=no out
    shift 2
    out="$(probe_says "$@")"
    [[ "$out" == *"python-format: ruff not on the hook PATH"* ]] && got=yes
    [[ "$out" == *"probe exited"* ]] && got="failed: $out"
    expect "$label" "$want" "$got"
  }
  reports "probe: a config tracked only in a subdirectory reports a missing ruff" yes "$PROBE_DIR/nested" pkg/sub/ruff.toml
  reports "probe: a repository with no config stays quiet about ruff" no "$PROBE_DIR/none" pkg/sub/main.py
  rm -rf "$PROBE_DIR"
else
  fail "probe cases need git and node"
fi

# The batch row takes no matcher and no `if`: the hooks reference says neither
# applies to the event, so its launcher flag is the only filter. The script reads
# the paths itself.
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" ]]; then
  # shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
  EXPECTED_ROW='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","PYTHON_FORMAT_ENABLED","--skip-unless-stdin-contains",".py","${CLAUDE_PLUGIN_ROOT}/hooks/python-format.sh"]'
  expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
  expect "hooks.json: one PostToolBatch group with one handler" "1 1" "$(jq -r '.hooks.PostToolBatch | "\(length) \(.[0].hooks | length)"' "$HOOKS_JSON")"
  expect "hooks.json: the batch handler has no matcher, no if, and runs the script behind the .py prefilter" \
    "node true true $EXPECTED_ROW" \
    "$(jq -r '.hooks.PostToolBatch[0] as $g | $g.hooks[0] | "\(.command) \($g | has("matcher") | not) \(has("if") | not) \(.args | tojson)"' "$HOOKS_JSON")"
  # shellcheck disable=SC2016
  EXPECTED_STOP='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","PYTHON_FORMAT_ENABLED","--require-true","PYTHON_FORMAT_END_OF_TURN","${CLAUDE_PLUGIN_ROOT}/hooks/python-format.sh","--end-of-turn"]'
  expect "hooks.json: the Stop row is gated on the end-of-turn option" "$EXPECTED_STOP" "$(jq -c '.hooks.Stop[0].hooks[0].args' "$HOOKS_JSON")"
  expect "hooks.json: the end-of-turn option is declared, default false" "boolean false" \
    "$(jq -r '.userConfig.python_format_end_of_turn | "\(.type) \(.default)"' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
else
  fail "hooks.json assertions need jq and $HOOKS_JSON"
fi

expect "prerequisites.json: session_probe is gated on python_format_enabled" "PYTHON_FORMAT_ENABLED" \
  "$(jq -r '.session_probe.run_if_unset_or_true' "$PLUGIN_ROOT/prerequisites.json" | tr -d '\r')"

if [[ -n "${RUFF_TEST_BIN:-}" && -x "${RUFF_TEST_BIN}" ]]; then
  REAL_RUFF="${RUFF_TEST_BIN}"
elif command -v ruff >/dev/null 2>&1; then
  REAL_RUFF="$(command -v ruff)"
else
  echo "SKIP: no Ruff binary (set RUFF_TEST_BIN or put ruff on PATH) -- remaining python-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$WORK" "$UNRELATED"' EXIT

mapfile -t ROW_ARGS < <(jq -r '.hooks.PostToolBatch[0].hooks[0].args[]' "$HOOKS_JSON" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN_ROOT#g")

new_ruff_repo() {
  local r="$1" cfg="${2:-}"
  mkdir -p "$r/.venv/bin"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exec "%s" "$@"\n' "$REAL_RUFF"
  } >"$r/.venv/bin/ruff"
  chmod +x "$r/.venv/bin/ruff"
  if [[ "$cfg" != "NO_CONFIG" ]]; then
    if [[ -n "$cfg" ]]; then
      printf '%s\n' "$cfg" >"$r/ruff.toml"
    else
      printf 'line-length = 88\n' >"$r/ruff.toml"
    fi
  fi
}

payload() {
  local tool="$1"
  shift
  jq -n --arg t "$tool" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [$ARGS.positional[] | {tool_name: $t, tool_input: {file_path: .}, tool_use_id: "toolu_x", tool_response: "ok"}]}' --args "$@"
}

fire() {
  local p="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_ENABLED=true "$@" node "${ROW_ARGS[@]}" <<<"$p" 2>&1
  )
}

run_edit() { fire "$(payload Edit "$1")"; }

REPO_NO="$WORK/no-config"
new_ruff_repo "$REPO_NO" NO_CONFIG
printf 'x=1\n' >"$REPO_NO/nofmt.py"
OUT=$(run_edit "$REPO_NO/nofmt.py")
RC=$?
expect "no config: exit 0 and silent" "0|" "$RC|$OUT"
expect "no config: file left untouched" "x=1" "$(cat "$REPO_NO/nofmt.py")"

# pyproject.toml WITHOUT [tool.ruff] does not opt in: Ruff ignores it for config
# discovery, so the gate does too.
REPO_PP="$WORK/pyproject-plain"
new_ruff_repo "$REPO_PP" NO_CONFIG
printf '[project]\nname = "t"\n' >"$REPO_PP/pyproject.toml"
printf 'x=1\n' >"$REPO_PP/plain.py"
run_edit "$REPO_PP/plain.py" >/dev/null
expect "pyproject without [tool.ruff]: file left untouched" "x=1" "$(cat "$REPO_PP/plain.py")"

REPO_PT="$WORK/pyproject-ruff"
new_ruff_repo "$REPO_PT" NO_CONFIG
printf '[project]\nname = "t"\n\n[tool.ruff]\nline-length = 88\n' >"$REPO_PT/pyproject.toml"
printf 'x=1\n' >"$REPO_PT/opt.py"
run_edit "$REPO_PT/opt.py" >/dev/null
expect "pyproject with [tool.ruff]: file formatted" "x = 1" "$(cat "$REPO_PT/opt.py")"

REPO_PI="$WORK/pyproject-inline"
new_ruff_repo "$REPO_PI" NO_CONFIG
printf '[project]\nname = "t"\n\n[tool]\nruff = { line-length = 88 }\n' >"$REPO_PI/pyproject.toml"
printf 'x=1\n' >"$REPO_PI/inline.py"
run_edit "$REPO_PI/inline.py" >/dev/null
expect "pyproject with [tool] inline-table ruff: file left untouched (known limitation)" "x=1" "$(cat "$REPO_PI/inline.py")"

REPO="$WORK/consumer"
new_ruff_repo "$REPO"
mkdir -p "$REPO/src" "$REPO/lib"
printf 'x=1\ny  =  2\n' >"$REPO/src/fmt.py"
OUT=$(run_edit "$REPO/src/fmt.py")
RC=$?
expect "Edit of a subdirectory file: formatted" "$(printf 'x = 1\ny = 2')" "$(cat "$REPO/src/fmt.py")"
expect "a rewrite prints nothing to the model or the user, exit 0" "0|" "$RC|$OUT"

printf 'x = 1\n' >"$REPO/clean.py"
OUT=$(run_edit "$REPO/clean.py")
expect "a clean file: silent exit 0 and unchanged" "0||x = 1" "$?|$OUT|$(cat "$REPO/clean.py")"

printf 'x=1\nprint(undefined_name)\n' >"$REPO/lib/lint.py"
OUT=$(run_edit "$REPO/lib/lint.py")
expect "a lint finding is not reported (no additionalContext, no systemMessage)" "0|" "$?|$OUT"
expect "the finding's file is still formatted" "$(printf 'x = 1\nprint(undefined_name)')" "$(cat "$REPO/lib/lint.py")"

printf 'def f(:\n' >"$REPO/syntax.py"
OUT=$(run_edit "$REPO/syntax.py")
expect "a mid-edit syntax error is silent" "0|" "$?|$OUT"

printf 'import os\n' >"$REPO/imp.py"
run_edit "$REPO/imp.py" >/dev/null
expect "an unused import survives the in-session rewrite" "import os" "$(cat "$REPO/imp.py")"

REPO_FIX="$WORK/safe-fix"
new_ruff_repo "$REPO_FIX" $'[lint]\nselect = ["I"]'
printf 'import sys\nimport os\n\nprint(os, sys)\n' >"$REPO_FIX/fix.py"
run_edit "$REPO_FIX/fix.py" >/dev/null
expect "selected import sorting is applied" "$(printf 'import os\nimport sys\n\nprint(os, sys)')" "$(cat "$REPO_FIX/fix.py")"

REPO_LF="$WORK/no-lint-fix"
new_ruff_repo "$REPO_LF" $'[lint]\nselect = ["F", "I"]'
printf 'x = f"plain"\n' >"$REPO_LF/f.py"
run_edit "$REPO_LF/f.py" >/dev/null
expect "a safe fix of a selected lint rule (F541) is not applied in session" 'x = f"plain"' "$(cat "$REPO_LF/f.py")"

REPO_UNSAFE="$WORK/unsafe-fixes"
new_ruff_repo "$REPO_UNSAFE" $'unsafe-fixes = true\nlint.select = ["E712"]'
printf 'x = 1\nif x == True:\n    pass\n' >"$REPO_UNSAFE/u.py"
run_edit "$REPO_UNSAFE/u.py" >/dev/null
expect "an unsafe fix is not applied despite unsafe-fixes = true" "if x == True:" "$(sed -n 2p "$REPO_UNSAFE/u.py")"

printf 'a=1\n' >"$REPO/b1.py"
printf 'b=1\n' >"$REPO/b2.pyi"
printf 'c=1\n' >"$REPO/b3.py"
printf 'q=1\n' >"$REPO/notes.txt"
BATCH="$(jq -n --arg d "$REPO" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [
  {tool_name: "Write", tool_input: {file_path: "\($d)/b1.py"}, tool_use_id: "1", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b2.pyi"}, tool_use_id: "2", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b1.py"}, tool_use_id: "3", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/notes.txt"}, tool_use_id: "4", tool_response: "ok"},
  {tool_name: "Read", tool_input: {file_path: "\($d)/b3.py"}, tool_use_id: "5", tool_response: "1\tc=1"},
  {tool_name: "Bash", tool_input: {command: "ls b3.py"}, tool_use_id: "6", tool_response: "b3.py"}]}')"
OUT=$(fire "$BATCH")
expect "a mixed batch prints nothing" "0|" "$?|$OUT"
expect "batch: a Write'd .py is rewritten" "a = 1" "$(cat "$REPO/b1.py")"
expect "batch: an Edit'd .pyi is rewritten" "b = 1" "$(cat "$REPO/b2.pyi")"
expect "batch: a Read'd .py is never rewritten" "c=1" "$(cat "$REPO/b3.py")"
expect "batch: a non-Python file is untouched" "q=1" "$(cat "$REPO/notes.txt")"

printf 'def f(:\n' >"$REPO/bad.py"
printf 'z=1\n' >"$REPO/good.py"
fire "$(payload Edit "$REPO/bad.py" "$REPO/good.py")" >/dev/null
expect "a syntax-error file does not stop another file in the batch" "z = 1" "$(cat "$REPO/good.py")"

printf 'm=1\n' >"$REPO/multi.py"
fire "$(payload MultiEdit "$REPO/multi.py")" >/dev/null
expect "a MultiEdit'd file is rewritten" "m = 1" "$(cat "$REPO/multi.py")"

mkdir -p "$REPO/.githooks/python-format"
printf 'g=1\n' >"$REPO/.githooks/python-format/copy.py"
fire "$(payload Write "$REPO/.githooks/python-format/copy.py")" >/dev/null
expect "a file under .githooks/ is skipped" "g=1" "$(cat "$REPO/.githooks/python-format/copy.py")"

REPO_EX="$WORK/exclude-config"
new_ruff_repo "$REPO_EX" 'extend-exclude = ["gen"]'
mkdir -p "$REPO_EX/gen"
printf 'x=1\n' >"$REPO_EX/gen/g.py"
OUT=$(run_edit "$REPO_EX/gen/g.py")
expect "an excluded file is left untouched and silent" "0|x=1" "$?|$OUT$(cat "$REPO_EX/gen/g.py")"

printf 'k=1\n' >"$REPO/kill.py"
OUT=$(fire "$(payload Edit "$REPO/kill.py")" CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_ENABLED=false)
expect "kill switch off: silent and the file untouched" "0|k=1" "$?|$OUT$(cat "$REPO/kill.py")"

REPO_PATH="$WORK/path-fallback"
mkdir -p "$REPO_PATH"
git -C "$REPO_PATH" init -q
printf 'line-length = 88\n' >"$REPO_PATH/ruff.toml"
printf 'p=1\n' >"$REPO_PATH/p.py"
fire "$(payload Edit "$REPO_PATH/p.py")" PATH="$(dirname "$REAL_RUFF"):$PATH" >/dev/null
expect "PATH fallback: Ruff resolved and file formatted" "p = 1" "$(cat "$REPO_PATH/p.py")"

REPO_NR="$WORK/no-ruff"
mkdir -p "$REPO_NR"
git -C "$REPO_NR" init -q
printf 'line-length = 88\n' >"$REPO_NR/.ruff.toml"
printf 'x=1\n' >"$REPO_NR/app.py"
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink node; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
OUT=$(fire "$(payload Edit "$REPO_NR/app.py")" PATH="$FAKEBIN")
expect "ruff absent: silent exit 0 and the file untouched" "0|x=1" "$?|$OUT$(cat "$REPO_NR/app.py")"

REPO_IGN="$WORK/gitignored"
new_ruff_repo "$REPO_IGN"
git -C "$REPO_IGN" config core.excludesFile /dev/null
printf '.work/\n.venv/\n' >"$REPO_IGN/.gitignore"
mkdir -p "$REPO_IGN/.work"
printf 'x=1\n' >"$REPO_IGN/.work/scratch.py"
run_edit "$REPO_IGN/.work/scratch.py" >/dev/null
expect "gitignored: file not rewritten" "x=1" "$(cat "$REPO_IGN/.work/scratch.py")"
fire "$(payload Edit "$REPO_IGN/.work/scratch.py")" CLAUDE_PLUGIN_OPTION_PYTHON_FORMAT_LINT_GITIGNORED=true >/dev/null
expect "gitignored + python_format_lint_gitignored=true: file formatted" "x = 1" "$(cat "$REPO_IGN/.work/scratch.py")"

if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_ruff_repo "$REPO_SL"
  mkdir -p "$REPO_SL/pkg"
  printf 'x=1\n' >"$REPO_SL/pkg/mod.py"
  run_edit "$WORK/symlink-link/pkg/mod.py" >/dev/null
  expect "symlinked root: the file is rewritten" "x = 1" "$(cat "$REPO_SL/pkg/mod.py")"
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

STUB="$WORK/stub"
mkdir -p "$STUB"
# shellcheck disable=SC2016 # the stub's own shell text
printf '#!/bin/sh\nfor a in "$@"; do printf "%%s\\n" "$a" >>"%s/stub.log"; printf "formatted\\n" >"$a"; done\n' "$WORK" >"$STUB/stubfmt"
chmod +x "$STUB/stubfmt"
REPO_REC="$WORK/record"
new_ruff_repo "$REPO_REC"
mkdir -p "$REPO_REC/.claude/ecosystems"
printf 'globs: ["*.py"]\nfix-cmd: "stubfmt <files>"\n' >"$REPO_REC/.claude/ecosystems/python.yaml"
git -C "$REPO_REC" add .claude/ecosystems/python.yaml
git -C "$REPO_REC" commit -q -m record --no-verify
printf 'x=1\n' >"$REPO_REC/r.py"
# shellcheck disable=SC2016 # a literal file name
CRAFTED='$(touch pwned);c.py'
printf 'x=1\n' >"$REPO_REC/$CRAFTED"
: >"$WORK/stub.log"
OUT=$(fire "$(payload Edit "$REPO_REC/r.py" "$REPO_REC/$CRAFTED")" PATH="$STUB:$PATH")
expect "with a record present, Ruff formats, silently" "0|x = 1" "$?|$OUT$(cat "$REPO_REC/r.py")"
expect "the record's command never ran" "" "$(cat "$WORK/stub.log")"
expect "a crafted file name reached Ruff as data" "x = 1" "$(cat "$REPO_REC/$CRAFTED")"
expect "a crafted file name ran nothing" "no" "$([[ -e "$REPO_REC/pwned" || -e "$UNRELATED/pwned" ]] && echo yes || echo no)"

# PostToolBatch has no matcher, so the row fires on every batch of every session.
# A batch that never mentions .py costs only the node launcher.
CENSUS="$REPO_ROOT/scripts/hook-census.sh"
# A working Linux strace, not merely one on PATH: Git Bash ships Cygwin's, which has no -s.
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1 && strace -qq -o /dev/null -e trace=execve true 2>/dev/null; then
  out="$(bash "$CENSUS" python-format PostToolBatch python-format.sh \
    '{"session_id":"census","hook_event_name":"PostToolBatch","cwd":"@DIR@","tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"@DIR@/README.md"},"tool_use_id":"toolu_census","tool_response":"# readme"}]}' \
    --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: a batch with no Python costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: a working strace or scripts/hook-census.sh is absent; the spawn budget case did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
