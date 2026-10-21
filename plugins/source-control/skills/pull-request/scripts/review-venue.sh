#!/usr/bin/env bash
# review-venue.sh — Say, per AI review lane, whether CI reviews this repository's
# pull requests and is healthy, so a local review runs only where CI does not.
#
# A lane is a workflow whose pull_request runs call the org's reusable review
# workflow: ci-workflows pr-review.yml (code-review) or pr-review-security.yml
# (security-review). It is healthy when its workflow is active and its newest
# pull_request run that reached a verdict (completed, and neither skipped nor
# cancelled) succeeded and was created within --max-age-days. A failed run whose
# every failed job says failure-class=skipped-validation reached no verdict: the
# pull request edits the caller workflow, so the review skipped itself by
# design. A disabled workflow, any other failed run (a usage-limit stop
# included), a timed-out one, or none in the window is not healthy.
#
# Usage:
#   review-venue.sh [--repo <owner/repo>] [--max-age-days <n>]
#
# Output, one line per lane, code-review first:
#   <lane> ci healthy: <detail>
#   <lane> local absent|failing|stale: <detail>
#
# Exit codes:
#   0  read; every lane has a line
#   1  invalid argument
#   2  a gh call failed or returned something unparsable: treat every lane as local
#   5  prerequisite missing (gh, jq)

# portability-scope: the GitHub implementation of the review-venue read; every read is a gh call.
set -uo pipefail

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'review-venue: %s\n' "$2" >&2
  exit "$1"
}

