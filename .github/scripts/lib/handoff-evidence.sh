#!/usr/bin/env bash
# handoff-evidence.sh: what a lane's read-runner calls left behind, read from
# this run's jobs through the Actions API, never from a call's outputs (its run
# job runs head code and can forge them). Run by every job that decides on a
# handoff: pr-unblock.yml's handoff jobs and fix-ci-unreported,
# pr-refine.yml's fix-docs-handoff, work-resolve-issue.yml's
# resolve-issue-handoff and resolve-issue-stale, and each lane's
# <subscription>-handoff job before its third call.
#
# Facts, each over the calls in CALLS (true when any call holds it):
#   allowed  the call's broker-allowed job succeeded: pr-run-activity-read.yml
#            runs it only on broker-check's allow, which no run job can write.
#            A failed or skipped broker-check is false at once.
#   posted   the call's report job posted its check. A skipped or absent
#            report job (a handoff, forged or not) is false at once; a report
#            that ran answers through its "Post the check run" step, and one
#            whose steps are listed without it (it ended before that step)
#            is false.
#   handed-off  the call handed off: allowed, its run job succeeded, and its
#            scan job, which the read runner skips only on a handoff, is
#            skipped or absent. All three are job conclusions.
#   stale    the call's run job stopped at `Stop on stale workflow files`
#            (issue mode, before any model turn): read from the step, which
#            no run job can rename. A skipped or absent run job is false.
#   credit-stop  the call's key leg hit a credit stop: its run job's `Mark a
#            key credit stop` step succeeded, a step that runs only on
#            run-claude-cli's handoff-reason, set after the leg ends. A skipped
#            or absent run job is false.
#
# GitHub's jobs listing can return a job's steps empty, or a step's conclusion
# null, for minutes after the job ends. Job-level fields come at once, so they
# decide first; a fact only a step can settle is read again, and only while it is
# unsettled. HANDOFF_EVIDENCE_DELAYS (seconds, default "15 30 60 90 120") caps each
# wait: full jitter draws it from 0 to its cap. Reads then go on at the last cap
# until the waits sum to the caps' sum, about five minutes, the lag this exists
# for, so at worst about seven minutes and at most max_reads reads. A broker-check
# whose broker-allowed job is absent or neither succeeded nor skipped answers
# through its broker step the same way.
#
# The listing is read a page at a time. A read after the first sends each page
# it already got with an ETag as a conditional request, and a 304 gives back
# the body that ETag came with. GitHub does not count a conditional
# request answered 304 against the primary rate limit when it carries an
# Authorization header, as gh's do
# (https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api#use-conditional-requests).
#
# Usage: handoff-evidence.sh FACT... (allowed, posted, handed-off, stale, credit-stop)
# Environment: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_OUTPUT, CALLS.
# Outputs: one FACT=true|false line per requested fact, and one log line
# naming them with the read count. A fact still unsettled after the last read:
#   - a last read that failed, on fix-docs or fix-docs-subscription, pr-refine.yml's
#     two reads, holds (outage posture element 2): one ::notice line, no output
#     and exit 0, after at most 3 failed reads (element 1), and a rate limit's
#     annotation is a notice too. Empty outputs start no next leg, and
#     fix-docs-dispatch.mjs reads a leg that handed off with no next leg as this
#     hold and dispatches the PR again.
#   - a last read that got the listing, with HANDOFF_EVIDENCE_LAG=notice, set by a
#     job whose empty outputs start nothing, ends the same way: one ::notice::
#     line, no output and exit 0.
#   - anything else fails closed: exit 1, one ::error line naming what stayed
#     missing and no output, after at most 6 failed reads. Its callers read an
#     empty output as a failed read; each lane's own job fallbacks depend on it,
#     pr-unblock's starting its second leg on that read.
set -euo pipefail
# In a job, each gh call keeps its rate-limit reading for the job-end
# api-budget notice (.github/actions/log-api-budget).
# shellcheck source=/dev/null
[[ -z "${RUNNER_TEMP:-}" ]] || ! . "${BASH_SOURCE[0]%/*}/../../../.github/actions/log-api-budget/api-budget.bash" 2>/dev/null || api_budget_wrap_gh github-token

