#!/usr/bin/env bash

set -uo pipefail

usage() {
  cat <<'EOF'
Mechanical gate for an /interview open-question register.

`/interview` writes one register row per question at the moment the round is
ASKED — before any reply arrives. This gate reads that register and decides,
with NO model involvement, whether any question is still unresolved. It exists
because the reported failure is a question that was asked, went unanswered
across a reply about an unrelated topic, and was never re-surfaced: a check
that consulted the conversation could not see it, but a row left at `open` on
disk is visible forever.

What this gate does NOT prove: it grades the interview's own bookkeeping, so a
question that was never registered is invisible to it. The ask-time write rule
is what makes the register independent of the answer — registering is a
byproduct of asking, not of resolving. The structural checks below (contiguous
Q numbering, no duplicate ids) are the affordable defense against a row that
was silently dropped after being written; a question never written at all is
out of reach of any file-based check and is the skill's contract to keep.

Exit 0 = every registered question is resolved (register is clean) and, with
         --procedure, the procedure checks below pass
Exit 1 = at least one question is still `open`, `discussing` or `superseded-by-plan` (the
         contract is not locked), --procedure found a procedure defect
         (the register is gradeable but the interview did not complete its
         own procedure; fix the ledger or Brief and re-run), the named
         Brief is stamped `UNCONFIRMED` (the user has not confirmed the
         latest restatement, or none was posted; `brief=unconfirmed`), or a
         stamped Brief still carries the export's placeholder Goal or
         criteria while answered rows exist (`brief=placeholder`)
Exit 2 = ungradeable: no ledger, no register section, a duplicate register or
         deferred-questions heading, an unterminated fenced block, an empty
         register, a malformed row, an unknown status, a duplicate, an
         out-of-order or a missing (gap) Q id that no `- gap | Q<a>-Q<b> | <why>`
         line declares, a malformed gap line, a declared gap that covers a
         row, an unfenced `- Q<N> |` row
         outside the register section (any heading ends the section, a
         sub-heading inside it included), a named `--brief` that is
         missing, or a `--surface` that is missing, comes without `--brief`
         and `--procedure`, or cannot be exported. Row errors are collected
         in one pass, each on stderr with its own ledger line, and the
         verdict keeps the counts of the rows that parsed.

Usage:
  bash check-open-questions.sh --ledger <interview-checklist.md> [--brief <PLAN.md>] [--procedure] [--surface <data_dir>]
  bash check-open-questions.sh --help

Register row shape (inside the ledger's `## Open-question register` section):
  - Q1 | answered | round 1 | <question> | <resolution>
Statuses: open | discussing | answered | deferred | withdrawn | blocked | superseded-by-plan
`discussing` is an `open` question the user asked to talk through: it counts
in `open=<n>` and blocks the gate the same way.
`superseded-by-plan` is NOT terminal: a plan displaced the user's answer and
the user has not reconfirmed it. It counts as `superseded=<n>` and blocks the
gate exactly like `open`.
A row of any status whose resolution ends `stale:: C<N>[, C<N>...]` was not
checked against those constraints: the export writes it, the verdict adds
`stale=<n>`, and the gate blocks exactly as it does on `open` until Claude
revises or reconfirms the question. A ledger with no such row reads as before.
Register tags before it (`kind::`, `problem::`, `depends::`, `reopened::`,
`recheck::`, `topic:: <plain words>`) are not part of the resolution.

--brief is OPT-IN and cross-checks that every `deferred` and `blocked` row
reached the Brief's `### Deferred questions` section, keyed by its `Q<N>` id.
A row the ledger retired but the contract never records is the same silent
hole this gate exists to refuse. When --brief is omitted the verdict says
`brief=unchecked` rather than omitting the field: a check the caller only
appeared to get is worse than one it knowingly skipped. The named Brief must
exist. The deferred cross-check reads it only when the register retired a row:
with nothing to look up it is satisfied (`brief=ok`), and the Brief's own
headings and fences are not graded, so a stray fence in an unrelated section
of a large planning document cannot fail a clean register.

--brief also fails (exit 1, `brief=unconfirmed`) on the stamp
`- Restatement: UNCONFIRMED (latest rev <N>)` that `round.sh export-brief` writes
while the newest restatement has no Confirm, and on
`- Restatement: UNCONFIRMED (no restatement posted)` it writes with none. A
stamped Brief with an answered row fails (exit 1, `brief=placeholder`) when
its Goal's first paragraph equals its `- Page title:` line (the export's
fallback without a confirmed goal) or its only acceptance criterion is
`- none recorded in the interview surface`. A Brief with no `- Restatement:`
line (hand-written) is graded for none of this. A line inside a fenced block
is documentation.

--procedure is OPT-IN and adds checks a script can derive from the ledger, so
a caller that omits it keeps every verdict and exit code above unchanged:
  - round numbers in the register rows run contiguously from 1 (a `round`
    field that is not `round <N>` or `round <N> (added in round <M>)`, with
    N, M >= 1, counts as a defect)
  - every `answered`, `deferred`, `withdrawn` and `blocked` row carries a
    non-empty resolution (the fifth field)
  - with --brief, the Brief holds every section of the literal Brief template:
    TLDR, Problem, Goal, Work size, Constraints, Acceptance criteria,
    Captured assumptions, Out-of-scope, Deferred questions (headings only;
    content is not graded), plus Intent when the Brief carries a
    `- Restatement:` stamp (a page export)
  - with --brief, the Goal carries a `- Finish line:` line whose text is
    non-empty and not `not settled yet`
  - with --surface <data_dir> (the interview page's data dir), the gate runs
    `surface/round.sh export-brief --ledger <ledger>` on that data dir and
    the Brief holds every section that export writes (Decisions among them
    when the confirmed restatement has decisions), and its Intent section
    holds every line of the export's Intent: the intent paragraph and each
    live ask, note, own answer and note typed on a choice, compared with
    whitespace runs made one space. Its TLDR and Acceptance criteria hold
    every line the export writes there, and its Decisions hold each export
    line as many times as the export writes it and no other line naming a
    Q<N>, so a decision repeated, put back in an earlier form or contradicted
    by a second line naming its Q<N> fails. Needs Python 3, as the page does
  - no Step-exit checkbox (`- [ ] Step <N> exit ...`) is unchecked; a skipped
    exit step is ticked with `SKIPPED: <reason>`
  - every row of the ledger's `## Assumption sweep` section,
    `- S<N> | sweep <M> | <category> | <class> | <source> | <disposition>`,
    has a disposition: `Q<N>` naming a register row, `F<N>` naming a
    `## Self-answered facts` line whose basis quotes its source (`"..."`) with
    a file:line or a URL, or `deferred: <where>`. A `decision` or `person`
    item, or any `unstated-value` item, never takes `F<N>`, nor `deferred:`
    unless it is `hedged`. Only a
    `hedged` item's `Q<N>` may be a row its source names; any other item
    becomes a new row, above the sweep's `- sweep <M> | register through Q<N>`
    line, which precedes the sweep's rows and names the register's last row
    when that sweep ran. S ids run
    contiguously within each sweep, from S1 or on from the last sweep's
    highest S id, no S row sits outside the section,
    a section with no item says `- none`, and a ticked Step 2 exit that is
    not `SKIPPED` needs the section
  - with --brief, the ledger's `## Glossary lookup` section holds a line
    (the glossary read and the terms it held or lacked, `none found` with the
    paths searched, or `off (domain_docs)`), else `missing=glossary-lookup`;
    and a line under `## ADR outcomes` names each `answered` row's Q<N> left
    of its first `|` (`- Q<N> (<decision>) | record: <why>`), else
    `missing=adr-outcome:Q<N>`, unless a line there starts
    `every other decision`, which covers every row
Each defect is named on stderr. Without --procedure the verdict says
`procedure=unchecked`, the same convention as `brief=unchecked`. A gradeable
register with a procedure defect exits 1 with `status=incomplete` (`open` when
a row is also unresolved); ungradeable stays exit 2 with `procedure=unchecked`.
With --procedure the named Brief is always read, so an unterminated fence in
it is ungradeable even when the register retired nothing.

What stays a model judgment and is NOT checked here: whether the Step 1
survey genuinely grounded the questions, whether a quoted source says what
the F-line claims (the interview's fresh-context quote check owns that),
whether every item the sweep returned was recorded, whether the domain was classified,
whether the register was written at ask-time rather than answer-time, and
whether the frontier was recomputed between rounds. A file written after the
fact looks identical to one written at ask-time.

Fenced blocks (``` or ~~~) are documentation in both files. A fence closes
only on a line of the same character at least as long as its opener with
nothing else on it, so a four-backtick fence can quote a three-backtick
example and a `~~~` line inside a backtick fence is content.

Output (stdout, greppable):
  `registered=<n> open=<n> deferred=<n> blocked=<n> withdrawn=<n> answered=<n> superseded=<n> brief=<ok|unchecked|unconfirmed|placeholder> status=<clean|open|incomplete|ungradeable> procedure=<ok|unchecked|fail>`
EOF
}

# The one definition of "inside a fence", shared by heading_matches and
# extract_section so the two cannot disagree about what a heading is; the row
# loop below reads the state these emit rather than detecting fences a third
# time. fence_line(line) returns 1 when the line is a fence delimiter (and
# updates the `fenced` state), 0 otherwise. A fence opens on three or more
# backticks or tildes; it closes only on a line of the SAME character, at least
# as LONG as the opener, with nothing but whitespace after it (a trailing CR
# counts as whitespace, so a CRLF closer closes). Any other fence-shaped line
# while a fence is open is content: a four-backtick fence can quote a
# three-backtick example, and `~~~` inside a backtick fence does not close it.
fence_awk='
  function fence_line(line,    run, ch, n) {
    if (match(line, /^[[:space:]]*(```+|~~~+)/) == 0) { return 0 }
    run = substr(line, RSTART, RLENGTH)
    sub(/^[[:space:]]*/, "", run)
    ch = substr(run, 1, 1)
    n = length(run)
    if (!fenced) { fenced = 1; fence_ch = ch; fence_len = n; return 1 }
    if (ch == fence_ch && n >= fence_len && substr(line, RSTART + RLENGTH) ~ /^[[:space:]]*$/) {
      fenced = 0
      return 1
    }
    return 0
  }
