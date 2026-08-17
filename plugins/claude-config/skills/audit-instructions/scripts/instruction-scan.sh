#!/usr/bin/env bash
# instruction-scan.sh — advisory deterministic pre-scan for the audit-instructions
# skill. Marks CANDIDATE lines for catalog checks (reference/criteria.md) in the
# instruction files handed to it:
#
#   I6  bare prohibition ("never", "do not", "don't", "must not", "should not")
#       on a line that carries no rationale marker (because/since/so that/…). A
#       grep cannot judge whether a rationale is genuinely present or whether the
#       prohibition is a genuine hard "never", so these are candidates the model
#       lane refines — not confirmed findings.
#   I10 reasoning-echo directive (show/explain/reproduce your thinking or
#       reasoning, "think out loud", reasoning_extraction). These tell the model
#       to emit its internal reasoning as response text.
#   I8  model-era candidates, three pattern families emitted with per-family ids
#       matching the catalog's I8 rows — I8-a and I8-c are Opus-5-scoped, I8-b is
#       unscoped (promotion gate met; fires for every target). The scanner is
#       model-blind — the model lane adjudicates against the resolved target model
#       and the criteria-owned fences:
#         I8-a instructed self-check ("double-check", "re-verify", "final
#              verification step", "use a subagent to verify", "verify your own work")
#         I8-b conservative-reporting directives ("be conservative", "only report
#              high-severity", "don't nitpick")
#         I8-c don't-think / don't-reason directives ("do not think", "don't
#              reason", "without thinking", "skip the reasoning")
#       Over-production is by design: restraint clauses, quoted/meta text,
#       idiomatic uses ("do not think of this as…"), and substring near-misses
#       ("don't reasonably…") ARE emitted; the fences live in
#       reference/criteria.md, never here.
#   I23 self-estimated context-budget trigger ("context is heavy", "running low
#       on context", "remaining context", "check /context", "final third of the
#       window"). The catalog's subject is a directive to judge one's own window
#       and then stop, summarize, hand off, or trim on that basis — but the
#       scanner marks the BUDGET PHRASING alone and never the verb it governs,
#       because the two routinely sit in different sentences. It therefore also
#       emits the counter-steer text that forbids the behavior (inverted
#       polarity), documents ABOUT the pattern, and operator-facing budgets:
#       all three are criteria-owned exemptions the model lane applies.
#   I27 effort-for-brevity candidates: a line pairing an effort-lowering
#       directive ("lower/reduce/decrease/drop … effort") with a brevity token
#       (short/brief/concise/terse/length/verbose/wordy). The model lane
#       adjudicates whether the line actually premises brevity on effort.
#   I28 trigger-emphasis / blanket-default candidates, two families:
#         I28-a forced-compliance emphasis ("CRITICAL:", "You MUST", "MANDATORY";
#              case-sensitive — the all-caps marker is the signal)
#         I28-b blanket tool defaults ("default to using", "if in doubt, use")
#   I25 retired sampling parameters (temperature/top_p/top_k prescriptions; the
#       affected-model range is a criteria-owned Detect condition)
#
# Advisory: prints candidate rows, ALWAYS exits 0 (candidates never fail a run).
# Requires grep; exits 2 when grep is absent.
#
# Rows are `file:line:check-id` (grep -n convention). With no rationale on a line
# a prohibition surfaces as an I6 row; a line may surface once per matching check
# id (I6, I10, I23, I27, and one of the I8 families). Nonexistent path arguments
# are
# skipped, not errors.
#
# Usage:
#   instruction-scan.sh FILE...            # one candidate row per line; exit 0
#   instruction-scan.sh --count FILE...    # integer candidate count only; exit 0
#   instruction-scan.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
instruction-scan.sh — mark I6/I8/I10/I23/I25/I27/I28 instruction candidates in given files.

Usage: instruction-scan.sh [--count|--help] FILE...

  FILE...    print one candidate row (file:line:check-id) per match; exit 0
  --count    print the integer candidate count only; exit 0
  --help     this message

