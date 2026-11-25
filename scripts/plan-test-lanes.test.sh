#!/usr/bin/env bash
# test-scope: .github/workflows/pr-test-platforms.yml
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
fixture_tree::build scratch --label plan-test-lanes-err || exit 1
ERR="$scratch/plan.err"

cp "$REPO_ROOT/scripts/affected-tests-no-suite.txt" "$REPO_ROOT/scripts/node-subprojects.txt" "$repo/scripts/"
: >"$repo/scripts/run-plugin-tests-serial.txt"
printf '%s\n' plugins/knowledge/vendor/repo-analysis .github/actions/check-signed-commits .github/actions/check-wip-cap \
  .github/actions/log-api-budget .github/scripts/lib .github/scripts/pr-merge .github/scripts/pr-verify \
  scripts/lane-transcripts >"$repo/scripts/outside-node-packages.txt"
printf 'plugins/fx/evals/fixtures/\n' >"$repo/scripts/outside-node-exclusions.txt"

mk() {
  mkdir -p "$repo/$(dirname "$1")"
  printf '%s\n' "${2:-# $1}" >"$repo/$1"
}
mk lib/widget.sh "widget() { :; }"
mk scripts/sync-widget.sh "[ \"\$1\" = --print-manifest ] && printf 'src\\tlib/widget.sh\\n'"
for s in a b c d e f g h; do
  mk "plugins/$s/$s.sh" "echo $s"
  mk "plugins/$s/$s.test.sh" "bash \"\$(dirname \"\$0\")/$s.sh\""
done
mk plugins/a/a.css "p {}"
printf 'cat a.css\n' >>"$repo/plugins/a/a.test.sh"
printf 'plugins/a/*.css # a stylesheet no Windows step reads\n' >"$repo/scripts/test-windows-inert-paths.txt"
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
mk .github/workflows/pr-test-platforms.yml "name: test-windows"
printf '%s\n' "# seconds" \
  "plugins/a/a.test.sh 100" "plugins/b/b.test.sh 30" "plugins/c/c.test.sh 90" "plugins/d/d.test.sh 60" \
  "plugins/e/e.test.sh 50" "plugins/f/f.test.sh 40" "plugins/g/g.test.sh 20" "plugins/h/h.test.sh 10" \
  "plugins/p/test_p.py 200" "plugins/q/test_q.py 100" \
  "plugins/animation/anim.test.sh 5" "plugins/speech/sp.test.sh 5" \
  "plugins/harness-ops/skills/inventory/inv.test.sh 5" >"$repo/scripts/suite-seconds.txt"
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
suites() { key "$1_plan" | jq -r '.[][]' | tr -d '\r' | LC_ALL=C sort; }
check() {
  if [[ "$2" -eq 0 ]]; then ok "$1"; else fail "$1 (rc=$RC) $(cat "$ERR") $OUT"; fi
}
is() { [[ "$1" == "$2" ]]; }
same() { [[ -n "$1" && "$1" == "$2" ]]; }

plan -- plugins/a/a.sh plugins/b/b.sh
is "$(suites bash | tr '\n' ' ')" "plugins/a/a.test.sh plugins/b/b.test.sh " &&
  is "$(key python)" false && is "$(key node)" false
check "two shell changes plan their two siblings" $?

is "$(key bash_plan)" '{"0":["plugins/a/a.test.sh","plugins/b/b.test.sh"]}'
check "the fewest legs that keep the budget's critical path are the plan" $?

is "$(key windows_jobs)" '["win-a","win-b"]' && is "$(key windows_steps)" '["plugins/a/a.test.sh","plugins/b/b.test.sh"]'
check "test-windows runs the steps whose suites the change selects, and their jobs" $?

plan -- plugins/a/a.sh plugins/b/b.sh plugins/c/c.sh plugins/d/d.sh plugins/e/e.sh plugins/f/f.sh plugins/g/g.sh plugins/h/h.sh
is "$(key bash_legs)" "[0,1]" && is "$(suites bash | wc -l | tr -d ' ')" 8 &&
  is "$(key bash_plan | jq -r '[.[][]] | length' | tr -d '\r')" 8 &&
  is "$(key bash_plan | jq -r '[.[][]] | unique | length' | tr -d '\r')" 8
check "400 suite-seconds the budget puts on 4 legs (critical path 100 s) fit 2, each suite once" $?

