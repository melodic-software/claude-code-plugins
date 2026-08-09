#!/usr/bin/env bash
# Black-box contract test for typos-format.sh (the typos-format plugin hook).
#
# Proves WIRING: the hook fires on any file (no extension filter) UNCONDITIONALLY
# — with or without a consumer typos config — is REPORT-ONLY by default
# (#1809's single-writer decision), applies typos' safe corrections in place
# only under the typos_format_write_changes opt-in, honors typos' own
# typos.toml > _typos.toml > .typos.toml > Cargo.toml > pyproject.toml
# precedence when a config IS present, surfaces residual (unfixable) findings
# via additionalContext with remediation guidance, honors the kill switch, and
# emits a schema-valid telemetry envelope.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked from an UNRELATED cwd so any reliance on the caller's
# own working directory would surface (typos resolves config relative to the
# target path passed on the command line, not the process CWD — Case 3 below
# locks this in — so the hook's own cd to the repo root does not change which
# config governs).
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

# new_typos_repo <dir> [config_filename] -> init a git repo, optionally with a
# typos config file (default _typos.toml with a fixable typo + unfixable
# blank-correction "disallowme" pair). config_filename NO_CONFIG omits it.
new_typos_repo() {
  local r="$1" cfg_name="${2:-_typos.toml}"
  mkdir -p "$r"
  git -C "$r" init -q
  git -C "$r" config user.email t@t.t
  git -C "$r" config user.name t
  if [[ "$cfg_name" != "NO_CONFIG" ]]; then
    printf '[default.extend-words]\ndisallowme = ""\n' >"$r/$cfg_name"
  fi
}

# Invoke the hook from an unrelated cwd. CLAUDE_PROJECT_DIR is left UNSET so
# read_file_path's membership guard is disabled (not part of the fire gate);
# this isolates gate/fix behavior from path-form mismatch in the guard.
# Write mode is opted IN here: these cases exercise the fix/config contract,
# which only exists under the opt-in. The report-only DEFAULT has its own
# cases (stub/default-report-only and the explicit-false override below).
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true \
        CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES=true \
        PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK"
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

# ============================================================================
# Disclosure contract — driven by a STUB typos, so it runs everywhere
# ============================================================================
# The cases below assert the contract that matters most about this hook: it
# changes the content of the user's files, and every change it makes must be
# reported on both channels. A real typos binary is not installed on the CI
# runner, so the real-binary suite further down SKIPs there — asserting this
# contract only against a real binary would leave it ungated in exactly the
# place a regression would land unnoticed. The stub implements the slice of
# typos' documented contract this hook depends on and nothing more:
#
# spellchecker:off
#   token       corrections            --write-changes behavior
#   ----------- ---------------------- ---------------------------------------
#   teh         ["the"]                applied
#   wnat        ["want","what"]        NOT applied (ambiguous), stays residual
#   disallowme  null                   NOT applied (no correction), residual
#
# Exit codes mirror typos-cli 1.44.0 as verified against the real binary:
# 0 = nothing left to report, 2 = findings remain. jsonlines on stdout.
STUB_BIN="$(mktemp -d "$WORK/stubbin.XXXXXX")"
cat >"$STUB_BIN/typos" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
write=0
target=""
skip_next=0
for arg in "$@"; do
  if ((skip_next == 1)); then
    skip_next=0
    continue
  fi
  case "$arg" in
  --write-changes) write=1 ;;
  --format) skip_next=1 ;;
  --format=*) ;;
  -*) ;;
  *) target="$arg" ;;
  esac
done
[[ -n "$target" && -f "$target" ]] || exit 0

# STUB_BREAK: exit 2 with EMPTY output on the write pass — a typos break
# mid-write. Read as "nothing residual" it would classify every scanned finding
# as applied, disclosing rewrites that never happened.
if ((write == 1)) && [[ -n "${STUB_BREAK:-}" ]]; then
  exit 2
fi

# STUB_LONG: report an absurdly long correction for every fixable finding. The
# entry COUNT is capped, but a single entry is arbitrary text from the file, so
# ten of them can still overrun the systemMessage character cap.
long=""
if [[ -n "${STUB_LONG:-}" ]]; then
  i=0
  while ((i < 40)); do
    long="${long}veryverylongcorrectiontoken"
    i=$((i + 1))
  done
fi

# STUB_REFLOW: on the WRITE pass, report every surviving finding one line lower
# than the scan reported it — a sibling formatter (markdown-format on the same
# .md, say) reflowing the file between the hook's two passes. Claude Code runs
# matching PostToolUse hooks in parallel, so nothing orders them. typos changed
# nothing about these findings; only their position moved.
shift_lines=0
if ((write == 1)) && [[ -n "${STUB_REFLOW:-}" ]]; then
  shift_lines=1
fi

residual=0
out=""
lineno=0
tmp="$target.stubtmp"
: >"$tmp"
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  reported=$((lineno + shift_lines))
  for tok in teh wnat disallowme; do
    case " $line " in
    *" $tok "*) ;;
    *) continue ;;
    esac
    case "$tok" in
    teh)
      # STUB_MIXED: one spelling, two correction decisions in one file — the
      # shape typos produces when extend-identifiers reaches an occurrence that
      # extend-words does not. A line carrying the marker is DISALLOWED (null
      # corrections) and survives the write; every other occurrence is fixable
      # and gets rewritten.
      if [[ -n "${STUB_MIXED:-}" && "$line" == *keepteh* ]]; then
        out+='{"type":"typo","path":"'"$target"'","line_num":'"$reported"',"byte_offset":0,"typo":"teh","corrections":null}'$'\n'
        residual=1
      else
        out+='{"type":"typo","path":"'"$target"'","line_num":'"$reported"',"byte_offset":0,"typo":"teh","corrections":["'"${long:-the}"'"]}'$'\n'
        if ((write == 1)); then line="${line//" teh "/" the "}"; else residual=1; fi
      fi
      ;;
    wnat)
      out+='{"type":"typo","path":"'"$target"'","line_num":'"$reported"',"byte_offset":0,"typo":"wnat","corrections":["want","what"]}'$'\n'
      residual=1
      ;;
    disallowme)
      out+='{"type":"typo","path":"'"$target"'","line_num":'"$reported"',"byte_offset":0,"typo":"disallowme","corrections":null}'$'\n'
      residual=1
      ;;
    esac
  done
  printf '%s\n' "$line" >>"$tmp"