[[ $# -gt 0 ]] || {
  echo "::error::usage: handoff-evidence.sh FACT... (allowed, posted, handed-off, stale, credit-stop)"
  exit 2
}
for fact in "$@"; do
  case $fact in allowed | posted | handed-off | stale | credit-stop) ;; *)
    echo "::error::unknown handoff fact: $fact"
    exit 2
    ;;
  esac
done
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_OUTPUT:?}" "${CALLS:?}"
read -r -a delays <<<"${HANDOFF_EVIDENCE_DELAYS-15 30 60 90 120}"
window=0
for cap in "${delays[@]}"; do window=$((window + cap)); done

max_failed=6
hold=""
if [[ $CALLS =~ ^fix-docs(-subscription)?$ ]]; then
  max_failed=3
  hold=1
  export API_BUDGET_HOLD=1
fi
# A conditional read answered 304 costs no rate limit, but a page with no ETag does.
max_reads=12

# Per requested fact: "true", "false", or the missing evidence, as one line
# "fact<TAB>value".
# shellcheck disable=SC2016 # a jq program, not a shell expansion
settle='
  . as $jobs
  | def job($n): first($jobs[] | select(.name == $n)) // null;
  def step($j; $s): first(($j.steps // [])[] | select(.name == $s)) // null;
  def by_step($j; $s): step($j; $s) as $st
    | if $st.conclusion == "success" then "true"
      elif ($st.conclusion // "") != "" then "false"
      elif $st == null and (($j.steps // []) | length) > 0 then "false"
      elif $st == null then "missing: \($j.name) has no steps listed"
      else "missing: \($j.name) step \"\($s)\" has no conclusion" end;
  def allowed($c): job("\($c) / broker-check") as $b | job("\($c) / broker-allowed") as $m
    | if $m.conclusion == "success" then "true"
      elif $b == null then "false"
      elif ($b.conclusion // "") == "" then "missing: \($b.name) has no conclusion"
      elif $b.conclusion != "success" then "false"
      elif $m.conclusion == "skipped" then "false"
      else by_step($b; "Ask the broker whether the lane may run") end;
  def job_step($n; $s): job($n) as $j
    | if $j == null or $j.conclusion == "skipped" then "false"
      elif ($j.conclusion // "") == "" then "missing: \($j.name) has no conclusion"
      else by_step($j; $s) end;
  def handed_off($c): allowed($c) as $a | job("\($c) / run") as $r | job("\($c) / scan") as $s
    | if $a != "true" then $a
      elif $r == null then "false"
      elif ($r.conclusion // "") == "" then "missing: \($r.name) has no conclusion"
      elif $r.conclusion != "success" then "false"
      elif $s == null or $s.conclusion == "skipped" then "true"
      elif ($s.conclusion // "") == "" then "missing: \($s.name) has no conclusion"
      else "false" end;
  def fact($f; $c): if $f == "allowed" then allowed($c)
    elif $f == "posted" then job_step("\($c) / report"; "Post the check run")
    elif $f == "stale" then job_step("\($c) / run"; "Stop on stale workflow files")
    elif $f == "credit-stop" then job_step("\($c) / run"; "Mark a key credit stop")
    else handed_off($c) end;
  def any_of($vals): if any($vals[]; . == "true") then "true"
    elif any($vals[]; startswith("missing")) then ([$vals[] | select(startswith("missing"))] | join("; "))
    else "false" end;
  ($calls | split(" ") | map(select(. != ""))) as $cs
  | $facts | split(" ")[]
  | . as $f
  | "\($f)\t\(any_of([$cs[] | fact($f; .)]))"'

# Pages read per listing: a Link header that never ends cannot loop.
max_pages=20
# Each listing page's ETag, the body that came with it and its Link header's
# next page, by the URL read: a 304 need not carry the Link header.
declare -A page_etag=() page_body=() page_next=()

# Sets listing to one {name, conclusion, steps} line per job on every page of
# the run's latest jobs. Returns 1 when a page is not answered 200 with gh
# exiting 0, or 304 to a conditional request, or its body is not a job
# listing: gh exits 1 on a 304, which -i still prints, and on a body cut off
# after its headers.
read_jobs() {
  local url="repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs?filter=latest&per_page=100"
  local out headers status body jobs pages=0 cond rc
  listing=""
  while [[ -n $url ]]; do
    pages=$((pages + 1))
    ((pages <= max_pages)) || return 1
    cond=()
    [[ -z ${page_etag[$url]:-} ]] || cond=(-H "If-None-Match: ${page_etag[$url]}")
    rc=0
    out=$(gh api -i "$url" "${cond[@]}") || rc=$?
    headers=$(awk '{ sub(/\r$/, "") } $0 == "" { exit } { print }' <<<"$out")
    status=$(awk 'NR == 1 { print $2 }' <<<"$headers")
    if [[ $status == 200 && $rc -eq 0 ]]; then
      body=$(awk 'seen { print; next } { line = $0; sub(/\r$/, "", line) } line == "" { seen = 1 }' <<<"$out")
    elif [[ $status == 304 && ${#cond[@]} -gt 0 ]]; then
      body=${page_body[$url]}
    else
      return 1
    fi
    # input fails on an empty body, which would otherwise read as no jobs.
    jobs=$(jq -nc 'input | .jobs[] | {name, conclusion, steps: [.steps[]? | {name, conclusion}]}' <<<"$body") || return 1
    # Only a page whose body parsed is kept, so a 304 never reuses a bad one.
    if [[ $status == 200 ]]; then
      page_body[$url]=$body
      page_etag[$url]=$(awk 'NR > 1 && tolower($0) ~ /^etag:/ { sub(/^[^:]*:[ \t]*/, ""); print; exit }' <<<"$headers")
      page_next[$url]=$(grep -i '^link:' <<<"$headers" | grep -o '<[^>]*>; *rel="next"' | sed 's/^<\([^>]*\)>.*/\1/') || page_next[$url]=""
    fi
    listing+=${jobs:+$jobs$'\n'}
    url=${page_next[$url]}
  done
}

reads=0
failed=0
waited=0
while :; do
  reads=$((reads + 1))
  missing=""
  # shellcheck disable=SC2310 # read_jobs returns 1 itself on every failed read
  if read_jobs; then
    if answers=$(jq -rs --arg calls "$CALLS" --arg facts "$*" "$settle" <<<"$listing"); then
      missing=$(grep -v $'\t\\(true\\|false\\)$' <<<"$answers" | cut -f2- | paste -sd ';' - || true)
    else
      missing="the jobs listing did not parse"
    fi
  else
    missing="the jobs read failed"
    failed=$((failed + 1))
  fi
  if [[ -z $missing ]]; then
    printf '%s\n' "${answers//$'\t'/=}" >>"${GITHUB_OUTPUT}"
    echo "handoff evidence: $(paste -sd ' ' - <<<"${answers//$'\t'/=}") ($reads read$([[ $reads -eq 1 ]] || echo s))"
    exit 0
  fi
  if ((reads <= ${#delays[@]})); then
    cap=${delays[reads - 1]}
  elif ((waited < window)); then
    cap=${delays[-1]}
  else
    break
  fi
  ((reads < max_reads && failed < max_failed)) || break
  delay=$(shuf -i "0-$cap" -n 1)
  echo "Read $reads: $missing; reading again in ${delay}s"
  sleep "$delay"
  waited=$((waited + delay))
done
if [[ ${HANDOFF_EVIDENCE_LAG:-} == notice && $missing == missing:* ]]; then
  echo "::notice::handoff evidence for ${CALLS} still missing after $reads reads: $missing; the outputs stay empty"
  exit 0
fi
if [[ -n $hold && $missing != missing:* ]]; then
  echo "::notice title=Handoff evidence hold::handoff evidence for ${CALLS} still missing after $reads reads: $missing; no fallback starts, and the next dispatcher tick sends the PR again"
  # A hold job's lane-hold marker (lane-hold-marker.mjs); a failed write leaves the hold as it is.
  [[ -z ${LANE_HOLD_MARKER:-} ]] || { mkdir -p "${LANE_HOLD_MARKER%/*}" && printf '%s %s\n' "${LANE_HOLD_MARKER##*/}" "${GITHUB_RUN_ID:-}" >"$LANE_HOLD_MARKER"; } || true
  exit 0
fi
echo "::error::handoff evidence for ${CALLS} still missing after $reads reads: $missing"
exit 1
