# shellcheck shell=bash
# Self-contained assertion library for the work-item-tracker seam's *.test.sh
# files. The seam ships with its own harness so its tests run unchanged wherever
# the seam is resolved from — the plugin's bundled copy or a consumer-vendored
# copy — with no dependency on the host repo's test tooling.
#
# Source it from any seam test, CWD-independent, relative to the test's own
# location (never via git toplevel — the host repo is not the seam's repo):
#   source "$SCRIPT_DIR/../tests/lib.sh"
#
# Each test file owns its own FAILED and CASE_NUM counters; helpers increment
# them in the caller's scope. PASS lines go to stdout, FAIL lines to stderr.
# Test files exit non-zero at the end:  [[ $FAILED -eq 0 ]] || exit 1
#
# Duplicated across plugins by design, not drift — see
# docs/conventions/shell-test-helpers/README.md at the repo root.

[[ -n "${_WIT_TESTS_LIB_LOADED:-}" ]] && return 0
readonly _WIT_TESTS_LIB_LOADED=1

# Strip any inherited git-hook context so a test that builds a git fixture can
# never resolve to the real repo instead of its throwaway dir (a git hook chain
# exports GIT_DIR / GIT_INDEX_FILE etc.; leaving them set has rewritten a real
# repo's refs in the past). Every seam test gets a clean git environment.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

# Defensive counter defaults so the first assertion in a test that forgot to
# declare them does not trip `set -u`.
: "${FAILED:=0}"
: "${CASE_NUM:=0}"

# pass <label> — print a PASS line, increment CASE_NUM. No exit.
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}

# fail <label> <expected> <actual> — print a FAIL line to stderr, increment
# FAILED + CASE_NUM. No exit (run-all-cases discipline; the final check exits).
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' \
    "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}

# skip_suite <reason> — print a SKIP marker and exit 0. Use when a test cannot
# run ANY of its cases (missing toolchain, wrong platform).
skip_suite() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
}

# assert_eq <label> <expected> <actual> — exact match.
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

# assert_succeeds <label> <expected> <actual> <command...>: the command must exit 0.
# The command's stdout is discarded so the PASS/FAIL line stays the only stdout of
# the case; its stderr is left alone, so a diagnostic the case does not assert on
# still reaches the log. <expected>/<actual> are the words the FAIL line reports.
assert_succeeds() {
  local label="$1" expected="$2" actual="$3"
  shift 3
  if "$@" >/dev/null; then
    pass "$label"
  else
    fail "$label" "$expected" "$actual"
  fi
}

# assert_fails <label> <expected> <actual> <command...>: the command must exit
# non-zero. Same stdout/stderr handling as assert_succeeds.
assert_fails() {
  local label="$1" expected="$2" actual="$3"
  shift 3
  if "$@" >/dev/null; then
    fail "$label" "$expected" "$actual"
  else
    pass "$label"
  fi
}

# assert_contains <label> <haystack> <needle> — substring match.
assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$label"
  else
    CASE_NUM=$((CASE_NUM + 1))
    printf 'FAIL: [%d] %s — expected %q in: %s\n' \
      "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

# assert_not_contains <label> <haystack> <needle> — substring absence.
assert_not_contains() {
  local label="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$label"
  else
    CASE_NUM=$((CASE_NUM + 1))
    printf 'FAIL: [%d] %s — forbidden %q present in: %s\n' \
      "$CASE_NUM" "$label" "$needle" "$haystack" >&2
    FAILED=$((FAILED + 1))
  fi
}

# write_blocking_network_shim <dir>: install gh and curl stubs in <dir> that print
# a blocked notice on stderr and exit 1. Put <dir> first on PATH to prove a code
# path never reaches for a network tool (no unshare -n on Git Bash).
write_blocking_network_shim() {
  local dir="$1"
  # shellcheck disable=SC2016  # shim body is literal by design: $(basename) evaluates at shim runtime, not here
  printf '#!/usr/bin/env bash\necho "blocked: $(basename "$0")" >&2\nexit 1\n' >"$dir/gh"
  cp "$dir/gh" "$dir/curl"
  chmod +x "$dir/gh" "$dir/curl"
}
