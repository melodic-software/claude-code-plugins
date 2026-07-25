#!/usr/bin/env bash
# Black-box contract test for actionlint-check.sh (the actionlint plugin hook).
#
# Proves WIRING: the hook fires on .github/workflows/*.yml and *.yaml, skips
# other paths, surfaces actionlint findings via additionalContext (advisory,
# exit 0), honors the kill switch, disables the embedded-bash ShellCheck
# integration (-shellcheck=), and emits a schema-valid telemetry envelope. No
# consumer-specific policy prose in the surfaced context.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked as a subprocess from an UNRELATED cwd so any reliance on
# the caller's working directory would surface (the tool is file-anchored, so a
# correct hook needs no cd). actionlint is required to drive the violation
# assertions; without it the suite skips (the hook itself no-ops silently).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/actionlint-check.sh"

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

if ! command -v actionlint >/dev/null 2>&1; then
  echo "SKIP: actionlint not on PATH -- actionlint hook tests skipped"
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

new_repo() {
  local r="$1"
  mkdir -p "$r/.github/workflows"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate);
# this isolates lint behavior from path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true bash "$HOOK"
  )
}

# Same as run_hook but with caller-supplied extra env (NAME=VALUE ...) passed
# through env.
run_hook_env() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR "$@" bash "$HOOK"
  )
}

REPO="$WORK/consumer"
new_repo "$REPO"

# --- Case 1: clean .yml -> exit 0, empty stdout -----------------------------
printf 'name: clean\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "ok"\n' \
  >"$REPO/.github/workflows/clean.yml"
OUT=$(run_hook "$REPO/.github/workflows/clean.yml")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .yml -> exit 0"; else fail "clean .yml exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .yml -> empty stdout"; else fail "clean .yml stdout not empty: $OUT"; fi

# --- Case 2: clean .yaml -> exit 0 (extension coverage) ---------------------
printf 'name: clean2\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "ok"\n' \
  >"$REPO/.github/workflows/clean.yaml"
OUT=$(run_hook "$REPO/.github/workflows/clean.yaml")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "clean .yaml -> exit 0 empty (glob covers .yaml)"; else fail "clean .yaml (rc=$RC out=$OUT)"; fi

# --- Case 3: violation -> advisory (exit 0) + finding in additionalContext ---
# shellcheck disable=SC2016  # literal workflow YAML fixture: ${{ }} must stay unexpanded
printf 'name: bad\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "${{ steps.missing.outputs.x }}"\n' \
  >"$REPO/.github/workflows/violation.yml"
OUT=$(run_hook "$REPO/.github/workflows/violation.yml")
RC=$?
if [[ $RC -eq 0 ]]; then ok "violation -> exit 0 (advisory)"; else fail "violation exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q 'missing'; then
    ok "violation -> diagnostic in additionalContext"
  else
    fail "violation ctx missing diagnostic: $CTX"
  fi
  if printf '%s' "$CTX" | grep -qiE 'commit/CI will block|hard gate|lefthook'; then
    fail "ctx carries consumer-specific policy prose: $CTX"
  else
    ok "ctx free of consumer-specific policy prose"
  fi
else
  fail "violation -> no additionalContext JSON: $OUT"
fi

# --- Case 4: workflow-shaped name OUTSIDE .github/workflows -> exit 0 silent -
printf 'name: anything\n' >"$REPO/foo.yml"
OUT=$(run_hook "$REPO/foo.yml")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-workflow .yml -> exit 0 silent"; else fail "non-workflow .yml not skipped (rc=$RC out=$OUT)"; fi

