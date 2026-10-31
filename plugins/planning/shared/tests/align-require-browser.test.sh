#!/usr/bin/env bash
# align.test.sh passes a browser skip locally and fails it under CI=true. It runs here against a copy of
# align.test.sh in a throwaway folder beside a stub align.js that prints the skip line a browser-less machine
# produces.
# test-scope: plugins/planning/shared/tests/align.test.sh
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
cp "$here/align.test.sh" "$tmp/"
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
run() { env -u CI "$@" "$BASH" "$tmp/align.test.sh" >/dev/null 2>&1; }

echo 'console.log("SKIP: no Chromium to launch (stub)");' >"$tmp/align.js"
run
check "a missing Chromium skips green on a local run" 0 $?
run CI=true
check "a missing Chromium fails under CI=true" 1 $?

echo 'console.log("SKIP: align.js needs playwright-core (stub)");' >"$tmp/align.js"
run
check "a missing playwright-core skips green on a local run" 0 $?
run CI=true
check "a missing playwright-core fails under CI=true" 1 $?

echo 'console.log("PASS 3 / 3");' >"$tmp/align.js"
run CI=true
check "a run that passed passes under CI=true" 0 $?

echo 'console.log("PASS 2 / 3");' >"$tmp/align.js"
run CI=true
check "a partial pass fails under CI=true" 1 $?

nodeless="$tmp/bin"
mkdir -p "$nodeless"
ln -s "$(command -v dirname)" "$nodeless/dirname"
run PATH="$nodeless"
check "a missing node skips green on a local run" 0 $?
run PATH="$nodeless" CI=true
check "a missing node fails under CI=true" 1 $?

echo "align-require-browser: $pass passed, $failed failed"
((failed == 0))
