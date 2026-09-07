#!/usr/bin/env bash
# Black-box contract test for biome-format.sh (the biome-format plugin hook).
#
# Proves WIRING: the hook fires on JS/TS/JSX/JSON, skips otherwise, applies
# Biome's --write fixes, surfaces residual findings via additionalContext
# (advisory, exit 0), honors the kill switch, gates on a consumer biome.json
# (present -> run, absent -> leave bytes untouched), respects the config's own
# ignore rules for an explicitly-edited file (no nag), and emits a schema-valid
# telemetry envelope. No medley-policy prose in the surfaced context.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# Each repo gets a node_modules/.bin/biome shim that forwards to a real Biome,
# so the hook's node_modules resolution path is exercised. The hook is invoked
# from an UNRELATED cwd so any reliance on the caller's working directory would
# surface (Biome discovers config from the cwd the hook cd's to, not the caller).
#
# Requires a real Biome binary: $BIOME_TEST_BIN if set, else `biome` on PATH.
# Without one the behavioral assertions cannot run, so the suite skips.

set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/biome-format.sh"

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

# --- Missing-binary visibility (dim-9 doctrine) ------------------------------
# Needs NO real Biome, so it runs even when the rest of the suite skips: a repo
# with a governing biome.json but no binary anywhere must produce a visible
# once-per-session skip notice on both channels, silent on the second run.
NB_WORK="$(mktemp -d)"
NB_FAKEBIN="$NB_WORK/fakebin"
mkdir -p "$NB_FAKEBIN"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$NB_FAKEBIN/$t"
  chmod +x "$NB_FAKEBIN/$t"
done
NB_REPO="$NB_WORK/repo"
mkdir -p "$NB_REPO"
git -C "$NB_REPO" init -q
printf '{}\n' >"$NB_REPO/biome.json"
printf 'const x = 1\n' >"$NB_REPO/app.js"
NB_DATA="$NB_WORK/plugdata"
mkdir -p "$NB_DATA"
run_nb() {
  printf '{"session_id":"test-nobiome-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$NB_REPO/app.js" |
    env -u CLAUDE_PROJECT_DIR PATH="$NB_FAKEBIN" CLAUDE_PLUGIN_DATA="$NB_DATA" \
      CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true bash "$HOOK"
}
OUT_NB=$(run_nb)
RC_NB=$?
if [[ $RC_NB -eq 0 ]]; then ok "biome-absent -> exit 0"; else fail "biome-absent exit $RC_NB"; fi
if jq -e '(.systemMessage | contains("biome")) and (.hookSpecificOutput.additionalContext | contains("Biome config"))' <<<"$OUT_NB" >/dev/null 2>&1; then
  ok "biome-absent with governing config -> visible notice on both channels"
else
  fail "biome-absent: notice missing or malformed: $OUT_NB"
fi
OUT_NB2=$(run_nb)
if [[ -z "$OUT_NB2" ]]; then
  ok "biome-absent -> second run same session is silent (once-per-session)"
else
  fail "biome-absent second run not silent: $OUT_NB2"
fi
rm -rf "$NB_WORK"

# Resolve a real Biome binary. node_modules/.bin/biome shims in each fixture
# forward to this. Skip the suite when none is available.
if [[ -n "${BIOME_TEST_BIN:-}" && -x "${BIOME_TEST_BIN}" ]]; then
  REAL_BIOME="${BIOME_TEST_BIN}"
elif command -v biome >/dev/null 2>&1; then
  REAL_BIOME="$(command -v biome)"
else
  echo "SKIP: no Biome binary (set BIOME_TEST_BIN or put biome on PATH) -- remaining biome-format hook tests skipped"
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
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

