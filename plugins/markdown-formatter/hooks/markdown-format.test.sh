#!/usr/bin/env bash
# Black-box contract test for markdown-format.sh (the markdown-formatter plugin hook).
#
# Proves WIRING, not baseline parity: that the hook fires on *.md/*.mdc, skips
# otherwise, runs markdownlint-cli2 --fix from the linted file's repo root
# (config discovery is CWD-anchored), preserves --fix bytes, and surfaces
# residual findings via additionalContext with no medley-policy prose.
#
# Self-contained: builds a throwaway git repo with its own markdownlint config
# and runtime-generated fixtures (CRLF preserved via printf, never committed —
# a committed CRLF fixture would be LF-normalized by .gitattributes). The hook
# is invoked as a subprocess from an UNRELATED cwd so the `cd repo-root` config
# discovery is genuinely exercised (running from the repo root would false-pass
# a hook that skips the cd).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/markdown-format.sh"

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

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# --- Build the throwaway consumer repo --------------------------------------
REPO="$WORK/consumer"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t

# Consumer's own markdownlint config — the cascade the hook must discover by
# cd-ing to the repo root. MD004 dash makes `*` markers a fixable violation;
# MD024 siblings_only makes a duplicate sibling heading an unfixable residual.
cat >"$REPO/.markdownlint-cli2.jsonc" <<'JSONC'
{
  "config": {
    "MD004": { "style": "dash" },
    "MD024": { "siblings_only": true },
    "MD013": false
  }
}
JSONC

# Invoke the hook as a subprocess from an unrelated cwd. CLAUDE_PROJECT_DIR is
# left UNSET so read_file_path's project-membership guard is disabled (it is not
# part of the fire-gate contract); this isolates formatting behavior from any
# POSIX-vs-Windows path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$file_path" \
    | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")
}

# --- Fixture A: fixable only (Path A) — clean after fix, no additionalContext -
# CRLF, no final newline. Only issue is the missing final newline (MD047);
# after --fix the file is clean → empty stdout.
FA="$REPO/fixtureA.md"
printf '# Title A\r\n\r\nSome text\r\n\r\n- item one\r\n- item two' >"$FA"

OUT_A="$(run_hook "$FA")"
RC_A=$?

if [[ $RC_A -eq 0 ]]; then ok "fixtureA exit 0"; else fail "fixtureA exit $RC_A"; fi
if [[ -z "$OUT_A" ]]; then ok "fixtureA empty stdout (clean after fix)"; else fail "fixtureA stdout not empty: $OUT_A"; fi
# --fix added a final newline; CRLF preserved.
EXPECT_A="$(printf '# Title A\r\n\r\nSome text\r\n\r\n- item one\r\n- item two\r\n')"
TAIL_A="$(tail -c 2 "$FA" | od -An -tx1 | tr -d ' \n')"
if [[ "$(cat "$FA")" == "$EXPECT_A" && "$TAIL_A" == "0d0a" ]]; then
  ok "fixtureA --fix added final newline, CRLF preserved"
else
  fail "fixtureA bytes wrong: $(od -c "$FA" | tail -3)"
fi

# --- Fixture B: fixable + unfixable (Path B) — fix applied + residual finding -
# `* star item` (MD004 dash, fixable) + duplicate sibling `## Section` (MD024,
# unfixable). --fix converts `*`→`-`; MD024 residual surfaces via context.
FB="$REPO/fixtureB.md"
printf '# Doc B\n\n## Section\n\ntext\n\n## Section\n\n* star item\n' >"$FB"

OUT_B="$(run_hook "$FB")"
RC_B=$?

if [[ $RC_B -eq 0 ]]; then ok "fixtureB exit 0"; else fail "fixtureB exit $RC_B"; fi
# Fixable MD004 applied: marker is now a dash.
if grep -q '^- star item$' "$FB" && ! grep -q '^\* star item$' "$FB"; then
  ok "fixtureB --fix applied MD004 dash"
else
  fail "fixtureB MD004 not fixed: $(cat "$FB")"
fi
# additionalContext carries the MD024 finding line (substring identity).
CTX_B=""
if [[ -n "$OUT_B" ]] && printf '%s' "$OUT_B" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX_B="$(printf '%s' "$OUT_B" | jq -r '.hookSpecificOutput.additionalContext')"
  ok "fixtureB emitted hookSpecificOutput.additionalContext"
else
  fail "fixtureB no additionalContext JSON: $OUT_B"
fi
if printf '%s' "$CTX_B" | grep -q 'fixtureB.md:7'; then
  ok "fixtureB ctx has finding line :7"
else
  fail "fixtureB ctx missing :7: $CTX_B"
