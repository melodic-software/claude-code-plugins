#!/usr/bin/env bash
# report-escalation.sh: the pr-unblock lane's report-escalation leaf. Hands the
# PR to a person: one machine-marked comment with the reason, the resume key
# and how to resume, plus the human-gated role label. Run from the base copy;
# it reads only the trusted base checkout and the GitHub API, never a PR head
# file, and never writes to the branch.
#
# Environment:
#   GH_TOKEN            token with pull-requests: write and issues: write
#                       (statuses: write in status mode)
#   GITHUB_REPOSITORY   owner/repo
#   PR_NUMBER           the pull request
#   HEAD_SHA            the gated head; it is the resume key
#   ESCALATION_REASON   protected-path-conflict | workflow-staged
#                       | unexpected-path-staged | repeat-cap
#                       | unresolved-conflict | feedback-protected-path
#                       | feedback-round-cap | feedback-uncertain
#                       | feedback-not-landed | feedback-invalid
#                       | feedback-partial | feedback-incomplete
#                       | feedback-disputed | dependency-round-cap
#                       | dependency-invalid | dependency-fix-not-landed
#                       | dependency-security-close | dependency-escalate
#                       | dependency-config-unreadable
#                       | dependency-files-truncated
#                       | dependency-control-uncited
#                       | dependency-workflow-unpinned
#                       | dependency-fix-refused | ci-fix-round-cap
#                       | ci-fix-empty | ci-fix-invalid
#                       | ci-fix-protected-path | ci-fix-not-applied
#                       | ci-fix-escalated | conflict-patch-invalid
#                       | conflict-patch-not-applied
#                       | conflict-patch-protected-path
#   TRACKER_CONFIG      base .work-item-tracker.json
#                       (default .base/.work-item-tracker.json)
#   LANES_BOT_LOGIN     the lanes App bot login, the only author whose marker
#                       counts (default melodic-automation-lanes[bot])
#
# The role label is config.role_labels["human-gated"]. A missing file or entry
# means needs-human; a present entry that is not a non-empty string fails.
# Idempotent: with the label on the PR and a LANES_BOT_LOGIN marker for this
# resume key and reason, it writes nothing; another reason on the same head
# gets its own comment, so gate-source.mjs reads every reason the label holds
# for. Without the label (a person removed it to resume), it
# escalates again. The label is written before the comment, so a retry after a
# failure between the two finds the label and posts at most one comment. The
# comment write is tried three times, so a transient failure does not leave the
# label without its explanation.
#
# With the argument `status`, it instead posts one failing `pr-unblock/conflict`
# commit status on HEAD_SHA when the reason is unresolved-conflict, and nothing
# for any other reason. GitHub starts no pull_request workflow on a conflicted
# PR, so this status is what shows the head why its CI is missing. That mode
# needs GH_TOKEN with statuses: write and reads TARGET_URL (optional, the run).
#
# Exit: 0 when escalated or already escalated; 1 on bad input or API failure.
set -euo pipefail

die() {
  printf 'report-escalation.sh: %s\n' "$*" >&2
  exit 1
}

case ${ESCALATION_REASON:-} in
  protected-path-conflict) why='a conflicted path is a workflow, submodule config or a settings file, which the lane does not resolve' ;;
  workflow-staged) why='the merge stages a change under .github/workflows/, which the lane does not push' ;;
  unexpected-path-staged) why='the conflict resolution changes a path outside the conflicted ones, which the lane does not push' ;;
  repeat-cap) why='the lane has resolved conflicts on this branch as many times in a row as its cap allows' ;;
  unresolved-conflict) why='the lane could not resolve every conflict' ;;
  feedback-protected-path) why='the pull request changes .github/workflows/, which the lane token cannot push, so the lane does not address its review threads' ;;
  feedback-round-cap) why='the lane has addressed review threads on this pull request as many rounds as its cap allows, and an open thread is a security or intent finding, which a person decides' ;;
  feedback-uncertain) why='a review finding is uncertain or deferred, so a person decides it' ;;
  feedback-not-landed) why='a fix the lane recorded did not reach the branch, so none of its review replies was posted' ;;
  feedback-invalid) why='the review replies the lane recorded did not pass validation, so none was posted' ;;
  feedback-partial) why='posting the review replies stopped partway, or a fixed thread could not be resolved, so a person finishes them' ;;
  feedback-incomplete) why='the lane did not record a disposition for every review thread it kept, so none was posted' ;;
  feedback-disputed) why='the lane replied with evidence that a review finding is incorrect; a person decides and resolves that thread' ;;
  dependency-round-cap) why='the lane has reviewed this dependency update as many rounds as its cap allows' ;;
  dependency-invalid) why='the dependency review verdict did not pass validation, so the lane acted on none of it' ;;
  dependency-fix-not-landed) why='the dependency review chose a fix, but no fix commit reached the branch (the lane lands a fix only when it changes nothing but the versions in npm or pip manifest and lock files outside .github/)' ;;
  dependency-security-close) why='the dependency review would close a security update, which the lane never closes' ;;
  dependency-escalate) why='the dependency review found a risk the lane does not decide alone' ;;
  dependency-config-unreadable) why='the lane could not read the base .github/dependabot.yml, so it does not mark this dependency update for merge' ;;
  dependency-files-truncated) why='the dependency review chose merge, but the files listing it read was cut short, so the lane does not mark this dependency update for merge' ;;
  dependency-fix-refused) why='a commit on the dependency update other than Dependabot'"'"'s changes more than a version of an npm or pip manifest or lock file, as a regular file outside .github/, so the lane does not act on the review' ;;
  dependency-control-uncited) why='the dependency review chose merge for a review-only dependency without quoting its control, so the lane does not mark it for merge' ;;
  dependency-workflow-unpinned) why='the dependency review chose merge, but the update changes a workflow or action file by more than swapping one full-SHA action pin for another, so the lane does not mark it for merge' ;;
  ci-fix-round-cap) why='the lane has pushed as many CI fixes to this pull request as its cap allows, and CI still fails' ;;
  ci-fix-empty) why='the lane changed nothing that fixes the failing checks' ;;
  ci-fix-invalid) why='the CI fix the lane wrote did not pass validation, so it was not pushed' ;;
  ci-fix-protected-path) why='the CI fix changes a path the lane does not push: .github/workflows/, CODEOWNERS, .gitmodules or a settings file' ;;
  ci-fix-not-applied) why='the CI fix did not apply to the head it was written for, so it was not pushed' ;;
  ci-fix-escalated) why='the lane could not fix every failing check; its run log names each one and why' ;;
  conflict-patch-invalid) why='the conflict resolution the lane wrote did not pass validation, so the merge was not pushed' ;;
  conflict-patch-not-applied) why='the conflict resolution did not apply to the merge it was written for, so the merge was not pushed' ;;
  conflict-patch-protected-path) why='the conflict resolution changes a path the lane does not push: .github/workflows/, CODEOWNERS, .gitmodules or a settings file' ;;
  *) die "unknown escalation reason [${ESCALATION_REASON:-}]" ;;
