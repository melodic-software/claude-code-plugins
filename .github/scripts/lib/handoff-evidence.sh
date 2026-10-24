#!/usr/bin/env bash
# handoff-evidence.sh: what a lane's read-runner calls left behind, read from
# this run's jobs through the Actions API, never from a call's outputs (its run
# job runs head code and can forge them). Run by every job that decides on a
# handoff: pr-unblock.yml's handoff jobs and fix-ci-unreported,
# pr-refine.yml's fix-docs-handoff, and work-resolve-issue.yml's
# resolve-issue-handoff.
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
#
# GitHub's jobs listing can return a job's steps empty, or a step's conclusion
# null, for minutes after the job ends. Job-level fields come at once, so they
# decide first; a fact only a step can settle is read again after each delay in
# HANDOFF_EVIDENCE_DELAYS (seconds, default "15 30 60 90 120", about five
# minutes), and only while it is unsettled. A broker-check whose broker-allowed
# job is absent or neither succeeded nor skipped answers through its broker
# step the same way.
#
# Usage: handoff-evidence.sh FACT... (allowed, posted, handed-off)
# Environment: GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_OUTPUT, CALLS.
# Outputs: one FACT=true|false line per requested fact. Exit 1, with one
# ::error line naming what stayed missing and no output, when a fact is still
# unsettled after the last read; callers read an empty output as a failed read.
set -euo pipefail

[[ $# -gt 0 ]] || {
  echo "::error::usage: handoff-evidence.sh FACT... (allowed, posted, handed-off)"
  exit 2
}
for fact in "$@"; do
  case $fact in allowed | posted | handed-off) ;; *)
    echo "::error::unknown handoff fact: $fact"
    exit 2
    ;;
  esac
done
: "${GH_TOKEN:?}" "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_OUTPUT:?}" "${CALLS:?}"
read -r -a delays <<<"${HANDOFF_EVIDENCE_DELAYS-15 30 60 90 120}"

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
  def posted($c): job("\($c) / report") as $r
    | if $r == null or $r.conclusion == "skipped" then "false"
      elif ($r.conclusion // "") == "" then "missing: \($r.name) has no conclusion"
      else by_step($r; "Post the check run") end;
  def handed_off($c): allowed($c) as $a | job("\($c) / run") as $r | job("\($c) / scan") as $s
    | if $a != "true" then $a
      elif $r == null then "false"
      elif ($r.conclusion // "") == "" then "missing: \($r.name) has no conclusion"
      elif $r.conclusion != "success" then "false"
      elif $s == null or $s.conclusion == "skipped" then "true"
      elif ($s.conclusion // "") == "" then "missing: \($s.name) has no conclusion"
      else "false" end;
  def any_of($vals): if any($vals[]; . == "true") then "true"
    elif any($vals[]; startswith("missing")) then ([$vals[] | select(startswith("missing"))] | join("; "))
    else "false" end;
  ($calls | split(" ") | map(select(. != ""))) as $cs
  | $facts | split(" ")[]
  | . as $f
  | "\($f)\t\(any_of([$cs[] | if $f == "allowed" then allowed(.) elif $f == "posted" then posted(.) else handed_off(.) end]))"'

reads=0
for delay in "${delays[@]}" ""; do
  reads=$((reads + 1))
  missing=""
  if listing=$(gh api --paginate "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs?filter=latest&per_page=100" \
    --jq '.jobs[] | {name, conclusion, steps: [.steps[]? | {name, conclusion}]}'); then
    if answers=$(jq -rs --arg calls "$CALLS" --arg facts "$*" "$settle" <<<"$listing"); then
      missing=$(grep -v $'\t\\(true\\|false\\)$' <<<"$answers" | cut -f2- | paste -sd ';' - || true)
    else
      missing="the jobs listing did not parse"
    fi
  else
    missing="the jobs read failed"
  fi
  if [[ -z $missing ]]; then
    printf '%s\n' "${answers//$'\t'/=}" >>"${GITHUB_OUTPUT}"
    exit 0
  fi
  [[ -n $delay ]] || break
  echo "Read $reads: $missing; reading again in ${delay}s"
  sleep "$delay"
done
echo "::error::handoff evidence for ${CALLS} still missing after $reads reads: $missing"
exit 1
