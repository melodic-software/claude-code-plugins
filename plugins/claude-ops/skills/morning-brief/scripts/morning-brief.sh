#!/usr/bin/env bash
# morning-brief.sh — read-only operator morning view for a GitHub repo.
#
# Prints, for the current repo, one scannable picture: open issue counts per
# queue label, the gh-native merge-ready PR list, parked decisions with their
# RECOMMENDED lines, and loop-lane telemetry freshness (last-cycle age + flags).
#
# Read-only and gh-based: it never mutates labels, comments, issues, or PRs.
# It runs `gh` read queries only. The authoritative merge gate lives in the
# source-control:babysit-prs skill; the merge-ready list here is a lighter
# gh-native signal (mergeStateStatus CLEAN + non-draft) meant for a 5-second
# glance, not a substitute for that skill's classification.
#
# Owner/repo is derived from `gh repo view` (the checkout's default remote),
# never hardcoded, so the tool is reusable across repos.
#
# Usage:
#   morning-brief.sh                          live view of the current repo
#   morning-brief.sh --repo owner/name        target a specific repo
#   morning-brief.sh --telemetry-issue N      pin the lane-telemetry issue
#   morning-brief.sh --stale-hours N          age past which a lane is STALE (default 6)
#   morning-brief.sh --rec-maxlen N           truncate RECOMMENDED previews (default 240; 0 = full)
#   morning-brief.sh --help
#
# Fixture flags (skip the network; used by the test suite and for reuse):
#   --now ISO                 fixed clock for deterministic staleness
#   --counts-json FILE        label->count object, e.g. {"status: ready":4}
#   --pr-json FILE            array as emitted by `gh pr list --json ...`
#   --decisions-json FILE     array of {number,title,url,body,comments:[{body}]}
#   --telemetry-json FILE     array of {body} (the telemetry issue's comments)
#
# Exit codes:
#   0  brief rendered (a data source degrading gracefully is not a failure)
#   3  invalid argument
#   4  prerequisite missing (gh or jq), or repo could not be resolved

set -uo pipefail

# --- Queue labels (verified against `gh label list`) --------------------------
QUEUE_LABELS=(
  "priority: needs-triage"
  "status: ready"
  "status: needs-decision"
  "needs-human"
)
DECISION_LABEL="status: needs-decision"

REPO=""
TELEMETRY_ISSUE=""
STALE_HOURS="6"
REC_MAXLEN="240"
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

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --repo)
    require_value "$1" "${2:-}"
    REPO="$2"
    shift 2
    ;;
  --telemetry-issue)
    require_value "$1" "${2:-}"
    TELEMETRY_ISSUE="$2"
    shift 2
    ;;
  --stale-hours)
    require_value "$1" "${2:-}"
    [[ "$2" =~ ^[0-9]+$ ]] || {
      printf 'morning-brief: --stale-hours requires a non-negative integer\n' >&2
      exit 3
    }
    # 10# forces base-10 so a leading-zero value (e.g. 08) is not later misread
    # as octal in the staleness arithmetic (08 errors, 010 would evaluate as 8).
    STALE_HOURS="$((10#$2))"
    shift 2
    ;;
  --rec-maxlen)
    require_value "$1" "${2:-}"
    [[ "$2" =~ ^[0-9]+$ ]] || {
      printf 'morning-brief: --rec-maxlen requires a non-negative integer\n' >&2
      exit 3
    }
    # 10# forces base-10 so a leading-zero value (e.g. 010) is not later misread
    # as octal in the truncation length (010 would evaluate as 8, not 10).
    REC_MAXLEN="$((10#$2))"
    shift 2
    ;;
  --stranded-days)
    require_value "$1" "${2:-}"
    [[ "$2" =~ ^[0-9]+$ ]] || {
      printf 'morning-brief: --stranded-days requires a non-negative integer\n' >&2
      exit 3
    }
    # 10# forces base-10 so a leading-zero value is not misread as octal.
    STRANDED_DAYS="$((10#$2))"
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

# gh is only needed for live sources; a fully fixtured run (tests) must not
# require it. Demand it only when at least one section will hit the network.
ANY_LIVE=0
[[ -z "$COUNTS_JSON" || -z "$PR_JSON" || -z "$DECISIONS_JSON" || -z "$TELEMETRY_JSON" ]] && ANY_LIVE=1
if ((ANY_LIVE)) && ! have gh; then
  printf 'morning-brief: gh required for live queries (pass fixtures to run offline)\n' >&2
  exit 4
fi

# --- Resolve the target repo --------------------------------------------------
if [[ -z "$REPO" ]] && ((ANY_LIVE)); then
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r')"
  if [[ -z "$REPO" ]]; then
    printf 'morning-brief: could not resolve owner/repo (run inside a gh repo or pass --repo)\n' >&2
    exit 4
  fi
