#!/usr/bin/env bash
# Deterministic eval-QUALITY lint for skill evals/evals.json files.
#
# Complements schema validation (reference/evals.schema.json): the schema
# proves a case is structurally gradeable; this lint flags cases whose
# CONTENT undermines grading — duplicate identities, missing fixtures,
# empty or vague grading criteria, and sets missing the rich-form coverage
# the migration playbook asks for (trigger/routing, happy path, at least one
# refusal/guardrail, one anti-pattern). Static and deterministic: bash + jq,
# NO model invocation, so results are reproducible in CI.
#
# Exit 0 = no FAIL findings (WARNs allowed); 1 = one or more FAIL findings;
# 2 = usage/environment error (no jq, missing file, unparseable JSON —
# fail closed, never a silent skip; schema validation owns shape errors).
#
# Usage:
#   bash check-evals-quality.sh <evals.json> [<evals.json> ...]
#   bash check-evals-quality.sh --help
#
# Checks (Q1-Q4 FAIL; Q5-Q9 WARN — quality heuristics stay advisory so the
# gate never blocks on a judgment call):
#   Q1. Duplicate case `id` within a set (FAIL — ids must be stable and
#       unique for a grader to address a case)
#   Q2. Duplicate case `name` within a set (FAIL)
#   Q3. Non-gradeable grading criterion (FAIL — the schema only requires
#       the ARRAY be non-empty / the string be minLength 1): an
#       `expectations`/`assertions` item that is an empty or
#       whitespace-only string, null, or an empty container; or a
#       whitespace-only `expected_output` standing as a case's sole
#       criterion. Non-empty object/array items pass — item shape is
#       skill-author-defined
#   Q4. A `files` fixture entry that resolves to no file or directory
#       relative to the skill dir or the evals dir, or that escapes those
#       roots via an absolute path or a `..` component (FAIL — a case
#       whose fixtures cannot be found under the documented roots cannot
#       be exercised from the tree)
#   Q5. A case carrying BOTH `expectations` and `assertions` (WARN — the
#       schema treats them as equivalent alternatives; carrying both makes
#       the grading contract ambiguous. Pick one)
#   Q6. Two cases sharing an identical prompt AND identical files (WARN —
#       the second case adds no coverage unless its criteria differ for a
#       reason; usually a copy-paste residue)
#   Q7. Vague, unmeasurable criterion phrasing — a whole item (or a whole
#       expected_output) that says only "the output is good" / "works as
#       expected" etc. (WARN — Anthropic's evaluation guidance: criteria
#       must be specific and measurable; a grader is told what to look
#       for, what is allowed, what is disqualifying)
#   Q8. Sole-criterion expected_output thinner than EXPECTED_OUTPUT_MIN
#       chars after trimming, with no expectations/assertions (WARN — too
#       thin to guide a grader as rubric instructions; padding cannot
#       clear the floor)
#   Q9. Set-level coverage: no case in the set exhibits refusal/guardrail
#       or anti-pattern language (WARN — the playbook's rich form asks each
#       set to aim for at least one refusal/guardrail and one anti-pattern
#       case; detection is lexical, so treat as a prompt to check, not
#       proof of absence)
#
# Deliberately NOT checked: case count. The marketplace's low case volume
# is a RECORDED divergence from the guidance's volume-over-polish principle
# (see the playbook's "Method source"), revisited when the deferred runner
# lands — a volume lint would contradict that recorded decision.
#
# Fixture resolution (Q4): each `files` entry is looked up relative to the
# SKILL directory (the parent of the evals dir — the playbook's convention)
# and, as a fallback, the evals dir itself. Entries naming files the eval
# RUNNER must synthesize (consumer-repo state like `.claude/<config>.md`)
# should still ship a fixture copy at one of those roots so the case stays
# exercisable from the tree.
set -uo pipefail

