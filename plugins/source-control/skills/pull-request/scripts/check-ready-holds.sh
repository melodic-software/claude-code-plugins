#!/usr/bin/env bash
# portability-scope: the GitHub implementation of the ready flip's hold check; every read is a gh call.
set -uo pipefail

usage() {
  cat <<'EOF'
check-ready-holds.sh: refuse the ready flip for a held or superseded pull request.
The do-not-merge label holds the merge only, so it never refuses the flip.

Usage:
  check-ready-holds.sh <pr> [--repo <owner/repo>] [--unattended]

  --repo        the pull request's repository
  --unattended  also hold on a body line starting "Draft:"

Exit codes:
  0  no hold: the flip may go on
  1  invalid argument
  2  a gh call failed; the flip stops, since no hold was ruled out
  3  held or superseded: one reason per line on stdout
  5  prerequisite missing (gh, jq)
EOF
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

facts=$(gh pr view "$PR" ${repo_args[@]+"${repo_args[@]}"} --json title,body,closingIssuesReferences) ||
  die 2 "gh pr view $PR failed"

reasons=$(jq -r --argjson unattended "$UNATTENDED" '
  (if $unattended then (.body // "" | [scan("(?mi)^[ \\t>]*Draft:[ \\t]*[^\\r\\n]*")] | first // empty | "draft: a person asked for this draft (\(gsub("[[:cntrl:]]"; ""))); only a person flips it") else empty end),
  (.title // "" | if test("^\\s*(?:[a-z]+(?:\\([^)]*\\))?!?:\\s*)?wip\\b|[\\[(]wip[\\])]"; "i") then "title: a WIP marker in \"\(gsub("[[:cntrl:]]"; ""))\"" else empty end)
' <<<"$facts") || die 2 "cannot parse the pull request facts"

refs=$(jq -r '.closingIssuesReferences[]? | [(.url | capture("^https?://(?<h>[^/]+)/").h), "\(.repository.owner.login)/\(.repository.name)", (.number | tostring)] | @tsv' <<<"$facts") ||
  die 2 "cannot parse the closing issue references"
refs=${refs//$'\r'/}

while IFS=$'\t' read -r host path num; do
  [[ -n "$num" ]] || continue
  state=$(gh api --hostname "$host" "repos/$path/issues/$num" --jq .state | tr -d '\r') ||
    die 2 "cannot read the state of $path#$num"
  [[ "$state" == closed ]] && reasons+="${reasons:+$'\n'}superseded: it closes $path#$num, which is already closed"
done <<<"$refs"

[[ -z "$reasons" ]] && exit 0
printf '%s\n' "$reasons"
exit 3
