# shellcheck shell=bash
# test-helpers.sh: the assertion primitives, stub-PATH builder and exit report
# shared by this skill's *.test.sh suites. Sourced, not executed; the runner's
# *.test.sh glob never picks it up.
#
# Provides the FAILED / CASE_NUM counters, pass / fail, the four assert_*
# primitives, count_matching, make_stub_path and report_and_exit. PASS lines go
# to stdout, FAIL lines to stderr, and a suite's last line is report_and_exit so
# its exit status is 0 only when nothing failed.
#
# Duplicated per plugin by design, not drift. See
# docs/conventions/shell-test-helpers/README.md at the repo root.

FAILED=0
CASE_NUM=0

# The interpreter's own absolute path. A stub PATH that takes one tool away must
# not take bash away with it, so suites invoke "$real_bash" explicitly.
real_bash="$(command -v bash)"

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
count_matching() { printf '%s\n' "$1" | grep -cE "$2"; }

# make_stub_path <dir> <tool>...: a PATH directory holding one wrapper per named
# tool, so a case can withhold a single tool rather than all of them. A bare
# PATH= makes the interpreter itself unresolvable (exit 127, "command not
# found"), which would "pass" for a reason unrelated to the tool under test.
#
# Each entry execs the real binary at its absolute path, deliberately NOT a
# copy: an MSYS binary copied out of /usr/bin loses the msys-2.0.dll sitting
# beside it and fails to start, which would make a case "pass" by breaking every
# tool instead of the one under test. A tool that is not on PATH is left out.
make_stub_path() {
  local dir="$1" tool src
  shift
  mkdir -p "$dir"
  for tool in "$@"; do
    src="$(command -v "$tool" 2>/dev/null)" || continue
    printf '#!%s\nexec "%s" "$@"\n' "$real_bash" "$src" >"$dir/$tool"
    chmod +x "$dir/$tool"
  done
}

# report_and_exit: the suite's last line. Totals to stdout when everything
# passed, to stderr otherwise, then the suite's exit status.
report_and_exit() {
  if [[ "$FAILED" -eq 0 ]]; then
    printf '\nAll %d checks passed.\n' "$CASE_NUM"
    exit 0
  fi
  printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
  exit 1
}
