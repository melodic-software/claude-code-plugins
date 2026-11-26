#!/usr/bin/env bash
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
    if [[ ! -d node_modules && -f package-lock.json ]]; then
      npm ci --ignore-scripts --no-audit --no-fund >&2 || exit
    fi
    run_child npx --no-install vitest run "$file"
    ;;
  *) checkout_path::refuse "'$1' is not a test_*.py, *.test.sh, *.test.mjs or vitest *.test.js/*.test.ts file" ;;
esac