grep -q 'bash: 8 suite(s), 400 suite-seconds, 2 leg(s): 190s/4 210s/4' "$ERR"
check "a leg weighs its suite-seconds plus its longest suite's share of the other workers" $?

plan -- plugins/a/a.sh plugins/d/d.sh plugins/f/f.sh plugins/g/g.sh plugins/h/h.sh
is "$(key bash_plan)" '{"0":["plugins/a/a.test.sh","plugins/d/d.test.sh","plugins/f/f.test.sh","plugins/g/g.test.sh","plugins/h/h.test.sh"]}'
check "a short suite rides on the longest suite's leg when that leg still ends with it" $?

cp "$repo/scripts/suite-seconds.txt" "$scratch/suite-seconds.txt"
many=()
for i in $(seq -w 1 79); do
  mk "plugins/n/n$i.test.sh" "true"
  printf 'plugins/n/n%s.test.sh 40\n' "$i" >>"$repo/scripts/suite-seconds.txt"
  many+=("plugins/n/n$i.test.sh")
done
plan -- plugins/a/a.test.sh "${many[@]}"
rm -rf "${repo:?}/plugins/n"
cp "$scratch/suite-seconds.txt" "$repo/scripts/suite-seconds.txt"
grep -q 'bash: 80 suite(s), 3260 suite-seconds, 10 leg(s): 220s/4 ' "$ERR"
check "the longest suite's leg keeps room: its other workers finish well before it" $?

plan -- plugins/a/a.sh plugins/g/g.sh
before="$(key bash_legs)"
printf 'plugins/g/g.test.sh\n' >"$repo/scripts/run-plugin-tests-serial.txt"
plan -- plugins/a/a.sh plugins/g/g.sh
: >"$repo/scripts/run-plugin-tests-serial.txt"
is "$before" "[0]" && is "$(key bash_legs)" "[0,1]"
check "a suite that runs alone weighs three times its seconds: 100 + 3 x 20 needs a second leg" $?

printf 'plugins/g/g.test.sh\n' >"$repo/scripts/run-plugin-tests-serial.txt"
plan -- plugins/d/d.sh plugins/e/e.sh plugins/g/g.sh plugins/h/h.sh
: >"$repo/scripts/run-plugin-tests-serial.txt"
is "$(key bash_plan)" '{"0":["plugins/d/d.test.sh","plugins/h/h.test.sh"],"1":["plugins/g/g.test.sh","plugins/e/e.test.sh"]}'
check "a leg's serial suites run before its longest suite can start, so they add to its weight" $?

plan -- plugins/animation/anim.sh plugins/harness-ops/skills/inventory/inv.sh plugins/a/a.sh plugins/c/c.sh
is "$(key bash_needs)" '{"0":"","1":"animation inventory duckdb"}'
check "a leg's needs name the optional toolchains of its own suites only" $?

plan -- plugins/speech/sp.sh
is "$(key bash_needs)" '{"0":"animation"}'
check "a speech suite gets the animation wheels, where its numpy comes from" $?

mk plugins/testing/skills/check-visual-parity/scripts/vc.sh
mk plugins/testing/skills/check-visual-parity/scripts/vc.test.sh
plan -- plugins/testing/skills/check-visual-parity/scripts/vc.sh
is "$(key bash_needs)" '{"0":"visualcheck"}'
check "a check-visual-parity suite gets the visual-compare packages" $?
rm -rf "$repo/plugins/testing"

for part in a b c; do
  mk "plugins/planning/shared/tests/ui-$part.test.sh"
  plan -- "plugins/planning/shared/tests/ui-$part.test.sh"
  is "$(key bash_needs)" '{"0":"browser"}'
  check "the shared-page UI suite's part $part gets Chromium on whatever leg it lands" $?
done
mk plugins/planning/shared/tests/ui-require-browser.test.sh
plan -- plugins/planning/shared/tests/ui-require-browser.test.sh
is "$(key bash_needs)" '{"0":""}'
check "the UI runner's own suite, which runs stubs, gets no Chromium" $?
for part in a b c; do
  mk "plugins/planning/shared/tests/align-$part.test.sh"
  plan -- "plugins/planning/shared/tests/align-$part.test.sh"
  is "$(key bash_needs)" '{"0":"browser"}'
  check "the shared-page alignment suite's part $part gets Chromium on whatever leg it lands" $?
