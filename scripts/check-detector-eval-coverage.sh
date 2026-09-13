#!/usr/bin/env bash
# Gate: a skill's eval suite and its detector must agree on the check-id set,
# in BOTH directions.
#
#   scripts/check-detector-eval-coverage.sh          discover: per registered
#                                                     pair, print the emitted
#                                                     ids, the eval-named ids,
#                                                     and each id's status
#   scripts/check-detector-eval-coverage.sh --check  fail if an emitted id is
#                                                     covered by no eval case, or
#                                                     an eval case names an id
#                                                     the detector cannot emit
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): 0 clean, 1 findings, 2 environment or usage, findings on stderr.
#
# WHY. claude-code-plugins#4149 found claude-config:audit-permission-grants
# emitting five check ids while its eval suite exercised three, and one case
# (`scope-boundary-routes-out`) asserting in prose that the owned scope IS the
# stale three. So the suite did not merely under-cover the detector: it graded a
# model for ignoring a check that fires. Backfilling the missing cases closes
# that instance; nothing stopped the NEXT added check from reopening it, which
# is what this gate is.
#
# The reverse direction is the half that would have caught the stale case, and
# it is the half a coverage-only check omits. An eval naming an id the detector
# cannot emit is either a check that was renamed out from under its suite or a
# scope claim that was never true. Both read as coverage until something asks
# the detector.
#
# WHAT COUNTS AS COVERAGE, and why it is not "the string appears in the file".
# An earlier revision read every string anywhere in evals.json through
# `.. | strings`. That verifies MENTION, not coverage, and four shapes passed it
# while covering nothing: an id named only inside a NEGATIVE assertion ("does
# NOT exercise P4"), an id that is only an incidental path token in `files`
# (`~/w/P4/settings.json`), a suite with ZERO cases whose id appears only in
# top-level `skill_name`, and a file that is a bare JSON string -- `jq -e .`
# accepts one, so parseability was the only shape check there was.
#
# So the shape is asserted first: the suite must be a JSON OBJECT carrying a
# NON-EMPTY `evals` ARRAY whose every entry is an OBJECT. Anything else is exit
# 2 (a suite this gate cannot read), never a pass. A mention outside `evals[]`
# -- `skill_name` included -- counts for nothing.
#
# Within an entry, the coverage-bearing fields are `expected_output` and
# `expectations`, and only those. Read the real suite
# (plugins/claude-config/skills/audit-permission-grants/evals/evals.json): an
# entry carries `id`, `name`, `prompt`, `files`, `expected_output`,
# `expectations`. Of those, `expected_output` and `expectations` are the two the
# runner GRADES a response against, so naming a check id there is the suite
# asserting that check is exercised. The rest cannot carry that force: `prompt`
# is the operator's INPUT (naming an id there feeds it to the model, it does not
# grade it), `name` is a label, `files` is fixture paths (the incidental-token
# shape above), and `id` is an ordinal.
#
# NEGATIVE ASSERTIONS, and the residue that stays open. A graded expectation can
# name an id in order to assert it is NOT exercised, and that is the opposite of
# coverage. This gate screens it with a bounded heuristic: within a
# coverage-bearing string, an id occurrence does not count as covering when a
# negation cue (not / never / without / n't / excludes / omits / ignores /
# neither / nor) appears in the same clause before it -- clause being the text
# back to the previous `.`, `;` or `:`, capped at 80 characters. That closes the
# blunt shapes ("deliberately does NOT exercise P4") and nothing more. It is a
# heuristic over English, and it is NOT closed: a negation phrased around the
# cue set, or one that spans a clause boundary ("P4 is out of scope. It is never
# exercised."), still reads as coverage here. Treat a passing run as "no case
# obviously disclaims this id", not as proof the case exercises it. The screen
# is deliberately one-directional: a negatively-named id is still NAMED, so it
# still has to be emittable, because disclaiming an id the detector cannot emit
# is the same stale-scope claim in a different voice.
#
# ACCOUNTING FOR EVERY EMIT CALL SITE, and why a partial loss is exit 2. The
# emitted-id set comes from `emit <severity> <id>` call sites. An earlier
# revision extracted them with one greedy sed and guarded only the case where
# extraction yielded exactly ZERO, so every PARTIAL loss passed silently:
# `emit "$sev" P4` (variable severity), `emit error "$id"` (variable id), two
# emits on one line (the greedy `.*` kept only the last), a partially renamed
# emitter, and an id outside the row's pattern (`P2ab` under `P[0-9]+[a-z]?`)
# each dropped an id while the rest of the file kept the count non-zero.
#
# So the scanner COUNTS candidate call sites and compares that count against the
# ids it actually resolved. Any mismatch is exit 2 -- cannot determine -- and
# names the unparsed sites. A gate that cannot see its inputs must never pass,
# and an emitter shape this scanner cannot read is exactly that.
#
# The scanner reads shell rather than grepping it: heredoc bodies and quoted
# string contents are removed before any call site is looked for, so an
# `emit error P9` inside the detector's own help text or prose is not a call
# site (which the greedy sed counted, yielding a permanent false failure), and a
# `#` comment after real code is dropped once quoting is resolved. RESIDUE: an
# emitter renamed to something that does not begin with `emit` is invisible to
# both the count and the extraction; a total rename still trips the zero-ids
# guard, a partial one to such a name does not.
#
# Adjacent and DIFFERENT: scripts/check-detector-findings-crosswalk.sh checks
# that each severity-crosswalk row in docs/conventions/detector-findings/ argues
# its disposition from a stated test. That is a judgment about a markdown table
# and says nothing about eval coverage.
# scripts/check-fleet-finding-test-coverage.sh is the same SHAPE one surface
# over (emitted kinds vs unit-test assertions) for one named collector; it does
# not read any evals.json.
#
# WHY A REGISTRY RATHER THAN DISCOVERY, AND WHY DISCOVERY ANYWAY. Globbing
# plugins/*/skills/*/ for a detector plus an evals.json finds the pair, but not
# the third fact the comparison needs: the shape of that detector's check ids.
# They are a per-skill vocabulary (`P1`/`P2b` here, something else next time),
# and a gate that guessed the shape would go quietly empty on the first detector
# that spelled them differently. A registry row carries the id pattern
# explicitly.
#
# But a registry with no stopping rule leaves the first NEW detector-plus-evals
# skill silently unenforced, which is the same false-green one level up.
# scripts/check-script-contract.test.sh already answers this for its own family
# ("THE REGISTRY IS THE STOPPING RULE": a new member fails as UNREGISTERED
# rather than being quietly uncovered), so this follows that precedent. Every
# run walks plugins/*/skills/*/ for a QUALIFYING pair -- a skill with an
# evals/evals.json and a non-test script carrying at least two distinct
# `emit <word> <ID>` call sites whose ID is check-id shaped
# (/[A-Z][A-Za-z]*[0-9]+[A-Za-z0-9]*/) -- and an unregistered one is a FINDING
# (exit 1), not an environment answer: the tree is in a real state with a real
# remedy, which is to add the row. Two distinct ids is what separates a check-id
# vocabulary from an `emit <scope> <kind>` printer; the other emitters in this
# repo (permission-state.sh, discover-instruction-surfaces.sh,
# file-provenance.sh) pass none and are correctly not candidates.
#
# Registry row: <detector script>|<evals.json>|<check-id ERE>
#
# The ERE matches WHOLE word tokens on both sides: the detector's resolved
# `emit <severity> <id>` call sites, and the coverage-bearing strings of each
# eval entry. So `P1` in `PLAN1` and `P4` in `xP4` name nothing, while `P2` in
# `(P1/P2/P3)` names P2. The row's pattern must therefore describe an id made of
# [A-Za-z0-9_]; an id family spelled with punctuation needs this splitting rule
# revisited rather than a wider pattern.
#
# The boundaries are spelled out rather than written as \b, which is a GNU
# extension scripts/check-shell-portability.sh rejects.
#
# DETECTOR_EVAL_COVERAGE_PAIRS overrides the rows (newline-separated), for the
# self-test and for historical proofs.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

