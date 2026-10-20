#!/usr/bin/env bash
# ui.test.sh passes a browser skip locally and fails it under CI=true. It runs here against a copy in a
# throwaway folder holding one stub suite that prints the skip line a browser-less machine produces.
# test-scope: plugins/planning/shared/tests/ui.test.sh
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
cp "$here/ui.test.sh" "$tmp/ui.test.sh"
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
run() { env -u CI "$@" bash "$tmp/ui.test.sh" >/dev/null 2>&1; }

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

echo "ui-require-browser: $pass passed, $failed failed"
((failed == 0))