done
rm -rf "$repo/plugins/planning"

for plugin in guardrails code-tidying; do
  mk "plugins/$plugin/git-hooks/lefthook-remote.test.sh"
  plan -- "plugins/$plugin/git-hooks/lefthook-remote.test.sh"
  is "$(key bash_needs)" '{"0":"lefthook"}'
  check "the $plugin remote's end-to-end suite gets lefthook on whatever leg it lands" $?
  rm -rf "$repo/plugins/$plugin"
done

mk plugins/playwright/skills/demo-video/requirements.txt "numpy==2.5.4"
mk plugins/playwright/skills/demo-video/scripts/demo-video.test.sh \
  "# test-scope: plugins/playwright/skills/demo-video/scripts/* plugins/playwright/skills/demo-video/requirements.txt"
plan -- plugins/playwright/skills/demo-video/requirements.txt
is "$(key bash_plan)" '{"0":["plugins/playwright/skills/demo-video/scripts/demo-video.test.sh"]}' &&
  is "$(key bash_needs)" '{"0":"animation demovideo mediarender"}'
check "a demo-video requirements change puts the demovideo toolchain in its leg's needs" $?
rm -rf "$repo/plugins/playwright"

mk plugins/locks/locks.test.sh "# test-scope: .github/requirements-ci.txt .github/requirements-relock.txt plugins/animation/requirements.txt plugins/playwright/skills/demo-video/requirements.txt lib/media-render/requirements.txt"
for lock in .github/requirements-ci.txt plugins/animation/requirements.txt \
  plugins/playwright/skills/demo-video/requirements.txt lib/media-render/requirements.txt; do
  mk "$lock" "numpy==2.5.4"
  plan -- "$lock" plugins/c/c.sh plugins/a/a.sh
  is "$(key bash_needs | jq -r '.["0"]' | tr -d '\r')" "animation demovideo mediarender" &&
    is "$(key bash_needs | jq -r '[.[]] | map(select(test("demovideo"))) | length' | tr -d '\r')" 1
  check "a change to $lock installs every co-installed lock together on leg 0 only" $?
done
mk .github/requirements-relock.txt "numpy==2.5.4"
plan -- .github/requirements-relock.txt
is "$(key bash_needs)" '{"0":""}'
check "a change to a lock the test-bash step never installs brings no lock toolchain" $?
rm -rf "$repo/plugins/locks" "$repo/plugins/animation/requirements.txt" "$repo/plugins/playwright" "$repo/lib/media-render" \
  "$repo/.github/requirements-ci.txt" "$repo/.github/requirements-relock.txt"

mk lib/media-render/media-render.test.sh "# test-scope: lib/media-render/*"
mk plugins/explainer-video/scripts/explainer-video.test.sh "# test-scope: plugins/explainer-video/scripts/*"
plan -- lib/media-render/media_encode.py plugins/explainer-video/scripts/stills.py
is "$(key bash_needs)" '{"0":"mediarender"}'
check "the media-render and explainer-video suites get the mediarender toolchain" $?
rm -rf "$repo/lib/media-render" "$repo/plugins/explainer-video"

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
plan -- plugins/animation/requirements.txt
is "$(suites python | tr '\n' ' ')" "plugins/p/test_p.py plugins/q/test_q.py "
check "the animation lock test-python installs is a Python pin" $?

mk plugins/u/test_u.py "assert True"
plan -- plugins/p/p.py plugins/q/test_q.py plugins/u/test_u.py
grep -q 'python: 3 suite(s), 450 suite-seconds, 3 leg(s)' "$ERR"
check "an unlisted Python suite counts the mean of the listed ones, so 200 + 100 + 150 take 3 legs" $?

cp "$repo/scripts/suite-seconds.txt" "$scratch/suite-seconds.txt"
for i in $(seq 1 20); do printf 'plugins/one/test_one%s.py 1\n' "$i"; done >>"$repo/scripts/suite-seconds.txt"
plan -- plugins/u/test_u.py
grep -q 'python: 1 suite(s), 15 suite-seconds, 1 leg(s)' "$ERR"
check "with many 1 s rows an unlisted Python suite still weighs their mean (15), above the 5 s default" $?
grep -v 'test_[pq][.]py' "$repo/scripts/suite-seconds.txt" >"$scratch/light.txt"
cp "$scratch/light.txt" "$repo/scripts/suite-seconds.txt"
plan -- plugins/u/test_u.py
grep -q 'python: 1 suite(s), 5 suite-seconds, 1 leg(s)' "$ERR"
check "an unlisted Python suite never weighs less than the 5 s default" $?
cp "$scratch/suite-seconds.txt" "$repo/scripts/suite-seconds.txt"
rm -f "$repo/plugins/u/test_u.py"

