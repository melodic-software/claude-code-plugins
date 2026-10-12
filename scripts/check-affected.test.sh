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
run STUB_CHECK_SHELL_PORTABILITY=1 -- --base base
check "uncommitted edits to a changed file skip every check, not just the file linters" \
  '[[ $RC == 0 && $ERR == *"SKIP every check (uncommitted edits"* && $ERR != *"ran"* ]]'
git_test_config "$repo" checkout -q -- notes.txt

# validate-plugins runs only when a claude CLI resolves; a stub stands in. This
# case diffs against its own plugin-base branch and resets HEAD afterwards, so
# the cases below still see the base..HEAD diff of notes.txt and tool alone.
pre_plugin="$(git_test_config "$repo" rev-parse HEAD)"
mkdir -p "$tmp/bin" "$repo/plugins/demo"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/claude"
printf '#!/usr/bin/env bash\necho "validate-plugins ran: $*" >&2\nexit "${STUB_VALIDATE_PLUGINS:-0}"\n' \
  >"$repo/scripts/validate-plugins.sh"
chmod +x "$tmp/bin/claude" "$repo/scripts/validate-plugins.sh"
printf 'x\n' >"$repo/plugins/demo/keep.md"
printf 'x\n' >"$repo/plugins/demo/required.json"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m plugin
git_test_config "$repo" branch -q plugin-base
git_test_config "$repo" rm -q plugins/demo/required.json
git_test_config "$repo" commit -q -m delete
run PATH="$tmp/bin:$PATH" STUB_VALIDATE_PLUGINS=1 -- --base plugin-base
check "a branch that only deletes a plugin file still validates that plugin" \
  '[[ $RC == 1 && $ERR == *"FAIL validate-plugins"* && $ERR == *"validate-plugins ran: --only demo"* ]]'
git_test_config "$repo" reset -q --hard "$pre_plugin"

git_test_config "$repo" remote add origin "$tmp/missing-remote"
git_test_config "$repo" update-ref refs/remotes/origin/main "$(git_test_config "$repo" rev-parse base)"
run PATH="$tmp/bin:$PATH" --
check "a failed fetch skips the stale-base check only" \
  '[[ $RC == 0 && $ERR == *"SKIP stale-base-overlap (git fetch of origin/main failed)"* && $OUT$ERR == *"validate-plugins (no plugin changed)"* ]]'

# Run from another tree (the pre-push hook's merge-base copy), every check
# script comes from that tree and is told which tree to read; the checked
# tree's own scripts and its test code never run.
tools="$tmp/tools"
mkdir -p "$tools/scripts"
cp "$SELF_DIR/check-affected.sh" "$tools/scripts/"
for s in check-shell-portability check-changelog-fragments check-stale-base-overlap affected-tests; do
  printf '#!/usr/bin/env bash\necho "copy of %s read $CHECK_DATA_ROOT" >&2\nexit 1\n' "$s" >"$tools/scripts/$s.sh"
done
chmod +x "$tools"/scripts/*.sh
RC=0
ERR="$(cd "$repo" && bash "$tools/scripts/check-affected.sh" --base base --tests 2>&1)" || RC=$?
check "a copy run elsewhere runs its own check scripts against the checked tree" \
  '[[ $RC == 1 && $ERR == *"copy of check-shell-portability read $repo"* ]]'
check "a copy run elsewhere skips the checked tree's tests" \
  '[[ $ERR == *"SKIP tests"* && $ERR != *"affected-tests"* ]]'

if command -v markdownlint-cli2 >/dev/null 2>&1; then
  printf '{ "config": { "MD013": false } }\n' >"$tools/.markdownlint-cli2.jsonc"
  mkdir -p "$repo/docs"
  printf 'require("fs").writeFileSync(%s, "x");\nmodule.exports = {};\n' "'$tmp/md-payload'" \
    >"$repo/docs/.markdownlint-cli2.cjs"
  printf '# Title\n\nText.\n' >"$repo/docs/a.md"
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -q -m docs
  RC=0
  ERR="$(cd "$repo" && bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere never loads the checked tree's markdownlint config" \
    '[[ ! -e $tmp/md-payload && $ERR != *"SKIP markdown"* ]]'
  printf '# Title\nText.\n' >"$repo/docs/a.md"
  git_test_config "$repo" commit -q -am bad-md
  RC=0
  ERR="$(cd "$repo" && bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere still lints the checked tree's markdown" \
    '[[ $RC == 1 && $ERR == *"FAIL markdown"* && $ERR == *"MD022"* ]]'
else
  ok "SKIP markdown copy cases (markdownlint-cli2 not installed)"
fi

run -- --bogus
check "an unknown flag is a usage error" '[[ $RC == 2 ]]'
run -- --base no-such-ref
check "an unresolvable base is exit 2" '[[ $RC == 2 && $ERR == *"merge-base"* ]]'

test_harness::report
