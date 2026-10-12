#!/usr/bin/env bash
# Mechanical outcome gate for a drafted PLAN.md (/planning:plan Step 4.7).
#
# The model that just wrote a plan rubber-stamps its own recap, so the criteria
# that can be decided off the file are decided here, with no model involvement:
#
#   phases          at least one `### Phase N:` heading (N is 1, 2.5, 3a, or IV)
#   status-tags     every `### Phase N:` heading ends in one of the three status
#                   tags /planning:plan defines: not-started, [DOING] or [DONE]
#                   (a note after " - " inside the brackets, as in [DOING - standing], is kept)
#   sanity-checks   every phase section carries at least one `Sanity Check`
#   decisions       when the plan tags a decision [EXEC-SHAPE] or [FALLBACK], a
#                   `| Decision | What it changes ...` table has at least one row
#   blast-radius    a Blast radius heading or line names LOW, MEDIUM, HIGH or CRITICAL
#   portable-paths  no drive-letter path (C:\ or C:/) and no /Users/<name> or
#                   /home/<name> path, unless the line carries <!-- path-example -->.
#                   /Users and /home count only where they begin a path: not right
#                   after a letter, digit, _, . / or -, so a repo folder such as
#                   Domain/Users/ or src/home/ passes, but one right after a colon,
#                   pipe or comma fails
#   planned-breakage  every `**Planned breakage:**` line (a list marker before it
#                   is allowed) sits in a phase section and reads
#                   `<build|tests|lint> red until Phase <M> for <paths or test
#                   filter>: <reason>`, where Phase <M> is a later `### Phase`
#                   heading by position, so 2.5, 3a and IV compare by heading order.
#                   A plan with no such line passes. Failures are listed as
#                   `invalid=<line>:<reason>`, the reason one of kind, until, for,
#                   missing-phase, not-later, last-phase or outside-phase
#
# "Every brief scope-item maps to a phase" is judgment and stays in the skill's
# prose; this gate does not claim it.
#
# Headings inside fenced code blocks are ignored. A fence closes only on the same
# character with at least the opening length and no info string, so a three-backtick
# block quoted inside a four-backtick block stays inside it. The path check reads
# every line, fenced or not, because a published PLAN.md is read on other machines
# either way.
#
# The default run is the Step 4.7 draft gate and does not look at the `Approval:`
# line, which is written only after approval. `--approval-only` runs that one
# check after the line is written:
#
#   approval        an `Approval:` line exists and its value is non-empty and is
#                   neither the template placeholder (angle-bracket text) nor TBD.
#                   Presence only: whether the recorded mandate is adequate is judgment.
#                   An `Approval:` line inside a code fence does not count.
#
# Exit 0 = every criterion passes
# Exit 1 = at least one criterion fails
# Exit 2 = usage or environment error (missing or unreadable file, ...)
#
# Usage:
#   bash check-plan-outcome.sh <PLAN.md>
#   bash check-plan-outcome.sh --approval-only <PLAN.md>
#   bash check-plan-outcome.sh --help
#
# Output (stdout, greppable): one `criterion=<name> status=<pass|fail> ...` line
# per criterion, each failing path hit as `path-hit=<line>:<text>` (at most 20
# lines, then `path-hit-truncated=<n>` when more exist; `hits=` is the full
# count), then a closing `phases=<n> status=<ok|fail>` line. `--approval-only` prints the single
# `criterion=approval status=<pass|fail>` line.

set -uo pipefail

usage() {
  sed -n '/^# Mechanical/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  echo "error: $1" >&2
  exit 2
}

plan=""
approval_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --approval-only)
    approval_only=1
    shift
    ;;
  -*)
    die "unknown option: $1"
    ;;
  *)
    [[ -z "$plan" ]] || die "exactly one PLAN.md path is expected"
    plan="$1"
    shift
    ;;
  esac
done

[[ -n "$plan" ]] || die "a PLAN.md path is required (see --help)"
[[ -f "$plan" ]] || die "not a file: $plan"
[[ -r "$plan" ]] || die "not readable: $plan"

