#!/usr/bin/env bash
# Tests for the eval fixture forge (fixtures/gh-forge): install.sh in a throwaway repository, then the gh stand-in it
# installs. Expected values come from GitHub's mergeStateStatus enum (UNSTABLE: mergeable with a
# non-passing commit status) and gh's `pr checks` source (the --json path exits 0 whatever the
# checks say; the table exits 1 when one failed).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../scripts/test-helpers.sh
source "$SCRIPT_DIR/../scripts/test-helpers.sh"

command -v jq >/dev/null 2>&1 || skip_suite "jq not installed"

# make_forge <dir> [install.sh options...]: a repository with main and a head branch one commit
# ahead, given an offline forge serving PR 7 from them.
make_forge() {
  local repo="$TEST_TMPDIR/$1"
  shift
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.name eval
    git config user.email eval@example.invalid
    echo a >f
    git add f
    git commit -q -m seed
    git checkout -q -b feat/x
    echo b >f
    git commit -q -am change
    bash "$SCRIPT_DIR/fixtures/gh-forge/install.sh" 7 feat/x main "feat: x" "$@"
  ) >/dev/null 2>&1
  assert_exit "install.sh $*: exit 0" 0 "$?"
}

run_gh() {
  local repo="$1"
  shift
  (cd "$repo" && "$repo/.git/eval-forge/bin/gh" "$@")
}

FAILING="$TEST_TMPDIR/failing" GREEN="$TEST_TMPDIR/green"
make_forge failing --open --failing-check integration-tests
make_forge green --open

out=$(run_gh "$FAILING" pr view 7 --json mergeStateStatus --jq .mergeStateStatus)
assert_eq "failing check: the PR reads UNSTABLE, never CLEAN" "UNSTABLE" "$out"

out=$(run_gh "$GREEN" pr view 7 --json mergeStateStatus --jq .mergeStateStatus)
assert_eq "no checks, head up to date: the PR reads CLEAN" "CLEAN" "$out"

out=$(run_gh "$FAILING" pr checks 7 --json name,bucket --jq '.[] | "\(.name) \(.bucket)"')
rc=$?
assert_exit "pr checks --json: exit 0 with a failed check" 0 "$rc"
assert_eq "pr checks --json: the failed check is listed" "integration-tests fail" "$out"

run_gh "$FAILING" pr checks 7 >/dev/null
assert_exit "pr checks table: exit 1 with a failed check" 1 "$?"

helper=missing
[[ -x "$GREEN/.git/eval-forge/bin/git-remote-evalforge" ]] && helper=executable
assert_eq "install.sh: git-remote-evalforge lands executable beside the gh stand-in" executable "$helper"

# push-branch.sh through the helper: origin reads as github.com, the bytes land in the bare repository.
PUSH="$SCRIPT_DIR/../skills/pull-request/scripts/push-branch.sh"
FORGE_PATH="$GREEN/.git/eval-forge/bin:$PATH"
(
  cd "$GREEN" || exit 1
  echo c >f
  PATH="$FORGE_PATH" git commit -q -am more
  PATH="$FORGE_PATH" bash "$PUSH" --pr 7
) >/dev/null 2>&1
assert_exit "push-branch.sh --pr 7: exit 0 against the fixture origin" 0 "$?"
assert_eq "push-branch.sh: the bare origin's head ref equals local HEAD" \
  "$(git -C "$GREEN" rev-parse HEAD)" "$(git -C "$GREEN/.git/eval-forge/eval-fixture/app.git" rev-parse feat/x)"
(cd "$GREEN" && PATH="$FORGE_PATH" git fetch origin) >/dev/null 2>&1
assert_exit "git fetch origin succeeds through the helper" 0 "$?"

echo
if ((FAILED)); then
  echo "Results: $FAILED of $CASE_NUM failed"
  exit 1
fi
echo "Results: $CASE_NUM passed"
