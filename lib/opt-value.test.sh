#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fails=0
check() {
  local name="$1" want="$2" want_err="$3" err code
  shift 3
  local -a env=()
  while [[ "$1" != -- ]]; do
    env+=("$1")
    shift
  done
  shift
  # shellcheck disable=SC2016  # the child shell expands its own arguments
  err="$(env ${env[@]+"${env[@]}"} bash -c '. "$1" && shift && require_opt_value "$@" && echo ok' _ "$HERE/opt-value.sh" "$@" 2>&1 >/dev/null)"
  code=$?
  if [[ "$code" == "$want" && "$err" == "$want_err" ]]; then
    echo "PASS: $name"
  else
    echo "FAIL: $name (exit $code, stderr '$err')" >&2
    fails=1
  fi
}

check "a value passes" 0 "" -- s.sh --out file
check "a value with spaces passes" 0 "" -- s.sh --out "a b"
check "no value fails" 2 "s.sh: --out requires a value" -- s.sh --out
check "an empty value fails" 2 "s.sh: --out requires a value" -- s.sh --out ""
check "a flag as the value fails" 2 "s.sh: --out requires a value" -- s.sh --out --max
check "a negative number fails" 2 "s.sh: --max requires a value" -- s.sh --max -1
check "a lone dash fails by default" 2 "s.sh: --report requires a value" -- s.sh --report -
check "a lone dash passes with OPT_VALUE_STDIN" 0 "" OPT_VALUE_STDIN=1 -- s.sh --report -
check "OPT_VALUE_STDIN admits only a lone dash" 2 "s.sh: --report requires a value" OPT_VALUE_STDIN=1 -- s.sh --report --x
check "OPT_VALUE_EXIT sets the exit code" 3 "s.sh: --ledger requires a value" OPT_VALUE_EXIT=3 -- s.sh --ledger
check "only the first value is judged" 0 "" -- s.sh --out file --max

exit "$fails"
