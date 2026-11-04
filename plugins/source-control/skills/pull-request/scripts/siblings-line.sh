#!/usr/bin/env bash
# siblings-line.sh — Print the Siblings: line for a pull request that closes issues.
#
# When several pull requests deliver one issue, the earlier ones carry a
# `Refs: #<issue>` line and close nothing, and the last one closes the issue
# and names them on a first-column `Siblings: #<a>, #<b>` line. This lists the
# merged pull requests in the repository whose body has a `Refs: #<issue>`
# line of its own, for any issue given, and that close no issue, and prints
# one line naming them in ascending order. pr-verify credits none when a body
# names more than 10, so the line keeps the 10 newest. With none, it prints
# nothing. pr-verify's resolve-pr applies the credit checks (author, base
# branch, edits), so this does not.
#
# Usage:
#   siblings-line.sh <issue>... [--repo <owner/repo>]
#
# Exit codes:
#   0  the line, or nothing when no pull request matches
#   1  invalid argument
#   2  a gh read failed; no line was printed
#   5  prerequisite missing (gh, jq)

# portability-scope: the GitHub implementation of create's Siblings: line; the read is a gh call.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'siblings-line: %s\n' "$2" >&2
  exit "$1"
}

ISSUES=() REPO=""
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo)
    (($# >= 2)) || die 1 "--repo needs a value"
    REPO="$2"
    shift 2
    ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ "$1" =~ ^[1-9][0-9]{0,8}$ ]] || die 1 "not an issue number: $(printf '%q' "$1")"
    ISSUES+=("$1")
    shift
    ;;
  esac
done
((${#ISSUES[@]} > 0)) || die 1 "an issue number is required (use --help)"

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

repo_args=()
[[ -n "$REPO" ]] && repo_args=(--repo "$REPO")

found='[]'
for issue in "${ISSUES[@]}"; do
  # The search narrows the list; the jq filter below decides, since search
  # matches words, not the line.
  prs=$(gh pr list ${repo_args[@]+"${repo_args[@]}"} --state merged --limit 100 \
    --search "\"Refs: #$issue\" in:body" --json number,body,closingIssuesReferences) ||
    die 2 "gh pr list failed for #$issue"
  found=$(jq -c --arg n "$issue" --argjson found "$found" '
    $found + [.[]
      | select((.closingIssuesReferences // []) | length == 0)
      | select(.body // "" | test("(?m)^Refs:[ \\t]*#" + $n + "[ \\t]*\\r?$"))
      | .number]
  ' <<<"$prs") || die 2 "cannot parse the pull request list for #$issue"
done

numbers=$(jq -r 'unique | .[-10:] | map("#\(.)") | join(", ")' <<<"$found") ||
  die 2 "cannot build the line"

[[ -n "$numbers" ]] && printf 'Siblings: %s\n' "$numbers"
exit 0
