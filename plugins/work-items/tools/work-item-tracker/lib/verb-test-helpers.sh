# shellcheck shell=bash
# Shared assertions for adapter verb *.test.sh files. Sourced, never run
# directly (runner ignores non-*.test.sh). Each verb test asserts the
# skill-script contract (--help exits 0 with non-empty stdout) plus one
# offline usage-error path (bad args exit 2 before any provider I/O).
set -uo pipefail

: "${FAILED:=0}"
: "${CASE_NUM:=0}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../tests/lib.sh"

# assert_help <script> — --help exits 0 with non-empty stdout.
assert_help() {
  local script="$1" name out rc
  name="$(basename "$script")"
  out="$(bash "$script" --help 2>/dev/null)"
  rc=$?
  assert_eq "$name --help exit 0" "0" "$rc"
  if [[ -n "$out" ]]; then
    pass "$name --help non-empty stdout"
  else
    fail "$name --help non-empty stdout" "non-empty" "empty"
  fi
}

# assert_usage_error <script> <args…> — the invocation exits 2 (usage).
assert_usage_error() {
  local script="$1"
  shift
  local name rc
  name="$(basename "$script")"
  bash "$script" "$@" >/dev/null 2>&1
  rc=$?
  assert_eq "$name usage error → exit 2" "2" "$rc"
}
