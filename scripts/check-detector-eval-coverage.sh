#!/usr/bin/env bash
# Gate: a skill's eval suite and its detector must agree on the check-id set,
# in BOTH directions.
#
#   scripts/check-detector-eval-coverage.sh          discover: per registered
#                                                     pair, print the emitted
#                                                     ids, the eval-named ids,
#                                                     and each id's status
#   scripts/check-detector-eval-coverage.sh --check  fail if an emitted id is
#                                                     named by no eval case, or
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
# Adjacent and DIFFERENT: scripts/check-detector-findings-crosswalk.sh checks
# that each severity-crosswalk row in docs/conventions/detector-findings/ argues
# its disposition from a stated test. That is a judgment about a markdown table
# and says nothing about eval coverage.
# scripts/check-fleet-finding-test-coverage.sh is the same SHAPE one surface
# over (emitted kinds vs unit-test assertions) for one named collector; it does
# not read any evals.json.
#
# WHY A REGISTRY RATHER THAN DISCOVERY. Globbing plugins/*/skills/*/ for a
# detector plus an evals.json finds the pair, but not the third fact the
# comparison needs: the shape of that detector's check ids. They are a per-skill
# vocabulary (`P1`/`P2b` here, something else next time), and a gate that
# guessed the shape would go quietly empty on the first detector that spelled
# them differently, reporting a clean run over nothing. A registry row carries
# the id pattern explicitly, and an unregistered skill is honestly unenforced
# rather than falsely green. Rows are cheap: add one when a skill grows both
# surfaces.
#
# Registry row: <detector script>|<evals.json>|<check-id ERE>
#
# The ERE matches WHOLE word tokens on both sides: the detector's
# `emit <severity> <id>` call sites, and every JSON string value in the eval
# suite split on non-word characters. So `P1` in `PLAN1` and `P4` in `xP4` name
# nothing, while `P2` in `(P1/P2/P3)` names P2. The row's pattern must therefore
# describe an id made of [A-Za-z0-9_]; an id family spelled with punctuation
# needs this splitting rule revisited rather than a wider pattern.
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
trap 'rm -f "$emitted_tmp" "$named_tmp"' EXIT

errors=0
total_emitted=0
total_named=0

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

  # A suite that names no id is a real answer (every emitted id is then
  # uncovered, which is a finding). A suite that does not PARSE is not an answer
  # at all, so it is settled before either set is read.
  if ! jq -e . "$evals" >/dev/null 2>&1; then
    echo "check-detector-eval-coverage: $evals is not valid JSON; the eval-named id set cannot be read" >&2
    exit 2
  fi

  # Emitted ids: `emit <severity> <id>` call sites, comment lines dropped first
  # so the emitter's own usage comment and the prose around it cannot invent an
  # id the detector never fires.
  grep -vE '^[[:space:]]*#' "$detector" |
    sed -nE "s/.*(^|[^A-Za-z0-9_])emit[[:space:]]+[A-Za-z]+[[:space:]]+(${id_re})([^A-Za-z0-9_].*)?\$/\\2/p" |
    sort -u >"$emitted_tmp"

  # Eval-named ids: every string value anywhere in the suite. A case names its
  # check in `expected_output` or in an `expectations` entry, and pinning which
  # field would make the gate depend on a schema the suite is free to grow.
  jq -r '.. | strings' "$evals" |
    tr -c 'A-Za-z0-9_' '\n' | grep -xE "$id_re" | sort -u >"$named_tmp"

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
    echo "$detector"
    echo "  evals:          $evals"
    echo "  id pattern:     $id_re"
    echo "  emitted ids:    $emitted_count"
    echo "  eval-named ids: $named_count"
    while IFS= read -r id; do
      if grep -Fxq -- "$id" "$named_tmp"; then
        printf '    COVERED    %s\n' "$id"
      else
        printf '    UNCOVERED  %s\n' "$id"
      fi
    done <"$emitted_tmp"
    while IFS= read -r id; do
      grep -Fxq -- "$id" "$emitted_tmp" || printf '    UNEMITTABLE %s\n' "$id"
    done <"$named_tmp"
  else
    while IFS= read -r id; do
      if ! grep -Fxq -- "$id" "$named_tmp"; then
        echo "UNCOVERED CHECK ID: $id is emitted by $detector and named by no case in $evals" >&2
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

if [[ "$mode" == "discover" ]]; then
  echo "check-detector-eval-coverage: ${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s)"
  exit 0
fi

if [[ "$errors" -gt 0 ]]; then
  echo "check-detector-eval-coverage: FAILED — $errors gap(s) across ${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s)" >&2
  exit 1
fi

echo "check-detector-eval-coverage: passed — every emitted check id has an eval case naming it and every eval-named id is emittable (${#pairs[@]} pair(s), $total_emitted emitted id(s), $total_named eval-named id(s))"
exit 0
