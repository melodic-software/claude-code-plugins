#!/usr/bin/env bash
# morning-brief.sh — read-only operator morning view for a GitHub repo.
#
# Prints, for the current repo, one scannable picture: open issue counts per
# queue label, the gh-native merge-ready PR list, parked decisions with their
# RECOMMENDED lines, loop-lane telemetry freshness (last-cycle age + flags),
# review findings stranded on already-merged PRs, and per lane workflow the last
# 7 days of runs: failures by class, limit stops, restarts and turn headroom,
# then model usage per activity and profile; last, what on GitHub or Azure is
# charging or could start charging.
#
# Read-only: it never mutates labels, comments, issues, PRs, or any GitHub or
# Azure setting. It runs `gh` read queries, plus `az` reads for the Azure cost
# lines when az is installed and logged in. The authoritative merge gate lives in the
# source-control:babysit-prs skill; the merge-ready list here is a lighter
# gh-native signal (mergeStateStatus CLEAN + non-draft) meant for a 5-second
# glance, not a substitute for that skill's classification. A clean PR whose
# head does not contain its base tip, or whose comparison was not read, carries
# an UNVERIFIED line.
#
# Owner/repo is derived from `gh repo view`, or from the checkout's `origin`
# remote when that call is unavailable; never hardcoded, so the tool is
# reusable across repos.
#
# Degraded-mode contract. Every section is one of three states: data, empty,
# or UNREADABLE. A section whose data source failed (a non-zero gh exit, or an
# error document in the body) renders as UNREADABLE with the error's first
# line, never with empty-state wording. A response the script cannot parse is
# a failed source too. The header counts the unreadable sections. The exit code
# tells "nothing to report" from "could not read": 5 when every section was
# unreadable, 6 when some were, 0 when none was. The cost section is one section
# of separate reads: a failed read is an UNREADABLE line beside the lines that
# did read, and the section counts as unreadable when any line is; it counts
# toward exit 5 only when none of its lines read anything.
#
# Caps. Every list read that carries a result cap prints a PARTIAL line when
# the result reaches the cap, so a truncated list never reads as the whole set.
#
# Stranded window. The stranded-findings read pages merged PRs newest-updated
# first and stops at the cutoff. The cutoff is the older of --stranded-days
# before now and a per-repo bookmark under the data dir; the bookmark advances
# to this run's --stranded-days floor only after the section was read in full,
# so a gap between runs never drops a merge out of the window.
#
# Transport. The gh subcommands ride GraphQL. When a GraphQL call is refused
# (the cloud GitHub proxy's HTTP 403 refusal), sections 1-4 are re-read from repository-scoped REST endpoints and
# the header names the transport. The stranded-findings section needs
# reviewThreads, which has no REST equivalent, so it renders UNREADABLE there.
#
# Usage:
#   morning-brief.sh                          live view of the current repo
#   morning-brief.sh --repo owner/name        target a specific repo
#   morning-brief.sh --telemetry-issue N      pin the lane-telemetry issue
#   morning-brief.sh --queue-labels A,B,C     pin the queue-label set (comma-separated)
#   morning-brief.sh --decision-label L       pin the parked-decision label
#   morning-brief.sh --stale-hours N          age past which a lane is STALE (default 6)
#   morning-brief.sh --stranded-days N        floor of the stranded-findings window, in days (default 3)
#   morning-brief.sh --data-dir DIR           base dir for the stranded bookmark (default $CLAUDE_PLUGIN_DATA
#                                             when it names harness-ops, else ~/.claude/plugins/data/harness-ops);
#                                             absolute, with no .. segment or control character
#   morning-brief.sh --rec-maxlen N           truncate RECOMMENDED previews (default 240; 0 = full)
#   morning-brief.sh --pr-limit N             cap on per-PR reads: REST merge state, and base freshness of clean PRs (default 50)
#   morning-brief.sh --lane-workflows A,B     pin the lane workflow files the lanes section reads
#   morning-brief.sh --lane-read-limit N      cap on lane runs whose job annotations are read (default 200)
#   morning-brief.sh --max-turns-hits N       max-turns hits per activity and profile above which
#                                             the lanes model-usage table prints RECOMMENDED (default: unset)
#   morning-brief.sh --org ORG                GitHub org whose billing the cost section reads
#                                             (default: the repo's owner)
#   morning-brief.sh --subscription ID        Azure subscription the cost section reads
#                                             (default: az's current one)
#   morning-brief.sh --actions-included-minutes N
#                                             Actions minutes the org's plan includes (default: unset)
#   morning-brief.sh --actions-included-storage-gb N
#                                             artifact storage the plan includes, in GB (default: unset)
#   morning-brief.sh --usage-alert-percent N  share of an included amount that is an ALERT (default 50)
#   morning-brief.sh --log-cap-alert-percent N
#                                             share of a workspace's daily cap that is an ALERT (default 50)
#   morning-brief.sh --forecast-alert N       budget forecast above which a budget is an ALERT
#                                             (default: the budget's own amount)
#   morning-brief.sh --required-budgets A,B   Azure budgets that must exist (default: none named)
#   morning-brief.sh --anomaly-alert NAME     the cost anomaly alert that must exist (default: any)
#   morning-brief.sh --expiry-days N          days before a budget or alert ends that are an ALERT
#                                             (default 30)
#   morning-brief.sh --allowed-collaborators A,B
#                                             direct collaborators besides org admins (default: none)
#   morning-brief.sh --workflow-read-limit N  cap on workflow files read for secret triggers (default 300)
#   morning-brief.sh --help
#
# Fixture flags (skip the network; used by the test suite and for reuse):
#   --now ISO                 fixed clock for deterministic staleness
#   --counts-json FILE        label->count object, e.g. {"status: ready":4}
#   --repo-labels-json FILE   array of label names (or {name} objects) for existence checks
#   --pr-json FILE            array as emitted by `gh pr list --json ...`
#   --behind-json FILE        object mapping a PR number to how many commits
#                             its head is behind its base, e.g. {"10":0,"13":4}
#                             (the compare reads of the merge-ready section)
#   --decisions-json FILE     array of {number,title,url,body,comments:[{body}]}
#   --telemetry-json FILE     array of {body} (the telemetry issue's comments)
#   --merged-json FILE        array of merged-PR GraphQL page documents, as
#                             emitted by `gh api graphql --paginate` (the
#                             stranded-findings section)
#   --lane-runs-json FILE     object mapping a workflow file name to its runs,
#                             each {id,html_url,event,display_title,head_sha,
#                             status,conclusion,created_at} (the lanes section)
#   --lane-annotations-json FILE
#                             object mapping a run id to the joined annotation
#                             messages of its jobs, plus an activity=<name>
#                             line per reusable-workflow job with annotations;
#                             a run absent from it was not read
#   --billing-usage-json FILE the org billing usage response ({usageItems})
#   --billing-budgets-json FILE
#                             the org billing budgets response ({budgets})
#   --azure-json FILE         object mapping each Azure read to its az output:
#                             account, budgets, pricings, defenderCost, activity,
#                             secureScores, advisorSecurity, advisorCost; no
#                             account means az is not logged in, and another
#                             absent key is a read that failed; also budgets
#                             and scheduledActions (the REST list responses),
#                             workspaces, and laUsage (workspace id -> query rows)
#   --org-scan-json FILE      the org scan: {admins:[login], repos:[{name,
#                             visibility, archived, collaborators:[login],
#                             workflows:[{path, text}]}], partial: N}
#
# Exit codes:
#   0  brief rendered, every section read
#   3  invalid argument
#   4  prerequisite missing (gh or jq), or repo could not be resolved
#   5  every section was unreadable; the brief carries no data
#   6  brief rendered, but at least one section was unreadable

# shellcheck disable=SC2329  # the per-section fetch functions are dispatched by name through gql_or_rest, which ShellCheck cannot follow
set -uo pipefail

# --- Queue labels (melodic-software defaults; overridable / filtered live) ------
DEFAULT_QUEUE_LABELS=(
  "needs-triage"
  "status: ready"
  "status: needs-decision"
  "needs-human"
)
DEFAULT_DECISION_LABEL="status: needs-decision"
QUEUE_LABELS=()
DECISION_LABEL=""
QUEUE_LABELS_ARG=""
DECISION_LABEL_ARG=""

REPO=""
REPO_SOURCE=""
TELEMETRY_ISSUE=""
REPO_LABELS_JSON=""
STALE_HOURS="6"
REC_MAXLEN="240"
PR_LIMIT="50"
NOW_ISO=""
COUNTS_JSON=""
PR_JSON=""
BEHIND_JSON=""
DECISIONS_JSON=""
TELEMETRY_JSON=""
MERGED_JSON=""
# The floor of the window for merged PRs still carrying unresolved review
# threads: wide enough to cover a bot that reviews well after a merge lands. A
# gap between runs is covered by the bookmark, not by this number.
STRANDED_DAYS="3"
DATA_DIR_ARG=""
LANE_RUNS_JSON=""
LANE_ANNOTATIONS_JSON=""
LANE_WORKFLOWS_ARG=""
# The workflows that run Claude in the melodic-software repos; live runs keep
# the ones that exist in the target repo.
DEFAULT_LANE_WORKFLOWS=(
  "intake-triage.yml"
  "pr-review-hosted.yml"
  "pr-review-security-hosted.yml"
  "pr-verify.yml"
  "pr-refine.yml"
  "pr-unblock.yml"
  "work-resolve-issue.yml"
)
LANE_DAYS=7
# Each read run costs one jobs read plus one annotations read per job.
LANE_READ_LIMIT=200
# Max-turns hits per activity and profile above which the model-usage table
# prints a RECOMMENDED line. Unset by default: no evidence yet sets a number.
MAX_TURNS_HITS=""
ORG_ARG=""
ORG_SCAN_JSON=""
ACTIONS_INCLUDED_MINUTES=""
ACTIONS_INCLUDED_STORAGE_GB=""
USAGE_ALERT_PERCENT=50
LOG_CAP_ALERT_PERCENT=50
FORECAST_ALERT=""
REQUIRED_BUDGETS_ARG=""
ANOMALY_ALERT=""
EXPIRY_DAYS=30
ALLOWED_COLLABORATORS_ARG=""
WORKFLOW_READ_LIMIT=300
SUBSCRIPTION_ARG=""
BILLING_USAGE_JSON=""
BILLING_BUDGETS_JSON=""
AZURE_JSON=""

# Result caps on the gh list reads. A result that reaches its cap prints PARTIAL.
LABEL_LIMIT=500
COUNT_LIMIT=1000
PR_LIST_LIMIT=200
DECISION_LIMIT=200
TELEMETRY_SEARCH_LIMIT=100

# Telemetry-issue discovery. The lanes skill's consumer posts to the issue this
# search finds, so the literal is shared verbatim with that script rather than
# through an import (the two skills install independently). The REST path
# derives its title tokens from the same literal: every token must appear.
TELEMETRY_SEARCH='loop-lane telemetry running per-lane status in:title'
read -ra TELEMETRY_TITLE_TOKENS <<<"${TELEMETRY_SEARCH% in:title}"

usage() {
  # Sentinel-based, not a hardcoded line range: prints every comment line after
  # the shebang up to the first non-comment (blank) line, so the header can
  # grow or shrink without silently truncating or over-running --help output.
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "${BASH_SOURCE[0]}"
  exit 0
}

require_value() {
  [[ -n "${2:-}" && "$2" != -* ]] || {
    printf 'morning-brief: %s requires an argument\n' "$1" >&2
    exit 3
  }
}

require_file() {
  [[ -f "$2" ]] || {
    printf 'morning-brief: %s file not found: %s\n' "$1" "$2" >&2
    exit 3
  }
}

# Same shape as require_value above, for the numeric flags. Callers then
# assign with `$((10#$2))`, which forces base-10 so a leading-zero value is not
# misread as octal (08 errors outright, 010 would evaluate as 8).
# A money or size amount: digits with an optional decimal part.
require_amount() {
  [[ "$2" =~ ^[0-9]+(\.[0-9]+)?$ ]] || {
    printf 'morning-brief: %s requires a non-negative number\n' "$1" >&2
    exit 3
  }
}

