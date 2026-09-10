#!/usr/bin/env bash
# morning-brief.sh — read-only operator morning view for a GitHub repo.
#
# Prints, for the current repo, one scannable picture: open issue counts per
# queue label, the gh-native merge-ready PR list, parked decisions with their
# RECOMMENDED lines, loop-lane telemetry freshness (last-cycle age + flags), and
# review findings stranded on already-merged PRs.
#
# Read-only and gh-based: it never mutates labels, comments, issues, or PRs.
# It runs `gh` read queries only. The authoritative merge gate lives in the
# source-control:babysit-prs skill; the merge-ready list here is a lighter
# gh-native signal (mergeStateStatus CLEAN + non-draft) meant for a 5-second
# glance, not a substitute for that skill's classification.
#
# Owner/repo is derived from `gh repo view`, or from the checkout's `origin`
# remote when that call is unavailable; never hardcoded, so the tool is
# reusable across repos.
#
# Degraded-mode contract. Every section is one of three states: data, empty,
# or UNREADABLE. A section whose data source failed (a non-zero gh exit, or an
# error document in the body) renders as UNREADABLE with the error's first
# line, never with empty-state wording. The header counts the unreadable
# sections. When every section is unreadable the script exits 5, so a caller
# can tell "nothing to report" from "could not read"; a partial brief exits 0.
#
# Transport. The gh subcommands ride GraphQL. When the host serves only a
# pinned set of GraphQL operations (the HTTP 403 "not enabled for this session"
# shape), sections 1-4 are re-read from repository-scoped REST endpoints and
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
#   morning-brief.sh --stranded-days N        age window for stranded review findings (default 3)
#   morning-brief.sh --rec-maxlen N           truncate RECOMMENDED previews (default 240; 0 = full)
#   morning-brief.sh --pr-limit N             open PRs whose merge state the REST path checks (default 50)
#   morning-brief.sh --help
#
# Fixture flags (skip the network; used by the test suite and for reuse):
#   --now ISO                 fixed clock for deterministic staleness
#   --counts-json FILE        label->count object, e.g. {"status: ready":4}
#   --repo-labels-json FILE   array of label names (or {name} objects) for existence checks
#   --pr-json FILE            array as emitted by `gh pr list --json ...`
#   --decisions-json FILE     array of {number,title,url,body,comments:[{body}]}
#   --telemetry-json FILE     array of {body} (the telemetry issue's comments)
#   --merged-json FILE        array of merged-PR GraphQL page documents, as
#                             emitted by `gh api graphql --paginate` (the
#                             stranded-findings section)
#
# Exit codes:
#   0  brief rendered (at least one section carries data or a real empty state)
#   3  invalid argument
#   4  prerequisite missing (gh or jq), or repo could not be resolved
#   5  every section was unreadable; the brief carries no data

# shellcheck disable=SC2329  # the per-section fetch functions are dispatched by name through gql_or_rest, which ShellCheck cannot follow
set -uo pipefail

# --- Queue labels (melodic-software defaults; overridable / filtered live) ------
DEFAULT_QUEUE_LABELS=(
  "priority: needs-triage"
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
DECISIONS_JSON=""
TELEMETRY_JSON=""
MERGED_JSON=""
# How far back to look for merged PRs still carrying unresolved review threads.
# Wide enough to cover a bot that reviews well after a merge lands, and the
# operator-absent stretch (a weekend) during which nobody would look.
STRANDED_DAYS="3"

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
  --pr-limit)
    require_value "$1" "${2:-}"
    require_uint "$1" "$2"
    PR_LIMIT="$((10#$2))"
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

