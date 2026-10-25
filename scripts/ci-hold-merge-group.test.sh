#!/usr/bin/env bash
# Runs the `Fail a queued pull request carrying a hold label` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions
# gives a step with no `shell:` (bash -e), against stub `gh` and `sleep`.
#
# A merge-group run carries no pull request, so this step is the only reader of
# the hold labels in the merge queue: `do-not-merge` and the human-gated label
# the base commit's .work-item-tracker.json names (default `needs-human`). It
# must fail on either, pass without them, and fail closed when it cannot tell.
# For a pull request an automation opened it also applies the trust hold to
# the linked issue: a label naming untrusted work, in any spelling, or one
# removed other than by a person on the base's trusted-actor list, holds, so
# a label added after the pull request opened stops the merge.
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

NAME='Fail a queued pull request carrying a hold label'
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
if [[ "$step" == *"if: github.event_name == 'merge_group'"* ]]; then
  ok "step runs on merge_group only"
else
  fail "step lost its merge_group condition"
fi
if [[ "$step" == *"continue-on-error"* ]]; then
  fail "step must not continue on error: its exit code is the hold"
else
  ok "step fails the job on its exit code"
fi
if [[ "$step" == *"BASE_SHA: \${{ github.event.merge_group.base_sha }}"* ]]; then
  ok "step names the group's base commit"
else
  fail "step does not name merge_group.base_sha"
fi
if [[ "$step" == *"BASE_CONFIG: \${{ steps.base_config.outcome == 'success' && format('{0}/base-config', github.workspace) || '' }}"* ]]; then
  ok "step reads the tracker config from the base checkout, and none when it failed"
else
  fail "step does not read the tracker config from the base_config checkout"
fi
# Inside ci-status, before the aggregate, so a red here is the job's answer.
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

# The base commit's config is a fixture directory: STUB_TRACKER is its
# .work-item-tracker.json (absent when unset), and STUB_CHECKOUT_FAILED leaves
# BASE_CONFIG empty, as a failed checkout does. The gh stub logs its
# arguments. A labels read fails its first STUB_FAILS calls, then prints
# STUB_LABELS one per line.
mkdir -p "$TMP_ROOT/bin"
# The link read answers STUB_LINK (default: a person's pull request), or
# fails with STUB_LINK_FAIL; a timeline read prints STUB_TIMELINE, one
# unlabeled event per line, or fails with STUB_TIMELINE_FAIL; issue 18's
# labels read prints STUB_ISSUE_LABELS.
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*graphql*)
  [[ -z "${STUB_LINK_FAIL:-}" ]] || exit 1
  # The api-budget wrapper adds -i to a single read: the headers come first.
  [[ "$2" != -i ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: graphql\r\n\r\n'
  person='{"data":{"repository":{"pullRequest":{"author":{"__typename":"User"}}}}}'
  printf '%s\n' "${STUB_LINK:-$person}"
  ;;
*/timeline*)
  [[ -z "${STUB_TIMELINE_FAIL:-}" ]] || exit 1
  [[ -z "${STUB_TIMELINE:-}" ]] || printf '%s\n' "$STUB_TIMELINE"
  ;;
*issues/18/labels*)
  [[ -z "${STUB_ISSUE_LABELS:-}" ]] || tr ',' '\n' <<<"$STUB_ISSUE_LABELS"
  ;;
