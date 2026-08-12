#!/usr/bin/env bash
# draft-automode-block.sh — compose an `autoMode` block from interview answers,
# print it to stdout, and stop. The human reads it and pastes it.
#
# It writes nothing, anywhere, under any flag. That is not caution: a skill that
# edited a consumer's settings file would be making a permission decision on
# their behalf, which is the one thing this whole plugin exists NOT to do.
#
# Input: answer records on stdin, one per line, in the shape
#
#   section <environment|allow|soft_deny|hard_deny>
#   label   <short subject, the part before the colon>
#   covered <what IS covered — repeatable>
#   not     <what is NOT covered — repeatable>
#   why     <one line of rationale>
#
# A blank line, or the next `section` record, closes the current entry. The
# record shape mirrors what the interview asks, so the skill never has to
# transform answers into some other vocabulary on the way here.
#
# Why this shape, rather than free prose: `claude auto-mode critique` on a real
# 66 KB hand-authored block found that the classifier is "an LLM doing a single
# pass under a 'default is ALLOW' instruction", so "buried conditions in
# paragraph position 40 will be missed at a materially higher rate than
# conditions in a bullet list", and recommended exactly this — bulleted COVERED /
# NOT COVERED plus a one-line rationale, with provenance stripped. The entry
# template here IS that recommendation, applied at authoring time instead of
# reported after the fact.
#
# Output: a JSON object carrying only the sections that received entries, each
# opening with "$defaults" so the built-in rules are kept. Strict-parseable by
# construction — we author it, so `jq -e .` must accept it. (The non-strict
# allowance elsewhere in this plugin exists for the CLI's malformed emission,
# not for anything written here.)
#
# Prerequisites: jq (required for correctness — it does the JSON escaping, which
# is the one part of this that must not be hand-rolled).
#
# Usage:
#   draft-automode-block.sh < answers
#   draft-automode-block.sh [--help]

set -uo pipefail

usage() {
  cat <<'EOF'
draft-automode-block.sh — compose an autoMode block from interview answers.

Usage: draft-automode-block.sh < answers
       draft-automode-block.sh [--help]

Answer records, one per line:
  section <environment|allow|soft_deny|hard_deny>
  label   <short subject>
  covered <what IS covered>          repeatable
  not     <what is NOT covered>      repeatable
  why     <one line of rationale>

Prints a JSON object to stdout. Writes nothing, anywhere, under any flag —
paste the output into your own settings file yourself.

Every emitted section opens with "$defaults": a customized section REPLACES the
built-in rule list rather than adding to it, so omitting the token would discard
every shipped rule in that section.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
"") ;;
*)
  echo "ERROR: unknown argument '$1'" >&2
  exit 2
  ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required" >&2
  exit 2
fi

answers="$(cat)"
if [[ -z "${answers//[[:space:]]/}" ]]; then
  echo "ERROR: no answer records on input — nothing to draft" >&2
  exit 2
fi

# jq builds the whole document: it owns the escaping, and hand-rolling JSON
# string escaping in awk is how a draft ends up carrying the very defect this
# plugin reports elsewhere (a raw control character inside a string value).
printf '%s\n' "$answers" | jq -Rn '
  def trim: sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "");

  # Entry text follows the shape `claude auto-mode critique` recommends: a
  # label, then bulleted COVERED / NOT COVERED, then one line of rationale.
  # Conditions the classifier cannot evaluate from a transcript are the
  # documented weakness, so the interview is what keeps them out -- this only
  # renders what it was given.
  def render($e):
    ($e.label // "" | trim) as $label
    | ($e.covered // []) as $covered
    | ($e.not // []) as $not
    | ($e.why // "" | trim) as $why
    | [ "\($label):" ]
      + (if ($covered | length) > 0 then ["COVERED:"] + ($covered | map("- " + trim)) else [] end)
      + (if ($not | length) > 0 then ["NOT COVERED:"] + ($not | map("- " + trim)) else [] end)
      + (if $why != "" then ["Why: " + $why] else [] end)
    | join("\n");

  [inputs]
  | map(select(test("[^[:space:]]")))
  | reduce .[] as $line (
      {section: null, current: null, entries: []};
      ($line | capture("^[[:space:]]*(?<key>section|label|covered|not|why)[[:space:]]+(?<value>.*)$") // null) as $rec
      | if $rec == null then .
        elif $rec.key == "section" then
          (if .current != null then .entries += [.current] else . end)
          | .section = ($rec.value | trim)
          | .current = null
        elif $rec.key == "label" then
          (if .current != null then .entries += [.current] else . end)
          | .current = {section: .section, label: $rec.value, covered: [], not: [], why: ""}
        elif .current == null then .
        elif $rec.key == "covered" then .current.covered += [$rec.value]
        elif $rec.key == "not" then .current.not += [$rec.value]
        else .current.why = $rec.value
        end
    )
  | (if .current != null then .entries + [.current] else .entries end)
  # Only the four documented sections are emitted. A drafter that happily wrote
  # `bogus_section` (or "") into an autoMode block would be manufacturing
  # exactly the "written where nothing reads it" defect its audit sibling
  # exists to find -- the one thing an authoring tool must never produce.
  | map(select(.section != null and (.label | test("[^[:space:]]"))))
  # FAIL CLOSED on an unknown section rather than skipping it with a warning.
  #
  # Skipping printed a warning on stderr and valid JSON on stdout, which is
  # correct until the caller captures both together -- and agent tooling merges
  # streams by default, so the merged stream was not parseable JSON. Failing
  # loudly makes that impossible: there is no partial output left to corrupt.
  # It also matches the posture every script here already takes, where a
  # non-zero exit means "could not run" and never "found nothing". The cost is
  # nil: an unknown section is a typo in composed input, free to fix and rerun.
  #
  # A `_warnings` key inside the JSON was considered and rejected -- it would
  # land in the pasted autoMode block as a section the classifier does not read,
  # manufacturing the exact defect this check exists to prevent.
  | (map(select(.section | IN("environment", "allow", "soft_deny", "hard_deny") | not))
     | map(.section) | unique) as $unknown
  | (if ($unknown | length) > 0 then
       ("draft-automode-block.sh: unknown section(s): " + ($unknown | join(", "))
        + " -- the classifier reads only environment, allow, soft_deny and hard_deny. Nothing was drafted; fix the section name and rerun."
        | halt_error(2))
     else . end)
    | (map(select(.section | IN("environment", "allow", "soft_deny", "hard_deny")))
  | group_by(.section)
  | map({
      key: .[0].section,
      # "$defaults" leads every section: customizing REPLACES the built-in list
      # rather than adding to it, so a section without it silently discards
      # every shipped rule -- the exact defect the audit sibling reports.
      value: (["$defaults"] + map(render(.)))
    })
  | from_entries)
'
