#!/usr/bin/env bash
# Black-box contract test for ruff-format.sh (the ruff-format plugin hook).
#
# Proves WIRING: the hook fires on .py/.pyi, skips otherwise, applies Ruff's
# safe fixes and formatting, surfaces residual findings via additionalContext
# (advisory, exit 0), honors the kill switch, gates on a consumer Ruff config
# (present -> run, absent -> leave bytes untouched; pyproject.toml counts only
# with [tool.ruff]), protects just-added imports (--unfixable F401), respects
# the config's own excludes for an explicitly-edited file (no nag), flags
# target-version-aware syntax errors, and emits a schema-valid telemetry
# envelope. No source-repo policy prose in the surfaced context.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# Each repo gets a .venv/bin/ruff shim that forwards to a real Ruff, so the
# hook's virtual-environment resolution path is exercised. The hook is invoked
# from an UNRELATED cwd so any reliance on the caller's working directory would
# surface (Ruff's config discovery is file-anchored, not CWD-anchored).
#
# Requires a real Ruff binary: $RUFF_TEST_BIN if set, else `ruff` on PATH.
# Without one the behavioral assertions cannot run, so the suite skips.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/ruff-format.sh"

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

# --- The .venv walk is bound to prerequisites.json ------------------------------
# The missing-binary notice is composed from the manifest at run time; the .venv
# walk is not, so this case is the binding: the manifest lists ruff, jq and node,
# and the walk states ruff's local_bin verbatim.
MANIFEST="${HOOK_DIR%/*}/prerequisites.json"
if command -v jq >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
  if jq -e '(.requires | map(.id)) == ["ruff", "jq", "node"] and .requires[0].detect.local_bin == [".venv/bin/ruff"]' "$MANIFEST" >/dev/null 2>&1; then
    ok "manifest: declares exactly ruff (at .venv/bin/ruff), jq and node"
  else
    fail "manifest: expected tools ruff, jq and node with local_bin .venv/bin/ruff: $(cat "$MANIFEST")"
  fi
  MF_LOCAL="$(jq -r '.requires[0].detect.local_bin[0]' "$MANIFEST")"
  WALK_FN="$(sed -n '/^ruff_venv_bin_here()/,/^}/p' "$HOOK")"
  # assert_hook_states <field> <needle> <haystack>
  assert_hook_states() {
    if [[ -n "$2" ]] && grep -qF -- "$2" <<<"$3"; then
      ok "manifest binding: hook states the manifest's $1 ($2)"
    else
      fail "manifest binding: hook does not state the manifest's $1 (needle='$2')"
    fi
  }
  assert_hook_states local_bin "$MF_LOCAL" "$WALK_FN"
else
  fail "manifest binding needs jq and $MANIFEST"
fi

# --- SessionStart probe honors ruff_format_enabled -----------------------------
# Runs the hooks.json SessionStart row as the harness spawns it: `node` with the
# row's args, ${CLAUDE_PLUGIN_ROOT} expanded, from an empty cwd, on a PATH that
# holds the system tools and no ruff. The gate is `--run-if-unset-or-true` in
# exec-bash.mjs, so a row without it prints the notice for a disabled plugin.
# Needs no real Ruff. A missing node fails the suite instead of skipping the
# cases: every hook row launches through it.
PLUGIN_ROOT="${HOOK_DIR%/*}"
HOOKS_JSON="$HOOK_DIR/hooks.json"
NODE_BIN="$(command -v node 2>/dev/null)"
if [[ -z "$NODE_BIN" ]]; then
  fail "probe-gate: node is not on PATH, and every hook row launches through node hooks/exec-bash.mjs"
else
  PG_WORK="$(mktemp -d)"
  mkdir -p "$PG_WORK/sysbin" "$PG_WORK/cwd"
  for dir in /usr/local/bin /usr/bin /bin; do
    for exe in "$dir"/*; do
      base="${exe##*/}"
      [[ -x "$exe" && "$base" != ruff && ! -e "$PG_WORK/sysbin/$base" ]] || continue
      ln -s "$exe" "$PG_WORK/sysbin/$base"
    done
  done
  PG_ARGS=()
  while IFS= read -r pg_arg; do
    # shellcheck disable=SC2016  # the placeholder is matched literally, as Claude Code substitutes it
    PG_ARGS+=("${pg_arg//\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_ROOT}")
  done < <(jq -r '.hooks.SessionStart[0].hooks[0].args[]' "$HOOKS_JSON")
  IFS=$'\t' read -r PG_NAME PG_CHECK PG_INSTALL < <(jq -r '.requires[0] | [.id, .check, (.install | to_entries[0].value)] | @tsv' "$PLUGIN_ROOT/prerequisites.json")

  # run_probe <value|__unset__> -> run the row with ruff_format_enabled set to <value> (or unset).
  run_probe() {
    local v="$1"
    local -a opt=(env -u CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED)
    [[ "$v" == "__unset__" ]] || opt=(env "CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=$v")
    (cd "$PG_WORK/cwd" && printf '{"session_id":"s1"}' |
      "${opt[@]}" PATH="$PG_WORK/sysbin" CLAUDE_PLUGIN_DATA="$(mktemp -d "$PG_WORK/data.XXXXXX")" \
        "$NODE_BIN" "${PG_ARGS[@]}" 2>&1)
  }

  OUT_PG=$(run_probe false)
  RC_PG=$?
  if [[ $RC_PG -eq 0 && -z "$OUT_PG" ]]; then
    ok "probe-gate: ruff_format_enabled=false -> exit 0 and no notice"
  else
    fail "probe-gate: ruff_format_enabled=false should print nothing and exit 0 (rc=$RC_PG out=$OUT_PG)"
  fi
  for v in __unset__ true; do
    label="ruff_format_enabled=$v"
    [[ "$v" == "__unset__" ]] && label="ruff_format_enabled unset"
    OUT_PG=$(run_probe "$v")
    RC_PG=$?
    if [[ $RC_PG -eq 0 && "$OUT_PG" == *"$PG_NAME"* && "$OUT_PG" == *"$PG_CHECK"* && "$OUT_PG" == *"$PG_INSTALL"* ]]; then
      ok "probe-gate: $label -> notice names $PG_NAME, $PG_CHECK and the install line"
    else
      fail "probe-gate: $label should print the missing-ruff notice (rc=$RC_PG out=$OUT_PG)"
    fi
  done
  rm -rf "${PG_WORK:?}"
