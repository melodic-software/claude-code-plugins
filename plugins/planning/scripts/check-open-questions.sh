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
# Exit 0 = every registered question is resolved (register is clean)
# Exit 1 = at least one question is still `open` (the contract is not locked)
# Exit 2 = ungradeable: no ledger, no register section, a duplicate register or
#          deferred-questions heading, an unterminated fenced block, an empty
#          register, a malformed row, an unknown status, a duplicate or
#          non-contiguous Q id, or a named `--brief` that is missing
#
# Usage:
#   bash check-open-questions.sh --ledger <interview-checklist.md> [--brief <PLAN.md>]
#   bash check-open-questions.sh --help
#
# Register row shape (inside the ledger's `## Open-question register` section):
#   - Q1 | answered | round 1 | <question> | <resolution>
# Statuses: open | answered | deferred | withdrawn | blocked
#
# --brief is OPT-IN and cross-checks that every `deferred` and `blocked` row
# reached the Brief's `### Deferred questions` section, keyed by its `Q<N>` id.
# A row the ledger retired but the contract never records is the same silent
# hole this gate exists to refuse. When --brief is omitted the verdict says
# `brief=unchecked` rather than omitting the field: a check the caller only
# appeared to get is worse than one it knowingly skipped. The named Brief must
# exist, but it is only READ when the register retired a row: with nothing to
# look up the cross-check is satisfied (`brief=ok`), and the Brief's own
# headings and fences are not graded, so a stray fence in an unrelated section
# of a large planning document cannot fail a clean register.
#
# Fenced blocks (``` or ~~~) are documentation in both files. A fence closes
# only on a line of the same character at least as long as its opener with
# nothing else on it, so a four-backtick fence can quote a three-backtick
# example and a `~~~` line inside a backtick fence is content.
#
# Output (stdout, greppable):
#   `registered=<n> open=<n> deferred=<n> blocked=<n> withdrawn=<n> answered=<n> brief=<ok|unchecked> status=<clean|open|ungradeable>`

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
# A parity toggle got both wrong and read the quoted example's heading as live.
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

ledger=""
brief=""
brief_named=0

