#!/usr/bin/env bash
# Tests for scripts/plan-test-lanes.sh: every selected suite lands on exactly one
# leg of the lane of its ecosystem, the legs are sized from suite-seconds, a lane
# goes wider than the selection only where the planner's header says, and a
# selected suite no lane runs fails the plan. The fixture cases run a copy of
# the planner and the selector in a throwaway repo; the LIVE cases hold the
# real tree: scripts/test-windows-plan.txt names exactly the steps
# pr-test-windows.yml gates.
# test-scope: .github/workflows/pr-test-windows.yml
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

repo="" scratch=""
fixture_tree::build repo --sut plan-test-lanes.sh --sut affected-tests.sh --sut run-plugin-tests.sh \
  --git --label plan-test-lanes || exit 1
# Outside the fixture repo: an untracked file there is part of every --base diff.
fixture_tree::build scratch --label plan-test-lanes-err || exit 1
ERR="$scratch/plan.err"

cp "$REPO_ROOT/scripts/affected-tests-no-suite.txt" "$repo/scripts/"
: >"$repo/scripts/run-plugin-tests-serial.txt"
printf 'plugins/knowledge/vendor/repo-analysis\n' >"$repo/scripts/outside-node-packages.txt"
printf 'plugins/fx/evals/fixtures/\n' >"$repo/scripts/outside-node-exclusions.txt"

# mk <path> [<content>]: a fixture file.
mk() {
  mkdir -p "$repo/$(dirname "$1")"
  printf '%s\n' "${2:-# $1}" >"$repo/$1"
}
# The selector refuses a tree with no shared-library manifest; one canonical-only
# source satisfies it.
mk lib/widget.sh "widget() { :; }"
mk scripts/sync-widget.sh "[ \"\$1\" = --print-manifest ] && printf 'src\\tlib/widget.sh\\n'"
for s in a b c d e f g h; do
  mk "plugins/$s/$s.sh" "echo $s"
  mk "plugins/$s/$s.test.sh" "bash \"\$(dirname \"\$0\")/$s.sh\""
done
mk plugins/animation/anim.sh
mk plugins/animation/anim.test.sh
mk plugins/speech/sp.sh
mk plugins/speech/sp.test.sh
mk plugins/harness-ops/skills/inventory/inv.sh
mk plugins/harness-ops/skills/inventory/inv.test.sh
mk plugins/p/p.py "VALUE = 1"
mk plugins/p/test_p.py "from p import VALUE"
mk plugins/q/test_q.py "assert True"
mk plugins/fx/evals/fixtures/test_fx.py "assert True"
mk plugins/fx/evals/fixtures/fx.test.js "// fixture"
mk lib/w.mjs "export const w = 1;"
mk lib/w.test.mjs "import { w } from './w.mjs';"
mk lib/w.test.sh "node w.test.mjs"
mk plugins/knowledge/vendor/repo-analysis/index.js "module.exports = 1;"
mk plugins/knowledge/vendor/repo-analysis/index.test.js "require('./index.js');"
mk plugins/knowledge/vendor/repo-analysis/package.json '{"scripts":{"test":"node --test"}}'
mk plugins/knowledge/skills/video-digest/extraction/package.json \
  '{"dependencies":{"@melodic/repo-analysis":"file:../../../vendor/repo-analysis"}}'
mk plugins/orphan/o.js "module.exports = 1;"
mk plugins/orphan/o.test.js "require('./o.js');"
mk plugins/ps/x.ps1 "function X {}"
mk plugins/ps/x.Tests.ps1 ". \$PSScriptRoot/x.ps1"
mk plugins/z/data.cfg "k=v"
mk plugins/z/z.sh "echo z"
mk .github/actions/download-full-history/action.yml "name: download-full-history"
mk .github/actions/other/action.yml "name: other"
mk docs/conventions/pr-pipeline/pr-pipeline.schema.json "{}"
mk .python-version 3.14
mk pyproject.toml "[project]"
mk .node-version 24
mk .github/workflows/pr-require-checks.yml "name: ci"
mk .github/workflows/pr-test-windows.yml "name: test-windows"
printf '%s\n' "# seconds" \
  "plugins/a/a.test.sh 100" "plugins/b/b.test.sh 30" "plugins/c/c.test.sh 90" "plugins/d/d.test.sh 60" \
  "plugins/e/e.test.sh 50" "plugins/f/f.test.sh 40" "plugins/g/g.test.sh 20" "plugins/h/h.test.sh 10" \
  "plugins/p/test_p.py 200" "plugins/q/test_q.py 100" >"$repo/scripts/suite-seconds.txt"
printf '%s\n' "# job key [pattern...]" \
  "win-a plugins/a/a.test.sh" \
  "win-b plugins/ps/run.ps1 plugins/ps/*.Tests.ps1" \
  "win-b plugins/b/b.test.sh" >"$repo/scripts/test-windows-plan.txt"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm base >/dev/null