# --- Case 5: non-yaml extension under workflows -> exit 0 silent -------------
printf 'not yaml\n' >"$REPO/.github/workflows/foo.txt"
OUT=$(run_hook "$REPO/.github/workflows/foo.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok ".txt under workflows -> exit 0 silent"; else fail ".txt not skipped (rc=$RC out=$OUT)"; fi

# --- Case 6: kill switch bypasses hook --------------------------------------
OUT=$(run_hook_env "$REPO/.github/workflows/violation.yml" CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent despite violation"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi

# --- Case 7: large run: block, -shellcheck= disabled -> exit 0 (no SC) -------
# `echo $UNQUOTED` is a ShellCheck-only finding (SC2086) with no native
# actionlint diagnostic. With the embedded ShellCheck integration off, the hook
# exits 0 with no finding. If -shellcheck= regressed AND ShellCheck is present,
# an SC2086 line would surface. When ShellCheck is absent actionlint skips the
# integration regardless, so this never false-fails.
# shellcheck disable=SC2016  # literal workflow YAML fixture: $FOO must stay unexpanded
printf 'name: bigrun\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: |\n          FOO=bar\n          echo $FOO\n          for i in 1 2 3; do echo "line $i"; done\n' \
  >"$REPO/.github/workflows/bigrun.yml"
OUT=$(run_hook "$REPO/.github/workflows/bigrun.yml")
RC=$?
if [[ $RC -eq 0 ]]; then ok "large run: block -> exit 0 (no hang)"; else fail "bigrun exit $RC"; fi
if printf '%s' "$OUT" | grep -q 'SC2086'; then
  fail "shellcheck finding surfaced (SC2086) -- -shellcheck= regressed: $OUT"
else
  ok "no shellcheck finding surfaced (SC2086)"
fi

# --- Case 8: -pyflakes= disabled -> no pyflakes finding (regression) ---------
# `print(undefined_name)` in a `shell: python` run block is a pyflakes-only
# finding ("undefined name") with no native actionlint diagnostic. With the
# integration off, no finding surfaces; when pyflakes is absent actionlint
# skips the integration regardless, so this never false-fails.
printf 'name: pyrun\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: print(undefined_name)\n        shell: python\n' \
  >"$REPO/.github/workflows/pyrun.yml"
OUT=$(run_hook "$REPO/.github/workflows/pyrun.yml")
RC=$?
if [[ $RC -eq 0 ]]; then ok "python run: block -> exit 0"; else fail "pyrun exit $RC"; fi
if printf '%s' "$OUT" | grep -qi 'undefined name'; then
  fail "pyflakes finding surfaced -- -pyflakes= regressed: $OUT"
else
  ok "no pyflakes finding surfaced (-pyflakes= holds)"
fi

# --- Case 9: NO membership guard -- mismatched CLAUDE_PROJECT_DIR still lints
# Regression for the silent-skip bug: the old hook::read_file_path membership
# guard silently exited when the file path did not prefix-match
# CLAUDE_PROJECT_DIR (its concrete trigger: Windows 8.3 short-form paths that
# GNU realpath does not expand). An advisory PostToolUse linter must lint
# regardless of project membership -- prove it with a deliberately unrelated
# CLAUDE_PROJECT_DIR.
OUT=$(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/.github/workflows/violation.yml" |
    env CLAUDE_PROJECT_DIR="$UNRELATED" CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true bash "$HOOK"
)
RC=$?
if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("missing")' >/dev/null 2>&1; then
  ok "mismatched CLAUDE_PROJECT_DIR -> still lints (no membership guard)"
else
  fail "mismatched CLAUDE_PROJECT_DIR silently skipped lint (rc=$RC out=$OUT)"
fi

# --- Case 9b: Windows 8.3 short-form path still lints (where available) ------
# The real-world shape is a SHORT-form prefix (the user/temp dir Claude Code
# hands out) with a long-form tail -- .github/workflows components are 8.3-safe
# and arrive unmangled, so the location filter still matches while the old
# membership guard's realpath comparison did not. cygpath -ms yields the short
# form with forward slashes (JSON-safe). Only meaningful where cygpath exists
# AND the volume generates short names; skip silently otherwise.
if command -v cygpath >/dev/null 2>&1; then
  SHORT_REPO=$(cygpath -ms "$REPO" 2>/dev/null || true)
  SHORT="${SHORT_REPO:+$SHORT_REPO/.github/workflows/violation.yml}"
  if [[ -n "$SHORT" && -f "$SHORT" && "$SHORT_REPO" != "$(cygpath -m "$REPO" 2>/dev/null)" ]]; then
    OUT=$(
      cd "$UNRELATED" || exit 1
      printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$SHORT" |
        env CLAUDE_PROJECT_DIR="$REPO" CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true bash "$HOOK"
    )
    RC=$?
    if [[ $RC -eq 0 ]] && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("missing")' >/dev/null 2>&1; then
      ok "8.3 short-form path -> still lints"
    else
      fail "8.3 short-form path silently skipped (rc=$RC out=$OUT)"
    fi
  else
    echo "note: 8.3 short-name case skipped (no distinct short form on this volume)"
  fi
fi

# --- Case 10: actionlint hard failure -> telemetry status error, never ok ----
# Stub actionlint exits 3 (fatal) -- the lint DID NOT run; the old code read
# empty-output-as-clean. PATH keeps real tools via exec wrappers.
ERRBIN="$(mktemp -d -p "$WORK" errbin.XXXXXX)"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$ERRBIN/$t"
  chmod +x "$ERRBIN/$t"
done
printf '#!/bin/sh\necho "fatal: simulated actionlint failure" >&2\nexit 3\n' >"$ERRBIN/actionlint"
chmod +x "$ERRBIN/actionlint"
ERR_TEL="$(mktemp)"
ERR_SINK="$(make_sink "cat >\"$ERR_TEL\"")"
OUT_ERR=$(
  cd "$UNRELATED" || exit 1
  printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/.github/workflows/clean.yml" |
    env -u CLAUDE_PROJECT_DIR PATH="$ERRBIN" CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true \
      HOOK_TELEMETRY_SINK="$ERR_SINK" bash "$HOOK"
)
RC_ERR=$?
if [[ $RC_ERR -eq 0 && -z "$OUT_ERR" ]]; then
  ok "actionlint hard failure -> exit 0, silent on channels (advisory; sink carries the error)"
else
  fail "hard-failure (rc=$RC_ERR out=$OUT_ERR)"
fi
wait_for_sink "$ERR_TEL"
if [[ -s "$ERR_TEL" ]]; then
  if [[ "$(jq -r '.status' "$ERR_TEL")" == "error" ]]; then
    ok "actionlint hard failure -> telemetry status error (not ok)"
  else
    fail "hard-failure telemetry status=$(jq -r '.status' "$ERR_TEL") (must be error)"
  fi
else
  fail "hard-failure: no telemetry envelope written"
fi
rm -f "$ERR_TEL"

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ----------------------------
OUT_NS=$(run_hook_env "$REPO/.github/workflows/clean.yml" -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + violation -> envelope status ok with findings --------------
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/.github/workflows/violation.yml" CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "actionlint-check" ]]; then ok "envelope: hook is actionlint-check"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
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

# --- Stub sink + clean file -> status ok, findings [] -----------------------
TELC="$(mktemp)"
SINKC="$(make_sink "cat >\"$TELC\"")"
run_hook_env "$REPO/.github/workflows/clean.yml" CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKC" >/dev/null
wait_for_sink "$TELC"
if [[ -s "$TELC" ]]; then
  if [[ "$(jq -r '.status' "$TELC")" == "ok" ]]; then ok "telemetry/clean: status ok"; else fail "telemetry/clean: status=$(jq -r '.status' "$TELC")"; fi
  if [[ "$(jq '.data.findings | length' "$TELC")" -eq 0 ]]; then ok "telemetry/clean: findings empty array"; else fail "telemetry/clean: findings not empty ($(jq '.data.findings' "$TELC"))"; fi
else
  fail "telemetry/clean: no envelope written"
fi
rm -f "$TELC"

# --- actionlint-absent -> exit 0, VISIBLE once-per-session notice, skipped ---
# Shadow actionlint via a fake-bin dir of exec wrappers for every tool the hook
# needs (jq may share a real dir with actionlint, so keeping whole dirs cannot
# isolate the shadow). First run must emit the skip notice on both channels;
# a second run in the same session (same CLAUDE_PLUGIN_DATA + session_id) must
# be silent; telemetry still records status "skipped".
ABSENT_TEL="$(mktemp)"
ABSENT_SINK="$(make_sink "cat >\"$ABSENT_TEL\"")"
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
ABSENT_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
run_absent() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-absent-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/.github/workflows/clean.yml" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$ABSENT_DATA" \
        CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true HOOK_TELEMETRY_SINK="$ABSENT_SINK" bash "$HOOK"
  )
}
OUT_ABS=$(run_absent)
RC_ABS=$?
if [[ $RC_ABS -eq 0 ]]; then ok "actionlint-absent -> exit 0"; else fail "actionlint-absent exit $RC_ABS"; fi
if jq -e '(.systemMessage | contains("actionlint")) and (.hookSpecificOutput.additionalContext | contains("actionlint"))' <<<"$OUT_ABS" >/dev/null 2>&1; then
  ok "actionlint-absent -> visible notice on both channels"
