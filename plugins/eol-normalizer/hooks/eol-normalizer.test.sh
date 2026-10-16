#!/usr/bin/env bash
# Black-box contract test for the eol-normalizer PostToolBatch row, launched
# exactly as hooks.json registers it (node exec-bash.mjs with the row's args).
#
# Proves WIRING + BEHAVIOR: one PostToolBatch row and no PostToolUse row; the row
# rewrites the files a Write, Edit or MultiEdit in the batch named, to the eol
# their repository's own .gitattributes resolves through git check-attr (CRLF to
# LF and LF to CRLF, both on every OS), and never anything a Read or Bash named;
# unspecified paths, -text paths and binary content under text=auto are left
# alone; .githooks/ and gitignored files are skipped unless opted in; the kill
# switch holds; the row prints nothing and exits 0; a batch with no file path
# costs only the launcher.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures and
# .gitattributes. The row is run from an UNRELATED cwd so any reliance on the
# caller's working directory would surface. git and jq are required for the
# behavior cases; without them the suite skips them.
# test-scope: plugins/eol-normalizer/hooks/hooks.json

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/eol-normalizer.sh"
PLUGIN_ROOT="${HOOK_DIR%/*}"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
HOOKS_JSON="$HOOK_DIR/hooks.json"

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

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
trap 'rm -rf "$WORK" "$UNRELATED"' EXIT

if ! command -v jq >/dev/null 2>&1 || ! command -v node >/dev/null 2>&1; then
  echo "SKIP: jq or node not on PATH -- eol-normalizer hook tests skipped"
  exit 0
fi

# --- hooks.json: one PostToolBatch row, no PostToolUse -------------------------
# The batch row takes no matcher and no `if`: the hooks reference says neither
# applies to the event, and an `if` would narrow the .gitattributes-driven file
# set (#3411). `async` could race the next Edit of the file.
# The SessionStart node-notice row is pinned fleet-wide by scripts/node-notice-rows.test.sh.
# shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
EXPECTED_ROW='["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs","--run-if-unset-or-true","EOL_NORMALIZER_ENABLED","--skip-unless-stdin-contains","file_path","${CLAUDE_PLUGIN_ROOT}/hooks/eol-normalizer.sh"]'
expect "hooks.json: no PostToolUse row" "0" "$(jq '[.hooks.PostToolUse // [] | .[]] | length' "$HOOKS_JSON")"
expect "hooks.json: no Stop row (the entry reports nothing, so there is no end-of-turn mode)" "0" "$(jq '[.hooks.Stop // [] | .[]] | length' "$HOOKS_JSON")"
expect "hooks.json: one hook command outside SessionStart" "1" "$(jq '[.hooks | del(.SessionStart)[][].hooks[]] | length' "$HOOKS_JSON")"
expect "hooks.json: one PostToolBatch group with one handler" "1 1" "$(jq -r '.hooks.PostToolBatch | "\(length) \(.[0].hooks | length)"' "$HOOKS_JSON")"
expect "hooks.json: the batch handler is exec form with no matcher, no if, no async, no shell" \
  "node true true true true $EXPECTED_ROW" \
  "$(jq -r '.hooks.PostToolBatch[0] as $g | $g.hooks[0] | "\(.command) \($g | has("matcher") | not) \(has("if") | not) \(has("async") | not) \(has("shell") | not) \(.args | tojson)"' "$HOOKS_JSON")"

ROW_JSON=$(jq -c '.hooks.PostToolBatch[0].hooks[0]' "$HOOKS_JSON")

# --- The kill switch in exec form ------------------------------------------------
# The gate is `--run-if-unset-or-true` in exec-bash.mjs, which exits 0 before
# bash when the option is set to something other than true. A sentinel stands in
# for eol-normalizer.sh and records whether it started. The expected verdict for
# each value comes from the script's own kill-switch line, run under the same
# environment, so the row and the script cannot disagree.
# shellcheck disable=SC2016  # the literal text of the script's kill-switch line
PRED_LINE=$(grep -m1 -F '[[ "${CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED:-true}" == "true" ]] || exit 0' "$HOOK")
if [[ -n "$PRED_LINE" ]]; then
  ok "row-gate: read the script's own kill-switch line"
else
  fail "row-gate: the script's kill-switch line was not found in $HOOK"
fi