I8 pattern families (model-era candidates; model lane adjudicates): I8-a
instructed self-check, I8-b conservative-reporting, I8-c don't-think /
don't-reason. I23 marks self-estimated context-budget phrasing. I27 marks
effort-for-brevity candidates (effort-lowering directive paired with a brevity
token on one line). I28 families: I28-a forced-compliance emphasis
(case-sensitive), I28-b blanket tool defaults. I25: retired sampling
parameters.

Advisory — always exits 0 (candidates never fail the run). Requires grep
(exit 2 when absent). Seeds the candidate set of the audit-instructions
skill; the per-surface lane refines every candidate against reference/criteria.md.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  *) ;;
esac

if ! command -v grep >/dev/null 2>&1; then
  echo "ERROR: grep required" >&2
  exit 2
fi

mode="report"
if [[ "${1:-}" == "--count" ]]; then
  mode="count"
  shift
fi

# --- Detection patterns (case-insensitive) -----------------------------------
# POSIX ERE has no word-boundary assertion (GNU grep's ERE \b is an extension
# BSD grep lacks), so compose boundaries from consuming byte classes — safe here
# because every use is line-level -q/-n matching, never match extraction. The
# negated classes are single-byte under a C locale, which still bounds correctly
# against multibyte neighbors: their first byte is non-alnum.
WB_L="(^|[^[:alnum:]_])"
WB_R='([^[:alnum:]_]|$)'
# I6 prohibition tokens. `do NOT` folds into `do not` under -i. The ('|’)?
# alternation in the contraction forms covers straight, curly (U+2019), and
# absent apostrophes as literal byte sequences — a `.`/bracket class breaks on
# multibyte apostrophes under a C locale.
I6_ERE="${WB_L}never${WB_R}|${WB_L}do not${WB_R}|${WB_L}don('|’)?t${WB_R}|${WB_L}must ?not${WB_R}|${WB_L}mustn('|’)?t${WB_R}|${WB_L}should ?not${WB_R}|${WB_L}shouldn('|’)?t${WB_R}"
# Rationale markers — a prohibition line carrying one of these is not an I6 candidate.
RATIONALE_ERE="because|${WB_L}since${WB_R}|${WB_L}so that${WB_R}|${WB_L}so it${WB_R}|${WB_L}so the${WB_R}|${WB_L}to avoid${WB_R}|${WB_L}otherwise${WB_R}|${WB_L}in order to${WB_R}|${WB_L}rationale${WB_R}|${WB_L}reason${WB_R}"
# I10 reasoning-echo phrasing.
I10_ERE="(show|explain|reproduce|echo|transcribe|verbalize|narrate|share|describe) (your |the )?(thinking|reasoning|thought process|chain of thought)"
I10_ERE="${I10_ERE}|think out loud|walk (me|us) through your (thinking|reasoning)|reasoning_extraction|chain[- ]of[- ]thought"
# I8 model-era candidate families (I8-a/I8-c Opus-5-scoped, I8-b unscoped;
# scanner is model-blind; per-family ids I8-a/I8-b/I8-c). Stem forms
# (`re[- ]?verif`) deliberately catch inflections; over-production is the contract.
I8_A_ERE="double[- ]check|${WB_L}re[- ]?verif|final verification step|(sub)?agent to verify|have (a |an )?(sub)?agent verify|verifier (sub)?agent|verify your (own )?work"
I8_B_ERE="be conservative|(only report|report only) (the )?(high|critical)|(don('|’)?t|do not) nitpick"
I8_C_ERE="(do not|don('|’)?t) (think|reason)|without thinking|skip the reasoning"
# I23 self-estimated context-budget phrasing. Deliberately anchored to
# BUDGET-AS-TRIGGER forms, never to the bare term "context window" — that term
# is ordinary vocabulary in any instruction surface discussing sessions, and
# matching it would return the whole corpus rather than a candidate set.
I23_ERE="context (is |gets |getting |grows )?(heavy|tight|saturated|exhausted)|heavy context"
I23_ERE="${I23_ERE}|(running|runs|run) (out of|low on) context|low on context"
I23_ERE="${I23_ERE}|remaining[- ](context|window|tokens)|context[- ](budget|percentage|occupancy|countdown)|token[- ](budget|countdown)"
I23_ERE="${I23_ERE}|(check|checking|watch|watching|monitor|monitoring) (the |your )?/context|/context output"
I23_ERE="${I23_ERE}|(final|last) (third|quarter|half) of (the|your|its) window|window position"
I23_ERE="${I23_ERE}|(nearing|approaching) (the )?(context|token)[- ](limit|cap|budget|window)"
# I27 effort-for-brevity: both patterns must hit the SAME line — the AND lives
# in scan_file. Stem forms catch inflections (decrease/decreasing via the bare
# stem, drop/dropped/dropping via the doubled-p form; verbos carries no left
# boundary so compounds match too); over-production is the contract, as with I8.
I27_EFFORT_ERE="(lower|reduc|decreas|dropp?)(e|ed|es|ing|s)? (the |your )?effort" # spellchecker:disable-line
I27_BREVITY_ERE="${WB_L}short|${WB_L}brief|${WB_L}concise|${WB_L}terse|${WB_L}length|verbos|${WB_L}wordy"
# I28 trigger-emphasis / blanket-default candidates (criteria fences decide:
# emphasis guarding a destructive gate or a stated hard precondition is not a
# finding). Case-sensitive arm: the all-caps markers themselves. "use even
# when" is an attested blanket-default form ("Use even when you think you know
# the answer"), not a quoted guide example — over-production by design.
I28_A_ERE="CRITICAL:|IMPORTANT:|(You|you) MUST|MANDATORY|ALWAYS use|NEVER skip"
I28_B_ERE="${WB_L}default to (using|running|calling)${WB_R}|if in doubt,? use|${WB_L}always use${WB_R}|use even when"
# I25 retired sampling parameters (model range is a criteria-owned Detect
# condition; the scanner is model-blind and marks every prescription).
I25_ERE="${WB_L}temperature${WB_R}|${WB_L}top_p${WB_R}|${WB_L}top_k${WB_R}"

