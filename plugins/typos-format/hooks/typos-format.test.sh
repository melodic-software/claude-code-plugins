#!/usr/bin/env bash
# Black-box contract test for typos-format.sh (the typos-format plugin hook).
#
# Proves WIRING: the hook fires on every Write|Edit (no extension filter),
# runs `typos -w` from the file's own path (no repo-root `cd`, since typos'
# config discovery is file-anchored, not CWD-anchored), auto-fixes unambiguous
# typos, surfaces residual (ambiguous) findings via additionalContext
# (advisory, exit 0), honors the kill switch, discovers a consumer
# _typos.toml several directories above the edited file regardless of the
# hook's own working directory, respects the consumer's [files] extend-exclude
# for an explicitly-edited file via --force-exclude, and emits a schema-valid
# telemetry envelope. No source-repo policy prose in the surfaced context.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked as a subprocess from an UNRELATED cwd so file-anchored
# config discovery is genuinely exercised (running from the repo root would
# false-pass a hook that silently depended on its own cwd).
#
# Requires a real typos binary: $TYPOS_TEST_BIN if set, else `typos` on PATH.
# Without one the behavioral assertions cannot run, so the suite skips.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/typos-format.sh"

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

# Resolve a real typos binary. Skip the suite when none is available (mirrors
# ruff-format/bash-format: an individual contract test SKIPs rather than
# fails when its optional tool is absent).
if [[ -n "${TYPOS_TEST_BIN:-}" && -x "${TYPOS_TEST_BIN}" ]]; then
  REAL_TYPOS="${TYPOS_TEST_BIN}"
elif command -v typos >/dev/null 2>&1; then
  REAL_TYPOS="$(command -v typos)"
else
  echo "SKIP: no typos binary (set TYPOS_TEST_BIN or put typos on PATH) -- typos-format hook tests skipped"
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

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate);
# this isolates fix behavior from any path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK"
  )
}

REPO="$WORK/consumer"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t

# --- Fixture A: unambiguous typo, fully fixable -> clean after fix ----------
FA="$REPO/fixtureA.txt"
printf 'This has a recieve typo.\n' >"$FA"

OUT_A="$(run_hook "$FA")"
RC_A=$?
if [[ $RC_A -eq 0 ]]; then ok "fixtureA exit 0"; else fail "fixtureA exit $RC_A"; fi
if [[ -z "$OUT_A" ]]; then ok "fixtureA empty stdout (clean after fix)"; else fail "fixtureA stdout not empty: $OUT_A"; fi
if grep -q '^This has a receive typo\.$' "$FA"; then
  ok "fixtureA --write-changes applied unambiguous fix"
else
  fail "fixtureA not fixed: $(cat "$FA")"
fi

# --- Fixture B: fixable + ambiguous residual (typos-cli 1.44.0: `fo` has 5 --
# candidate corrections and is never auto-applied) -------------------------
FB="$REPO/fixtureB.txt"
printf 'This has a mroe typo and an ambiguous fo case.\n' >"$FB"

OUT_B="$(run_hook "$FB")"
RC_B=$?
if [[ $RC_B -eq 0 ]]; then ok "fixtureB exit 0"; else fail "fixtureB exit $RC_B"; fi
if grep -q ' more ' "$FB" && ! grep -q ' mroe ' "$FB"; then
  ok "fixtureB unambiguous fix (mroe -> more) applied"
else
  fail "fixtureB unambiguous fix missing: $(cat "$FB")"
fi
if grep -q ' fo ' "$FB"; then
  ok "fixtureB ambiguous word left untouched (fo)"
else
  fail "fixtureB ambiguous word was altered: $(cat "$FB")"
fi
CTX_B=""
if [[ -n "$OUT_B" ]] && printf '%s' "$OUT_B" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX_B="$(printf '%s' "$OUT_B" | jq -r '.hookSpecificOutput.additionalContext')"
  ok "fixtureB emitted hookSpecificOutput.additionalContext"
else
  fail "fixtureB no additionalContext JSON: $OUT_B"
fi
if printf '%s' "$CTX_B" | grep -q 'fo ->'; then
  ok "fixtureB ctx names the residual typo (fo)"