*/labels*)
  [[ "$(grep -c '/labels' "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || exit 1
  [[ -z "$STUB_LABELS" ]] || tr ',' '\n' <<<"$STUB_LABELS"
  ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

SHA=0123456789abcdef0123456789abcdef01234567
BASE=89abcdef0123456789abcdef0123456789abcdef
QUEUE="refs/heads/gh-readonly-queue/main/pr-6419-$SHA"
CUSTOM='{"config":{"role_labels":{"human-gated":" owner-call "}}}'
# The base's trusted-actor list: person 100, and the lanes App 200.
ACTORS='{"version":1,"actors":[{"id":100,"login":"maintainer","kind":"human"},{"id":200,"login":"agent-lanes[bot]","kind":"bot"}]}'

# expect <label> <want-rc> <want-label-calls> <want-pr|-> <GITHUB_REF> <STUB_LABELS> <STUB_FAILS> [want-out]
# The tracker fixture is set by the caller's environment (STUB_TRACKER, STUB_CHECKOUT_FAILED, BASE_SHA).
expect() {
  local label="$1" want_rc="$2" want_calls="$3" want_pr="$4" out rc calls config="$TMP_ROOT/base-config"
  : >"$TMP_ROOT/log"
  rm -rf "$config"
  mkdir -p "$config"
  [[ -z "${STUB_TRACKER+set}" ]] || printf '%s\n' "$STUB_TRACKER" >"$config/.work-item-tracker.json"
  mkdir -p "$config/.github/standards/trusted-actors" "$config/.github/scripts/pr-merge"
  printf '%s\n' "${STUB_ACTORS:-$ACTORS}" >"$config/.github/standards/trusted-actors/trusted-actors.json"
  cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$config/.github/scripts/pr-merge/"
  [[ -z "${STUB_CHECKOUT_FAILED:-}" ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REF="$5" STUB_LABELS="$6" STUB_FAILS="$7" \
    GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" BASE_SHA="${BASE_SHA-$BASE}" BASE_CONFIG="$config" \
    bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -c '/labels' "$TMP_ROOT/log")
  TRUST_CALLS=$(grep -cE 'graphql|/timeline|issues/18/labels' "$TMP_ROOT/log")
  TRUST_OUT=$out
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls labels call(s) got $calls"
  elif [[ "$want_pr" != - ]] &&
    [[ "$(grep '/labels' "$TMP_ROOT/log" | sort -u)" != "api repos/o/r/issues/$want_pr/labels?per_page=100 --paginate --jq .[].name" ]]; then
    fail "$label: unexpected gh call '$(sort -u "$TMP_ROOT/log")'"
  elif grep -q '/contents/' "$TMP_ROOT/log"; then
    fail "$label: the tracker config was read through the API: '$(sort -u "$TMP_ROOT/log")'"
  elif [[ -n "${8:-}" && "$out" != *"$8"* ]]; then
    fail "$label: output lacks '$8': '$out'"
  else
    ok "$label"
  fi
}

expect "unlabeled queued pull request passes" 0 1 6419 "$QUEUE" "enhancement,ci" 0 "#6419 carries neither"
expect "pull request with no labels passes" 0 1 6419 "$QUEUE" "" 0
expect "do-not-merge fails the run" 1 1 6419 "$QUEUE" "ci,do-not-merge" 0 "::error::#6419 carries the 'do-not-merge' label"
expect "needs-human fails the run" 1 1 6419 "$QUEUE" "ci,needs-human" 0 "::error::#6419 carries 'needs-human'; the merge queue removes it. Removing the label approves this pull request"
expect "a label that only contains the name does not hold" 0 1 6419 "$QUEUE" "do-not-merge-later,not-do-not-merge,needs-human-later" 0
expect "ref without refs/heads/ is read" 1 1 6419 "gh-readonly-queue/main/pr-6419-$SHA" "do-not-merge" 0
expect "base branch with a slash is read" 1 1 12 "refs/heads/gh-readonly-queue/release/v2/pr-12-$SHA" "do-not-merge" 0
expect "a transient read failure is retried" 1 2 6419 "$QUEUE" "do-not-merge" 1
expect "an unreadable label list fails closed" 1 3 6419 "$QUEUE" "" 3 "::error::could not read the labels of #6419"
expect "a non-queue ref fails closed without a call" 1 0 - "refs/heads/main" "" 0 "::error::cannot read a pull request number"
expect "a short sha fails closed without a call" 1 0 - "refs/heads/gh-readonly-queue/main/pr-6419-abc123" "" 0

export STUB_TRACKER="$CUSTOM"
expect "the base tracker's human-gated label holds" 1 1 6419 "$QUEUE" "owner-call" 0 "::error::#6419 carries 'owner-call'"
expect "needs-human does not hold when the tracker names another label" 0 1 6419 "$QUEUE" "needs-human" 0 "carries neither 'do-not-merge' nor 'owner-call'"
export STUB_TRACKER='{"config":{"lease_ttl_hours":24}}'
expect "a tracker naming no label falls back to needs-human" 1 1 6419 "$QUEUE" "needs-human" 0 "carries 'needs-human'"
export STUB_TRACKER='{not json'
expect "an invalid tracker config fails closed" 1 0 - "$QUEUE" "" 0 "::error::cannot read the human-gated role label"
export STUB_TRACKER="$CUSTOM" STUB_CHECKOUT_FAILED=1
expect "a base checkout that failed fails closed" 1 0 - "$QUEUE" "" 0 "::error::could not read .work-item-tracker.json at $BASE; re-run this run."
unset STUB_TRACKER STUB_CHECKOUT_FAILED
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed without a call" 1 0 - "$QUEUE" "" 0 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

# The trust hold. link <author type> <closing issue JSON nodes> [body]: the
# link read's answer for the queued pull request.
link() {
  jq -nc --arg author "$1" --argjson nodes "$2" --arg body "${3:-}" \
    '{data: {repository: {pullRequest: {author: {__typename: $author}, body: $body,
      closingIssuesReferences: {totalCount: ($nodes | length), nodes: $nodes}}}}}'
}
issue() {
  jq -nc --argjson n "$1" --arg repo "${3:-o/r}" --argjson names "$2" \
    '{number: $n, repository: {nameWithOwner: $repo}, labels: {totalCount: ($names | length), nodes: ($names | map({name: .}))}}'
}
unlabeled() {
  jq -nc --arg type "$2" --argjson id "$3" --argjson app "${4:-null}" --arg name "$1" \
    '{event: "unlabeled", label: {name: $name}, actor: {type: $type, id: $id}, performed_via_github_app: $app}'
}
# trust <label> <want-rc> <want-trust-calls> [want-out] [refs]: one case over
# the STUB_* the caller set; a clean pull request label list. With `refs`, the
# Refs issue's labels read is a second labels call.
trust() {
  if [[ -n "${5:-}" ]]; then
    expect "$1" "$2" 2 - "$QUEUE" "enhancement" 0 "${4:-}"
  else
    expect "$1" "$2" 1 6419 "$QUEUE" "enhancement" 0 "${4:-}"
  fi
  if [[ "$TRUST_CALLS" -ne "$3" ]]; then
    fail "$1: expected $3 trust-hold call(s) got $TRUST_CALLS: '$TRUST_OUT'"
  fi
}
UNTRUSTED='work-class: untrusted-provenance'