'

squash_awk='
  function squash(s) {
    gsub(/[[:space:]]+/, " ", s)
    sub(/^ /, "", s)
    sub(/ $/, "", s)
    return s
  }
'

# List the headings whose text matches `pattern` (case-insensitively, so a ledger
# that title-cases the section still grades), one per line as
# `<line number><TAB><heading>`. A heading-shaped line inside a fenced block is
# documentation, never a heading: the template's own register carries a fenced
# bash block whose `# Step 3 ...` comment lines would otherwise count, and a
# fenced comment must neither bind a section nor terminate one. A trailing CR is
# stripped so a CRLF ledger names its heading cleanly. No output means no match.
# A fence still open at end of file exits 4: every heading after it was hidden,
# and hiding is the silent drop this gate exists to refuse.
heading_matches() {
  awk -v pattern="$1" "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    /^#+[[:space:]]/ && tolower($0) ~ pattern {
      heading = $0
      sub(/\r$/, "", heading)
      print NR "\t" heading
    }
    END { if (fenced) { exit 4 } }
  ' "$2"
}

match_count() { printf '%s\n' "$1" | wc -l | tr -d '[:space:]'; }
match_lines() { printf '%s\n' "$1" | cut -f1 | paste -sd, - | sed 's/,/, /g'; }