# new_biome_repo <dir> [config_body] -> init a git repo with a node_modules
# biome shim and (unless config_body is the literal NO_CONFIG) a biome.json.
new_biome_repo() {
  local r="$1" cfg="${2:-}"
  mkdir -p "$r/node_modules/.bin"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  {
    printf '#!/usr/bin/env bash\n'
    printf 'exec "%s" "$@"\n' "$REAL_BIOME"
  } >"$r/node_modules/.bin/biome"
  chmod +x "$r/node_modules/.bin/biome"
  if [[ "$cfg" != "NO_CONFIG" ]]; then
    if [[ -n "$cfg" ]]; then
      printf '%s\n' "$cfg" >"$r/biome.json"
    else
      printf '{}\n' >"$r/biome.json"
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
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true bash "$HOOK"
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

# --- Case 1: opt-in gate OFF (no biome.json) -> file left untouched ----------
# The whole conservative opt-in: a repo with Biome installed but NO config must
# not have its files rewritten to Biome's built-in defaults.
REPO_NO="$WORK/no-config"
new_biome_repo "$REPO_NO" NO_CONFIG
printf 'const x=1;var y=2\n' >"$REPO_NO/nofmt.ts"
BEFORE_NO="$(cat "$REPO_NO/nofmt.ts")"
OUT=$(run_hook "$REPO_NO/nofmt.ts")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "gate OFF (no biome.json) -> exit 0, silent"; else fail "gate OFF not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_NO/nofmt.ts")" == "$BEFORE_NO" ]]; then ok "gate OFF -> file left untouched"; else fail "gate OFF -> file was rewritten"; fi

# --- Case 1b: hidden .biome.json alone does NOT opt in ----------------------
# .biome.json/.biome.jsonc are only loaded by Biome >= 2.4, so the gate must not
# fire on them — otherwise an older Biome would reformat with built-in defaults.
REPO_DOT="$WORK/dotted-only"
new_biome_repo "$REPO_DOT" NO_CONFIG
printf '{}\n' >"$REPO_DOT/.biome.json"
printf 'const x=1;var y=2\n' >"$REPO_DOT/dot.ts"
BEFORE_DOT="$(cat "$REPO_DOT/dot.ts")"
OUT=$(run_hook "$REPO_DOT/dot.ts")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "hidden .biome.json only -> exit 0, silent (no opt-in)"; else fail "hidden config opted in (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_DOT/dot.ts")" == "$BEFORE_DOT" ]]; then ok "hidden .biome.json only -> file left untouched"; else fail "hidden config -> file was rewritten"; fi

# --- Case 2: gate ON + clean file -> exit 0, empty stdout -------------------
REPO="$WORK/consumer"
new_biome_repo "$REPO"
printf 'const x = 1;\nexport { x };\n' >"$REPO/clean.ts"
# Stabilize against Biome's canonical layout so a second hook pass is a true no-op.
(cd "$REPO" && "$REAL_BIOME" check --write clean.ts) >/dev/null 2>&1 || true
OUT=$(run_hook "$REPO/clean.ts")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .ts -> exit 0"; else fail "clean .ts exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .ts -> empty stdout"; else fail "clean .ts stdout not empty: $OUT"; fi

# --- Case 3: gate ON + bad formatting (no lint error) -> file formatted ------
mkdir -p "$REPO/src"
printf 'const a = 1;export {a}\n' >"$REPO/src/fmt.ts"
OUT=$(run_hook "$REPO/src/fmt.ts")
RC=$?
if [[ $RC -eq 0 ]]; then ok "format case -> exit 0 (advisory)"; else fail "format case exit $RC"; fi
if grep -q 'export { a };' "$REPO/src/fmt.ts"; then
  ok "gate ON (subdir file) -> Biome reformatted the file"
else
  fail "gate ON -> file not formatted: $(cat "$REPO/src/fmt.ts")"
fi
if printf '%s' "$OUT" | grep -q 'biome-format: auto-fixed and/or reformatted'; then
  ok "format case -> user-channel mutation disclosure"
else
  fail "format case -> missing systemMessage disclosure: $OUT"
fi

