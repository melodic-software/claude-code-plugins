#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/check-docs-only-gate.sh"
DETECTOR="$ROOT/scripts/check-docs-only.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

scratch=""
fixture_tree::build scratch --label docs-only-gate

expect() {
  local label="$1" want_rc="$2" want_text="$3"
  shift 3
  local out rc
  out="$(bash "$GATE" "$@" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
    return
  fi
  if [[ -n "$want_text" && "$out" != *"$want_text"* ]]; then
    fail "$label: expected output to contain '$want_text', got '$out'"
    return
  fi
  ok "$label"
}

xform_delete() { awk -v m="$2" 'index($0, m) == 0' "$1" >"$3"; }
xform_replace_line() { awk -v m="$2" -v r="$3" '{ if (index($0, m) > 0) print r; else print }' "$1" >"$4"; }
xform_insert_after() { awk -v m="$2" -v r="$3" '{ print; if (index($0, m) > 0) print r }' "$1" >"$4"; }
xform_append() { cp "$1" "$3" && printf '%s\n' "$2" >>"$3"; }

base="$scratch/base.yml"
cat >"$base" <<'YAML'
name: ci

on:
  pull_request:

permissions:
  contents: read

jobs:
  # A leading comment block, the way the real file carries them.
  select-tests:
    runs-on: ubuntu-24.04
    outputs:
      run_full: ${{ steps.detect.outputs.docs_only != 'true' }}
      run_tests: ${{ steps.detect.outputs.docs_only != 'true' && github.event.pull_request.draft != true }}
      run_bash: ${{ steps.detect.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.bash != 'false' }}
      run_python: ${{ steps.detect.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.python != 'false' }}
      run_node: ${{ steps.detect.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.node != 'false' }}
      run_shell: ${{ github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['lint_shell'] != 'false' }}
      run_check_tests: ${{ steps.base.outputs.ref == '' }}
      run_selection: ${{ steps.base.outputs.ref != '' && github.event.pull_request.draft != true && steps.suites.outputs.any != 'false' }}
      run_workflows: ${{ steps.detect.outputs.docs_only != 'true' && fromJSON(steps.match.outputs.results || '{}')['workflows'] != 'false' }}
      run_skill_checker: ${{ steps.detect.outputs.docs_only != 'true' && github.event.pull_request.draft != true && fromJSON(steps.match.outputs.results || '{}')['skill_checker'] != 'false' }}
      run_manifests: ${{ steps.detect.outputs.docs_only != 'true' && fromJSON(steps.match.outputs.results || '{}')['manifests'] != 'false' }}
      lane_base: ${{ steps.base.outputs.ref }}
      standards_sha: ${{ steps.standards.outputs.sha }}
      bash_legs: ${{ steps.plan.outputs.bash_legs }}
      bash_plan: ${{ steps.plan.outputs.bash_plan }}
      bash_needs: ${{ steps.plan.outputs.bash_needs }}
      python_legs: ${{ steps.plan.outputs.python_legs }}
      python_plan: ${{ steps.plan.outputs.python_plan }}
      python_needs: ${{ steps.plan.outputs.python_needs }}
      node_legs: ${{ steps.plan.outputs.node_legs }}
      node_plan: ${{ steps.plan.outputs.node_plan }}
      selection_suites: ${{ steps.suites.outputs.list }}
      playwright_cache_key: ${{ steps.playwright_key.outputs.key }}
    # A comment INSIDE the job body, between two mapping keys.
    steps:
      - name: Check out
        uses: actions/checkout@v7
      - name: Test the docs-only detector
        run: bash scripts/check-docs-only.test.sh
      # A comment between two steps.
      - name: Detect a docs-only diff
        id: detect
        if: github.event_name == 'pull_request'
        continue-on-error: true
        env:
          BASE_REF: ${{ github.base_ref }}
        run: scripts/check-docs-only.sh "origin/$BASE_REF"
      - name: Match the changed files against the filter groups
        id: match
        continue-on-error: true
        uses: some-org/ci-workflows/.github/actions/change-detection@v1

  # A consumer, gated at the step level so the job itself never skips.
  alpha:
    needs: [select-tests]
    runs-on: ubuntu-24.04
    steps:
      - name: Do the work
        id: work
        if: needs.select-tests.outputs.run_full == 'true'
        run: echo work
      - name: A block scalar whose body looks like workflow structure
        run: |
          echo "  not-a-job: this line lives inside a block scalar"
          echo "      - name: neither is this"
          echo "        if: always()"
      - name: Run a narrowed lane
        id: node-work
        if: needs.select-tests.outputs.run_node == 'true'
        run: echo node
      - name: Report not applicable to a docs-only diff
        if: needs.select-tests.outputs.run_full == 'false'
        run: echo not-applicable
      - name: Diff against the resolved base
        env:
          DIFF_BASE: ${{ needs.select-tests.outputs.lane_base }}
        run: echo "${DIFF_BASE:-whole tree}"
      - name: Aggregate
        if: always()
        env:
          CHECK_RESULTS: |
            alpha-check=${{ needs.select-tests.outputs.run_full == 'false' && 'success' || steps.work.outcome }}
            alpha-node=${{ needs.select-tests.outputs.run_node == 'false' && 'success' || steps.node-work.outcome }}
        run: echo aggregate

  # A second consumer using the block-sequence needs form, with a trailing
  # comment on its job key.
  beta: # a consumer
    needs:
      - select-tests # the resolver
    runs-on: ubuntu-24.04
    steps:
      - name: Do the work
        if: needs.select-tests.outputs.run_tests == 'true'
        run: echo work

  # A third consumer using a quoted flow sequence.
  gamma:
    needs: ['select-tests']
    runs-on: ubuntu-24.04
    steps:
      - name: Do the work
        if: needs.select-tests.outputs.run_full == 'true'
        run: echo work

  # A reusable-workflow job that does NOT read the output.
  delta:
    uses: some-org/some-repo/.github/workflows/lint.yml@v1

  # A lane OUTSIDE the aggregate's needs closure: non-required, so it may skip
  # the whole job rather than run it to report nothing, and it says so.
  # lane-coverage-ok: non-required platform lane, excluded from the aggregate
  epsilon:
    needs:
      - select-tests
    if: needs.select-tests.outputs.run_python == 'true'
    runs-on: windows-2025
    steps:
      - name: Do the work
        run: echo work

  ci-status:
    needs:
      - select-tests
      - alpha
      - beta
      - gamma
      - delta
    if: ${{ !cancelled() }}
    runs-on: ubuntu-24.04
    steps:
      - name: Aggregate lane results
        run: echo ok
