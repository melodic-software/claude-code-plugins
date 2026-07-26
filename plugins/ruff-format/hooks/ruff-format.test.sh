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

# Resolve a real Ruff binary. .venv/bin/ruff shims in each fixture forward to
# this. Skip the suite when none is available.
if [[ -n "${RUFF_TEST_BIN:-}" && -x "${RUFF_TEST_BIN}" ]]; then
  REAL_RUFF="${RUFF_TEST_BIN}"
elif command -v ruff >/dev/null 2>&1; then
  REAL_RUFF="$(command -v ruff)"
else
  echo "SKIP: no Ruff binary (set RUFF_TEST_BIN or put ruff on PATH) -- ruff-format hook tests skipped"
  exit 0
fi

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# make_sink <body> -> path to an executable single-command stub sink running
# <body> (which reads the envelope on stdin). HOOK_TELEMETRY_SINK must be a
# single executable path, not a command-with-args, so tests point it at a stub.
make_sink() {
  local s
  s="$(mktemp "$WORK/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [tries] -> block until <file> is non-empty (the
# fire-and-forget sink flushed) or the bound elapses, polling in 20ms steps.
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    if [[ -s "$f" ]]; then
      return 0
    fi
    sleep 0.02
  done
  return 1
}

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

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate);
# this isolates lint/format behavior from path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE ...).
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
  )
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
  if printf '%s' "$CTX" | grep -qi 'has Ruff findings' && printf '%s' "$CTX" | grep -qi 'syntax'; then
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
RC=$?
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
# finding surface as advisory instead.
REPO_UNSAFE="$WORK/unsafe-fixes"
new_ruff_repo "$REPO_UNSAFE" 'unsafe-fixes = true'
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
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL" >/dev/null 2>&1; then
      ok "envelope: $field present"
    else
      fail "envelope: $field missing ($(cat "$TEL"))"
    fi
  done
  if [[ "$(jq -r '.hook' "$TEL")" == "ruff-format" ]]; then ok "envelope: hook is ruff-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

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
  [[ -n "$real_t" ]] || continue
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
        CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED=true bash "$HOOK"
  )
}
OUT_NR=$(run_nr)
RC_NR=$?
if [[ $RC_NR -eq 0 ]]; then ok "ruff-absent -> exit 0"; else fail "ruff-absent exit $RC_NR"; fi
if jq -e '(.systemMessage | contains("ruff")) and (.hookSpecificOutput.additionalContext | contains("Ruff config"))' <<<"$OUT_NR" >/dev/null 2>&1; then
  ok "ruff-absent with governing config -> visible notice on both channels"
else
  fail "ruff-absent: notice missing or malformed: $OUT_NR"
fi
OUT_NR2=$(run_nr)
if [[ -z "$OUT_NR2" ]]; then
  ok "ruff-absent -> second run same session is silent (once-per-session)"
else
  fail "ruff-absent second run not silent: $OUT_NR2"
fi

# jq-absent -> visible once-per-session notice (input parsing gate).
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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