ROWGATE="$(mktemp -d "$WORK/rowgate.XXXXXX")"
mkdir -p "$ROWGATE/root/hooks"
# shellcheck disable=SC2016  # the sentinel's own lines, expanded when it runs
printf '%s\n' '#!/usr/bin/env bash' ': >"$ROWGATE_OUT/started"' 'cat >"$ROWGATE_OUT/stdin"' 'exit 7' \
  >"$ROWGATE/root/hooks/eol-normalizer.sh"
chmod +x "$ROWGATE/root/hooks/eol-normalizer.sh"
cp "$HOOK_DIR/exec-bash.mjs" "$ROWGATE/root/hooks/exec-bash.mjs"
printf '{"session_id":"row-1","hook_event_name":"PostToolBatch","tool_calls":[{"tool_name":"Write","tool_input":{"file_path":"x.txt"}}]}\n' >"$ROWGATE/payload"
ROW_ARGS_RUN=()
while IFS= read -r row_arg; do
  # shellcheck disable=SC2016  # the placeholder is matched literally, as Claude Code substitutes it
  ROW_ARGS_RUN+=("${row_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$ROWGATE/root}")
done < <(jq -r '.args[]' <<<"$ROW_JSON")

# run_opt <case-dir> <value|__unset__> <command...> -> run <command> with the
# option set to <value> (or unset) and ROWGATE_OUT pointing at <case-dir>.
run_opt() {
  local out="$1" v="$2"
  shift 2
  if [[ "$v" == "__unset__" ]]; then
    env -u CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED ROWGATE_OUT="$out" "$@"
  else
    env CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED="$v" ROWGATE_OUT="$out" "$@"
  fi
}

ROW_VALUES=("__unset__" "" "true" "false" "False" "TRUE" "0" "1" "yes" " true" "-n" "a=b")
i=0
for v in "${ROW_VALUES[@]}"; do
  i=$((i + 1))
  label="'$v'"
  [[ "$v" == "__unset__" ]] && label="unset"
  case "$v" in
    __unset__ | "" | true) want=started ;;
    *) want=skipped ;;
  esac
  case_dir="$ROWGATE/case$i"
  mkdir -p "$case_dir"
  run_opt "$case_dir" "$v" bash -c "$PRED_LINE"$'\nexit 3' </dev/null
  if [[ $? -eq 3 ]]; then pred=started; else pred=skipped; fi
  row_out=$(run_opt "$case_dir" "$v" node "${ROW_ARGS_RUN[@]}" <"$ROWGATE/payload")
  row_rc=$?
  if [[ -e "$case_dir/started" ]]; then got=started; else got=skipped; fi

  if [[ "$got" == "$pred" ]]; then
    ok "row-gate/$label: the row agrees with the script's own predicate ($got)"
  else
    fail "row-gate/$label: the row $got the script but its own predicate says $pred"
  fi
  if [[ "$want" == started ]]; then
    if [[ "$got" == started && $row_rc -eq 7 ]] && cmp -s "$ROWGATE/payload" "$case_dir/stdin"; then
      ok "row-gate/$label: the row starts the script with stdin unchanged and returns its exit code"
    else
      fail "row-gate/$label: want the script started with stdin unchanged and rc 7 (got=$got rc=$row_rc)"
    fi
  else
    if [[ "$got" == skipped && $row_rc -eq 0 && -z "$row_out" ]]; then
      ok "row-gate/$label: the row exits 0 silently without starting the script"
    else
      fail "row-gate/$label: want no start, rc 0, empty stdout (got=$got rc=$row_rc out=$row_out)"
    fi
  fi
done

# An inherited nounset (exported SHELLOPTS, or a BASH_ENV that runs `set -u`)
# must not turn an unset option into a failed row: unset means on.
printf 'set -u\n' >"$ROWGATE/nounset.env"
for how in SHELLOPTS BASH_ENV; do
  case_dir="$ROWGATE/nounset-$how"
  mkdir -p "$case_dir"
  if [[ "$how" == SHELLOPTS ]]; then
    run_opt "$case_dir" __unset__ env SHELLOPTS=nounset node "${ROW_ARGS_RUN[@]}" <"$ROWGATE/payload"
  else
    run_opt "$case_dir" __unset__ env BASH_ENV="$ROWGATE/nounset.env" node "${ROW_ARGS_RUN[@]}" <"$ROWGATE/payload"
  fi
  row_rc=$?
  if [[ -e "$case_dir/started" && $row_rc -eq 7 ]]; then
    ok "row-gate/nounset-$how: an unset option still starts the script"
  else
    fail "row-gate/nounset-$how: want the script started and rc 7 (started=$([[ -e "$case_dir/started" ]] && echo yes || echo no) rc=$row_rc)"
  fi
