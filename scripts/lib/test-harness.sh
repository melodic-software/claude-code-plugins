# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf 'scripts/lib/test-harness.sh is sourced-only\n' >&2
  exit 2
fi

if [[ -n "${TEST_HARNESS_SOURCED:-}" ]]; then
  return 0
fi
TEST_HARNESS_SOURCED=1

_test_harness_pass=0
_test_harness_fail=0

ok() {
  printf 'ok: %s\n' "$*"
  _test_harness_pass=$((_test_harness_pass + 1))
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  _test_harness_fail=$((_test_harness_fail + 1))
}

pass() { ok "$1"; }
bad() { fail "$1${2:+: $2}"; }

assert_output_contains() {
  local name="$1" needle="$2"
  if [[ "$LAST_OUTPUT" == *"$needle"* ]]; then
    pass "$name"
  else
    bad "$name" "expected output to contain '$needle'; got: $LAST_OUTPUT"
  fi
}

test_harness::run_guard() {
  local expected="$1" name="$2" script="$3" program="$4"
  shift 4
  local status
  LAST_OUTPUT="$(
    env -i \
      PATH="$PATH" \
      HOME="${HOME:-/tmp}" \
      "$@" \
      bash -c "$program" harness "$script" 2>&1
  )"
  status=$?
  if [[ "$status" -eq "$expected" ]]; then
    pass "$name"
    return 0
  fi
  bad "$name" "expected exit $expected, got $status; output: $LAST_OUTPUT"
  return 1
}

test_harness::check_case() {
  local _th_build="$1" _th_script="$2" label="$3" expected="$4" setup="$5"
  shift 5
  local tree out rc s
  "$_th_build" tree || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$tree" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  out="$(bash "$tree/scripts/$_th_script" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$out"; then
      fail "$label: '$s' not named in output: $out"
      return
    fi
  done
  ok "$label"
}

test_harness::assert_discover_quiet() {
  local stdout rc
  stdout="$(bash "$1" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 1 && -z "$stdout" ]]; then
    ok "discover mode exits 1 with nothing on stdout"
  else
    fail "discover mode should exit 1 with an empty stdout (rc=$rc): $stdout"
  fi
}

test_harness::assert_unknown_mode() {
  local rc
  bash "$1" --bogus >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 2 ]]; then
    ok "unknown mode exits 2"
  else
    fail "unknown mode should exit 2 (rc=$rc)"
  fi
}

test_harness::report() {
  printf 'PASS=%d FAIL=%d\n' "$_test_harness_pass" "$_test_harness_fail"
  if ((_test_harness_fail > 0)); then
    return 1
  fi
  return 0
}
