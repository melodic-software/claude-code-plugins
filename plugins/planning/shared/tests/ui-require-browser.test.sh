#!/usr/bin/env bash
# ui-run.sh passes a browser skip locally and fails it under CI=true, and refuses to run a part until every
# ui_*.js beside it is in exactly one part that has its ui-<part>.test.sh. It runs here against copies of
# ui-run.sh and ui-a.test.sh in a throwaway folder holding stub suites, the first printing the skip line a
# browser-less machine produces, and the part check also runs on the live ui-parts.txt.
# test-scope: plugins/planning/shared/tests/ui-parts.txt plugins/planning/shared/tests/ui-*.test.sh
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
cp "$here/ui-run.sh" "$here/ui-a.test.sh" "$tmp/"
pass=0 failed=0
check() { # <name> <expected exit> <actual exit>
  if [[ $2 == "$3" ]]; then
    pass=$((pass + 1))
    echo "PASS $1"
  else
    failed=$((failed + 1))
    echo "FAIL $1 (exit $3, wanted $2)"
  fi
}
run() { env -u CI "$@" bash "$tmp/ui-a.test.sh" >/dev/null 2>&1; }

bash "$here/ui-run.sh" --check
check "every ui_*.js beside ui-run.sh is in exactly one part, and each part has its wrapper" 0 $?

echo 'ui_stub.js a' >"$tmp/ui-parts.txt"
echo 'console.log("SKIP: no Chromium to launch (stub)");' >"$tmp/ui_stub.js"
run
check "a missing Chromium skips green on a local run" 0 $?
run CI=true
check "a missing Chromium fails under CI=true" 1 $?

echo 'console.log("SKIP: ui_stub.js needs playwright-core (stub)");' >"$tmp/ui_stub.js"
run CI=true
check "a missing playwright-core fails under CI=true" 1 $?

echo 'console.log("PASS stub");' >"$tmp/ui_stub.js"
run CI=true
check "a suite that ran passes under CI=true" 0 $?

echo 'console.log("PASS other");' >"$tmp/ui_other.js"
run CI=true
check "a suite in no part fails the run" 2 $?

printf 'ui_stub.js a\nui_other.js a\nui_other.js a\n' >"$tmp/ui-parts.txt"
run CI=true
check "a suite in two rows fails the run" 2 $?

printf 'ui_stub.js a\nui_other.js b\n' >"$tmp/ui-parts.txt"
run CI=true
check "a part with no ui-<part>.test.sh fails the run" 2 $?

printf 'ui_stub.js a\nui_other.js a\nui_gone.js a\n' >"$tmp/ui-parts.txt"
run CI=true
check "a row naming no suite beside it fails the run" 2 $?

echo "ui-require-browser: $pass passed, $failed failed"
((failed == 0))
