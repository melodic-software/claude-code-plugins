#!/usr/bin/env bash
# Runs the `Fail a head a pr-unblock lane stopped` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# ci-status fails while the newest `pr-unblock/*` status on the head, by
# github-actions[bot], is a failure or error, and names each such context. A
# later success on the same head supersedes a failure. In the merge queue the
# head is the queued pull request's, read live. The rule is the base commit's
# merge-holds.mjs unblockStops, here the repository's own copy. It fails closed
# when it cannot tell, a base module that cannot judge included.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"
export RUNNER_TEMP="$TMP_ROOT"
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" budget || fail "the ci-status gh_read helper step is missing or fails"

NAME='Fail a head a pr-unblock lane stopped'
step="$(awk -v name="      - name: $NAME" '$0 == name { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no '$NAME' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi
# A draft's ci-status passes by design (`Note a draft`), so the step makes no
# read there; a merge group has no pull_request.draft, so the queue runs it.
if [[ "$step" == *"if: \${{ !cancelled() && (github.event_name == 'pull_request' || github.event_name == 'merge_group') && github.event.pull_request.draft != true }}"* ]]; then
  ok "step runs on every pull_request and merge_group run that is not cancelled or a draft"
else
  fail "step lost its pull_request and merge_group condition or its draft skip"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