require_uint() {
  [[ "$2" =~ ^[0-9]+$ ]] || {
    printf 'morning-brief: %s requires a non-negative integer\n' "$1" >&2
    exit 3
  }
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo)
    require_value "$1" "${2:-}"
    REPO="$2"
    REPO_SOURCE="--repo"
    shift 2
    ;;
  --telemetry-issue)
    require_value "$1" "${2:-}"
    TELEMETRY_ISSUE="$2"
    shift 2
    ;;
  --queue-labels)
    require_value "$1" "${2:-}"
    QUEUE_LABELS_ARG="$2"
    shift 2
    ;;
  --decision-label)
    require_value "$1" "${2:-}"
    DECISION_LABEL_ARG="$2"
    shift 2
    ;;
  --repo-labels-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    REPO_LABELS_JSON="$2"
    shift 2
    ;;
  --stale-hours)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    STALE_HOURS="$((10#$2))"
    shift 2
    ;;
  --rec-maxlen)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    REC_MAXLEN="$((10#$2))"
    shift 2
    ;;
  --stranded-days)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    STRANDED_DAYS="$((10#$2))"
    shift 2
    ;;
  --data-dir)
    require_value "$1" "${2:-}"
    # The skill pre-approves this script with any arguments, so the one path it
    # writes under must be absolute and literal.
    abs_re='^(/|[A-Za-z]:[/\\])' dotdot_re='(^|[/\\])\.\.([/\\]|$)'
    [[ "$2" =~ $abs_re && ! "$2" =~ $dotdot_re && "$2" != *[[:cntrl:]]* ]] || {
      printf 'morning-brief: --data-dir must be an absolute path with no .. segment or control character\n' >&2
      exit 3
    }
    DATA_DIR_ARG="$2"
    shift 2
    ;;
  --pr-limit)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    PR_LIMIT="$((10#$2))"
    shift 2
    ;;
  --lane-workflows)
    require_value "$1" "${2:-}"
    LANE_WORKFLOWS_ARG="$2"
    shift 2
    ;;
  --lane-read-limit)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    LANE_READ_LIMIT="$((10#$2))"
    shift 2
    ;;
  --max-turns-hits)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    MAX_TURNS_HITS="$((10#$2))"
    shift 2
    ;;
  --lane-runs-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    LANE_RUNS_JSON="$2"
    shift 2
    ;;
  --lane-annotations-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    LANE_ANNOTATIONS_JSON="$2"
    shift 2
    ;;
  --org)
    require_value "$1" "${2:-}"
    ORG_ARG="$2"
    shift 2
    ;;
  --subscription)
    require_value "$1" "${2:-}"
    SUBSCRIPTION_ARG="$2"
    shift 2
    ;;
  --billing-usage-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    BILLING_USAGE_JSON="$2"
    shift 2
    ;;
  --billing-budgets-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    BILLING_BUDGETS_JSON="$2"
    shift 2
    ;;
  --org-scan-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    ORG_SCAN_JSON="$2"
    shift 2
    ;;
  --actions-included-minutes)
    require_value "$1" "${2:-}"
    require_amount "$1" "$2"
    ACTIONS_INCLUDED_MINUTES="$2"
    shift 2
    ;;
  --actions-included-storage-gb)
    require_value "$1" "${2:-}"
    require_amount "$1" "$2"
    ACTIONS_INCLUDED_STORAGE_GB="$2"
    shift 2
    ;;
  --usage-alert-percent)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    USAGE_ALERT_PERCENT="$((10#$2))"
    shift 2
    ;;
  --log-cap-alert-percent)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    LOG_CAP_ALERT_PERCENT="$((10#$2))"
    shift 2
    ;;
  --forecast-alert)
    require_value "$1" "${2:-}"
    require_amount "$1" "$2"
    FORECAST_ALERT="$2"
    shift 2
    ;;
  --required-budgets)
    require_value "$1" "${2:-}"
    REQUIRED_BUDGETS_ARG="$2"
    shift 2
    ;;
  --anomaly-alert)
    require_value "$1" "${2:-}"
    ANOMALY_ALERT="$2"
    shift 2
    ;;
  --expiry-days)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    EXPIRY_DAYS="$((10#$2))"
    shift 2
    ;;
  --allowed-collaborators)
    require_value "$1" "${2:-}"
    ALLOWED_COLLABORATORS_ARG="$2"
    shift 2
    ;;
  --workflow-read-limit)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    WORKFLOW_READ_LIMIT="$((10#$2))"
    shift 2
    ;;
  --azure-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    AZURE_JSON="$2"
    shift 2
    ;;
  --now)
    require_value "$1" "${2:-}"
    NOW_ISO="$2"
    shift 2
    ;;
  --counts-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    COUNTS_JSON="$2"
    shift 2
    ;;
  --pr-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    PR_JSON="$2"
    shift 2
    ;;
  --behind-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    BEHIND_JSON="$2"
    shift 2
    ;;
  --decisions-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    DECISIONS_JSON="$2"
    shift 2
    ;;
  --telemetry-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    TELEMETRY_JSON="$2"
    shift 2
    ;;
  --merged-json)
    require_value "$1" "${2:-}"
    require_file "$1" "$2"
    MERGED_JSON="$2"
    shift 2
    ;;
  -*)
    printf 'morning-brief: unknown flag %q (use --help)\n' "$1" >&2
    exit 3
    ;;
  *)
    printf 'morning-brief: unexpected argument %q\n' "$1" >&2
    exit 3
    ;;
  esac
done