fi

# Resolve a real Ruff binary. .venv/bin/ruff shims in each fixture forward to
# this. Skip the suite when none is available.
if [[ -n "${RUFF_TEST_BIN:-}" && -x "${RUFF_TEST_BIN}" ]]; then
  REAL_RUFF="${RUFF_TEST_BIN}"
elif command -v ruff >/dev/null 2>&1; then
  REAL_RUFF="$(command -v ruff)"
else
  echo "SKIP: no Ruff binary (set RUFF_TEST_BIN or put ruff on PATH) -- remaining ruff-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# shellcheck source=hook-test-sink.sh
source "$HOOK_DIR/hook-test-sink.sh"

# new_ruff_repo <dir> [config_body] -> init a git repo with a .venv ruff shim
# and (unless config_body is the literal NO_CONFIG) a ruff.toml.
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

# Invoke the hook from an unrelated cwd with caller-supplied env
# (NAME=VALUE ...). CLAUDE_PROJECT_DIR is left UNSET so read_file_path's
# membership guard is disabled (not part of the fire gate); this isolates
# lint/format behavior from path-form mismatch in the guard.
run_hook_env() {
  local file_path="$1" payload
  shift
  # A here-string, never a pipe: the kill switch exits before reading stdin, and
  # a printf still writing then fails on the closed pipe, which pipefail reports.
  printf -v payload '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path"
  (
    cd "$UNRELATED" || return 1
    env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK" <<<"$payload"
  )
}

run_hook() {
  run_hook_env "$1" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true
}

# --- Case 1: opt-in gate OFF (no Ruff config) -> file left untouched ---------
# The whole conservative opt-in: a repo with Ruff installed but NO config must
# not have its files rewritten to Ruff's built-in defaults.
REPO_NO="$WORK/no-config"
new_ruff_repo "$REPO_NO" NO_CONFIG
printf 'x=1\n' >"$REPO_NO/nofmt.py"
BEFORE_NO="$(cat "$REPO_NO/nofmt.py")"
OUT=$(run_hook "$REPO_NO/nofmt.py")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "gate OFF (no config) -> exit 0, silent"; else fail "gate OFF not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_NO/nofmt.py")" == "$BEFORE_NO" ]]; then ok "gate OFF -> file left untouched"; else fail "gate OFF -> file was rewritten"; fi

# --- Case 1b: pyproject.toml WITHOUT [tool.ruff] does NOT opt in -------------
# Ruff ignores a pyproject.toml lacking [tool.ruff] for config discovery, so
# the gate must too — otherwise a plain Python project would be reformatted to
# Ruff's built-in defaults it never chose.
REPO_PP="$WORK/pyproject-plain"
new_ruff_repo "$REPO_PP" NO_CONFIG
printf '[project]\nname = "t"\n' >"$REPO_PP/pyproject.toml"
printf 'x=1\n' >"$REPO_PP/plain.py"
BEFORE_PP="$(cat "$REPO_PP/plain.py")"
OUT=$(run_hook "$REPO_PP/plain.py")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "pyproject without [tool.ruff] -> exit 0, silent (no opt-in)"; else fail "plain pyproject opted in (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_PP/plain.py")" == "$BEFORE_PP" ]]; then ok "pyproject without [tool.ruff] -> file left untouched"; else fail "plain pyproject -> file was rewritten"; fi

