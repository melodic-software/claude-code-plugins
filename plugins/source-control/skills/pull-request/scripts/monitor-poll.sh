#!/usr/bin/env bash
# The pull-request monitor's Monitor watch: polls one PR over REST and prints a line for each
# check that finishes, each new comment on the three review surfaces, and each change in the
# unresolved review-thread count. Contract: reference/monitor.md 3.0.1 of the pull-request skill;
# the GitHub facts behind each read: reference/providers/github/pull-request/monitor.md
# "Poll checks over REST" in this plugin.
#
# Usage: monitor-poll.sh --pr <n> (--checkout <dir> | --repo <owner>/<repo>)
#          [--interval <seconds>] [--baseline <file>] [--snapshot <file>] [--once]
#   --checkout  the checkout of the PR's repository; target-repo.sh resolves the repository
#   --repo      the PR's base repository, named explicitly (a triangular flow); wins over --checkout
#   --interval  seconds between polls, default 60; raise it to poll less often with several watchers
#   --baseline  re-arm only: the file a --snapshot run of this script wrote
#   --snapshot  read the checks once, write them to this file under a marker line, then exit
#   --once      exit 0 at the end of the first poll that printed a check, comment or thread line
# Exit 0: the PR is merged or closed, the snapshot was written, or a --once poll printed a line.
# Exit 1: the repository did not resolve, or a snapshot run's checks read failed.
# Exit 2: a rate limit stopped the watch.
# Exit 3: usage error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THREADS_SCRIPT="$SCRIPT_DIR/../../../scripts/source-control-review-threads"

usage() {
  echo "usage: monitor-poll.sh --pr <n> (--checkout <dir> | --repo <owner>/<repo>) [--interval <seconds>] [--baseline <file>] [--snapshot <file>] [--once]" >&2
  exit 3
}

PR_NUMBER=""
CHECKOUT=""
OWNER_REPO=""
INTERVAL=60
BASELINE_FILE=""
SNAPSHOT_FILE=""
ONCE=0
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --once ]]; then
    ONCE=1
    shift
    continue
  fi
  [[ $# -ge 2 ]] || usage
  case "$1" in
  --pr) PR_NUMBER=$2 ;;
  --checkout) CHECKOUT=$2 ;;
  --repo) OWNER_REPO=$2 ;;
  --interval) INTERVAL=$2 ;;
  --baseline) BASELINE_FILE=$2 ;;
  --snapshot) SNAPSHOT_FILE=$2 ;;
  *) usage ;;
  esac
  shift 2
done
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]] || usage
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || usage
[[ -n "$OWNER_REPO" || -n "$CHECKOUT" ]] || usage
if [[ -z "$OWNER_REPO" ]]; then
  OWNER_REPO=$(bash "$SCRIPT_DIR/target-repo.sh" --dir "$CHECKOUT") || exit 1
