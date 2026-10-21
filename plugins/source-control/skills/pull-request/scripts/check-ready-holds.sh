#!/usr/bin/env bash
# check-ready-holds.sh — Refuse the ready flip for a held or superseded pull request.
#
# The `ready` action runs this before it touches the branch. A pull request is
# held when it carries the do-not-merge label (any case), its body says "do not
# merge" or "don't merge", or its title carries WIP as a word. A body line
# starting "Hold:" holds the merge only, so it does not hold the flip. It is
# superseded when an issue it closes is already closed. With --unattended (no
# person drives the run: a lane, a loop, a dispatched worker), a body line
# starting "Draft:" (any case, after optional spaces or a quote marker), such as
# create's "Draft: requested early look" or "Draft: multi-session container",
# also holds the flip: a person chose that draft, so only a person flips it.
#
# Usage:
#   check-ready-holds.sh <pr> [--repo <owner/repo>] [--unattended]
#
# Exit codes:
#   0  no hold: the flip may go on
#   1  invalid argument
#   2  a gh call failed; the flip stops, since no hold was ruled out
#   3  held or superseded: one reason per line on stdout
#   5  prerequisite missing (gh, jq)

# portability-scope: the GitHub implementation of the ready flip's hold check; every read is a gh call.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'check-ready-holds: %s\n' "$2" >&2
  exit "$1"
}

PR="" REPO="" UNATTENDED=false
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --unattended)
    UNATTENDED=true
    shift
    ;;
  --repo)
    (($# >= 2)) || die 1 "--repo needs a value"
    REPO="$2"
    shift 2
    ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ -z "$PR" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    PR="$1"
    shift
    ;;
  esac
done
[[ "$PR" =~ ^[0-9]+$ ]] || die 1 "a pull request number is required (use --help)"

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

repo_args=()
[[ -n "$REPO" ]] && repo_args=(--repo "$REPO")

facts=$(gh pr view "$PR" ${repo_args[@]+"${repo_args[@]}"} --json title,body,labels,closingIssuesReferences) ||
  die 2 "gh pr view $PR failed"

# The body pattern is the do-not-merge alternative of babysit-prs'
# BODY_MERGE_HOLD_RE (babysit_merge.py); its `Hold:` line alternative holds the
# merge only, so it is left out here, and a "do not merge" on a Hold: line (any
# case, after optional spaces or a quote marker) is not read as a flip hold. The
# hyphenated label name is not matched, so a body that only names the label
# holds nothing.
reasons=$(jq -r --argjson unattended "$UNATTENDED" '
  (if $unattended then (.body // "" | [scan("(?mi)^[ \\t>]*Draft:[ \\t]*[^\\r\\n]*")] | first // empty | "draft: a person asked for this draft (\(gsub("[[:cntrl:]]"; ""))); only a person flips it") else empty end),
  ([.labels[]?.name | select(ascii_downcase == "do-not-merge")] | if length > 0 then "label: the pull request carries do-not-merge" else empty end),
  (.body // "" | gsub("(?mi)^[ \\t>]*Hold:[^\\r\\n]*"; "") | if test("\\bdo(?:n['"'"'\u2019]?t| not)\\s+merge\\b"; "i") then "body: it says do not merge" else empty end),
  (.title // "" | if test("\\bwip\\b"; "i") then "title: a WIP marker in \"\(gsub("[[:cntrl:]]"; ""))\"" else empty end)
' <<<"$facts") || die 2 "cannot parse the pull request facts"

refs=$(jq -r '.closingIssuesReferences[]? | [(.url | capture("^https?://(?<h>[^/]+)/").h), "\(.repository.owner.login)/\(.repository.name)", (.number | tostring)] | @tsv' <<<"$facts") ||
  die 2 "cannot parse the closing issue references"

while IFS=$'\t' read -r host path num; do
  [[ -n "$num" ]] || continue
  # REST, not GraphQL: some sandboxed sessions are refused GraphQL.
  state=$(gh api --hostname "$host" "repos/$path/issues/$num" --jq .state | tr -d '\r') ||
    die 2 "cannot read the state of $path#$num"
  [[ "$state" == closed ]] && reasons+="${reasons:+$'\n'}superseded: it closes $path#$num, which is already closed"
done <<<"$refs"

[[ -z "$reasons" ]] && exit 0
printf '%s\n' "$reasons"
exit 3
