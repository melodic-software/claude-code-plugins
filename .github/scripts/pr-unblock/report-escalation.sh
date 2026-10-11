#!/usr/bin/env bash
# report-escalation.sh: the pr-unblock lane's report-escalation leaf. Hands the
# PR to a person: one machine-marked comment with the reason, the resume key
# and how to resume, plus the human-gated role label. Run from the base copy;
# it reads only the trusted base checkout and the GitHub API, never a PR head
# file, and never writes to the branch.
#
# Environment:
#   GH_TOKEN            token with pull-requests: write and issues: write
#   GITHUB_REPOSITORY   owner/repo
#   PR_NUMBER           the pull request
#   HEAD_SHA            the gated head; it is the resume key
#   ESCALATION_REASON   protected-path-conflict | workflow-staged | repeat-cap
#                       | unresolved-conflict
#   TRACKER_CONFIG      base .work-item-tracker.json
#                       (default .base/.work-item-tracker.json)
#   LANES_BOT_LOGIN     the lanes App bot login, the only author whose marker
#                       counts (default melodic-automation-lanes[bot])
#
# The role label is config.role_labels["human-gated"]. A missing file or entry
# means needs-human; a present entry that is not a non-empty string fails.
# Idempotent: with the label on the PR and a LANES_BOT_LOGIN marker for this
# resume key, it writes nothing. Without the label (a person removed it to resume), it
# escalates again. The label is written before the comment, so a retry after a
# failure between the two finds the label and posts at most one comment.
# When the PR head is no longer HEAD_SHA, the escalation is superseded: it
# writes nothing and the run on the new head decides.
#
# Exit: 0 when escalated, already escalated or superseded; 1 on bad input or
# API failure.
set -euo pipefail

die() {
  printf 'report-escalation.sh: %s\n' "$*" >&2
  exit 1
}

case ${ESCALATION_REASON:-} in
  protected-path-conflict) why='a conflicted path is protected, so the lane does not resolve it' ;;
  workflow-staged) why='the merge stages a change under .github/workflows/, which the lane does not push' ;;
  repeat-cap) why='the lane has resolved conflicts on this branch as many times in a row as its cap allows' ;;
  unresolved-conflict) why='the lane could not resolve every conflict' ;;
  *) die "unknown escalation reason [${ESCALATION_REASON:-}]" ;;
esac
[[ ${PR_NUMBER:-} =~ ^[1-9][0-9]*$ ]] || die "PR_NUMBER is not a pull request number"
[[ ${HEAD_SHA:-} =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || die "HEAD_SHA is not a commit id"
[[ ${GITHUB_REPOSITORY:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "GITHUB_REPOSITORY is not owner/repo"

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
    '[add[] | select(.user.login == $bot) | (.body // "") | split("\n")
      | select((.[0] | rtrimstr("\r")) == $m and (.[1] // "" | rtrimstr("\r")) == $k)] | length > 0')
  if [[ $marked == true ]]; then
    echo "already escalated for resume key $HEAD_SHA"
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

To resume, deal with the reason above, remove the \`$label\` label (and \`do-not-merge\`, if set), then dispatch the \`pr-unblock\` workflow with \`pr-number=$PR_NUMBER\`:

\`\`\`sh
gh workflow run pr-unblock.yml -R $GITHUB_REPOSITORY -f pr-number=$PR_NUMBER
\`\`\`
EOF

live=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER" | jq -r '.head.sha')
if [[ $live != "$HEAD_SHA" ]]; then
  echo "superseded: the PR head moved from $HEAD_SHA to $live; not escalating"
  exit 0
fi

if [[ $labeled != true ]]; then
  gh api -X POST "$issue/labels" -f "labels[]=$label" >/dev/null
fi
gh api -X POST "$issue/comments" -F "body=@$body" >/dev/null
echo "escalated: $ESCALATION_REASON, label $label, resume key $HEAD_SHA"
