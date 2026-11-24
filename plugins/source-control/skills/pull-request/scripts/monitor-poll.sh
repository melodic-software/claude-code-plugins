#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THREADS_SCRIPT="$SCRIPT_DIR/../../../scripts/source-control-review-threads"

usage() {
  cat >&2 <<'EOF'
usage: monitor-poll.sh --pr <n> (--checkout <dir> | --repo <owner>/<repo>) [--interval <seconds>] [--baseline <file>] [--snapshot <file>] [--once] [--verdict]

The pull-request monitor's Monitor watch: polls one PR over REST and prints a line for each
check that finishes, each new comment on the three review surfaces, each change in the
unresolved review-thread count, and each new pr-verify verdict at the PR's head where the base
branch has .github/workflows/pr-verify.yml. Contract: reference/monitor.md 3.0.1 of the
pull-request skill; the GitHub facts behind each read: reference/providers/github/pull-request/monitor.md
"Poll checks over REST" in this plugin.

  --checkout  the checkout of the PR's repository; target-repo.sh resolves the repository
  --repo      the PR's base repository, named explicitly (a triangular flow); wins over --checkout
  --interval  seconds between polls, default 90; every read is a conditional request, so a poll
              where nothing changed counts nothing against the REST rate limit
  --baseline  re-arm only: the file a --snapshot run of this script wrote
  --snapshot  read the checks and the verdicts once, write them to this file under a marker line, then exit
  --once      exit 0 at the end of the first poll that printed a check, comment, thread or verdict line
  --verdict   read the pr-verify verdicts at the head once, print them, then exit

Exit 0: the PR is merged or closed, the snapshot was written, a --once poll printed a line, or
        a --verdict run read the verdicts.
Exit 1: the repository did not resolve, a snapshot run's checks read failed, or a --verdict
        run's read failed.
Exit 2: a rate limit stopped the watch.
Exit 3: usage error.
EOF
  exit 3
}

PR_NUMBER=""
CHECKOUT=""
OWNER_REPO=""
INTERVAL=90
BASELINE_FILE=""
SNAPSHOT_FILE=""
ONCE=0
VERDICT_ONLY=0
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --once || "$1" == --verdict ]]; then
    [[ "$1" == --once ]] && ONCE=1 || VERDICT_ONLY=1
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
VERDICT_KEY='^PR-VERIFY (pass|pass-notes|fail) [0-9a-f]{40}$'
prev_checks=""
baselined=0
pv_seen=""
pv_based=0
if [[ -n "$BASELINE_FILE" && "$(head -n 1 "$BASELINE_FILE" 2>/dev/null | tr -d '\r')" == "$SNAPSHOT_MARK" ]]; then
  prev_checks=$(tail -n +2 "$BASELINE_FILE" | tr -d '\r' | grep -v '^$' | grep -vE "$VERDICT_KEY" | sort || true)
  pv_seen=$(tail -n +2 "$BASELINE_FILE" | tr -d '\r' | grep -E "$VERDICT_KEY" || true)
  baselined=1
  pv_based=1
elif [[ -n "$BASELINE_FILE" ]]; then
  echo "BASELINE-UNREADABLE $BASELINE_FILE — missing or not a snapshot this script wrote; first checks poll only records; run a full scan"