done

# A batch whose payload never names a file path is closed by the launcher, so
# bash never starts.
case_dir="$ROWGATE/no-file-path"
mkdir -p "$case_dir"
row_out=$(run_opt "$case_dir" true node "${ROW_ARGS_RUN[@]}" <<<'{"session_id":"row-2","hook_event_name":"PostToolBatch","tool_calls":[{"tool_name":"Bash","tool_input":{"command":"ls"}}]}')
if [[ ! -e "$case_dir/started" && $? -eq 0 && -z "$row_out" ]]; then
  ok "row-gate: a batch with no file_path never starts the script"
else
  fail "row-gate: a batch with no file_path started the script or printed output ($row_out)"
fi

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not on PATH -- eol-normalizer behavior tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
fi

cr_count() { tr -cd '\r' <"$1" | wc -c | tr -d ' '; }

new_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# The row's args from hooks.json, with the plugin root substituted.
mapfile -t ROW_ARGS < <(jq -r '.hooks.PostToolBatch[0].hooks[0].args[]' "$HOOKS_JSON" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$PLUGIN_ROOT#g")

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
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=true "$@" node "${ROW_ARGS[@]}" <<<"$p" 2>&1
  )
}

run_write() { fire "$(payload Write "$1")"; }

REPO="$WORK/consumer"
new_repo "$REPO"
# The consuming repo's authority: .sh -> LF, .txt -> CRLF, .png unspecified.
printf '*.sh eol=lf\n*.txt eol=crlf\n' >"$REPO/.gitattributes"

# --- LF arm and CRLF arm (every OS), and the row prints nothing ----------------
printf 'echo a\r\necho b\r\n' >"$REPO/seed.sh"
expect "pre: seed.sh seeded with 2 CR" "2" "$(cr_count "$REPO/seed.sh")"
OUT=$(run_write "$REPO/seed.sh")
expect "LF arm: exit 0 and nothing printed (no disclosure reaches the model)" "0|" "$?|$OUT"
expect "LF arm: CRLF .sh -> 0 CR" "0" "$(cr_count "$REPO/seed.sh")"
expect "LF arm: only the carriage returns went" "$(printf 'echo a\necho b')" "$(cat "$REPO/seed.sh")"

printf 'line one\nline two\n' >"$REPO/gap.txt"
OUT=$(run_write "$REPO/gap.txt")
expect "CRLF arm: exit 0 and nothing printed" "0|" "$?|$OUT"
expect "CRLF arm: LF .txt -> 2 CR" "2" "$(cr_count "$REPO/gap.txt")"

printf 'line one\r\nline two\r\n' >"$REPO/already.txt"
run_write "$REPO/already.txt" >/dev/null
expect "CRLF arm: an already-CRLF file does not become CRCRLF" "2" "$(cr_count "$REPO/already.txt")"

# --- Unspecified -> no-op ------------------------------------------------------
printf 'not really binary\r\n' >"$REPO/img.png"
OUT=$(run_write "$REPO/img.png")
expect "unspecified .png: silent exit 0" "0|" "$?|$OUT"
expect "unspecified .png: CR preserved (no-op)" "1" "$(cr_count "$REPO/img.png")"

# --- Kill switch -------------------------------------------------------------------
printf 'echo x\r\n' >"$REPO/off.sh"
OUT=$(fire "$(payload Write "$REPO/off.sh")" CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_ENABLED=false)
expect "kill switch: silent exit 0" "0|" "$?|$OUT"
expect "kill switch: CRLF preserved" "1" "$(cr_count "$REPO/off.sh")"

# --- text=auto binary guard: NUL content is never rewritten --------------------
# Under a broad `* text=auto eol=lf` rule, check-attr resolves eol=lf for
# binaries too; the hook must content-sniff and skip instead of corrupting.
AUTOREPO="$WORK/autorepo"
new_repo "$AUTOREPO"
printf '* text=auto eol=lf\n' >"$AUTOREPO/.gitattributes"
printf 'BIN\r\n\x00\x01\x02\r\ndata' >"$AUTOREPO/blob.bin"
BIN_BYTES_BEFORE=$(wc -c <"$AUTOREPO/blob.bin" | tr -d ' ')
run_write "$AUTOREPO/blob.bin" >/dev/null
expect "binary guard: NUL file under text=auto eol=lf left byte-identical" "$BIN_BYTES_BEFORE 2" \
  "$(wc -c <"$AUTOREPO/blob.bin" | tr -d ' ') $(cr_count "$AUTOREPO/blob.bin")"