# --- Case 1c: pyproject.toml WITH [tool.ruff] opts in ------------------------
REPO_PT="$WORK/pyproject-ruff"
new_ruff_repo "$REPO_PT" NO_CONFIG
printf '[project]\nname = "t"\n\n[tool.ruff]\nline-length = 88\n' >"$REPO_PT/pyproject.toml"
printf 'x=1\n' >"$REPO_PT/opt.py"
OUT=$(run_hook "$REPO_PT/opt.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "pyproject with [tool.ruff] -> exit 0"; else fail "pyproject opt-in exit $RC"; fi
if grep -q 'x = 1' "$REPO_PT/opt.py"; then ok "pyproject with [tool.ruff] -> file formatted"; else fail "pyproject opt-in -> not formatted: $(cat "$REPO_PT/opt.py")"; fi

# --- Case 1d: pyproject.toml with [tool] inline-table form does NOT opt in ---
# Known limitation (documented in the hook and README): the line-anchored gate
# only recognizes the `[tool.ruff]` header form. A bare `[tool]` header with
# `ruff = { ... }` as an inline table is equivalent TOML that Ruff itself does
# honor, but the gate does not detect it — fails safe (missed opt-in, not a
# wrong edit) rather than heuristically pattern-matching it.
REPO_PI="$WORK/pyproject-inline"
new_ruff_repo "$REPO_PI" NO_CONFIG
printf '[project]\nname = "t"\n\n[tool]\nruff = { line-length = 88 }\n' >"$REPO_PI/pyproject.toml"
printf 'x=1\n' >"$REPO_PI/inline.py"
BEFORE_PI="$(cat "$REPO_PI/inline.py")"
OUT=$(run_hook "$REPO_PI/inline.py")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "pyproject with [tool] inline-table ruff -> exit 0, silent (known limitation)"; else fail "inline-table pyproject opted in (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_PI/inline.py")" == "$BEFORE_PI" ]]; then ok "pyproject with [tool] inline-table ruff -> file left untouched"; else fail "inline-table pyproject -> file was rewritten"; fi

