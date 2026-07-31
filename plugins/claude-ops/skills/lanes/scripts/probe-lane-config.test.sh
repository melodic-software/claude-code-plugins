#!/usr/bin/env bash
# Regression tests for probe-lane-config.sh.
#
# The script exists only to reproduce, from a bundled file, what a pre-compute
# line used to compute inline (#1687). So every case asserts TWO things: the
# script's output against the expected literal, and the script's output against
# the ORIGINAL inline one-liner run in the same environment. The second assertion
# is the one that matters — it is the byte-for-byte equivalence claim, checked
# rather than reasoned about, and it stays honest whatever jq the host ships.
#
# Coverage:
#   - CLAUDE_OPS_LANES_CONFIG override: used verbatim, no `.work/lanes.json`
#     suffix appended; an EMPTY value falls through to the default
#   - default path from the git toplevel, and from the working directory when
#     not inside a repo
#   - a CRLF-terminated git toplevel does not leak a stray CR into the path
#   - present config → `<path> (<N> lanes)`; `.lanes` absent → `0 lanes`
#   - unavailable count (jq missing / malformed JSON) degrades to `( lanes)`
#     rather than erroring
#   - absent config → the `absent (<path>) — author one …` line, em dash intact
#   - argument validation exit code
#
# PATH-stubs `git` so no real repository state is touched, and stubs a
# not-found `jq` for the degradation case (empty stdout + nonzero status is
# exactly what an absent binary produces once stderr is suppressed).
#
# Every case runs in THIS shell, never a `( … )` subshell: an assertion inside a
# subshell increments a copy of the failure counter and the run would report
# green with a failing case in it. Environment scoping is therefore explicit
# set/unset around each case rather than subshell containment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/probe-lane-config.sh"
START_DIR="$PWD"
TMP="$(mktemp -d)"
trap 'cd "$START_DIR" 2>/dev/null; rm -rf "$TMP"' EXIT

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s\n      expected: %q\n      got:      %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }

# --- The pre-compute line this script replaced, verbatim ---------------------
ORIGINAL="$TMP/original.sh"
cat >"$ORIGINAL" <<'ORIG'
c="${CLAUDE_OPS_LANES_CONFIG:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.work/lanes.json}"; [[ -f "$c" ]] && echo "$c ($(jq -r '(.lanes//[])|length' "$c" 2>/dev/null) lanes)" || echo "absent ($c) — author one (see context/config.md)"
ORIG

# --- Stubs -------------------------------------------------------------------
STUB="$TMP/stub"
mkdir -p "$STUB"
cat >"$STUB/git" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--show-toplevel" ]]; then
  if [[ -n "${STUB_GIT_TOPLEVEL:-}" ]]; then
    if [[ -n "${STUB_GIT_CRLF:-}" ]]; then
      printf '%s\r\n' "$STUB_GIT_TOPLEVEL"
    else
      printf '%s\n' "$STUB_GIT_TOPLEVEL"
    fi
    exit 0
  fi
  printf 'fatal: not a git repository\n' >&2
  exit 128
fi
exit 0
SH
chmod +x "$STUB/git"

NOJQ="$TMP/nojq"
mkdir -p "$NOJQ"
cat >"$NOJQ/jq" <<'SH'
#!/usr/bin/env bash
printf 'bash: jq: command not found\n' >&2
exit 127
SH
chmod +x "$NOJQ/jq"

BASE_PATH="$STUB:$PATH"
export PATH="$BASE_PATH"

# --- Fixtures ----------------------------------------------------------------
ROOT="$TMP/repo"
mkdir -p "$ROOT/.work"
cat >"$ROOT/.work/lanes.json" <<'JSON'
{ "lanes": [ { "name": "a" }, { "name": "b" }, { "name": "c" } ] }
JSON

NO_LANES_KEY="$TMP/no-lanes-key.json"
cat >"$NO_LANES_KEY" <<'JSON'
{ "other": true }
JSON

