#!/usr/bin/env bash
# align.test.sh passes a browser skip locally and fails it under CI=true. It runs here against a copy of
# align.test.sh in a throwaway folder beside a stub align.js that prints each SKIP line the real align.js
# can print, taken from align.js itself.
# test-scope: plugins/planning/shared/tests/align.test.sh plugins/planning/shared/tests/align.js
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

mapfile -t skips < <(grep -oE 'SKIP: [^"`$\\]*' "$here/align.js")
((${#skips[@]} > 0))
check "align.js prints at least one SKIP line" 0 $?

for line in "${skips[@]}"; do
  echo "console.log(\"$line\");" >"$tmp/align.js"
  run
  check "'$line' skips green on a local run" 0 $?
  run CI=true
  check "'$line' fails under CI=true" 1 $?
done

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