# --- Case 2: gate ON + clean file -> exit 0, empty stdout --------------------
REPO="$WORK/consumer"
new_ruff_repo "$REPO"
printf 'x = 1\n' >"$REPO/clean.py"
OUT=$(run_hook "$REPO/clean.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .py -> exit 0"; else fail "clean .py exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .py -> empty stdout"; else fail "clean .py stdout not empty: $OUT"; fi

# --- Case 3: gate ON + bad formatting (no lint error) -> file formatted ------
mkdir -p "$REPO/src"
printf 'x=1\ny  =  2\n' >"$REPO/src/fmt.py"
OUT=$(run_hook "$REPO/src/fmt.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "format case -> exit 0 (advisory)"; else fail "format case exit $RC"; fi
if grep -q '^x = 1$' "$REPO/src/fmt.py" && grep -q '^y = 2$' "$REPO/src/fmt.py"; then
  ok "gate ON (subdir file) -> Ruff reformatted the file"
else
  fail "gate ON -> file not formatted: $(cat "$REPO/src/fmt.py")"
fi
if printf '%s' "$OUT" | jq -e '.systemMessage == "ruff-format: reformatted fmt.py."' >/dev/null 2>&1; then
  ok "format case -> user-channel mutation disclosure"
else
  fail "format case -> missing systemMessage disclosure: $OUT"
fi

# --- Case 4: gate ON + lint finding (undefined name) -> advisory context -----
# F821 has no auto-fix, so it must survive the fix pass and surface in the
# verify pass. File in a subdir (config at repo root) exercises both the walk
# and the repo-root-relative path passed to Ruff.
mkdir -p "$REPO/lib"
printf 'print(undefined_name)\n' >"$REPO/lib/lint.py"
OUT=$(run_hook "$REPO/lib/lint.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "lint finding -> exit 0 (advisory)"; else fail "lint finding exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q 'F821'; then
    ok "lint finding -> surfaced in additionalContext"
  else
    fail "lint ctx missing the finding: $CTX"
  fi
  # Path is repo-relative (lib/lint.py or lib\lint.py), not absolute. Accept
  # either separator for cross-platform parity.
  if printf '%s' "$CTX" | grep -qE '(^|[^/\\[:alnum:]])lib[/\\]lint\.py' && ! printf '%s' "$CTX" | grep -qiE '[a-z]:[/\\]|^/tmp/'; then
    ok "lint finding -> path is clean and repo-relative"
  else
    fail "lint finding -> path not clean/relative: $CTX"
  fi
  if printf '%s' "$CTX" | grep -qi 'commit/CI will block\|hard gate\|lefthook'; then
    fail "ctx still carries source-repo policy prose: $CTX"
  else
    ok "ctx free of source-repo policy prose"
  fi
else
  fail "lint finding -> no additionalContext JSON: $OUT"
fi

# --- Case 4a: rewrite AND findings -> ONE JSON document, both channels -------
# The #3406 regression: the format pass rewrites (x=1 -> x = 1) AND the verify
# pass reports an unfixable F821, so the run carries a rewrite disclosure and
# findings together. They must compose into a single JSON document — a second
# printed object is an invalid hook response and either message can be lost.
printf 'x=1\nprint(undefined_name)\n' >"$REPO/lib/both.py"
OUT=$(run_hook "$REPO/lib/both.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "rewrite+findings -> exit 0 (advisory)"; else fail "rewrite+findings exit $RC"; fi
DOCS=$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null)
if [[ "$DOCS" == "1" ]]; then
  ok "rewrite+findings -> exactly one JSON document (#3406)"
else
  fail "rewrite+findings -> $DOCS documents on stdout (#3406): $OUT"
fi
if printf '%s' "$OUT" | jq -e '.systemMessage' >/dev/null 2>&1 &&
  printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  MSG=$(printf '%s' "$OUT" | jq -r '.systemMessage')
  if printf '%s' "$CTX" | grep -q 'F821' && printf '%s' "$MSG" | grep -qi 'reformatted'; then
    ok "rewrite+findings -> both channels carried in the one document"
  else
    fail "rewrite+findings -> channels malformed (ctx=$CTX msg=$MSG)"
  fi
else
  fail "rewrite+findings -> a channel is missing: $OUT"
fi

# --- Case 4b: mid-edit syntax error -> surfaced as a finding, not a break ----
# The dominant on-edit trigger: the file does not parse yet. Ruff reports
# invalid-syntax as a regular diagnostic (exit 1), so it must land in the
# findings branch (advisory, exit 0), not be mislabeled as a tool break.
printf 'def f(:\n' >"$REPO/syntax.py"
OUT=$(run_hook "$REPO/syntax.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "syntax error -> exit 0 (advisory)"; else fail "syntax error exit $RC"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -qi 'has findings' && printf '%s' "$CTX" | grep -qi 'syntax'; then
    ok "syntax error -> surfaced as a finding (not a tool break)"
  else
    fail "syntax error -> not in findings branch: $CTX"
  fi
else
  fail "syntax error -> no additionalContext JSON: $OUT"
fi

# --- Case 4c: unused import preserved (--unfixable F401) but reported --------
# The just-added-import guard: F401 must NOT be auto-deleted (the code using it
# often arrives on the next edit) yet must still surface as a finding.
printf 'import os\n' >"$REPO/imp.py"
OUT=$(run_hook "$REPO/imp.py")
if grep -q 'import os' "$REPO/imp.py"; then
  ok "unused import preserved (not auto-deleted mid-edit)"
else
  fail "unused import was auto-deleted: $(cat "$REPO/imp.py")"
fi
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'F401'; then
  ok "unused import still reported as a finding"
else
  fail "unused import not reported: $OUT"
fi
if [[ "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)" == $'ruff-format: imp.py has findings:\n  1:8: F401 [*] `os` imported but unused' ]]; then
  ok "finding lines drop the path prefix the heading already names"
else
  fail "finding report shape: $OUT"
fi

# --- Case 4c2: an unchanged finding set is sent once --------------------------
# With a data directory, the F401 above is sent on the first edit and not on
# the next; telemetry still records it. A clean run clears the record, so the
# finding is sent again when it returns, and so is it after a SessionStart
# compact or clear resets the records.
DELTA_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
run_delta() {
  run_hook_env "$1" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true CLAUDE_PLUGIN_DATA="$DELTA_DATA" "${@:2}"
}
delta_ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1" 2>/dev/null; }
printf 'import os\n' >"$REPO/delta.py"
D1=$(run_delta "$REPO/delta.py")
TELD="$(mktemp)"
SINKD="$(make_sink "cat >\"$TELD\"")"
D2=$(run_delta "$REPO/delta.py" HOOK_TELEMETRY_SINK="$SINKD")
wait_for_sink "$TELD"
if [[ "$(delta_ctx "$D1")" == *F401* && -z "$D2" ]]; then
  ok "delta: an unchanged finding set is sent once, then nothing"
else
  fail "delta: first='$D1' second='$D2'"
fi
if [[ -s "$TELD" ]] && jq -e '.data.findings | map(test("F401")) | any' "$TELD" >/dev/null 2>&1; then
  ok "delta: telemetry still records the finding the context left out"
else
  fail "delta: telemetry findings: $(cat "$TELD" 2>/dev/null)"
fi
printf '{"source":"compact"}' | env CLAUDE_PLUGIN_DATA="$DELTA_DATA" bash "$HOOK" --reset-digests
D3=$(run_delta "$REPO/delta.py")
if [[ "$(delta_ctx "$D3")" == *F401* ]]; then
  ok "delta: SessionStart compact resets the record, so the set is sent again"
else
  fail "delta: after compact reset: '$D3'"
fi
printf '{"source":"resume"}' | env CLAUDE_PLUGIN_DATA="$DELTA_DATA" bash "$HOOK" --reset-digests
D4=$(run_delta "$REPO/delta.py")
if [[ -z "$D4" ]]; then ok "delta: SessionStart resume keeps the record"; else fail "delta: after resume: '$D4'"; fi
printf 'x = 1\n' >"$REPO/delta.py"
run_delta "$REPO/delta.py" >/dev/null
printf 'import os\n' >"$REPO/delta.py"
D5=$(run_delta "$REPO/delta.py")
if [[ "$(delta_ctx "$D5")" == *F401* ]]; then
  ok "delta: a finding that returns after a clean run is sent again"
else
  fail "delta: after clean run: '$D5'"
fi

# --- Case 4d: target-version-aware syntax error ------------------------------
# Ruff's parser flags syntax newer than the configured Python floor. A match
# statement under target-version py39 must surface as a finding.
REPO_VER="$WORK/version-floor"
new_ruff_repo "$REPO_VER" 'target-version = "py39"'
printf 'match x:\n    case 1:\n        pass\n' >"$REPO_VER/m.py"
OUT=$(run_hook "$REPO_VER/m.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "version-floor syntax -> exit 0 (advisory)"; else fail "version-floor syntax exit $RC"; fi
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -qi 'match.*3\.9\|3\.9.*match\|invalid-syntax'; then
  ok "version-floor syntax -> target-version-aware finding surfaced"
else
  fail "version-floor syntax not flagged: $OUT"
fi

# --- Case 4e: consumer unsafe-fixes = true -> unsafe fix NOT applied ---------
# A consumer config may set unsafe-fixes = true for interactive runs; the
# hook's fix pass passes --no-unsafe-fixes so the unattended edit-time pass
# never applies fixes Ruff labels as possibly not intent-preserving. E712's
# fix (x == True -> x) is such a fix: the comparison must survive and the
# finding surface as advisory instead. The fixture selects E712 rather than
# relying on it being a default rule — Ruff 0.16.0 dropped it from the default
# set, and a case that asserts on one rule's fix safety must name that rule.
REPO_UNSAFE="$WORK/unsafe-fixes"
new_ruff_repo "$REPO_UNSAFE" 'unsafe-fixes = true
lint.select = ["E712"]'
printf 'x = 1\nif x == True:\n    pass\n' >"$REPO_UNSAFE/u.py"
OUT=$(run_hook "$REPO_UNSAFE/u.py")
RC=$?
if [[ $RC -eq 0 ]]; then ok "unsafe-fixes config -> exit 0 (advisory)"; else fail "unsafe-fixes config exit $RC"; fi
if grep -q 'x == True' "$REPO_UNSAFE/u.py"; then
  ok "unsafe fix NOT applied despite unsafe-fixes = true"
else
  fail "unsafe fix applied (intent-changing rewrite): $(cat "$REPO_UNSAFE/u.py")"
fi
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'E712'; then
  ok "unsafe-fixable finding surfaced as advisory instead"
else
  fail "E712 not reported: $OUT"
fi

# --- Case 5: config excludes the edited file -> untouched, no nag ------------
# --force-exclude honors the config's excludes even for an explicitly-passed
# path. An excluded file must be left untouched with no advisory noise.
REPO_EX="$WORK/exclude-config"
new_ruff_repo "$REPO_EX" 'extend-exclude = ["gen"]'
mkdir -p "$REPO_EX/gen"
printf 'x=1\n' >"$REPO_EX/gen/g.py"
BEFORE_EX="$(cat "$REPO_EX/gen/g.py")"
OUT=$(run_hook "$REPO_EX/gen/g.py")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "excluded file -> exit 0, silent (no nag)"; else fail "excluded file not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_EX/gen/g.py")" == "$BEFORE_EX" ]]; then ok "excluded file -> left untouched (respects config exclude)"; else fail "excluded file -> was rewritten"; fi

# --- Case 6: non-matching extension -> exit 0 silently ------------------------
echo "plain text" >"$REPO/notes.txt"
OUT=$(run_hook "$REPO/notes.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-matching ext -> exit 0 silent"; else fail "non-matching ext not skipped (rc=$RC out=$OUT)"; fi

# --- Case 7: kill switch bypasses hook ----------------------------------------
printf 'k=1\n' >"$REPO/kill.py"
BEFORE_K="$(cat "$REPO/kill.py")"
OUT=$(run_hook_env "$REPO/kill.py" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/kill.py")" == "$BEFORE_K" ]]; then ok "kill switch -> file untouched"; else fail "kill switch -> file was modified"; fi

# --- Case 8: no .venv shim -> PATH fallback resolves Ruff ---------------------
# Same real Ruff, reached via PATH (prepended) instead of the venv walk.
REPO_PATH="$WORK/path-fallback"
mkdir -p "$REPO_PATH"
git -C "$REPO_PATH" init -q
printf 'line-length = 88\n' >"$REPO_PATH/ruff.toml"
printf 'p=1\n' >"$REPO_PATH/p.py"
OUT=$(run_hook_env "$REPO_PATH/p.py" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true PATH="$(dirname "$REAL_RUFF"):$PATH")
RC=$?
if [[ $RC -eq 0 ]] && grep -q 'p = 1' "$REPO_PATH/p.py"; then
  ok "PATH fallback -> Ruff resolved and file formatted"
else
  fail "PATH fallback failed (rc=$RC): $(cat "$REPO_PATH/p.py")"
fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ------------------------------
OUT_NS=$(run_hook_env "$REPO/clean.py" -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + lint finding -> envelope status ok with findings -------------
printf 'print(undefined_tel)\n' >"$REPO/tel.py"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel.py" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
wait_for_sink "$TEL"
if [[ -s "$TEL" ]]; then
  ok "telemetry/stub-sink: envelope received"
  if check_envelope "$TEL"; then ok "envelope: matches envelope schema"; else fail "envelope: does not match envelope schema. envelope=$(cat "$TEL")"; fi
  if [[ "$(jq -r '.hook' "$TEL")" == "ruff-format" ]]; then ok "envelope: hook is ruff-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.1" ]]; then ok "envelope: schema_version 1.1"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  # An undefined name is not auto-fixable and the line is already formatted: no bytes moved.
  if [[ "$(jq -r '.data.changed' "$TEL")" == "false" ]]; then ok "envelope: data.changed false (nothing rewritten)"; else fail "envelope: data.changed=$(jq -c '.data.changed' "$TEL")"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + format rewrite -> data.changed true (#3755) ------------------
printf 'x=1\n' >"$REPO/tel-fmt.py"
TELF="$(mktemp)"
SINKF="$(make_sink "cat >\"$TELF\"")"
OUT_F=$(run_hook_env "$REPO/tel-fmt.py" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKF")
wait_for_sink "$TELF"
if [[ -s "$TELF" ]]; then
  if [[ "$(jq -r '.status' "$TELF")" == "ok" ]]; then ok "telemetry/rewrite: status ok"; else fail "telemetry/rewrite: status=$(jq -r '.status' "$TELF")"; fi
  if [[ "$(jq -r '.data.changed' "$TELF")" == "true" ]]; then ok "telemetry/rewrite: data.changed true after ruff format rewrote the file"; else fail "telemetry/rewrite: data.changed=$(jq -c '.data.changed' "$TELF")"; fi
  if [[ "$OUT_F" == *'"systemMessage"'* ]]; then ok "telemetry/rewrite: the disclosure still reaches stdout"; else fail "telemetry/rewrite: disclosure missing from stdout: $OUT_F"; fi
else
  fail "telemetry/rewrite: no envelope written"
fi
rm -f "$TELF"

# --- Stub sink + gate OFF -> status skipped -----------------------------------
printf 's=1\n' >"$REPO_NO/tel2.py"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO_NO/tel2.py" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "skipped" ]]; then ok "telemetry/gate-off: status skipped"; else fail "telemetry/gate-off: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/gate-off: findings empty array"; else fail "telemetry/gate-off: findings not empty"; fi
else
  fail "telemetry/gate-off: no envelope written"
fi
rm -f "$TELS"

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers (no ruff): a repo with a governing Ruff config
# but no binary must produce a visible once-per-session skip notice on both
# channels, silent on the second run. jq removal then exercises the input gate.
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
REPO_NR="$WORK/no-ruff"
mkdir -p "$REPO_NR"
git -C "$REPO_NR" init -q
printf 'line-length = 88\n' >"$REPO_NR/.ruff.toml"
printf 'x=1\n' >"$REPO_NR/app.py"
NR_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
run_nr() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-noruff-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NR/app.py" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$NR_DATA" \
        CLAUDE_PLUGIN_ROOT="${HOOK_DIR%/*}" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true bash "$HOOK"
  )
}
OUT_NR=$(run_nr)
RC_NR=$?
if [[ $RC_NR -eq 0 ]]; then ok "ruff-absent -> exit 0"; else fail "ruff-absent exit $RC_NR"; fi
# The manifest's where, degrade and check reach the model; its install route
# reaches the user only.
if jq -e '(.hookSpecificOutput.additionalContext | startswith("ruff-format: ruff not on the hook PATH or at .venv/bin/ruff. Without ruff,") and contains("/ruff-format:check") and (contains("pip install") | not))
    and (.systemMessage | contains("pip install ruff"))' <<<"$OUT_NR" >/dev/null 2>&1; then
  ok "ruff-absent with governing config -> manifest notice, install route on the user channel only"
else
  fail "ruff-absent: notice missing or malformed: $OUT_NR"
fi
OUT_NR2=$(run_nr)
if [[ -z "$OUT_NR2" ]]; then
  ok "ruff-absent -> second run same session is silent (once-per-session)"
else
  fail "ruff-absent second run not silent: $OUT_NR2"
fi

# jq-absent -> visible once per session and agent notice (input parsing gate).
rm -f "$FAKEBIN/jq"
JQ_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
OUT_NOJQ=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-nojq-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NR/app.py" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
      CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true bash "$HOOK"
)
RC_NOJQ=$?
if [[ $RC_NOJQ -eq 0 && "$OUT_NOJQ" == *'"systemMessage"'* && "$OUT_NOJQ" == *jq* ]]; then
  ok "jq-absent -> exit 0 with visible notice"