printf 'echo t\r\n' >"$AUTOREPO/auto.sh"
run_write "$AUTOREPO/auto.sh" >/dev/null
expect "binary guard: a text file under text=auto is still normalized" "0" "$(cr_count "$AUTOREPO/auto.sh")"

# --- -text is never rewritten even with eol set --------------------------------
printf '*.dat -text eol=lf\n' >>"$AUTOREPO/.gitattributes"
printf 'a\r\nb\r\n' >"$AUTOREPO/keep.dat"
run_write "$AUTOREPO/keep.dat" >/dev/null
expect "-text guard: CR preserved despite eol=lf" "2" "$(cr_count "$AUTOREPO/keep.dat")"

# --- No-perl fallback preserves file mode (white-box) --------------------------
# The mktemp fallback stages into a fresh temp file; without mode preservation
# a 755 script would come back non-executable. Shadow `command` so the lib's
# perl probe fails, forcing the fallback arm.
printf '#!/bin/sh\r\necho hi\r\n' >"$REPO/exec.sh"
chmod 755 "$REPO/exec.sh"
(
  # shellcheck disable=SC2329  # invoked indirectly: the sourced lib's `command -v perl` probe hits this shadow
  command() {
    if [[ "${1:-}" == "-v" && "${2:-}" == "perl" ]]; then return 1; fi
    builtin command "$@"
  }
  if command -v perl >/dev/null 2>&1; then
    echo "FAIL: test shim: perl shadow ineffective" >&2
    exit 1
  fi
  # shellcheck source=normalize-eol.sh
  source "$HOOK_DIR/normalize-eol.sh"
  normalize_eol_to_lf "$REPO/exec.sh"
) || fail "fallback: subshell failed"
expect "fallback: CRLF stripped without perl" "0" "$(cr_count "$REPO/exec.sh")"
if [[ -x "$REPO/exec.sh" ]]; then ok "fallback: executable mode preserved"; else fail "fallback: exec bit lost"; fi

# --- The batch -----------------------------------------------------------------
# One batch, several tools: Write, Edit and MultiEdit files are rewritten, once
# each even when named twice; a Read and a Bash command are not.
printf 'a\r\n' >"$REPO/b1.sh"
printf 'b\r\n' >"$REPO/b2.sh"
printf 'c\r\n' >"$REPO/b3.sh"
printf 'd\r\n' >"$REPO/b4.sh"
printf 'e\r\n' >"$REPO/b5.sh"
BATCH="$(jq -n --arg d "$REPO" '{session_id: "s", hook_event_name: "PostToolBatch", tool_calls: [
  {tool_name: "Write", tool_input: {file_path: "\($d)/b1.sh"}, tool_use_id: "1", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b2.sh"}, tool_use_id: "2", tool_response: "ok"},
  {tool_name: "MultiEdit", tool_input: {file_path: "\($d)/b3.sh"}, tool_use_id: "3", tool_response: "ok"},
  {tool_name: "Edit", tool_input: {file_path: "\($d)/b1.sh"}, tool_use_id: "4", tool_response: "ok"},
  {tool_name: "Read", tool_input: {file_path: "\($d)/b4.sh"}, tool_use_id: "5", tool_response: "1\ta"},
  {tool_name: "Bash", tool_input: {command: "cat b5.sh"}, tool_use_id: "6", tool_response: "e"}]}')"
OUT=$(fire "$BATCH")
expect "a mixed batch prints nothing" "0|" "$?|$OUT"
expect "batch: a Write'd file is rewritten" "0" "$(cr_count "$REPO/b1.sh")"
expect "batch: an Edit'd file is rewritten" "0" "$(cr_count "$REPO/b2.sh")"
expect "batch: a MultiEdit'd file is rewritten" "0" "$(cr_count "$REPO/b3.sh")"
expect "batch: a Read'd file is never rewritten" "1" "$(cr_count "$REPO/b4.sh")"
expect "batch: a file only Bash mentioned is never rewritten" "1" "$(cr_count "$REPO/b5.sh")"

# A Read-only batch reaches the script (the launcher flag matches file_path) and
# the script returns without touching the file.
printf 'r\r\n' >"$REPO/readonly.sh"
OUT=$(fire "$(payload Read "$REPO/readonly.sh")")
expect "a Read-only batch: silent and the file untouched" "0|1" "$?|$(cr_count "$REPO/readonly.sh")"