die_ungradeable() {
  echo "error: $1" >&2
  echo "registered=0 open=0 deferred=0 blocked=0 withdrawn=0 answered=0 brief=unchecked status=ungradeable"
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
answered=0
deferred=0
withdrawn=0
blocked=0
seen_ids=" "
deferred_ids=""
expected=1

skipped_fenced_row=0
while IFS= read -r line; do
  # extract_section prefixes every line with its fence state; strip the marker
  # before parsing. A fenced block inside the register section is documentation
  # (the row shape, a worked example), not data. Grading it would fail a ledger
  # for quoting its own schema.
  marker="${line%%$'\t'*}"
  line="${line#*$'\t'}"
  if [[ "$marker" == "f" ]]; then
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+[Qq][0-9]+([^0-9]|$) ]]; then
      skipped_fenced_row=1
    fi
    continue
  fi

  # Any non-fenced `- Q<N>` line is a CANDIDATE row; its shape is validated
  # below. The prefilter deliberately does not require the first pipe: a row
  # that lost it (`- Q2 open | round 1 | ...`) would otherwise be skipped
  # silently, the contiguity check would never see the id, and a register with a
  # dropped question would grade clean — the exact silent drop this gate exists
  # to refuse. Rows are model-written, so malformed is a real state; it exits 2.
  [[ "$line" =~ ^[[:space:]]*-[[:space:]]+[Qq][0-9]+([^0-9]|$) ]] || continue

  if ! [[ "$line" =~ ^[[:space:]]*-[[:space:]]+[Qq][0-9]+[[:space:]]*\| ]]; then
    die_ungradeable "malformed register row (needs 'Q<N> | status | round | question'): $line ($where)"
  fi

  row="${line#*-}"
  row="${row#"${row%%[![:space:]]*}"}"

  id="${row%%|*}"
  id="${id#"${id%%[![:space:]]*}"}"
  id="${id%"${id##*[![:space:]]}"}"

  rest="${row#*|}"
  status_field="${rest%%|*}"
  status_field="${status_field#"${status_field%%[![:space:]]*}"}"
  status_field="${status_field%"${status_field##*[![:space:]]}"}"
  status_field="$(printf '%s' "$status_field" | tr '[:upper:]' '[:lower:]')"

  # Field count without a subprocess per row: on a single record `awk -F'|'`
  # reports NF as the number of `|` separators plus one.
  separators="${row//[!|]/}"
  if [[ "${#separators}" -lt 3 ]]; then
    die_ungradeable "malformed register row (needs 'Q<N> | status | round | question'): $line ($where)"
  fi

  # No leading zeros, and no Q0. `[[ ]]` numeric comparison evaluates its
  # operands in arithmetic context, where a leading-zero numeral is OCTAL: the
  # contiguity test below on `Q08` errors to stderr and resolves FALSE, so a
  # gapped register would silently pass. Rejecting the form outright keeps the
  # comparison total. Q<N> is a running counter from 1, so `Q08` is malformed
  # by the register's own contract anyway.
  num="${id#[Qq]}"
  if ! [[ "$num" =~ ^[1-9][0-9]*$ ]]; then
    die_ungradeable "malformed question id (expected Q1, Q2, … with no leading zero): $id ($where)"
  fi
  # Normalize so `q3` and `Q3` collide as the same id.
  id="Q$num"

  case "$seen_ids" in
  *" $id "*) die_ungradeable "duplicate question id: $id ($where)" ;;
  *) ;; # not seen before — fall through and register it
  esac
  seen_ids="$seen_ids$id "

  # Q numbering runs continuously across rounds (SKILL.md "Relentless mode"), so
  # a gap is a row that went missing after it was written — the exact silent drop
  # this gate is here to refuse. Ungradeable, never a pass.
  if [[ "$num" -ne "$expected" ]]; then
    die_ungradeable "non-contiguous question id: expected Q$expected, got $id ($where)"
  fi
  expected=$((expected + 1))

  registered=$((registered + 1))
  case "$status_field" in
  open) open_count=$((open_count + 1)) ;;
  answered) answered=$((answered + 1)) ;;
  deferred)
    deferred=$((deferred + 1))
    deferred_ids="$deferred_ids$id "
    ;;
  withdrawn) withdrawn=$((withdrawn + 1)) ;;
  blocked)
    blocked=$((blocked + 1))
    deferred_ids="$deferred_ids$id "
    ;;
  *) die_ungradeable "unknown status '$status_field' in row: $line ($where)" ;;
  esac
done <<<"$section"

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
  brief_where=""
  if [[ -z "$brief_matches" ]]; then
    if [[ -n "$deferred_ids" ]]; then
      die_ungradeable "no '### Deferred questions' section in: $brief (register retires:${deferred_ids% })"
    fi
    deferred_section=""
  else
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
  fi

  missing=""
  # The match MUST stay a builtin `[[ =~ ]]`, not `printf | grep -qE`. Under this
  # script's `set -uo pipefail`, grep -q exits 0 the moment it matches, printf is
  # then killed by SIGPIPE, and pipefail promotes the whole pipeline to 141 —
  # which `if !` reads as "id absent" and turns a PRESENT id into a spurious
  # ungradeable error. It is a RACE against the 64 KB pipe buffer, not a size
  # threshold: printf only takes SIGPIPE if it still has data to write when grep
  # exits. Measured on this container, id on the section's first line, 15 runs
  # per size, counting runs where the pipeline returned nonzero: 2/15 at 64 KB,
  # 7/15 at 100 KB, then 15/15 at 128 KB and above. So it is intermittent from
  # roughly the buffer size and deterministic from ~128 KB. The intermittent band
  # is the dangerous one: a registered question reported missing only sometimes
  # reads as a transient and invites a re-run instead of an investigation.
  # The builtin reads the string directly and cannot SIGPIPE.
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

verdict="registered=$registered open=$open_count deferred=$deferred blocked=$blocked withdrawn=$withdrawn answered=$answered brief=$brief_state"

if [[ "$open_count" -gt 0 ]]; then
  echo "$verdict status=open"
  exit 1
fi

echo "$verdict status=clean"
exit 0
