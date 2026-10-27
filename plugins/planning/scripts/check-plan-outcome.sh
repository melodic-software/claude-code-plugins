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
#                   `| Decision | What it changes ...` table has at least one row.
#                   A tag may carry an id, `[EXEC-SHAPE D4]`, and the row for that
#                   decision starts its first column with the same id (`| D4 Ignore
#                   file first | ...`). An id is a capital letter, up to two more
#                   letters, then letters or digits (D4, DX12, D4a); one id per tag. The criterion fails on a tag
#                   id with no row (`id-without-row=`) and on a row id no tag cites
#                   (`row-without-tag=`); several tags may cite one row. Pass prints
#                   `mapped=<n>`, the distinct tag ids that have a row. A bare tag
#                   with no id still passes, with a `warning=bare-tag` line naming it
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
#   criteria        every acceptance criterion id maps to a phase. A criterion is a
#                   list item under an `Acceptance criteria` heading; its id opens
#                   the item after any checkbox or bold, `AC` then digits
#                   (`- AC3: ...`). A phase names the ids it satisfies on a
#                   `**Satisfies:** AC1, AC3` line (a list marker before it is
#                   allowed); one outside a phase section maps nothing. Fails on a
#                   criterion id no phase satisfies (`unmapped=`), a satisfied id no
#                   criterion defines (`unknown=`), a criterion with no id once any
#                   has one (`without-id=<line>`) and an id defined twice
#                   (`duplicate=`). Pass prints `ids=<n> mapped=<n>`. A plan with no
#                   id anywhere passes `ids=0`, with a `warning=criteria-without-ids`
#                   line when it has criteria; an item reading `none ...` is not one
#
# "No phase does Out-of-scope work, and every phase traces to a criterion" is
# judgment and stays in the skill's prose; this gate does not claim it.
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
    BEGIN { ID_RE = "^[A-Z][A-Za-z]?[A-Za-z]?[0-9]+[A-Za-z0-9]*" }
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
      in_ac = (tolower(heading) ~ /^#+[ \t]+acceptance criteria[ \t:]*$/)
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
    in_ac && /^ ?[-*+][ \t]+/ {
      text = $0
      sub(/^ ?[-*+][ \t]+/, "", text)
      sub(/^\[[ xX]\][ \t]+/, "", text)
      sub(/^[*_]+/, "", text)
      if (match(text, /^AC[0-9]+/) && substr(text, RLENGTH + 1, 1) !~ /[A-Za-z0-9]/) {
        id = substr(text, 1, RLENGTH)
        if (id in ac_def) ac_dup = ac_dup " " id
        else { ac_n++; ac_order[ac_n] = id; ac_def[id] = 1 }
      } else if (tolower(text) !~ /^none([^a-z]|$)/) ac_noid = ac_noid " " NR
    }
    in_phase && /^[ \t]*([-*+][ \t]+)?\*\*Satisfies:\*\*/ {
      text = $0
      sub(/^[ \t]*([-*+][ \t]+)?\*\*Satisfies:\*\*/, "", text)
      while (match(text, /AC[0-9]+/)) {
        id = substr(text, RSTART, RLENGTH)
        text = substr(text, RSTART + RLENGTH)
        if (!(id in sat)) { sat_n++; sat_order[sat_n] = id; sat[id] = 1 }
      }
    }
    {
      if (in_phase && $0 ~ /Sanity Check/) phase_sanity = 1
      if ($0 ~ /^[ \t]*\|[ \t]*Decision[ \t]*\|[ \t]*What it changes/) { in_table = 1; decisions_table = 1; next }
      if (in_table && $0 !~ /^[ \t]*\|/) in_table = 0
      if (in_table) {
        if ($0 !~ /^[ \t]*\|[ \t:|-]*$/) {
          decision_rows++
          cell = $0
          sub(/^[ \t]*\|[ \t]*/, "", cell)
          sub(/[ \t]*\|.*/, "", cell)
          sub(/^[*_`\[ \t]+/, "", cell)
          if (match(cell, ID_RE)) row_id[substr(cell, RSTART, RLENGTH)] = 1
        }
        next
      }
      rest = $0
      while (match(rest, /\[(EXEC-SHAPE|FALLBACK)([^]A-Za-z][^]]*)?\]/)) {
        tag = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        tagged++
        inner = tag
        sub(/^\[(EXEC-SHAPE|FALLBACK)/, "", inner)
        sub(/\]$/, "", inner)
        sub(/^[ \t]+/, "", inner)
        if (match(inner, ID_RE)) tag_id[substr(inner, RSTART, RLENGTH)] = 1
        else { bare_n++; bare_tag[bare_n] = NR ":" tag }
      }
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
      for (id in tag_id) {
        if (id in row_id) mapped++
        else no_row = no_row " " id
      }
      # A plan with only bare tags passes: a row that merely starts like an id (S3, UTF8) is not one.
      for (id in tag_id) have_tag_id = 1
      if (have_tag_id) for (id in row_id) if (!(id in tag_id)) no_tag = no_tag " " id
      printf "mapped=%d\n", mapped
      printf "id_without_row=%s\n", no_row
      printf "row_without_tag=%s\n", no_tag
      for (i = 1; i <= bare_n; i++) printf "bare_tag=%s\n", bare_tag[i]
      for (i = 1; i <= ac_n; i++) {
        if (ac_order[i] in sat) ac_mapped++
        else ac_unmapped = ac_unmapped " " ac_order[i]
      }
      for (i = 1; i <= sat_n; i++) if (!(sat_order[i] in ac_def)) ac_unknown = ac_unknown " " sat_order[i]
      printf "ac_ids=%d\n", ac_n
      printf "ac_cited=%d\n", sat_n
      printf "ac_mapped=%d\n", ac_mapped
      printf "ac_unmapped=%s\n", ac_unmapped
      printf "ac_unknown=%s\n", ac_unknown
      printf "ac_noid=%s\n", ac_noid
      printf "ac_dup=%s\n", ac_dup
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
mapped="$(field mapped)"
id_without_row="$(field id_without_row)"
row_without_tag="$(field row_without_tag)"
breakages="$(field breakages)"
breakage_invalid="$(field breakage_invalid)"
ac_ids="$(field ac_ids)"
ac_cited="$(field ac_cited)"
ac_mapped="$(field ac_mapped)"
ac_unmapped="$(field ac_unmapped)"
ac_unknown="$(field ac_unknown)"
ac_noid="$(field ac_noid)"
ac_dup="$(field ac_dup)"

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
  detail="tagged=$tagged rows=$decision_rows mapped=$mapped"
  [[ -z "${id_without_row// /}" ]] || detail+=" id-without-row=$(sed 's/^ //; s/ /,/g' <<<"$id_without_row")"
  [[ -z "${row_without_tag// /}" ]] || detail+=" row-without-tag=$(sed 's/^ //; s/ /,/g' <<<"$row_without_tag")"
  if [[ "$detail" == *-without-* ]]; then
    report decisions fail "$detail"
  else
    report decisions pass "$detail"
  fi
elif [[ "$decisions_table" -eq 1 ]]; then
  report decisions fail "tagged=$tagged rows=0 (the Decision table has no row)"
else
  report decisions fail "tagged=$tagged (no '| Decision | What it changes' table)"
fi

printf '%s\n' "$structural" | sed -n 's/^bare_tag=\(.*\)$/warning=bare-tag line \1 (no id, so it maps to no row)/p'

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

commas() { sed 's/^ //; s/ /,/g' <<<"$1"; }
if [[ "$ac_ids" -eq 0 && "$ac_cited" -eq 0 ]]; then
  report criteria pass "ids=0"
  if [[ -n "${ac_noid// /}" ]]; then
    printf 'warning=criteria-without-ids count=%s (no acceptance criterion carries an AC<n> id, so none is traced to a phase)\n' "$(wc -w <<<"$ac_noid" | tr -d ' ')"
  fi
else
  detail="ids=$ac_ids mapped=$ac_mapped"
  [[ -z "${ac_unmapped// /}" ]] || detail+=" unmapped=$(commas "$ac_unmapped")"
  [[ -z "${ac_unknown// /}" ]] || detail+=" unknown=$(commas "$ac_unknown")"
  [[ -z "${ac_noid// /}" ]] || detail+=" without-id=$(commas "$ac_noid")"
  [[ -z "${ac_dup// /}" ]] || detail+=" duplicate=$(commas "$ac_dup")"
  if [[ "$detail" == "ids=$ac_ids mapped=$ac_mapped" ]]; then
    report criteria pass "$detail"
  else
    report criteria fail "$detail"
  fi
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