YAML

expect "known-good fixture satisfies the contract" 0 "scope resolved once" --check "$base"

sharded="$scratch/sharded.yml"
xform_insert_after "$base" "      - gamma" "      - zeta" "$sharded"
cat >>"$sharded" <<'YAML'

  # A required consumer whose work is partitioned across four runners.
  zeta:
    needs: [select-tests]
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix: ${{ github.event_name == 'pull_request' && fromJSON('{"leg":[0,1,2,3]}') || fromJSON('{"leg":[0]}') }}
    steps:
      - name: Run this leg of the affected suite set
        if: needs.select-tests.outputs.run_tests == 'true'
        env:
          LEG: ${{ strategy.job-index }}
          LEGS: ${{ strategy.job-total }}
        run: scripts/affected-tests.sh --run --shard "$LEG/$LEGS"
      - name: Run a Node build only when Node sources changed
        if: needs.select-tests.outputs.run_node == 'true'
        run: npm test
YAML
expect "a sharded lane gating its steps satisfies the contract" 0 "scope resolved once" \
  --check "$sharded"

f="$scratch/leg-in-gate.yml"
xform_replace_line "$sharded" \
  "if: needs.select-tests.outputs.run_node == 'true'" \
  "        if: needs.select-tests.outputs.run_node == 'true' && strategy.job-index == 0" "$f"
expect "a leg index folded into a step gate is unsanctioned" 1 "unsanctioned condition" --check "$f"

f="$scratch/second-resolution.yml"
xform_replace_line "$base" "run: echo not-applicable" '        run: scripts/check-docs-only.sh "origin/main"' "$f"
expect "a consumer re-running the detector is a second resolution" 1 "invoked from 2 job(s)" --check "$f"

f="$scratch/second-resolution-relative.yml"
xform_replace_line "$base" "run: echo not-applicable" '        run: cd scripts && bash check-docs-only.sh origin/main' "$f"
expect "a relative-path re-resolution is still a second resolution" 1 "invoked from 2 job(s)" --check "$f"

f="$scratch/second-resolution-scalar.yml"
xform_insert_after "$base" 'echo "      - name: neither is this"' '          bash scripts/check-docs-only.sh origin/main' "$f"
expect "a re-resolution inside a block scalar is still seen" 1 "invoked from 2 job(s)" --check "$f"

