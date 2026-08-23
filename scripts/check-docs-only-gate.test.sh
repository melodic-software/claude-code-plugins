#!/usr/bin/env bash
# Self-test for scripts/check-docs-only-gate.sh
#
# The gate exists to replace a prose comment that asserted the docs-only
# short-circuit was fail-closed. A gate that only ever passes would be the same
# nominal closure in a new costume, so every case below breaks exactly one
# property of a known-good fixture and asserts the gate NAMES that property.
#
# The known-good fixture deliberately carries the shapes a structural reader is
# fragile on — a comment inside a job body, a job key with a trailing comment, a
# block scalar whose body contains lines that look like workflow structure, a
# quoted flow `needs:`, and a reusable-workflow job — because a gate that only
# ever sees tidy input is only ever tested against tidy input. The EVASION
# section then attacks the gate directly: each case is a workflow that is
# genuinely broken at runtime and must not be reported as satisfied.
#
# Fixtures are plain files under mktemp, addressed by ABSOLUTE path: the gate
# cds to the git toplevel, so an absolute fixture path resolves from anywhere and
# no scratch git repo is needed. That is deliberate — a fixture repo would need
# `git -C <dir> config user.*`, and the un-scoped form of that command writes the
# test identity into the CALLER's repo config (claude-code-plugins#2839).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$ROOT/scripts/check-docs-only-gate.sh"
DETECTOR="$ROOT/scripts/check-docs-only.sh"
failures=0

ok() { printf 'ok - %s\n' "$1"; }
fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

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

# --- fixture transforms -----------------------------------------------------
#
# Exact-substring transforms via awk index(), never regex: the fixture bodies
# carry `${{ }}`, quotes and dots, and a regex dialect difference between GNU
# and BSD tools must not decide whether a test case is even built.

xform_delete() { awk -v m="$2" 'index($0, m) == 0' "$1" >"$3"; }
xform_replace_line() { awk -v m="$2" -v r="$3" '{ if (index($0, m) > 0) print r; else print }' "$1" >"$4"; }
xform_insert_after() { awk -v m="$2" -v r="$3" '{ print; if (index($0, m) > 0) print r }' "$1" >"$4"; }
xform_append() { cp "$1" "$3" && printf '%s\n' "$2" >>"$3"; }

# --- the known-good fixture -------------------------------------------------

base="$scratch/base.yml"
cat >"$base" <<'YAML'
name: ci

on:
  pull_request:

permissions:
  contents: read

jobs:
  # A leading comment block, the way the real file carries them.
  scope:
    runs-on: ubuntu-24.04
    outputs:
      run_full: ${{ steps.detect.outputs.docs_only != 'true' }}
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

  # A consumer, gated at the step level so the job itself never skips.
  alpha:
    needs: [scope]
    runs-on: ubuntu-24.04
    steps:
      - name: Do the work
        id: work
        if: needs.scope.outputs.run_full == 'true'
        run: echo work
      - name: A block scalar whose body looks like workflow structure
        run: |
          echo "  not-a-job: this line lives inside a block scalar"
          echo "      - name: neither is this"
          echo "        if: always()"
      - name: Report not applicable to a docs-only diff
        if: needs.scope.outputs.run_full == 'false'
        run: echo not-applicable
      - name: Aggregate
        if: always()
        env:
          CHECK_RESULTS: |
            alpha-check=${{ needs.scope.outputs.run_full == 'false' && 'success' || steps.work.outcome }}
        run: echo aggregate

  # A second consumer using the block-sequence needs form, with a trailing
  # comment on its job key.
  beta: # a consumer
    needs:
      - scope # the resolver
    runs-on: ubuntu-24.04
    steps:
      - name: Do the work
        if: needs.scope.outputs.run_full == 'true'
        run: echo work

  # A third consumer using a quoted flow sequence.
  gamma:
    needs: ['scope']
    runs-on: ubuntu-24.04
    steps:
      - name: Do the work
        if: needs.scope.outputs.run_full == 'true'
        run: echo work

  # A reusable-workflow job that does NOT read the output.
  delta:
    uses: some-org/some-repo/.github/workflows/lint.yml@v1

  ci-status:
    needs:
      - scope
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

# --- 1. SINGLE RESOLUTION ---------------------------------------------------