PAIRS_DEFAULT=(
  "plugins/claude-config/skills/audit-permission-grants/scripts/permission-rule-check.sh|plugins/claude-config/skills/audit-permission-grants/evals/evals.json|P[0-9]+[a-z]?"
)

# The check-id SHAPE the stopping rule recognizes across skills it has never
# seen. Deliberately wider than any row's own pattern: this one only has to
# decide "is this a check-id vocabulary at all", and the row that follows states
# the real spelling.
QUALIFYING_ID_ERE='[A-Z][A-Za-z]*[0-9]+[A-Za-z0-9]*'

# Argv is exact. `--check extra` used to ignore its trailing words, which reads
# as a mode the gate accepted and did not run.
if [[ "$#" -gt 1 ]]; then
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
fi
mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

# Read the eval suite through a JSON parser, not a grep: a suite that no longer
# parses must be an environment answer, never a pass. jq is the prerequisite and
# its absence is exit 2 before anything reaches stdout.
if ! command -v jq >/dev/null 2>&1; then
  echo "check-detector-eval-coverage: jq not found; cannot read any eval suite" >&2
  exit 2
fi

# --- the emit-call-site scanner ----------------------------------------------
# Removes heredoc bodies and quoted contents, then resolves each candidate call
# site to an id or reports it unresolved. Emits `ID <id>` lines, `UNRESOLVED
# <site>` lines, and a final `CANDIDATES <n>`.
EMIT_SCAN_AWK=""
read -r -d '' EMIT_SCAN_AWK <<'AWK'
BEGIN { hd = ""; candidates = 0; anchored = "^(" idre ")$" }
{
  line = $0

  # Inside a heredoc body: prose, usage text, or a template. Never a call site.
  if (hd != "") {
    t = line
    sub(/^[[:space:]]*/, "", t)
    sub(/[[:space:]]*$/, "", t)
    if (t == hd) hd = ""
    next
  }

  if (line ~ /^[[:space:]]*#/) next

  # A heredoc OPENING on this line arms the skip for the lines after it. `<<<`
  # is a here-string and opens no body.
  s2 = line
  while ((r = index(s2, "<<")) > 0) {
    tail = substr(s2, r + 2)
    if (substr(tail, 1, 1) == "<") { s2 = substr(s2, r + 3); continue }
    if (substr(tail, 1, 1) == "-") tail = substr(tail, 2)
    sub(/^[[:space:]]*/, "", tail)
    if (match(tail, /^("[A-Za-z_][A-Za-z0-9_]*"|'[A-Za-z_][A-Za-z0-9_]*'|\\?[A-Za-z_][A-Za-z0-9_]*)/)) {
      d = substr(tail, RSTART, RLENGTH)
      gsub(/["'\\]/, "", d)
      hd = d
    }
    break
  }

  # Quoted contents become one opaque @Q@ token, which preserves each call
  # site's ARITY (so `emit "$sev" P4` stays three words and is seen as
  # unresolved) while making prose inside a string unreadable as code. A `#`
  # that survives the walk is a real comment: drop the rest of the line.
  out = ""
  n = length(line)
  i = 1
  q = ""
  while (i <= n) {
    c = substr(line, i, 1)
    if (q == "") {
      if (c == "\\") { i += 2; continue }
      if (c == "\"" || c == "'") { q = c; out = out "@Q@"; i++; continue }
      if (c == "#") {
        p = (out == "") ? "" : substr(out, length(out), 1)
        if (p == "" || p ~ /[[:space:]]/) break
      }
      out = out c
      i++
    } else {
      if (q == "\"" && c == "\\") { i += 2; continue }
      if (c == q) { q = ""; i++; continue }
      i++
    }
  }

  # A definition (`emit() {`) is not a call. Separators become whitespace so
  # that two call sites on one line are two sites, not one.
  gsub(/[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/, " ", out)
  gsub(/[;&|(){}`<>]/, " ", out)

  nt = split(out, tok, /[[:space:]]+/)
  for (k = 1; k <= nt; k++) {
    if (tok[k] !~ /^emit[A-Za-z0-9_]*$/) continue
    candidates++
    sev = (k + 1 <= nt) ? tok[k + 1] : ""
    id = (k + 2 <= nt) ? tok[k + 2] : ""
    if (sev ~ /^[A-Za-z][A-Za-z0-9_]*$/ && id ~ anchored) {
      print "ID " id
    } else {
      site = line
      sub(/^[[:space:]]*/, "", site)
      print "UNRESOLVED line " FNR ": " site
    }
  }
}
END { print "CANDIDATES " candidates }
AWK

# --- the coverage-bearing-string reader --------------------------------------
# Reads one JSON-encoded string per line and prints `COVERING <id>` for each
# whole-token id occurrence no negation cue disclaims, and `NAMED <id>` for
# every occurrence including the disclaimed ones.
COVERAGE_AWK=""
read -r -d '' COVERAGE_AWK <<'AWK'
BEGIN {
  apos = sprintf("%c", 39)
  cue = "(^|[^a-z0-9_])(not|never|without|n" apos "t|excludes?|omits?|ignores?|neither|nor)([^a-z0-9_]|$)"
}
{
  rest = $0
  done = ""
  while (match(rest, idre)) {
    s = RSTART
    l = RLENGTH
    before = (s > 1) ? substr(rest, s - 1, 1) : substr(done, length(done), 1)
    after = substr(rest, s + l, 1)
    id = substr(rest, s, l)
    if ((before == "" || before !~ /[A-Za-z0-9_]/) && (after == "" || after !~ /[A-Za-z0-9_]/)) {
      print "NAMED " id
      clause = done substr(rest, 1, s - 1)
      # Back to the previous clause break, then capped, so a cue far away in an
      # unrelated sentence cannot disclaim this occurrence.
      if (match(clause, /^.*[.;:]/)) clause = substr(clause, RSTART + RLENGTH)
      if (length(clause) > 80) clause = substr(clause, length(clause) - 79)
      if (tolower(clause) !~ cue) print "COVERING " id
    }
    done = done substr(rest, 1, s + l - 1)
    rest = substr(rest, s + l)
  }
}
AWK

pairs=()
if [[ -n "${DETECTOR_EVAL_COVERAGE_PAIRS:-}" ]]; then
  while IFS= read -r line; do
    [[ -n "${line//[[:space:]]/}" ]] && pairs+=("$line")
  done <<<"$DETECTOR_EVAL_COVERAGE_PAIRS"
else
  pairs=("${PAIRS_DEFAULT[@]}")
fi

if [[ "${#pairs[@]}" -eq 0 ]]; then
  echo "check-detector-eval-coverage: no registered pairs; there is nothing this run could have inspected" >&2
  exit 2
fi

emitted_tmp="$(mktemp)" || exit 2
named_tmp="$(mktemp)" || exit 2
covering_tmp="$(mktemp)" || exit 2
scan_tmp="$(mktemp)" || exit 2
strings_tmp="$(mktemp)" || exit 2
# Discover-mode stdout is BUFFERED, not streamed: a per-row exit 2 used to leave
# a partial report on stdout with no denominator trailer under it, and the
# check-script contract says a run that inspected nothing says nothing there.
report_tmp="$(mktemp)" || exit 2
trap 'rm -f "$emitted_tmp" "$named_tmp" "$covering_tmp" "$scan_tmp" "$strings_tmp" "$report_tmp"' EXIT

errors=0
total_emitted=0
total_named=0

# qualifying_detectors -- every non-test skill script that carries a check-id
# vocabulary next to an eval suite. The greedy `.*` keeps only the LAST call
# site per line, which is fine here and nowhere else: this only has to find two
# distinct ids somewhere in the file, not the whole set.
qualifying_detectors() {
  local evals_path skill script ids count
  for evals_path in plugins/*/skills/*/evals/evals.json; do
    [[ -f "$evals_path" ]] || continue
    skill="${evals_path%/evals/evals.json}"
    [[ -d "$skill/scripts" ]] || continue
    for script in "$skill"/scripts/*.sh; do
      [[ -f "$script" ]] || continue
      case "$script" in
      *.test.sh) continue ;;
      *) ;;
      esac
      ids="$(grep -vE '^[[:space:]]*#' "$script" |
        sed -nE "s/.*(^|[^A-Za-z0-9_])emit[A-Za-z0-9_]*[[:space:]]+[A-Za-z][A-Za-z0-9_]*[[:space:]]+(${QUALIFYING_ID_ERE})([^A-Za-z0-9_].*)?\$/\\2/p" |
        sort -u)"
      count="$(printf '%s' "$ids" | grep -c .)"
      [[ "$count" -ge 2 ]] && printf '%s\n' "$script"
    done
  done
}

for row in "${pairs[@]}"; do
  detector="${row%%|*}"
  rest="${row#*|}"
  evals="${rest%%|*}"
  id_re="${rest#*|}"

  if [[ -z "$detector" || -z "$evals" || -z "$id_re" || "$evals" == "$rest" ]]; then
    echo "check-detector-eval-coverage: malformed registry row: $row" >&2
    exit 2
  fi
  if [[ ! -r "$detector" ]]; then
    echo "check-detector-eval-coverage: detector not readable: $detector" >&2
    exit 2
  fi
  if [[ ! -r "$evals" ]]; then
    echo "check-detector-eval-coverage: eval suite not readable: $evals" >&2
    exit 2
  fi

  # A suite that covers no id is a real answer (every emitted id is then
  # uncovered, which is a finding). A suite that does not PARSE, or that is not
  # the SHAPE coverage can be read out of, is not an answer at all.
  if ! jq -e . "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not valid JSON; the eval-named id set cannot be read" >&2
    exit 2
  fi
  if ! jq -e 'type == "object" and (.evals | type) == "array" and (.evals | length) > 0 and ([.evals[] | type] | all(. == "object"))' \
    "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not a suite this gate can read coverage out of; it must be a JSON object whose 'evals' is a non-empty array of objects" >&2
    exit 2
  fi

  # Emitted ids, with every candidate call site accounted for.
  if ! awk -v idre="$id_re" "$EMIT_SCAN_AWK" "$detector" >"$scan_tmp" 2>/dev/null; then
    echo "check-detector-eval-coverage: the emit-call-site scan of $detector failed; the emitted id set cannot be read" >&2
    exit 2
  fi
  sed -n 's/^ID //p' "$scan_tmp" | sort -u >"$emitted_tmp"
  candidate_count="$(sed -n 's/^CANDIDATES //p' "$scan_tmp" | tail -n 1)"
  resolved_count="$(grep -c '^ID ' "$scan_tmp")"

  if [[ "$candidate_count" != "$resolved_count" ]]; then
    {
      echo "check-detector-eval-coverage: $detector has $candidate_count emit call site(s) but only $resolved_count resolved to a check id under /${id_re}/; the emitted id set is incomplete, so no verdict is available"
      sed -n 's/^UNRESOLVED /  unparsed: /p' "$scan_tmp"
    } >&2
    exit 2
  fi

  # Eval-named and eval-COVERING ids, read only out of entries of `evals` and
  # only out of the two fields the runner grades against.
  jq -r '.evals[] | (.expected_output, .expectations) | .. | strings | @json' "$evals" >"$strings_tmp"
  awk -v idre="$id_re" "$COVERAGE_AWK" "$strings_tmp" >"$scan_tmp"
  sed -n 's/^NAMED //p' "$scan_tmp" | sort -u >"$named_tmp"
  sed -n 's/^COVERING //p' "$scan_tmp" | sort -u >"$covering_tmp"

  emitted_count="$(grep -c . "$emitted_tmp")"
  named_count="$(grep -c . "$named_tmp")"

  # A detector that emits nothing under the row's pattern means the extraction
  # broke (an emitter renamed, an id shape changed), not that the suite is
  # complete. Passing here would be the false-green this gate exists to stop.
  if [[ "$emitted_count" -eq 0 ]]; then
    echo "check-detector-eval-coverage: no check ids extracted from $detector with /${id_re}/; the extraction, not the eval suite, is broken" >&2
    exit 2
  fi

  total_emitted=$((total_emitted + emitted_count))
  total_named=$((total_named + named_count))

  if [[ "$mode" == "discover" ]]; then
    {
      echo "$detector"
      echo "  evals:          $evals"
      echo "  id pattern:     $id_re"
      echo "  emitted ids:    $emitted_count"
      echo "  eval-named ids: $named_count"
      while IFS= read -r id; do
        if grep -Fxq -- "$id" "$covering_tmp"; then
          printf '    COVERED    %s\n' "$id"
        else
          printf '    UNCOVERED  %s\n' "$id"
        fi
      done <"$emitted_tmp"
      while IFS= read -r id; do
        grep -Fxq -- "$id" "$emitted_tmp" || printf '    UNEMITTABLE %s\n' "$id"
      done <"$named_tmp"
    } >>"$report_tmp"
  else
    while IFS= read -r id; do
      if ! grep -Fxq -- "$id" "$covering_tmp"; then
        echo "UNCOVERED CHECK ID: $id is emitted by $detector and covered by no case in $evals" >&2
        errors=$((errors + 1))
      fi
    done <"$emitted_tmp"

    # The direction that catches a suite asserting a scope the detector outgrew.
    while IFS= read -r id; do
      if ! grep -Fxq -- "$id" "$emitted_tmp"; then
        echo "UNEMITTABLE CHECK ID: $id is named in $evals and $detector cannot emit it" >&2
        errors=$((errors + 1))
      fi
    done <"$named_tmp"
  fi
done

# The stopping rule. Runs after the rows so an unregistered pair is reported
# alongside them rather than instead of them.
registered_detectors=""
for row in "${pairs[@]}"; do
  registered_detectors+="${row%%|*}"$'\n'
done
while IFS= read -r candidate; do
  [[ -n "$candidate" ]] || continue
  if ! printf '%s' "$registered_detectors" | grep -Fxq -- "$candidate"; then
    if [[ "$mode" == "discover" ]]; then
      printf 'UNREGISTERED PAIR: %s emits check ids beside an eval suite and has no registry row\n' \
        "$candidate" >>"$report_tmp"
    else
      echo "UNREGISTERED PAIR: $candidate emits check ids beside an eval suite and has no registry row, so nothing compares them; add a row" >&2
      errors=$((errors + 1))
    fi
  fi
done < <(qualifying_detectors)

if [[ "$mode" == "discover" ]]; then
  cat "$report_tmp"
  echo "check-detector-eval-coverage: ${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s)"
  exit 0
fi

if [[ "$errors" -gt 0 ]]; then
  echo "check-detector-eval-coverage: FAILED — $errors gap(s) across ${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s)" >&2
  exit 1
fi

echo "check-detector-eval-coverage: passed — every emitted check id is covered by an eval case and every eval-named id is emittable (${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s))"
exit 0
