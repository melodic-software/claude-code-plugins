#!/usr/bin/env bash
set -uo pipefail
here=$(dirname "${BASH_SOURCE[0]}")
export AFFECTED_TESTS_ROOT=${AFFECTED_TESTS_ROOT:-$PWD}
select=${RUN_COVERING_TESTS_SELECT:-$here/affected-tests.sh}
run=${RUN_COVERING_TESTS_RUN:-$here/run-test-file.sh}

[[ "$#" -eq 1 ]] || {
  echo "usage: run-covering-tests.sh <source file>" >&2
  exit 2
}
if ! selection=$(bash "$select" "$1"); then
  echo "no covering suite: the selection for '$1' failed" >&2
  exit 2
fi
mapfile -t suites < <(grep -v '^$' <<<"$selection")
[[ ${#suites[@]} -gt 0 ]] || {
  echo "no covering suite selects '$1'" >&2
  exit 2
}
failed=0
for suite in "${suites[@]}"; do
  if bash "$run" "$suite" >/dev/null 2>&1; then
    echo "PASS $suite"
  else
    echo "FAIL $suite (exit $?)"
    failed=$((failed + 1))
  fi
done
echo "covering suites: ${#suites[@]}, failed: $failed"
[[ $failed -eq 0 ]]