if [[ "$approval_only" -eq 1 ]]; then
  value="$(
    tr -d '\r' <"$plan" |
      awk '
        match($0, /^[ \t]*(```+|~~~+)/) {
          fence = substr($0, RSTART, RLENGTH)
          sub(/^[ \t]*/, "", fence)
          bare = (substr($0, RSTART + RLENGTH) ~ /^[ \t]*$/)
          if (!in_fence) { in_fence = 1; fence_ch = substr(fence, 1, 1); fence_len = length(fence); next }
          if (substr(fence, 1, 1) == fence_ch && length(fence) >= fence_len && bare) in_fence = 0
          next
        }
        !in_fence { print }
      ' |
      sed -nE 's/^[[:space:]]*(\*\*)?Approval:(\*\*)?[[:space:]]*(.*[^[:space:]])?[[:space:]]*$/\3/p' |
      grep -vE '^(<.*>|[Tt][Bb][Dd]\.?)?$' | head -n 1
  )"
  if [[ -n "$value" ]]; then
    echo "criterion=approval status=pass"
    exit 0
  fi
  echo "criterion=approval status=fail (no 'Approval:' line with a recorded value; empty, placeholder and TBD do not count)"
  exit 1
fi

# One awk pass decides the structural criteria. CRLF is stripped so a plan
# saved on Windows grades the same as one saved elsewhere.
structural="$(
  awk '
    function flush_phase() {
      if (in_phase && !phase_sanity) missing_sanity = missing_sanity " " phase_name
    }
    { sub(/\r$/, "") }
    match($0, /^[ \t]*(```+|~~~+)/) {
      fence = substr($0, RSTART, RLENGTH)
      sub(/^[ \t]*/, "", fence)
      bare = (substr($0, RSTART + RLENGTH) ~ /^[ \t]*$/)
      if (!in_fence) { in_fence = 1; fence_ch = substr(fence, 1, 1); fence_len = length(fence); next }
      if (substr(fence, 1, 1) == fence_ch && length(fence) >= fence_len && bare) in_fence = 0
      next
    }
    in_fence { next }
    /^#+[ \t]/ {
      heading = $0
      in_table = 0
      if (heading ~ /^###[ \t]+Phase[ \t]+([0-9]+(\.[0-9]+)?[A-Za-z]?|[IVXLC]+)[ \t]*:/) {
        flush_phase()
        phases++
        in_phase = 1
        phase_sanity = 0
        phase_id = heading
        sub(/^###[ \t]+Phase[ \t]+/, "", phase_id)
        sub(/[ \t]*:.*/, "", phase_id)
        if (!(phase_id in phase_pos)) phase_pos[phase_id] = phases
        phase_name = heading
        sub(/^###[ \t]+/, "", phase_name)
        sub(/[ \t]*:.*/, "", phase_name)
        gsub(/[ \t]+/, "-", phase_name)
        trimmed = heading
        sub(/[ \t]+$/, "", trimmed)
        if (trimmed !~ /\[(TODO|DOING|DONE)([ \t]+-[^]]*)?\]$/) untagged = untagged " " phase_name
      } else if (heading ~ /^(#|##|###)[ \t]/) {
        flush_phase()
        in_phase = 0
      }
      if (tolower(heading) ~ /blast[- ]radius/) { blast_open = 4; if (heading ~ /(LOW|MEDIUM|HIGH|CRITICAL)/) blast_level = 1 }
      next
    }
    /^[ \t]*([-*+][ \t]+)?\*\*Planned breakage:\*\*/ {
      breakages++
      breakage_line[breakages] = NR
      breakage_phase[breakages] = in_phase ? phases : 0
      text = $0
      sub(/^[ \t]*([-*+][ \t]+)?\*\*Planned breakage:\*\*[ \t]*/, "", text)
      breakage_text[breakages] = text
    }
    {
      if (in_phase && $0 ~ /Sanity Check/) phase_sanity = 1
      if ($0 ~ /^[ \t]*\|[ \t]*Decision[ \t]*\|[ \t]*What it changes/) { in_table = 1; decisions_table = 1; next }
      if (in_table && $0 !~ /^[ \t]*\|/) in_table = 0
      if (in_table) { if ($0 !~ /^[ \t]*\|[ \t:|-]*$/) decision_rows++; next }
      if ($0 ~ /\[(EXEC-SHAPE|FALLBACK)([^]A-Za-z][^]]*)?\]/) tagged++
      if (tolower($0) ~ /^[ \t*_-]*blast[- ]radius[ \t*_]*:/) { blast_open = 1; if ($0 ~ /(LOW|MEDIUM|HIGH|CRITICAL)/) blast_level = 1 }
      else if (blast_open > 0 && $0 ~ /[^ \t]/) { if ($0 ~ /(LOW|MEDIUM|HIGH|CRITICAL)/) blast_level = 1; blast_open-- }
    }
    function breakage_reason(i,    text, target) {
      if (breakage_phase[i] == 0) return "outside-phase"
      text = breakage_text[i]
      if (text !~ /^(build|tests|lint)[ \t]/) return "kind"
      sub(/^[a-z]+/, "", text)
      if (!match(text, /^[ \t]+red[ \t]+until[ \t]+Phase[ \t]+([0-9]+(\.[0-9]+)?[A-Za-z]?|[IVXLC]+)/)) return "until"
      target = substr(text, RSTART, RLENGTH)
      sub(/.*Phase[ \t]+/, "", target)
      text = substr(text, RSTART + RLENGTH)
      if (text !~ /^[ \t]+for[ \t]+[^ \t:].*:[ \t]+[^ \t]/) return "for"
      if (breakage_phase[i] == phases) return "last-phase"
      if (!(target in phase_pos)) return "missing-phase"
      if (phase_pos[target] <= breakage_phase[i]) return "not-later"
      return ""
    }
    END {
      flush_phase()
      for (i = 1; i <= breakages; i++) {
        reason = breakage_reason(i)
        if (reason != "") breakage_invalid = breakage_invalid " " breakage_line[i] ":" reason
      }
      printf "breakages=%d\n", breakages
      printf "breakage_invalid=%s\n", breakage_invalid
      printf "phases=%d\n", phases
      printf "untagged=%s\n", untagged
      printf "missing_sanity=%s\n", missing_sanity
      printf "tagged=%d\n", tagged
      printf "decisions_table=%d\n", decisions_table
      printf "decision_rows=%d\n", decision_rows
      printf "blast_level=%d\n", blast_level
    }
  ' "$plan"
)" || die "could not parse: $plan"