cp "$repo/scripts/suite-seconds.txt" "$scratch/suite-seconds.txt"
for s in r s t u v w x y m; do mk "plugins/$s/test_$s.py" "assert True"; done
printf '%s\n' "plugins/r/test_r.py 190" "plugins/s/test_s.py 180" "plugins/t/test_t.py 170" \
  "plugins/u/test_u.py 160" "plugins/v/test_v.py 150" "plugins/w/test_w.py 140" \
  "plugins/x/test_x.py 130" "plugins/y/test_y.py 120" "plugins/m/test_m.py 110" >>"$repo/scripts/suite-seconds.txt"
plan -- .python-version
for s in r s t u v w x y m; do rm -rf "${repo:?}/plugins/$s"; done
cp "$scratch/suite-seconds.txt" "$repo/scripts/suite-seconds.txt"
is "$(key python_legs)" "[0,1,2,3,4,5,6,7,8]" &&
  grep -q 'python: 11 suite(s), 1650 suite-seconds, 9 leg(s): 200s/1 190s/1 180s/1 170s/1 160s/1 150s/1 140s/1 230s/2 230s/2' "$ERR"
check "test-python packs by suite-seconds onto at most 9 legs, longest first to the least-loaded leg" $?

plan -- lib/w.mjs
is "$(suites bash)" "lib/w.test.sh" && is "$(key node)" false
check "a Node suite with a sibling .test.sh runs through it on test-bash" $?

plan -- plugins/knowledge/vendor/repo-analysis/index.js
is "$(key node_packages)" "plugins/knowledge/skills/video-digest/extraction plugins/knowledge/vendor/repo-analysis" &&
  is "$(key node)" true
check "a vendor change runs its package and the package that takes it as a file: dependency" $?

mk plugins/knowledge/scripts/work-root.mjs "export const root = 1;"
mk plugins/knowledge/scripts/work-root.test.sh "bash \"\$(dirname \"\$0\")/work-root.mjs\""
plan -- plugins/knowledge/scripts/work-root.mjs
rm -rf "${repo:?}/plugins/knowledge/scripts"
is "$(key node_packages)" "plugins/knowledge/skills/video-digest/extraction plugins/knowledge/skills/course-digest/extraction" &&
  is "$(key node)" true
check "a change to the knowledge plugin's shared scripts runs both extraction packages" $?

plan -- plugins/orphan/o.js
[[ "$RC" -eq 2 ]] && grep -q 'plugins/orphan/o.test.js is a selected Node suite that no lane runs' "$ERR"
check "a selected Node suite with no wrapper and no package fails the plan" $?

cp "$repo/scripts/node-subprojects.txt" "$scratch/node-subprojects.saved"
printf '# no rows\n' >"$repo/scripts/node-subprojects.txt"
plan -- plugins/orphan/o.js
[[ "$RC" -eq 2 ]] && grep -q 'node-subprojects.txt has no rows' "$ERR"
check "an empty sub-project list stops the plan instead of matching every suite" $?

printf 'plugins/x/server\n' >"$repo/scripts/node-subprojects.txt"
plan -- plugins/orphan/o.js
[[ "$RC" -eq 2 ]] && grep -q "row 'plugins/x/server' has no owner directory" "$ERR"
check "a sub-project row with no owner stops the plan" $?
cp "$scratch/node-subprojects.saved" "$repo/scripts/node-subprojects.txt"

plan -- plugins/fx/evals/fixtures/fx.test.js
[[ "$RC" -eq 0 ]] && is "$(key node)" false
check "a Node eval fixture is data, not a suite" $?

plan -- docs/conventions/pr-pipeline/pr-pipeline.schema.json
is "$(key node_packages)" ".github/actions/resolve-config" && is "$(key node)" true
check "a change under a package's trigger directory runs that package" $?

plan -- .github/scripts/pr-unblock/feedback-dispatch.mjs
is "$(key node_packages)" ".github/actions/resolve-config" && is "$(key node)" true
check "a change to a package's later trigger file runs that package" $?

