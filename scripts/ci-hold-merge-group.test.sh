#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"
# shellcheck source=lib/ci-step.sh
. "$ROOT/scripts/lib/ci-step.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# shellcheck source=lib/ci-gh-read.sh
. "$ROOT/scripts/lib/ci-gh-read.sh"
export RUNNER_TEMP="$TMP_ROOT"
ci_gh_read::install "$WORKFLOW" "$TMP_ROOT" budget || fail "the ci-status gh_read helper step is missing or fails"

NAME='Fail a queued pull request carrying a hold label'
step="$(ci_step::read "$WORKFLOW" "$NAME" "$TMP_ROOT/body.sh")" || ci_step::abort "$WORKFLOW" "$NAME"
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
order="$(grep -nE "^  ci-status:$|^      - name: ($NAME|Aggregate lane results)$" "$WORKFLOW" | cut -d: -f1 | paste -sd' ')"
read -r job_line hold_line agg_line <<<"$order"
if [[ -n "${agg_line:-}" && "$job_line" -lt "$hold_line" && "$hold_line" -lt "$agg_line" ]]; then
  ok "step sits in ci-status before the aggregate"
else
  fail "step is not inside ci-status before the aggregate (lines: $order)"
fi

mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$*" in
*graphql*)
  [[ -z "${STUB_LINK_FAIL:-}" ]] || exit 1
  [[ "$(grep -c graphql "$STUB_LOG")" -gt "${STUB_FAILS:-0}" ]] || exit 1
  # The api-budget wrapper adds -i to a single read: the headers come first.
  [[ "$2" != -i ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: graphql\r\n\r\n'
  person='{"data":{"repository":{"pullRequest":{"author":{"__typename":"User"}}}}}'
  jq -c --arg labels "${STUB_LABELS:-}" 'if .data.repository.pullRequest | has("labels") then . else
    .data.repository.pullRequest.labels = ($labels | split(",") | map(select(length > 0)) | {totalCount: length, nodes: map({name: .})}) end' <<<"${STUB_LINK:-$person}"
  ;;
*/timeline*)
  [[ -z "${STUB_TIMELINE_FAIL:-}" ]] || exit 1
  [[ -z "${STUB_TIMELINE:-}" ]] || printf '%s\n' "$STUB_TIMELINE"
  ;;
*issues/18/labels*)
  [[ -z "${STUB_ISSUE_LABELS:-}" ]] || tr ',' '\n' <<<"$STUB_ISSUE_LABELS"
  ;;
*pulls/6419/files*)
  [[ -n "${STUB_FILES:-}" ]] || exit 1
  [[ "$2" != -i ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: core\r\n\r\n'
  printf '%s\n' "$STUB_FILES"
  ;;
*pulls/6419*)
  [[ -n "${STUB_PULL:-}" ]] || exit 1
  [[ "$2" != -i ]] || printf 'HTTP/2.0 200 OK\r\nX-Ratelimit-Remaining: 4000\r\nX-Ratelimit-Resource: core\r\n\r\n'
  printf '%s\n' "$STUB_PULL"
  ;;
*) exit 1 ;;
esac
EOF
printf '#!/usr/bin/env bash\n' >"$TMP_ROOT/bin/sleep"
chmod +x "$TMP_ROOT/bin/gh" "$TMP_ROOT/bin/sleep"

pins="$(grep -nE '^ +LANES_APP_ID:' "$WORKFLOW")"
if [[ "$pins" =~ ^[0-9]+:"      LANES_APP_ID: \${{ vars.AUTOMATION_LANES_APP_SENDER_ID }}"$ ]]; then
  ok "ci-status names the lanes App id once, from the repository variable"
else
  fail "LANES_APP_ID is not set once, at ci-status's job level, from vars.AUTOMATION_LANES_APP_SENDER_ID: '$pins'"
fi
identity="$(sed -nE 's/^  agent-identity: (.+)$/\1/p' "$ROOT/docs/conventions/pr-pipeline.yaml")"
LANES="$(jq -r --arg login "$identity" '.. | objects | select(.login? == $login) | .id' "$ROOT/.github/scripts/lib/fixtures/standards/components/trusted-actors/trusted-actors.json")" DEPENDABOT=49699333
[[ "$LANES" =~ ^[1-9][0-9]*$ ]] || fail "no trusted-actor id for merge.agent-identity '$identity': '$LANES'"

