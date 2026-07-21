#!/usr/bin/env bash
# Black-box contract test for typos-format.sh (the typos-format plugin hook).
#
# Proves WIRING: the hook fires on any file (no extension filter), gates on a
# consumer typos config (present -> run, absent -> leave bytes untouched),
# honors typos.toml > _typos.toml > .typos.toml > Cargo.toml > pyproject.toml
# precedence, applies typos' safe corrections in place, surfaces residual
# (unfixable) findings via additionalContext with remediation guidance,
# honors the kill switch, and emits a schema-valid telemetry envelope.
#
# Self-contained: builds throwaway git repos with runtime-generated fixtures.
# The hook is invoked from an UNRELATED cwd so any reliance on the caller's
# working directory would surface (typos' config discovery is CWD-anchored;
# the hook cd's to the repo root before running).
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

# Resolve a real typos binary. Skip the suite when none is available.
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
run_hook() {
  local file_path="$1"
  (
    cd "$UNRELATED" || return 1
    printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
      env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true PATH="$(dirname "$REAL_TYPOS"):$PATH" bash "$HOOK"
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

# --- Case 1: opt-in gate OFF (no typos config) -> file left untouched -------
# A repo with typos installed but NO config must not have its files checked
# against typos' built-in dictionary.
REPO_NO="$WORK/no-config"
new_typos_repo "$REPO_NO" NO_CONFIG
printf 'this has teh typo\n' >"$REPO_NO/doc.txt" # spellchecker:disable-line
BEFORE_NO="$(cat "$REPO_NO/doc.txt")"
OUT=$(run_hook "$REPO_NO/doc.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "gate OFF (no config) -> exit 0, silent"; else fail "gate OFF not silent (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_NO/doc.txt")" == "$BEFORE_NO" ]]; then ok "gate OFF -> file left untouched"; else fail "gate OFF -> file was rewritten"; fi

# --- Case 1b: pyproject.toml WITHOUT [tool.typos] does NOT opt in -----------
REPO_PP="$WORK/pyproject-plain"
new_typos_repo "$REPO_PP" NO_CONFIG
printf '[project]\nname = "t"\n' >"$REPO_PP/pyproject.toml"
printf 'this has teh typo\n' >"$REPO_PP/plain.txt" # spellchecker:disable-line
BEFORE_PP="$(cat "$REPO_PP/plain.txt")"
OUT=$(run_hook "$REPO_PP/plain.txt")
RC=$?
if [[ $RC -eq 0 && -z "$OUT" ]]; then ok "pyproject without [tool.typos] -> exit 0, silent (no opt-in)"; else fail "plain pyproject opted in (rc=$RC out=$OUT)"; fi
if [[ "$(cat "$REPO_PP/plain.txt")" == "$BEFORE_PP" ]]; then ok "pyproject without [tool.typos] -> file left untouched"; else fail "plain pyproject -> file was rewritten"; fi

# --- Case 1c: pyproject.toml WITH [tool.typos] opts in ----------------------
REPO_PT="$WORK/pyproject-typos"
new_typos_repo "$REPO_PT" NO_CONFIG
printf '[project]\nname = "t"\n\n[tool.typos]\n' >"$REPO_PT/pyproject.toml"
printf 'this has teh typo\n' >"$REPO_PT/opt.txt" # spellchecker:disable-line
OUT=$(run_hook "$REPO_PT/opt.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "pyproject with [tool.typos] -> exit 0"; else fail "pyproject opt-in exit $RC"; fi
if grep -q ' the ' "$REPO_PT/opt.txt"; then ok "pyproject with [tool.typos] -> file fixed"; else fail "pyproject opt-in -> not fixed: $(cat "$REPO_PT/opt.txt")"; fi

# --- Case 1d: typos.toml takes precedence over _typos.toml in the same dir --
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

# --- Case 2: gate ON + clean file -> exit 0, empty stdout -------------------
REPO="$WORK/consumer"
new_typos_repo "$REPO"
printf 'this is a clean document\n' >"$REPO/clean.txt"
OUT=$(run_hook "$REPO/clean.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "clean file -> exit 0"; else fail "clean file exit $RC"; fi
if [[ -z "$OUT" ]]; then ok "clean file -> empty stdout"; else fail "clean file stdout not empty: $OUT"; fi

# --- Case 3: gate ON + fixable typo -> autofixed in place -------------------
mkdir -p "$REPO/src"
printf 'this has teh typo\n' >"$REPO/src/fix.txt" # spellchecker:disable-line
OUT=$(run_hook "$REPO/src/fix.txt")
RC=$?
if [[ $RC -eq 0 ]]; then ok "fixable typo -> exit 0 (advisory)"; else fail "fixable typo exit $RC"; fi
if grep -q ' the ' "$REPO/src/fix.txt"; then
  ok "gate ON (subdir file) -> typos autofixed"
else
  fail "gate ON -> file not fixed: $(cat "$REPO/src/fix.txt")"
fi

# --- Case 3b: config nested BELOW repo root (root itself has no config) -----
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

# --- Case 4: gate ON + unfixable finding -> advisory context with remediation
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

# --- Case 4b: fixable + unfixable together -> fixable applied, unfixable reported
printf 'this has teh typo and a disallowme term\n' >"$REPO/mixed.txt" # spellchecker:disable-line
OUT=$(run_hook "$REPO/mixed.txt")
if grep -q ' the ' "$REPO/mixed.txt" && grep -q 'disallowme' "$REPO/mixed.txt"; then
  ok "mixed fixable+unfixable -> fixable applied, unfixable left in place"
else
  fail "mixed case wrong: $(cat "$REPO/mixed.txt")"
fi
CTX_MIXED=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
FIXED_TYPO='teh' # spellchecker:disable-line
if printf '%s' "$CTX_MIXED" | grep -q 'disallowme' && ! printf '%s' "$CTX_MIXED" | grep -qF "\"$FIXED_TYPO\""; then
  ok "mixed fixable+unfixable -> only unfixable reported (fixed typo absent)"
else
  fail "mixed case: reporting wrong: $CTX_MIXED"
fi

# --- Case 5: config excludes the edited file -> untouched, no nag ------------
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

# --- Case 6: kill switch bypasses hook ---------------------------------------
printf 'this has teh typo\n' >"$REPO/kill.txt" # spellchecker:disable-line
BEFORE_K="$(cat "$REPO/kill.txt")"
OUT=$(run_hook_env "$REPO/kill.txt" PATH="$(dirname "$REAL_TYPOS"):$PATH" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=false)
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

# --- Stub sink + gate OFF -> status skipped -----------------------------------
printf 'this has teh typo\n' >"$REPO_NO/tel2.txt" # spellchecker:disable-line
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_hook_env "$REPO_NO/tel2.txt" PATH="$(dirname "$REAL_TYPOS"):$PATH" CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS"
if [[ -s "$TELS" ]]; then
  if [[ "$(jq -r '.status' "$TELS")" == "skipped" ]]; then ok "telemetry/gate-off: status skipped"; else fail "telemetry/gate-off: status=$(jq -r '.status' "$TELS")"; fi
  if [[ "$(jq '.data.findings | length' "$TELS")" -eq 0 ]]; then ok "telemetry/gate-off: findings empty array"; else fail "telemetry/gate-off: findings not empty"; fi
else
  fail "telemetry/gate-off: no envelope written"
fi
rm -f "$TELS"

# --- Missing-tool visibility (dim-9 doctrine) --------------------------------
# Fake-bin dir of exec wrappers (no typos): a repo with a governing typos
# config but no binary must produce a visible once-per-session skip notice on
# both channels, silent on the second run. jq removal then exercises the
# input-parsing gate.
FAKEBIN="$(mktemp -d -p "$WORK" fakebin.XXXXXX)"
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
NT_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
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
if jq -e '(.systemMessage | contains("typos")) and (.hookSpecificOutput.additionalContext | contains("typos config"))' <<<"$OUT_NT" >/dev/null 2>&1; then
  ok "typos-absent with governing config -> visible notice on both channels"
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
JQ_DATA="$(mktemp -d -p "$WORK" plugdata.XXXXXX)"
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