done <"$target"

if ((write == 1)); then
  mv -f "$tmp" "$target"
  # Re-emit only what survived the write. Under STUB_MIXED the disallowed `teh`
  # survives too, so drop only the fixable form (the one carrying a corrections
  # array) rather than every `teh` line.
  if [[ -n "${STUB_MIXED:-}" ]]; then
    printf '%s' "$out" | grep -v '"typo":"teh","corrections":\['
  else
    printf '%s' "$out" | grep -v '"typo":"teh"'
  fi
  ((residual == 1)) && exit 2
  exit 0
fi
rm -f "$tmp"
printf '%s' "$out"
[[ -n "$out" ]] && exit 2
exit 0
STUB
# spellchecker:on
chmod +x "$STUB_BIN/typos"

# Invoke the hook with the stub on PATH, in opted-in write mode (the
# disclosure contract below is about the changes write mode makes). A caller's
# own trailing env assignments win over the opt-in (env is last-wins), so the
# explicit-false override case can still pass WRITE_CHANGES=false here.
run_stub() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"stub-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR PATH="$STUB_BIN:$PATH" \
        CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true \
        CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES=true "$@" bash "$HOOK"
  )
}

# Invoke the hook with the stub on PATH and NO write-mode option at all — the
# out-of-the-box posture.
run_stub_default() {
  local file_path="$1"
  shift
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"stub-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES \
        PATH="$STUB_BIN:$PATH" \
        CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true "$@" bash "$HOOK"
  )
}

STUB_REPO="$WORK/stub-repo"
new_typos_repo "$STUB_REPO" NO_CONFIG

# --- Applied correction is disclosed on BOTH channels ------------------------
# The defect this closes: on the all-fixed path the hook emitted no stdout at
# all, so a dictionary rewrite of a domain term reached the file with the only
# trace being the harness's generic "a hook modified this file" line — no hook
# name, no word, no diff.
printf 'this has teh typo\n' >"$STUB_REPO/applied.txt" # spellchecker:disable-line
OUT_AP=$(run_stub "$STUB_REPO/applied.txt")
RC_AP=$?
if [[ $RC_AP -eq 0 ]]; then ok "stub/applied: exit 0 (advisory)"; else fail "stub/applied: exit $RC_AP"; fi
if grep -q ' the ' "$STUB_REPO/applied.txt"; then
  ok "stub/applied: correction written to the file"
else
  fail "stub/applied: file not rewritten: $(cat "$STUB_REPO/applied.txt")"
fi
if printf '%s' "$OUT_AP" | jq -e . >/dev/null 2>&1; then
  ok "stub/applied: stdout is one parseable JSON document"
else
  fail "stub/applied: stdout is not a single JSON document: $OUT_AP"
