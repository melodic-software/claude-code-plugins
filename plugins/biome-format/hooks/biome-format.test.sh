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

# Resolve a real Biome binary. node_modules/.bin/biome shims in each fixture
# forward to this. Skip the suite when none is available.
if [[ -n "${BIOME_TEST_BIN:-}" && -x "${BIOME_TEST_BIN}" ]]; then
  REAL_BIOME="${BIOME_TEST_BIN}"
elif command -v biome >/dev/null 2>&1; then
  REAL_BIOME="$(command -v biome)"
else
  echo "SKIP: no Biome binary (set BIOME_TEST_BIN or put biome on PATH) -- biome-format hook tests skipped"
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
  s="$(mktemp -p "$WORK" sink.XXXXXX)"
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
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" \
      | env -u CLAUDE_PROJECT_DIR HOOK_BIOME_FORMAT_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE ...).
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" \
      | env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
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
OUT=$(run_hook_env "$REPO/kill.ts" HOOK_BIOME_FORMAT_ENABLED=false)
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

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ----------------------------
OUT_NS=$(run_hook_env "$REPO/clean.ts" -u HOOK_TELEMETRY_SINK HOOK_BIOME_FORMAT_ENABLED=true)
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
run_hook_env "$REPO/tel.ts" HOOK_BIOME_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + gate OFF -> status skipped ---------------------------------
printf 'const s=1;var t=2\n' >"$REPO_NO/tel2.ts"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO_NO/tel2.ts" HOOK_BIOME_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "skipped" ]]; then ok "telemetry/gate-off: status skipped"; else fail "telemetry/gate-off: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/gate-off: findings empty array"; else fail "telemetry/gate-off: findings not empty"; fi
else
  fail "telemetry/gate-off: no envelope written"
fi
rm -f "$TELS"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