# Print a section body: every line after `start` (the matched heading's line
# number) up to the next unfenced heading of any level or end of file, each
# prefixed `<marker><TAB>` where the marker is `f` for a fence delimiter or a
# line inside a fence and `.` for a live line. The marker carries the fence
# state to the caller so no second fence detector is needed. Taking the line
# number rather than re-matching a pattern binds the body graded to the heading
# the caller already named in its diagnostics. A fence opened in the section and
# never closed exits 4: the row loop would otherwise skip every row after it as
# documentation and grade the register clean with a question hidden. A caller
# that ran heading_matches first never sees that exit (a heading only binds
# outside a fence, so the whole-file check fires first); the guard is for a
# caller that extracts by line number without it.
extract_section() {
  awk -v start="$1" "$fence_awk"'
    NR <= start { next }
    fence_line($0) { print "f\t" $0; next }
    fenced { print "f\t" $0; next }
    /^#+[[:space:]]/ { exit }
    { print ".\t" $0 }
    END { if (fenced) { exit 4 } }
  ' "$2"
}

rows_outside() {
  awk -v lo="$1" -v hi="$2" "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    /^#+[[:space:]]/ { reopened = (tolower($0) ~ /^#+[[:space:]]+reopened answers[[:space:]]*$/) }
    NR >= lo && NR <= hi { next }
    reopened && /^[[:space:]]*-[[:space:]]+[Qq][1-9][0-9]*[[:space:]]*[|][[:space:]]*round[[:space:]]+[1-9][0-9]*[[:space:]]*[|][[:space:]]*was:.*[|][[:space:]]*fact:/ { next }
    /^[[:space:]]*-[[:space:]]+[Qq][0-9]+[[:space:]]*[|]/ { print NR }
  ' "$3"
}

brief_bounds() {
  local brief_h2 brief_h2_status
  brief_lo=0
  brief_hi=999999999
  brief_h2="$(heading_matches '^##[[:space:]]' "$brief")"
  brief_h2_status=$?
  if [[ "$brief_h2_status" -eq 4 ]]; then
    [[ "${1-}" == "lenient" ]] ||
      die_ungradeable "unterminated fenced block in: $brief (every heading after it is hidden; close the fence)"
  elif [[ "$brief_h2_status" -ne 0 ]]; then
    die_ungradeable "could not read the headings of: $brief"
  fi
  brief_lo="$(printf '%s\n' "$brief_h2" | awk -F'\t' 'tolower($2) ~ /^##[[:space:]]+brief[[:space:]]*$/ { print $1; exit }')"
  if [[ -n "$brief_lo" ]]; then
    brief_hi="$(printf '%s\n' "$brief_h2" | awk -F'\t' -v lo="$brief_lo" '$1 > lo { print $1; exit }')"
    brief_hi="${brief_hi:-999999999}"
  else
    brief_lo=0
  fi
}

brief_fields() {
  awk -v lo="$1" -v hi="$2" "$fence_awk$squash_awk"'
    NR <= lo || NR >= hi { next }
    fence_line($0) { next }
    fenced { next }
    { text = squash($0) }
    /^#+[[:space:]]/ {
      section = tolower(text)
      sub(/^#+ /, "", section)
      goal_state = 0
      next
    }
    !titled && text ~ /^- Page title: / {
      titled = 1
      print "title\t" substr(text, 15)
      next
    }
    section == "goal" && goal_state < 2 {
      if (text ~ /^[-*+] /) { goal_state = 2; next }
      if (text == "") { if (goal_state == 1) { goal_state = 2 }; next }
      goal_state = 1
      print "goal\t" text
      next
    }
    section == "acceptance criteria" && text != "" { print "criteria\t" text }
  ' "$3"
}

heading_texts() {
  awk -v lo="$1" -v hi="$2" "$fence_awk$squash_awk"'
    NR <= lo || NR >= hi { next }
    fence_line($0) { next }
    fenced { next }
    /^#+[[:space:]]/ {
      text = tolower($0)
      sub(/^#+/, "", text)
      print squash(text)
    }
  ' "$3"
}

section_lines() {
  awk -v name="$1" -v lo="$2" -v hi="$3" "$fence_awk$squash_awk"'
    NR <= lo || NR >= hi { next }
    fence_line($0) { next }
    fenced { next }
    { text = squash($0) }
    /^#+[[:space:]]/ {
      section = tolower(text)
      sub(/^#+ /, "", section)
      next
    }
    section ~ ("^(" name ")$") && text != "" { print text }
  ' "$4"
}

