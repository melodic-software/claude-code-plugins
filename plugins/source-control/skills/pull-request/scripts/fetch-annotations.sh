#!/usr/bin/env bash
# fetch-annotations.sh — Fetch GitHub Actions check-run annotations for a PR.
#
# Annotations carry path/line/level/title/message data the agent uses to
# locate fix sites without grepping log files. Output is JSONL (one
# annotation per line) for easy programmatic consumption + cheap to scan
# visually.
#
# The agent uses this when classifying CI failures (see
# reference/monitor.md §3.2 of the pull-request skill).
#
# Usage:
#   fetch-annotations.sh <pr-number>           # all check-runs on PR head SHA
#   fetch-annotations.sh <pr-number> --failed  # only failure-conclusion check-runs
#
# Env overrides:
#   FETCH_ANNOT_REPO    default `gh repo view --json nameWithOwner -q .nameWithOwner`
#
# Exit codes:
#   0  success (zero or more annotations emitted)
#   1  invalid argument
#   2  gh api call failed
#   5  prerequisite missing (gh, jq)

set -uo pipefail

# --- Argument parsing --------------------------------------------------------

PR_NUMBER=""
FAILED_ONLY=0

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --failed)
    FAILED_ONLY=1
    shift
    ;;
  --)
    shift
    break
    ;;
  -*)
    printf 'fetch-annotations: unknown flag %q (use --help)\n' "$1" >&2
    exit 1
    ;;
  *)
    if [[ -z "$PR_NUMBER" ]]; then
      PR_NUMBER="$1"
    else
      printf 'fetch-annotations: unexpected argument %q\n' "$1" >&2
      exit 1
    fi
    shift
    ;;
  esac
done

if [[ -z "$PR_NUMBER" ]]; then
  printf 'fetch-annotations: <pr-number> required\n' >&2
  exit 1
fi

# --- Prerequisites -----------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

have gh || {
  printf 'fetch-annotations: gh CLI required\n' >&2
  exit 5
}
have jq || {
  printf 'fetch-annotations: jq required\n' >&2
  exit 5
}

# --- Repo resolution ---------------------------------------------------------

if [[ -n "${FETCH_ANNOT_REPO:-}" ]]; then
  REPO="$FETCH_ANNOT_REPO"
else
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r\n')
fi

if [[ -z "$REPO" || "$REPO" != */* ]]; then
  printf 'fetch-annotations: cannot resolve owner/repo (set FETCH_ANNOT_REPO=owner/name)\n' >&2
  exit 2
fi

# --- Resolve PR head SHA -----------------------------------------------------

HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid -q .headRefOid 2>/dev/null | tr -d '\r\n')
if [[ -z "$HEAD_SHA" ]]; then
  printf 'fetch-annotations: gh pr view %s failed (no head SHA)\n' "$PR_NUMBER" >&2
  exit 2
fi

# --- Fetch check-runs for head SHA ------------------------------------------

# Returns list of check_run records: id, name, conclusion, status. Apply jq
# client-side (avoids gh's --jq flag for stubbing simplicity). `--paginate`
# walks all pages so PRs with >100 check-runs aren't silently truncated. The
# `gh api` exit code is captured via PIPESTATUS so transport/auth/rate-limit
# failures surface as exit 2 (per the docstring contract) instead of falling
# through the empty-output branch as a misleading success.
CHECK_RUNS_RAW=$(gh api --paginate "repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" 2>/dev/null)
api_rc=$?
if [[ $api_rc -ne 0 ]]; then
  printf 'fetch-annotations: gh api check-runs failed (exit %d)\n' "$api_rc" >&2
  exit 2
fi

CHECK_RUNS_JSON=$(printf '%s' "$CHECK_RUNS_RAW" |
  jq -c '.check_runs[] | {id: .id, name: .name, conclusion: .conclusion, status: .status}')

if [[ -z "$CHECK_RUNS_JSON" ]]; then
  # Empty is not an error — PR may have no check-runs yet.
  exit 0
fi

# Filter to failed-only when requested. jq -c keeps each record on one line.
if [[ "$FAILED_ONLY" -eq 1 ]]; then
  FILTERED=$(printf '%s\n' "$CHECK_RUNS_JSON" |
    jq -c 'select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "action_required" or .conclusion == "cancelled")')
else
  FILTERED=$(printf '%s\n' "$CHECK_RUNS_JSON" | jq -c '.')
fi

if [[ -z "$FILTERED" ]]; then
  exit 0
fi

# --- Walk each check-run, fetch annotations, emit JSONL ---------------------

# Output schema (one JSON object per line):
#   {"check_run_id":N,"check_run_name":"x","level":"failure|warning|notice",
#    "path":"x","start_line":N,"end_line":N,"title":"x","message":"x"}

while IFS= read -r cr; do
  cr_id=$(printf '%s' "$cr" | jq -r '.id')
  cr_name=$(printf '%s' "$cr" | jq -r '.name')
  [[ -z "$cr_id" || "$cr_id" == "null" ]] && continue

  # `--paginate` walks all annotation pages — large lint/test failures can
  # exceed the 100/page cap and silently drop diagnostics otherwise. Per-page
  # response is `[...]`; jq's `if type == "array" then .[] else . end`
  # already flattens the multi-array stream paginate emits. Capture the API
  # exit code separately so transport/auth/rate-limit failures (403/429/etc.)
  # surface as exit 2 per the docstring contract instead of silently emitting
  # partial JSONL. The trailing `|| true` on the jq pipe still tolerates
  # benign per-record decode quirks without aborting the whole walk.
  ANNOT_RAW=$(gh api --paginate "repos/$REPO/check-runs/$cr_id/annotations?per_page=100" 2>/dev/null)
  annot_rc=$?
  if [[ $annot_rc -ne 0 ]]; then
    printf 'fetch-annotations: gh api annotations for check-run %s failed (exit %d)\n' "$cr_id" "$annot_rc" >&2
    exit 2
  fi
  printf '%s' "$ANNOT_RAW" |
    jq -c --argjson cr_id "$cr_id" --arg cr_name "$cr_name" '
        if type == "array" then .[] else . end
        | {
            check_run_id: $cr_id,
            check_run_name: $cr_name,
            level: .annotation_level,
            path: .path,
            start_line: .start_line,
            end_line: .end_line,
            title: .title,
            message: .message
          }
      ' 2>/dev/null || true
done <<<"$FILTERED"

exit 0