MALFORMED="$TMP/malformed.json"
cat >"$MALFORMED" <<'JSON'
{ "lanes": [ this is not json
JSON

ELSEWHERE="$TMP/elsewhere"
mkdir -p "$ELSEWHERE/.work"

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# run_both <label> <expected-literal|SKIP> — runs the script and the original
# one-liner in the CURRENT environment and asserts both.
#
# The original's output is CR-stripped before comparison, and that is the ONE
# deliberate divergence between the two: some native-Windows jq builds
# CRLF-terminate their output, `$(…)` strips only the trailing LF, and the
# original line therefore embedded a stray CR mid-string on those hosts. The
# script routes the count through `tr -d '\r'` per this directory's standing
# convention (machine-behavior.sh). Comparing raw would make this suite fail on
# exactly the hosts the CR-strip exists to fix, so the normalization is applied
# to the original rather than the divergence being hidden.
run_both() {
  local label="$1" expected="$2" got orig
  got="$(bash "$SCRIPT" 2>/dev/null)"
  orig="$(bash "$ORIGINAL" 2>/dev/null | tr -d '\r')"
  [[ "$expected" == "SKIP" ]] || assert_eq "$label" "$expected" "$got"
  assert_eq "$label (matches the original inline line, modulo the CR-strip)" "$orig" "$got"
}

# --- 1. Env override, present config -----------------------------------------
export STUB_GIT_TOPLEVEL="$ROOT"
export CLAUDE_OPS_LANES_CONFIG="$ROOT/.work/lanes.json"
if ((HAVE_JQ)); then
  run_both "override → present config with a lane count" "$ROOT/.work/lanes.json (3 lanes)"
else
  run_both "override → present config (jq absent; equivalence only)" "SKIP"
fi

# --- 2. Env override used verbatim (no .work/lanes.json suffix appended) ------
export CLAUDE_OPS_LANES_CONFIG="$TMP/nowhere.json"
run_both "override is used verbatim when the file is absent" \
  "absent ($TMP/nowhere.json) — author one (see context/config.md)"

# --- 3. Empty override falls through to the default --------------------------
export CLAUDE_OPS_LANES_CONFIG=""
if ((HAVE_JQ)); then
  run_both "empty override falls through to <toplevel>/.work/lanes.json" \
    "$ROOT/.work/lanes.json (3 lanes)"
else
  run_both "empty override falls through (jq absent; equivalence only)" "SKIP"
fi
unset CLAUDE_OPS_LANES_CONFIG

# --- 4. Default path from the git toplevel -----------------------------------
export STUB_GIT_TOPLEVEL="$ELSEWHERE"
run_both "default resolves under the git toplevel" \
  "absent ($ELSEWHERE/.work/lanes.json) — author one (see context/config.md)"

# --- 5. A CRLF-terminated toplevel leaves no stray CR in the path ------------
export STUB_GIT_CRLF=1
assert_eq "CRLF toplevel is stripped" \
  "absent ($ELSEWHERE/.work/lanes.json) — author one (see context/config.md)" \
  "$(bash "$SCRIPT" 2>/dev/null)"
unset STUB_GIT_CRLF

# --- 6. Not inside a repo → the working directory ----------------------------
unset STUB_GIT_TOPLEVEL
cd "$ELSEWHERE" || exit 1
run_both "not in a repo → default resolves under the working directory" \
  "absent ($ELSEWHERE/.work/lanes.json) — author one (see context/config.md)"
cd "$START_DIR" || exit 1

# --- 7. `.lanes` absent from the config, and malformed JSON ------------------
export STUB_GIT_TOPLEVEL="$ROOT"
if ((HAVE_JQ)); then
  export CLAUDE_OPS_LANES_CONFIG="$NO_LANES_KEY"
  run_both "config without a .lanes key counts 0" "$NO_LANES_KEY (0 lanes)"
  export CLAUDE_OPS_LANES_CONFIG="$MALFORMED"
  run_both "malformed config degrades the count to empty" "$MALFORMED ( lanes)"
  unset CLAUDE_OPS_LANES_CONFIG
else
  printf 'SKIP: jq absent — real-count cases not exercised\n'
fi

# --- 8. jq missing → the count degrades to empty, not an error ---------------
export PATH="$NOJQ:$BASE_PATH"
export CLAUDE_OPS_LANES_CONFIG="$ROOT/.work/lanes.json"
run_both "jq missing degrades the count to empty" "$ROOT/.work/lanes.json ( lanes)"
unset CLAUDE_OPS_LANES_CONFIG
export PATH="$BASE_PATH"

# --- 9. Argument validation ---------------------------------------------------
out="$(bash "$SCRIPT" --bogus 2>&1)"
rc=$?
assert_eq "unknown argument exits 3" "3" "$rc"
case "$out" in
*"unknown argument: --bogus"*) pass "unknown argument is named on stderr" ;;
*) fail "unknown argument is named on stderr" "unknown argument: --bogus" "$out" ;;
esac

bash "$SCRIPT" --help >/dev/null 2>&1
assert_eq "--help exits 0" "0" "$?"

if [[ $FAILED -eq 0 ]]; then
  printf '\nAll %d cases passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d of %d cases FAILED.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