# The host serves only a pinned set of GraphQL operations. Every other GraphQL
# query is refused with this message shape; REST stays available.
graphql_blocked() {
  grep -qiE 'GraphQL query.*not enabled|pinned set of PR-review' <<<"$1"
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
fetch_repo_labels_gql() {
  gh_read "$WORK/labels.raw" label list "${REPO_ARGS[@]}" --limit 500 --json name -q '.[].name' || return 1
  tr -d '\r' <"$WORK/labels.raw" | jq -R -s 'split("\n") | map(select(length > 0)) | unique' >"$1"
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
SECTIONS_TOTAL=5
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
    --limit 1000 --json number -q 'length' || return 1
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
  local rows=()
  for label in "${labels_to_show[@]}"; do
    if [[ -n "$COUNTS_JSON" ]]; then
      n="$(jq -r --arg l "$label" 'if type == "object" then (.[$l] // 0) else 0 end' "$COUNTS_JSON" 2>/dev/null)"
    else
      local count_fn_gql=count_label_gql count_fn_rest=count_label_rest
      if [[ "$TRANSPORT" == "gh" ]]; then
        if ! "$count_fn_gql" "$WORK/count" "$label"; then
          if graphql_blocked "$LAST_ERR"; then
            TRANSPORT="rest"
          else
            unreadable queues "$label: $LAST_ERR"
            return
          fi
        fi
      fi
      if [[ "$TRANSPORT" == "rest" ]]; then
        "$count_fn_rest" "$WORK/count" "$label" || {
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
    rows+=("$(printf '  %-24s %s' "$label" "$n")")
  done
  printf '%s\n' "${rows[@]}"
  echo
}

# =============================================================================
# Section 2 — merge-ready PRs (gh-native: non-draft + mergeStateStatus CLEAN)
# =============================================================================
fetch_prs_gql() {
  gh_read "$1" pr list "${REPO_ARGS[@]}" --state open --limit 200 \
    --json number,title,url,isDraft,mergeStateStatus,reviewDecision
}

PR_PARTIAL=()
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
  local out="$1" total i number retry=() uncomputed=()
  rest_paginate_array "$WORK/prs.rest" "repos/$REPO/pulls?state=open&per_page=100" || return 1
  total="$(jq 'length' "$WORK/prs.rest")"
  PR_PARTIAL=()
  ((total > PR_LIMIT)) && PR_PARTIAL+=("$total open PRs; merge state read for the first $PR_LIMIT only (raise --pr-limit)")
  : >"$WORK/prs.detail"
  for ((i = 0; i < total && i < PR_LIMIT; i++)); do
    number="$(jq -r ".[$i].number" "$WORK/prs.rest")"
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
  for ((i = 0; i < total && i < PR_LIMIT; i++)); do
    number="$(jq -r ".[$i].number" "$WORK/prs.rest")"
    cat "$WORK/pr.$number" >>"$WORK/prs.detail"
  done
  if ((${#uncomputed[@]} > 0)); then
    PR_PARTIAL+=("merge state not yet computed by GitHub for ${uncomputed[*]}; inconclusive, re-run shortly")
  fi
  # The REST pull schema carries no review-decision field; the REST path
  # reports it as n/a.
  jq -s '[ .[] | {number, title, url: .html_url, isDraft: .draft,
                  mergeStateStatus: ((.mergeable_state // "unknown") | ascii_upcase),
                  reviewDecision: "n/a"} ]' "$WORK/prs.detail" >"$out"
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
  local ready
  ready="$(jq -r '
    [ .[] | select(.isDraft == false and .mergeStateStatus == "CLEAN") ]
    | sort_by(.number)
    | .[]
    | "  #\(.number) \(.title)\n    \(.url)  review=\(.reviewDecision // "" | if . == "" then "none" else . end)"
  ' "$prs_file" 2>/dev/null)"
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
    --limit 200 --json number,title,url,body,comments
}

fetch_decisions_rest() {
  local out="$1" total i number
  rest_paginate_array "$WORK/dec.rest" \
    "repos/$REPO/issues?state=open&per_page=100&labels=$(urlencode "$DECISION_LABEL")" || return 1
  jq '[ .[] | select(has("pull_request") | not) ] | .[:200]' "$WORK/dec.rest" >"$WORK/dec.issues"
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
  count="$(jq -r 'length' "$decisions_file" 2>/dev/null || echo 0)"
  if [[ "${count:-0}" -eq 0 ]]; then
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
  echo
}

# =============================================================================
# Section 4 — loop-lane telemetry freshness (per-lane telemetry-issue comments)
# =============================================================================
find_telemetry_issue_gql() {
  gh_read "$WORK/tel.raw" issue list "${REPO_ARGS[@]}" --state open \
    --search "$TELEMETRY_SEARCH" \
    --json number -q 'sort_by(.number) | .[0].number // empty' || return 1
  tr -d '\r' <"$WORK/tel.raw" >"$1"
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

  # A lane comment carries a `lane:` field. For each, pull lane, last-cycle, flags.
  local n
  n="$(jq -r 'length' <<<"$comments" 2>/dev/null || echo 0)"
  local i body lane last flags any=0
  for ((i = 0; i < n; i++)); do
    body="$(jq -r ".[$i].body // \"\"" <<<"$comments" 2>/dev/null)"
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
fetch_merged_gql() {
  # `search/issues` dates the merge; reviewThreads needs GraphQL. One paged
  # GraphQL query does both, so this stays a single call rather than N+1.
  # shellcheck disable=SC2016  # $owner/$name/$endCursor are GraphQL variables bound by -F, and MUST reach the server unexpanded
  gh_read "$1" api graphql --paginate -F owner="${REPO%%/*}" -F name="${REPO##*/}" -f query='
    query($owner:String!, $name:String!, $endCursor:String) {
      repository(owner:$owner, name:$name) {
        pullRequests(states:MERGED, first:25, orderBy:{field:UPDATED_AT, direction:DESC}, after:$endCursor) {
          pageInfo { hasNextPage endCursor }
          nodes {
            number title url mergedAt
            # 100 is the GraphQL page maximum. --paginate follows only the
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
}

print_stranded() {
  echo "== Findings stranded on merged PRs (last ${STRANDED_DAYS}d) =="
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
    if ! fetch_merged_gql "$merged_file"; then
      graphql_blocked "$LAST_ERR" && TRANSPORT="rest"
      unreadable stranded "$LAST_ERR"
      return
    fi
  fi

  local cutoff stranded
  cutoff="$((NOW_EPOCH - STRANDED_DAYS * 86400))"
  # `--paginate` concatenates one JSON document per page, so slurp and walk every
  # page's nodes rather than assuming a single top-level object.
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
  ' "$merged_file" 2>/dev/null)"

  # A truncated thread page means the read was PARTIAL, so neither a finding
  # list nor an all-clear below can be trusted to be complete. Say so.
  local truncated
  truncated="$(jq -s -r '
    [ .. | objects | select(has("data")) | .data.repository.pullRequests.nodes[]?
      | select(.reviewThreads.pageInfo.hasNextPage == true) | .number ]
    | unique | map("#\(.)") | join(", ")
  ' "$merged_file" 2>/dev/null)"
  if [[ -n "$truncated" ]]; then
    echo "  WARNING: more than 100 review threads on $truncated — this read is PARTIAL, not an all-clear"
  fi

  if [[ -n "$stranded" ]]; then
    echo "$stranded"
    echo "  these merged with the finding unread — the merge gate could not see it"
  else
    echo "  (none — every merged PR in the window is clear)"
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

printf 'Morning brief — %s — %s\n' "${REPO:-<fixtures>}" "$(from_epoch "$NOW_EPOCH")"
[[ "$REPO_SOURCE" == "git remote" ]] && echo "  repo resolved from the git origin remote (gh repo view unavailable)"
[[ "$TRANSPORT" == "rest" ]] && echo "  transport: REST (this session does not serve the gh GraphQL queries)"
if ((UNREADABLE > 0)); then
  echo "  $UNREADABLE of $SECTIONS_TOTAL sections unreadable: ${UNREADABLE_NAMES[*]}"
fi
echo
cat "$WORK/s1" "$WORK/s2" "$WORK/s3" "$WORK/s4" "$WORK/s5"

# Exit 5 only when the brief carries no data at all. A partial brief, one or
# more sections unreadable beside others that rendered, is still a brief.
if ((UNREADABLE >= SECTIONS_TOTAL)); then
  exit 5
fi
exit 0