fi
[[ "$OWNER_REPO" == */* ]] || usage
OWNER=${OWNER_REPO%%/*} REPO=${OWNER_REPO#*/}

SNAPSHOT_MARK='# monitor-poll checks snapshot'
prev_checks=""
baselined=0  # set by a snapshot BASELINE_FILE or the first successful check read
if [[ -n "$BASELINE_FILE" && "$(head -n 1 "$BASELINE_FILE" 2>/dev/null | tr -d '\r')" == "$SNAPSHOT_MARK" ]]; then
  prev_checks=$(tail -n +2 "$BASELINE_FILE" | tr -d '\r' | grep -v '^$' | sort || true)
  baselined=1
elif [[ -n "$BASELINE_FILE" ]]; then
  echo "BASELINE-UNREADABLE $BASELINE_FILE — missing or not a snapshot this script wrote; first checks poll only records; run a full scan"
fi
last_comment_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
prev_threads=""
poll=0
emitted=0  # set when a poll prints a check, comment or thread line; read by --once
errs=""  # stderr of every later read this poll, checked for a rate limit at its end
# read_into CMD...: the command's stdout into out, its stderr appended to errs;
# returns the command's status. The stderr comes first in the capture, since
# the command has exited before printf writes the \037 marker, status and stdout.
read_into() {
  local all rest
  all=$( { out=$("$@"); printf '\037%s:%s' "$?" "$out"; } 2>&1 )
  errs+=${all%%$'\037'*}
  rest=${all#*$'\037'}
  out=${rest#*:}
  return "${rest%%:*}"
}

while true; do
  # Terminal state check — exit watch if PR closed/merged. REST, like the
  # CI read below (§3.1 "Polling CI from more than one worker"). A rate
  # limit stops the watch: polling on would probe for recovery
  # (reference/providers/github/README.md#api-budget).
  if out=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" \
    --jq '"\(if .merged then "MERGED" elif .state == "closed" then "CLOSED" else "OPEN" end) \(.head.sha)"' 2>&1); then
    read -r state head_sha <<<"$(printf '%s' "$out" | tr -d '\r')"
  elif grep -qiE 'rate limit|HTTP 429' <<<"$out"; then
    echo "RATE-LIMITED — watch stopped: $out"
    exit 2
  fi
  if [[ "$state" == "MERGED" || "$state" == "CLOSED" ]]; then
    echo "PR #$PR_NUMBER $state — watch complete"
    exit 0
  fi

  # CI changes: one "name: bucket" line per check, the same rows and
  # buckets `gh pr checks` reports, read over REST. Check runs are
  # deduplicated as gh does (latest start per name/workflow/event);
  # commit statuses are always read, since check-runs omit them.
  b='def b: ascii_upcase | if . == "SUCCESS" then "pass" elif . == "SKIPPED" or . == "NEUTRAL" then "skipping" elif . == "CANCELLED" then "cancel" elif . == "ERROR" or . == "FAILURE" or . == "TIMED_OUT" or . == "ACTION_REQUIRED" then "fail" else "pending" end;'
  # A failed read of any call below leaves the baseline alone and emits
  # nothing: an empty list from a failed read would otherwise be stored as
  # the baseline, and the next good poll would emit every finished check.
  checks_ok=1
  [[ -n "${head_sha:-}" ]] || checks_ok=0
  if [[ "$checks_ok" -eq 1 ]]; then
    if read_into gh api --paginate "repos/$OWNER/$REPO/actions/runs?head_sha=$head_sha&per_page=100" \
      --jq '.workflow_runs[] | {(.check_suite_id | tostring): "\(.name)/\(.event)"}'; then
      wf=$(printf '%s\n' "$out" | jq -s -c 'add // {}') || checks_ok=0
    else checks_ok=0; fi
  fi
  if [[ "$checks_ok" -eq 1 ]]; then
    read_into gh api --paginate "repos/$OWNER/$REPO/commits/$head_sha/check-runs?per_page=100" || checks_ok=0
    runs_raw=$out
    read_into gh api --paginate "repos/$OWNER/$REPO/commits/$head_sha/status?per_page=100" \
      --jq "$b"' .statuses[] | "\(.context): \(.state | b)"' || checks_ok=0
    stat_raw=$out
  fi
  if [[ "$checks_ok" -eq 1 ]]; then
    run_rows=$(printf '%s\n' "$runs_raw" | jq -s -r --argjson wf "$wf" "$b"' [.[].check_runs[] | {k: "\(.name)/\($wf[.check_suite.id | tostring] // "")", name, t: (.started_at // ""), s: (if .status == "completed" then .conclusion else .status end)}] | group_by(.k) | map(max_by(.t))[] | "\(.name): \(.s | b)"') || checks_ok=0
    cur_checks=$({ printf '%s\n' "$run_rows"; printf '%s\n' "$stat_raw"; } \
      | tr -d '\r' | grep -v -e '^$' -e ': pending$' | sort || true)
  fi
  if [[ -n "$SNAPSHOT_FILE" ]]; then
    if [[ "$checks_ok" -ne 1 ]]; then
      echo "SNAPSHOT-FAILED — checks read failed; no snapshot written"
      exit 1
    fi
    printf '%s\n%s\n' "$SNAPSHOT_MARK" "$cur_checks" >"$SNAPSHOT_FILE.tmp" &&
      mv "$SNAPSHOT_FILE.tmp" "$SNAPSHOT_FILE"
    exit $?
  fi
  if [[ "$checks_ok" -eq 1 ]]; then
    # Bucket values mirror gh pr checks: pass|fail|pending|skipping|cancel.
    # With no baseline, the first poll whose check read succeeds only records
    # the checks. A re-arm starts from the full iteration's snapshot instead,
    # so a check that finished since that read is emitted and the rest are not
    # re-emitted.
    if [[ "$baselined" -eq 1 && "$cur_checks" != "$prev_checks" ]]; then
      comm -13 <(echo "$prev_checks") <(echo "$cur_checks") | \
        grep --line-buffered -E ': (pass|fail|skipping|cancel)$' \
        && emitted=1
    fi
    prev_checks="$cur_checks"
    baselined=1
  fi

  # New comments — all three review surfaces (issue-level, inline
  # review comments, review bodies). Watching only issues/comments
  # misses inline findings posted with no CI state change.
  # Advance the watermark only when every fetch succeeded — a transient
  # gh failure would otherwise skip past comments that arrived during
  # the failed poll window and never emit them.
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fetch_ok=1
  if read_into gh api --paginate "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments?since=$last_comment_ts&per_page=100" \
    --jq '.[] | "COMMENT \(.user.login): \(.body[:80])"'; then
    printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . && emitted=1
  else fetch_ok=0; fi
  if read_into gh api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments?since=$last_comment_ts&per_page=100" \
    --jq '.[] | "INLINE-COMMENT \(.user.login): \(.body[:80])"'; then
    printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . && emitted=1
  else fetch_ok=0; fi
  # Reviews API has no `since` param — filter client-side on submitted_at.
  # Client-side filtering makes pagination required: an unpaginated read
  # returns the 30 oldest reviews, so on a PR past that count the new ones
  # this poll exists to catch are exactly the ones never fetched.
  if read_into gh api --paginate "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews?per_page=100" \
    --jq ".[] | select(.submitted_at > \"$last_comment_ts\") | \"REVIEW \(.user.login) [\(.state)]: \(.body[:80])\""; then
    printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . && emitted=1
  else fetch_ok=0; fi
  [[ "$fetch_ok" -eq 1 ]] && last_comment_ts="$now"

  # Review threads: resolving one moves no check and posts no comment, so
  # the reads above never see it. The Gate 7 read (readiness.md) costs a
  # GraphQL call, so it runs every 4th poll (about 4 minutes) and emits
  # when the unresolved count, or THREADS_UNPROVEN, changes.
  if ((poll % 4 == 0)); then
    read_into bash "$THREADS_SCRIPT" "$OWNER/$REPO#$PR_NUMBER"
    cur_threads=$(printf '%s\n' "$out" \
      | awk 'NR == 1 && /^THREADS_(OK|BLOCKED) unresolved=/ { sub(/.*unresolved=/, ""); sub(/[^0-9].*/, ""); print }')
    cur_threads=${cur_threads:-THREADS_UNPROVEN}
    if [[ "$cur_threads" != "$prev_threads" ]]; then
      [[ "$poll" -gt 0 ]] && echo "REVIEW-THREADS unresolved=$cur_threads" && emitted=1
      prev_threads="$cur_threads"
    fi
  fi
  if grep -qiE 'rate limit|HTTP 429' <<<"$errs"; then
    echo "RATE-LIMITED — watch stopped: $(grep -iE -m1 'rate limit|HTTP 429' <<<"$errs")"
    exit 2
  fi
  [[ "$ONCE" -eq 1 && "$emitted" -eq 1 ]] && exit 0
  errs=""
  poll=$((poll + 1))

  sleep "$INTERVAL"
done
