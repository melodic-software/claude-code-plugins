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
# `-` and `/`, so no runner reads it as a pytest node id or parameter. Git
# reads a fixed test config in place of the host's (scripts/lib/test-git-env.sh).
# The runner is a child, not exec'd, so the EXIT trap can remove that config; a
# TERM, INT or HUP sent to this script (as `timeout` sends) is forwarded to it.
# Exits 2 on a refused argument, else with the runner's status (128+signal when
# a signal ended it).
set -uo pipefail
# shellcheck source=scripts/lib/checkout-path.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/checkout-path.sh"
# shellcheck source=scripts/lib/pytest-python.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/pytest-python.sh"
# shellcheck source=scripts/lib/test-git-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/test-git-env.sh"

[[ "$#" -eq 1 ]] || {
  echo "usage: run-test-file.sh <test file>" >&2
  exit 2
}
checkout_path::require "$1"
[[ $1 =~ ^[A-Za-z0-9._/-]+$ ]] || checkout_path::refuse "'$1' has a character outside [A-Za-z0-9._/-]"
[[ -f "$1" ]] || checkout_path::refuse "'$1' is not a file"
unset GH_TOKEN GITHUB_TOKEN
git_config=$(mktemp) || exit 2
trap 'rm -f "$git_config"' EXIT
test_git_env::isolate "$git_config" || exit 2
# run_child <command...>: run the command as a child with this script's stdin
# and default INT and QUIT handling (a background job otherwise ignores both),
# forward TERM, INT and HUP to it, and exit with its status.
run_child() {
  local child rc sig
  (
    trap - INT QUIT
    exec "$@"
  ) <&0 &
  child=$!
  for sig in TERM INT HUP; do
    # shellcheck disable=SC2064 # expand $sig and $child now
    trap "kill -$sig $child 2>/dev/null" "$sig"
  done
  wait "$child"
  rc=$?
  # A trapped signal ends `wait` early with 128+signal; wait again for the child.
  while ((rc > 128)) && kill -0 "$child" 2>/dev/null; do
    wait "$child"
    rc=$?
  done
  exit "$rc"
}
case ${1##*/} in
  test_*.py) run_child env PYTHONDONTWRITEBYTECODE=1 "$(pytest_python::resolve)" -m pytest -q -p no:cacheprovider -- "$1" ;;
  *.test.sh) run_child bash -- "$1" ;;
  *.test.mjs) run_child node --test -- "$1" ;;
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
    run_child npx --no-install vitest run "$file"
    ;;
  *) checkout_path::refuse "'$1' is not a test_*.py, *.test.sh, *.test.mjs or vitest *.test.js/*.test.ts file" ;;
esac