else
  fail "actionlint-absent: notice missing or malformed: $OUT_ABS"
fi
wait_for_sink "$ABSENT_TEL"
if [[ -s "$ABSENT_TEL" ]]; then
  if [[ "$(jq -r '.status' "$ABSENT_TEL")" == "skipped" ]]; then ok "actionlint-absent -> telemetry status skipped"; else fail "actionlint-absent status=$(jq -r '.status' "$ABSENT_TEL")"; fi
else
  fail "actionlint-absent: no telemetry envelope written"
fi
OUT_ABS2=$(run_absent)
RC_ABS2=$?
if [[ $RC_ABS2 -eq 0 && -z "$OUT_ABS2" ]]; then
  ok "actionlint-absent -> second run same session is silent (once-per-session)"
else
  fail "actionlint-absent second run (rc=$RC_ABS2 out=$OUT_ABS2)"
fi
rm -f "$ABSENT_TEL"

# --- jq-absent -> exit 0, VISIBLE once-per-session notice --------------------
# Same fake-bin, minus jq: the hook cannot parse its input at all, so the gate
# must surface the skip instead of silently no-opping on every edit.
rm -f "$FAKEBIN/jq"
JQ_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
run_nojq() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-nojq-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/.github/workflows/clean.yml" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
        CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true bash "$HOOK"
  )
}
OUT_NOJQ=$(run_nojq)
RC_NOJQ=$?
if [[ $RC_NOJQ -eq 0 && "$OUT_NOJQ" == *'"systemMessage"'* && "$OUT_NOJQ" == *jq* ]]; then
  ok "jq-absent -> exit 0 with visible notice"
else
  fail "jq-absent (rc=$RC_NOJQ out=$OUT_NOJQ)"
fi
OUT_NOJQ2=$(run_nojq)
if [[ -z "$OUT_NOJQ2" ]]; then
  ok "jq-absent -> second run same session is silent (once-per-session)"
else
  fail "jq-absent second run not silent: $OUT_NOJQ2"
fi
# Out-of-scope edit (README, not a workflow file) with jq absent -> fully
# silent: the jq-free applicability pre-filter must run before the jq gate.
JQ_DATA2="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
OUT_OOS=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-oos-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/README.md" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA2" \
      CLAUDE_PLUGIN_OPTION_ACTIONLINT_ENABLED=true bash "$HOOK"
)
RC_OOS=$?
if [[ $RC_OOS -eq 0 && -z "$OUT_OOS" ]]; then
  ok "jq-absent + out-of-scope edit -> fully silent (pre-filter before gate)"
else
  fail "jq-absent out-of-scope edit (rc=$RC_OOS out=$OUT_OOS)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
