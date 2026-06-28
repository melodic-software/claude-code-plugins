#!/usr/bin/env bash
# Black-box contract test for bash-lint.sh (the bash-lint plugin hook).
#
# Proves WIRING: the hook fires on *.sh/*.bash, skips otherwise, surfaces
# ShellCheck findings via additionalContext (advisory, exit 0), honors the
# kill switch, gates shfmt formatting on a consumer .editorconfig (present ->
# format, absent -> leave bytes untouched), and emits a schema-valid telemetry
# envelope. No medley-policy prose in the surfaced context.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked as a subprocess from an UNRELATED cwd so any reliance on
# the caller's working directory would surface (the tools are file-anchored, so
# a correct hook needs no cd). shellcheck is required; without it the lint
# branch -- which drives the findings assertions -- cannot fire, so the suite
# skips. shfmt-gated cases skip when shfmt is absent.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/bash-lint.sh"

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

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: shellcheck not on PATH -- bash-lint hook tests skipped"
  exit 0
fi
HAVE_SHFMT=0
if command -v shfmt >/dev/null 2>&1; then
  HAVE_SHFMT=1
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

new_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate);
# this isolates lint/format behavior from path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" \
      | env -u CLAUDE_PROJECT_DIR HOOK_BASH_LINT_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE ...) and an
# optional override of HOOK_BASH_LINT_ENABLED, passed through env.
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" \
      | env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
  )
}

REPO="$WORK/consumer"
new_repo "$REPO"

# --- Case 1: clean .sh -> exit 0, empty stdout ------------------------------
cat >"$REPO/clean.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "clean"
EOF
OUT=$(run_hook "$REPO/clean.sh")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .sh -> exit 0"; else fail "clean .sh exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .sh -> empty stdout"; else fail "clean .sh stdout not empty: $OUT"; fi

# --- Case 2: clean .bash -> exit 0 (glob match) -----------------------------
cat >"$REPO/clean.bash" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "clean bash"
EOF
OUT=$(run_hook "$REPO/clean.bash")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .bash -> exit 0 (glob match)"; else fail "clean .bash exit $RC"; fi

# --- Case 3: SC2154 reference to unassigned var -> advisory (exit 0) ---------
cat >"$REPO/violation.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$undefined_var"
EOF
OUT=$(run_hook "$REPO/violation.sh")
RC=$?
if [[ $RC -eq 0 ]]; then ok "SC2154 violation -> exit 0 (advisory)"; else fail "violation exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q 'SC2154'; then
    ok "violation -> SC2154 in additionalContext"
  else
    fail "violation ctx missing SC2154: $CTX"
  fi
  if printf '%s' "$CTX" | grep -qi 'commit/CI will block\|hard gate\|lefthook'; then
    fail "ctx still carries medley-policy prose: $CTX"
  else
    ok "ctx free of medley-policy prose"
  fi
else
  fail "violation -> no additionalContext JSON: $OUT"
fi

# --- Case 4: non-shell extension -> exit 0 silently -------------------------
echo "not a script" >"$REPO/foo.txt"
OUT=$(run_hook "$REPO/foo.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-shell ext -> exit 0 silent"; else fail "non-shell not skipped (rc=$RC out=$OUT)"; fi

# --- Case 5: kill switch bypasses hook --------------------------------------
OUT=$(run_hook_env "$REPO/violation.sh" HOOK_BASH_LINT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent despite violation"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi

# --- Case 6+7: shfmt gate on .editorconfig ----------------------------------
# Fixture body is deliberately unindented inside an if-block; shfmt would indent
# the inner line. Gate ON (with .editorconfig) -> indented; gate OFF -> untouched.
if [[ $HAVE_SHFMT -eq 1 ]]; then
  # Gate ON: .editorconfig at repo root, file in a subdir (exercises the walk).
  REPO_YES="$WORK/with-config"
  new_repo "$REPO_YES"
  cat >"$REPO_YES/.editorconfig" <<'EOF'
root = true
[*.sh]
indent_style = space
indent_size = 2
EOF
  mkdir -p "$REPO_YES/src"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_YES/src/fmt.sh"
  run_hook "$REPO_YES/src/fmt.sh" >/dev/null
  if grep -q '^  echo hi$' "$REPO_YES/src/fmt.sh"; then
    ok "shfmt gate ON (.editorconfig present) -> file formatted"
  else
    fail "shfmt gate ON -> not formatted: $(cat "$REPO_YES/src/fmt.sh")"
  fi

  # Gate OFF: no .editorconfig anywhere in the repo -> bytes untouched.
  REPO_NO="$WORK/no-config"
  new_repo "$REPO_NO"
  mkdir -p "$REPO_NO/src"
  printf '#!/usr/bin/env bash\nif true; then\necho hi\nfi\n' >"$REPO_NO/src/fmt.sh"
  run_hook "$REPO_NO/src/fmt.sh" >/dev/null
  if grep -q '^echo hi$' "$REPO_NO/src/fmt.sh"; then
    ok "shfmt gate OFF (no .editorconfig) -> file left untouched"
  else
    fail "shfmt gate OFF -> file was reformatted: $(cat "$REPO_NO/src/fmt.sh")"
  fi
else
  echo "  (shfmt absent -- gate cases skipped)"
fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ----------------------------
OUT_NS=$(run_hook_env "$REPO/clean.sh" -u HOOK_TELEMETRY_SINK HOOK_BASH_LINT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + violation -> envelope status ok with findings --------------
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/violation.sh" HOOK_BASH_LINT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "bash-lint" ]]; then ok "envelope: hook is bash-lint"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  if jq -e '.data.findings | any(test("SC2154"))' "$TEL" >/dev/null 2>&1; then ok "envelope: findings name SC2154"; else fail "envelope: findings missing SC2154 ($(jq '.data.findings' "$TEL"))"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + clean file -> status ok, findings [] -----------------------
TELC="$(mktemp)"
SINKC="$(make_sink "cat >\"$TELC\"")"
run_hook_env "$REPO/clean.sh" HOOK_BASH_LINT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKC" >/dev/null
wait_for_sink "$TELC"
if [[ -s "$TELC" ]]; then
  if [[ "$(jq -r '.status' "$TELC")" == "ok" ]]; then ok "telemetry/clean: status ok"; else fail "telemetry/clean: status=$(jq -r '.status' "$TELC")"; fi
  if [[ "$(jq '.data.findings | length' "$TELC")" -eq 0 ]]; then ok "telemetry/clean: findings empty array"; else fail "telemetry/clean: findings not empty ($(jq '.data.findings' "$TELC"))"; fi
else
  fail "telemetry/clean: no envelope written"
fi
rm -f "$TELC"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