need_export_lines() {
  local have want
  have=$'\n'"$(section_lines "$1" "$brief_lo" "$brief_hi" "$brief")"$'\n'
  while IFS= read -r want; do
    [[ -z "$want" || "$have" == *$'\n'"$want"$'\n'* ]] ||
      proc_problem "Brief's $2 is missing a line the page export writes: $want"
  done <<<"$(section_lines "$1" 1 "$export_hi" "$expected_brief")"
}

count_line() {
  local n=0 line
  while IFS= read -r line; do
    [[ "$line" != "$1" ]] || n=$((n + 1))
  done <<<"$2"
  printf '%s' "$n"
}

check_decisions() {
  local want want_n have_n seen=$'\n' export_lines brief_lines
  export_lines="$(section_lines decisions 1 "$export_hi" "$expected_brief")"
  brief_lines="$(section_lines decisions "$brief_lo" "$brief_hi" "$brief")"
  while IFS= read -r want; do
    [[ -n "$want" && "$seen" != *$'\n'"$want"$'\n'* ]] || continue
    seen="$seen$want"$'\n'
    want_n="$(count_line "$want" "$export_lines")"
    have_n="$(count_line "$want" "$brief_lines")"
    if [[ "$have_n" -lt "$want_n" ]]; then
      proc_problem "Brief's Decisions is missing a line the page export writes: $want"
    elif [[ "$have_n" -gt "$want_n" ]]; then
      proc_problem "Brief's Decisions has a line $have_n times that the page export writes $want_n time(s): $want"
    fi
  done <<<"$export_lines"
  no_stray_decisions decisions Decisions
  no_stray_decisions constraints Constraints
}

no_stray_decisions() {
  local have export_lines
  local qn_re='(^|[^A-Za-z0-9])[Qq][1-9][0-9]*([^0-9A-Za-z_]|$)'
  export_lines=$'\n'"$(section_lines "$1" 1 "$export_hi" "$expected_brief")"$'\n'
  while IFS= read -r have; do
    [[ -n "$have" && "$have" =~ $qn_re ]] || continue
    [[ "$export_lines" == *$'\n'"$have"$'\n'* ]] ||
      proc_problem "Brief's $2 has a line the page export does not write (a decision in another form, or a second line for it): $have"
  done <<<"$(section_lines "$1" "$brief_lo" "$brief_hi" "$brief")"
}

trim_into() {
  trimmed="${1#"${1%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
}

proc_problem() { proc_problems="$proc_problems$1"$'\n'; }

live_section_lines() {
  local matches text out=""
  matches="$(heading_matches "$1" "$ledger")"
  [[ -n "$matches" ]] || return 0
  while IFS= read -r text; do
    [[ "${text%%$'\t'*}" == "." ]] || continue
    text="${text#*$'\t'}"
    [[ "$text" =~ [^[:space:]] ]] && out="$out$text"$'\n'
  done <<<"$(extract_section "${matches%%$'\t'*}" "$ledger")"
  printf '%s' "$out"
}

check_records() {
  local outcomes="" line id
  [[ -n "$(live_section_lines '^#+[[:space:]]+glossary lookup[[:space:]]*$')" ]] ||
    proc_problem "missing=glossary-lookup: no line under '## Glossary lookup'; record the glossary read and the terms it held or lacked, 'none found' with the paths searched, or 'off (domain_docs)'"
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*([-*+][[:space:]]+)?[Ee]very\ other\ decision ]] && return
    [[ "$line" == *"|"* ]] || continue
    outcomes="$outcomes ${line%%|*}"$'\n'
  done <<<"$(live_section_lines '^#+[[:space:]]+adr outcomes[[:space:]]*$')"
  for id in $answered_ids; do
    [[ "$outcomes" =~ (^|[^A-Za-z0-9])$id([^0-9]|$) ]] ||
      proc_problem "missing=adr-outcome:$id: no line under '## ADR outcomes' names $id; add '- $id (<decision>) | record: <why>' or '| declined: <reason>', or close the section with '- every other decision | declined: <reason>'"
  done
}

ledger=""
brief=""
brief_named=0
procedure_on=0
surface=""
surface_named=0

die_ungradeable() {
  echo "error: $1" >&2
  echo "registered=0 open=0 deferred=0 blocked=0 withdrawn=0 answered=0 superseded=0 brief=unchecked status=ungradeable procedure=unchecked"
  exit 2
}

headings_or_die() {
  matches="$(heading_matches "$1" "$2")"
  case $? in
  0) ;;
  4) die_ungradeable "unterminated fenced block in: $2 (every heading after it is hidden; close the fence)" ;;
  *) die_ungradeable "could not read the headings of: $2" ;;
  esac
}

# shellcheck source=lib/check-sweep.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/check-sweep.sh" ||
  die_ungradeable "could not load lib/check-sweep.sh beside this script"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  --ledger)
    ledger="${2-}"
    shift 2 || die_ungradeable "--ledger needs a value"
    ;;
  --ledger=*)
    ledger="${1#*=}"
    shift
    ;;
  --brief)
    brief="${2-}"
    brief_named=1
    shift 2 || die_ungradeable "--brief needs a value"
    ;;
  --brief=*)
    brief="${1#*=}"
    brief_named=1
    shift
    ;;
  --procedure)
    procedure_on=1
    shift
    ;;
  --surface)
    surface="${2-}"
    surface_named=1
    shift 2 || die_ungradeable "--surface needs a value"
    ;;
  --surface=*)
    surface="${1#*=}"
    surface_named=1
    shift
    ;;
  *)
    die_ungradeable "unknown argument: $1"
    ;;
  esac
