#!/usr/bin/env bash
# Runs the `Fail a queued pull request a hold stops, before the lanes` step
# body of .github/workflows/pr-require-checks.yml's select-tests under the
# shell Actions gives a step with no `shell:` (bash -e), against a stub `gh`,
# with the repository's own merge-holds.mjs and api-budget.bash as the base
# commit's.
#
# In the merge queue a pull request carrying a hold label (do-not-merge, the
# tracker's human-gated label, pr-verify-failed), a head a pr-unblock lane
# stopped, or a lanes App pull request while the kill switch is on fails
# select-tests, which every lane needs, so no lane runs (#10747). ci-status
# still judges each hold. A read that fails, an unparsable ref or a base module
# without queueHolds leaves the hold to ci-status and passes. The step ends
# with the api-calls notice: two requests, the pull and one statuses page.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

NAME='Fail a queued pull request a hold stops, before the lanes'
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
if [[ "$step" == *"if: github.event_name == 'merge_group'"* && "$step" != *"continue-on-error"* ]]; then
  ok "step runs only in the merge queue and fails the job on its exit code"
else
  fail "step lost its merge_group condition or continues on error"
fi
order="$(grep -nE "^  (select-tests|lint-repo):$|^      - name: ($NAME|Fetch base)$" "$WORKFLOW" | cut -d: -f1 | head -4 | paste -sd' ')"
read -r job_line hold_line fetch_line next_job <<<"$order"
if [[ -n "${next_job:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$fetch_line" && "$fetch_line" -lt "$next_job" ]]; then
  ok "step sits in select-tests before the history fetch"
else
  fail "step is not in select-tests before the history fetch (lines: $order)"
fi
if grep -qE "^      - (select-tests|mark-lanes)$" <<<"$(awk '/^  ci-status:$/ { on = 1 } on && /^    if:/ { exit } on' "$WORKFLOW")"; then
  ok "ci-status still needs select-tests, so a held group's aggregate fails"
else
  fail "ci-status no longer needs select-tests"
fi

RULES="$TMP_ROOT/rules"
mkdir -p "$RULES"
cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$ROOT/.github/actions/log-api-budget/api-budget.bash" "$RULES/"

# The gh stub logs its arguments and, under GH_DEBUG, the request line the
# api-budget wrapper counts. A pulls read answers STUB_PULL, after a header
# block when the wrapper added -i. A statuses read applies the step's --jq to
# STUB_STATUSES (newest first). STUB_FAIL=pulls|statuses fails that read.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
[[ -z "${GH_DEBUG:-}" ]] || echo "* Request to https://api.github.com/x" >&2
case "$*" in
*/pulls/*)
  [[ "${STUB_FAIL:-}" != pulls ]] || exit 1
  [[ "$2" != -i ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: core\r\n\r\n'
  printf '%s\n' "$STUB_PULL"
  ;;
*/statuses*)
  [[ "${STUB_FAIL:-}" != statuses ]] || exit 1
  while [[ $# -gt 0 && "$1" != --jq ]]; do shift; done
  jq -r "$2" <<<"${STUB_STATUSES:-[]}"
  ;;
*) exit 1 ;;
esac
EOF
chmod +x "$TMP_ROOT/bin/gh"

HEAD=fedcba9876543210fedcba9876543210fedcba98
GROUP_BASE=89abcdef0123456789abcdef0123456789abcdef
REF="refs/heads/gh-readonly-queue/main/pr-7-$GROUP_BASE"
LANE='{"login":"github-actions[bot]"}'
# pull [labels-json] [user-json]
PERSON='{"id":5,"type":"User"}'
pull() { jq -cn --arg h "$HEAD" --argjson l "${1:-[]}" --argjson u "${2:-$PERSON}" '{number: 7, head: {sha: $h}, labels: $l, user: $u}'; }
status() { jq -cn --arg c "$1" --arg s "$2" --argjson u "$LANE" '{context: $c, state: $s, creator: $u, description: "The lane stopped"}'; }

# expect <label> <want-rc> <STUB_PULL> <STUB_STATUSES> [want-out] [refuse-out]
expect() {
  local label="$1" want_rc="$2" out rc
  : >"$TMP_ROOT/log"
  rm -rf "$TMP_ROOT/api-budget"
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_PULL="$3" STUB_STATUSES="$4" \
    GITHUB_REPOSITORY=o/r GITHUB_REF="${GROUP_REF-$REF}" RULES="${RULES_DIR-$RULES}" RUNNER_TEMP="$TMP_ROOT" \
    LANES_APP_SENDER_ID=99 LANES_DISABLED="${DISABLED-false}" LANES_REPO_DISABLED=false bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ -n "${5:-}" && "$out" != *"$5"* ]]; then
    fail "$label: output lacks '$5': '$out'"
  elif [[ -n "${6:-}" && "$out" == *"$6"* ]]; then
    fail "$label: output has '$6': '$out'"
  else
    ok "$label"
  fi
}

expect "an unheld pull request passes" 0 "$(pull)" "[$(status pr-unblock/fix-ci success)]" \
  "#7: no hold label, pr-unblock stop or kill switch holds it before the lanes." "::error::"
if grep -q "^api -i repos/o/r/pulls/7$" "$TMP_ROOT/log" && grep -q "^api repos/o/r/commits/$HEAD/statuses?per_page=100 --paginate --jq " "$TMP_ROOT/log" &&
  ! grep -q "$GROUP_BASE/statuses" "$TMP_ROOT/log"; then
  ok "it reads #7 and its head's statuses, every page, not the group's base"