else
  fail "jq-absent (rc=$RC_NOJQ out=$OUT_NOJQ)"
fi

# --- Symlinked repo root: the lint target must stay the edited file ----------
# The hook passes Ruff a repo-relative path so diagnostics read cleanly, and it
# computes that path with hook::repo_relative_path_to, which REDACTS to a bare
# basename when the repo-root prefix strip does not match. Reaching one repo
# through a symlink produces exactly that mismatch: file_path keeps the
# symlinked spelling while `git rev-parse --show-toplevel` answers with the
# physical path. A basename resolved against the repo root is a DIFFERENT file
# (here: none), so without the degrade branch Ruff lints the wrong path and the
# real finding disappears from an advisory hook. The file sits one directory
# deep so a same-named file at the root cannot mask the bug.
if ln -s "$WORK/symlink-real" "$WORK/symlink-link" 2>/dev/null; then
  REPO_SL="$WORK/symlink-real"
  new_ruff_repo "$REPO_SL"
  mkdir -p "$REPO_SL/pkg"
  printf 'x = undefined_name_here\n' >"$REPO_SL/pkg/mod.py"
  OUT_SL=$(run_hook "$WORK/symlink-link/pkg/mod.py")
  if [[ "$OUT_SL" == *F821* ]]; then
    ok "symlinked root: the real finding still surfaces (lint target not redacted)"
  else
    fail "symlinked root: F821 lost, hook linted a redacted path: $OUT_SL"
  fi
  if [[ "$OUT_SL" != *E902* ]]; then
    ok "symlinked root: no 'no such file' error from a basename-only target"
  else
    fail "symlinked root: Ruff got a nonexistent target: $OUT_SL"
  fi
  # The redaction itself must still hold on the telemetry side: data.file is
  # the basename, never the absolute path that embeds the developer's username.
  SL_OUT="$WORK/sl-telemetry.json"
  SL_SINK=$(make_sink "cat >\"$SL_OUT\"")
  run_hook_env "$WORK/symlink-link/pkg/mod.py" \
    CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SL_SINK" >/dev/null
  if wait_for_sink "$SL_OUT" && [[ "$(jq -r '.data.file' "$SL_OUT" 2>/dev/null)" == "mod.py" ]]; then
    ok "symlinked root: telemetry data.file stays redacted to the basename"
  else
    fail "symlinked root: data.file was $(jq -r '.data.file' "$SL_OUT" 2>/dev/null)"
  fi
