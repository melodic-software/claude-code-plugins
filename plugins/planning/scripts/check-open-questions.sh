#!/usr/bin/env bash
# Mechanical gate for an /interview open-question register.
#
# `/interview` writes one register row per question at the moment the round is
# ASKED — before any reply arrives. This gate reads that register and decides,
# with NO model involvement, whether any question is still unresolved. It exists
# because the reported failure is a question that was asked, went unanswered
# across a reply about an unrelated topic, and was never re-surfaced: a check
# that consulted the conversation could not see it, but a row left at `open` on
# disk is visible forever.
#
# What this gate does NOT prove: it grades the interview's own bookkeeping, so a
# question that was never registered is invisible to it. The ask-time write rule
# is what makes the register independent of the answer — registering is a
# byproduct of asking, not of resolving. The structural checks below (contiguous
# Q numbering, no duplicate ids) are the affordable defense against a row that
# was silently dropped after being written; a question never written at all is
# out of reach of any file-based check and is the skill's contract to keep.
#
# Exit 0 = every registered question is resolved (register is clean) and, with
#          --procedure, the procedure checks below pass
# Exit 1 = at least one question is still `open` or `superseded-by-plan` (the
#          contract is not locked), --procedure found a procedure defect
#          (the register is gradeable but the interview did not complete its
#          own procedure; fix the ledger or Brief and re-run), the named
#          Brief is stamped `UNCONFIRMED` (the user has not confirmed the
#          latest restatement, or none was posted; `brief=unconfirmed`), or a
#          stamped Brief still carries the export's placeholder Goal or
#          criteria while answered rows exist (`brief=placeholder`)
# Exit 2 = ungradeable: no ledger, no register section, a duplicate register or
#          deferred-questions heading, an unterminated fenced block, an empty
#          register, a malformed row, an unknown status, a duplicate, an
#          out-of-order or a missing (gap) Q id, an unfenced `- Q<N> |` row
#          outside the register section (any heading ends the section, a
#          sub-heading inside it included), a named `--brief` that is
#          missing, or a `--surface` that is missing, comes without `--brief`
#          and `--procedure`, or cannot be exported. Row errors are collected
#          in one pass, each on stderr with its own ledger line, and the
#          verdict keeps the counts of the rows that parsed.
#
# Usage:
#   bash check-open-questions.sh --ledger <interview-checklist.md> [--brief <PLAN.md>] [--procedure] [--surface <data_dir>]
#   bash check-open-questions.sh --help
#
# Register row shape (inside the ledger's `## Open-question register` section):
#   - Q1 | answered | round 1 | <question> | <resolution>
# Statuses: open | answered | deferred | withdrawn | blocked | superseded-by-plan
# `superseded-by-plan` is NOT terminal: a plan displaced the user's answer and
# the user has not reconfirmed it. It counts as `superseded=<n>` and blocks the
# gate exactly like `open`.
# A row of any status whose resolution ends `stale:: C<N>[, C<N>...]` was not
# checked against those constraints: the export writes it, the verdict adds
# `stale=<n>`, and the gate blocks exactly as it does on `open` until Claude
# revises or reconfirms the question. A ledger with no such row reads as before.
#
# --brief is OPT-IN and cross-checks that every `deferred` and `blocked` row
# reached the Brief's `### Deferred questions` section, keyed by its `Q<N>` id.
# A row the ledger retired but the contract never records is the same silent
# hole this gate exists to refuse. When --brief is omitted the verdict says
# `brief=unchecked` rather than omitting the field: a check the caller only
# appeared to get is worse than one it knowingly skipped. The named Brief must
# exist. The deferred cross-check reads it only when the register retired a row:
# with nothing to look up it is satisfied (`brief=ok`), and the Brief's own
# headings and fences are not graded, so a stray fence in an unrelated section
# of a large planning document cannot fail a clean register.
#
# --brief also fails (exit 1, `brief=unconfirmed`) on the stamp
# `- Restatement: UNCONFIRMED (latest rev <N>)` that `round.sh export-brief` writes
# while the newest restatement has no Confirm, and on
# `- Restatement: UNCONFIRMED (no restatement posted)` it writes with none. A
# stamped Brief with an answered row fails (exit 1, `brief=placeholder`) when
# its Goal's first paragraph equals its `- Page title:` line (the export's
# fallback without a confirmed goal) or its only acceptance criterion is
# `- none recorded in the interview surface`. A Brief with no `- Restatement:`
# line (hand-written) is graded for none of this. A line inside a fenced block
# is documentation.
#
# --procedure is OPT-IN and adds checks a script can derive from the ledger, so
# a caller that omits it keeps every verdict and exit code above unchanged:
#   - round numbers in the register rows run contiguously from 1 (a `round`
#     field that is not `round <N>` with N >= 1 counts as a defect)
#   - every `answered`, `deferred`, `withdrawn` and `blocked` row carries a
#     non-empty resolution (the fifth field)
#   - with --brief, the Brief holds every section of the literal Brief template:
#     TLDR, Problem, Goal, Work size, Constraints, Acceptance criteria,
#     Captured assumptions, Out-of-scope, Deferred questions (headings only;
#     content is not graded), plus Intent when the Brief carries a
#     `- Restatement:` stamp (a page export)
#   - with --surface <data_dir> (the interview page's data dir), the gate runs
#     `surface/round.sh export-brief --ledger <ledger>` on that data dir and
#     the Brief holds every section that export writes (Decisions among them
#     when the confirmed restatement has decisions), and its Intent section
#     holds every line of the export's Intent: the intent paragraph and each
#     live ask, note, own answer and note typed on a choice, compared with
#     whitespace runs made one space. Its TLDR and Acceptance criteria hold
#     every line the export writes there, and its Decisions hold each export
#     line as many times as the export writes it and no other line naming a
#     Q<N>, so a decision repeated, put back in an earlier form or contradicted
#     by a second line naming its Q<N> fails. Needs Python 3, as the page does
#   - no Step-exit checkbox (`- [ ] Step <N> exit ...`) is unchecked; a skipped
#     exit step is ticked with `SKIPPED: <reason>`
#   - every row of the ledger's `## Assumption sweep` section,
#     `- S<N> | sweep <M> | <category> | <class> | <source> | <disposition>`,
#     has a disposition: `Q<N>` naming a register row, `F<N>` naming a
#     `## Self-answered facts` line whose basis quotes its source (`"..."`) with
#     a file:line or a URL, or `deferred: <where>`. A `decision` or `person`
#     item, or any `unstated-value` item, never takes `F<N>`, nor `deferred:`
#     unless it is `hedged`. Only a
#     `hedged` item's `Q<N>` may be a row its source names; any other item
#     becomes a new row, above the sweep's `- sweep <M> | register through Q<N>`
#     line, which precedes the sweep's rows and names the register's last row
#     when that sweep ran. S ids run
#     contiguously from 1 within each sweep, no S row sits outside the section,
#     a section with no item says `- none`, and a ticked Step 2 exit that is
#     not `SKIPPED` needs the section
# Each defect is named on stderr. Without --procedure the verdict says
# `procedure=unchecked`, the same convention as `brief=unchecked`. A gradeable
# register with a procedure defect exits 1 with `status=incomplete` (`open` when
# a row is also unresolved); ungradeable stays exit 2 with `procedure=unchecked`.
# With --procedure the named Brief is always read, so an unterminated fence in
# it is ungradeable even when the register retired nothing.
#
# What stays a model judgment and is NOT checked here: whether the Step 1
# survey genuinely grounded the questions, whether a quoted source says what
# the F-line claims (the interview's fresh-context quote check owns that),
# whether every item the sweep returned was recorded, whether the domain was classified,
# whether the register was written at ask-time rather than answer-time, and
# whether the frontier was recomputed between rounds. A file written after the
# fact looks identical to one written at ask-time.
#
# Fenced blocks (``` or ~~~) are documentation in both files. A fence closes
# only on a line of the same character at least as long as its opener with
# nothing else on it, so a four-backtick fence can quote a three-backtick
# example and a `~~~` line inside a backtick fence is content.
#
# Output (stdout, greppable):
#   `registered=<n> open=<n> deferred=<n> blocked=<n> withdrawn=<n> answered=<n> superseded=<n> brief=<ok|unchecked|unconfirmed|placeholder> status=<clean|open|incomplete|ungradeable> procedure=<ok|unchecked|fail>`

