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
# The real patterns file machine-specific-paths sources, committed at the base.
patterns_lib=plugins/guardrails/lib/path-detection/machine-path-patterns.sh
mkdir -p "$repo/${patterns_lib%/*}"
cp "$SELF_DIR/../$patterns_lib" "$repo/$patterns_lib"
# Each stub exits with STUB_<NAME> (default 0), so a case picks which check fails.
for s in check-shell-portability check-changelog-fragments check-stale-base-overlap affected-tests \
  check-spoke-plugin-root check-changelog-parity check-changed-skills check-comment-hygiene setup-env; do
  var="STUB_$(printf '%s' "$s" | tr 'a-z-' 'A-Z_')"
  printf '#!/usr/bin/env bash\necho "%s ran: $*" >&2\nexit "${%s:-0}"\n' "$s" "$var" >"$repo/scripts/$s.sh"
done
# The changed-skills stub also echoes whether the skills' script tests are skipped.
printf '#!/usr/bin/env bash\necho "check-changed-skills ran: $* skip-script-tests=${CHECK_SKILL_SKIP_SCRIPT_TESTS-unset}" >&2\nexit "${STUB_CHECK_CHANGED_SKILLS:-0}"\n' \
  >"$repo/scripts/check-changed-skills.sh"
# The affected-tests stub also writes STUB_NOT_RUN to its --write-not-run file,
# as the real one lists the selected suites it did not run.
cat >"$repo/scripts/affected-tests.sh" <<'STUB'
#!/usr/bin/env bash
echo "affected-tests ran" >&2
[[ -z "${STUB_ARGS_LOG:-}" ]] || printf '%s\n' "$*" >"$STUB_ARGS_LOG"
[[ -z "${STUB_ENV_LOG:-}" ]] || printf '%s' "${CHECK_DATA_ROOT-unset}" >"$STUB_ENV_LOG"
[[ -z "${STUB_SHARE_LOG:-}" ]] || printf '%s' "${PLUGIN_TEST_SHARE_WARN_ONLY-unset}" >"$STUB_SHARE_LOG"
# The real selector diffs its own tree's work tree, so the stub logs that.
[[ -z "${STUB_STATUS_LOG:-}" ]] || git -C "$(dirname "$0")/.." status --porcelain --untracked-files=all >"$STUB_STATUS_LOG"
[[ -v CHECK_DATA_ROOT ]] && { echo "affected-tests saw CHECK_DATA_ROOT" >&2; exit 1; }
while (($#)); do
  [[ "$1" == --write-not-run ]] && printf '%s' "${STUB_NOT_RUN:-}" >"$2"
  shift
done
exit "${STUB_AFFECTED_TESTS:-0}"
STUB
printf 'import os, sys\nsys.stderr.write("sync-plugin-options-docs ran\\n")\nsys.exit(int(os.environ.get("STUB_SYNC_PLUGIN_OPTIONS_DOCS", "0")))\n' \
  >"$repo/scripts/sync-plugin-options-docs.py"
cp "$SELF_DIR/check-affected-gates.txt" "$repo/scripts/"
# The real Node package runner, over one registered fixture package.
mkdir -p "$repo/scripts/lib"
cp "$SELF_DIR/lib/read-list.sh" "$SELF_DIR/lib/test-git-env.sh" "$repo/scripts/lib/"
cp "$SELF_DIR/run-outside-node-suites.sh" "$repo/scripts/"
printf '# fixture\npkg/demo\n' >"$repo/scripts/outside-node-packages.txt"
printf '# fixture\nfixtures/\n' >"$repo/scripts/outside-node-exclusions.txt"
: >"$repo/_typos.toml"
# The workflow typos reads its exclusions from: its typos step's `exclude:` line.
mkdir -p "$repo/.github/workflows"
cat >"$repo/.github/workflows/pr-require-checks.yml" <<'YAML'
jobs:
  lint-repo:
    steps:
      - name: Spell-check
        id: typos
        with:
          config: _typos.toml
          exclude: plugins/*/skills/*/vendor/** plugins/*/tools/*/vendor/**
      - name: Machine paths
        id: machine_paths
        with:
          exclude: >-
            other/**
YAML
chmod +x "$repo"/scripts/*.sh
# A typos stand-in on every run's PATH, so a typos on the machine never sees the
# fixture's missing config. It echoes its arguments and exits STUB_TYPOS.
mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\necho "typos ran: $*" >&2\nexit "${STUB_TYPOS:-0}"\n' >"$tmp/bin/typos"
chmod +x "$tmp/bin/typos"
export PATH="$tmp/bin:$PATH"

# path_without <command>: PATH minus every directory holding that command.
path_without() {
  local d out='' dirs
  IFS=: read -ra dirs <<<"$PATH"
  for d in "${dirs[@]}"; do
    [[ -x "$d/$1" ]] || out+="${out:+:}$d"
  done
  printf '%s' "$out"
}
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

check "a diff with no skill file skips changed-skills" \
  '[[ $ERR == *"SKIP changed-skills (no changed skill file)"* && $ERR != *"check-changed-skills ran"* ]]'
check "every hygiene gate the runner does not run is named CI only" \
  '[[ $ERR == *"CI only: zizmor ("* && $ERR == *"CI only: actionlint ("* && $ERR == *"CI only: gitleaks ("* ]]'
check "a gate the runner runs is not named CI only" \
  '[[ $ERR != *"CI only: markdown "* && $ERR != *"CI only: spoke-plugin-root "* && $ERR != *"CI only: typos "* && $ERR != *"CI only: machine-specific-paths "* ]]'
check "a diff with no file of a scanned type skips machine-specific-paths" \
  '[[ $ERR == *"SKIP machine-specific-paths (no changed file of a type it scans)"* ]]'

# The tree checked is the one holding the script, whatever the working
# directory: run by path from another checkout whose HEAD is at its base (a main
# checkout beside a worktree), it still lists the branch's one change, notes.txt.
other="$tmp/other"
git_test_config "$tmp" clone -q --branch base "$repo" "$other"
git_test_config "$other" update-ref refs/remotes/origin/main "$(git_test_config "$repo" rev-parse HEAD)"
# run_from <dir> <args...>: runs the fixture repo's script from <dir>; sets RC, OUT, ERR.
run_from() {
  local dir="$1"
  shift
  RC=0
  OUT="$(cd "$dir" && bash "$repo/scripts/check-affected.sh" "$@" 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
}
run_from "$other" --base base --tests
check "run from another checkout, it lists the script's own branch's change" \
  '[[ $RC == 0 && $OUT == *"over 1 changed files"* && $ERR != *"SKIP tests"* ]]'
# The ready step names the script's own tree in CHECK_DATA_ROOT from another
# checkout. The suites build fixture repositories of their own, so the variable
# must not reach them, or each one reads this tree in place of its fixture.
RC=0
OUT="$(cd "$other" && CHECK_DATA_ROOT="$repo" STUB_ENV_LOG="$tmp/env.log" \
  bash "$repo/scripts/check-affected.sh" --base base --tests 2>"$tmp/err")" || RC=$?
ERR="$(cat "$tmp/err")"
check "CHECK_DATA_ROOT naming the script's own tree checks that tree and is not passed to the suites" \
  '[[ $RC == 0 && $OUT == *"over 1 changed files"* && $(cat "$tmp/env.log") == unset ]]'
git_test_config "$repo" update-ref refs/remotes/origin/main "$(git_test_config "$repo" rev-parse base)"
run_from "$other" --base origin/main --no-fetch
check "an explicit --base run from another checkout still lists the change" \
  '[[ $RC == 0 && $OUT == *"over 1 changed files"* ]]'
git_test_config "$repo" update-ref -d refs/remotes/origin/main

# An empty changed set while HEAD is not the base means the wrong tree or range
# was read, never a pass: HEAD behind the base, and commits that change nothing.
RC=0
ERR="$(cd "$other" && bash scripts/check-affected.sh --base origin/main --no-fetch 2>&1)" || RC=$?
check "HEAD behind its base with no changed files exits non-zero with a message" \
  '[[ $RC != 0 && $ERR == *"no changed files"* && $ERR != *"passed"* ]]'
git_test_config "$other" commit -q --allow-empty -m empty
RC=0
ERR="$(cd "$other" && bash scripts/check-affected.sh --base origin/base --no-fetch 2>&1)" || RC=$?
check "commits beyond the base that change no file exit non-zero with a message" \
  '[[ $RC != 0 && $ERR == *"no changed files"* && $ERR != *"passed"* ]]'
git_test_config "$other" reset -q --hard origin/base
RC=0
OUT="$(cd "$other" && bash scripts/check-affected.sh --base base --no-fetch 2>/dev/null)" || RC=$?
check "HEAD at its base passes with nothing to check" '[[ $RC == 0 && $OUT == *"over 0 changed files"* ]]'

run STUB_TYPOS=2 -- --base base
check "a typos exit of 2 is a finding, not a check that could not run" \
  '[[ $RC == 1 && $ERR == *"FAIL typos"* && $ERR != *"SKIP typos"* ]]'
run STUB_TYPOS=1 -- --base base
check "a typos finding fails the typos check" '[[ $RC == 1 && $ERR == *"FAIL typos"* ]]'
check "typos gets the config, the exclusions and the changed files" \
  '[[ $ERR == *"typos ran: --config "*"/_typos.toml --force-exclude --exclude plugins/*/skills/*/vendor/**"*"-- notes.txt"* ]]'
run PATH="$(path_without typos)" -- --base base
check "a missing typos is a skip, not a failure" \
  '[[ $RC == 0 && $ERR == *"SKIP typos (typos not installed)"* ]]'
# The exclusions are the checked tree's workflow's, so a branch that adds one
# with the files it exempts is judged by it.
pre_typos="$(git_test_config "$repo" rev-parse HEAD)"
workflow="$repo/.github/workflows/pr-require-checks.yml"
sed -i.bak 's|exclude: plugins/.*|& legacy/samples/**|' "$workflow" && rm -f "$workflow.bak"
git_test_config "$repo" commit -q -am typos-exclude
run STUB_TYPOS=1 -- --base base
check "typos takes an exclusion the branch adds to the workflow" \
  '[[ $ERR == *"--exclude plugins/*/tools/*/vendor/** --exclude legacy/samples/** "* ]]'
sed -i.bak 's|exclude: plugins/.*|exclude:|' "$workflow" && rm -f "$workflow.bak"
git_test_config "$repo" commit -q -am typos-no-globs
run -- --base base
check "a workflow typos step with no exclude globs fails typos closed" \
  '[[ $RC == 1 && $ERR == *"FAIL typos"* && $ERR == *"no exclude globs"* && $ERR != *"typos ran"* ]]'
# The scan stops at the end of the typos step, so the next step's exclude is
# never read as typos'.
sed -i.bak '/^ *exclude:$/d' "$workflow" && rm -f "$workflow.bak"
git_test_config "$repo" commit -q -am typos-no-exclude
run -- --base base
check "a typos step with no exclude fails closed, not reading the next step's" \
  '[[ $RC == 1 && $ERR == *"FAIL typos"* && $ERR == *"no exclude globs"* && $ERR != *"typos ran"* ]]'
sed -i.bak 's|config: _typos.toml|&\
          exclude: >-\
            folded/**|' "$workflow" && rm -f "$workflow.bak"
git_test_config "$repo" commit -q -am typos-folded
run -- --base base
check "a folded typos exclude is refused with a message" \
  '[[ $RC == 1 && $ERR == *"FAIL typos"* && $ERR == *"block scalar"* && $ERR != *"typos ran"* ]]'
git_test_config "$repo" rm -q .github/workflows/pr-require-checks.yml
git_test_config "$repo" commit -q -m typos-no-workflow
run -- --base base
check "a missing workflow fails typos closed" \
  '[[ $RC == 1 && $ERR == *"FAIL typos"* && $ERR == *"pr-require-checks.yml"* && $ERR != *"typos ran"* ]]'
git_test_config "$repo" reset -q --hard "$pre_typos"
run -- --base base
# shellcheck disable=SC2034 # read by the eval in check
base_sha="$(git_test_config "$repo" rev-parse base)"
check "a clean comment-hygiene passes" \
  '[[ $RC == 0 && $ERR != *"FAIL comment-hygiene"* && $ERR != *"SKIP comment-hygiene"* ]]'
check "comment-hygiene is not named CI only" '[[ $ERR != *"CI only: comment-hygiene "* ]]'
# A passing check's output is not printed, so the failing run shows the arguments.
run STUB_CHECK_COMMENT_HYGIENE=1 -- --base base
check "comment-hygiene gets the merge-base and the changed files" \
  '[[ $ERR == *"check-comment-hygiene ran: $base_sha notes.txt"* ]]'
check "a comment-hygiene violation fails the check, naming how to reproduce it" \
  '[[ $RC == 1 && $ERR == *"FAIL comment-hygiene"* && $ERR == *"Reproduce: bash scripts/check-comment-hygiene.sh $base_sha notes.txt"* ]]'
run STUB_CHECK_COMMENT_HYGIENE=2 -- --base base
check "a comment-hygiene that could not fetch its patterns is a skip, not a failure" \
  '[[ $RC == 0 && $ERR == *"SKIP comment-hygiene (could not run, exit 2"* ]]'
run STUB_CHECK_SPOKE_PLUGIN_ROOT=1 -- --base base
check "a failing spoke-plugin-root fails the check" '[[ $RC == 1 && $ERR == *"FAIL spoke-plugin-root"* ]]'
run STUB_SYNC_PLUGIN_OPTIONS_DOCS=1 -- --base base
check "a failing plugin-options-docs fails the check" '[[ $RC == 1 && $ERR == *"FAIL plugin-options-docs"* ]]'
run STUB_CHECK_CHANGELOG_PARITY=1 -- --base base
check "a failing changelog-parity fails the check" '[[ $RC == 1 && $ERR == *"FAIL changelog-parity"* ]]'

# machine-specific-paths scans the changed files with the committed patterns
# file. Each home path is built at run time, so this file holds none.
pre_paths="$(git_test_config "$repo" rev-parse HEAD)"
printf '{"root": "/%s/alice/project"}\n' home >"$repo/settings.json"
git_test_config "$repo" add settings.json
git_test_config "$repo" commit -q -m home-path
run -- --base base
check "a changed file holding a home path fails machine-specific-paths, naming the file" \
  '[[ $RC == 1 && $ERR == *"FAIL machine-specific-paths"* && $ERR == *"Linux user path: settings.json:1:"* ]]'
git_test_config "$repo" reset -q --hard "$pre_paths"
excluded=plugins/autonomy/skills/setup/evals/fixtures/security-binding
mkdir -p "$repo/$excluded"
printf '{"root": "/%s/alice/project"}\n' home >"$repo/$excluded/case.json"
printf '{"root": "/%s/.../project",\n"note": "/%s/alice/x machine-path:allow"}\n' home home >"$repo/placeholder.json"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m excluded-paths
run -- --base base
check "a home path in a file the workflow step excludes, a placeholder, or an allow-marked line passes" \
  '[[ $RC == 0 && $ERR != *"FAIL machine-specific-paths"* && $ERR != *"SKIP machine-specific-paths"* ]]'
git_test_config "$repo" reset -q --hard "$pre_paths"

run STUB_CHECK_CHANGELOG_FRAGMENTS=1 -- --base base
check "a failing check exits 1" '[[ $RC == 1 ]]'
check "the failure names the check and how to reproduce it" \
  '[[ $ERR == *"FAIL changelog-fragments"* && $ERR == *"Reproduce: scripts/check-changelog-fragments.sh"* ]]'
check "the failing check's output is shown" '[[ $ERR == *"check-changelog-fragments ran"* ]]'
check "a failure prints nothing on stdout" '[[ -z $OUT ]]'

run STUB_CHECK_CHANGELOG_FRAGMENTS=1 -- --base base --tests
check "a failing static check skips the suites and their npm install" \
  '[[ $RC == 1 && $ERR == *"FAIL changelog-fragments"* && $ERR == *"SKIP tests (a static check failed above)"* && $ERR != *"affected-tests ran"* && $ERR != *"setup-env ran"* ]]'

run STUB_CHECK_SHELL_PORTABILITY=2 -- --base base
check "a check that could not run is a skip, not a failure" \
  '[[ $RC == 0 && $ERR == *"SKIP shell-portability (could not run, exit 2"* ]]'

run -- --base base --tests
check "--tests runs the affected suites" '[[ $RC == 0 && $OUT == *"passed"* ]]'
# A passing check's output is not printed, so the stub logs its arguments.
args_log="$tmp/affected-args.log"
run -u CHECK_AFFECTED_JOBS -u CHECK_AFFECTED_BUDGET STUB_ARGS_LOG="$args_log" -- --base base --tests
check "--tests passes a default job count of at most 8 and the 120 s budget" \
  '[[ $RC == 0 && $(cat "$args_log") =~ ^"--run --jobs "[1-8]" --budget 120 " ]]'
run CHECK_AFFECTED_JOBS=5 CHECK_AFFECTED_BUDGET=300 STUB_ARGS_LOG="$args_log" -- --base base --tests
check "CHECK_AFFECTED_JOBS and CHECK_AFFECTED_BUDGET override the defaults" \
  '[[ $RC == 0 && $(cat "$args_log") == "--run --jobs 5 --budget 300 "* ]]'
run STUB_ARGS_LOG="$args_log" -- --base base --tests --budget 45
check "--budget sets the budget passed to affected-tests" '[[ $RC == 0 && $(cat "$args_log") == *" --budget 45 "* ]]'
share_log="$tmp/affected-share.log"
run -u PLUGIN_TEST_SHARE_WARN_ONLY STUB_SHARE_LOG="$share_log" -- --base base --tests
check "--tests passes PLUGIN_TEST_SHARE_WARN_ONLY=1 to the suites" '[[ $RC == 0 && $(cat "$share_log") == 1 ]]'
run CHECK_DATA_ROOT="$repo" -- --base base --tests
check "--tests keeps a caller's CHECK_DATA_ROOT from the suites" '[[ $RC == 0 && $ERR != *"saw CHECK_DATA_ROOT"* ]]'
run STUB_AFFECTED_TESTS=3 STUB_NOT_RUN=$'eco/test_x.py\neco/X.Tests.ps1\n' -- --base base --tests
check "--tests reports selected suites left unrun as a skip counting them, never a pass" \
  '[[ $RC == 0 && $ERR == *"SKIP tests (could not run, exit 2: 2 selected suite(s) not run here, left to their own CI lanes)"* ]]'
run STUB_AFFECTED_TESTS=3 -- --base base --tests
check "--tests does not pass an exit 3 that names no unrun suite" \
  '[[ $RC == 0 && $ERR == *"SKIP tests (could not run, exit 2: affected-tests exited 3 but named no unrun suite)"* ]]'
mkdir -p "$repo/eco"
printf '#!/usr/bin/env bash\nexit 0\n' >"$repo/eco/w.test.sh"
run STUB_AFFECTED_TESTS=3 STUB_NOT_RUN=$'eco/w.test.mjs\n' -- --base base --tests
check "--tests counts a Node suite beside its .test.sh wrapper as run" \
  '[[ $RC == 0 && $ERR != *"SKIP tests"* ]]'
rm -rf "$repo/eco"
run STUB_AFFECTED_TESTS=3 STUB_NOT_RUN=$'fixtures/case.test.js\n' -- --base base --tests
check "--tests counts no path under outside-node-exclusions.txt as an unrun suite" \
  '[[ $RC == 0 && $ERR != *"SKIP tests"* ]]'
# A selected Node suite in a registered package runs through the package's own
# npm test, and a failing one fails tests.
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  mkdir -p "$repo/pkg/demo"
  printf '{"name":"demo","private":true,"scripts":{"test":"node --test x.test.mjs"}}\n' >"$repo/pkg/demo/package.json"
  node_suite='import test from "node:test";\nimport assert from "node:assert";\ntest("planted", () => assert.equal(1, %s));\n'
  # shellcheck disable=SC2059 # the format is the suite template above.
  printf "$node_suite" 2 >"$repo/pkg/demo/x.test.mjs"
  run STUB_AFFECTED_TESTS=3 STUB_NOT_RUN=$'pkg/demo/x.test.mjs\n' -- --base base --tests
  check "--tests fails on a failing selected Node suite in a registered package" \
    '[[ $RC == 1 && $ERR == *"FAIL tests"* ]]'
  # shellcheck disable=SC2059 # the format is the suite template above.
  printf "$node_suite" 1 >"$repo/pkg/demo/x.test.mjs"
  run STUB_AFFECTED_TESTS=3 STUB_NOT_RUN=$'pkg/demo/x.test.mjs\n' -- --base base --tests
  check "--tests passes when the selected Node package suites pass and nothing is left unrun" \
    '[[ $RC == 0 && $ERR != *"SKIP tests"* && $ERR != *"FAIL tests"* ]]'
  run STUB_AFFECTED_TESTS=3 STUB_NOT_RUN=$'pkg/demo/x.test.mjs\neco/test_x.py\n' -- --base base --tests
  check "--tests runs the Node package suites and still skips, counting, the ones left unrun" \
    '[[ $RC == 0 && $ERR == *"SKIP tests (could not run, exit 2: 1 selected suite(s) not run here"* ]]'
  rm -rf "$repo/pkg"
else
  ok "SKIP Node package cases (node, npm or jq not installed)"
fi
run STUB_AFFECTED_TESTS=1 -- --base base --tests
check "--tests fails on a failing suite" '[[ $RC == 1 && $ERR == *"FAIL tests"* ]]'

run STUB_SETUP_ENV=1 -- --base base --tests
check "--tests fails, naming the command, when setup-env --node fails, and runs no suites" \
  '[[ $RC == 1 && $ERR == *"FAIL npm-deps (exit 1). Reproduce: bash scripts/setup-env.sh --node"* && $ERR == *"SKIP tests (npm dependencies did not install)"* ]]'

run STUB_SETUP_ENV=127 -- --base base --tests
check "--tests skips npm-deps and still runs the suites when setup-env --node could not run" \
  '[[ $RC == 0 && $ERR == *"SKIP npm-deps (could not run, exit 127"* && $OUT == *"passed"* ]]'

# A fresh worktree has lockfiles but no node_modules: --tests installs each
# through the real setup-env.sh --node. The npm stand-in logs its arguments and
# creates the node_modules its --prefix names, or exits STUB_NPM.
cp "$repo/scripts/setup-env.sh" "$tmp/setup-env.stub"
cp "$SELF_DIR/setup-env.sh" "$repo/scripts/setup-env.sh"
mkdir -p "$tmp/npmbin" "$repo/.github/standards/runner-policy"
cat >"$tmp/npmbin/npm" <<'NPM'
#!/usr/bin/env bash
echo "$*" >>"$NPM_LOG"
[[ "${STUB_NPM:-0}" == 0 ]] || exit "$STUB_NPM"
dir=.
while (($#)); do
  [[ "$1" == --prefix ]] && dir="$2"
  shift
done
mkdir -p "$dir/node_modules"
NPM
chmod +x "$tmp/npmbin/npm"
echo '{"v":1}' >"$repo/package-lock.json"
echo '{"v":2}' >"$repo/.github/standards/runner-policy/package-lock.json"
npm_env=(PATH="$tmp/npmbin:$PATH" NPM_LOG="$tmp/npm.log")
: >"$tmp/npm.log"
# shellcheck disable=SC2034 # read by the eval in check
npm_want="$(printf '%s\n' "ci --no-audit --no-fund --prefix ." "ci --no-audit --no-fund --prefix .github/standards/runner-policy")"
run "${npm_env[@]}" -- --base base --tests
check "--tests runs npm ci in each tree missing node_modules, then the suites" \
  '[[ $RC == 0 && $(cat "$tmp/npm.log") == "$npm_want" && $ERR != *"SKIP tests"* ]]'
check "each install is named on stderr" \
  '[[ $ERR == *"setup-env: installed ./package-lock.json into ./node_modules"* && $ERR == *"setup-env: installed .github/standards/runner-policy/package-lock.json into .github/standards/runner-policy/node_modules"* ]]'
: >"$tmp/npm.log"
run "${npm_env[@]}" -- --base base --tests
check "--tests installs nothing where node_modules is current" '[[ $RC == 0 && ! -s "$tmp/npm.log" ]]'
echo '{"v":3}' >"$repo/package-lock.json"
run "${npm_env[@]}" -- --base base --tests
check "--tests reinstalls the tree whose lockfile changed" \
  '[[ $RC == 0 && $(cat "$tmp/npm.log") == "ci --no-audit --no-fund --prefix ." ]]'
rm -rf "$repo/node_modules"
run "${npm_env[@]}" STUB_NPM=1 -- --base base --tests
check "a failed npm ci fails the run and runs no suites" \
  '[[ $RC == 1 && $ERR == *"FAIL npm-deps"* && $ERR == *"SKIP tests (npm dependencies did not install)"* ]]'
rm -rf "$repo/.github/standards" "$repo/package-lock.json" "$repo/node_modules" "$tmp/npmbin"
cp "$tmp/setup-env.stub" "$repo/scripts/setup-env.sh"

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
mkdir -p "$repo/plugins/demo/skills/s"
printf 'x\n' >"$repo/plugins/demo/skills/s/notes.txt"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m skill
run STUB_CHECK_CHANGED_SKILLS=1 -- --base plugin-base
# shellcheck disable=SC2034 # read by the eval in check
plugin_base_sha="$(git_test_config "$repo" rev-parse plugin-base)"
check "a changed skill file runs changed-skills against the base, resolved to its commit, without script tests" \
  '[[ $RC == 1 && $ERR == *"FAIL changed-skills"* && $ERR == *"skip-script-tests=1"* && $ERR == *"Reproduce: CHECK_SKILL_SKIP_SCRIPT_TESTS=1 scripts/check-changed-skills.sh $plugin_base_sha"* ]]'
run STUB_CHECK_CHANGED_SKILLS=1 -- --base plugin-base --tests
check "--tests runs changed-skills with the skills' script tests" \
  '[[ $RC == 1 && $ERR == *"skip-script-tests=unset"* && $ERR == *"Reproduce: scripts/check-changed-skills.sh $plugin_base_sha"* ]]'
run PATH="$tmp/bin:$PATH" STUB_CHECK_CHANGELOG_FRAGMENTS=1 STUB_VALIDATE_PLUGINS=1 STUB_CHECK_CHANGED_SKILLS=1 -- --base plugin-base
check "a failing static check reports at once, with validate-plugins and changed-skills skipped" \
  '[[ $RC == 1 && $ERR == *"FAIL changelog-fragments"* && $ERR == *"SKIP validate-plugins (a static check failed above)"* && $ERR == *"SKIP changed-skills (a static check failed above)"* && $ERR != *"validate-plugins ran"* && $ERR != *"check-changed-skills ran"* ]]'
git_test_config "$repo" reset -q --hard "$pre_plugin"

git_test_config "$repo" remote add origin "$tmp/missing-remote"
git_test_config "$repo" update-ref refs/remotes/origin/main "$(git_test_config "$repo" rev-parse base)"
run PATH="$tmp/bin:$PATH" --
check "a failed fetch skips the stale-base check only" \
  '[[ $RC == 0 && $ERR == *"SKIP stale-base-overlap (git fetch of origin/main failed)"* && $OUT$ERR == *"validate-plugins (no plugin changed)"* ]]'

# A copy outside the checked tree (the pre-push hook's merge-base copy) checks
# the tree CHECK_DATA_ROOT names: every check script comes from the copy and is
# told which tree to read; the checked tree's own scripts and its test code
# never run.
tools="$tmp/tools"
mkdir -p "$tools/scripts/lib"
cp "$SELF_DIR/check-affected.sh" "$tools/scripts/"
cp "$SELF_DIR/lib/markdownlint-config-data.mjs" "$tools/scripts/lib/"
for s in check-shell-portability check-changelog-fragments check-stale-base-overlap affected-tests \
  check-spoke-plugin-root check-changelog-parity check-changed-skills check-comment-hygiene; do
  printf '#!/usr/bin/env bash\necho "copy of %s read $CHECK_DATA_ROOT" >&2\nexit "${COPY_STUB_RC:-1}"\n' "$s" >"$tools/scripts/$s.sh"
done
printf 'import os, sys\nsys.stderr.write("copy of sync-plugin-options-docs read " + os.environ["CHECK_DATA_ROOT"] + "\\n")\nsys.exit(int(os.environ.get("COPY_STUB_RC", "1")))\n' \
  >"$tools/scripts/sync-plugin-options-docs.py"
cp "$SELF_DIR/check-affected-gates.txt" "$tools/scripts/"
chmod +x "$tools"/scripts/*.sh
RC=0
ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base --tests 2>&1)" || RC=$?
check "a copy run elsewhere runs its own check scripts against the checked tree" \
  '[[ $RC == 1 && $ERR == *"copy of check-shell-portability read $repo"* ]]'
check "a copy run elsewhere points the spoke, options-docs and changelog-parity checks at the checked tree" \
  '[[ $ERR == *"copy of check-spoke-plugin-root read $repo"* && $ERR == *"copy of sync-plugin-options-docs read $repo"* && $ERR == *"copy of check-changelog-parity read $repo"* ]]'
check "a copy run elsewhere runs its own comment-hygiene against the checked tree" \
  '[[ $ERR == *"copy of check-comment-hygiene read $repo"* && $ERR != *"check-comment-hygiene ran"* ]]'
check "a copy run elsewhere skips the checked tree's tests" \
  '[[ $ERR == *"SKIP tests"* && $ERR != *"copy of affected-tests"* ]]'

mkdir -p "$repo/plugins/demo/skills/s"
printf 'x\n' >"$repo/plugins/demo/skills/s/notes.txt"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m skill
RC=0
# The copies exit 0 here: a failing static check would skip the slow ones, hiding the reason asserted.
ERR="$(cd "$tmp" && COPY_STUB_RC=0 CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
check "a copy run elsewhere skips changed-skills, which runs the checked tree's skill-quality code" \
  '[[ $ERR == *"SKIP changed-skills (runs the checked tree"* && $ERR != *"copy of check-changed-skills"* ]]'
git_test_config "$repo" reset -q --hard HEAD~1

# The options-docs generator writes the READMEs, so a branch that changes it and
# regenerates them fails the copy's older generator; a README-only drift is
# still the copy's to judge.
pre_docs="$(git_test_config "$repo" rev-parse HEAD)"
mkdir -p "$repo/plugins/demo"
printf '# Demo\n' >"$repo/plugins/demo/README.md"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m readme
RC=0
ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
check "a copy run elsewhere checks a README-only change with its own options-docs generator" \
  '[[ $RC == 1 && $ERR == *"copy of sync-plugin-options-docs read $repo"* && $ERR == *"FAIL plugin-options-docs"* ]]'
printf '# changed generator\n' >>"$repo/scripts/sync-plugin-options-docs.py"
git_test_config "$repo" commit -q -am generator
RC=0
ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
check "a copy run elsewhere skips options-docs when the branch changes the generator" \
  '[[ $ERR == *"SKIP plugin-options-docs (the branch changes the generator"* && $ERR != *"copy of sync-plugin-options-docs"* && $ERR != *"FAIL plugin-options-docs"* ]]'
run STUB_SYNC_PLUGIN_OPTIONS_DOCS=1 -- --base base
check "the branch's own run still checks options-docs when it changes the generator" \
  '[[ $RC == 1 && $ERR == *"FAIL plugin-options-docs"* ]]'
git_test_config "$repo" reset -q --hard "$pre_docs"

# machine-specific-paths loads the merge-base's patterns file, never the
# branch's, whose own edit here would make a home path pass.
printf '{"root": "/%s/alice/project"}\n' home >"$repo/settings.json"
printf "HPP_LINUX_USER_BODY='never-matches'\n" >>"$repo/$patterns_lib"
git_test_config "$repo" add -A
git_test_config "$repo" commit -q -m home-path
RC=0
ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
check "a copy run elsewhere scans with the merge-base's patterns file, not the checked tree's" \
  '[[ $ERR == *"FAIL machine-specific-paths"* && $ERR == *"Linux user path: settings.json:1:"* ]]'
run -- --base base
check "an in-place run scans with the merge-base's patterns file, not the branch's" \
  '[[ $ERR == *"FAIL machine-specific-paths"* && $ERR == *"Linux user path: settings.json:1:"* ]]'
git_test_config "$repo" reset -q --hard HEAD~1

# typos reads its exclusions from the checked tree's workflow, which is data.
sed -i.bak 's|exclude: plugins/.*|& legacy/samples/**|' "$workflow" && rm -f "$workflow.bak"
git_test_config "$repo" commit -q -am typos-exclude
RC=0
ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" STUB_TYPOS=1 bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
check "a copy run elsewhere takes the typos exclusions from the checked tree's workflow" \
  '[[ $ERR == *"--exclude legacy/samples/** "* ]]'
git_test_config "$repo" reset -q --hard HEAD~1

if command -v markdownlint-cli2 >/dev/null 2>&1; then
  printf '{ "config": { "MD013": false } }\n' >"$tools/.markdownlint-cli2.jsonc"
  mkdir -p "$repo/docs"
  printf 'require("fs").writeFileSync(%s, "x");\nmodule.exports = {};\n' "'$tmp/md-payload'" \
    >"$repo/docs/.markdownlint-cli2.cjs"
  printf '# Title\n\nText.\n' >"$repo/docs/a.md"
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -q -m docs
  RC=0
  ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere never loads the checked tree's markdownlint config" \
    '[[ ! -e $tmp/md-payload && $ERR != *"SKIP markdown ("* ]]'
  printf '# Title\nText.\n' >"$repo/docs/a.md"
  git_test_config "$repo" commit -q -am bad-md
  RC=0
  ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere still lints the checked tree's markdown" \
    '[[ $RC == 1 && $ERR == *"FAIL markdown"* && $ERR == *"MD022"* ]]'
  check "a copy run elsewhere says why it refused a JavaScript markdownlint config" \
    '[[ $ERR == *"SKIP markdown: config docs/.markdownlint-cli2.cjs (refused:"* ]]'
  pre_md="$(git_test_config "$repo" rev-parse HEAD)"

  # A branch-only nested config that is data exempts the files it covers.
  mkdir -p "$repo/legacy"
  printf '# Title\nText.\n' >"$repo/legacy/a.md"
  printf '{\n  // vendored, never restyled\n  "config": { "default": false, },\n}\n' >"$repo/legacy/.markdownlint-cli2.jsonc"
  git_test_config "$repo" rm -q docs/a.md
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -q -m legacy
  RC=0
  ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere honors a branch-only nested markdownlint config that is data" \
    '[[ $ERR != *"FAIL markdown"* && $ERR != *"SKIP markdown ("* && $ERR != *"config legacy/"* ]]'

  # A config naming a custom rule, reaching one through __proto__, or extending
  # another file is refused whole, so its exemption is not applied either.
  printf '{ "customRules": ["./rule.cjs"], "config": { "default": false } }\n' >"$repo/legacy/.markdownlint-cli2.jsonc"
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -q -m custom-rule
  RC=0
  ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere refuses a markdownlint config with customRules and lints with the merge-base's" \
    '[[ $RC == 1 && $ERR == *"FAIL markdown"* && $ERR == *"SKIP markdown: config legacy/.markdownlint-cli2.jsonc (refused:"*"customRules"* ]]'
  printf '{ "\\u005f_proto__": { "customRules": ["./rule.cjs"] }, "config": { "default": false } }\n' >"$repo/legacy/.markdownlint-cli2.jsonc"
  git_test_config "$repo" commit -q -am proto
  RC=0
  ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere refuses a markdownlint config that sets __proto__" \
    '[[ $RC == 1 && $ERR == *"FAIL markdown"* && $ERR == *"SKIP markdown: config legacy/.markdownlint-cli2.jsonc (refused:"*"__proto__"* ]]'
  git_test_config "$repo" rm -q legacy/.markdownlint-cli2.jsonc
  printf '{ "extends": "./rule.cjs", "default": false }\n' >"$repo/legacy/.markdownlint.json"
  git_test_config "$repo" add -A
  git_test_config "$repo" commit -q -m extends
  RC=0
  ERR="$(cd "$tmp" && CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --base base 2>&1)" || RC=$?
  check "a copy run elsewhere refuses a markdownlint config with extends" \
    '[[ $RC == 1 && $ERR == *"FAIL markdown"* && $ERR == *"SKIP markdown: config legacy/.markdownlint.json (refused:"*"extends"* ]]'
  git_test_config "$repo" reset -q --hard "$pre_md"
else
  ok "SKIP markdown copy cases (markdownlint-cli2 not installed)"
fi

# --uncommitted: the issue lane commits the files on disk through an API, with
# each file's mode taken from disk, so the checks judge the work tree as that
# commit, and the checkout itself is left untouched.
state() {
  git_test_config "$repo" rev-parse HEAD
  git_test_config "$repo" status --porcelain --untracked-files=all
  git_test_config "$repo" worktree list --porcelain
}
# shellcheck disable=SC2034  # read inside check's eval
before="$(state)"
printf '#!/usr/bin/env bash\necho hi\n' >"$repo/new-tool"
run -- --uncommitted
check "--uncommitted checks an untracked #! file's mode on disk" \
  '[[ $RC == 1 && $ERR == *"FAIL exec-bit"* && $ERR == *"new-tool starts with #!"* ]]'
# The issue lane's wrapper sets CHECK_DATA_ROOT to the checkout; the snapshot,
# not the checkout's committed state, is still what gets checked.
run CHECK_DATA_ROOT="$repo" -- --uncommitted
check "--uncommitted under the lane's CHECK_DATA_ROOT still checks the work tree" \
  '[[ $RC == 1 && $ERR == *"new-tool starts with #!"* ]]'
run CHECK_AFFECTED_SCRIPT_EXEC_BIT=1 -- --uncommitted
check "--uncommitted with CHECK_AFFECTED_SCRIPT_EXEC_BIT judges a new #! file as executable, as apply-patch commits it" \
  '[[ $RC == 0 && $OUT == *"over 1 changed files"* && ! -x $repo/new-tool ]]'
chmod +x "$repo/new-tool"
run -- --uncommitted
check "--uncommitted passes once the file is executable on disk" \
  '[[ $RC == 0 && $OUT == *"over 1 changed files"* ]]'
# The snapshot is this tree's own work tree, so --tests selects from that work
# tree, uncommitted edits included, as a committed run selects from its diff.
run STUB_STATUS_LOG="$tmp/status.log" -- --uncommitted --tests
check "--uncommitted --tests runs the suites over the uncommitted change" \
  '[[ $RC == 0 && $ERR != *"SKIP tests"* && $(cat "$tmp/status.log" 2>/dev/null) == *"?? new-tool"* ]]'
RC=0
ERR="$(cd "$tmp" && COPY_STUB_RC=0 CHECK_DATA_ROOT="$repo" bash "$tools/scripts/check-affected.sh" --uncommitted --tests 2>&1)" || RC=$?
check "a copy's --uncommitted --tests run still skips the checked tree's tests" \
  '[[ $ERR == *"SKIP tests (runs the checked tree"* && $ERR != *"copy of affected-tests"* ]]'
mkdir -p "$repo/plugins/demo"
printf 'x\n' >"$repo/plugins/demo/new.md"
printf '#!/usr/bin/env bash\necho "validate-plugins ran: $*" >&2\nexit 1\n' >"$repo/scripts/validate-plugins.sh"
chmod +x "$repo/scripts/validate-plugins.sh"
run PATH="$tmp/bin:$PATH" -- --uncommitted
check "--uncommitted validates a plugin that only untracked files touch" \
  '[[ $RC == 1 && $ERR == *"FAIL validate-plugins"* && $ERR == *"validate-plugins ran: --only demo"* ]]'
rm -rf "$repo/plugins/demo" "$repo/scripts/validate-plugins.sh"
# The lane's sandbox masks dotfiles in the checkout with /dev/null, a device git
# refuses to add; it is skipped and the regular untracked file still checked.
if bwrap --bind / / --dev /dev true 2>/dev/null; then
  chmod -x "$repo/new-tool"
  : >"$repo/.bash_profile"
  RC=0
  OUT="$(cd "$repo" && bwrap --bind / / --dev /dev --ro-bind /dev/null "$repo/.bash_profile" --ro-bind /dev/null "$repo/notes.txt" \
    bash scripts/check-affected.sh --uncommitted 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
  check "--uncommitted skips untracked and tracked device nodes and still checks the regular file beside it" \
    '[[ $RC == 1 && $ERR == *"new-tool starts with #!"* && $ERR != *"can only add regular files"* ]]'
  rm -f "$repo/.bash_profile"
  # The lane's sandbox can leave .git read-only; the snapshot must not write there.
  RC=0
  OUT="$(cd "$repo" && bwrap --bind / / --dev /dev --ro-bind "$repo/.git" "$repo/.git" \
    bash scripts/check-affected.sh --uncommitted --base base 2>"$tmp/err")" || RC=$?
  ERR="$(cat "$tmp/err")"
  check "--uncommitted runs the checks with a read-only .git" \
    '[[ $RC == 1 && $ERR == *"new-tool starts with #!"* && $ERR != *"Read-only file system"* ]]'
else
  ok "SKIP device-node and read-only .git cases (bwrap cannot start here)"
fi
rm -rf "$repo/new-tool"
# The inner run lints from the scratch repository, with the rcfile beside the
# outer copy of the script; an optional check the rcfile enables proves it read it.
if grep -q -- --rcfile <<<"$(shellcheck --help 2>&1)"; then
  cp "$SELF_DIR/../.shellcheckrc" "$repo/.shellcheckrc"
  printf '#!/usr/bin/env bash\nif [ -n "${1:-}" ]; then echo hi; fi\n' >"$repo/lint-me.sh"
  chmod +x "$repo/lint-me.sh"
  run -- --uncommitted
  check "--uncommitted lints a changed shell file with the repository's .shellcheckrc" \
    '[[ $RC == 1 && $ERR == *"FAIL shellcheck"* && $ERR == *"SC2292"* && $ERR != *"unrecognized option"* ]]'
  rm -f "$repo/.shellcheckrc" "$repo/lint-me.sh"
else
  ok "SKIP --uncommitted shellcheck case (no shellcheck with --rcfile here)"
fi
check "--uncommitted leaves HEAD, the index and the worktree list as they were" '[[ $(state) == "$before" ]]'
run -- --uncommitted
check "--uncommitted with no edits passes with nothing to check" '[[ $RC == 0 && $OUT == *"over 0 changed files"* ]]'

# The default job count is one less than the core count, at most 8 and at most
# one per 2 GiB of free memory, on a host whatever nproc and the memory files
# report; CHECK_AFFECTED_JOBS and --jobs still set it outright.
unset CHECK_AFFECTED_JOBS
mkdir -p "$tmp/nprocbin" "$tmp/cg/slice/scope/leaf"
printf '#!/usr/bin/env bash\necho "$STUB_NPROC"\n' >"$tmp/nprocbin/nproc"
chmod +x "$tmp/nprocbin/nproc"
printf 'MemTotal: 100663296 kB\nMemAvailable: 67108864 kB\n' >"$tmp/meminfo-64g"
printf 'MemAvailable: 6291456 kB\n' >"$tmp/meminfo-6g"
printf 'MemAvailable: 1048576 kB\n' >"$tmp/meminfo-1g"
# A slice capped at 10 GiB holding 6 GiB, 1 GiB of it inactive file cache: 5 GiB
# free under it. The scope below sets no cap of its own.
echo 10737418240 >"$tmp/cg/slice/memory.max"
echo 6442450944 >"$tmp/cg/slice/memory.current"
printf 'anon 5368709120\ninactive_file 1073741824\n' >"$tmp/cg/slice/memory.stat"
echo max >"$tmp/cg/slice/scope/memory.max"
echo 4294967296 >"$tmp/cg/slice/scope/memory.current"
jobs_env=(PATH="$tmp/nprocbin:$PATH" STUB_ARGS_LOG="$tmp/args.log" CHECK_AFFECTED_MEMINFO="$tmp/meminfo-64g" CHECK_AFFECTED_CGROUP_DIR="$tmp/no-cgroup")
run "${jobs_env[@]}" STUB_NPROC=24 -- --base base --tests
check "a 24-core host defaults to 8 jobs" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 8 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=4 -- --base base --tests
check "a 4-core host defaults to 3 jobs" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 3 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_MEMINFO="$tmp/meminfo-6g" -- --base base --tests
check "6 GiB of MemAvailable caps a 24-core host at 3 jobs" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 3 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_CGROUP_DIR="$tmp/cg/slice/scope" -- --base base --tests
check "a parent cgroup with 5 GiB free caps a 64 GiB host at 2 jobs" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 2 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_CGROUP_DIR="$tmp/cg/slice/scope/leaf" -- --base base --tests
check "a leaf cgroup with no memory files still takes an ancestor's cap" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 2 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_MEMINFO="$tmp/meminfo-1g" -- --base base --tests
check "under 2 GiB free still runs 1 job" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 1 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_MEMINFO="$tmp/no-meminfo" -- --base base --tests
check "with no meminfo the core cap alone applies" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 8 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_MEMINFO="$tmp/meminfo-1g" CHECK_AFFECTED_JOBS=6 -- --base base --tests
check "CHECK_AFFECTED_JOBS sets the job count past the memory cap" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 6 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_JOBS=16 -- --base base --tests
check "CHECK_AFFECTED_JOBS sets the job count past the default cap" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 16 "* ]]'
run "${jobs_env[@]}" STUB_NPROC=24 CHECK_AFFECTED_JOBS=16 -- --base base --tests --jobs 12
check "--jobs sets the job count over CHECK_AFFECTED_JOBS and the cap" '[[ $RC == 0 && $(cat "$tmp/args.log") == *"--jobs 12 "* ]]'

# The stale-base check judges the base as resolved at the start of the run,
# not a remote-tracking ref another worktree's fetch moves while it runs. The
# real check runs; the shell-portability stub, which runs before it, moves
# origin/main to a commit that touches the branch's notes.txt.
cp "$SELF_DIR/check-stale-base-overlap.sh" "$repo/scripts/"
cp "$SELF_DIR/lib/changed-files.sh" "$SELF_DIR/lib/gate-entry.sh" "$repo/scripts/lib/"
moved="$(git_test_config "$repo" commit-tree "HEAD^{tree}" -p base -m moved)"
printf '#!/usr/bin/env bash\n[[ -z "${STUB_MOVE_TO:-}" ]] || git update-ref refs/remotes/origin/main "$STUB_MOVE_TO"\n' \
  >"$repo/scripts/check-shell-portability.sh"
git_test_config "$repo" update-ref refs/remotes/origin/main "$(git_test_config "$repo" rev-parse base)"
run STUB_MOVE_TO="$moved" -- --base origin/main --no-fetch
check "a base that moves after the run starts does not fail stale-base-overlap" \
  '[[ $RC == 0 && $ERR != *"stale-base-overlap"* ]]'
git_test_config "$repo" update-ref refs/remotes/origin/main "$moved"
run -- --base origin/main --no-fetch
check "a branch behind its base at the start on an overlapping path fails stale-base-overlap" \
  '[[ $RC == 1 && $ERR == *"FAIL stale-base-overlap"* && $ERR == *"notes.txt"* ]]'
git_test_config "$repo" checkout -q -- scripts/check-stale-base-overlap.sh scripts/check-shell-portability.sh
rm -f "$repo/scripts/lib/changed-files.sh" "$repo/scripts/lib/gate-entry.sh"

run -- --bogus
check "an unknown flag is a usage error" '[[ $RC == 2 ]]'
run -- --jobs 0
check "a --jobs count below one is a usage error" '[[ $RC == 2 && $ERR == *"--jobs N"* ]]'
run -- --budget 0
check "a --budget below one second is a usage error" '[[ $RC == 2 && $ERR == *"--budget S"* ]]'
run -- --base no-such-ref
check "an unresolvable base is exit 2" '[[ $RC == 2 && $ERR == *"merge-base"* ]]'

test_harness::report
