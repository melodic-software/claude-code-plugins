#!/usr/bin/env bash
# conflict-scan.sh — advisory deterministic pre-scan for the audit-instructions
# skill's cross-surface conflict pass (reference/conflict-criteria.md).
#
# Emits CANDIDATE PAIRS: two lines in two DIFFERENT files that name the same
# entity with opposed polarity — one mandating it, one prohibiting it.
#
#   entity    a CamelCase identifier (AskUserQuestion, WebFetch, PreToolUse).
#             Derived by shape, never from a hardcoded tool list, so a tool the
#             scan has never heard of is still covered. The tradeoff is recall
#             over precision, not strictly better: CamelCase proper nouns
#             (GitHub, PowerShell, GraphQL) match the same shape and dominate a
#             repo-wide run. Entity triage is the lane's first refinement step.
#   mandate   the line requires the entity (must/always/mandatory/required/use)
#   prohibit  the line forbids it (the I6 token set, shared with instruction-scan.sh)
#
# Only the four gates a text scan can actually decide are applied here:
# distinct files, same entity, opposed polarity, and the config-gate filter.
# The remaining gates — whether the two lines constrain the same observable, and
# whether a realistic prompt fires both — are not greppable and belong to the
# model lane. This scan therefore narrows a quadratic search space to a review
# queue; it never reports a conflict.
#
# Advisory: prints candidate rows, ALWAYS exits 0 (candidates never fail a run).
# Requires grep; exits 2 when grep is absent.
#
# Rows are `fileA:lineA|fileB:lineB|entity|flags`, sorted and de-duplicated.
# `flags` is `-`, or a `+`-joined list drawn from:
#   exception-A / exception-B   that side carries an exception clause (unless,
#                               except, only when). The clause may or may not
#                               reach the other surface — that is gate 4, and
#                               the lane adjudicates it rather than the scan.
#
# A line whose entity mention is conditioned by an explicit user-config opt-in
# is SUPPRESSED, not flagged: an opt-in gate is arbitration, so the pair is
# resolved and is not a candidate.
#
# Nonexistent path arguments are skipped, not errors. Fewer than two readable
# files can produce no pair, which is a valid clean result.
#
# Usage:
#   conflict-scan.sh FILE...            # one candidate-pair row per match; exit 0
#   conflict-scan.sh --count FILE...    # integer candidate-pair count only; exit 0
#   conflict-scan.sh --help

set -uo pipefail