f="$scratch/second-invocation-same-job.yml"
# shellcheck disable=SC2016 # `$BASE_REF` is fixture text, not a shell variable.
xform_insert_after "$base" 'run: scripts/check-docs-only.sh "origin/$BASE_REF"' '        run: scripts/check-docs-only.sh "origin/HEAD"' "$f"
expect "a second invocation in the resolver job is a second resolution" 1 "invoked 2 times" --check "$f"

f="$scratch/step-output.yml"
# shellcheck disable=SC2016 # `${{ }}` must reach the fixture verbatim.
xform_replace_line "$base" "run: echo not-applicable" '        run: echo ${{ steps.detect.outputs.docs_only }}' "$f"
expect "a surviving step-level docs_only read is a second answer" 1 "step-level docs_only output is still read" --check "$f"

f="$scratch/inverted-expression.yml"
xform_replace_line "$base" "run_full: " "      run_full: \${{ steps.detect.outputs.docs_only == 'true' }}" "$f"
expect "an inverted output expression is rejected" 1 "FAIL-CLOSED DEFAULT" --check "$f"

f="$scratch/no-output.yml"
xform_delete "$base" "run_full: \${{" "$f"
expect "a resolving job publishing no output is rejected" 1 "publishes no 'run_full' output" --check "$f"

f="$scratch/commented-output.yml"
xform_replace_line "$base" "run_full: \${{" "      # run_full: \${{ steps.detect.outputs.docs_only != 'true' }}" "$f"
expect "a commented-out output expression does not satisfy the contract" 1 "publishes no 'run_full' output" --check "$f"

f="$scratch/detect-fails-job.yml"
xform_delete "$base" "continue-on-error: true" "$f"
expect "a detect step that can fail its own job is rejected" 1 "missing 'continue-on-error: true'" --check "$f"

f="$scratch/no-detect-step.yml"
xform_delete "$base" "id: detect" "$f"
expect "a resolving job with no detect step is rejected" 1 "no step declares 'id: detect'" --check "$f"

f="$scratch/coe-on-sibling.yml"
xform_delete "$base" "continue-on-error: true" "$scratch/_nocoe.yml"
xform_insert_after "$scratch/_nocoe.yml" "- name: Check out" "        id: detect-nothing
        continue-on-error: true" "$f"
expect "continue-on-error on a sibling step does not satisfy the detect step" 1 "missing 'continue-on-error: true'" --check "$f"

f="$scratch/detect-runs-nothing.yml"
# shellcheck disable=SC2016 # `$BASE_REF` is fixture text, not a shell variable.
xform_replace_line "$base" 'run: scripts/check-docs-only.sh "origin/$BASE_REF"' '        run: echo nothing' "$scratch/_nodetect.yml"
xform_insert_after "$scratch/_nodetect.yml" "run: bash scripts/check-docs-only.test.sh" '        run: scripts/check-docs-only.sh "origin/main"' "$f"
expect "a detect step that runs something else is rejected" 1 "does not invoke the docs-only detector" --check "$f"

f="$scratch/decoy-invocation.yml"
# shellcheck disable=SC2016 # fixture text; `$BASE_REF` and `$GITHUB_OUTPUT` stay literal.
xform_replace_line "$base" 'run: scripts/check-docs-only.sh "origin/$BASE_REF"' '        run: |
          # was: scripts/check-docs-only.sh "origin/$BASE_REF"
          echo "docs_only=true" >> "$GITHUB_OUTPUT"' "$f"
expect "a commented-out detector call does not count as invoking it" 1 "does not invoke the docs-only detector" --check "$f"

f="$scratch/prose-mentions-detector.yml"
xform_insert_after "$base" 'echo "  not-a-job: this line lives inside a block scalar"' '          # the scope is resolved once, by scripts/check-docs-only.sh' "$f"
expect "prose naming the detector is not a second resolution" 0 "scope resolved once" --check "$f"

f="$scratch/no-self-test.yml"
xform_delete "$base" "check-docs-only.test.sh" "$f"
expect "dropping the detector self-test is rejected" 1 "does not run the detector's own suite" --check "$f"

f="$scratch/commented-self-test.yml"
xform_replace_line "$base" "run: bash scripts/check-docs-only.test.sh" "        # run: bash scripts/check-docs-only.test.sh" "$f"
expect "a commented-out self-test does not satisfy the contract" 1 "does not run the detector's own suite" --check "$f"