# --- Case 4: gate ON + lint finding (unused var) -> advisory context ---------
# File in a subdir (config at repo root) exercises both the walk and the
# CONFIG_DIR-relative path passed to Biome.
mkdir -p "$REPO/lib"
printf 'const unusedVar = 1;\n' >"$REPO/lib/lint.ts"
OUT=$(run_hook "$REPO/lib/lint.ts")
RC=$?
if [[ $RC -eq 0 ]]; then ok "lint finding -> exit 0 (advisory)"; else fail "lint finding exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -qi 'noUnusedVariables\|unused'; then
    ok "lint finding -> surfaced in additionalContext"
  else
    fail "lint ctx missing the finding: $CTX"
  fi
  # Path is repo-relative (lib/lint.ts or lib\lint.ts), not an absolute,
  # URL-encoded one (C%3A...). Accept either separator for cross-platform parity.
  if printf '%s' "$CTX" | grep -qiE 'lib[/\\]lint\.ts' && ! printf '%s' "$CTX" | grep -qi 'C%3A\|%3A'; then
    ok "lint finding -> path is clean and repo-relative"
  else
    fail "lint finding -> path not clean/relative: $CTX"
  fi
  if printf '%s' "$CTX" | grep -qi 'commit/CI will block\|hard gate\|lefthook'; then
    fail "ctx still carries medley-policy prose: $CTX"
  else
    ok "ctx free of medley-policy prose"
  fi
else
  fail "lint finding -> no additionalContext JSON: $OUT"
fi

# --- Case 4a: rewrite AND findings -> ONE JSON document, both channels -------
# The #3406 regression: --write reformats the badly-spaced file AND the unused
# variable survives as a residual finding, so the run carries a rewrite
# disclosure and findings together. They must compose into a single JSON
# document — a second printed object is an invalid hook response and either
# message can be lost.
printf 'const unusedVar=1;\n' >"$REPO/lib/both.ts"
OUT=$(run_hook "$REPO/lib/both.ts")
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
  if printf '%s' "$CTX" | grep -qi 'unused' && printf '%s' "$MSG" | grep -qi 'reformatted'; then
    ok "rewrite+findings -> both channels carried in the one document"
  else
    fail "rewrite+findings -> channels malformed (ctx=$CTX msg=$MSG)"
  fi
else
  fail "rewrite+findings -> a channel is missing: $OUT"
fi

# --- Case 4b: mid-edit syntax error -> surfaced as a finding, not a break ----
# The dominant on-edit trigger: the file does not parse yet. Biome's github
# reporter emits ::error title=parse lines, so it must land in the findings
# branch (advisory, exit 0), not be mislabeled as a tool break.
printf 'const = ;\n' >"$REPO/syntax.ts"
OUT=$(run_hook "$REPO/syntax.ts")
RC=$?
if [[ $RC -eq 0 ]]; then ok "syntax error -> exit 0 (advisory)"; else fail "syntax error exit $RC"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -qi 'has Biome findings' && printf '%s' "$CTX" | grep -qi 'parse\|expected'; then
    ok "syntax error -> surfaced as a finding (not a tool break)"
  else
    fail "syntax error -> not in findings branch: $CTX"
  fi
else
  fail "syntax error -> no additionalContext JSON: $OUT"
fi

# --- Case 5: gate ON + JSON needing format -> file formatted (in-scope) ------
printf '{"b":2,"a":1}\n' >"$REPO/data.json"
OUT=$(run_hook "$REPO/data.json")
RC=$?
if [[ $RC -eq 0 ]]; then ok "JSON case -> exit 0"; else fail "JSON case exit $RC"; fi
if grep -q '"b": 2' "$REPO/data.json"; then
  ok "JSON file formatted by Biome"
else
  fail "JSON not formatted: $(cat "$REPO/data.json")"
fi

# --- Case 6: non-matching extension -> exit 0 silently ----------------------
echo "plain text" >"$REPO/notes.txt"
OUT=$(run_hook "$REPO/notes.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-matching ext -> exit 0 silent"; else fail "non-matching ext not skipped (rc=$RC out=$OUT)"; fi

# --- Case 7: kill switch bypasses hook --------------------------------------
printf 'const k=1;var j=2\n' >"$REPO/kill.ts"
BEFORE_K="$(cat "$REPO/kill.ts")"
OUT=$(run_hook_env "$REPO/kill.ts" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/kill.ts")" == "$BEFORE_K" ]]; then ok "kill switch -> file untouched"; else fail "kill switch -> file was modified"; fi