fi
REPO_ARGS=()
[[ -n "$REPO" ]] && REPO_ARGS=(--repo "$REPO")

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

# =============================================================================
# Section 1 — queue label counts
# =============================================================================
print_queues() {
  echo "== Queues (open issues per label) =="
  local counts=""
  if [[ -n "$COUNTS_JSON" ]]; then
    counts="$(cat "$COUNTS_JSON")"
  fi
  local label n
  for label in "${QUEUE_LABELS[@]}"; do
    if [[ -n "$counts" ]]; then
      n="$(jq -r --arg l "$label" '.[$l] // 0' <<<"$counts" 2>/dev/null)"
    else
      n="$(gh issue list "${REPO_ARGS[@]}" --state open --label "$label" \
        --limit 1000 --json number -q 'length' 2>/dev/null | tr -d '\r')"
    fi
    [[ -n "$n" ]] || n="?"
    printf '  %-24s %s\n' "$label" "$n"
  done
  echo
}

# =============================================================================
# Section 2 — merge-ready PRs (gh-native: non-draft + mergeStateStatus CLEAN)
# =============================================================================
print_merge_ready() {
  echo "== Merge-ready PRs (non-draft, mergeStateStatus=CLEAN) =="
  local prs
  if [[ -n "$PR_JSON" ]]; then
    prs="$(cat "$PR_JSON")"
  else
    prs="$(gh pr list "${REPO_ARGS[@]}" --state open --limit 200 \
      --json number,title,url,isDraft,mergeStateStatus,reviewDecision 2>/dev/null)"
  fi
  if [[ -z "$prs" ]]; then
    echo "  (unable to read PR list)"
    echo
    return
  fi
  local ready
  ready="$(jq -r '
    [ .[] | select(.isDraft == false and .mergeStateStatus == "CLEAN") ]
    | sort_by(.number)
    | .[]
    | "  #\(.number) \(.title)\n    \(.url)  review=\(.reviewDecision // "" | if . == "" then "none" else . end)"
  ' <<<"$prs" 2>/dev/null)"
  if [[ -n "$ready" ]]; then
    echo "$ready"
  else
    echo "  (none clean right now)"
  fi
  echo "  authoritative merge gate: /source-control:babysit-prs"
  echo
}

