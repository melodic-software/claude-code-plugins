#!/usr/bin/env bash
# Self-test for scripts/check-lane-coverage.sh
#
# Fixtures are plain files under mktemp, addressed by ABSOLUTE path: the script
# cds to the git toplevel, so an absolute fixture path resolves from anywhere and
# no scratch git repo is needed. That is deliberate — a fixture repo would need
# `git -C <dir> config user.*`, and the un-scoped form of that command writes the
# test identity into the CALLER's repo config (claude-code-plugins#2839). No git
# state means the class cannot recur here.
#
# Every fixture run passes its OWN step opt-out list. The repository's real list
# names steps of the real ci.yml, and an entry naming a step no fixture defines
# is a stale opt-out by construction — so a fixture checked against it would fail
# for a reason that has nothing to do with the case under test.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/check-lane-coverage.sh"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$ROOT/scripts/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
scratch=""
fixture_tree::build scratch --label lane-coverage

NONE="$scratch/no-optouts.txt"
: >"$NONE"

# Runs the gate and asserts exit code plus (optionally) a substring of output.
expect() {
  local label="$1" want_rc="$2" want_text="$3"
  shift 3
  local out rc
  out="$(bash "$SCRIPT" "$@" 2>&1)" && rc=0 || rc=$?
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

# --- fixture builders -------------------------------------------------------

# A minimal but structurally faithful workflow: two lanes, an aggregate, and a
# body shaped like the real file (comments, block scalars, nested `if:` keys).
write_workflow() {
  local path="$1" extra_job_block="$2" needs_block="$3"
  cat >"$path" <<YAML
name: ci

on:
  pull_request:

permissions:
  contents: read

jobs:
  # A leading comment block, the way the real file carries them.
  alpha:
    runs-on: ubuntu-24.04
    steps:
      - name: Do a thing
        run: |
          echo "  not-a-job: this line lives inside a block scalar"
          echo done

  beta:
    runs-on: ubuntu-24.04
    if: github.event_name == 'pull_request'
    steps:
      - name: Do another thing
        run: echo ok
${extra_job_block}
  ci-status:
${needs_block}
    if: \${{ !cancelled() }}
    runs-on: ubuntu-24.04
    steps:
      - name: Aggregate lane results
        run: echo aggregated
YAML
}

needs_of() {
  printf '    needs:\n'
  local n
  for n in "$@"; do printf '      - %s\n' "$n"; done
}

# The step-level shape: a `lint` job whose lanes are `continue-on-error` steps,
# with an aggregator feed reading their outcomes back out of a block scalar. The
# caller supplies the steps and the feed rows so each case can break exactly one
# side of the pairing. A `noop` lane rides along so `ci-status.needs` is never
# empty, which is its own exit-2 shape.
#
# An annotation on `lint` also takes `lint` OUT of needs, because an annotated
# job that IS in needs is a stale opt-out — a different defect from the one such
# a fixture is built to exercise.
write_step_workflow() {
  local path="$1" steps_block="$2" feed_block="$3" job_annotation="${4:-}"
  local needs_rows='      - noop'
  [[ -n "$job_annotation" ]] || needs_rows+='
      - lint'
  cat >"$path" <<YAML
name: ci

on:
  pull_request:

jobs:
  noop:
    runs-on: ubuntu-24.04
    steps:
      - name: Do nothing
        run: echo ok

${job_annotation}  lint:
    runs-on: ubuntu-24.04
    steps:
${steps_block}
      - name: Aggregate this job's gate steps
        env:
          CHECK_RESULTS: |
${feed_block}
        run: scripts/aggregate-hygiene-results.sh

  ci-status:
    needs:
${needs_rows}
    runs-on: ubuntu-24.04
    steps:
      - name: Aggregate lane results
        run: echo aggregated
YAML
}

# A steps block, from one `<kind>:<id>` spec per step:
#   gate  — `continue-on-error: true` plus an id, the pairable shape
#   plain — an id but no absorb flag, so the step fails its job on its own
#   anon  — the absorb flag with no id, so nothing can read its outcome
steps_of() {
  local spec kind id
  for spec in "$@"; do
    kind="${spec%%:*}"
    id="${spec#*:}"
    printf '      - name: Run the %s gate\n' "$id"
    [[ "$kind" == anon ]] || printf '        id: %s\n' "$id"
    [[ "$kind" == plain ]] || printf '        continue-on-error: true\n'
    printf '        run: scripts/%s.sh --check\n' "$id"
  done
}

# The aggregator feed rows for the named ids, in the shape ci.yml uses.
# shellcheck disable=SC2016 # deliberate: ${{ }} is workflow syntax, not a shell expansion
feed_of() {
  local id
  for id in "$@"; do printf '            %s=${{ steps.%s.outcome }}\n' "$id" "$id"; done
}

# --- usage / input errors ---------------------------------------------------

expect "bare invocation exits 2 with usage" 2 "usage:"
expect "unknown mode exits 2 with usage" 2 "usage:" --verify
expect "missing workflow exits 2" 2 "workflow not found" --check "$scratch/nope.yml"
expect "excess arguments exit 2" 2 "usage:" --check "$scratch/nope.yml" ci-status "$NONE" extra

write_workflow "$scratch/list-missing.yml" "" "$(needs_of alpha beta)"
expect "missing step opt-out list exits 2" 2 "step opt-out list not found" \
  --check "$scratch/list-missing.yml" ci-status "$scratch/no-such-list.txt"

printf 'name: ci\non:\n  pull_request:\n' >"$scratch/nojobs.yml"
expect "workflow with no jobs mapping exits 2" 2 "no jobs: mapping found" \
  --check "$scratch/nojobs.yml" ci-status "$NONE"

# --- the defect this gate exists to catch, at JOB level ---------------------

write_workflow "$scratch/ungated.yml" "" "$(needs_of alpha)"
expect "job absent from needs fails and names the job" 1 "UNGATED LANE: job 'beta'" \
  --check "$scratch/ungated.yml" ci-status "$NONE"

write_workflow "$scratch/covered.yml" "" "$(needs_of alpha beta)"
expect "every job in needs passes" 0 "all 2 lane(s) reachable" \
  --check "$scratch/covered.yml" ci-status "$NONE"

# --- a lane that fans out across a matrix -----------------------------------
#
# Sharding a lane leaves the LANE LIST alone: the job key is unchanged, so one
# `needs` entry still covers every leg. What is new is the `strategy:` block,
# whose 6- and 8-space lines this structural parser must fall through rather
# than read as job keys or as needs entries. It is pinned here because
# check-lane-coverage.sh exits 2 on any shape it does not model, and an
# inconclusive gate on the real ci.yml would block every pull request.
write_workflow "$scratch/sharded.yml" "  gamma:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix: \${{ github.event_name == 'pull_request' && fromJSON('{\"leg\":[0,1,2,3]}') || fromJSON('{\"leg\":[0]}') }}
    steps:
      - name: Run this leg
        env:
          LEG: \${{ strategy.job-index }}
          LEGS: \${{ strategy.job-total }}
        run: echo \"leg \$LEG of \$LEGS\"
" "$(needs_of alpha beta gamma)"
expect "a lane carrying a strategy matrix parses and stays covered" 0 "all 3 lane(s) reachable" \
  --check "$scratch/sharded.yml" ci-status "$NONE"

write_workflow "$scratch/sharded-static.yml" "  gamma:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        leg: [0, 1, 2, 3]
    steps:
      - name: Run this leg
        run: echo leg
" "$(needs_of alpha beta gamma)"
expect "a literal matrix block parses too" 0 "all 3 lane(s) reachable" \
  --check "$scratch/sharded-static.yml" ci-status "$NONE"

# --- the job opt-out path ---------------------------------------------------

write_workflow "$scratch/optout.yml" "" "$(needs_of alpha)"
# Annotate `beta` via the contiguous comment block immediately above its key.
annotate_above() {
  local file="$1" job="$2" comment="$3"
  awk -v job="  ${job}:" -v c="$comment" '
    $0 == job { print c } { print }
  ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}
annotate_above "$scratch/optout.yml" beta "  # lane-coverage-ok: advisory lane, findings routed to code scanning"
expect "annotated opt-out passes" 0 "all 1 lane(s) reachable" \
  --check "$scratch/optout.yml" ci-status "$NONE"

write_workflow "$scratch/bare-optout.yml" "" "$(needs_of alpha)"
annotate_above "$scratch/bare-optout.yml" beta "  # lane-coverage-ok:"
expect "opt-out with no reason fails" 1 "BARE OPT-OUT: job 'beta'" \
  --check "$scratch/bare-optout.yml" ci-status "$NONE"

write_workflow "$scratch/trailing-optout.yml" "" "$(needs_of alpha)"
awk '{ sub(/^  beta:$/, "  beta:  # lane-coverage-ok: deliberately advisory"); print }' \
  "$scratch/trailing-optout.yml" >"$scratch/trailing-optout.yml.tmp" &&
  mv "$scratch/trailing-optout.yml.tmp" "$scratch/trailing-optout.yml"
expect "trailing-comment opt-out passes" 0 "all 1 lane(s) reachable" \
  --check "$scratch/trailing-optout.yml" ci-status "$NONE"

write_workflow "$scratch/stale-optout.yml" "" "$(needs_of alpha beta)"
annotate_above "$scratch/stale-optout.yml" beta "  # lane-coverage-ok: no longer true"
expect "opt-out on a job that IS in needs fails as stale" 1 "STALE OPT-OUT: job 'beta'" \
  --check "$scratch/stale-optout.yml" ci-status "$NONE"

# An annotation separated from its job key by a blank line must NOT carry over.
write_workflow "$scratch/detached-optout.yml" "" "$(needs_of alpha)"
awk '
  $0 == "  beta:" { print "  # lane-coverage-ok: this comment is not contiguous"; print "" }
  { print }
' "$scratch/detached-optout.yml" >"$scratch/detached-optout.yml.tmp" &&
  mv "$scratch/detached-optout.yml.tmp" "$scratch/detached-optout.yml"
expect "non-contiguous annotation does not exempt the job" 1 "UNGATED LANE: job 'beta'" \
  --check "$scratch/detached-optout.yml" ci-status "$NONE"

# --- dangling needs ---------------------------------------------------------

write_workflow "$scratch/dangling.yml" "" "$(needs_of alpha beta gamma)"
expect "needs entry with no defined job fails" 1 "DANGLING NEED" \
  --check "$scratch/dangling.yml" ci-status "$NONE"

# --- unrecognized shapes must be inconclusive, never green ------------------

write_workflow "$scratch/flow-needs.yml" "" "    needs: [alpha, beta]"
expect "flow-sequence needs exits 2, not 0" 2 "not a block sequence" \
  --check "$scratch/flow-needs.yml" ci-status "$NONE"

write_workflow "$scratch/scalar-needs.yml" "" "    needs: alpha"
expect "scalar needs exits 2, not 0" 2 "not a block sequence" \
  --check "$scratch/scalar-needs.yml" ci-status "$NONE"

write_workflow "$scratch/no-needs.yml" "" "    permissions:
      contents: read"
expect "aggregate with no needs block exits 2" 2 "declares no needs: block" \
  --check "$scratch/no-needs.yml" ci-status "$NONE"

write_workflow "$scratch/empty-needs.yml" "" "    needs:
"
expect "aggregate with an empty needs block exits 2" 2 "empty needs: block" \
  --check "$scratch/empty-needs.yml" ci-status "$NONE"

write_workflow "$scratch/odd-key.yml" "  &anchor-not-a-job:
    runs-on: ubuntu-24.04
" "$(needs_of alpha beta)"
expect "unmodelled 2-space key exits 2" 2 "unrecognized key under jobs" \
  --check "$scratch/odd-key.yml" ci-status "$NONE"

write_workflow "$scratch/missing-agg.yml" "" "$(needs_of alpha beta)"
expect "unknown aggregate job exits 2" 2 "is not defined" \
  --check "$scratch/missing-agg.yml" no-such-job "$NONE"

# --- STEP level: the gate set and the feed set must be equal ----------------
#
# This is the half that survived the six-job collapse. A lane is now a step
# carrying `continue-on-error: true`; the flag absorbs its failure, so the only
# thing that turns anything red is the aggregator reading `steps.<id>.outcome`
# back. A gate the feed does not read is decoration, and the job-level check
# above cannot see it, because the JOB is in `needs`.

write_step_workflow "$scratch/steps-paired.yml" \
  "$(steps_of gate:shellcheck gate:typos)" "$(feed_of shellcheck typos)"
expect "every gate step fed to the aggregator passes" 0 "all 2 gate step(s) fed" \
  --check "$scratch/steps-paired.yml" ci-status "$NONE"

write_step_workflow "$scratch/steps-unfed.yml" \
  "$(steps_of gate:shellcheck gate:typos)" "$(feed_of shellcheck)"
expect "a gate step missing from the feed fails and names it" 1 \
  "UNFED GATE: step 'typos' in job 'lint'" \
  --check "$scratch/steps-unfed.yml" ci-status "$NONE"

write_step_workflow "$scratch/steps-anonymous.yml" \
  "$(steps_of gate:shellcheck anon:typos)" "$(feed_of shellcheck)"
expect "a gate step with no id fails as unreadable" 1 \
  "UNREADABLE GATE: job 'lint' step #2 ('Run the typos gate')" \
  --check "$scratch/steps-anonymous.yml" ci-status "$NONE"

write_step_workflow "$scratch/steps-dangling-feed.yml" \
  "$(steps_of gate:shellcheck)" "$(feed_of shellcheck typos)"
expect "a feed row naming no step fails" 1 "no step in that job declares 'id: typos'" \
  --check "$scratch/steps-dangling-feed.yml" ci-status "$NONE"

write_step_workflow "$scratch/steps-feed-without-flag.yml" \
  "$(steps_of gate:shellcheck plain:typos)" "$(feed_of shellcheck typos)"
expect "a feed row for a step without continue-on-error fails" 1 \
  "does not carry 'continue-on-error: true'" \
  --check "$scratch/steps-feed-without-flag.yml" ci-status "$NONE"

# The feed carries an override on a docs-only diff; the row still names exactly
# one step, and that is the only part this gate reads. (Which overrides are
# sanctioned is scripts/check-docs-only-gate.sh's question, not this one.)
write_step_workflow "$scratch/steps-overridden-feed.yml" \
  "$(steps_of gate:shellcheck)" \
  "            shellcheck=\${{ needs.changes.outputs.run_full == 'false' && 'success' || steps.shellcheck.outcome }}"
expect "an overridden feed row still pairs with its gate step" 0 "all 1 gate step(s) fed" \
  --check "$scratch/steps-overridden-feed.yml" ci-status "$NONE"

# Steps of a job that is itself an annotated opt-out cannot gate a merge
# whatever they do, so the step-level check does not second-guess them.
write_step_workflow "$scratch/steps-annotated-job.yml" \
  "$(steps_of gate:shellcheck gate:typos)" "$(feed_of shellcheck)" \
  "  # lane-coverage-ok: advisory lane, findings routed to code scanning
"
expect "an unfed gate step in an annotated job is exempt" 0 "all 1 gate step(s) fed" \
  --check "$scratch/steps-annotated-job.yml" ci-status "$NONE"

# --- STEP level: shapes this gate refuses to guess at -----------------------

write_step_workflow "$scratch/steps-expr-flag.yml" \
  "      - name: Run the shellcheck gate
        id: shellcheck
        continue-on-error: \${{ github.event_name == 'pull_request' }}
        run: scripts/shellcheck.sh --check" \
  "$(feed_of shellcheck)"
expect "an expression-valued continue-on-error exits 2" 2 "is not a literal true/false" \
  --check "$scratch/steps-expr-flag.yml" ci-status "$NONE"

write_step_workflow "$scratch/steps-odd-feed.yml" \
  "$(steps_of gate:shellcheck)" \
  "            shellcheck=\${{ steps.shellcheck.outcome == 'success' }}"
expect "a feed row in an unmodelled shape exits 2" 2 "a shape this gate does not model" \
  --check "$scratch/steps-odd-feed.yml" ci-status "$NONE"

write_step_workflow "$scratch/steps-two-in-a-row.yml" \
  "$(steps_of gate:shellcheck gate:typos)" \
  "            both=\${{ steps.shellcheck.outcome || steps.typos.outcome }}"
expect "a feed row naming two steps exits 2" 2 "reads more than one step" \
  --check "$scratch/steps-two-in-a-row.yml" ci-status "$NONE"

# --- STEP level: the opt-out list, checked in both directions ---------------

optout_list() {
  local path="$1"
  shift
  printf '%s\n' "$@" >"$path"
  printf '%s' "$path"
}

write_step_workflow "$scratch/steps-optout.yml" \
  "$(steps_of gate:shellcheck gate:resolver)" "$(feed_of shellcheck)"
expect "an opted-out gate step passes" 0 "1 opted out" \
  --check "$scratch/steps-optout.yml" ci-status \
  "$(optout_list "$scratch/ol-good.txt" \
    "# A whole-line comment is prose about the list, not a reason." \
    "lint/resolver  its failure must fall through to a fail-open default, not turn the job red")"

