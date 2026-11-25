#!/usr/bin/env bash
set -euo pipefail
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
max_reads=12

# shellcheck disable=SC2016 # a jq program, not a shell expansion
settle='
  . as $jobs
  | def titled($id): $id | split("-") | map(if . == "ci" then "CI" else (.[:1] | ascii_upcase) + .[1:] end) | join(" ");
  def job($n): ($n | split(" / ")) as $p
    | first($jobs[] | select(.name == "\(titled($p[0])) / \(titled($p[1]))")) // first($jobs[] | select(.name == $n)) // null;
  def step($j; $s): first(($j.steps // [])[] | select(.name == $s)) // null;
  def by_step($j; $s): step($j; $s) as $st
    | if $st.conclusion == "success" then "true"
      elif ($st.conclusion // "") != "" then "false"
      elif $st == null and (($j.steps // []) | length) > 0 then "false"
      elif $st == null then "missing: \($j.name) has no steps listed"
      else "missing: \($j.name) step \"\($s)\" has no conclusion" end;
  def allowed($c): (job("\($c) / broker-check") // job("\($c) / check-broker")) as $b
    | (job("\($c) / broker-allowed") // job("\($c) / record-broker-allow")) as $m
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

max_pages=20
declare -A page_etag=() page_body=() page_next=()

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
    jobs=$(jq -nc 'input | .jobs[] | {name, conclusion, steps: [.steps[]? | {name, conclusion}]}' <<<"$body") || return 1
    if [[ $status == 200 ]]; then
      page_body[$url]=$body
      page_etag[$url]=$(awk 'NR > 1 && tolower($0) ~ /^etag:/ { sub(/^[^:]*:[ \t]*/, ""); print; exit }' <<<"$headers")
      page_next[$url]=$(grep -i '^link:' <<<"$headers" | grep -o '<[^>]*>; *rel="next"' | sed 's/^<\([^>]*\)>.*/\1/') || page_next[$url]=""
    fi
    listing+=${jobs:+$jobs$'\n'}
    url=${page_next[$url]}
  done
}

held_by() {
  declare -F api_budget_stop_until >/dev/null || return 0
  local until status
  until=$(api_budget_stop_until core)
  [[ -n $until ]] || return 0
  if status=$(api_budget_server_status core "$until"); then
    echo "GitHub answered HTTP $status with a Retry-After, so no call goes before $(api_budget_when "$until")"
  else
    echo "GitHub's core API rate limit holds until $(api_budget_when "$until")"
  fi
}
rate_guard=${BASH_SOURCE[0]%/*}/../../actions/log-api-budget/rate-guard.mjs

reads=0
failed=0
waited=0
waited_out=""
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
    held=$(held_by)
    if [[ -n $held ]]; then
      missing+=": $held"
      if [[ -n ${API_BUDGET_WAIT_SECONDS:-} ]]; then
        if [[ -z $waited_out && -f $rate_guard ]] &&
          node --input-type=module -e 'const { createRateLimitLatch } = await import(process.argv[1]); const latch = createRateLimitLatch(); if (!latch.waits(process.argv[2])) process.exit(3); await latch.waitOut(process.argv[2], "GET");' \
            "$(realpath "$rate_guard")" "/repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/jobs"; then
          waited_out=1
          if [[ -z $(held_by) ]]; then
            failed=$((failed - 1))
            continue
          fi
        fi
        stop=$(api_budget_stop_until core)
        ((${stop:-0} - $(date +%s) <= window - waited)) || break
      fi
    fi
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
  [[ -z ${LANE_HOLD_MARKER:-} ]] || { mkdir -p "${LANE_HOLD_MARKER%/*}" && printf '%s %s\n' "${LANE_HOLD_MARKER##*/}" "${GITHUB_RUN_ID:-}" >"$LANE_HOLD_MARKER"; } || true
  exit 0
fi
echo "::error::handoff evidence for ${CALLS} still missing after $reads reads: $missing"
exit 1