# The header range is derived from the comment block itself, so adding
# header lines can never desync the help output.
usage() {
  awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: jq is required (quality lint is jq-based; schema validation is a separate step)\n' >&2
  exit 2
fi

if [[ $# -lt 1 ]]; then
  printf 'Usage: check-evals-quality.sh <evals.json> [<evals.json> ...]\n' >&2
  exit 2
fi

for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    printf 'Error: not a file: %s\n' "$f" >&2
    exit 2
  fi
done

# Tunables.
EXPECTED_OUTPUT_MIN=40
# Q7: whole-item hedges only — a substring match would flag verifiable
# criteria that merely contain a hedge word ("Touches no files" is fine).
VAGUE_RE='^(the )?(output|response|result|it) (is|looks|seems) (good|correct|right|fine|reasonable|appropriate|as expected)[.]?$|^(works( as expected| correctly| well)?|correct( behavior)?|looks good|handles it( gracefully| well)?|good (output|behavior|response)|behaves (correctly|properly|well|as expected)|responds appropriately)[.]?$'
# Q9: lexical signal that a case pins behavior the skill must NOT exhibit.
# Deliberately lenient (matches inside longer words/phrases): under-warning
# beats noise for an advisory check.
NEGATIVE_RE='refus|declin|must not|does not|doesn.t|never|reject|block|anti-pattern|antipattern|not |guardrail|instead of|rather than|without'

FAILED=0
WARNINGS=0

err() {
  printf 'FAIL: %s\n' "$*" >&2
  FAILED=$((FAILED + 1))
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
  WARNINGS=$((WARNINGS + 1))
}

# One jq pass over every file: emits KIND<US>message lines (US = 0x1f), with
# FILE<US>path lines for the fixture-existence check bash must do itself.
# input_filename keys each finding to its source file. jq aborts on the
# first unparseable input — that surfaces as exit 2 below (fail closed;
# point schema validation at the file).
# shellcheck disable=SC2016  # single quotes are deliberate: the $names inside are jq variables, not shell expansions
JQ_PROG='
  input_filename as $f |
  def items: ((.expectations // []) + (.assertions // []));
  def caseref: if .name then "case \(.name) (id=\(.id))" else "case id=\(.id)" end;
  (.evals // []) as $cases |
  # Q1: duplicate ids (int 1 and string "1" collide by design — an id pair
  # distinguishable only by JSON type is still ambiguous to a grader).
  ($cases | group_by(.id | tostring) | .[] | select(length > 1)
    | "FAIL" + $u + "\($f): duplicate case id \(.[0].id | tostring) used by \(length) cases (Q1)"),
  # Q2: duplicate names.
  ($cases | map(select(.name)) | group_by(.name) | .[] | select(length > 1)
    | "FAIL" + $u + "\($f): duplicate case name \(.[0].name) used by \(length) cases (Q2)"),
  # Q3: non-gradeable criterion items — empty/whitespace-only strings, null,
  # and empty containers. Non-empty objects/arrays pass: the schema leaves
  # item shape skill-author-defined (upstream assertions may be structured).
  ($cases[] | caseref as $c | items[]?
    | select((type == "string" and (gsub("\\s+"; "") == ""))
             or type == "null"
             or ((type == "array" or type == "object") and length == 0))
    | "FAIL" + $u + "\($f): \($c): empty or non-gradeable expectations/assertions item (empty/whitespace string, null, or empty container) — an empty criterion cannot be graded (Q3)"),
  # Q3 also covers a sole-criterion expected_output that is whitespace-only:
  # it clears the schema (minLength counts whitespace) yet cannot be graded.
  ($cases[] | select(.expectations == null and .assertions == null)
    | select((.expected_output // "") | (length > 0) and (gsub("\\s"; "") == ""))
    | caseref as $c
    | "FAIL" + $u + "\($f): \($c): whitespace-only expected_output is the sole grading criterion — it cannot be graded (Q3)"),
  # Q4: fixture entries, resolved by bash.
  ($cases[] | caseref as $c | .files[]?
    | "FILE" + $u + "\($f)" + $u + "\($c)" + $u + "\(.)"),
  # Q5: both field names on one case.
  ($cases[] | select(.expectations != null and .assertions != null) | caseref as $c
    | "WARN" + $u + "\($f): \($c): carries BOTH expectations and assertions — the fields are equivalent alternatives; pick one (Q5)"),
  # Q6: identical prompt + files pair.
  ($cases | group_by([.prompt, (.files // [])]) | .[] | select(length > 1)
    | "WARN" + $u + "\($f): cases \(map(.id | tostring) | join(", ")) share an identical prompt and files — distinguishable only by criteria or out-of-band context; confirm the duplication is intentional (Q6)"),
  # Q7: vague whole-item criteria (items and expected_output).
  ($cases[] | caseref as $c |
    ((items[]? | select(type == "string")), (.expected_output // empty))
    | select(test($vague; "i"))
    | "WARN" + $u + "\($f): \($c): vague criterion \"\(.)\" — state what a grader must find, not that the output is good (Q7)"),
  # Q8: thin sole-criterion expected_output. Length is measured after
  # trimming, so padding cannot clear the floor; whitespace-only strings are
  # Q3 FAILs and excluded here to avoid a double report.
  ($cases[] | select(.expectations == null and .assertions == null)
    | select((.expected_output // "") | (gsub("\\s"; "") != "") or . == "")
    | select(((.expected_output // "") | gsub("^\\s+|\\s+$"; "") | length) < $min) | caseref as $c
    | "WARN" + $u + "\($f): \($c): sole grading criterion is a \((.expected_output // "") | gsub("^\\s+|\\s+$"; "") | length)-char expected_output (min \($min)) — too thin to guide a grader (Q8)"),
  # Q9: set-level refusal/anti-pattern coverage.
  (if ($cases | length) > 0 and
      ([$cases[] | [(.name // ""), .prompt, (.expected_output // ""),
                    (items | map(tostring) | join(" "))] | join(" ")]
       | any(test($neg; "i")) | not)
   then "WARN" + $u + "\($f): no case exhibits refusal/guardrail or anti-pattern language — the rich form aims for at least one of each (lexical check; verify by reading the set) (Q9)"
   else empty end)
'

# US (0x1f) delimits lint-line fields — it cannot appear in jq -r output of
# JSON string content, so fields with spaces/tabs survive the bash read.
US=$'\x1f'
LINT_OUT="$(jq -r --arg u "$US" --arg vague "$VAGUE_RE" --arg neg "$NEGATIVE_RE" \
  --argjson min "$EXPECTED_OUTPUT_MIN" "$JQ_PROG" "$@" 2>&1)"
JQ_RC=$?
LINT_OUT="$(printf '%s' "$LINT_OUT" | tr -d '\r')"

if [[ $JQ_RC -ne 0 ]]; then
  printf 'Error: jq failed (unparseable JSON or internal error) — run schema validation on the input first:\n%s\n' "$LINT_OUT" >&2
  exit 2
fi

while IFS="$US" read -r kind a b c; do
  [[ -z "$kind" ]] && continue
  case "$kind" in
    FAIL) err "$a" ;;
    WARN) warn "$a" ;;
    FILE)
      # a=file, b=caseref, c=fixture path. Resolve relative to the skill dir
      # (parent of the evals dir), then the evals dir. An absolute path or a
      # `..` component escapes the documented roots — reject it BEFORE the
      # existence test, so a traversal entry can never pass by pointing at a
      # host file that happens to exist.
      if [[ "$c" == /* || "$c" =~ ^[A-Za-z]: || "/$c/" == *"/../"* ]]; then
        err "$a: $b: files entry \"$c\" escapes the documented fixture roots (absolute path or '..' component) — fixtures must live under the skill or evals directory (Q4)"
      else
        evals_dir="$(dirname "$a")"
        skill_dir="$(dirname "$evals_dir")"
        if [[ ! -e "$skill_dir/$c" && ! -e "$evals_dir/$c" ]]; then
          err "$a: $b: files entry \"$c\" not found under $skill_dir/ or $evals_dir/ — a case whose fixtures cannot be found cannot be exercised (Q4)"
        fi
      fi
      ;;
    *) err "internal: unrecognized lint line kind '$kind'" ;;
  esac
done <<<"$LINT_OUT"

if [[ $FAILED -gt 0 ]]; then
  printf 'check-evals-quality: FAIL (%d failure(s), %d warning(s) across %d file(s))\n' "$FAILED" "$WARNINGS" "$#"
  exit 1
fi
printf 'check-evals-quality: PASS (%d warning(s) across %d file(s))\n' "$WARNINGS" "$#"
exit 0