f="$scratch/soft-self-test.yml"
xform_insert_after "$base" "- name: Test the docs-only detector" "        continue-on-error: true" "$f"
expect "a self-test that cannot turn the job red is rejected" 1 "carries continue-on-error" --check "$f"

f="$scratch/negated-form.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_full == 'false'" "        if: needs.select-tests.outputs.run_full != 'true'" "$f"
expect "the inverse-polarity consumer form is rejected" 1 "unsanctioned condition" --check "$f"

f="$scratch/truthy-form.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_full == 'false'" "        if: needs.select-tests.outputs.run_full" "$f"
expect "a bare truthiness consumer form is rejected" 1 "unsanctioned condition" --check "$f"

f="$scratch/wrapped-negation.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_full == 'false'" "        if: \${{ !(needs.select-tests.outputs.run_full == 'false') }}" "$f"
expect "a negation wrapped around the sanctioned form is rejected" 1 "unsanctioned condition" --check "$f"

f="$scratch/index-syntax-output.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_full == 'false'" "        if: needs.select-tests.outputs['run_full'] != 'true'" "$f"
expect "an index-syntax output name is rejected rather than ignored" 1 "unsanctioned condition" --check "$f"

f="$scratch/index-syntax-whole.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_full == 'false'" "        if: needs['select-tests']['outputs']['run_full'] == 'false'" "$f"
expect "a fully bracketed accessor is rejected rather than ignored" 1 "unsanctioned condition" --check "$f"

f="$scratch/case-variant.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_full == 'false'" "        if: needs.SELECT-TESTS.outputs.run_full == 'false'" "$f"
expect "a case-variant accessor is rejected rather than ignored" 1 "unsanctioned condition" --check "$f"

f="$scratch/job-level-gate.yml"
xform_insert_after "$base" "  gamma:" "    if: needs.select-tests.outputs.run_full == 'true'" "$f"
expect "a job-level condition on the output is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/reusable-consumer.yml"
xform_insert_after "$base" "    uses: some-org/some-repo/.github/workflows/lint.yml@v1" "    if: needs.select-tests.outputs.run_full == 'true'" "$f"
expect "a reusable-workflow job reading the output is rejected" 1 "delegates to a reusable workflow" --check "$f"

f="$scratch/gate-inside-scalar.yml"
xform_replace_line "$base" 'echo "        if: always()"' '          echo "        if: needs.select-tests.outputs.run_full == '"'"'true'"'"'"' "$f"
expect "a condition-shaped line inside a block scalar is not a step condition" 1 "outside a step condition" --check "$f"

f="$scratch/mutated-feed.yml"
xform_replace_line "$base" "alpha-check=" "            alpha-check=\${{ needs.select-tests.outputs.run_full == 'true' && 'success' || steps.work.outcome }}" "$f"
expect "a mutated aggregator feed entry is rejected" 1 "outside the aggregator feed template" --check "$f"

f="$scratch/feed-without-gate.yml"
xform_replace_line "$base" "alpha-check=" "            alpha-check=\${{ needs.select-tests.outputs.run_full == 'false' && 'success' || steps.ungated.outcome }}" "$f"
expect "a feed override for an ungated step is rejected" 1 "THE FEED MIRRORS A REAL GATE" --check "$f"

f="$scratch/consumer-always.yml"
xform_insert_after "$base" "  gamma:" "    if: always()" "$f"
expect "a consumer carrying an unconditional job-level if is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/consumer-not-cancelled.yml"
xform_insert_after "$base" "  gamma:" "    if: \${{ !cancelled() }}" "$f"
expect "a consumer carrying !cancelled() is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

contract_gate="\${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('[\"labeled\",\"unlabeled\"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))) }}"

f="$scratch/consumer-contract-gate.yml"
xform_insert_after "$base" "  gamma:" "    if: $contract_gate" "$f"
expect "a consumer carrying exactly the contract-only gate is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/consumer-contract-gate-always.yml"
xform_insert_after "$base" "  gamma:" "    if: \${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('[\"labeled\",\"unlabeled\"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))) || always() }}" "$f"
expect "the contract-only gate widened with always() is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/consumer-contract-gate-drifted.yml"
xform_insert_after "$base" "  gamma:" "    if: \${{ !(contains(fromJSON('[\"labeled\",\"unlabeled\"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base)) }}" "$f"
expect "a drifted copy of the contract-only predicate is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

