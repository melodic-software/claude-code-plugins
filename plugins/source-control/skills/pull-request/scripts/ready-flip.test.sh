#!/usr/bin/env bash
# Regression tests for ready's wait, guarded flip and ready-run confirmation (the "Wait for the
# push's CI run", "Flip to ready" and "Confirm a ready run" blocks of the GitHub ready reference)
# against a forge that lags one read behind a push: its first head read still returns the
# pre-push commit. Black-box, with the
# blocks extracted from the reference and run in a fixture repository against a stubbed `gh`.
# test-scope: plugins/source-control/skills/pull-request/scripts/pr-worktree.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REF="$SCRIPT_DIR/../../../reference/providers/github/pull-request/ready-for-review.md"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

REPORT_REF="$SKILL_DIR/reference/ready-for-review.md"

# block <heading> [<n>] [<file>]: the nth (default first) fenced block in that heading's section
# of <file> (default: the GitHub ready reference), with <skill-dir> filled in.
block() {
  awk -v h="$1" -v n="${2:-1}" '$0 == h { on = 1; next } on && !f && /^## / { exit }
    on && /^```bash/ { if (++i == n) f = 1; next } f && /^```/ { exit } f' "${3:-$REF}" |
    sed "s#<skill-dir>#$SKILL_DIR#g"
}

FLOW="$TEST_TMPDIR/flow.sh"
# shellcheck disable=SC2016 # the echoed lines expand in the generated script, not this one
{
  block "## Wait for the push's CI run"
  echo 'echo "WAITED=${FOUND:-skipped} HEAD_SHA=$HEAD_SHA"'
  block "## Flip to ready"
  echo 'echo "FLIP_EXIT=$?"'
  block "## Confirm a ready run" 1
  block "## Confirm a ready run" 2
  echo 'echo "CONFIRM=$?"'
} >"$FLOW"
if ! grep -q 'verify-gate.sh" check --head' "$FLOW" || ! grep -q '^ready_run_seen$' "$FLOW"; then
  echo "FAIL: the wait, flip and confirmation blocks were not found in $REF" >&2
  exit 1
fi
REPORT="$TEST_TMPDIR/report.sh"
block "## 2.5.6 Report" 1 "$REPORT_REF" >"$REPORT"
if ! grep -q 'confirm-verdict.sh" show --head' "$REPORT"; then
  echo "FAIL: the confirm verdict block was not found in $REPORT_REF" >&2
  exit 1
fi

# Fixture: the parent commit is the PR head before the push, the tip is the pushed commit.
REPO="$TEST_TMPDIR/repo"
git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m before
BEFORE=$(git -C "$REPO" rev-parse HEAD)
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m review-fix
PUSHED=$(git -C "$REPO" rev-parse HEAD)

STUB_DIR="$TEST_TMPDIR/stubs"
mkdir -p "$STUB_DIR"
printf '#!/usr/bin/env bash\nexit 0\n' >"$STUB_DIR/sleep"
# The forge's first head read returns STUB_STALE, later reads STUB_FORGE (default: the pushed
# commit); pr-worktree.sh's head read returns STUB_BRANCH and STUB_OID. Runs exist only for the pushed commit, and a new one only once the PR is flipped. Each
# run list logs the commit it asked about; `pr ready` logs the flip.
cat >"$STUB_DIR/gh" <<'STUB_EOF'
#!/usr/bin/env bash
case "$1 $2" in
"pr view")
  if [[ "$*" == *headRefName* ]]; then
    echo "$STUB_BRANCH $STUB_OID"
  elif [[ ! -e "$STUB_STATE/read" ]]; then
    : >"$STUB_STATE/read"
    echo "$STUB_STALE"
  else
    echo "${STUB_FORGE:-$STUB_PUSHED}"
  fi
  ;;