# A file that is missing does not stop its neighbors.
printf 'n\r\n' >"$REPO/neighbor.sh"
fire "$(payload Write "$REPO/missing.sh" "$REPO/neighbor.sh")" >/dev/null
expect "a missing file does not stop another file in the batch" "0" "$(cr_count "$REPO/neighbor.sh")"

# --- Skips ---------------------------------------------------------------------
# .githooks/ holds installed copies of check scripts, never rewritten here.
mkdir -p "$REPO/.githooks/eol-normalizer"
printf 'g\r\n' >"$REPO/.githooks/eol-normalizer/copy.sh"
fire "$(payload Write "$REPO/.githooks/eol-normalizer/copy.sh")" >/dev/null
expect "a file under .githooks/ is skipped" "1" "$(cr_count "$REPO/.githooks/eol-normalizer/copy.sh")"

# Gitignored path: left alone by default, unless eol_normalizer_lint_gitignored is
# set. A TRACKED file matching an ignore pattern stays in scope.
REPO_IGN="$WORK/gitignored"
new_repo "$REPO_IGN"
git -C "$REPO_IGN" config core.excludesFile /dev/null
printf '*.sh eol=lf\n' >"$REPO_IGN/.gitattributes"
printf '.work/\n*.gen.sh\n' >"$REPO_IGN/.gitignore"
mkdir -p "$REPO_IGN/.work"
printf 'echo a\r\necho b\r\n' >"$REPO_IGN/.work/scratch.sh"
OUT=$(run_write "$REPO_IGN/.work/scratch.sh")
expect "gitignored: silent and the CRLF file untouched" "|2" "$OUT|$(cr_count "$REPO_IGN/.work/scratch.sh")"
fire "$(payload Write "$REPO_IGN/.work/scratch.sh")" CLAUDE_PLUGIN_OPTION_EOL_NORMALIZER_LINT_GITIGNORED=true >/dev/null
expect "gitignored + eol_normalizer_lint_gitignored=true: file normalized" "0" "$(cr_count "$REPO_IGN/.work/scratch.sh")"
printf 'echo a\r\n' >"$REPO_IGN/tracked.gen.sh"
git -C "$REPO_IGN" add -f tracked.gen.sh .gitattributes .gitignore
git -C "$REPO_IGN" commit -q -m init
printf 'echo a\r\necho b\r\n' >"$REPO_IGN/tracked.gen.sh"
run_write "$REPO_IGN/tracked.gen.sh" >/dev/null
expect "a tracked file matching an ignore pattern is still normalized" "0" "$(cr_count "$REPO_IGN/tracked.gen.sh")"

# Symlinked repo root: the file reached through a symlinked directory is still rewritten.
if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_repo "$REPO_SL"
  printf '*.sh eol=lf\n' >"$REPO_SL/.gitattributes"
  printf 'x\r\n' >"$REPO_SL/mod.sh"
  run_write "$WORK/symlink-link/mod.sh" >/dev/null
  expect "symlinked root: the file is rewritten" "0" "$(cr_count "$REPO_SL/mod.sh")"
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

# jq absent: the script cannot read the payload and leaves every file alone,
# silently (the check skill and the prerequisites manifest report the gap).
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink node; do # portability-ok: names in a PATH shim, not an mktemp -p call
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
printf 'j\r\n' >"$REPO/nojq.sh"
OUT=$(fire "$(payload Write "$REPO/nojq.sh")" PATH="$FAKEBIN")
expect "jq absent: silent exit 0 and the file untouched" "0|1" "$?|$(cr_count "$REPO/nojq.sh")"

# --- Spawn budget ----------------------------------------------------------------
# PostToolBatch has no matcher, so the row fires on every batch of every session.
# A batch that names no file path costs only the node launcher.
CENSUS="$REPO_ROOT/scripts/hook-census.sh"
if [[ -f "$CENSUS" ]] && command -v strace >/dev/null 2>&1; then
  out="$(bash "$CENSUS" eol-normalizer PostToolBatch eol-normalizer.sh \
    '{"session_id":"census","hook_event_name":"PostToolBatch","cwd":"@DIR@","tool_calls":[{"tool_name":"Bash","tool_input":{"command":"true"},"tool_use_id":"toolu_census","tool_response":"ok"}]}' \
    --check 'test ! -s "$HOOK_STDOUT"')"
  expect "spawn budget: a batch with no file path costs only the node launcher" "spawns=1" "${out%% *}"
else
  echo "NOTE: strace or scripts/hook-census.sh absent; the spawn budget case did not run."
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