f="$scratch/second-resolution.yml"
xform_replace_line "$base" "run: echo not-applicable" '        run: scripts/check-docs-only.sh "origin/main"' "$f"
expect "a consumer re-running the detector is a second resolution" 1 "invoked from 2 job(s)" --check "$f"

# The detector reached by a different spelling is the same second answer.
f="$scratch/second-resolution-relative.yml"
xform_replace_line "$base" "run: echo not-applicable" '        run: cd scripts && bash check-docs-only.sh origin/main' "$f"
expect "a relative-path re-resolution is still a second resolution" 1 "invoked from 2 job(s)" --check "$f"

# A run: body is a block scalar, and a re-resolution hidden in one still counts.
f="$scratch/second-resolution-scalar.yml"
xform_insert_after "$base" 'echo "      - name: neither is this"' '          bash scripts/check-docs-only.sh origin/main' "$f"
expect "a re-resolution inside a block scalar is still seen" 1 "invoked from 2 job(s)" --check "$f"

f="$scratch/step-output.yml"
# shellcheck disable=SC2016 # `${{ }}` must reach the fixture verbatim.
xform_replace_line "$base" "run: echo not-applicable" '        run: echo ${{ steps.detect.outputs.docs_only }}' "$f"
expect "a surviving step-level docs_only read is a second answer" 1 "step-level docs_only output is still read" --check "$f"

# --- 2. FAIL-CLOSED DEFAULT -------------------------------------------------
#
# The inverted expression is the exact defect the contract exists to prevent:
# it renders an UNSET detector output as `false`, so a detector that never ran
# would short-circuit every consumer instead of running the full suite.

f="$scratch/inverted-expression.yml"
xform_replace_line "$base" "run_full: " "      run_full: \${{ steps.detect.outputs.docs_only == 'true' }}" "$f"
expect "an inverted output expression is rejected" 1 "FAIL-CLOSED DEFAULT" --check "$f"

f="$scratch/no-output.yml"
xform_delete "$base" "run_full: \${{" "$f"
expect "a resolving job publishing no output is rejected" 1 "publishes no 'run_full' output" --check "$f"

# A commented-out expression is prose, not a contract.
f="$scratch/commented-output.yml"
xform_replace_line "$base" "run_full: \${{" "      # run_full: \${{ steps.detect.outputs.docs_only != 'true' }}" "$f"
expect "a commented-out output expression does not satisfy the contract" 1 "publishes no 'run_full' output" --check "$f"

# --- 3. FAILURE IS ABSORBED -------------------------------------------------

f="$scratch/detect-fails-job.yml"
xform_delete "$base" "continue-on-error: true" "$f"
expect "a detect step that can fail its own job is rejected" 1 "missing 'continue-on-error: true'" --check "$f"

f="$scratch/no-detect-step.yml"
xform_delete "$base" "id: detect" "$f"
expect "a resolving job with no detect step is rejected" 1 "no step declares 'id: detect'" --check "$f"

# A sibling step must not lend its continue-on-error to the detect step.
f="$scratch/coe-on-sibling.yml"
xform_delete "$base" "continue-on-error: true" "$scratch/_nocoe.yml"
xform_insert_after "$scratch/_nocoe.yml" "- name: Check out" "        id: detect-nothing
        continue-on-error: true" "$f"
expect "continue-on-error on a sibling step does not satisfy the detect step" 1 "missing 'continue-on-error: true'" --check "$f"

# The detect step must be the step that actually runs the detector.
f="$scratch/detect-runs-nothing.yml"
# shellcheck disable=SC2016 # `$BASE_REF` is fixture text, not a shell variable.
xform_replace_line "$base" 'run: scripts/check-docs-only.sh "origin/$BASE_REF"' '        run: echo nothing' "$scratch/_nodetect.yml"
xform_insert_after "$scratch/_nodetect.yml" "run: bash scripts/check-docs-only.test.sh" '        run: scripts/check-docs-only.sh "origin/main"' "$f"
expect "a detect step that runs something else is rejected" 1 "does not invoke the docs-only detector" --check "$f"