set -uo pipefail

usage() {
  # Sentinel range (not fixed line numbers) so the printed usage never silently
  # truncates when the header grows or shrinks on a future edit.
  sed -n '/^# Mechanical/,/^#   `registered=/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# Count of, and comma-separated line numbers from, a heading_matches result.
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

# Print the line number of each unfenced `- Q<N> |` row outside lines `lo` to
# `hi` (inclusive), the register section's body. The register reads only the
# rows above its next heading, so a row below a sub-heading would otherwise go
# ungraded while the gate reports clean. The pipe is required: the exported
# ledger's deferred-questions list (`- Q3: <question>`) is not a register row.
rows_outside() {
  awk -v lo="$1" -v hi="$2" "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    NR >= lo && NR <= hi { next }
    /^[[:space:]]*-[[:space:]]+[Qq][0-9]+[[:space:]]*[|]/ { print NR }
  ' "$3"
}

# Set brief_lo and brief_hi to the Brief's own lines in "$brief". A PLAN.md holds
# `## Brief` + `## Plan`: a heading under `## Plan` must not stand in for a
# section the Brief lacks, so only the lines from the `## Brief` heading to the
# next level-2 heading count. A file with no `## Brief` heading counts whole.
# With `lenient`, a fence left open reads the headings above it rather than
# making the Brief ungradeable: a stray fence under `## Plan` sits below every
# Brief heading.
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

# Print, from the Brief's lines between `lo` and `hi` (both exclusive), the
# first `- Page title:` value, each line of the Goal section's opening paragraph
# (up to a blank line or a list item, so the Intent and Vision bullets a PLAN.md
# adds under it are not part of it), and each non-blank Acceptance criteria
# line, as `title`, `goal` or `criteria`, a TAB, then the text with its
# whitespace runs made one space. A fenced line is documentation; the heading
# bounds came from outside any fence.
brief_fields() {
  awk -v lo="$1" -v hi="$2" "$fence_awk"'
    NR <= lo || NR >= hi { next }
    fence_line($0) { next }
    fenced { next }
    {
      text = $0
      gsub(/[[:space:]]+/, " ", text)
      sub(/^ /, "", text)
      sub(/ $/, "", text)
    }
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

# Print each unfenced heading's text between lines `lo` and `hi` (both
# exclusive), lowercased, its #s dropped and its whitespace runs made one space.
heading_texts() {
  awk -v lo="$1" -v hi="$2" "$fence_awk"'
    NR <= lo || NR >= hi { next }
    fence_line($0) { next }
    fenced { next }
    /^#+[[:space:]]/ {
      text = tolower($0)
      sub(/^#+/, "", text)
      gsub(/[[:space:]]+/, " ", text)
      sub(/^ /, "", text)
      sub(/ $/, "", text)
      print text
    }
  ' "$3"
}

# Print each non-blank, unfenced line of the section whose whole heading text
# matches the awk regex `name` (lowercase) between lines `lo` and `hi` (both
# exclusive), with its whitespace runs made one space, as brief_fields reads a line.
section_lines() {
  awk -v name="$1" -v lo="$2" -v hi="$3" "$fence_awk"'
    NR <= lo || NR >= hi { next }
    fence_line($0) { next }
    fenced { next }
    {
      text = $0
      gsub(/[[:space:]]+/, " ", text)
      sub(/^ /, "", text)
      sub(/ $/, "", text)
    }
    /^#+[[:space:]]/ {
      section = tolower(text)
      sub(/^#+ /, "", section)
      next
    }
    section ~ ("^(" name ")$") && text != "" { print text }
  ' "$4"
}

# Name each line of the page export's section `name` (a section_lines regex) that
# the Brief's own section lacks, as the section `label`. Reads the --surface
# globals: the export in $expected_brief up to $export_hi, the Brief's bounds.
need_export_lines() {
  local have want
  have=$'\n'"$(section_lines "$1" "$brief_lo" "$brief_hi" "$brief")"$'\n'
  while IFS= read -r want; do
    [[ -z "$want" || "$have" == *$'\n'"$want"$'\n'* ]] ||
      proc_problem "Brief's $2 is missing a line the page export writes: $want"
  done <<<"$(section_lines "$1" 1 "$export_hi" "$expected_brief")"
}

# Print how many lines of $2 equal $1.
count_line() {
  local n=0 line
  while IFS= read -r line; do
    [[ "$line" != "$1" ]] || n=$((n + 1))
  done <<<"$2"
  printf '%s' "$n"
}

# The Brief's Decisions against the page export's: each export line appears as
# often as the export writes it, and a Brief line naming a Q<N> is one of the
# export's lines. A decision duplicated, put back in an earlier form, or
# contradicted by a second line naming its Q<N> fails.
check_decisions() {
  local want have want_n have_n seen=$'\n' export_lines brief_lines
  local qn_re='(^|[^A-Za-z0-9])[Qq][1-9][0-9]*([^0-9A-Za-z_]|$)'
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
  while IFS= read -r have; do
    [[ -n "$have" && "$have" =~ $qn_re ]] || continue
    [[ $'\n'"$export_lines"$'\n' == *$'\n'"$have"$'\n'* ]] ||
      proc_problem "Brief's Decisions has a line the page export does not write (a decision in another form, or a second line for it): $have"
  done <<<"$brief_lines"
}

# Set `trimmed` to $1 without its leading and trailing whitespace (no subshell).
trim_into() {
  trimmed="${1#"${1%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
}

proc_problem() { proc_problems="$proc_problems$1"$'\n'; }

# The --procedure ledger checks beyond the register: Step-exit checkboxes and the
# assumption sweep's dispositions (assumption-sweep.md "Disposition"). A sweep
# item settled in the main loop by an uncited fact, or a `decision` item settled
# without a register row, is the hole these close: the register alone cannot
# show an item that never became a row. Runs after the register loop, so
# `seen_ids` holds every register id.
check_sweep() {
  local text lno sweep_ran sweep_matches sweep_line facts_matches facts="" body
  local s_lo=0 s_hi=0 sweep_keys=$'\n' sweep_rows=0 sweep_none=0 row seps key
  local sweep_marks=$'\n' sweep_no high_water
  local category class src disposition hedged user_owned owned_kind qnum qid fid basis found gaps src_rest src_max
  local quote_re='"[^"]+"' loc_re='(https?://[^[:space:]]+|[^[:space:]:]+:[0-9]+)'

  while IFS=$'\t' read -r lno text; do
    [[ -n "$lno" ]] && proc_problem "line $lno: Step-exit checkbox is unchecked: $text (tick it when the step is done; a skipped step is ticked with 'SKIPPED: <reason>')"
  done <<<"$(awk "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    {
      l = tolower($0)
      if (l ~ /^[[:space:]]*[-*+][[:space:]]+\[ \][[:space:]]+step[[:space:]]+[0-9.]+[[:space:]]+exit/) {
        match(l, /step[[:space:]]+[0-9.]+[[:space:]]+exit/)
        print NR "\t" substr($0, RSTART, RLENGTH)
      }
    }
  ' "$ledger")"

  sweep_ran="$(awk "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    {
      l = tolower($0)
      if (l ~ /^[[:space:]]*[-*+][[:space:]]+\[x\][[:space:]]+step[[:space:]]+2[[:space:]]+exit/ && l !~ /skipped:/) { print NR; exit }
    }
  ' "$ledger")"

  sweep_matches="$(heading_matches '^#+[[:space:]]+assumption sweep[[:space:]]*$' "$ledger")"
  if [[ -z "$sweep_matches" ]]; then
    [[ -z "$sweep_ran" ]] ||
      proc_problem "line $sweep_ran: Step 2 exit is ticked but the ledger has no '## Assumption sweep' section; record each sweep item there with its disposition, or '- none'"
  elif [[ "$(match_count "$sweep_matches")" -gt 1 ]]; then
    proc_problem "$(match_count "$sweep_matches") headings match 'assumption sweep' (lines $(match_lines "$sweep_matches")); keep one section"
    return
  else
    sweep_line="${sweep_matches%%$'\t'*}"
    facts_matches="$(heading_matches '^#+[[:space:]]+self-answered facts[[:space:]]*$' "$ledger")"
    if [[ -n "$facts_matches" && "$(match_count "$facts_matches")" -eq 1 ]]; then
      # One `F<n><TAB><basis>` line per fact; the basis is the text after the last `|`.
      while IFS= read -r text; do
        [[ "${text%%$'\t'*}" == "." ]] || continue
        text="${text#*$'\t'}"
        [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Ff]([1-9][0-9]*)[[:space:]]*\| ]] || continue
        facts="${facts}F${BASH_REMATCH[1]}"$'\t'"${text##*|}"$'\n'
      done <<<"$(extract_section "${facts_matches%%$'\t'*}" "$ledger")"
    fi

    body="$(extract_section "$sweep_line" "$ledger")"
    s_lo=$((sweep_line + 1))
    lno="$sweep_line"
    while IFS= read -r text; do
      lno=$((lno + 1))
      [[ "${text%%$'\t'*}" == "." ]] || continue
      text="${text#*$'\t'}"
      if [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Nn][Oo][Nn][Ee][[:space:]]*$ ]]; then
        sweep_none=1
        continue
      fi
      if [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Ss]weep[[:space:]]+([1-9][0-9]*)[[:space:]]*\|[[:space:]]*(register|Register)[[:space:]]+through[[:space:]]+[Qq]([1-9][0-9]*)[[:space:]]*$ ]]; then
        sweep_no="${BASH_REMATCH[1]}"
        qnum="${BASH_REMATCH[3]}"
        case "$seen_ids" in
        *" Q$qnum "*) ;;
        *) proc_problem "line $lno: sweep $sweep_no's high-water line names Q$qnum, which has no register row" ;;
        esac
        case "$sweep_marks" in
        *$'\n'"$sweep_no "*) proc_problem "line $lno: duplicate high-water line for sweep $sweep_no" ;;
        *) sweep_marks="$sweep_marks$sweep_no $qnum"$'\n' ;;
        esac
        continue
      fi
      [[ "$text" =~ ^[[:space:]]*-[[:space:]]+[Ss][0-9]+([^0-9]|$) ]] || continue
      sweep_rows=$((sweep_rows + 1))
      row="${text#*-}"
      seps="${row//[!|]/}"
      if ! [[ "$row" =~ ^[[:space:]]*[Ss]([1-9][0-9]*)[[:space:]]*\|[[:space:]]*[Ss]weep[[:space:]]+([1-9][0-9]*)[[:space:]]*\| ]] || [[ "${#seps}" -lt 5 ]]; then
        proc_problem "line $lno: malformed sweep row (needs 'S<N> | sweep <M> | category | class | source | disposition'): $text"
        continue
      fi
      sweep_no="${BASH_REMATCH[2]}"
      key="sweep $sweep_no S${BASH_REMATCH[1]}"
      case "$sweep_keys" in
      *$'\n'"$key"$'\n'*)
        proc_problem "line $lno: duplicate sweep row: $key"
        continue
        ;;
      *) ;;
      esac
      sweep_keys="$sweep_keys$key"$'\n'
      row="${row#*|}"
      row="${row#*|}"
      trim_into "${row%%|*}"
      category="$trimmed"
      row="${row#*|}"
      trim_into "${row%%|*}"
      class="$trimmed"
      row="${row#*|}"
      src="${row%|*}"
      trim_into "${row##*|}"
      disposition="$trimmed"

      shopt -s nocasematch
      case "$category" in
      undecided | hidden-default | contradiction | inherited | hedged | coined-term | unstated-value) ;;
      *) proc_problem "line $lno: $key has unknown category '$category'" ;;
      esac
      case "$class" in
      decision | fact | tenant | person) ;;
      *) proc_problem "line $lno: $key has unknown class '$class'" ;;
      esac
      # A hedged item points at the answered row it came from and goes to the
      # confirmation restate; every other item becomes a new row, asked.
      hedged=0
      [[ "$category" != hedged ]] || hedged=1
      user_owned=0
      [[ "$class" != decision && "$class" != person && "$category" != unstated-value ]] || user_owned=1
      owned_kind="$class"
      [[ "$category" != unstated-value ]] || owned_kind="$category"
      shopt -u nocasematch

      if [[ "$disposition" =~ ^[Qq]([1-9][0-9]*)$ ]]; then
        qnum="${BASH_REMATCH[1]}"
        qid="Q$qnum"
        case "$seen_ids" in
        *" $qid "*) ;;
        *) proc_problem "line $lno: $key names $qid, which has no register row" ;;
        esac
        if [[ "$hedged" -eq 0 ]]; then
          if [[ "$src" =~ (^|[^A-Za-z0-9])[Qq]$qnum([^0-9]|$) ]]; then
            proc_problem "line $lno: $key names $qid, the row it was found in; a sweep item becomes a new register row at the next Q<N>, asked with a recommendation"
          else
            # The new row is written after the sweep ran, so its id is above the
            # register's last row at that point, which is also at or above every
            # row the source names. An older row (an earlier answer) would settle
            # the item without asking it.
            src_rest="$src"
            src_max=0
            while [[ "$src_rest" =~ (^|[^A-Za-z0-9])[Qq]([1-9][0-9]*)([^0-9].*)?$ ]]; do
              [[ "${BASH_REMATCH[2]}" -le "$src_max" ]] || src_max="${BASH_REMATCH[2]}"
              # Keep an alphanumeric in front of the tail, so a Q right after the
              # digits is not read as a token the single-row test above would skip.
              src_rest="x${BASH_REMATCH[3]}"
            done
            high_water="${sweep_marks#*$'\n'"$sweep_no "}"
            if [[ "$high_water" == "$sweep_marks" ]]; then
              proc_problem "line $lno: $key has a Q<N> disposition but sweep $sweep_no has no '- sweep $sweep_no | register through Q<N>' line above it; write that line, with the register's last row, before the sweep runs"
            else
              high_water="${high_water%%$'\n'*}"
              if [[ "$src_max" -gt "$high_water" ]]; then
                proc_problem "line $lno: $key's source names Q$src_max, above Q$high_water, sweep $sweep_no's high-water line; that line names the register's last row when the sweep ran"
              elif [[ "$qnum" -le "$high_water" ]]; then
                proc_problem "line $lno: $key names $qid, which is not above Q$high_water, the last row before sweep $sweep_no; a sweep item becomes a new register row at the next Q<N>, asked with a recommendation"
              fi
            fi
          fi
        fi
      elif [[ "$disposition" =~ ^[Ff]([1-9][0-9]*)$ ]]; then
        fid="F${BASH_REMATCH[1]}"
        if [[ "$user_owned" -eq 1 ]]; then
          proc_problem "line $lno: $key is a $owned_kind item settled by $fid; a $owned_kind item becomes an open register row asked with a recommendation, never a fact"
          continue
        fi
        found=0
        basis=""
        while IFS=$'\t' read -r text basis; do
          if [[ "$text" == "$fid" ]]; then
            found=1
            break
          fi
        done <<<"$facts"
        if [[ "$found" -eq 0 ]]; then
          proc_problem "line $lno: $key names $fid, which has no line in '## Self-answered facts'"
        elif ! [[ "$basis" =~ $quote_re && "$basis" =~ $loc_re ]]; then
          proc_problem "line $lno: $key is settled by $fid, whose basis does not quote its source (\"...\") with a file:line or a URL: '$basis'"
        fi
      elif [[ "$disposition" =~ ^[Dd]eferred:[[:space:]]*[^[:space:]] ]]; then
        [[ "$user_owned" -eq 0 || "$hedged" -eq 1 ]] ||
          proc_problem "line $lno: $key is a $owned_kind item deferred outside the register; it becomes a register row (deferred or blocked there when it cannot be asked)"
      else
        proc_problem "line $lno: $key has no disposition (Q<N>, F<N> or 'deferred: <where>'): '$disposition'"
      fi
    done <<<"$body"
    s_hi="$lno"

    if [[ "$sweep_rows" -eq 0 && "$sweep_none" -eq 0 ]]; then
      proc_problem "the '## Assumption sweep' section at line $sweep_line records no item; write '- none' when the sweep returned nothing"
    fi
    # S ids run contiguously from 1 within each sweep, so an item dropped
    # between two recorded ones is caught.
    gaps="$(printf '%s' "$sweep_keys" | awk '
      NF < 3 { next }
      { m = $2; n = substr($3, 2) + 0; if (n > max[m]) max[m] = n; seen[m " " n] = 1 }
      END { for (m in max) for (n = 1; n <= max[m]; n++) if (!((m " " n) in seen)) print "sweep " m " has no row for S" n }
    ')"
    while IFS= read -r text; do
      [[ -n "$text" ]] && proc_problem "$text (S ids run contiguously from 1 within a sweep)"
    done <<<"$gaps"
  fi

  while IFS= read -r lno; do
    [[ -n "$lno" ]] && proc_problem "line $lno: sweep row outside the '## Assumption sweep' section; move it into the section, above its next heading"
  done <<<"$(awk -v lo="$s_lo" -v hi="$s_hi" "$fence_awk"'
    fence_line($0) { next }
    fenced { next }
    NR >= lo && NR <= hi { next }
    /^[[:space:]]*-[[:space:]]+[Ss][0-9]+[[:space:]]*[|]/ { print NR }
  ' "$ledger")"
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
# --surface grades the Brief's sections, which only --brief with --procedure
# reads; accepting it alone would report a comparison that never ran.
if [[ "$surface_named" -eq 1 ]]; then
  [[ -n "$surface" ]] || die_ungradeable "--surface needs a value"
  [[ "$brief_named" -eq 1 && "$procedure_on" -eq 1 ]] ||
    die_ungradeable "--surface needs --brief and --procedure"
  [[ -d "$surface" ]] || die_ungradeable "--surface not found: $surface"