usage() {
  cat <<'EOF'
conflict-scan.sh — mark cross-surface conflict candidate PAIRS in given files.

Usage: conflict-scan.sh [--count|--help] FILE...

  FILE...    print one candidate row (fileA:lineA|fileB:lineB|entity|flags); exit 0
  --count    print the integer candidate-pair count only; exit 0
  --help     this message

Advisory — always exits 0 (candidates never fail the run). Requires grep
(exit 2 when absent). Seeds the mechanical tier of the audit-instructions
cross-surface conflict pass; the lane refines every candidate against
reference/conflict-criteria.md. A pair is a candidate, never a finding.
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

# --- Detection patterns ------------------------------------------------------
# Classification runs inside a single awk pass rather than a grep per mention:
# an instruction tree yields tens of thousands of mentions, and a subprocess per
# mention does not finish. Patterns are therefore written in awk ERE against a
# space-padded, lowercased window, so `[^a-z]` supplies the word boundary that
# POSIX awk has no `\b` for.
#
# Entity shape, case-SENSITIVE and matched on the raw line: a CamelCase
# identifier anywhere, or a single capitalized word INSIDE BACKTICKS. The second
# alternative is what reaches single-word tools (`Bash`, `Read`, `Edit`), which
# CamelCase alone cannot match; requiring the backticks is what keeps every
# sentence-initial capitalized word out. Backticks are stripped from the entity
# name, so a backticked and a bare mention of one tool pair with each other.
ENTITY_ERE='[A-Z][a-z]+([A-Z][a-z]*)+|`[A-Z][a-z]+`'
# Prohibition tokens — the I6 set, kept semantically identical to
# instruction-scan.sh so the two scans classify a line's polarity the same way.
PROHIBIT_ERE='[^a-z](never|do not|don[^a-z]?t|must ?not|mustn[^a-z]?t|should ?not|shouldn[^a-z]?t)[^a-z]'
# Mandate tokens. Checked only after prohibition, so "never use X" is a
# prohibition rather than an ambiguous both-polarity line.
MANDATE_ERE='[^a-z](must|always|mandator(y|ily)|require[ds]?|shall|use|present|ask)[^a-z]'
# Exception clauses — flagged, not suppressed. Whether the exception reaches the
# other surface is gate 4, which the lane decides.
EXCEPTION_ERE='[^a-z](unless|except|only when|only if|other than)[^a-z]'
# Explicit user-config opt-in gates — SUPPRESSED. An opt-in is arbitration, so
# the pair is already resolved. Generic by shape, not a per-plugin allowlist.
# Suppression additionally requires a CONDITIONAL marker, because naming an
# opt-in is not the same as being gated on one: "never use `X` for opt-in
# prompts" describes the subject and must still be classified as a prohibition.
GATED_ERE='(user_config|user config|[^a-z]opt-?in[^a-z]|[^a-z]opted in[^a-z])'
CONDITIONAL_ERE='[^a-z](only when|only if|unless|requires?|gated|enabled|is on|when set)[^a-z]'

# Polarity is read from a window around each entity mention, not from the whole
# line. A prose line often carries a prohibition about one object and names an
# unrelated entity elsewhere ("never offer them for `git branch -d` … via
# `AskUserQuestion`"); whole-line classification reads that as a conflict. The
# window keeps the polarity token in the same clause as the entity it governs.
WINDOW_CHARS="${CONFLICT_SCAN_WINDOW:-60}"

# Pairing is bucketed by entity, so the cross product is taken only within one
# entity's mandate and prohibit lists — never across the whole corpus.
mapfile -t rows < <(
  for file in "$@"; do
    [[ -f "$file" ]] && printf '%s\n' "$file"
  done | awk -v w="$WINDOW_CHARS" -v entpat="$ENTITY_ERE" -v prohibit="$PROHIBIT_ERE" \
    -v mandate="$MANDATE_ERE" -v exception="$EXCEPTION_ERE" -v gated="$GATED_ERE" \
    -v conditional="$CONDITIONAL_ERE" '
    function classify(file, lineno, ent, prewindow, postwindow, window,   pol, exc, key) {
      # An opt-in gate arbitrates the pair away, but only when it reads as a
      # condition rather than as the subject being described.
      if (window ~ gated && window ~ conditional) return
      # A prohibition governing the entity sits either before it ("never use X")
      # or immediately after it within the same sentence ("X must not be used").
      # Beyond a sentence break a trailing prohibition almost always governs a
      # different object ("… via `X` once. Do not gate per repo"), which is why
      # the caller truncates postwindow at the first sentence-ending mark.
      if (prewindow ~ prohibit || postwindow ~ prohibit) pol = "prohibit"
      else if (window ~ mandate) pol = "mandate"
      else return
      exc = (window ~ exception) ? "yes" : "no"
      key = pol SUBSEP ent SUBSEP file SUBSEP lineno SUBSEP exc
      if (key in seen) return
      seen[key] = 1
      n = ++count[pol, ent]
      rec[pol, ent, n] = file SUBSEP lineno SUBSEP exc
      if (!(ent in entities)) entities[ent] = 1
    }
    {
      # Filenames arrive on stdin so one awk process reads every file.
      file = $0
      while ((getline line < file) > 0) {
        lineno++
        gsub(/\t/, " ", line)
        pad = " " tolower(line) " "
        rest = line
        base = 0
        while (match(rest, entpat)) {
          # RSTART/RLENGTH are global and any later match() clobbers them, so the
          # loop advance is computed from copies taken before anything else runs.
          mstart = RSTART
          mlen = RLENGTH
          s = base + mstart
          e = s + mlen - 1
          ent = substr(rest, mstart, mlen)
          gsub(/`/, "", ent)
          ws = s - w
          if (ws < 1) ws = 1
          # Trailing text is cut at the first sentence-ending mark, so only a
          # prohibition inside the same sentence can flip the polarity.
          post = substr(pad, e + 2, w)
          if (match(post, /[.;!?]/)) post = substr(post, 1, RSTART - 1)
          classify(file, lineno, ent, \
            " " substr(pad, ws + 1, s - ws) " ", \
            " " post " ", \
            " " substr(pad, ws + 1, (e + w) - ws + 1) " ")
          base = e
          rest = substr(rest, mstart + mlen)
        }
      }
      close(file)
      lineno = 0
    }
    END {
      for (ent in entities) {
        for (i = 1; i <= count["mandate", ent]; i++) {
          split(rec["mandate", ent, i], a, SUBSEP)
          for (j = 1; j <= count["prohibit", ent]; j++) {
            split(rec["prohibit", ent, j], b, SUBSEP)
            # Cross-surface by definition: a pair inside one file is not a
            # finding here.
            if (a[1] == b[1]) continue
            flags = ""
            if (a[3] == "yes") flags = "exception-A"
            if (b[3] == "yes") flags = (flags == "") ? "exception-B" : flags "+exception-B"
            if (flags == "") flags = "-"
            print a[1] ":" a[2] "|" b[1] ":" b[2] "|" ent "|" flags
          }
        }
      }
    }
  ' | sort -u
)

if [[ "$mode" == "count" ]]; then
  printf '%s\n' "${#rows[@]}"
  exit 0
fi

if [[ "${#rows[@]}" -eq 0 ]]; then
  echo "No conflict candidates found."
else
  printf '%s\n' "${rows[@]}"
fi
exit 0