else
  fail "fixtureB ctx missing residual typo: $CTX_B"
fi
if printf '%s' "$CTX_B" | grep -qi 'mroe'; then
  fail "fixtureB ctx still lists the already-fixed typo (mroe)"
else
  ok "fixtureB ctx omits the already-fixed typo"
fi

# --- No extension filter: an arbitrary non-code file is still processed -----
FC="$REPO/fixtureC.someweirdext"
printf 'This has a recieve typo.\n' >"$FC"
# shellcheck disable=SC2034  # stdout captured so the $(...) subshell fully drains; only the exit code is asserted here
OUT_C="$(run_hook "$FC")"
RC_C=$?
if [[ $RC_C -eq 0 ]]; then ok "fixtureC (unusual extension) exit 0"; else fail "fixtureC exit $RC_C"; fi
if grep -q '^This has a receive typo\.$' "$FC"; then
  ok "fixtureC (unusual extension) still fixed -- no extension gate"
else
  fail "fixtureC not fixed: $(cat "$FC")"
fi

# --- Missing .txt: fire gate skips (mirrors sibling formatter hooks) --------
OUT_M="$(run_hook "$REPO/does-not-exist.txt")"
RC_M=$?
if [[ $RC_M -eq 0 && -z "$OUT_M" ]]; then
  ok "missing file skipped"
else
  fail "missing file not skipped (rc=$RC_M out=$OUT_M)"
fi

# --- Consumer _typos.toml discovered several directories above the edited --
# file, from an UNRELATED hook cwd (file-anchored discovery, not CWD-anchored)
NESTED="$REPO/nested/sub/dir"
mkdir -p "$NESTED"
printf '[default.extend-words]\nmroe = "mroe"\n' >"$REPO/nested/_typos.toml"
FD="$NESTED/fixtureD.txt"
printf 'This has a mroe typo and recieve too.\n' >"$FD"

# shellcheck disable=SC2034  # stdout captured so the $(...) subshell fully drains; only the exit code is asserted here
OUT_D="$(run_hook "$FD")"
RC_D=$?
if [[ $RC_D -eq 0 ]]; then ok "fixtureD exit 0"; else fail "fixtureD exit $RC_D"; fi
if grep -q ' mroe ' "$FD"; then
  ok "fixtureD nested _typos.toml allowlist respected (mroe left alone)"
else
  fail "fixtureD allowlisted word was altered: $(cat "$FD")"
fi
if grep -q ' receive ' "$FD"; then
  ok "fixtureD still fixed the non-allowlisted typo (recieve -> receive)"
else
  fail "fixtureD non-allowlisted typo not fixed: $(cat "$FD")"
fi

# --- force-exclude: a consumer [files] extend-exclude entry is honored for --
# an explicitly-edited file, not silently overridden the way a bare CLI
# invocation would (typos-cli 1.44.0: extend-exclude is ignored for a
# directly-named path unless --force-exclude is passed).
EXREPO="$WORK/exclude-consumer"
mkdir -p "$EXREPO"
git -C "$EXREPO" init -q
git -C "$EXREPO" config user.email t@t.t
git -C "$EXREPO" config user.name t
printf '[files]\nextend-exclude = ["excluded.txt"]\n' >"$EXREPO/_typos.toml"
FE="$EXREPO/excluded.txt"
printf 'This has a recieve typo.\n' >"$FE"

OUT_E="$(run_hook "$FE")"
RC_E=$?
if [[ $RC_E -eq 0 && -z "$OUT_E" ]]; then
  ok "excluded file: exit 0, no advisory"
else
  fail "excluded file not silent (rc=$RC_E out=$OUT_E)"
fi
if grep -q ' recieve ' "$FE"; then
  ok "excluded file left byte-for-byte untouched"
else
  fail "excluded file was modified despite extend-exclude: $(cat "$FE")"
fi