rows=()

# collect_rows <file> <check-id> <ere> <grep-flags> [<require-ere>] [<reject-ere>]
#
# Append one `file:line:check-id` row per line of <file> matching <ere>. The
# grep flags travel per call because I28-a is case-SENSITIVE by design — the
# all-caps marker IS the signal — while every other family folds case.
# <require-ere> keeps only hits whose text also matches (I27's brevity token,
# which must land on the SAME line as the effort directive); <reject-ere> drops
# hits whose text matches (I6's rationale marker).
collect_rows() {
  local file="$1" id="$2" ere="$3" grep_flags="$4" require="${5:-}" reject="${6:-}"
  local hit lineno text
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    lineno="${hit%%:*}"
    text="${hit#*:}"
    if [[ -n "$reject" ]] && printf '%s\n' "$text" | grep -qiE "$reject"; then
      continue
    fi
    if [[ -n "$require" ]] && ! printf '%s\n' "$text" | grep -qiE "$require"; then
      continue
    fi
    rows+=("$file:$lineno:$id")
  done < <(grep "$grep_flags" "$ere" "$file" 2>/dev/null)
}

scan_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  collect_rows "$file" I6 "$I6_ERE" -niE "" "$RATIONALE_ERE"
  collect_rows "$file" I10 "$I10_ERE" -niE
  collect_rows "$file" I23 "$I23_ERE" -niE
  collect_rows "$file" I8-a "$I8_A_ERE" -niE
  collect_rows "$file" I8-b "$I8_B_ERE" -niE
  collect_rows "$file" I8-c "$I8_C_ERE" -niE
  collect_rows "$file" I27 "$I27_EFFORT_ERE" -niE "$I27_BREVITY_ERE"
  collect_rows "$file" I28-a "$I28_A_ERE" -nE
  collect_rows "$file" I28-b "$I28_B_ERE" -niE
  collect_rows "$file" I25 "$I25_ERE" -niE
}

for file in "$@"; do
  scan_file "$file"
done

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#rows[@]}"
  exit 0
fi

if [[ "${#rows[@]}" -eq 0 ]]; then
  echo "No instruction candidates found."
else
  printf '%s\n' "${rows[@]}"
fi
exit 0