field() { printf '%s\n' "$structural" | sed -n "s/^$1=//p"; }

phases="$(field phases)"
untagged="$(field untagged)"
missing_sanity="$(field missing_sanity)"
tagged="$(field tagged)"
decisions_table="$(field decisions_table)"
decision_rows="$(field decision_rows)"
blast_level="$(field blast_level)"
breakages="$(field breakages)"
breakage_invalid="$(field breakage_invalid)"

failed=0
report() {
  local name="$1" ok="$2" detail="$3"
  if [[ "$ok" == pass ]]; then
    printf 'criterion=%s status=pass %s\n' "$name" "$detail"
  else
    printf 'criterion=%s status=fail %s\n' "$name" "$detail"
    failed=1
  fi
}

if [[ "$phases" -ge 1 ]]; then
  report phases pass "count=$phases"
else
  report phases fail "count=0 (no '### Phase N:' heading outside a code fence)"
fi

if [[ -z "${untagged// /}" ]]; then
  report status-tags pass "untagged=none"
else
  report status-tags fail "untagged=${untagged# }"
fi

if [[ "$phases" -ge 1 && -z "${missing_sanity// /}" ]]; then
  report sanity-checks pass "missing=none"
elif [[ "$phases" -lt 1 ]]; then
  report sanity-checks fail "missing=no-phases"
else
  report sanity-checks fail "missing=${missing_sanity# }"
fi

if [[ "$tagged" -eq 0 ]]; then
  report decisions pass "tagged=0"
elif [[ "$decisions_table" -eq 1 && "$decision_rows" -ge 1 ]]; then
  report decisions pass "tagged=$tagged rows=$decision_rows"
elif [[ "$decisions_table" -eq 1 ]]; then
  report decisions fail "tagged=$tagged rows=0 (the Decision table has no row)"
else
  report decisions fail "tagged=$tagged (no '| Decision | What it changes' table)"
fi

if [[ "$blast_level" -eq 1 ]]; then
  report blast-radius pass "level=named"
else
  report blast-radius fail "level=missing (no Blast radius line naming LOW, MEDIUM, HIGH or CRITICAL)"
fi

if [[ -z "${breakage_invalid// /}" ]]; then
  report planned-breakage pass "declarations=$breakages"
else
  invalid="${breakage_invalid# }"
  report planned-breakage fail "invalid=${invalid// /,}"
fi

readonly max_path_hits=20

# /Users and /home must begin a path: not preceded by a path-continuation character.
path_hits="$(
  tr -d '\r' <"$plan" |
    grep -nE '(^|[^A-Za-z])[A-Za-z]:[\\/]|(^|[^A-Za-z0-9_./-])/(Users|home)/[A-Za-z0-9_]' |
    grep -v '<!-- path-example -->'
)"
if [[ -z "$path_hits" ]]; then
  report portable-paths pass "hits=0"
else
  total_hits="$(printf '%s\n' "$path_hits" | wc -l | tr -d ' ')"
  report portable-paths fail "hits=$total_hits"
  printf '%s\n' "$path_hits" | head -n "$max_path_hits" | sed 's/^/path-hit=/'
  if [[ "$total_hits" -gt "$max_path_hits" ]]; then
    printf 'path-hit-truncated=%s\n' "$((total_hits - max_path_hits))"
  fi
fi

if [[ "$failed" -eq 0 ]]; then
  printf 'phases=%s status=ok\n' "$phases"
  exit 0
fi
printf 'phases=%s status=fail\n' "$phases"
exit 1
