#!/usr/bin/env bash
# Tests scripts/run-covering-tests.sh against stub selection and runner scripts.
#
#   bash scripts/run-covering-tests.test.sh
set -uo pipefail
script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-covering-tests.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0 fail=0

check() {
  local name=$1 want_status=$2 want_out=$3 status out
  out=$(RUN_COVERING_TESTS_SELECT="$work/select" RUN_COVERING_TESTS_RUN="$work/run" bash "$script" "${@:4}" 2>"$work/err")
  status=$?
  if [[ $status -eq $want_status && $out == "$want_out" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  status %s, want %s\n  stdout: %s\n  want:   %s\n  stderr: %s\n' \
      "$name" "$status" "$want_status" "$out" "$want_out" "$(<"$work/err")"
  fi
}

# The selection stub prints the suites in $SUITES; the runner stub fails a
# suite whose name holds "red", exiting 3.
cat >"$work/select" <<'EOF'
[[ $1 == src.sh ]] || exit 1
printf '%s\n' $SUITES
EOF
cat >"$work/run" <<'EOF'
echo "noise on stdout"
[[ $1 != *red* ]] || exit 3
EOF

SUITES="a.test.sh b.test.mjs" check "every suite passes" 0 \
  $'PASS a.test.sh\nPASS b.test.mjs\ncovering suites: 2, failed: 0' src.sh
SUITES="a.test.sh red.test.sh c.test.sh" check "a failing suite is a kill and the rest still run" 1 \
  $'PASS a.test.sh\nFAIL red.test.sh (exit 3)\nPASS c.test.sh\ncovering suites: 3, failed: 1' src.sh
SUITES="" check "no covering suite" 2 "" src.sh
SUITES="a.test.sh" check "a failed selection" 2 "" other.sh
SUITES="a.test.sh" check "no argument" 2 ""
SUITES="a.test.sh" check "two arguments" 2 "" src.sh src.sh

echo "run-covering-tests: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