fi
CTX_AP=$(printf '%s' "$OUT_AP" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
SYS_AP=$(printf '%s' "$OUT_AP" | jq -r '.systemMessage // empty' 2>/dev/null)
if printf '%s' "$CTX_AP" | grep -qF '"teh" -> "the"'; then # spellchecker:disable-line
  ok "stub/applied: rewrite disclosed on the agent channel"
else
  fail "stub/applied: no agent-channel disclosure: $CTX_AP"
fi
if printf '%s' "$SYS_AP" | grep -qF '"teh" -> "the"'; then # spellchecker:disable-line
  ok "stub/applied: rewrite disclosed on the user channel"
else
  fail "stub/applied: no user-channel disclosure: $SYS_AP"
fi
if printf '%s' "$CTX_AP" | grep -qi 'extend-words'; then
  ok "stub/applied: allow-list remediation rides on the APPLIED path (not just the residual one)"
else
  fail "stub/applied: no extend-words guidance on the applied path: $CTX_AP"
fi

# --- DEFAULT is report-only: the out-of-the-box hook never writes ------------
# Pins #1809's single-writer decision: with no typos_format_write_changes
# option set at all, the hook must report findings and leave the file
# byte-identical. This is the invariant that removes the unconditional-writer
# race with sibling formatter hooks — a regression here reintroduces it.
printf 'this has teh typo\n' >"$STUB_REPO/default.txt" # spellchecker:disable-line
BEFORE_DEF="$(cat "$STUB_REPO/default.txt")"
OUT_DEF=$(run_stub_default "$STUB_REPO/default.txt")
RC_DEF=$?
if [[ $RC_DEF -eq 0 ]]; then ok "stub/default: exit 0"; else fail "stub/default: exit $RC_DEF"; fi
if [[ "$(cat "$STUB_REPO/default.txt")" == "$BEFORE_DEF" ]]; then
  ok "stub/default: file left byte-identical with NO write-mode option set (single-writer default)"
else
  fail "stub/default: out-of-the-box hook modified the file: $(cat "$STUB_REPO/default.txt")"
fi
CTX_DEF=$(printf '%s' "$OUT_DEF" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_DEF" | grep -q 'report-only' && printf '%s' "$CTX_DEF" | grep -q 'teh'; then # spellchecker:disable-line
  ok "stub/default: findings still reported in report-only default"
else
  fail "stub/default: findings or mode statement missing: $CTX_DEF"
fi
if [[ -z "$(printf '%s' "$OUT_DEF" | jq -r '.systemMessage // empty' 2>/dev/null)" ]]; then
  ok "stub/default: no user-channel message (nothing was mutated)"
else
  fail "stub/default: emitted a systemMessage without mutating anything"
fi

# --- Report-only can also be pinned explicitly (option set to false) ---------
printf 'this has teh typo\n' >"$STUB_REPO/readonly.txt" # spellchecker:disable-line
BEFORE_RO="$(cat "$STUB_REPO/readonly.txt")"
OUT_RO=$(run_stub "$STUB_REPO/readonly.txt" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES=false)
RC_RO=$?
if [[ $RC_RO -eq 0 ]]; then ok "stub/report-only: exit 0"; else fail "stub/report-only: exit $RC_RO"; fi
if [[ "$(cat "$STUB_REPO/readonly.txt")" == "$BEFORE_RO" ]]; then
  ok "stub/report-only: file left byte-identical"
else
  fail "stub/report-only: file was modified: $(cat "$STUB_REPO/readonly.txt")"
fi
CTX_RO=$(printf '%s' "$OUT_RO" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_RO" | grep -q 'report-only' && printf '%s' "$CTX_RO" | grep -q 'NOT modified'; then
  ok "stub/report-only: mode is stated in the report"
else
  fail "stub/report-only: mode not stated: $CTX_RO"
fi
if [[ -z "$(printf '%s' "$OUT_RO" | jq -r '.systemMessage // empty' 2>/dev/null)" ]]; then
  ok "stub/report-only: no user-channel message (nothing was mutated)"
else
  fail "stub/report-only: emitted a systemMessage without mutating anything"
fi

# --- Applied + residual in one run: both sections, one document --------------
printf 'this has teh typo and wnat and a disallowme term\n' >"$STUB_REPO/both.txt" # spellchecker:disable-line
OUT_BOTH=$(run_stub "$STUB_REPO/both.txt")
CTX_BOTH=$(printf '%s' "$OUT_BOTH" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_BOTH" | grep -qF '"teh" -> "the"' && # spellchecker:disable-line
  printf '%s' "$CTX_BOTH" | grep -q 'disallowme' &&
  printf '%s' "$CTX_BOTH" | grep -q 'wnat'; then # spellchecker:disable-line
  ok "stub/both: applied rewrite and both residual findings reported together"
else
  fail "stub/both: sections missing: $CTX_BOTH"
fi
if printf '%s' "$OUT_BOTH" | jq -e '.systemMessage and .hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "stub/both: both channels composed into ONE stdout document"
else
  fail "stub/both: channels not composed: $OUT_BOTH"
fi

# --- A residual that MOVED between the passes is not a rewrite ---------------
# Claude Code runs matching PostToolUse hooks in parallel, so a sibling
# formatter can reflow the file between this hook's scan and write passes and
# carry an untouched finding to a different line. STUB_REFLOW forces exactly
# that, deterministically: every write-pass finding is reported one line below
# where the scan reported it. Nothing else about the run changes.
#
# The planted misspelling below is ambiguous, so typos declines it and it
# survives the write. The truth is therefore that NOTHING was applied. Keyed
# by line, the moved
# residual misses its own scan entry and the finding is reported as a rewrite
# typos never made — a false mutation disclosure on the one channel this hook
# exists to make trustworthy.
printf 'this has wnat here\n' >"$STUB_REPO/reflow.txt" # spellchecker:disable-line
BEFORE_RF="$(cat "$STUB_REPO/reflow.txt")"
SINKRF="$WORK/tel-reflow.jsonl"
OUT_RF=$(run_stub "$STUB_REPO/reflow.txt" STUB_REFLOW=1 HOOK_TELEMETRY_SINK="$SINKRF")
if [[ "$(cat "$STUB_REPO/reflow.txt")" == "$BEFORE_RF" ]]; then
  ok "stub/reflow: file unchanged (the ambiguous finding was never fixable)"
else
  fail "stub/reflow: stub wrote to a file with no fixable finding: $(cat "$STUB_REPO/reflow.txt")"
fi
CTX_RF=$(printf '%s' "$OUT_RF" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_RF" | grep -qF '"wnat" ->'; then # spellchecker:disable-line
  fail "stub/reflow: moved residual reported as an applied rewrite: $CTX_RF"
else
  ok "stub/reflow: moved residual is NOT reported as an applied rewrite"
fi
if printf '%s' "$CTX_RF" | grep -q 'wnat'; then # spellchecker:disable-line
  ok "stub/reflow: the finding is still reported, as a residual"
else
  fail "stub/reflow: moved residual vanished from the report entirely: $CTX_RF"
fi
if [[ -z "$(printf '%s' "$OUT_RF" | jq -r '.systemMessage // empty' 2>/dev/null)" ]]; then
  ok "stub/reflow: no user-channel mutation message (nothing was mutated)"
else
  fail "stub/reflow: claimed a mutation that never happened: $(printf '%s' "$OUT_RF" | jq -r '.systemMessage')"
fi
if [[ -s "$SINKRF" ]]; then
  if [[ "$(jq -s '.[-1].data.applied | length' "$SINKRF" 2>/dev/null)" == "0" ]]; then
    ok "stub/reflow: telemetry records zero applied rewrites"
  else
    fail "stub/reflow: telemetry claims rewrites: $(jq -s -c '.[-1].data.applied' "$SINKRF")"
  fi
fi

# --- One spelling, two correction decisions ----------------------------------
# typos can flag the same spelling with different correction sets in one file —
# an occurrence reached by extend-identifiers beside one reached by
# extend-words, or a fixable occurrence beside a disallowed one. Cancelling
# residuals by token ALONE merges those, and the count can then retire the
# fixable scan entry and disclose the disallowed one instead: a rewrite claimed
# at the wrong line with a blank correction, while the rewrite that really
# happened goes unmentioned. The correction decision therefore belongs in the
# key. Here line 1's occurrence is fixable and rewritten; line 2's is disallowed
# and survives. Exactly one rewrite happened, on line 1.
printf 'this has teh typo\nkeepteh line has teh here\n' >"$STUB_REPO/mixed.txt" # spellchecker:disable-line
OUT_MX=$(run_stub "$STUB_REPO/mixed.txt" STUB_MIXED=1)
CTX_MX=$(printf '%s' "$OUT_MX" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_MX" | grep -qF '"teh" -> "the" (line 1)'; then # spellchecker:disable-line
  ok "stub/mixed: the rewrite that happened is disclosed at its own line"
else
  fail "stub/mixed: real rewrite missing from the disclosure: $CTX_MX"
fi
if printf '%s' "$CTX_MX" | grep -qF '"teh" -> ""'; then # spellchecker:disable-line
  fail "stub/mixed: disallowed occurrence disclosed as an applied rewrite with a blank correction: $CTX_MX"
else
  ok "stub/mixed: no blank-correction rewrite claimed"
fi
if printf '%s' "$CTX_MX" | grep -qF '(line 2)'; then
  ok "stub/mixed: the disallowed occurrence is still reported, as a residual"
else
  fail "stub/mixed: disallowed occurrence vanished from the report: $CTX_MX"
fi

# --- Disclosure is capped ----------------------------------------------------
# A file with hundreds of corrections must not turn the disclosure into the
# unbounded context flood it exists to prevent.
: >"$STUB_REPO/many.txt"
for _i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  printf 'line with teh typo\n' >>"$STUB_REPO/many.txt" # spellchecker:disable-line
done
OUT_MANY=$(run_stub "$STUB_REPO/many.txt")
CTX_MANY=$(printf '%s' "$OUT_MANY" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
DETAIL_LINES=$(printf '%s' "$CTX_MANY" | grep -cF '(line ')
if [[ "$DETAIL_LINES" -eq 10 ]]; then
  ok "stub/cap: per-word detail capped at 10 lines (got $DETAIL_LINES)"
else
  fail "stub/cap: expected 10 detail lines, got $DETAIL_LINES: $CTX_MANY"
fi
if printf '%s' "$CTX_MANY" | grep -q 'REWROTE 15 word' && printf '%s' "$CTX_MANY" | grep -q 'and 5 more'; then
  ok "stub/cap: full count and remainder still reported"
else
  fail "stub/cap: count/remainder missing: $CTX_MANY"
fi

# --- Scale: disclosure must still arrive on a heavily-corrected file ---------
# Two distinct failures live here, both ending in the same place — the file is
# rewritten and stdout is empty, which is the silent mutation this whole change
# exists to end, hitting hardest on exactly the files that need it most:
#
#   1. A subprocess per finding. The handler declares a 15-second timeout; a
#      per-finding loop blew it at ~100 corrections.
#   2. Passing the finding sets to jq as --arg values. Windows caps a process
#      command line at 32767 characters and typos' jsonlines run ~110 bytes per
#      finding, so this broke silently somewhere past ~300 corrections — jq
#      never ran and the hook degraded to "could not be summarized".
#
# 500 is therefore the floor for this case, not 100: it has to exceed the argv
# limit, which a smaller count does not. Both streams go to jq on stdin now.
SCALE_N=500
: >"$STUB_REPO/scale.txt"
for _i in $(seq 1 "$SCALE_N"); do
  printf 'line %s has teh typo\n' "$_i" >>"$STUB_REPO/scale.txt" # spellchecker:disable-line
done
SCALE_START=$(date +%s)
OUT_SC=$(run_stub "$STUB_REPO/scale.txt")
SCALE_ELAPSED=$(($(date +%s) - SCALE_START))
CTX_SC=$(printf '%s' "$OUT_SC" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_SC" | grep -q "REWROTE $SCALE_N word"; then
  ok "stub/scale: $SCALE_N corrections are disclosed, not dropped"
else
  fail "stub/scale: disclosure missing on a $SCALE_N-correction file: $CTX_SC"
fi
if printf '%s' "$CTX_SC" | grep -q 'could not be summarized'; then
  fail "stub/scale: classification failed at $SCALE_N findings (argv limit?): $CTX_SC"
else
  ok "stub/scale: classification survives a finding set larger than a Windows command line"
fi
if printf '%s' "$CTX_SC" | grep -q $'\r'; then
  fail "stub/scale: carriage returns leaked into the report text"
else
  ok "stub/scale: report text carries no stray carriage returns"
fi
if [[ "$SCALE_ELAPSED" -lt 10 ]]; then
  ok "stub/scale: completed in ${SCALE_ELAPSED}s, inside the handler's 15s timeout"
else
  fail "stub/scale: took ${SCALE_ELAPSED}s — at or over the handler's 15s timeout budget"
fi

# The telemetry arrays are uncapped, so they hit the same argv ceiling as the
# finding sets. build_data_json feeds jq on stdin for that reason. The shared
# hook::emit_telemetry then hands the FINISHED payload over as an --argjson
# value, which is a fleet-wide fix tracked separately (#1595) — so an oversized
# envelope is currently dropped rather than delivered. Assert the invariant that
# holds either way and keeps holding once #1595 lands: telemetry is documented
# best-effort and lossy, so losing an envelope is inside contract. An envelope
# that ARRIVES reporting `applied: []` for a file this hook just rewrote 500
# words in is not — that is the local fallback firing.
TELSC="$(mktemp)"
SINKSC="$(make_sink "cat >\"$TELSC\"")"
run_stub "$STUB_REPO/scale.txt" HOOK_TELEMETRY_SINK="$SINKSC" >/dev/null
wait_for_sink "$TELSC" 50
if [[ -s "$TELSC" ]]; then
  SC_APPLIED=$(jq '.data.applied | length' "$TELSC" 2>/dev/null)
  SC_FINDINGS=$(jq '.data.findings | length' "$TELSC" 2>/dev/null)
  # The second run finds nothing left to fix (the first already rewrote the
  # file), so an accurate envelope here is empty on both arrays — the point is
  # that it is accurate, not that it is populated.
  if [[ "$SC_APPLIED" =~ ^[0-9]+$ && "$SC_FINDINGS" =~ ^[0-9]+$ ]]; then
    ok "stub/scale: the envelope that arrived carries well-formed arrays, not the blank fallback"
  else
    fail "stub/scale: envelope malformed at scale: $(cat "$TELSC")"
  fi
  if [[ "$(jq -r '.data.file' "$TELSC" 2>/dev/null)" == "" ]]; then
    fail "stub/scale: envelope arrived with data.file blanked — that is the build_data_json fallback"
  else
    ok "stub/scale: envelope names the file (build_data_json did not fall back)"
  fi
else
  ok "stub/scale: oversized envelope was dropped, not falsified (loss is in contract; see #1595)"
fi
rm -f "$TELSC"

# --- Scale, residual side: the membership test must not be a linear scan -----
# The case above is entirely APPLIED corrections, so it never exercises the
# residual-membership branch. Classifying residuals with a linear `index` over
# an array is quadratic: 10,000 all-residual findings measured ~15.7s in the jq
# invocation alone, past the handler's 15-second timeout — and the file is
# rewritten BEFORE classification, so that timeout lands after the mutation and
# before any disclosure. A minified or generated file where most findings are
# ambiguous is exactly that shape. Hash lookup does the same set in ~0.6s.
: >"$STUB_REPO/scale-residual.txt"
for _i in $(seq 1 "$SCALE_N"); do
  printf 'line %s has wnat and disallowme\n' "$_i" >>"$STUB_REPO/scale-residual.txt" # spellchecker:disable-line
done
RES_START=$(date +%s)
OUT_SR=$(run_stub "$STUB_REPO/scale-residual.txt")
RES_ELAPSED=$(($(date +%s) - RES_START))
CTX_SR=$(printf '%s' "$OUT_SR" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_SR" | grep -q "$((SCALE_N * 2)) finding(s)\|residual typos findings"; then
  ok "stub/scale-residual: an all-residual set of $((SCALE_N * 2)) findings is still reported"
else
  fail "stub/scale-residual: residual report missing: $CTX_SR"
fi
if printf '%s' "$CTX_SR" | grep -q 'REWROTE'; then
  fail "stub/scale-residual: claimed rewrites for a set where nothing was applied: $CTX_SR"
else
  ok "stub/scale-residual: nothing is claimed as rewritten when nothing was applied"
fi
if [[ "$RES_ELAPSED" -lt 10 ]]; then
  ok "stub/scale-residual: completed in ${RES_ELAPSED}s, inside the handler's 15s timeout"
else
  fail "stub/scale-residual: took ${RES_ELAPSED}s — quadratic membership regression?"
fi

# --- The disclosure must respect the channel's character cap -----------------
# Capping the number of entries does not cap the message: a token or correction
# is arbitrary text from the file, so ten long ones can still overrun the
# 10,000-character systemMessage cap and get the disclosure truncated or
# rejected by the channel — after the file has already been rewritten. Ten
# corrections of ~1,080 characters each is ~10,800 before any prose.
: >"$STUB_REPO/longtok.txt"
for _i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  printf 'line %s has teh typo\n' "$_i" >>"$STUB_REPO/longtok.txt" # spellchecker:disable-line
done
OUT_LT=$(run_stub "$STUB_REPO/longtok.txt" STUB_LONG=1)
SYS_LT=$(printf '%s' "$OUT_LT" | jq -r '.systemMessage // empty' 2>/dev/null)
CTX_LT=$(printf '%s' "$OUT_LT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ -n "$SYS_LT" && "${#SYS_LT}" -lt 10000 ]]; then
  ok "stub/long: systemMessage stays under the 10,000-character channel cap (${#SYS_LT})"
else
  fail "stub/long: systemMessage is ${#SYS_LT} characters — at or over the channel cap"
fi
if printf '%s' "$SYS_LT" | grep -q 'rewrote 12 word'; then
  ok "stub/long: the true rewrite count survives the character bound"
else
  fail "stub/long: count lost under truncation: $SYS_LT"
fi
if printf '%s' "$CTX_LT" | grep -q 'veryverylongcorrectiontokenveryverylongcorrectiontokenveryverylongcorrectiontoken'; then
  fail "stub/long: an unelided long token reached the report"
else
  ok "stub/long: long tokens are elided in the rendered report"
fi

# --- A broken write pass must not be read as "everything was applied" --------
printf 'this has teh typo and wnat too\n' >"$STUB_REPO/break.txt" # spellchecker:disable-line
OUT_BR=$(run_stub "$STUB_REPO/break.txt" STUB_BREAK=1)
RC_BR=$?
CTX_BR=$(printf '%s' "$OUT_BR" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ $RC_BR -eq 0 ]] && printf '%s' "$CTX_BR" | grep -q 'tool break'; then
  ok "stub/write-break: exit 2 with empty output is reported as a tool break"
else
  fail "stub/write-break: not reported as a tool break (rc=$RC_BR): $CTX_BR"
fi
if printf '%s' "$CTX_BR" | grep -q 'REWROTE'; then
  fail "stub/write-break: claimed rewrites after a broken write: $CTX_BR"
else
  ok "stub/write-break: no rewrite is claimed when the write never completed"
fi
if [[ -z "$(printf '%s' "$OUT_BR" | jq -r '.systemMessage // empty' 2>/dev/null)" ]]; then
  ok "stub/write-break: no user-channel mutation notice for a write that broke"
else
  fail "stub/write-break: emitted a mutation notice for a broken write"
fi

# --- Telemetry carries the applied rewrites ----------------------------------
printf 'this has teh typo and a disallowme term\n' >"$STUB_REPO/tel-applied.txt" # spellchecker:disable-line
TELA="$(mktemp)"
SINKA="$(make_sink "cat >\"$TELA\"")"
run_stub "$STUB_REPO/tel-applied.txt" HOOK_TELEMETRY_SINK="$SINKA" >/dev/null
wait_for_sink "$TELA"
if [[ -s "$TELA" ]]; then
  if [[ "$(jq -r '.data.applied[0].typo' "$TELA")" == "teh" ]]; then # spellchecker:disable-line
    ok "stub/telemetry: data.applied records the rewritten token"
  else
    fail "stub/telemetry: data.applied wrong: $(jq -c '.data.applied' "$TELA")"
  fi
  if [[ "$(jq -r '.data.applied[0].correction' "$TELA")" == "the" ]]; then
    ok "stub/telemetry: data.applied records the replacement"
  else
    fail "stub/telemetry: data.applied.correction wrong: $(jq -c '.data.applied' "$TELA")"
  fi
  # `line` is required by the data schema and is the only field that must be a
  # JSON number rather than a string — a quoted line number would validate as
  # neither the schema's integer nor anything a sink can sort on.
  if jq -e '.data.applied[0].line | type == "number" and . >= 1' "$TELA" >/dev/null 2>&1; then
    ok "stub/telemetry: data.applied.line is a positive number, as the schema requires"
  else
    fail "stub/telemetry: data.applied.line wrong: $(jq -c '.data.applied' "$TELA")"
  fi
  if [[ "$(jq -r '.data.findings[0].typo' "$TELA")" == "disallowme" ]]; then
    ok "stub/telemetry: data.findings still carries residual findings only"
  else
    fail "stub/telemetry: data.findings wrong: $(jq -c '.data.findings' "$TELA")"
  fi
else
  fail "stub/telemetry: no envelope written"
fi
rm -f "$TELA"

# ============================================================================
# Real-binary suite — wiring, config discovery, exclusion, kill switch
# ============================================================================
# Resolve a real typos binary. Skip the REST of the suite when none is
# available; the stub-driven contract cases above have already run.
if [[ -n "${TYPOS_TEST_BIN:-}" && -x "${TYPOS_TEST_BIN}" ]]; then
  REAL_TYPOS="${TYPOS_TEST_BIN}"
elif command -v typos >/dev/null 2>&1; then
  REAL_TYPOS="$(command -v typos)"
else
  echo "SKIP: no typos binary (set TYPOS_TEST_BIN or put typos on PATH) -- real-binary typos-format cases skipped"
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
  exit
fi

# --- Case 1: no typos config anywhere -> hook still runs unconditionally ----
# typos ships a built-in spelling dictionary and runs with zero configuration.
# A repo that has never adopted a typos config must still get its typos found
# — the hook must not gate on a consumer config existing. (run_hook opts into
# write mode, so the fix landing proves the config-free run end to end.)
REPO_NO="$WORK/no-config"
new_typos_repo "$REPO_NO" NO_CONFIG
printf 'this has teh typo\n' >"$REPO_NO/doc.txt" # spellchecker:disable-line
OUT=$(run_hook "$REPO_NO/doc.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "no config anywhere -> exit 0"; else fail "no config anywhere exit $RC"; fi
if grep -q ' the ' "$REPO_NO/doc.txt"; then
  ok "no config anywhere -> hook still fixes using typos' built-in dictionary"
else
  fail "no config anywhere -> file not fixed (hook incorrectly gated): $(cat "$REPO_NO/doc.txt")"
fi

# --- Case 2: typos.toml takes precedence over _typos.toml in the same dir ---
# The hook does not walk for a config itself; it passes the target path and
# lets typos resolve config on its own. This proves that resolution — and its
# documented same-directory precedence — still applies automatically.
REPO_PREC="$WORK/precedence"
new_typos_repo "$REPO_PREC" NO_CONFIG
printf '[default.extend-words]\nfooone = "correctone"\n' >"$REPO_PREC/_typos.toml"
printf '[default.extend-words]\nfootwo = "correcttwo"\n' >"$REPO_PREC/typos.toml"
printf 'this has fooone and footwo words\n' >"$REPO_PREC/p.txt"
run_hook "$REPO_PREC/p.txt" >/dev/null
if grep -q 'correcttwo' "$REPO_PREC/p.txt" && grep -q 'fooone' "$REPO_PREC/p.txt"; then
  ok "typos.toml wins over _typos.toml in the same directory"
else
  fail "config precedence wrong: $(cat "$REPO_PREC/p.txt")"
fi

# --- Case 3: config present + clean file -> exit 0, empty stdout ------------
REPO="$WORK/consumer"
new_typos_repo "$REPO"
printf 'this is a clean document\n' >"$REPO/clean.txt"
OUT=$(run_hook "$REPO/clean.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean file -> exit 0"; else fail "clean file exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean file -> empty stdout"; else fail "clean file stdout not empty: $OUT"; fi

# --- Case 4: config present + fixable typo -> autofixed in place ------------
mkdir -p "$REPO/src"
printf 'this has teh typo\n' >"$REPO/src/fix.txt" # spellchecker:disable-line
OUT=$(run_hook "$REPO/src/fix.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "fixable typo -> exit 0 (advisory)"; else fail "fixable typo exit $RC"; fi
if grep -q ' the ' "$REPO/src/fix.txt"; then
  ok "config present (subdir file) -> typos autofixed"
else
  fail "config present -> file not fixed: $(cat "$REPO/src/fix.txt")"
fi

# --- Case 5: config nested BELOW repo root (root itself has no config) ------
# The hook runs typos from the repo root (RUN_DIR), never from the config's
# own directory. This proves that does not matter: typos resolves config
# relative to the target path passed on the command line, not the process
# CWD, so a config nested arbitrarily deep is still discovered and honored.
REPO_NEST="$WORK/nested-config"
new_typos_repo "$REPO_NEST" NO_CONFIG
mkdir -p "$REPO_NEST/packages/pkg"
printf '[default.extend-words]\npkgword = "correctword"\n' >"$REPO_NEST/packages/pkg/_typos.toml"
printf 'this has pkgword in it\n' >"$REPO_NEST/packages/pkg/file.txt" # spellchecker:disable-line
run_hook "$REPO_NEST/packages/pkg/file.txt" >/dev/null
if grep -q 'correctword' "$REPO_NEST/packages/pkg/file.txt"; then
  ok "nested config (no root config) -> discovered and applied from repo root RUN_DIR"
else
  fail "nested config not applied: $(cat "$REPO_NEST/packages/pkg/file.txt")"
fi

# --- Case 6: unfixable finding -> advisory context with remediation ---------
mkdir -p "$REPO/lib"
printf 'this has a disallowme term\n' >"$REPO/lib/lint.txt"
OUT=$(run_hook "$REPO/lib/lint.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "unfixable finding -> exit 0 (advisory)"; else fail "unfixable finding exit $RC (must be advisory)"; fi
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')
  if printf '%s' "$CTX" | grep -q 'disallowme'; then
    ok "unfixable finding -> surfaced in additionalContext"
  else
    fail "unfixable ctx missing the finding: $CTX"
  fi
  if printf '%s' "$CTX" | grep -qi 'extend-words\|extend-identifiers\|extend-ignore-re'; then
    ok "unfixable finding -> remediation guidance present (epic-named deliverable)"
  else
    fail "unfixable finding -> no remediation guidance: $CTX"
  fi
else
  fail "unfixable finding -> no additionalContext JSON: $OUT"
fi

# --- Case 6b: fixable + unfixable together -> fixable applied, unfixable reported
printf 'this has teh typo and a disallowme term\n' >"$REPO/mixed.txt" # spellchecker:disable-line
OUT=$(run_hook "$REPO/mixed.txt")
if grep -q ' the ' "$REPO/mixed.txt" && grep -q 'disallowme' "$REPO/mixed.txt"; then
  ok "mixed fixable+unfixable -> fixable applied, unfixable left in place"
else
  fail "mixed case wrong: $(cat "$REPO/mixed.txt")"
fi
CTX_MIXED=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
FIXED_TYPO='teh' # spellchecker:disable-line
# BOTH halves are reported now: the residual finding as advisory, and the
# correction the hook APPLIED as a disclosed content mutation. A rewrite the
# user never asked for and never saw is the defect this reporting exists to
# close, so the applied word must appear, not be filtered out.
if printf '%s' "$CTX_MIXED" | grep -q 'disallowme' && printf '%s' "$CTX_MIXED" | grep -qF "\"$FIXED_TYPO\" -> \"the\""; then
  ok "mixed fixable+unfixable -> applied rewrite disclosed AND residual reported"
else
  fail "mixed case: reporting wrong: $CTX_MIXED"
fi
SYS_MIXED=$(printf '%s' "$OUT" | jq -r '.systemMessage // empty' 2>/dev/null)
if printf '%s' "$SYS_MIXED" | grep -qF "\"$FIXED_TYPO\" -> \"the\""; then
  ok "mixed fixable+unfixable -> applied rewrite also disclosed on the user channel"
else
  fail "mixed case: no user-channel disclosure of the rewrite: $SYS_MIXED"
fi

# --- Case 7: config excludes the edited file -> untouched, no nag ------------
# --force-exclude honors the config's own exclude/extend-exclude even for an
# explicitly-passed path. An excluded file must be left untouched with no
# advisory noise, even though it contains a fixable typo.
REPO_EX="$WORK/exclude-config"
new_typos_repo "$REPO_EX" NO_CONFIG
printf '[default.extend-words]\ndisallowme = ""\n\n[files]\nextend-exclude = ["gen"]\n' >"$REPO_EX/_typos.toml"
mkdir -p "$REPO_EX/gen"
printf 'this has teh typo\n' >"$REPO_EX/gen/g.txt" # spellchecker:disable-line
BEFORE_EX="$(cat "$REPO_EX/gen/g.txt")"
OUT=$(run_hook "$REPO_EX/gen/g.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "excluded file -> exit 0, silent (no nag)"; else fail "excluded file not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_EX/gen/g.txt")" == "$BEFORE_EX" ]]; then ok "excluded file -> left untouched (respects config exclude)"; else fail "excluded file -> was rewritten"; fi

# --- Case 7b: harness scratchpad under a home-shaped project dir -> untouched -
# The production over-fire (#1769): a session whose CLAUDE_PROJECT_DIR is the
# user's home admits the harness's own per-session scratchpad — it lives under
# the OS temp root, which is under home — so this hook autocorrected a shell
# variable in a throwaway script, in a location with no repo and therefore no
# typos config to allow-list the token with. Rewriting there is a content
# mutation of a file that is not project content and cannot be opted out of.
#
# Built without depending on where this host puts its temp tree: an outer
# project root outside any temp tree ($HOME), a stand-in temp root nested
# inside it that TMPDIR/TMP/TEMP point at, and the fixture file under that.
# `env -u CLAUDE_PROJECT_DIR` in run_hook_env is applied before the caller's
# own assignments, so passing CLAUDE_PROJECT_DIR here does set it.
SCRATCH_HOME=""
if [[ -n "${HOME:-}" && -d "${HOME:-}" ]]; then
  SCRATCH_HOME=$(mktemp -d "$HOME/.typos-format-test.XXXXXX" 2>/dev/null) || SCRATCH_HOME=""
fi
if [[ -n "$SCRATCH_HOME" ]]; then
  mkdir -p "$SCRATCH_HOME/scratchpad"
  printf 'this has teh typo\n' >"$SCRATCH_HOME/scratchpad/inventory.txt" # spellchecker:disable-line
  BEFORE_SP="$(cat "$SCRATCH_HOME/scratchpad/inventory.txt")"
  OUT_SP=$(run_hook_env "$SCRATCH_HOME/scratchpad/inventory.txt" \
    PATH="$(dirname "$REAL_TYPOS"):$PATH" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES=true \
    CLAUDE_PROJECT_DIR="$SCRATCH_HOME" TMPDIR="$SCRATCH_HOME/scratchpad" \
    TMP="$SCRATCH_HOME/scratchpad" TEMP="$SCRATCH_HOME/scratchpad")
  RC_SP=$?
  if [[ $RC_SP -eq 0 && -z "$OUT_SP" ]]; then
    ok "temp-tree file under a home-shaped project dir -> exit 0, silent"
  else
    fail "temp-tree file not silent (rc=$RC_SP out=$OUT_SP)"
  fi
  if [[ "$(cat "$SCRATCH_HOME/scratchpad/inventory.txt")" == "$BEFORE_SP" ]]; then
    ok "temp-tree file under a home-shaped project dir -> NOT rewritten"
  else
    fail "temp-tree file was rewritten: $(cat "$SCRATCH_HOME/scratchpad/inventory.txt")"
  fi
  rm -rf "$SCRATCH_HOME"
else
  ok "temp-tree scoping SKIPPED (no writable HOME on this host — no coverage here, not a pass)"
fi

# --- Case 8: kill switch bypasses hook ---------------------------------------
printf 'this has teh typo\n' >"$REPO/kill.txt" # spellchecker:disable-line
BEFORE_K="$(cat "$REPO/kill.txt")"
OUT=$(run_hook_env "$REPO/kill.txt" PATH="$(dirname "$REAL_TYPOS"):$PATH" \
  CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES=true CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false)
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "kill switch off -> exit 0 silent"; else fail "kill switch failed (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO/kill.txt")" == "$BEFORE_K" ]]; then ok "kill switch -> file untouched"; else fail "kill switch -> file was modified"; fi

# ============================================================================
# Telemetry
# ============================================================================

# --- Sink unset -> empty stdout, exit 0 (parity) ------------------------------
printf 'this is a clean telemetry parity check\n' >"$REPO/tel-clean.txt"
OUT_NS=$(run_hook_env "$REPO/tel-clean.txt" -u HOOK_TELEMETRY_SINK PATH="$(dirname "$REAL_TYPOS"):$PATH" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true)
RC_NS=$?
if [[ $RC_NS -eq 0 && -z "$OUT_NS" ]]; then
  ok "telemetry/sink-unset: exit 0, empty stdout (parity)"
else
  fail "telemetry/sink-unset: rc=$RC_NS out=$OUT_NS"
fi

# --- Stub sink + unfixable finding -> envelope status ok with findings -------
printf 'this has a disallowme term\n' >"$REPO/tel.txt"
TEL="$(mktemp)"
SINK="$(make_sink "cat >\"$TEL\"")"
run_hook_env "$REPO/tel.txt" PATH="$(dirname "$REAL_TYPOS"):$PATH" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINK" >/dev/null
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
  if [[ "$(jq -r '.hook' "$TEL")" == "typos-format" ]]; then ok "envelope: hook is typos-format"; else fail "envelope: hook=$(jq -r '.hook' "$TEL")"; fi
  if [[ "$(jq -r '.status' "$TEL")" == "ok" ]]; then ok "envelope: status ok"; else fail "envelope: status=$(jq -r '.status' "$TEL")"; fi
  if [[ "$(jq -r '.schema_version' "$TEL")" == "1.0" ]]; then ok "envelope: schema_version 1.0"; else fail "envelope: schema_version=$(jq -r '.schema_version' "$TEL")"; fi
  if [[ "$(jq '.data.findings | length' "$TEL")" -ge 1 ]]; then ok "envelope: findings populated"; else fail "envelope: findings empty ($(jq '.data.findings' "$TEL"))"; fi
  if [[ "$(jq -r '.data.findings[0].typo' "$TEL")" == "disallowme" ]]; then ok "envelope: findings[0].typo correct"; else fail "envelope: findings[0].typo=$(jq -r '.data.findings[0].typo' "$TEL")"; fi
  if [[ "$(jq -r '.data.findings[0].corrections' "$TEL")" == "null" ]]; then ok "envelope: findings[0].corrections null for disallowed entry"; else fail "envelope: findings[0].corrections=$(jq -r '.data.findings[0].corrections' "$TEL")"; fi
  FREL=$(jq -r '.data.file' "$TEL")
  if [[ -n "$FREL" && "$FREL" != /* && "$FREL" != ?:* ]]; then ok "envelope: data.file repo-relative ($FREL)"; else fail "envelope: data.file not repo-relative: $FREL"; fi
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL" >/dev/null 2>&1; then ok "envelope: duration_ms non-negative int"; else fail "envelope: duration_ms invalid ($(jq .duration_ms "$TEL"))"; fi
  if ! printf '%s' "$OUT" | grep -q schema_version 2>/dev/null; then ok "envelope: never leaked into hook's own stdout"; else fail "envelope leaked into stdout"; fi
else
  fail "telemetry/stub-sink: no envelope written"
fi
rm -f "$TEL"

# --- Stub sink + no config, fully-fixed file -> status ok, no residual findings
printf 'this has teh typo\n' >"$REPO_NO/tel2.txt" # spellchecker:disable-line
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO_NO/tel2.txt" PATH="$(dirname "$REAL_TYPOS"):$PATH" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true \
  CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "ok" ]]; then ok "telemetry/no-config: status ok (unconditional run)"; else fail "telemetry/no-config: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/no-config: findings empty array (fully fixed)"; else fail "telemetry/no-config: findings not empty"; fi
else
  fail "telemetry/no-config: no envelope written"
fi
rm -f "$TELS"

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers (no typos): with no 'typos' binary on PATH the
# hook must produce a visible once-per-session skip notice on both channels,
# silent on the second run. jq removal then exercises the input-parsing gate.
FAKEBIN="$(mktemp -d "$WORK/fakebin.XXXXXX")"
for t in bash jq git dirname basename cat env printf mktemp mkdir find tr awk grep sed uname sleep cygpath realpath readlink; do
  real_t="$(command -v "$t" 2>/dev/null)" || continue
  [[ -n "$real_t" ]] || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$real_t" >"$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
REPO_NT="$WORK/no-typos"
mkdir -p "$REPO_NT"
git -C "$REPO_NT" init -q
printf '[default.extend-words]\ndisallowme = ""\n' >"$REPO_NT/_typos.toml"
printf 'this has teh typo\n' >"$REPO_NT/app.txt" # spellchecker:disable-line
NT_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
run_nt() {
  (
    cd "$UNRELATED" || return 1
    printf '{"session_id":"test-notypos-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NT/app.txt" |
      env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$NT_DATA" \
        CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true bash "$HOOK"
  )
}
OUT_NT=$(run_nt)
RC_NT=$?
if [[ $RC_NT -eq 0 ]]; then ok "typos-absent -> exit 0"; else fail "typos-absent exit $RC_NT"; fi
if jq -e '(.systemMessage | contains("typos")) and (.hookSpecificOutput.additionalContext | contains("PATH"))' <<<"$OUT_NT" >/dev/null 2>&1; then
  ok "typos-absent -> visible notice on both channels"
else
  fail "typos-absent: notice missing or malformed: $OUT_NT"
fi
OUT_NT2=$(run_nt)
if [[ -z "$OUT_NT2" ]]; then
  ok "typos-absent -> second run same session is silent (once-per-session)"
else
  fail "typos-absent second run not silent: $OUT_NT2"
fi

# jq-absent -> visible once-per-session notice (input parsing gate).
rm -f "$FAKEBIN/jq"
JQ_DATA="$(mktemp -d "$WORK/plugdata.XXXXXX")"
OUT_NOJQ=$(
  cd "$UNRELATED" || exit 1
  printf '{"session_id":"test-nojq-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO_NT/app.txt" |
    env -u CLAUDE_PROJECT_DIR PATH="$FAKEBIN" CLAUDE_PLUGIN_DATA="$JQ_DATA" \
      CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true bash "$HOOK"
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