# --- Tool break (malformed consumer config): advisory, not a finding --------
BADREPO="$WORK/badcfg-consumer"
mkdir -p "$BADREPO"
git -C "$BADREPO" init -q
git -C "$BADREPO" config user.email t@t.t
git -C "$BADREPO" config user.name t
printf 'this is not valid toml [[[\n' >"$BADREPO/_typos.toml"
FBAD="$BADREPO/f.txt"
printf 'clean text.\n' >"$FBAD"

OUT_BAD="$(run_hook "$FBAD")"
RC_BAD=$?
if [[ $RC_BAD -eq 0 ]]; then ok "tool-break case: hook exit 0 (advisory)"; else fail "tool-break case: hook exit $RC_BAD"; fi
if printf '%s' "$OUT_BAD" | jq -e '.hookSpecificOutput.additionalContext | contains("tool break, not a finding")' >/dev/null 2>&1; then
  ok "tool-break case emits a tool-break advisory (not a spelling finding)"
else
  fail "tool-break advisory absent: $OUT_BAD"
fi

# --- Kill switch: disabled hook is a no-op ----------------------------------
FK="$REPO/fixtureK.txt"
printf 'This has a recieve typo.\n' >"$FK"
OUT_K="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FK" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_K=$?
if [[ $RC_K -eq 0 && -z "$OUT_K" ]]; then
  ok "kill switch disables hook"
else
  fail "kill switch failed (rc=$RC_K out=$OUT_K)"
fi
if grep -q ' recieve ' "$FK"; then
  ok "kill switch: file left untouched"
else
  fail "kill switch: file was modified despite the toggle being off: $(cat "$FK")"
fi

# --- Missing typos: visible advisory on both channels -----------------------
# Fake-bin dir of exec wrappers forwarding to the REAL tool for everything
# except typos itself (an explicit allowlist PATH, not a subtractive one --
# jq and typos share the same install directory on this machine, so removing
# a directory from PATH would hide both).
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done

FNT="$REPO/fixtureNoTypos.txt"
printf 'This has a recieve typo.\n' >"$FNT"
PD_NO_TYPOS="$(mktemp -d -p "$WORK" pd.XXXXXX)"
OUT_NO_TYPOS="$(cd "$UNRELATED" && printf '{"session_id":"test-notypos-1","tool_input":{"file_path":"%s"}}' "$FNT" |
  env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$PD_NO_TYPOS" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true bash "$HOOK")"
RC_NO_TYPOS=$?
if [[ $RC_NO_TYPOS -eq 0 ]]; then ok "missing typos exits 0 (advisory)"; else fail "missing typos exit $RC_NO_TYPOS"; fi
if printf '%s' "$OUT_NO_TYPOS" | jq -e '(.hookSpecificOutput.additionalContext | contains("was not found on PATH")) and (.systemMessage | contains("was not found on PATH"))' >/dev/null 2>&1; then
  ok "missing typos emits visible notice on both channels"
else
  fail "missing typos warning absent: $OUT_NO_TYPOS"
fi
if grep -q ' recieve ' "$FNT"; then
  ok "missing typos: file left untouched"
else
  fail "missing typos: file was modified: $(cat "$FNT")"
fi
OUT_NO_TYPOS_2="$(cd "$UNRELATED" && printf '{"session_id":"test-notypos-1","tool_input":{"file_path":"%s"}}' "$FNT" |
  env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$PD_NO_TYPOS" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true bash "$HOOK")"
if [[ -z "$OUT_NO_TYPOS_2" ]]; then
  ok "missing typos: second run same session is silent (once-per-session)"
else
  fail "missing typos: second run not silent: $OUT_NO_TYPOS_2"
fi

# --- Missing jq: visible advisory, no malformed parsing ---------------------
NO_JQ_ENV="$WORK/no-jq.bashenv"
cat >"$NO_JQ_ENV" <<'EOF'
command() {
  if [[ "${1:-}" == "-v" && "${2:-}" == "jq" ]]; then
    return 1
  fi
  builtin command "$@"
}
EOF
FNJ="$REPO/fixtureNoJq.txt"
printf 'This has a recieve typo.\n' >"$FNJ"
PD_NO_JQ="$(mktemp -d -p "$WORK" pd.XXXXXX)"
OUT_NO_JQ="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FNJ" |
  env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_JQ_ENV" CLAUDE_PLUGIN_DATA="$PD_NO_JQ" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_NO_JQ=$?
