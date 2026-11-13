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
#   fetch-annotations.sh <pr-number> --dir <checkout>
#
# --dir names any checkout of the PR's repository, resolved with target-repo.sh
# (which honors GH_REPO). Default: `gh repo view` in the current directory.
#
# Env overrides:
#   FETCH_ANNOT_REPO    owner/name; wins over --dir and the default
#
# Exit codes:
#   0  success (zero or more annotations emitted)
#   1  invalid argument, or --dir names no directory
#   2  gh api call failed
#   5  prerequisite missing (gh, jq)

# portability-scope: reads GitHub check-run annotations through the GitHub REST API with gh; the script is the GitHub provider's annotation read.
set -uo pipefail

# --- Argument parsing --------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PR_NUMBER=""
FAILED_ONLY=0
CHECKOUT=""

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

die() {
  printf 'fetch-annotations: %s\n' "$2" >&2
  exit "$1"
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --failed) FAILED_ONLY=1 ;;
  --dir)
    (($# >= 2)) && [[ -n "$2" && -z "$CHECKOUT" ]] || die 1 "--dir needs one value and is given once"
    CHECKOUT="$2"
    shift
    ;;
  --) break ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ -z "$PR_NUMBER" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    PR_NUMBER="$1"
    ;;
  esac
  shift
done

[[ -n "$PR_NUMBER" ]] || die 1 "<pr-number> required"
[[ -z "$CHECKOUT" || -d "$CHECKOUT" ]] || die 1 "--dir $(printf '%q' "$CHECKOUT") is not a directory"

# --- Prerequisites -----------------------------------------------------------

command -v gh >/dev/null 2>&1 || die 5 "gh CLI required"
command -v jq >/dev/null 2>&1 || die 5 "jq required"

# --- Repo resolution ---------------------------------------------------------

REPO="${FETCH_ANNOT_REPO:-}"
if [[ -z "$REPO" && -n "$CHECKOUT" ]]; then
  REPO=$(bash "$SCRIPT_DIR/target-repo.sh" --dir "$CHECKOUT" | tr -d '\r\n')
elif [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r\n')
fi
[[ "$REPO" == */* ]] || die 2 "cannot resolve owner/repo (set FETCH_ANNOT_REPO=owner/name)"

# --- Resolve PR head SHA -----------------------------------------------------

# With --dir the shell's directory names no repository, so the read names it.
REPO_ARGS=()
[[ -z "$CHECKOUT" ]] || REPO_ARGS=(-R "$REPO")
HEAD_SHA=$(gh pr view "$PR_NUMBER" ${REPO_ARGS[@]+"${REPO_ARGS[@]}"} --json headRefOid -q .headRefOid 2>/dev/null | tr -d '\r\n')
[[ -n "$HEAD_SHA" ]] || die 2 "gh pr view $PR_NUMBER failed (no head SHA)"

# --- Fetch check-runs for head SHA ------------------------------------------

# Returns list of check_run records: id, name, conclusion, status. Apply jq
# client-side (avoids gh's --jq flag for stubbing simplicity). `--paginate`
# walks all pages so PRs with >100 check-runs aren't silently truncated. A
# failed `gh api` (transport, auth, rate limit) exits 2 instead of falling
# through the empty-output branch as a misleading success.
CHECK_RUNS_RAW=$(gh api --paginate "repos/$REPO/commits/$HEAD_SHA/check-runs?per_page=100" 2>/dev/null) ||
  die 2 "gh api check-runs failed (exit $?)"

# One jq pass both projects the records and applies --failed. jq -c keeps each
# record on one line, the form the walk below reads.
FILTERED=$(printf '%s' "$CHECK_RUNS_RAW" |
  jq -c --argjson failed_only "$FAILED_ONLY" '
      .check_runs[]
      | {id, name, conclusion, status}
      | select($failed_only == 0
               or (.conclusion | IN("failure", "timed_out", "action_required", "cancelled")))
    ')

if [[ -z "$FILTERED" ]]; then
  # Empty is not an error — the PR may have no check-runs yet, and --failed can
  # legitimately match none.
  exit 0
fi

# --- Walk each check-run, fetch annotations, emit JSONL ---------------------

# Output schema (one JSON object per line):
#   {"check_run_id":N,"check_run_name":"x","level":"failure|warning|notice",
#    "path":"x","start_line":N,"end_line":N,"title":"x","message":"x"}

while IFS= read -r cr; do
  cr_id=$(jq -r '.id' <<<"$cr")
  cr_name=$(jq -r '.name' <<<"$cr")
  [[ -z "$cr_id" || "$cr_id" == "null" ]] && continue

  # `--paginate` walks all annotation pages — large lint/test failures can
  # exceed the 100/page cap and silently drop diagnostics otherwise. Per-page
  # response is `[...]`; jq's `if type == "array" then .[] else . end`
  # already flattens the multi-array stream paginate emits. A failed `gh api`
  # (403, 429 and the like) exits 2 instead of silently emitting partial
  # JSONL. The trailing `|| true` on jq still tolerates benign per-record
  # decode quirks without aborting the whole walk.
  ANNOT_RAW=$(gh api --paginate "repos/$REPO/check-runs/$cr_id/annotations?per_page=100" 2>/dev/null) ||
    die 2 "gh api annotations for check-run $cr_id failed (exit $?)"
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