# A detect step whose real invocation is commented out, emitting a hardcoded
# flag instead, is the maximal false green: every consumer short-circuits on
# every event. The comment must not read as the invocation.
f="$scratch/decoy-invocation.yml"
# shellcheck disable=SC2016 # fixture text; `$BASE_REF` and `$GITHUB_OUTPUT` stay literal.
xform_replace_line "$base" 'run: scripts/check-docs-only.sh "origin/$BASE_REF"' '        run: |
          # was: scripts/check-docs-only.sh "origin/$BASE_REF"
          echo "docs_only=true" >> "$GITHUB_OUTPUT"' "$f"
expect "a commented-out detector call does not count as invoking it" 1 "does not invoke the docs-only detector" --check "$f"

# The mirror of that case: prose naming the detector is not a second resolution.
f="$scratch/prose-mentions-detector.yml"
xform_insert_after "$base" 'echo "  not-a-job: this line lives inside a block scalar"' '          # the scope is resolved once, by scripts/check-docs-only.sh' "$f"
expect "prose naming the detector is not a second resolution" 0 "scope resolved once" --check "$f"

# --- 4. SELF-TEST INTACT ----------------------------------------------------

f="$scratch/no-self-test.yml"
xform_delete "$base" "check-docs-only.test.sh" "$f"
expect "dropping the detector self-test is rejected" 1 "does not run the detector's own suite" --check "$f"

f="$scratch/commented-self-test.yml"
xform_replace_line "$base" "run: bash scripts/check-docs-only.test.sh" "        # run: bash scripts/check-docs-only.test.sh" "$f"
expect "a commented-out self-test does not satisfy the contract" 1 "does not run the detector's own suite" --check "$f"

f="$scratch/soft-self-test.yml"
xform_insert_after "$base" "- name: Test the docs-only detector" "        continue-on-error: true" "$f"
expect "a self-test that cannot turn the job red is rejected" 1 "carries continue-on-error" --check "$f"

# --- 5. ONE CONSUMER FORM ---------------------------------------------------
#
# The historical shape. `!= 'true'` is behaviourally correct here, and is still
# rejected: the contract is that there is exactly one spelling to copy, so the
# next consumer has no polarity decision to make and no comment to keep true.

f="$scratch/negated-form.yml"
xform_replace_line "$base" "if: needs.scope.outputs.run_full == 'false'" "        if: needs.scope.outputs.run_full != 'true'" "$f"
expect "the inverse-polarity consumer form is rejected" 1 "unsanctioned condition" --check "$f"

f="$scratch/truthy-form.yml"
xform_replace_line "$base" "if: needs.scope.outputs.run_full == 'false'" "        if: needs.scope.outputs.run_full" "$f"
expect "a bare truthiness consumer form is rejected" 1 "unsanctioned condition" --check "$f"

# An outer negation whose inner half IS the sanctioned string. A substring
# search would strip the sanctioned half and see nothing left to complain about.
f="$scratch/wrapped-negation.yml"
xform_replace_line "$base" "if: needs.scope.outputs.run_full == 'false'" "        if: \${{ !(needs.scope.outputs.run_full == 'false') }}" "$f"
expect "a negation wrapped around the sanctioned form is rejected" 1 "unsanctioned condition" --check "$f"

# Index syntax is legal Actions and reads identically at runtime; it is still an
# unmodelled spelling, and an unmodelled spelling must never read as sanctioned.
# The three variants below bracket a different part of the accessor each time,
# because a matcher that models only the spelling it expects does not REJECT the
# others — it cannot see them at all, which is the opposite of rejecting them.
f="$scratch/index-syntax-output.yml"
xform_replace_line "$base" "if: needs.scope.outputs.run_full == 'false'" "        if: needs.scope.outputs['run_full'] != 'true'" "$f"
expect "an index-syntax output name is rejected rather than ignored" 1 "unsanctioned condition" --check "$f"

f="$scratch/index-syntax-whole.yml"
xform_replace_line "$base" "if: needs.scope.outputs.run_full == 'false'" "        if: needs['scope']['outputs']['run_full'] == 'false'" "$f"
expect "a fully bracketed accessor is rejected rather than ignored" 1 "unsanctioned condition" --check "$f"

# Actions context accessors are case-insensitive, so this resolves at runtime.
f="$scratch/case-variant.yml"
xform_replace_line "$base" "if: needs.scope.outputs.run_full == 'false'" "        if: needs.SCOPE.outputs.run_full == 'false'" "$f"
expect "a case-variant accessor is rejected rather than ignored" 1 "unsanctioned condition" --check "$f"