fi
if printf '%s' "$CTX_B" | grep -q 'MD024'; then
  ok "fixtureB ctx names MD024"
else
  fail "fixtureB ctx missing MD024: $CTX_B"
fi
# Genericized wrapper: medley-policy tail must be gone.
if printf '%s' "$CTX_B" | grep -qi 'commit/CI will block'; then
  fail "fixtureB ctx still has medley policy tail"
else
  ok "fixtureB ctx dropped medley policy tail"
fi

# --- Fire gate: non-.md extension skips -------------------------------------
SKIP="$REPO/skip.other"
printf 'whatever\n' >"$SKIP"
OUT_S="$(run_hook "$SKIP")"
RC_S=$?
if [[ $RC_S -eq 0 && -z "$OUT_S" ]]; then
  ok "non-md extension skipped"
else
  fail "non-md not skipped (rc=$RC_S out=$OUT_S)"
fi

# --- Fire gate: non-existent .md skips --------------------------------------
OUT_M="$(run_hook "$REPO/does-not-exist.md")"
RC_M=$?
if [[ $RC_M -eq 0 && -z "$OUT_M" ]]; then
  ok "missing .md skipped"
else
  fail "missing .md not skipped (rc=$RC_M out=$OUT_M)"
fi

# --- Kill switch: disabled hook is a no-op ----------------------------------
OUT_K="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FB" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=false bash "$HOOK")"
RC_K=$?
if [[ $RC_K -eq 0 && -z "$OUT_K" ]]; then
  ok "kill switch disables hook"
else
  fail "kill switch failed (rc=$RC_K out=$OUT_K)"
fi

# ============================================================================
# Phase 2: hook telemetry tests
# ============================================================================

# --- Telemetry sink unset → hook stdout + exit identical to pre-change ------
# Additive-safety proof: HOOK_TELEMETRY_SINK unset must produce byte-identical
# stdout and exit code to the pre-Phase-2 baseline.

# Re-run fixture A with sink unset — must still produce empty stdout, exit 0.
printf '# Title A2\r\n\r\nSome text\r\n\r\n- item one\r\n- item two' >"$REPO/fixtureA2.md"
OUT_A_NOSINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$REPO/fixtureA2.md" \
  | env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK HOOK_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_A_NOSINK=$?
if [[ $RC_A_NOSINK -eq 0 ]]; then ok "telemetry/sink-unset: exit 0 (parity)"; else fail "telemetry/sink-unset: expected 0, got $RC_A_NOSINK"; fi
if [[ -z "$OUT_A_NOSINK" ]]; then ok "telemetry/sink-unset: empty stdout (parity)"; else fail "telemetry/sink-unset: stdout not empty: $OUT_A_NOSINK"; fi

# Re-run fixture B with sink unset — must still emit additionalContext, exit 0.
printf '# Doc B2\n\n## Section\n\ntext\n\n## Section\n\n* star item\n' >"$REPO/fixtureB2.md"
OUT_B_NOSINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Edit"}' "$REPO/fixtureB2.md" \
  | env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK HOOK_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_B_NOSINK=$?
if [[ $RC_B_NOSINK -eq 0 ]]; then ok "telemetry/sink-unset B: exit 0 (parity)"; else fail "telemetry/sink-unset B: expected 0, got $RC_B_NOSINK"; fi
if printf '%s' "$OUT_B_NOSINK" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "telemetry/sink-unset B: additionalContext present (parity)"
else
  fail "telemetry/sink-unset B: no additionalContext: $OUT_B_NOSINK"
fi
# Emit must NOT appear in hook stdout (no envelope JSON alongside additionalContext)
if printf '%s' "$OUT_B_NOSINK" | jq -e '.schema_version' >/dev/null 2>&1; then
  fail "telemetry/sink-unset B: envelope leaked to hook stdout"
else
  ok "telemetry/sink-unset B: no envelope in hook stdout"
fi

# --- Stub sink: real edit → schema-valid envelope with status ok and findings -
TEL_FILE="$(mktemp)"
STUB_SINK="tee $TEL_FILE"

# Fixture with unfixable finding (MD024 duplicate heading): status ok + findings populated.
printf '# Doc T\n\n## Section\n\ntext\n\n## Section\n\nmore text\n' >"$REPO/fixtureT.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_FILE
_OUT_T="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureT.md" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_SINK" bash "$HOOK")"
RC_T=$?
sleep 0.3  # allow background sink to flush

if [[ $RC_T -eq 0 ]]; then ok "telemetry/stub-sink: hook exit 0"; else fail "telemetry/stub-sink: hook exit $RC_T"; fi