OUT="" RC=0
plan() {
  OUT="$(cd "$repo" && bash scripts/plan-test-lanes.sh "$@" 2>"$ERR")" && RC=0 || RC=$?
}
key() { sed -n "s/^$1=//p" <<<"$OUT"; }
# suites <lane>: every suite of the lane's plan, one per line, sorted.
suites() { key "$1_plan" | jq -r '.[][]' | tr -d '\r' | LC_ALL=C sort; }
check() { # <label> <condition-rc>
  if [[ "$2" -eq 0 ]]; then ok "$1"; else fail "$1 (rc=$RC) $(cat "$ERR") $OUT"; fi
}
is() { [[ "$1" == "$2" ]]; }
same() { [[ -n "$1" && "$1" == "$2" ]]; }

# --- the selection, by ecosystem --------------------------------------------

plan -- plugins/a/a.sh plugins/b/b.sh
is "$(suites bash | tr '\n' ' ')" "plugins/a/a.test.sh plugins/b/b.test.sh " &&
  is "$(key bash_legs)" "[0,1]" && is "$(key python)" false && is "$(key node)" false
check "two shell changes plan their two siblings on ceil(130/120) = 2 legs" $?

is "$(key bash_plan)" '{"0":["plugins/a/a.test.sh"],"1":["plugins/b/b.test.sh"]}'
check "the longest suite goes first, each to the least-loaded leg" $?

is "$(key windows_jobs)" '["win-a","win-b"]' && is "$(key windows_steps)" '["plugins/a/a.test.sh","plugins/b/b.test.sh"]'
check "test-windows runs the steps whose suites the change selects, and their jobs" $?

plan -- plugins/a/a.sh plugins/b/b.sh plugins/c/c.sh plugins/d/d.sh plugins/e/e.sh plugins/f/f.sh plugins/g/g.sh plugins/h/h.sh
is "$(key bash_legs)" "[0,1,2,3]" && is "$(suites bash | wc -l | tr -d ' ')" 8 &&
  is "$(key bash_plan | jq -r '[.[][]] | length' | tr -d '\r')" 8 &&
  is "$(key bash_plan | jq -r '[.[][]] | unique | length' | tr -d '\r')" 8
check "400 suite-seconds take 4 legs, and the 8 suites land on them exactly once" $?

grep -q 'bash: 8 suite(s), 400 suite-seconds, 4 leg(s): 100s/1 110s/2 100s/3 90s/2' "$ERR"
check "longest first to the least-loaded leg keeps the legs within 20 s of each other" $?

plan -- plugins/a/a.sh plugins/g/g.sh
before="$(key bash_legs)"
printf 'plugins/g/g.test.sh\n' >"$repo/scripts/run-plugin-tests-serial.txt"
plan -- plugins/a/a.sh plugins/g/g.sh
: >"$repo/scripts/run-plugin-tests-serial.txt"
is "$before" "[0]" && is "$(key bash_legs)" "[0,1]"
check "a suite that runs alone weighs three times its seconds: 100 + 3 x 20 needs a second leg" $?

plan -- plugins/animation/anim.sh plugins/harness-ops/skills/inventory/inv.sh plugins/a/a.sh plugins/c/c.sh
is "$(key bash_needs)" '{"0":"","1":"animation inventory duckdb"}'
check "a leg's needs name the optional toolchains of its own suites only" $?

plan -- plugins/speech/sp.sh
is "$(key bash_needs)" '{"0":"animation"}'
check "a speech suite gets the animation wheels, where its numpy comes from" $?

plan -- plugins/p/p.py
is "$(suites python)" "plugins/p/test_p.py" && is "$(key bash)" false && is "$(key python_legs)" "[0]"
check "a Python change plans its test module on test-python, and test-bash has no work" $?

plan -- .python-version
is "$(suites python | tr '\n' ' ')" "plugins/p/test_p.py plugins/q/test_q.py " && is "$(key python_legs)" "[0,1]"
check "a Python pin runs every Python suite but the eval fixtures, on ceil(300/180) = 2 legs" $?
is "$(key windows_jobs)" '["win-a","win-b"]'
check "the Python version pin runs every Windows step, whose jobs set up Python from it" $?
plan -- pyproject.toml
is "$(key windows_jobs)" '[]' && is "$(key python)" true
check "another Python pin runs the Python suites but no Windows step" $?

plan -- lib/w.mjs
is "$(suites bash)" "lib/w.test.sh" && is "$(key node)" false
check "a Node suite with a sibling .test.sh runs through it on test-bash" $?

plan -- plugins/knowledge/vendor/repo-analysis/index.js
is "$(key node_packages)" "plugins/knowledge/skills/video-digest/extraction plugins/knowledge/vendor/repo-analysis" &&
  is "$(key node)" true
check "a vendor change runs its package and the package that takes it as a file: dependency" $?

plan -- plugins/orphan/o.js
[[ "$RC" -eq 2 ]] && grep -q 'plugins/orphan/o.test.js is a selected Node suite that no lane runs' "$ERR"
check "a selected Node suite with no wrapper and no package fails the plan" $?

plan -- plugins/fx/evals/fixtures/fx.test.js
[[ "$RC" -eq 0 ]] && is "$(key node)" false
check "a Node eval fixture is data, not a suite" $?

