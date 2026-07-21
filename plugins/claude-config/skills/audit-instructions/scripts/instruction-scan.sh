#!/usr/bin/env bash
# instruction-scan.sh — advisory deterministic pre-scan for the audit-instructions
# skill. Marks CANDIDATE lines for two of the catalog checks (reference/criteria.md)
# in the instruction files handed to it:
#
#   I6  bare prohibition ("never", "do not", "don't", "must not", "should not")
#       on a line that carries no rationale marker (because/since/so that/…). A
#       grep cannot judge whether a rationale is genuinely present or whether the
#       prohibition is a genuine hard "never", so these are candidates the model
#       lane refines — not confirmed findings.
#   I10 reasoning-echo directive (show/explain/reproduce your thinking or
#       reasoning, "think out loud", reasoning_extraction). These tell the model
#       to emit its internal reasoning as response text.
#
# Advisory: prints candidate rows, ALWAYS exits 0 (candidates never fail a run).
# Requires grep; exits 2 when grep is absent.
#
# Rows are `file:line:check-id` (grep -n convention). With no rationale on a line
# a prohibition surfaces as an I6 row; a line may surface once for I6 and once for
# I10. Nonexistent path arguments are skipped, not errors.
#
# Usage:
#   instruction-scan.sh FILE...            # one candidate row per line; exit 0
#   instruction-scan.sh --count FILE...    # integer candidate count only; exit 0
#   instruction-scan.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
instruction-scan.sh — mark I6/I10 instruction candidates in given files.

Usage: instruction-scan.sh [--count|--help] FILE...

  FILE...    print one candidate row (file:line:check-id) per match; exit 0
  --count    print the integer candidate count only; exit 0
  --help     this message

Advisory — always exits 0 (candidates never fail the run). Requires grep
(exit 2 when absent). Seeds the mechanical tier of the audit-instructions
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
# I6 prohibition tokens. `do NOT` folds into `do not` under -i.
I6_ERE="\\bnever\\b|\\bdo not\\b|\\bdon'?t\\b|\\bmust ?not\\b|\\bmustn'?t\\b|\\bshould ?not\\b|\\bshouldn'?t\\b"
# Rationale markers — a prohibition line carrying one of these is not an I6 candidate.
RATIONALE_ERE="because|\\bsince\\b|\\bso that\\b|\\bso it\\b|\\bso the\\b|\\bto avoid\\b|\\botherwise\\b|\\bin order to\\b|\\brationale\\b|\\breason\\b"
# I10 reasoning-echo phrasing.
I10_ERE="(show|explain|reproduce|echo|transcribe|verbalize|narrate|share|describe) (your |the )?(thinking|reasoning|thought process|chain of thought)"
I10_ERE="${I10_ERE}|think out loud|walk (me|us) through your (thinking|reasoning)|reasoning_extraction|chain[- ]of[- ]thought"

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
