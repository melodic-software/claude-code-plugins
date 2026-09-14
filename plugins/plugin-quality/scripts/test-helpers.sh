# shellcheck shell=bash
# test-helpers.sh - assertion primitives for this plugin's *.test.sh suites.
# Sourced, not executed; the plugin test runner collects *.test.sh only.
#
# Two lane shapes live here, and a suite calls exactly ONE initializer. The
# initializer defines that shape's primitives and its counters as globals:
#
#   test_helpers::drift_lane     ok / fail / norm / require_readable /
#                                drift_report, with the PASS and FAIL counters.
#                                The shape for lanes that assert load-bearing
#                                phrases across prose surfaces.
#   test_helpers::contract_lane  pass / fail / run / has / contract_report, with
#                                the fails counter and last_out. The shape for
#                                black-box lanes that invoke $SUT and assert its
#                                exit code and output.
#
# The two reporters carry the shape in their name because both shapes are
# visible to a reader (and to shellcheck) of this one file at once.
#
# The two shapes keep separate wording and separate counters on purpose: each
# suite's own lines are a contract its readers and this repo's lanes rely on.
#
# Duplicated across plugins by design, not drift - see
# docs/conventions/shell-test-helpers/README.md at the repo root.

# test_helpers::drift_lane - phrase-drift assertion shape.
# shellcheck disable=SC2329  # the primitives below are invoked by the suite that sources this file, never here
test_helpers::drift_lane() {
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

  # norm <file> - drop markdown emphasis/backticks, flatten all whitespace runs.
  norm() {
    # shellcheck disable=SC2312  # the suites that source this file set pipefail, so no stage's status is masked
    tr -d '`*' <"$1" | tr '\n' ' ' | tr -s ' '
  }

  # require_readable <file>... - a surface this lane reads must be there.
  require_readable() {
    local f
    for f in "$@"; do
      if [[ ! -r "$f" ]]; then
        echo "FAIL: required file missing or unreadable: $f" >&2
        exit 1
      fi
    done
  }

  # drift_report - final tally. Call it LAST: its status is the suite's exit status.
  drift_report() {
    echo
    echo "PASS=$PASS FAIL=$FAIL"
    [[ $FAIL -eq 0 ]]
  }
}

# test_helpers::contract_lane - black-box script-under-test shape. The suite
# sets $SUT to the script under test before the first `run`.
test_helpers::contract_lane() {
  fails=0
  last_out=""

  pass() { printf 'ok   - %s\n' "$1"; }

  fail() {
    printf 'FAIL - %s\n' "$1" >&2
    fails=$((fails + 1))
  }

  # run <expected-exit> <label> [args...] - captures output into last_out for reuse.
  run() {
    local expected="$1" label="$2"
    shift 2
    local actual
    # shellcheck disable=SC2154  # SUT is the sourcing suite's, set before the first run
    last_out="$(bash "$SUT" "$@" 2>&1)"
    actual=$?
    if [[ "$actual" -eq "$expected" ]]; then
      pass "$label (exit $actual)"
    else
      fail "$label — expected exit $expected, got $actual: $last_out"
    fi
  }

  # has <phrase> <label> - the last run's combined output carries <phrase>.
  has() {
    if [[ "$last_out" == *"$1"* ]]; then
      pass "$2"
    else
      fail "$2 — output was: $last_out"
    fi
  }

  # contract_report <script-name> - final tally; exits the suite.
  contract_report() {
    echo
    if [[ $fails -eq 0 ]]; then
      echo "all $1 contract tests passed"
      exit 0
    fi
    echo "$fails $1 contract test(s) failed" >&2
    exit 1
  }
}