else
  echo "SKIP: symlinks unavailable on this filesystem -- symlinked-root case skipped"
fi

# --- hooks.json: the if rows equal the script's own extension set (#3411) ----
# The if rows are what keep a Write or Edit of any other file from spawning
# this hook: Claude Code evaluates a handler's `if` at match time and drops the
# handler without a spawn (hooks reference, `if`, re-fetched 2026-09-07; the
# installed CLI logs "Skipping hook due to if condition ... not matching"), and
# an Edit(...) rule is the one consulted for Write and NotebookEdit as well.
# The script's own filter stays as defense in depth, so the two sets must be
# IDENTICAL: an if row the script does not handle spawns a process that exits
# at the filter, and an extension the script handles with no if row is a silent
# regression, since the hook then never runs for it.
#
# The script's set is the glob list it hands hook::begin, lifted from that call
# with continuation lines joined the way bash joins them. One declaration
# serves both of the script's gates — the jq-free pre-filter and the re-check
# on the parsed path — so the two cannot disagree with each other and this
# pairing with the manifest is the only one left to check. An extraction that
# finds no call fails loudly below rather than passing on no evidence.
#
# On the manifest side every handler under every event and matcher group is
# read. Two things are pinned separately, since they answer different
# questions. The `if` rows, which paths a handler applies to: the values
# across every handler must be exactly the derived set, one row each, so a
# handler with no if, an if outside the set, a `Write(...)` rule, a duplicate
# row or an unfiltered group under any event fails. The group, which tools
# invoke the handler at all: every group must be PostToolUse with a matcher
# whose alternation is exactly Write and Edit in either order, the two tools
# whose payload carries a file this script formats (the rule validator folds
# Write and NotebookEdit into an Edit(...) rule, but the matcher is the tool
# name regex the harness consults first, and a matcher narrowed to one tool
# is the hook silently never running for the other, which no if row can show).
# The command must be the plugin's own script by either quoting placement,
# with no prefix, suffix or argument. What this does not reach is a
# registration outside hooks/hooks.json.
HOOKS_JSON="$HOOK_DIR/hooks.json"
BEGIN_LINE="$(awk '
  /^hook::begin[[:space:]]/ {
    line = $0
    while (line ~ /\\$/) {
      sub(/[[:space:]]*\\$/, "", line)
      if ((getline nxt) <= 0) break
      sub(/^[[:space:]]+/, "", nxt)
      line = line " " nxt
    }
    print line
    exit
  }' "$HOOK")"
