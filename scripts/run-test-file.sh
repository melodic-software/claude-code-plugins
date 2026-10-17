#!/usr/bin/env bash
# Runs one repository test file with the runner its name selects:
#
#   scripts/run-test-file.sh <test file>
#
# test_*.py runs under python3 -m pytest, *.test.sh under bash, *.test.mjs
# under node --test, and a *.test.js or *.test.ts file that imports vitest
# under its package's locked vitest (npx --no-install vitest run, from the
# nearest directory holding a package.json, within the checkout). The path
# must name a test file inside the checkout (the
# current directory; scripts/lib/checkout-path.sh). The test runs without
# GH_TOKEN or GITHUB_TOKEN. The name may hold only letters, digits, `.`, `_`,
# `-` and `/`, so no runner reads it as a pytest node id or parameter. Exits 2
# on a refused argument, else with the runner's status.
set -uo pipefail
# shellcheck source=scripts/lib/checkout-path.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/checkout-path.sh"

[[ "$#" -eq 1 ]] || {
  echo "usage: run-test-file.sh <test file>" >&2
  exit 2
}
checkout_path::require "$1"
[[ $1 =~ ^[A-Za-z0-9._/-]+$ ]] || checkout_path::refuse "'$1' has a character outside [A-Za-z0-9._/-]"
[[ -f "$1" ]] || checkout_path::refuse "'$1' is not a file"
unset GH_TOKEN GITHUB_TOKEN
case ${1##*/} in
  test_*.py) PYTHONDONTWRITEBYTECODE=1 exec python3 -m pytest -q -p no:cacheprovider -- "$1" ;;
  *.test.sh) exec bash -- "$1" ;;
  *.test.mjs) exec node --test -- "$1" ;;
  *.test.js | *.test.ts)
    grep -Eq "from ['\"]vitest['\"]" -- "$1" || checkout_path::refuse "'$1' does not import vitest"
    here=$(pwd -P)
    file=$(realpath -- "$1")
    dir=${file%/*}
    until [[ -f $dir/package.json ]]; do
      [[ $dir != "$here" ]] || checkout_path::refuse "'$1' has no package.json inside the checkout"
      dir=${dir%/*}
    done
    # An absolute path, so vitest cannot read the filter as an option.
    cd -- "$dir" && exec npx --no-install vitest run "$file"
    ;;
  *) checkout_path::refuse "'$1' is not a test_*.py, *.test.sh, *.test.mjs or vitest *.test.js/*.test.ts file" ;;
esac