SHA=0123456789abcdef0123456789abcdef01234567
BASE=89abcdef0123456789abcdef0123456789abcdef
QUEUE="refs/heads/gh-readonly-queue/main/pr-6419-$SHA"
CUSTOM='{"config":{"role_labels":{"human-gated":" owner-call "}}}'
ACTORS='{"version":1,"actors":[{"id":100,"login":"maintainer","kind":"human"},{"id":200,"login":"agent-lanes[bot]","kind":"bot"}]}'

expect() {
  local label="$1" want_rc="$2" want_calls="$3" want_pr="$4" out rc calls config="$TMP_ROOT/base-config"
  : >"$TMP_ROOT/log"
  rm -rf "$config" "$TMP_ROOT/standards"
  mkdir -p "$config" "$TMP_ROOT/standards/components/trusted-actors"
  [[ -z "${STUB_TRACKER+set}" ]] || { mkdir -p "$config/docs/conventions" && printf 'tracker: %s\n' "$STUB_TRACKER" >"$config/docs/conventions/work-items.yaml"; }
  mkdir -p "$config/docs/conventions"
  if [[ -n "${STUB_BASELINE_FILE:-}" ]]; then
    printf 'merge:\n  baseline-file: %s\n' "$STUB_BASELINE_FILE" >"$config/docs/conventions/pr-pipeline.yaml"
  else
    printf 'merge:\n  lane-prs: native\n' >"$config/docs/conventions/pr-pipeline.yaml"
  fi
  mkdir -p "$config/.github/scripts/pr-merge"
  printf '%s\n' "${STUB_ACTORS:-$ACTORS}" >"$TMP_ROOT/standards/components/trusted-actors/trusted-actors.json"
  if [[ -n "${STUB_MODULE_TEXT:-}" ]]; then
    printf '%s\n' "$STUB_MODULE_TEXT" >"$config/.github/scripts/pr-merge/merge-holds.mjs"
  elif [[ -z "${STUB_NO_MODULE:-}" ]]; then
    cp "$ROOT/.github/scripts/pr-merge/merge-holds.mjs" "$config/.github/scripts/pr-merge/"
  fi
  [[ -z "${STUB_CHECKOUT_FAILED:-}" ]] || config=
  out="$(PATH="$TMP_ROOT/bin:$PATH" STUB_LOG="$TMP_ROOT/log" GITHUB_REF="$5" STUB_LABELS="$6" STUB_FAILS="$7" \
    GITHUB_REPOSITORY=o/r RUNNER_TEMP="$TMP_ROOT" LANES_APP_ID="$LANES" BASE_SHA="${BASE_SHA-$BASE}" BASE_CONFIG="$config" \
    STANDARDS_DIR="${STUB_STANDARDS-$TMP_ROOT/standards}" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  calls=$(grep -cE 'graphql|/labels' "$TMP_ROOT/log")
  TRUST_CALLS=$(grep -cE 'graphql|/timeline|issues/18/labels' "$TMP_ROOT/log")
  TRUST_OUT=$out
  if [[ "$rc" -ne "$want_rc" ]]; then
    fail "$label: expected rc=$want_rc got rc=$rc out='$out'"
  elif [[ "$calls" -ne "$want_calls" ]]; then
    fail "$label: expected $want_calls labels call(s) got $calls"
  elif grep -q '/labels' < <(grep -vE 'issues/18/labels' "$TMP_ROOT/log"); then
    fail "$label: the pull request's labels were read over REST: '$(sort -u "$TMP_ROOT/log")'"
  elif [[ "$want_pr" != - ]] && grep -vq -- "-F n=$want_pr\$" < <(grep graphql "$TMP_ROOT/log"); then
    fail "$label: the GraphQL read is not for #$want_pr: '$(sort -u "$TMP_ROOT/log")'"
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
expect "pr-verify-failed fails the run" 1 1 6419 "$QUEUE" "ci,pr-verify-failed" 0 "::error::#6419 carries 'pr-verify-failed': pr-verify failed its head, and a pr-verify pass removes the label, at a new commit or at the same head: once a trusted person edits the body, and only trusted people have edited it since the fail, that head is judged again, so a fail on the body or the issues it links needs only the body fixed, no new commit. The merge queue removes it; re-queue it once the label is off."
expect "a label that only contains the name does not hold" 0 1 6419 "$QUEUE" "do-not-merge-later,not-do-not-merge,needs-human-later,pr-verify-failed-later" 0
expect "ref without refs/heads/ is read" 1 1 6419 "gh-readonly-queue/main/pr-6419-$SHA" "do-not-merge" 0
expect "base branch with a slash is read" 1 1 12 "refs/heads/gh-readonly-queue/release/v2/pr-12-$SHA" "do-not-merge" 0
expect "a transient read failure is retried" 1 2 6419 "$QUEUE" "do-not-merge" 1
expect "an unreadable label list fails closed" 1 3 6419 "$QUEUE" "" 3 "::error::could not read the labels and issue link of #6419"
person='{"data":{"repository":{"pullRequest":{"author":{"__typename":"User"}}}}}'
export STUB_LINK
STUB_LINK="$(jq -c '.data.repository.pullRequest.labels = {totalCount: 101, nodes: [{name: "ci"}]}' <<<"$person")"
expect "a cut label list fails closed" 1 1 6419 "$QUEUE" "" 0 "::error::the labels of #6419 could not all be read"
STUB_LINK="$(jq -c '.data.repository.pullRequest.labels = {totalCount: 101, nodes: [{name: "do-not-merge"}]}' <<<"$person")"
expect "a cut label list holding do-not-merge still fails closed" 1 1 6419 "$QUEUE" "" 0 "could not all be read"
STUB_LINK="$(jq -c '.data.repository.pullRequest.labels = null' <<<"$person")"
expect "a missing label list fails closed" 1 1 6419 "$QUEUE" "" 0 "could not all be read"
STUB_LINK="$(jq -c '.data.repository.pullRequest.labels = {totalCount: 1, nodes: [{name: null}]}' <<<"$person")"
expect "a label name that is not a string fails closed" 1 1 6419 "$QUEUE" "" 0 "could not all be read"
STUB_LINK="$(jq -c '.data.repository.pullRequest.labels = {totalCount: 2, nodes: [{name: "ci"}, {name: "do-not-merge"}]}' <<<"$person")"
expect "do-not-merge in the GraphQL label list holds a person's pull request" 1 1 6419 "$QUEUE" "" 0 "::error::#6419 carries the 'do-not-merge' label"
STUB_LINK=''
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
expect "a base checkout that failed fails closed" 1 0 - "$QUEUE" "" 0 "::error::could not read docs/conventions/work-items.yaml at $BASE; re-run this run."
unset STUB_TRACKER STUB_CHECKOUT_FAILED
export STUB_TRACKER=''
expect "an empty tracker config falls back to needs-human" 1 1 6419 "$QUEUE" "needs-human" 0 "::error::#6419 carries 'needs-human'"
export STUB_TRACKER='{"config":{"role_labels":{"human-gated":[1]}}}'
expect "a non-string tracker label falls back to needs-human" 1 1 6419 "$QUEUE" "needs-human" 0 "::error::#6419 carries 'needs-human'"
unset STUB_TRACKER
expect "every hold label is named" 1 1 6419 "$QUEUE" "pr-verify-failed,needs-human,do-not-merge" 0 \
  "::error::#6419 carries the 'do-not-merge' label; the merge queue removes it. Remove the label and re-queue to merge.
::error::#6419 carries 'needs-human'; the merge queue removes it."
export STUB_NO_MODULE=1
expect "a base with no merge-holds.mjs fails closed without a call" 1 0 - "$QUEUE" "do-not-merge" 0 "::error::cannot read merge-holds.mjs at $BASE; re-run this run."
unset STUB_NO_MODULE
export STUB_MODULE_TEXT='export const refsIssue = () => null;'
expect "a base module without labelHolds fails closed without a call" 1 0 - "$QUEUE" "" 0 "::error::cannot read the human-gated role label from docs/conventions/work-items.yaml at $BASE with its merge-holds.mjs"
export STUB_MODULE_TEXT='export const humanGatedLabel = () => "needs-human";'
expect "a base module with humanGatedLabel alone fails closed" 1 1 6419 "$QUEUE" "" 0 "::error::merge-holds.mjs at $BASE could not judge the labels of #6419; re-run this run."
export STUB_MODULE_TEXT='export const humanGatedLabel = () => "needs-human"; export const labelHolds = () => null;'
expect "a base module answering no list fails closed" 1 1 6419 "$QUEUE" "" 0 "could not judge the labels of #6419"
export STUB_MODULE_TEXT='export const humanGatedLabel = () => "needs-human"; export const labelHolds = () => [""];'
expect "a base module answering an empty reason fails closed" 1 1 6419 "$QUEUE" "" 0 "could not judge the labels of #6419"
export STUB_MODULE_TEXT='export const humanGatedLabel = () => "needs-human"; export const labelHolds = () => { process.exit(0); };'
expect "a base module exiting silently fails closed" 1 1 6419 "$QUEUE" "" 0 "could not judge the labels of #6419"
unset STUB_MODULE_TEXT
export BASE_SHA=main
expect "a base that is not a commit SHA fails closed without a call" 1 0 - "$QUEUE" "" 0 "::error::the base commit 'main' is not a commit SHA"
unset BASE_SHA

link() {
  jq -nc --arg author "$1" --argjson nodes "$2" --arg body "${3:-}" --argjson id "${4:-$DEPENDABOT}" \
    '{data: {repository: {pullRequest: {author: {__typename: $author, databaseId: $id}, body: $body,
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
UNTRUSTED='provenance: untrusted'

export STUB_LINK='' STUB_LINK_FAIL='' STUB_TIMELINE='' STUB_TIMELINE_FAIL='' STUB_ISSUE_LABELS='' STUB_ACTORS='' STUB_PULL='' STUB_FILES=''
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
expect "an unreadable link fails closed after three reads" 1 3 6419 "$QUEUE" "enhancement" 0 "::error::could not read the labels and issue link of #6419"
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
STUB_STANDARDS='' trust "with no standards checkout the hold config's copy is never read, and it fails closed" 1 1 "could not read trusted-actors.json from the standards checkout"
STUB_LINK="$(link Bot '[]' 'Refs: #18')" STUB_ISSUE_LABELS="agent-ready,$UNTRUSTED"
trust "the one Refs issue is read and holds" 1 2 "issue #18, which #6419 links, carries a label naming untrusted work" refs
STUB_ISSUE_LABELS=agent-ready
trust "a clean Refs issue passes" 0 3 "carries no label naming untrusted work" refs
STUB_LINK="$(link Bot '[]' 'Refs: #18
Refs: #19' "$DEPENDABOT")"
trust "another automation's two Refs issues link none" 0 1 "links no issue in this repository"
STUB_LINK="$(link Bot '[]' '' "$DEPENDABOT")"
trust "another automation's pull request linking nothing passes" 0 1 "links no issue in this repository"
STUB_LINK='' STUB_ISSUE_LABELS=''

STUB_LINK="$(link Bot '[]' 'Refs: #18
Refs: #19' "$LANES")"
trust "the lanes App's two Refs issues fail the run" 1 1 "its Refs: lines name no single issue"
STUB_LINK="$(link Bot '[]' '' "$LANES")"
trust "the lanes App's pull request linking nothing fails the run" 1 1 "its Refs: lines name no single issue"
STUB_LINK="$(link Bot "[$(issue 16 '[]' other/repo)]" '' "$LANES")"
trust "the lanes App's issue in another repository fails the run" 1 1 "it closes 1 issue(s), none or more than one here"
STUB_LINK="$(link Bot "[$(issue 16 '[]'),$(issue 17 '[]')]" '' "$LANES")"
trust "the lanes App's two closing issues fail the run" 1 1 "it closes 2 issue(s), none or more than one here"
STUB_LINK="$(link Bot "[$(issue 16 '[]'),$(issue 17 '[]' other/repo)]" '' "$LANES")"
trust "the lanes App's second closing issue elsewhere fails the run" 1 1 "it closes 2 issue(s), none or more than one here"
STUB_LINK="$(link Bot "[$(issue 16 '[]')]" '' "$LANES")"
trust "the lanes App's one clean closing issue passes" 0 2 "carries no label naming untrusted work"
STUB_LINK="$(link Bot '[]' 'Refs: #18' "$LANES")" STUB_ISSUE_LABELS=agent-ready
trust "the lanes App's one clean Refs issue passes" 0 3 "carries no label naming untrusted work" refs
STUB_LINK="$(link Bot "[$(issue 16 '[]')]" '' null)"
trust "a bot author with no numeric id fails closed" 1 1 "::error::the bot author id of #6419 could not be read"
app_id=$LANES LANES=''
STUB_LINK="$(link Bot '[]' '' "$app_id")"
trust "an empty lanes App id fails a bot's unlinked pull request closed" 1 1 "::error::the bot author id of #6419 could not be read"
LANES=$app_id
STUB_LINK='' STUB_ISSUE_LABELS=''

NATIVE=docs/upstream/claude-code-native-surfaces.min.json
STUB_BASELINE_FILE=$NATIVE
STUB_LINK="$(link Bot '[]' 'No related issue: baseline.' "$LANES")"
STUB_PULL="$(jq -nc --arg login "$identity" --argjson id "$LANES" '{user: {login: $login, id: $id, type: "Bot"}, changed_files: 1}')"
STUB_FILES="[\"$NATIVE\",null]"
trust "the lanes App's merge.baseline-file linking nothing passes" 0 1 "changes only $NATIVE (merge.baseline-file)"
STUB_BASELINE_FILE=''
trust "with no merge.baseline-file the baseline still needs a link" 1 1 "its Refs: lines name no single issue"
STUB_BASELINE_FILE=docs/upstream/other.json
trust "another merge.baseline-file does not take the baseline" 1 1 "its Refs: lines name no single issue"
STUB_BASELINE_FILE=$NATIVE
STUB_PULL="$(jq -c '.changed_files = 2' <<<"$STUB_PULL")" STUB_FILES="[\"$NATIVE\",null]
[\"docs/a.md\",null]"
trust "the baseline beside another file still needs a link" 1 1 "its Refs: lines name no single issue"
STUB_FILES="[\"$NATIVE\",null]"
trust "a file list shorter than the count still needs a link" 1 1 "its Refs: lines name no single issue"
STUB_PULL="$(jq -c '.changed_files = 1' <<<"$STUB_PULL")" STUB_FILES="[\"$NATIVE\",\"docs/upstream/old.json\"]"
trust "the baseline renamed into place still needs a link" 1 1 "its Refs: lines name no single issue"
STUB_PULL="$(jq -c '.user.id = 1' <<<"$STUB_PULL")" STUB_FILES="[\"$NATIVE\",null]"
trust "another bot id's baseline still needs a link" 1 1 "its Refs: lines name no single issue"
STUB_PULL='' STUB_FILES=''
trust "an unread pull request still needs a link" 1 1 "its Refs: lines name no single issue"
STUB_LINK='' STUB_BASELINE_FILE=''

STUB_LINK="$(link Bot "[$(issue 16 '[null]')]")"
trust "a label that is not a string fails closed" 1 1 "could not be matched"
STUB_LINK="$(link Bot "[$(issue 16 '[]')]")" STUB_TIMELINE='{not json'
trust "a timeline that does not parse fails closed" 1 2 "could not be matched"
STUB_LINK='' STUB_TIMELINE=''

TABLE="$ROOT/plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/untrusted-labels.json"
while IFS=$'\t' read -r want label; do
  STUB_LINK="$(link Bot "[$(issue 16 "$(jq -nc --arg l "$label" '[$l]')")]")"
  if [[ "$want" == holds ]]; then
    trust "the shared table's '$label' holds" 1 1 "(untrusted-provenance)"
  else
    trust "the shared table's '$label' passes" 0 2 "carries no label naming untrusted work"
  fi
done < <(jq -r '(.holds[] | "holds\t\(.)"), (.passes[] | "passes\t\(.)")' "$TABLE")
STUB_LINK=''

test_harness::report