done

[[ -n "$ledger" ]] || die_ungradeable "--ledger <path> is required"
[[ -f "$ledger" ]] || die_ungradeable "--ledger not found: $ledger"

# A named-but-missing --brief exits 2 rather than downgrading to `unchecked`:
# the caller asked for the cross-check, so silently not running it would report
# a pass the caller never earned.
if [[ "$brief_named" -eq 1 ]]; then
  [[ -n "$brief" ]] || die_ungradeable "--brief needs a value"
  [[ -f "$brief" ]] || die_ungradeable "--brief not found: $brief"
fi
if [[ "$surface_named" -eq 1 ]]; then
  [[ -n "$surface" ]] || die_ungradeable "--surface needs a value"
  [[ "$brief_named" -eq 1 && "$procedure_on" -eq 1 ]] ||
    die_ungradeable "--surface needs --brief and --procedure"
  [[ -d "$surface" ]] || die_ungradeable "--surface not found: $surface"
fi

headings_or_die 'open-question register' "$ledger"
register_matches="$matches"
[[ -n "$register_matches" ]] || die_ungradeable "no '## Open-question register' section in: $ledger"

register_count="$(match_count "$register_matches")"
if [[ "$register_count" -gt 1 ]]; then
  die_ungradeable "$register_count headings match 'open-question register' in: $ledger (lines $(match_lines "$register_matches")); the gate reads exactly one section, so delete the template's instructional copy and keep the single live register"
fi

register_line="${register_matches%%$'\t'*}"
register_heading="${register_matches#*$'\t'}"
where="register '$register_heading' at line $register_line"

section="$(extract_section "$register_line" "$ledger")"
extract_status=$?
if [[ "$extract_status" -eq 4 ]]; then
  die_ungradeable "unterminated fenced block in the register section; rows after it would be skipped as documentation ($where in: $ledger)"
elif [[ "$extract_status" -ne 0 ]]; then
  die_ungradeable "could not read the register section from: $ledger ($where)"
fi

registered=0
open_count=0
stale_count=0
recheck_count=0
stale_list='stale:: C[0-9]+(, C[0-9]+)*'
stale_tail_re='(^|\] |(^|[^\\])(\\\\)*; )'"$stale_list"'$'
qlist='Q[1-9][0-9]*(, Q[1-9][0-9]*)*'
topic_re='[^;|\[:space:]]([^;|\]*[^;|\[:space:]])?'
tag_re='(kind:: discovery|problem:: P[1-9][0-9]*|depends:: '"$qlist"'|reopened:: round [1-9][0-9]*|recheck:: '"$qlist"'|topic:: '"$topic_re"')'
recheck_tail_re='(^|\] |(^|[^\\])(\\\\)*; )('"$tag_re"'; )*recheck:: '"$qlist"'(; '"$tag_re"')*(; '"$stale_list"')?$'
tags_only_re='^(\[[^]]*\][[:space:]]*)?'"$tag_re"'(; '"$tag_re"')*(; '"$stale_list"')?$'
answered=0
deferred=0
withdrawn=0
blocked=0
superseded=0
seen_ids=" "
deferred_ids=""
answered_ids=""
ids_in_order=""
declared_gaps=""
max_id=0
rounds_seen=" "
max_round=0
proc_problems=""
row_errors=""
lineno=0

row_error() { row_errors="${row_errors}line $lineno: $1"$'\n'; }

track_id() {
  dup=0
  case "$seen_ids" in
  *" Q$1 "*)
    row_error "duplicate question id: Q$1"
    dup=1
    return
    ;;
  *) ;;
  esac
  seen_ids="${seen_ids}Q$1 "
  ids_in_order="$ids_in_order$1 "
  if [[ "$1" -lt "$max_id" ]]; then
    row_error "question id out of order: Q$1 follows Q$max_id"
  else
    max_id="$1"
  fi
}

row_candidate_re='^[[:space:]]*-[[:space:]]+[Qq][0-9]+([^0-9]|$)'
gap_candidate_re='^[[:space:]]*-[[:space:]]+[Gg]ap[[:space:]]*\|'
gap_line_re='^[[:space:]]*-[[:space:]]+[Gg]ap[[:space:]]*\|[[:space:]]*[Qq]([1-9][0-9]*)[[:space:]]*-[[:space:]]*[Qq]([1-9][0-9]*)[[:space:]]*\|[[:space:]]*[^[:space:]]'

round_field_re='^[Rr]ound[[:space:]]+([1-9][0-9]*)([[:space:]]+\([Aa]dded in [Rr]ound[[:space:]]+[1-9][0-9]*\))?$'

