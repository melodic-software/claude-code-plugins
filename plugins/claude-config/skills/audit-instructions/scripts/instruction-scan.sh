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
#       matching the catalog's Opus-5-scoped rows (the scanner is model-blind —
#       the model lane adjudicates against the resolved target model and the
#       criteria-owned fences):
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
#
# Advisory: prints candidate rows, ALWAYS exits 0 (candidates never fail a run).
# Requires grep; exits 2 when grep is absent.
#
# Rows are `file:line:check-id` (grep -n convention). With no rationale on a line
# a prohibition surfaces as an I6 row; a line may surface once per matching check
# id (I6, I10, and one of the I8 families). Nonexistent path arguments are
# skipped, not errors.
#
# Usage:
#   instruction-scan.sh FILE...            # one candidate row per line; exit 0
#   instruction-scan.sh --count FILE...    # integer candidate count only; exit 0
#   instruction-scan.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
instruction-scan.sh — mark I6/I8/I10 instruction candidates in given files.

Usage: instruction-scan.sh [--count|--help] FILE...

  FILE...    print one candidate row (file:line:check-id) per match; exit 0
  --count    print the integer candidate count only; exit 0
  --help     this message

I8 pattern families (model-era candidates; model lane adjudicates): I8-a
instructed self-check, I8-b conservative-reporting, I8-c don't-think /
don't-reason.

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
# I8 model-era candidate families (Opus-5-scoped catalog rows; scanner is
# model-blind; per-family ids I8-a/I8-b/I8-c). Stem forms (`re[- ]?verif`)
# deliberately catch inflections; over-production is the contract.
I8_A_ERE="double[- ]check|${WB_L}re[- ]?verif|final verification step|(sub)?agent to verify|have (a |an )?(sub)?agent verify|verifier (sub)?agent|verify your (own )?work"
I8_B_ERE="be conservative|(only report|report only) (the )?(high|critical)|(don('|’)?t|do not) nitpick"
I8_C_ERE="(do not|don('|’)?t) (think|reason)|without thinking|skip the reasoning"

rows=()

scan_file() {
  local file="$1" hit lineno text
  [[ -f "$file" ]] || return 0

  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    lineno="${hit%%:*}"
    text="${hit#*:}"
    printf '%s\n' "$text" | grep -qiE "$RATIONALE_ERE" && continue
    rows+=("$file:$lineno:I6")
  done < <(grep -niE "$I6_ERE" "$file" 2>/dev/null)

  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    lineno="${hit%%:*}"
    rows+=("$file:$lineno:I10")
  done < <(grep -niE "$I10_ERE" "$file" 2>/dev/null)

  local fam ere
  for fam in a b c; do
    case "$fam" in
      a) ere="$I8_A_ERE" ;;
      b) ere="$I8_B_ERE" ;;
      c) ere="$I8_C_ERE" ;;
      *) continue ;;
    esac
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      lineno="${hit%%:*}"
      rows+=("$file:$lineno:I8-$fam")
    done < <(grep -niE "$ere" "$file" 2>/dev/null)
  done
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