REPO="{owner}/{repo}" MAX_AGE_DAYS=7
while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo)
    (($# >= 2)) || die 1 "--repo needs a value"
    [[ "$2" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die 1 "--repo must be <owner>/<repo>"
    REPO="$2"
    shift 2
    ;;
  --max-age-days)
    (($# >= 2)) || die 1 "--max-age-days needs a value"
    [[ "$2" =~ ^[1-9][0-9]{0,2}$ ]] || die 1 "--max-age-days must be a whole number from 1 to 999"
    MAX_AGE_DAYS="$2"
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

# Each lane and the reusable workflow its caller references, in output order.
# Fixed here: a pull request cannot widen them.
LANES=(code-review security-review)
REUSABLE=(
  '^melodic-software/ci-workflows/\.github/workflows/pr-review\.yml@'
  '^melodic-software/ci-workflows/\.github/workflows/pr-review-security\.yml@'
)
WORKFLOW_ID=("" "") WORKFLOW_PATH=("" "")
PAGES=3
# Skipped-validation reds passed over per lane before it reads stale.
MAX_PASSED=10

# skipped_validation <run-id>: true when the run failed only because the pull
# request edits the caller workflow. A run with no failed job keeps its verdict.
skipped_validation() {
  local jobs ids id ann hit
  jobs=$(gh api "repos/$REPO/actions/runs/$1/jobs?per_page=100") || die 2 "cannot read the jobs of run $1"
  ids=$(jq -r '.jobs[]? | select(.conclusion | IN("failure", "timed_out")) | .id' <<<"$jobs") ||
    die 2 "cannot parse the jobs of run $1"
  [[ -n "$ids" ]] || return 1
  for id in $ids; do
    [[ "$id" =~ ^[0-9]+$ ]] || die 2 "unexpected job id in run $1"
    ann=$(gh api "repos/$REPO/check-runs/$id/annotations?per_page=100") || die 2 "cannot read the annotations of job $id"
    hit=$(jq 'any(.[]?; .annotation_level == "failure" and (.message | test("^failure-class=skipped-validation(:|$)")))' <<<"$ann") ||
      die 2 "cannot parse the annotations of job $id"
    [[ "$hit" == true ]] || return 1
  done
}

# Find each lane's caller workflow among the newest pull_request runs. Every PR
# event starts each lane, a draft's run included (it concludes skipped), so a
# repository with lanes shows them in the first pages.
for ((page = 1; page <= PAGES; page++)); do
  runs=$(gh api "repos/$REPO/actions/runs?event=pull_request&per_page=100&page=$page") ||
    die 2 "cannot list the workflow runs of $REPO"
  for i in "${!LANES[@]}"; do
    [[ -n "${WORKFLOW_ID[i]}" ]] && continue
    hit=$(jq -r --arg re "${REUSABLE[i]}" '
      [.workflow_runs[]? | select(any(.referenced_workflows[]?; .path | test($re)))][0]
      | select(. != null) | "\(.workflow_id)\t\(.path)"' <<<"$runs") ||
      die 2 "cannot parse the workflow runs of $REPO"
    if [[ -n "$hit" ]]; then
      WORKFLOW_ID[i]="${hit%%$'\t'*}"
      WORKFLOW_PATH[i]="${hit#*$'\t'}"
    fi
  done
  [[ -n "${WORKFLOW_ID[0]}" && -n "${WORKFLOW_ID[1]}" ]] && break
  [[ "$(jq '.workflow_runs | length' <<<"$runs")" -lt 100 ]] && break
done

for i in "${!LANES[@]}"; do
  lane="${LANES[i]}" id="${WORKFLOW_ID[i]}" path="${WORKFLOW_PATH[i]}"
  if [[ -z "$id" ]]; then
    printf '%s local absent: no recent pull_request run calls the %s lane\n' "$lane" "$lane"
    continue
  fi
  [[ "$id" =~ ^[0-9]+$ ]] || die 2 "unexpected workflow id for $lane"
  # A disabled workflow keeps its run history but answers no trigger.
  wf=$(gh api "repos/$REPO/actions/workflows/$id") || die 2 "cannot read the workflow $path"
  state=$(jq -er '.state | strings' <<<"$wf") || die 2 "cannot parse the workflow $path"
  if [[ "$state" != active ]]; then
    printf '%s local absent: %s is %s\n' "$lane" "$path" "$state"
    continue
  fi
  lane_runs=$(gh api "repos/$REPO/actions/workflows/$id/runs?event=pull_request&per_page=100") ||
    die 2 "cannot list the runs of $path"
  verdicts=$(jq -r '.workflow_runs[]? | select(.status == "completed" and (.conclusion | IN("skipped", "cancelled") | not))
    | "\(.id)\t\(.conclusion)\t\(.created_at)"' <<<"$lane_runs") || die 2 "cannot parse the runs of $path"
  rid="" passed=0
  while IFS=$'\t' read -r rid conclusion created; do
    [[ -n "$rid" ]] || continue
    [[ "$rid" =~ ^[0-9]+$ ]] || die 2 "unexpected run id in $path"
    if [[ "$conclusion" == success ]] || ! skipped_validation "$rid"; then break; fi
    rid="" passed=$((passed + 1))
    ((passed < MAX_PASSED)) || break
  done <<<"$verdicts"
  [[ -z "$rid" ]] || made=$(jq -nr --arg t "$created" '$t | fromdateiso8601') || die 2 "cannot parse the time of run $rid"
  if [[ -z "$rid" ]]; then
    printf '%s local stale: %s has no run with a verdict among its newest 100\n' "$lane" "$path"
  elif ((made < $(date +%s) - MAX_AGE_DAYS * 86400)); then
    printf '%s local stale: the newest run with a verdict, %s, is from %s, older than %s days (%s)\n' "$lane" "$rid" "$created" "$MAX_AGE_DAYS" "$path"
  elif [[ "$conclusion" == success ]]; then
    printf '%s ci healthy: newest run with a verdict, %s, succeeded at %s (%s)\n' "$lane" "$rid" "$created" "$path"
  else
    printf '%s local failing: newest run with a verdict, %s, concluded %s at %s (%s)\n' "$lane" "$rid" "$conclusion" "$created" "$path"
  fi
done