fi

register_matches="$(heading_matches 'open-question register' "$ledger")"
matches_status=$?
if [[ "$matches_status" -eq 4 ]]; then
  die_ungradeable "unterminated fenced block in: $ledger (every heading after it is hidden; close the fence)"
elif [[ "$matches_status" -ne 0 ]]; then
  die_ungradeable "could not read the headings of: $ledger"
fi
[[ -n "$register_matches" ]] || die_ungradeable "no '## Open-question register' section in: $ledger"

# The gate reads exactly one section. Binding to the first match would grade a
# template's instructional copy (whose example rows parse as data) instead of
# the live register below it; binding to the last would guess. Either hides the
# ambiguity, so two matches are a refusal that names both.
register_count="$(match_count "$register_matches")"
if [[ "$register_count" -gt 1 ]]; then
  die_ungradeable "$register_count headings match 'open-question register' in: $ledger (lines $(match_lines "$register_matches")); the gate reads exactly one section, so delete the template's instructional copy and keep the single live register"
fi

register_line="${register_matches%%$'\t'*}"
register_heading="${register_matches#*$'\t'}"
# Every register-derived error names the heading it bound to and its line, so a
# bind to the wrong section is visible from stderr alone.
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
stale_tail_re='(^|\] |(^|[^\\])(\\\\)*; )stale:: C[0-9]+(, C[0-9]+)*$'
answered=0
deferred=0
withdrawn=0
blocked=0
superseded=0
seen_ids=" "
deferred_ids=""
ids_in_order=""
max_id=0
rounds_seen=" "
max_round=0
proc_problems=""
row_errors=""
lineno=0