"run list")
  args="$*" commit=""
  while (($# > 0)); do
    [[ "$1" == --commit ]] && commit="$2"
    shift
  done
  echo "$commit" >>"$STUB_STATE/runs"
  if [[ "$args" == *index* ]]; then
    [[ "$commit" == "$STUB_PUSHED" && -e "$STUB_STATE/flipped" ]] && echo 1 || echo 0
  elif [[ "$commit" == "$STUB_PUSHED" ]]; then
    [[ "$args" == *length* ]] && echo 2 || echo '[11,12]'
  else
    [[ "$args" == *length* ]] && echo 0 || echo '[]'
  fi
  ;;
"pr ready") echo "$*" >>"$STUB_STATE/flipped" ;;
*) exit 1 ;;
esac
STUB_EOF
chmod +x "$STUB_DIR/gh" "$STUB_DIR/sleep"

# new_state [<sha>]: a fresh stub state and verify dir, with a pass recorded for <sha>.
RUN=0
new_state() {
  RUN=$((RUN + 1))
  STATE="$TEST_TMPDIR/state-$RUN"
  mkdir -p "$STATE/verify"
  [[ -z "${1:-}" ]] || READY_VERIFY_DIR="$STATE/verify" bash "$SKILL_DIR/scripts/verify-gate.sh" record --head "$1" --result pass
}

