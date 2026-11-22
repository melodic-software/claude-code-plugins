#!/usr/bin/env bash
# test-scope: scripts/check-affected.sh scripts/check-affected-gates.txt scripts/check-vocabulary.py scripts/vocabulary-senses.json
# shellcheck disable=SC2016
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh" || exit 2

tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
retired="$(printf 'Pick the diagram %s first.' "ru""ng")"
mkdir -p "$repo/scripts"
git_init_test_repo "$repo" || exit 2
cp "$SELF_DIR/check-affected.sh" "$SELF_DIR/check-affected-gates.txt" \
  "$SELF_DIR/check-vocabulary.py" "$SELF_DIR/vocabulary-senses.json" "$repo/scripts/"
printf 'Pick the diagram first.\n' >"$repo/notes.txt"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m base
git_test_config "$repo" branch -q base

run() {
  RC=0
  OUT="$(cd "$repo" && bash scripts/check-affected.sh --no-fetch "$@" 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
}
check() {
  if eval "$2"; then ok "$1"; else bad "$1" "rc=$RC out=$OUT err=$ERR"; fi
}

printf 'Pick the diagram form first.\n' >"$repo/notes.txt"
git_test_config "$repo" commit -q -am clean
run --base base
check "a change with no retired sense passes vocabulary" \
  '[[ $ERR != *"FAIL vocabulary"* && $ERR != *"SKIP vocabulary"* && $ERR != *"CI only: vocabulary "* ]]'

printf '%s\n' "$retired" >>"$repo/notes.txt"
git_test_config "$repo" commit -q -am planted
run --base base
check "a committed retired sense fails vocabulary at its line" \
  '[[ $RC == 1 && $ERR == *"FAIL vocabulary"* && $ERR == *"notes.txt:2: rung:"* ]]'

git_test_config "$repo" reset -q --hard base
printf '%s\n' "$retired" >"$repo/notes.txt"
run --uncommitted
check "an uncommitted retired sense fails vocabulary under --uncommitted" \
  '[[ $RC == 1 && $ERR == *"FAIL vocabulary"* && $ERR == *"notes.txt:1: rung:"* ]]'

git_test_config "$repo" reset -q --hard base
printf '%s\n' "$retired" >"$repo/old.txt"
git_test_config "$repo" add old.txt
git_test_config "$repo" commit -q -m old-base
git_test_config "$repo" branch -q old-base
printf '\n' >>"$repo/scripts/vocabulary-senses.json"
git_test_config "$repo" commit -q -am senses
run --base old-base
check "a branch that changes the senses file scans the whole tree" \
  '[[ $RC == 1 && $ERR == *"FAIL vocabulary"* && $ERR == *"old.txt:1: rung:"* ]]'

printf 'More notes.\n' >>"$repo/notes.txt"
run --base old-base
check "a whole-tree scan skips while a file it would read has uncommitted edits" \
  '[[ $ERR == *"SKIP vocabulary (the branch changes the checker or its senses file, and the whole-tree scan would read uncommitted edits a push does not send)"* && $ERR != *"FAIL vocabulary"* ]]'

git_test_config "$repo" reset -q --hard old-base
printf '\n' >>"$repo/scripts/vocabulary-senses.json"
run --uncommitted
check "a snapshot that changes the senses file leaves vocabulary to CI" \
  '[[ $ERR == *"SKIP vocabulary (the branch changes the checker or its senses file; CI runs the branch'"'"'s copy)"* && $ERR != *"FAIL vocabulary"* ]]'

test_harness::report
