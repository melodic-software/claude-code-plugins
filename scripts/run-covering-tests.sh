#!/usr/bin/env bash
# Runs every suite that covers one source file, in one command:
#
#   scripts/run-covering-tests.sh <source file>
#
# scripts/affected-tests.sh selects the suites; each runs through
# scripts/run-test-file.sh, which picks its runner and drops GH_TOKEN and
# GITHUB_TOKEN. One line per suite on stdout, `PASS <suite>` or
# `FAIL <suite> (exit <n>)`, then `covering suites: <n>, failed: <m>`.
# Exits 0 when every suite passed, 1 when any failed, 2 when the file has no
# covering suite or the selection itself failed. The post-merge mutation lane
# runs it once per mutant, so a kill is any failing suite.
set -uo pipefail
here=$(dirname "${BASH_SOURCE[0]}")
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
  bash "$run" "$suite" >/dev/null 2>&1
  status=$?
  if [[ $status -eq 0 ]]; then
    echo "PASS $suite"
  else
    echo "FAIL $suite (exit $status)"
    failed=$((failed + 1))
  fi
done
echo "covering suites: ${#suites[@]}, failed: $failed"
[[ $failed -eq 0 ]]