skipped_fenced_row=0
while IFS= read -r line; do
  lineno=$((lineno == 0 ? register_line + 1 : lineno + 1))
  marker="${line%%$'\t'*}"
  line="${line#*$'\t'}"
  if [[ "$marker" == "f" ]]; then
    if [[ "$line" =~ $row_candidate_re ]]; then
      skipped_fenced_row=1
    fi
    continue
  fi

  if [[ "$line" =~ $gap_candidate_re ]]; then
    if [[ "$line" =~ $gap_line_re && "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ]]; then
      declared_gaps="$declared_gaps${BASH_REMATCH[1]} ${BASH_REMATCH[2]} $lineno"$'\n'
    else
      row_error "malformed gap line (expected '- gap | Q<a>-Q<b> | <why these ids have no row>'): $line"
    fi
    continue
  fi

  [[ "$line" =~ $row_candidate_re ]] || continue

  # No leading zeros, and no Q0. `[[ ]]` numeric comparison evaluates its
  # operands in arithmetic context, where a leading-zero numeral is OCTAL: the
  # order test on `Q08` errors to stderr and resolves FALSE, so a misplaced row
  # would silently pass. Rejecting the form outright keeps the comparison total.
  # Q<N> is a running counter from 1, so `Q08` is malformed by the register's
  # own contract anyway.
  [[ "$line" =~ ^[[:space:]]*-[[:space:]]+([Qq]([0-9]+)) ]]
  token="${BASH_REMATCH[1]}"
  num="${BASH_REMATCH[2]}"
  if ! [[ "$num" =~ ^[1-9][0-9]*$ ]]; then
    row_error "malformed question id (expected Q1, Q2, … with no leading zero): $token"
    continue
  fi
  id="Q$num"
  track_id "$num"
  [[ "$dup" -eq 0 ]] || continue

  if ! [[ "$line" =~ ^[[:space:]]*-[[:space:]]+[Qq][0-9]+[[:space:]]*\| ]]; then
    row_error "malformed register row (needs 'Q<N> | status | round | question'): $line"
    continue
  fi

  row="${line#*-}"
  row="${row#"${row%%[![:space:]]*}"}"

  rest="${row#*|}"
  trim_into "${rest%%|*}"
  status_field="$trimmed"

  separators="${row//[!|]/}"
  if [[ "${#separators}" -lt 3 ]]; then
    row_error "malformed register row (needs 'Q<N> | status | round | question'): $line"
    continue
  fi

  after_status="${rest#*|}"
  trim_into "${after_status%%|*}"
  round_field="$trimmed"
  resolution="${after_status#*|}"
  if [[ "$resolution" == *"|"* ]]; then resolution="${resolution##*|}"; else resolution=""; fi
  trim_into "$resolution"
  resolution="$trimmed"
  [[ "$resolution" =~ $stale_tail_re ]] && stale_count=$((stale_count + 1))
  [[ "$resolution" =~ $recheck_tail_re ]] && recheck_count=$((recheck_count + 1))
  [[ "$resolution" =~ $tags_only_re ]] && resolution=""
  if [[ "$round_field" =~ $round_field_re ]]; then
    round_num="${BASH_REMATCH[1]}"
    rounds_seen="$rounds_seen$round_num "
    [[ "$round_num" -gt "$max_round" ]] && max_round="$round_num"
  else
    proc_problem "$id: round field is not 'round <N>' or 'round <N> (added in round <M>)' (N, M >= 1): '$round_field'"
  fi

  # Statuses match case-insensitively without a subprocess per row (a `tr` fork
  # costs over a second per row on a loaded Windows host). nocasematch, not
  # ${var,,}, because macOS /bin/bash is 3.2; scoped so no other match sees it.
  shopt -s nocasematch
  case "$status_field" in
  open | discussing) open_count=$((open_count + 1)) ;;
  answered)
    answered=$((answered + 1))
    answered_ids="$answered_ids$id "
    ;;
  deferred)
    deferred=$((deferred + 1))
    deferred_ids="$deferred_ids$id "
    ;;
  withdrawn) withdrawn=$((withdrawn + 1)) ;;
  superseded-by-plan) superseded=$((superseded + 1)) ;;
  blocked)
    blocked=$((blocked + 1))
    deferred_ids="$deferred_ids$id "
    ;;
  *)
    row_error "unknown status '$status_field' in row: $line"
    shopt -u nocasematch
    continue
    ;;
  esac
  case "$status_field" in
  answered | deferred | withdrawn | blocked)
    [[ -n "$resolution" ]] || proc_problem "$id: $status_field row has an empty resolution"
    ;;
  *) ;;
  esac
  shopt -u nocasematch
  registered=$((registered + 1))
done <<<"$section"

outside_lines="$(rows_outside $((register_line + 1)) "$lineno" "$ledger")" ||
  die_ungradeable "could not read the rows of: $ledger"
for lineno in $outside_lines; do
  row_error "question row outside the register section (any heading ends it, a sub-heading included); move the row into the register, above its next heading"
done

undeclared_gap() {
  local gap="Q$1"
  [[ "$2" -gt "$1" ]] && gap="$gap to Q$2"
  row_errors="${row_errors}gap in question ids: no row for $gap; declare an intended gap with a '- gap | Q$1-Q$2 | <why>' line"$'\n'
}

report_gap() {
  local lo="$1" hi="$2" a b
  while read -r a b _; do
    [[ -n "$a" && "$b" -ge "$lo" ]] || continue
    [[ "$a" -gt "$hi" ]] && break
    [[ "$a" -gt "$lo" ]] && undeclared_gap "$lo" $((a - 1))
    lo=$((b + 1))
    [[ "$lo" -gt "$hi" ]] && return
  done <<<"$sorted_gaps"
  undeclared_gap "$lo" "$hi"
}