if [[ $RC_NO_JQ -eq 0 ]]; then ok "missing jq exits 0 (advisory)"; else fail "missing jq exit $RC_NO_JQ"; fi
if printf '%s' "$OUT_NO_JQ" | jq -e '(.hookSpecificOutput.additionalContext | contains("jq not found on PATH")) and (.systemMessage | contains("jq not found on PATH"))' >/dev/null 2>&1; then
  ok "missing jq emits visible notice on both channels"
else
  fail "missing jq warning absent: $OUT_NO_JQ"
fi

# ============================================================================
# Phase 2: hook telemetry tests
# ============================================================================

# --- Telemetry sink unset -> hook stdout + exit identical to pre-change -----
FA2="$REPO/fixtureA2.txt"
printf 'This has a recieve typo.\n' >"$FA2"
OUT_A_NOSINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FA2" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_A_NOSINK=$?
if [[ $RC_A_NOSINK -eq 0 ]]; then ok "telemetry/sink-unset: exit 0 (parity)"; else fail "telemetry/sink-unset: expected 0, got $RC_A_NOSINK"; fi
if [[ -z "$OUT_A_NOSINK" ]]; then ok "telemetry/sink-unset: empty stdout (parity)"; else fail "telemetry/sink-unset: stdout not empty: $OUT_A_NOSINK"; fi

FB2="$REPO/fixtureB2.txt"
printf 'This has a mroe typo and an ambiguous fo case.\n' >"$FB2"
OUT_B_NOSINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Edit"}' "$FB2" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_B_NOSINK=$?
if [[ $RC_B_NOSINK -eq 0 ]]; then ok "telemetry/sink-unset B: exit 0 (parity)"; else fail "telemetry/sink-unset B: expected 0, got $RC_B_NOSINK"; fi
if printf '%s' "$OUT_B_NOSINK" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "telemetry/sink-unset B: additionalContext present (parity)"
else
  fail "telemetry/sink-unset B: no additionalContext: $OUT_B_NOSINK"
fi
if printf '%s' "$OUT_B_NOSINK" | jq -e '.schema_version' >/dev/null 2>&1; then
  fail "telemetry/sink-unset B: envelope leaked to hook stdout"
else
  ok "telemetry/sink-unset B: no envelope in hook stdout"
fi

# --- Stub sink: residual finding -> schema-valid envelope, status ok --------
TEL_FILE="$(mktemp)"
STUB_SINK="$(make_sink "cat >\"$TEL_FILE\"")"
FT="$REPO/fixtureT.txt"
printf 'This has a mroe typo and an ambiguous fo case.\n' >"$FT"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_FILE
_OUT_T="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FT" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_SINK" PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_T=$?
wait_for_sink "$TEL_FILE"

