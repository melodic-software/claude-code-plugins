#!/usr/bin/env bash
# test-scope: scripts/check-affected.sh scripts/check-affected-gates.txt plugins/code-tidying/git-hooks/* plugins/code-tidying/lib/* plugins/code-tidying/scripts/*
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh" || exit 2

if ! python3 -c 'import pygments' 2>/dev/null; then
  echo "FAIL - python3 cannot import pygments, which the comment lint needs" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
planted="$SELF_DIR/../plugins/code-tidying/git-hooks/fixtures/shape2.sh.txt"
mkdir -p "$repo/scripts"
git_init_test_repo "$repo" || exit 2
cp "$SELF_DIR/check-affected.sh" "$SELF_DIR/check-affected-gates.txt" "$repo/scripts/"
printf '#!/bin/sh\necho "$1"\n' >"$repo/tool.sh"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m base
git_test_config "$repo" branch -q bare
printf 'x\n' >"$repo/notes.txt"
git_test_config "$repo" add notes.txt
git_test_config "$repo" commit -q -m notes

run() {
  local -a envs=()
  while [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  RC=0
  OUT="$(cd "$repo" && env ${envs[@]+"${envs[@]}"} bash scripts/check-affected.sh --no-fetch "$@" 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
}
check() {
  if eval "$2"; then ok "$1"; else bad "$1" "rc=$RC out=$OUT err=$ERR"; fi
}

run -- --base bare
check "a tree without the comment-lint hook skips comment-lint" \
  '[[ $ERR == *"SKIP comment-lint (no plugins/code-tidying/git-hooks/comment-lint.sh beside this script)"* ]]'

mkdir -p "$repo/plugins/code-tidying" "$repo/docs/conventions"
for part in git-hooks lib scripts; do
  cp -R "$SELF_DIR/../plugins/code-tidying/$part" "$repo/plugins/code-tidying/"
done
printf 'comment_posture: necessary\ncomment_lint: block\n' >"$repo/docs/conventions/code-tidying.yaml"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m lint-base
git_test_config "$repo" branch -q lint-base
printf '#!/bin/sh\necho "$1" "$2"\n' >"$repo/tool.sh"
git_test_config "$repo" commit -q -am clean-tool

mkdir -p "$tmp/nopy"
printf '#!/bin/sh\nexit 1\n' >"$tmp/nopy/python3"
chmod +x "$tmp/nopy/python3"
run PATH="$tmp/nopy:$PATH" -- --base lint-base
check "a python3 that cannot import pygments skips comment-lint, not a failure" \
  '[[ $ERR == *"SKIP comment-lint (python3 with pygments not installed)"* && $ERR != *"FAIL comment-lint"* ]]'

run -- --base lint-base
check "a change with no comment passes comment-lint" \
  '[[ $ERR != *"FAIL comment-lint"* && $ERR != *"SKIP comment-lint"* && $ERR != *"CI only: comment-lint "* ]]'

cp "$planted" "$repo/tool.sh"
git_test_config "$repo" commit -q -am planted-tool
run -- --base lint-base
check "a committed comment the posture disallows fails comment-lint at its line" \
  '[[ $RC == 1 && $ERR == *"FAIL comment-lint"* && $ERR == *"tool.sh:8:"* ]]'

printf 'comment_posture: necessary\ncomment_lint: off\n' >"$repo/docs/conventions/code-tidying.yaml"
git_test_config "$repo" commit -q -am lint-off
run -- --base lint-base
check "the merge-base's comment_lint level decides, not one the branch sets" \
  '[[ $RC == 1 && $ERR == *"FAIL comment-lint"* && $ERR == *"tool.sh:8:"* ]]'

git_test_config "$repo" reset -q --hard lint-base
cp "$planted" "$repo/tool.sh"
run -- --uncommitted
check "an uncommitted comment the posture disallows fails comment-lint under --uncommitted" \
  '[[ $RC == 1 && $ERR == *"FAIL comment-lint"* && $ERR == *"tool.sh:8:"* ]]'

test_harness::report