plan -- .github/scripts/pr-unblock/report-escalation.sh
rc=0
[[ " $(key node_packages) " != *" .github/actions/resolve-config "* ]] || rc=1
check "a sibling of a trigger file does not run that package" "$rc"

EVERY_WORKFLOW=".github/actions/resolve-config .github/actions/check-signed-commits .github/actions/check-wip-cap \
.github/actions/log-api-budget .github/scripts/lib .github/scripts/pr-merge scripts/lane-transcripts"

plan -- .github/workflows/pr-verify.yml
is "$(key node_packages)" "${EVERY_WORKFLOW% *} .github/scripts/pr-verify scripts/lane-transcripts" && is "$(key node)" true
check "a change to pr-verify.yml alone runs the pr-verify package" $?

plan -- .github/workflows/pr-unblock.yml
rc=0
[[ " $(key node_packages) " != *" .github/scripts/pr-verify "* ]] || rc=1
check "another workflow does not run the pr-verify package" "$rc"

plan -- .github/workflows/new-uploader.yml
is "$(key node_packages)" "$EVERY_WORKFLOW" && is "$(key node)" true
check "a workflow no suite names runs every package whose suites read every workflow" $?

plan -- .github/actions/check-kill-switch/action.yml
is "$(key node_packages)" "" && is "$(key node)" false
check "a change outside .github/workflows/ runs none of the packages that read every workflow" $?

plan -- .node-version
is "$(key node_packages | wc -w | tr -d ' ')" 13
check "a Node pin runs every Node package" $?

is "$(suites node)" "$(key node_packages | tr ' ' '\n' | LC_ALL=C sort)" &&
  is "$(key node_plan | jq -r '[.[][]] | length' | tr -d '\r')" 13 &&
  is "$(key node_legs)" "[0]" && grep -q 'node: 13 suite(s), 65 suite-seconds, 1 leg(s)' "$ERR"
check "unlisted Node packages count the 5 s default, so 13 of them share one leg, each once" $?

cp "$repo/scripts/suite-seconds.txt" "$scratch/suite-seconds.txt"
printf '%s\n' ".github/actions/resolve-config 100" ".github/scripts/pr-merge 90" ".github/scripts/pr-verify 80" \
  ".github/scripts/lib 60" "plugins/miro/server 1" "plugins/ai-briefing/skills/generate/output/build 1" \
  "plugins/knowledge/skills/video-digest/extraction 1" "plugins/knowledge/skills/course-digest/extraction 1" \
  "plugins/knowledge/vendor/repo-analysis 1" ".github/actions/check-signed-commits 1" ".github/actions/check-wip-cap 1" \
  ".github/actions/log-api-budget 1" "scripts/lane-transcripts 1" >>"$repo/scripts/suite-seconds.txt"
plan -- .node-version
cp "$scratch/suite-seconds.txt" "$repo/scripts/suite-seconds.txt"
is "$(key node_legs)" "[0,1,2]" &&
  is "$(key node_plan | jq -c '.["0"], .["2"]' | tr -d '\r' | paste -sd ' ' -)" \
    '[".github/actions/resolve-config"] [".github/scripts/pr-verify",".github/scripts/lib"]' &&
  grep -q 'node: 13 suite(s), 339 suite-seconds, 3 leg(s): 100s/1 99s/10 140s/2' "$ERR"
check "339 package-seconds take ceil(339/140) = 3 legs: 100, 90 and 80 open them, 60 joins 80 and the nine 1 s packages fill 90 to 99" $?

plan -- plugins/ps/x.ps1
is "$(key windows_steps)" '["plugins/ps/run.ps1"]' && is "$(key windows_jobs)" '["win-b"]' && is "$(key bash)" false
check "a Pester suite starts the test-windows step a pattern names, and no Linux lane" $?

plan -- plugins/a/a.css
is "$(suites bash)" "plugins/a/a.test.sh" && is "$(key windows_jobs)" "[]" && is "$(key windows_steps)" "[]"
check "a change made only of inert paths runs their Linux suites and no Windows step" $?

plan -- plugins/a/a.css plugins/b/b.sh
is "$(suites bash | tr '\n' ' ')" "plugins/a/a.test.sh plugins/b/b.test.sh " &&
  is "$(key windows_jobs)" '["win-b"]' && is "$(key windows_steps)" '["plugins/b/b.test.sh"]'