# Row errors are collected, not fatal on the first, so one run names every bad
# row with its own line; any of them still makes the register ungradeable.
row_error() { row_errors="${row_errors}line $lineno: $1"$'\n'; }

# Record a question id (its number, no leading zero) in file order. A repeat is
# a duplicate (dup=1, the row is skipped); a number below one already seen is
# out of order. Gaps are found after the loop, from the whole id set, so an
# out-of-order row is not also reported as a gap.
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

# What counts as a CANDIDATE register row, defined once. The fenced branch and
# the live branch below both test it, and they must agree: a shape skipped as
# documentation has to be the same shape that would have been graded as data.
row_candidate_re='^[[:space:]]*-[[:space:]]+[Qq][0-9]+([^0-9]|$)'

skipped_fenced_row=0
while IFS= read -r line; do
  # extract_section emits one line per ledger line after the heading, so the
  # ledger line number is the heading's plus the count read so far.
  lineno=$((lineno == 0 ? register_line + 1 : lineno + 1))
  # extract_section prefixes every line with its fence state; strip the marker
  # before parsing. A fenced block inside the register section is documentation
  # (the row shape, a worked example), not data. Grading it would fail a ledger
  # for quoting its own schema.
  marker="${line%%$'\t'*}"
  line="${line#*$'\t'}"
  if [[ "$marker" == "f" ]]; then
    if [[ "$line" =~ $row_candidate_re ]]; then
      skipped_fenced_row=1
    fi
    continue
  fi

  # A candidate row's shape is validated below. The prefilter deliberately does
  # not require the first pipe: a row that lost it (`- Q2 open | round 1 | ...`)
  # would otherwise be skipped silently, the contiguity check would never see
  # the id, and a register with a dropped question would grade clean — the exact
  # silent drop this gate exists to refuse. Rows are model-written, so malformed
  # is a real state; it exits 2.
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
  # Normalize so `q3` and `Q3` collide as the same id. Q numbering runs
  # continuously across rounds (SKILL.md "Relentless mode"), so a gap is a row
  # that went missing after it was written, the exact silent drop this gate is
  # here to refuse. A malformed row's id still counts, so it is not also a gap.
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
  status_field="${rest%%|*}"
  status_field="${status_field#"${status_field%%[![:space:]]*}"}"
  status_field="${status_field%"${status_field##*[![:space:]]}"}"

  # Field count without a subprocess per row: on a single record `awk -F'|'`
  # reports NF as the number of `|` separators plus one.
  separators="${row//[!|]/}"
  if [[ "${#separators}" -lt 3 ]]; then
    row_error "malformed register row (needs 'Q<N> | status | round | question'): $line"
    continue
  fi

  # Fields after the id: status | round | question | resolution. The resolution
  # is the text after the last `|`, so a `|` inside the question cannot make an
  # empty resolution look filled; a row with no question and resolution
  # fields has none.
  after_status="${rest#*|}"
  round_field="${after_status%%|*}"
  round_field="${round_field#"${round_field%%[![:space:]]*}"}"
  round_field="${round_field%"${round_field##*[![:space:]]}"}"
  resolution="${after_status#*|}"
  if [[ "$resolution" == *"|"* ]]; then resolution="${resolution##*|}"; else resolution=""; fi
  resolution="${resolution#"${resolution%%[![:space:]]*}"}"
  resolution="${resolution%"${resolution##*[![:space:]]}"}"
  [[ "$resolution" =~ $stale_tail_re ]] && stale_count=$((stale_count + 1))
  if [[ "$round_field" =~ ^[Rr]ound[[:space:]]+([1-9][0-9]*)$ ]]; then
    round_num="${BASH_REMATCH[1]}"
    rounds_seen="$rounds_seen$round_num "
    [[ "$round_num" -gt "$max_round" ]] && max_round="$round_num"
  else
    proc_problems="$proc_problems$id: round field is not 'round <N>' (N >= 1): '$round_field'"$'\n'
  fi

  # Statuses match case-insensitively without a subprocess per row (a `tr` fork
  # costs over a second per row on a loaded Windows host). nocasematch, not
  # ${var,,}, because macOS /bin/bash is 3.2; scoped so no other match sees it.
  shopt -s nocasematch
  case "$status_field" in
  open) open_count=$((open_count + 1)) ;;
  answered) answered=$((answered + 1)) ;;
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
    [[ -n "$resolution" ]] || proc_problems="$proc_problems$id: $status_field row has an empty resolution"$'\n'
    ;;
  *) ;;
  esac
  shopt -u nocasematch
  registered=$((registered + 1))