sorted_gaps=""
[[ -z "$declared_gaps" ]] || sorted_gaps="$(printf '%s' "$declared_gaps" | sort -n -k1,1)"
prev=0
# shellcheck disable=SC2086 # deliberate: one id per word
for n in $(printf '%s\n' $ids_in_order | sort -n); do
  [[ "$n" -gt $((prev + 1)) ]] && report_gap $((prev + 1)) $((n - 1))
  prev="$n"
done

read -ra row_ids <<<"$ids_in_order"
while read -r a b gap_line; do
  [[ -n "$a" ]] || continue
  for n in ${row_ids[@]+"${row_ids[@]}"}; do
    if [[ "$n" -ge "$a" && "$n" -le "$b" ]]; then
      row_errors="${row_errors}line $gap_line: declared gap Q$a-Q$b covers the row Q$n"$'\n'
      break
    fi
  done
done <<<"$declared_gaps"

if [[ -n "$row_errors" ]]; then
  # Exit 2 stays load-bearing for Step 3 and the --brief path; the verdict
  # keeps the counts of the rows that parsed, so a row error reads apart from
  # a ledger the gate could not read at all (whose counts are all zero).
  printf 'error: row errors in %s in: %s\n' "$where" "$ledger" >&2
  while IFS= read -r row_err; do
    printf 'error: %s\n' "$row_err" >&2
  done <<<"${row_errors%$'\n'}"
  echo "registered=$registered open=$open_count deferred=$deferred blocked=$blocked withdrawn=$withdrawn answered=$answered superseded=$superseded brief=unchecked status=ungradeable procedure=unchecked"
  exit 2
fi

if [[ "$registered" -eq 0 ]]; then
  if [[ "$skipped_fenced_row" -eq 1 ]]; then
    die_ungradeable "the register section holds no question rows in: $ledger ($where; rows inside a fenced block are ignored by design; register rows must be unfenced)"
  fi
  die_ungradeable "the register section holds no question rows in: $ledger ($where)"
fi

brief_state="unchecked"
if [[ "$brief_named" -eq 1 && -z "$deferred_ids" ]]; then
  brief_state="ok"
elif [[ "$brief_named" -eq 1 ]]; then
  headings_or_die 'deferred questions' "$brief"
  brief_matches="$matches"
  if [[ -z "$brief_matches" ]]; then
    die_ungradeable "no '### Deferred questions' section in: $brief (register retires:${deferred_ids% })"
  fi

  brief_count="$(match_count "$brief_matches")"
  if [[ "$brief_count" -gt 1 ]]; then
    die_ungradeable "$brief_count headings match 'deferred questions' in: $brief (lines $(match_lines "$brief_matches")); the gate reads exactly one section"
  fi
  brief_line="${brief_matches%%$'\t'*}"
  brief_heading="${brief_matches#*$'\t'}"
  brief_where=" (deferred questions '$brief_heading' at line $brief_line)"
  deferred_section="$(extract_section "$brief_line" "$brief")"
  brief_extract_status=$?
  if [[ "$brief_extract_status" -eq 4 ]]; then
    die_ungradeable "unterminated fenced block in the deferred-questions section of: $brief$brief_where"
  elif [[ "$brief_extract_status" -ne 0 ]]; then
    die_ungradeable "could not read the deferred-questions section from: $brief$brief_where"
  fi

  missing=""
  # MUST stay a builtin `[[ =~ ]]`: under pipefail, `printf | grep -qE` on a large
  # section SIGPIPEs printf, and the 141 reads as a PRESENT id being absent.
  for id in $deferred_ids; do
    if ! [[ "$deferred_section" =~ (^|[^A-Za-z0-9])$id([^0-9]|$) ]]; then
      missing="$missing$id "
    fi
  done
  if [[ -n "$missing" ]]; then
    die_ungradeable "deferred/blocked question(s) absent from the Brief's deferred questions: ${missing% }$brief_where"
  fi
  brief_state="ok"
fi

if [[ "$brief_named" -eq 1 ]]; then
  restatement_stamp="$(awk "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    /^- Restatement: / { sub(/\r$/, ""); print; exit }
  ' "$brief")"
  if [[ "$restatement_stamp" =~ ^-\ Restatement:\ UNCONFIRMED\ \(no\ restatement\ posted\) ]]; then
    brief_state="unconfirmed"
    printf 'brief: the restatement is unconfirmed (%s in %s); restate on the page, the user confirms it, then the Brief is exported again\n' "${restatement_stamp#- Restatement: }" "$brief" >&2
  elif [[ "$restatement_stamp" =~ ^-\ Restatement:\ UNCONFIRMED\ \(latest\ rev\ [0-9]+\) ]]; then
    brief_state="unconfirmed"
    printf 'brief: the restatement is unconfirmed (%s in %s); the user confirms the latest restate, then the Brief is exported again\n' "${restatement_stamp#- Restatement: }" "$brief" >&2
  elif [[ -n "$restatement_stamp" && "$answered" -gt 0 ]]; then
    brief_bounds lenient
    page_title=""
    goal=""
    criteria=""
    while IFS=$'\t' read -r tag text; do
      case "$tag" in
      title) [[ -n "$page_title" ]] || page_title="$text" ;;
      goal) goal="${goal:+$goal }$text" ;;
      criteria) criteria="$criteria$text"$'\n' ;;
      *) ;;
      esac
    done <<<"$(brief_fields "$brief_lo" "$brief_hi" "$brief")"
    if [[ -n "$page_title" && "$goal" == "$page_title" ]]; then
      brief_state="placeholder"
      printf "brief: the Goal is the page title ('%s' in %s) while %s question(s) are answered; the confirmed restatement needs a goal, then the Brief is exported again\n" "$page_title" "$brief" "$answered" >&2
    fi
    if [[ "$criteria" == $'- none recorded in the interview surface\n' ]]; then
      brief_state="placeholder"
      printf 'brief: the acceptance criteria are the placeholder (in %s) while %s question(s) are answered; the confirmed restatement needs acceptance criteria, then the Brief is exported again\n' "$brief" "$answered" >&2
    fi
  fi