if [[ $RC_T -eq 0 ]]; then ok "telemetry/stub-sink: hook exit 0"; else fail "telemetry/stub-sink: hook exit $RC_T"; fi
if [[ -s "$TEL_FILE" ]]; then
  ok "telemetry/stub-sink: envelope received"
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL_FILE" >/dev/null 2>&1; then
      ok "telemetry/envelope: $field present"
    else
      fail "telemetry/envelope: $field missing. file=$(cat "$TEL_FILE")"
    fi
  done
  TEL_HOOK="$(jq -r '.hook' "$TEL_FILE")"
  if [[ "$TEL_HOOK" == "typos-format" ]]; then ok "telemetry/envelope: hook is typos-format"; else fail "telemetry/envelope: hook expected typos-format, got $TEL_HOOK"; fi
  TEL_STATUS="$(jq -r '.status' "$TEL_FILE")"
  if [[ "$TEL_STATUS" == "ok" ]]; then ok "telemetry/envelope: status ok"; else fail "telemetry/envelope: status expected ok, got $TEL_STATUS"; fi
  TEL_FINDINGS_LEN="$(jq '.data.findings | length' "$TEL_FILE")"
  if [[ "$TEL_FINDINGS_LEN" -eq 1 ]]; then
    ok "telemetry/envelope: findings has exactly 1 item (residual only, no already-fixed noise)"
  else
    fail "telemetry/envelope: findings expected 1, got $TEL_FINDINGS_LEN: $(jq '.data.findings' "$TEL_FILE")"
  fi
  if jq -e '.data.findings[0] | test("fo")' "$TEL_FILE" >/dev/null 2>&1; then
    ok "telemetry/envelope: findings[0] names the residual typo (fo)"
  else
    fail "telemetry/envelope: findings[0] does not name fo: $(jq '.data.findings[0]' "$TEL_FILE")"
  fi
  TEL_TOOL="$(jq -r '.data.tool' "$TEL_FILE")"
  if [[ "$TEL_TOOL" == "Write" ]]; then ok "telemetry/envelope: data.tool is Write"; else fail "telemetry/envelope: data.tool expected Write, got $TEL_TOOL"; fi
  TEL_FILE_VAL="$(jq -r '.data.file' "$TEL_FILE")"
  if [[ -n "$TEL_FILE_VAL" && "$TEL_FILE_VAL" != /* && "$TEL_FILE_VAL" != ?:* ]]; then
    ok "telemetry/envelope: data.file is repo-relative ($TEL_FILE_VAL)"
  else
    fail "telemetry/envelope: data.file expected repo-relative, got: $TEL_FILE_VAL"
  fi
  TEL_SV="$(jq -r '.schema_version' "$TEL_FILE")"
  if [[ "$TEL_SV" == "1.0" ]]; then ok "telemetry/envelope: schema_version 1.0"; else fail "telemetry/envelope: schema_version expected 1.0, got $TEL_SV"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL_FILE" >/dev/null 2>&1; then
    ok "telemetry/envelope: duration_ms is non-negative integer"
  else
    fail "telemetry/envelope: duration_ms invalid: $(jq .duration_ms "$TEL_FILE")"
  fi
else
  fail "telemetry/stub-sink: no envelope written to sink"
fi
rm -f "$TEL_FILE"

# --- Stub sink: clean file -> status ok, findings empty array ---------------
TEL_CLEAN="$(mktemp)"
STUB_CLEAN="$(make_sink "cat >\"$TEL_CLEAN\"")"
FCLEAN="$REPO/fixtureClean.txt"
printf 'Some clean text.\n' >"$FCLEAN"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_CLEAN
_OUT_CLEAN="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FCLEAN" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_CLEAN" PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_CLEAN=$?
wait_for_sink "$TEL_CLEAN"
if [[ $RC_CLEAN -eq 0 ]]; then ok "telemetry/clean: hook exit 0"; else fail "telemetry/clean: hook exit $RC_CLEAN"; fi
if [[ -s "$TEL_CLEAN" ]]; then
  STATUS_CLEAN="$(jq -r '.status' "$TEL_CLEAN")"
  if [[ "$STATUS_CLEAN" == "ok" ]]; then ok "telemetry/clean: status ok"; else fail "telemetry/clean: status expected ok, got $STATUS_CLEAN"; fi
  FINDINGS_CLEAN="$(jq '.data.findings | length' "$TEL_CLEAN")"
  if [[ "$FINDINGS_CLEAN" -eq 0 ]]; then ok "telemetry/clean: findings empty array"; else fail "telemetry/clean: findings should be empty, got $FINDINGS_CLEAN items"; fi
else
  fail "telemetry/clean: no envelope written"
fi
rm -f "$TEL_CLEAN"

# --- Stub sink: missing-typos path reports status skipped -------------------
TEL_SKIP="$(mktemp)"
STUB_SKIP="$(make_sink "cat >\"$TEL_SKIP\"")"
FSKIP="$REPO/fixtureSkipTel.txt"
printf 'This has a recieve typo.\n' >"$FSKIP"
PD_SKIP_TEL="$(mktemp -d -p "$WORK" pd.XXXXXX)"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_SKIP
_OUT_SKIP_TEL="$(cd "$UNRELATED" && printf '{"session_id":"test-notypos-tel","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FSKIP" |
  env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$PD_SKIP_TEL" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_SKIP" bash "$HOOK")"
wait_for_sink "$TEL_SKIP"
if [[ -s "$TEL_SKIP" ]] && [[ "$(jq -r '.status' "$TEL_SKIP")" == "skipped" ]]; then
  ok "telemetry/missing-typos: status skipped"
else
  fail "telemetry/missing-typos: expected status skipped: $(cat "$TEL_SKIP" 2>/dev/null)"
fi
rm -f "$TEL_SKIP"

# --- Stub sink non-zero exit -> hook exit 0 unaffected ----------------------
FAIL_SINK_FILE="$(mktemp)"
FAIL_SINK="$(make_sink "cat >\"$FAIL_SINK_FILE\"; exit 1")"
FFS="$REPO/fixtureFailSink.txt"
printf 'Some clean text.\n' >"$FFS"
# shellcheck disable=SC2034  # stdout captured for timing correctness; exit code is the assertion
_OUT_FS="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FFS" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$FAIL_SINK" PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_FS=$?
wait_for_sink "$FAIL_SINK_FILE"
if [[ $RC_FS -eq 0 ]]; then ok "telemetry/fail-sink: hook exit 0 despite sink failure"; else fail "telemetry/fail-sink: hook exit $RC_FS, expected 0"; fi
rm -f "$FAIL_SINK_FILE"

# --- Slow sink (C1 detector): hook returns in <<3s ---------------------------
SLOW_SINK="$(make_sink "cat >/dev/null; sleep 3")"
FSS="$REPO/fixtureSlowSink.txt"
printf 'Some clean text.\n' >"$FSS"
TS_SLOW_START=$EPOCHREALTIME
# shellcheck disable=SC2034  # stdout captured so the $(...) blocks until fd1 closes -- proves no fd1 leak
_OUT_SLOW="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FSS" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SLOW_SINK" PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_SLOW=$?
TS_SLOW_END=$EPOCHREALTIME
SS="${TS_SLOW_START%[.,]*}"
SF="${TS_SLOW_START#*[.,]}"
ES="${TS_SLOW_END%[.,]*}"
EF="${TS_SLOW_END#*[.,]}"
SLOW_MS=$(((ES * 1000000 + 10#$EF - SS * 1000000 - 10#$SF) / 1000))

echo "  (C1 slow-sink elapsed: ${SLOW_MS}ms)"
if [[ $RC_SLOW -eq 0 ]]; then ok "telemetry/slow-sink: hook exit 0"; else fail "telemetry/slow-sink: hook exit $RC_SLOW"; fi
if [[ $SLOW_MS -lt 2000 ]]; then
  ok "telemetry/slow-sink: returned in ${SLOW_MS}ms (<<3000ms = C1 passes)"
else
  fail "telemetry/slow-sink: returned in ${SLOW_MS}ms -- fd1 leak blocks (C1 FAIL)"
fi

# --- Emit never leaks to hook stdout -----------------------------------------
TEL_LEAK="$(mktemp)"
LEAK_SINK="$(make_sink "cat >\"$TEL_LEAK\"")"
FLEAK="$REPO/fixtureLeakCheck.txt"
printf 'This has a mroe typo and an ambiguous fo case.\n' >"$FLEAK"
OUT_LEAK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FLEAK" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$LEAK_SINK" PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
wait_for_sink "$TEL_LEAK"

if printf '%s' "$OUT_LEAK" | jq -e '.schema_version' >/dev/null 2>&1; then
  fail "telemetry/stdout-leak: envelope schema_version found in hook stdout"
elif printf '%s' "$OUT_LEAK" | jq -e '.duration_ms' >/dev/null 2>&1; then
  fail "telemetry/stdout-leak: envelope duration_ms found in hook stdout"
else
  ok "telemetry/stdout-leak: no envelope in hook stdout"
fi
if printf '%s' "$OUT_LEAK" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "telemetry/stdout-leak: additionalContext still present when sink set"
else
  fail "telemetry/stdout-leak: additionalContext missing when sink set: $OUT_LEAK"
fi
rm -f "$TEL_LEAK"

# --- Unwired producer runs zero telemetry-only subprocesses -------------------
# The telemetry payload (tool_name jq parse, cygpath path normalization, data
# JSON build) must be gated on sink presence. Count subprocess spawns via PATH
# shims: a cygpath shim that logs and echoes its last argument unchanged, and a
# jq shim that logs then delegates to the real jq so hook behavior is
# unaffected. cygpath assertions filter on the hook's `-lm` flag.
SHIM_DIR="$WORK/shims"
mkdir -p "$SHIM_DIR"
CYG_LOG="$WORK/cygpath.log"
JQ_LOG="$WORK/jq.log"
REAL_JQ="$(command -v jq)"
cat >"$SHIM_DIR/cygpath" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CYG_LOG"
printf '%s\n' "\${!#}"
EOF
cat >"$SHIM_DIR/jq" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$JQ_LOG"
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$SHIM_DIR/cygpath" "$SHIM_DIR/jq"

count_lm() { grep -c -- '-lm' "$CYG_LOG" 2>/dev/null || true; }

: >"$CYG_LOG"
: >"$JQ_LOG"
FGATE="$REPO/fixtureGate.txt"
printf 'Clean text.\n' >"$FGATE"
OUT_GATE="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FGATE" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true PATH="$SHIM_DIR:$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
RC_GATE=$?
if [[ $RC_GATE -eq 0 && -z "$OUT_GATE" ]]; then
  ok "telemetry-gate/unwired: exit 0, empty stdout"
else
  fail "telemetry-gate/unwired: rc=$RC_GATE out=$OUT_GATE"
fi
CYG_LM_UNWIRED="$(count_lm)"
if [[ "$CYG_LM_UNWIRED" -eq 0 ]]; then
  ok "telemetry-gate/unwired: zero cygpath -lm spawns"
else
  fail "telemetry-gate/unwired: $CYG_LM_UNWIRED cygpath -lm spawns: $(cat "$CYG_LOG")"
fi
JQ_UNWIRED="$(wc -l <"$JQ_LOG")"
if [[ "$JQ_UNWIRED" -eq 2 ]]; then
  ok "telemetry-gate/unwired: exactly 2 jq spawns (stdin probe + file_path parse)"
else
  fail "telemetry-gate/unwired: expected 2 jq spawns, got $JQ_UNWIRED: $(cat "$JQ_LOG")"
fi

# Wired (stub sink), same fixture shape: the payload construction must still
# run -- positive control proving the shims observe the telemetry spawns.
: >"$CYG_LOG"
: >"$JQ_LOG"
TEL_GATE="$(mktemp)"
GATE_SINK="$(make_sink "cat >\"$TEL_GATE\"")"
FGATEW="$REPO/fixtureGateWired.txt"
printf 'Clean text.\n' >"$FGATEW"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_GATE
_OUT_GW="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$FGATEW" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$GATE_SINK" PATH="$SHIM_DIR:$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK")"
wait_for_sink "$TEL_GATE"
CYG_LM_WIRED="$(count_lm)"
if [[ "$CYG_LM_WIRED" -eq 2 ]]; then
  ok "telemetry-gate/wired: 2 cygpath -lm spawns (FILE + REPO_ROOT normalization)"
else
  fail "telemetry-gate/wired: expected 2 cygpath -lm spawns, got $CYG_LM_WIRED: $(cat "$CYG_LOG")"
fi
JQ_WIRED="$(wc -l <"$JQ_LOG")"
if [[ "$JQ_WIRED" -gt 1 ]]; then
  ok "telemetry-gate/wired: payload jq spawns present ($JQ_WIRED total)"
else
  fail "telemetry-gate/wired: expected >1 jq spawns, got $JQ_WIRED: $(cat "$JQ_LOG")"
fi
if [[ -s "$TEL_GATE" ]] && jq -e '.data.tool == "Write"' "$TEL_GATE" >/dev/null 2>&1; then
  ok "telemetry-gate/wired: envelope delivered with data.tool intact"
else
  fail "telemetry-gate/wired: envelope missing or data.tool wrong: $(cat "$TEL_GATE" 2>/dev/null)"
fi
rm -f "$TEL_GATE"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