check "beside an inert path, a path the list does not name still starts its Windows step" $?

plan -- scripts/test-windows-inert-paths.txt
is "$(key windows_jobs)" '["win-a","win-b"]'
check "a change to the inert list runs every Windows step" $?

plan -- plugins/z/data.cfg
is "$(key unmapped)" 1 && is "$(key bash)" false && is "$(key python)" false
check "an unmapped data file runs no corpus and is counted" $?

mk plugins/a/unread.css "p {}"
plan -- plugins/a/unread.css plugins/z/data.cfg
rm "$repo/plugins/a/unread.css"
is "$(key unmapped)" 2 && is "$(key bash)" false && is "$(key windows_steps)" "[]"
check "an unmapped file on each side of the inert list counts once each" $?

plan -- plugins/z/z.sh
is "$(key unmapped)" 1 && is "$(suites bash | wc -l | tr -d ' ')" 12 && is "$(key python)" false
check "an unmapped shell file runs the whole shell corpus and is counted" $?

plan -- .github/workflows/pr-require-checks.yml
is "$(key bash_legs)" "[0,1,2,3,4]" && is "$(suites bash | wc -l | tr -d ' ')" 12 &&
  is "$(suites python | wc -l | tr -d ' ')" 2 && is "$(key node_packages | wc -w | tr -d ' ')" 13 &&
  is "$(key windows_jobs)" "[]"
check "a pr-require-checks.yml change runs every pr-require-checks.yml lane whole, and test-windows from the selection" $?

plan -- .github/actions/download-full-history/action.yml
is "$(key bash_legs)" "[0,1,2,3,4]" && is "$(key windows_jobs)" '["win-a","win-b"]'
check "the local action every lane runs plans every lane whole" $?

plan -- .github/actions/other/action.yml
is "$(key bash)" false && is "$(key python)" false && is "$(key windows_jobs)" "[]"
check "another local action plans no lane whole" $?

plan -- .github/workflows/pr-test-platforms.yml
is "$(key windows_jobs)" '["win-a","win-b"]' && is "$(key bash)" false
check "a pr-test-platforms.yml change runs every Windows step and no pr-require-checks.yml lane" $?

plan
is "$(suites bash)" "$(cd "$repo" && bash scripts/run-plugin-tests.sh --list | LC_ALL=C sort)" &&
  is "$(key bash_legs)" "[0,1,2,3,4]"
check "the whole tree plans the runner's whole corpus on the fewest of its 12 legs that keep a's 100 s" $?

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

yml_pairs="$(awk '
  /^  [A-Za-z0-9_-]+:[[:blank:]]*$/ { job = $1; sub(/:$/, "", job) }
  match($0, /outputs\.steps\), '\''[^'\'']+'\''\)/) {
    k = substr($0, RSTART, RLENGTH); sub(/^outputs\.steps\), '\''/, "", k); sub(/'\''\)$/, "", k)
    print job " " k
  }' "$REPO_ROOT/.github/workflows/pr-test-platforms.yml" | LC_ALL=C sort -u)"
plan_pairs="$(awk '!/^[[:blank:]]*(#|$)/ { print $1 " " $2 }' "$REPO_ROOT/scripts/test-windows-plan.txt" | LC_ALL=C sort -u)"
same "$yml_pairs" "$plan_pairs"
check "live: pr-test-platforms.yml gates exactly the steps scripts/test-windows-plan.txt names" $?
yml_jobs="$(awk '
  /^  [A-Za-z0-9_-]+:[[:blank:]]*$/ { job = $1; sub(/:$/, "", job) }
  match($0, /outputs\.jobs \|\| '\''\[\]'\''\), '\''[^'\'']+'\''\)/) {
    k = substr($0, RSTART, RLENGTH); sub(/^.*\), '\''/, "", k); sub(/'\''\)$/, "", k)
    print (k == job ? job : "MISMATCH " job " gates on " k)
  }' "$REPO_ROOT/.github/workflows/pr-test-platforms.yml" | LC_ALL=C sort -u)"
same "$yml_jobs" "$(cut -d' ' -f1 <<<"$plan_pairs" | LC_ALL=C sort -u)"
check "live: every pr-test-platforms.yml job gates on the plan's job list under its own name" $?

test_harness::report
