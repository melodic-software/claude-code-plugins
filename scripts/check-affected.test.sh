#!/usr/bin/env bash
# Contract test for scripts/check-affected.sh: how it runs the checks and reads
# their exits, against a fixture repository whose check scripts are stubs. What
# each check finds is that check's own suite's business.
#
#   bash scripts/check-affected.test.sh
#
# The cases hold shell source as literal data on purpose.
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
mkdir -p "$repo/scripts"
git_init_test_repo "$repo" || exit 2
cp "$SELF_DIR/check-affected.sh" "$repo/scripts/"
# Each stub exits with STUB_<NAME> (default 0), so a case picks which check fails.
for s in check-shell-portability check-changelog-fragments check-stale-base-overlap affected-tests; do
  var="STUB_$(printf '%s' "$s" | tr 'a-z-' 'A-Z_')"
  printf '#!/usr/bin/env bash\necho "%s ran" >&2\nexit "${%s:-0}"\n' "$s" "$var" >"$repo/scripts/$s.sh"
done
chmod +x "$repo"/scripts/*.sh
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m base
git_test_config "$repo" branch -q base
printf 'data\n' >"$repo/notes.txt"
git_test_config "$repo" add notes.txt
git_test_config "$repo" commit -q -m change

# run <env...> -- <args...>: sets RC, OUT, ERR.
run() {
  local -a envs=()
  while [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  RC=0
  OUT="$(cd "$repo" && env ${envs[@]+"${envs[@]}"} bash scripts/check-affected.sh "$@" 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
}

check() {
  local name="$1" cond="$2"
  if eval "$cond"; then ok "$name"; else bad "$name" "rc=$RC out=$OUT err=$ERR"; fi
}

run -- --base base
check "every check passing exits 0 with the statement on stdout" \
  '[[ $RC == 0 && $OUT == *"passed"* ]]'

run STUB_CHECK_CHANGELOG_FRAGMENTS=1 -- --base base
check "a failing check exits 1" '[[ $RC == 1 ]]'
check "the failure names the check and how to reproduce it" \
  '[[ $ERR == *"FAIL changelog-fragments"* && $ERR == *"Reproduce: scripts/check-changelog-fragments.sh"* ]]'
check "the failing check's output is shown" '[[ $ERR == *"check-changelog-fragments ran"* ]]'
check "a failure prints nothing on stdout" '[[ -z $OUT ]]'

run STUB_CHECK_SHELL_PORTABILITY=2 -- --base base
check "a check that could not run is a skip, not a failure" \
  '[[ $RC == 0 && $ERR == *"SKIP shell-portability (could not run, exit 2"* ]]'

run -- --base base --tests
check "--tests runs the affected suites" '[[ $RC == 0 && $OUT == *"passed"* ]]'
run STUB_AFFECTED_TESTS=3 -- --base base --tests
check "--tests passes when only another ecosystem's suites went unrun" '[[ $RC == 0 ]]'
run STUB_AFFECTED_TESTS=1 -- --base base --tests
check "--tests fails on a failing suite" '[[ $RC == 1 && $ERR == *"FAIL tests"* ]]'

printf '#!/usr/bin/env bash\necho hi\n' >"$repo/tool"
git_test_config "$repo" add tool
git_test_config "$repo" commit -q -m tool
run -- --base base
check "a changed #! file without the exec bit fails exec-bit" \
  '[[ $RC == 1 && $ERR == *"FAIL exec-bit"* && $ERR == *"update-index --chmod=+x tool"* ]]'
git_test_config "$repo" update-index --chmod=+x tool
git_test_config "$repo" commit -q -m chmod

printf 'edit\n' >>"$repo/notes.txt"
run -- --base base
check "uncommitted edits to a changed file skip the file linters" \
  '[[ $RC == 0 && $ERR == *"SKIP markdown (uncommitted edits"* && $ERR == *"SKIP shellcheck (uncommitted edits"* ]]'
git_test_config "$repo" checkout -q -- notes.txt

git_test_config "$repo" remote add origin "$tmp/missing-remote"
git_test_config "$repo" update-ref refs/remotes/origin/main "$(git_test_config "$repo" rev-parse base)"
run --
check "a failed fetch skips the stale-base check only" \
  '[[ $RC == 0 && $ERR == *"SKIP stale-base-overlap (git fetch of origin/main failed)"* ]]'

run -- --bogus
check "an unknown flag is a usage error" '[[ $RC == 2 ]]'
run -- --base no-such-ref
check "an unresolvable base is exit 2" '[[ $RC == 2 && $ERR == *"merge-base"* ]]'

test_harness::report