done <<<"$section"

# The loop read one line per ledger line, so lineno is the section's last line
# (an empty section reads one empty line: the line after the heading, which is
# a heading or past the end of the file, never a row).
outside_lines="$(rows_outside $((register_line + 1)) "$lineno" "$ledger")" ||
  die_ungradeable "could not read the rows of: $ledger"
for lineno in $outside_lines; do
  row_error "question row outside the register section (any heading ends it, a sub-heading included); move the row into the register, above its next heading"
done

# A gap is a number missing below the highest id; one sort over the whole set,
# not a walk to the highest id, so a mistyped Q99999 costs nothing extra.
prev=0
# shellcheck disable=SC2086 # deliberate: one id per word
for n in $(printf '%s\n' $ids_in_order | sort -n); do
  if [[ "$n" -gt $((prev + 1)) ]]; then
    gap="Q$((prev + 1))"
    [[ "$n" -gt $((prev + 2)) ]] && gap="$gap to Q$((n - 1))"
    row_errors="${row_errors}gap in question ids: no row for $gap"$'\n'
  fi
  prev="$n"
done

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
  # Nothing was retired, so there is nothing to look up and the Brief is not
  # read. Its headings and fences are graded only in service of the lookup: a
  # Brief is a large planning document with its own code samples, and refusing a
  # clean register over a stray fence in a section this gate never grades would
  # fail the caller for a defect outside the check they asked for. The
  # existence check above still ran; the caller named a file that must exist.
  brief_state="ok"