fi
watch_start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
last_comment_ts=$watch_start
prev_threads=""
poll=0
emitted=0
errs=""
read_into() {
  local all rest
  all=$( { out=$("$@"); printf '\037%s:%s' "$?" "$out"; } 2>&1 )
  errs+=${all%%$'\037'*}
  rest=${all#*$'\037'}
  out=${rest#*:}
  return "${rest%%:*}"
}

# Every read is a conditional GET: each page goes out with the ETag of its last answer, and a 304
# replays that answer's body. GitHub does not count an authorized 304 against the primary rate
# limit, so a poll where nothing changed costs no requests:
# https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests
# Each page is cached on its own because a change can land on any page, and every URL stays the
# same from poll to poll, since a different query string gets a different ETag.
# An ETag covers the body, not the Link header, so a full page that answers 304 still reads the page
# after it: a list that grows from per_page items to one more adds a page and leaves page 1 as it was.
# A read's new answers are staged and cached only once the whole read, and for a comment surface
# its filter, succeeded; a read that fails partway leaves the old ETags, so the next poll reads
# the new pages again instead of answering 304 for them.
# The cache is parallel indexed arrays, not `declare -A`, which Bash 3.2 (macOS) lacks.
per_page=100
c_url=() c_etag=() c_body=() c_next=() c_full=()
link_next='<([^>]*)>; rel="next"'
cache_find() {
  local i
  for ((i = 0; i < ${#c_url[@]}; i++)); do
    [[ "${c_url[i]}" == "$1" ]] && ci=$i && return 0
  done
  ci=${#c_url[@]}
  return 1
}
cache_commit() {
  local i
  for ((i = 0; i < ${#s_url[@]}; i++)); do
    cache_find "${s_url[i]}"
    c_url[ci]=${s_url[i]} c_etag[ci]=${s_etag[i]} c_body[ci]=${s_body[i]} c_next[ci]=${s_next[i]} c_full[ci]=${s_full[i]}
  done
  s_url=()
}
cget() {
  local url=$1 first=$1 page=1 pages="" head body status tag next line full n
  local -a cond
  fresh=0 s_url=() s_etag=() s_body=() s_next=() s_full=()
  while [[ -n "$url" ]]; do
    cond=()
    cache_find "$url" && cond=(-H "If-None-Match: ${c_etag[ci]}")
    read_into gh api -i "${cond[@]}" "$url"
    out=${out//$'\r'/}
    head=${out%%$'\n\n'*} body=""
    [[ "$head" != "$out" ]] && body=${out#*$'\n\n'}
    status=${head%%$'\n'*} status=${status#* } status=${status%% *}
    cget_status=$status
    tag="" next=""
    while IFS= read -r line; do
      case "$line" in
      [Ee][Tt][Aa][Gg]:*) tag=${line#*: } ;;
      [Ll][Ii][Nn][Kk]:*) [[ "$line" =~ $link_next ]] && next=${BASH_REMATCH[1]} ;;
      *) ;;
      esac
    done <<<"$head"
    if [[ "$status" == 304 ]] && cache_find "$url"; then
      body=${c_body[ci]} next=${c_next[ci]} full=${c_full[ci]}
    elif [[ "$status" == 200 ]]; then
      fresh=1
      n=$(printf '%s' "$body" | jq 'if type == "array" then length else ([.[] | arrays | length] | max // 0) end' 2>/dev/null)
      full=0
      [[ "${n//$'\r'/}" -ge "$per_page" ]] 2>/dev/null && full=1
      if [[ -n "$tag" ]]; then
        n=${#s_url[@]}
        s_url[n]=$url s_etag[n]=$tag s_body[n]=$body s_next[n]=$next s_full[n]=$full
      fi
    else
      return 1
    fi
    pages+=$body$'\n'
    page=$((page + 1))
    [[ -z "$next" && "$full" -eq 1 && "$first" == *per_page=* ]] && next="$first&page=$page"
    url=$next
  done
  out=$pages
  [[ "${2:-}" == defer ]] || cache_commit
}

# Verdict and FAIL-index artifact names (artifactName, failIndexNames):
# https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/pr-verify/write-verdict.mjs
pv_base="" pv_on=0
verdict_read() {
  local v name ref d n before ids_pr sel
  pv_now=""
  [[ -n "$base_ref" && "$base_ref" != null && "$default_branch" != null ]] || return 1
  if [[ "$pv_base" != "$base_ref" ]]; then
    ref=$(jq -rn --arg r "$base_ref" '$r | @uri') || return 1
    before=${#errs}
    if cget "repos/$OWNER/$REPO/contents/.github/workflows/pr-verify.yml?ref=$ref"; then
      pv_on=1
    elif [[ "$cget_status" == 404 || "${errs:before}" == *"(HTTP 404)"* ]]; then
      pv_on=0
    else
      return 1
    fi
    pv_base=$base_ref
  fi
  [[ "$pv_on" -eq 1 ]] || return 0
  # shellcheck disable=SC2016 # $n and $d are jq variables
  sel='[.[].artifacts[]? | select(.name == $n and .expired == false and .workflow_run.head_branch == $d) | .workflow_run.id] | unique'
  d=$(printf '%s' "$head_ref" | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null; } | cut -c1-16)
  [[ "$d" =~ ^[0-9a-f]{16}$ ]] || d=""
  for v in pass pass-notes; do
    for name in "pr-verify-$PR_NUMBER-$head_sha-$v" ${d:+"pr-verify-$PR_NUMBER-$head_sha-$v-$d"}; do
      cget "repos/$OWNER/$REPO/actions/artifacts?name=$name&per_page=$per_page" || return 1
      n=$(printf '%s' "$out" | jq -s --arg n "$name" --arg d "$default_branch" "$sel | length") || return 1
      if [[ "${n//$'\r'/}" -gt 0 ]]; then
        pv_now+="PR-VERIFY $v $head_sha"$'\n'
        break
      fi
    done
  done
  for name in "pr-verify-index-pr-$PR_NUMBER" "pr-verify-index-sha-$head_sha"; do
    cget "repos/$OWNER/$REPO/actions/artifacts?name=$name&per_page=$per_page" || return 1
    n=$(printf '%s' "$out" | jq -s -c --arg n "$name" --arg d "$default_branch" "$sel") || return 1
    [[ "$name" == *-pr-* ]] && ids_pr=$n && continue
    n=$(jq -n --argjson a "$ids_pr" --argjson b "$n" '$a - ($a - $b) | length') || return 1
    [[ "${n//$'\r'/}" -gt 0 ]] && pv_now+="PR-VERIFY fail $head_sha"$'\n'
  done
  return 0
}
pv_wanted() {
  [[ "$checks_ok" -eq 1 ]] && ! grep -q ': pending$' <<<"$run_rows" &&
    ! grep -qE "^PR-VERIFY pass(-notes)? $head_sha\$" <<<"$pv_seen"
}
pv_print() {
  if [[ "$1" == "PR-VERIFY fail "* ]]; then
    echo "$1 — label pr-verify-failed; its notes are the review threads that open with <!-- pr-verify:fail-note -->"
  else
    echo "$1"
  fi
}

while true; do
  if cget "repos/$OWNER/$REPO/pulls/$PR_NUMBER" &&
    pr=$(printf '%s' "$out" | jq -r '"\(if .merged then "MERGED" elif .state == "closed" then "CLOSED" else "OPEN" end) \(.head.sha) \(.base.ref) \(.base.repo.default_branch) \(.head.ref)"'); then
    read -r state head_sha base_ref default_branch head_ref <<<"${pr//$'\r'/}"
  elif grep -qiE 'rate limit|HTTP 429' <<<"$errs"; then
    echo "RATE-LIMITED — watch stopped: $(grep -iE -m1 'rate limit|HTTP 429' <<<"$errs")"
    exit 2
  fi
  if [[ "$state" == "MERGED" || "$state" == "CLOSED" ]]; then
    echo "PR #$PR_NUMBER $state — watch complete"
    exit 0
  fi
  if [[ "$VERDICT_ONLY" -eq 1 ]]; then
    if [[ -z "${head_sha:-}" ]] || ! verdict_read; then
      echo "PR-VERIFY-UNREAD — $(grep -m1 . <<<"$errs")"
      exit 1
    fi
    if [[ "$pv_on" -eq 0 ]]; then
      echo "PR-VERIFY off — the base branch has no .github/workflows/pr-verify.yml"
    elif [[ -z "$pv_now" ]]; then
      echo "PR-VERIFY none $head_sha"
    else
      while IFS= read -r key; do [[ -n "$key" ]] && pv_print "$key"; done <<<"$pv_now"
    fi
    exit 0
  fi

  # Commit statuses are read separately because the check-runs endpoint omits them:
  # https://docs.github.com/en/rest/commits/statuses
  b='def b: ascii_upcase | if . == "SUCCESS" then "pass" elif . == "SKIPPED" or . == "NEUTRAL" then "skipping" elif . == "CANCELLED" then "cancel" elif . == "ERROR" or . == "FAILURE" or . == "TIMED_OUT" or . == "ACTION_REQUIRED" then "fail" else "pending" end;'
  checks_ok=1
  [[ -n "${head_sha:-}" ]] || checks_ok=0
  if [[ "$checks_ok" -eq 1 ]]; then
    if cget "repos/$OWNER/$REPO/actions/runs?head_sha=$head_sha&per_page=$per_page"; then
      wf=$(printf '%s' "$out" | jq -s -c '[.[].workflow_runs[] | {(.check_suite_id | tostring): "\(.name)/\(.event)"}] | add // {}') || checks_ok=0
    else checks_ok=0; fi
  fi
  if [[ "$checks_ok" -eq 1 ]]; then
    cget "repos/$OWNER/$REPO/commits/$head_sha/check-runs?per_page=$per_page" || checks_ok=0
    runs_raw=$out
    if cget "repos/$OWNER/$REPO/commits/$head_sha/status?per_page=$per_page"; then
      stat_raw=$(printf '%s' "$out" | jq -r "$b"' .statuses[] | "\(.context): \(.state | b)"') || checks_ok=0
    else checks_ok=0; fi
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
    pv_now=""
    if pv_wanted && ! verdict_read; then pv_now=""; fi
    printf '%s\n%s\n%s' "$SNAPSHOT_MARK" "$cur_checks" "$pv_now" >"$SNAPSHOT_FILE.tmp" &&
      mv "$SNAPSHOT_FILE.tmp" "$SNAPSHOT_FILE"
    exit $?
  fi
  if [[ "$checks_ok" -eq 1 ]]; then
    if [[ "$baselined" -eq 1 && "$cur_checks" != "$prev_checks" ]]; then
      comm -13 <(echo "$prev_checks") <(echo "$cur_checks") | \
        grep --line-buffered -E ': (pass|fail|skipping|cancel)$' \
        && emitted=1
    fi
    prev_checks="$cur_checks"
    baselined=1
  fi
  if [[ -n "${head_sha:-}" ]] && pv_wanted && verdict_read; then
    while IFS= read -r key; do
      [[ -n "$key" ]] || continue
      grep -qxF -- "$key" <<<"$pv_seen" && continue
      pv_seen+=$'\n'$key
      [[ "$pv_based" -eq 1 ]] || continue
      pv_print "$key"
      emitted=1
    done <<<"$pv_now"
    pv_based=1
  fi

  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  fetch_ok=1
  # `since` stays at the watch's start so the URL, and so its ETag, holds from poll to poll; the
  # watermark filter runs here, on updated_at, the field `since` filters on. A surface whose every
  # page came back 304 holds nothing the poll that cached it did not already report, so it is
  # skipped rather than filtered again.
  # The reviews endpoint takes no `since` parameter, so its filter is on submitted_at and the read
  # must paginate to reach the newest reviews:
  # https://docs.github.com/en/rest/pulls/reviews#list-reviews-for-a-pull-request
  for surface in "issues/$PR_NUMBER/comments?since=$watch_start&" "pulls/$PR_NUMBER/comments?since=$watch_start&" \
    "pulls/$PR_NUMBER/reviews?"; do
    # shellcheck disable=SC2016 # $ts is a jq variable
    case "$surface" in
    issues/*) row='select(.updated_at >= $ts) | "COMMENT \(.user.login): \(.body[:80])"' ;;
    */comments*) row='select(.updated_at >= $ts) | "INLINE-COMMENT \(.user.login): \(.body[:80])"' ;;
    *) row='select(.submitted_at > $ts) | "REVIEW \(.user.login) [\(.state)]: \(.body[:80])"' ;;
    esac
    if ! cget "repos/$OWNER/$REPO/${surface}per_page=$per_page" defer; then
      fetch_ok=0
    elif [[ "$fresh" -eq 0 ]]; then
      :
    elif new=$(printf '%s' "$out" | jq -r --arg ts "$last_comment_ts" ".[] | $row"); then
      cache_commit
      printf '%s\n' "$new" | tr -d '\r' | grep --line-buffered . && emitted=1
    else fetch_ok=0; fi
  done
  [[ "$fetch_ok" -eq 1 ]] && last_comment_ts="$now"

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