draft_gate="\${{ !(github.event.pull_request.head.repo.full_name == github.repository && (contains(fromJSON('[\"labeled\",\"unlabeled\"]'), github.event.action) || (github.event.action == 'edited' && !github.event.changes.base))) && github.event.pull_request.draft != true }}"
skip_as_fail="$scratch/skip-as-fail.yml"
xform_insert_after "$base" "      - name: Aggregate lane results" "        with:\n          treat-skipped-as: fail" "$skip_as_fail"

f="$scratch/consumer-draft-gate.yml"
xform_insert_after "$skip_as_fail" "  gamma:" "    if: $draft_gate" "$f"
expect "a consumer carrying exactly the draft form of the gate is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/consumer-draft-gate-flipped.yml"
xform_insert_after "$skip_as_fail" "  gamma:" "    if: ${draft_gate/draft != true/draft == true}" "$f"
expect "the draft gate with its polarity flipped is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

expect "the aggregate failing every skip is allowed" 0 "scope resolved once" --check "$skip_as_fail"

f="$scratch/skip-as-draft.yml"
xform_insert_after "$base" "      - name: Aggregate lane results" "        with:\n          treat-skipped-as: \${{ github.event.pull_request.draft && 'pass' || 'fail' }}" "$f"
expect "the aggregate passing skips only on a draft is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/skip-as-draft-flipped.yml"
xform_insert_after "$base" "      - name: Aggregate lane results" "        with:\n          treat-skipped-as: \${{ github.event.pull_request.draft && 'fail' || 'pass' }}" "$f"
expect "the draft form with its values flipped is rejected" 1 "A SKIPPED LANE NEVER PASSES" --check "$f"

f="$scratch/skip-as-pass.yml"
xform_insert_after "$base" "      - name: Aggregate lane results" "        with:\n          treat-skipped-as: pass" "$f"
expect "the aggregate passing skips everywhere is rejected" 1 "A SKIPPED LANE NEVER PASSES" --check "$f"

f="$scratch/draft-gate-no-skip-as.yml"
xform_insert_after "$base" "  gamma:" "    if: $draft_gate" "$f"
expect "a draft-gated lane with no treat-skipped-as on the aggregate is rejected" 1 "sets no treat-skipped-as" --check "$f"

expect "the aggregate's own job-level condition is untouched" 0 "scope resolved once" --check "$base"

skip_form="${draft_gate% \}\}} && needs.select-tests.outputs.run_python == 'true' }}"
ordered="$scratch/ordered-skip.yml"
xform_insert_after "$skip_as_fail" "      - gamma" "      - test-python" "$scratch/o1.yml"
xform_replace_line "$scratch/o1.yml" "      - name: Aggregate lane results" \
  "      - name: Check each skipped lane against scope\n        id: lanes\n        run: echo checked\n      - name: Aggregate lane results" "$scratch/o2.yml"
xform_insert_after "$scratch/o2.yml" "          treat-skipped-as: fail" "          results: \${{ steps.lanes.outputs.results }}" "$scratch/o3.yml"
xform_append "$scratch/o3.yml" "
  test-python:
    needs: [select-tests]
    if: $skip_form
    runs-on: ubuntu-24.04
    steps:
      - name: Run the selected Python suites
        run: echo python" "$ordered"
expect "a test lane skipping on its own row, checked by the aggregate, is allowed" 0 "scope resolved once" --check "$ordered"