elif [[ "$brief_named" -eq 1 ]]; then
  brief_matches="$(heading_matches 'deferred questions' "$brief")"
  brief_matches_status=$?
  if [[ "$brief_matches_status" -eq 4 ]]; then
    die_ungradeable "unterminated fenced block in: $brief (every heading after it is hidden; close the fence)"
  elif [[ "$brief_matches_status" -ne 0 ]]; then
    die_ungradeable "could not read the headings of: $brief"
  fi
  # This branch is reached only with rows retired, so a Brief that carries no
  # deferred-questions section cannot satisfy the lookup.
  if [[ -z "$brief_matches" ]]; then
    die_ungradeable "no '### Deferred questions' section in: $brief (register retires:${deferred_ids% })"
  fi

  # Same one-section rule as the register: two matches are a refusal, not a guess.
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

# export-brief stamps every page export with a `- Restatement:` line: `UNCONFIRMED (latest rev N)`
# while the newest restatement has no Confirm, `UNCONFIRMED (no restatement posted)` with none.
# Either fails. A stamped export whose Goal is still its `- Page title:` line, or whose criteria
# are the placeholder, fails too while answered rows exist: the user decided things the Brief
# does not carry. A Brief with no stamp (hand-written) is not graded for any of it; a fenced
# line is documentation.
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
    # Lenient, as the deferred lookup is: without --procedure a stray fence is not refused.
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
  # Contiguous rounds never exceed the row count, so bound the walk there: a
  # mistyped round number fails fast instead of iterating to it.
  round_limit="$max_round"
  if [[ "$max_round" -gt "$registered" ]]; then
    round_limit="$registered"
    proc_problems="${proc_problems}highest round $max_round exceeds the $registered registered question(s); rounds must run contiguously from 1"$'\n'
  fi
  for ((round_num = 1; round_num <= round_limit; round_num++)); do
    case "$rounds_seen" in
    *" $round_num "*) ;;
    *) proc_problems="${proc_problems}round $round_num has no register row (rounds must run contiguously from 1; highest is $max_round)"$'\n' ;;
    esac
  done

  check_sweep

  if [[ "$brief_named" -eq 1 ]]; then
    brief_bounds
    section_patterns=('tl;?dr' 'problem' 'goal' 'work[- ]size' 'constraints'
      'acceptance criteria' 'captured assumptions' 'out[- ]of[- ]scope' 'deferred questions')
    # A page export writes Intent above Goal; a hand-written Brief need not.
    [[ -z "$restatement_stamp" ]] || section_patterns+=('intent')
    for section_pattern in "${section_patterns[@]}"; do
      section_matches="$(heading_matches "^#+[[:space:]]+${section_pattern}[[:space:]]*\$" "$brief")"
      section_status=$?
      if [[ "$section_status" -eq 4 ]]; then
        die_ungradeable "unterminated fenced block in: $brief (every heading after it is hidden; close the fence)"
      elif [[ "$section_status" -ne 0 ]]; then
        die_ungradeable "could not read the headings of: $brief"
      fi
      section_matches="$(printf '%s\n' "$section_matches" | awk -F'\t' -v lo="$brief_lo" -v hi="$brief_hi" '$1 > lo && $1 < hi')"
      [[ -n "$section_matches" ]] || proc_problems="${proc_problems}Brief is missing the section matching '$section_pattern'"$'\n'
    done

    # The page's own export is what the Brief must still carry: a section a
    # confirmed restatement filled (Decisions) and the user's words in Intent
    # exist only on the page, so the template headings alone cannot show them.
    if [[ "$surface_named" -eq 1 ]]; then
      expected_brief="$(mktemp)" || die_ungradeable "could not create a temp file for the --surface export"
      trap 'rm -f "$expected_brief"' EXIT
      round_sh="$(dirname "${BASH_SOURCE[0]}")/../surface/round.sh"
      export_err="$(bash "$round_sh" --dir "$surface" export-brief --ledger "$ledger" --out "$expected_brief" 2>&1 >/dev/null)" ||
        die_ungradeable "could not export the Brief from --surface $surface: $export_err"
      # export-brief writes `## Brief` on line 1 and ends the Brief at `## Plan`.
      export_hi="$(awk '/^##[[:space:]]+Plan[[:space:]]*$/ { print NR; exit }' "$expected_brief")"
      export_hi="${export_hi:-999999999}"
      brief_headings=$'\n'"$(heading_texts "$brief_lo" "$brief_hi" "$brief")"$'\n'
      while IFS= read -r want; do
        [[ -z "$want" || "$brief_headings" == *$'\n'"$want"$'\n'* ]] ||
          proc_problems="${proc_problems}Brief is missing the section '$want' that the page export writes"$'\n'
      done <<<"$(heading_texts 1 "$export_hi" "$expected_brief")"
      need_export_lines intent Intent
      need_export_lines 'tl;?dr' TLDR
      need_export_lines 'acceptance criteria' 'Acceptance criteria'
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

if [[ $((open_count + superseded + stale_count)) -gt 0 ]]; then
  echo "$verdict status=open procedure=$procedure_state"
  exit 1
fi

if [[ "$procedure_state" == "fail" || "$brief_state" == "unconfirmed" || "$brief_state" == "placeholder" ]]; then
  echo "$verdict status=incomplete procedure=$procedure_state"
  exit 1
fi

echo "$verdict status=clean procedure=$procedure_state"
exit 0