if [[ -s "$TEL_FILE" ]]; then
  ok "telemetry/stub-sink: envelope received"
  # Validate all 7 required common fields
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL_FILE" >/dev/null 2>&1; then
      ok "telemetry/envelope: $field present"
    else
      fail "telemetry/envelope: $field missing. file=$(cat "$TEL_FILE")"
    fi
  done
  # status must be "ok"
  TEL_STATUS="$(jq -r '.status' "$TEL_FILE")"
  if [[ "$TEL_STATUS" == "ok" ]]; then ok "telemetry/envelope: status ok"; else fail "telemetry/envelope: status expected ok, got $TEL_STATUS"; fi
  # data.findings must contain exactly the MD024 violation line (not banner noise).
  # Schema: "Unfixable markdownlint violations remaining after --fix, one per line."
  # Banner lines (version, Finding:, Linting:, Summary:) must be excluded.
  TEL_FINDINGS_LEN="$(jq '.data.findings | length' "$TEL_FILE")"
  if [[ "$TEL_FINDINGS_LEN" -eq 1 ]]; then
    ok "telemetry/envelope: findings has exactly 1 item (violation only, no banner noise)"
  else
    fail "telemetry/envelope: findings expected 1 violation, got $TEL_FINDINGS_LEN: $(jq '.data.findings' "$TEL_FILE")"
  fi
  # The single finding must name the MD024 rule.
  if jq -e '.data.findings[0] | test("MD024")' "$TEL_FILE" >/dev/null 2>&1; then
    ok "telemetry/envelope: findings[0] names MD024"
  else
    fail "telemetry/envelope: findings[0] does not name MD024: $(jq '.data.findings[0]' "$TEL_FILE")"
  fi
  # data.tool must be "Write" (from the input JSON)
  TEL_TOOL="$(jq -r '.data.tool' "$TEL_FILE")"
  if [[ "$TEL_TOOL" == "Write" ]]; then ok "telemetry/envelope: data.tool is Write"; else fail "telemetry/envelope: data.tool expected Write, got $TEL_TOOL"; fi
  # data.file must be repo-relative (schema: "relative to the consuming repo root").
  # A relative path does not start with / or a Windows drive letter.
  TEL_FILE_VAL="$(jq -r '.data.file' "$TEL_FILE")"
  if [[ -n "$TEL_FILE_VAL" && "$TEL_FILE_VAL" != /* && "$TEL_FILE_VAL" != ?:* ]]; then
    ok "telemetry/envelope: data.file is repo-relative ($TEL_FILE_VAL)"
  else
    fail "telemetry/envelope: data.file expected repo-relative, got: $TEL_FILE_VAL"
  fi
  # schema_version must be "1.0"
  TEL_SV="$(jq -r '.schema_version' "$TEL_FILE")"
  if [[ "$TEL_SV" == "1.0" ]]; then ok "telemetry/envelope: schema_version 1.0"; else fail "telemetry/envelope: schema_version expected 1.0, got $TEL_SV"; fi
  # duration_ms must be non-negative integer
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL_FILE" >/dev/null 2>&1; then
    ok "telemetry/envelope: duration_ms is non-negative integer"
  else
    fail "telemetry/envelope: duration_ms invalid: $(jq .duration_ms "$TEL_FILE")"
  fi
else
  fail "telemetry/stub-sink: no envelope written to sink"
  for field in schema_version timestamp hook hook_event status duration_ms data status findings tool file schema_version duration_ms; do
    : # counters already accounted by the outer if branch counting
  done
  fail "telemetry/envelope: status (no envelope)"
  fail "telemetry/envelope: findings (no envelope)"
  fail "telemetry/envelope: data.tool (no envelope)"
  fail "telemetry/envelope: data.file (no envelope)"
  fail "telemetry/envelope: schema_version (no envelope)"
  fail "telemetry/envelope: duration_ms (no envelope)"
fi
rm -f "$TEL_FILE"

# --- Stub sink: clean file → status ok, findings empty array -----------------
TEL_CLEAN="$(mktemp)"
STUB_CLEAN="tee $TEL_CLEAN"
printf '# Clean Doc\n\nSome text.\n' >"$REPO/fixtureClean.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_CLEAN
_OUT_CLEAN="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureClean.md" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_CLEAN" bash "$HOOK")"
RC_CLEAN=$?
sleep 0.3

if [[ $RC_CLEAN -eq 0 ]]; then ok "telemetry/clean: hook exit 0"; else fail "telemetry/clean: hook exit $RC_CLEAN"; fi
if [[ -s "$TEL_CLEAN" ]]; then
  STATUS_CLEAN="$(jq -r '.status' "$TEL_CLEAN")"
  if [[ "$STATUS_CLEAN" == "ok" ]]; then ok "telemetry/clean: status ok"; else fail "telemetry/clean: status expected ok, got $STATUS_CLEAN"; fi
  FINDINGS_CLEAN="$(jq '.data.findings | length' "$TEL_CLEAN")"
  if [[ "$FINDINGS_CLEAN" -eq 0 ]]; then ok "telemetry/clean: findings empty array"; else fail "telemetry/clean: findings should be empty, got $FINDINGS_CLEAN items"; fi
else
  fail "telemetry/clean: no envelope written"
  fail "telemetry/clean: status (no envelope)"
  fail "telemetry/clean: findings empty (no envelope)"
fi
rm -f "$TEL_CLEAN"

# --- Stub sink non-zero exit → format + hook exit 0 unaffected ---------------
FAIL_SINK_FILE="$(mktemp)"
# A sink that exits non-zero but still writes (to prove hook ignores sink failure)
FAIL_SINK="bash -c 'tee \"$FAIL_SINK_FILE\"; exit 1'"
printf '# Failing Sink Doc\n\nSome text.\n' >"$REPO/fixtureFailSink.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; exit code is the assertion
_OUT_FS="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureFailSink.md" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$FAIL_SINK" bash "$HOOK")"
RC_FS=$?
sleep 0.3

if [[ $RC_FS -eq 0 ]]; then ok "telemetry/fail-sink: hook exit 0 despite sink failure"; else fail "telemetry/fail-sink: hook exit $RC_FS, expected 0"; fi
rm -f "$FAIL_SINK_FILE"

# --- Slow sink (C1 detector): hook returns in <<3s ---------------------------
# A sink that sleeps 3s; the hook must return in well under 3s.
SLOW_SINK="bash -c 'cat >/dev/null; sleep 3'"
printf '# Slow Sink Doc\n\nSome text.\n' >"$REPO/fixtureSlowSink.md"

TS_SLOW_START=$EPOCHREALTIME
# shellcheck disable=SC2034  # stdout captured so the $(...) blocks until fd1 closes — proves no fd1 leak
_OUT_SLOW="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureSlowSink.md" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SLOW_SINK" bash "$HOOK")"
RC_SLOW=$?
TS_SLOW_END=$EPOCHREALTIME
SS="${TS_SLOW_START%[.,]*}"; SF="${TS_SLOW_START#*[.,]}"
ES="${TS_SLOW_END%[.,]*}"; EF="${TS_SLOW_END#*[.,]}"
SLOW_MS=$(( (ES * 1000000 + 10#$EF - SS * 1000000 - 10#$SF) / 1000 ))

echo "  (C1 slow-sink elapsed: ${SLOW_MS}ms)"
if [[ $RC_SLOW -eq 0 ]]; then ok "telemetry/slow-sink: hook exit 0"; else fail "telemetry/slow-sink: hook exit $RC_SLOW"; fi
if [[ $SLOW_MS -lt 2000 ]]; then
  ok "telemetry/slow-sink: returned in ${SLOW_MS}ms (<<3000ms = C1 passes)"
else
  fail "telemetry/slow-sink: returned in ${SLOW_MS}ms — fd1 leak blocks (C1 FAIL)"
fi

# --- Emit never leaks to hook stdout -----------------------------------------
# hook stdout must contain ONLY the hookSpecificOutput JSON (for residual case)
# or be empty (clean case). Never the telemetry envelope.
TEL_LEAK="$(mktemp)"
LEAK_SINK="tee $TEL_LEAK"
printf '# Leak Doc\n\n## Section\n\ntext\n\n## Section\n\nmore text\n' >"$REPO/fixtureLeakCheck.md"
OUT_LEAK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureLeakCheck.md" \
  | env -u CLAUDE_PROJECT_DIR HOOK_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$LEAK_SINK" bash "$HOOK")"
sleep 0.3

# The hook stdout must NOT contain the telemetry envelope's top-level keys
if printf '%s' "$OUT_LEAK" | jq -e '.schema_version' >/dev/null 2>&1; then
  fail "telemetry/stdout-leak: envelope schema_version found in hook stdout"
elif printf '%s' "$OUT_LEAK" | jq -e '.duration_ms' >/dev/null 2>&1; then
  fail "telemetry/stdout-leak: envelope duration_ms found in hook stdout"
else
  ok "telemetry/stdout-leak: no envelope in hook stdout"
fi
# Hook stdout must still contain additionalContext (findings present for this fixture)
if printf '%s' "$OUT_LEAK" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "telemetry/stdout-leak: additionalContext still present when sink set"
else
  fail "telemetry/stdout-leak: additionalContext missing when sink set: $OUT_LEAK"
fi
rm -f "$TEL_LEAK"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