f="$scratch/ordered-skip-lint-shell.yml"
xform_replace_line "$ordered" "  test-python:" "  lint-shell:" "$scratch/ls1.yml"
xform_replace_line "$scratch/ls1.yml" "      - test-python" "      - lint-shell" "$scratch/ls2.yml"
xform_replace_line "$scratch/ls2.yml" "    if: $skip_form" "    if: ${skip_form/run_python/run_shell}" "$f"
expect "lint-shell skipping on its run_shell row, checked by the aggregate, is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/ordered-skip-lint-repo.yml"
xform_replace_line "$scratch/ordered-skip-lint-shell.yml" "  lint-shell:" "  lint-repo:" "$scratch/lr1.yml"
xform_replace_line "$scratch/lr1.yml" "      - lint-shell" "      - lint-repo" "$f"
expect "another lint lane may not borrow run_shell" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/ordered-skip-check-tests.yml"
xform_replace_line "$ordered" "  test-python:" "  check-tests:" "$scratch/ct1.yml"
xform_replace_line "$scratch/ct1.yml" "      - test-python" "      - check-tests" "$scratch/ct2.yml"
xform_replace_line "$scratch/ct2.yml" "    if: $skip_form" "    if: ${skip_form/run_python/run_check_tests}" "$f"
expect "check-tests skipping on its run_check_tests row, checked by the aggregate, is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/ordered-skip-check-plugins.yml"
xform_replace_line "$scratch/ordered-skip-check-tests.yml" "  check-tests:" "  check-plugins:" "$scratch/cp1.yml"
xform_replace_line "$scratch/cp1.yml" "      - check-tests" "      - check-plugins" "$f"
expect "another check lane may not borrow run_check_tests" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/check-tests-row-inverted.yml"
xform_replace_line "$scratch/ordered-skip-check-tests.yml" "      run_check_tests:" "      run_check_tests: \${{ steps.base.outputs.ref != '' }}" "$f"
expect "a run_check_tests row that is true beside a diff base is rejected" 1 "publishes 'run_check_tests: \${{ steps.base.outputs.ref != '' }}', expected exactly" --check "$f"

f="$scratch/ordered-skip-other-row.yml"
xform_replace_line "$ordered" "    if: $skip_form" "    if: ${skip_form/run_python/run_bash}" "$f"
expect "a test lane skipping on another lane's row is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/ordered-skip-not-a-test-lane.yml"
xform_insert_after "$scratch/o3.yml" "  gamma:" "    if: $skip_form" "$f"
expect "the ordered skip on a job that is not test-<x> is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/ordered-skip-flipped.yml"
want_true="run_python == 'true'"
want_false="run_python == 'false'"
xform_replace_line "$ordered" "    if: $skip_form" "    if: ${skip_form/"$want_true"/"$want_false"}" "$f"
expect "the ordered skip with its polarity flipped is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/ordered-skip-raw-results.yml"
xform_replace_line "$ordered" "          results: \${{ steps.lanes.outputs.results }}" "          results: \${{ join(needs.*.result, ' ') }}" "$f"
expect "an ordered skip the aggregate reads raw is rejected" 1 "A SKIP IS CHECKED" --check "$f"

f="$scratch/ordered-skip-no-check-step.yml"
xform_delete "$ordered" "        id: lanes" "$f"
expect "an ordered skip with no checking step is rejected" 1 "has no step 'id: lanes'" --check "$f"

f="$scratch/missing-edge.yml"
xform_delete "$base" "needs: [select-tests]" "$f"
expect "a consumer reading the output without the needs edge is rejected" 1 "EDGE DECLARED" --check "$f"

f="$scratch/no-consumers.yml"
xform_delete "$base" "needs.select-tests.outputs." "$f"
expect "a resolver nobody reads is rejected" 1 "CONTRACT IS LIVE" --check "$f"

f="$scratch/epsilon-required.yml"
xform_insert_after "$base" "      - delta" "      - epsilon" "$f"
expect "a job-level condition inside the closure is rejected" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"
expect "and the lane opt-out inside the closure is rejected with it" 1 "LANE OPT-OUT ON A REQUIRED LANE" --check "$f"

f="$scratch/epsilon-transitive.yml"
xform_replace_line "$base" "    needs: [select-tests]" "    needs: [select-tests, epsilon]" "$f"
expect "a lane reached transitively is inside the closure too" 1 "LANE OPT-OUT ON A REQUIRED LANE" --check "$f"
expect "and its job-level condition is a defect for the same reason" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER" --check "$f"

f="$scratch/gamma-not-required.yml"
xform_delete "$base" "      - gamma" "$f"
xform_insert_after "$f" "  gamma:" "    if: needs.select-tests.outputs.run_python == 'true'" "$scratch/gamma-not-required-2.yml"
expect "a job-level condition outside the closure is allowed" 0 "scope resolved once" --check "$scratch/gamma-not-required-2.yml"

f="$scratch/no-aggregate.yml"
xform_replace_line "$base" "  ci-status:" "  renamed-status:" "$f"
expect "a missing aggregate is inconclusive, never a pass" 2 "closure cannot be computed" --check "$f"

f="$scratch/extra-output.yml"
xform_insert_after "$base" "      run_workflows:" "      run_something: \${{ steps.detect.outputs.docs_only != 'true' }}" "$f"
expect "an output outside the table is rejected" 1 "which neither the output table nor the data table names" --check "$f"