SCRIPT_EXTS="$(printf '%s\n' "$BEGIN_LINE" |
  sed -n 's/^.*[[:space:]]PostToolUse[[:space:]][[:space:]]*//p' |
  tr -d "'\"" | tr ' ' '\n' | grep . | LC_ALL=C sort -u)"
EXPECTED_IF="$(printf '%s\n' "$SCRIPT_EXTS" | sed 's/.*/Edit(&)/' | tr '\n' ' ')"
EXPECTED_IF="${EXPECTED_IF% }"
EXPECTED_COUNT="$(printf '%s\n' "$SCRIPT_EXTS" | grep -c .)"
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" && -n "$BEGIN_LINE" && "$EXPECTED_COUNT" -gt 0 ]]; then
  # The node-notice SessionStart row is filtered out here and pinned fleet-wide by
  # scripts/node-notice-rows.test.sh.
  # The one row outside this gate is the SessionStart prerequisite probe, exec
  # form behind the ruff_format_enabled launcher gate, which is asserted on its
  # own here.
  ALL_HANDLERS="$(jq -c '[.hooks | to_entries[] | .key as $ev | .value[]? | .matcher as $m | .hooks[]? | select((.command // "") | contains("node-notice") | not) | . + {event: $ev, matcher: ($m // "(none)")}]' "$HOOKS_JSON")"
  PROBE_COUNT="$(jq -c --arg checker '${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs' --arg root '${CLAUDE_PLUGIN_ROOT}' '[.[] | select(.event == "SessionStart" and .command == "node" and .args == [$checker, "probe", $root, "--run-if-unset-or-true", "RUFF_FORMAT_ENABLED"])] | length' <<<"$ALL_HANDLERS")"
  HANDLERS="$(jq -c --arg checker '${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs' --arg root '${CLAUDE_PLUGIN_ROOT}' '[.[] | select((.event == "SessionStart" and .command == "node" and .args == [$checker, "probe", $root, "--run-if-unset-or-true", "RUFF_FORMAT_ENABLED"]) | not)]' <<<"$ALL_HANDLERS")"
  if [[ "$PROBE_COUNT" == "1" ]]; then
    ok "hooks.json: one exec-form SessionStart row runs the prerequisites checker's probe behind --run-if-unset-or-true RUFF_FORMAT_ENABLED"
  else
    fail "hooks.json: expected one exec-form SessionStart prerequisites probe row behind --run-if-unset-or-true RUFF_FORMAT_ENABLED, found $PROBE_COUNT"
  fi
  # The SessionStart compact|clear row that resets the findings delta gate.
  # shellcheck disable=SC2016 # the CLAUDE_PLUGIN_ROOT placeholders are literal manifest text
  RESET_SEL='.event == "SessionStart" and .matcher == "compact|clear" and .command == "node" and .args == ["${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs", "${CLAUDE_PLUGIN_ROOT}/hooks/ruff-format.sh", "--reset-digests"]'
  if [[ "$(jq "[.[] | select($RESET_SEL)] | length" <<<"$HANDLERS")" == "1" ]]; then
    ok "hooks.json: one SessionStart compact|clear row runs the script with --reset-digests"
  else
    fail "hooks.json: expected one SessionStart compact|clear --reset-digests row"
  fi
  HANDLERS="$(jq -c "[.[] | select(($RESET_SEL) | not)]" <<<"$HANDLERS")"
  HANDLER_COUNT="$(jq 'length' <<<"$HANDLERS")"
  HANDLER_GROUPS="$(jq -r '[.[] | "\(.event):\(.matcher)"] | unique | join(",")' <<<"$HANDLERS")"
  GROUPS_OFF="$(jq -r '[.[] | select(.event != "PostToolUse" or ((.matcher | split("|") | sort | unique) != ["Edit", "Write"])) | "\(.event):\(.matcher)"] | unique | join(",")' <<<"$HANDLERS")"
  IF_VALUES="$(jq -r '[.[] | (.if // "(none)")] | sort | join(" ")' <<<"$HANDLERS")"
  WRITE_IF="$(jq '[.[] | select(has("if") and (.if | startswith("Write(")))] | length' <<<"$HANDLERS")"
  CMD_OFF="$(jq -r --arg script '${CLAUDE_PLUGIN_ROOT}/hooks/ruff-format.sh' '
    [.[] | select(
      ((.command == "node") and ((.args // []) | index($script)))
      | not) | (.command // "(none)")] | unique | join(",")' <<<"$HANDLERS")"
  if [[ "$HANDLER_COUNT" == "$EXPECTED_COUNT" && "$IF_VALUES" == "$EXPECTED_IF" && "$WRITE_IF" == "0" && -z "$GROUPS_OFF" && -z "$CMD_OFF" ]]; then
    ok "hooks.json: every handler ($HANDLER_GROUPS) is a PostToolUse Write and Edit group running the plugin's script, and the if rows are exactly $EXPECTED_IF, the script's own hook::begin glob list"
  else
    fail "hooks.json launch gate: handlers=$HANDLER_COUNT/$EXPECTED_COUNT groups=$HANDLER_GROUPS groups_off='$GROUPS_OFF' if='$IF_VALUES' expected='$EXPECTED_IF' write_if=$WRITE_IF cmd_off='$CMD_OFF'"
  fi
else
  fail "hooks.json launch-gate assertions need jq, $HOOKS_JSON and a hook::begin glob list in the script (begin='$BEGIN_LINE' globs=(${SCRIPT_EXTS//$'\n'/ }))"
fi

# --- Gitignored path (#4671): neither rewritten nor reported by default ------
# `x=1` would be reformatted and `undefined_name` reported (F821); under an
# ignored directory neither happens, unless ruff_format_lint_gitignored is set.
# Ruff's own respect-gitignore does not reach an explicitly passed path.
REPO_IGN="$WORK/gitignored"
new_ruff_repo "$REPO_IGN"
git -C "$REPO_IGN" config core.excludesFile /dev/null
printf '.work/\n.venv/\n' >"$REPO_IGN/.gitignore"
mkdir -p "$REPO_IGN/.work"
printf 'x=1\nprint(undefined_name)\n' >"$REPO_IGN/.work/scratch.py"
IGN_BEFORE="$(cat "$REPO_IGN/.work/scratch.py")"
OUT=$(run_hook "$REPO_IGN/.work/scratch.py")
if [[ -z "$OUT" ]]; then ok "gitignored: no findings reported"; else fail "gitignored: reported: $OUT"; fi
if [[ "$(cat "$REPO_IGN/.work/scratch.py")" == "$IGN_BEFORE" ]]; then
  ok "gitignored: file not rewritten"
else
  fail "gitignored: file was rewritten: $(cat "$REPO_IGN/.work/scratch.py")"
fi
run_hook_env "$REPO_IGN/.work/scratch.py" CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true \
  CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_LINT_GITIGNORED=true >/dev/null
if grep -q '^x = 1$' "$REPO_IGN/.work/scratch.py"; then
  ok "gitignored + ruff_format_lint_gitignored=true: file formatted"
else
  fail "gitignored + opt-in: not formatted: $(cat "$REPO_IGN/.work/scratch.py")"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
