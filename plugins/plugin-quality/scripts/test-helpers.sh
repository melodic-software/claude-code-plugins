# shellcheck shell=bash

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

  norm() {
    # shellcheck disable=SC2312  # the suites that source this file set pipefail, so no stage's status is masked
    tr -d '`*' <"$1" | tr '\n' ' ' | tr -s ' '
  }

  require_readable() {
    local f
    for f in "$@"; do
      if [[ ! -r "$f" ]]; then
        echo "FAIL: required file missing or unreadable: $f" >&2
        exit 1
      fi
    done
  }

  drift_report() {
    echo
    echo "PASS=$PASS FAIL=$FAIL"
    [[ $FAIL -eq 0 ]]
  }
}

test_helpers::contract_lane() {
  fails=0
  last_out=""

  pass() { printf 'ok   - %s\n' "$1"; }

  fail() {
    printf 'FAIL - %s\n' "$1" >&2
    fails=$((fails + 1))
  }

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

  has() {
    if [[ "$last_out" == *"$1"* ]]; then
      pass "$2"
    else
      fail "$2 — output was: $last_out"
    fi
  }

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