# Gating the JOB skips the lane, which leaves a required check Pending.
f="$scratch/job-level-gate.yml"
xform_insert_after "$base" "  gamma:" "    if: needs.scope.outputs.run_full == 'true'" "$f"
expect "a job-level condition on the output is rejected" 1 "JOB-level condition" --check "$f"

# A reusable-workflow job cannot gate at step level, so its polarity decision
# would live in a file this gate never opens.
f="$scratch/reusable-consumer.yml"
xform_insert_after "$base" "    uses: some-org/some-repo/.github/workflows/lint.yml@v1" "    if: needs.scope.outputs.run_full == 'true'" "$f"
expect "a reusable-workflow job reading the output is rejected" 1 "delegates to a reusable workflow" --check "$f"

# A block-scalar body is a script, never a gate. A condition-shaped line inside
# one must not be credited as a step condition — the whole point of skipping
# scalar structure while still reading scalar content.
f="$scratch/gate-inside-scalar.yml"
xform_replace_line "$base" 'echo "        if: always()"' '          echo "        if: needs.scope.outputs.run_full == '"'"'true'"'"'"' "$f"
expect "a condition-shaped line inside a block scalar is not a step condition" 1 "outside a step condition" --check "$f"

# The aggregator feed has its own exact template; a mutated one is not it.
f="$scratch/mutated-feed.yml"
xform_replace_line "$base" "alpha-check=" "            alpha-check=\${{ needs.scope.outputs.run_full == 'true' && 'success' || steps.work.outcome }}" "$f"
expect "a mutated aggregator feed entry is rejected" 1 "outside the aggregator feed template" --check "$f"

# --- 5b. THE FEED MIRRORS A REAL GATE ---------------------------------------
#
# Forgetting a feed override is fail-closed (the raw `skipped` reds the
# aggregate). Adding one for a step that is NOT gated is fail-open: on every
# docs-only diff that step's real outcome is replaced by `success`. Only the
# second direction needs a gate, and this is it.
f="$scratch/feed-without-gate.yml"
xform_replace_line "$base" "alpha-check=" "            alpha-check=\${{ needs.scope.outputs.run_full == 'false' && 'success' || steps.ungated.outcome }}" "$f"
expect "a feed override for an ungated step is rejected" 1 "THE FEED MIRRORS A REAL GATE" --check "$f"

# --- 5c. NO JOB-LEVEL CONDITION ON A CONSUMER -------------------------------
#
# The two sanctioned forms are exact complements only while the output is set,
# which is guaranteed by the consumer running solely on a successful resolver.
# A job-level condition can let the job run anyway, and then BOTH forms are
# false: every gated step and its not-applicable reporter skip together, and the
# lane reports success having done nothing. The condition need not mention the
# output to do this.
f="$scratch/consumer-always.yml"
xform_insert_after "$base" "  gamma:" "    if: always()" "$f"
expect "a consumer carrying an unconditional job-level if is rejected" 1 "NO JOB-LEVEL CONDITION ON A CONSUMER" --check "$f"

f="$scratch/consumer-not-cancelled.yml"
xform_insert_after "$base" "  gamma:" "    if: \${{ !cancelled() }}" "$f"
expect "a consumer carrying !cancelled() is rejected" 1 "NO JOB-LEVEL CONDITION ON A CONSUMER" --check "$f"

# The aggregate's own job-level condition is not a consumer's, and must stand.
expect "the aggregate's own job-level condition is untouched" 0 "scope resolved once" --check "$base"

# --- 6. EDGE DECLARED -------------------------------------------------------

f="$scratch/missing-edge.yml"
xform_delete "$base" "needs: [scope]" "$f"
expect "a consumer reading the output without the needs edge is rejected" 1 "EDGE DECLARED" --check "$f"

# --- 7. CONTRACT IS LIVE ----------------------------------------------------
#
# Zero references must never read as "every reference is well formed".

f="$scratch/no-consumers.yml"
xform_delete "$base" "needs.scope.outputs.run_full" "$f"
expect "a resolver nobody reads is rejected" 1 "CONTRACT IS LIVE" --check "$f"

# --- fail closed on shape and usage -----------------------------------------