# =============================================================================
# Section 3 — parked decisions (needs-decision) with their RECOMMENDED line
# =============================================================================
print_decisions() {
  echo "== Parked decisions (${DECISION_LABEL}) with RECOMMENDED lines =="
  local decisions
  if [[ -n "$DECISIONS_JSON" ]]; then
    decisions="$(cat "$DECISIONS_JSON")"
  else
    # One call returns body + comments for every decision issue -- no N+1
    # hydration loop (which also avoids `gh` draining a while-read loop's stdin).
    decisions="$(gh issue list "${REPO_ARGS[@]}" --state open --label "$DECISION_LABEL" \
      --limit 200 --json number,title,url,body,comments 2>/dev/null)"
    if [[ -z "$decisions" ]]; then
      echo "  (unable to read decision queue)"
      echo
      return
    fi
  fi

  local count
  count="$(jq -r 'length' <<<"$decisions" 2>/dev/null || echo 0)"
  if [[ "${count:-0}" -eq 0 ]]; then
    echo "  (none parked)"
    echo
    return
  fi

  local i number title url rec
  for ((i = 0; i < count; i++)); do
    number="$(jq -r ".[$i].number" <<<"$decisions")"
    title="$(jq -r ".[$i].title" <<<"$decisions")"
    url="$(jq -r ".[$i].url // \"\"" <<<"$decisions")"
    # RECOMMENDED marker across the body and every comment. Two-tier so the
    # deliberate uppercase marker wins over an incidental lowercase mention
    # (e.g. "not recommended"): tier 1 = the uppercase RECOMMENDED token, tier 2
    # = a case-insensitive fallback (recorded by the process note as necessary
    # because a case-sensitive-only scan produced false negatives). BOTH tiers
    # require a LABELED marker — RECOMMENDED immediately followed (past optional
    # bold/space) by a `:`/`-`/em-dash separator — not mere presence. That
    # separator is the load-bearing discriminator on each tier independently: it
    # accepts a real marker whether at line start or mid-line ("After review,
    # RECOMMENDED: ...") while rejecting negated prose ("... is NOT RECOMMENDED
    # because ...", "not recommended for ..."), where the token is followed by a
    # word, not a separator — the false positive that otherwise renders the
    # REJECTED option. Anchoring to line start instead would wrongly drop the
    # legitimate mid-line marker form.
    local combined marker_re
    marker_re='RECOMMENDED[[:space:]]*\**[[:space:]]*[-:—]'
    combined="$(jq -r ".[$i] | (.body // \"\") + \"\n\" + ((.comments // []) | map(.body // \"\") | join(\"\n\"))" \
      <<<"$decisions")"
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
resolve_telemetry_issue() {
  [[ -n "$TELEMETRY_ISSUE" ]] && {
    echo "$TELEMETRY_ISSUE"
    return
  }
  # Auto-discover by title. Absent in a consuming repo -> empty (caller degrades).
  gh issue list "${REPO_ARGS[@]}" --state open \
    --search "loop-lane telemetry running per-lane status in:title" \
    --json number -q 'sort_by(.number) | .[0].number // empty' 2>/dev/null | tr -d '\r'
}

print_telemetry() {
  echo "== Lane telemetry freshness (last-cycle age + flags) =="
  local comments issue
  if [[ -n "$TELEMETRY_JSON" ]]; then
    comments="$(cat "$TELEMETRY_JSON")"
  else
    issue="$(resolve_telemetry_issue)"
    if [[ -z "$issue" ]]; then
      echo "  no telemetry issue found (nothing to report)"
      echo
      return
    fi
    comments="$(gh issue view "$issue" "${REPO_ARGS[@]}" --json comments -q '.comments' 2>/dev/null)"
    echo "  source: issue #$issue"
  fi
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
# nothing on a merged PR surfaces its open threads. Real case: six findings (one
# P1) posted 46 seconds after #1720 merged sat unread for a day (#1777).
#
# Only threads whose FIRST comment postdates the merge are reported. A thread
# that predates it was visible to the gate, so its being open is an ordinary
# unresolved-thread matter and not this failure mode.
print_stranded() {
  echo "== Findings stranded on merged PRs (last ${STRANDED_DAYS}d) =="
  local merged
  if [[ -n "$MERGED_JSON" ]]; then
    merged="$(cat "$MERGED_JSON")"
  elif [[ -z "$REPO" ]]; then
    # Every other section can be driven entirely from fixtures, so a fixture-only
    # run never resolves a repo. Degrade like the telemetry section does rather
    # than making this section's live path a new requirement on those runs.
    echo "  (no repo resolved — pass --repo or --merged-json)"
    echo
    return
  else
    # `search/issues` dates the merge; reviewThreads needs GraphQL. One paged
    # GraphQL query does both, so this stays a single call rather than N+1.
    # shellcheck disable=SC2016  # $owner/$name/$endCursor are GraphQL variables bound by -F, and MUST reach the server unexpanded
    merged="$(gh api graphql --paginate -F owner="${REPO%%/*}" -F name="${REPO##*/}" -f query='
      query($owner:String!, $name:String!, $endCursor:String) {
        repository(owner:$owner, name:$name) {
          pullRequests(states:MERGED, first:25, orderBy:{field:UPDATED_AT, direction:DESC}, after:$endCursor) {
            pageInfo { hasNextPage endCursor }
            nodes {
              number title url mergedAt
              reviewThreads(first:50) {
                nodes {
                  isResolved
                  comments(first:1) { nodes { createdAt author { login } body } }
                }
              }
            }
          }
        }
      }' 2>/dev/null)"
  fi
  if [[ -z "$merged" ]]; then
    echo "  (unable to read merged PRs)"
    echo
    return
  fi
  # FAIL LOUD. A GraphQL error document is well-formed JSON that carries no
  # `data`, so the extraction below yields an empty list and the section would
  # print "every merged PR is clear" — reporting an unread API as an all-clear,
  # which is the exact fail-open shape this section exists to catch. Observed
  # live: a rate-limit error rendered as a clean window.
  local api_err
  api_err="$(jq -s -r '[ .. | objects | select(has("errors")) | .errors[]?.message ] | first // empty' <<<"$merged" 2>/dev/null)"
  if [[ -n "$api_err" ]]; then
    echo "  (unable to read merged PRs — the API returned an error, so this is NOT an all-clear)"
    echo "    $api_err"
    echo
    return
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
              # like a P3. Markers are matched on the badge alt-text/bracket
              # forms the review bots actually emit.
              sev: (
                (.comments.nodes[0].body // "")
                | if test("P0|CRITICAL|SECURITY"; "i") then "P0"
                  elif test("P1"; "i") then "P1"
                  elif test("P2"; "i") then "P2"
                  else "--" end
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
        sev: (map(.sev) | sort | .[0])
      })
    | sort_by(.sev, .pr)
    | .[]
    | "  [\(.sev)] #\(.pr) \(.title)  (\(.n) finding\(if .n == 1 then "" else "s" end))\n    \(.url)  by \(.author)"
  ' <<<"$merged" 2>/dev/null)"

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
printf 'Morning brief — %s — %s\n\n' "${REPO:-<fixtures>}" "$(from_epoch "$NOW_EPOCH")"
print_queues
print_merge_ready
print_decisions
print_telemetry
print_stranded
exit 0