expect "an opt-out with no reason fails" 1 "BARE STEP OPT-OUT" \
  --check "$scratch/steps-optout.yml" ci-status \
  "$(optout_list "$scratch/ol-bare.txt" "lint/resolver")"

# A whole-line comment is prose about the list. It never stands in as the reason
# for the entry under it, so the reason cannot drift away from what it excuses.
expect "a comment line above an entry is not its reason" 1 "BARE STEP OPT-OUT" \
  --check "$scratch/steps-optout.yml" ci-status \
  "$(optout_list "$scratch/ol-above.txt" "# resolver's own step, fails open by design" "lint/resolver")"

write_step_workflow "$scratch/steps-paired-again.yml" \
  "$(steps_of gate:shellcheck gate:typos)" "$(feed_of shellcheck typos)"
expect "an opt-out for a step the feed reads anyway fails as stale" 1 \
  "STALE STEP OPT-OUT: " \
  --check "$scratch/steps-paired-again.yml" ci-status \
  "$(optout_list "$scratch/ol-fed.txt" "lint/typos  no longer true")"

expect "an opt-out for a step that is not a gate fails as stale" 1 \
  "no step with that id in that job carries 'continue-on-error: true'" \
  --check "$scratch/steps-paired-again.yml" ci-status \
  "$(optout_list "$scratch/ol-gone.txt" "lint/deleted  the step this excused was deleted")"

expect "a malformed opt-out entry exits 2" 2 "malformed entry in" \
  --check "$scratch/steps-paired-again.yml" ci-status \
  "$(optout_list "$scratch/ol-malformed.txt" "lint:typos  the separator is a slash")"

# --- the real workflow ------------------------------------------------------

expect "the repository's own ci.yml is fully covered" 0 "reachable from ci-status.needs" --check
expect "every gate step in the repository's own ci.yml is fed or opted out" 0 \
  "gate step(s) fed to the aggregator" --check

test_harness::report
