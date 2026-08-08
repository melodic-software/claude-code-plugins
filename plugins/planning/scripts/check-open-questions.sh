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
# Exit 2 = ungradeable: no ledger, no register section, an empty register, a
#          malformed row, an unknown status, a duplicate or non-contiguous Q id,
#          or a named `--brief` that is missing
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
# appeared to get is worse than one it knowingly skipped.
#
# Output (stdout, greppable):
#   `registered=<n> open=<n> deferred=<n> blocked=<n> withdrawn=<n> answered=<n> brief=<ok|unchecked> status=<clean|open|ungradeable>`

set -uo pipefail

usage() {
  # Sentinel range (not fixed line numbers) so the printed usage never silently
  # truncates when the header grows or shrinks on a future edit.
  sed -n '/^# Mechanical/,/^#   `registered=/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# Extract the register section: from its heading to the next heading of any
# level, or end of file. Matched case-insensitively on the heading text so a
# ledger that title-cases the section still grades.
section="$(awk '
  /^#+[[:space:]]/ {
    if (inside) { exit }
    line = tolower($0)
    if (line ~ /open-question register/) { inside = 1; found = 1; next }
  }
  inside { print }
  END { if (!found) { exit 3 } }
' "$ledger")"
awk_status=$?

if [[ "$awk_status" -eq 3 ]]; then
  die_ungradeable "no '## Open-question register' section in: $ledger"
elif [[ "$awk_status" -ne 0 ]]; then
  die_ungradeable "could not read the register section from: $ledger"
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

in_fence=0
while IFS= read -r line; do
  # A fenced block inside the register section is documentation (the row shape,
  # a worked example), not data. Grading it would fail a ledger for quoting its
  # own schema.
  if [[ "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
    in_fence=$((1 - in_fence))
    continue
  fi
  [[ "$in_fence" -eq 0 ]] || continue

  # Any non-fenced `- Q<N>` line is a CANDIDATE row; its shape is validated
  # below. The prefilter deliberately does not require the first pipe: a row
  # that lost it (`- Q2 open | round 1 | ...`) would otherwise be skipped
  # silently, the contiguity check would never see the id, and a register with a
  # dropped question would grade clean — the exact silent drop this gate exists
  # to refuse. Rows are model-written, so malformed is a real state; it exits 2.
  [[ "$line" =~ ^[[:space:]]*-[[:space:]]+[Qq][0-9]+([^0-9]|$) ]] || continue

  if ! [[ "$line" =~ ^[[:space:]]*-[[:space:]]+[Qq][0-9]+[[:space:]]*\| ]]; then
    die_ungradeable "malformed register row (needs 'Q<N> | status | round | question'): $line"
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

  # A row must carry at least id | status | round | question.
  field_count="$(printf '%s' "$row" | awk -F'|' '{print NF}')"
  if [[ "$field_count" -lt 4 ]]; then
    die_ungradeable "malformed register row (needs 'Q<N> | status | round | question'): $line"
  fi

  num="${id#[Qq]}"
  if ! [[ "$num" =~ ^[0-9]+$ ]]; then
    die_ungradeable "malformed question id: $id"
  fi
  # Normalize so `q3` and `Q3` collide as the same id.
  id="Q$num"

  case "$seen_ids" in
  *" $id "*) die_ungradeable "duplicate question id: $id" ;;
  *) ;; # not seen before — fall through and register it
  esac
  seen_ids="$seen_ids$id "

  # Q numbering runs continuously across rounds (SKILL.md "Relentless mode"), so
  # a gap is a row that went missing after it was written — the exact silent drop
  # this gate is here to refuse. Ungradeable, never a pass.
  if [[ "$num" -ne "$expected" ]]; then
    die_ungradeable "non-contiguous question id: expected Q$expected, got $id"
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
  *) die_ungradeable "unknown status '$status_field' in row: $line" ;;
  esac
done <<<"$section"

if [[ "$registered" -eq 0 ]]; then
  die_ungradeable "the register section holds no question rows in: $ledger"
fi

brief_state="unchecked"
if [[ "$brief_named" -eq 1 ]]; then
  # The Brief's `### Deferred questions` section, to end of the section.
  deferred_section="$(awk '
    /^#+[[:space:]]/ {
      if (inside) { exit }
      line = tolower($0)
      if (line ~ /deferred questions/) { inside = 1; found = 1; next }
    }
    inside { print }
    END { if (!found) { exit 3 } }
  ' "$brief")"
  brief_awk=$?

  if [[ "$brief_awk" -eq 3 ]]; then
    if [[ -n "$deferred_ids" ]]; then
      die_ungradeable "no '### Deferred questions' section in: $brief (register retires:${deferred_ids% })"
    fi
    deferred_section=""
  elif [[ "$brief_awk" -ne 0 ]]; then
    die_ungradeable "could not read the deferred-questions section from: $brief"
  fi

  missing=""
  for id in $deferred_ids; do
    if ! printf '%s' "$deferred_section" | grep -qE "(^|[^A-Za-z0-9])$id([^0-9]|$)"; then
      missing="$missing$id "
    fi
  done
  if [[ -n "$missing" ]]; then
    die_ungradeable "deferred/blocked question(s) absent from the Brief's deferred questions: ${missing% }"
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