f="$scratch/bad-shape.yml"
xform_insert_after "$base" "jobs:" "  not a job key" "$f"
expect "an unparsed workflow shape is inconclusive, never a pass" 2 "unrecognized workflow shape" --check "$f"

f="$scratch/bad-needs-entry.yml"
xform_replace_line "$base" "      - scope # the resolver" "      - [scope]" "$f"
expect "an unmodelled needs entry is inconclusive, never a bogus defect" 2 "unsupported needs entry" --check "$f"

# A sequence item at the key's own indent is valid YAML and must not read as a
# missing edge — a gate that cries wolf on a legal shape gets switched off.
f="$scratch/shallow-needs-item.yml"
xform_replace_line "$base" "      - scope # the resolver" "    - scope" "$f"
expect "a same-indent needs item is a declared edge, not a defect" 0 "scope resolved once" --check "$f"

# `continue-on-error` decides whether a failure is absorbed. An expression-valued
# one cannot be judged without evaluating it, so the gate must refuse rather than
# guess in either direction.
f="$scratch/expression-coe.yml"
xform_replace_line "$base" "        continue-on-error: true" "        continue-on-error: \${{ true }}" "$f"
expect "an expression-valued continue-on-error is inconclusive, never a pass" 2 "not a literal true/false" --check "$f"

f="$scratch/no-jobs.yml"
xform_delete "$base" "jobs:" "$f"
expect "a file with no jobs mapping is inconclusive" 2 "no jobs: mapping found" --check "$f"

f="$scratch/no-resolver.yml"
xform_replace_line "$base" "  scope:" "  renamed-scope:" "$f"
expect "a missing resolving job is inconclusive, never a pass" 2 "is not defined" --check "$f"

expect "a missing workflow file is inconclusive" 2 "workflow not found" --check "$scratch/absent.yml"
expect "a bare invocation prints usage" 2 "usage:"
expect "an unknown mode prints usage" 2 "usage:" --lint
expect "an excess argument prints usage" 2 "usage:" --check "$base" ci-status

# --- the live contract ------------------------------------------------------
#
# The point of the suite: the shipped workflow satisfies what the cases above
# prove the gate can detect. This is what makes the fixture cases load-bearing
# rather than a private exercise.

expect "the shipped ci.yml satisfies the contract" 0 "scope resolved once" --check ".github/workflows/ci.yml"

# --- the half of the fail-closed proof that lives in the detector ------------
#
# The gate pins the workflow-side half: the published output is derived by
# `docs_only != 'true'`, so an UNSET detector output resolves to "run the full
# suite". That is only a real guarantee if a detector that fails leaves the
# output genuinely unset. These cases close that half against the real script.
#
# check-docs-only.test.sh covers the RESOLVABLE fail-closed paths (an unreadable
# allowlist, an unresolvable base ref) emitting docs_only=false. What is
# asserted here is what happens when the script cannot complete at all.

gho="$scratch/github-output"

# A usage abort returns before the emit path is reachable.
: >"$gho"
if GITHUB_OUTPUT="$gho" bash "$DETECTOR" >/dev/null 2>&1; then
  fail "detector invoked with no base-ref argument should exit non-zero"
elif [[ -s "$gho" ]]; then
  fail "a detector usage abort wrote to GITHUB_OUTPUT: $(cat "$gho")"
else
  ok "a detector usage abort leaves docs_only unset, which run_full renders as 'true'"
fi

# An unwritable $GITHUB_OUTPUT is the case the workflow comment names. The
# script's own header claims a non-zero exit here; it does not in fact exit
# non-zero, because emit() does not check its redirect. That is why the
# workflow's guarantee is built on the output being UNSET rather than on the
# script's exit status: the assertion below is the one the contract rests on.
unwritable="$scratch/no-such-dir/output"
GITHUB_OUTPUT="$unwritable" bash "$DETECTOR" "origin/main" >/dev/null 2>&1
if [[ -e "$unwritable" ]]; then
  fail "expected no output file to be produced at an unwritable path"
else
  ok "an unwritable GITHUB_OUTPUT leaves docs_only unset, which run_full renders as 'true'"
fi

# --- verdict ----------------------------------------------------------------

if [[ "$failures" -ne 0 ]]; then
  printf '\n%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall tests passed\n'
