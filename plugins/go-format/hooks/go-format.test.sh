#!/usr/bin/env bash
# Black-box contract test for go-format.sh (the go-format plugin hook).
#
# Proves WIRING: the hook fires ONLY on *.go files, runs gofmt UNCONDITIONALLY
# (gofmt has no configuration surface, so there is no opt-in gate to test),
# reformats in place, leaves a syntax-error file byte-for-byte untouched while
# surfacing the diagnostic via additionalContext, honors the kill switch, and
# emits a schema-valid telemetry envelope.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked from an UNRELATED cwd so any reliance on the caller's
# own working directory would surface.
#
# Requires a real gofmt binary: $GOFMT_TEST_BIN if set, else `gofmt` on PATH.
# Without one the behavioral assertions cannot run, so the suite skips.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/go-format.sh"

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

# Resolve a real gofmt binary. Skip the suite when none is available.
if [[ -n "${GOFMT_TEST_BIN:-}" && -x "${GOFMT_TEST_BIN}" ]]; then
  REAL_GOFMT="${GOFMT_TEST_BIN}"
elif command -v gofmt >/dev/null 2>&1; then
  REAL_GOFMT="$(command -v gofmt)"
else
  echo "SKIP: no gofmt binary (set GOFMT_TEST_BIN or put gofmt on PATH) -- go-format hook tests skipped"
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

# new_go_repo <dir> -> init a git repo (go-format never reads a consumer
# config; gofmt has none — so fixtures need no per-repo config file).
new_go_repo() {
  local r="$1"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate).
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true PATH="$(dirname "$REAL_GOFMT"):$PATH" bash "$HOOK"
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

REPO="$WORK/consumer"
new_go_repo "$REPO"

# --- Case 1: non-.go file -> hook never fires (extension pre-filter) --------
printf 'package  main\n' >"$REPO/notes.txt"
BEFORE_NG="$(cat "$REPO/notes.txt")"
OUT=$(run_hook "$REPO/notes.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "non-.go file -> exit 0, silent"; else fail "non-.go file not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/notes.txt")" == "$BEFORE_NG" ]]; then ok "non-.go file -> left untouched"; else fail "non-.go file -> was rewritten"; fi