f="$scratch/data-missing.yml"
xform_delete "$base" "      lane_base:" "$f"
expect "a missing data output is rejected" 1 "publishes no 'lane_base' data output" --check "$f"

f="$scratch/data-wrapped.yml"
xform_replace_line "$base" "      lane_base:" "      lane_base: \${{ steps.base.outputs.ref || 'origin/main' }}" "$f"
expect "a data output with a defaulting expression is rejected" 1 "DATA IS NOT A GATE" --check "$f"

f="$scratch/data-in-step-if.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_node == 'true'" "        if: needs.select-tests.outputs.lane_base == 'true'" "$f"
expect "a data output in a step condition is rejected" 1 "which the resolver's output table does not name" --check "$f"

f="$scratch/data-in-longer-expr.yml"
xform_replace_line "$base" "DIFF_BASE: \${{" "          DIFF_BASE: \${{ needs.select-tests.outputs.lane_base || 'origin/main' }}" "$f"
expect "a data output inside a longer expression is rejected" 1 "outside the aggregator feed template" --check "$f"

f="$scratch/data-lowercase-key.yml"
xform_replace_line "$base" "DIFF_BASE: \${{" "          diff_ref: \${{ needs.select-tests.outputs.lane_base }}" "$f"
expect "a data output read under a non-env key is rejected" 1 "outside the aggregator feed template" --check "$f"

f="$scratch/data-aggregate-reads-value.yml"
xform_insert_after "$base" "    if: \${{ !cancelled() }}" "    env:\n      STANDARDS_COMMIT: \${{ needs.select-tests.outputs.standards_sha }}" "$f"
expect "the aggregate reading only a data value under !cancelled() is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/data-and-gate-under-cancelled.yml"
xform_insert_after "$base" "  gamma:" "    if: \${{ !cancelled() }}\n    env:\n      STANDARDS_COMMIT: \${{ needs.select-tests.outputs.standards_sha }}" "$f"
expect "a data read does not excuse a gated consumer carrying !cancelled()" 1 "NO JOB-LEVEL CONDITION ON A REQUIRED CONSUMER: job 'gamma'" --check "$f"

f="$scratch/data-matrix.yml"
xform_replace_line "$sharded" "      matrix: \${{" "      matrix:\n        leg: \${{ fromJSON(needs.select-tests.outputs.bash_legs || '[0]') }}" "$f"
expect "the matrix sized from bash_legs with its one-leg default is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/data-matrix-python.yml"
xform_replace_line "$sharded" "      matrix: \${{" "      matrix:\n        leg: \${{ fromJSON(needs.select-tests.outputs.python_legs || '[0]') }}" "$f"
expect "the matrix sized from python_legs with its one-leg default is allowed" 0 "scope resolved once" --check "$f"

f="$scratch/data-matrix-no-default.yml"
xform_replace_line "$sharded" "      matrix: \${{" "      matrix:\n        leg: \${{ fromJSON(needs.select-tests.outputs.bash_legs) }}" "$f"
expect "the matrix read without its default is rejected" 1 "outside the aggregator feed template" --check "$f"

f="$scratch/data-in-job-if.yml"
xform_replace_line "$base" "    if: needs.select-tests.outputs.run_python == 'true'" "    if: needs.select-tests.outputs.lane_base != ''" "$f"
expect "a data output in a job condition is rejected" 1 "DATA IS NOT A GATE" --check "$f"

f="$scratch/unknown-output-consumer.yml"
xform_replace_line "$base" "if: needs.select-tests.outputs.run_node == 'true'" "        if: needs.select-tests.outputs.run_invented == 'true'" "$f"
expect "a step gated on an output outside the table is rejected" 1 "which the resolver's output table does not name" --check "$f"

f="$scratch/inverted-narrowing.yml"
xform_replace_line "$base" "      run_node:" "      run_node: \${{ steps.detect.outputs.docs_only != 'true' && github.event.pull_request.draft != true && steps.plan.outputs.node == 'true' }}" "$f"
expect "a narrowing row comparing against 'true' is rejected" 1 "FAIL-CLOSED DEFAULT" --check "$f"

f="$scratch/skill-checker-no-draft.yml"
xform_replace_line "$base" "      run_skill_checker:" "      run_skill_checker: \${{ steps.detect.outputs.docs_only != 'true' && fromJSON(steps.match.outputs.results || '{}')['skill_checker'] != 'false' }}" "$f"
expect "a run_skill_checker row without its draft term is rejected" 1 "FAIL-CLOSED DEFAULT" --check "$f"