# Exported once and emptied, never unset, so each assignment reaches the step.
export STUB_LINK='' STUB_LINK_FAIL='' STUB_TIMELINE='' STUB_TIMELINE_FAIL='' STUB_ISSUE_LABELS='' STUB_ACTORS=''
trust "a person's pull request reads no issue" 0 1 "is a person's pull request"
STUB_LINK="$(link Bot "[$(issue 16 '["agent-ready"]')]")"
trust "an automation's pull request whose issue is clean passes" 0 2 "carries no label naming untrusted work"
STUB_LINK="$(link Bot "[$(issue 16 "[\"agent-ready\",\"$UNTRUSTED\"]")]")"
trust "an issue labeled after the pull request opened fails the run" 1 1 "::error::issue #16, which #6419 links, carries a label naming untrusted work (untrusted-provenance)"
for variant in 'Work-Class: Untrusted_Provenance' 'untrusted' 'work-class:UNTRUSTED-provenance'; do
  STUB_LINK="$(link Bot "[$(issue 16 "[\"$variant\"]")]")"
  trust "the variant spelling '$variant' fails the run" 1 1 "(untrusted-provenance)"
done
STUB_LINK="$(link Bot "[$(issue 16 '[]'),$(issue 17 "[\"$UNTRUSTED\"]")]")"
trust "any of several closing issues holds" 1 2 "issue #17"
STUB_LINK="$(link Bot "[$(issue 16 "[\"$UNTRUSTED\"]" other/repo)]")"
trust "an issue in another repository is not read" 0 1 "links no issue in this repository"
cut="$(issue 16 '["agent-ready"]' | jq -c '.labels.totalCount = 101')"
STUB_LINK="$(link Bot "[$cut]")"
trust "a cut label list fails closed" 1 1 "(issue-labels-unreadable)"
STUB_LINK="$(link Bot '[]' | jq -c '.data.repository.pullRequest.closingIssuesReferences.totalCount = 11')"
trust "a cut closing-issue list fails closed" 1 1 "could not all be read"
STUB_LINK_FAIL=1
expect "an unreadable link fails closed after three reads" 1 1 6419 "$QUEUE" "enhancement" 0 "::error::could not read the issue link of #6419"
[[ "$TRUST_CALLS" -eq 3 ]] || fail "an unreadable link: expected 3 reads got $TRUST_CALLS"
STUB_LINK_FAIL=''
STUB_LINK="$(link Bot "[$(issue 16 '[]')]")" STUB_TIMELINE_FAIL=1
trust "an unreadable timeline fails closed after three reads" 1 4 "::error::could not read the timeline of issue #16"
STUB_TIMELINE_FAIL=''
for event in "$(unlabeled "$UNTRUSTED" Bot 200)" "$(unlabeled "$UNTRUSTED" User 100 '{"slug":"x"}')" "$(unlabeled 'Untrusted' User 300)"; do
  STUB_TIMELINE="$event"
  trust "a removal by a non-human holds: $event" 1 2 "(untrusted-provenance-removed-by-non-human)"
done
STUB_TIMELINE="$(unlabeled "$UNTRUSTED" User 100)
$(unlabeled 'ci' Bot 200)"
trust "a listed person's removal lifts it, and another label's removal is ignored" 0 2 "no such label was removed"
STUB_TIMELINE=''
STUB_ACTORS='{not json'
trust "an unreadable trusted-actor list fails closed" 1 1 "could not read trusted-actors.json"
STUB_ACTORS=''
STUB_LINK="$(link Bot '[]' 'Refs: #18')" STUB_ISSUE_LABELS="agent-ready,$UNTRUSTED"
trust "the one Refs issue is read and holds" 1 2 "issue #18, which #6419 links, carries a label naming untrusted work" refs
STUB_ISSUE_LABELS=agent-ready
trust "a clean Refs issue passes" 0 3 "carries no label naming untrusted work" refs
STUB_LINK="$(link Bot '[]' 'Refs: #18
Refs: #19')"
trust "two Refs issues link none" 0 1 "links no issue in this repository"
STUB_LINK='' STUB_ISSUE_LABELS=''

test_harness::report
