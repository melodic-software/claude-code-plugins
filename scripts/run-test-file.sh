#!/usr/bin/env bash
# Runs one repository test file with the runner its name selects:
#
#   scripts/run-test-file.sh <test file>
#
# test_*.py runs under pytest with the interpreter scripts/lib/pytest-python.sh
# picks (it may build the setup-env venv once), *.test.sh under bash, *.test.mjs
# under node --test, and a *.test.js or *.test.ts file that imports vitest
# under its package's locked vitest (npx --no-install vitest run, from the
# nearest directory holding a package.json, within the checkout), after
# npm ci --ignore-scripts there when it has a package-lock.json and no
# node_modules. The path
# must name a test file inside the checkout (the
# current directory; scripts/lib/checkout-path.sh). The test runs without
# GH_TOKEN or GITHUB_TOKEN. The name may hold only letters, digits, `.`, `_`,
# `-` and `/`, so no runner reads it as a pytest node id or parameter. Exits 2
# on a refused argument, else with the runner's status.
set -uo pipefail
# shellcheck source=scripts/lib/checkout-path.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/checkout-path.sh"
# shellcheck source=scripts/lib/pytest-python.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/pytest-python.sh"

[[ "$#" -eq 1 ]] || {
  echo "usage: run-test-file.sh <test file>" >&2
  exit 2
}
checkout_path::require "$1"
[[ $1 =~ ^[A-Za-z0-9._/-]+$ ]] || checkout_path::refuse "'$1' has a character outside [A-Za-z0-9._/-]"
[[ -f "$1" ]] || checkout_path::refuse "'$1' is not a file"
unset GH_TOKEN GITHUB_TOKEN
case ${1##*/} in
  test_*.py) PYTHONDONTWRITEBYTECODE=1 exec "$(pytest_python::resolve)" -m pytest -q -p no:cacheprovider -- "$1" ;;
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
    cd -- "$dir" || exit 2
    # A lane checkout installs no plugin package, so install its lockfile
    # once, with no install scripts, as scripts/setup-env.sh does at the root.
    if [[ ! -d node_modules && -f package-lock.json ]]; then
      npm ci --ignore-scripts --no-audit --no-fund >&2 || exit
    fi
    # An absolute path, so vitest cannot read the filter as an option.
    exec npx --no-install vitest run "$file"
    ;;
  *) checkout_path::refuse "'$1' is not a test_*.py, *.test.sh, *.test.mjs or vitest *.test.js/*.test.ts file" ;;
esac
