#!/usr/bin/env bash
# portability-scope: the GitHub implementation of the review-venue read; every read is a gh call.
set -uo pipefail

usage() {
  cat <<'EOF'
review-venue.sh: say per AI review lane whether CI reviews this repository's pull requests and is healthy.

Usage:
  review-venue.sh [--repo <owner/repo>] [--max-age-days <n>] [--head <sha>]

  --repo          the repository (default: the current directory's)
  --max-age-days  how recent a lane's last verdict must be
  --head          also print a `tests` line for whether CI's test lanes covered this commit

Output, one line per lane, code-review first, then tests with --head:
  <lane> ci healthy: <detail>
  <lane> local absent|failing|stale|unreadable: <detail>
  tests ci healthy: <detail>
  tests local absent|failing|pending: <detail>

Exit codes:
  0  read; every lane has a line
  1  invalid argument
  2  a gh call failed or returned something unparsable: treat every lane as local
  5  prerequisite missing (gh, jq)
EOF
  exit 0
}

die() {
  printf 'review-venue: %s\n' "$2" >&2
  exit "$1"
}

REPO="{owner}/{repo}" MAX_AGE_DAYS=7 HEAD_SHA=""
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
  --head)
    (($# >= 2)) || die 1 "--head needs a value"
    [[ "$2" =~ ^[0-9a-f]{40}$ ]] || die 1 "--head must be a full 40-character commit sha"
    HEAD_SHA="$2"
    shift 2
    ;;
  *) die 1 "unknown argument $(printf '%q' "$1") (use --help)" ;;
  esac
done

command -v gh >/dev/null 2>&1 || die 5 "gh not found on PATH"
command -v jq >/dev/null 2>&1 || die 5 "jq not found on PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_PY="$SCRIPT_DIR/../../babysit-prs/scripts/babysit_merge_settings.py"
settings=$(
  # shellcheck source=../../babysit-prs/scripts/babysit-python.sh
  . "$SCRIPT_DIR/../../babysit-prs/scripts/babysit-python.sh"
  babysit_python "$SETTINGS_PY" show
) || die 2 "cannot read the review_lane_workflows setting"
wfs() { jq -c --arg l "$1" '[.review_lane_workflows[]? | select(.lane == $l) | .workflow]' <<<"$settings"; }
LANES=(code-review security-review)
code_wfs=$(wfs code-review) || die 2 "cannot parse the review_lane_workflows setting"
security_wfs=$(wfs security-review) || die 2 "cannot parse the review_lane_workflows setting"
CLI=$(wfs either) || die 2 "cannot parse the review_lane_workflows setting"
REUSABLE=("$code_wfs" "$security_wfs")
CLI_SECURITY=(false true)
WORKFLOW_ID=("" "") WORKFLOW_PATH=("" "")
PAGES=3
MAX_PASSED=10
READ_ATTEMPTS=3

read_runs() {
  local out whole attempt
  for ((attempt = 1; attempt <= READ_ATTEMPTS; attempt++)); do
    ((attempt == 1)) || sleep "$attempt"
    out=$(gh api "$1") || return 2
    whole=$(jq --argjson off "$2" 'if type != "object" then error("not an object") else
      (.workflow_runs | type) == "array" and (.total_count | type) == "number"
      and (.workflow_runs | length) == ([.total_count - $off, 100] | min | [., 0] | max) end' <<<"$out") || return 2
    [[ -n "$whole" ]] || return 2
    if [[ "$whole" == true ]]; then
      printf '%s\n' "$out"
      return 0
    fi
  done
  return 1
}

skipped_validation() {
  local jobs ids id ann hit
  jobs=$(gh api "repos/$REPO/actions/runs/$1/jobs?per_page=100") || die 2 "cannot read the jobs of run $1"
  ids=$(jq -r '.jobs[]? | select(.conclusion | IN("failure", "timed_out")) | .id' <<<"$jobs") ||
    die 2 "cannot parse the jobs of run $1"
  [[ -n "$ids" ]] || return 1
  for id in $ids; do
    [[ "$id" =~ ^[0-9]+$ ]] || die 2 "unexpected job id in run $1"
    ann=$(gh api "repos/$REPO/check-runs/$id/annotations?per_page=100") || die 2 "cannot read the annotations of job $id"
    hit=$(jq 'any(.[]?; .annotation_level == "failure" and (.message | test("^([a-z-]+: )?failure-class=skipped-validation(:|$)")))' <<<"$ann") ||
      die 2 "cannot parse the annotations of job $id"
    [[ "$hit" == true ]] || return 1
  done
}

UNREAD=""
[[ "$code_wfs$security_wfs$CLI" == "[][][]" ]] && PAGES=0
for ((page = 1; page <= PAGES; page++)); do
  runs=$(read_runs "repos/$REPO/actions/runs?event=pull_request&per_page=100&page=$page" $(((page - 1) * 100)))
  case $? in
  0) ;;
  1)
    UNREAD="page $page of the pull_request run listing came back incomplete in $READ_ATTEMPTS reads"
    break
    ;;
  *) die 2 "cannot list the workflow runs of $REPO" ;;
  esac
  for i in "${!LANES[@]}"; do
    [[ -n "${WORKFLOW_ID[i]}" ]] && continue
    hit=$(jq -r --argjson wfs "${REUSABLE[i]}" --argjson cli "$CLI" --argjson sec "${CLI_SECURITY[i]}" '
      def calls($names): any(.referenced_workflows[]?; .path as $p
        | any($names[]; . as $w | $p | type == "string" and startswith($w + "@")));
      [.workflow_runs[]? | select(calls($wfs)
        or ((.path // "" | test("security")) == $sec and calls($cli)))][0]
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
  if [[ "${REUSABLE[i]}" == "[]" && "$CLI" == "[]" ]]; then
    printf '%s local absent: the review_lane_workflows setting names no workflow for the %s lane\n' "$lane" "$lane"
    continue
  elif [[ -z "$id" && -n "$UNREAD" ]]; then
    printf '%s local unreadable: %s\n' "$lane" "$UNREAD"
    continue
  elif [[ -z "$id" ]]; then
    printf '%s local absent: no recent pull_request run calls the %s lane\n' "$lane" "$lane"
    continue
  fi
  [[ "$id" =~ ^[0-9]+$ ]] || die 2 "unexpected workflow id for $lane"
  wf=$(gh api "repos/$REPO/actions/workflows/$id") || die 2 "cannot read the workflow $path"
  state=$(jq -er '.state | strings' <<<"$wf") || die 2 "cannot parse the workflow $path"
  if [[ "$state" != active ]]; then
    printf '%s local absent: %s is %s\n' "$lane" "$path" "$state"
    continue
  fi
  lane_runs=$(read_runs "repos/$REPO/actions/workflows/$id/runs?event=pull_request&per_page=100" 0)
  case $? in
  0) ;;
  1)
    printf '%s local unreadable: the pull_request runs of %s came back incomplete in %s reads\n' "$lane" "$path" "$READ_ATTEMPTS"
    continue
    ;;
  *) die 2 "cannot list the runs of $path" ;;
  esac
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

[[ -n "$HEAD_SHA" ]] || exit 0
CHECK_PAGES=5
tests="[]" complete=false
for ((page = 1; page <= CHECK_PAGES; page++)); do
  checks=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs?filter=all&per_page=100&page=$page") ||
    die 2 "cannot list the check runs of $HEAD_SHA"
  tests=$(jq -c --argjson acc "$tests" '$acc + [.check_runs[]
    | select(.app.slug == "github-actions" and (.name | test("^[Tt]est($|[- (])")))
    | {id, name, status, conclusion}]' <<<"$checks") || die 2 "cannot parse the check runs of $HEAD_SHA"
  if [[ "$(jq '.check_runs | length' <<<"$checks")" -lt 100 ]]; then
    complete=true
    break
  fi
done
if [[ "$complete" != true ]]; then
  printf 'tests local absent: %s has more than %s check runs, not all read\n' "$HEAD_SHA" "$((CHECK_PAGES * 100))"
  exit 0
fi
verdict=$(jq -r --arg h "$HEAD_SHA" '
  def names: map(.name | sub(" \\(.*\\)$"; "")) | unique | join(", ");
  def finished: .conclusion | IN("success", "skipped", "neutral");
  group_by(.name) | map((map(select(.conclusion != "skipped")) | max_by(.id)) // max_by(.id))
  | if length == 0 then "local absent: no test-lane check run on \($h)"
  elif any(.status != "completed") then map(select(.status != "completed")) as $open
    | "local pending: \($open | length) of \(length) test-lane check runs on \($h) have not finished (\($open | names))"
  elif any(finished | not) then map(select(finished | not)) as $bad
    | "local failing: \($bad | names) concluded \($bad | map(.conclusion) | unique | join(", ")) on \($h)"
  elif any(.conclusion == "success") | not then "local absent: every test-lane check run on \($h) skipped"
  else map(select(.conclusion == "success")) as $ok
    | "ci healthy: \($ok | length) test-lane check runs succeeded on \($h) (\($ok | names))"
  end' <<<"$tests") || die 2 "cannot read the test lanes of $HEAD_SHA"
printf 'tests %s\n' "$verdict"