f="$scratch/feed-output-mismatch.yml"
xform_replace_line "$base" "alpha-node=" "            alpha-node=\${{ needs.select-tests.outputs.run_full == 'false' && 'success' || steps.node-work.outcome }}" "$f"
expect "a feed override paired with a different output is rejected" 1 "THE FEED MIRRORS A REAL GATE" --check "$f"

f="$scratch/bad-shape.yml"
xform_insert_after "$base" "jobs:" "  not a job key" "$f"
expect "an unparsed workflow shape is inconclusive, never a pass" 2 "unrecognized workflow shape" --check "$f"

f="$scratch/bad-needs-entry.yml"
xform_replace_line "$base" "      - select-tests # the resolver" "      - [select-tests]" "$f"
expect "an unmodeled needs entry is inconclusive, never a bogus defect" 2 "unsupported needs entry" --check "$f"

f="$scratch/shallow-needs-item.yml"
xform_replace_line "$base" "      - select-tests # the resolver" "    - select-tests" "$f"
expect "a same-indent needs item is a declared edge, not a defect" 0 "scope resolved once" --check "$f"

f="$scratch/expression-coe.yml"
xform_replace_line "$base" "        continue-on-error: true" "        continue-on-error: \${{ true }}" "$f"
expect "an expression-valued continue-on-error is inconclusive, never a pass" 2 "not a literal true/false" --check "$f"

f="$scratch/no-jobs.yml"
xform_delete "$base" "jobs:" "$f"
expect "a file with no jobs mapping is inconclusive" 2 "no jobs: mapping found" --check "$f"

f="$scratch/no-resolver.yml"
xform_replace_line "$base" "  select-tests:" "  renamed-select-tests:" "$f"
expect "a missing resolving job is inconclusive, never a pass" 2 "is not defined" --check "$f"

expect "a missing workflow file is inconclusive" 2 "workflow not found" --check "$scratch/absent.yml"
expect "a bare invocation prints usage" 2 "usage:"
expect "an unknown mode prints usage" 2 "usage:" --lint
expect "an excess argument prints usage" 2 "usage:" --check "$base" ci-status

expect "the shipped pr-require-checks.yml satisfies the contract" 0 "scope resolved once" --check ".github/workflows/pr-require-checks.yml"

gho="$scratch/github-output"

: >"$gho"
if GITHUB_OUTPUT="$gho" bash "$DETECTOR" >/dev/null 2>&1; then
  fail "detector invoked with no base-ref argument should exit non-zero"
elif [[ -s "$gho" ]]; then
  fail "a detector usage abort wrote to GITHUB_OUTPUT: $(cat "$gho")"
else
  ok "a detector usage abort leaves docs_only unset, which run_full renders as 'true'"
fi

unwritable="$scratch/no-such-dir/output"
GITHUB_OUTPUT="$unwritable" bash "$DETECTOR" "origin/main" >/dev/null 2>&1
if [[ -e "$unwritable" ]]; then
  fail "expected no output file to be produced at an unwritable path"
else
  ok "an unwritable GITHUB_OUTPUT leaves docs_only unset, which run_full renders as 'true'"
fi

live_workflow="$ROOT/.github/workflows/pr-require-checks.yml"
suite_steps="$(
  awk '
    /^  [A-Za-z_][A-Za-z0-9_-]*:[[:blank:]]*(#.*)?$/ {
      job = $0; sub(/:.*$/, "", job); sub(/^  /, "", job)
    }
    job == "" || job == "select-tests" { next }
    /^      - / { ident = 0 }
    /^        id:/ { ident = 1 }
    /^[[:blank:]]+(run: )?bash (scripts|lib)\/[^ ]*\.test\.sh[[:blank:]]*$/ {
      line = $0; sub(/^[[:blank:]]*(run: )?bash /, "", line)
      if (!ident && line != "scripts/hook-census.test.sh") print job ": " line
    }
  ' "$live_workflow"
)"
if [[ -z "$suite_steps" ]]; then
  ok "no scripts/ or lib/ suite runs as a step of its own in the live workflow"
else
  fail "scripts/ or lib/ suite(s) run as steps of their own:$(printf '%s' "$suite_steps" | tr '\n' ' ')"
fi

test_harness::report