# run_flow <stale-head> <head-before> [<later-forge-head>], in the state new_state made, from
# $FLOW_CWD (default: the PR's checkout), with pr-worktree.sh reading STUB_OID (default: the
# pre-push head, as a lagging read returns it).
STUB_BRANCH=$(git -C "$REPO" branch --show-current)
run_flow() {
  (cd "${FLOW_CWD:-$REPO}" && PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" STUB_STALE="$1" STUB_PUSHED="$PUSHED" \
    STUB_FORGE="${3:-$PUSHED}" STUB_BRANCH="$STUB_BRANCH" STUB_OID="${STUB_OID:-$BEFORE}" \
    READY_VERIFY_DIR="$STATE/verify" PR_NUMBER=5 HEAD_BEFORE="$2" timeout 30 bash "$FLOW" 2>&1)
}

new_state "$PUSHED"
out=$(run_flow "$BEFORE" "$BEFORE")
assert_contains "lagging forge: the wait finds the pushed commit's runs" "$out" "WAITED=1 HEAD_SHA=$PUSHED"
assert_contains "lagging forge: the guarded flip passes on the pushed commit" "$out" "FLIP_EXIT=0"
assert_eq "lagging forge: the PR is flipped once" "pr ready 5" "$(cat "$STATE/flipped" 2>/dev/null)"
assert_not_contains "lagging forge: no run list asks about the pre-push commit" "$(cat "$STATE/runs")" "$BEFORE"
assert_contains "lagging forge: the confirmation sees the ready run, so no toggle" "$out" "CONFIRM=0"

new_state ""
out=$(run_flow "$BEFORE" "$BEFORE")
assert_contains "no verify record for the pushed commit: the guard refuses" "$out" "FLIP_EXIT=2"
[[ -e "$STATE/flipped" ]] && flipped=yes || flipped=no
assert_eq "no verify record for the pushed commit: the PR is not flipped" "no" "$flipped"

new_state "$BEFORE"
out=$(run_flow "$BEFORE" "$BEFORE")
assert_contains "a record for the pre-push commit only: the guard refuses" "$out" "FLIP_EXIT=2"

# The /verification:confirm verdict: recorded per head, named in the 2.5.6 report for the PR
# worktree's HEAD, and advisory, so neither NEEDS WORK nor a missing verdict stops the flip or
# changes the verify gate's result for that head.
confirm_record() { CONFIRM_VERDICT_DIR="$STATE/confirm" bash "$SKILL_DIR/scripts/confirm-verdict.sh" record "$@"; }
run_report() {
  (cd "$REPO" && PATH="$STUB_DIR:$PATH" STUB_STATE="$STATE" STUB_BRANCH="$STUB_BRANCH" STUB_OID="$PUSHED" \
    CONFIRM_VERDICT_DIR="$STATE/confirm" PR_NUMBER=5 timeout 30 bash "$REPORT" 2>&1)
}

new_state "$PUSHED"
confirm_record --head "$PUSHED" --verdict 'NEEDS WORK' --missing 'AC1: unmet' --partial 'AC2: half'
assert_exit "a NEEDS WORK verdict with items is recorded for the head" 0 "$?"
READY_VERIFY_DIR="$STATE/verify" bash "$SKILL_DIR/scripts/verify-gate.sh" check --head "$PUSHED"
assert_exit "a NEEDS WORK verdict leaves the head's verify pass as it was" 0 "$?"
out=$(CONFIRM_VERDICT_DIR="$STATE/confirm" run_flow "$BEFORE" "$BEFORE")
assert_contains "a NEEDS WORK verdict for the head: the guarded flip passes" "$out" "FLIP_EXIT=0"
assert_eq "a NEEDS WORK verdict for the head: the PR is flipped once" "pr ready 5" "$(cat "$STATE/flipped" 2>/dev/null)"
out=$(run_report)
assert_exit "the report's confirm verdict line exits 0 after the flip" 0 "$?"
assert_eq "the report names NEEDS WORK for the head and each MISSING or PARTIAL item" "confirm: NEEDS WORK for head $PUSHED
  MISSING: AC1: unmet
  PARTIAL: AC2: half" "$out"

new_state ""
confirm_record --head "$PUSHED" --verdict CONFIRMED
assert_exit "a CONFIRMED verdict with no items is recorded for the head" 0 "$?"
out=$(CONFIRM_VERDICT_DIR="$STATE/confirm" run_flow "$BEFORE" "$BEFORE")
assert_contains "a CONFIRMED verdict does not stand in for a missing verify record" "$out" "FLIP_EXIT=2"
assert_eq "the report names a CONFIRMED verdict for the head" "confirm: CONFIRMED for head $PUSHED" "$(run_report)"

new_state "$PUSHED"
confirm_record --head "$BEFORE" --verdict 'NEEDS WORK' --missing 'AC1: unmet'
assert_exit "a verdict is recorded for the pre-push head only" 0 "$?"
out=$(CONFIRM_VERDICT_DIR="$STATE/confirm" run_flow "$BEFORE" "$BEFORE")
assert_contains "no confirm verdict for the head: the guarded flip passes" "$out" "FLIP_EXIT=0"
out=$(run_report)
assert_exit "the report's confirm verdict line exits 0 with no verdict for the head" 0 "$?"
assert_eq "a verdict for an earlier head only: the report says none is recorded for this head" \
  "confirm: no verdict recorded for head $PUSHED" "$out"

# The /verification:measure verdict: recorded per head in the same store, named in the report only
# when one is recorded for the head, and advisory, so no verdict word stops the flip.
measure_record() { CONFIRM_VERDICT_DIR="$STATE/confirm" bash "$SKILL_DIR/scripts/confirm-verdict.sh" record --of measure "$@"; }

for verdict in 'CANNOT QUANTIFY' DEGRADED 'NOT CONFIRMED' INCONCLUSIVE MIXED CONFIRMED; do
  new_state "$PUSHED"
  measure_record --head "$PUSHED" --verdict "$verdict"
  assert_exit "a $verdict measure verdict is recorded for the head" 0 "$?"
  out=$(CONFIRM_VERDICT_DIR="$STATE/confirm" run_flow "$BEFORE" "$BEFORE")
  assert_contains "a $verdict measure verdict for the head: the guarded flip passes" "$out" "FLIP_EXIT=0"
  assert_eq "a $verdict measure verdict for the head: the PR is flipped once" "pr ready 5" "$(cat "$STATE/flipped" 2>/dev/null)"
done

new_state "$PUSHED"
measure_record --head "$PUSHED" --verdict 'CANNOT QUANTIFY' --claim 'startup is twice as fast'
assert_exit "a CANNOT QUANTIFY measure verdict with its claim is recorded for the head" 0 "$?"
out=$(run_report)
assert_exit "the report's verdict lines exit 0 with a CANNOT QUANTIFY verdict" 0 "$?"
assert_eq "the report says cannot quantify for the head and names the claim" "confirm: no verdict recorded for head $PUSHED
measure: CANNOT QUANTIFY for head $PUSHED: no baseline was captured before the change
  CLAIM: startup is twice as fast" "$out"

new_state "$PUSHED"
confirm_record --head "$PUSHED" --verdict CONFIRMED
measure_record --head "$PUSHED" --verdict DEGRADED
assert_eq "the report names both verdicts for the head" "confirm: CONFIRMED for head $PUSHED
measure: DEGRADED for head $PUSHED" "$(run_report)"

new_state "$PUSHED"
measure_record --head "$BEFORE" --verdict CONFIRMED
out=$(run_report)
assert_eq "a measure verdict for an earlier head only adds no line for this head" \
  "confirm: no verdict recorded for head $PUSHED" "$out"
assert_not_contains "no measure verdict for the head: the report has no measure line" "$out" "measure"

new_state "$PUSHED"
out=$(run_flow "$PUSHED" "$PUSHED")
assert_contains "nothing pushed: the wait is skipped" "$out" "WAITED=skipped HEAD_SHA=$PUSHED"
assert_contains "nothing pushed: the guarded flip passes on the head" "$out" "FLIP_EXIT=0"

PEER=$(git -C "$REPO" -c user.name=t -c user.email=t@t commit-tree -p "$PUSHED" -m peer "$(git -C "$REPO" rev-parse "HEAD^{tree}")")
new_state "$PUSHED"
out=$(run_flow "$PEER" "$BEFORE" "$PEER")
assert_contains "the forge's head is a peer commit: the guard refuses" "$out" "FLIP_EXIT=1"
[[ -e "$STATE/flipped" ]] && flipped=yes || flipped=no
assert_eq "the forge's head is a peer commit: the PR is not flipped" "no" "$flipped"

# The session's shell sits in another checkout of the repository, on another branch at the
# pre-push commit: HEAD_SHA is still the PR worktree's HEAD.
git -C "$REPO" worktree add -q -b other "$TEST_TMPDIR/other" "$BEFORE"
new_state "$PUSHED"
out=$(FLOW_CWD="$TEST_TMPDIR/other" run_flow "$BEFORE" "$BEFORE")
assert_contains "from another checkout: HEAD_SHA is the PR worktree's HEAD" "$out" "HEAD_SHA=$PUSHED"
assert_contains "from another checkout: the guarded flip passes on the PR's head" "$out" "FLIP_EXIT=0"

new_state "$PUSHED"
out=$(FLOW_CWD="$TEST_TMPDIR/other" STUB_BRANCH=gone run_flow "$BEFORE" "$BEFORE")
[[ -e "$STATE/flipped" ]] && flipped=yes || flipped=no
assert_eq "the PR's head branch is checked out nowhere: the PR is not flipped" "no" "$flipped"
assert_contains "the PR's head branch is checked out nowhere: the refusal names the branch" "$out" "'gone'"

new_state "$PUSHED"
out=$(FLOW_CWD="$TEST_TMPDIR/other" STUB_OID="$PEER" run_flow "$BEFORE" "$BEFORE")
[[ -e "$STATE/flipped" ]] && flipped=yes || flipped=no
assert_eq "the worktree on the head branch lacks the PR's head commit: the PR is not flipped" "no" "$flipped"
assert_contains "the worktree on the head branch lacks the PR's head commit: the refusal names it" "$out" "$PEER"

[[ $FAILED -eq 0 ]] || exit 1
exit 0