have() { command -v "$1" >/dev/null 2>&1; }
have jq || {
  printf 'morning-brief: jq required\n' >&2
  exit 4
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ERR_FILE="$WORK/stderr"

# =============================================================================
# gh invocation and error detection
# =============================================================================
# Every gh call goes through gh_read so that a non-zero exit and an error
# document in the body are both surfaced to the caller as a failure. A caller
# that captures stdout and ignores the status turns an unread API into an empty
# result, which the rendering below would print as an all-clear; that is the
# fail-open this file is written to prevent.
#
# gh_read OUTFILE gh-args...   writes stdout to OUTFILE; returns 1 on failure
#                              with LAST_ERR set to the error's first line.
LAST_ERR=""
TRANSPORT="gh"

first_error_line() {
  local out="$1" err="$2" line=""
  line="$(grep -m1 -v '^[[:space:]]*$' "$err" 2>/dev/null)"
  [[ -n "$line" ]] || line="$(jq -r -s 'first(.[] | objects | (.errors[]?.message // .message // empty)) // empty' "$out" 2>/dev/null)"
  line="${line#gh: }"
  printf '%s' "$line"
}

# An error body is either a GraphQL document carrying `errors` (with or without
# a partial `data`), or GitHub's REST error shape: a bare object with `message`
# beside `documentation_url`. A commit or issue body that happens to contain a
# `message` field does not match, because those never carry documentation_url.
body_error() {
  jq -r -s '
    [ .. | objects
      | select(has("errors") or (has("message") and has("documentation_url")))
      | (.errors[]?.message // .message) ]
    | first // empty
  ' "$1" 2>/dev/null
}

gh_read() {
  local out="$1"
  shift
  LAST_ERR=""
  : >"$ERR_FILE"
  gh "$@" >"$out" 2>"$ERR_FILE"
  local rc=$?
  if ((rc != 0)); then
    LAST_ERR="$(first_error_line "$out" "$ERR_FILE")"
    [[ -n "$LAST_ERR" ]] || LAST_ERR="gh exited $rc"
    return 1
  fi
  local body_err
  body_err="$(body_error "$out")"
  if [[ -n "$body_err" ]]; then
    LAST_ERR="$body_err"
    return 1
  fi
  return 0
}

# The cloud GitHub proxy's GraphQL refusal (see the record in SKILL.md);
# REST is the fallback.
graphql_blocked() {
  grep -qi 'GraphQL is not available from Claude Code sessions' <<<"$1"
}

# gql_or_rest OUTFILE gql_fn rest_fn
# Runs gql_fn unless the transport already switched to REST. When gql_fn fails
# with the blocked shape, switches the transport for the rest of the run and
# runs rest_fn. Any other failure propagates with LAST_ERR intact.
gql_or_rest() {
  local out="$1" gql_fn="$2" rest_fn="$3"
  if [[ "$TRANSPORT" == "gh" ]]; then
    "$gql_fn" "$out" && return 0
    graphql_blocked "$LAST_ERR" || return 1
    TRANSPORT="rest"
  fi
  "$rest_fn" "$out"
}

urlencode() { jq -rn --arg s "$1" '$s | @uri'; }

# gh api --paginate emits one JSON document per page. For REST array endpoints
# that is a sequence of arrays; flatten them into one array in OUTFILE.
rest_paginate_array() {
  local out="$1"
  shift
  gh_read "$WORK/page" api --paginate "$@" || return 1
  jq -s '[ .[][] ]' "$WORK/page" >"$out" 2>/dev/null || {
    LAST_ERR="could not parse REST response"
    return 1
  }
}

# gh is only needed for live sources; a fully fixtured run (tests) must not
# require it. Demand it only when at least one section will hit the network.
NEEDS_LIVE_COUNTS=0
NEEDS_LIVE_PRS=0
NEEDS_LIVE_DECISIONS=0
NEEDS_LIVE_TELEMETRY=0
NEEDS_LIVE_MERGED=0
[[ -z "$COUNTS_JSON" ]] && NEEDS_LIVE_COUNTS=1
[[ -z "$PR_JSON" ]] && NEEDS_LIVE_PRS=1
[[ -z "$DECISIONS_JSON" ]] && NEEDS_LIVE_DECISIONS=1
[[ -z "$TELEMETRY_JSON" ]] && NEEDS_LIVE_TELEMETRY=1
[[ -z "$MERGED_JSON" ]] && NEEDS_LIVE_MERGED=1

# --- Repo label inventory -------------------------------------------------------
# An inventory that reached its cap cannot prove a label absent, so it is
# reported as unavailable: the callers then show every configured label instead
# of dropping one that sits past the cap.
LABELS_CAPPED=0
fetch_repo_labels_gql() {
  gh_read "$WORK/labels.raw" label list "${REPO_ARGS[@]}" --limit "$LABEL_LIMIT" --json name -q '.[].name' || return 1
  tr -d '\r' <"$WORK/labels.raw" | jq -R -s 'split("\n") | map(select(length > 0))' >"$WORK/labels.all" || {
    LAST_ERR="could not parse the label list"
    return 1
  }
  if (($(jq 'length' "$WORK/labels.all") >= LABEL_LIMIT)); then
    LABELS_CAPPED=1
    LAST_ERR="label inventory reached its $LABEL_LIMIT-label cap"
    return 1
  fi
  jq 'unique' "$WORK/labels.all" >"$1"
}

fetch_repo_labels_rest() {
  rest_paginate_array "$WORK/labels.rest" "repos/$REPO/labels?per_page=100" || return 1
  jq '[ .[].name ] | unique' "$WORK/labels.rest" >"$1"
}

# fetch_repo_label_names OUTFILE: a JSON array of label names, or 1.
fetch_repo_label_names() {
  local out="$1"
  if [[ -n "$REPO_LABELS_JSON" ]]; then
    jq -e 'type == "array"' "$REPO_LABELS_JSON" >/dev/null 2>&1 || {
      LAST_ERR="--repo-labels-json is not an array"
      return 1
    }
    jq '[ .[] | if type == "string" then . else .name end ] | unique' "$REPO_LABELS_JSON" >"$out" 2>/dev/null || {
      LAST_ERR="--repo-labels-json could not be parsed"
      return 1
    }
    return 0
  fi
  [[ -n "$REPO" ]] || {
    LAST_ERR="no repo resolved"
    return 1
  }
  gql_or_rest "$out" fetch_repo_labels_gql fetch_repo_labels_rest
}

label_exists_in_repo() {
  local label="$1" names_file="$2"
  jq -e --arg l "$label" 'index($l) != null' "$names_file" >/dev/null 2>&1
}

# Parked-decisions can short-circuit on a fixture label inventory when the
# decision label is absent — no gh issue list needed for that probe.
if ((NEEDS_LIVE_DECISIONS)) && [[ -n "$REPO_LABELS_JSON" ]]; then
  _probe_decision_label="${DECISION_LABEL_ARG:-$DEFAULT_DECISION_LABEL}"
  if fetch_repo_label_names "$WORK/probe-labels.json"; then
    label_exists_in_repo "$_probe_decision_label" "$WORK/probe-labels.json" || NEEDS_LIVE_DECISIONS=0
  fi
fi
# The stranded section alone never forces a repo resolution: every other
# section can be driven from fixtures, and a fixture-only run must not reach
# for the network just to resolve a repo it was not given. With --repo, or once
# another live section resolves one, the section is live like the rest.
ANY_LIVE=$((NEEDS_LIVE_COUNTS || NEEDS_LIVE_PRS || NEEDS_LIVE_DECISIONS || NEEDS_LIVE_TELEMETRY || (NEEDS_LIVE_MERGED && ${#REPO} > 0)))
if ((ANY_LIVE)) && ! have gh; then
  printf 'morning-brief: gh required for live queries (pass fixtures to run offline)\n' >&2
  exit 4
fi

# --- Resolve the target repo --------------------------------------------------
# `gh repo view` first (the checkout's default remote as gh sees it). When that
# call is unavailable, the `origin` remote of the current checkout is the same
# derivation without the network round-trip.
repo_from_git_remote() {
  local url
  url="$(git remote get-url origin 2>/dev/null | tr -d '\r')" || return 1
  [[ -n "$url" ]] || return 1
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
  *github.com[:/]*)
    url="${url##*github.com[:/]}"
    ;;
  *) return 1 ;;
  esac
  [[ "$url" == */* && "$url" != */*/* ]] || return 1
  printf '%s' "$url"
}

if [[ -z "$REPO" ]] && ((ANY_LIVE)); then
  if gh_read "$WORK/repo" repo view --json nameWithOwner -q .nameWithOwner; then
    REPO="$(tr -d '\r' <"$WORK/repo")"
    REPO_SOURCE="gh repo view"
  fi
  if [[ -z "$REPO" ]]; then
    graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
    if REPO="$(repo_from_git_remote)"; then
      REPO_SOURCE="git remote"
    else
      printf 'morning-brief: could not resolve owner/repo (run inside a checkout with a GitHub origin remote, or pass --repo)\n' >&2
      [[ -n "$LAST_ERR" ]] && printf 'morning-brief: gh repo view: %s\n' "$LAST_ERR" >&2
      exit 4
    fi
  fi
fi
REPO_ARGS=()
[[ -n "$REPO" ]] && REPO_ARGS=(--repo "$REPO")
[[ -n "$REPO" ]] || NEEDS_LIVE_MERGED=0

# --- Portable date handling ---------------------------------------------------
# GNU `date -d` and BSD/macOS `date -j -f` are mutually exclusive dialects, and
# Claude Code commonly runs on macOS. to_epoch/from_epoch try GNU first (Linux,
# most CI) then BSD, so a timestamp parses on either platform. On the BSD branch
# the literal `Z` is matched by strptime as a plain character (not `%Z`), so the
# parsed value is timezone-naive; TZ=UTC forces it to UTC, matching how GNU
# reads the `Z`-suffixed telemetry stamps. Only time-bearing formats are tried:
# a bare `%Y-%m-%d` would prefix-match a malformed stamp and yield a wrong
# midnight instead of leaving it unparsable.
to_epoch() {
  local s="$1" e fmt
  # portability-ok: GNU-first of the dual-dialect ladder documented above (BSD
  # `date -j -f` fallback follows in the loop below, cross-statement so the
  # gate's same-line guard shape does not cover it — #1510).
  e="$(date -u -d "$s" +%s 2>/dev/null)" && {
    printf '%s' "$e"
    return
  }
  for fmt in '%Y-%m-%dT%H:%MZ' '%Y-%m-%dT%H:%M:%SZ' '%Y-%m-%dT%H:%M:%S' '%Y-%m-%dT%H:%M'; do
    e="$(TZ=UTC date -j -f "$fmt" "$s" +%s 2>/dev/null)" && {
      printf '%s' "$e"
      return
    }
  done
}

from_epoch() {
  local e="$1" out
  # portability-ok: GNU-first of the dual-dialect ladder documented above (BSD
  # `date -u -r` fallback follows immediately below, cross-statement so the
  # gate's same-line guard shape does not cover it — #1510).
  out="$(date -u -d "@$e" '+%Y-%m-%dT%H:%MZ' 2>/dev/null)" && {
    printf '%s' "$out"
    return
  }
  out="$(date -u -r "$e" '+%Y-%m-%dT%H:%MZ' 2>/dev/null)" && {
    printf '%s' "$out"
    return
  }
  date -u '+%Y-%m-%dT%H:%MZ'
}

# Every date stamp the brief prints names its zone: the stamps are UTC (a `Z`
# stamp is, and the clock is read with `date -u`), while a scheduler's own zone
# differs (an Actions cron fires in UTC, `/loop` uses the machine's). The
# bookmark file keeps the bare form `from_epoch` renders, so it stays parseable.
utc_stamp() { printf '%s UTC' "$(from_epoch "$1")"; }

# --- Clock --------------------------------------------------------------------
if [[ -n "$NOW_ISO" ]]; then
  NOW_EPOCH="$(to_epoch "$NOW_ISO")"
  [[ -n "$NOW_EPOCH" ]] || {
    printf 'morning-brief: could not parse --now value: %s\n' "$NOW_ISO" >&2
    exit 3
  }
else
  NOW_EPOCH="$(date -u +%s)"
fi

# Render a non-negative second-delta as a compact age (e.g. "2d 3h", "5h 12m",
# "8m"). A negative delta (clock skew / future stamp) renders as "future".
fmt_age() {
  local secs="$1"
  if ((secs < 0)); then
    printf 'future'
    return
  fi
  local d=$((secs / 86400)) h=$(((secs % 86400) / 3600)) m=$(((secs % 3600) / 60))
  if ((d > 0)); then
    printf '%dd %dh' "$d" "$h"
  elif ((h > 0)); then
    printf '%dh %dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# --- Queue label resolution ---------------------------------------------------
# Defaults match melodic-software's taxonomy. Live runs filter to labels that
# actually exist in the target repo so a consuming repo with a different scheme
# does not render misleading rows. Pass --queue-labels / --decision-label to
# pin a custom set (same spirit as --telemetry-issue).
resolve_queue_labels() {
  QUEUE_LABELS=()
  if [[ -n "$QUEUE_LABELS_ARG" ]]; then
    local part _parts
    IFS=',' read -ra _parts <<<"$QUEUE_LABELS_ARG"
    for part in "${_parts[@]}"; do
      part="${part#"${part%%[![:space:]]*}"}"
      part="${part%"${part##*[![:space:]]}"}"
      [[ -n "$part" ]] && QUEUE_LABELS+=("$part")
    done
  else
    QUEUE_LABELS=("${DEFAULT_QUEUE_LABELS[@]}")
  fi
}

resolve_decision_label() {
  DECISION_LABEL="${DECISION_LABEL_ARG:-$DEFAULT_DECISION_LABEL}"
}

resolve_queue_labels
resolve_decision_label

# --- Section state ---------------------------------------------------------
# Sections render into files so the header, printed first, can carry the
# unreadable count.
SECTIONS_TOTAL=7
UNREADABLE=0
UNREADABLE_NAMES=()

unreadable() {
  # unreadable <section-name> <error>
  UNREADABLE=$((UNREADABLE + 1))
  UNREADABLE_NAMES+=("$1")
  echo "  UNREADABLE: ${2:-data source failed}"
  echo
}

# =============================================================================
# Section 1 — queue label counts
# =============================================================================
count_label_gql() {
  # count_label_gql OUTFILE label
  gh_read "$WORK/count.raw" issue list "${REPO_ARGS[@]}" --state open --label "$2" \
    --limit "$COUNT_LIMIT" --json number -q 'length' || return 1
  tr -d '\r' <"$WORK/count.raw" >"$1"
}

count_label_rest() {
  # The issues endpoint also lists pull requests; exclude those so the count
  # matches what `gh issue list` reports.
  rest_paginate_array "$WORK/count.rest" \
    "repos/$REPO/issues?state=open&per_page=100&labels=$(urlencode "$2")" || return 1
  jq '[ .[] | select(has("pull_request") | not) ] | length' "$WORK/count.rest" >"$1"
}

print_queues() {
  echo "== Queues (open issues per label) =="
  local labels_to_show=() label n labels_available=0
  # The inventory only narrows the rows to labels that exist. When it cannot be
  # read, the counts below still decide whether the section is readable.
  if [[ -n "$REPO_LABELS_JSON" || (-z "$COUNTS_JSON" && -n "$REPO") ]]; then
    if fetch_repo_label_names "$WORK/labels.json"; then
      labels_available=1
    fi
  fi
  if ((labels_available)); then
    for label in "${QUEUE_LABELS[@]}"; do
      label_exists_in_repo "$label" "$WORK/labels.json" && labels_to_show+=("$label")
    done
    if ((${#labels_to_show[@]} == 0)); then
      echo "  no queue labels found in this repo (nothing to report)"
      if [[ -z "$QUEUE_LABELS_ARG" ]]; then
        echo "  defaults: ${DEFAULT_QUEUE_LABELS[*]} — pass --queue-labels to customize"
      else
        echo "  pinned: ${QUEUE_LABELS[*]}"
      fi
      echo
      return
    fi
  else
    labels_to_show=("${QUEUE_LABELS[@]}")
  fi
  local rows=() capped=() via_list
  for label in "${labels_to_show[@]}"; do
    via_list=0
    if [[ -n "$COUNTS_JSON" ]]; then
      n="$(jq -r --arg l "$label" 'if type == "object" then (.[$l] // 0) else 0 end' "$COUNTS_JSON" 2>/dev/null)"
    else
      if [[ "$TRANSPORT" == "gh" ]]; then
        if count_label_gql "$WORK/count" "$label"; then
          via_list=1
        elif graphql_blocked "$LAST_ERR"; then
          TRANSPORT="rest"
        else
          unreadable queues "$label: $LAST_ERR"
          return
        fi
      fi
      if [[ "$TRANSPORT" == "rest" ]]; then
        count_label_rest "$WORK/count" "$label" || {
          unreadable queues "$label: $LAST_ERR"
          return
        }
      fi
      n="$(cat "$WORK/count")"
    fi
    [[ "$n" =~ ^[0-9]+$ ]] || {
      unreadable queues "$label: count not numeric"
      return
    }
    if ((via_list && n >= COUNT_LIMIT)); then
      capped+=("$label")
      n="$n+"
    fi
    rows+=("$(printf '  %-24s %s' "$label" "$n")")
  done
  printf '%s\n' "${rows[@]}"
  ((LABELS_CAPPED)) && echo "  PARTIAL: the label inventory reached its $LABEL_LIMIT-label cap; rows are not filtered to labels that exist"
  if ((${#capped[@]} > 0)); then
    label="$(printf '%s, ' "${capped[@]}")"
    echo "  PARTIAL: ${label%, }: count reached the $COUNT_LIMIT-issue read cap; the true count may be higher"
  fi
  echo
}

# =============================================================================
# Section 2 — merge-ready PRs (gh-native: non-draft + mergeStateStatus CLEAN)
# =============================================================================
PR_PARTIAL=()
fetch_prs_gql() {
  gh_read "$1" pr list "${REPO_ARGS[@]}" --state open --limit "$PR_LIST_LIMIT" \
    --json number,title,url,isDraft,mergeStateStatus,reviewDecision,baseRefName,headRefOid || return 1
  local n
  n="$(jq -e 'length' "$1" 2>/dev/null)" || {
    LAST_ERR="could not parse the PR list"
    return 1
  }
  ((n >= PR_LIST_LIMIT)) && PR_PARTIAL+=("the open-PR list reached its $PR_LIST_LIMIT-PR read cap; a clean PR past it is not shown")
  return 0
}

# A REST pull carries `mergeable: null` (and `mergeable_state: "unknown"`) while
# GitHub is still computing mergeability in the background; the documented
# remedy is to resubmit the request after giving the job time. One retry per
# batch, after MERGE_STATE_RETRY_SECS, then any PR still uncomputed is reported
# as inconclusive rather than rendered as "not clean".
MERGE_STATE_RETRY_SECS="${MORNING_BRIEF_MERGE_STATE_RETRY_SECS:-2}"

merge_state_uncomputed() {
  jq -e '(.mergeable == null) or ((.mergeable_state // "unknown") == "unknown")' "$1" >/dev/null 2>&1
}

fetch_prs_rest() {
  # The list endpoint carries no merge state; each PR costs one more GET for
  # `mergeable_state`, so the read is capped. A capped read is reported as
  # partial rather than rendered as the whole queue.
  local out="$1" total i number numbers=() retry=() uncomputed=()
  rest_paginate_array "$WORK/prs.rest" "repos/$REPO/pulls?state=open&per_page=100" || return 1
  total="$(jq 'length' "$WORK/prs.rest")"
  PR_PARTIAL=()
  ((total > PR_LIMIT)) && PR_PARTIAL+=("$total open PRs; merge state read for the first $PR_LIMIT only (raise --pr-limit)")
  : >"$WORK/prs.detail"
  for ((i = 0; i < total && i < PR_LIMIT; i++)); do
    number="$(jq -r ".[$i].number" "$WORK/prs.rest")"
    numbers+=("$number")
    gh_read "$WORK/pr.$number" api "repos/$REPO/pulls/$number" || return 1
    merge_state_uncomputed "$WORK/pr.$number" && retry+=("$number")
  done
  if ((${#retry[@]} > 0)); then
    sleep "$MERGE_STATE_RETRY_SECS"
    for number in "${retry[@]}"; do
      gh_read "$WORK/pr.$number" api "repos/$REPO/pulls/$number" || return 1
      merge_state_uncomputed "$WORK/pr.$number" && uncomputed+=("#$number")
    done
  fi
  # After the retry pass, so a re-read pull replaces its first response.
  for number in "${numbers[@]}"; do
    cat "$WORK/pr.$number" >>"$WORK/prs.detail"
  done
  if ((${#uncomputed[@]} > 0)); then
    PR_PARTIAL+=("merge state not yet computed by GitHub for ${uncomputed[*]}; inconclusive, re-run shortly")
  fi
  # The REST pull schema carries no review-decision field; the REST path
  # reports it as n/a.
  jq -s '[ .[] | {number, title, url: .html_url, isDraft: .draft,
                  mergeStateStatus: ((.mergeable_state // "unknown") | ascii_upcase),
                  reviewDecision: "n/a", baseRefName: .base.ref, headRefOid: .head.sha} ]' "$WORK/prs.detail" >"$out"
}

# A clean PR counts as verified only when its head contains the base tip
# (SKILL.md carries the upstream record). The compare endpoint's `behind_by`
# decides: 0 prints nothing; a positive count, or a read that failed, prints
# why the PR's CLEAN is unverified.
#
# freshness_note NUMBER BASE HEAD_SHA
freshness_note() {
  local number="$1" base="$2" sha="$3" behind=""
  if [[ -z "$base" || ! "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'base freshness unread: the PR record names no base branch or head commit'
    return
  fi
  if [[ -n "$BEHIND_JSON" ]]; then
    behind="$(jq -r --arg n "$number" '.[$n] // empty' "$BEHIND_JSON" 2>/dev/null)"
  elif [[ -n "$PR_JSON" ]]; then
    printf 'base freshness unread: --pr-json given without --behind-json'
    return
  elif gh_read "$WORK/compare" api "repos/$REPO/compare/$(urlencode "$base")...$sha?per_page=1"; then
    behind="$(jq -r '.behind_by // empty' "$WORK/compare" 2>/dev/null)"
  else
    printf 'base freshness unread: %s' "$LAST_ERR"
    return
  fi
  if [[ ! "$behind" =~ ^[0-9]+$ ]]; then
    printf 'base freshness unread: no behind count for #%s' "$number"
  elif ((behind > 0)); then
    printf 'head is %s commit(s) behind %s; checks may predate the current base' "$behind" "$base"
  fi
}

print_merge_ready() {
  echo "== Merge-ready PRs (non-draft, mergeStateStatus=CLEAN) =="
  local prs_file="$WORK/prs.json"
  if [[ -n "$PR_JSON" ]]; then
    prs_file="$PR_JSON"
  else
    gql_or_rest "$prs_file" fetch_prs_gql fetch_prs_rest || {
      unreadable merge-ready "$LAST_ERR"
      return
    }
  fi
  jq -e 'type == "array"' "$prs_file" >/dev/null 2>&1 || {
    unreadable merge-ready "could not parse the PR list"
    return
  }
  local clean='[ .[] | select(.isDraft == false and .mergeStateStatus == "CLEAN") ] | sort_by(.number) | .[]'
  local notes='{}' number base sha note ready read=0
  # One compare GET per clean PR, so the reads share the --pr-limit cap; a PR
  # past it is UNVERIFIED, and the section says the read was partial.
  # stdin from /dev/null so gh cannot drain the loop's input.
  while IFS=$'\t' read -r number base sha; do
    if ((read < PR_LIMIT)); then
      note="$(freshness_note "$number" "$base" "$sha" </dev/null)"
    else
      note="base freshness unread: compare reads capped at $PR_LIMIT (raise --pr-limit)"
    fi
    ((++read))
    [[ -n "$note" ]] && notes="$(jq -c --arg n "$number" --arg v "$note" '.[$n] = $v' <<<"$notes")"
  done < <(jq -r "$clean"' | [.number, (.baseRefName // ""), (.headRefOid // "")] | @tsv' "$prs_file" 2>/dev/null)
  ((read > PR_LIMIT)) && PR_PARTIAL+=("$read clean PRs; base freshness read for the first $PR_LIMIT only (raise --pr-limit)")
  ready="$(jq -r --argjson notes "$notes" "$clean"'
    | "  #\(.number) \(.title)\n    \(.url)  review=\(.reviewDecision // "" | if . == "" then "none" else . end)"
      + ($notes[.number | tostring] | if . then "\n    UNVERIFIED: \(.)" else "" end)
  ' "$prs_file" 2>/dev/null)" || {
    unreadable merge-ready "could not parse the PR list"
    return
  }
  if [[ -n "$ready" ]]; then
    echo "$ready"
  else
    echo "  (none clean right now)"
  fi
  local note
  for note in "${PR_PARTIAL[@]}"; do
    echo "  PARTIAL: $note"
  done
  echo "  authoritative merge gate: /source-control:babysit-prs"
  echo
}

# =============================================================================
# Section 3 — parked decisions (needs-decision) with their RECOMMENDED line
# =============================================================================
fetch_decisions_gql() {
  # One call returns body + comments for every decision issue -- no N+1
  # hydration loop (which also avoids `gh` draining a while-read loop's stdin).
  gh_read "$1" issue list "${REPO_ARGS[@]}" --state open --label "$DECISION_LABEL" \
    --limit "$DECISION_LIMIT" --json number,title,url,body,comments || return 1
  local n
  n="$(jq -e 'length' "$1" 2>/dev/null)" || {
    LAST_ERR="could not parse the decision issues"
    return 1
  }
  ((n >= DECISION_LIMIT)) && DECISIONS_PARTIAL=1
  return 0
}

DECISIONS_PARTIAL=0
fetch_decisions_rest() {
  local out="$1" total i number
  rest_paginate_array "$WORK/dec.rest" \
    "repos/$REPO/issues?state=open&per_page=100&labels=$(urlencode "$DECISION_LABEL")" || return 1
  jq '[ .[] | select(has("pull_request") | not) ]' "$WORK/dec.rest" >"$WORK/dec.all"
  (($(jq 'length' "$WORK/dec.all") > DECISION_LIMIT)) && DECISIONS_PARTIAL=1
  jq --argjson lim "$DECISION_LIMIT" '.[:$lim]' "$WORK/dec.all" >"$WORK/dec.issues"
  total="$(jq 'length' "$WORK/dec.issues")"
  : >"$WORK/dec.detail"
  for ((i = 0; i < total; i++)); do
    number="$(jq -r ".[$i].number" "$WORK/dec.issues")"
    rest_paginate_array "$WORK/dec.comments" "repos/$REPO/issues/$number/comments?per_page=100" || return 1
    jq -c --slurpfile c "$WORK/dec.comments" ".[$i] | {number, title, url: .html_url, body, comments: (\$c[0] | map({body}))}" \
      "$WORK/dec.issues" >>"$WORK/dec.detail"
  done
  jq -s '.' "$WORK/dec.detail" >"$out"
}

print_decisions() {
  echo "== Parked decisions (${DECISION_LABEL}) with RECOMMENDED lines =="
  local decisions_file="$WORK/decisions.json"
  # An unreadable inventory does not decide this section; the decision read
  # below carries its own error if it fails.
  if [[ -z "$DECISIONS_JSON" && (-n "$REPO" || -n "$REPO_LABELS_JSON") ]]; then
    if fetch_repo_label_names "$WORK/labels.json" &&
      ! label_exists_in_repo "$DECISION_LABEL" "$WORK/labels.json"; then
      echo "  (decision label not found in this repo — pass --decision-label to customize)"
      echo
      return
    fi
  fi
  if [[ -n "$DECISIONS_JSON" ]]; then
    decisions_file="$DECISIONS_JSON"
  else
    gql_or_rest "$decisions_file" fetch_decisions_gql fetch_decisions_rest || {
      unreadable decisions "$LAST_ERR"
      return
    }
  fi

  local count
  count="$(jq -r 'if type == "array" then length else error("not a list") end' "$decisions_file" 2>/dev/null)" || {
    unreadable decisions "could not parse the decision issues"
    return
  }
  if ((count == 0)); then
    echo "  (none parked)"
    echo
    return
  fi

  local i number title url rec
  for ((i = 0; i < count; i++)); do
    number="$(jq -r ".[$i].number" "$decisions_file")"
    title="$(jq -r ".[$i].title" "$decisions_file")"
    url="$(jq -r ".[$i].url // \"\"" "$decisions_file")"
    # RECOMMENDED marker across the body and every comment. Two-tier so the
    # deliberate uppercase marker wins over an incidental lowercase mention
    # (e.g. "not recommended"): tier 1 = the uppercase RECOMMENDED token, tier 2
    # = a case-insensitive fallback. BOTH tiers require a LABELED marker —
    # RECOMMENDED immediately followed (past optional bold/space) by a
    # `:`/`-`/em-dash separator — not mere presence. That separator is the
    # discriminator on each tier independently: it accepts a real marker whether
    # at line start or mid-line ("After review, RECOMMENDED: ...") while
    # rejecting negated prose ("... is NOT RECOMMENDED because ...", "not
    # recommended for ..."), where the token is followed by a word, not a
    # separator. Anchoring to line start instead would wrongly drop the
    # legitimate mid-line marker form.
    local combined marker_re
    marker_re='RECOMMENDED[[:space:]]*\**[[:space:]]*[-:—]'
    combined="$(jq -r ".[$i] | (.body // \"\") + \"\n\" + ((.comments // []) | map(.body // \"\") | join(\"\n\"))" \
      "$decisions_file")"
    rec="$(grep -am1 -E "$marker_re" <<<"$combined")"
    [[ -n "$rec" ]] || rec="$(grep -iam1 -E "$marker_re" <<<"$combined")"
    # Strip leading list bullets / enumeration / blockquote / bold so the line reads clean.
    rec="$(sed -E 's/^[[:space:]]*//; s/^[0-9]+[.)][[:space:]]*//; s/^[-*>|#[:space:]]*//; s/\*\*//g; s/[[:space:]]*$//' <<<"$rec")"
    # Drop a leading RECOMMENDED/recommended token + its separator: the section
    # already labels the line, so keeping it would double-print "RECOMMENDED: RECOMMENDED —".
    if [[ "$rec" == RECOMMENDED* || "$rec" == recommended* ]]; then
      rec="${rec#RECOMMENDED}"
      rec="${rec#recommended}"
      rec="$(sed -E 's/^([[:space:]]|[-:—])*//' <<<"$rec")"
    fi
    # Truncate to a scannable preview (0 = never truncate); the URL above
    # carries the full text for anyone who wants it.
    if [[ "$REC_MAXLEN" != "0" && -n "$rec" && "${#rec}" -gt "$REC_MAXLEN" ]]; then
      rec="${rec:0:$REC_MAXLEN}…"
    fi
    printf '  #%s %s\n' "$number" "$title"
    [[ -n "$url" ]] && printf '    %s\n' "$url"
    if [[ -n "$rec" ]]; then
      printf '    RECOMMENDED: %s\n' "$rec"
    else
      printf '    (no RECOMMENDED line found)\n'
    fi
  done
  ((DECISIONS_PARTIAL)) && echo "  PARTIAL: the decision list reached its $DECISION_LIMIT-issue read cap; an issue past it is not shown"
  echo
}

# =============================================================================
# Section 4 — loop-lane telemetry freshness (per-lane telemetry-issue comments)
# =============================================================================
TELEMETRY_PARTIAL=0
find_telemetry_issue_gql() {
  gh_read "$WORK/tel.raw" issue list "${REPO_ARGS[@]}" --state open \
    --search "$TELEMETRY_SEARCH" --limit "$TELEMETRY_SEARCH_LIMIT" --json number || return 1
  local n
  n="$(jq -e 'length' "$WORK/tel.raw" 2>/dev/null)" || {
    LAST_ERR="could not parse the issue search"
    return 1
  }
  ((n >= TELEMETRY_SEARCH_LIMIT)) && TELEMETRY_PARTIAL=1
  jq -r 'sort_by(.number) | .[0].number // empty' "$WORK/tel.raw" >"$1"
}

find_telemetry_issue_rest() {
  rest_paginate_array "$WORK/tel.rest" "repos/$REPO/issues?state=open&per_page=100" || return 1
  jq -r --argjson tokens "$(printf '%s\n' "${TELEMETRY_TITLE_TOKENS[@]}" | jq -R . | jq -s .)" '
    [ .[] | select(has("pull_request") | not)
      | select(.title as $t | $tokens | all(. as $tok | ($t | ascii_downcase | contains($tok))))
      | .number ]
    | sort | .[0] // empty
  ' "$WORK/tel.rest" >"$1"
}

fetch_telemetry_comments_gql() {
  gh_read "$1" issue view "$TELEMETRY_ISSUE_RESOLVED" "${REPO_ARGS[@]}" --json comments -q '.comments'
}

fetch_telemetry_comments_rest() {
  rest_paginate_array "$WORK/telc.rest" "repos/$REPO/issues/$TELEMETRY_ISSUE_RESOLVED/comments?per_page=100" || return 1
  jq 'map({body})' "$WORK/telc.rest" >"$1"
}

TELEMETRY_ISSUE_RESOLVED=""
print_telemetry() {
  echo "== Lane telemetry freshness (last-cycle age + flags) =="
  local comments_file="$WORK/telemetry.json"
  if [[ -n "$TELEMETRY_JSON" ]]; then
    comments_file="$TELEMETRY_JSON"
  else
    if [[ -n "$TELEMETRY_ISSUE" ]]; then
      TELEMETRY_ISSUE_RESOLVED="$TELEMETRY_ISSUE"
    else
      gql_or_rest "$WORK/tel.issue" find_telemetry_issue_gql find_telemetry_issue_rest || {
        unreadable telemetry "issue search: $LAST_ERR"
        return
      }
      TELEMETRY_ISSUE_RESOLVED="$(tr -d '[:space:]' <"$WORK/tel.issue")"
    fi
    if [[ -z "$TELEMETRY_ISSUE_RESOLVED" ]]; then
      echo "  no telemetry issue found (nothing to report)"
      echo
      return
    fi
    gql_or_rest "$comments_file" fetch_telemetry_comments_gql fetch_telemetry_comments_rest || {
      unreadable telemetry "issue #$TELEMETRY_ISSUE_RESOLVED: $LAST_ERR"
      return
    }
    echo "  source: issue #$TELEMETRY_ISSUE_RESOLVED"
  fi
  local comments
  comments="$(cat "$comments_file")"
  if [[ -z "$comments" || "$comments" == "null" ]]; then
    echo "  no telemetry issue found (nothing to report)"
    echo
    return
  fi

  # A lane comment opens with the lane-telemetry sentinel and carries a `lane:`
  # field. For each, pull lane, last-cycle, flags.
  local n
  n="$(jq -r 'if type == "array" then length else error("not a list") end' <<<"$comments" 2>/dev/null)" || {
    unreadable telemetry "could not parse the telemetry comments"
    return
  }
  ((TELEMETRY_PARTIAL)) && echo "  PARTIAL: the telemetry issue search reached its $TELEMETRY_SEARCH_LIMIT-issue cap; the oldest match may lie past it"
  local i body lane last flags any=0
  for ((i = 0; i < n; i++)); do
    body="$(jq -r ".[$i].body // \"\"" <<<"$comments" 2>/dev/null)"
    [[ "$body" == "<!-- harness-ops:lane-telemetry marker="* ]] || continue
    lane="$(grep -im1 -oE '(^|[^a-z])lane:[[:space:]]*[a-z0-9_-]+' <<<"$body" | sed -E 's/.*lane:[[:space:]]*//')"
    [[ -n "$lane" ]] || continue
    any=1
    last="$(grep -im1 'last-cycle:' <<<"$body" | sed -E 's/.*last-cycle:[[:space:]]*//; s/[[:space:]].*$//; s/[[:space:]]*$//')"
    flags="$(grep -im1 'flags:' <<<"$body" | sed -E 's/.*flags:[[:space:]]*//; s/[[:space:]]*$//')"

    local age_note=""
    if [[ -n "$last" ]]; then
      local then_epoch
      then_epoch="$(to_epoch "$last")"
      if [[ -n "$then_epoch" ]]; then
        local delta=$((NOW_EPOCH - then_epoch))
        age_note="$(fmt_age "$delta")"
        if ((delta > STALE_HOURS * 3600)); then
          age_note="$age_note  STALE (>${STALE_HOURS}h)"
        fi
      else
        age_note="unparsable timestamp"
      fi
      [[ -n "$then_epoch" ]] && last="$last UTC"
    else
      last="(none)"
      age_note="no last-cycle recorded"
    fi

    printf '  %-10s last-cycle=%s  age=%s\n' "$lane" "$last" "$age_note"
    if [[ -n "$flags" && "$flags" != "none" && "$flags" != "-" ]]; then
      printf '    flags: %s\n' "$flags"
    fi
  done
  ((any)) || echo "  (no per-lane comments found on the telemetry issue)"
  echo
}

# =============================================================================
# Section 5 — findings stranded on merged PRs
# =============================================================================
# A review that lands AFTER a merge has nowhere to go: the merge gate is a
# merge-time predicate that already passed, the babysit lane works OPEN PRs, and
# nothing on a merged PR surfaces its open threads.
#
# Only threads whose FIRST comment postdates the merge are reported. A thread
# that predates it was visible to the gate, so its being open is an ordinary
# unresolved-thread matter and not this failure mode.
# fetch_merged_gql OUTFILE CUTOFF_EPOCH
# Writes one GraphQL page document per page, the shape `gh api --paginate`
# emits. Pages run newest-updated first and the walk stops after the first page
# whose oldest PR was last updated before the cutoff: a PR merged after the
# cutoff was also updated after it, so no later page can hold one.
fetch_merged_gql() {
  local out="$1" cutoff="$2" cursor="" args
  : >"$out"
  while :; do
    args=(api graphql -F owner="${REPO%%/*}" -F name="${REPO##*/}" -f query="$MERGED_QUERY")
    [[ -n "$cursor" ]] && args+=(-f endCursor="$cursor")
    gh_read "$WORK/merged.page" "${args[@]}" || return 1
    cat "$WORK/merged.page" >>"$out"
    cursor="$(jq -r --argjson cutoff "$cutoff" '
      .data.repository.pullRequests
      | if .pageInfo.hasNextPage != true then ""
        elif (.nodes | length) == 0 or .pageInfo.endCursor == null then "!"
        elif ((.nodes | last | .updatedAt // null) == null)
          or ((.nodes | last | .updatedAt | fromdateiso8601) < $cutoff)
        then "" else .pageInfo.endCursor end
    ' "$WORK/merged.page" 2>/dev/null)" || {
      LAST_ERR="could not parse a merged-PR page"
      return 1
    }
    [[ "$cursor" != "!" ]] || {
      LAST_ERR="a merged-PR page reported more results but no cursor to them"
      return 1
    }
    [[ -n "$cursor" ]] || return 0
  done
}

# `search/issues` dates the merge; reviewThreads needs GraphQL. One paged
# GraphQL query does both, so this stays one call per page rather than N+1.
# shellcheck disable=SC2016  # $owner/$name/$endCursor are GraphQL variables bound by -F/-f, and MUST reach the server unexpanded
MERGED_QUERY='
    query($owner:String!, $name:String!, $endCursor:String) {
      repository(owner:$owner, name:$name) {
        pullRequests(states:MERGED, first:25, orderBy:{field:UPDATED_AT, direction:DESC}, after:$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number title url mergedAt updatedAt
            # 100 is the GraphQL page maximum. The walk follows only the
            # OUTER cursor, so a PR with more threads than this would be
            # truncated with no signal. hasNextPage is read below and
            # reported, because a partial read must never render as an
            # all-clear.
            reviewThreads(first:100) {
              pageInfo { hasNextPage }
              nodes {
                isResolved
                comments(first:1) { nodes { createdAt author { login } body } }
              }
            }
          }
        }
      }
    }'

# The bookmark: one file per repo under the data dir, holding the cutoff the
# next run must read back to. Empty when no usable path resolves.
stranded_bookmark_path() {
  local base="$DATA_DIR_ARG" seg="${CLAUDE_PLUGIN_DATA:-}" key
  if [[ -z "$base" ]]; then
    seg="${seg%[/\\]}"
    seg="${seg##*[/\\]}"
    if [[ "$seg" == harness-ops || "$seg" == harness-ops-* ]]; then
      base="$CLAUDE_PLUGIN_DATA"
    else
      base="${HOME:-}/.claude/plugins/data/harness-ops"
    fi
  fi
  key="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
  [[ "$key" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ && "$key" != *..* ]] || return 0
  printf '%s/morning-brief/%s/stranded-cutoff' "${base%/}" "$key"
}

# Refuses a symlinked bookmark, and writes through a fresh mktemp file so a
# link planted at the temp path is never followed.
save_bookmark() {
  local file="$1" value="$2" tmp
  [[ ! -L "$file" ]] && mkdir -p "${file%/*}" 2>/dev/null &&
    tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || return 1
  if ! { printf '%s\n' "$value" >"$tmp" && mv -f "$tmp" "$file"; } 2>/dev/null; then
    rm -f "$tmp"
    return 1
  fi
}

print_stranded() {
  local floor=$((NOW_EPOCH - STRANDED_DAYS * 86400)) cutoff bookmark="" mark mark_epoch window
  cutoff=$floor
  window="last ${STRANDED_DAYS}d"
  # The bookmark belongs to a live read of the repo; a fixture run neither
  # reads nor moves it.
  if [[ -z "$MERGED_JSON" && -n "$REPO" ]]; then
    bookmark="$(stranded_bookmark_path)"
    if [[ -n "$bookmark" && -f "$bookmark" ]]; then
      mark="$(tr -d '[:space:]' <"$bookmark")"
      mark_epoch="$(to_epoch "$mark")"
      if [[ -z "$mark_epoch" ]]; then
        window="$window; bookmark unparsable, ignored"
      elif ((mark_epoch < floor)); then
        cutoff=$mark_epoch
        window="$window, widened to the last full read's bookmark"
      fi
    fi
  fi
  echo "== Findings stranded on merged PRs (merged since $(utc_stamp "$cutoff"): $window) =="
  local merged_file="$WORK/merged.json"
  if [[ -n "$MERGED_JSON" ]]; then
    merged_file="$MERGED_JSON"
    # A fixture is held to the same standard as a live read: an error document
    # is an unreadable source, never an all-clear.
    local fixture_err
    fixture_err="$(body_error "$merged_file")"
    if [[ -n "$fixture_err" ]]; then
      unreadable stranded "$fixture_err"
      return
    fi
  elif [[ -z "$REPO" ]]; then
    # A fixture-only run resolves no repo; that is an empty state, not a failure.
    echo "  (no repo resolved — pass --repo or --merged-json)"
    echo
    return
  elif [[ "$TRANSPORT" == "rest" ]]; then
    # reviewThreads is GraphQL-only; there is no REST read for this section.
    unreadable stranded "review threads need GraphQL, which this session does not serve"
    return
  else
    if ! fetch_merged_gql "$merged_file" "$cutoff"; then
      graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
      unreadable stranded "$LAST_ERR"
      return
    fi
  fi

  # A response with no page document is not a clean window.
  jq -s -e '[ .. | objects | select(has("data")) | .data.repository.pullRequests | objects ] | length > 0' \
    "$merged_file" >/dev/null 2>&1 || {
    unreadable stranded "could not parse the merged-PR pages"
    return
  }

  local stranded
  # The pages are a sequence of JSON documents, one per page, so slurp and walk
  # every page's nodes rather than assuming a single top-level object.
  stranded="$(jq -s -r --argjson cutoff "$cutoff" '
    # `jq -s` wraps the input in one more array, and `gh --paginate` emits a
    # bare sequence of page objects while a fixture file is already an array of
    # them. `..|objects` walks both shapes without caring which arrived, then
    # selects only true page documents.
    [ .. | objects | select(has("data")) | .data.repository.pullRequests.nodes[]? ]
    | map(select(.mergedAt != null and ((.mergedAt | fromdateiso8601) >= $cutoff)))
    | map(
        . as $pr
        | ($pr.reviewThreads.nodes // [])
          | map(select(
              .isResolved == false
              and (.comments.nodes[0].createdAt // null) != null
              # The discriminator: the finding arrived after the gate had passed.
              and ((.comments.nodes[0].createdAt | fromdateiso8601) > ($pr.mergedAt | fromdateiso8601))
            ))
          | map({
              pr: $pr.number, title: $pr.title, url: $pr.url,
              author: (.comments.nodes[0].author.login // "unknown"),
              # Severity must survive to the operator: a stranded P1 cannot read
              # like a P3. Matched on the STRUCTURED marker only — the badge
              # alt-text (`![P1 Badge]`), the shields URL (`badge/P1`), or a
              # leading bracket — never on free prose. A body-wide substring
              # test falsely promotes a P2 titled "Preserve P1 labels", and any
              # finding that merely discusses CRITICAL or SECURITY.
              sev: (
                (.comments.nodes[0].body // "")
                # `[ match(...) ]` rather than `capture(...).s` or a bare
                # `match(...)`: a non-match must yield EMPTY so the next
                # alternative is tried. Indexing a non-matching capture instead
                # aborts the whole program, which renders every PR as clear.
                | . as $b
                | [ ( $b | [ match("!\\[[[:space:]]*(P[0-9])[ _-]?Badge"; "i") ] ),
                    ( $b | [ match("badge/(P[0-9])"; "i") ] ),
                    ( $b | [ match("^[[:space:]]*\\[(P[0-9])\\]"; "i") ] ) ]
                | map(.[0].captures[0].string // empty)
                | (.[0] // "")
                | ascii_upcase
              )
            })
      )
    | add // []
    # Collapse to one line per PR. Several findings on one PR are one thing for
    # the operator to go look at, and repeating the identical title once per
    # thread buries the other PRs. The PR carries its WORST severity, so
    # collapsing can never soften a P0 sitting beside advisory findings.
    | group_by(.pr)
    | map({
        pr: .[0].pr, title: .[0].title, url: .[0].url,
        author: (map(.author) | unique | join(", ")),
        n: length,
        # Rank NUMERICALLY, never on the display string: "--" sorts before "P0"
        # lexicographically, so an unclassified thread beside a P0 would hide
        # the P0 behind a "[--]" label. Unrecognized ranks last (99).
        sev: (map(.sev) | map(if . == "" then 99 else (.[1:] | tonumber) end) | min
              | if . == 99 then "--" else "P\(.)" end)
      })
    | sort_by(if .sev == "--" then 99 else (.sev[1:] | tonumber) end, .pr)
    | .[]
    | "  [\(.sev)] #\(.pr) \(.title)  (\(.n) finding\(if .n == 1 then "" else "s" end))\n    \(.url)  by \(.author)"
  ' "$merged_file" 2>/dev/null)" || {
    unreadable stranded "could not parse the merged-PR pages"
    return
  }

  # A truncated thread page means the read was PARTIAL, so neither a finding
  # list nor an all-clear below can be trusted to be complete. Say so.
  local truncated
  truncated="$(jq -s -r '
    [ .. | objects | select(has("data")) | .data.repository.pullRequests.nodes[]?
      | select(.reviewThreads.pageInfo.hasNextPage == true) | .number ]
    | unique | map("#\(.)") | join(", ")
  ' "$merged_file" 2>/dev/null)" || {
    unreadable stranded "could not parse the merged-PR pages"
    return
  }
  if [[ -n "$truncated" ]]; then
    echo "  WARNING: more than 100 review threads on $truncated — this read is PARTIAL, not an all-clear"
  fi

  if [[ -n "$stranded" ]]; then
    echo "$stranded"
    echo "  these merged with the finding unread — the merge gate could not see it"
  else
    echo "  (none — every merged PR in the window is clear)"
  fi
  # Advance the bookmark only past a full read: the next run then reads back
  # to this run's floor, so every merge since then is read at least once more.
  if [[ -n "$bookmark" ]]; then
    if [[ -n "$truncated" ]]; then
      echo "  bookmark not advanced: this read is PARTIAL"
    elif ! save_bookmark "$bookmark" "$(from_epoch "$floor")"; then
      echo "  bookmark not saved under the data dir; the next run reads back to its floor or an older bookmark"
    fi
  fi
  echo
}

# =============================================================================
# Section 6 — lane runs: failures by class, limit stops, restarts, turn headroom
# =============================================================================
# One row per lane workflow over the last LANE_DAYS days. A failed run's class
# comes from its jobs' check-run annotations: the lane record's `class=` field
# (ci-workflows classify), except that a run the action stopped for exceeding
# its turn cap is max-turns even where classify still writes class=other. Turns
# and the cap come from the record's `turns=` and `max-turns=` fields, else from
# the SDK result's num_turns or the action's "after N turns, exceeding the
# configured maximum of M" annotation. A restart is a run of a lane on an item
# whose previous run of that lane was a limit stop. An item is the head commit
# for a pull_request or workflow_run run. Any other run carries no head or
# issue number, so its item is the event and the `#N` that ends its title
# (pr-unblock's run-name, work-resolve-issue's), else its whole title.
# shellcheck disable=SC2016  # $runs, $ann, $lanes, $since and $threshold are jq variables bound by --slurpfile/--argjson
LANE_DEFS='
  def num(re): [match(re; "i") | .captures[0].string | tonumber] | first;
  def tok($k): [match("(?:^|[^A-Za-z0-9_-])" + $k + "=([A-Za-z0-9._:/,\\[\\]-]+)") | .captures[0].string | sub("[.,]+$"; "")] | first;
  def turns_of: num("(?:^|[^a-z-])turns=([0-9]+)") // num("\"num_turns\":([0-9]+)") // num("after ([0-9]+) turns, exceeding");
  def cap_of: num("max-turns=([0-9]+)") // num("configured maximum of ([0-9]+)");
  def klass:
    if test("class=rate-limit(?![a-z-])") then "rate-limit"
    elif test("class=auth(?![a-z-])") then "auth"
    elif test("class=max-turns(?![a-z-])|error_max_turns|exceeding the configured maximum of [0-9]+|maximum number of turns"; "i") then "max-turns"
    else "other" end;
  def hot($cap): $cap != null and . != null and . * 100 >= 80 * $cap;
  def lane_runs($wf):
    ($ann[0]) as $texts
    | ($wf | sub("\\.ya?ml$"; "")) as $lane
    | [ ($runs[0][$wf] // [])[]
      | select(.status == "completed" and .conclusion != "skipped" and .conclusion != null)
      | select((.created_at | fromdateiso8601) >= $since)
      | ($texts[(.id | tostring)]) as $t
      | (if $t != null then ($t | tok("activity")) else null end) as $act
      | . + {
          read: ($t != null),
          record: ($t != null and ($t | test("(?:^|[^A-Za-z0-9_-])(?:class|turns|max-turns|models|profile)="))),
          failed: (.conclusion | IN("failure", "timed_out", "startup_failure")),
          turns: (if $t != null then ($t | turns_of) else null end),
          cap: (if $t != null then ($t | cap_of) else null end),
          head: (((.event // "") | startswith("pull_request")) or .event == "workflow_run"),
          number: ([(.display_title // "") | capture(" #(?<n>[0-9]+)$") | .n] | first),
          name: (if $act != null and $act != $lane then "\($lane) / \($act)" else $lane end),
          profile: ((if $t != null then ($t | tok("profile")) else null end) // "unknown"),
          models: (if $t != null then (($t | tok("models")) // "" | split(",") | map(select(. != ""))) else [] end)
        }
      | . + {
          key: (if .head then "head \(.head_sha)" elif .number then "\(.event) #\(.number)" else "title \(.display_title)" end)
        }
      | . + {class: (if .failed | not then null
                     elif .conclusion != "failure" then "other"
                     elif .read then ($t | klass)
                     else "unread" end)}
    ];
'
# shellcheck disable=SC2016  # jq variables, as above
LANES_JQ="$LANE_DEFS"'
  $lanes[]
  | . as $wf
  | lane_runs($wf) as $r
  | ($r | map(select(.failed))) as $f
  | ($f | map(select(.class == "rate-limit")) | length) as $stops
  | ($r | group_by(.key) | map(sort_by(.created_at))) as $items
  | ([ $items[] | . as $g | range(1; length) | select($g[. - 1].class == "rate-limit") ] | length) as $restarts
  | [ $items[] | select((map(select(.class == "rate-limit")) | length) >= 3)
      | {n: (map(select(.class == "rate-limit")) | length), title: .[0].display_title, sha: (.[0].head_sha // "")[0:7], head: .[0].head} ] as $repeat
  | ($r | map(.turns | numbers) | sort) as $ts
  | ($r | sort_by(.created_at) | map(.cap | numbers) | last) as $cap
  | (if ($ts | length) > 0 then $ts[((($ts | length) * 0.9) | ceil) - 1] else null end) as $p90
  | ($f | map(select(.class == "max-turns")) | length) as $maxturns
  | "  \($wf)  runs=\($r | length)  failed=\($f | length) [rate-limit \($stops), max-turns \($maxturns), auth \($f | map(select(.class == "auth")) | length), other \($f | map(select(.class == "other")) | length)\(($f | map(select(.class == "unread")) | length) as $u | if $u > 0 then ", unread \($u)" else "" end)]  limit-stops=\($stops)  restarts=\($restarts)",
    (if ($ts | length) > 0 then
       "    turns: max=\($ts | last) p90=\($p90) cap=\($cap // "?") (\($ts | length) runs)"
       + (if $maxturns > 0 or ($p90 | hot($cap)) then "  CHECK: " + ([ (if $maxturns > 0 then "\($maxturns) max-turns failure(s)" else empty end), (if ($p90 | hot($cap)) then "p90 at or above 80% of the cap" else empty end) ] | join("; ")) + "; raise the cap or inspect the runs" else "" end)
     elif $maxturns > 0 then "    turns: none recorded  CHECK: \($maxturns) max-turns failure(s); raise the cap or inspect the runs"
     else empty end),
    ($r | map(select(.class == "max-turns" or ((.cap // $cap) as $c | .turns | hot($c)))) | sort_by(.created_at) | reverse | .[:5][] | "      \(.html_url)"),
    ($repeat[] | "    \(.n) limit stops on one \(if .head then "head" else "item" end): \(.title)\(if .head and .sha != "" then " @ \(.sha)" else "" end)")
'
# The model-usage baseline: one row per activity and profile over the same
# runs, from the record tokens of the runs whose annotations carry a lane
# record; a run read with none (cancelled, stopped at a gate) is left out. An
# activity is the record's `activity=` (a pipeline lane's), else the lane; a
# profile is the record's `profile=`, else unknown. A pass is a run that
# concluded success; a max-turns hit is a failed run of class max-turns.
# shellcheck disable=SC2016  # jq variables, as above
MODELS_JQ="$LANE_DEFS"'
  def median: if length == 0 then null elif length % 2 == 1 then .[length / 2 | floor] else (.[length / 2 - 1] + .[length / 2]) / 2 end;
  [ $lanes[] as $wf | lane_runs($wf)[] ] as $all
  | ($all | map(select(.record))) as $read
  | (($all | length) - ($read | length)) as $unread
  | ($read | group_by([.name, .profile]) | map({
      name: .[0].name, profile: .[0].profile, runs: length,
      pass: (map(select(.conclusion == "success")) | length),
      median: (map(.turns | numbers) | sort | median),
      hits: (map(select(.class == "max-turns")) | length),
      models: ([.[].models[]] | unique)
    })) as $cells
  | "  model usage by activity and profile (runs with a read lane record; no sizes or costs):",
    (if ($cells | length) == 0 then "    no lane records read" else empty end),
    ($cells[] | "    \(.name)  profile=\(.profile)  runs=\(.runs)  pass=\(.pass)/\(.runs)  median-turns=\(.median // "-")  max-turns-hits=\(.hits)  models=\(if (.models | length) > 0 then .models | join(",") else "none recorded" end)"),
    (if $unread > 0 then "    \($unread) run(s) left out: no lane record was read" else empty end),
    (if $threshold == null then "    no threshold set: pass --max-turns-hits N for RECOMMENDED lines"
     else ($cells[] | select(.hits > $threshold)
       | "    RECOMMENDED: \(.name) profile=\(.profile) hit max-turns \(.hits) times, over the threshold of \($threshold); raise its max-turns or route it to a stronger profile in the models: table")
     end)
'

LANES_PARTIAL=0
CALLER_JOB_RE='^([a-z0-9][a-z0-9-]*) / '
# fetch_lane_runs OUTFILE SINCE_EPOCH: an object of workflow file -> runs.
fetch_lane_runs() {
  local out="$1" day wf
  day="$(from_epoch "$2")"
  day="${day%%T*}"
  echo '{}' >"$out"
  for wf in "${LANE_WORKFLOWS[@]}"; do
    gh_read "$WORK/lane.page" api --paginate "repos/$REPO/actions/workflows/$(urlencode "$wf")/runs?created=>=$day&per_page=100" || return 1
    jq -s --arg wf "$wf" --slurpfile acc "$out" '
      $acc[0] + {($wf): [ .[].workflow_runs[]? | {id, html_url, event, display_title, head_sha, status, conclusion, created_at} ]}
    ' "$WORK/lane.page" >"$WORK/lane.acc" 2>/dev/null || {
      LAST_ERR="could not parse the runs of $wf"
      return 1
    }
    mv "$WORK/lane.acc" "$out"
  done
}

# fetch_lane_annotations RUNSFILE OUTFILE: the joined job annotations of up to
# LANE_READ_LIMIT finished runs, by run id: failed runs first, then the rest,
# each newest first. A run whose read failed is left out, which the rendering
# shows as unread. A job a reusable workflow ran is named "<caller job> / <job>";
# the pipeline lanes name each caller job after its activity, so such a job
# with annotations adds an `activity=<caller job>` line. That name comes from
# the jobs read already made, so the posted `<lane> / <activity>` check runs,
# whose record copies the run job's, cost no read.
fetch_lane_annotations() {
  local runs="$1" out="$2" id jid jname ids n
  : >"$WORK/lane.ann"
  ids="$(jq -r '[ .[][] | select(.status == "completed" and .conclusion != "skipped") ]
    | sort_by(.created_at) | reverse | sort_by(.conclusion != "failure") | .[].id' "$runs")"
  n="$(grep -c . <<<"$ids")"
  ((n > LANE_READ_LIMIT)) && LANES_PARTIAL=$((n - LANE_READ_LIMIT))
  for id in $(head -n "$LANE_READ_LIMIT" <<<"$ids"); do
    gh_read "$WORK/lane.jobs" api --paginate "repos/$REPO/actions/runs/$id/jobs?per_page=100" || continue
    : >"$WORK/lane.msgs"
    local ok=1
    while IFS=$'\t' read -r jid jname; do
      [[ -n "$jid" ]] || continue
      gh_read "$WORK/lane.one" api "repos/$REPO/check-runs/$jid/annotations?per_page=100" || {
        ok=0
        break
      }
      jq -r '.[]?.message // empty' "$WORK/lane.one" >>"$WORK/lane.msgs" 2>/dev/null
      [[ "$jname" =~ $CALLER_JOB_RE ]] && jq -e 'length > 0' "$WORK/lane.one" >/dev/null 2>&1 &&
        echo "activity=${BASH_REMATCH[1]}" >>"$WORK/lane.msgs"
    done < <(jq -r -s '.[].jobs[]? | [.id, (.name // "")] | @tsv' "$WORK/lane.jobs" 2>/dev/null)
    ((ok)) && jq -R -s -c --arg id "$id" '{($id): .}' "$WORK/lane.msgs" >>"$WORK/lane.ann"
  done
  jq -s 'add // {}' "$WORK/lane.ann" >"$out"
}

print_lanes() {
  local since=$((NOW_EPOCH - LANE_DAYS * 86400)) runs="$WORK/lane-runs.json" ann="$WORK/lane-ann.json" part _parts
  echo "== Lanes, last ${LANE_DAYS}d (runs, failures by class, limit stops, restarts, turn headroom, model usage) =="
  LANE_WORKFLOWS=()
  if [[ -n "$LANE_WORKFLOWS_ARG" ]]; then
    IFS=',' read -ra _parts <<<"$LANE_WORKFLOWS_ARG"
    for part in "${_parts[@]}"; do
      part="${part//[[:space:]]/}"
      [[ -n "$part" ]] && LANE_WORKFLOWS+=("$part")
    done
  fi
  if [[ -n "$LANE_RUNS_JSON" ]]; then
    runs="$LANE_RUNS_JSON"
    jq -e 'type == "object"' "$runs" >/dev/null 2>&1 || {
      unreadable lanes "--lane-runs-json is not an object"
      return
    }
    ((${#LANE_WORKFLOWS[@]})) || mapfile -t LANE_WORKFLOWS < <(jq -r 'keys[]' "$runs")
    if [[ -n "$LANE_ANNOTATIONS_JSON" ]]; then ann="$LANE_ANNOTATIONS_JSON"; else echo '{}' >"$ann"; fi
    ((${#LANE_WORKFLOWS[@]})) || {
      echo "  no lane workflows found (nothing to report)"
      echo
      return
    }
  elif [[ -z "$REPO" ]]; then
    echo "  (no repo resolved — pass --repo or --lane-runs-json)"
    echo
    return
  else
    if ((${#LANE_WORKFLOWS[@]} == 0)); then
      gh_read "$WORK/lane.wfs" api --paginate "repos/$REPO/actions/workflows?per_page=100" || {
        unreadable lanes "workflow list: $LAST_ERR"
        return
      }
      local wf
      for wf in "${DEFAULT_LANE_WORKFLOWS[@]}"; do
        jq -s -e --arg wf "$wf" '[ .[].workflows[]?.path | split("/") | last ] | index($wf) != null' "$WORK/lane.wfs" >/dev/null 2>&1 &&
          LANE_WORKFLOWS+=("$wf")
      done
    fi
    ((${#LANE_WORKFLOWS[@]})) || {
      echo "  no lane workflows found (nothing to report)"
      echo
      return
    }
    fetch_lane_runs "$runs" "$since" || {
      unreadable lanes "$LAST_ERR"
      return
    }
    fetch_lane_annotations "$runs" "$ann"
  fi
  local rows
  rows="$(jq -n -r --argjson since "$since" --slurpfile runs "$runs" --slurpfile ann "$ann" \
    --argjson lanes "$(printf '%s\n' "${LANE_WORKFLOWS[@]}" | jq -R . | jq -s .)" "$LANES_JQ" 2>&1)" || {
    unreadable lanes "could not parse the lane runs: ${rows%%$'\n'*}"
    return
  }
  echo "$rows"
  ((LANES_PARTIAL)) && echo "  PARTIAL: annotations read for $LANE_READ_LIMIT runs, failed runs first; $LANES_PARTIAL more were not read (raise --lane-read-limit)"
  rows="$(jq -n -r --argjson since "$since" --slurpfile runs "$runs" --slurpfile ann "$ann" \
    --argjson threshold "${MAX_TURNS_HITS:-null}" \
    --argjson lanes "$(printf '%s\n' "${LANE_WORKFLOWS[@]}" | jq -R . | jq -s .)" "$MODELS_JQ" 2>&1)" || {
    unreadable lanes "could not parse the lane records: ${rows%%$'\n'*}"
    return
  }
  echo "$rows"
  echo
}

# =============================================================================
# Section 7 — cost: what on GitHub or Azure is charging or could start charging
# =============================================================================
# One line per check: a status (OK, ALERT, INFO, UNREADABLE or SKIPPED), its
# source, a label and the detail. ALERT is the line to act on. A read the
# operator may not make (GitHub billing needs an org admin) or cannot make (az
# absent or logged out) is SKIPPED and fails nothing; any other failed read is
# an UNREADABLE line beside the lines that did read.
#
# Every Azure read is a GET, except the Cost Management query, a POST that
# reads. Never `--refresh`, never `az graph`, never a plan or setting write
# (SKILL.md points at the upstream pages that say why). Dynamic extension
# install is off, so a command that would need one fails instead of installing.
COST_ROWS=()
COST_PARTIAL=()
COST_HAS_DATA=0
COST_LOST=0
AZ_SUB_ARGS=()
[[ -n "$SUBSCRIPTION_ARG" ]] && AZ_SUB_ARGS=(--subscription "$SUBSCRIPTION_ARG")
# Month-to-date actual cost by service and meter category, one page.
COST_QUERY_BODY='{"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"None","aggregation":{"cost":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"ServiceName"},{"type":"Dimension","name":"MeterCategory"}]}}'
# Activity-log events read per run; a read that reaches it prints PARTIAL.
AZ_ACTIVITY_LIMIT=1000
# Control-plane writes that can start a charge or widen access.
COST_WRITE_OPS='["microsoft.security/pricings/write","microsoft.authorization/policyassignments/write","microsoft.authorization/roleassignments/write"]'
COST_MONTH="$(from_epoch "$NOW_EPOCH")"
COST_MONTH="${COST_MONTH:0:7}"
COST_ORG="${ORG_ARG:-${REPO%%/*}}"
# A fixture run never reaches for the network: the cost reads go live with the
# rest of the brief, or when --org or --subscription asks for them.
GH_COST_LIVE=$(((ANY_LIVE || ${#ORG_ARG} > 0) && ${#COST_ORG} > 0))
AZ_COST_LIVE=$((ANY_LIVE || ${#ORG_ARG} > 0 || ${#SUBSCRIPTION_ARG} > 0))
# Hours in this month, the period an included storage amount covers.
COST_YEAR=$((10#${COST_MONTH:0:4}))
COST_MON=$((10#${COST_MONTH:5:2}))
COST_NEXT="$((COST_YEAR + COST_MON / 12))-$(printf '%02d' $((COST_MON % 12 + 1)))"
COST_HOURS=$((($(to_epoch "${COST_NEXT}-01T00:00Z") - $(to_epoch "${COST_MONTH}-01T00:00Z")) / 3600))
# Comma lists become JSON arrays for the jq programs.
csv_json() { jq -cn --arg s "$1" '$s | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))'; }
REQUIRED_BUDGETS_JSON="$(csv_json "$REQUIRED_BUDGETS_ARG")"
ALLOWED_COLLABORATORS_JSON="$(csv_json "$ALLOWED_COLLABORATORS_ARG")"
# The Azure lines, so a failed az login renders each of them UNREADABLE.
AZ_LABELS=("budgets" "budget and anomaly alerts" "Defender plans" "Defender charges, month to date"
  "Log Analytics" "activity, last 24h" "secure score" "Advisor security" "Advisor cost")
# The Log Analytics query: the peak day of billable ingestion over 31 days.
LA_PEAK_QUERY='Usage | where TimeGenerated > ago(31d) | where IsBillable == true | summarize GB = sum(Quantity) / 1000.0 by Day = bin(TimeGenerated, 1d) | top 1 by GB desc'

# Each program turns one response into rows of [status, source, label, detail];
# a response of the wrong shape is an error, so the read renders UNREADABLE.
# shellcheck disable=SC2016  # $month, $ops and $label are jq variables bound by cost_jq
COST_DEFS='
  def money: (. * 100 | round) / 100 | tostring;
  def num: if type == "string" then tonumber elif type == "number" then . else error("not a number") end;
  def list: if type == "array" then . else error("not a list") end;
  def str: if type == "string" then . else error("not a string") end;
  def bool: if type == "boolean" then . else error("not a boolean") end;
'
# shellcheck disable=SC2016  # jq variables, as above
USAGE_JQ='
  .usageItems | list
  | map(select(.date | str | startswith($month))) | group_by(.product)
  | if length == 0 then ["OK", "GitHub", "usage \($month)", "no metered usage"]
    else .[] | (map(.netAmount | num) | add) as $net
      | [(if $net > 0 then "ALERT" else "OK" end), "GitHub", "usage \($month) \(.[0].product)", "net \($net | money)"]
    end'
# Private-repo Actions minutes and artifact storage this month against the
# plan's included amounts. A repo the org scan did not list counts as private.
# shellcheck disable=SC2016  # jq variables, as above
INCLUDED_JQ='
  (if .repos == null then {} else (.repos | list | map({key: (.name | str), value: (.visibility | str)}) | from_entries) end) as $vis
  | (if .repos == null then "; repo visibility unread, every repo counted as private" else "" end) as $note
  | [.usage.usageItems | list | .[]
      | select(.date | str | startswith($month)) | select((.product | str) == "actions")
      | select(($vis[.repositoryName // ""] // "private") != "public")] as $private
  | ($private | map(select((.unitType | str) == "Minutes") | .quantity | num) | add // 0) as $minutes
  | ($private | map(select((.unitType | str) == "GigabyteHours") | .quantity | num) | add // 0) as $gb_hours
  | def against($used; $included; $unit; $label; $flag):
      if $included == null
      then ["INFO", "GitHub", $label, "\($used | money) \($unit) used; included amount not configured (pass \($flag))\($note)"]
      else (if $included > 0 then $used * 100 / $included else 100 end) as $pct
        | [(if $pct >= $pct_alert then "ALERT" else "OK" end), "GitHub", $label,
           "\($used | money) of \($included | money) \($unit) included (\($pct | round)%)\($note)"]
      end;
    against($minutes; $inc_minutes; "minutes"; "Actions minutes \($month), private repos"; "--actions-included-minutes"),
    against($gb_hours; (if $inc_gb == null then null else $inc_gb * $hours end); "GB-hours"; "Actions storage \($month), private repos";
      "--actions-included-storage-gb")'
# The org scan: direct collaborators besides org admins, and workflows on a
# fork-triggered event that reference a secret whose name contains _CLAUDE_.
# shellcheck disable=SC2016  # jq variables, as above
SCAN_JQ='
  (.admins | list | map(.login? // . | str)) as $admins
  | [.repos | list | .[] | select(.archived != true)] as $repos
  | [$repos[] | .name as $r | .collaborators | list | .[] | (.login? // . | str)
      | . as $who | select(($admins + $allowed) | index($who) | not) | {r: $r, who: $who}] as $extra
  | [$repos[] | (.name | str) as $r | .workflows | list | .[]
      | (.path | str) as $path
      | (.text | str | split("\n") | map(select(test("^\\s*#") | not))) as $lines
      | ([$lines[] | select(test("(^|[\\s,\\[])(pull_request_target|workflow_run)(\\s*:|\\s*[\\],]|\\s*$)"))
          | match("pull_request_target|workflow_run").string] | unique) as $events
      | ([$lines[] | match("secrets\\.([A-Za-z0-9_]*_CLAUDE_[A-Za-z0-9_]*)|secrets\\[\\s*.([A-Za-z0-9_]*_CLAUDE_[A-Za-z0-9_]*).\\s*\\]"; "gi")
          | .captures[] | .string // empty] | unique) as $secrets
      | select(($events | length) > 0 and ($secrets | length) > 0)
      | {r: $r, path: $path, events: $events, secrets: $secrets}] as $hits
  | (if ($extra | length) == 0
     then [["OK", "GitHub", "collaborators", "no direct collaborator besides org admins on \($repos | length) repos"]]
     else [$extra[] | ["ALERT", "GitHub", "collaborators", "\(.r): direct collaborator \(.who)"]] end)
    + (if ($hits | length) == 0
       then [["OK", "GitHub", "fork-triggered workflows", "none reads a _CLAUDE_ secret (\([$repos[].workflows | length] | add // 0) files)"]]
       else [$hits[] | ["ALERT", "GitHub", "fork-triggered workflows", "\(.r) \(.path): \(.events | join(", ")) reads \(.secrets | join(", "))"]] end)
  | .[]'
# shellcheck disable=SC2016  # jq variables, as above
BUDGETS_JQ='
  .budgets | list
  | if length == 0 then ["INFO", "GitHub", "budgets", "none set"]
    else .[] | (.budget_amount | num) as $amount | (.prevent_further_usage | bool) as $stop
      | [(if $amount > 0 or ($stop | not) then "ALERT" else "OK" end), "GitHub",
         "budget \(.budget_product_sku // .budget_type // .id)",
         "amount \($amount | money), stop at limit \(if $stop then "on" else "off" end)"]
    end'
# A budget is an ALERT when its spend reached its amount, or its forecast is
# above --forecast-alert (else above the budget's own amount).
# shellcheck disable=SC2016  # jq variables, as above
AZ_BUDGETS_JQ='
  .value | list
  | if length == 0 then ["INFO", "Azure", "budgets", "none on this subscription"]
    else .[] | .name as $name | .properties
      | (.currentSpend.amount | num) as $spent | (.amount | num) as $cap
      | (.forecastSpend.amount | num) as $forecast | ($forecast_alert // $cap) as $limit
      | [(if $spent >= $cap or $forecast > $limit then "ALERT" else "OK" end), "Azure", "budget \($name)",
         "spent \($spent | money), forecast \($forecast | money) (alert above \($limit | money)), of \($cap | money) \(.currentSpend.unit | str); read \($read_at)"]
    end'
# The budgets and the anomaly alert that must exist, and when each ends.
# shellcheck disable=SC2016  # jq variables, as above
ALERTS_JQ='
  ((.budgets.value | list | map({key: (.name | str), value: .properties})) | from_entries) as $budgets
  | (.actions.value | list) as $actions
  | ($now + $days * 86400) as $horizon
  | def ends($end; $what):
      ($end | str | sub("\\.[0-9]+"; "") | fromdateiso8601) as $e
      | if $e <= $horizon then ["ALERT", "Azure", "budget and anomaly alerts", "\($what) ends \($end[0:10]), within \($days) days"]
        else ["OK", "Azure", "budget and anomaly alerts", "\($what) ends \($end[0:10])"] end;
    (if ($required | length) == 0 then ["INFO", "Azure", "budget and anomaly alerts", "no required budgets named (pass --required-budgets)"]
     else $required[] as $b
       | if $budgets[$b] == null then ["ALERT", "Azure", "budget and anomaly alerts", "budget \($b) is missing"]
         else ends($budgets[$b].timePeriod.endDate; "budget \($b)") end
     end),
    ([$actions[] | select(if $anomaly != null then .name == $anomaly else (.kind | str) == "InsightAlert" end)] as $found
     | if ($found | length) == 0
       then ["ALERT", "Azure", "budget and anomaly alerts", "anomaly alert \($anomaly // "(any)") is missing"]
       else $found[] | .name as $n
         | if (.properties.status | str) != "Enabled"
           then ["ALERT", "Azure", "budget and anomaly alerts", "anomaly alert \($n) is \(.properties.status)"]
           else ends(.properties.schedule.endDate; "anomaly alert \($n)") end
       end)'
# One workspace: its peak billable day over 31 days against its daily cap; a cap
# of -1 (none) is an ALERT, since nothing stops ingestion.
# shellcheck disable=SC2016  # jq variables, as above
LA_JQ='
  .ws as $ws | ($ws.workspaceCapping.dailyQuotaGb | num) as $cap
  | (.rows | list | map(.GB | num) | max // 0) as $peak
  | (.rows | list | map(.Day | str) | first // "none") as $day
  | if $cap < 0 then ["ALERT", "Azure", "Log Analytics \($ws.name | str)", "no daily cap; peak \($peak | money) GB on \($day[0:10])"]
    else ($peak * 100 / $cap) as $pct
      | [(if $pct >= $log_pct_alert then "ALERT" else "OK" end), "Azure", "Log Analytics \($ws.name | str)",
         "peak \($peak | money) GB on \($day[0:10]) of a \($cap | money) GB daily cap (\($pct | round)%)"]
    end'
# shellcheck disable=SC2016  # jq variables, as above
PRICINGS_JQ='
  (if type == "object" then .value else . end) | list
  | map(select((.pricingTier // "") != "Free")) as $paid
  | if ($paid | length) > 0
    then ["INFO", "Azure", "Defender plans", "not Free: " + ($paid | map("\(.name) (\(.pricingTier // "no tier"))") | join(", "))]
    else ["INFO", "Azure", "Defender plans", "\(length) plans, all Free"] end'
# A cost row is a Defender charge when its service or meter category names
# Defender or its former name; the columns are found by name, not position.
# shellcheck disable=SC2016  # jq variables, as above
CHARGES_JQ='
  .properties as $p
  | ($p.columns | list | map(.name | ascii_downcase)) as $c
  | ($c | index("cost")) as $ic | ($c | index("servicename")) as $is
  | ($c | index("metercategory")) as $im | ($c | index("currency")) as $iu
  | if $ic == null or $is == null or $im == null then error("missing columns") else . end
  | [ $p.rows | list | .[]
      | ([.[$is], .[$im]] | map(if . == null or type == "string" then . // "" else error("a service or meter category is not a string") end)) as $names
      | if ($names | all(. == "")) then error("a cost row names no service or meter category") else . end
      | select($names | join(" ") | ascii_downcase | test("defender|security center")) ]
  | (map(.[$ic] | num) | add // 0) as $cost
  | [(if $cost > 0 then "ALERT" else "OK" end), "Azure", $label,
     (if length == 0 then "no Defender cost rows"
      else ("\($cost | money) \(if $iu != null then .[0][$iu] // "" else "" end)" | rtrimstr(" ")) end)]'
# shellcheck disable=SC2016  # jq variables, as above
ACTIVITY_JQ='
  list
  | map(select((.operationName.value | str | if . == "" then error("an event names no operation") else ascii_downcase end) as $op | $ops | index($op)))
  | if length == 0 then ["OK", "Azure", "activity, last 24h", "no Defender plan, policy assignment or role assignment writes"]
    else group_by(.operationName.value | ascii_downcase)[] | max_by(.eventTimestamp // "") as $last
      | ["ALERT", "Azure", "activity, last 24h",
         "\($last.operationName.value): \(length) event(s), latest \(($last.eventTimestamp // "")[0:16])Z UTC by \($last.caller // "unknown")"]
    end'
SCORES_JQ='
  list
  | if length == 0 then ["INFO", "Azure", "secure score", "none reported"]
    else .[] | ["INFO", "Azure", "secure score", "\(.displayName // .name) \(.current | num | money)/\(.max | num | money)"] end'
# shellcheck disable=SC2016  # jq variables, as above
ADVISOR_JQ='list | ["INFO", "Azure", $label, "\(length) recommendation(s)"]'

# cost_row STATUS SOURCE LABEL DETAIL. Control characters in a field (escapes
# in an error message or a subscription name) become spaces, as in cost_jq.
cost_row() {
  local f row=""
  for f in "$1" "$2" "$3" "$4"; do
    row+="${row:+$'\x1f'}${f//[[:cntrl:]]/ }"
  done
  COST_ROWS+=("$row")
}

# cost_jq FILE PROGRAM LABEL: appends the rows PROGRAM derives from FILE, or 1.
# Control characters in a field (newlines, escapes in a budget or caller name)
# become spaces, so one row stays one line.
cost_jq() {
  local rows
  rows="$(jq -r --arg month "$COST_MONTH" --argjson ops "$COST_WRITE_OPS" --arg label "$3" \
    --argjson pct_alert "$USAGE_ALERT_PERCENT" --argjson log_pct_alert "$LOG_CAP_ALERT_PERCENT" \
    --argjson inc_minutes "${ACTIONS_INCLUDED_MINUTES:-null}" --argjson inc_gb "${ACTIONS_INCLUDED_STORAGE_GB:-null}" \
    --argjson hours "$COST_HOURS" --argjson forecast_alert "${FORECAST_ALERT:-null}" \
    --arg read_at "$(utc_stamp "$NOW_EPOCH")" --argjson now "$NOW_EPOCH" --argjson days "$EXPIRY_DAYS" \
    --argjson required "$REQUIRED_BUDGETS_JSON" --argjson anomaly "$(jq -cn --arg a "$ANOMALY_ALERT" 'if $a == "" then null else $a end')" \
    --argjson allowed "$ALLOWED_COLLABORATORS_JSON" \
    "$COST_DEFS $2"' | map(tostring | gsub("[[:cntrl:]]"; " ")) | join("\u001f")' "$1" 2>/dev/null)" || return 1
  [[ -n "$rows" ]] || return 1
  mapfile -t -O "${#COST_ROWS[@]}" COST_ROWS <<<"$rows"
}

# billing_read OUTFILE FIXTURE API-PATH: 0 read; 1 failed, with LAST_ERR set;
# 2 refused for want of an org admin; 3 not read (no org in a fixture run).
# GitHub documents no message text for that refusal, so only a 403 whose
# message names admin rights, a billing manager or an owner counts as one; any
# other 403 (a rate limit, SAML enforcement) is a failed read.
billing_read() {
  local out="$1" fixture="$2"
  LAST_ERR=""
  if [[ -n "$fixture" ]]; then
    cp "$fixture" "$out"
    LAST_ERR="$(body_error "$out")"
  elif ((!GH_COST_LIVE)); then
    return 3
  elif ! have gh; then
    LAST_ERR="gh not installed"
    return 1
  else
    gh_read "$out" api "$3"
  fi
  [[ -n "$LAST_ERR" ]] || return 0
  # The cloud proxy's GraphQL refusal is a 403 too, and says nothing about
  # the operator's role.
  if ! graphql_blocked "$LAST_ERR" &&
    { [[ "$LAST_ERR" == *"HTTP 403"* ]] || jq -e '.status == "403"' "$out" >/dev/null 2>&1; } &&
    grep -qiE 'admin|billing manager|organization owner' <<<"$LAST_ERR"; then
    return 2
  fi
  return 1
}

# fetch_org_scan OUTFILE: the org's repos (listed once), its admins, and for
# each live repo its direct collaborators and default-branch workflow files, up
# to WORKFLOW_READ_LIMIT files. Returns 1 with LAST_ERR set on a failed read; a
# repo with no .github/workflows directory has no workflows.
fetch_org_scan() {
  local out="$1" repo branch archived name files=0 skipped=0
  rest_paginate_array "$WORK/org-repos" "orgs/$COST_ORG/repos?per_page=100&type=all" || return 1
  rest_paginate_array "$WORK/org-admins" "orgs/$COST_ORG/members?role=admin&per_page=100" || return 1
  : >"$WORK/scan-repos"
  while IFS=$'\t' read -r repo branch archived; do
    jq -n --slurpfile repos "$WORK/org-repos" --arg r "$repo" \
      '$repos[0][] | select(.name == $r) | {name, visibility, archived, collaborators: [], workflows: []}' >"$WORK/scan-repo"
    if [[ "$archived" != true ]]; then
      rest_paginate_array "$WORK/collab" "repos/$COST_ORG/$repo/collaborators?affiliation=direct&per_page=100" || {
        LAST_ERR="$repo collaborators: $LAST_ERR"
        return 1
      }
      jq --slurpfile c "$WORK/collab" '.collaborators = [$c[0][].login]' "$WORK/scan-repo" >"$WORK/scan-repo.next" &&
        mv "$WORK/scan-repo.next" "$WORK/scan-repo"
      if gh_read "$WORK/wf-list" api "repos/$COST_ORG/$repo/contents/.github/workflows?ref=$(urlencode "$branch")"; then
        while IFS= read -r name; do
          if ((files >= WORKFLOW_READ_LIMIT)); then
            skipped=$((skipped + 1))
            continue
          fi
          gh_read "$WORK/wf" api -H "Accept: application/vnd.github.raw" \
            "repos/$COST_ORG/$repo/contents/.github/workflows/$(urlencode "$name")?ref=$(urlencode "$branch")" || {
            LAST_ERR="$repo $name: $LAST_ERR"
            return 1
          }
          files=$((files + 1))
          jq --arg p ".github/workflows/$name" --rawfile t "$WORK/wf" '.workflows += [{path: $p, text: $t}]' "$WORK/scan-repo" \
            >"$WORK/scan-repo.next" && mv "$WORK/scan-repo.next" "$WORK/scan-repo"
        done < <(jq -r '.[]? | select(.type == "file" and (.name | test("\\.ya?ml$"))) | .name' "$WORK/wf-list")
      elif [[ "$LAST_ERR" != *"HTTP 404"* ]]; then
        LAST_ERR="$repo workflows: $LAST_ERR"
        return 1
      fi
    fi
    cat "$WORK/scan-repo" >>"$WORK/scan-repos"
  done < <(jq -r '.[] | [.name, (.default_branch // "main"), (.archived | tostring)] | @tsv' "$WORK/org-repos")
  jq -n --slurpfile admins "$WORK/org-admins" --slurpfile repos "$WORK/scan-repos" --argjson partial "$skipped" \
    '{admins: [$admins[0][].login], repos: $repos, partial: $partial}' >"$out"
}

cost_github() {
  local usage="$WORK/billing-usage.json" budgets="$WORK/billing-budgets.json" scan="$WORK/org-scan.json" rc scanned=0 scan_status=UNREADABLE
  if [[ -z "$BILLING_USAGE_JSON$BILLING_BUDGETS_JSON$ORG_SCAN_JSON" ]] && ((!GH_COST_LIVE)); then
    cost_row SKIPPED GitHub "billing" "not checked: no org resolved (pass --org or --billing-usage-json)"
    return
  fi
  # The org scan first: the usage lines need each repo's visibility.
  if [[ -n "$ORG_SCAN_JSON" ]]; then
    cp "$ORG_SCAN_JSON" "$scan" && scanned=1
  elif ((GH_COST_LIVE)) && have gh; then
    fetch_org_scan "$scan" && scanned=1
  elif ((GH_COST_LIVE)); then
    LAST_ERR="gh not installed"
  else
    scan_status=SKIPPED
    LAST_ERR="not checked: no org scan in a fixture run (pass --org-scan-json)"
  fi
  local scan_err="$LAST_ERR"
  billing_read "$usage" "$BILLING_USAGE_JSON" "orgs/$COST_ORG/settings/billing/usage?year=${COST_MONTH:0:4}&month=$((10#${COST_MONTH:5:2}))"
  rc=$?
  case $rc in
  0)
    cost_jq "$usage" "$USAGE_JQ" "" || cost_row UNREADABLE GitHub "usage $COST_MONTH" "could not parse the billing usage"
    if ((scanned)); then
      jq -n --slurpfile u "$usage" --slurpfile s "$scan" '{usage: $u[0], repos: $s[0].repos}' >"$WORK/included.json"
    else
      jq -n --slurpfile u "$usage" '{usage: $u[0], repos: null}' >"$WORK/included.json"
    fi
    cost_jq "$WORK/included.json" "$INCLUDED_JQ" "" ||
      cost_row UNREADABLE GitHub "Actions quota $COST_MONTH" "could not parse the billing usage"
    ;;
  1) cost_row UNREADABLE GitHub "usage $COST_MONTH" "$LAST_ERR" ;;
  2) cost_row SKIPPED GitHub "usage $COST_MONTH" "not readable (org admin needed)" ;;
  *) cost_row SKIPPED GitHub "usage $COST_MONTH" "not checked: no org resolved (pass --org or --billing-usage-json)" ;;
  esac
  billing_read "$budgets" "$BILLING_BUDGETS_JSON" "orgs/$COST_ORG/settings/billing/budgets?per_page=100"
  rc=$?
  case $rc in
  0)
    cost_jq "$budgets" "$BUDGETS_JQ" "" || cost_row UNREADABLE GitHub "budgets" "could not parse the billing budgets"
    jq -e '.has_next_page == true' "$budgets" >/dev/null 2>&1 &&
      COST_PARTIAL+=("GitHub budgets: more than one page; the rest were not read")
    ;;
  1) cost_row UNREADABLE GitHub "budgets" "$LAST_ERR" ;;
  2) cost_row SKIPPED GitHub "budgets" "not readable (org admin needed)" ;;
  *) cost_row SKIPPED GitHub "budgets" "not checked: no org resolved (pass --org or --billing-budgets-json)" ;;
  esac
  if ((scanned)) && cost_jq "$scan" "$SCAN_JQ" ""; then
    jq -e '(.partial // 0) > 0' "$scan" >/dev/null 2>&1 &&
      COST_PARTIAL+=("GitHub workflows: the read reached its $WORKFLOW_READ_LIMIT-file cap; $(jq -r '.partial' "$scan") more were not read (raise --workflow-read-limit)")
  else
    ((scanned)) && scan_err="could not parse the org scan"
    cost_row "$scan_status" GitHub "collaborators" "$scan_err"
    cost_row "$scan_status" GitHub "fork-triggered workflows" "$scan_err"
  fi
}

# az_read OUTFILE KEY az-args...: one az read, or its KEY in --azure-json.
# Returns 1 with LAST_ERR set when the read failed.
az_read() {
  local out="$1" key="$2" rc
  shift 2
  LAST_ERR=""
  if [[ -n "$AZURE_JSON" ]]; then
    # A KEY of a/b reads a nested value; an absent or null value is a failed read.
    jq -e --arg k "$key" 'type == "object" and getpath($k | split("/")) != null' "$AZURE_JSON" >/dev/null 2>&1 || {
      LAST_ERR="no $key in --azure-json"
      return 1
    }
    jq --arg k "$key" 'getpath($k | split("/"))' "$AZURE_JSON" >"$out"
    return 0
  fi
  have az || {
    LAST_ERR="az not installed"
    return 1
  }
  : >"$ERR_FILE"
  # WSLENV carries the setting to a Windows az run from WSL; elsewhere it is inert.
  # az reads its stdin, so it gets none: a caller's loop input stays the loop's.
  WSLENV="${WSLENV:+$WSLENV:}AZURE_EXTENSION_USE_DYNAMIC_INSTALL" AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no az "$@" "${AZ_SUB_ARGS[@]}" --only-show-errors -o json >"$out" 2>"$ERR_FILE" </dev/null
  rc=$?
  if ((rc != 0)); then
    LAST_ERR="$(grep -m1 -v '^[[:space:]]*$' "$ERR_FILE" 2>/dev/null)"
    LAST_ERR="${LAST_ERR#ERROR: }"
    [[ -n "$LAST_ERR" ]] || LAST_ERR="az exited $rc"
    return 1
  fi
}

# az_check KEY LABEL PROGRAM az-args...: one read rendered into rows; a failed
# read or a response PROGRAM cannot parse is an UNREADABLE row.
az_check() {
  local key="$1" label="$2" prog="$3" out="$WORK/az-$1.json"
  shift 3
  if az_read "$out" "$key" "$@"; then
    cost_jq "$out" "$prog" "$label" && return
    LAST_ERR="could not parse the $key response"
  fi
  cost_row UNREADABLE Azure "$label" "$LAST_ERR"
}

cost_azure() {
  local acct="$WORK/az-account.json" sub label arm ws_file id
  if [[ -z "$AZURE_JSON" ]] && ((!AZ_COST_LIVE)); then
    cost_row SKIPPED Azure "" "not checked: no live read in a fixture run (pass --subscription or --azure-json)"
    return
  fi
  if [[ -z "$AZURE_JSON" && -z "$SUBSCRIPTION_ARG" ]] && ! have az; then
    cost_row SKIPPED Azure "" "not checked (az not installed)"
    return
  fi
  if ! az_read "$acct" account account show || ! sub="$(jq -r '.id // empty' "$acct" 2>/dev/null)" || [[ -z "$sub" ]]; then
    # az is installed (or a subscription was named) but no account reads:
    # every Azure line is a read that failed.
    LAST_ERR="${LAST_ERR:-account show named no subscription id}"
    [[ "$LAST_ERR" == "az not installed" || "$LAST_ERR" == *"az login"* ]] || LAST_ERR="$LAST_ERR; run az login"
    cost_row UNREADABLE Azure "subscription${SUBSCRIPTION_ARG:+ $SUBSCRIPTION_ARG}" "$LAST_ERR"
    for label in "${AZ_LABELS[@]}"; do
      cost_row UNREADABLE Azure "$label" "$LAST_ERR"
    done
    return
  fi
  # Every later read names the subscription account show resolved.
  AZ_SUB_ARGS=(--subscription "$sub")
  arm="https://management.azure.com/subscriptions/$sub/providers"
  cost_row INFO Azure "subscription" "$(jq -r '"\(.name // .id) (\(.state // "state unknown"))"' "$acct")"
  az_check budgets "budgets" "$AZ_BUDGETS_JQ" rest --method get --url "$arm/Microsoft.Consumption/budgets?api-version=2024-08-01"
  if az_read "$WORK/az-actions.json" scheduledActions rest --method get \
    --url "$arm/Microsoft.CostManagement/scheduledActions?api-version=2023-11-01"; then
    if jq -n --slurpfile b "$WORK/az-budgets.json" --slurpfile a "$WORK/az-actions.json" '{budgets: $b[0], actions: $a[0]}' \
      >"$WORK/az-alerts.json" 2>/dev/null && cost_jq "$WORK/az-alerts.json" "$ALERTS_JQ" ""; then
      :
    else
      cost_row UNREADABLE Azure "budget and anomaly alerts" "could not parse the budgets or scheduled actions"
    fi
  else
    cost_row UNREADABLE Azure "budget and anomaly alerts" "$LAST_ERR"
  fi
  az_check pricings "Defender plans" "$PRICINGS_JQ" security pricing list
  # A plan's tier is not a charge: the month's actual cost is. The query is a
  # POST that reads only, and the only `az rest` POST the script makes.
  az_check defenderCost "Defender charges, month to date" "$CHARGES_JQ" rest --method post \
    --url "$arm/Microsoft.CostManagement/query?api-version=2023-11-01" \
    --body "$COST_QUERY_BODY"
  jq -e '.properties.nextLink // empty | length > 0' "$WORK/az-defenderCost.json" >/dev/null 2>&1 &&
    COST_PARTIAL+=("Azure Defender charges: the cost query returned more than one page; the rest were not read")
  ws_file="$WORK/az-workspaces.json"
  if ! az_read "$ws_file" workspaces monitor log-analytics workspace list; then
    cost_row UNREADABLE Azure "Log Analytics" "$LAST_ERR"
  elif ! jq -e 'type == "array"' "$ws_file" >/dev/null 2>&1; then
    cost_row UNREADABLE Azure "Log Analytics" "could not parse the workspaces response"
  elif jq -e 'length == 0' "$ws_file" >/dev/null; then
    cost_row INFO Azure "Log Analytics" "no workspaces on this subscription"
  else
    while IFS= read -r id; do
      if az_read "$WORK/az-la.json" "laUsage/$id" monitor log-analytics query --workspace "$id" --analytics-query "$LA_PEAK_QUERY" &&
        jq -n --slurpfile w "$ws_file" --slurpfile r "$WORK/az-la.json" --arg id "$id" \
          '{ws: ($w[0][] | select(.customerId == $id)), rows: $r[0]}' >"$WORK/az-la-one.json" 2>/dev/null &&
        cost_jq "$WORK/az-la-one.json" "$LA_JQ" ""; then
        :
      else
        [[ -n "$LAST_ERR" ]] || LAST_ERR="could not parse the Log Analytics response"
        cost_row UNREADABLE Azure "Log Analytics $(jq -r --arg id "$id" '.[] | select(.customerId == $id) | .name' "$ws_file")" "$LAST_ERR"
      fi
    done < <(jq -r '.[] | .customerId // "missing-id"' "$ws_file")
  fi
  az_check activity "activity, last 24h" "$ACTIVITY_JQ" monitor activity-log list --offset 1d --max-events "$AZ_ACTIVITY_LIMIT"
  jq -e --argjson n "$AZ_ACTIVITY_LIMIT" 'type == "array" and length >= $n' "$WORK/az-activity.json" >/dev/null 2>&1 &&
    COST_PARTIAL+=("Azure activity: the read reached its $AZ_ACTIVITY_LIMIT-event cap; a write past it is not shown")
  az_check secureScores "secure score" "$SCORES_JQ" security secure-scores list
  az_check advisorSecurity "Advisor security" "$ADVISOR_JQ" advisor recommendation list --category Security
  az_check advisorCost "Advisor cost" "$ADVISOR_JQ" advisor recommendation list --category Cost
}

print_cost() {
  echo "== Cost (GitHub and Azure: charges, included usage, budgets and alerts, secret triggers, posture) =="
  cost_github
  cost_azure
  local row status source label detail unread=0 line
  for row in "${COST_ROWS[@]}"; do
    IFS=$'\x1f' read -r status source label detail <<<"$row"
    case "$status" in
    UNREADABLE) unread=$((unread + 1)) ;;
    OK | ALERT | INFO) COST_HAS_DATA=1 ;;
    *) ;;
    esac
    line="$source${label:+ $label}: $detail"
    printf '  %-10s %s\n' "$status" "$line"
  done
  for line in "${COST_PARTIAL[@]}"; do
    echo "  PARTIAL: $line"
  done
  if ((unread > 0)); then
    UNREADABLE=$((UNREADABLE + 1))
    UNREADABLE_NAMES+=("cost")
    COST_LOST=1
  fi
  echo
}

# =============================================================================
# Render
# =============================================================================
# Each section renders into its own file first so the header can state how
# many were unreadable before any section prints.
print_queues >"$WORK/s1"
print_merge_ready >"$WORK/s2"
print_decisions >"$WORK/s3"
print_telemetry >"$WORK/s4"
print_stranded >"$WORK/s5"
print_lanes >"$WORK/s6"
print_cost >"$WORK/s7"

printf 'Morning brief — %s — %s\n' "${REPO:-<fixtures>}" "$(utc_stamp "$NOW_EPOCH")"
[[ "$REPO_SOURCE" == "git remote" ]] && echo "  repo resolved from the git origin remote (gh repo view unavailable)"
[[ "$TRANSPORT" == "rest" ]] && echo "  transport: REST (this session does not serve the gh GraphQL queries)"
if ((UNREADABLE > 0)); then
  echo "  $UNREADABLE of $SECTIONS_TOTAL sections unreadable: ${UNREADABLE_NAMES[*]}"
fi
echo
cat "$WORK/s1" "$WORK/s2" "$WORK/s3" "$WORK/s4" "$WORK/s5" "$WORK/s6" "$WORK/s7"

# Exit 5 when the brief carries no data at all; 6 when some sections rendered
# beside unreadable ones, so a caller never takes a partial brief for a full one.
# When every other section is lost, the brief carries data only if a cost line
# is OK, ALERT or INFO; a cost section of SKIPPED lines carries none.
if ((UNREADABLE - COST_LOST >= SECTIONS_TOTAL - 1 && !COST_HAS_DATA)); then
  exit 5
elif ((UNREADABLE > 0)); then
  exit 6
fi
exit 0