plan -- docs/conventions/pr-pipeline/pr-pipeline.schema.json
is "$(key node_packages)" ".github/actions/resolve-config" && is "$(key node)" true
check "a change under a package's trigger directory runs that package" $?

plan -- .node-version
is "$(key node_packages | wc -w | tr -d ' ')" 6
check "a Node pin runs every Node package" $?

plan -- plugins/ps/x.ps1
is "$(key windows_steps)" '["plugins/ps/run.ps1"]' && is "$(key windows_jobs)" '["win-b"]' && is "$(key bash)" false
check "a Pester suite starts the test-windows step a pattern names, and no Linux lane" $?

plan -- plugins/z/data.cfg
is "$(key unmapped)" 1 && is "$(key bash)" false && is "$(key python)" false
check "an unmapped data file runs no corpus and is counted" $?

plan -- plugins/z/z.sh
is "$(key unmapped)" 1 && is "$(suites bash | wc -l | tr -d ' ')" 12 && is "$(key python)" false
check "an unmapped shell file runs the whole shell corpus and is counted" $?

# --- wider than the selection ------------------------------------------------

plan -- .github/workflows/pr-require-checks.yml
is "$(key bash_legs)" "[0,1,2,3,4,5]" && is "$(suites bash | wc -l | tr -d ' ')" 12 &&
  is "$(suites python | wc -l | tr -d ' ')" 2 && is "$(key node_packages | wc -w | tr -d ' ')" 6 &&
  is "$(key windows_jobs)" "[]"
check "a pr-require-checks.yml change runs every pr-require-checks.yml lane whole on 6 legs, and test-windows from the selection" $?

plan -- .github/actions/download-full-history/action.yml
is "$(key bash_legs)" "[0,1,2,3,4,5]" && is "$(key windows_jobs)" '["win-a","win-b"]'
check "the local action every lane runs plans every lane whole" $?

plan -- .github/actions/other/action.yml
is "$(key bash)" false && is "$(key python)" false && is "$(key windows_jobs)" "[]"
check "another local action plans no lane whole" $?

plan -- .github/workflows/pr-test-windows.yml
is "$(key windows_jobs)" '["win-a","win-b"]' && is "$(key bash)" false
check "a pr-test-windows.yml change runs every Windows step and no pr-require-checks.yml lane" $?

plan
is "$(suites bash)" "$(cd "$repo" && bash scripts/run-plugin-tests.sh --list | LC_ALL=C sort)" &&
  is "$(key bash_legs)" "[0,1,2,3,4,5]"
check "the whole tree plans the runner's whole corpus on 6 legs" $?

# --- a diff base ---------------------------------------------------------------

printf 'echo changed\n' >>"$repo/plugins/c/c.sh"
plan --base HEAD
is "$(suites bash)" "plugins/c/c.test.sh"
check "--base plans the working tree's change since the merge base" $?
git_test_config "$repo" checkout -q -- plugins/c/c.sh

plan --base HEAD -- plugins/a/a.sh
is "$RC" 2
check "--base and explicit paths together are a usage error" $?
plan --base
is "$RC" 2
check "--base with no ref is a usage error" $?

# --- LIVE: the real tree -------------------------------------------------------
# The whole-tree plan of the live tree reads every file, so it is the
# `test-plan-corpus` gate step of pr-require-checks.yml's lint-repo job, which
# runs on every pull request, not a case here.

# The (job, key) pairs pr-test-windows.yml gates on, against the plan's lines.
yml_pairs="$(awk '
  /^  [A-Za-z0-9_-]+:[[:blank:]]*$/ { job = $1; sub(/:$/, "", job) }
  match($0, /outputs\.steps\), '\''[^'\'']+'\''\)/) {
    k = substr($0, RSTART, RLENGTH); sub(/^outputs\.steps\), '\''/, "", k); sub(/'\''\)$/, "", k)
    print job " " k
  }' "$REPO_ROOT/.github/workflows/pr-test-windows.yml" | LC_ALL=C sort -u)"
plan_pairs="$(awk '!/^[[:blank:]]*(#|$)/ { print $1 " " $2 }' "$REPO_ROOT/scripts/test-windows-plan.txt" | LC_ALL=C sort -u)"
same "$yml_pairs" "$plan_pairs"
check "live: pr-test-windows.yml gates exactly the steps scripts/test-windows-plan.txt names" $?
yml_jobs="$(awk '
  /^  [A-Za-z0-9_-]+:[[:blank:]]*$/ { job = $1; sub(/:$/, "", job) }
  match($0, /outputs\.jobs \|\| '\''\[\]'\''\), '\''[^'\'']+'\''\)/) {
    k = substr($0, RSTART, RLENGTH); sub(/^.*\), '\''/, "", k); sub(/'\''\)$/, "", k)
    print (k == job ? job : "MISMATCH " job " gates on " k)
  }' "$REPO_ROOT/.github/workflows/pr-test-windows.yml" | LC_ALL=C sort -u)"
same "$yml_jobs" "$(cut -d' ' -f1 <<<"$plan_pairs" | LC_ALL=C sort -u)"
check "live: every pr-test-windows.yml job gates on the plan's job list under its own name" $?

test_harness::report