# --- Case 8: config ignores the edited file -> untouched, no nag ------------
# Biome 2.x respects files.includes ignores even for an explicitly-passed path.
# The hook must treat "provided but ignored" as a silent skip, not a tool break.
REPO_IGN="$WORK/ignore-config"
new_biome_repo "$REPO_IGN" '{ "files": { "includes": ["**", "!**/generated/**"] } }'
mkdir -p "$REPO_IGN/generated"
printf 'const z=1;var w=2\n' >"$REPO_IGN/generated/gen.ts"
BEFORE_IGN="$(cat "$REPO_IGN/generated/gen.ts")"
OUT=$(run_hook "$REPO_IGN/generated/gen.ts")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "ignored file -> exit 0, silent (no nag)"; else fail "ignored file not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_IGN/generated/gen.ts")" == "$BEFORE_IGN" ]]; then ok "ignored file -> left untouched (respects config ignore)"; else fail "ignored file -> was rewritten"; fi

# --- Case 9: BIOME_CONFIG_PATH override does not hijack the repo config -------
# Biome reads BIOME_CONFIG_PATH as a config-path override; the hook unsets it so
# the gated repo config stays authoritative. Repo config formats single-quoted;
# an external config formats double-quoted. With BIOME_CONFIG_PATH pointing at
# the external config, the result must still be single-quoted (repo config wins).
REPO_ENV="$WORK/env-override"
new_biome_repo "$REPO_ENV" '{ "javascript": { "formatter": { "quoteStyle": "single" } } }'
EXT_CFG="$WORK/external-cfg"
mkdir -p "$EXT_CFG"
printf '%s\n' '{ "javascript": { "formatter": { "quoteStyle": "double" } } }' >"$EXT_CFG/biome.json"
printf 'const s = "hi";\nexport { s };\n' >"$REPO_ENV/q.ts"
run_hook_env "$REPO_ENV/q.ts" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true BIOME_CONFIG_PATH="$EXT_CFG" >/dev/null
if grep -q "const s = 'hi';" "$REPO_ENV/q.ts"; then
  ok "BIOME_CONFIG_PATH override neutralized -> repo config authoritative"
else
  fail "BIOME_CONFIG_PATH hijacked the config: $(cat "$REPO_ENV/q.ts")"
fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ----------------------------
OUT_NS=$(run_hook_env "$REPO/clean.ts" -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + lint finding -> envelope status ok with findings -----------
printf 'const unusedTel = 1;\n' >"$REPO/tel.ts"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel.ts" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "biome-format" ]]; then ok "envelope: hook is biome-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.1" ]]; then ok "envelope: schema_version 1.1"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  # An unused binding is a finding, not a fix, and the line is already formatted: no bytes moved.
  if [[ "$(jq -r '.data.changed' "$TEL")" == "false" ]]; then ok "envelope: data.changed false (nothing rewritten)"; else fail "envelope: data.changed=$(jq -c '.data.changed' "$TEL")"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + format rewrite -> data.changed true (#3755) ----------------
# Exported, so no unused-binding finding; the missing spaces and semicolon are
# what Biome's formatter rewrites.
printf 'export const telFmt=1\n' >"$REPO/tel-fmt.ts"
TELF="$(mktemp)"
SINKF="$(make_sink "cat >\"$TELF\"")"
OUT_F=$(run_hook_env "$REPO/tel-fmt.ts" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKF")
wait_for_sink "$TELF"
if [[ -s "$TELF" ]]; then
  if [[ "$(jq -r '.data.changed' "$TELF")" == "true" ]]; then ok "telemetry/rewrite: data.changed true after Biome reformatted the file"; else fail "telemetry/rewrite: data.changed=$(jq -c '.data.changed' "$TELF") status=$(jq -r '.status' "$TELF")"; fi
  if [[ "$OUT_F" == *'"systemMessage"'* ]]; then ok "telemetry/rewrite: the disclosure still reaches stdout"; else fail "telemetry/rewrite: disclosure missing from stdout: $OUT_F"; fi
else
  fail "telemetry/rewrite: no envelope written"
fi
rm -f "$TELF"

# --- Stub sink + gate OFF -> status skipped ---------------------------------
printf 'const s=1;var t=2\n' >"$REPO_NO/tel2.ts"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO_NO/tel2.ts" CLAUDE_PLUGIN_OPTION_BIOME_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "skipped" ]]; then ok "telemetry/gate-off: status skipped"; else fail "telemetry/gate-off: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/gate-off: findings empty array"; else fail "telemetry/gate-off: findings not empty"; fi
else
  fail "telemetry/gate-off: no envelope written"
fi
rm -f "$TELS"

# --- hooks.json: the if rows equal the script's own extension set (#3411) ----
# The if rows are what keep a Write or Edit of any other file from spawning
# this hook: Claude Code evaluates a handler's `if` at match time and drops the
# handler without a spawn (hooks reference, `if`, re-fetched 2026-09-07; the
# installed CLI logs "Skipping hook due to if condition ... not matching"), and
# an Edit(...) rule is the one consulted for Write and NotebookEdit as well.
# The script's own case filter stays as defense in depth, so the two sets must
# be IDENTICAL: an if row the script does not handle spawns a process that
# exits at the case, and an extension the script handles with no if row is a
# silent regression, since the hook then never runs for it.
#
# The expected set is every pattern of every arm in the script's whole
# `case "$RAW_FILE" ... esac` block except the bare `*` catch-all, so an arm
# added anywhere in the block counts. The block is read the way bash reads it:
# a backslash continuation joins lines with nothing in between (so `;\` and a
# following `;` is one `;;`), a comment after `in` or on any arm is dropped, a
# one-line `case ... esac` is one block, `in` on the line after the `case`
# word opens the block all the same, and every arm terminator bash has
# (`;;`, the `;&` fall-through and the `;;&` continue-matching form) ends an
# arm, so the patterns of an arm reached only by fall-through count too. What
# the parser does not read is an arm's body, so a pattern in any arm, even one
# after `*)` that can never match, counts as handled and must have its row.
# The script's `case "$FILE"` re-check after path normalization (the duplicate
# #3408 owns folding) is read the same way, and every such gate must yield the
# same set, so an exclusion added to either gate fails here instead of sitting
# unread; a script with one gate left passes as it is.
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
SCRIPT_GATES="$(awk '
  function flush(   n, i, m, j, p, pats, arms, alts) {
    inblock = 0
    print nblocks "\t"
    gsub(/;;&/, "\n", block)
    gsub(/;;/, "\n", block)
    gsub(/;&/, "\n", block)
    n = split(block, arms, "\n")
    for (i = 1; i <= n; i++) {
      if (index(arms[i], ")") == 0) continue
      pats = substr(arms[i], 1, index(arms[i], ")") - 1)
      sub(/^[[:space:]]*\(/, "", pats)
      m = split(pats, alts, "|")
      for (j = 1; j <= m; j++) {
        p = alts[j]
        gsub(/[[:space:]]+/, "", p)
        if (p != "" && p != "*") print nblocks "\t" p
      }
    }
  }
  !inblock && !pending && $0 ~ /^case "[$](RAW_FILE|FILE)"[[:space:]]*(#.*)?$/ {
    pending = 1
    next
  }
  pending && match($0, /^[[:space:]]*in([[:space:]]|$)/) {
    pending = 0
    inblock = 1
    nblocks++
    block = ""
    sep = ""
    $0 = substr($0, RLENGTH + 1)
  }
  !inblock && match($0, /^case "[$](RAW_FILE|FILE)" in([[:space:]]|$)/) {
    inblock = 1
    nblocks++
    block = ""
    sep = ""
    $0 = substr($0, RLENGTH + 1)
  }
  inblock {
    sub(/#.*/, "")
    if ($0 ~ /^[[:space:]]*esac([[:space:]]|$)/) {
      flush()
      next
    }
    if (match($0, /[[:space:]]esac([[:space:]]|$)/)) {
      block = block sep substr($0, 1, RSTART - 1)
      flush()
      next
    }
    if (sub(/\\$/, "")) {
      block = block sep $0
      sep = ""
    } else {
      block = block sep $0
      sep = " "
    }
  }' "$HOOK")"
CASE_BLOCKS="$(printf '%s\n' "$SCRIPT_GATES" | cut -f1 | LC_ALL=C sort -u | grep -c .)"
SCRIPT_EXTS="$(printf '%s\n' "$SCRIPT_GATES" | awk -F'\t' '$1 == 1 && $2 != "" { print $2 }' | LC_ALL=C sort -u)"
GATES_OFF=""
for ((g = 2; g <= CASE_BLOCKS; g++)); do
  GATE_EXTS="$(printf '%s\n' "$SCRIPT_GATES" | awk -F'\t' -v g="$g" '$1 == g && $2 != "" { print $2 }' | LC_ALL=C sort -u)"
  [[ "$GATE_EXTS" == "$SCRIPT_EXTS" ]] || GATES_OFF+=" gate$g=(${GATE_EXTS//$'\n'/ })"
done
EXPECTED_IF="$(printf '%s\n' "$SCRIPT_EXTS" | sed 's/.*/Edit(&)/' | tr '\n' ' ')"
EXPECTED_IF="${EXPECTED_IF% }"
EXPECTED_COUNT="$(printf '%s\n' "$SCRIPT_EXTS" | grep -c .)"
if command -v jq >/dev/null 2>&1 && [[ -f "$HOOKS_JSON" && "$CASE_BLOCKS" -ge 1 && -z "$GATES_OFF" && "$EXPECTED_COUNT" -gt 0 ]]; then
  HANDLERS="$(jq -c '[.hooks | to_entries[] | .key as $ev | .value[]? | .matcher as $m | .hooks[]? | . + {event: $ev, matcher: ($m // "(none)")}]' "$HOOKS_JSON")"
  HANDLER_COUNT="$(jq 'length' <<<"$HANDLERS")"
  HANDLER_GROUPS="$(jq -r '[.[] | "\(.event):\(.matcher)"] | unique | join(",")' <<<"$HANDLERS")"
  GROUPS_OFF="$(jq -r '[.[] | select(.event != "PostToolUse" or ((.matcher | split("|") | sort | unique) != ["Edit", "Write"])) | "\(.event):\(.matcher)"] | unique | join(",")' <<<"$HANDLERS")"
  IF_VALUES="$(jq -r '[.[] | (.if // "(none)")] | sort | join(" ")' <<<"$HANDLERS")"
  WRITE_IF="$(jq '[.[] | select(has("if") and (.if | startswith("Write(")))] | length' <<<"$HANDLERS")"
  CMD_OFF="$(jq -r '[.[] | (.command // "(none)") | select(test("^(\"[$][{]?CLAUDE_PLUGIN_ROOT[}]?\"/hooks/biome-format[.]sh|\"[$][{]?CLAUDE_PLUGIN_ROOT[}]?/hooks/biome-format[.]sh\")$") | not)] | unique | join(",")' <<<"$HANDLERS")"
  if [[ "$HANDLER_COUNT" == "$EXPECTED_COUNT" && "$IF_VALUES" == "$EXPECTED_IF" && "$WRITE_IF" == "0" && -z "$GROUPS_OFF" && -z "$CMD_OFF" ]]; then
    ok "hooks.json: every handler ($HANDLER_GROUPS) is a PostToolUse Write and Edit group running the plugin's script, and the if rows are exactly $EXPECTED_IF, the script's own extension set ($CASE_BLOCKS case gates agree)"
  else
    fail "hooks.json launch gate: handlers=$HANDLER_COUNT/$EXPECTED_COUNT groups=$HANDLER_GROUPS groups_off='$GROUPS_OFF' if='$IF_VALUES' expected='$EXPECTED_IF' write_if=$WRITE_IF cmd_off='$CMD_OFF'"
  fi
else
  fail "hooks.json launch-gate assertions need jq, $HOOKS_JSON and agreeing case \"\$RAW_FILE\" / \"\$FILE\" gates in the script (gates=$CASE_BLOCKS gate1=(${SCRIPT_EXTS//$'\n'/ }) disagreeing:${GATES_OFF:- none})"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