esac
case $ESCALATION_REASON in
  feedback-*) activity=address-feedback ;;
  dependency-*) activity=review-dependency ;;
  ci-fix-*) activity=fix-ci ;;
  *) activity=resolve-conflicts ;;
esac
[[ ${PR_NUMBER:-} =~ ^[1-9][0-9]*$ ]] || die "PR_NUMBER is not a pull request number"
[[ ${HEAD_SHA:-} =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || die "HEAD_SHA is not a commit id"
[[ ${GITHUB_REPOSITORY:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GITHUB_REPOSITORY is not owner/repo"

case ${1:-} in
  '') ;;
  status)
    if [[ $ESCALATION_REASON != unresolved-conflict ]]; then
      echo "no conflict status for $ESCALATION_REASON"
      exit 0
    fi
    args=(-f state=failure -f context=pr-unblock/conflict
      -f "description=Conflicts with the base branch; CI does not run until they are resolved")
    [[ -n ${TARGET_URL:-} ]] && args+=(-f "target_url=$TARGET_URL")
    gh api -X POST "repos/$GITHUB_REPOSITORY/statuses/$HEAD_SHA" "${args[@]}" >/dev/null
    echo "posted pr-unblock/conflict failure on $HEAD_SHA"
    exit 0
    ;;
  *) die "unknown mode [$1]" ;;
esac

tracker=${TRACKER_CONFIG:-.base/.work-item-tracker.json}
label=needs-human
if [[ -f $tracker ]]; then
  label=$(jq -er '.config.role_labels // {}
    | if has("human-gated") then .["human-gated"] | strings | select(length > 0) else "needs-human" end' "$tracker") ||
    die "cannot read the human-gated role label from $tracker"
fi

bot=${LANES_BOT_LOGIN:-melodic-automation-lanes[bot]}
issue="repos/$GITHUB_REPOSITORY/issues/$PR_NUMBER"
marker='<!-- work-items:escalation lane=pr-unblock kind=escalated -->'
key_line="<!-- pr-unblock resume-key=$HEAD_SHA -->"

labeled=$(gh api "$issue" | jq --arg l "$label" '[.labels[].name] | index($l) != null')
if [[ $labeled == true ]]; then
  marked=$(gh api --paginate "$issue/comments" | jq -s --arg bot "$bot" --arg m "$marker" --arg k "$key_line" \
    --arg r "- Reason: \`$ESCALATION_REASON\`" \
    '[add[] | select(.user.login == $bot) | (.body // "") | split("\n") | map(rtrimstr("\r"))
      | select(.[0] == $m and (.[1] // "") == $k and any(.[]; . == $r))] | length > 0')
  if [[ $marked == true ]]; then
    echo "already escalated $ESCALATION_REASON for resume key $HEAD_SHA"
    exit 0
  fi
fi

body=$(mktemp)
trap 'rm -f "$body"' EXIT
cat >"$body" <<EOF
$marker
$key_line
The pr-unblock lane stopped on this pull request and needs a person: $why.

- Reason: \`$ESCALATION_REASON\`
- Resume key: \`$HEAD_SHA\` (the head the lane stopped on)

To resume, deal with the reason above, remove the \`$label\` label (and \`do-not-merge\`, if set), then dispatch the \`pr-unblock\` workflow with \`pr-number=$PR_NUMBER\` and \`activity=$activity\`:

\`\`\`sh
gh workflow run pr-unblock.yml -R $GITHUB_REPOSITORY -f pr-number=$PR_NUMBER -f activity=$activity
\`\`\`
EOF

if [[ $labeled != true ]]; then
  gh api -X POST "$issue/labels" -f "labels[]=$label" >/dev/null
fi
for attempt in 1 2 3; do
  gh api -X POST "$issue/comments" -F "body=@$body" >/dev/null && break
  ((attempt < 3)) || die "cannot post the escalation comment after $attempt attempts; the $label label is on"
  sleep $((attempt * 5))
done
echo "escalated: $ESCALATION_REASON, label $label, resume key $HEAD_SHA"