# --- Case 2: no config anywhere -> hook still formats unconditionally -------
# gofmt has no configuration surface — there is one canonical Go style — so
# the hook must never gate on a consumer config existing.
printf 'package main\n\nfunc main(){\nx:=1\n_=x\n}\n' >"$REPO/messy.go"
OUT=$(run_hook "$REPO/messy.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "unformatted .go file -> exit 0 (advisory)"; else fail "unformatted .go file exit $RC"; fi
if grep -q 'func main() {' "$REPO/messy.go" && grep -q '	x := 1' "$REPO/messy.go"; then
  ok "unformatted .go file -> gofmt reformatted in place unconditionally"
else
  fail "unformatted .go file -> not reformatted: $(cat "$REPO/messy.go")"
fi

# --- Case 3: already-clean file -> exit 0, empty stdout, unchanged ----------
printf 'package main\n\nfunc main() {\n}\n' >"$REPO/clean.go"
BEFORE_CLEAN="$(cat "$REPO/clean.go")"
OUT=$(run_hook "$REPO/clean.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean .go file -> exit 0"; else fail "clean .go file exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean .go file -> empty stdout"; else fail "clean .go file stdout not empty: $OUT"; fi
if [[ "$(cat "$REPO/clean.go")" == "$BEFORE_CLEAN" ]]; then ok "clean .go file -> byte-identical (idempotent)"; else fail "clean .go file -> was rewritten"; fi

# --- Case 4: syntax error -> file left untouched, diagnostic surfaced -------
# gofmt parses before writing: on a syntax error it writes nothing. This
# proves the hook never corrupts a file mid-edit and reports the diagnostic
# as an advisory finding rather than silently discarding it.
mkdir -p "$REPO/src"
printf 'package main\n\nfunc main( {\n\tx := 1\n}\n' >"$REPO/src/bad.go"
BEFORE_BAD="$(cat "$REPO/src/bad.go")"
OUT=$(run_hook "$REPO/src/bad.go")
RC=$?
if [[ $RC -eq 0 ]]; then ok "syntax error -> exit 0 (advisory)"; else fail "syntax error exit $RC (must be advisory)"; fi
if [[ "$(cat "$REPO/src/bad.go")" == "$BEFORE_BAD" ]]; then
  ok "syntax error -> file left byte-for-byte untouched"
else
  fail "syntax error -> file was modified: $(cat "$REPO/src/bad.go")"
fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q "bad.go"; then
    ok "syntax error -> surfaced in additionalContext"
  else
    fail "syntax error ctx missing the file: $CTX"
  fi
else
  fail "syntax error -> no additionalContext JSON: $OUT"
fi

# --- Case 5: kill switch bypasses hook ---------------------------------------
printf 'package main\n\nfunc main(){\nx:=1\n_=x\n}\n' >"$REPO/kill.go"
BEFORE_K="$(cat "$REPO/kill.go")"
OUT=$(run_hook_env "$REPO/kill.go" PATH="$(dirname "$REAL_GOFMT"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/kill.go")" == "$BEFORE_K" ]]; then ok "kill switch -> file untouched"; else fail "kill switch -> file was modified"; fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ------------------------------
printf 'package main\n\nfunc main() {\n}\n' >"$REPO/tel-clean.go"
OUT_NS=$(run_hook_env "$REPO/tel-clean.go" -u HOOK_TELEMETRY_SINK PATH="$(dirname "$REAL_GOFMT"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + syntax error -> envelope status ok with findings -----------
printf 'package main\n\nfunc main( {\n\tx := 1\n}\n' >"$REPO/tel.go"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel.go" PATH="$(dirname "$REAL_GOFMT"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "go-format" ]]; then ok "envelope: hook is go-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  if jq -e '.data.findings[0] | has("line") and has("col") and has("message")' "$TEL" >/dev/null 2>&1; then
    ok "envelope: findings[0] has line/col/message"
  else
    fail "envelope: findings[0] malformed: $(jq -c '.data.findings[0]' "$TEL")"
  fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
  if ! printf '%s' "$OUT" | grep -q schema_version 2>/dev/null; then ok "envelope: never leaked into hook's own stdout"; else fail "envelope leaked into stdout"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + already-formatted file -> status ok, no findings -----------
printf 'package main\n\nfunc main() {\n}\n' >"$REPO/tel2.go"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO/tel2.go" PATH="$(dirname "$REAL_GOFMT"):$PATH" CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "ok" ]]; then ok "telemetry/clean-file: status ok (unconditional run)"; else fail "telemetry/clean-file: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/clean-file: findings empty array"; else fail "telemetry/clean-file: findings not empty"; fi
else
  fail "telemetry/clean-file: no envelope written"
fi
rm -f "$TELS"

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers (no gofmt): with no 'gofmt' binary on PATH the
# hook must produce a visible once-per-session skip notice on both channels,
# silent on the second run. jq removal then exercises the input-parsing gate.
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
REPO_NT="$WORK/no-gofmt"
mkdir -p "$REPO_NT"
git -C "$REPO_NT" init -q
printf 'package main\n\nfunc main(){\nx:=1\n_=x\n}\n' >"$REPO_NT/app.go"
NT_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
run_nt() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-nogofmt-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NT/app.go" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$NT_DATA" \
        CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true bash "$HOOK"
  )
}
OUT_NT=$(run_nt)
RC_NT=$?
if [[ $RC_NT -eq 0 ]]; then ok "gofmt-absent -> exit 0"; else fail "gofmt-absent exit $RC_NT"; fi
if jq -e '(.systemMessage | contains("gofmt")) and (.hookSpecificOutput.additionalContext | contains("PATH"))' <<<"$OUT_NT" >/dev/null 2>&1; then
  ok "gofmt-absent -> visible notice on both channels"
else
  fail "gofmt-absent: notice missing or malformed: $OUT_NT"
fi
OUT_NT2=$(run_nt)
if [[ -z "$OUT_NT2" ]]; then
  ok "gofmt-absent -> second run same session is silent (once-per-session)"
else
  fail "gofmt-absent second run not silent: $OUT_NT2"
fi

# jq-absent -> visible once-per-session notice (input parsing gate).
rm -f "$FAKEBIN/jq"
JQ_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
OUT_NOJQ=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-nojq-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NT/app.go" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
      CLAUDE_PLUGIN_OPTION_GO_FORMAT_ENABLED=true bash "$HOOK"
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