else
  fail "unexpected reads: '$(cat "$TMP_ROOT/log")'"
fi
expect "the step ends with its api-calls notice: the pull and one statuses page" 0 "$(pull)" "[]" \
  "::notice title=api-calls::github-token=2 not-modified=0"
expect "do-not-merge fails before the lanes" 1 "$(pull '[{"name":"do-not-merge"}]')" "[]" \
  "::error::#7 carries the 'do-not-merge' label; the merge queue removes it. Remove the label and re-queue to merge. The lanes do not run"
expect "needs-human fails before the lanes" 1 "$(pull '[{"name":"needs-human"}]')" "[]" "::error::#7 carries 'needs-human'"
expect "pr-verify-failed fails before the lanes" 1 "$(pull '[{"name":"pr-verify-failed"}]')" "[]" "::error::#7 carries 'pr-verify-failed'"
expect "an unheld label passes" 0 "$(pull '[{"name":"bug"}]')" "[]"
echo '{"config":{"role_labels":{"human-gated":"hitl"}}}' >"$RULES/tracker.json"
expect "the base tracker's human-gated label holds" 1 "$(pull '[{"name":"hitl"}]')" "[]" "::error::#7 carries 'hitl'"
expect "with the tracker's own label, needs-human is not a hold" 0 "$(pull '[{"name":"needs-human"}]')" "[]"
rm "$RULES/tracker.json"
expect "a pr-unblock stop on the head fails before the lanes" 1 "$(pull)" "[$(status pr-unblock/fix-ci failure)]" \
  "::error::'pr-unblock/fix-ci' is failure on $HEAD: The lane stopped."
expect "a stop a newer success supersedes passes" 0 "$(pull)" "[$(status pr-unblock/fix-ci success),$(status pr-unblock/fix-ci failure)]"
expect "another account's failure does not hold" 0 "$(pull)" "$(jq -c '.[0].creator = {login: "someone"}' <<<"[$(status pr-unblock/fix-ci failure)]")"
DISABLED=true expect "the lanes App's pull request fails while the kill switch is on" 1 "$(pull '[]' '{"id":99,"type":"Bot"}')" "[]" \
  "::error::#7: the lanes kill switch is on"
DISABLED=true expect "a person's pull request is not held by the kill switch" 0 "$(pull)" "[]"
DISABLED=false expect "the lanes App's pull request passes with the switch off" 0 "$(pull '[]' '{"id":99,"type":"Bot"}')" "[]"
DISABLED=true
expect "every hold is named" 1 "$(pull '[{"name":"do-not-merge"}]' '{"id":99,"type":"Bot"}')" "[$(status pr-unblock/conflict error)]" \
  "'pr-unblock/conflict' is error"
n=$(grep -c "^::error::" <<<"$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" STUB_PULL="$(pull '[{"name":"do-not-merge"}]' '{"id":99,"type":"Bot"}')" \
STUB_STATUSES="[$(status pr-unblock/conflict error)]" GITHUB_REPOSITORY=o/r GITHUB_REF="$REF" RULES="$RULES" RUNNER_TEMP="$TMP_ROOT" \
LANES_APP_SENDER_ID=99 LANES_DISABLED=true LANES_REPO_DISABLED=false bash -e "$TMP_ROOT/body.sh" 2>&1)")
if [[ "$n" -eq 3 ]]; then ok "three holds give three errors"; else fail "three holds gave $n errors"; fi
unset DISABLED

# What it cannot read it leaves to ci-status, and passes.
STUB_FAIL=pulls expect "an unreadable pull request passes to ci-status" 0 "$(pull '[{"name":"do-not-merge"}]')" "[]" \
  "::warning::could not read #7; ci-status judges the holds."
STUB_FAIL=statuses expect "an unreadable status list passes to ci-status" 0 "$(pull)" "[]" "::warning::could not read the statuses of $HEAD"
expect "a pull request with no head passes to ci-status" 0 '{"number":7,"head":{},"labels":[{"name":"do-not-merge"}]}' "[]" \
  "::warning::the head of #7 is not a commit SHA"
GROUP_REF=refs/heads/gh-readonly-queue/main/pr-7-abc expect "an unparsable ref passes to ci-status" 0 "$(pull)" "[]" \
  "::warning::cannot read a pull request number from the merge-group ref"
if [[ -s "$TMP_ROOT/log" ]]; then fail "an unparsable ref was read: '$(cat "$TMP_ROOT/log")'"; else ok "an unparsable ref makes no call"; fi
RULES_DIR='' expect "no base rules pass to ci-status" 0 "$(pull '[{"name":"do-not-merge"}]')" "[]" \
  "::notice::the base commit's hold rules did not read; ci-status judges the holds."
if [[ -s "$TMP_ROOT/log" ]]; then fail "no base rules still read: '$(cat "$TMP_ROOT/log")'"; else ok "no base rules make no call"; fi
mkdir -p "$TMP_ROOT/old"
cp "$RULES/api-budget.bash" "$TMP_ROOT/old/"
echo 'export const unblockStops = () => [];' >"$TMP_ROOT/old/merge-holds.mjs"
RULES_DIR="$TMP_ROOT/old" expect "a base module without queueHolds passes to ci-status" 0 "$(pull '[{"name":"do-not-merge"}]')" "[]" \
  "::warning::the base commit's merge-holds.mjs could not judge #7; ci-status judges the holds."

test_harness::report