fi

procedure_state="unchecked"
if [[ "$procedure_on" -eq 1 ]]; then
  round_limit="$max_round"
  if [[ "$max_round" -gt "$registered" ]]; then
    round_limit="$registered"
    proc_problem "highest round $max_round exceeds the $registered registered question(s); rounds must run contiguously from 1"
  fi
  for ((round_num = 1; round_num <= round_limit; round_num++)); do
    case "$rounds_seen" in
    *" $round_num "*) ;;
    *) proc_problem "round $round_num has no register row (rounds must run contiguously from 1; highest is $max_round)" ;;
    esac
  done

  check_sweep

  if [[ "$brief_named" -eq 1 ]]; then
    brief_bounds
    section_patterns=('tl;?dr' 'problem' 'goal' 'work[- ]size' 'constraints'
      'acceptance criteria' 'captured assumptions' 'out[- ]of[- ]scope' 'deferred questions')
    [[ -z "$restatement_stamp" ]] || section_patterns+=('intent')
    for section_pattern in "${section_patterns[@]}"; do
      headings_or_die "^#+[[:space:]]+${section_pattern}[[:space:]]*\$" "$brief"
      section_matches="$(printf '%s\n' "$matches" | awk -F'\t' -v lo="$brief_lo" -v hi="$brief_hi" '$1 > lo && $1 < hi')"
      [[ -n "$section_matches" ]] || proc_problem "Brief is missing the section matching '$section_pattern'"
    done

    finish_line="$(section_lines 'goal' "$brief_lo" "$brief_hi" "$brief" | tr '[:upper:]' '[:lower:]' | sed -e 's/\*\*//g' -e 's/__//g' | sed -n 's/^[-*+] finish line:[[:space:]]*//p' | head -n 1)"
    finish_check="$(printf '%s' "$finish_line" | tr -d '`' | tr '[:upper:]' '[:lower:]')"
    case "$finish_check" in
    '' | 'not settled yet' | 'not settled yet.')
      proc_problem "Brief's Goal has no settled '- Finish line:' line (<merged | released | in use> — checked by <who> via <observable check>)"
      ;;
    *) ;;
    esac

    check_records

    if [[ "$surface_named" -eq 1 ]]; then
      expected_brief="$(mktemp)" || die_ungradeable "could not create a temp file for the --surface export"
      trap 'rm -f "$expected_brief"' EXIT
      round_sh="$(dirname "${BASH_SOURCE[0]}")/../surface/round.sh"
      export_err="$(bash "$round_sh" --dir "$surface" export-brief --ledger "$ledger" --out "$expected_brief" 2>&1 >/dev/null)" ||
        die_ungradeable "could not export the Brief from --surface $surface: $export_err"
      export_hi="$(awk '/^##[[:space:]]+Plan[[:space:]]*$/ { print NR; exit }' "$expected_brief")"
      export_hi="${export_hi:-999999999}"
      brief_headings=$'\n'"$(heading_texts "$brief_lo" "$brief_hi" "$brief")"$'\n'
      while IFS= read -r want; do
        [[ -z "$want" || "$brief_headings" == *$'\n'"$want"$'\n'* ]] ||
          proc_problem "Brief is missing the section '$want' that the page export writes"
      done <<<"$(heading_texts 1 "$export_hi" "$expected_brief")"
      while IFS= read -r want; do
        [[ -z "$want" || "$want" == decisions ]] && continue
        # Not ${want^}: macOS /bin/bash is 3.2.
        label="$(printf '%s' "${want:0:1}" | tr '[:lower:]' '[:upper:]')${want:1}"
        [[ "$want" != tldr ]] || label=TLDR
        need_export_lines "${want//[^a-z0-9 -]/.}" "$label"
      done <<<"$(heading_texts 1 "$export_hi" "$expected_brief")"
      check_decisions
    fi
  fi

  if [[ -n "$proc_problems" ]]; then
    procedure_state="fail"
    printf 'procedure: %s\n' "${proc_problems%$'\n'}" >&2
  else
    procedure_state="ok"
  fi
fi

verdict="registered=$registered open=$open_count deferred=$deferred blocked=$blocked withdrawn=$withdrawn answered=$answered superseded=$superseded brief=$brief_state"
[[ "$stale_count" -gt 0 ]] && verdict="$verdict stale=$stale_count"
[[ "$recheck_count" -gt 0 ]] && verdict="$verdict recheck=$recheck_count"

if [[ $((open_count + superseded + stale_count + recheck_count)) -gt 0 ]]; then
  echo "$verdict status=open procedure=$procedure_state"
  exit 1
fi

if [[ "$procedure_state" == "fail" || "$brief_state" == "unconfirmed" || "$brief_state" == "placeholder" ]]; then
  echo "$verdict status=incomplete procedure=$procedure_state"
  exit 1
fi

echo "$verdict status=clean procedure=$procedure_state"
exit 0