# The gh stub logs its arguments. A pulls read answers STUB_PULL, after the
# api-budget wrapper's header block when it added -i. A statuses read fails
# while STUB_STATUS_FAILS is set, else applies the step's --jq filter to the
# STUB_STATUSES array (newest first, as the API lists them), as gh does per
# page.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*/pulls/*)
  [[ -z "${STUB_PULL_FAILS:-}" ]] || exit 1
  [[ "$2" != -i ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: core\r\n\r\n'
  printf '%s\n' "$STUB_PULL"
  ;;
*/statuses*)
  [[ -z "${STUB_STATUS_FAILS:-}" ]] || exit 1
  while [[ $# -gt 0 && "$1" != --jq ]]; do shift; done
  jq -r "$2" <<<"${STUB_STATUSES:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
cat >"$TMP_ROOT/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_SLEEPS"
EOF
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"
mkdir -p "$TMP_ROOT/base/.github/scripts/pr-merge"
cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$TMP_ROOT/base/.github/scripts/pr-merge/"

HEAD=0123456789abcdef0123456789abcdef01234567
QUEUED=fedcba9876543210fedcba9876543210fedcba98
GROUP_BASE=89abcdef0123456789abcdef0123456789abcdef
LANE='{"login":"github-actions[bot]"}'
# status <context> <state> [creator] [description]
status() { jq -cn --arg c "$1" --arg s "$2" --argjson u "${3:-$LANE}" --arg d "${4:-The lane stopped}" \
  '{context: $c, state: $s, creator: $u, description: $d}'; }

# expect <label> <want-rc> <STUB_STATUSES> [want-out] [refuse-out]
# EVENT (default pull_request), REF and STUB_PULL come from the environment.
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  : >"$TMP_ROOT/sleeps"
  ci_gh_read::reset "$TMP_ROOT" 1792800600
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_SLEEPS="$TMP_ROOT/sleeps" STUB_STATUSES="$3" \
    GITHUB_REPOSITORY=o/r GITHUB_EVENT_NAME="${EVENT:-pull_request}" GITHUB_REF="${REF:-refs/pull/7/merge}" \
    HEAD_SHA="${HEAD_SHA-$HEAD}" BASE_CONFIG="${BASE_CONFIG-$TMP_ROOT/base}" RUNNER_TEMP="$TMP_ROOT" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${4:-}" && "$out" != *"$4"* ]]; then
    fail "$label: output lacks '$4': '$out'"
  elif [[ -n "${5:-}" && "$out" == *"$5"* ]]; then
    fail "$label: output has '$5': '$out'"
  else
    ok "$label"
  fi
}

expect "no pr-unblock status passes" 0 "[$(status ci-lanes failure)]" "No pr-unblock/* status fails on $HEAD."
if grep -q "^api repos/o/r/commits/$HEAD/statuses?per_page=100 --paginate --jq " "$TMP_ROOT/log"; then
  ok "the statuses of the event's head are read, every page"
else
  fail "unexpected statuses read: '$(cat "$TMP_ROOT/log")'"
fi
expect "an empty status list passes" 0 "[]"
expect "a success passes" 0 "[$(status pr-unblock/fix-ci success)]"
expect "a pending status passes" 0 "[$(status pr-unblock/fix-ci pending)]"
expect "a failure fails and names the context" 1 "[$(status pr-unblock/fix-ci failure)]" \
  "::error::'pr-unblock/fix-ci' is failure on $HEAD: The lane stopped."
expect "an error fails and names the context" 1 "[$(status pr-unblock/conflict error)]" "::error::'pr-unblock/conflict' is error on $HEAD"
expect "each failing context is named" 1 "[$(status pr-unblock/fix-ci failure),$(status pr-unblock/address-feedback success),$(status pr-unblock/conflict error)]" \
  "'pr-unblock/conflict' is error" "'pr-unblock/address-feedback'"
out_both="$(grep -c "::error::'pr-unblock/" <<<"$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_SLEEPS="$TMP_ROOT/sleeps" \
  STUB_STATUSES="[$(status pr-unblock/fix-ci failure),$(status pr-unblock/conflict error)]" GITHUB_REPOSITORY=o/r \
  GITHUB_EVENT_NAME=pull_request HEAD_SHA="$HEAD" BASE_CONFIG="$TMP_ROOT/base" RUNNER_TEMP="$TMP_ROOT" bash -e "$TMP_ROOT/body.sh" 2>&1)")"
if [[ "$out_both" -eq 2 ]]; then ok "two failing contexts give two errors"; else fail "two failing contexts gave $out_both errors"; fi
expect "a newer success supersedes an older failure" 0 "[$(status pr-unblock/fix-ci success),$(status pr-unblock/fix-ci failure)]"
expect "a newer failure over an older success fails" 1 "[$(status pr-unblock/fix-ci failure),$(status pr-unblock/fix-ci success)]" "'pr-unblock/fix-ci' is failure"
expect "another account's newer success does not supersede the lane's failure" 1 \
  "[$(status pr-unblock/fix-ci success '{"login":"someone"}'),$(status pr-unblock/fix-ci failure)]" "'pr-unblock/fix-ci' is failure"
expect "another account's failure does not hold" 0 "[$(status pr-unblock/fix-ci failure '{"login":"someone"}')]"
expect "a description's percent sign is escaped" 1 "[$(status pr-unblock/fix-ci failure "$LANE" '100% stuck')]" "100%25 stuck"
export STUB_STATUS_FAILS=1
expect "an unreadable status list fails closed" 1 "[]" "::error::could not read the statuses of $HEAD; re-run this run."
unset STUB_STATUS_FAILS
expect "a description's tab and newline become spaces" 1 "[$(status pr-unblock/fix-ci failure "$LANE" $'one\ttwo\nthree')]" "on $HEAD: one two three. The lane"
export BASE_CONFIG=
expect "no base config fails closed" 1 "[]" "::error::cannot read merge-holds.mjs in the hold config (the default branch's tip at run time, or the base commit for another base); re-run this run."
if [[ -s "$TMP_ROOT/log" ]]; then fail "no base config still read: '$(cat "$TMP_ROOT/log")'"; else ok "no base config makes no call"; fi
mkdir -p "$TMP_ROOT/old/.github/scripts/pr-merge"
echo 'export const refsIssue = () => null;' >"$TMP_ROOT/old/.github/scripts/pr-merge/merge-holds.mjs"
export BASE_CONFIG="$TMP_ROOT/old"
expect "a base module without unblockStops fails closed" 1 "[$(status pr-unblock/fix-ci success)]" \
  "::error::merge-holds.mjs in the hold config (the default branch's tip at run time, or the base commit for another base) could not judge the statuses of $HEAD; re-run this run."
echo 'export const unblockStops = () => ({});' >"$TMP_ROOT/old/.github/scripts/pr-merge/merge-holds.mjs"
expect "a base module that answers no list fails closed" 1 "[]" "could not judge the statuses of $HEAD"
unset BASE_CONFIG
export HEAD_SHA=main
expect "a pull request head that is not a commit SHA fails closed" 1 "[]" "::error::the head 'main' is not a commit SHA."
if [[ -s "$TMP_ROOT/log" ]]; then fail "a bad head was read: '$(cat "$TMP_ROOT/log")'"; else ok "a bad head makes no call"; fi
unset HEAD_SHA

export EVENT=merge_group REF="refs/heads/gh-readonly-queue/main/pr-7-$GROUP_BASE" HEAD_SHA=
export STUB_PULL="{\"number\":7,\"head\":{\"sha\":\"$QUEUED\"}}"
expect "the queued pull request's head is read, not the group's base" 1 \
  "[$(status pr-unblock/fix-ci failure)]" "::error::'pr-unblock/fix-ci' is failure on $QUEUED"
if grep -q "^api -i repos/o/r/pulls/7$\|^api repos/o/r/pulls/7$" "$TMP_ROOT/log" && grep -q "commits/$QUEUED/statuses" "$TMP_ROOT/log" &&
  ! grep -q "$GROUP_BASE/statuses" "$TMP_ROOT/log"; then
  ok "the merge queue reads #7 and its head's statuses"
else
  fail "unexpected merge-queue reads: '$(cat "$TMP_ROOT/log")'"
fi
expect "a queued pull request with a superseded failure passes" 0 "[$(status pr-unblock/fix-ci success),$(status pr-unblock/fix-ci failure)]"
export STUB_PULL_FAILS=1
expect "an unreadable queued pull request fails closed" 1 "[]" "::error::could not read #7; re-run this run."
unset STUB_PULL_FAILS
export STUB_PULL='{"number":7,"head":{}}'
expect "a queued pull request with no head fails closed" 1 "[]" "::error::the head '' is not a commit SHA."
export REF="refs/heads/gh-readonly-queue/main/pr-7-abc123"
expect "an unparsable merge-group ref fails closed" 1 "[]" "::error::cannot read a pull request number from the merge-group ref"
if [[ -s "$TMP_ROOT/log" ]]; then fail "an unparsable ref was read: '$(cat "$TMP_ROOT/log")'"; else ok "an unparsable ref makes no call"; fi
unset EVENT REF HEAD_SHA STUB_PULL

test_harness::report
